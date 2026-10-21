"""Ask: questions about your training, answered by a language model that calls the studio's
tested functions. The model explains; it never computes figures itself.

Two data modes (docs/STUDIO_PLAN.md section 7):
- "summaries" (default): tools return only figures the studio computed. No raw sets, no notes.
- "full": adds read-only SQL over the backup snapshot, single workouts and note search.

Two providers: Claude (Anthropic Messages API; the key lives in the macOS keychain) and a
local model through Ollama. Both use plain HTTPS from the standard library.
"""
from __future__ import annotations

import json
import time
import sqlite3
import subprocess
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Optional

from . import analysis, progression
from .data import History

KEYCHAIN_SERVICE = "GymApp Studio"
KEYCHAIN_ACCOUNT = "anthropic"
CLAUDE_MODELS = ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"]
MAX_STEPS = 8
LOCAL_DEADLINE = 180      # seconds for one local answer; a laptop model must stop, not run for 40 minutes
LOCAL_TOOL_CHARS = 12000  # about 3,000 tokens: fits the local context below
LOCAL_CONTEXT = 8192      # tokens; Ollama's smaller default silently drops long tool results

SYSTEM = """You are the analysis assistant inside GymApp Studio, a private training analysis tool for one lifter.
Answer from the tools only. Every number you state must come from a tool result; never estimate, compute or invent figures.
If the tools can't answer, say what is missing. Be concise and practical: short paragraphs or bullets, kg as given.
Training facts: loads are as entered (kg or lb); e1RM is Epley; a plateau is three weeks of continuous training with no
session-to-session weight increase; muscle volume is fractional hard sets per week (1 primary, 0.5 secondary), target band 10-20.
The history up to Oct 2026 came from JEFIT and has no reps-in-reserve; the rule lab therefore has no proven winner yet.
When suggesting changes, label them as suggestions and give the reason from the data. Today is {today}."""


# Keychain


def get_key() -> Optional[str]:
    r = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() or None if r.returncode == 0 else None


def set_key(key: Optional[str]) -> None:
    if not key:
        subprocess.run(["security", "delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT],
                       capture_output=True)
        return
    subprocess.run(["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w", key],
                   check=True, capture_output=True)


# Tools


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict
    run: Callable[..., object]
    full_only: bool = False


def resolve_exercise(h: History, s: analysis.Settings, text: str) -> Optional[str]:
    """An id, or the most-trained exercise whose name contains every word of the text."""
    if text in h.exercises:
        return text
    words = text.lower().split()
    matches = [r for r in analysis.exercise_index(h, s) if all(w in r["name"].lower() for w in words)]
    return max(matches, key=lambda r: r["sessions"])["id"] if matches else None


def _exercise_summary(h: History, s: analysis.Settings, exercise_id: str = "", name: str = "", **extra) -> dict:
    text = exercise_id if exercise_id in h.exercises else (name or extra.get("query") or exercise_id)
    exercise_id = resolve_exercise(h, s, text) if text else None
    if exercise_id is None:
        return {"error": f"no exercise matches '{text}'; use find_exercises"}
    d = analysis.exercise_detail(h, exercise_id, s)
    d.pop("sessions", None)
    pts = d.pop("points")
    d["recent_points"] = pts[-12:]
    d["session_count"] = len(pts)
    d["records"]["rep_records"] = d["records"]["rep_records"][:10]
    return d


def _find_exercises(h: History, s: analysis.Settings, query: str = "") -> list:
    from . import stats
    q = query.lower()
    out = []
    for r in analysis.exercise_index(h, s):
        if q not in r["name"].lower():
            continue
        best = stats.records(h, r["id"]).best_e1rm
        out.append({"id": r["id"], "name": r["name"], "sessions": r["sessions"], "last_trained": r["last_done"][:10],
                    "best_e1rm_kg": round(best.value_kg, 1) if best else None,
                    "best_e1rm_date": best.date.date().isoformat() if best else None,
                    "plateau_status": r["plateau"], "in_program": r["in_program"]})
        if len(out) == 25:
            break
    return out


def _rule_lab(h: History, s: analysis.Settings, exercise_id: Optional[str] = None) -> dict:
    r = progression.backtest(h, s, exercise_id)
    return {"recommended_rule": r["recommended_rule"], "limitations": r["limitations"],
            "rules": [{"id": x["id"], "name": x["name"], "metrics": x["metrics"], "holdout": x.get("holdout")} for x in r["rules"]]}


def _sql(db_path, query: str) -> dict:
    q = query.strip().rstrip(";")
    if not q.lower().startswith(("select", "with")):
        return {"error": "only SELECT queries are allowed"}
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        cur = db.execute(q)
        rows = cur.fetchmany(200)
        return {"columns": [c[0] for c in cur.description or []], "rows": rows, "truncated": len(rows) == 200}
    except sqlite3.Error as e:
        return {"error": str(e)}
    finally:
        db.close()


def _workout(h: History, workout_id: str) -> dict:
    w = h.workouts.get(workout_id)
    if not w:
        return {"error": "unknown workout id"}
    return {"title": w.title, "date": w.started_at.isoformat(), "minutes": round(w.duration_s / 60), "note": w.note,
            "exercises": [{"name": h.exercises[x.exercise_id].name if x.exercise_id in h.exercises else x.exercise_id,
                           "note": x.note, "sets": [f"{y.kg:g}x{y.reps} {y.type}" + (f" @{y.reps_in_reserve}" if y.reps_in_reserve is not None else "")
                                                    for y in x.sets]} for x in w.sessions]}


def _notes(h: History, text: str = "") -> list:
    t = text.lower()
    names = {k: v.name for k, v in h.exercises.items()}
    return [{"date": n["date"], "exercise": names.get(n["exerciseId"], n["exerciseId"]), "text": n["text"]}
            for n in h.exercise_notes if t in n["text"].lower()][:80]


def tools(h: History, s: analysis.Settings, db_path=None) -> list[Tool]:
    db_path = db_path or h.path
    obj = lambda props, req=(): {"type": "object", "properties": props, "required": list(req)}
    ex_id = {"exercise_id": {"type": "string", "description": "id from find_exercises, e.g. jefit:1:2"}}
    return [
        Tool("overview", "Totals, this week, streak, plateaus, next-session targets for the program, balance and breaks.",
             obj({}), lambda: analysis.overview(h, s)),
        Tool("find_exercises", "Search exercises by name; returns ids, session counts, best e1RM and plateau status.",
             obj({"query": {"type": "string"}}), lambda query="": _find_exercises(h, s, query)),
        Tool("exercise_summary", "Computed figures for one exercise (by id or by name, e.g. 'bench press'): records, plateau, progress rate, next target, weak points, breaks, load step, recent points.",
             obj({**ex_id, "name": {"type": "string", "description": "exercise name if the id is unknown"}}),
             lambda exercise_id="", name="", **kw: _exercise_summary(h, s, exercise_id, name, **kw)),
        Tool("muscle_volume", "Fractional hard sets per muscle per week for recent weeks, with the target band.",
             obj({"weeks": {"type": "integer"}}), lambda weeks=8: analysis.weekly_muscle_sets(h, s, max(1, min(int(weeks), 52)))),
        Tool("balance", "Push:pull, upper:lower, quads:hamstrings and chest:back hard-set ratios over recent weeks.",
             obj({"days": {"type": "integer"}}), lambda days=28: analysis.balance(h, s, max(7, min(int(days), 365)))),
        Tool("consistency", "Sessions per week over recent weeks and the current streak.",
             obj({"weeks": {"type": "integer"}}), lambda weeks=26: analysis.consistency(h, s, max(1, min(int(weeks), 260)))),
        Tool("rule_lab", "Back-test of progression and deload rules over the history, overall or for one exercise.",
             obj({"exercise_id": {"type": "string"}}), lambda exercise_id=None: _rule_lab(h, s, exercise_id)),
        Tool("formula_lab", "Which 1RM formula is most consistent on this lifter's sets.", obj({}),
             lambda: analysis.formula_consistency(h)),
        Tool("sql", "Read-only SQL (SELECT) over the backup. Tables: exercise, workout, workoutExercise, workoutSet, exerciseNote, bodyEntry, program, programDay, dayExercise. History = workout.endedAt IS NOT NULL and workoutSet.completedAt IS NOT NULL. Loads: loadHundredths/100 in unit.",
             obj({"query": {"type": "string"}}, ["query"]), lambda query: _sql(db_path, query), full_only=True),
        Tool("workout", "Every set of one workout, with notes.", obj({"workout_id": {"type": "string"}}, ["workout_id"]),
             lambda workout_id: _workout(h, workout_id), full_only=True),
        Tool("search_notes", "Exercise notes containing the text (empty text returns recent notes).",
             obj({"text": {"type": "string"}}), lambda text="": _notes(h, text), full_only=True),
    ]


def available(h: History, s: analysis.Settings, mode: str, db_path=None) -> list[Tool]:
    return [t for t in tools(h, s, db_path) if mode == "full" or not t.full_only]


def call_tool(ts: list[Tool], name: str, args: dict) -> str:
    tool = next((t for t in ts if t.name == name), None)
    if tool is None:
        return json.dumps({"error": f"tool {name} is not available in this mode"})
    try:
        result = tool.run(**(args or {}))
    except TypeError as e:
        result = {"error": f"bad arguments: {e}"}
    text = json.dumps(result, default=str)
    return text if len(text) < 60000 else text[:60000] + '..."(truncated)"'


# Providers


def _post(url: str, body: dict, headers: dict, timeout: int = 120) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:400]
        raise RuntimeError(f"{e.code}: {detail}") from e


def claude_turn(messages: list, ts: list[Tool], model: str, key: str, system: str) -> dict:
    return _post("https://api.anthropic.com/v1/messages",
                 {"model": model, "max_tokens": 2000, "system": system, "messages": messages,
                  "tools": [{"name": t.name, "description": t.description, "input_schema": t.parameters} for t in ts]},
                 {"x-api-key": key, "anthropic-version": "2023-06-01"})


def ollama_turn(messages: list, ts: list[Tool], model: str, system: str, timeout: float = LOCAL_DEADLINE) -> dict:
    # keep_alive frees the model's memory two minutes after the answer, so the Mac recovers.
    return _post("http://127.0.0.1:11434/api/chat",
                 {"model": model, "stream": False, "keep_alive": "2m", "options": {"num_ctx": LOCAL_CONTEXT},
                  "messages": [{"role": "system", "content": system}] + messages,
                  "tools": [{"type": "function", "function": {"name": t.name, "description": t.description, "parameters": t.parameters}} for t in ts]},
                 {}, timeout=max(1, int(timeout)))


@dataclass
class Answer:
    text: str
    tool_calls: list = field(default_factory=list)
    provider: str = ""
    model: str = ""
    unverified: list = field(default_factory=list)   # figures in the text not found in any tool result


import re

_NUMBER = re.compile(r"(?<![\d.])-?\d+(?:[.,]\d+)?(?![\d])")


def unverified_numbers(text: str, tool_outputs: list[str], question: str = "") -> list[str]:
    """Figures the answer states that no tool returned. Small whole numbers (counts up to
    31, like "3 weeks") and numbers from the question are allowed; everything else must
    match a tool value to within rounding. Dates are matched by their parts."""
    pool = []
    for out in tool_outputs + [question]:
        for m in _NUMBER.findall(out):
            try:
                pool.append(float(m.replace(",", "")))
            except ValueError:
                pass
    bad = []
    for m in _NUMBER.findall(text):
        try:
            v = float(m.replace(",", ""))
        except ValueError:
            continue
        if v.is_integer() and 0 <= v <= 31:
            continue
        decimals = len(m.split(".")[1]) if "." in m else 0
        tol = 0.5 * 10 ** -decimals + 1e-9
        if not any(abs(v - x) <= tol or abs(abs(v) - abs(x)) <= tol for x in pool):
            bad.append(m)
    return sorted(set(bad), key=bad.index)


def ask(h: History, s: analysis.Settings, question: str, history: list | None = None, provider: str = "claude",
        model: Optional[str] = None, mode: str = "summaries", db_path=None,
        claude: Callable = claude_turn, ollama: Callable = ollama_turn) -> Answer:
    """Runs the tool loop. `history` is earlier [{"role", "content"}] text turns of this chat."""
    ts = available(h, s, mode, db_path)
    system = SYSTEM.format(today=datetime.now().strftime("%A %d %B %Y"))
    calls, outputs = [], []
    msgs = [{"role": m["role"], "content": m["content"]} for m in (history or [])] + [{"role": "user", "content": question}]
    if provider == "claude":
        key = get_key()
        if not key:
            raise RuntimeError("No Claude API key. Add one in Settings, or switch to the local model.")
        model = model or CLAUDE_MODELS[0]
        for _ in range(MAX_STEPS):
            r = claude(msgs, ts, model, key, system)
            uses = [b for b in r["content"] if b["type"] == "tool_use"]
            if not uses:
                text = "".join(b.get("text", "") for b in r["content"] if b["type"] == "text")
                return Answer(text, calls, provider, model, unverified_numbers(text, outputs, question))
            msgs.append({"role": "assistant", "content": r["content"]})
            results = []
            for u in uses:
                calls.append({"tool": u["name"], "input": u["input"]})
                out = call_tool(ts, u["name"], u["input"])
                outputs.append(out)
                results.append({"type": "tool_result", "tool_use_id": u["id"], "content": out})
            msgs.append({"role": "user", "content": results})
    else:
        model = model or (local_models() or ["llama3.2"])[0]
        deadline = time.monotonic() + LOCAL_DEADLINE
        for _ in range(MAX_STEPS):
            left = deadline - time.monotonic()
            if left <= 0:
                return Answer(f"The local model ({model}) took more than {LOCAL_DEADLINE // 60} minutes, so I stopped it. "
                              "Pick a smaller model, ask a narrower question, or use Summaries only.", calls, provider, model)
            try:
                r = ollama(msgs, ts, model, system, left)
            except (TimeoutError, OSError) as e:
                if "timed out" not in str(e):
                    raise
                return Answer(f"The local model ({model}) took more than {LOCAL_DEADLINE // 60} minutes, so I stopped it. "
                              "Pick a smaller model, ask a narrower question, or use Summaries only.", calls, provider, model)
            m = r["message"]
            uses = m.get("tool_calls") or []
            if not uses:
                text = m.get("content", "")
                return Answer(text, calls, provider, model, unverified_numbers(text, outputs, question))
            msgs.append(m)
            for u in uses:
                fn = u["function"]
                args = fn.get("arguments") or {}
                if isinstance(args, str):
                    args = json.loads(args or "{}")
                calls.append({"tool": fn["name"], "input": args})
                out = call_tool(ts, fn["name"], args)
                outputs.append(out)
                if len(out) > LOCAL_TOOL_CHARS:
                    out = out[:LOCAL_TOOL_CHARS] + '..."(truncated: ask a narrower question for the rest)"'
                msgs.append({"role": "tool", "content": out})
    return Answer("I ran out of steps before finishing. Try a narrower question.", calls, provider, model)


def local_models() -> list[str]:
    try:
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=2) as r:
            models = json.loads(r.read())["models"]
            # Text models first, smallest first: the first is the default, and a small model
            # answers in seconds where a 14B one can fill a 16 GB Mac's memory.
            return [m["name"] for m in sorted(models, key=lambda m: ("vision" in m["name"], m.get("size", 0), m["name"]))]
    except (OSError, ValueError, KeyError):
        return []


PRESETS = {
    "weekly": "Give me my weekly review: what went up, what stalled, what I skipped, muscle volume against the band, and two or three concrete suggestions for next week.",
    "plateaus": "Which of my program's lifts are stalled or rebuilding, what is the likely weak point for each, and what do you suggest?",
    "balance": "Is my training balanced? Use the balance and muscle volume tools and say what to change.",
    "notes": "Read my exercise notes and summarise the recurring themes: injuries or pain, machine set-ups and seat positions, and cues. Group by exercise.",
}
