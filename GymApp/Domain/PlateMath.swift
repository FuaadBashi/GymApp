import Foundation

/// Plates per side for a barbell load: greedy from the largest plate, unlimited pairs of each.
nonisolated enum PlateMath {
    struct Result: Equatable {
        var perSide: [Double]
        var achieved: Double
        var shortBy: Double
    }

    static let defaultKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let defaultLb: [Double] = [45, 35, 25, 10, 5, 2.5]

    static func bar(for equipment: Equipment, unit: WeightUnit) -> Double {
        switch (equipment, unit) {
        case (.smith, _): 0
        case (.ezBar, .kg): 10
        case (.ezBar, .lb): 25
        case (_, .kg): 20
        case (_, .lb): 45
        }
    }

    static func plates(target: Double, bar: Double, available: [Double]) -> Result? {
        guard target >= bar else { return nil }
        // Work in hundredths so 2.5 and 1.25 don't drift.
        var remaining = Int(((target - bar) / 2 * 100).rounded(.down))
        var perSide: [Double] = []
        for plate in available.sorted(by: >) {
            let p = Int((plate * 100).rounded())
            guard p > 0 else { continue }
            while remaining >= p {
                perSide.append(plate)
                remaining -= p
            }
        }
        let achieved = bar + 2 * perSide.reduce(0, +)
        let short = target - achieved
        return Result(perSide: perSide, achieved: achieved, shortBy: abs(short) < 0.001 ? 0 : short)
    }
}
