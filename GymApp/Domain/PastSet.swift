import Foundation

/// A set as the maths sees it: kg already converted, a reps-only set carrying 0.
nonisolated struct PastSet: Codable, Hashable {
    var kg: Double
    var reps: Int
    var type: SetType
}

extension PastSet {
    nonisolated var shortText: String { "\(Load.format(kg))×\(reps)" }
}
