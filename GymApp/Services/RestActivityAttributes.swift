import ActivityKit
import AppIntents
import Foundation

nonisolated struct RestActivityAttributes: ActivityAttributes {
    var workoutTitle: String

    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var restEndsAt: Date
        var nextSetText: String
        var nextSetId: String? = nil   // the set the Log button logs
    }
}

/// The Log button on the rest Live Activity. It runs in the app's process, which sets
/// `handler`; the widget extension only draws the button.
nonisolated struct LogSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log set"
    nonisolated(unsafe) static var handler: (@Sendable (String) async -> Void)?

    @Parameter(title: "Set") var setId: String

    init() {}
    init(setId: String) { self.setId = setId }

    func perform() async throws -> some IntentResult {
        await Self.handler?(setId)
        return .result()
    }
}
