import Foundation
import GRDB
import Testing
@testable import GymApp

struct ExerciseStatsTests {
    let db = try! AppDatabase.inMemory()

    /// Three sessions: day 1 warm-up 40×10 then 60×8; day 3 70×5 then a drop row 50×8; day 5
    /// 70×5 again (a tie with day 3) and 60×9.
    private func fixture() throws -> [ExerciseSession] {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("bench", [(40, 10), (60, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(3), exercises: [("bench", [(70, 5), (50, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5), exercises: [("bench", [(70, 5), (60, 9)])])
            try db.execute(sql: "UPDATE workoutSet SET type = 'warmUp' WHERE loadHundredths = 4000")
            try db.execute(sql: "UPDATE workoutSet SET type = 'drop' WHERE loadHundredths = 5000")
        }
        return try db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "bench") }
    }

    @Test func pointsAreOldestFirstAndSkipWarmUpsAndDrops() throws {
        let points = ExerciseStats.points(try fixture(), loadMode: .total) { _ in nil }
        #expect(points.map(\.date) == [1, 3, 5].map(TestData.day))
        let heaviest: [Double?] = [60, 70, 70]
        #expect(points.map(\.heaviestKg) == heaviest)
        let e1: [Double] = points.map { ($0.bestE1RM! * 100).rounded() / 100 }
        let expected: [Double] = [76, 81.67, 81.67]
        #expect(e1 == expected)
        // Volume skips warm-ups but counts drop segments (rulebook §3).
        let volumes: [Double] = [480, 750, 890]   // 60×8; 70×5 + drop 50×8; 70×5 + 60×9
        #expect(points.map(\.volumeKg) == volumes)
    }

    @Test func recordsKeepTheEarliestDateOnATie() throws {
        let r = ExerciseStats.records(try fixture(), loadMode: .total) { _ in nil }
        #expect(r.heaviest?.valueKg == 70 && r.heaviest?.date == TestData.day(3))
        #expect(r.bestE1RM?.date == TestData.day(3))
        #expect(r.bestVolume?.valueKg == 890 && r.bestVolume?.date == TestData.day(5))
        #expect(r.repRecords.map(\.valueKg) == [70, 60])
        #expect(r.repRecords.map(\.reps) == [5, 9])
        #expect(r.repRecords[1].date == TestData.day(5))
    }

    @Test func bodyWeightExercisesHaveOnlyVolume() throws {
        let sessions = try fixture()
        let r = ExerciseStats.records(sessions, loadMode: .bodyweightPlus) { _ in 80 }
        #expect(r.heaviest == nil && r.bestE1RM == nil && r.repRecords.isEmpty)
        #expect(r.bestVolume != nil)
    }

    @Test(.enabled(if: Fixtures.hasRealExport))
    func benchPressBestE1RMMatchesRawRows() async throws {
        try await db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
        _ = try await ImportService.importJEFIT(fileAt: Fixtures.realExport, into: db)
        let sessions = try await db.reader.read { try ExerciseQueries.sessions($0, exerciseId: "jefit:1:2") }
        let r = ExerciseStats.records(sessions, loadMode: .total) { _ in nil }
        // Independently from SQL: Epley over working and failed sets, 1–12 reps, kg loads.
        let rows = try await db.reader.read {
            try Row.fetchAll($0, sql: """
                SELECT s.loadHundredths, s.unit, s.reps FROM workoutSet s
                JOIN workoutExercise we ON we.id = s.workoutExerciseId JOIN workout w ON w.id = we.workoutId
                WHERE we.exerciseId = 'jefit:1:2' AND w.endedAt IS NOT NULL AND s.completedAt IS NOT NULL
                  AND s.type IN ('working', 'failed') AND s.reps BETWEEN 1 AND 12 AND s.loadHundredths > 0
                """)
        }
        let expected = rows.map { row -> Double in
            let h: Int = row["loadHundredths"], unit: String = row["unit"], reps: Int = row["reps"]
            let kg = Double(h) / 100 * (unit == "lb" ? 0.45359237 : 1)
            return reps == 1 ? kg : kg * (1 + Double(reps) / 30)
        }.max()
        #expect(sessions.count > 50)
        #expect(abs((r.bestE1RM?.valueKg ?? 0) - (expected ?? -1)) < 0.0001)
    }
}
