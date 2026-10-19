import GRDB
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    @Entry var appDatabase: AppDatabase? = nil
}

/// Opens the database and seeds the library once at launch. Failure is shown, never a crash:
/// the data on the phone matters more than the app starting.
enum AppStartup {
    static func openDatabase() -> Result<AppDatabase, Error> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestFixture") { return Result { try uiTestFixture() } }
        #endif
        return Result {
            let db = try AppDatabase.onDisk()
            try MetadataDraft.replay(into: db)
            _ = try db.writer.write { db in
                try LibrarySeeder.seed(in: db, now: .now)
                try LibrarySeeder.linkImported(in: db)
            }
            return db
        }
    }

    #if DEBUG
    /// UI tests: an in-memory database, so the phone's data is never touched. One exercise with
    /// an old all-time best (100 × 5, 400 days ago), a 12-month best (80 × 8, 60 days ago, after
    /// a break) and a workout in progress with one planned set of 60 × 10.
    static func uiTestFixture() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            let exercise = ExerciseRecord(id: "ui-bench", name: "Test Bench", equipment: .barbell, loadMode: .total,
                                          primaryMuscles: [.chest], secondaryMuscles: [], force: nil, mechanic: nil,
                                          category: .strength, bodyRegion: .upper, movementPattern: nil, instructions: [],
                                          source: .custom, libraryId: nil, stickyNote: nil, defaultRestSeconds: 90,
                                          preferredUnit: .kg, isFavorite: false, isArchived: false, createdAt: .now)
            try exercise.insert(db)
            for (days, kg, reps) in [(400.0, 100.0, 5), (60.0, 80.0, 8)] {
                let start = Date.now.addingTimeInterval(-days * 86_400)
                let w = WorkoutRecord(id: UUID().uuidString, startedAt: start, endedAt: start.addingTimeInterval(3600), programDayId: nil,
                                      title: "Past", note: nil, effort: nil, restEndsAt: nil, restDurationSeconds: nil, source: .app, externalId: nil)
                try w.insert(db)
                let we = WorkoutExerciseRecord(id: UUID().uuidString, workoutId: w.id, exerciseId: exercise.id, position: 0, dayExerciseId: nil,
                                               targetSets: nil, repMin: nil, repMax: nil, restSeconds: 90, note: nil, externalId: nil)
                try we.insert(db)
                try WorkoutSetRecord(id: UUID().uuidString, workoutExerciseId: we.id, position: 0, loadHundredths: Int(kg * 100), unit: .kg,
                                     reps: reps, type: .working, completedAt: start, rpe: nil, externalId: nil).insert(db)
            }
            let settings = try AppSettings.load(db)
            let w = try WorkoutWrites.start(db, dayId: nil, settings: settings, now: .now)
            let item = try WorkoutWrites.addExercise(db, workoutId: w.id, exerciseId: exercise.id, settings: settings)
            for set in try WorkoutSetRecord.filter(Column("workoutExerciseId") == item.id).fetchAll(db) {
                try WorkoutWrites.updateSet(db, setId: set.id, edit: SetEdit(loadHundredths: 6000, unit: .kg, reps: 10, type: .working))
            }
        }
        return db
    }
    #endif
}

struct DatabaseErrorView: View {
    let error: Error
    @State private var choosingBackup = false
    @State private var candidate: URL?
    @State private var inspection: RecoveryStore.Inspection?
    @State private var message: String?

    var body: some View {
        ContentUnavailableView {
            Label("The database could not be opened", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Recover from a backup…") { choosingBackup = true }
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                inspection = try RecoveryStore.inspect(url)
                candidate = url
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Restore this backup next launch?", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }), titleVisibility: .visible) {
            Button("Schedule recovery", role: .destructive) {
                guard let candidate else { return }
                do {
                    let store = try RecoveryStore(folder: URL.applicationSupportDirectory.appending(path: "GymApp/Recovery"))
                    _ = try store.stageRestore(candidate)
                    message = "Backup checked. Close and reopen GymApp. The original files will be kept in a safety archive."
                } catch { message = error.localizedDescription }
                self.candidate = nil
            }
        } message: {
            Text("\(inspection?.workouts ?? 0) workouts and \(inspection?.sets ?? 0) sets. Preserve the current files, then replace them with this backup.")
        }
        .alert("Recovery", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}
