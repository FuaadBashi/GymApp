"""Figures the app also shows, computed the same way (ExerciseStats.swift, SummaryQueries.swift).

Anything new in the studio builds on these, so the studio and the phone start from the
same numbers.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from . import rulebook
from .data import History, Session


@dataclass
class Point:
    workout_id: str
    date: datetime
    best_e1rm: Optional[float]
    heaviest_kg: Optional[float]
    volume_kg: float


@dataclass
class Mark:
    value_kg: float
    reps: Optional[int]
    date: datetime
    workout_id: str


@dataclass
class Records:
    heaviest: Optional[Mark]
    best_e1rm: Optional[Mark]
    best_volume: Optional[Mark]
    rep_records: list[Mark]


def _merged(sessions: list[Session]) -> list[tuple[str, datetime, list]]:
    """A workout can hold an exercise twice; figures are per workout."""
    by_workout: dict[str, tuple[datetime, list]] = {}
    for s in sessions:
        entry = by_workout.setdefault(s.workout_id, (s.started_at, []))
        entry[1].extend(s.sets)
    return sorted(((w, d, sets) for w, (d, sets) in by_workout.items()), key=lambda x: x[1])


def points(history: History, exercise_id: str) -> list[Point]:
    """One point per workout, oldest first (ExerciseStats.points)."""
    mode = history.exercises[exercise_id].load_mode
    out = []
    for wid, date, sets in _merged(history.sessions_for(exercise_id)):
        past = [s.past() for s in sets]
        b = rulebook.bests(past, mode)
        out.append(Point(wid, date, b.best_e1rm, b.heaviest_kg,
                         rulebook.volume_kg(past, mode, history.body_weight_on(date))))
    return out


def records(history: History, exercise_id: str) -> Records:
    """Rulebook §5. Ties keep the earliest date (ExerciseStats.records)."""
    mode = history.exercises[exercise_id].load_mode
    heaviest = e1rm = volume = None
    reps: dict[int, Mark] = {}
    load_records = mode not in ("bodyweightPlus", "repsOnly")
    for wid, date, sets in _merged(history.sessions_for(exercise_id)):
        past = [s.past() for s in sets]
        v = rulebook.volume_kg(past, mode, history.body_weight_on(date))
        if v > 0 and v > (volume.value_kg if volume else 0):
            volume = Mark(v, None, date, wid)
        if not load_records:
            continue
        for s in past:
            if s.type in ("warmUp", "drop") or s.kg <= 0 or s.reps <= 0:
                continue
            if s.kg > (heaviest.value_kg if heaviest else 0):
                heaviest = Mark(s.kg, s.reps, date, wid)
            e = rulebook.displayable_e1rm(s.kg, s.reps, mode)
            if e is not None and e > (e1rm.value_kg if e1rm else 0):
                e1rm = Mark(e, s.reps, date, wid)
            key = round(s.kg * 100)
            if s.reps > (reps[key].reps if key in reps else 0):
                reps[key] = Mark(key / 100, s.reps, date, wid)
    return Records(heaviest, e1rm, volume, sorted(reps.values(), key=lambda m: -m.value_kg))


def effort_reference(history: History, session: Session) -> Optional[float]:
    """§6a (EffortQueries.reference): the exercise's best e1RM over working and failed sets in
    other workouts that started in the 56 days before this one."""
    ex = history.exercises.get(session.exercise_id)
    if ex is None or ex.load_mode in ("bodyweightPlus", "repsOnly"):
        return None
    since = session.started_at - timedelta(days=rulebook.EFFORT_WINDOW_DAYS)
    values = [rulebook.e1rm_epley(x.kg, x.reps) for s in history.sessions_for(session.exercise_id)
              if s.workout_id != session.workout_id and since <= s.started_at < session.started_at
              for x in s.sets if x.type in ("working", "failed") and x.kg > 0 and x.reps >= 1]
    return max(values) if values else None


def session_hard_sets(history: History, session: Session) -> float:
    """§6a: the session's sets, each weighted by its effort."""
    reference = effort_reference(history, session)
    return sum(rulebook.set_effort(x.type, x.reps_in_reserve, x.annotations,
                                   rulebook.e1rm_epley(x.kg, x.reps) if x.kg > 0 and x.reps >= 1 else None, reference)
               for x in session.sets)


def hard_sets_per_muscle(history: History, sessions: list[Session]) -> dict[str, float]:
    """Rulebook §6, fractional: each set's effort (§6a) counts 1× per primary muscle and ½× per
    secondary (EffortQueries.addMuscles)."""
    counts: dict[str, float] = defaultdict(float)
    for s in sessions:
        ex = history.exercises.get(s.exercise_id)
        if ex is None:
            continue
        hard = session_hard_sets(history, s)
        for m in ex.primary_muscles:
            counts[m] += hard
        for m in ex.secondary_muscles:
            counts[m] += hard * 0.5
    return dict(counts)


def workout_volume_kg(history: History, workout_id: str) -> float:
    w = history.workouts[workout_id]
    bw = history.body_weight_on(w.started_at)
    return sum(rulebook.volume_kg([x.past() for x in s.sets], history.exercises[s.exercise_id].load_mode, bw)
               for s in w.sessions if s.exercise_id in history.exercises)
