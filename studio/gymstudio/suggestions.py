"""Suggestions for the phone (card 6.3). The studio drafts them from its checks, the owner
reviews and publishes, and the app shows each with its reason until it is accepted or
dismissed. The file format is docs/specs/06-studio-phone.md, card 6.3.

Ids are derived from what the suggestion is about and the session it was based on, so
drafting again after publishing gives the same id, and a decided suggestion is not offered
twice."""
from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from . import analysis
from .data import History

FILE = "GymApp-suggestions.json"
DECISIONS = "GymApp-suggestion-decisions.json"
KINDS = ("target", "swap", "note")


def _id(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


def _iso(when: datetime) -> str:
    return when.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _first_int(text: str) -> Optional[int]:
    m = re.search(r"\d+", str(text))
    return int(m.group()) if m else None


def close_variant(h: History, exercise_id: str, exclude: set[str]) -> Optional[str]:
    """Another exercise for the same primary muscle and movement pattern, the one done most
    often, for a swap after a plateau."""
    ex = h.exercises[exercise_id]
    if not ex.primary_muscles:
        return None
    best, count = None, 0
    for oid, other in h.exercises.items():
        if oid in exclude or oid == exercise_id or other.is_archived:
            continue
        if other.primary_muscles[:1] != ex.primary_muscles[:1] or other.movement_pattern != ex.movement_pattern:
            continue
        n = len(analysis.per_workout(h, oid))
        if n > count:
            best, count = oid, n
    return best


def drafts(h: History, s: analysis.Settings, today: Optional[datetime] = None) -> list[dict]:
    """Targets for every exercise in the active program; on a plateau, the deload target, a
    swap to a close variant in that day, and the weak-point check as a note."""
    today = today or analysis.now_utc()
    created = _iso(today)
    out: list[dict] = []
    days = {}
    for item in h.active_day_items():
        days.setdefault(item["exerciseId"], []).append(item["dayId"])
    for eid, day_ids in days.items():
        if eid not in h.exercises:
            continue
        ex = h.exercises[eid]
        t = analysis.next_target(h, eid, s, today)
        if not t:
            continue
        sessions = analysis.per_workout(h, eid)
        last = sessions[-1][1].date().isoformat()
        reps = _first_int(t["reps"])
        rule = {"plateau": "plateau_deload", "add weight": "double_progression", "add reps": "double_progression"}[t["kind"]]
        out.append({"id": _id("target", eid, last), "created": created, "kind": "target",
                    "title": f"{ex.name}: {t['weight']:g} {t['unit']} × {reps}",
                    "detail": f"Next session. Last time: {', '.join(t['last'])}.",
                    "reason": t["reason"], "rule": rule, "exerciseId": eid, "dayId": None,
                    "change": {"weight": t["weight"], "unit": t["unit"], "reps": reps}})
        if t["kind"] != "plateau":
            continue
        for day_id in day_ids:
            in_day = {i["exerciseId"] for i in h.day_items if i["dayId"] == day_id}
            to = close_variant(h, eid, in_day)
            if to:
                day_name = h.program_days.get(day_id, {}).get("name", "the day")
                out.append({"id": _id("swap", eid, to, day_id, last), "created": created, "kind": "swap",
                            "title": f"Swap {ex.name} for {h.exercises[to].name} in {day_name}",
                            "detail": f"{h.exercises[to].name} trains the same muscle with the same movement.",
                            "reason": f"No weight increase on {ex.name} in {s.plateau_days} days.",
                            "rule": "plateau_swap", "exerciseId": eid, "dayId": day_id,
                            "change": {"from": eid, "to": to}})
        weak = [w for w in analysis.weak_points(h, eid, s, today) if w["likely_weak_point"]]
        if weak:
            parts = [f"{w['muscle']}: {'; '.join(w['reasons'])}" for w in weak]
            out.append({"id": _id("note", "weak", eid, last), "created": created, "kind": "note",
                        "title": f"Weak points behind the {ex.name} plateau",
                        "detail": ". ".join(parts) + ".",
                        "reason": "Checked after a plateau: muscles under the weekly set band, or whose other exercises are flat too.",
                        "rule": "weak_point", "exerciseId": eid, "dayId": None, "change": None})
    return out


def note(title: str, detail: str, reason: str, today: Optional[datetime] = None) -> dict:
    today = today or analysis.now_utc()
    if not title.strip():
        raise ValueError("A note needs a title")
    return {"id": _id("free", title, detail, _iso(today)), "created": _iso(today), "kind": "note",
            "title": title.strip(), "detail": detail.strip(), "reason": reason.strip() or "Written in the studio.",
            "rule": "free_text", "exerciseId": None, "dayId": None, "change": None}


def validate(item: dict) -> dict:
    """The same checks the app makes, so nothing published is silently skipped there."""
    for key in ("id", "created", "kind", "title", "detail", "reason", "rule"):
        if not isinstance(item.get(key), str):
            raise ValueError(f"Missing {key}")
    if item["kind"] not in KINDS or not item["id"] or not item["title"]:
        raise ValueError("Unknown kind or empty id/title")
    c = item.get("change") or {}
    if item["kind"] == "target":
        if not item.get("exerciseId") or c.get("unit") not in ("kg", "lb") or not isinstance(c.get("weight"), (int, float)) \
                or not isinstance(c.get("reps"), int) or c["reps"] < 1:
            raise ValueError(f"Target {item['id']} needs an exercise, a weight, a unit and reps")
    if item["kind"] == "swap" and (not item.get("dayId") or not c.get("from") or not c.get("to") or c["from"] == c["to"]):
        raise ValueError(f"Swap {item['id']} needs a day and two different exercises")
    return item


def _read(path: Path) -> list:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, list) else []
    except (OSError, ValueError):
        return []


def published(folder: Path) -> list[dict]:
    return _read(folder / FILE)


def decisions(folder: Path) -> dict[str, dict]:
    return {d["id"]: d for d in _read(folder / DECISIONS) if isinstance(d, dict) and "id" in d}


def publish(folder: Path, items: list[dict]) -> list[dict]:
    """Writes the list atomically. Already-decided items are dropped: the phone keeps its own
    record of them."""
    decided = decisions(folder)
    unique: dict[str, dict] = {}
    for item in items:
        validate(item)
        if item["id"] not in decided:
            unique[item["id"]] = item
    folder.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile("w", dir=folder, delete=False, suffix=".partial") as file:
            name = file.name
            json.dump(list(unique.values()), file, indent=1, ensure_ascii=False)
            file.flush()
            os.fsync(file.fileno())
        os.replace(name, folder / FILE)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)
    return list(unique.values())
