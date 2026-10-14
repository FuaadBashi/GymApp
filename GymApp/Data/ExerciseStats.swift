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

/// §5a: the all-time best estimated 1RM and the best of each window, for hints (card 7.3).
nonisolated struct BestMarks: Equatable {
    var allTime: Double?
    var windows: [Int: Double]        // months → best in that window
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

    /// §5a: every counted set's estimated 1RM with when it was done, oldest first. Sets that
    /// can't set a record (§5) are left out.
    static func e1RMHistory(_ sessions: [ExerciseSession], loadMode: LoadMode) -> [(date: Date, e1RM: Double)] {
        sessions.flatMap { session in
            session.sets.compactMap { set -> (date: Date, e1RM: Double)? in
                guard set.type != .warmUp, set.type != .drop, let load = set.loadHundredths, set.reps > 0,
                      let e = TrainingMath.displayableE1RM(kg: Load(hundredths: load, unit: set.unit).kg, reps: set.reps, loadMode: loadMode)
                else { return nil }
                return (set.completedAt ?? session.workout.startedAt, e)
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// §5a for a run of sets in order: each judged against `history` and the sets before it.
    /// Returns the statuses that are bests, and the history with the sets appended.
    static func statuses(_ sets: [WorkoutSetRecord], history: [(date: Date, e1RM: Double)], loadMode: LoadMode,
                         fallbackDate: Date) -> (bests: [String: TrainingMath.BestStatus], history: [(date: Date, e1RM: Double)]) {
        var history = history
        var out: [String: TrainingMath.BestStatus] = [:]
        guard loadMode != .bodyweightPlus, loadMode != .repsOnly else { return (out, history) }
        for set in sets.sorted(by: { ($0.completedAt ?? fallbackDate) < ($1.completedAt ?? fallbackDate) }) {
            guard set.type != .warmUp, set.type != .drop, let load = set.loadHundredths,
                  let e = TrainingMath.displayableE1RM(kg: Load(hundredths: load, unit: set.unit).kg, reps: set.reps, loadMode: loadMode)
            else { continue }
            let done = set.completedAt ?? fallbackDate
            let status = TrainingMath.bestStatus(e1RM: e, history: history, at: done)
            if status != .none { out[set.id] = status }
            history.append((done, e))
        }
        return (out, history)
    }

    static func marks(_ history: [(date: Date, e1RM: Double)], at date: Date) -> BestMarks {
        let earlier = history.filter { $0.date <= date }
        var windows: [Int: Double] = [:]
        for window in TrainingMath.bestWindows {
            let from = date.addingTimeInterval(-Double(window.days) * 86_400)
            windows[window.months] = earlier.filter { $0.date >= from }.map(\.e1RM).max()
        }
        return BestMarks(allTime: earlier.map(\.e1RM).max(), windows: windows)
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
