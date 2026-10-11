import Foundation
import GRDB

/// The app's one database. Every write goes through `writer`, so the schema's CHECK
/// constraints and foreign keys apply to every caller.
nonisolated final class AppDatabase: Sendable {
    let recovery: RecoveryStore?
    let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter, recovery: RecoveryStore? = nil) throws {
        self.recovery = recovery
        self.writer = writer
        try Schema.migrator.migrate(writer)
        if let recovery {
            writer.writeWithoutTransaction { db in
                db.add(transactionObserver: recovery, extent: .databaseLifetime)
                do { _ = try recovery.capture(db) } catch { recovery.record(error) }
            }
        }
    }

    /// Application Support/GymApp/gymapp.sqlite. WAL mode, via DatabasePool.
    static func onDisk() throws -> AppDatabase {
        let folder = URL.applicationSupportDirectory.appending(path: "GymApp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let live = folder.appending(path: "gymapp.sqlite")
        let recovery = try RecoveryStore(folder: folder.appending(path: "Recovery", directoryHint: .isDirectory))
        try recovery.applyPendingRestore(to: live)
        var config = Configuration()
        config.prepareDatabase { try $0.execute(sql: "PRAGMA synchronous = FULL") }
        let pool = try DatabasePool(path: live.path, configuration: config)
        // Preserve the previous schema before applying any new migration.
        if FileManager.default.fileExists(atPath: live.path) {
            try pool.read { db in
                if try db.tableExists("workout"),
                   try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").count < 2 {
                    _ = try recovery.capture(db, safety: true)
                }
            }
        }
        return try AppDatabase(pool, recovery: recovery)
    }

    /// For tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }
}
