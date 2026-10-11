import Foundation
import GRDB

nonisolated struct WorkoutListItem: Identifiable, Equatable {
    var workout: WorkoutRecord
    var duration: TimeInterval        // endedAt − startedAt
    var setCount: Int                 // completed, not warm-up, not drop
    var volumeKg: Double              // as SummaryQueries
    var exerciseNames: [String]       // position order
    var dayId: String?                // programDayId
    var id: String { workout.id }
}

nonisolated struct HistoryWeek: Identifiable, Equatable {
    var start: Date                   // local midnight of the first day of the week
    var workouts: [WorkoutListItem]   // newest first
    var id: Date { start }
}

/// Card 3.1: the finished workouts, grouped by week. History means finished workouts and
/// completed sets.
nonisolated enum HistoryQueries {
    static func calendar(_ weekStartsOn: WeekStart, base: Calendar = .current) -> Calendar {
        var c = base
        c.firstWeekday = weekStartsOn == .sunday ? 1 : 2
        return c
    }

    /// Rulebook §6: a workout belongs to the local date it started.
    static func weekStart(of date: Date, weekStartsOn: WeekStart, calendar: Calendar = .current) -> Date {
        let c = Self.calendar(weekStartsOn, base: calendar)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }

    /// Every finished workout with its figures, newest first. One pass over all sets: the real
    /// history has thousands, and a query per workout is too slow for a scrolling list.
    static func items(_ db: Database, from: Date? = nil, to: Date? = nil) throws -> [WorkoutListItem] {
        var sql = "SELECT * FROM workout WHERE endedAt IS NOT NULL"
        var args: [any DatabaseValueConvertible] = []
        if let from { sql += " AND startedAt >= ?"; args.append(from) }
        if let to { sql += " AND startedAt < ?"; args.append(to) }
        sql += " ORDER BY startedAt DESC"
        let workouts = try WorkoutRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        guard !workouts.isEmpty else { return [] }
        let ids = Set(workouts.map(\.id))

        let wes = try WorkoutExerciseRecord.fetchAll(db, sql: """
            SELECT we.* FROM workoutExercise we JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL ORDER BY we.workoutId, we.position
            """).filter { ids.contains($0.workoutId) }
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord
            .filter(keys: Set(wes.map(\.exerciseId))).fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord.fetchAll(db, sql: """
            SELECT s.* FROM workoutSet s
            JOIN workoutExercise we ON we.id = s.workoutExerciseId
            JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL AND s.completedAt IS NOT NULL
            ORDER BY s.workoutExerciseId, s.position
            """), by: \.workoutExerciseId)
        let byWorkout = Dictionary(grouping: wes, by: \.workoutId)
        let weight = try BodyQueries.weightLookup(db)

        return workouts.map { workout in
            let lines: [WorkoutSummary.ExerciseLine] = (byWorkout[workout.id] ?? []).compactMap { we in
                guard let exercise = exercises[we.exerciseId], let done = sets[we.id], !done.isEmpty else { return nil }
                return .init(exercise: exercise, sets: done)
            }
            return WorkoutListItem(workout: workout,
                                   duration: (workout.endedAt ?? workout.startedAt).timeIntervalSince(workout.startedAt),
                                   setCount: SummaryQueries.hardSetCount(lines),
                                   volumeKg: SummaryQueries.volumeKg(lines, bodyWeightKg: weight(workout.startedAt)),
                                   exerciseNames: lines.map(\.exercise.name),
                                   dayId: workout.programDayId)
        }
    }

    /// Newest week first; only weeks that have a workout.
    static func weeks(_ db: Database, settings: AppSettings) throws -> [HistoryWeek] {
        group(try items(db), weekStartsOn: settings.weekStartsOn)
    }

    static func group(_ items: [WorkoutListItem], weekStartsOn: WeekStart) -> [HistoryWeek] {
        var weeks: [HistoryWeek] = []
        for item in items {   // already newest first
            let start = weekStart(of: item.workout.startedAt, weekStartsOn: weekStartsOn)
            if weeks.last?.start == start { weeks[weeks.count - 1].workouts.append(item) }
            else { weeks.append(HistoryWeek(start: start, workouts: [item])) }
        }
        return weeks
    }

    /// Local start of day → the program day of each finished workout that day, in the month
    /// containing `date`.
    static func workoutDays(_ db: Database, inMonthOf date: Date, calendar: Calendar = .current) throws -> [Date: [String?]] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [:] }
        let rows = try Row.fetchAll(db, sql: """
            SELECT startedAt, programDayId FROM workout
            WHERE endedAt IS NOT NULL AND startedAt >= ? AND startedAt < ? ORDER BY startedAt
            """, arguments: [month.start, month.end])
        var days: [Date: [String?]] = [:]
        for row in rows {
            let started: Date = row["startedAt"]
            days[calendar.startOfDay(for: started), default: []].append(row["programDayId"])
        }
        return days
    }

    /// Finished workouts this week, against the active program's goal.
    static func sessionsThisWeek(_ db: Database, settings: AppSettings, now: Date) throws -> (done: Int, goal: Int?) {
        let start = weekStart(of: now, weekStartsOn: settings.weekStartsOn)
        let done = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout WHERE endedAt IS NOT NULL AND startedAt >= ?",
                                    arguments: [start]) ?? 0
        return (done, try ProgramQueries.activeProgram(db)?.sessionsPerWeekGoal)
    }
}
