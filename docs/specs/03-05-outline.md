# Phases 3–5: outline

These phases are outlined, not specified. Each gets a full spec, with cards in the format of
phases 0–2, once the phase before it is closed: by then the data layer and screens they build
on exist and have been used. **Do not build from this file.**

## Phase 3: History and analytics

**History tab**
- A month calendar: a dot per workout day, coloured by the program day (or neutral for
  JEFIT/ad hoc), weeks starting on the `weekStartsOn` setting.
- The week's sessions against the active program's `sessionsPerWeekGoal`.
- Every finished workout since August 2022, grouped by week, newest first. Each row has the
  title, date, duration, set count and volume.
- Workout detail: every exercise and set, volume, duration, records set in it, note and
  effort.
- Editing a past workout's sets, notes and title, with every derived figure recomputing
  (rulebook §10). Deleting asks first.

**Exercise page: Charts and Records** (replacing the phase 1 placeholder)
- Swift Charts line charts over time, with ranges 3M, 1Y and All:
  - best estimated 1RM per session;
  - heaviest load per session;
  - session volume.
- A records table (rulebook §5):
  - heaviest load;
  - best estimated 1RM;
  - rep record per load (most reps at each distinct load);
  - best session volume.

  Each has its date and a link to the workout.
- All figures through `TrainingMath`; nothing stored.

**Progress tab**
- Weekly volume, sessions and training time for the last 12 weeks, as bars, each against
  the week before.
- Hard sets per muscle per week (rulebook §6), drawn on a front and back body map, plus a
  list with target ranges. The body-map artwork needs a licensed or hand-drawn SVG; decide
  before specifying.
- Recent records: the last 20.
- Consistency: sessions per week over 12 months, as a heat strip.
- Body: weight and body-fat charts from `bodyEntry`; add an entry; measurements table.

**Likely cards:** history queries and the calendar; workout detail and editing; exercise
charts; records; the Progress dashboard; body stats.

**Checks to specify:** chart values for a few exercises must equal hand calculations from
the export; JEFIT's `EXERCISE RECORDS` should match where JEFIT_EXPORT.md trap 6 says it
does (155 of 195).

## Phase 4: Import, export and backups

- **Full backup:** `writer.backup(to:)` into a dated `.sqlite` file, shared with the share
  sheet.
- **Restore:** pick a backup, validate it (it opens, it migrates, and the counts read back),
  then back up the current data, then replace it. Show before-and-after counts.
- **CSV export of every set,** one row per set: date, workout, exercise, set number, type,
  load, unit, reps, RPE, workout note. Columns are compatible with Strong's export, so other
  apps can read it.
- **Automatic backup after each finished workout** to a folder chosen once with
  `UIDocumentPickerViewController` in folder mode, kept with a security-scoped bookmark.
  Keep the last 30 plus one per month (decision #9). Verify this works with iCloud Drive on
  a free Apple ID.
- **Re-importing JEFIT** stays available and idempotent.

**Check to specify:** a backup taken on the phone restores onto a fresh simulator install
with identical counts and identical figures on three exercise pages. This test must be run,
not assumed.

## Phase 5: On the phone

- **Signing:** a free Apple ID added in Xcode (by Fuaad), Developer Mode on the iPhone, and
  the team selected for both targets. Bundle ids are `com.fuaadshurie.GymApp` and
  `.GymAppWidgets`.
- **Expiry warning (decision #3):**
  - read the expiry date from `embedded.mobileprovision` (the plist between `<?xml` and
    `</plist>`, key `ExpirationDate`);
  - show a banner on Train two days before;
  - schedule a local notification for the same moment.
- **Check on the device:**
  - the rest alert with the phone locked and music playing;
  - the Live Activity (it may not be allowed on a free account; the alert is enough if not);
  - the backup folder in iCloud Drive.
- First real sessions alongside JEFIT, then JEFIT is dropped.
