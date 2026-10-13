"""The studio's local server: a JSON API over the analyses, and the web interface.

Runs on 127.0.0.1 only. Nothing leaves the Mac unless the optional AI is switched on.
"""
from __future__ import annotations

import json
import threading
from dataclasses import fields
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import analysis, watch
from .data import History

WEB = Path(__file__).resolve().parents[1] / "web"
SUPPORT = Path.home() / "Library/Application Support/GymApp Studio"
SETTINGS_FILE = SUPPORT / "settings.json"


class State:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.history: Optional[History] = None
        self.path: Optional[Path] = None
        self.loaded_at: Optional[datetime] = None
        self.settings = self._load_settings()
        self.folders: Optional[list[Path]] = None

    def _load_settings(self) -> analysis.Settings:
        s = analysis.Settings()
        try:
            saved = json.loads(SETTINGS_FILE.read_text())
            for f in fields(s):
                if f.name in saved:
                    value = saved[f.name]
                    setattr(s, f.name, tuple(value) if isinstance(getattr(s, f.name), tuple) else value)
        except (OSError, ValueError):
            pass
        return s

    def save_settings(self) -> None:
        SUPPORT.mkdir(parents=True, exist_ok=True)
        SETTINGS_FILE.write_text(json.dumps(self.settings.to_dict(), indent=1))

    def load(self, path: Path) -> None:
        h = History(path)
        with self.lock:
            self.history, self.path, self.loaded_at = h, path, datetime.now(timezone.utc)

    def require(self) -> History:
        if self.history is None:
            raise HTTPException(503, "No backup found yet. Choose a backup folder in Settings.")
        return self.history


state = State()
app = FastAPI(title="GymApp Studio", docs_url=None, redoc_url=None)


def start_watching(folders: Optional[list[Path]] = None, interval: float = 10.0) -> None:
    state.folders = folders
    first = watch.latest(folders)
    if first:
        state.load(first)
    threading.Thread(target=watch.follow, args=(lambda p: p != state.path and state.load(p), folders, interval),
                     daemon=True).start()


# API


@app.get("/api/status")
def status():
    h = state.history
    return {"backup": str(state.path) if state.path else None,
            "loaded_at": state.loaded_at.isoformat() if state.loaded_at else None,
            "workouts": len(h.workouts) if h else 0,
            "folders": [str(f) for f in (state.folders or watch.default_folders())]}


@app.post("/api/reload")
def reload():
    path = watch.latest(state.folders)
    if not path:
        raise HTTPException(404, "No backup found")
    state.load(path)
    return status()


@app.get("/api/settings")
def get_settings():
    return state.settings.to_dict()


@app.put("/api/settings")
def put_settings(values: dict):
    s = state.settings
    for f in fields(s):
        if f.name in values:
            current = getattr(s, f.name)
            value = values[f.name]
            setattr(s, f.name, tuple(value) if isinstance(current, tuple) else type(current)(value))
    state.save_settings()
    return s.to_dict()


@app.get("/api/overview")
def overview():
    return analysis.overview(state.require(), state.settings)


@app.get("/api/exercises")
def exercises():
    return analysis.exercise_index(state.require(), state.settings)


@app.get("/api/exercise/{exercise_id:path}")
def exercise(exercise_id: str):
    h = state.require()
    if exercise_id not in h.exercises:
        raise HTTPException(404, "Unknown exercise")
    return analysis.exercise_detail(h, exercise_id, state.settings)


@app.get("/api/muscles")
def muscles(weeks: int = 12):
    h = state.require()
    return {"weekly": analysis.weekly_muscle_sets(h, state.settings, weeks),
            "balance": analysis.balance(h, state.settings)}


@app.get("/api/history")
def history():
    return analysis.history_rows(state.require())


@app.get("/api/workout/{workout_id}")
def workout(workout_id: str):
    h = state.require()
    w = h.workouts.get(workout_id)
    if not w:
        raise HTTPException(404, "Unknown workout")
    return {"id": w.id, "title": w.title, "date": w.started_at.isoformat(), "minutes": round(w.duration_s / 60),
            "note": w.note, "effort": w.effort,
            "exercises": [{"id": x.exercise_id, "name": h.exercises[x.exercise_id].name if x.exercise_id in h.exercises else x.exercise_id,
                           "note": x.note,
                           "sets": [{"kg": round(y.kg, 2), "reps": y.reps, "type": y.type, "rir": y.reps_in_reserve} for y in x.sets]}
                          for x in w.sessions]}


@app.get("/api/formulas")
def formulas():
    return analysis.formula_consistency(state.require())


@app.get("/api/breaks")
def breaks():
    return analysis.breaks(state.require(), state.settings)


# Interface


@app.get("/")
def index():
    return FileResponse(WEB / "index.html")


app.mount("/", StaticFiles(directory=WEB), name="web")


@app.exception_handler(HTTPException)
def http_error(_, exc: HTTPException):
    return JSONResponse({"error": exc.detail}, status_code=exc.status_code)
