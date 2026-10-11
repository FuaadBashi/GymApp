import Foundation

nonisolated enum SetAnnotation: String, Codable, CaseIterable, Sendable {
    case deload, injury, form
    var label: String { rawValue.capitalized }
}
