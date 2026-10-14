"""Card 6.3: drafting, validating and publishing suggestions for the phone."""
import json
import sqlite3
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from gymstudio import analysis, suggestions
from gymstudio.data import History
from tests.test_synthetic import build


class SuggestionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        path = self.folder / "b.sqlite"
        build(path)
        db = sqlite3.connect(path)
        db.execute("INSERT INTO program (id,name,split,isActive,source,createdAt) VALUES ('p','P','fullBody',1,'app','2026-01-01 00:00:00.000')")
        db.execute("INSERT INTO programDay (id,programId,name,focus,position) VALUES ('d','p','A','fullBody',0)")
        db.execute("INSERT INTO dayExercise (id,dayId,exerciseId,position,targetSets,repMin,repMax,restSeconds) VALUES ('i','d','bench',0,3,8,12,90)")
        db.commit(); db.close()
        self.h = History(path)
        self.today = datetime(2026, 1, 10, 12, tzinfo=timezone.utc)

    def tearDown(self):
        self.tmp.cleanup()

    def test_drafts_are_valid_and_stable(self):
        a = suggestions.drafts(self.h, analysis.Settings(), self.today)
        b = suggestions.drafts(self.h, analysis.Settings(), self.today)
        self.assertTrue(a)
        self.assertEqual([x["id"] for x in a], [x["id"] for x in b])
        target = next(x for x in a if x["kind"] == "target")
        self.assertEqual(target["exerciseId"], "bench")
        self.assertIsInstance(target["change"]["reps"], int)
        for item in a:
            suggestions.validate(item)

    def test_publish_writes_a_list_and_drops_decided_items(self):
        items = suggestions.drafts(self.h, analysis.Settings(), self.today)
        items.append(suggestions.note("Sleep", "Eight hours", "", self.today))
        written = suggestions.publish(self.folder, items)
        on_disk = json.loads((self.folder / suggestions.FILE).read_text())
        self.assertEqual([x["id"] for x in on_disk], [x["id"] for x in written])
        (self.folder / suggestions.DECISIONS).write_text(json.dumps([{"id": written[0]["id"], "decision": "accepted"}]))
        again = suggestions.publish(self.folder, items)
        self.assertNotIn(written[0]["id"], [x["id"] for x in again])

    def test_invalid_items_are_refused(self):
        bad = {"id": "x", "created": "2026-01-01T00:00:00Z", "kind": "target", "title": "t", "detail": "",
               "reason": "", "rule": "r", "exerciseId": "bench", "change": {"weight": 50, "unit": "kg"}}
        with self.assertRaises(ValueError):
            suggestions.publish(self.folder, [bad])
        self.assertFalse((self.folder / suggestions.FILE).exists())


if __name__ == "__main__":
    unittest.main()
