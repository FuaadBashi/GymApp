# Phase 6: the phone side of the studio

**Specified 14 October 2026.** The studio (studio/) proves rules and proposes changes; this
phase lets the phone record what the studio needs, receive its suggestions safely, and show
the JEFIT views still missing ([STUDIO_PLAN.md](../STUDIO_PLAN.md) sections 2 and 7).

## Card 6.1: Reps left in one tap

The rule lab can't score effort-based rules without reps in reserve, and the sheet is too
slow mid-session. Under the selected set's steppers, a row of chips: **Max · 1 · 2 · 3**
(0–3 reps left, rulebook-compatible with the existing `repsInReserve` column). Tapping one
writes it at once through `WorkoutWrites.setMetadata`, keeping the set's note and labels;
tapping the selected chip clears it. The row's existing label shows "Max rep" or "MR −n".
Same chips in focus mode.

**Done when:** a test sets and clears reserve without touching note or labels; the chips work
on the device.

## Card 6.2: Steps and weight from Apple Health

- HealthKit, read-only: daily step count and body mass. Entitlement and usage string added;
  permission asked from Settings → Apple Health, never at launch.
- Migration **v3**: table `healthDay(date TEXT PRIMARY KEY, steps INTEGER, weightHundredths
  INTEGER, weightUnit TEXT, source TEXT NOT NULL DEFAULT 'health')`. Daily totals for the last
  365 days are upserted on launch and on return to the foreground. `RecoveryStore.inspect`
  accepts v1, v1+v2 and v1+v2+v3 backups.
- `BodyQueries.weightKg` also reads `healthDay` (latest on or before the day, either source),
  so body-weight volume uses scale weights.
- Progress tab: a steps card (last 30 days, daily average, this week vs last).
- Studio: steps and Health weight load from the backup; Overview shows steps.

**Done when:** migration and query tests pass; on the device, Settings shows Health access and
the Progress tab shows real steps.

## Card 6.3: Studio suggestions inbox

- The studio writes `GymApp-suggestions.json` into the backup folder: a list of
  `{id, created, kind, title, detail, reason, exerciseId?, dayId?, change}` where kind is
  `target` (weight × reps for the next session), `swap` (replace an exercise in a day) or
  `note` (advice with no change). Every item carries its reason and the rule that made it.
- The app reads the file from the bookmarked backup folder on launch, foreground and pull
  to refresh. Train shows a "Studio suggestions (n)" card; each suggestion opens with the
  reason and **Accept** / **Dismiss**. Nothing changes until Accept.
- Accept: `target` stores an accepted target that the workout screen shows above that
  exercise's sets ("Studio: 52.5 kg × 8", with "Fill sets"); `swap` changes the day item
  through `ProgramWrites`; `note` is just marked read. Decisions are stored (table
  `studioDecision`, migration v3) and written back to `GymApp-suggestion-decisions.json`
  so the studio knows what was accepted.
- Studio: a Suggestions page to draft, review and publish them, from plateau checks, the
  weak-point check and next targets, plus free text.

**Done when:** parsing, accept and dismiss are tested; a published suggestion appears on the
device and an accepted target shows in the workout.

## Card 6.4: Tap a chart point

On the exercise Progress chart, tapping near a point selects that session and shows its date
and sets under the chart, with a link to the workout (JEFIT parity).

## Card 6.5: Recovery and movement patterns

- **Recovery**: per muscle, the hard sets of the last 72 hours weighted by time since (100%
  fresh after 72 h, linear), shown as the body map coloured fresh → worked, plus a list.
- **Movement patterns**: weekly best e1RM change for squat, hinge, horizontal push, vertical
  push, horizontal pull and vertical pull, over the last 8 weeks.

## Card 6.6: Recaps

Monthly and yearly recap from History: workouts, time, volume, sets, records set, most
trained muscle, longest weekly streak; a "Year in training" page for each year since 2022.

## Card 6.7: Phase close

Device checks, HANDOFF, README.
