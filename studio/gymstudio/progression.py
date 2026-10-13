"""Causal, observational replay of progression rules over finished workouts.

Targets use only exposures available at the decision time. Later sessions evaluate
predictions; they never teach an earlier increment or supply an earlier rep range.
This cannot estimate the gains a lifter would have made under an untried programme.
"""
from __future__ import annotations

import math
from collections import Counter
from datetime import timedelta

from . import analysis, rulebook
from .data import History

RULES = {
    "double_progression": "Double progression + time-based plateau",
    "double_stall_2": "Double progression + 2 stalled exposures",
    "double_stall_3": "Double progression + 3 stalled exposures",
    "linear_3_misses": "Linear progression + 3 missed exposures",
    "rir_double": "Double progression at 2 reps left",
}


def validate_settings(s: analysis.Settings) -> None:
    for name in ("plateau_days", "break_days", "progress_window_days"):
        v = getattr(s, name)
        if isinstance(v, bool) or not isinstance(v, int) or not 1 <= v <= 3650:
            raise ValueError(f"{name} must be a whole number from 1 to 3650")
    if not isinstance(s.week_starts_monday, bool):
        raise ValueError("week_starts_monday must be true or false")
    if not isinstance(s.deload_fraction, (float, int)) or isinstance(s.deload_fraction, bool) or not 0 < s.deload_fraction < 1:
        raise ValueError("Deload fraction must be between 0 and 1")
    for name in ("volume_band", "default_rep_range"):
        values = getattr(s, name)
        if not isinstance(values, (tuple, list)) or len(values) != 2 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
            raise ValueError(f"{name} must contain two finite numbers")
        if values[0] < 0 or values[1] < values[0]:
            raise ValueError(f"{name} must be ordered from lower to upper")
    if any(not isinstance(v, int) or not 1 <= v <= 50 for v in s.default_rep_range):
        raise ValueError("Rep bounds must be whole numbers from 1 to 50")


def _exposures(h: History, eid: str, s: analysis.Settings) -> list[dict]:
    out = []
    for wid, date, sets in analysis.per_workout(h, eid):
        valid = [x for x in sets if x.type in ("working", "failed") and x.load_hundredths is not None and x.reps >= 0]
        if not valid:
            continue
        top = max(x.kg for x in valid)
        top_sets = [x for x in valid if abs(x.kg - top) < .00001]
        snapshots = [x for x in h.workouts[wid].sessions if x.exercise_id == eid]
        ranges = {(x.rep_min, x.rep_max) for x in snapshots if x.rep_min is not None and x.rep_max is not None}
        captured = len(ranges) == 1 and all(x.rep_min is not None and x.rep_max is not None for x in snapshots)
        lo, hi = next(iter(ranges)) if captured else s.default_rep_range
        out.append(dict(workout_id=wid, date=date, sets=valid, top=top, top_sets=top_sets,
                        lo=lo, hi=hi, range_source="workout snapshot" if captured else "configured fallback"))
    return out


def _step(prefix: list[dict], unit: str, equipment: str) -> dict:
    loads = sorted({x.load_hundredths for row in prefix for x in row["sets"] if x.unit == unit})
    counts = Counter(b - a for a, b in zip(loads, loads[1:]) if 0 < b - a <= 2000)
    if counts:
        size, count = sorted(counts.items(), key=lambda x: (-x[1], x[0]))[0]
        return {"size": size / 100, "unit": unit, "source": "earlier observed loads",
                "confidence": round(count / sum(counts.values()), 3), "loads_seen": len(loads)}
    default = 5 if unit == "lb" else {"dumbbell": 2, "kettlebell": 4, "band": 1, "bodyweight": 1, "other": 1}.get(equipment, 2.5)
    return {"size": default, "unit": unit, "source": "equipment fallback", "confidence": 0, "loads_seen": len(loads)}


def _recent_block(prefix: list[dict], s: analysis.Settings) -> list[dict]:
    start = 0
    for i in range(1, len(prefix)):
        if prefix[i]["date"] - prefix[i - 1]["date"] >= timedelta(days=s.break_days):
            start = i
    return prefix[start:]


def _target(prefix: list[dict], ex, rule: str, s: analysis.Settings) -> dict | None:
    row = prefix[-1]
    top_sets = row["top_sets"]
    entered = top_sets[0]
    unit = entered.unit
    weight = entered.load_hundredths / 100
    step = _step(prefix, unit, ex.equipment)
    block = _recent_block(prefix, s)
    lo, hi = row["lo"], row["hi"]
    minimum = min(x.reps for x in top_sets)
    failed = any(x.type == "failed" for x in top_sets)
    out = dict(weight=weight, unit=unit, reps=lo, sets=len(top_sets), step=step,
               rep_range=[lo, hi], range_source=row["range_source"], deload=False, rir=None)
    if rule == "rir_double":
        if any(x.reps_in_reserve is None for x in top_sets):
            return None
        out["rir"] = 2
    if len(prefix) > 1 and len(block) == 1:
        return {**out, "kind": "rebuild", "reason": "First exposure after a break: repeat and establish a new baseline before increasing."}
    changes = [b["top"] - a["top"] for a, b in zip(block, block[1:])]
    deload = False
    if rule == "double_progression":
        last_increase = block[0]["date"]
        for a, b in zip(block, block[1:]):
            if b["top"] > a["top"] + 1e-6:
                last_increase = b["date"]
        deload = len(block) >= 3 and row["date"] - last_increase >= timedelta(days=s.plateau_days)
        reason = f"No weight increase for {s.plateau_days} days of continuous exercise exposures."
    elif rule in ("double_stall_2", "double_stall_3"):
        count = int(rule[-1])
        deload = len(changes) >= count and all(v <= 1e-6 for v in changes[-count:])
        reason = f"No weight increase across {count} consecutive exposure comparisons."
    else:
        def miss(r):
            return any(x.type == "failed" or x.reps < r["lo"] for x in r["top_sets"])
        deload = len(block) >= 3 and all(miss(r) for r in block[-3:])
        reason = "Three consecutive exposures missed the lower rep bound."
    if deload:
        steps = max(1, math.floor(abs(weight) * s.deload_fraction / step["size"] + .5))
        target = round(weight - steps * step["size"], 2)
        if weight > 0 and target <= 0:
            return {**out, "kind": "hold", "reason": "No lower positive weight fits the estimated step; repeat rather than invent an available load."}
        return {**out, "kind": "deload", "deload": True, "weight": target,
                "reason": reason + f" Reduce difficulty by about {s.deload_fraction:.0%}, rounded to the estimated load step."}
    complete = minimum >= (lo if rule == "linear_3_misses" else hi) and not failed
    if rule == "rir_double":
        complete = complete and all(x.reps_in_reserve >= 2 for x in top_sets)
    if complete:
        return {**out, "kind": "add weight", "weight": round(weight + step["size"], 2),
                "reason": "Every top-weight set met the rule's rep and effort gate; add one estimated step."}
    reps = lo if rule == "linear_3_misses" else max(lo, min(hi, minimum + 1))
    return {**out, "kind": "add reps", "reps": reps,
            "reason": "Repeat the top weight and complete the next rep target before adding weight."}


def _observed_plateau(rows: list[dict], i: int, days: int, break_days: int) -> bool | None:
    row = rows[i]
    end = row["date"] + timedelta(days=days)
    future = [r for r in rows[i + 1:] if r["date"] <= end]
    if rows[-1]["date"] < end or len(future) < 2:
        return None
    segment = [row] + future
    if any(b["date"] - a["date"] >= timedelta(days=break_days) for a, b in zip(segment, segment[1:])):
        return None
    return not any(r["top"] > row["top"] + 1e-6 for r in future)


def _next_result(target: dict | None, current: dict, following: dict | None, s: analysis.Settings) -> str:
    if target is None:
        return "no RIR data"
    if following is None or following["date"] - current["date"] >= timedelta(days=s.break_days):
        return "no continuous follow-up"
    kg = rulebook.to_kg(round(target["weight"] * 100), target["unit"])
    attempted = [x for x in following["sets"] if abs(x.kg - kg) < .005]
    if not attempted:
        return "not attempted"
    if target["rir"] is not None and any(x.reps_in_reserve is None for x in attempted):
        return "follow-up RIR missing"
    met = len(attempted) >= target["sets"] and all(x.reps >= target["reps"] and x.type != "failed" for x in attempted)
    if target["rir"] is not None:
        met = met and all(x.reps_in_reserve >= target["rir"] for x in attempted)
    return "met" if met else "missed"


def _metrics(trials: list[dict]) -> dict:
    scored = [r for r in trials if r["observed_plateau"] is not None and r["target"] is not None]
    tp = sum(r["target"]["deload"] and r["observed_plateau"] for r in scored)
    fp = sum(r["target"]["deload"] and not r["observed_plateau"] for r in scored)
    fn = sum(not r["target"]["deload"] and r["observed_plateau"] for r in scored)
    tn = len(scored) - tp - fp - fn
    divide = lambda a, b: round(a / b, 4) if b else None
    recall = divide(tp, tp + fn)
    specificity = divide(tn, tn + fp)
    met = sum(r["next_result"] == "met" for r in trials)
    missed = sum(r["next_result"] == "missed" for r in trials)
    raised = [r for r in trials if r["target"] and r["target"]["kind"] == "add weight"]
    raised_misses = sum(r["next_result"] == "missed" for r in raised)
    raised_scored = sum(r["next_result"] in ("met", "missed") for r in raised)
    return dict(predictions=sum(r["target"] is not None for r in trials), abstained=sum(r["target"] is None for r in trials),
                plateau_evaluated=len(scored), true_positive=tp, false_positive=fp, false_negative=fn, true_negative=tn,
                precision=divide(tp, tp + fp), recall=recall,
                balanced_accuracy=round((recall + specificity) / 2, 4) if recall is not None and specificity is not None else None,
                targets_met=met, targets_missed=missed, attempted_target_success=divide(met, met + missed),
                raised_targets_evaluated=raised_scored, raised_targets_missed=raised_misses,
                raised_target_miss_rate=divide(raised_misses, raised_scored))


def backtest(h: History, s: analysis.Settings, exercise_id: str | None = None, outcome_days: int = 21,
             holdout_fraction: float = .3, since=None, until=None) -> dict:
    validate_settings(s)
    if not isinstance(outcome_days, int) or not 7 <= outcome_days <= 180 or not .1 <= holdout_fraction <= .8:
        raise ValueError("Outcome window must be 7–180 days; holdout fraction must be 0.1–0.8")
    if exercise_id is not None and exercise_id not in h.exercises:
        raise KeyError(exercise_id)
    grouped = {rule: [] for rule in RULES}
    included = []
    skipped = []
    for eid, ex in h.exercises.items():
        if exercise_id and eid != exercise_id:
            continue
        if ex.load_mode == "repsOnly":
            skipped.append({"id": eid, "reason": "Reps-only progression is not a weight progression comparison."})
            continue
        rows = _exposures(h, eid, s)
        if until is not None:
            rows = [r for r in rows if r["date"] <= until]
        if not rows:
            continue
        included.append({"id": eid, "name": ex.name, "exposures": len(rows)})
        split = max(1, math.floor(len(rows) * (1 - holdout_fraction)))
        for i, row in enumerate(rows):
            if since is not None and row["date"] < since:
                continue
            observed = _observed_plateau(rows, i, outcome_days, s.break_days)
            for rule in RULES:
                target = _target(rows[:i + 1], ex, rule, s)
                grouped[rule].append(dict(exercise_id=eid, name=ex.name, workout_id=row["workout_id"],
                    date=row["date"].isoformat(), fold="holdout" if i >= split else "earlier",
                    target=target, observed_plateau=observed,
                    next_result=_next_result(target, row, rows[i + 1] if i + 1 < len(rows) else None, s),
                    last=[dict(weight=x.load_hundredths / 100, unit=x.unit, reps=x.reps, type=x.type, rir=x.reps_in_reserve) for x in row["sets"]]))
    rules = []
    for key, rows in grouped.items():
        rows.sort(key=lambda r: (r["date"], r["exercise_id"], r["workout_id"]))
        rules.append(dict(id=key, name=RULES[key], metrics=_metrics(rows), holdout=_metrics([r for r in rows if r["fold"] == "holdout"]), trials=rows))
    return dict(rules=rules, exercises=included, skipped=skipped, recommended_rule=None,
                outcome_days=outcome_days, holdout_fraction=holdout_fraction, settings=s.to_dict(),
                method="Each decision uses the completed session and earlier sessions only. The last fraction of each exercise's exposures is reported separately as holdout.",
                limitations=["Observed plateau means no heavier top working load in the next window, with at least two exposures and sufficient continuous follow-up. It is a descriptive proxy, not a diagnosis.",
                    "A raised target is scored only if that exact load was attempted in the next continuous session. Unattempted loads and missing effort remain unscored.",
                    "Load steps are estimated from earlier logged loads, not verified machine specifications. Historic rep ranges use workout snapshots or the configured fallback, never today's programme.",
                    "Overlapping windows are correlated. Holdout scores are descriptive; changing settings after viewing them tunes to that history.",
                    "Observational replay cannot prove which rule would have caused better gains or whether a deload would have helped. No winning rule is automatically promoted to the phone."])
