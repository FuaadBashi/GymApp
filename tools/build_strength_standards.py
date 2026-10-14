"""Fetch gym-lifter strength standards from FitnessVolt's public API into
GymApp/Resources/strength-standards.json.

Usage: python3 -I tools/build_strength_standards.py

Data: FitnessVolt strength standards, CC BY 4.0 (https://fitnessvolt.com/strength-standards/),
self-reported gym population sourced from Symmetric Strength. Only the gym population is
kept (the owner chose gym-lifter comparisons); percentiles are estimated 1RM in kg by sex and
bodyweight class. The app must show "Powered by FitnessVolt" with a link wherever it shows them.
"""
import json, sys, urllib.request
from datetime import date
from pathlib import Path

BASE = "https://fitnessvolt.com/wp-json/rpe-training/v1/public/standards/"
# FitnessVolt lift → how the app recognises it: name words (all must appear) and equipment.
LIFTS = {
    "squat": {"label": "Back squat", "match": [["squat"]], "exclude": ["front", "split", "goblet", "hack", "plate", "box", "smith"]},
    "bench-press": {"label": "Bench press", "match": [["bench", "press"]], "exclude": ["incline", "decline", "close", "smith", "dumbbell"]},
    "deadlift": {"label": "Deadlift", "match": [["deadlift"]], "exclude": ["romanian", "stiff", "sumo", "trap", "hex", "single", "dumbbell"]},
    "front-squat": {"label": "Front squat", "match": [["front", "squat"]], "exclude": []},
    "sumo-deadlift": {"label": "Sumo deadlift", "match": [["sumo", "deadlift"]], "exclude": []},
    "incline-bench-press": {"label": "Incline bench press", "match": [["incline", "bench", "press"]], "exclude": ["dumbbell", "smith"]},
    "overhead-press": {"label": "Overhead press", "match": [["overhead", "press"], ["military", "press"], ["shoulder", "press", "standing"]], "exclude": ["dumbbell", "machine", "seated"]},
    "pendlay-row": {"label": "Barbell row", "match": [["row", "bent"], ["pendlay", "row"]], "exclude": ["dumbbell", "cable", "machine", "t-bar"]},
}


def fetch(lift: str, sex: str) -> dict:
    request = urllib.request.Request(f"{BASE}{lift}?sex={sex}&unit=kg", headers={"User-Agent": "GymApp-standards/1.0"})
    with urllib.request.urlopen(request, timeout=30) as r:
        data = json.load(r)
    gym = data.get("gym") or {}
    classes = []
    for c in gym.get("weight_classes", []):
        name = c["weight_class"]
        upper = None if name.endswith("+kg") else float(name.removesuffix("kg"))
        classes.append({"upperKg": upper, "sample": c["sample_size"],
                        "percentiles": {k.removeprefix("p"): round(v, 1) for k, v in c["percentiles"].items()}})
    return {"classes": classes, "sample": gym.get("total_sample_size")}


def main() -> None:
    out = {"source": "FitnessVolt strength standards (gym population, from Symmetric Strength)",
           "licence": "CC BY 4.0", "attribution": "Powered by FitnessVolt",
           "url": "https://fitnessvolt.com/strength-standards/", "fetched": date.today().isoformat(),
           "lifts": {}}
    for lift, meta in LIFTS.items():
        entry = {"label": meta["label"], "match": meta["match"], "exclude": meta["exclude"], "sexes": {}}
        for sex in ("male", "female"):
            data = fetch(lift, sex)
            if data["classes"]:
                entry["sexes"][sex] = data["classes"]
        out["lifts"][lift] = entry
        print(lift, {s: len(c) for s, c in entry["sexes"].items()}, file=sys.stderr)
    path = Path(__file__).resolve().parents[1] / "GymApp/Resources/strength-standards.json"
    path.write_text(json.dumps(out, indent=1) + "\n")
    print(f"wrote {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
