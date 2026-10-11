# Implementation specs

One file per roadmap phase. Each phase is split into **cards**: a card is one unit of work,
small enough to finish, test and commit in one sitting. Cards are done in order; a card may
rely on everything before it.

| File | Phase | Detail |
|---|---|---|
| [00-foundation.md](00-foundation.md) | 0: database, JEFIT import, exercise library | full |
| [01-programs-library.md](01-programs-library.md) | 1: programs and the exercise library | full |
| [02-workout-screen.md](02-workout-screen.md) | 2: workout screen | full |
| [03-05-outline.md](03-05-outline.md) | 3–5: history and analytics, export and backups, phone | outline, specified in full after phase 2 |

Progress is tracked in [../HANDOFF.md](../HANDOFF.md).

## How a card reads

- **Goal:** one sentence.
- **Read first:** the docs and code the card depends on.
- **Files:** exactly which files to create or change.
- **Steps:** what to build, with names, signatures and edge cases already decided.
- **Tests:** what to assert, often with exact expected values.
- **Done when:** the checks that must pass. All of them, every time.
- **Out of scope:** what not to do, even if it looks related.

## Rules for every card

1. **The spec decides.** Where it gives a name, a signature, a schema or a number, use it
   as written. If it is ambiguous or wrong, stop and record the question in HANDOFF.md under
   *Open questions*. Do not invent an answer.
2. **Stay inside the card.** No refactors, renames or "while I'm here" changes outside its
   file list. Note anything worth doing in HANDOFF.md instead.
3. **Tests first where the card gives expected values.** Write the test, watch it fail, then
   make it pass.
4. **Never weaken a test to make it pass.** If an expected value looks wrong, check it with
   `tools/reference_import.py` or by hand, and record the finding in HANDOFF.md.
5. **The project file.** `GymApp.xcodeproj` uses folder-synchronised groups: a new file under
   `GymApp/` or `GymAppTests/` joins its target automatically. Do not edit `project.pbxproj`
   unless a card says so.
6. **Finish every card the same way:**

   ```bash
   xcodebuild test -project GymApp.xcodeproj -scheme GymApp \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -30
   ```

   It must end in `** TEST SUCCEEDED **` with no new warnings in files the card touched.
   Then update HANDOFF.md (tick the card, add a short session note) and commit:
   `git add -A && git commit -m "<card id>: <what changed, plain sentence>"`.

## Conventions

- **Swift 5 language mode, main-actor by default.** The target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Anything used inside a GRDB database closure
  (records, enums stored in records, `TrainingMath`, `Load`, importers) must be declared
  `nonisolated`. Otherwise the compiler rejects its `Codable` or `FetchableRecord`
  conformance in that closure. The pattern is in 00-foundation.md, card 0.2, and has been
  checked to compile.
- **Tests use Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Name tests as
  sentences stating the claim: `@Test func assistedLoadsAreStoredNegative()`.
- **Fixtures** live in `GymAppTests/Fixtures/`. Read them with a path built from `#filePath`:

  ```swift
  let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
  ```

  The real JEFIT export lives in `data/` and is not in the repository. Tests that need it use
  `.enabled(if: FileManager.default.fileExists(atPath: realExportPath))` so they skip, rather
  than fail, on a machine without it.
- **Comments explain why,** naming the failure a rule prevents. Match the surrounding density.
- **Commit messages** are plain sentences describing the change, with no trailers.
