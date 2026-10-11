import Foundation

/// The formulas from docs/TRAINING_RULEBOOK.md. Every figure on screen comes from here, so
/// a summary and a chart can never disagree about what "volume" means.
enum TrainingMath {
    /// §4: Epley. A single rep is the load itself.
    static func e1RM(kg: Double, reps: Int) -> Double {
        reps <= 1 ? kg : kg * (1 + Double(reps) / 30)
    }

    /// §4: shown only for 1–12 reps, where the estimate means something.
    static func displayableE1RM(kg: Double, reps: Int, equipment: ProtoEquipment) -> Double? {
        guard equipment != .assisted, kg > 0, (1...12).contains(reps) else { return nil }
        return e1RM(kg: kg, reps: reps)
    }

    /// §2: assisted loads are body weight plus the (negative) logged figure. Without a body
    /// weight there is no honest number, so the set drops out of volume.
    static func calculationKg(_ kg: Double, equipment: ProtoEquipment, bodyWeightKg: Double?) -> Double? {
        guard equipment == .assisted else { return kg }
        guard let bodyWeightKg else { return nil }
        return max(bodyWeightKg + kg, 0)
    }

    /// §6: Σ load × reps, warm-ups excluded (§3).
    static func volumeKg(_ sets: [PastSet], equipment: ProtoEquipment, bodyWeightKg: Double?) -> Double {
        sets.reduce(0) { total, set in
            guard set.type != .warmUp,
                  let load = calculationKg(set.kg, equipment: equipment, bodyWeightKg: bodyWeightKg)
            else { return total }
            return total + load * Double(set.reps) * equipment.volumeMultiplier
        }
    }

    struct Bests {
        var heaviestKg: Double?
        var bestE1RM: Double?
    }

    /// §5: working and failed sets count; warm-ups never do. Assisted work has no
    /// meaningful heaviest load, so it is left out.
    static func bests(_ sets: [PastSet], equipment: ProtoEquipment) -> Bests {
        guard equipment != .assisted else { return Bests() }
        let counted = sets.filter { $0.type != .warmUp && $0.reps > 0 && $0.kg > 0 }
        return Bests(
            heaviestKg: counted.map(\.kg).max(),
            bestE1RM: counted.compactMap { displayableE1RM(kg: $0.kg, reps: $0.reps, equipment: equipment) }.max()
        )
    }
}

extension PastSet {
    var shortText: String { "\(Load.format(kg))×\(reps)" }
}
