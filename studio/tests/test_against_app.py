"""Whole-history checks against the app's own fixtures. Skipped without a real backup
(personal data lives in data/, which is never committed)."""
import json
import os
import unittest
from pathlib import Path

from gymstudio.data import History
from gymstudio import stats

ROOT = Path(__file__).resolve().parents[2]
BACKUP = Path(os.environ.get("GYMAPP_BACKUP", ROOT / "data/backups/phone-2026-10-13.sqlite"))
EXPECTED = json.loads((ROOT / "GymAppTests/Fixtures/phase3_expected.json").read_text())


@unittest.skipUnless(BACKUP.exists(), "no real backup in data/backups")
class AgainstAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = History(BACKUP)

    def test_history_counts(self):
        self.assertGreaterEqual(len(self.h.workouts), 469)
        sets = sum(len(s.sets) for w in self.h.workouts.values() for s in w.sessions)
        self.assertGreaterEqual(sets, 7765)

    def test_exercise_figures_match_the_app_and_the_export(self):
        for eid, want in EXPECTED["exercises"].items():
            r = stats.records(self.h, eid)
            self.assertEqual(len(stats.points(self.h, eid)), want["sessions"], want["name"])
            self.assertAlmostEqual(r.heaviest.value_kg, want["heaviestKg"], places=2)
            self.assertAlmostEqual(r.best_e1rm.value_kg, want["bestE1RMKg"], places=2)
            self.assertAlmostEqual(r.best_volume.value_kg, want["bestSessionVolumeKg"], places=2)


if __name__ == "__main__":
    unittest.main()
