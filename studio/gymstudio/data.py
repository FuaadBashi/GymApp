"""Reading a GymApp backup.

The studio only ever reads a backup (docs/EXPORT_FORMAT.md), opened read-only and copied
first, so neither the phone's copy nor iCloud's sync can be disturbed. History means
finished workouts and completed sets.
"""
from __future__ import annotations

import shutil
import sqlite3
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from . import rulebook


@dataclass
class Exercise:
    id: str
    name: str
    equipment: str
    load_mode: str
    primary_muscles: list[str]
    secondary_muscles: list[str]
    body_region: str
    movement_pattern: Optional[str]
    force: Optional[str]
    library_id: Optional[str]
    is_archived: bool


@dataclass
class SetRow:
    id: str
    position: int
    load_hundredths: Optional[int]
    unit: str
    reps: int
    type: str
    completed_at: Optional[datetime]
    reps_in_reserve: Optional[int]
    note: Optional[str]

    @property
    def kg(self) -> float:
        return rulebook.to_kg(self.load_hundredths, self.unit)

    def past(self) -> rulebook.PastSet:
        return rulebook.PastSet(self.kg, self.reps, self.type)


@dataclass
class Session:
    """One exercise within one finished workout, with its completed sets."""
    workout_id: str
    started_at: datetime
    exercise_id: str
    position: int
    sets: list[SetRow] = field(default_factory=list)
    note: Optional[str] = None


@dataclass
class Workout:
    id: str
    started_at: datetime
    ended_at: datetime
    title: str
    program_day_id: Optional[str]
    note: Optional[str]
    effort: Optional[int]
    sessions: list[Session] = field(default_factory=list)

    @property
    def duration_s(self) -> float:
        return (self.ended_at - self.started_at).total_seconds()


def parse_time(value) -> Optional[datetime]:
    """GRDB stores dates as 'yyyy-MM-dd HH:mm:ss.SSS' in UTC."""
    if value is None:
        return None
    text = str(value)
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(text, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.fromisoformat(text).astimezone(timezone.utc)


def _json_list(text) -> list[str]:
    import json
    return json.loads(text) if text else []


class History:
    """Everything the studio reads, loaded once into memory (the real history is small)."""

    def __init__(self, path: Path):
        self.path = Path(path)
        with tempfile.TemporaryDirectory() as tmp:
            # Copy first: a backup in iCloud may be mid-sync, and SQLite should never lock it.
            copy = Path(tmp) / "backup.sqlite"
            shutil.copyfile(self.path, copy)
            db = sqlite3.connect(f"file:{copy}?mode=ro", uri=True)
            db.row_factory = sqlite3.Row
            try:
                self._load(db)
            finally:
                db.close()

    def _load(self, db: sqlite3.Connection) -> None:
        self.exercises = {
            r["id"]: Exercise(r["id"], r["name"], r["equipment"], r["loadMode"],
                              _json_list(r["primaryMuscles"]), _json_list(r["secondaryMuscles"]),
                              r["bodyRegion"], r["movementPattern"], r["force"], r["libraryId"], bool(r["isArchived"]))
            for r in db.execute("SELECT * FROM exercise")
        }
        self.workouts: dict[str, Workout] = {}
        for r in db.execute("SELECT * FROM workout WHERE endedAt IS NOT NULL ORDER BY startedAt"):
            self.workouts[r["id"]] = Workout(r["id"], parse_time(r["startedAt"]), parse_time(r["endedAt"]),
                                             r["title"], r["programDayId"], r["note"], r["effort"])
        sessions: dict[str, Session] = {}
        for r in db.execute("SELECT * FROM workoutExercise ORDER BY workoutId, position"):
            w = self.workouts.get(r["workoutId"])
            if w is None:
                continue
            s = Session(w.id, w.started_at, r["exerciseId"], r["position"], note=r["note"])
            sessions[r["id"]] = s
        columns = {row[1] for row in db.execute("PRAGMA table_info(workoutSet)")}
        has_v2 = "repsInReserve" in columns
        for r in db.execute("SELECT * FROM workoutSet WHERE completedAt IS NOT NULL ORDER BY workoutExerciseId, position"):
            s = sessions.get(r["workoutExerciseId"])
            if s is None:
                continue
            s.sets.append(SetRow(r["id"], r["position"], r["loadHundredths"], r["unit"], r["reps"], r["type"],
                                 parse_time(r["completedAt"]),
                                 r["repsInReserve"] if has_v2 else None, r["note"] if has_v2 else None))
        for s in sessions.values():
            if s.sets:
                self.workouts[s.workout_id].sessions.append(s)
        self.body_weights = [
            (r["date"], rulebook.to_kg(r["weightHundredths"], r["weightUnit"]))
            for r in db.execute("SELECT date, weightHundredths, weightUnit FROM bodyEntry "
                                "WHERE weightHundredths IS NOT NULL ORDER BY date")
        ]
        self.program_days = {r["id"]: dict(r) for r in db.execute("SELECT * FROM programDay")}
        self.programs = {r["id"]: dict(r) for r in db.execute("SELECT * FROM program")}
        self.day_items = [dict(r) for r in db.execute("SELECT * FROM dayExercise ORDER BY dayId, position")]
        self.exercise_notes = [dict(r) for r in db.execute("SELECT * FROM exerciseNote ORDER BY date")]

    # Queries

    def active_day_items(self) -> list[dict]:
        """Items of the active program's days, in day then position order."""
        active = {pid for pid, p in self.programs.items() if p["isActive"]}
        days = {d for d, row in self.program_days.items() if row["programId"] in active}
        order = {d: self.program_days[d]["position"] for d in days}
        return sorted((i for i in self.day_items if i["dayId"] in days), key=lambda i: (order[i["dayId"]], i["position"]))

    def sessions_for(self, exercise_id: str) -> list[Session]:
        """Oldest first, like the app's ExerciseQueries.sessions but ascending."""
        return [s for w in self.workouts.values() for s in w.sessions if s.exercise_id == exercise_id]

    def body_weight_on(self, when: datetime) -> Optional[float]:
        """The latest recorded weight on or before that local day (BodyQueries.weightKg)."""
        day = when.astimezone().strftime("%Y-%m-%d")
        latest = None
        for date, kg in self.body_weights:
            if date <= day:
                latest = kg
            else:
                break
        return latest


def newest_backup(folder: Path) -> Optional[Path]:
    """The most recent recovery-*.sqlite in a backup folder. Names carry a millisecond
    timestamp, so the lexically last one is the newest."""
    candidates = sorted(Path(folder).glob("recovery-*.sqlite"))
    return candidates[-1] if candidates else None
