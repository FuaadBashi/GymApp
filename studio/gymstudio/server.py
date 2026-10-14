"""The studio's local server: a JSON API over the analyses, and the web interface.

Runs on 127.0.0.1 only. Nothing leaves the Mac unless the optional AI is switched on.
"""
from __future__ import annotations

import json
import threading
import os
import tempfile
import sqlite3
import hashlib
import secrets
from contextlib import asynccontextmanager
from dataclasses import fields, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import analysis, ask, health, planner, progression, reports, suggestions, watch
from .data import History
from .lab import NotebookLab

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
        self.load_error = None
        self.reports: list = []
        self.reports_info: dict = {}
        self.snapshot = None
        self.fingerprint = None

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
        try:
            progression.validate_settings(s)
        except ValueError:
            return analysis.Settings()
        return s

    def save_settings(self, settings=None) -> None:
        SUPPORT.mkdir(parents=True, exist_ok=True)
        name = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=SUPPORT, delete=False) as file:
                name = file.name
                file.write(json.dumps((settings or self.settings).to_dict(), indent=1))
                file.flush()
                os.fsync(file.fileno())
            os.replace(name, SETTINGS_FILE)
        finally:
            if name and os.path.exists(name): os.unlink(name)

    def load(self, path: Path) -> None:
        # Freeze the exact bytes shared with notebooks before validating/loading.
        content = path.read_bytes()
        fingerprint = hashlib.sha256(content).hexdigest()
        folder = SUPPORT / "LoadedData"
        folder.mkdir(parents=True, exist_ok=True)
        snapshot = folder / (fingerprint + ".sqlite")
        if not snapshot.exists():
            with tempfile.NamedTemporaryFile(dir=folder, delete=False) as file:
                temporary = Path(file.name)
                file.write(content)
            try:
                h = History(temporary)
                os.replace(temporary, snapshot)
            finally:
                temporary.unlink(missing_ok=True)
        else:
            h = History(snapshot)
        with self.lock:
            self.history, self.path, self.loaded_at = h, path, datetime.now(timezone.utc)
            self.snapshot, self.fingerprint = snapshot, fingerprint
            self.load_error = None
        self.refresh_reports()

    def refresh_reports(self) -> None:
        """Card 8.1: rebuild every report and write them beside the loaded backup."""
        try:
            built = reports.build(self.history, self.settings)
            info = reports.write(built, self.path.parent)
            self.reports, self.reports_info = built, {**info, "error": None}
        except (OSError, ValueError) as error:
            self.reports_info = {"error": f"Reports could not be written: {error}"}

    def try_load(self, path: Path) -> bool:
        try:
            self.load(path)
            return True
        except (OSError, ValueError, sqlite3.Error):
            self.load_error = "Newest backup is unavailable or invalid; keeping the previous loaded data."
            return False

    def require(self) -> History:
        if self.history is None:
            raise HTTPException(503, "No backup found yet. Choose a backup folder in Settings.")
        return self.history


state = State()
lab = NotebookLab(SUPPORT)
WRITE_TOKEN = secrets.token_urlsafe(32)


@asynccontextmanager
async def lifespan(_):
    yield
    lab.stop()


app = FastAPI(title="GymApp Studio", docs_url=None, redoc_url=None, lifespan=lifespan)


def start_watching(folders: Optional[list[Path]] = None, interval: float = 10.0) -> None:
    state.folders = folders
    first = watch.latest(folders)
    if first:
        state.try_load(first)
    threading.Thread(target=watch.follow, args=(state.try_load, folders, interval),
                     daemon=True).start()


# API


@app.get("/api/status")
def status():
    h = state.history
    return {"backup": str(state.path) if state.path else None,
            "load_error": state.load_error,
            "loaded_at": state.loaded_at.isoformat() if state.loaded_at else None,
            "workouts": len(h.workouts) if h else 0,
            "folders": [str(f) for f in (state.folders or watch.default_folders())]}


@app.post("/api/reload")
def reload():
    path = watch.latest(state.folders)
    if not path:
        raise HTTPException(404, "No backup found")
    if not state.try_load(path): raise HTTPException(422, state.load_error)
    return status()


@app.get("/api/settings")
def get_settings():
    return state.settings.to_dict()


@app.put("/api/settings")
def put_settings(values: dict):
    known = {f.name for f in fields(state.settings)}
    if set(values) - known: raise HTTPException(422, "Unknown settings")
    try:
        with state.lock:
            s = replace(state.settings, **values)
            progression.validate_settings(s)
            state.save_settings(s)
            state.settings = s
    except (TypeError, ValueError) as error:
        raise HTTPException(422, str(error)) from error
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


@app.get("/api/rules")
def rules(exercise_id: Optional[str] = None, outcome_days: int = Query(21, ge=7, le=180),
          holdout_fraction: float = Query(.3, ge=.1, le=.8), rule: Optional[str] = None,
          offset: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=500)):
    h = state.require()
    if exercise_id is not None and exercise_id not in h.exercises:
        raise HTTPException(404, "Unknown exercise")
    if rule is not None and rule not in progression.RULES:
        raise HTTPException(422, "Unknown progression rule")
    try:
        result = progression.backtest(h, state.settings, exercise_id, outcome_days, holdout_fraction)
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    for entry in result["rules"]:
        trials = entry.pop("trials")
        entry["trial_count"] = len(trials)
        entry["trials"] = list(reversed(trials))[offset:offset + limit] if rule == entry["id"] else []
    return result


# Interface


@app.get("/api/lab/notebooks")
def notebooks():
    return {"notebooks": lab.list(), "folder": str(lab.notebooks)}


@app.post("/api/lab/notebooks")
def create_notebook(values: dict, request: Request):
    check_notebook_write(request)
    try:
        return lab.create(values.get("name"))
    except (ValueError, FileExistsError) as error:
        raise HTTPException(422, str(error)) from error


@app.get("/api/lab/context")
def notebook_context():
    with state.lock:
        state.require()
        return lab.context(state.snapshot, state.settings.to_dict(), WRITE_TOKEN)


@app.post("/api/lab/start")
def start_notebooks(request: Request):
    check_notebook_write(request)
    try:
        return lab.start(str(request.base_url).rstrip("/"))
    except ValueError as error:
        raise HTTPException(503, str(error)) from error


@app.get("/api/lab/metrics")
def notebook_metrics():
    return {"metrics": lab.metrics(state.fingerprint)}


@app.post("/api/lab/metrics")
def publish_metric(values: dict, request: Request):
    check_notebook_write(request)
    try:
        return lab.publish(values)
    except ValueError as error:
        raise HTTPException(422, str(error)) from error


@app.get("/api/ask/config")
def ask_config():
    return {"has_key": ask.get_key() is not None, "claude_models": ask.CLAUDE_MODELS,
            "local_models": ask.local_models(), "presets": ask.PRESETS}


def check_same_origin(request: Request) -> None:
    origin = request.headers.get("origin")
    if origin and origin != str(request.base_url).rstrip("/"):
        raise HTTPException(403, "Requests must come from Studio")


@app.put("/api/ask/key")
def ask_key(values: dict, request: Request):
    check_same_origin(request)
    key = (values.get("key") or "").strip()
    if key and not key.startswith("sk-ant-"):
        raise HTTPException(422, "That doesn't look like an Anthropic API key (it starts with sk-ant-).")
    ask.set_key(key or None)
    return {"has_key": ask.get_key() is not None}


@app.post("/api/ask")
def ask_question(values: dict, request: Request):
    check_same_origin(request)
    h = state.require()
    question = (values.get("question") or "").strip()
    if not question:
        raise HTTPException(422, "Ask a question")
    mode = "full" if values.get("mode") == "full" else "summaries"
    provider = "local" if values.get("provider") == "local" else "claude"
    try:
        a = ask.ask(h, state.settings, question, values.get("history") or [], provider, values.get("model"), mode,
                    db_path=state.snapshot)
    except RuntimeError as error:
        raise HTTPException(502, str(error)) from error
    return {"answer": a.text, "tool_calls": a.tool_calls, "provider": a.provider, "model": a.model, "mode": mode,
            "unverified": a.unverified}


def suggestions_folder() -> Path:
    """Suggestions go beside the loaded backup, which is the phone's backup folder when the
    studio reads it from iCloud Drive."""
    state.require()
    return state.path.parent


@app.get("/api/reports")
def get_reports():
    state.require()
    return {"folder": str(state.path.parent / reports.FOLDER), "info": state.reports_info,
            "reports": [{"id": r.id, "kind": r.kind, "title": r.title, "headline": r.headline,
                         "from": r.start.date().isoformat()}
                        for r in sorted(state.reports, key=lambda r: (r.end, r.kind == "week"), reverse=True)]}


@app.get("/api/reports/{report_id}")
def get_report(report_id: str):
    state.require()
    for r in state.reports:
        if r.id == report_id:
            return {**r.app_dict(), "markdown": r.markdown(), "figures": {k: v for k, v in r.figures.items() if k != "muscles"},
                    "muscles": r.figures.get("muscles", {})}
    raise HTTPException(404, "No such report")


@app.get("/api/health")
def get_health():
    h = state.require()
    folder = suggestions_folder()
    decided = suggestions.decisions(folder)
    live = {i["id"] for i in suggestions.published(folder)}
    return {"findings": [{**f, "published": f["id"] in live, "decision": (decided.get(f["id"]) or {}).get("decision")}
                         for f in health.findings(h)]}


@app.post("/api/health/publish")
def publish_fixes(values: dict, request: Request):
    """Publishes the ticked fixes as `fix` suggestions, keeping what is already waiting."""
    check_same_origin(request)
    h = state.require()
    folder = suggestions_folder()
    wanted = set(values.get("ids") or [])
    created = analysis.now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")
    fixes = [health.suggestion(f, created) for f in health.findings(h) if f["id"] in wanted and f["fix"]]
    decided = suggestions.decisions(folder)
    keep = [i for i in suggestions.published(folder) if i["id"] not in decided]
    try:
        written = suggestions.publish(folder, keep + fixes)
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    return {"published": len(fixes), "waiting": len(written)}


@app.get("/api/planner")
def get_plan(weeks: int = Query(5, ge=4, le=6)):
    return planner.plan(state.require(), state.settings, weeks)


@app.post("/api/planner/send")
def send_plan(values: dict, request: Request):
    """Only on the owner's press: the chosen weeks go to the phone as notes."""
    check_same_origin(request)
    h = state.require()
    p = planner.plan(h, state.settings, int(values.get("weeks") or 5))
    if p.get("error"):
        raise HTTPException(422, p["error"])
    folder = suggestions_folder()
    items = planner.notes(p, [int(w) for w in values.get("chosen") or []], analysis.now_utc().strftime("%Y-%m-%dT%H:%M:%SZ"))
    decided = suggestions.decisions(folder)
    keep = [i for i in suggestions.published(folder) if i["id"] not in decided]
    written = suggestions.publish(folder, keep + items)
    return {"published": len(items), "waiting": len(written)}


@app.get("/api/suggestions")
def get_suggestions():
    h = state.require()
    folder = suggestions_folder()
    decided = suggestions.decisions(folder)
    live = {i["id"] for i in suggestions.published(folder)}
    drafts = [d for d in suggestions.drafts(h, state.settings) if d["id"] not in decided and d["id"] not in live]
    return {"folder": str(folder), "drafts": drafts, "published": suggestions.published(folder),
            "decisions": list(decided.values())}


@app.post("/api/suggestions/publish")
def publish_suggestions(values: dict, request: Request):
    check_same_origin(request)
    folder = suggestions_folder()
    items = list(values.get("items") or [])
    for n in values.get("notes") or []:
        try:
            items.append(suggestions.note(n.get("title", ""), n.get("detail", ""), n.get("reason", "")))
        except ValueError as error:
            raise HTTPException(422, str(error)) from error
    try:
        written = suggestions.publish(folder, items)
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    return {"published": written, "folder": str(folder)}


def check_notebook_write(request):
    if not secrets.compare_digest(request.headers.get("X-Studio-Token", ""), WRITE_TOKEN):
        raise HTTPException(403, "Invalid notebook write token")
    origin = request.headers.get("origin")
    if origin and origin != str(request.base_url).rstrip("/"):
        raise HTTPException(403, "Notebook writes must come from Studio")


@app.get("/")
def index():
    return FileResponse(WEB / "index.html")


app.mount("/", StaticFiles(directory=WEB), name="web")


@app.exception_handler(HTTPException)
def http_error(_, exc: HTTPException):
    return JSONResponse({"error": exc.detail}, status_code=exc.status_code)
