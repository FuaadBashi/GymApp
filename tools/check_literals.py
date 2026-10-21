"""Redesign R.7: no colour, padding, corner radius or fixed font size outside the tokens."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = [r"\.padding\((\.[a-zA-Z]+, )?\d", r"cornerRadius: \d", r"\.system\(size: \d", r"Color\((red|white):"]
bad = []
for f in (ROOT / "GymApp").rglob("*.swift"):
    if f.name == "Tokens.swift":
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if any(re.search(r, line) for r in RULES):
            bad.append(f"{f.relative_to(ROOT)}:{n}: {line.strip()}")
# R.8: the studio's CSS and JS take colours and font sizes from tokens.css.
WEB = [r"#[0-9a-fA-F]{3,8}\b", r"rgba?\(", r"font-size: ?\d+px"]
for f in (ROOT / "studio/web/style.css", ROOT / "studio/web/app.js"):
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if any(re.search(r, line) for r in WEB):
            bad.append(f"{f.relative_to(ROOT)}:{n}: {line.strip()[:120]}")
print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
