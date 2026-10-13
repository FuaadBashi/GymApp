# Studio S2: progression replay

Implemented on 14 October 2026, with commit and push authorised by the owner. No phone changes.
The user requested Rule Lab completion and explicitly asked to retain the notebook.

## Behaviour

- Compare five progression/deload rules, using each completed workout and earlier
  exercise exposures to compute its next target. Future loads never teach earlier steps.
- Reset progression after a training break. Use captured workout rep ranges when
  available, otherwise an explicit configurable fallback. Estimate entered-unit load
  steps from earlier logs and show their source.
- Report plateau-proxy precision, recall and balanced accuracy for fully observed
  windows, with a separate later-session holdout. Show exact attempted-target outcomes
  and conditional raised-target misses. Missing follow-up and missing RIR are unscored.
- Filter by exercise and inspect paginated targets and reasons. Open the original
  workout from a replay row. Explain observational limitations; declare no causal winner
  and send no automatic recommendations to the phone.
- Validate settings before atomically saving. Keep the last valid backup loaded when
  an incoming copy is incomplete or invalid.
- Retain editable local notebooks and metric publishing. Freeze the dashboard snapshot
  shared with notebooks, preserve existing files, label stale metrics and stop editor
  processes when the Studio server exits. Ask is deferred.

## Validation

48 Python tests pass. Coverage includes future-data isolation, kg/lb and assisted loads,
break resets, historical rep-range snapshots, effort gates, censored outcomes, API
pagination, invalid settings, invalid backups, notebook preservation and immutable
tables. JavaScript syntax and Git whitespace checks are required before handoff.

The replay describes observed workouts; it does not simulate the gains from an
unfollowed training programme. Small or overlapping outcome samples are not proof
that one rule causes better progress.
