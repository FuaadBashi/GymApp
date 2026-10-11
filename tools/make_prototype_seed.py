"""Build the prototype's seed from a JEFIT export: the current routine days, each
exercise's full history, and its newest note.

Prototype only. The real app will import the CSV itself (docs/JEFIT_EXPORT.md);
this exists so the workout screen can be tried against real numbers first.

    python3 -I tools/make_prototype_seed.py data/jefit/jefit-export-2026-10-11.csv

Writes GymApp/Prototype/PrototypeSeed.json, which is gitignored because it
carries personal notes.
"""
import argparse, datetime as dt, json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from jefit_parse import parse, table

LB_TO_KG = 0.45359237
SET_TYPES = {"default": "working", "warm-up": "warmUp", "failure": "failed"}


def equipment(name):
    n = name.lower()
    if "assisted" in n:
        return "assisted"
    if n.startswith(("barbell", "ez bar", "smith machine")):
        return "barbell"
    if n.startswith("dumbbell"):
        return "dumbbell"
    if n.startswith("cable"):
        return "cable"
    if n.startswith(("machine", "leverage", "lever")):
        return "machine"
    return "other"


def iso(ts):
    return dt.datetime.fromtimestamp(int(ts), tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("--days", nargs="+", default=["1FBD 1", "2FBD 2"])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "GymApp", "Prototype", "PrototypeSeed.json"))
    a = ap.parse_args()

    s = parse(a.export)
    days = table(s, "ROUTINES", "dayIndex")
    day_items = table(s, "ROUTINES", "exercisename")
    sessions = {w["_id"]: w for w in table(s, "WORKOUT SESSIONS", "starttime")}
    logs = table(s, "EXERCISE LOGS", "ename")
    set_rows = table(s, "EXERCISE SET LOGS", "weight_lbs")
    notes = table(s, "NOTES", "mynote")
    profile = table(s, "PROFILE", "weight")

    item_day = {i["_id"]: i["belongplan"] for i in day_items}
    rows_by_log = {}
    for r in set_rows:
        rows_by_log.setdefault(r["exercise_log_id"], {})[int(r["set_index"])] = r  # last row wins a duplicate index

    def sets_of(log, assisted):
        # JEFIT_EXPORT.md trap 1: set rows are canonical; `logs` only before they existed.
        out = []
        if log["_id"] in rows_by_log:
            for _, r in sorted(rows_by_log[log["_id"]].items()):
                kg = float(r["weight_lbs"]) * LB_TO_KG if r["weight_lbs"] else 0.0
                out.append((kg, int(r["reps"] or 0), SET_TYPES.get(r["set_type"], "working")))
        else:
            for tok in log["logs"].split(","):
                w, reps = tok.split("x")
                out.append((float(w), int(reps), "working"))
        sign = -1 if assisted else 1  # trap 2: assistance is logged as a positive weight
        return [{"kg": round(sign * kg, 2), "reps": reps, "type": t} for kg, reps, t in out if reps > 0]

    def history(sys_, eid, name):
        assisted = equipment(name) == "assisted"
        entries = []
        for l in logs:
            if (l["belongSys"], l["eid"]) != (sys_, eid):
                continue
            sets = sets_of(l, assisted)
            if not sets:
                continue
            d = item_day.get(l["day_item_id"])
            entries.append({
                "date": iso(sessions[l["belongsession"]]["starttime"]),
                "dayId": f"jefit-day-{d}" if d else None,
                "sets": sets,
            })
        return sorted(entries, key=lambda e: e["date"])

    def newest_note(sys_, eid):
        mine = [n for n in notes if (n["belongSys"], n["eid"]) == (sys_, eid) and n["mynote"].strip()]
        if not mine:
            return None
        n = max(mine, key=lambda n: (n["mydate"], int(n["_id"])))
        return {"date": n["mydate"], "text": n["mynote"].strip()}

    out_days = []
    for want in a.days:
        day = next((d for d in days if d["name"].strip() == want), None)
        if day is None:
            sys.exit(f"no routine day named {want!r}")
        items = sorted((i for i in day_items if i["belongplan"] == day["_id"]), key=lambda i: int(i["mysort"] or 0))
        exercises = []
        for i in items:
            name = i["exercisename"].strip()
            exercises.append({
                "id": f"jefit-{i['belongSys']}-{i['exercise_id']}",
                "name": name,
                "equipment": equipment(name),
                "restSeconds": int(i["timer"] or 60),
                "targetSets": int(i["setcount"] or 3),
                "note": newest_note(i["belongSys"], i["exercise_id"]),
                "history": history(i["belongSys"], i["exercise_id"], name),
            })
        out_days.append({"id": f"jefit-day-{day['_id']}", "name": want, "exercises": exercises})

    latest = max(profile, key=lambda p: p["mydate"])
    seed = {
        "source": os.path.basename(a.export),
        "bodyWeightKg": float(latest["weight"]),
        "bodyWeightDate": latest["mydate"],
        "days": out_days,
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(seed, f, indent=1, ensure_ascii=False)
    n_hist = sum(len(e["history"]) for d in out_days for e in d["exercises"])
    print(f"wrote {os.path.relpath(a.out)}: {len(out_days)} days, "
          f"{sum(len(d['exercises']) for d in out_days)} exercises, {n_hist} past sessions")


if __name__ == "__main__":
    main()
