import Foundation

/// Rulebook §1: loads are stored exactly as entered, as hundredths of the unit they were
/// entered in. Converting on the way in would turn 45 lb into 44.99 lb on the way back.
nonisolated enum WeightUnit: String, Codable, CaseIterable {
    case kg, lb

    static let kgPerLb = 0.45359237
}

nonisolated struct Load: Codable, Hashable {
    var hundredths: Int
    var unit: WeightUnit

    init(hundredths: Int, unit: WeightUnit) {
        self.hundredths = hundredths
        self.unit = unit
    }

    init(_ value: Double, _ unit: WeightUnit) {
        self.init(hundredths: Int((value * 100).rounded()), unit: unit)
    }

    var value: Double { Double(hundredths) / 100 }

    /// Every comparison and aggregate happens in kg (§1.4), whatever the entry unit.
    var kg: Double { unit == .kg ? value : value * WeightUnit.kgPerLb }

    func adding(_ step: Double) -> Load { Load(value + step, unit) }

    var formatted: String { Self.format(value) }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
