import hashlib
import tempfile
import unittest
from pathlib import Path
from gymstudio.lab import NotebookLab


class NotebookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.lab = NotebookLab(Path(self.tmp.name))
        self.addCleanup(self.lab.stop)

    def test_seed_preserves_edited_notebooks(self):
        self.lab.seed()
        path = self.lab.notebooks / "training_explorer.py"
        path.write_text("# My changes")
        self.lab.seed()
        self.assertEqual(path.read_text(), "# My changes")

    def test_creation_rejects_traversal_and_overwrite(self):
        with self.assertRaises(ValueError): self.lab.create("../escape")
        self.lab.create("my_training")
        with self.assertRaises(FileExistsError): self.lab.create("my_training")

    def test_snapshot_is_unchanged_after_source_changes(self):
        source = Path(self.tmp.name) / "source.sqlite"
        source.write_bytes(b"snapshot")
        context = self.lab.context(source, {}, "token")
        source.write_bytes(b"later")
        self.assertEqual(Path(context["snapshot"]).read_bytes(), b"snapshot")
        self.assertEqual(context["fingerprint"], hashlib.sha256(b"snapshot").hexdigest())

    def test_metrics_survive_restart_and_mark_stale(self):
        self.lab.publish(dict(name="Count", value=7, fingerprint="a" * 64))
        restarted = NotebookLab(Path(self.tmp.name))
        self.addCleanup(restarted.stop)
        self.assertFalse(restarted.metrics("a" * 64)[0]["stale"])
        self.assertTrue(restarted.metrics("b" * 64)[0]["stale"])
        restarted.publish(dict(name="Count", value=8, fingerprint="a" * 64))
        self.assertEqual(len(restarted.metrics()), 1)
        self.assertEqual(restarted.metrics()[0]["value"], 8)

    def test_invalid_metric_does_not_destroy_saved_values(self):
        self.lab.publish(dict(name="Count", value=7, fingerprint="a" * 64))
        for value in (float("nan"), float("inf"), True, "7"):
            with self.assertRaises(ValueError):
                self.lab.publish(dict(name="Count", value=value, fingerprint="a" * 64))
        self.assertEqual(self.lab.metrics()[0]["value"], 7)
