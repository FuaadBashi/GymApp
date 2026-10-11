import Foundation
import GRDB
import Testing
@testable import GymApp

struct ProgressTests {
    let db = try! AppDatabase.inMemory()

    @Test func weeklyTotalsEqualHistoryAndIncludeEmptyWeeks() throws {
        let now = TestData.day(30)
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            for n in [2, 3, 16, 29] {
                try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(n), exercises: [("bench", [(50, 10)])])
            }
        }
        let items = try db.reader.read { try HistoryQueries.items($0) }
        let weeks = ProgressQueries.weeks(items, weekStartsOn: .sunday, now: now)
        #expect(weeks.count == 12)
        #expect(weeks.map(\.start) == weeks.map(\.start).sorted())
        #expect(weeks.last?.start == HistoryQueries.weekStart(of: now, weekStartsOn: .sunday))
        #expect(weeks.reduce(0) { $0 + $1.sessions } == 4)
        #expect(weeks.reduce(0) { $0 + $1.volumeKg } == items.reduce(0) { $0 + $1.volumeKg })
        #expect(weeks.contains { $0.sessions == 0 && $0.volumeKg == 0 })
        #expect(weeks.reduce(0) { $0 + $1.seconds } == 4 * 3600)
    }

    @Test func musclesCountOnlyTheWeekAsked() throws {
        try db.writer.write { db in
            var bench = try TestData.exercise(db, id: "bench")
            bench.primaryMuscles = [.chest]; bench.secondaryMuscles = [.triceps]
            try bench.update(db)
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(3), exercises: [("bench", [(50, 10), (50, 10)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(12), exercises: [("bench", [(50, 10)])])
        }
        let m = try db.reader.read { try ProgressQueries.muscles($0, from: TestData.day(1), to: TestData.day(8)) }
        #expect(m.map(\.muscle) == [.chest, .triceps])
        #expect(m.map(\.sets) == [2, 1])
    }

    @Test func recentRecordsAreNewestFirstAndNeedEarlierHistory() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(1), exercises: [("bench", [(50, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(3), exercises: [("bench", [(55, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(5), exercises: [("bench", [(50, 8)])])
            try TestData.finishedWorkout(db, dayId: nil, startedAt: TestData.day(7), exercises: [("bench", [(55, 10)])])
        }
        let r = try db.reader.read { try ProgressQueries.recentRecords($0) }
        #expect(r.map(\.date) == [7, 3, 3].map(TestData.day))
        #expect(r[0].kind == .e1RM && r[0].previousKg > 69 && r[0].previousKg < 70)
        #expect(Set(r.dropFirst().map(\.kind)) == [.heaviest, .e1RM])
    }

    @Test func aWeightIsSavedOncePerDayAndReadBackInKg() throws {
        let today = TestData.day(4)
        try db.writer.write { db in
            try ProgressQueries.addWeight(db, value: 200, unit: .lb, on: today)
            try ProgressQueries.addWeight(db, value: 90.5, unit: .kg, on: today)
        }
        let w = try db.reader.read { try ProgressQueries.bodyWeights($0) }
        #expect(w.count == 1 && w[0].kg == 90.5)
        #expect(try db.reader.read { try BodyQueries.weightKg($0, onOrBefore: today) } == 90.5)
    }

    @MainActor @Test func theBodyMapCoversEveryMuscle() throws {
        let map = try #require(BodyMap.bundled)
        #expect(map.coveredMuscles == Set(Muscle.allCases))
        #expect(map.figures["front"]?.isEmpty == false && map.figures["back"]?.isEmpty == false)
        let regions = map.figures.values.flatMap { $0 }
        #expect(regions.allSatisfy { $0.muscles.allSatisfy { Muscle(rawValue: $0) != nil } })
    }
}
