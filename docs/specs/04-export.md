# Phase 4: Import, export and backups (reconciled)

**Specified 12 October 2026.** Most of the outline was delivered early by the post-phase-2
additions ([02a-additions.md](02a-additions.md)): full `.sqlite` backups shared with the share
sheet, validated staged restores with a safety copy, automatic verified copies after every
change, an external folder kept with a security-scoped bookmark, retention (latest 30 plus
one per month), and idempotent JEFIT re-import. This phase adds what is left: the CSV
export, the documented export format the separate analysis tool reads (decision #36), and the
round-trip check the outline asked for.

## Card 4.1: CSV export of every set

**Files:** create `GymApp/Data/CSVExport.swift`, `GymAppTests/CSVExportTests.swift`; change
`Features/Settings/SettingsView.swift` (a "Export sets as CSV" button in Data, shared with the
share sheet).

- One row per completed set of every finished workout, oldest workout first, then exercise
  position, then set position.
- Columns, in order. The first twelve are Strong's export columns, so other apps read it:
  `Date` (local `yyyy-MM-dd HH:mm:ss`), `Workout Name`, `Duration` (`1h 5m` / `45m`),
  `Exercise Name`, `Set Order` (1-based, warm-ups `W`, drop rows `D`), `Weight` (as entered,
  empty for reps-only), `Reps`, `Distance` (empty), `Seconds` (0), `Notes` (set note),
  `Workout Notes`, `RPE` (empty unless set).
  Then GymApp's own: `Weight Unit`, `Set Type`, `Reps In Reserve`, `Labels` (`;`-joined),
  `Exercise Note` (the session's exercise note), `Load Mode`, `Equipment`, `Primary Muscles`
  (`;`-joined), `Effort`, `Workout ID`, `Exercise ID`.
- RFC 4180 quoting: fields containing `,`, `"`, CR or LF are quoted, `"` doubled. Line ends
  `\r\n`. UTF-8 without BOM.
- Weights are written as entered with their unit (rulebook §1); a reader converts.
- File name `GymApp-sets-<yyyy-MM-dd>.csv` in the temporary directory.

**Tests:** header exact; a warm-up, a drop row, an assisted (negative) load, a reps-only set,
a note with a comma and a quote, and an unfinished workout (excluded). With the real export:
row count equals the SQL count of completed sets in finished workouts (7,751 after import).

## Card 4.2: Export format and round trip

**Files:** create `docs/EXPORT_FORMAT.md`; add tests to `GymAppTests/RecoveryTests.swift`.

- `EXPORT_FORMAT.md` documents both exports for anyone building on them (the planned
  offline analysis tool first): the CSV columns above, and the `.sqlite` backup's tables and
  columns, which rules derive which figures (pointing at the rulebook), and that derived
  figures are never stored.
- **Round trip:** a test imports the real export, takes a backup with `RecoveryStore`,
  restores it into a fresh database, and asserts identical row counts for every table and
  identical `ExerciseStats.records` for bench press, squat and deadlift.
- Phase close: README, ROADMAP and HANDOFF.

**Out of scope:** importing Strong or other apps' CSVs.
