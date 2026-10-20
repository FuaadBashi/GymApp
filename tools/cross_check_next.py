"""Studio side of the §13 cross-check: the studio's next_target for every exercise in a
backup, written for the app's NextSetCrossCheckTests to compare against NextSet.

Usage: python3 -I tools/cross_check_next.py data/backups/<backup>.sqlite
Writes data/next_cross_check.json (data/ is never committed).

Only the rules both sides share are compared, so the studio's plateau rule is switched off
and every lift uses the default 8-12 range; the app skips its comeback rule for lifts away
30+ days, which the studio does not have.
"""
import json
import sys
from datetime import timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "studio"))
from gymstudio import analysis as a  # noqa: E402
from gymstudio.data import History  # noqa: E402


def main() -> None:
    backup = Path(sys.argv[1]).resolve()
    h = History(backup)
    s = a.Settings()
    a.plateau = lambda *args, **kw: {"status": "ok"}
    a.rep_range_for = lambda *args, **kw: s.default_rep_range
    out = {}
    for eid, ex in h.exercises.items():
        sessions = a.per_workout(h, eid)
        if ex.load_mode in ("repsOnly", "bodyweightPlus") or not sessions:
            continue
        # Each lift is asked the day after its own last session, so no break is involved.
        today = sessions[-1][1] + timedelta(days=1)
        t = a.next_target(h, eid, s, today)
        if t:
            out[eid] = {"kind": t["kind"], "weight": t["weight"], "unit": t["unit"], "reps": int(t["reps"].rstrip("+")),
                        "today": today.strftime("%Y-%m-%dT%H:%M:%SZ")}
    result = {"backup": backup.name, "range": list(s.default_rep_range), "exercises": out}
    (ROOT / "data/next_cross_check.json").write_text(json.dumps(result, indent=1) + "\n")
    print(f"{len(out)} exercises", file=sys.stderr)


if __name__ == "__main__":
    main()
