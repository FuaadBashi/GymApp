# Phase 10: Demonstrations, form cues, the exercise page and the studio's look

**Specified 14 October 2026** from the owner's answers. Design rules: [DESIGN.md](../DESIGN.md).

Decisions:

- **Coverage target:** at least 80% of the exercises the owner has logged (155 of 193 on
  14 October) have a demonstration; the whole library is not a target.
- **Realistic first:** a real, openly licensed one-angle video where one exists (wger:
  78 videos for 46 exercises, CC BY-SA; 29 are already bundled). Everything else gets two-pose
  pictures, rest and effort, shown as a slow loop: **Everkinetic** illustrations (CC BY-SA 4.0)
  and **wger** images with a named licence and author. The free-exercise-db photos were the
  first plan but their source cannot be verified (decision #14), so they are not used; the
  owner chose licensed sources only. Animated 3D figures and two angles are out of scope: no
  free source exists, AI video is unreliable for lifting, and building a figure pipeline is a
  project of its own. A bought library remains an option for later (recorded in HANDOFF).
- **Size budget:** demonstrations stay under 60 MB in the app (photos about 30 KB each at
  480 px; videos re-encoded to 480 px, about 0.3–0.7 MB each).
- **Studio:** the web interface is restyled to feel like a native Mac app; no rewrite.

## Card 10.1: Demonstration sources

- `tools/build_demos.py` writes `GymApp/Resources/Demos/` from `tools/demo_map.json`: each
  mapped exercise's two poses downscaled to 480 px (Everkinetic pinned to commit
  446bb9a, images from `src/images-web` by slug, else `dist/png` by number; wger images from
  its API, with animated WebPs reduced to their full-canvas frames), and `demos.json` with
  every asset's source, author, licence and changes, and the exercise → asset map.
- Images whose provenance looks doubtful (commercial 3D-render style with no named author) are
  left out even when wger lists a licence.
- **Done when:** the build reports the size (13.8 MB on 14 October).

## Card 10.2: Demonstration twins

- `tools/demo_map.json`: a hand-checked map from logged exercises without a video to the
  picture showing the same movement on the same or close equipment, with a note when it is a
  close equivalent (a demonstration only; records and history are never merged, decision #28
  stands). Ambiguous names are left unmapped rather than guessed.
- **Done when:** coverage of logged exercises ≥ 80% (160 of 193, 82.9%, on 14 October: 22 by
  video, 138 by pictures).

## Card 10.3: The demonstration view

- `ExerciseMediaView` shows, in order of preference: the bundled video; else the two photos
  as a loop (each held 1.2 s, 0.4 s crossfade, paused under Reduce Motion with a start/end
  toggle); else "No demonstration yet". A credit line names source and licence.
- **Tests:** the resolver picks video, then photos, then none, and follows twins.

## Card 10.4: Form cues

- Migration **v8**: `formCue(id, exerciseId, kind TEXT CHECK IN ('setup','movement','mistake'),
  text, position, showOnOpen INTEGER, source TEXT CHECK IN ('library','owner'))`.
- Seeded on first open of an exercise from its library instructions: the first sentence as
  setup, the most specific movement sentence as movement; mistakes are left for the owner
  (none are invented). The owner can edit, reorder, add and delete cues, and choose which show
  when the exercise opens in a workout (default: none until chosen).
- **Tests:** seeding is idempotent; owner cues survive reseeding; deleting a library cue keeps
  it deleted.

## Card 10.5: Cues in the workout

- When an exercise becomes current, its chosen cues appear as a compact strip under the
  exercise name, dismissible with one tap, with "Hide for this exercise". Focus mode shows the
  same strip.

## Card 10.6: The exercise page

- Redesigned against DESIGN.md: the demonstration first and full width, then cues, then the
  progress chart with the best and goal as the one dominant figure; records as a plain list
  with dividers, not cards; About folded into a secondary section.
- **Done when:** before and after screenshots (kept local), and the seven tells checked.

## Card 10.7: Studio restyle

- Native-feeling web UI: a translucent sidebar with line icons, a toolbar per page, one hero
  figure per page instead of tile grids, denser tables with hover rows, chart crosshairs,
  ⌘K command palette for pages and exercises, keyboard navigation, and DESIGN.md applied.
- **Done when:** every page checked in the browser with no script errors.

## Card 10.8: Phase close

Device checks, coverage figure, HANDOFF, README.
