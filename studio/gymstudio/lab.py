"""Private notebook files, immutable analysis snapshots and local metric storage."""
import atexit
import hashlib
import json
import math
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.request import urlopen


class NotebookLab:
    def __init__(self, folder: Path):
        self.folder = folder
        self.notebooks = folder / "Notebooks"
        self.metrics_file = folder / "metrics.json"
        self.process = self.port = self.token = None
        self.lock = threading.RLock()
        atexit.register(self.stop)

    def seed(self):
        self.notebooks.mkdir(parents=True, exist_ok=True)
        for source in (Path(__file__).resolve().parents[1] / "notebooks").glob("*.py"):
            destination = self.notebooks / source.name
            if not destination.exists():
                shutil.copyfile(source, destination)

    def list(self):
        self.seed()
        return [{"name": p.stem, "filename": p.name} for p in sorted(self.notebooks.glob("*.py"))]

    def create(self, name):
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", name):
            raise ValueError("Use 1–64 letters, numbers, underscores or hyphens")
        self.seed()
        source = Path(__file__).resolve().parents[1] / "notebooks/training_explorer.py"
        with (self.notebooks / (name + ".py")).open("x") as file:
            file.write(source.read_text())
        return {"name": name, "filename": name + ".py"}

    def context(self, backup, settings, write_token):
        with self.lock:
            digest = hashlib.sha256(backup.read_bytes()).hexdigest()
            folder = self.folder / "NotebookData"
            folder.mkdir(parents=True, exist_ok=True)
            destination = folder / (digest + ".sqlite")
            if not destination.exists():
                partial = folder / (digest + ".partial")
                shutil.copyfile(backup, partial)
                os.replace(partial, destination)
            return dict(snapshot=str(destination), fingerprint=digest, settings=settings, write_token=write_token)

    def metrics(self, fingerprint=None):
        with self.lock:
            try:
                rows = json.loads(self.metrics_file.read_text())
            except (OSError, ValueError):
                rows = []
            return [dict(row, stale=fingerprint is not None and row["fingerprint"] != fingerprint)
                    for row in rows if not row.get("archived")]

    def publish(self, values):
        from datetime import datetime, timezone
        name, value = values.get("name"), values.get("value")
        if not isinstance(name, str) or not 1 <= len(name) <= 80:
            raise ValueError("A metric needs a name of 1–80 characters")
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("Metric value must be a finite number")
        for key, limit in (("unit", 40), ("description", 400)):
            if not isinstance(values.get(key, ""), str) or len(values.get(key, "")) > limit:
                raise ValueError("Invalid metric " + key)
        if not re.fullmatch(r"[a-f0-9]{64}", str(values.get("fingerprint", ""))):
            raise ValueError("Invalid snapshot fingerprint")
        row = dict(name=name, value=value, unit=values.get("unit", ""), description=values.get("description", ""),
                   fingerprint=values["fingerprint"], updated_at=datetime.now(timezone.utc).isoformat())
        with self.lock:
            rows = [r for r in self.metrics() if r["name"] != name]
            rows.append(row)
            self.folder.mkdir(parents=True, exist_ok=True)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode="w", dir=self.folder, delete=False) as file:
                    temporary = file.name
                    json.dump(rows, file, allow_nan=False)
                    file.flush()
                    os.fsync(file.fileno())
                os.replace(temporary, self.metrics_file)
            finally:
                if temporary and os.path.exists(temporary): os.unlink(temporary)
        return row

    def start(self, api_url):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                return {"url": f"http://127.0.0.1:{self.port}/?access_token={self.token}"}
            self.seed()
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                self.port = sock.getsockname()[1]
            self.token = secrets.token_urlsafe(32)
            password = self.folder / "notebook-token"
            password.write_text(self.token)
            password.chmod(0o600)
            environment = dict(os.environ, GYMSTUDIO_API_URL=api_url,
                               PYTHONPATH=str(Path(__file__).resolve().parents[1]) + os.pathsep + os.environ.get("PYTHONPATH", ""))
            with (self.folder / "notebook-server.log").open("a") as log:
                self.process = subprocess.Popen([sys.executable, "-m", "marimo", "edit", str(self.notebooks),
                    "--headless", "--host", "127.0.0.1", "--port", str(self.port), "--token-password-file", str(password),
                    "--skip-update-check", "--no-sandbox"], env=environment, stdout=log, stderr=log, start_new_session=True)
            url = f"http://127.0.0.1:{self.port}/?access_token={self.token}"
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and self.process.poll() is None:
                try:
                    with urlopen(url, timeout=.5) as response:
                        if response.status == 200: return {"url": url}
                except OSError:
                    pass
                time.sleep(.1)
            self.stop()
            raise ValueError("Notebook editor did not start. Check the installed requirements.")

    def stop(self):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                try:
                    os.killpg(self.process.pid, signal.SIGTERM)
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
                except ProcessLookupError:
                    pass
            self.process = None
