"""Card 8.4: the program planner."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gymstudio import analysis, planner, suggestions
from gymstudio.data import History
from tests.test_synthetic import build


class RampTests(unittest.TestCase):
    def test_a_five_week_ramp_climbs_evenly_from_the_band_bottom(self):
        self.assertEqual(planner.ramp(6, 10, 20, 5), [10, 12.5, 15, 17.5, 20])
        self.assertEqual(planner.ramp(14, 10, 20, 5), [14, 15.5, 17, 18.5, 20])
        self.assertEqual(planner.ramp(24, 10, 20, 4), [24, 24, 24, 24])   # above the band holds


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "b.sqlite"
        build(self.path)
        db = sqlite3.connect(self.path)
        db.execute("INSERT INTO program (id,name,split,isActive,sessionsPerWeekGoal,source,createdAt) VALUES ('p','P','fullBody',1,2,'app','2026-01-01 00:00:00.000')")
        db.execute("INSERT INTO programDay (id,programId,name,focus,position) VALUES ('d','p','A','fullBody',0)")
        db.execute("INSERT INTO dayExercise (id,dayId,exerciseId,position,targetSets,repMin,repMax,restSeconds) VALUES ('i','d','bench',0,3,8,12,90)")
        db.commit(); db.close()
        self.h = History(self.path)

    def tearDown(self):
        self.tmp.cleanup()

    def test_weekly_sets_and_planned_sets_follow_the_ramp(self):
        p = planner.plan(self.h, analysis.Settings(), 5)
        # One day done twice a week: bench 3 sets → chest 6, triceps and shoulders 3.
        self.assertEqual(p["now"], {"chest": 6.0, "shoulders": 3.0, "triceps": 3.0})
        self.assertEqual([w["items"][0]["plannedSets"] for w in p["weeks"]], [5, 6, 8, 9, 10])
        self.assertFalse(p["deload_week"])
        self.assertFalse(any(w["deload"] for w in p["weeks"]))

    def test_a_deload_week_needs_three_plateaued_lifts(self):
        plateau = {"status": "plateau", "sessions_in_window": 3}
        with mock.patch.object(analysis, "plateau", return_value=plateau):
            p = planner.plan(self.h, analysis.Settings(), 4)
        self.assertEqual(len(p["plateaued"]), 1)
        self.assertFalse(p["deload_week"])               # one plateaued lift: its own target only

    def test_notes_are_valid_suggestions_for_the_chosen_weeks_only(self):
        p = planner.plan(self.h, analysis.Settings(), 4)
        out = planner.notes(p, [1, 3], "2026-02-01T00:00:00Z")
        self.assertEqual([n["title"] for n in out], ["Plan week 1", "Plan week 3"])
        for n in out:
            suggestions.validate(n)


if __name__ == "__main__":
    unittest.main()
