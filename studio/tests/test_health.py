"""Card 8.2: data health."""
import sqlite3
import tempfile
import unittest
from pathlib import Path

from gymstudio import health, suggestions
from gymstudio.data import History
from tests.test_synthetic import SCHEMA


def build(path: Path, loads: list[float], reps: int = 8) -> None:
    """One exercise, one session per load, a few days apart."""
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    db.execute("INSERT INTO exercise (id,name,equipment,loadMode,primaryMuscles,secondaryMuscles,category,bodyRegion,source,createdAt) "
               "VALUES ('row','Row','machine','total','[\"lats\"]','[]','strength','upper','custom','2026-01-01 00:00:00.000')")
    for i, load in enumerate(loads):
        day = f"2026-{1 + i // 28:02d}-{1 + i % 28:02d}"
        db.execute("INSERT INTO workout (id,startedAt,endedAt,title,source) VALUES (?,?,?,'W','app')",
                   (f"w{i}", f"{day} 10:00:00.000", f"{day} 11:00:00.000"))
        db.execute("INSERT INTO workoutExercise (id,workoutId,exerciseId,position,restSeconds) VALUES (?,?,'row',0,60)", (f"we{i}", f"w{i}"))
        db.execute("INSERT INTO workoutSet (id,workoutExerciseId,position,loadHundredths,unit,reps,type,completedAt) "
                   "VALUES (?,?,0,?,'kg',?,'working',?)", (f"s{i}", f"we{i}", round(load * 100), reps, f"{day} 10:10:00.000"))
    db.commit(); db.close()


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "b.sqlite"

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_slipped_decimal_is_found_and_fixed(self):
        build(self.path, [57, 58, 59, 59, 590, 60, 60, 61])
        f = [x for x in health.findings(History(self.path)) if x["kind"] == "load"]
        self.assertEqual(len(f), 1)
        self.assertEqual((f[0]["set_id"], f[0]["fix"]), ("s4", {"weight": 59.0, "unit": "kg", "reps": 8}))
        s = health.suggestion(f[0], "2026-03-01T00:00:00Z")
        suggestions.validate(s)
        self.assertEqual(s["change"]["setId"], "s4")

    def test_a_real_twenty_percent_jump_is_not_flagged(self):
        build(self.path, [50, 50, 52.5, 52.5, 63, 63, 65, 65])
        self.assertEqual(health.findings(History(self.path)), [])

    def test_a_light_set_without_a_likely_typo_is_not_flagged(self):
        build(self.path, [60, 60, 60, 20, 60, 60, 60])
        self.assertEqual(health.findings(History(self.path)), [])


if __name__ == "__main__":
    unittest.main()
