"""The training rulebook (docs/TRAINING_RULEBOOK.md) in Python.

A line-for-line port of GymApp/Domain/TrainingMath.swift. The two must agree on every
figure: tests/test_rulebook.py repeats the Swift tests' expected values, and
tests/test_against_app.py checks whole exercises against the app's own test fixtures.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable, Optional

KG_PER_LB = 0.45359237

LOAD_MODES = ("total", "perHand", "perSide", "bodyweightPlus", "repsOnly")
SET_TYPES = ("working", "warmUp", "failed", "drop")


@dataclass(frozen=True)
class PastSet:
    """A set as the maths sees it: kg already converted, a reps-only set carrying 0."""
    kg: float
    reps: int
    type: str = "working"


def to_kg(load_hundredths: Optional[int], unit: str) -> float:
    """§1: loads are stored as entered (hundredths plus unit); every sum happens in kg."""
    value = (load_hundredths or 0) / 100
    return value if unit == "kg" else value * KG_PER_LB


def volume_multiplier(load_mode: str) -> float:
    return 2.0 if load_mode in ("perHand", "perSide") else 1.0


def e1rm_epley(kg: float, reps: int) -> float:
    """§4: Epley. A single rep is the load itself."""
    return kg if reps <= 1 else kg * (1 + reps / 30)


def displayable_e1rm(kg: float, reps: int, load_mode: str) -> Optional[float]:
    """§4: only for 1–12 reps; body-weight loads have no honest 1RM."""
    if load_mode in ("bodyweightPlus", "repsOnly") or kg <= 0 or not 1 <= reps <= 12:
        return None
    return e1rm_epley(kg, reps)


def calculation_kg(kg: float, load_mode: str, body_weight_kg: Optional[float]) -> Optional[float]:
    """§2: without a body weight a body-weight set drops out of volume."""
    if load_mode in ("total", "perHand", "perSide"):
        return kg
    if load_mode == "bodyweightPlus":
        return None if body_weight_kg is None else max(body_weight_kg + kg, 0.0)
    return None


def volume_kg(sets: Iterable[PastSet], load_mode: str, body_weight_kg: Optional[float]) -> float:
    """§6: Σ load × reps × multiplier, warm-ups excluded (§3); drop segments count."""
    total = 0.0
    for s in sets:
        if s.type == "warmUp":
            continue
        load = calculation_kg(s.kg, load_mode, body_weight_kg)
        if load is None:
            continue
        total += load * s.reps * volume_multiplier(load_mode)
    return total


@dataclass(frozen=True)
class Bests:
    heaviest_kg: Optional[float] = None
    best_e1rm: Optional[float] = None


def bests(sets: Iterable[PastSet], load_mode: str) -> Bests:
    """§5: working and failed sets only; drop rows never set records."""
    if load_mode in ("bodyweightPlus", "repsOnly"):
        return Bests()
    counted = [s for s in sets if s.type not in ("warmUp", "drop") and s.reps > 0 and s.kg > 0]
    if not counted:
        return Bests()
    e1rms = [e for s in counted if (e := displayable_e1rm(s.kg, s.reps, load_mode)) is not None]
    return Bests(heaviest_kg=max(s.kg for s in counted), best_e1rm=max(e1rms) if e1rms else None)


def is_hard_set(set_type: str) -> bool:
    """§3/§6: warm-ups and drop rows (part of the set before) are not hard sets."""
    return set_type not in ("warmUp", "drop")


def e1rm_marzagao(kg: float, reps: int) -> float:
    """Load-dependent equation fitted on 303,494 near-failure sets (Marzagao 2026, arXiv
    2603.17495): 1RM = w·(1 + (r−1)^0.85 / (−2.55 + 4.58·ln w)). Used only in the formula
    lab; the app uses Epley until the lab shows this fits better."""
    if reps <= 1:
        return kg
    denominator = -2.55 + 4.58 * math.log(kg)
    if denominator <= 0:   # very light loads, outside the fitted range
        return e1rm_epley(kg, reps)
    return kg * (1 + (reps - 1) ** 0.85 / denominator)


def e1rm_brzycki(kg: float, reps: int) -> float:
    return kg if reps <= 1 else kg * 36 / (37 - reps)
