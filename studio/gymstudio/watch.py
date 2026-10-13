"""Finding and following the newest backup.

The phone copies a verified backup into the chosen folder after every change; with that
folder in iCloud Drive it appears on this Mac by itself. The studio polls the folder (no
extra dependency) and reloads when a newer, fully downloaded backup lands.
"""
from __future__ import annotations

import time
from pathlib import Path
from typing import Callable, Optional

from .data import newest_backup

ICLOUD = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs"


def default_folders() -> list[Path]:
    """Where to look, in order: an iCloud Drive folder named like the app's, then data/backups."""
    repo = Path(__file__).resolve().parents[2]
    found = [p for p in ICLOUD.glob("*") if p.is_dir() and "gymapp" in p.name.lower().replace(" ", "")]
    return found + [repo / "data/backups"]


def latest(folders: Optional[list[Path]] = None) -> Optional[Path]:
    """The newest backup across the folders; iCloud placeholders (.icloud) are skipped."""
    best = None
    for folder in folders or default_folders():
        if not folder.exists():
            continue
        candidate = newest_backup(folder)
        if candidate is None:
            # A manually copied backup (e.g. phone-2026-10-13.sqlite) counts too.
            others = sorted(folder.glob("*.sqlite"), key=lambda p: p.stat().st_mtime)
            candidate = others[-1] if others else None
        if candidate and (best is None or candidate.stat().st_mtime > best.stat().st_mtime):
            best = candidate
    return best


def follow(on_new: Callable[[Path], None], folders: Optional[list[Path]] = None, interval: float = 10.0,
           stop: Callable[[], bool] = lambda: False) -> None:
    """Calls on_new with each newer backup, after its size has stopped changing."""
    seen = None
    while not stop():
        path = latest(folders)
        if path and path != seen:
            size = path.stat().st_size
            time.sleep(1.0)
            if path.stat().st_size == size:
                seen = path
                on_new(path)
        time.sleep(interval)
