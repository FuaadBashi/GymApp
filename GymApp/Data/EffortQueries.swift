import Foundation
import GRDB

/// Rulebook §6a: each set's hard-set weight, judged against the exercise's recent best.
nonisolated enum EffortQueries {
    /// The best e1RM of the exercise's completed working and failed sets in finished workouts that
    /// started in the 56 days before `before`, other than `excluding`. Nil for body-weight and
    /// reps-only exercises, and when there is no such set.
    static func reference(_ db: Database, exercise: ExerciseRecord, before: Date, excluding workoutId: String) throws -> Double? {
        guard exercise.loadMode != .bodyweightPlus, exercise.loadMode != .repsOnly else { return nil }
        let since = before.addingTimeInterval(-TrainingMath.effortWindowDays * 86_400)
        let sets = try WorkoutSetRecord.fetchAll(db, sql: """
            SELECT s.* FROM workoutSet s
            JOIN workoutExercise we ON we.id = s.workoutExerciseId JOIN workout w ON w.id = we.workoutId
            WHERE we.exerciseId = ? AND w.id != ? AND w.endedAt IS NOT NULL AND w.startedAt >= ? AND w.startedAt < ?
              AND s.completedAt IS NOT NULL AND s.type IN ('working', 'failed') AND s.loadHundredths > 0 AND s.reps >= 1
            """, arguments: [exercise.id, workoutId, since, before])
        return sets.map { TrainingMath.e1RM(kg: SetFormat.kg($0), reps: $0.reps) }.max()
    }

    static func weight(_ set: WorkoutSetRecord, reference: Double?) -> Double {
        guard set.completedAt != nil else { return 0 }
        let e1RM = (set.loadHundredths ?? 0) > 0 && set.reps >= 1 ? TrainingMath.e1RM(kg: SetFormat.kg(set), reps: set.reps) : nil
        return TrainingMath.effort(type: set.type, repsInReserve: set.repsInReserve, annotations: set.annotations,
                                   e1RM: e1RM, reference: reference)
    }

    /// Hard sets per muscle for one workout's lines: each set's weight counts 1× for each
    /// primary muscle and ½× for each secondary (§6), added into `counts`.
    static func addMuscles(_ db: Database, lines: [WorkoutSummary.ExerciseLine], workout: WorkoutRecord,
                           into counts: inout [Muscle: Double]) throws {
        var references: [String: Double?] = [:]
        for line in lines {
            let id = line.exercise.id
            if references[id] == nil {
                references[id] = try reference(db, exercise: line.exercise, before: workout.startedAt, excluding: workout.id)
            }
            let hard = line.sets.reduce(0) { $0 + weight($1, reference: references[id] ?? nil) }
            guard hard > 0 else { continue }
            for m in line.exercise.primaryMuscles { counts[m, default: 0] += hard }
            for m in line.exercise.secondaryMuscles { counts[m, default: 0] += hard * 0.5 }
        }
    }

    static func sorted(_ counts: [Muscle: Double]) -> [(muscle: Muscle, sets: Double)] {
        counts.filter { $0.value > 0.005 }.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
    }
}
