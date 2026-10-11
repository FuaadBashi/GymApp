"""Reference implementation of the JEFIT import rules in docs/specs/00-foundation.md.

The Swift importer must reproduce these numbers exactly. This script is the arbiter: if
the two disagree, one of them misreads the spec, and the spec decides which.

    python3 -I tools/reference_import.py data/jefit/jefit-export-2026-10-11.csv

Writes GymAppTests/Fixtures/jefit_expected.json: row counts per table, skip counts per
reason, and full spot checks of chosen workouts and exercises.
"""
import argparse, collections, datetime as dt, json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from jefit_parse import parse, table

HERE = os.path.dirname(__file__)
LB_TO_KG = 0.45359237
SET_TYPES = {"default": "working", "warm-up": "warmUp", "failure": "failed"}


def epley(kg, reps):
    return kg if reps <= 1 else kg * (1 + reps / 30)


def parse_reps(text):
    nums = [int(t) for t in text.split(",") if t.strip().isdigit() and int(t) > 0]
    return (min(nums), max(nums)) if nums else (10, 10)


def run(path, map_path, spot_checks=True):
    s = parse(path)
    emap = {e["jefitId"]: e for e in json.load(open(map_path))["exercises"]}
    skips = collections.Counter()
    out = {}

    # 1. Exercises
    exercises = {k: e for k, e in emap.items() if not e["skipOnImport"]}
    skips["exercise: cardio, not supported yet"] += sum(1 for e in emap.values() if e["skipOnImport"])
    out["exercise"] = len(exercises)

    # 2. Programs, days, day exercises
    routines = table(s, "ROUTINES", "difficulty")
    days = table(s, "ROUTINES", "dayIndex")
    items = table(s, "ROUTINES", "exercisename")
    out["program"] = len(routines)
    out["programDay"] = len(days)
    day_items = {}
    for i in items:
        key = f'{i["belongSys"]}:{i["exercise_id"]}'
        if key not in emap:
            skips["dayExercise: exercise never logged, so not in the exercise map"] += 1
            continue
        if emap[key]["skipOnImport"]:
            skips["dayExercise: cardio, not supported yet"] += 1
            continue
        day_items[i["_id"]] = i
    out["dayExercise"] = len(day_items)

    # 3. Workouts, workout exercises, sets
    sessions = table(s, "WORKOUT SESSIONS", "starttime")
    logs = table(s, "EXERCISE LOGS", "ename")
    rows = {}
    for r in table(s, "EXERCISE SET LOGS", "weight_lbs"):
        rows.setdefault(r["exercise_log_id"], {})[int(r["set_index"])] = r  # later row wins
    log_ids = {l["_id"] for l in logs}
    skips["set row: no matching exercise log"] += sum(1 for r in table(s, "EXERCISE SET LOGS", "weight_lbs") if r["exercise_log_id"] not in log_ids)
    dup = sum(c - 1 for c in collections.Counter((r["exercise_log_id"], r["set_index"]) for r in table(s, "EXERCISE SET LOGS", "weight_lbs")).values() if c > 1)
    skips["set row: duplicate set index, later row kept"] += dup

    logs_by_session = collections.defaultdict(list)
    for l in logs:
        logs_by_session[l["belongsession"]].append(l)

    workouts, n_we, n_sets = {}, 0, 0
    sets_by_exercise = collections.defaultdict(list)
    for w in sorted(sessions, key=lambda w: int(w["starttime"])):
        imported = []
        for l in sorted(logs_by_session.get(w["_id"], []), key=lambda l: int(l["_id"])):
            key = f'{l["belongSys"]}:{l["eid"]}'
            e = emap.get(key)
            if e is None:
                skips["exercise log: exercise missing from the map"] += 1
                continue
            if e["skipOnImport"]:
                skips["exercise log: cardio, not supported yet"] += 1
                continue
            raw = []
            if l["_id"] in rows:
                for _, r in sorted(rows[l["_id"]].items()):
                    kg = float(r["weight_lbs"]) * LB_TO_KG if r["weight_lbs"] else 0.0
                    raw.append((kg, int(r["reps"] or 0), SET_TYPES.get(r["set_type"], "working"), int(r["log_time"])))
            else:
                for tok in l["logs"].split(","):
                    wt, reps = tok.split("x")
                    raw.append((float(wt), int(reps), "working", int(w["starttime"])))
            sets = []
            for kg, reps, typ, t in raw:
                if reps <= 0:
                    skips["set: zero reps"] += 1
                    continue
                if e["importWeights"] == "drop":
                    load = None if e["loadMode"] == "repsOnly" else 0
                else:
                    kg = -kg if e["negateOnImport"] else kg
                    load = round(kg * 100)
                sets.append({"loadHundredths": load, "reps": reps, "type": typ, "completedAt": t})
            if not sets:
                skips["exercise log: no sets left"] += 1
                continue
            day_item = day_items.get(l["day_item_id"])
            imported.append({"logId": l["_id"], "exerciseId": f"jefit:{key}", "name": e["name"],
                             "dayItemId": l["day_item_id"] if day_item else None,
                             "dayId": day_item["belongplan"] if day_item else None, "sets": sets})
        if not imported:
            if logs_by_session.get(w["_id"]):
                skips["workout: only cardio or empty exercise logs"] += 1
            else:
                skips["workout: empty in JEFIT (no exercises logged)"] += 1
            continue
        day_votes = collections.Counter(x["dayId"] for x in imported if x["dayId"])
        day_id = None
        if day_votes:
            top = max(day_votes.values())
            day_id = next(x["dayId"] for x in imported if x["dayId"] and day_votes[x["dayId"]] == top)
        workouts[w["_id"]] = {"startedAt": int(w["starttime"]), "endedAt": int(w["endtime"]),
                              "dayId": day_id, "exercises": imported}
        n_we += len(imported)
        n_sets += sum(len(x["sets"]) for x in imported)
        for x in imported:
            sets_by_exercise[x["exerciseId"]].extend(x["sets"])
    out["workout"] = len(workouts)
    out["workoutExercise"] = n_we
    out["workoutSet"] = n_sets
    out["workoutsLinkedToADay"] = sum(1 for w in workouts.values() if w["dayId"])

    # 4. Notes
    notes = []
    for n in table(s, "NOTES", "mynote"):
        key = f'{n["belongSys"]}:{n["eid"]}'
        if n["eid"] in ("", "0"):
            skips["note: not attached to an exercise"] += 1
        elif not n["mynote"].strip():
            skips["note: empty"] += 1
        elif key not in exercises:
            skips["note: exercise not imported"] += 1
        else:
            notes.append(n)
    out["exerciseNote"] = len(notes)
    out["exercisesWithStickyNote"] = len({f'{n["belongSys"]}:{n["eid"]}' for n in notes})

    # 5. Body entries, favourites, sections not imported
    out["bodyEntry"] = len(table(s, "PROFILE", "weight"))
    favs = {f'{f["belongSys"]}:{f["exercise_id"]}' for f in table(s, "FAVORITE EXERCISES", "exercise_id")}
    out["favoriteExercises"] = len(favs & set(exercises))
    skips["favourite: exercise not imported"] += len(favs - set(exercises))
    skips["section: CARDIO LOGS, not supported yet"] += len(table(s, "CARDIO LOGS", "speed"))
    skips["section: CARDIO EXERCISE LOGS, not supported yet"] += len(table(s, "CARDIO EXERCISE LOGS", "el_id"))
    skips["section: EXERCISE RECORDS, derived instead (rulebook §5)"] += len(table(s, "EXERCISE RECORDS", "target1RM"))

    result = {"source": os.path.basename(path), "counts": out, "skips": dict(sorted(skips.items()))}
    if not spot_checks:
        return result

    # Spot checks
    def workout_of_log(name, date):
        for wid, w in workouts.items():
            for x in w["exercises"]:
                if x["name"] == name and dt.datetime.fromtimestamp(x["sets"][0]["completedAt"], dt.timezone.utc).date().isoformat() <= date and \
                        dt.datetime.fromtimestamp(w["startedAt"], dt.timezone.utc).date().isoformat() == date:
                    return wid
        raise SystemExit(f"no workout with {name} on {date}")

    def show(wid):
        w = workouts[wid]
        return {"externalId": f"jefit:session:{wid}", "startedAt": w["startedAt"], "endedAt": w["endedAt"],
                "programDayExternalId": f'jefit:day:{w["dayId"]}' if w["dayId"] else None,
                "exercises": [{"exerciseId": x["exerciseId"], "name": x["name"],
                               "sets": [[st["loadHundredths"], st["reps"], st["type"]] for st in x["sets"]]}
                              for x in w["exercises"]]}

    latest = sorted(workouts, key=lambda k: workouts[k]["startedAt"])[-3:]
    spot = {"pushdown_2024_12_27": show(workout_of_log("Cable Tricep Pushdown (V-Bar)", "2024-12-27"))}
    for i, wid in enumerate(latest):
        spot[f"latest_{i + 1}_of_3"] = show(wid)

    def bests(exercise_id):
        st = [x for x in sets_by_exercise[exercise_id] if x["type"] != "warmUp" and x["loadHundredths"]]
        heaviest = max(x["loadHundredths"] for x in st)
        best = max(epley(x["loadHundredths"] / 100, x["reps"]) for x in st if 1 <= x["reps"] <= 12)
        return {"sets": len(sets_by_exercise[exercise_id]), "heaviestHundredths": heaviest, "bestE1RMKg": round(best, 2)}

    exercise_checks = {k: bests(k) for k in ["jefit:1:2", "jefit:1:12", "jefit:1:93", "jefit:1:86"]}
    assisted = [x for x in sets_by_exercise["jefit:1:1262"]]
    exercise_checks["jefit:1:1262"] = {"sets": len(assisted), "allLoadsNegative": all(x["loadHundredths"] < 0 for x in assisted)}
    reps_only = sets_by_exercise["jefit:1:690"]
    exercise_checks["jefit:1:690"] = {"sets": len(reps_only), "allLoadsNull": all(x["loadHundredths"] is None for x in reps_only)}
    pullups = sets_by_exercise["jefit:1:83"]
    exercise_checks["jefit:1:83"] = {"sets": len(pullups), "allLoadsZero": all(x["loadHundredths"] == 0 for x in pullups)}

    result.update({"workouts": spot, "exercises": exercise_checks})
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("--map", default=os.path.join(HERE, "..", "GymApp", "Resources", "Library", "jefit_exercise_map.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "..", "GymAppTests", "Fixtures", "jefit_expected.json"))
    ap.add_argument("--no-spot-checks", action="store_true", help="for exports other than the real one, e.g. jefit_mini.csv")
    a = ap.parse_args()
    result = run(a.export, a.map, spot_checks=not a.no_spot_checks)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(result, f, indent=1, ensure_ascii=False)
    print(json.dumps(result["counts"], indent=1))
    print(json.dumps(result["skips"], indent=1))


if __name__ == "__main__":
    main()
