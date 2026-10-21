import Foundation
import GRDB
import Testing
@testable import GymApp

/// Rulebook §5b: the live comparison and the beat table's round trip.
struct BestPanelTests {
    /// For every best, step and rep count the suggested load beats the best, and one step
    /// lighter does not: the table's answer is the lightest that works.
    @Test func beatTableRoundTripsForEveryRepCount() {
        for best in stride(from: 20.0, through: 300.0, by: 7.3) {
            for step in [1.0, 1.25, 2.5, 4.5, 5.0] {
                for row in TrainingMath.beatTable(best: best, reps: 1...12, step: step) {
                    let beats: Double = TrainingMath.e1RM(kg: row.kg, reps: row.reps) - best
                    let lighter: Double = TrainingMath.e1RM(kg: row.kg - step, reps: row.reps) - best
                    #expect(beats > 0.01, "best \(best) step \(step) reps \(row.reps)")
                    #expect(lighter <= 0.01, "not lightest: best \(best) step \(step) reps \(row.reps)")
                }
            }
        }
    }

    @Test func deltaSaysAboveBelowOrLevel() {
        #expect(BestHintLine.delta(2.14) == "2.1 kg above")
        #expect(BestHintLine.delta(-48.66) == "48.7 kg below")
        #expect(BestHintLine.delta(0.005) == "level with it")
    }

    @Test func noEstimateOutsideOneToTwelveReps() {
        #expect(TrainingMath.displayableE1RM(kg: 60, reps: 13, loadMode: .total) == nil)
        #expect(TrainingMath.displayableE1RM(kg: 60, reps: 0, loadMode: .total) == nil)
        let expected: Double = 65 * (1 + 10.0 / 30)
        #expect(TrainingMath.displayableE1RM(kg: 65, reps: 10, loadMode: .total) == expected)
    }

    /// The hint names the set that made each best, so the panel can say "127.5×10".
    @MainActor @Test func hintsCarryTheSetBehindTheBest() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TestData.exercise(db, id: "dl")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-400 * 86_400), exercises: [("dl", [(127.5, 10), (100, 5)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-60 * 86_400), exercises: [("dl", [(90, 8)])])
        }
        let model = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        try await model.start(dayId: nil)
        await model.addExercise("dl")
        let hint = try #require(model.snapshot?.hints["dl"])
        #expect(hint.allTimeSet?.loadHundredths == 12750)
        #expect(hint.allTimeSet?.reps == 10)
        #expect(hint.windowMonths == 12)
        #expect(hint.windowSet?.loadHundredths == 9000)
        #expect(hint.windowSet?.reps == 8)
    }

    /// Rulebook §5b: no set in the last 12 months, so no window best; the last session's best
    /// (80 × 8, 400 days ago) is shown as the nearer target.
    @MainActor @Test func bestLastTimeAfterALongBreak() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TestData.exercise(db, id: "dl")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-800 * 86_400), exercises: [("dl", [(100, 5)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-400 * 86_400), exercises: [("dl", [(80, 8), (70, 8)])])
        }
        let model = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        try await model.start(dayId: nil)
        await model.addExercise("dl")
        let hint = try #require(model.snapshot?.hints["dl"])
        #expect(hint.windowMonths == nil)
        #expect(hint.lastSessionSet?.loadHundredths == 8000)
        let best: Double = 80 * (1 + 8.0 / 30)
        #expect(abs((hint.lastSessionBest ?? 0) - best) < 0.01)
    }

    @MainActor @Test func noBestLastTimeWhenTheLiftIsRecent() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try TestData.exercise(db, id: "dl")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-60 * 86_400), exercises: [("dl", [(100, 5)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: Date.now.addingTimeInterval(-5 * 86_400), exercises: [("dl", [(80, 8)])])
        }
        let model = ActiveWorkoutModel(db: db, notifier: FakeNotifier())
        try await model.start(dayId: nil)
        await model.addExercise("dl")
        #expect(model.snapshot?.hints["dl"]?.lastSessionBest == nil)
    }
}
