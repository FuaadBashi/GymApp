import Foundation

/// The formulas from docs/TRAINING_RULEBOOK.md. Every figure on screen comes from here, so
/// a summary and a chart can never disagree about what "volume" means.
nonisolated enum TrainingMath {
    /// §4: Epley. A single rep is the load itself.
    static func e1RM(kg: Double, reps: Int) -> Double {
        reps <= 1 ? kg : kg * (1 + Double(reps) / 30)
    }

    /// §4: shown only for 1–12 reps, where the estimate means something. Body-weight loads
    /// have no honest 1RM.
    static func displayableE1RM(kg: Double, reps: Int, loadMode: LoadMode) -> Double? {
        guard loadMode != .bodyweightPlus, loadMode != .repsOnly,
              kg > 0, (1...12).contains(reps) else { return nil }
        return e1RM(kg: kg, reps: reps)
    }

    /// §2: without a body weight there is no honest number for a body-weight load, so the
    /// set drops out of volume rather than counting as zero kilos.
    static func calculationKg(_ kg: Double, loadMode: LoadMode, bodyWeightKg: Double?) -> Double? {
        switch loadMode {
        case .total, .perHand, .perSide: return kg
        case .bodyweightPlus:
            guard let bodyWeightKg else { return nil }
            return max(bodyWeightKg + kg, 0)
        case .repsOnly: return nil
        }
    }

    /// §6: Σ load × reps × multiplier, warm-ups excluded (§3). Drop segments count.
    static func volumeKg(_ sets: [PastSet], loadMode: LoadMode, bodyWeightKg: Double?) -> Double {
        sets.reduce(0) { total, set in
            guard set.type != .warmUp,
                  let load = calculationKg(set.kg, loadMode: loadMode, bodyWeightKg: bodyWeightKg)
            else { return total }
            return total + load * Double(set.reps) * loadMode.volumeMultiplier
        }
    }

    struct Bests: Equatable {
        var heaviestKg: Double?
        var bestE1RM: Double?
    }

    /// §5: working and failed sets only. Only a drop set's first segment can set a record,
    /// and it is logged as working or failed, so `.drop` rows are skipped.
    static func bests(_ sets: [PastSet], loadMode: LoadMode) -> Bests {
        guard loadMode != .bodyweightPlus, loadMode != .repsOnly else { return Bests() }
        let counted = sets.filter { $0.type != .warmUp && $0.type != .drop && $0.reps > 0 && $0.kg > 0 }
        return Bests(
            heaviestKg: counted.map(\.kg).max(),
            bestE1RM: counted.compactMap { displayableE1RM(kg: $0.kg, reps: $0.reps, loadMode: loadMode) }.max()
        )
    }

    // MARK: §5a Time-window bests

    /// §5a: what a set's estimated 1RM beat.
    enum BestStatus: Equatable {
        case allTime(beat: Double)
        case window(months: Int, beat: Double)
        case none
    }

    static let bestWindows: [(months: Int, days: Int)] = [(12, 365), (6, 182), (1, 30)]
    static let breakDays = 30

    /// §5a: the all-time best first; else, only after a break of `breakDays` or more since the
    /// all-time best was set, the longest of the 12, 6 and 1-month windows whose best is below
    /// the all-time best and is beaten. Ties are not bests (0.01 kg), and a first-ever set has
    /// nothing to beat. `history` holds earlier estimated 1RMs with their dates.
    static func bestStatus(e1RM: Double, history: [(date: Date, e1RM: Double)], at date: Date) -> BestStatus {
        let earlier = history.filter { $0.date <= date }.sorted { $0.date < $1.date }
        guard let allTime = earlier.map(\.e1RM).max() else { return .none }
        if e1RM - allTime > 0.01 { return .allTime(beat: allTime) }

        // When the all-time best was last reached, and whether training broke off since.
        let bestDate = earlier.last { allTime - $0.e1RM <= 0.01 }!.date
        let since = earlier.map(\.date).filter { $0 >= bestDate } + [date]
        let gapSeconds = Double(breakDays) * 86_400
        let hadBreak = zip(since, since.dropFirst()).contains { $1.timeIntervalSince($0) >= gapSeconds }
        guard hadBreak else { return .none }

        for window in bestWindows {
            let from = date.addingTimeInterval(-Double(window.days) * 86_400)
            guard let best = earlier.filter({ $0.date >= from }).map(\.e1RM).max(),
                  allTime - best > 0.01, e1RM - best > 0.01 else { continue }
            return .window(months: window.months, beat: best)
        }
        return .none
    }
}
