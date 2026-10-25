import Foundation
import GRDB

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

    /// Start the next day, or bring up the workout already in progress (rulebook §19).
    static func startNext() async {
        guard let db else { return }
        let model = model(for: db)
        if (try? await db.reader.read({ try WorkoutQueries.inProgress($0) })) != nil {
            await model.resumeIfNeeded()
            model.isPresented = true
            return
        }
        let dayId = try? await db.reader.read { db -> String? in
            guard let program = try ProgramQueries.activeProgram(db) else { return nil }
            return try ProgramQueries.nextDay(db, programId: program.id)?.id
        }
        try? await model.start(dayId: dayId ?? nil)
    }

    static func install() {
        StartNextWorkoutIntent.handler = { await WorkoutHub.startNext() }
        AdjustRestIntent.handler = { seconds in
            await MainActor.run { () -> Task<Void, Never>? in
                guard let db = WorkoutHub.db else { return nil }
                let model = WorkoutHub.model(for: db)
                return Task { await model.resumeIfNeeded(); await model.adjustRest(by: seconds) }
            }?.value
        }
        SkipRestIntent.handler = {
            await MainActor.run { () -> Task<Void, Never>? in
                guard let db = WorkoutHub.db else { return nil }
                let model = WorkoutHub.model(for: db)
                return Task { await model.resumeIfNeeded(); await model.skipRest() }
            }?.value
        }
        LogSetIntent.handler = { setId in
            await MainActor.run { () -> Task<Void, Never>? in
                guard let db = WorkoutHub.db else { return nil }
                let model = WorkoutHub.model(for: db)
                return Task { await model.logFromActivity(setId) }
            }?.value
        }
    }
}
