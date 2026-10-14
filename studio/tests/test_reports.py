"""Card 8.1: weekly and monthly reports."""
import json
import sqlite3
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from gymstudio import analysis, reports, rulebook
from gymstudio.data import History
from tests.test_synthetic import build


class BestRuleTests(unittest.TestCase):
    """The port of rulebook §5a matches the app's BestStatusTests."""
    def d(self, n):
        return datetime(2026, 1, 1, tzinfo=timezone.utc) + __import__("datetime").timedelta(days=n)

    def test_weekly_training_only_shows_all_time_bests(self):
        history = [(self.d(0), 100.0)] + [(self.d(w * 7), 90.0) for w in range(1, 21)]
        self.assertEqual(rulebook.best_status(95, history, self.d(147)), ("none",))
        self.assertEqual(rulebook.best_status(101, history, self.d(147)), ("all_time", 100.0))

    def test_comeback_earns_the_longest_window(self):
        history = [(self.d(60), 100.0), (self.d(90), 80.0), (self.d(130), 85.0), (self.d(210), 70.0)]
        self.assertEqual(rulebook.best_status(86, history, self.d(300)), ("window", 6, 85.0))
        self.assertEqual(rulebook.best_status(75, history, self.d(300)), ("none",))
        back = history + [(self.d(295), 72.0)]
        self.assertEqual(rulebook.best_status(74, back, self.d(300)), ("window", 1, 72.0))


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        path = self.folder / "b.sqlite"
        build(path)
        self.h = History(path)
        self.today = datetime(2026, 2, 15, 12, tzinfo=timezone.utc)

    def tearDown(self):
        self.tmp.cleanup()

    def test_week_and_month_totals_and_bests(self):
        rs = reports.build(self.h, analysis.Settings(), self.today)
        weeks = [r for r in rs if r.kind == "week"]
        # Fri 2 Jan and Mon 5 Jan 2026 fall in different Sunday-start weeks.
        self.assertEqual([w.figures["workouts"] for w in weeks], [1, 1])
        self.assertAlmostEqual(weeks[0].figures["volume_kg"], 460)               # 57.5 × 8, warm-up excluded
        self.assertAlmostEqual(weeks[1].figures["volume_kg"], 270 + 480 + 320)  # assisted at 90 kg, drop row counts
        bests = next(s for s in weeks[1].sections if s["title"] == "Bests")["lines"]
        self.assertTrue(any(line.startswith("Bench: all-time best") for line in bests))
        self.assertEqual(next(s for s in weeks[0].sections if s["title"] == "Bests")["lines"], ["No new bests."])
        month = next(r for r in rs if r.kind == "month")
        self.assertEqual((month.id, month.figures["workouts"]), ("2026-01", 2))
        totals = next(s for s in month.sections if s["title"] == "Totals")
        self.assertIn("1,530 kg lifted", totals["lines"][0])

    def test_markdown_holds_every_line_and_files_are_written(self):
        rs = reports.build(self.h, analysis.Settings(), self.today)
        info = reports.write(rs, self.folder)
        for r in rs:
            md = (self.folder / "Reports" / f"{r.id}.md").read_text()
            for section in r.sections:
                for line in section["lines"]:
                    self.assertIn(line, md)
        app = json.loads((self.folder / reports.APP_FILE).read_text())
        self.assertEqual(len(app), info["app_reports"])
        self.assertEqual(set(app[0]), {"id", "kind", "title", "from", "to", "headline", "sections"})
        self.assertEqual(reports.write(rs, self.folder)["markdown_written"], 0)   # unchanged files are left alone


if __name__ == "__main__":
    unittest.main()
