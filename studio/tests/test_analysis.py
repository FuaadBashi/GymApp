import tempfile
import unittest
from datetime import timedelta
from pathlib import Path

from gymstudio import analysis as a
from gymstudio.data import History
from tests.backups import BASE, make

EX = {"bench": ("Bench", "barbell", "total", ["chest"], ["triceps"]),
      "fly": ("Fly", "machine", "total", ["chest"], [])}
W = "working"


def history(workouts, items=(("bench", 8, 10),)):
    tmp = tempfile.TemporaryDirectory()
    path = Path(tmp.name) / "b.sqlite"
    make(path, EX, workouts, items)
    h = History(path)
    tmp.cleanup()
    return h


class PlateauTests(unittest.TestCase):
    s = a.Settings()

    def test_no_increase_for_three_weeks_of_training_is_a_plateau(self):
        h = history([(d, [("bench", [(60, 8, W)])]) for d in (0, 7, 14, 21, 28)])
        self.assertEqual(a.plateau(h, "bench", self.s, BASE + timedelta(days=29))["status"], "plateau")

    def test_an_increase_in_the_window_is_progress(self):
        h = history([(0, [("bench", [(60, 8, W)])]), (14, [("bench", [(60, 8, W)])]), (21, [("bench", [(62.5, 8, W)])])])
        self.assertEqual(a.plateau(h, "bench", self.s, BASE + timedelta(days=22))["status"], "progressing")

    def test_after_a_break_it_is_rebuilding(self):
        h = history([(0, [("bench", [(80, 8, W)])]), (100, [("bench", [(60, 8, W)])]), (107, [("bench", [(60, 8, W)])])])
        self.assertEqual(a.plateau(h, "bench", self.s, BASE + timedelta(days=108))["status"], "rebuilding")


class NextTargetTests(unittest.TestCase):
    s = a.Settings()

    def test_all_sets_at_the_top_of_the_range_add_one_learnt_step(self):
        h = history([(0, [("bench", [(57.5, 10, W)])]), (7, [("bench", [(60, 10, W), (60, 10, W)])])])
        t = a.next_target(h, "bench", self.s, BASE + timedelta(days=8))
        self.assertEqual((t["kind"], t["weight"], t["reps"]), ("add weight", 62.5, "8"))

    def test_otherwise_stay_and_beat_the_lowest_set(self):
        h = history([(0, [("bench", [(60, 10, W), (60, 7, W)])])])
        t = a.next_target(h, "bench", self.s, BASE + timedelta(days=1))
        self.assertEqual((t["kind"], t["weight"], t["reps"]), ("add reps", 60, "8+"))

    def test_easy_sets_at_the_top_add_two_steps(self):
        h = history([(0, [("bench", [(57.5, 10, W)])]), (7, [("bench", [(60, 10, W, 2), (60, 10, W, 3)])])])
        t = a.next_target(h, "bench", self.s, BASE + timedelta(days=8))
        self.assertEqual((t["kind"], t["weight"], t["reps"]), ("add weight", 65, "8"))

    def test_easy_sets_below_the_top_add_two_reps_and_one_hard_set_keeps_one(self):
        easy = history([(0, [("bench", [(60, 8, W, 2), (60, 7, W, 2)])])])
        self.assertEqual(a.next_target(easy, "bench", self.s, BASE + timedelta(days=1))["reps"], "9+")
        mixed = history([(0, [("bench", [(60, 8, W, 2), (60, 7, W, 1)])])])
        self.assertEqual(a.next_target(mixed, "bench", self.s, BASE + timedelta(days=1))["reps"], "8+")

    def test_a_tied_step_goes_to_the_smaller_gap_as_in_the_app(self):
        # Loads 5, 14, 17.5, 18, 20: every gap occurs once, so the step is the smallest, 0.5.
        h = history([(d, [("bench", [(kg, 8, W)])]) for d, kg in ((0, 5), (7, 14), (14, 17.5), (21, 18), (28, 20))])
        self.assertEqual(a.increment(h, "bench")["step"], 0.5)

    def test_a_plateau_suggests_a_deload(self):
        h = history([(d, [("bench", [(60, 8, W)])]) for d in (0, 7, 14, 21, 28)])
        t = a.next_target(h, "bench", self.s, BASE + timedelta(days=29))
        self.assertEqual((t["kind"], t["weight"]), ("plateau", 54))


class ProgressTests(unittest.TestCase):
    def test_a_few_sessions_close_together_give_no_trend(self):
        from datetime import datetime, timezone
        pts = [(datetime(2026, 1, d, tzinfo=timezone.utc), v) for d, v in ((1, 50), (3, 60), (5, 70))]
        self.assertIsNone(a.slope_per_30_days(pts))

    def test_a_steady_rise_gives_its_rate(self):
        from datetime import datetime, timedelta, timezone
        start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        pts = [(start + timedelta(days=10 * i), 60 + i) for i in range(6)]
        self.assertAlmostEqual(a.slope_per_30_days(pts), 3.0)


class OtherTests(unittest.TestCase):
    s = a.Settings()

    def test_increment_is_the_most_common_step(self):
        h = history([(i, [("bench", [(40 + 2.5 * i, 8, W)])]) for i in range(5)] + [(9, [("bench", [(55, 8, W)])])])
        inc = a.increment(h, "bench")
        self.assertEqual((inc["unit"], inc["step"]), ("kg", 2.5))

    def test_weak_point_flags_low_volume_and_flat_partners(self):
        rows = [(d, [("bench", [(60, 8, W)]), ("fly", [(30, 10, W)])]) for d in (0, 7, 14, 21, 28)]
        h = history(rows)
        wp = a.weak_points(h, "bench", self.s, BASE + timedelta(days=29))
        chest = next(r for r in wp if r["muscle"] == "chest")
        self.assertTrue(chest["likely_weak_point"])
        self.assertEqual(chest["other_exercises"][0]["status"], "plateau")

    def test_formula_lab_compares_three_equations(self):
        h = history([(0, [("bench", [(80, 3, W), (60, 10, W)])])])
        r = a.formula_consistency(h)
        self.assertEqual(r["sessions_compared"], 1)
        self.assertEqual(set(r["mean_spread_pct"]), {"epley", "brzycki", "marzagao_2026"})


if __name__ == "__main__":
    unittest.main()
