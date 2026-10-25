import Foundation
import Testing
@testable import GymApp

/// Rulebook §16.
@Suite struct BreakGuardTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; c.firstWeekday = 2; return c }
    // Monday 5 October 2026 starts a week.
    func day(_ n: Int, _ h: Int = 20) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + n, hour: h))! }
    func weekStart(_ d: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: d)!.start }
    func status(_ days: [Int], now: Int, goal: Int = 3) -> BreakGuard.Status {
        BreakGuard.status(workouts: days.map { day($0) }, goal: goal, now: day(now, 12), weekStart: weekStart, calendar: calendar)
    }

    @Test func aFullWeekSaysNothing() {
        #expect(status([0, 2, 4, 7, 9, 11], now: 14).message == nil)
    }

    @Test func oneShortWeekAsksNotToMissTwice() {
        let s = status([0, 2, 4, 7], now: 14)
        #expect(s.shortWeeksInRow == 1)
        #expect(s.message?.hasPrefix("Last week was short of 3 sessions. Never miss twice: 3 this week") == true)
        #expect(status([0, 2, 4, 7, 14], now: 15).message?.contains("2 this week") == true)
    }

    @Test func twoShortWeeksSayItPlainly() {
        let s = status([0, 2, 4, 7, 14], now: 21)
        #expect(s.shortWeeksInRow == 2)
        #expect(s.message?.hasPrefix("2 weeks below your 3 a week") == true)
    }

    @Test func meetingThisWeeksGoalClearsTheWarning() {
        #expect(status([7, 21, 22, 23], now: 24).message == nil)
    }

    @Test func aSlideIsCaughtBeforeAnyWeekIsShortOfAGoalOfOne() {
        // Three a week for 8 weeks, then one a week for 4: the goal of 1 is met, the slide is not.
        var earlier: [Int] = []
        for w in 0..<8 { earlier += [w * 7, w * 7 + 2, w * 7 + 4] }
        let recent: [Int] = [56, 63, 70, 77]
        let s = status(earlier + recent, now: 84, goal: 1)
        #expect(s.shortWeeksInRow == 0)
        #expect(s.recentPerWeek == 1 && s.earlierPerWeek == 3)
        #expect(s.message?.hasPrefix("Fewer sessions lately: 1.0 a week, down from 3.0") == true)
    }

    @Test func aNewUserWithNoHistoryIsNotWarned() {
        #expect(status([], now: 3).message == nil)
    }

    @Test func theNudgeComesAtTheUsualHourWhenTheGapGetsTooLong() {
        let starts = [day(0, 19), day(2, 20), day(4, 20), day(7, 21), day(9, 20)]
        #expect(BreakGuard.usualHour(starts, calendar: calendar) == 20)
        // Goal 3 a week: at most 3 days between sessions, so the nudge is on day 4 after the last.
        let nudge = BreakGuard.nudgeDate(lastWorkout: day(9), goal: 3, usualHour: 20, now: day(9, 22), calendar: calendar)
        #expect(nudge == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + 13, hour: 20)))
        #expect(BreakGuard.nudgeDate(lastWorkout: day(0), goal: 3, usualHour: 20, now: day(30), calendar: calendar) == nil, "never in the past")
        #expect(BreakGuard.nudgeDate(lastWorkout: nil, goal: 3, usualHour: 20, now: day(0), calendar: calendar) == nil)
    }
}
