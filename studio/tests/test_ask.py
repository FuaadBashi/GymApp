"""Ask's tool loop with fake providers: no network, no key."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gymstudio import analysis, ask
from gymstudio.data import History
from tests.backups import make

EX = {"bench": ("Bench", "barbell", "total", ["chest"], ["triceps"])}


class AskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        p = Path(cls.tmp.name) / "b.sqlite"
        make(p, EX, [(d, [("bench", [(60, 8, "working")])]) for d in (0, 7, 14)], [("bench", 8, 10)])
        cls.h, cls.s = History(p), analysis.Settings()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_summary_mode_hides_raw_data_tools(self):
        names = {t.name for t in ask.available(self.h, self.s, "summaries")}
        self.assertNotIn("sql", names)
        self.assertNotIn("search_notes", names)
        self.assertIn("sql", {t.name for t in ask.available(self.h, self.s, "full")})
        self.assertIn("not available", ask.call_tool(ask.available(self.h, self.s, "summaries"), "sql", {"query": "select 1"}))

    def test_sql_is_read_only(self):
        ts = ask.available(self.h, self.s, "full")
        self.assertIn("only SELECT", ask.call_tool(ts, "sql", {"query": "DELETE FROM workout"}))
        out = json.loads(ask.call_tool(ts, "sql", {"query": "SELECT COUNT(*) FROM workout"}))
        self.assertEqual(out["rows"], [[3]])

    def test_claude_loop_runs_tools_then_answers(self):
        replies = iter([
            {"content": [{"type": "tool_use", "id": "t1", "name": "find_exercises", "input": {"query": "ben"}}]},
            {"content": [{"type": "text", "text": "Bench has 3 sessions."}]},
        ])
        seen = []
        def fake(msgs, ts, model, key, system):
            seen.append(msgs)
            return next(replies)
        with mock.patch.object(ask, "get_key", return_value="k"):
            a = ask.ask(self.h, self.s, "How is bench?", claude=fake)
        self.assertEqual(a.text, "Bench has 3 sessions.")
        self.assertEqual(a.tool_calls, [{"tool": "find_exercises", "input": {"query": "ben"}}])
        result = seen[1][-1]["content"][0]
        self.assertEqual(result["type"], "tool_result")
        self.assertIn("Bench", result["content"])

    def test_local_loop_parses_tool_calls(self):
        replies = iter([
            {"message": {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": "overview", "arguments": {}}}]}},
            {"message": {"role": "assistant", "content": "All good."}},
        ])
        a = ask.ask(self.h, self.s, "Overview?", provider="local", ollama=lambda *a: next(replies))
        self.assertEqual((a.text, a.tool_calls[0]["tool"]), ("All good.", "overview"))

    def test_invented_figures_are_flagged(self):
        outs = ['{"best_e1rm_kg": 93.3, "best_e1rm_date": "2026-03-14", "sessions": 77}']
        self.assertEqual(ask.unverified_numbers("Best is 93.3 kg (93 rounded) on 2026-03-14 over 77 sessions, 3 weeks.", outs), [])
        self.assertEqual(ask.unverified_numbers("Your 1RM is 185kg.", outs), ["185"])

    def test_no_key_explains_itself(self):
        with mock.patch.object(ask, "get_key", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "No Claude API key"):
                ask.ask(self.h, self.s, "hi")


if __name__ == "__main__":
    unittest.main()
