# GymApp Studio

Offline analysis of GymApp backups on the Mac: dashboards, a rule lab for weight
progression, a Lab of notebooks for your own code, and optional AI over figures the code
has already computed. See [docs/STUDIO_PLAN.md](../docs/STUDIO_PLAN.md).

It only ever **reads** a backup (the format is in [docs/EXPORT_FORMAT.md](../docs/EXPORT_FORMAT.md)),
copying it first, so the phone's data is never touched. It finds the newest backup in an
iCloud Drive folder whose name contains "GymApp", or in `data/backups/`.

## Layout

| Path | What |
|---|---|
| `gymstudio/rulebook.py` | The training rulebook, a line-for-line port of `TrainingMath.swift` |
| `gymstudio/data.py` | Loads a backup: exercises, finished workouts, completed sets, body weight |
| `gymstudio/stats.py` | Records, per-session points and muscle sets, computed as the app does |
| `gymstudio/watch.py` | Finds and follows the newest backup |
| `tests/` | The Swift tests' expected values, a synthetic backup built from the app's schema, and real-history checks against `GymAppTests/Fixtures/phase3_expected.json` (skipped without a backup in `data/`) |

## Tests

```bash
cd studio && python3 -m unittest discover -s tests -t .
```
