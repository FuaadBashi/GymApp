# Exercise media

barbell-bench.mp4 and barbell-bench.jpg are derived from FitnessScape's
[bench press demonstration](https://commons.wikimedia.org/wiki/File:Bench_press_-_exercise_demonstration_video.webm),
licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
Original: https://upload.wikimedia.org/wikipedia/commons/d/df/Bench_press_-_exercise_demonstration_video.webm
Source SHA-1: 619a8ca8c5ad851bb6b7d1775f8babefd478e623.
Changes: transcoded VP9/WebM to silent H.264 MP4, extracted a frame at 0.2 seconds.
Visually checked the sequence: flat bench, free barbell, medium grip, lowered to chest
and pressed up. It is mapped only to the corresponding barbell bench IDs, never machines,
incline or close-grip variants. In-app credit links to author/source and license.
The media is bundled; playback requires no network.

barbell-squat.mp4 and barbell-squat.jpg use FitnessScape's
[back squat demonstration](https://commons.wikimedia.org/wiki/File:Squat_-_exercise_demonstration_video.webm),
also CC BY 3.0. Original:
https://upload.wikimedia.org/wikipedia/commons/5/5c/Squat_-_exercise_demonstration_video.webm
Changes: H.264 conversion without audio, still at 0.2 seconds. Sequence checked visually:
free barbell across the upper back, knee/hip flexion and return to standing. Mapped only
to conventional barbell back squat, not front, Smith, wide-stance or bench squat.

## Additional sequences reviewed 11 October 2026

- **barbell-deadlift** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Deadlift_-_exercise_demonstration_video.webm), CC BY 3.0. Conventional floor deadlift, free straight bar, knees and hips bend, return to standing. Excludes Romanian, stiff-leg, sumo, trap-bar and deficit variants.
- **barbell-row** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Bent-over_row_-_exercise_demonstration_video.webm), CC BY 3.0. Standing bent-over row with an overhand grip and free straight bar. Excludes reverse grip, one-arm, dumbbell, Smith and chest-supported rows.
- **barbell-incline** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Incline_press_-_exercise_demonstration_video.webm), CC BY 3.0. Inclined bench, medium overhand grip, free barbell lowered to upper chest and pressed up. Excludes flat/decline, dumbbell and Smith variants.
- **barbell-shoulder** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Shoulder_press_-_exercise_demonstration_video.webm), CC BY 3.0. Standing free barbell front overhead press. The library Barbell Shoulder Press describes a seated press and is deliberately excluded, as are ambiguous JEFIT Shoulder Press, seated military, behind-neck, Smith and push press variants.
- **pull-up** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Pull-ups_-_exercise_demonstration_video.webm), CC BY 3.0. Unassisted hanging overhand pull-up with chin reaching bar level. Excludes chin-up, neutral grip, band/machine assisted and rear pull-ups.
- **hanging-leg-raise** — [FitnessScape source](https://commons.wikimedia.org/wiki/File:Leg_raises_-_exercise_demonstration_video.webm), CC BY 3.0. Hanging from an overhead bar, raising extended legs toward horizontal and lowering. Excludes bent-knee crunches, lying raises and captain-chair variants.

All six were checked across a one-frame-per-second contact sheet, then converted
to silent H.264 with a still at 0.2 seconds. Pinned original SHA-256 hashes and download
URLs are in manifest.json. The acquisition script verifies original bytes before
conversion. All assets are bundled; source/license links are optional outbound links,
not playback dependencies. More variants require separate visual/provenance review.

## wger clips reviewed 13 October 2026

Twenty clips come from the [wger](https://wger.de) exercise database. Every one is by
**Goulart**, licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); the
converted clips and stills are shared under the same licence. The originals are 1080p HEVC
phone videos; changes: silent H.264 at 480p, 24 fps, CRF 30, and a JPEG frame at 1 second.
Download URLs and SHA-256 hashes of the originals are pinned in manifest.json, and
`tools/fetch_exercise_media.py` rebuilds them only if the originals are unchanged.

Each was checked on an eight-frame contact sheet. What each shows, and what it is mapped to:

| Clip | wger exercise | Shows | Mapped to |
|---|---|---|---|
| leg-curl-lying | Leg Curls (laying) | prone, plate-loaded lying leg curl machine | Machine Leg Curl (Prone), Lying Leg Curls |
| dumbbell-lateral-raise | Lateral Raises | standing, both arms together | Dumbbell Lateral Raise, Side Lateral Raise |
| dumbbell-bench | Benchpress Dumbbells | flat bench, two dumbbells | Dumbbell Bench Press |
| dumbbell-shoulder-press | Shoulder Press, Dumbbells | seated upright, two dumbbells | Dumbbell Seated Shoulder Press |
| assisted-pull-up | Pull Ups on Machine | overhand pull-up on an assisted machine | Machine Assisted Pull-Up |
| leg-press-seated | Leg Press | seated, selectorised horizontal leg press | Machine Leg Press |
| machine-shoulder-press | Shoulder Press, on Machine | seated machine overhead press | Machine Shoulder Press |
| face-pull | Facepull | standing cable pull to the face | Cable Rope Face Pull, Face Pull |
| cable-seated-row | Rowing seated, narrow grip | seated cable row, close handle | Cable Seated Row, Seated Cable Rows |
| dumbbell-romanian-deadlift | Romanian Deadlift | standing, **dumbbells** | Dumbbell Romanian Deadlift only (not barbell) |
| alternating-hammer-curl | Hammer Curls | standing, one arm at a time | Dumbbell Alternating Hammer Curl |
| incline-dumbbell-press | Incline Bench Press - Dumbbell | incline bench, two dumbbells | Dumbbell Incline Bench Press |
| hip-adduction | Seated Hip Adduction | seated adduction machine | Thigh Adductor (and exercises linked to it) |
| barbell-shrug | Shoulder Shrug | standing, barbell in front | Barbell Shrug |
| one-arm-cable-curl | Biceps Curl With Cable | standing, one arm, low pulley | Standing One-Arm Cable Curl |
| overhead-rope-extension | Triceps Extensions on Cable | overhead, rope | Cable Rope Overhead Tricep Extension |
| dip | Dips | parallel bars, body weight | Dip, Parallel Bar Dip |
| dumbbell-curl | Biceps Curls With Dumbbell | standing, both arms together | Dumbbell Bicep Curl (not alternating) |
| one-arm-preacher-curl | Single-arm Preacher Curl | one dumbbell on a preacher pad | Dumbbell One-Arm Preacher Curl |
| leg-press-wide | Leg Presses (wide) | 45° sled, wide stance | Machine Leg Press (Wide Stance) |

Rejected: "Leg Curls (sitting)" (frames too ambiguous to confirm the machine) and
"Hammercurls on Cable" (one-armed; the matching exercise is two-armed with a rope).

The app also uses an exercise's hand-checked library link (tools/build_jefit_map.py
LIBRARY_LINKS) to find a clip, still requiring the equipment to match what the clip shows.
