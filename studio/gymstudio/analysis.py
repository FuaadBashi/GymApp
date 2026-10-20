"""The studio's analyses. Every function takes the loaded History and settings and returns
plain data (dicts, lists, numbers) for the dashboards, the Lab and the AI.

Thresholds live in Settings so they can be changed from the interface. Defaults follow
docs/STUDIO_PLAN.md section 7 and docs/ANALYTICS_RESEARCH.md.
"""
from __future__ import annotations

import math
import statistics
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

from . import rulebook, stats
from .data import History, Session

DAY = timedelta(days=1)


@dataclass
class Settings:
    plateau_days: int = 21                 # "3 weeks with no increase in weight"
    volume_band: tuple[float, float] = (10.0, 20.0)   # fractional sets per muscle per week
    break_days: int = 21                   # a gap this long counts as a break
    progress_window_days: int = 90         # window for the progress rate
    deload_fraction: float = 0.10          # deload size suggested on a plateau
    default_rep_range: tuple[int, int] = (8, 12)
    week_starts_monday: bool = False

    def to_dict(self) -> dict:
        return asdict(self)


# Basics


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def local_midnight(day) -> datetime:
    """Midnight of a calendar date in the Mac's time zone, with that date's own UTC offset,
    so boundaries stay at midnight across clock changes."""
    return datetime.combine(day, datetime.min.time()).astimezone()


def week_start(d: datetime, monday: bool) -> datetime:
    local = d.astimezone()
    offset = local.weekday() if monday else (local.weekday() + 1) % 7
    return local_midnight(local.date() - timedelta(days=offset))


def per_workout(h: History, exercise_id: str) -> list[tuple[str, datetime, list]]:
    return stats._merged(h.sessions_for(exercise_id))


def top_load(sets: list, load_mode: str) -> Optional[float]:
    """The heaviest working or failed set's load in kg (reps for reps-only exercises).
    For assisted exercises a smaller assistance is heavier, which the signed kg already says."""
    counted = [s for s in sets if s.type in ("working", "failed") and s.reps > 0]
    if not counted:
        return None
    if load_mode == "repsOnly":
        return float(max(s.reps for s in counted))
    return max(s.kg for s in counted)


def slope_per_30_days(points: list[tuple[datetime, float]], min_points: int = 4, min_span_days: int = 30) -> Optional[float]:
    """Least-squares slope, in units per 30 days. A trend needs enough sessions spread over
    enough time: three sessions in one week would otherwise extrapolate wildly."""
    if len(points) < min_points or (points[-1][0] - points[0][0]).days < min_span_days:
        return None
    t0 = points[0][0]
    xs = [(d - t0).total_seconds() / 86400 for d, _ in points]
    ys = [v for _, v in points]
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx * 30


# Plateaus


def plateau(h: History, exercise_id: str, s: Settings, today: Optional[datetime] = None) -> dict:
    """Plateau as defined for this studio: three weeks of training with no increase in
    weight. Each session's top working weight is compared with the session before it; if
    none of the sessions in the last `plateau_days` went up, and training was continuous
    into that window (no break), it is a plateau. Sessions after a break that are still
    below the old best are "rebuilding", not a plateau."""
    today = today or now_utc()
    ex = h.exercises[exercise_id]
    rows = [(d, top_load(sets, ex.load_mode)) for _, d, sets in per_workout(h, exercise_id)]
    rows = [(d, v) for d, v in rows if v is not None and d <= today]
    start = today - timedelta(days=s.plateau_days)
    recent = [v for d, v in rows if d >= start]
    earlier = [(d, v) for d, v in rows if d < start]
    baseline = earlier[-1][1] if earlier else None
    last_increase = None
    for (d0, v0), (d1, v1) in zip(rows, rows[1:]):
        if v1 > v0 + 1e-9:
            last_increase = d1
    continuous = bool(earlier) and (start - earlier[-1][0]).days <= s.break_days
    if len(recent) < 2:
        status = "not enough data"
    elif last_increase is not None and last_increase >= start:
        status = "progressing"
    elif not continuous:
        status = "rebuilding"      # back after a break: below the old best is expected
    else:
        status = "plateau"
    return {
        "status": status,
        "sessions_in_window": len(recent),
        "best_recent": max(recent) if recent else None,
        "baseline": baseline,
        "last_increase": last_increase.isoformat() if last_increase else None,
        "days_since_increase": (today - last_increase).days if last_increase else None,
        "all_time_top": max((v for _, v in rows), default=None),
    }


def weak_points(h: History, exercise_id: str, s: Settings, today: Optional[datetime] = None) -> list[dict]:
    """After a plateau: the plateaued lift's muscles, how much weekly work each has had,
    and how the other exercises for those muscles are trending. A muscle under the volume
    band, or whose other exercises are also flat, is the likely weak point."""
    today = today or now_utc()
    ex = h.exercises[exercise_id]
    since = today - timedelta(days=28)
    recent_sessions = [x for w in h.workouts.values() if w.started_at >= since for x in w.sessions]
    weekly = {m: v / 4 for m, v in stats.hard_sets_per_muscle(h, recent_sessions).items()}
    out = []
    for muscle in ex.primary_muscles + ex.secondary_muscles:
        others = []
        for oid, other in h.exercises.items():
            if oid == exercise_id or muscle not in other.primary_muscles:
                continue
            p = plateau(h, oid, s, today)
            if p["sessions_in_window"]:
                others.append({"exercise_id": oid, "name": other.name, "status": p["status"]})
        sets = round(weekly.get(muscle, 0.0), 1)
        flat = [o for o in others if o["status"] == "plateau"]
        reasons = []
        if sets < s.volume_band[0]:
            reasons.append(f"{sets} sets a week, under the {s.volume_band[0]:g}–{s.volume_band[1]:g} band")
        if others and len(flat) == len(others):
            reasons.append("every other exercise for it is flat too")
        out.append({"muscle": muscle, "primary": muscle in ex.primary_muscles, "weekly_sets": sets,
                    "other_exercises": others, "likely_weak_point": bool(reasons), "reasons": reasons})
    return sorted(out, key=lambda r: (not r["likely_weak_point"], r["weekly_sets"]))


# Progress, breaks, increments


def progress_rate(h: History, exercise_id: str, s: Settings, today: Optional[datetime] = None) -> dict:
    today = today or now_utc()
    pts = [(p.date, p.best_e1rm) for p in stats.points(h, exercise_id) if p.best_e1rm]
    window = [(d, v) for d, v in pts if d >= today - timedelta(days=s.progress_window_days)]
    best_period = worst_period = None
    # Rolling 90-day slopes across the whole history, for best and worst stretches.
    slopes = []
    for i, (d, _) in enumerate(pts):
        chunk = [(dd, vv) for dd, vv in pts if d <= dd < d + timedelta(days=90)]
        sl = slope_per_30_days(chunk)
        if sl is not None and len(chunk) >= 4:
            slopes.append((sl, d))
    if slopes:
        best = max(slopes)
        worst = min(slopes)
        best_period = {"from": best[1].date().isoformat(), "kg_per_month": round(best[0], 2)}
        worst_period = {"from": worst[1].date().isoformat(), "kg_per_month": round(worst[0], 2)}
    rate = slope_per_30_days(window)
    return {"kg_e1rm_per_month": round(rate, 2) if rate is not None else None,
            "window_days": s.progress_window_days, "best_90_days": best_period, "worst_90_days": worst_period}


def breaks(h: History, s: Settings) -> list[dict]:
    """Gaps of at least `break_days` between workouts."""
    dates = [w.started_at for w in h.workouts.values()]
    out = []
    for a, b in zip(dates, dates[1:]):
        if (b - a).days >= s.break_days:
            out.append({"from": a.isoformat(), "to": b.isoformat(), "days": (b - a).days})
    return out


def detraining(h: History, exercise_id: str, s: Settings) -> list[dict]:
    """For each break: best e1RM in the 4 weeks before, first session after, and how many
    sessions it took to get back to the level before."""
    pts = [(p.date, p.best_e1rm) for p in stats.points(h, exercise_id) if p.best_e1rm]
    out = []
    for br in breaks(h, s):
        start, end = datetime.fromisoformat(br["from"]), datetime.fromisoformat(br["to"])
        before = [v for d, v in pts if start - timedelta(days=28) <= d <= start]
        after = [(d, v) for d, v in pts if d >= end]
        if not before or not after:
            continue
        level = max(before)
        back = next((i + 1 for i, (_, v) in enumerate(after) if v >= level - 1e-9), None)
        out.append({"break_days": br["days"], "from": br["from"][:10], "e1rm_before": round(level, 1),
                    "e1rm_first_back": round(after[0][1], 1),
                    "loss_pct": round((1 - after[0][1] / level) * 100, 1),
                    "sessions_to_recover": back})
    return out


def increment(h: History, exercise_id: str) -> dict:
    """The real load step this exercise allows, learnt from loads used (as entered, in their
    own unit): the most common gap between neighbouring distinct loads."""
    loads: dict[str, set] = defaultdict(set)
    for _, _, sets in per_workout(h, exercise_id):
        for x in sets:
            if x.load_hundredths is not None and x.type != "warmUp":
                loads[x.unit].add(x.load_hundredths)
    if not loads:
        return {"unit": None, "step": None, "confidence": 0}
    unit = max(loads, key=lambda u: len(loads[u]))
    values = sorted(loads[unit])
    gaps = Counter(b - a for a, b in zip(values, values[1:]) if 0 < b - a <= 2000)
    if not gaps:
        return {"unit": unit, "step": None, "confidence": 0}
    # The most common gap; a tie goes to the smaller gap, as in the app (TrainingMath.step).
    step, count = min(gaps.items(), key=lambda g: (-g[1], g[0]))
    return {"unit": unit, "step": step / 100, "confidence": round(count / sum(gaps.values()), 2),
            "loads_seen": len(values)}


# Next session (default rule until the rule lab proves another)


def rep_range_for(h: History, exercise_id: str, s: Settings) -> tuple[int, int]:
    for item in h.active_day_items():
        if item["exerciseId"] == exercise_id:
            return item["repMin"], item["repMax"]
    return s.default_rep_range


EASY_RESERVE = 2


def next_target(h: History, exercise_id: str, s: Settings, today: Optional[datetime] = None) -> Optional[dict]:
    """Double progression (Plotkin 2022: reps and load progress muscle similarly): stay at
    the weight until every working set reaches the top of the range, then add one learnt
    increment and return to the bottom. On a plateau, suggest a deload or a swap instead."""
    ex = h.exercises[exercise_id]
    sessions = per_workout(h, exercise_id)
    if not sessions or ex.load_mode == "repsOnly":
        return None
    _, last_date, sets = sessions[-1]
    working = [x for x in sets if x.type in ("working", "failed") and x.reps > 0]
    if not working:
        return None
    top = max(x.kg for x in working)
    at_top = [x for x in working if abs(x.kg - top) < 1e-6]
    lo, hi = rep_range_for(h, exercise_id, s)
    inc = increment(h, exercise_id)
    step_kg = rulebook.to_kg(int((inc["step"] or 2.5) * 100), inc["unit"] or "kg")
    p = plateau(h, exercise_id, s, today)
    entered = at_top[0]
    def as_entered(kg: float) -> float:
        """Back to the unit the lift is entered in, keeping two decimals like the app."""
        value = kg if entered.unit == "kg" else kg / rulebook.KG_PER_LB
        return round(value, 2)
    if p["status"] == "plateau":
        return {"kind": "plateau", "weight": as_entered(top * (1 - s.deload_fraction)), "unit": entered.unit,
                "reps": f"{lo}–{hi}",
                "reason": f"No weight increase in {s.plateau_days} days. Deload {int(s.deload_fraction*100)}% and rebuild, "
                          f"or swap to a close variant; see the weak-point check.",
                "last": [f"{x.kg:g}×{x.reps}" for x in working]}
    # Rulebook §13 rule 4: every top set logged with 2+ reps in reserve moves twice as fast.
    reserves = [x.reps_in_reserve for x in at_top]
    easy = all(r is not None for r in reserves) and min(reserves) >= EASY_RESERVE
    if all(x.reps >= hi for x in at_top):
        return {"kind": "add weight", "weight": as_entered(top + step_kg * (2 if easy else 1)), "unit": entered.unit, "reps": f"{lo}",
                "reason": f"Every set at {as_entered(top):g} {entered.unit} reached {hi} reps; add one step "
                          f"({inc['step'] or 2.5:g} {inc['unit'] or 'kg'}) and go back to {lo}.",
                "last": [f"{x.kg:g}×{x.reps}" for x in working]}
    lowest = min(x.reps for x in at_top)
    return {"kind": "add reps", "weight": as_entered(top), "unit": entered.unit, "reps": f"{min(lowest + (2 if easy else 1), hi)}+",
            "reason": f"Stay at {as_entered(top):g} {entered.unit} and beat the lowest set ({lowest} reps) until every set reaches {hi}.",
            "last": [f"{x.kg:g}×{x.reps}" for x in working]}


# 1RM formula lab


def formula_consistency(h: History, exercise_ids: Optional[list[str]] = None, near_failure_rir: int = 1) -> dict:
    """Internal consistency, as in Marzagao (2026): estimates from different weight × rep
    sets of the same lift in the same session should agree. Lower spread is better.
    Without logged RIR every working set is used, which mixes in sets far from failure;
    once RIR is logged only sets at or below `near_failure_rir` are used."""
    formulas = {"epley": rulebook.e1rm_epley, "brzycki": rulebook.e1rm_brzycki, "marzagao_2026": rulebook.e1rm_marzagao}
    spreads = {k: [] for k in formulas}
    used = 0
    with_rir = 0
    for eid, ex in h.exercises.items():
        if exercise_ids and eid not in exercise_ids:
            continue
        if ex.load_mode in ("bodyweightPlus", "repsOnly"):
            continue
        for _, _, sets in per_workout(h, eid):
            cand = [x for x in sets if x.type in ("working", "failed") and 1 <= x.reps <= 12 and x.kg > 0]
            rir = [x for x in cand if x.reps_in_reserve is not None and x.reps_in_reserve <= near_failure_rir]
            if len(rir) >= 2:
                cand, with_rir = rir, with_rir + 1
            if len({x.reps for x in cand}) < 2:
                continue
            used += 1
            for name, f in formulas.items():
                est = [f(x.kg, x.reps) for x in cand]
                spreads[name].append(statistics.pstdev(est) / statistics.fmean(est))
    result = {name: round(statistics.fmean(v) * 100, 2) if v else None for name, v in spreads.items()}
    best = min((k for k in result if result[k] is not None), key=lambda k: result[k], default=None)
    return {"mean_spread_pct": result, "sessions_compared": used, "sessions_with_rir": with_rir, "most_consistent": best,
            "caveat": None if with_rir else "No RIR in the history yet: sets not taken near failure blur this comparison."}


# Volume, balance, history


def weekly_muscle_sets(h: History, s: Settings, weeks: int = 12, today: Optional[datetime] = None) -> dict:
    today = today or now_utc()
    current = week_start(today, s.week_starts_monday)
    starts = [current - timedelta(weeks=i) for i in reversed(range(weeks))]
    by_week: dict[str, list[Session]] = defaultdict(list)
    for w in h.workouts.values():
        ws = week_start(w.started_at, s.week_starts_monday)
        if ws >= starts[0]:
            by_week[ws.date().isoformat()].extend(w.sessions)
    series = {st.date().isoformat(): stats.hard_sets_per_muscle(h, by_week.get(st.date().isoformat(), [])) for st in starts}
    muscles = sorted({m for v in series.values() for m in v})
    return {"weeks": [st.date().isoformat() for st in starts], "band": list(s.volume_band),
            "muscles": {m: [round(series[w].get(m, 0.0), 1) for w in series] for m in muscles}}


PUSH_PULL = {"push": {"horizontalPush", "inclinePush", "verticalPush", "chestFly", "lateralRaise", "frontRaise", "tricepsExtension", "dip"},
             "pull": {"horizontalPull", "verticalPull", "rearDelt", "shrug", "pullover", "bicepsCurl"}}


def balance(h: History, s: Settings, days: int = 28, today: Optional[datetime] = None) -> dict:
    """Hard-set ratios over recent weeks: push vs pull, upper vs lower, quads vs hamstrings,
    chest vs back. 1.0 is even."""
    today = today or now_utc()
    sessions = [x for w in h.workouts.values() if w.started_at >= today - timedelta(days=days) for x in w.sessions]
    m = stats.hard_sets_per_muscle(h, sessions)
    pp = Counter()
    region = Counter()
    for x in sessions:
        ex = h.exercises.get(x.exercise_id)
        if not ex:
            continue
        hard = sum(1 for y in x.sets if rulebook.is_hard_set(y.type))
        for side, pats in PUSH_PULL.items():
            if ex.movement_pattern in pats:
                pp[side] += hard
        region[ex.body_region] += hard
    def ratio(a, b):
        return round(a / b, 2) if b else None
    return {"days": days,
            "push_pull": {"push": pp["push"], "pull": pp["pull"], "ratio": ratio(pp["push"], pp["pull"])},
            "upper_lower": {"upper": region["upper"], "lower": region["lower"], "ratio": ratio(region["upper"], region["lower"])},
            "quads_hamstrings": {"ratio": ratio(m.get("quadriceps", 0), m.get("hamstrings", 0))},
            "chest_back": {"ratio": ratio(m.get("chest", 0), m.get("lats", 0) + m.get("middleBack", 0))}}


def history_rows(h: History) -> list[dict]:
    rows = []
    for w in reversed(list(h.workouts.values())):
        hard = sum(1 for x in w.sessions for y in x.sets if rulebook.is_hard_set(y.type))
        rows.append({"id": w.id, "date": w.started_at.isoformat(), "title": w.title,
                     "minutes": round(w.duration_s / 60), "sets": hard,
                     "volume_kg": round(stats.workout_volume_kg(h, w.id)),
                     "exercises": [h.exercises[x.exercise_id].name for x in w.sessions if x.exercise_id in h.exercises]})
    return rows


def consistency(h: History, s: Settings, weeks: int = 52, today: Optional[datetime] = None) -> dict:
    today = today or now_utc()
    current = week_start(today, s.week_starts_monday)
    counts = Counter(week_start(w.started_at, s.week_starts_monday).date().isoformat() for w in h.workouts.values())
    series = [(current - timedelta(weeks=i)).date().isoformat() for i in reversed(range(weeks))]
    streak = 0
    for wk in reversed(series):
        if counts.get(wk):
            streak += 1
        elif wk != series[-1]:
            break
    return {"weeks": series, "sessions": [counts.get(wk, 0) for wk in series], "current_streak_weeks": streak,
            "average_per_week": round(statistics.fmean(counts.get(wk, 0) for wk in series), 2)}


def exercise_index(h: History, s: Settings, today: Optional[datetime] = None) -> list[dict]:
    today = today or now_utc()
    out = []
    for eid, ex in h.exercises.items():
        sessions = per_workout(h, eid)
        if not sessions:
            continue
        r = stats.records(h, eid)
        out.append({"id": eid, "name": ex.name, "equipment": ex.equipment, "sessions": len(sessions),
                    "last_done": sessions[-1][1].isoformat(),
                    "best_e1rm": round(r.best_e1rm.value_kg, 1) if r.best_e1rm else None,
                    "plateau": plateau(h, eid, s, today)["status"],
                    "in_program": any(i["exerciseId"] == eid for i in h.active_day_items())})
    return sorted(out, key=lambda r: r["last_done"], reverse=True)


def exercise_detail(h: History, eid: str, s: Settings, today: Optional[datetime] = None) -> dict:
    ex = h.exercises[eid]
    r = stats.records(h, eid)
    mark = lambda m: None if m is None else {"kg": round(m.value_kg, 2), "reps": m.reps, "date": m.date.isoformat(), "workout_id": m.workout_id}
    sessions = [{"date": d.isoformat(), "workout_id": wid,
                 "sets": [{"kg": round(x.kg, 2), "reps": x.reps, "type": x.type, "rir": x.reps_in_reserve} for x in sets]}
                for wid, d, sets in per_workout(h, eid)]
    return {"id": eid, "name": ex.name, "equipment": ex.equipment, "load_mode": ex.load_mode,
            "muscles": {"primary": ex.primary_muscles, "secondary": ex.secondary_muscles},
            "points": [{"date": p.date.isoformat(), "e1rm": p.best_e1rm, "heaviest": p.heaviest_kg, "volume": p.volume_kg,
                        "workout_id": p.workout_id} for p in stats.points(h, eid)],
            "records": {"heaviest": mark(r.heaviest), "best_e1rm": mark(r.best_e1rm), "best_volume": mark(r.best_volume),
                        "rep_records": [mark(m) for m in r.rep_records]},
            "plateau": plateau(h, eid, s, today), "weak_points": weak_points(h, eid, s, today),
            "progress": progress_rate(h, eid, s, today), "detraining": detraining(h, eid, s),
            "increment": increment(h, eid), "next": next_target(h, eid, s, today),
            "formulas": formula_consistency(h, [eid]), "sessions": sessions[::-1]}


def overview(h: History, s: Settings, today: Optional[datetime] = None) -> dict:
    today = today or now_utc()
    this_week = week_start(today, s.week_starts_monday)
    week_workouts = [w for w in h.workouts.values() if w.started_at >= this_week]
    program = [i["exerciseId"] for i in h.active_day_items()]
    targets = []
    for eid in dict.fromkeys(program):
        if eid in h.exercises:
            t = next_target(h, eid, s, today)
            if t:
                targets.append({"id": eid, "name": h.exercises[eid].name, **t})
    plateaus = [r for r in exercise_index(h, s, today) if r["plateau"] == "plateau"]
    sets = sum(len(x.sets) for w in h.workouts.values() for x in w.sessions)
    return {"totals": {"workouts": len(h.workouts), "sets": sets,
                       "since": next(iter(h.workouts.values())).started_at.date().isoformat() if h.workouts else None},
            "this_week": {"workouts": len(week_workouts), "volume_kg": round(sum(stats.workout_volume_kg(h, w.id) for w in week_workouts))},
            "consistency": consistency(h, s, 26, today), "plateaus": plateaus, "next_targets": targets,
            "balance": balance(h, s, 28, today), "breaks": breaks(h, s)[-5:],
            "last_workout": history_rows(h)[0] if h.workouts else None,
            "steps": steps_summary(h, today), "body_weight": h.body_weights[-1] if h.body_weights else None}


def steps_summary(h: History, today: Optional[datetime] = None, days: int = 30) -> Optional[dict]:
    """Daily steps from Apple Health over the last `days` days, as the app's Progress card."""
    today = today or now_utc()
    end = today.astimezone().date()
    start = (end - timedelta(days=days - 1)).isoformat()
    rows = [(d, n) for d, n in h.steps if start <= d <= end.isoformat()]
    if not rows:
        return None
    return {"days": [{"date": d, "steps": n} for d, n in rows],
            "daily_average": round(sum(n for _, n in rows) / len(rows))}
