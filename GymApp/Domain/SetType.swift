import Foundation

/// Rulebook §3. Stored by raw value, so cases may be added but never renamed.
nonisolated enum SetType: String, Codable, CaseIterable {
    case working, warmUp, failed, drop
}
