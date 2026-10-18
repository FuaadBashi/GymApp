import Foundation
import GRDB
import Testing
@testable import GymApp

/// Guards on the writes that touch logged history and program structure: positions stay
/// dense, history survives program edits, and nothing logged is lost on finish.
struct CoreWritesTests {
    let db = try! AppDatabase.inMemory()

    private func positions(_ db: Database, _ sql: String, _ id: String) throws -> [Int] {
        try Int.fetchAll(db, sql: sql, arguments: [id])
    }

    // MARK: Workout writes

    @Test func finishKeepsOnlyLoggedSetsAndDropsEmptyExercises() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a"); try TestData.exercise(db, id: "b")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            _ = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "b", settings: try AppSettings.load(db))
            let sets = try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).order(Column("position")).fetchAll(db)
            try WorkoutWrites.logSet(db, setId: sets.last!.id, now: TestData.base.addingTimeInterval(60))
            let done = try #require(try WorkoutWrites.finish(db, workoutId: w.id, now: TestData.base.addingTimeInterval(600)))
            #expect(done.endedAt != nil && done.restEndsAt == nil)
            let left = try WorkoutSetRecord.fetchAll(db)
            #expect(left.count == 1 && left[0].position == 0 && left[0].completedAt != nil)
            #expect(try WorkoutExerciseRecord.fetchCount(db) == 1)
        }
    }

    @Test func finishingWithNothingLoggedDiscardsTheWorkout() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            _ = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            #expect(try WorkoutWrites.finish(db, workoutId: w.id, now: TestData.base) == nil)
            #expect(try WorkoutRecord.fetchCount(db) == 0)
        }
    }

    @Test func finishNeverEndsBeforeItStarted() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            let set = try #require(try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).fetchOne(db))
            try WorkoutWrites.logSet(db, setId: set.id, now: TestData.base)
            let done = try #require(try WorkoutWrites.finish(db, workoutId: w.id, now: TestData.base.addingTimeInterval(-3600)))
            #expect(done.endedAt == done.startedAt)
        }
    }

    @Test func unloggingKeepsTheSetsValues() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            let set = try #require(try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).fetchOne(db))
            try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 4250, unit: .kg, reps: 7, type: .working))
            try WorkoutWrites.logSet(db, setId: set.id, now: TestData.base)
            try WorkoutWrites.unlogSet(db, setId: set.id)
            let after = try #require(try WorkoutSetRecord.fetchOne(db, key: set.id))
            #expect(after.completedAt == nil && after.loadHundredths == 4250 && after.reps == 7)
        }
    }

    @Test func negativeRepsAreRejected() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            let set = try #require(try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).fetchOne(db))
            #expect(throws: WorkoutError.invalidReps) {
                try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 100, unit: .kg, reps: -1, type: .working))
            }
        }
    }

    @Test func removingAndMovingExercisesKeepsPositionsDense() throws {
        try db.writer.write { db in
            for id in ["a", "b", "c", "d"] { try TestData.exercise(db, id: id) }
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            var items: [WorkoutExerciseRecord] = []
            for id in ["a", "b", "c", "d"] { items.append(try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: id, settings: try AppSettings.load(db))) }
            try WorkoutWrites.removeExercise(db, workoutExerciseId: items[1].id)
            try WorkoutWrites.moveExercise(db, workoutId: w.id, from: 2, to: 0)
            try WorkoutWrites.moveExercise(db, workoutId: w.id, from: 9, to: 0)   // out of range: no change
            let order = try String.fetchAll(db, sql: "SELECT exerciseId FROM workoutExercise WHERE workoutId = ? ORDER BY position", arguments: [w.id])
            #expect(order == ["d", "a", "c"])
            #expect(try positions(db, "SELECT position FROM workoutExercise WHERE workoutId = ? ORDER BY position", w.id) == [0, 1, 2])
        }
    }

    @Test func deletingASetRenumbersTheRest() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            _ = try WorkoutWrites.addSet(db, workoutExerciseId: a.id, settings: try AppSettings.load(db))
            let first = try #require(try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).order(Column("position")).fetchOne(db))
            let before = try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).fetchCount(db)
            try WorkoutWrites.deleteSet(db, setId: first.id)
            let after = try positions(db, "SELECT position FROM workoutSet WHERE workoutExerciseId = ? ORDER BY position", a.id)
            #expect(after == Array(0..<(before - 1)))
        }
    }

    @Test func shorteningRestPastNowClearsIt() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let w = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            let a = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: "a", settings: try AppSettings.load(db))
            let set = try #require(try WorkoutSetRecord.filter(Column("workoutExerciseId") == a.id).fetchOne(db))
            try WorkoutWrites.logSet(db, setId: set.id, now: TestData.base)
            let end = try #require(try WorkoutRecord.fetchOne(db, key: w.id)?.restEndsAt)
            try WorkoutWrites.adjustRest(db, workoutId: w.id, by: 15, now: TestData.base)
            #expect(try WorkoutRecord.fetchOne(db, key: w.id)?.restEndsAt == end.addingTimeInterval(15))
            try WorkoutWrites.adjustRest(db, workoutId: w.id, by: -10_000, now: TestData.base)
            #expect(try WorkoutRecord.fetchOne(db, key: w.id)?.restEndsAt == nil)
        }
    }

    @Test func onlyOneWorkoutCanBeInProgress() throws {
        try db.writer.write { db in
            _ = try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            #expect(throws: WorkoutError.alreadyInProgress) {
                try WorkoutWrites.start(db, dayId: nil, settings: try AppSettings.load(db), now: TestData.base)
            }
        }
    }

    // MARK: Program writes

    @Test func deletingAndMovingDaysKeepsPositionsDense() throws {
        try db.writer.write { db in
            let p = try TestData.program(db)
            let days = try (0..<4).map { try TestData.day(db, programId: p.id, name: "D\($0)", position: $0) }
            try ProgramWrites.deleteDay(db, dayId: days[1].id)
            try ProgramWrites.moveDay(db, programId: p.id, from: 0, to: 2)
            let names = try String.fetchAll(db, sql: "SELECT name FROM programDay WHERE programId = ? ORDER BY position", arguments: [p.id])
            #expect(names == ["D2", "D3", "D0"])
            #expect(try positions(db, "SELECT position FROM programDay WHERE programId = ? ORDER BY position", p.id) == [0, 1, 2])
        }
    }

    @Test func deletingADayKeepsItsWorkouts() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: ["a"])
            let w = try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.base, exercises: [("a", [(50, 5)])])
            try ProgramWrites.deleteDay(db, dayId: d.id)
            let kept = try #require(try WorkoutRecord.fetchOne(db, key: w.id))
            #expect(kept.programDayId == nil)
            #expect(try WorkoutSetRecord.fetchCount(db) == 1)
        }
    }

    @Test func movingAndRemovingDayItemsKeepsPositionsDense() throws {
        try db.writer.write { db in
            for id in ["a", "b", "c"] { try TestData.exercise(db, id: id) }
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: ["a", "b", "c"])
            try ProgramWrites.moveItem(db, dayId: d.id, from: 2, to: 0)
            let first = try #require(try DayExerciseRecord.filter(Column("dayId") == d.id).order(Column("position")).fetchOne(db))
            try ProgramWrites.removeItem(db, itemId: first.id)
            let order = try String.fetchAll(db, sql: "SELECT exerciseId FROM dayExercise WHERE dayId = ? ORDER BY position", arguments: [d.id])
            #expect(order == ["a", "b"])
            #expect(try positions(db, "SELECT position FROM dayExercise WHERE dayId = ? ORDER BY position", d.id) == [0, 1])
        }
    }

    @Test func copyingADayIntoItselfIsRefused() throws {
        try db.writer.write { db in
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0)
            #expect(throws: (any Error).self) { try ProgramWrites.copyDay(db, from: d.id, into: d.id) }
        }
    }

    @Test func renamingTrimsWhitespace() throws {
        try db.writer.write { db in
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0)
            try ProgramWrites.renameDay(db, dayId: d.id, to: "  Push  ")
            #expect(try ProgramDayRecord.fetchOne(db, key: d.id)?.name == "Push")
        }
    }

    // MARK: Exercise writes

    @Test func historyIsDetectedOnlyFromLoggedSets() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a"); try TestData.exercise(db, id: "b")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("a", [(20, 10)])])
            #expect(try ExerciseWrites.hasHistory(db, exerciseId: "a"))
            #expect(try !ExerciseWrites.hasHistory(db, exerciseId: "b"))
        }
    }

    @Test func archivingKeepsHistory() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "a")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.base, exercises: [("a", [(20, 10)])])
            try ExerciseWrites.setArchived(db, id: "a", true)
            #expect(try ExerciseRecord.fetchOne(db, key: "a")?.isArchived == true)
            #expect(try WorkoutSetRecord.fetchCount(db) == 1)
        }
    }
}
