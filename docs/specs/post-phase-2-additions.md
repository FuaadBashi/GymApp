# Additions requested after phase 2

Requested 11 October 2026. Requirements; implementation cards are in [02a-additions.md](02a-additions.md).
Schedule immediately after phase 2 and before phase 3. This includes the workout
protection and backup/recovery work previously assigned to phase 4. Specify these
additions as their own cards next, once phase 2 closes; do not defer them until after
history and analytics. Existing phase 2 work and its unresolved acceptance check
are unchanged.

## Exact exercise images and demonstrations

- Show a still image of the exact exercise variant, matching equipment, body position,
  grip and movement. A similar exercise must not be presented as an exact match.
- On hover, show how it is performed. On iPhone, provide a discoverable touch action
  to play the demonstration; choose tap or press-and-hold when specifying the UI.
- Real-person footage, generated visuals or freely reusable public assets are acceptable.
  Verify source rights and retain attribution where required. Generated demonstrations
  must be checked for correct movement before use.
- Choose sources and inspect their coverage before promising library-wide support.
  An exercise without a verified match gets an honest placeholder.
- Stills and demonstrations must work offline through bundled or downloaded assets;
  the workout must remain usable when an asset is unavailable.
- Respect reduced-motion settings and provide written instructions alongside the media.

## Notes and set labels

- Allow free-text notes on individual sets and exercises within a workout, including
  corrections in history. Keep persistent exercise cues separate from a note about
  one particular session. Existing sticky exercise notes continue to work.
- Offer these user-requested labels: **deload, max rep, MR - 1, MR - 2, MR - 3,
  injury, form, warm**. Keep existing working, warm-up, drop and failed semantics.
- Confirmed: max rep means 0 reps left in reserve; MR - 1/2/3 means 1/2/3 left.
  Store reserve separately from actual reps and RPE. Deload/injury/form are annotations
  that can coexist; warm maps to the existing warm-up type. Max rep does not imply failure.
- Specify each label's effect on volume, hard sets, records and plateau checks in the
  training rulebook before changing calculations. Historical sets retain their meaning.
- Save notes and label edits locally as they are made, including offline. Preserve
  them in full backup/restore and exports, without truncating text or losing scope.

## Workout durability and recovery

The requirement covers every user edit, not just completed sets or finished workouts:
loads, reps, types/labels, notes, exercise changes, programs and workouts in progress.
Connectivity must not determine whether work is saved.

The post-phase-2 durability cards must specify and verify:

- Transactional local writes and recovery after termination/relaunch, with clear save
  failures and recoverable unsaved edits. Never display an unsuccessful write as saved.
- Versioned local recovery copies/checkpoints covering unfinished sessions and edits,
  as well as the existing backup after every finished workout. Set the cadence explicitly.
- Independent backup outside the app's container to a user-chosen destination, plus
  manual portable export. Local copies alone do not survive phone loss or app deletion.
- When the destination or network is unavailable, retain local recovery data, mark the
  external backup pending, and retry when available. Distinguish saved locally, backed
  up locally, pending external backup and verified external backup.
- Preserve the last known-good backups; validate integrity, schema compatibility and
  restored contents before reporting success. Failed or incomplete copies must not
  replace good backups or trigger retention deletion.
- Retention based on decision #9 (last 30 plus monthly copies), with suitable recovery
  versions for in-progress edits and a pre-restore/pre-migration safety copy.
- Recovery from accidental changes/deletion and a documented restore flow that protects
  the current database before replacement.
- Run failure checks: kill mid-session/write/backup, offline edits, unavailable folder,
  low/full storage, interrupted export, corrupt backup, failed migration and restore
  onto a fresh install. Compare sets, values, notes, labels and program state, not just
  row counts; a restore must preserve an unfinished workout too.

No implementation can promise zero loss under every failure. Define the verified
recovery window and show the latest successful independent backup so the user knows
what is protected. Device signing expiry must never be solved by deleting the app.
