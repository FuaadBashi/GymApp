import Foundation
import GRDB

nonisolated struct SessionPoint: Identifiable, Equatable {
    var workoutId: String
    var date: Date
    var bestE1RM: Double?
    var heaviestKg: Double?
    var volumeKg: Double
    var id: String { workoutId }
}

nonisolated struct ExerciseRecords: Equatable {
    struct Mark: Equatable {
        var valueKg: Double
        var reps: Int?
        var date: Date
        var workoutId: String
    }
    var heaviest: Mark?
    var bestE1RM: Mark?
    var bestVolume: Mark?
    var repRecords: [Mark]            // most reps at each distinct load, heaviest load first
}

/// Card 3.4: an exercise's progress over time, and its records (rulebook §5). Derived on read
/// from finished sessions, so correcting a set changes them.
nonisolated enum ExerciseStats {
    /// Oldest first, one point per session.
    static func points(_ sessions: [ExerciseSession], loadMode: LoadMode, bodyWeightKg: (Date) -> Double?) -> [SessionPoint] {
        sessions.map { s in
            let past = SetFormat.pastSets(s.sets)
            let bests = TrainingMath.bests(past, loadMode: loadMode)
            return SessionPoint(workoutId: s.workout.id, date: s.workout.startedAt,
                                bestE1RM: bests.bestE1RM, heaviestKg: bests.heaviestKg,
                                volumeKg: TrainingMath.volumeKg(past, loadMode: loadMode, bodyWeightKg: bodyWeightKg(s.workout.startedAt)))
        }
        .sorted { $0.date < $1.date }
    }

    /// Card 6.4: the session closest in time to a tapped date on the chart.
    static func nearest<P>(_ points: [P], to date: Date, at: (P) -> Date) -> P? {
        points.min { abs(at($0).timeIntervalSince(date)) < abs(at($1).timeIntervalSince(date)) }
    }

    /// Ties keep the earliest date: that is when the record was set.
    static func records(_ sessions: [ExerciseSession], loadMode: LoadMode, bodyWeightKg: (Date) -> Double?) -> ExerciseRecords {
        let ordered = sessions.sorted { $0.workout.startedAt < $1.workout.startedAt }
        var heaviest: ExerciseRecords.Mark?
        var e1RM: ExerciseRecords.Mark?
        var volume: ExerciseRecords.Mark?
        var reps: [Int: ExerciseRecords.Mark] = [:]   // load in hundredths of a kg → mark
        let hasLoadRecords = loadMode != .bodyweightPlus && loadMode != .repsOnly

        for session in ordered {
            let date = session.workout.startedAt, id = session.workout.id
            let past = SetFormat.pastSets(session.sets)
            let v = TrainingMath.volumeKg(past, loadMode: loadMode, bodyWeightKg: bodyWeightKg(date))
            if v > 0, v > (volume?.valueKg ?? 0) { volume = .init(valueKg: v, reps: nil, date: date, workoutId: id) }
            guard hasLoadRecords else { continue }
            for set in past where set.type != .warmUp && set.type != .drop && set.kg > 0 && set.reps > 0 {
                if set.kg > (heaviest?.valueKg ?? 0) { heaviest = .init(valueKg: set.kg, reps: set.reps, date: date, workoutId: id) }
                if let e = TrainingMath.displayableE1RM(kg: set.kg, reps: set.reps, loadMode: loadMode), e > (e1RM?.valueKg ?? 0) {
                    e1RM = .init(valueKg: e, reps: set.reps, date: date, workoutId: id)
                }
                let key = Int((set.kg * 100).rounded())
                if set.reps > (reps[key]?.reps ?? 0) { reps[key] = .init(valueKg: Double(key) / 100, reps: set.reps, date: date, workoutId: id) }
            }
        }
        return ExerciseRecords(heaviest: heaviest, bestE1RM: e1RM, bestVolume: volume,
                               repRecords: reps.values.sorted { $0.valueKg > $1.valueKg })
    }
}
