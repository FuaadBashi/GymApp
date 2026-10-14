import Foundation
import GRDB
import Testing
@testable import GymApp

nonisolated enum Make {
    static func exercise(_ id: String, name: String = "Bench Press", primary: [Muscle] = [.chest]) -> ExerciseRecord {
        ExerciseRecord(id: id, name: name, equipment: .barbell, loadMode: .total, primaryMuscles: primary,
                       secondaryMuscles: [], force: .push, mechanic: .compound, category: .strength,
                       bodyRegion: .upper, movementPattern: .horizontalPush, instructions: [], source: .custom,
                       libraryId: nil, stickyNote: nil, defaultRestSeconds: 60, preferredUnit: .kg,
                       isFavorite: false, isArchived: false, createdAt: Date(timeIntervalSince1970: 0))
    }

    static func workout(_ id: String, start: TimeInterval = 1000, end: TimeInterval? = 2000) -> WorkoutRecord {
        WorkoutRecord(id: id, startedAt: Date(timeIntervalSince1970: start),
                      endedAt: end.map { Date(timeIntervalSince1970: $0) }, programDayId: nil, title: "Workout",
                      note: nil, effort: nil, restEndsAt: nil, restDurationSeconds: nil, source: .app, externalId: nil)
    }

    static func program(_ id: String, active: Bool) -> ProgramRecord {
        ProgramRecord(id: id, name: "P \(id)", split: .custom, isActive: active, isArchived: false,
                      sessionsPerWeekGoal: 3, source: .app, externalId: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    static func workoutExercise(_ id: String, workout: String, exercise: String) -> WorkoutExerciseRecord {
        WorkoutExerciseRecord(id: id, workoutId: workout, exerciseId: exercise, position: 0, dayExerciseId: nil,
                              targetSets: nil, repMin: nil, repMax: nil, restSeconds: 60, note: nil, externalId: nil)
    }

    static func set(_ id: String, we: String, reps: Int = 8) -> WorkoutSetRecord {
        WorkoutSetRecord(id: id, workoutExerciseId: we, position: 0, loadHundredths: 6000, unit: .kg, reps: reps,
                         type: .working, completedAt: Date(timeIntervalSince1970: 1500), rpe: nil, externalId: nil)
    }
}

struct SchemaTests {
    let db = try! AppDatabase.inMemory()

    @Test func migratingCreatesExactlyTheSpecifiedTables() throws {
        let tables = try db.reader.read {
            try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb%' AND name NOT LIKE 'sqlite%' ORDER BY name")
        }
        #expect(tables == ["bodyEntry", "dayExercise", "exercise", "exerciseNote", "importRun", "program",
                           "programDay", "setting", "workout", "workoutExercise", "workoutSet", "healthDay", "studioDecision"].sorted())
    }

    @Test func anExerciseRoundTripsWithMusclesStoredAsJSON() throws {
        let e = Make.exercise("x", primary: [.chest, .triceps])
        try db.writer.write { try e.insert($0) }
        #expect(try db.reader.read { try ExerciseRecord.fetchOne($0, key: "x") } == e)
        let raw = try db.reader.read { try String.fetchOne($0, sql: "SELECT primaryMuscles FROM exercise") }
        #expect(raw == #"["chest","triceps"]"#)
    }

    @Test func aSecondWorkoutInProgressIsRejected() throws {
        try db.writer.write { try Make.workout("a", end: nil).insert($0) }
        #expect(throws: (any Error).self) { try db.writer.write { try Make.workout("b", end: nil).insert($0) } }
    }

    @Test func aSecondActiveProgramIsRejected() throws {
        try db.writer.write { try Make.program("a", active: true).insert($0) }
        #expect(throws: (any Error).self) { try db.writer.write { try Make.program("b", active: true).insert($0) } }
    }

    @Test func negativeRepsAreRejected() throws {
        try insertWorkoutWithExercise()
        #expect(throws: (any Error).self) { try db.writer.write { try Make.set("s", we: "we", reps: -1).insert($0) } }
    }

    @Test func anUnknownUnitIsRejected() throws {
        try insertWorkoutWithExercise()
        #expect(throws: (any Error).self) {
            try db.writer.write {
                try $0.execute(sql: "INSERT INTO workoutSet (id, workoutExerciseId, position, unit, reps, type) VALUES ('s','we',0,'st',5,'working')")
            }
        }
    }

    @Test func aWorkoutCannotEndBeforeItStarts() throws {
        #expect(throws: (any Error).self) { try db.writer.write { try Make.workout("a", start: 2000, end: 1000).insert($0) } }
    }

    @Test func aBlankExerciseNameIsRejected() throws {
        #expect(throws: (any Error).self) { try db.writer.write { try Make.exercise("x", name: "   ").insert($0) } }
    }

    @Test func aWorkoutExerciseNeedsAnExistingExercise() throws {
        try db.writer.write { try Make.workout("w").insert($0) }
        #expect(throws: (any Error).self) {
            try db.writer.write { try Make.workoutExercise("we", workout: "w", exercise: "missing").insert($0) }
        }
    }

    @Test func deletingAWorkoutDeletesItsExercisesAndSets() throws {
        try insertWorkoutWithExercise()
        try db.writer.write { try Make.set("s", we: "we").insert($0) }
        _ = try db.writer.write { try WorkoutRecord.deleteOne($0, key: "w") }
        #expect(try db.reader.read { try WorkoutExerciseRecord.fetchCount($0) } == 0)
        #expect(try db.reader.read { try WorkoutSetRecord.fetchCount($0) } == 0)
    }

    @Test func anExerciseWithHistoryCannotBeDeleted() throws {
        try insertWorkoutWithExercise()
        #expect(throws: (any Error).self) { _ = try db.writer.write { try ExerciseRecord.deleteOne($0, key: "e") } }
    }

    private func insertWorkoutWithExercise() throws {
        try db.writer.write { db in
            try Make.exercise("e").insert(db)
            try Make.workout("w").insert(db)
            try Make.workoutExercise("we", workout: "w", exercise: "e").insert(db)
        }
    }
}
