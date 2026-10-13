"""Builds small backups from the app's real schema for tests."""
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCHEMA = (Path(__file__).parent / "fixtures/schema.sql").read_text()
BASE = datetime(2026, 1, 1, 10, tzinfo=timezone.utc)


def stamp(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.000")


def make(path: Path, exercises: dict, workouts: list, day_items: list = ()) -> None:
    """exercises: id -> (name, equipment, loadMode, primary, secondary)
    workouts: (day offset, [(exercise id, [(kg, reps, type), ...]), ...])
    day_items: (exercise id, repMin, repMax) in an active program day."""
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    for eid, (name, eq, mode, prim, sec) in exercises.items():
        db.execute("INSERT INTO exercise (id,name,equipment,loadMode,primaryMuscles,secondaryMuscles,category,bodyRegion,source,createdAt) "
                   "VALUES (?,?,?,?,?,?,'strength','upper','custom',?)", (eid, name, eq, mode, str(prim).replace("'", '"'), str(sec).replace("'", '"'), stamp(BASE)))
    if day_items:
        db.execute("INSERT INTO program (id,name,split,isActive,isArchived,sessionsPerWeekGoal,source,createdAt) VALUES ('p','P','custom',1,0,3,'app',?)", (stamp(BASE),))
        db.execute("INSERT INTO programDay (id,programId,name,focus,position) VALUES ('d','p','D','fullBody',0)")
        for i, (eid, lo, hi) in enumerate(day_items):
            db.execute("INSERT INTO dayExercise (id,dayId,exerciseId,position,targetSets,repMin,repMax,restSeconds) VALUES (?,?,?,?,3,?,?,90)", (f"i{i}", "d", eid, i, lo, hi))
    for n, (offset, rows) in enumerate(workouts):
        start = BASE + timedelta(days=offset)
        db.execute("INSERT INTO workout (id,startedAt,endedAt,title,source) VALUES (?,?,?,'W','app')", (f"w{n}", stamp(start), stamp(start + timedelta(hours=1))))
        for pos, (eid, sets) in enumerate(rows):
            we = f"w{n}-{pos}"
            db.execute("INSERT INTO workoutExercise (id,workoutId,exerciseId,position,restSeconds) VALUES (?,?,?,?,60)", (we, f"w{n}", eid, pos))
            for i, (kg, reps, typ) in enumerate(sets):
                db.execute("INSERT INTO workoutSet (id,workoutExerciseId,position,loadHundredths,unit,reps,type,completedAt) VALUES (?,?,?,?,'kg',?,?,?)",
                           (f"{we}-{i}", we, i, None if kg is None else round(kg * 100), reps, typ, stamp(start)))
    db.commit()
    db.close()
