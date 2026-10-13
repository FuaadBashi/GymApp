"""Classify every exercise in a JEFIT export: equipment, load mode, muscles, movement
pattern, and how its logged weights import. The output is checked in and read by the
app's importer, so the judgement calls live in one reviewable file, not in Swift.

    python3 -I tools/build_jefit_map.py data/jefit/jefit-export-2026-10-11.csv

Writes GymApp/Resources/Library/jefit_exercise_map.json. Rules are ordered: the first
pattern that matches an exercise's latest name wins. OVERRIDES then replace individual
fields for exercises the rules get wrong. Field meanings: docs/specs/00-foundation.md.
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
from jefit_parse import parse, table

UPPER = {"chest", "shoulders", "lats", "middle back", "traps", "biceps", "triceps", "forearms", "neck"}
LOWER = {"quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "lower back"}

# (regex on lowercased latest name, movementPattern, primary, secondary, force, mechanic, category)
RULES = [
    (r"treadmill|cycling|^walking", "cardio", [], [], None, None, "cardio"),
    (r"arm circles", "other", ["shoulders"], [], None, None, "stretching"),
    (r"neck", "neck", ["neck"], [], "push", "isolation", "strength"),
    (r"farmer", "carry", ["forearms"], ["traps"], "static", "compound", "strength"),
    (r"wrist curl|grip vice|grips strength", "grip", ["forearms"], [], "pull", "isolation", "strength"),
    (r"face pull|rear delt|reverse fly|posterior fly|bent-over lateral|lateral pulley", "rearDelt", ["shoulders"], ["traps", "middle back"], "pull", "isolation", "strength"),
    (r"shrug", "shrug", ["traps"], [], "pull", "isolation", "strength"),
    (r"upright row", "lateralRaise", ["shoulders"], ["traps"], "pull", "compound", "strength"),
    (r"lateral raise|side lateral|lateral shoulder raise|lui raise", "lateralRaise", ["shoulders"], [], "push", "isolation", "strength"),
    (r"front raise", "frontRaise", ["shoulders"], [], "push", "isolation", "strength"),
    (r"pullover", "pullover", ["lats"], ["chest", "triceps"], "pull", "isolation", "strength"),
    (r"vertical row", "horizontalPull", ["middle back", "lats"], ["biceps", "shoulders"], "pull", "compound", "strength"),
    (r"pulldown|pull-up|pullup|chin-up|chinup|high row", "verticalPull", ["lats"], ["biceps", "middle back"], "pull", "compound", "strength"),
    (r"\brows?\b", "horizontalPull", ["middle back", "lats"], ["biceps", "shoulders"], "pull", "compound", "strength"),
    (r"back extension|hyperextension", "backExtension", ["lower back"], ["glutes", "hamstrings"], "pull", "isolation", "strength"),
    (r"deadlift|good morning|pull through", "hinge", ["hamstrings"], ["glutes", "lower back"], "pull", "compound", "strength"),
    (r"parallel bar hip raise|leg raise|knee raise|crunch|sit-up|reverse crunch", "coreFlexion", ["abdominals"], [], "pull", "isolation", "strength"),
    (r"side bend", "coreFlexion", ["abdominals"], [], "pull", "isolation", "strength"),
    (r"plank", "coreStability", ["abdominals"], [], "static", "isolation", "strength"),
    (r"hip thrust|glute bridge", "hipThrust", ["glutes"], ["hamstrings"], "push", "compound", "strength"),
    (r"hip abduction", "hipAbduction", ["abductors"], ["glutes"], "push", "isolation", "strength"),
    (r"calf", "calfRaise", ["calves"], [], "push", "isolation", "strength"),
    (r"leg extension", "kneeExtension", ["quadriceps"], [], "push", "isolation", "strength"),
    (r"leg curl", "kneeFlexion", ["hamstrings"], [], "pull", "isolation", "strength"),
    (r"lunge|split squat", "lunge", ["quadriceps"], ["glutes", "hamstrings"], "push", "compound", "strength"),
    (r"leg press|squat|hack", "squat", ["quadriceps"], ["glutes", "hamstrings"], "push", "compound", "strength"),
    (r"skull crusher|tricep|triceps|pushdown|kickback|jm press", "tricepsExtension", ["triceps"], [], "push", "isolation", "strength"),
    (r"curl", "bicepsCurl", ["biceps"], ["forearms"], "pull", "isolation", "strength"),
    (r"fly|cross-over|crossover|inner chest press|chest raise", "chestFly", ["chest"], ["shoulders"], "push", "isolation", "strength"),
    (r"incline.*(press|bench)", "inclinePush", ["chest"], ["shoulders", "triceps"], "push", "compound", "strength"),
    (r"shoulder press|military|arnold|bradford|seated press|alternating press", "verticalPush", ["shoulders"], ["triceps"], "push", "compound", "strength"),
    (r"bench press|chest press|close grip press|decline press|push-up", "horizontalPush", ["chest"], ["triceps", "shoulders"], "push", "compound", "strength"),
    (r"\bdip\b", "dip", ["triceps"], ["chest", "shoulders"], "push", "compound", "strength"),
]

EQUIPMENT = [
    (r"^smith machine", "smith"),
    (r"^ez bar", "ezBar"),
    (r"^(barbell|t bar)", "barbell"),
    (r"^dumbbell", "dumbbell"),
    (r"^kettlebell", "kettlebell"),
    (r"^cable", "cable"),
    (r"^weight plate", "plate"),
    (r"^(exercise band|banded)", "band"),
    (r"^(machine|leverage|lever)|\bmachine\b|hack squat|calf press", "machine"),
]
UNILATERAL = r"one-arm|one arm|single-arm|single arm|single-leg|one-leg"

# Exercises the rules misjudge. Keyed by JEFIT id "belongSys:eid"; fields replace the rule's.
OVERRIDES = {
    "1:375": {"loadMode": "total", "why": "one dumbbell held in both hands"},
    "1:652": {"loadMode": "total", "why": "one dumbbell held in both hands"},
    "1:247": {"loadMode": "total", "why": "overhead extension with one dumbbell"},
    "1:158": {"loadMode": "total", "why": "one dumbbell held in both hands"},
    "1:80": {"loadMode": "perSide", "why": "one dumbbell, one side at a time"},
    "1:348": {"loadMode": "perSide"},
    "1:1381": {"loadMode": "perHand", "why": "a kettlebell in each hand"},
    "1:83": {"equipment": "bodyweight", "loadMode": "bodyweightPlus", "importWeights": "drop",
             "why": "set rows carry no weight; logged as bodyweight"},
    "1:24": {"equipment": "bodyweight", "loadMode": "bodyweightPlus", "importWeights": "drop",
             "why": "weights are JEFIT's 10 kg default or a one-off body weight, not added load"},
    "1:459": {"loadMode": "total", "why": "seated dip machine: the stack is the load"},
    "1:675": {"equipment": "plate", "loadMode": "total", "why": "weights vary 5-10 kg: a held plate"},
    "1:92": {"equipment": "plate", "loadMode": "total", "why": "weights vary 2.5-10 kg: a held plate"},
    "1:1259": {"loadMode": "total"},
    "1:1270": {"movementPattern": "chestFly"},
    "1:14": {"movementPattern": "chestFly"},
    "0:1": {"equipment": "dumbbell", "loadMode": "perHand", "movementPattern": "hinge",
            "name": "Dumbbell Romanian Deadlift", "why": "custom 'Romanian deadlifts dumbeel'"},
    "0:2": {"equipment": "band", "loadMode": "repsOnly", "importWeights": "drop"},
    "0:3": {"equipment": "other", "loadMode": "repsOnly", "importWeights": "drop"},
    "0:4": {"equipment": "other", "loadMode": "repsOnly", "importWeights": "drop"},
    "0:5": {"equipment": "plate", "loadMode": "total", "movementPattern": "lateralRaise",
            "why": "Lu raise with a plate, 5 kg every set"},
    "0:6": {"equipment": "plate", "loadMode": "total"},
    "1:1061": {"equipment": "bodyweight", "loadMode": "repsOnly", "why": "push-up on dumbbell handles"},
    "1:1236": {"equipment": "bodyweight", "loadMode": "repsOnly", "importWeights": "drop"},
}

# Library twins name matching misses, checked by hand: the same movement on the same
# equipment (decision #28: two different machines are never merged). With a link, the app
# hides the library duplicate and borrows its instructions.
LIBRARY_LINKS = {
    "1:86": "Wide-Grip_Lat_Pulldown", "1:130": "Leg_Extensions", "1:2": "Barbell_Bench_Press_-_Medium_Grip",
    "1:160": "Lying_Leg_Curls", "1:32": "Side_Lateral_Raise", "1:149": "Triceps_Pushdown_-_V-Bar_Attachment",
    "1:447": "Smith_Machine_Overhead_Shoulder_Press", "1:132": "Leg_Press", "1:46": "Machine_Shoulder_Military_Press",
    "1:874": "Face_Pull", "1:8": "Barbell_Incline_Bench_Press_-_Medium_Grip", "1:21": "Seated_Cable_Rows",
    "1:116": "Dumbbell_Alternate_Bicep_Curl", "1:1256": "Single-Leg_Leg_Extension", "1:45": "Butterfly",
    "1:199": "Romanian_Deadlift", "1:820": "Leverage_Iso_Row", "1:187": "V-Bar_Pulldown",
    "1:114": "Alternate_Hammer_Curl", "1:140": "Calf_Press_On_The_Leg_Press_Machine", "1:31": "Incline_Dumbbell_Press",
    "1:42": "Dumbbell_Shrug", "1:113": "Preacher_Curl", "1:155": "Cable_Rope_Overhead_Triceps_Extension",
    "1:102": "Standing_Biceps_Cable_Curl", "1:250": "Triceps_Pushdown", "1:83": "Pullups",
    "1:159": "Triceps_Pushdown_-_Rope_Attachment", "1:161": "Seated_Leg_Curl", "1:92": "Hyperextensions_Back_Extensions",
    "1:271": "Machine_Preacher_Curls", "1:1274": "Leverage_High_Row", "1:253": "Machine_Triceps_Extension",
    "1:146": "Seated_Side_Lateral_Raise", "1:474": "Dumbbell_Squat_To_A_Bench", "1:79": "Cable_Crunch",
    "1:1043": "Bent_Over_Two-Dumbbell_Row_With_Palms_In", "1:88": "Bent_Over_Two-Dumbbell_Row", "1:107": "Concentration_Curls",
    "1:108": "Hammer_Curls", "1:119": "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench", "1:1278": "Bent_Over_Low-Pulley_Side_Lateral",
    "1:14": "Cable_Crossover", "1:486": "Narrow_Stance_Leg_Press", "1:878": "Reverse_Machine_Flyes", "1:886": "Leverage_Shrug",
    "1:1040": "Dumbbell_Incline_Row", "1:115": "Alternate_Incline_Dumbbell_Curl", "1:136": "Dumbbell_Lunges",
    "1:158": "Seated_Triceps_Press", "1:236": "Lying_Dumbbell_Tricep_Extension", "1:460": "JM_Press",
    "1:467": "Barbell_Full_Squat", "1:954": "Stiff-Legged_Barbell_Deadlift", "1:393": "Pull_Through",
    "1:401": "Bradford_Rocky_Presses", "1:41": "Dumbbell_Flyes", "1:424": "Lying_Face_Down_Plate_Neck_Resistance",
    "1:425": "Lying_Face_Up_Plate_Neck_Resistance", "1:43": "Standing_Dumbbell_Upright_Row", "1:453": "Standing_Military_Press",
    "1:257": "Cable_Hammer_Curls_-_Rope_Attachment", "1:216": "Thigh_Abductor",
}

BODYWEIGHT_REPS_ONLY = r"push-up|knee raise|leg raise|hip raise|decline crunch|reverse crunch|plank|bodyweight squat|arm circles|side neck"


def camel(muscle):
    """Muscle raw values are camelCase in the app; the dataset spells two with spaces."""
    return {"lower back": "lowerBack", "middle back": "middleBack"}.get(muscle, muscle)


def latest_names(logs, custom):
    names, counts, last = {}, {}, {}
    for l in sorted(logs, key=lambda l: l["mydate"]):
        k = f'{l["belongSys"]}:{l["eid"]}'
        names[k] = l["ename"].strip()
        counts[k] = counts.get(k, 0) + 1
        last[k] = l["mydate"]
    for c in custom:  # custom exercises with no logs still exist in the user's library
        k = f'0:{c["_id"]}'
        names.setdefault(k, c["name"].strip())
        counts.setdefault(k, 0)
    return names, counts, last


def classify(key, name):
    n = name.lower()
    for rx, pattern, prim, sec, force, mech, cat in RULES:
        if re.search(rx, n):
            break
    else:
        pattern, prim, sec, force, mech, cat = "other", [], [], None, None, "strength"
    equipment = next((e for rx, e in EQUIPMENT if re.search(rx, n)), "bodyweight")
    if cat == "cardio":
        load_mode = "repsOnly"
    elif "assisted" in n:
        load_mode = "bodyweightPlus"
    elif equipment == "bodyweight":
        load_mode = "repsOnly" if re.search(BODYWEIGHT_REPS_ONLY, n) else "bodyweightPlus"
    elif equipment == "dumbbell":
        load_mode = "perSide" if re.search(UNILATERAL, n) else "perHand"
    elif re.search(UNILATERAL, n):
        load_mode = "perSide"
    else:
        load_mode = "total"
    regions = {"upper" if m in UPPER else "lower" if m in LOWER else "core" for m in prim}
    if cat == "cardio":
        region = "cardio"
    elif len(regions) == 1:
        region = regions.pop()
    elif regions:
        region = "fullBody"
    else:
        region = "upper"
    entry = {
        "jefitId": key, "name": name, "equipment": equipment, "loadMode": load_mode,
        "primaryMuscles": [camel(m) for m in prim], "secondaryMuscles": [camel(m) for m in sec],
        "force": force, "mechanic": mech,
        "category": cat, "bodyRegion": region, "movementPattern": pattern,
        "importWeights": None,
        "negateOnImport": "assisted" in n,
        "skipOnImport": cat == "cardio",
    }
    over = {k: v for k, v in OVERRIDES.get(key, {}).items() if k != "why"}
    entry.update(over)
    if entry["importWeights"] is None:
        # A reps-only exercise has no load to keep; JEFIT's numbers there are its 10 kg default.
        entry["importWeights"] = "drop" if entry["loadMode"] == "repsOnly" else "keep"
    if "why" in OVERRIDES.get(key, {}):
        entry["note"] = OVERRIDES[key]["why"]
    return entry


def norm(name):
    s = re.sub(r"[^a-z0-9 ]", " ", name.lower())
    s = s.replace("leverage", "lever").replace("ez bar", "ez bar")
    return " ".join(sorted(set(s.split()) - {"the", "a", "on", "with"}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("--library", default=os.path.join(os.path.dirname(__file__), "..", "third_party", "free-exercise-db", "exercises.json"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "GymApp", "Resources", "Library", "jefit_exercise_map.json"))
    a = ap.parse_args()

    s = parse(a.export)
    logs = table(s, "EXERCISE LOGS", "ename")
    custom = table(s, "CUSTOM EXERCISES", "unilateral")
    names, counts, last = latest_names(logs, custom)
    library_rows = json.load(open(a.library))
    library = {norm(x["name"]): x["id"] for x in library_rows}
    ids = {x["id"] for x in library_rows}
    assert all(v in ids for v in LIBRARY_LINKS.values()), "LIBRARY_LINKS names a missing library id"

    entries = []
    for key in sorted(names, key=lambda k: (-counts[k], k)):
        e = classify(key, names[key])
        e["libraryId"] = f'lib:{library[norm(e["name"])]}' if norm(e["name"]) in library else None
        if e["libraryId"] is None and key in LIBRARY_LINKS:
            e["libraryId"] = f'lib:{LIBRARY_LINKS[key]}'
        e["jefitLogCount"] = counts[key]
        entries.append(e)

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump({"source": os.path.basename(a.export), "exercises": entries}, f, indent=1, ensure_ascii=False)
    print(f"wrote {os.path.relpath(a.out)}: {len(entries)} exercises, "
          f"{sum(1 for e in entries if e['libraryId'])} matched to the library, "
          f"{sum(1 for e in entries if e['skipOnImport'])} skipped (cardio)")


if __name__ == "__main__":
    main()
