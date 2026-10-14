"""Data health (card 8.2): likely typos and oddities in the logged history, each with a
proposed fix where one is likely. Nothing is changed here: ticked fixes are published to
the phone as `fix` suggestions and only applied when accepted there (card 8.3).

A set's load is compared with the same exercise's loads in the five sessions before and the
five after it (median and median absolute deviation, MAD). A load more than 6 MADs from the
median and at least double or at most half of it is flagged, and corrections are tried in
order: a slipped decimal (÷10, ×10), a kg/lb slip, then a dropped or doubled digit; the first
that lands within 1 MAD (at least 5% of the median) is proposed. A light set with no likely
correction is not flagged: logged empty-bar sets and comebacks look like that."""
from __future__ import annotations

import hashlib
import re
import statistics
from collections import defaultdict
from typing import Optional

from . import analysis, rulebook
from .data import History

THRESHOLD = 6.0      # MADs from the median
RATIO = 2.0          # and at least double or at most half the median: typos are big
ACCEPT = 1.0         # a fix must land within this many MADs (at least 5% of the median)
NEIGHBOURS = 5
MAX_REPS = 50
JUMP = 0.60          # session-to-session top-set jump worth a look
JUMP_DAYS = 30       # only between sessions this close (a comeback isn't a jump)
LOADED = ("total", "perHand", "perSide")


def _id(*parts) -> str:
    return hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()[:16]


def _digit_variants(value: float) -> list[float]:
    """Loads one keystroke away: a digit dropped or doubled."""
    text = f"{value:g}"
    out = set()
    for i in range(len(text)):
        if text[i].isdigit():
            out.add(text[:i] + text[i + 1:])
            out.add(text[:i] + text[i] + text[i:])
    values = []
    for t in out:
        try:
            v = float(t)
        except ValueError:
            continue
        if v > 0 and v != value:
            values.append(v)
    return sorted(values)


def _spread(values: list[float]) -> tuple[float, float]:
    median = statistics.median(values)
    mad = statistics.median(abs(v - median) for v in values)
    return median, max(mad, 0.05 * median, 1.0)


def findings(h: History) -> list[dict]:
    out: list[dict] = []
    for eid, ex in h.exercises.items():
        if ex.load_mode not in LOADED:
            continue
        sessions = analysis.per_workout(h, eid)
        tops: list[tuple] = []
        for i, (wid, date, sets) in enumerate(sessions):
            around = sessions[max(0, i - NEIGHBOURS):i] + sessions[i + 1:i + 1 + NEIGHBOURS]
            loads = [x.kg for _, _, ss in around for x in ss if x.type != "warmUp" and x.kg > 0]
            working = [x for x in sets if x.type != "warmUp" and x.load_hundredths]
            for x in working:
                base = {"exercise_id": eid, "exercise": ex.name, "workout_id": wid, "date": date.date().isoformat(),
                        "set_id": x.id, "current": {"weight": x.load_hundredths / 100, "unit": x.unit, "reps": x.reps}}
                if x.reps > MAX_REPS:
                    fix = {"weight": x.load_hundredths / 100, "unit": x.unit, "reps": x.reps // 10} if x.reps // 10 >= 1 else None
                    out.append({**base, "kind": "reps", "fix": fix,
                                "reason": f"{x.reps} reps on a loaded lift; probably {x.reps // 10}."})
                if len(loads) < 4 or x.kg <= 0:
                    continue
                median, mad = _spread(loads)
                ratio = x.kg / median if median else 1
                if abs(x.kg - median) <= THRESHOLD * mad or 1 / RATIO < ratio < RATIO:
                    continue
                entered = x.load_hundredths / 100
                candidates = [(entered / 10, x.unit, "a slipped decimal"), (entered * 10, x.unit, "a slipped decimal"),
                              (entered, "lb" if x.unit == "kg" else "kg", "the wrong unit")]
                candidates += [(v, x.unit, "a mistyped digit") for v in _digit_variants(entered)]
                fix = reason = None
                for value, unit, why in candidates:
                    kg = rulebook.to_kg(round(value * 100), unit)
                    if abs(kg - median) <= max(ACCEPT * mad, 0.05 * median):
                        fix, reason = {"weight": round(value, 2), "unit": unit, "reps": x.reps}, why
                        break
                if fix is None and ratio < 1:
                    continue      # a light set with no likely typo is a warm-up or a comeback, not an error
                out.append({**base, "kind": "load", "fix": fix,
                            "reason": f"{entered:g} {x.unit} is far from this lift's usual {median:g} kg"
                                      + (f"; looks like {reason}." if fix else "; no obvious correction.")})
            top = max((x.kg for x in working if x.type in ("working", "failed")), default=None)
            if top:
                tops.append((wid, date, top))
        # Big jumps between consecutive sessions that the outlier test didn't already explain.
        flagged = {f["workout_id"] for f in out if f["exercise_id"] == eid and f["kind"] == "load"}
        for i, (w1, d1, b) in enumerate(tops):
            # Against the best of the previous three sessions within JUMP_DAYS, so returning to
            # normal after one light day isn't a jump.
            prior = [v for _, d0, v in tops[max(0, i - 3):i] if (d1 - d0).days <= JUMP_DAYS]
            a = max(prior, default=0)
            if a > 0 and (b - a) / a > JUMP and w1 not in flagged:
                out.append({"exercise_id": eid, "exercise": ex.name, "workout_id": w1, "date": d1.date().isoformat(),
                            "set_id": None, "kind": "jump", "fix": None, "current": None,
                            "reason": f"Top set jumped {(b - a) / a * 100:.0f}% from {a:g} kg to {b:g} kg; check it."})
    # Exercises whose names differ only in case or punctuation.
    by_key: dict[str, list] = defaultdict(list)
    for eid, ex in h.exercises.items():
        if not ex.is_archived:
            by_key[re.sub(r"[^a-z0-9]", "", ex.name.lower())].append(ex)
    for group in by_key.values():
        if len(group) > 1 and len({e.name for e in group}) > 1:
            out.append({"exercise_id": group[0].id, "exercise": " / ".join(e.name for e in group), "workout_id": None,
                        "date": None, "set_id": None, "kind": "duplicate", "fix": None, "current": None,
                        "reason": "These exercises differ only in case or punctuation; consider archiving one."})
    for f in out:
        f["id"] = _id(f["kind"], f["set_id"] or f["exercise_id"], f["workout_id"], f["fix"])
    return sorted(out, key=lambda f: (f["fix"] is None, f["date"] or "", f["exercise"]))


def suggestion(finding: dict, created: str) -> dict:
    """A `fix` suggestion for the phone (card 8.3)."""
    fix, cur = finding["fix"], finding["current"]
    return {"id": finding["id"], "created": created, "kind": "fix",
            "title": f"{finding['exercise']}, {finding['date']}: {cur['weight']:g} {cur['unit']} × {cur['reps']} → "
                     f"{fix['weight']:g} {fix['unit']} × {fix['reps']}",
            "detail": "Corrects one logged set. History is corrected, not deleted.",
            "reason": finding["reason"], "rule": "data_health", "exerciseId": finding["exercise_id"], "dayId": None,
            "change": {"setId": finding["set_id"], "weight": fix["weight"], "unit": fix["unit"], "reps": fix["reps"]}}
