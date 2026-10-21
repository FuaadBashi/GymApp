import Foundation
import GRDB
import Testing
@testable import GymApp

/// Redesign R.5: the end-of-workout headline and each lift's share of its best.
struct EndOfWorkoutTests {
    @Test func headlineNamesBestsThenLiftsUp() {
        #expect(SummaryView.headline(bests: 2, up: 5) == "2 bests, 5 lifts up")
        #expect(SummaryView.headline(bests: 1, up: 1) == "1 best, 1 lift up")
        #expect(SummaryView.headline(bests: 0, up: 3) == "3 lifts up")
        #expect(SummaryView.headline(bests: 0, up: 0) == "Workout logged")
    }

    @Test func shareOfBestIsTodayAgainstTheBestBeforeToday() {
        #expect(SummaryView.shareOfBest(today: 45.3, before: 123.5) == "37% of best")
        #expect(SummaryView.shareOfBest(today: 42, before: 34.5) == "new best")
        #expect(SummaryView.shareOfBest(today: 50, before: nil) == nil)
    }

    @Test func linesCarryTheBestBeforeToday() throws {
        let db = try AppDatabase.inMemory()
        let w = try db.writer.write { db -> WorkoutRecord in
            try TestData.exercise(db, id: "sq")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("sq", [(100, 5)])])
            return try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(30), exercises: [("sq", [(40, 4)])])
        }
        let line = try #require(try db.reader.read { try SummaryQueries.summary($0, workoutId: w.id) }.exercises.first)
        #expect(abs((line.bestBefore ?? 0) - 100 * (1 + 5.0 / 30)) < 0.01)
        #expect(abs((line.todayBest ?? 0) - 40 * (1 + 4.0 / 30)) < 0.01)
    }
}
