"""Draw the Bashi Gym mark (redesign card R.11) as the app icon and the studio's icons.

Usage: python3 tools/build_icon.py   (needs Pillow; macOS iconutil for the .icns)
The mark: a black B on volt, its stem drawn as the end of a barbell (collar and plate).
Colours come from design/tokens.json. Same geometry as the brand board's 64-unit SVG.
"""
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / "design/tokens.json").read_text())["color"]


def mark(size: int, rounded: bool) -> Image.Image:
    s = size / 64
    volt = TOKENS["accent"]
    img = Image.new("RGB" if not rounded else "RGBA", (size, size), volt if not rounded else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=15 * s, fill=volt)
    black = "#000000"
    d.rounded_rectangle([9 * s, 22 * s, 14 * s, 42 * s], radius=2 * s, fill=black)    # plate
    d.rounded_rectangle([15 * s, 26 * s, 19 * s, 38 * s], radius=1.5 * s, fill=black)  # collar
    w = 5.5 * s
    bowls = ((15, 36), (32, 38))   # top y and the x where each bowl starts to curve
    for top, right in bowls:       # solid outline of each bowl
        y0, y1 = top * s - w / 2, (top + 17) * s + w / 2
        r = (y1 - y0) / 2
        d.rectangle([24 * s - w / 2, y0, right * s, y1], fill=black)
        d.ellipse([right * s - r, y0, right * s + r, y1], fill=black)
    for top, right in bowls:       # then cut the two counters out
        y0, y1 = top * s + w / 2, (top + 17) * s - w / 2
        r = (y1 - y0) / 2
        d.rectangle([24 * s + w / 2, y0, right * s, y1], fill=volt)
        d.ellipse([right * s - r, y0, right * s + r, y1], fill=volt)
    return img


def main() -> None:
    iconset = ROOT / "GymApp/BrandAssets.xcassets/BashiIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    (iconset.parent / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
    mark(1024, rounded=False).save(iconset / "BashiIcon-1024.png")   # iOS rounds the corners itself
    (iconset / "Contents.json").write_text(json.dumps({"images": [{"filename": "BashiIcon-1024.png", "idiom": "universal",
                                                                    "platform": "ios", "size": "1024x1024"}],
                                                        "info": {"author": "xcode", "version": 1}}, indent=1) + "\n")
    web = ROOT / "studio/web/favicon.png"
    mark(64, rounded=True).save(web)
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "AppIcon.iconset"
        folder.mkdir()
        for px in (16, 32, 128, 256, 512):
            mark(px, rounded=True).save(folder / f"icon_{px}x{px}.png")
            mark(px * 2, rounded=True).save(folder / f"icon_{px}x{px}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(folder), "-o", str(ROOT / "studio/launcher/AppIcon.icns")], check=True)


if __name__ == "__main__":
    main()
