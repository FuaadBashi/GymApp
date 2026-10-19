import Foundation

/// The one workout model, shared by the screens and the Live Activity's Log button, which
/// can run while no screen is showing (iOS may launch the app in the background for it).
enum WorkoutHub {
    static var db: AppDatabase?
    private static var shared: ActiveWorkoutModel?

    static func model(for db: AppDatabase) -> ActiveWorkoutModel {
        if let shared { return shared }
        let model = ActiveWorkoutModel(db: db)
        shared = model
        return model
    }

    static func install() {
        LogSetIntent.handler = { setId in
            await MainActor.run { () -> Task<Void, Never>? in
                guard let db = WorkoutHub.db else { return nil }
                let model = WorkoutHub.model(for: db)
                return Task { await model.logFromActivity(setId) }
            }?.value
        }
    }
}
