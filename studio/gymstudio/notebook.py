"""Notebook access to the dashboard snapshot and local custom metrics."""
import json
import os
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from urllib.request import Request, urlopen

from .analysis import Settings
from .data import History


@dataclass
class Context:
    history: History
    settings: Settings
    tables: object
    fingerprint: str
    _token: str
    _url: str

    def publish(self, name, value, unit="", description=""):
        payload = dict(name=name, value=value, unit=unit, description=description,
                       fingerprint=self.fingerprint)
        request = Request(self._url + "/api/lab/metrics", data=json.dumps(payload, allow_nan=False).encode(),
                          headers={"Content-Type": "application/json", "X-Studio-Token": self._token})
        with urlopen(request, timeout=10) as response:
            return json.load(response)


def load_context():
    url = os.environ.get("GYMSTUDIO_API_URL", "http://127.0.0.1:8765")
    with urlopen(url + "/api/lab/context", timeout=10) as response:
        context = json.load(response)
    path = Path(context["snapshot"])
    history = History(path)
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)) as db:
        db.row_factory = sqlite3.Row
        names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        tables = MappingProxyType({name: tuple(MappingProxyType(dict(r)) for r in db.execute(
            'SELECT * FROM "' + name.replace('"', '""') + '"')) for name in names})
    return Context(history, Settings(**context["settings"]), tables, context["fingerprint"], context["write_token"], url)
