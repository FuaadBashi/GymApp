import Foundation
import GRDB
import Testing
@testable import GymApp

@Suite struct WeeklyDigestTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func itFiresAt7pmOnTheLastDayOfTheTrainingWeek() {
        // 25 Oct 2026 is a Sunday. Week starting Monday: the last day is Sunday the 25th.
        #expect(WeeklyDigest.fireDate(now: date(2026, 10, 21), weekStartsOn: .monday, calendar: calendar) == date(2026, 10, 25, 19))
        // Week starting Sunday: the last day is Saturday the 31st.
        #expect(WeeklyDigest.fireDate(now: date(2026, 10, 26), weekStartsOn: .sunday, calendar: calendar) == date(2026, 10, 31, 19))
        // After 19:00 on the last day, it moves to next week.
        #expect(WeeklyDigest.fireDate(now: date(2026, 10, 25, 20), weekStartsOn: .monday, calendar: calendar) == date(2026, 11, 1, 19))
    }

    @Test func theMessageUsesTheWeeksRecapFigures() {
        let recap = Recap(from: .now, to: .now, workouts: 3, seconds: 9_000, volumeKg: 12_450.4, sets: 34, records: 2,
                          topMuscle: .chest, topMuscleSets: 9.25, longestStreakWeeks: 1, months: [])
        #expect(WeeklyDigest.message(recap).body == "3 workouts · 34 sets · 12,450 kg lifted · 2 records. Most trained: chest (9.3 hard sets).")
        var one = recap
        one.workouts = 1; one.records = 0; one.topMuscle = nil
        #expect(WeeklyDigest.message(one).body == "1 workout · 34 sets · 12,450 kg lifted.")
        one.workouts = 0
        #expect(WeeklyDigest.message(one).body.hasPrefix("No workouts logged this week"))
    }

    @Test func contentComesFromTheDatabase() throws {
        let db = try AppDatabase.inMemory()
        let now = TestData.base.addingTimeInterval(3 * 86_400)
        try db.writer.write { db in
            try TestData.exercise(db, id: "bench")
            try TestData.finishedWorkout(db, dayId: nil, startedAt: now.addingTimeInterval(-3_600), exercises: [("bench", [(kg: 60, reps: 5)])])
        }
        let c = try db.reader.read { try WeeklyDigest.content($0, now: now) }
        #expect(c.fire > now)
        // TestData.base is a Monday; three days on is Thursday, so the workout is in the week covered.
        #expect(c.body.hasPrefix("1 workout · 1 set · 300 kg lifted"))
    }
}
