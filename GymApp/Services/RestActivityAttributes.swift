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

/// Starts the next training day, or opens the workout in progress. Used by the Control Center
/// control (and the Action button). Opens the app, where `handler` does the work; the widget
/// extension only shows the control.
nonisolated struct StartNextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription("Starts your next training day in Bashi Gym.")
    static let openAppWhenRun = true
    nonisolated(unsafe) static var handler: (@Sendable () async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await Self.handler?()
        return .result()
    }
}
