"""The Swift TrainingMathTests' expected values, repeated: both ports must agree."""
import unittest

from gymstudio import rulebook as rb
from gymstudio.rulebook import PastSet as S


class RulebookTests(unittest.TestCase):
    def test_epley(self):
        self.assertAlmostEqual(rb.e1rm_epley(50, 10), 66.6667, places=3)
        self.assertEqual(rb.e1rm_epley(100, 1), 100)

    def test_displayable_e1rm(self):
        self.assertAlmostEqual(rb.displayable_e1rm(60, 12, "total"), 84)
        self.assertIsNone(rb.displayable_e1rm(60, 13, "total"))
        self.assertIsNone(rb.displayable_e1rm(-45, 6, "bodyweightPlus"))

    def test_calculation_kg(self):
        self.assertEqual(rb.calculation_kg(-45, "bodyweightPlus", 90), 45)
        self.assertIsNone(rb.calculation_kg(-45, "bodyweightPlus", None))
        self.assertEqual(rb.calculation_kg(-100, "bodyweightPlus", 90), 0)
        self.assertIsNone(rb.calculation_kg(10, "repsOnly", 90))

    def test_volume(self):
        self.assertEqual(rb.volume_kg([S(20, 10), S(20, 10, "warmUp")], "perHand", None), 400)
        self.assertEqual(rb.volume_kg([S(-45, 6)], "bodyweightPlus", 90), 270)
        self.assertEqual(rb.volume_kg([S(0, 12)], "repsOnly", 90), 0)
        self.assertEqual(rb.volume_kg([S(60, 8, "failed")], "total", None), 480)
        self.assertEqual(rb.volume_kg([S(60, 8), S(40, 6, "drop")], "total", None), 720)

    def test_bests(self):
        b = rb.bests([S(100, 1, "warmUp"), S(80, 5), S(70, 12)], "total")
        self.assertEqual(b.heaviest_kg, 80)
        self.assertAlmostEqual(b.best_e1rm, 98)
        b = rb.bests([S(60, 8), S(90, 3, "drop")], "total")
        self.assertEqual(b.heaviest_kg, 60)
        self.assertAlmostEqual(b.best_e1rm, 76)
        self.assertEqual(rb.bests([S(-45, 6)], "bodyweightPlus"), rb.Bests())

    def test_units(self):
        self.assertAlmostEqual(rb.to_kg(10000, "lb"), 45.359237)
        self.assertEqual(rb.to_kg(None, "kg"), 0)

    def test_marzagao_reduces_to_load_at_one_rep(self):
        self.assertEqual(rb.e1rm_marzagao(100, 1), 100)
        self.assertGreater(rb.e1rm_marzagao(100, 5), 100)


if __name__ == "__main__":
    unittest.main()


class EffortCasesTest(unittest.TestCase):
    """§6a: the cases shared with the app's EffortTests (GymAppTests/Fixtures/effort_cases.json)."""

    def test_shared_cases_match(self):
        import json
        from pathlib import Path
        path = Path(__file__).resolve().parents[2] / "GymAppTests" / "Fixtures" / "effort_cases.json"
        cases = json.loads(path.read_text())
        self.assertGreaterEqual(len(cases), 18)
        for c in cases:
            got = rb.set_effort(c["type"], c["repsInReserve"], c["annotations"], c["e1RM"], c["reference"])
            self.assertAlmostEqual(got, c["expected"], places=6, msg=c["name"])
