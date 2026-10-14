# GymApp Studio

Offline analysis of GymApp backups on the Mac: dashboards, a rule lab for weight
progression, a Lab of notebooks for your own code, and optional AI over figures the code
has already computed. See [docs/STUDIO_PLAN.md](../docs/STUDIO_PLAN.md).

It only ever **reads** a backup (the format is in [docs/EXPORT_FORMAT.md](../docs/EXPORT_FORMAT.md)),
copying it first, so the phone's data is never touched. It finds the newest backup in an
iCloud Drive folder whose name contains "GymApp", or in `data/backups/`.

## Run it

```bash
cd studio
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
launcher/build.sh          # makes ~/Applications/GymApp Studio.app
```

Then double-click **GymApp Studio** in Applications. It starts the local server (port 8765,
this Mac only), opens its own window, and stops the server when you quit. Without the app:
`.venv/bin/python -m gymstudio`.

## Layout

| Path | What |
|---|---|
| `gymstudio/rulebook.py` | The training rulebook, a line-for-line port of `TrainingMath.swift` |
| `gymstudio/data.py` | Loads a backup: exercises, finished workouts, completed sets, body weight |
| `gymstudio/stats.py` | Records, per-session points and muscle sets, computed as the app does |
| `gymstudio/watch.py` | Finds and follows the newest backup |
| `gymstudio/analysis.py` | Plateaus, next-session targets, weak points, progress rate, breaks, increments, the 1RM formula lab, muscle volume and balance |
| `gymstudio/server.py` | Local JSON API and the web interface (`web/`, charts by Apache ECharts, bundled) |
| `gymstudio/progression.py` | Five progression/deload rules replayed using only history available at each decision |
| `gymstudio/lab.py`, `gymstudio/notebook.py`, `notebooks/` | Private notebook editor, immutable data tables and saved custom metrics |
| `gymstudio/ask.py` | Ask: Claude or a local Ollama model answering through the studio's tools; summaries-only or full-access mode; every figure in an answer is checked against what the tools returned |
| `launcher/` | The native Mac window (`main.swift`), its icon, and `build.sh` |
| `tests/` | The Swift tests' expected values, a synthetic backup built from the app's schema, and real-history checks against `GymAppTests/Fixtures/phase3_expected.json` (skipped without a backup in `data/`) |

## Tests

```bash
cd studio && python3 -m unittest discover -s tests -t .
```

## Rule Lab and notebooks

Rule Lab compares double progression with a time-based plateau, two or three stalled
exposures, linear progression with three missed exposures, and double progression at
two reps left. Filter by exercise, choose the outcome window and later-session holdout,
inspect individual targets, and click a row to see its original workout.

Scores describe the recorded history. They cannot prove that an untried rule would
have produced better gains. Exact targets are scored only when attempted; incomplete
follow-up and missing effort remain unscored. Historical rep ranges use workout
snapshots where available; otherwise the configured fallback. Load increments are
estimated from earlier logged loads. Nothing is automatically promoted to the phone.

Notebooks opens an editable marimo training explorer. Existing notebook files in
`~/Library/Application Support/GymApp Studio/Notebooks` are preserved. Use `load_context()`
for the dashboard's frozen snapshot, settings and read-only tables, and
`context.publish(...)` to save a local metric on Overview. Metrics from an older snapshot
are labelled. The editor runs Python locally and stops when Studio's server quits.

Ask remains deferred. Current validation: 48 Studio tests, including replay causality,
unit handling, breaks, RIR abstention, API validation and notebook preservation.
