"""Convert react-body-highlighter 2.0.5 (MIT, (c) 2020 GV79) polygon data into
GymApp/Resources/BodyMap/body_map.json.

Usage: python3 -I tools/build_body_map.py <path to the package's src/assets/index.ts>

Each region keeps its source name and maps to the app's Muscle cases. The source has no
separate lats or middle back: its 'upper-back' covers both, so both muscles shade it.
The source's names are swapped: its front 'abductors' and back 'adductor' regions both sit on
the inner thigh, so both shade adductors. There is no outer-hip region; abductors shade the
gluteal region, which holds gluteus medius, the main hip abductor. Head, knees and neck-as-outline stay unshaded body parts.
"""
import json, re, sys

MAP = {
    "chest": ["chest"], "obliques": ["abdominals"], "abs": ["abdominals"],
    "biceps": ["biceps"], "triceps": ["triceps"], "forearm": ["forearms"],
    "front-deltoids": ["shoulders"], "back-deltoids": ["shoulders"],
    "abductors": ["adductors"], "adductor": ["adductors"],
    "quadriceps": ["quadriceps"], "hamstring": ["hamstrings"], "gluteal": ["glutes", "abductors"],
    "calves": ["calves"], "left-soleus": ["calves"], "right-soleus": ["calves"],
    "trapezius": ["traps"], "upper-back": ["lats", "middleBack"], "lower-back": ["lowerBack"],
    "neck": ["neck"], "head": [], "knees": [],
}

src = open(sys.argv[1]).read()
types = {}
meta = open(sys.argv[1].replace("assets/index.ts", "component/metadata.ts")).read()
for name, value in re.findall(r"(\w+)\s*:\s*'([a-z-]+)'", meta):
    types[name] = value

out = {"viewBox": [100, 200], "source": "react-body-highlighter 2.0.5", "license": "MIT", "figures": {}}
for figure, key in [("front", "anteriorData"), ("back", "posteriorData")]:
    block = src[src.index(f"export const {key}"):]
    block = block[:block.index("];") + 2]
    regions = []
    for m in re.finditer(r"muscle:\s*MuscleType\.(\w+),\s*svgPoints:\s*\[(.*?)\]", block, re.S):
        name = types[m.group(1)]
        polys = []
        for pts in re.findall(r"'([^']+)'", m.group(2)):
            nums = [float(x) for x in pts.split()]
            polys.append([[round(nums[i], 3), round(nums[i + 1], 3)] for i in range(0, len(nums) - 1, 2)])
        regions.append({"name": name, "muscles": MAP[name], "polygons": polys})
    out["figures"][figure] = regions

missing = {"abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
           "lats", "lowerBack", "middleBack", "neck", "quadriceps", "shoulders", "traps", "triceps"} - \
          {m for f in out["figures"].values() for r in f for m in r["muscles"]}
assert not missing, missing
json.dump(out, open("GymApp/Resources/BodyMap/body_map.json", "w"), separators=(",", ":"))
print({f: len(r) for f, r in out["figures"].items()})
