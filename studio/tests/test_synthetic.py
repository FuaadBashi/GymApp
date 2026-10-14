"""A small backup built from the app's real schema (no personal data), so these tests run
anywhere."""
import sqlite3
import tempfile
import unittest
from pathlib import Path

from gymstudio import stats, watch
from gymstudio.data import History, newest_backup

SCHEMA = (Path(__file__).parent / "fixtures/schema.sql").read_text()


def build(path: Path) -> None:
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    ex = "INSERT INTO exercise (id,name,equipment,loadMode,primaryMuscles,secondaryMuscles,category,bodyRegion,source,createdAt) VALUES (?,?,?,?,?,?,'strength',?, 'custom','2026-01-01 00:00:00.000')"
    db.execute(ex, ("bench", "Bench", "barbell", "total", '["chest"]', '["triceps","shoulders"]', "upper"))
    db.execute(ex, ("pullup", "Assisted pull-up", "machine", "bodyweightPlus", '["lats"]', "[]", "upper"))
    db.execute("INSERT INTO bodyEntry (id,date,weightHundredths,weightUnit,measurements,source) VALUES ('b','2026-01-01',9000,'kg','{}','app')")
    def workout(wid, day, rows):
        db.execute("INSERT INTO workout (id,startedAt,endedAt,title,source) VALUES (?,?,?,'W','app')",
                   (wid, f"2026-01-{day:02d} 10:00:00.000", f"2026-01-{day:02d} 11:00:00.000"))
        for pos, (eid, sets) in enumerate(rows):
            we = f"{wid}-{eid}"
            db.execute("INSERT INTO workoutExercise (id,workoutId,exerciseId,position,restSeconds) VALUES (?,?,?,?,60)", (we, wid, eid, pos))
            for i, (load, reps, typ) in enumerate(sets):
                db.execute("INSERT INTO workoutSet (id,workoutExerciseId,position,loadHundredths,unit,reps,type,completedAt) VALUES (?,?,?,?,'kg',?,?,?)",
                           (f"{we}-{i}", we, i, load, reps, typ, f"2026-01-{day:02d} 10:10:00.000"))
    workout("w1", 2, [("bench", [(2000, 10, "warmUp"), (5750, 8, "working")])])
    workout("w2", 5, [("pullup", [(-4500, 6, "working")]), ("bench", [(6000, 8, "working"), (4000, 8, "drop")])])
    db.execute("INSERT INTO workout (id,startedAt,title,source) VALUES ('open','2026-01-06 10:00:00.000','In progress','app')")
    db.commit(); db.close()


class SyntheticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = Path(cls.tmp.name) / "recovery-1790000000000-A.sqlite"
        build(cls.path)
        cls.h = History(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_only_finished_workouts_load(self):
        self.assertEqual(list(self.h.workouts), ["w1", "w2"])

    def test_volume_matches_the_app_summary_example(self):
        # SummaryTests: assisted −45×6 at 90 kg body weight + 60×8 = 270 + 480; the drop row adds 320.
        self.assertAlmostEqual(stats.workout_volume_kg(self.h, "w2"), 270 + 480 + 320)

    def test_records_and_muscles(self):
        r = stats.records(self.h, "bench")
        self.assertEqual(r.heaviest.value_kg, 60)
        self.assertAlmostEqual(r.best_e1rm.value_kg, 76)
        m = stats.hard_sets_per_muscle(self.h, self.h.workouts["w2"].sessions)
        self.assertEqual(m, {"lats": 1, "chest": 1, "triceps": 0.5, "shoulders": 0.5})

    def test_newest_backup_by_name(self):
        later = Path(self.tmp.name) / "recovery-1790000000999-B.sqlite"
        later.write_bytes(self.path.read_bytes())
        self.assertEqual(newest_backup(Path(self.tmp.name)), later)
        self.assertEqual(watch.latest([Path(self.tmp.name)]).name, later.name)
        later.unlink()


if __name__ == "__main__":
    unittest.main()


# Migration v3 (card 6.2), as GymApp/Database/Schema.swift creates it.
HEALTH_DAY = """
CREATE TABLE healthDay (
  date TEXT PRIMARY KEY NOT NULL CHECK (length(date) = 10),
  steps INTEGER CHECK (steps >= 0),
  weightHundredths INTEGER CHECK (weightHundredths > 0),
  weightUnit TEXT CHECK (weightUnit IN ('kg','lb')),
  source TEXT NOT NULL DEFAULT 'health',
  CHECK ((weightHundredths IS NULL) = (weightUnit IS NULL))
)"""


class HealthDayTests(unittest.TestCase):
    def test_v3_backup_merges_weights_and_loads_steps(self):
        from datetime import datetime, timezone
        from gymstudio.analysis import steps_summary
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.sqlite"
            build(path)
            db = sqlite3.connect(path)
            db.execute(HEALTH_DAY)
            db.executemany("INSERT INTO healthDay (date,steps,weightHundredths,weightUnit) VALUES (?,?,?,?)",
                           [("2026-01-01", 5000, 8800, "kg"), ("2026-01-03", 7000, 8900, "kg"), ("2026-01-04", None, None, None)])
            db.commit(); db.close()
            h = History(path)
            # The typed 90 kg on 1 Jan wins over Health's 88.
            self.assertEqual(h.body_weights, [("2026-01-01", 90.0), ("2026-01-03", 89.0)])
            self.assertEqual(h.steps, [("2026-01-01", 5000), ("2026-01-03", 7000)])
            s = steps_summary(h, datetime(2026, 1, 10, 12, tzinfo=timezone.utc))
            self.assertEqual(s["daily_average"], 6000)
            self.assertEqual(len(s["days"]), 2)

    def test_older_backup_has_no_steps(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.sqlite"
            build(path)
            self.assertEqual(History(path).steps, [])
