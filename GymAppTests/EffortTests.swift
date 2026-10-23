import Foundation
import GRDB
import Testing
@testable import GymApp

/// Rulebook §6a. The cases in Fixtures/effort_cases.json are shared with the studio's tests.
@Suite struct EffortTests {
    struct Case: Decodable {
        var name: String
        var type: SetType
        var repsInReserve: Int?
        var annotations: [SetAnnotation]
        var e1RM: Double?
        var reference: Double?
        var expected: Double
    }

    @Test func theSharedCasesMatch() throws {
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: Fixtures.folder.appending(path: "effort_cases.json")))
        #expect(cases.count >= 18)
        for c in cases {
            let got = TrainingMath.effort(type: c.type, repsInReserve: c.repsInReserve, annotations: c.annotations,
                                          e1RM: c.e1RM, reference: c.reference)
            #expect(abs(got - c.expected) < 1e-6, "\(c.name): \(got) != \(c.expected)")
        }
    }

    let db = try! AppDatabase.inMemory()

    /// A light bench day after heavier ones counts for less in the weekly muscle sets and in recovery.
    @Test func aLightSessionCountsForLessThanAHeavyOne() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(0), exercises: [("bench", [(kg: 60, reps: 5), (kg: 60, reps: 5)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(7), exercises: [("bench", [(kg: 40, reps: 5), (kg: 40, reps: 5)])])
        }
        let week1 = try db.reader.read { try ProgressQueries.muscles($0, from: TestData.day(-1), to: TestData.day(1)) }
        let week2 = try db.reader.read { try ProgressQueries.muscles($0, from: TestData.day(6), to: TestData.day(8)) }
        #expect(week1.first { $0.muscle == .chest }?.sets == 2, "no history before it: every set counts")
        let light = (40.0 / 60.0 - 0.6) / 0.25
        #expect(abs((week2.first { $0.muscle == .chest }?.sets ?? 0) - 2 * light) < 1e-6)

        let recovery = try db.reader.read { try ProgressQueries.recovery($0, now: TestData.day(7)) }
        #expect(abs((recovery.first { $0.muscle == .chest }?.sets ?? 0) - 2 * light) < 0.05, "just after the light session")
    }

    @Test func labelsWinOverTheCalculation() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(0), exercises: [("bench", [(kg: 100, reps: 5)])])
            let w = try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(3), exercises: [("bench", [(kg: 40, reps: 5), (kg: 100, reps: 5)])])
            let sets = try WorkoutSetRecord.fetchAll(db, sql: """
                SELECT s.* FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId WHERE we.workoutId = ? ORDER BY s.position
                """, arguments: [w.id])
            try db.execute(sql: "UPDATE workoutSet SET repsInReserve = 0 WHERE id = ?", arguments: [sets[0].id])   // a max set at 40 kg
            try db.execute(sql: "UPDATE workoutSet SET annotations = '[\"deload\"]' WHERE id = ?", arguments: [sets[1].id])
        }
        let week = try db.reader.read { try ProgressQueries.muscles($0, from: TestData.day(2), to: TestData.day(4)) }
        #expect(week.first { $0.muscle == .chest }?.sets == 1, "max at 40 kg counts 1, the deload at 100 kg counts 0")
    }

    @Test func historyOlderThanEightWeeksIsIgnored() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(0), exercises: [("bench", [(kg: 100, reps: 5)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(60), exercises: [("bench", [(kg: 40, reps: 5)])])
        }
        let week = try db.reader.read { try ProgressQueries.muscles($0, from: TestData.day(59), to: TestData.day(61)) }
        #expect(week.first { $0.muscle == .chest }?.sets == 1)
    }

    @Test func theStepsLineShowsTheRecoveryDaysAgainstTheAverage() {
        let s = StepsSummary(days: [("2026-10-20", 18_400), ("2026-10-21", 9_200), ("2026-10-22", 6_100)],
                             dailyAverage: 7_900, thisWeek: nil, lastWeek: nil)
        let line = s.recoveryLine(today: "2026-10-22", yesterday: "2026-10-21", dayBefore: "2026-10-20")
        #expect(line?.hasPrefix("Steps: \(6_100.formatted()) today · \(9_200.formatted()) yesterday · \(18_400.formatted()) the day before") == true)
        #expect(line?.contains("30-day average \(7_900.formatted())") == true)
        #expect(line?.contains("big walking day") == true, "18,400 is more than 1.5 × 7,900")
        let quiet = StepsSummary(days: [("2026-10-22", 6_100)], dailyAverage: 7_900, thisWeek: nil, lastWeek: nil)
        #expect(quiet.recoveryLine(today: "2026-10-22", yesterday: "2026-10-21", dayBefore: "2026-10-20")?.contains("big") == false)
        #expect(StepsSummary(days: [], dailyAverage: nil, thisWeek: nil, lastWeek: nil)
            .recoveryLine(today: "2026-10-22", yesterday: "2026-10-21", dayBefore: "2026-10-20") == nil)
    }
}
