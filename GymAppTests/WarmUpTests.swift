import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 7.7: the warm-up builder (rulebook §3a).
struct WarmUpTests {
    @Test func rampsRoundToTheStep() {
        let strength = TrainingMath.warmUpRamp(workingKg: 100, strength: true, step: 2.5, bar: 20)
        #expect(strength.map(\.kg) == [20, 50, 70, 85] && strength.map(\.reps) == [10, 5, 3, 1])
        // 40 kg machine in 5 kg steps: 20 × 8, then 32 rounds to 30.
        let short = TrainingMath.warmUpRamp(workingKg: 40, strength: false, step: 5, bar: 20)
        #expect(short.map(\.kg) == [20, 30] && short.map(\.reps) == [8, 3])
        // A light barbell lift: no bar set under 30 kg, and nothing at or below the bar, so
        // only 85% (21.25, rounded to 22.5) remains.
        let light = TrainingMath.warmUpRamp(workingKg: 25, strength: true, step: 2.5, bar: 20)
        #expect(light.map(\.kg) == [22.5] && light.map(\.reps) == [1])
    }

    @Test func togglingBuildsBeforeTheWorkingSetsAndOffKeepsLoggedWarmUps() throws {
        let db = try AppDatabase.inMemory()
        let (we, dayItem) = try db.writer.write { db -> (WorkoutExerciseRecord, String) in
            try db.execute(sql: """
                INSERT INTO exercise (id, name, equipment, loadMode, primaryMuscles, secondaryMuscles, category, bodyRegion,
                  movementPattern, instructions, source, defaultRestSeconds, preferredUnit, isFavorite, isArchived, createdAt)
                SELECT 'bench', 'Bench', 'barbell', 'total', '["chest"]', '[]', 'strength', 'upper', 'horizontalPush', '[]', 'custom', 90, 'kg', 0, 0, createdAt
                FROM (SELECT '2026-01-01 00:00:00.000' AS createdAt)
                """)
            let p = try TestData.program(db)
            let d = try TestData.day(db, programId: p.id, name: "D", position: 0, items: ["bench"])
            try TestData.finishedWorkout(db, dayId: d.id, startedAt: TestData.day(1), exercises: [("bench", [(100, 5), (100, 5), (100, 5)])])
            let w = try WorkoutWrites.start(db, dayId: d.id, settings: AppSettings(), now: TestData.day(5))
            let item = try #require(try WorkoutExerciseRecord.filter(Column("workoutId") == w.id).fetchOne(db))
            return (item, item.dayExerciseId!)
        }
        try db.writer.write { try WorkoutWrites.setWarmUps($0, workoutExerciseId: we.id, on: true) }
        var sets = try db.reader.read { try WorkoutSetRecord.filter(Column("workoutExerciseId") == we.id).order(Column("position")).fetchAll($0) }
        #expect(sets.map(\.type) == [.warmUp, .warmUp, .warmUp, .warmUp, .working, .working, .working])
        #expect(sets.prefix(4).map(\.loadHundredths) == [2000, 5000, 7000, 8500])
        #expect(try db.reader.read { try Bool.fetchOne($0, sql: "SELECT warmUps FROM dayExercise WHERE id = ?", arguments: [dayItem]) } == true)

        try db.writer.write { try WorkoutWrites.logSet($0, setId: sets[0].id, now: TestData.day(5)) }
        try db.writer.write { try WorkoutWrites.setWarmUps($0, workoutExerciseId: we.id, on: false) }
        sets = try db.reader.read { try WorkoutSetRecord.filter(Column("workoutExerciseId") == we.id).order(Column("position")).fetchAll($0) }
        #expect(sets.map(\.type) == [.warmUp, .working, .working, .working])
        #expect(sets.map(\.position) == [0, 1, 2, 3])
    }
}
