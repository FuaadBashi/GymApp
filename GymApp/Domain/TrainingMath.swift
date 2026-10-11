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
}
