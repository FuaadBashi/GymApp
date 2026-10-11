"""Phase 3 close: figures for three exercises computed straight from the JEFIT export, to
compare with the app's exercise pages; and JEFIT's own EXERCISE RECORDS against the best
Epley figure from the logs (JEFIT_EXPORT.md trap 6).

    python3 -I tools/check_phase3.py data/jefit/jefit-export-2026-10-11.csv

Writes GymAppTests/Fixtures/phase3_expected.json, which the Swift tests compare against.
"""
import collections, json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from jefit_parse import parse, table
from reference_import import epley, LB_TO_KG, SET_TYPES

HERE = os.path.dirname(__file__)
CHECKED = {"jefit:1:2": "Barbell Bench Press", "jefit:1:12": "Barbell Squat", "jefit:1:93": "Barbell Deadlift"}


def main(path):
    s = parse(path)
    emap = {e["jefitId"]: e for e in json.load(open(os.path.join(HERE, "..", "GymApp", "Resources", "Library", "jefit_exercise_map.json")))["exercises"]}
    sessions = {w["_id"]: w for w in table(s, "WORKOUT SESSIONS", "starttime")}
    rows = {}
    for r in table(s, "EXERCISE SET LOGS", "weight_lbs"):
        rows.setdefault(r["exercise_log_id"], {})[int(r["set_index"])] = r

    # session id -> exercise id -> [(kg, reps, type)], with the importer's rules.
    by_session = collections.defaultdict(lambda: collections.defaultdict(list))
    for l in table(s, "EXERCISE LOGS", "ename"):
        key = f'{l["belongSys"]}:{l["eid"]}'
        e = emap.get(key)
        if e is None or e["skipOnImport"] or l["belongsession"] not in sessions:
            continue
        if l["_id"] in rows:
            raw = [(float(r["weight_lbs"] or 0) * LB_TO_KG, int(r["reps"] or 0), SET_TYPES.get(r["set_type"], "working"))
                   for _, r in sorted(rows[l["_id"]].items())]
        else:
            raw = [(float(t.split("x")[0]), int(t.split("x")[1]), "working") for t in l["logs"].split(",")]
        for kg, reps, typ in raw:
            if reps <= 0:
                continue
            if e["importWeights"] == "drop":
                kg = 0.0
            # Loads are stored in hundredths as the importer rounds them.
            kg = round(kg * 100) / 100
            by_session[l["belongsession"]][f"jefit:{key}"].append((kg, reps, typ))

    figures = {}
    for eid, name in CHECKED.items():
        mult = 2 if emap[eid.removeprefix("jefit:")]["loadMode"] in ("perHand", "perSide") else 1
        heaviest, best, best_volume, n = 0.0, 0.0, 0.0, 0
        for sid, ex in by_session.items():
            sets = ex.get(eid)
            if not sets:
                continue
            n += 1
            counted = [x for x in sets if x[2] not in ("warmUp", "drop") and x[0] > 0]
            heaviest = max([heaviest] + [x[0] for x in counted])
            best = max([best] + [epley(x[0], x[1]) for x in counted if 1 <= x[1] <= 12])
            best_volume = max(best_volume, sum(x[0] * x[1] * mult for x in sets if x[2] != "warmUp"))
        figures[eid] = {"name": name, "sessions": n, "heaviestKg": round(heaviest, 2),
                        "bestE1RMKg": round(best, 2), "bestSessionVolumeKg": round(best_volume, 2)}

    # JEFIT's records: compare JEFIT's stored 1RM with the best Epley from the logs.
    all_sets = collections.defaultdict(list)
    for ex in by_session.values():
        for eid, sets in ex.items():
            all_sets[eid].extend(sets)
    matched, compared = 0, 0
    for r in table(s, "EXERCISE RECORDS", "target1RM"):
        eid = f'jefit:{r["belongSys"]}:{r["eid"]}'
        stored = float(r["record"] or 0)
        cand = [epley(x[0], x[1]) for x in all_sets.get(eid, []) if x[2] not in ("warmUp", "drop") and x[0] > 0 and 1 <= x[1] <= 12]
        if stored <= 0 or not cand:
            continue
        compared += 1
        # JEFIT stores whole-kg (or lb) values; a match is within 1 kg.
        if abs(max(cand) - stored) <= 1 or abs(max(cand) - stored * LB_TO_KG) <= 1:
            matched += 1

    out = {"exercises": figures, "jefitRecords": {"compared": compared, "matched": matched}}
    target = os.path.join(HERE, "..", "GymAppTests", "Fixtures", "phase3_expected.json")
    json.dump(out, open(target, "w"), indent=1)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main(sys.argv[1])
