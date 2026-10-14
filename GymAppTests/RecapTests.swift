import Foundation
import GRDB
import Testing
@testable import GymApp

/// Card 6.6: monthly and yearly recaps.
struct RecapTests {
    let db = try! AppDatabase.inMemory()
    let calendar = HistoryQueries.calendar(.monday)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 10))! }

    @Test func aYearAddsUpLikeHistoryWithStreakRecordsAndMonths() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            // Weeks of 5, 12 and 19 Jan 2026 in a row, then 2 Feb after a gap; one in 2025.
            for (y, m, d, kg) in [(2026, 1, 6, 50.0), (2026, 1, 13, 55.0), (2026, 1, 20, 50.0), (2026, 2, 3, 60.0), (2025, 6, 1, 40.0)] {
                try TestData.finishedWorkout(db, dayId: nil, startedAt: date(y, m, d), exercises: [("bench", [(kg, 5), (kg, 5)])])
            }
        }
        let r = try db.reader.read { try RecapQueries.year($0, 2026, weekStartsOn: .monday) }
        let items = try db.reader.read { try HistoryQueries.items($0, from: r.from, to: r.to) }
        #expect(r.workouts == 4 && r.sets == 8)
        #expect(r.volumeKg == items.reduce(0) { $0 + $1.volumeKg })
        #expect(r.seconds == 4 * 3600)
        #expect(r.longestStreakWeeks == 3)
        // 50 on 6 Jan beats 2025's 40, then 55 and 60; each session sets heaviest and e1RM.
        #expect(r.records == 6)
        #expect(r.topMuscle == .chest && r.topMuscleSets == 8)
        #expect(r.months.count == 12)
        #expect(r.months.map(\.workouts).prefix(3) == [3, 1, 0])

        let jan = try db.reader.read { try RecapQueries.month($0, containing: date(2026, 1, 15), weekStartsOn: .monday) }
        #expect(jan.workouts == 3 && jan.months.isEmpty && jan.longestStreakWeeks == 3)
        #expect(try db.reader.read { try RecapQueries.years($0, calendar: calendar) } == [2026, 2025])
    }

    @Test func yearsBefore2022AreLeftOut() throws {
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: date(2021, 5, 1), exercises: [("bench", [(50, 5)])])
        }
        #expect(try db.reader.read { try RecapQueries.years($0, calendar: calendar) }.isEmpty)
    }
}
