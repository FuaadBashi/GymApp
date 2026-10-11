import GRDB
import SwiftUI

extension EnvironmentValues {
    @Entry var appDatabase: AppDatabase? = nil
}

/// Opens the database and seeds the library once at launch. Failure is shown, never a crash:
/// the data on the phone matters more than the app starting.
enum AppStartup {
    static func openDatabase() -> Result<AppDatabase, Error> {
        Result {
            let db = try AppDatabase.onDisk()
            try db.writer.write { try LibrarySeeder.seed(in: $0, now: .now) }
            return db
        }
    }
}

struct DatabaseErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("The database could not be opened", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error.localizedDescription)
        }
    }
}
