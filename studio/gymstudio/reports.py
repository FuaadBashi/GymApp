"""Weekly and monthly reports (card 8.1), for every completed week and month of history.

Each report is built from the same functions as the dashboards, so its figures match the
app's Recaps and Progress. Written three ways: kept in memory for the studio's Reports page,
as Markdown files in <backup folder>/Reports (every figure in plain text, for reading or
handing to an assistant later), and as GymApp-reports.json for the app (card 7.9: the last
26 weeks and 12 months)."""
from __future__ import annotations

import json
import os
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from . import analysis, rulebook, stats
from .data import History

APP_FILE = "GymApp-reports.json"
FOLDER = "Reports"


@dataclass
class Report:
    id: str
    kind: str                  # "week" | "month"
    title: str
    start: datetime            # local midnight, inclusive
    end: datetime              # exclusive
    headline: str = ""
    sections: list[dict] = field(default_factory=list)   # [{title, lines}]
    figures: dict = field(default_factory=dict)

    def app_dict(self) -> dict:
        return {"id": self.id, "kind": self.kind, "title": self.title, "from": self.start.date().isoformat(),
                "to": self.end.date().isoformat(), "headline": self.headline, "sections": self.sections}

    def markdown(self) -> str:
        out = [f"# {self.title}", "", f"{self.start.date().isoformat()} to {(self.end - timedelta(days=1)).date().isoformat()}", "",
               f"**{self.headline}**", ""]
        for section in self.sections:
            out += [f"## {section['title']}", ""] + [f"- {line}" for line in section["lines"]] + [""]
        return "\n".join(out)


def _muscle(name: str) -> str:
    """"middleBack" → "Middle back"."""
    spaced = "".join(" " + c.lower() if c.isupper() else c for c in name)
    return spaced[:1].upper() + spaced[1:]


def _lineage(h: History, day_id: str) -> set[str]:
    """A day and the days it was copied from (ProgramQueries.lineage)."""
    out, current = set(), day_id
    while current and current not in out:
        out.add(current)
        current = (h.program_days.get(current) or {}).get("copiedFromDayId")
    return out


def _kg(v: float) -> str:
    return f"{v:,.1f}".rstrip("0").rstrip(".") + " kg"


def _change(now: float, before: float, unit: str = "") -> str:
    if before == 0:
        return "no comparison"
    d = now - before
    return f"{'+' if d >= 0 else ''}{d:,.0f}{unit} ({'+' if d >= 0 else ''}{d / before * 100:.0f}%)"


def periods(h: History, s: analysis.Settings, today: datetime) -> list[tuple[str, datetime, datetime]]:
    """Every completed week and month from the first workout, oldest first."""
    if not h.workouts:
        return []
    first = next(iter(h.workouts.values())).started_at
    out = []
    week = analysis.week_start(first, s.week_starts_monday)
    now_week = analysis.week_start(today, s.week_starts_monday)
    while week < now_week:
        nxt = analysis.local_midnight(week.date() + timedelta(days=7))
        out.append(("week", week, nxt))
        week = nxt
    month = analysis.local_midnight(first.astimezone().date().replace(day=1))
    this_month = analysis.local_midnight(today.astimezone().date().replace(day=1))
    while month < this_month:
        nxt = analysis.local_midnight((month.date() + timedelta(days=32)).replace(day=1))
        out.append(("month", month, nxt))
        month = nxt
    return out


def _best_events(h: History) -> list[dict]:
    """Every set that was a best when logged (rulebook §5a), in date order."""
    events = []
    for eid, ex in h.exercises.items():
        if ex.load_mode in ("bodyweightPlus", "repsOnly"):
            continue
        history: list[tuple] = []
        for _, date, sets in analysis.per_workout(h, eid):
            for x in sorted(sets, key=lambda x: x.completed_at or date):
                if x.type in ("warmUp", "drop") or x.reps <= 0:
                    continue
                e = rulebook.displayable_e1rm(x.kg, x.reps, ex.load_mode)
                if e is None:
                    continue
                at = x.completed_at or date
                status = rulebook.best_status(e, history, at)
                if status[0] != "none":
                    events.append({"date": at, "exercise_id": eid, "name": ex.name, "e1rm": e, "status": status,
                                   "set": f"{x.kg:g}×{x.reps}"})
                history.append((at, e))
    return sorted(events, key=lambda e: e["date"])


def _totals(h: History, start: datetime, end: datetime) -> dict:
    ws = [w for w in h.workouts.values() if start <= w.started_at < end]
    return {"workouts": len(ws), "seconds": sum(w.duration_s for w in ws),
            "volume_kg": sum(stats.workout_volume_kg(h, w.id) for w in ws),
            "hard_sets": round(sum(stats.session_hard_sets(h, x) for w in ws for x in w.sessions), 1),
            "sessions": [x for w in ws for x in w.sessions], "workout_list": ws}


def build(h: History, s: analysis.Settings, today: Optional[datetime] = None) -> list[Report]:
    today = today or analysis.now_utc()
    events = _best_events(h)
    program = {i["exerciseId"] for i in h.active_day_items()}
    active_days = [d for d, row in h.program_days.items() if h.programs.get(row["programId"], {}).get("isActive")]
    reports: list[Report] = []
    previous: dict[str, dict] = {}
    for kind, start, end in periods(h, s, today):
        t = _totals(h, start, end)
        before = previous.get(kind)
        previous[kind] = t
        if t["workouts"] == 0:
            continue
        if kind == "week":
            monday = start + timedelta(days=(7 - start.weekday()) % 7 if start.weekday() else 0)
            iso = monday.isocalendar()
            rid, title = f"{iso[0]}-W{iso[1]:02d}", f"Week of {start.strftime('%-d %b %Y')}"
        else:
            rid, title = start.strftime("%Y-%m"), start.strftime("%B %Y")
        r = Report(rid, kind, title, start, end)
        weeks = (end - start).days / 7

        hours, minutes = divmod(round(t["seconds"] / 60), 60)
        lines = [f"{t['workouts']} workout{'s' if t['workouts'] != 1 else ''}, {hours} h {minutes} min, "
                 f"{_kg(round(t['volume_kg']))} lifted, {t['hard_sets']} hard sets"]
        if before and before["workouts"]:
            lines.append(f"Against the {kind} before: workouts {_change(t['workouts'], before['workouts'])}, "
                         f"volume {_change(t['volume_kg'], before['volume_kg'], ' kg')}")
        r.sections.append({"title": "Totals", "lines": lines})

        bests = [e for e in events if start <= e["date"] < end]
        by_exercise: dict[str, dict] = {}
        for e in bests:   # keep the strongest best per exercise in the period
            rank = 100 if e["status"][0] == "all_time" else e["status"][1]
            if e["exercise_id"] not in by_exercise or rank > by_exercise[e["exercise_id"]]["rank"] \
                    or (rank == by_exercise[e["exercise_id"]]["rank"] and e["e1rm"] > by_exercise[e["exercise_id"]]["e1rm"]):
                by_exercise[e["exercise_id"]] = {**e, "rank": rank}
        record_lines = []
        for e in sorted(by_exercise.values(), key=lambda e: (-e["rank"], e["name"])):
            st = e["status"]
            label = "all-time best" if st[0] == "all_time" else f"best in {st[1]} month{'s' if st[1] > 1 else ''}"
            record_lines.append(f"{e['name']}: {label}, est. 1RM {_kg(e['e1rm'])} from {e['set']} (beat {_kg(st[-1])})")
        r.sections.append({"title": "Bests", "lines": record_lines or ["No new bests."]})

        muscles = stats.hard_sets_per_muscle(h, t["sessions"])
        lo, hi = s.volume_band
        muscle_lines = []
        for m, sets in sorted(muscles.items(), key=lambda kv: -kv[1]):
            per_week = sets / weeks
            flag = "under the band" if per_week < lo else "over the band" if per_week > hi else "in the band"
            muscle_lines.append(f"{_muscle(m)}: {sets:g} sets ({per_week:.1f} a week, {flag})")
        r.sections.append({"title": f"Sets per muscle (band {lo:g}–{hi:g} a week)", "lines": muscle_lines or ["No hard sets."]})

        plateau_lines = []
        for eid in sorted(program):
            if eid not in h.exercises:
                continue
            p = analysis.plateau(h, eid, s, end)
            if p["status"] in ("plateau", "rebuilding") and p["sessions_in_window"]:
                plateau_lines.append(f"{h.exercises[eid].name}: {p['status']}"
                                     + (f", {p['days_since_increase']} days since an increase" if p["days_since_increase"] else ""))
        r.sections.append({"title": "Plateaus", "lines": plateau_lines or ["None among the program's lifts."]})

        if kind == "week" and active_days:
            done = {w.program_day_id for w in t["workout_list"]}
            skipped = [h.program_days[d]["name"] for d in sorted(active_days, key=lambda d: h.program_days[d]["position"])
                       if not (_lineage(h, d) & done)]
            r.sections.append({"title": "Program days", "lines": [f"Done {len(active_days) - len(skipped)} of {len(active_days)}"
                                                                     + (f"; not done: {', '.join(skipped)}" if skipped else "")]})

        body = []
        weights = [(d, kg) for d, kg in h.body_weights if start.date().isoformat() <= d < end.date().isoformat()]
        if weights:
            body.append(f"Body weight {_kg(weights[-1][1])} on {weights[-1][0]}"
                        + (f", {weights[-1][1] - weights[0][1]:+.1f} kg over the {kind}" if len(weights) > 1 else ""))
        steps = [n for d, n in h.steps if start.date().isoformat() <= d < end.date().isoformat()]
        if steps:
            body.append(f"Steps: {round(sum(steps) / len(steps)):,} a day over {len(steps)} days")
        if body:
            r.sections.append({"title": "Body", "lines": body})

        r.headline = (f"{t['workouts']} workout{'s' if t['workouts'] != 1 else ''}, {_kg(round(t['volume_kg']))}, "
                      f"{len(by_exercise)} best{'s' if len(by_exercise) != 1 else ''}")
        r.figures = {"workouts": t["workouts"], "seconds": t["seconds"], "volume_kg": t["volume_kg"],
                     "hard_sets": t["hard_sets"], "bests": len(by_exercise), "muscles": muscles}
        reports.append(r)

    # Next targets belong to the newest week only: they look forward from now.
    newest = next((r for r in reversed(reports) if r.kind == "week"), None)
    if newest:
        lines = []
        for eid in dict.fromkeys(i["exerciseId"] for i in h.active_day_items()):
            if eid in h.exercises and (t := analysis.next_target(h, eid, s, today)):
                lines.append(f"{h.exercises[eid].name}: {t['weight']:g} {t['unit']} × {t['reps']} ({t['kind']})")
        if lines:
            newest.sections.append({"title": "Next session targets", "lines": lines})
    return reports


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, suffix=".partial") as f:
            name = f.name
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def write(reports: list[Report], folder: Path) -> dict:
    """Markdown for every report (only rewritten when changed) and the app's JSON."""
    written = 0
    for r in reports:
        path = folder / FOLDER / f"{r.id}.md"
        text = r.markdown()
        if not path.exists() or path.read_text() != text:
            _atomic_write(path, text)
            written += 1
    weeks = [r for r in reports if r.kind == "week"][-26:]
    months = [r for r in reports if r.kind == "month"][-12:]
    app = sorted(weeks + months, key=lambda r: (r.start, r.kind), reverse=True)
    _atomic_write(folder / APP_FILE, json.dumps([r.app_dict() for r in app], indent=1, ensure_ascii=False))
    return {"markdown_written": written, "app_reports": len(app)}
