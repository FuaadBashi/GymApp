"""Turn the vendored free-exercise-db dataset into the library file the app bundles.

    python3 -I tools/build_library.py

Reads third_party/free-exercise-db/exercises.json and writes
GymApp/Resources/Library/exercises.json, with the same field names and enum values as
jefit_exercise_map.json so the app has one decoder for both. Field meanings and the enum
lists are in docs/specs/00-foundation.md.
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
from build_jefit_map import BODYWEIGHT_REPS_ONLY, LOWER, UNILATERAL, UPPER

HERE = os.path.dirname(__file__)
SOURCE = os.path.join(HERE, "..", "third_party", "free-exercise-db", "exercises.json")
OUT = os.path.join(HERE, "..", "GymApp", "Resources", "Library", "exercises.json")

EQUIPMENT = {
    "barbell": "barbell", "e-z curl bar": "ezBar", "dumbbell": "dumbbell",
    "kettlebells": "kettlebell", "cable": "cable", "machine": "machine", "bands": "band",
    "body only": "bodyweight", "medicine ball": "other", "exercise ball": "other",
    "foam roll": "other", "other": "other", None: "other",
}
CATEGORY = {
    "strength": "strength", "stretching": "stretching", "plyometrics": "plyometrics",
    "powerlifting": "powerlifting", "olympic weightlifting": "olympicWeightlifting",
    "strongman": "strongman", "cardio": "cardio",
}
MUSCLE = {"lower back": "lowerBack", "middle back": "middleBack"}  # every other name is already camelCase
WHOLE_BODY = r"pull-?up|chin-?up|\bdips?\b|muscle up"


def muscle(name):
    return MUSCLE.get(name, name)


def entry(x):
    name = x["name"].strip()
    n = name.lower()
    equipment = EQUIPMENT[x.get("equipment")]
    if equipment == "machine" and "smith" in n:
        equipment = "smith"
    category = CATEGORY[x["category"]]
    if category in ("cardio", "stretching"):
        load_mode = "repsOnly"
    elif equipment == "bodyweight":
        load_mode = "bodyweightPlus" if re.search(WHOLE_BODY, n) and not re.search(BODYWEIGHT_REPS_ONLY + r"|bench dip", n) else "repsOnly"
    elif equipment == "dumbbell":
        load_mode = "perSide" if re.search(UNILATERAL, n) else "perHand"
    elif re.search(UNILATERAL, n):
        load_mode = "perSide"
    else:
        load_mode = "total"
    prim = [muscle(m) for m in x["primaryMuscles"]]
    regions = {"upper" if m in UPPER else "lower" if m in LOWER else "core" for m in x["primaryMuscles"]}
    if category == "cardio":
        region = "cardio"
    elif len(regions) == 1:
        region = regions.pop()
    elif regions:
        region = "fullBody"
    else:
        region = "fullBody"
    return {
        "id": f'lib:{x["id"]}', "name": name, "equipment": equipment, "loadMode": load_mode,
        "primaryMuscles": prim, "secondaryMuscles": [muscle(m) for m in x["secondaryMuscles"]],
        "force": x.get("force"), "mechanic": x.get("mechanic"), "category": category,
        "bodyRegion": region, "movementPattern": None, "instructions": x.get("instructions", []),
    }


def main():
    data = json.load(open(SOURCE))
    out = sorted((entry(x) for x in data), key=lambda e: e["name"].lower())
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"source": "free-exercise-db@f00c92c", "exercises": out}, f, indent=1, ensure_ascii=False)
    counts = {}
    for e in out:
        counts[e["bodyRegion"]] = counts.get(e["bodyRegion"], 0) + 1
    print(f"wrote {os.path.relpath(OUT)}: {len(out)} exercises; regions {counts}")


if __name__ == "__main__":
    main()
