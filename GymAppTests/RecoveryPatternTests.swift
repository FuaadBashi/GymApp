import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 6.5: recovery and movement patterns on the Progress tab.
struct RecoveryPatternTests {
    let db = try! AppDatabase.inMemory()
    let now = TestData.day(30)

    @Test func recoveryWeightsHardSetsByTimeSinceAndIgnoresOlderThan72Hours() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "press")
            try db.execute(sql: "UPDATE exercise SET secondaryMuscles = '[\"triceps\"]' WHERE id = 'press'")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now, exercises: [("press", [(50, 8), (50, 8), (20, 10)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-36 * 3600), exercises: [("press", [(50, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-80 * 3600), exercises: [("press", [(50, 8)])])
            try db.execute(sql: "UPDATE workoutSet SET type = 'warmUp' WHERE loadHundredths = 2000")
        }
        let r = Dictionary(uniqueKeysWithValues: try db.reader.read { try ProgressQueries.recovery($0, now: now) }.map { ($0.muscle, $0.sets) })
        // Two fresh sets count 1 each, the set 36 hours ago ½; secondary muscles half of that.
        #expect(abs((r[.chest] ?? 0) - 2.5) < 1e-9)
        #expect(abs((r[.triceps] ?? 0) - 1.25) < 1e-9)
        #expect(r.count == 2)
    }

    @Test func patternChangeIsMeasuredFromEachLiftsFirstWeekInTheWindow() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench", pattern: .horizontalPush)
            try TestData.exercise(db, id: "incline", pattern: .horizontalPush)
            try TestData.exercise(db, id: "dip", pattern: .horizontalPush, loadMode: .bodyweightPlus)
            // Before the window: ignored.
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-70 * 86_400), exercises: [("bench", [(200, 1)])])
            // Bench: 100 three weeks ago, 105 now (+5%). Incline: 50 two weeks ago, 55 now (+10%).
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-21 * 86_400), exercises: [("bench", [(100, 1)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-14 * 86_400), exercises: [("incline", [(50, 1)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now, exercises: [("bench", [(105, 1)]), ("incline", [(55, 1)]), ("dip", [(20, 5)])])
        }
        let trends = try db.reader.read { try ProgressQueries.patterns($0, now: now, weekStartsOn: .monday) }
        #expect(trends.map(\.pattern) == [.horizontalPush])
        let weeks = try #require(trends.first?.weeks)
        #expect(weeks.map(\.change).prefix(2) == [0, 0])
        let last = try #require(weeks.last)
        #expect(last.start == HistoryQueries.weekStart(of: now, weekStartsOn: .monday))
        #expect(abs(last.change - 0.075) < 1e-9)
        #expect(weeks.count == 3)
    }
}
