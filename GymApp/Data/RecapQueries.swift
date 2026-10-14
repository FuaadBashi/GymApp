import Foundation
import GRDB

/// Card 6.6: a month or year at a glance, built on HistoryQueries, ProgressQueries and
/// SummaryQueries so every figure matches History and Progress.
nonisolated struct Recap: Equatable {
    var from: Date
    var to: Date
    var workouts: Int
    var seconds: TimeInterval
    var volumeKg: Double
    var sets: Int                      // completed, not warm-up, not drop (WorkoutListItem)
    var records: Int                   // heaviest and e1RM records set in the period
    var topMuscle: Muscle?
    var topMuscleSets: Double
    var longestStreakWeeks: Int        // consecutive weeks with at least one workout
    var months: [Month]                // for a year: each month with its totals

    nonisolated struct Month: Identifiable, Equatable {
        var start: Date
        var workouts: Int
        var volumeKg: Double
        var id: Date { start }
    }
}

nonisolated enum RecapQueries {
    static let firstYear = 2022

    /// Years with finished workouts from 2022 on, newest first.
    static func years(_ db: Database, calendar: Calendar = .current) throws -> [Int] {
        let dates = try Date.fetchAll(db, sql: "SELECT startedAt FROM workout WHERE endedAt IS NOT NULL")
        return Set(dates.map { calendar.component(.year, from: $0) }).filter { $0 >= firstYear }.sorted(by: >)
    }

    static func year(_ db: Database, _ year: Int, weekStartsOn: WeekStart) throws -> Recap {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let from = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let to = calendar.date(byAdding: .year, value: 1, to: from)!
        return try recap(db, from: from, to: to, weekStartsOn: weekStartsOn, byMonth: true)
    }

    static func month(_ db: Database, containing date: Date, weekStartsOn: WeekStart) throws -> Recap {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let from = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let to = calendar.date(byAdding: .month, value: 1, to: from)!
        return try recap(db, from: from, to: to, weekStartsOn: weekStartsOn, byMonth: false)
    }

    static func recap(_ db: Database, from: Date, to: Date, weekStartsOn: WeekStart, byMonth: Bool) throws -> Recap {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let items = try HistoryQueries.items(db, from: from, to: to)
        let muscles = try ProgressQueries.muscles(db, from: from, to: to)
        let records = try ProgressQueries.recentRecords(db, limit: .max).filter { $0.date >= from && $0.date < to }

        let weeks = Set(items.map { HistoryQueries.weekStart(of: $0.workout.startedAt, weekStartsOn: weekStartsOn) }).sorted()
        var longest = 0, run = 0
        var previous: Date?
        for week in weeks {
            let next = previous.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) }
            run = next.map { calendar.isDate($0, inSameDayAs: week) } == true ? run + 1 : 1
            longest = max(longest, run)
            previous = week
        }

        var months: [Recap.Month] = []
        if byMonth {
            var start = from
            while start < to {
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                let inMonth = items.filter { $0.workout.startedAt >= start && $0.workout.startedAt < end }
                months.append(.init(start: start, workouts: inMonth.count, volumeKg: inMonth.reduce(0) { $0 + $1.volumeKg }))
                start = end
            }
        }
        return Recap(from: from, to: to, workouts: items.count, seconds: items.reduce(0) { $0 + $1.duration },
                     volumeKg: items.reduce(0) { $0 + $1.volumeKg }, sets: items.reduce(0) { $0 + $1.setCount },
                     records: records.count, topMuscle: muscles.first?.muscle, topMuscleSets: muscles.first?.sets ?? 0,
                     longestStreakWeeks: longest, months: months)
    }
}
