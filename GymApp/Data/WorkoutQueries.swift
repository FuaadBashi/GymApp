import Foundation
import GRDB

nonisolated struct WorkoutSnapshot: Equatable {
    var workout: WorkoutRecord
    var items: [Item]

    nonisolated struct Item: Identifiable, Equatable {
        var workoutExercise: WorkoutExerciseRecord
        var exercise: ExerciseRecord
        var sets: [WorkoutSetRecord]       // position order, completed and planned
        var previous: ExerciseSession?     // rulebook §7, finished sessions only
        var previousIsSameDay: Bool
        var id: String { workoutExercise.id }
        var plannedSets: [WorkoutSetRecord] { sets.filter { $0.completedAt == nil } }
    }

    var completedSetCount: Int
    var totalSetCount: Int
}

nonisolated enum WorkoutQueries {
    static func inProgress(_ db: Database) throws -> WorkoutRecord? {
        try WorkoutRecord.filter(Column("endedAt") == nil).fetchOne(db)
    }

    static func snapshot(_ db: Database, workoutId: String, settings: AppSettings) throws -> WorkoutSnapshot {
        guard let workout = try WorkoutRecord.fetchOne(db, key: workoutId) else { throw WorkoutError.notFound }
        let workoutExercises = try WorkoutExerciseRecord.filter(Column("workoutId") == workoutId)
            .order(Column("position")).fetchAll(db)
        let exercises = Dictionary(uniqueKeysWithValues: try ExerciseRecord
            .filter(keys: Set(workoutExercises.map(\.exerciseId))).fetchAll(db).map { ($0.id, $0) })
        let sets = Dictionary(grouping: try WorkoutSetRecord
            .filter(workoutExercises.map(\.id).contains(Column("workoutExerciseId")))
            .order(Column("position")).fetchAll(db), by: \.workoutExerciseId)
        let days = try preferredDays(db, workout: workout, settings: settings)

        let items = try workoutExercises.compactMap { we -> WorkoutSnapshot.Item? in
            guard let exercise = exercises[we.exerciseId] else { return nil }
            let last = try ExerciseQueries.lastSession(db, exerciseId: exercise.id, preferringDays: days, before: workout.startedAt)
            return WorkoutSnapshot.Item(workoutExercise: we, exercise: exercise, sets: sets[we.id] ?? [],
                                        previous: last?.session, previousIsSameDay: last?.isSameDay ?? false)
        }
        let all = items.flatMap(\.sets)
        return WorkoutSnapshot(workout: workout, items: items,
                               completedSetCount: all.filter { $0.completedAt != nil }.count, totalSetCount: all.count)
    }

    /// The workout's day and the days it was copied from, when last time should prefer them.
    static func preferredDays(_ db: Database, workout: WorkoutRecord, settings: AppSettings) throws -> Set<String> {
        guard settings.lastTimeSource == .sameDay, let dayId = workout.programDayId else { return [] }
        return Set(try ProgramQueries.lineage(db, dayId: dayId))
    }
}
