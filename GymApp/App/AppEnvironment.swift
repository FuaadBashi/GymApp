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
        Result {
            let db = try AppDatabase.onDisk()
            try MetadataDraft.replay(into: db)
            _ = try db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
            return db
        }
    }
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
