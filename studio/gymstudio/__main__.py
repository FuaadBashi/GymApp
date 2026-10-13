"""Run the studio: `python -m gymstudio [--port 8765] [--backup FOLDER] [--no-browser]`."""
import argparse
import threading
import webbrowser
from pathlib import Path

import uvicorn

from .server import app, start_watching


def main() -> None:
    ap = argparse.ArgumentParser(prog="gymstudio")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--backup", action="append", type=Path, help="a folder of backups (repeatable)")
    ap.add_argument("--no-browser", action="store_true")
    a = ap.parse_args()
    start_watching(a.backup)
    if not a.no_browser:
        threading.Timer(1.0, lambda: webbrowser.open(f"http://127.0.0.1:{a.port}/")).start()
    uvicorn.run(app, host="127.0.0.1", port=a.port, log_level="warning")


if __name__ == "__main__":
    main()
