import Foundation
import GRDB

nonisolated struct WeekTotals: Identifiable, Equatable {
    var start: Date
    var volumeKg: Double
    var sessions: Int
    var seconds: TimeInterval
    var id: Date { start }
}

/// Card 6.2: the Progress steps card.
nonisolated struct StepsSummary: Equatable {
    var days: [(day: String, steps: Int)]
    /// Mean over the days in `days` that have a count.
    var dailyAverage: Int?
    /// Daily averages for this week so far and the whole of last week.
    var thisWeek: Int?
    var lastWeek: Int?

    static func == (a: StepsSummary, b: StepsSummary) -> Bool {
        a.days.map(\.day) == b.days.map(\.day) && a.days.map(\.steps) == b.days.map(\.steps)
            && a.dailyAverage == b.dailyAverage && a.thisWeek == b.thisWeek && a.lastWeek == b.lastWeek
    }
}

/// Card 6.5: one movement pattern's weekly best-e1RM change.
nonisolated struct PatternTrend: Identifiable, Equatable {
    var pattern: MovementPattern
    /// Week start → mean change against each exercise's baseline, as a fraction (0.05 = +5%).
    var weeks: [(start: Date, change: Double)]
    var id: MovementPattern { pattern }

    static func == (a: PatternTrend, b: PatternTrend) -> Bool {
        a.pattern == b.pattern && a.weeks.map(\.start) == b.weeks.map(\.start) && a.weeks.map(\.change) == b.weeks.map(\.change)
    }
}

nonisolated struct RecentRecord: Identifiable, Equatable {
    var exercise: ExerciseRecord
    var kind: WorkoutSummary.Record.Kind
    var valueKg: Double
    var previousKg: Double
    var date: Date
    var workoutId: String
    var id: String { workoutId + exercise.id + kind.rawValue }
}

/// Card 3.5: the Progress tab. Built on HistoryQueries and SummaryQueries so its totals can
/// never disagree with History.
nonisolated enum ProgressQueries {
    /// The last `count` weeks ending with the week containing `now`, oldest first, empty weeks
    /// included as zero.
    static func weeks(_ items: [WorkoutListItem], weekStartsOn: WeekStart, now: Date, count: Int = 12) -> [WeekTotals] {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let current = HistoryQueries.weekStart(of: now, weekStartsOn: weekStartsOn)
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var totals = Dictionary(uniqueKeysWithValues: starts.map { ($0, WeekTotals(start: $0, volumeKg: 0, sessions: 0, seconds: 0)) })
        for item in items {
            let start = HistoryQueries.weekStart(of: item.workout.startedAt, weekStartsOn: weekStartsOn)
            guard var t = totals[start] else { continue }
            t.volumeKg += item.volumeKg
            t.sessions += 1
            t.seconds += item.duration
            totals[start] = t
        }
        return starts.compactMap { totals[$0] }
    }

    /// Hard sets per muscle (rulebook §6) over the finished workouts that started in
    /// [from, to).
    static func muscles(_ db: Database, from: Date, to: Date) throws -> [(muscle: Muscle, sets: Double)] {
        let ids = try String.fetchAll(db, sql: "SELECT id FROM workout WHERE endedAt IS NOT NULL AND startedAt >= ? AND startedAt < ?",
                                      arguments: [from, to])
        // Only the sets are needed: a full summary also compares with last time and replays records.
        let lines = try ids.flatMap { try SummaryQueries.exerciseLines(db, workoutId: $0) }
        return SummaryQueries.muscles(lines)
    }

    /// Records set by beating every earlier session, newest first. One pass per exercise over
    /// its sessions in date order, through TrainingMath.bests.
    static func recentRecords(_ db: Database, limit: Int = 20) throws -> [RecentRecord] {
        let exerciseIds = try String.fetchAll(db, sql: """
            SELECT DISTINCT we.exerciseId FROM workoutExercise we JOIN workout w ON w.id = we.workoutId
            WHERE w.endedAt IS NOT NULL
            """)
        var records: [RecentRecord] = []
        for id in exerciseIds {
            guard let exercise = try ExerciseRecord.fetchOne(db, key: id),
                  exercise.loadMode != .bodyweightPlus, exercise.loadMode != .repsOnly else { continue }
            let sessions = try ExerciseQueries.sessions(db, exerciseId: id).sorted { $0.workout.startedAt < $1.workout.startedAt }
            var best = TrainingMath.Bests()
            // A workout can hold an exercise twice; group so a record is judged per workout.
            var seen: [String: [WorkoutSetRecord]] = [:]
            var order: [(WorkoutRecord, [WorkoutSetRecord])] = []
            for s in sessions {
                if seen[s.workout.id] == nil { order.append((s.workout, [])) }
                seen[s.workout.id, default: []].append(contentsOf: s.sets)
            }
            for (workout, _) in order {
                let now = TrainingMath.bests(SetFormat.pastSets(seen[workout.id] ?? []), loadMode: exercise.loadMode)
                let first = best.heaviestKg == nil && best.bestE1RM == nil
                if !first {
                    if let a = now.heaviestKg, let b = best.heaviestKg, a > b {
                        records.append(.init(exercise: exercise, kind: .heaviest, valueKg: a, previousKg: b, date: workout.startedAt, workoutId: workout.id))
                    }
                    if let a = now.bestE1RM, let b = best.bestE1RM, a - b > 0.01 {
                        records.append(.init(exercise: exercise, kind: .e1RM, valueKg: a, previousKg: b, date: workout.startedAt, workoutId: workout.id))
                    }
                }
                best.heaviestKg = [best.heaviestKg, now.heaviestKg].compactMap { $0 }.max()
                best.bestE1RM = [best.bestE1RM, now.bestE1RM].compactMap { $0 }.max()
            }
        }
        return Array(records.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }.prefix(limit))
    }

    /// Body weights, oldest first, in kg.
    /// Typed and Apple Health weights together (BodyQueries.weights).
    static func bodyWeights(_ db: Database) throws -> [(date: String, kg: Double)] {
        try BodyQueries.weights(db).map { ($0.day, $0.kg) }
    }

    // MARK: Recovery and movement patterns (card 6.5)

    static let recoveryHours: Double = 72

    /// Hard sets per muscle (rulebook §6: 1 per primary, ½ per secondary) logged in the last
    /// 72 hours, each weighted by how recent it is: a set counts fully just after it is done
    /// and nothing once 72 hours have passed, falling linearly. Unfinished workouts count.
    static func recovery(_ db: Database, now: Date) throws -> [(muscle: Muscle, sets: Double)] {
        let since = now.addingTimeInterval(-recoveryHours * 3600)
        let rows = try Row.fetchAll(db, sql: """
            SELECT s.*, we.exerciseId AS exerciseId FROM workoutSet s JOIN workoutExercise we ON we.id = s.workoutExerciseId
            WHERE s.completedAt IS NOT NULL AND s.completedAt >= ? AND s.completedAt <= ?
            """, arguments: [since, now])
        let ids = Set(rows.map { $0["exerciseId"] as String })
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord.filter(keys: ids).fetchAll(db).map { ($0.id, $0) })
        var counts: [Muscle: Double] = [:]
        for row in rows {
            let set = try WorkoutSetRecord(row: row)
            let exerciseId: String = row["exerciseId"]
            guard SummaryQueries.isHard(set), let done = set.completedAt, let exercise = exercises[exerciseId] else { continue }
            let weight = max(0, 1 - now.timeIntervalSince(done) / (recoveryHours * 3600))
            for m in exercise.primaryMuscles { counts[m, default: 0] += weight }
            for m in exercise.secondaryMuscles { counts[m, default: 0] += weight * 0.5 }
        }
        return counts.filter { $0.value > 0.005 }.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
    }

    static let trackedPatterns: [MovementPattern] = [.squat, .hinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull]

    /// For each tracked pattern and each of the last `weeks` weeks: the mean, over that
    /// pattern's exercises trained that week, of the week's best e1RM against the exercise's
    /// best e1RM in its first trained week of the window, so a lift's line starts at 0 and the
    /// pattern shows progress within the window even after a break. Body-weight and reps-only
    /// exercises (no e1RM, rulebook §5) are left out. Bests come from TrainingMath.bests.
    static func patterns(_ db: Database, now: Date, weekStartsOn: WeekStart, weeks: Int = 8) throws -> [PatternTrend] {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let current = HistoryQueries.weekStart(of: now, weekStartsOn: weekStartsOn)
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var out: [PatternTrend] = []
        for pattern in trackedPatterns {
            let exercises = try ExerciseRecord.filter(Column("movementPattern") == pattern.rawValue).fetchAll(db)
                .filter { $0.loadMode != .bodyweightPlus && $0.loadMode != .repsOnly }
            var changes: [Date: [Double]] = [:]
            for exercise in exercises {
                let sessions = try ExerciseQueries.sessions(db, exerciseId: exercise.id)
                func best(_ list: [ExerciseSession]) -> Double? {
                    TrainingMath.bests(SetFormat.pastSets(list.flatMap(\.sets)), loadMode: exercise.loadMode).bestE1RM
                }
                var baseline: Double?
                for start in starts {
                    let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
                    let week = sessions.filter { $0.workout.startedAt >= start && $0.workout.startedAt < end && $0.workout.startedAt <= now }
                    guard let value = best(week), value > 0 else { continue }
                    if baseline == nil { baseline = value }
                    if let baseline { changes[start, default: []].append(value / baseline - 1) }
                }
            }
            let points = starts.compactMap { start in changes[start].map { (start: start, change: $0.reduce(0, +) / Double($0.count)) } }
            if !points.isEmpty { out.append(PatternTrend(pattern: pattern, weeks: points)) }
        }
        return out
    }

    /// Daily steps for the last 30 days ending today, with averages. Days without a count
    /// are left out rather than counted as zero.
    static func steps(_ db: Database, now: Date, weekStartsOn: WeekStart) throws -> StepsSummary {
        let calendar = HistoryQueries.calendar(weekStartsOn)
        let today = calendar.startOfDay(for: now)
        let thisStart = HistoryQueries.weekStart(of: now, weekStartsOn: weekStartsOn)
        let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisStart) ?? thisStart
        let from = min(calendar.date(byAdding: .day, value: -29, to: today) ?? today, lastStart)
        let all = try BodyQueries.steps(db, since: DayString.from(from)).filter { $0.day <= DayString.from(today) }
        func average(_ list: [(day: String, steps: Int)]) -> Int? {
            list.isEmpty ? nil : Int((Double(list.map(\.steps).reduce(0, +)) / Double(list.count)).rounded())
        }
        let first30 = DayString.from(calendar.date(byAdding: .day, value: -29, to: today) ?? today)
        let days = all.filter { $0.day >= first30 }
        let this = DayString.from(thisStart), last = DayString.from(lastStart)
        return StepsSummary(days: days, dailyAverage: average(days),
                            thisWeek: average(all.filter { $0.day >= this }),
                            lastWeek: average(all.filter { $0.day >= last && $0.day < this }))
    }

    /// One weight per day: a second entry the same day replaces the first's weight.
    static func addWeight(_ db: Database, value: Double, unit: WeightUnit, on date: Date) throws {
        let day = DayString.from(date)
        let hundredths = Int((value * 100).rounded())
        if var existing = try BodyEntryRecord.filter(Column("date") == day && Column("source") == RecordSource.app.rawValue).fetchOne(db) {
            existing.weightHundredths = hundredths
            existing.weightUnit = unit
            try existing.update(db)
        } else {
            try BodyEntryRecord(id: UUID().uuidString, date: day, weightHundredths: hundredths, weightUnit: unit,
                                bodyFatPercent: nil, measurements: [:], source: .app, externalId: nil).insert(db)
        }
    }
}
