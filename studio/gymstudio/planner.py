"""The program planner (card 8.4): a block of 4–6 weeks for the active program in which
each muscle's weekly sets climb from the bottom of the band (or where it is now, if higher)
to the top, shown before anything is sent. Deloads are only proposed after plateaus: a deload
week when 3 or more of the program's lifts are on plateau, otherwise the single plateaued
lift's own deload target. Nothing reaches the phone unless the owner presses Send.

Weekly sets assume each program day is done `sessions_per_week / days` times a week."""
from __future__ import annotations

import math
from collections import defaultdict
from typing import Optional

from . import analysis
from .data import History

DELOAD_SETS = 0.6          # a deload week keeps 60% of the sets
DELOAD_TRIGGER = 3         # plateaued lifts that call for a whole deload week


def _program(h: History) -> Optional[dict]:
    return next((p for p in h.programs.values() if p["isActive"]), None)


def weekly_sets(h: History, items: list[dict], per_week: float) -> dict[str, float]:
    """Fractional hard sets per muscle a week (rulebook §6) from day items' target sets."""
    out: dict[str, float] = defaultdict(float)
    for item in items:
        ex = h.exercises.get(item["exerciseId"])
        if not ex:
            continue
        sets = item["targetSets"] * per_week
        for m in ex.primary_muscles:
            out[m] += sets
        for m in ex.secondary_muscles:
            out[m] += sets * 0.5
    return dict(out)


def ramp(current: float, lo: float, hi: float, weeks: int) -> list[float]:
    """Weekly targets for one muscle: from max(current, lo) up to hi, evenly; a muscle
    already above the band holds where it is."""
    start = max(current, lo)
    end = max(hi, start)
    if weeks == 1:
        return [start]
    return [round(start + (end - start) * k / (weeks - 1), 2) for k in range(weeks)]


def plan(h: History, s: analysis.Settings, weeks: int = 5, today=None) -> dict:
    weeks = min(max(weeks, 4), 6)
    program = _program(h)
    if not program:
        return {"error": "No active program in the backup."}
    items = h.active_day_items()
    days = {i["dayId"] for i in items}
    per_week = (program.get("sessionsPerWeekGoal") or len(days)) / max(len(days), 1)
    lo, hi = s.volume_band
    now = weekly_sets(h, items, per_week)
    targets = {m: ramp(v, lo, hi, weeks) for m, v in now.items()}

    plateaued = []
    for eid in dict.fromkeys(i["exerciseId"] for i in items):
        if eid in h.exercises and analysis.plateau(h, eid, s, today)["status"] == "plateau":
            t = analysis.next_target(h, eid, s, today)
            plateaued.append({"id": eid, "name": h.exercises[eid].name, "target": t})
    deload_week = len(plateaued) >= DELOAD_TRIGGER

    plan_weeks = []
    for k in range(weeks):
        week_items = []
        for item in items:
            ex = h.exercises.get(item["exerciseId"])
            if not ex:
                continue
            # Each exercise follows its first primary muscle's ramp.
            m = ex.primary_muscles[0] if ex.primary_muscles else None
            factor = targets[m][k] / now[m] if m and now.get(m) else 1.0
            sets = max(1, round(item["targetSets"] * factor))
            if deload_week and k == 0:
                sets = max(1, math.floor(item["targetSets"] * DELOAD_SETS))
            week_items.append({**item, "name": ex.name, "plannedSets": sets,
                               "day": h.program_days[item["dayId"]]["name"]})
        achieved = weekly_sets(h, [{**i, "targetSets": i["plannedSets"]} for i in week_items], per_week)
        plan_weeks.append({"week": k + 1, "deload": deload_week and k == 0, "items": week_items,
                           "muscles": {m: round(v, 1) for m, v in sorted(achieved.items())},
                           "balance": _ratios(h, week_items, per_week)})
    return {"program": program["name"], "per_week": round(per_week, 2), "band": [lo, hi], "weeks": plan_weeks,
            "now": {m: round(v, 1) for m, v in sorted(now.items())}, "plateaued": plateaued,
            "deload_week": deload_week,
            "deload_reason": (f"{len(plateaued)} of the program's lifts are on plateau: week 1 is a deload "
                              f"({int(DELOAD_SETS * 100)}% of sets)") if deload_week else None}


def _ratios(h: History, items: list[dict], per_week: float) -> dict:
    push = pull = upper = lower = 0.0
    for i in items:
        ex = h.exercises[i["exerciseId"]]
        sets = i["plannedSets"] * per_week
        if ex.movement_pattern in analysis.PUSH_PULL["push"]:
            push += sets
        if ex.movement_pattern in analysis.PUSH_PULL["pull"]:
            pull += sets
        if ex.body_region == "upper":
            upper += sets
        if ex.body_region == "lower":
            lower += sets
    return {"push_pull": round(push / pull, 2) if pull else None, "upper_lower": round(upper / lower, 2) if lower else None}


def notes(p: dict, chosen_weeks: list[int], created: str) -> list[dict]:
    """The chosen weeks as note suggestions: the plan to read on the phone, nothing applied."""
    from .suggestions import _id
    out = []
    for w in p["weeks"]:
        if w["week"] not in chosen_weeks:
            continue
        by_day: dict[str, list[str]] = defaultdict(list)
        for i in w["items"]:
            by_day[i["day"]].append(f"{i['name']} {i['plannedSets']} sets")
        detail = " · ".join(f"{day}: {', '.join(lines)}" for day, lines in by_day.items())
        title = f"Plan week {w['week']}" + (" (deload)" if w["deload"] else "")
        out.append({"id": _id("plan", p["program"], str(w["week"]), detail), "created": created, "kind": "note",
                    "title": title, "detail": detail,
                    "reason": p["deload_reason"] if w["deload"] else
                              f"Block of {len(p['weeks'])} weeks: sets per muscle climb toward {p['band'][1]:g} a week.",
                    "rule": "planner", "exerciseId": None, "dayId": None, "change": None})
    return out
