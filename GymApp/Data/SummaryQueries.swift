import Foundation
import GRDB

nonisolated struct WorkoutSummary: Equatable {
    nonisolated struct Record: Equatable, Identifiable {
        enum Kind: String { case heaviest = "Heaviest", e1RM = "Best est. 1RM" }
        var exercise: ExerciseRecord
        var kind: Kind
        var valueKg: Double
        var previousKg: Double
        var id: String { exercise.id + kind.rawValue }
    }

    nonisolated struct ExerciseLine: Equatable, Identifiable {
        var exercise: ExerciseRecord
        var sets: [WorkoutSetRecord]
        var note: String? = nil
        // Card 7.5: today against the last time, and the best this exercise reached today.
        var best: TrainingMath.BestStatus? = nil
        var bests: [String: TrainingMath.BestStatus] = [:]
        var lastTime: [WorkoutSetRecord]? = nil
        var e1RMChange: Double? = nil
        var volumeChange: Double? = nil
        /// Redesign R.5: today's best estimated 1RM and the best before today, for "x% of best".
        var todayBest: Double? = nil
        var bestBefore: Double? = nil
        var id: String { exercise.id }
    }

    /// Card 7.5: the workout the summary compares with (same day lineage first, else the last
    /// finished workout) and its totals.
    nonisolated struct Previous: Equatable {
        var workout: WorkoutRecord
        var duration: TimeInterval
        var volumeKg: Double
        var setCount: Int
        var records: Int
    }

    var workout: WorkoutRecord
    var duration: TimeInterval
    var volumeKg: Double
    var previousVolumeKg: Double?
    var setCount: Int
    var records: [Record]
    var muscles: [(muscle: Muscle, sets: Double)]
    var exercises: [ExerciseLine]
    var previous: Previous? = nil

    static func == (a: WorkoutSummary, b: WorkoutSummary) -> Bool {
        a.workout == b.workout && a.volumeKg == b.volumeKg && a.previousVolumeKg == b.previousVolumeKg
            && a.records == b.records && a.exercises == b.exercises && a.previous == b.previous
            && a.muscles.map(\.muscle) == b.muscles.map(\.muscle) && a.muscles.map(\.sets) == b.muscles.map(\.sets)
    }
}

/// Card 2.8: what the summary shows after Finish. Every figure comes from TrainingMath.
nonisolated enum SummaryQueries {
    static func summary(_ db: Database, workoutId: String) throws -> WorkoutSummary {
        guard let workout = try WorkoutRecord.fetchOne(db, key: workoutId) else { throw WorkoutError.notFound }
        let lines = try exerciseLines(db, workoutId: workoutId)
        let volume = try volumeKg(db, workout: workout, lines: lines)

        var previousVolume: Double?
        if let dayId = workout.programDayId {
            let days = try ProgramQueries.lineage(db, dayId: dayId)
            let previous = try WorkoutRecord.fetchOne(db, sql: """
                SELECT * FROM workout WHERE endedAt IS NOT NULL AND startedAt < ? AND id != ?
                  AND programDayId IN (\(days.map { _ in "?" }.joined(separator: ",")))
                ORDER BY startedAt DESC LIMIT 1
                """, arguments: StatementArguments([workout.startedAt, workout.id] as [any DatabaseValueConvertible]) + StatementArguments(days))
            if let previous {
                previousVolume = try volumeKg(db, workout: previous, lines: try exerciseLines(db, workoutId: previous.id))
            }
        }

        let records = try records(db, workout: workout, lines: lines)

        // Card 7.5: compare with the same day's lineage first, else the last finished workout.
        let days = try workout.programDayId.map { try ProgramQueries.lineage(db, dayId: $0) } ?? []
        var previous: WorkoutSummary.Previous?
        let before = try WorkoutRecord.filter(Column("endedAt") != nil && Column("startedAt") < workout.startedAt && Column("id") != workout.id)
            .order(Column("startedAt").desc)
        if let p = try (days.isEmpty ? nil : before.filter(days.contains(Column("programDayId"))).fetchOne(db)) ?? before.fetchOne(db) {
            let pLines = try exerciseLines(db, workoutId: p.id)
            previous = .init(workout: p, duration: (p.endedAt ?? p.startedAt).timeIntervalSince(p.startedAt),
                             volumeKg: try volumeKg(db, workout: p, lines: pLines), setCount: hardSetCount(pLines),
                             records: try self.records(db, workout: p, lines: pLines).count)
        }

        let bodyWeight = try BodyQueries.weightKg(db, onOrBefore: workout.startedAt)
        let annotated = try lines.map { line -> WorkoutSummary.ExerciseLine in
            var line = line
            let loadMode = line.exercise.loadMode
            let earlier = try ExerciseQueries.sessions(db, exerciseId: line.exercise.id)
                .filter { $0.workout.id != workout.id && $0.workout.startedAt < workout.startedAt }
            line.bests = ExerciseStats.statuses(line.sets, history: ExerciseStats.e1RMHistory(earlier, loadMode: loadMode),
                                                loadMode: loadMode, fallbackDate: workout.startedAt).bests
            line.best = line.bests.values.max { rank($0) < rank($1) }
            line.todayBest = TrainingMath.bests(SetFormat.pastSets(line.sets), loadMode: loadMode).bestE1RM
            line.bestBefore = TrainingMath.bests(SetFormat.pastSets(earlier.flatMap(\.sets)), loadMode: loadMode).bestE1RM
            if let last = try ExerciseQueries.lastSession(db, exerciseId: line.exercise.id, preferringDays: Set(days),
                                                          before: workout.startedAt) {
                line.lastTime = last.session.sets
                let todayBest = TrainingMath.bests(SetFormat.pastSets(line.sets), loadMode: loadMode).bestE1RM
                let lastBest = TrainingMath.bests(SetFormat.pastSets(last.session.sets), loadMode: loadMode).bestE1RM
                if let a = todayBest, let b = lastBest { line.e1RMChange = a - b }
                let lastWeight = try BodyQueries.weightKg(db, onOrBefore: last.session.workout.startedAt)
                line.volumeChange = TrainingMath.volumeKg(SetFormat.pastSets(line.sets), loadMode: loadMode, bodyWeightKg: bodyWeight)
                    - TrainingMath.volumeKg(SetFormat.pastSets(last.session.sets), loadMode: loadMode, bodyWeightKg: lastWeight)
            }
            return line
        }

        return WorkoutSummary(workout: workout, duration: (workout.endedAt ?? .now).timeIntervalSince(workout.startedAt),
                              volumeKg: volume, previousVolumeKg: previousVolume,
                              setCount: hardSetCount(lines),
                              records: records, muscles: muscles(lines), exercises: annotated, previous: previous)
    }

    /// Orders statuses for "the best this exercise reached": all-time, then longer windows.
    private static func rank(_ status: TrainingMath.BestStatus) -> Int {
        switch status {
        case .allTime: 100
        case .window(let months, _): months
        case .none: 0
        }
    }

    /// Heaviest and e1RM records set by a workout against every earlier session (card 2.8).
    static func records(_ db: Database, workout: WorkoutRecord, lines: [WorkoutSummary.ExerciseLine]) throws -> [WorkoutSummary.Record] {
        var records: [WorkoutSummary.Record] = []
        for line in lines {
            let now = TrainingMath.bests(SetFormat.pastSets(line.sets), loadMode: line.exercise.loadMode)
            let before = try ExerciseQueries.sessions(db, exerciseId: line.exercise.id)
                .filter { $0.workout.startedAt < workout.startedAt }
                .flatMap(\.sets)
            guard !before.isEmpty else { continue }
            let was = TrainingMath.bests(SetFormat.pastSets(before), loadMode: line.exercise.loadMode)
            if let a = now.heaviestKg, let b = was.heaviestKg, a > b {
                records.append(.init(exercise: line.exercise, kind: .heaviest, valueKg: a, previousKg: b))
            }
            if let a = now.bestE1RM, let b = was.bestE1RM, a - b > 0.01 {
                records.append(.init(exercise: line.exercise, kind: .e1RM, valueKg: a, previousKg: b))
            }
        }
        return records
    }

    /// Hard sets per muscle (rulebook §6): 1 per primary, 0.5 per secondary, for each completed
    /// set that is neither a warm-up nor a drop row (a drop row belongs to the set before it).
    /// Rulebook §6: a hard set is a completed set that is neither a warm-up nor a drop row.
    static func isHard(_ set: WorkoutSetRecord) -> Bool {
        set.completedAt != nil && set.type != .warmUp && set.type != .drop
    }

    static func muscles(_ lines: [WorkoutSummary.ExerciseLine]) -> [(muscle: Muscle, sets: Double)] {
        var counts: [Muscle: Double] = [:]
        for line in lines {
            let hard = line.sets.filter(isHard).count
            guard hard > 0 else { continue }
            for m in line.exercise.primaryMuscles { counts[m, default: 0] += Double(hard) }
            for m in line.exercise.secondaryMuscles { counts[m, default: 0] += Double(hard) * 0.5 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
    }

    static func exerciseLines(_ db: Database, workoutId: String) throws -> [WorkoutSummary.ExerciseLine] {
        let wes = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId).order(Column("position")).fetchAll(db)
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord.filter(keys: Set(wes.map(\.exerciseId))).fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord
            .filter(wes.map(\.id).contains(Column("workoutExerciseId")) && Column("completedAt") != nil)
            .order(Column("position")).fetchAll(db), by: \.workoutExerciseId)
        return wes.compactMap { we in
            guard let exercise = exercises[we.exerciseId], let done = sets[we.id], !done.isEmpty else { return nil }
            return .init(exercise: exercise, sets: done, note: we.note)
        }
    }

    private static func volumeKg(_ db: Database, workout: WorkoutRecord, lines: [WorkoutSummary.ExerciseLine]) throws -> Double {
        volumeKg(lines, bodyWeightKg: try BodyQueries.weightKg(db, onOrBefore: workout.startedAt))
    }

    /// Shared with the history list, so a row and its summary can never disagree.
    static func volumeKg(_ lines: [WorkoutSummary.ExerciseLine], bodyWeightKg: Double?) -> Double {
        lines.reduce(0) { total, line in
            total + TrainingMath.volumeKg(SetFormat.pastSets(line.sets), loadMode: line.exercise.loadMode, bodyWeightKg: bodyWeightKg)
        }
    }

    /// Completed sets that count as sets: warm-ups and drop rows don't (rulebook §3).
    static func hardSetCount(_ lines: [WorkoutSummary.ExerciseLine]) -> Int {
        lines.flatMap(\.sets).filter { $0.type != .warmUp && $0.type != .drop }.count
    }
}
