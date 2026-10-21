"""tools/build_tokens.py (redesign card R.2): colour parsing and both outputs."""
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_tokens", ROOT / "tools/build_tokens.py")
bt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bt)


class TokenTests(unittest.TestCase):
    def test_colours_parse_from_hex_and_rgba(self):
        self.assertEqual(bt.rgba("#C7F242"), (199, 242, 66, 1.0))
        self.assertEqual(bt.rgba("rgba(255,255,255,0.08)"), (255, 255, 255, 0.08))
        with self.assertRaises(ValueError):
            bt.rgba("volt")

    def test_both_outputs_carry_every_colour(self):
        tokens = json.loads((ROOT / "design/tokens.json").read_text())
        swift, css = bt.swift(tokens), bt.css(tokens)
        for name in tokens["color"]:
            self.assertIn(f"static let {name} = Color(", swift)
            self.assertIn(f"--color-{bt.kebab(name)}:", css)
        self.assertIn("--radius-card: 16px;", css)
        self.assertIn("static let workoutControl: CGFloat = 56", swift)
