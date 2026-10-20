import Foundation

/// Rulebook §13: what to lift today, from the exercise's finished sessions. The same double
/// progression as the studio's `next_target`, plus the comeback ramp after a break. Loads stay
/// in the unit the lift was last entered in.
nonisolated enum NextSet {
    enum Kind: String, Equatable { case addWeight = "add weight", addReps = "add reps", comeback }

    struct Suggestion: Equatable {
        var kind: Kind
        var loadHundredths: Int
        var unit: WeightUnit
        var reps: Int
        var reason: String
    }

    static let breakDays = TrainingMath.breakDays          // 30, as for window bests (§5a)
    static let longBreakDays = 90
    static let comebackStart = (short: 0.9, long: 0.8)     // share of the last top load
    static let comebackRamp = 0.05                         // of the pre-break top, per session
    static let easyReserve = 2                             // reps in reserve that count as easy

    /// `sessions` newest first. `stepKg` is the exercise's learnt step (§7a).
    static func suggest(sessions: [ExerciseSession], repRange: ClosedRange<Int>, stepKg: Double,
                        loadMode: LoadMode, now: Date) -> Suggestion? {
        guard loadMode != .repsOnly, loadMode != .bodyweightPlus, let last = sessions.first,
              let top = topSet(last) else { return nil }
        let unit = top.unit
        let step = unit == .kg ? stepKg : max(2.5, ((stepKg / WeightUnit.kgPerLb) / 2.5).rounded() * 2.5)
        let topLoad = Double(top.loadHundredths ?? 0) / 100
        let lo = repRange.lowerBound, hi = repRange.upperBound
        func down(_ x: Double) -> Int { Int(((x / step).rounded(.down) * step * 100).rounded()) }
        func up(_ x: Double) -> Int { Int(((x / step).rounded(.up) * step * 100).rounded()) }
        func fmt(_ h: Int) -> String { "\(Load.format(Double(h) / 100)) \(unit.rawValue)" }

        // 1. Back after a break: start lighter.
        let away = Int(now.timeIntervalSince(last.workout.startedAt) / 86_400)
        if away >= breakDays {
            let share = away >= longBreakDays ? comebackStart.long : comebackStart.short
            let load = max(down(topLoad * share), Int(step * 100))
            return Suggestion(kind: .comeback, loadHundredths: load, unit: unit, reps: lo,
                              reason: "First session in \(away) days: start at \(Int(share * 100))% of \(fmt(top.loadHundredths ?? 0)) and build back up.")
        }

        // 2. Still climbing back after a break: add 5% of the pre-break top per session.
        if let preBreak = preBreakTop(sessions), preBreak.unit == unit {
            let target = Double(preBreak.loadHundredths ?? 0) / 100
            if topLoad + 0.001 < target {
                let load = min(up(topLoad + max(step, target * comebackRamp)), Int((target * 100).rounded()))
                return Suggestion(kind: .comeback, loadHundredths: load, unit: unit, reps: lo,
                                  reason: "Rebuilding to \(fmt(preBreak.loadHundredths ?? 0)) from before the break: up about 5% a session.")
            }
        }

        // 3. Double progression.
        let atTop = working(last).filter { $0.loadHundredths == top.loadHundredths && $0.unit == unit }
        // 4. Reps in reserve: when every top set was logged with 2 or more left, move twice as fast.
        let reserve = atTop.allSatisfy { $0.repsInReserve != nil } ? atTop.compactMap(\.repsInReserve).min() : nil
        let easy = (reserve ?? 0) >= easyReserve
        let note = easy ? " (\(reserve!)+ reps in reserve on every set)" : ""
        if atTop.allSatisfy({ $0.reps >= hi }) {
            let steps = easy ? 2.0 : 1.0
            let load = Int(((topLoad + step * steps) * 100).rounded())
            return Suggestion(kind: .addWeight, loadHundredths: load, unit: unit, reps: lo,
                              reason: "Every set at \(fmt(top.loadHundredths ?? 0)) reached \(hi) reps\(note): add \(Load.format(step * steps)) \(unit.rawValue) and go back to \(lo).")
        }
        let lowest = atTop.map(\.reps).min() ?? lo
        return Suggestion(kind: .addReps, loadHundredths: top.loadHundredths ?? 0, unit: unit, reps: min(lowest + (easy ? 2 : 1), hi),
                          reason: "Stay at \(fmt(top.loadHundredths ?? 0)) and beat your lowest set (\(lowest) reps)\(note) until every set reaches \(hi).")
    }

    private static func working(_ s: ExerciseSession) -> [WorkoutSetRecord] {
        s.sets.filter { ($0.type == .working || $0.type == .failed) && $0.reps > 0 && $0.loadHundredths != nil }
    }

    /// The heaviest working set of a session, compared in kg so mixed units don't mislead.
    private static func topSet(_ s: ExerciseSession) -> WorkoutSetRecord? {
        working(s).max { Load(hundredths: $0.loadHundredths!, unit: $0.unit).kg < Load(hundredths: $1.loadHundredths!, unit: $1.unit).kg }
    }

    static let rampSessions = 6

    /// The top set of the session before a break of `breakDays` or more within the last
    /// `rampSessions` sessions; an older break no longer sets the target.
    private static func preBreakTop(_ sessions: [ExerciseSession]) -> WorkoutSetRecord? {
        let recent = sessions.prefix(rampSessions + 1)
        for (newer, older) in zip(recent, recent.dropFirst())
        where newer.workout.startedAt.timeIntervalSince(older.workout.startedAt) >= Double(breakDays) * 86_400 {
            return topSet(older)
        }
        return nil
    }
}
