# Phase 2 additions: protection, notes and exercise media

User-authorised 11 October 2026, before phase 3. Card 2.9 is being handled separately;
do not edit its ActivityKit implementation. No commits or pushes without a request.

## Verified delivery, 11 October

- [x] A1 implemented; backup/restore/failure/retention tests pass and recovery screen inspected.
- [x] A2 implemented; migration/math/draft tests pass, simulator notes and labels survive termination/relaunch.
- [x] A3 playback system and initial exact barbell bench/back squat assets implemented; bundled paths tested and squat still/play/stop inspected.

Full suite: **114 tests in 15 suites passed** (`/tmp/gymapp-additions-tests.log`). Final
backup-date presentation build also succeeded (`/tmp/gymapp-additions-build.log`).
`git diff --check` passed. Tests and screenshots used an isolated simulator and a
read-only copy of the original history; original training data was preserved.

Remaining: curate more exact exercise variants; choose an external backup folder on
the real phone; physical-device full-disk/termination/cloud-provider failure drills and
pointer hover/Reduce Motion checks. Local copied-file verification does not confirm a
cloud server upload. Phase 3 has not started. The user authorised committing all pending
work on 11 October; these additions are recorded with the phase-2 closure.

## A1: Saving and recovery

**Goal:** every successful edit, including an unfinished workout, has a verified local
recovery copy; backup failures are visible and independent of primary saves.

**Files:** Database/AppDatabase.swift, Services/RecoveryStore.swift,
Features/Settings/RecoveryView.swift, SettingsView.swift, App/AppEnvironment.swift,
Services/MetadataDraft.swift, RecoveryTests.swift.

**Steps:** FULL synchronous SQLite writes; transaction observer captures every changed
commit using SQLite backup (not a raw WAL file copy), validates integrity/foreign keys,
and publishes by rename only after validation. Failed/rolled-back writes do not replace
good copies. Retain latest 30 plus newest per month; preserve safety copies separately.
Settings shows local/external timestamps, pending/error state, folder selection, retry,
sharing full backups and restore preview. External copies are hash checked and opened
before success. A cloud-provider upload cannot be independently confirmed by local copy.
Restore is staged, checked/migrated before replacing live data on next launch, and makes
a safety copy first. Back up the previous schema before migration. Never erase a broken
live database to get the app open. Retry external copy on launch, each edit and manually.

**Tests:** unfinished sets/entered units survive backup; rollback leaves last good copy;
corrupt restore leaves live data untouched; restored unfinished workout matches original;
pre-restore safety copy contains displaced data. Add retention and destination-failure
checks. Device-only checks (full disk, app termination during backup, cloud availability)
remain explicitly unverified until run on a device.

## A2: Notes and labels

**Files:** Schema.swift (v2), Records.swift, Domain/SetAnnotation.swift,
WorkoutWrites.swift, Features/Workout/WorkoutMetadataEditor.swift, ExerciseCard.swift,
FocusView.swift, SummaryView.swift, exercise history display, SetMetadataTests.swift.

**Rules:** `max rep` = 0 reps in reserve; MR −1/−2/−3 = 1/2/3 reps in reserve,
confirmed by the user. Store as nullable repsInReserve, not RPE. Keep actual reps/load.
Deload, injury and form are independent annotations and may coexist with reserve labels
and existing set types. Warm is the existing warm-up type. Reserve/annotations do not
invent extra reps or change existing volume, hard-set, PR or plateau calculations.
Max rep does not imply a failed rep. Show selectable annotations and explicit set type.

Add nullable set note and reserve plus JSON tags by migration; existing values survive.
Use the existing workoutExercise.note for session-specific exercise notes, keeping it
separate from stickyNote. Autosave metadata with a persistent local draft and ordered
writes; display/retry failures instead of dismissing unsaved edits. Clear session notes,
reserve and annotations on prefill/add-set so injury/effort is not copied as today's fact.
Show saved metadata in workout, summary and exercise history. Include all in full backups.
CSV coverage is added when the CSV export is built. Set load/reps/type edits also use
durable drafts through ActiveWorkoutModel+DurableEdits.swift; summary notes and effort
use the same mechanism. On launch replay only drafts not yet committed. On restore,
archive displaced drafts alongside the displaced database instead of replaying them
against the restored history.

**Tests:** migration preserves v1 history; note/tag/reserve round trip; invalid reserve
rejected; warm excludes volume as before; annotations don't change actual-set maths;
new session doesn't inherit prior annotations; metadata survives backup and restore.

## A3: Offline exact exercise media

**Files:** Services/ExerciseMedia.swift, shared ExerciseMediaView.swift,
Resources/ExerciseMedia/, tools/ media acquisition script and provenance manifest;
ExerciseCard.swift, FocusView.swift and ExerciseDetailView.swift; media lookup tests.

**Steps:** curate explicit exact exercise-ID mappings, no fuzzy-name substitution.
Use licensed real footage with source/author/license/change attribution. Bundle video
and extracted still; play on tap and supported pointer hover; stop/reset on exit and
respect Reduce Motion. Show instructions and an honest missing-media state. Start with
verified assets actually obtained, then expand coverage; never label the whole library
covered. Do not reuse free-exercise-db images until provenance is verified.

**Done when:** the mapped asset visually matches equipment/variant, still and demo work
without network, attribution is shown, and mismatched/custom exercises get no substitution.

Finish each section with meaningful tests, simulator UI checks and a handoff update.
