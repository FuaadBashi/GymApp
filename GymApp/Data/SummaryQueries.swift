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
        var id: String { exercise.id }
    }

    var workout: WorkoutRecord
    var duration: TimeInterval
    var volumeKg: Double
    var previousVolumeKg: Double?
    var setCount: Int
    var records: [Record]
    var muscles: [(muscle: Muscle, sets: Double)]
    var exercises: [ExerciseLine]

    static func == (a: WorkoutSummary, b: WorkoutSummary) -> Bool {
        a.workout == b.workout && a.volumeKg == b.volumeKg && a.previousVolumeKg == b.previousVolumeKg
            && a.records == b.records && a.exercises == b.exercises
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

        return WorkoutSummary(workout: workout, duration: (workout.endedAt ?? .now).timeIntervalSince(workout.startedAt),
                              volumeKg: volume, previousVolumeKg: previousVolume,
                              setCount: lines.flatMap(\.sets).filter { $0.type != .warmUp && $0.type != .drop }.count,
                              records: records, muscles: muscles(lines), exercises: lines)
    }

    /// Hard sets per muscle (rulebook §6): 1 per primary, 0.5 per secondary, for each completed
    /// set that is neither a warm-up nor a drop row (a drop row belongs to the set before it).
    static func muscles(_ lines: [WorkoutSummary.ExerciseLine]) -> [(muscle: Muscle, sets: Double)] {
        var counts: [Muscle: Double] = [:]
        for line in lines {
            let hard = line.sets.filter { $0.completedAt != nil && $0.type != .warmUp && $0.type != .drop }.count
            guard hard > 0 else { continue }
            for m in line.exercise.primaryMuscles { counts[m, default: 0] += Double(hard) }
            for m in line.exercise.secondaryMuscles { counts[m, default: 0] += Double(hard) * 0.5 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
    }

    private static func exerciseLines(_ db: Database, workoutId: String) throws -> [WorkoutSummary.ExerciseLine] {
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
        let bodyWeight = try BodyQueries.weightKg(db, onOrBefore: workout.startedAt)
        return lines.reduce(0) { total, line in
            total + TrainingMath.volumeKg(SetFormat.pastSets(line.sets), loadMode: line.exercise.loadMode, bodyWeightKg: bodyWeight)
        }
    }
}
