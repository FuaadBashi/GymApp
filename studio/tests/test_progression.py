import unittest
from gymstudio import analysis, progression
from tests.test_analysis import history, W

class ReplayTests(unittest.TestCase):
    def rows(self, h, rule="double_progression"):
        result = progression.backtest(h, analysis.Settings(default_rep_range=(8, 10)), exercise_id="bench")
        return next(r for r in result["rules"] if r["id"] == rule)["trials"]

    def test_future_loads_do_not_change_an_earlier_target_or_increment(self):
        before = history([(0, [("bench", [(57.5, 10, W)])]), (7, [("bench", [(60, 10, W)])])])
        after = history([(0, [("bench", [(57.5, 10, W)])]), (7, [("bench", [(60, 10, W)])]), (14, [("bench", [(60.1, 10, W)])]), (21, [("bench", [(60.2, 10, W)])])])
        self.assertEqual(self.rows(before)[1]["target"], self.rows(after)[1]["target"])
        self.assertEqual(self.rows(before)[1]["target"]["weight"], 62.5)

    def test_unknown_capacity_at_an_unattempted_load_is_not_a_missed_target(self):
        row = self.rows(history([(0, [("bench", [(60, 10, W)])]), (7, [("bench", [(60, 9, W)])])]))[0]
        self.assertEqual(row["target"]["kind"], "add weight")
        self.assertEqual(row["next_result"], "not attempted")

    def test_missed_and_met_targets_are_scored_only_when_attempted(self):
        rows = self.rows(history([(0, [("bench", [(60, 10, W)])]), (7, [("bench", [(62.5, 7, W)])]), (14, [("bench", [(62.5, 8, W)])])]))
        self.assertEqual(rows[0]["next_result"], "missed")
        self.assertEqual(rows[1]["next_result"], "met")

    def test_breaks_reset_stall_evidence_and_suppress_increases_on_return(self):
        row = self.rows(history([(d, [("bench", [(60, 10, W)])]) for d in (0, 7, 14, 100)]), "double_stall_2")[-1]
        self.assertEqual(row["target"]["kind"], "rebuild")
        self.assertFalse(row["target"]["deload"])

    def test_three_week_plateau_and_grid_rounded_deload(self):
        rows = self.rows(history([(d, [("bench", [(60, 8, W)])]) for d in (0, 7, 14, 21, 28, 35, 42)]))
        row = next(r for r in rows if r["date"].startswith("2026-01-22"))
        self.assertTrue(row["target"]["deload"])
        self.assertEqual(row["target"]["weight"], 55)
        self.assertTrue(row["observed_plateau"])
        self.assertIsNone(rows[-1]["observed_plateau"])

    def test_short_followup_does_not_get_counted_as_a_correct_plateau_call(self):
        result = progression.backtest(history([(d, [("bench", [(60, 8, W)])]) for d in (0, 7, 14)]), analysis.Settings(), exercise_id="bench")
        self.assertTrue(all(r["metrics"]["plateau_evaluated"] == 0 for r in result["rules"]))
        self.assertIsNone(result["recommended_rule"])

    def test_rir_rule_abstains_when_effort_was_not_logged(self):
        rows = self.rows(history([(d, [("bench", [(60, 10, W)])]) for d in (0, 7)]), "rir_double")
        self.assertTrue(all(r["target"] is None for r in rows))

    def test_invalid_ranges_and_thresholds_are_rejected(self):
        with self.assertRaises(ValueError): progression.backtest(history([]), analysis.Settings(deload_fraction=1))
        with self.assertRaises(ValueError): progression.backtest(history([]), analysis.Settings(default_rep_range=(12, 8)))

    def test_load_increments_remain_in_the_entered_pounds(self):
        h = history([(0, [("bench", [(50, 10, W)])]), (7, [("bench", [(55, 10, W)])])])
        for i, w in enumerate(h.workouts.values()):
            w.sessions[0].sets[0].unit = "lb"
            w.sessions[0].sets[0].load_hundredths = 10000 + i * 500
        target = self.rows(h)[1]["target"]
        self.assertEqual((target["weight"], target["unit"], target["step"]["size"]), (110, "lb", 5))

    def test_assistance_deload_adds_assistance_instead_of_making_it_harder(self):
        h = history([(d, [("bench", [(-45, 8, W)])]) for d in (0, 7, 14, 21)])
        h.exercises["bench"].load_mode = "bodyweightPlus"
        target = self.rows(h)[-1]["target"]
        self.assertTrue(target["deload"])
        self.assertLess(target["weight"], -45)

    def test_historical_rep_snapshot_overrides_the_current_programme(self):
        h = history([(0, [("bench", [(60, 8, W)])])])
        h.workouts["w0"].sessions[0].rep_min = 6
        h.workouts["w0"].sessions[0].rep_max = 8
        h.day_items[0]["repMin"] = 20; h.day_items[0]["repMax"] = 30
        target = self.rows(h)[0]["target"]
        self.assertEqual((target["kind"], target["reps"], target["range_source"]), ("add weight", 6, "workout snapshot"))

    def test_rir_gate_requires_two_left_and_scores_missing_followup_as_unknown(self):
        h = history([(0, [("bench", [(60, 10, W)])]), (7, [("bench", [(62.5, 10, W)])])])
        h.workouts["w0"].sessions[0].sets[0].reps_in_reserve = 2
        rows = self.rows(h, "rir_double")
        self.assertEqual(rows[0]["target"]["kind"], "add weight")
        self.assertEqual(rows[0]["next_result"], "follow-up RIR missing")
