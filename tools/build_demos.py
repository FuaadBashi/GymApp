"""Build the bundled demonstration images (card 10.1) from tools/demo_map.json.

Usage: python3 -I tools/build_demos.py

Sources, all openly licensed and credited in the manifest:
- Everkinetic (https://github.com/everkinetic/data, CC BY-SA 4.0), pinned below: two poses
  per exercise, rest and effort, as illustrations.
- wger (https://wger.de, per-image licence and author from its API): photos.

Writes GymApp/Resources/Demos/: the images, downscaled to 480 px, and demos.json with every
asset's source, author and licence, and the exercise → asset map. A change to the pinned
commit or to an image needs another look at the pictures before shipping.
"""
import json
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "GymApp/Resources/Demos"
EVERKINETIC = "446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6"
EK_RAW = f"https://raw.githubusercontent.com/everkinetic/data/{EVERKINETIC}"
EK_LICENCE = "https://creativecommons.org/licenses/by-sa/4.0/"
WGER_LICENCES = {1: ("CC BY-SA 3.0", "https://creativecommons.org/licenses/by-sa/3.0/"),
                 2: ("CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
                 3: ("CC0", "https://creativecommons.org/publicdomain/zero/1.0/"),
                 4: ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")}
UA = {"User-Agent": "GymApp-demos/1.0"}


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def ek_image(item: dict, number: int, pose: str) -> bytes:
    """Everkinetic keeps poses in src/images-web by slug (sometimes spelt 'bicep' for
    'biceps'), and some only in dist/png by number."""
    slug = item["name"]
    for variant in dict.fromkeys([slug, slug.replace("biceps", "bicep"), slug.replace("curls", "curl"),
                                  slug.replace("crunch", "crunches")]):
        try:
            return get(f"{EK_RAW}/src/images-web/{variant}-{number}.png")
        except urllib.error.HTTPError:
            continue
    return get(f"{EK_RAW}/dist/png/{item['id_num']}-{pose}.png")


def full_frames(data: bytes) -> list[tuple[bytes, str]]:
    """A still WebP as itself; an animated one as its frames that cover the whole canvas
    (the others are deltas blended over the frame before), so they make clean poses."""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.webp"
        src.write_bytes(data)
        info = subprocess.run(["webpmux", "-info", str(src)], capture_output=True, text=True, check=True).stdout
        if "animation" not in info:
            return [(data, ".webp")]
        canvas = info.split("Canvas size:")[1].split()[0::2][:2]
        frames = []
        for line in info.splitlines():
            parts = line.split()
            if parts and parts[0].rstrip(":").isdigit() and parts[1:3] == canvas:
                out = Path(tmp) / f"f{parts[0].rstrip(':')}.webp"
                subprocess.run(["webpmux", "-get", "frame", parts[0].rstrip(":"), str(src), "-o", str(out)], check=True,
                               capture_output=True)
                frames.append((out.read_bytes(), ".webp"))
        return frames


def shrink(data: bytes, suffix: str, target: Path, fmt: str) -> None:
    """Downscale to 480 px on the long side with macOS sips, in PNG (drawings) or JPEG (photos)."""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / ("in" + suffix)
        src.write_bytes(data)
        if suffix == ".webp":   # decode with libwebp's dwebp, which reads every WebP variant
            png = Path(tmp) / "in.png"
            subprocess.run(["dwebp", "-quiet", str(src), "-o", str(png)], check=True)
            src = png
        args = ["sips", "-Z", "480", "-s", "format", fmt] + (["-s", "formatOptions", "70"] if fmt == "jpeg" else [])
        subprocess.run(args + [str(src), "--out", str(target)], check=True, capture_output=True)


def main() -> None:
    demo_map = json.loads((ROOT / "tools/demo_map.json").read_text())["map"]
    OUT.mkdir(parents=True, exist_ok=True)
    ek = {x["name"]: x for x in json.loads(get(f"{EK_RAW}/exercises.json"))}
    wger_images = json.loads(get("https://wger.de/api/v2/exerciseimage/?limit=1000"))["results"]
    by_wger: dict[int, list] = {}
    for image in wger_images:
        if not image.get("is_ai_generated"):
            by_wger.setdefault(image["exercise"], []).append(image)

    assets, mapping = {}, {}
    for exercise_id, entry in sorted(demo_map.items()):
        if entry["source"] == "everkinetic":
            item = ek[entry["ref"]]
            key = "ek-" + item["name"]
            if key not in assets:
                files = []
                for i, pose in ((1, "relaxation"), (2, "tension")):   # 1 = rest, 2 = effort
                    name = f"{key}-{i}.png"
                    shrink(ek_image(item, i, pose), ".png", OUT / name, "png")
                    files.append(name)
                assets[key] = {"files": files, "kind": "illustration", "title": item["title"],
                               "author": "Everkinetic", "license": "CC BY-SA 4.0", "licenseURL": EK_LICENCE,
                               "source": f"https://github.com/everkinetic/data/tree/{EVERKINETIC}",
                               "changes": "Downscaled to 480 px"}
        else:
            images = sorted(by_wger[entry["ref"]], key=lambda i: (not i["is_main"], i["id"]))[:2]
            key = f"wger-{entry['ref']}"
            if key not in assets:
                files = []
                sources = []
                for image in images:
                    data, suffix = get(image["image"]), Path(image["image"]).suffix.lower()
                    sources += full_frames(data)[:2] if suffix == ".webp" else [(data, suffix)]
                for n, (data, suffix) in enumerate(sources[:2]):
                    name = f"{key}-{n + 1}.jpg"
                    shrink(data, suffix, OUT / name, "jpeg")
                    files.append(name)
                short, url = WGER_LICENCES[images[0]["license"]]
                assets[key] = {"files": files, "kind": "photo", "title": f"wger exercise {entry['ref']}",
                               "author": images[0]["license_author"] or "wger contributors", "license": short,
                               "licenseURL": url, "source": f"https://wger.de/en/exercise/{entry['ref']}/view-base",
                               "changes": "Downscaled to 480 px, JPEG"}
        mapping[exercise_id] = {"asset": key, **({"note": entry["note"]} if entry.get("note") else {})}

    manifest = {"_about": "Generated by tools/build_demos.py; do not edit by hand.", "assets": assets, "map": mapping}
    (OUT / "demos.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    size = sum(p.stat().st_size for p in OUT.iterdir())
    print(f"{len(mapping)} exercises, {len(assets)} assets, {size / 1e6:.1f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
