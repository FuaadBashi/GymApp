import json
import socket
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import patch

import uvicorn
from gymstudio import server
from tests.test_analysis import history, W
from tests.backups import make
from tests.test_analysis import EX


class RulesAPITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.patches = [patch.object(server, "SUPPORT", Path(cls.tmp.name)),
                       patch.object(server, "lab", server.NotebookLab(Path(cls.tmp.name))),
                       patch.object(server, "SETTINGS_FILE", Path(cls.tmp.name) / "settings.json")]
        for p in cls.patches: p.start()
        cls.patches.append(patch.object(server, "state", server.State()))
        cls.patches[-1].start()
        cls.backup = Path(cls.tmp.name) / "source.sqlite"
        make(cls.backup, EX, [(d, [("bench", [(60, 8, W)])]) for d in (0, 7, 14, 21, 28, 35, 42)])
        server.state.load(cls.backup)
        cls.sock = socket.socket(); cls.sock.bind(("127.0.0.1", 0))
        cls.base = f"http://127.0.0.1:{cls.sock.getsockname()[1]}"
        cls.service = uvicorn.Server(uvicorn.Config(server.app, log_level="error", ws="none"))
        cls.thread = threading.Thread(target=cls.service.run, kwargs={"sockets": [cls.sock]}, daemon=True)
        cls.thread.start()
        deadline = time.monotonic() + 5
        while not cls.service.started and time.monotonic() < deadline: time.sleep(.01)
        assert cls.service.started

    @classmethod
    def tearDownClass(cls):
        cls.service.should_exit = True; cls.thread.join(5); cls.sock.close()
        for p in reversed(cls.patches): p.stop()
        cls.tmp.cleanup()

    def request(self, path, data=None):
        request = urllib.request.Request(self.base + path, data=json.dumps(data).encode() if data is not None else None,
                                        headers={"Content-Type": "application/json"}, method="PUT" if data is not None else "GET")
        try:
            with urllib.request.urlopen(request) as response: return response.status, json.load(response)
        except urllib.error.HTTPError as response:
            with response: return response.code, json.load(response)

    def test_replay_endpoint_paginates_only_the_selected_rule(self):
        status, body = self.request("/api/rules?exercise_id=bench&rule=double_progression&limit=2")
        self.assertEqual(status, 200)
        self.assertEqual(len(body["rules"]), 5)
        self.assertEqual([len(r["trials"]) for r in body["rules"]], [2, 0, 0, 0, 0])
        self.assertEqual(body["rules"][0]["trial_count"], 7)
        self.assertIsNone(body["recommended_rule"])

    def test_missing_exercises_and_invalid_query_bounds_are_rejected(self):
        self.assertEqual(self.request("/api/rules?exercise_id=missing")[0], 404)
        self.assertEqual(self.request("/api/rules?outcome_days=0")[0], 422)
        self.assertEqual(self.request("/api/rules?rule=unknown")[0], 422)

    def test_invalid_settings_do_not_partly_mutate_or_save_the_configuration(self):
        before = server.state.settings.to_dict()
        status, _ = self.request("/api/settings", {"plateau_days": 2, "default_rep_range": [12, 8]})
        self.assertEqual(status, 422)
        self.assertEqual(server.state.settings.to_dict(), before)
        self.assertFalse(server.SETTINGS_FILE.exists())

    def test_settings_survive_reload_and_keep_their_types(self):
        status, _ = self.request("/api/settings", {"plateau_days": 28, "default_rep_range": [6, 10], "week_starts_monday": True})
        self.assertEqual(status, 200)
        saved = server.State().settings
        self.assertEqual(saved.plateau_days, 28)
        self.assertEqual(saved.default_rep_range, (6, 10))
        self.assertTrue(saved.week_starts_monday)
        # Restore the synthetic test configuration without touching user settings.
        self.request("/api/settings", {"plateau_days": 21, "default_rep_range": [8, 12], "week_starts_monday": False})
        server.SETTINGS_FILE.unlink()

    def test_invalid_new_backup_keeps_the_last_good_loaded_history(self):
        before = server.state.history
        bad = Path(self.tmp.name) / "bad.sqlite"; bad.write_text("partial bytes")
        self.assertFalse(server.state.try_load(bad))
        self.assertIs(server.state.history, before)
        self.assertIsNotNone(server.state.load_error)
        server.state.load(self.backup)

    def test_notebook_context_matches_loaded_snapshot_and_read_only_tables(self):
        status, context = self.request("/api/lab/context")
        self.assertEqual(status, 200)
        self.assertEqual(context["fingerprint"], server.state.fingerprint)
        from gymstudio.notebook import load_context
        with patch.dict("os.environ", {"GYMSTUDIO_API_URL": self.base}):
            loaded = load_context()
        self.assertEqual(len(loaded.history.workouts), 7)
        with self.assertRaises(TypeError): loaded.tables["new"] = []
        self.assertEqual(loaded.publish("Test count", 7)["value"], 7)

    def test_notebook_write_requires_local_token(self):
        request = urllib.request.Request(self.base + "/api/lab/notebooks", data=b'{"name":"blocked"}',
                                        headers={"Content-Type":"application/json"})
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        self.assertEqual(error.exception.code, 403)
        error.exception.close()
