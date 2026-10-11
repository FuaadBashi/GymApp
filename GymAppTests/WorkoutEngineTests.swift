import Foundation
import GRDB
import Testing
@testable import GymApp

struct WorkoutEngineTests {
    let db = try! AppDatabase.inMemory()
    let now = TestData.day(20)

    /// A program with day D holding `items`, and D's id.
    private func day(_ items: [String], targetSets: Int = 3, rest: Int = 90) throws -> String {
        try db.writer.write { db in
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: items)
            try db.execute(sql: "UPDATE dayExercise SET targetSets = ?, restSeconds = ? WHERE dayId = ?", arguments: [targetSets, rest, d.id])
            return d.id
        }
    }

    private func start(_ dayId: String?, settings: AppSettings = AppSettings()) throws -> WorkoutSnapshot {
        try db.writer.write { db in
            let w = try WorkoutWrites.start(db, dayId: dayId, settings: settings, now: now)
            return try WorkoutQueries.snapshot(db, workoutId: w.id, settings: settings)
        }
    }

    private func values(_ sets: [WorkoutSetRecord]) -> [String] {
        sets.map { "\(($0.loadHundredths ?? -100) / 100)x\($0.reps)" }
    }

    // MARK: Prefill

    @Test func prefillCopiesTheSameDaysLastSession() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let d = try day(["bench"])
        try db.writer.write { _ = try TestData.finishedWorkout($0, dayId: d, startedAt: TestData.day(5), exercises: [("bench", [(20, 10), (50, 10), (40, 10)])]) }
        let item = try #require(try start(d).items.first)
        #expect(values(item.sets) == ["20x10", "50x10", "40x10"])
        #expect(item.sets.allSatisfy { $0.completedAt == nil })
        #expect(item.previousIsSameDay)
    }

    @Test func anyWorkoutUsesTheNewestSessionAnywhere() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let d = try day(["bench"])
        try db.writer.write { db in
            try TestData.finishedWorkout(db, dayId: d, startedAt: TestData.day(5), exercises: [("bench", [(20, 10), (50, 10), (40, 10)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(8), exercises: [("bench", [(60, 5), (60, 5), (60, 5)])])
        }
        var settings = AppSettings()
        settings.lastTimeSource = .anyWorkout
        let item = try #require(try start(d, settings: settings).items.first)
        #expect(values(item.sets) == ["60x5", "60x5", "60x5"])
        #expect(!item.previousIsSameDay)
    }

    @Test func fewerSetsLastTimeArePaddedWithTheLast() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let d = try day(["bench"])
        try db.writer.write { _ = try TestData.finishedWorkout($0, dayId: d, startedAt: TestData.day(5), exercises: [("bench", [(20, 10), (50, 8)])]) }
        #expect(values(try #require(try start(d).items.first).sets) == ["20x10", "50x8", "50x8"])
    }

    @Test func noHistoryGivesEmptyLoadsAtTheRepMinimum() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "pushup", loadMode: .repsOnly)
        }
        let d = try day(["bench", "pushup"])
        let items = try start(d).items
        #expect(values(items[0].sets) == ["0x8", "0x8", "0x8"])
        #expect(items[1].sets.map(\.loadHundredths) == [nil, nil, nil])
    }

    @Test func onlyOneWorkoutAtATime() throws {
        _ = try start(nil)
        #expect(throws: WorkoutError.alreadyInProgress) { try start(nil) }
    }

    // MARK: Logging and rest

    @Test func loggingASetStartsRest() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let snap = try start(try day(["bench"], rest: 90))
        let set = try #require(snap.items.first?.sets.first)
        try db.writer.write { try WorkoutWrites.logSet($0, setId: set.id, now: now) }
        let after = try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: snap.workout.id, settings: AppSettings()) }
        #expect(after.items[0].sets[0].completedAt == now)
        #expect(after.workout.restEndsAt == now.addingTimeInterval(90))
        #expect(after.completedSetCount == 1 && after.totalSetCount == 3)

        try db.writer.write { try WorkoutWrites.adjustRest($0, workoutId: snap.workout.id, by: -100, now: now) }
        let cleared = try db.reader.read { try WorkoutRecord.fetchOne($0, key: snap.workout.id) }
        #expect(cleared?.restEndsAt == nil && cleared?.restDurationSeconds == nil)
    }

    @Test func negativeRepsAreRejected() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let set = try #require(try start(try day(["bench"])).items.first?.sets.first)
        #expect(throws: WorkoutError.invalidReps) {
            try db.writer.write { try WorkoutWrites.updateSet($0, setId: set.id, edit: SetEdit(loadHundredths: 0, unit: .kg, reps: -1, type: .working)) }
        }
    }

    // MARK: Finishing

    @Test func finishingKeepsOnlyLoggedSets() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "row")
        }
        let snap = try start(try day(["bench", "row"]))
        let id = snap.workout.id
        let finished = try db.writer.write { db in
            try WorkoutWrites.logSet(db, setId: snap.items[1].sets[0].id, now: now)
            return try WorkoutWrites.finish(db, workoutId: id, now: now.addingTimeInterval(600))
        }
        #expect(finished?.endedAt == now.addingTimeInterval(600))
        #expect(finished?.restEndsAt == nil)
        let after = try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: id, settings: AppSettings()) }
        #expect(after.items.map(\.exercise.id) == ["row"])
        #expect(after.items[0].workoutExercise.position == 0)
        #expect(after.totalSetCount == 1)
    }

    @Test func finishingWithNothingLoggedDiscardsTheWorkout() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let snap = try start(try day(["bench"]))
        let result = try db.writer.write { try WorkoutWrites.finish($0, workoutId: snap.workout.id, now: now) }
        #expect(result == nil)
        #expect(try db.reader.read { try WorkoutRecord.fetchCount($0) } == 0)
    }

    // MARK: Swapping

    @Test func swappingAfterLoggingIsRefused() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "incline")
        }
        let snap = try start(try day(["bench"]))
        let item = snap.items[0]
        try db.writer.write { try WorkoutWrites.logSet($0, setId: item.sets[0].id, now: now) }
        #expect(throws: WorkoutError.swapAfterLogging) {
            try db.writer.write { try WorkoutWrites.swapExercise($0, workoutExerciseId: item.id, to: "incline", alsoInProgram: false, settings: AppSettings()) }
        }
    }

    @Test func swappingPrefillsFromTheNewExerciseAndCanUpdateTheProgram() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.exercise(db, id: "incline")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(4), exercises: [("incline", [(30, 12), (35, 10), (35, 9)])])
        }
        let d = try day(["bench"])
        let snap = try start(d)
        let item = snap.items[0]
        try db.writer.write { try WorkoutWrites.swapExercise($0, workoutExerciseId: item.id, to: "incline", alsoInProgram: true, settings: AppSettings()) }
        let after = try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: snap.workout.id, settings: AppSettings()) }
        #expect(after.items[0].exercise.id == "incline")
        #expect(values(after.items[0].sets) == ["30x12", "35x10", "35x9"])
        let dayItem = try db.reader.read { try ProgramQueries.detail($0, dayId: d) }?.items.first
        #expect(dayItem?.exercise.id == "incline")
    }

    // MARK: Sets and exercises

    @Test func addingAndDeletingSetsKeepsPositionsTight() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let snap = try start(try day(["bench"], targetSets: 2))
        let item = snap.items[0]
        let added = try db.writer.write { db in
            try WorkoutWrites.updateSet(db, setId: item.sets[1].id, edit: SetEdit(loadHundredths: 5000, unit: .kg, reps: 6, type: .working))
            return try WorkoutWrites.addSet(db, workoutExerciseId: item.id, settings: AppSettings())
        }
        #expect(added.loadHundredths == 5000 && added.reps == 6 && added.position == 2)
        try db.writer.write { try WorkoutWrites.deleteSet($0, setId: item.sets[0].id) }
        let sets = try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: snap.workout.id, settings: AppSettings()) }.items[0].sets
        #expect(sets.map(\.position) == [0, 1])
    }

    @Test func anAddedExerciseUsesItsDefaultRestAndIsPrefilled() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "curl") }
        let snap = try start(nil)
        let we = try db.writer.write { try WorkoutWrites.addExercise($0, workoutId: snap.workout.id, exerciseId: "curl", settings: AppSettings()) }
        #expect(we.restSeconds == 60 && we.targetSets == nil)
        let after = try db.reader.read { try WorkoutQueries.snapshot($0, workoutId: snap.workout.id, settings: AppSettings()) }
        #expect(after.workout.title == "Workout")
        #expect(after.totalSetCount == AppSettings().defaultSets)
    }

    // MARK: History visibility

    @Test func onlyFinishedWorkoutsAppearInHistory() throws {
        try db.writer.write { _ = try TestData.exercise($0, id: "bench") }
        let snap = try start(try day(["bench"]))
        let setId = snap.items[0].sets[0].id
        try db.writer.write { try WorkoutWrites.logSet($0, setId: setId, now: now) }
        #expect(try db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "bench") }.isEmpty)
        try db.writer.write { _ = try WorkoutWrites.finish($0, workoutId: snap.workout.id, now: now.addingTimeInterval(60)) }
        #expect(try db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "bench") }.count == 1)
    }
}
