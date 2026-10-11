import Foundation
import GRDB

/// The app's one database. Every write goes through `writer`, so the schema's CHECK
/// constraints and foreign keys apply to every caller.
nonisolated final class AppDatabase: Sendable {
    let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Schema.migrator.migrate(writer)
    }

    /// Application Support/GymApp/gymapp.sqlite. WAL mode, via DatabasePool.
    static func onDisk() throws -> AppDatabase {
        let folder = URL.applicationSupportDirectory.appending(path: "GymApp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: folder.appending(path: "gymapp.sqlite").path))
    }

    /// For tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }
}
