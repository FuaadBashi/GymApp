import ActivityKit
import Foundation

nonisolated struct RestActivityAttributes: ActivityAttributes {
    var workoutTitle: String

    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var restEndsAt: Date
        var nextSetText: String
    }
}
