import Foundation
import GRDB
import CryptoKit

/// Serialises recovery files separately from the live database. A failed backup never
/// turns a committed edit into a failed edit, or removes the last good recovery copy.
nonisolated final class RecoveryStore: @unchecked Sendable, TransactionObserver {
    struct Status: Codable, Sendable {
        var localAt: Date?
        var externalAt: Date?
        var externalPending = true
        var error: String?
    }
    struct Inspection: Equatable, Sendable {
        var workouts: Int
        var sets: Int
        var unfinished: Int
    }
    enum Failure: LocalizedError {
        case invalidBackup, missingFolder
        var errorDescription: String? {
            switch self {
            case .invalidBackup: "This file is not a valid, supported GymApp backup."
            case .missingFolder: "Choose a backup folder outside GymApp to protect against app deletion or phone loss."
            }
        }
    }
    let folder: URL
    enum Checkpoint: Sendable { case snapshotValidated, externalValidated, restoreValidated }
    private let check: @Sendable (Checkpoint) throws -> Void
    private let lock = NSRecursiveLock()
    private var changed = false
    private var statusValue = Status()
    private let fm = FileManager.default

    init(folder: URL, check: @escaping @Sendable (Checkpoint) throws -> Void = { _ in }) throws {
        self.folder = folder
        self.check = check
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appending(path: "status.json")),
           let value = try? JSONDecoder().decode(Status.self, from: data) { statusValue = value }
        // A terminated copy is unpublished. Reclaim only our private staging files.
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            let staged = [".recovery-", ".safety-", ".restore-", ".validated-restore-"].contains { name.hasPrefix($0) }
            let partial = [".partial", ".partial-wal", ".partial-shm", ".partial-journal"].contains { name.hasSuffix($0) }
            if staged && partial {
                do { try fm.removeItem(at: url) } catch { record(error) }
            }
        }
    }
    var status: Status { lock.withLock { statusValue } }
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
    func databaseDidChange(with event: DatabaseEvent) { changed = true }
    func databaseDidRollback(_ db: Database) { changed = false }
    func databaseDidCommit(_ db: Database) {
        guard changed else { return }
        changed = false
        do { _ = try capture(db) } catch { record(error) }
    }
    func record(_ error: Error) {
        lock.withLock { statusValue.error = error.localizedDescription; saveStatus() }
    }
    private func saveStatus() {
        do { try JSONEncoder().encode(statusValue).write(to: folder.appending(path: "status.json"), options: .atomic) }
        catch { statusValue.error = error.localizedDescription }
    }
    static func inspect(_ url: URL) throws -> Inspection {
        var config = Configuration(); config.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try queue.read { db in
            guard try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok",
                  try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else { throw Failure.invalidBackup }
            let versions = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
            // Any leading run of known migrations: a backup from an older version is valid.
            guard !versions.isEmpty, Set(versions) == Set(Schema.versions.prefix(versions.count)) else { throw Failure.invalidBackup }
            for table in ["exercise", "program", "programDay", "dayExercise", "workout", "workoutExercise", "workoutSet", "exerciseNote", "bodyEntry", "setting", "importRun"] {
                guard try db.tableExists(table) else { throw Failure.invalidBackup }
            }
            return Inspection(workouts: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout") ?? 0,
                              sets: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutSet") ?? 0,
                              unfinished: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout WHERE endedAt IS NULL") ?? 0)
        }
    }
    @discardableResult
    func capture(_ db: Database, safety: Bool = false) throws -> URL {
        try lock.withLock {
            let name = "\(safety ? "safety" : "recovery")-\(Int(Date.now.timeIntervalSince1970 * 1000))-\(UUID().uuidString).sqlite"
            let final = folder.appending(path: name)
            let partial = folder.appending(path: ".\(name).partial")
            do {
                let target = try DatabaseQueue(path: partial.path)
                try target.writeWithoutTransaction { destination in
                    try db.backup(to: destination)
                    // A portable snapshot must open read-only without WAL sidecar files.
                    _ = try String.fetchOne(destination, sql: "PRAGMA journal_mode = DELETE")
                }
                try target.close()
                _ = try Self.inspect(partial)
                try check(.snapshotValidated)
                try fm.moveItem(at: partial, to: final)
                removeSidecars(of: partial)
            } catch {
                try? fm.removeItem(at: partial)
                removeSidecars(of: partial)
                throw error
            }
            statusValue.localAt = .now
            statusValue.externalPending = true
            statusValue.error = nil
            saveStatus()
            // External failure leaves the verified local snapshot available for retry.
            do { try copyOutside(final) } catch { statusValue.error = error.localizedDescription; saveStatus() }
            if !safety { try prune() }
            return final
        }
    }
    /// Opening the staging copy can leave SQLite sidecars that outlive the rename.
    private func removeSidecars(of url: URL) {
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fm.removeItem(at: URL(filePath: url.path + suffix))
        }
    }
    func snapshots() throws -> [URL] {
        try lock.withLock {
            try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("recovery-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }
    private func prune(at directory: URL? = nil) throws {
        let copies: [URL]
        if let directory {
            copies = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("recovery-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } else { copies = try snapshots() }
        var retained = Set(copies.prefix(30))
        var months = Set<String>()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for url in copies {
            let date = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            if months.insert(formatter.string(from: date)).inserted { retained.insert(url) }
        }
        for url in copies where !retained.contains(url) { try fm.removeItem(at: url) }
    }
    func chooseExternalFolder(_ url: URL) throws {
        try lock.withLock {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            try bookmark.write(to: folder.appending(path: "destination.bookmark"), options: .atomic)
            statusValue.externalPending = true
            saveStatus()
        }
    }
    /// Runs `body` with the chosen backup folder open, for files other than backups (card 6.3).
    func withExternalFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark = try? Data(contentsOf: folder.appending(path: "destination.bookmark")) else { throw Failure.missingFolder }
        var stale = false
        let destination = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        return try body(destination)
    }
    private func copyOutside(_ source: URL) throws {
        guard let bookmark = try? Data(contentsOf: folder.appending(path: "destination.bookmark")) else { throw Failure.missingFolder }
        var stale = false
        let destination = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        if stale {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw Failure.missingFolder }
            let refreshed = try destination.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            try refreshed.write(to: folder.appending(path: "destination.bookmark"), options: .atomic)
        }
        let final = destination.appending(path: source.lastPathComponent)
        let partial = destination.appending(path: ".\(UUID().uuidString).partial")
        do {
            try fm.copyItem(at: source, to: partial)
            // Read back and compare with the local copy, which `capture` already opened and
            // checked. SQLite itself is not opened here: file-provider folders (iCloud Drive,
            // On My iPhone) refuse SQLite's locks and fail with error 14, while plain reads work.
            guard SHA256.hash(data: try Data(contentsOf: source)) == SHA256.hash(data: try Data(contentsOf: partial)) else { throw Failure.invalidBackup }
            try check(.externalValidated)
            if fm.fileExists(atPath: final.path) {
                guard SHA256.hash(data: try Data(contentsOf: final)) == SHA256.hash(data: try Data(contentsOf: source)) else { throw Failure.invalidBackup }
                try fm.removeItem(at: partial)
            } else { try fm.moveItem(at: partial, to: final) }
            try prune(at: destination)
            statusValue.externalAt = .now
            statusValue.externalPending = false
            statusValue.error = nil
            saveStatus()
        } catch { try? fm.removeItem(at: partial); throw error }
    }
    func retryExternal() throws {
        try lock.withLock {
            guard let latest = try snapshots().first else { return }
            do { try copyOutside(latest) } catch { statusValue.externalPending = true; record(error); throw error }
        }
    }
    func export(_ source: URL) throws -> URL {
        try lock.withLock {
            _ = try Self.inspect(source)
            let directory = folder.appending(path: "Exports")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appending(path: "GymApp-\(UUID().uuidString).sqlite")
            try fm.copyItem(at: source, to: copy)
            _ = try Self.inspect(copy)
            return copy
        }
    }
    /// A chosen file may live in a file-provider folder SQLite cannot open (error 14), so it
    /// is copied into the app's temporary directory first and only ever opened there.
    static func localCopy(of url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appending(path: "chosen-\(UUID().uuidString).sqlite")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .forUploading, error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: copy) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return copy
    }

    func stageRestore(_ source: URL) throws -> Inspection {
        try lock.withLock {
            let source = try Self.localCopy(of: source)
            defer { try? fm.removeItem(at: source) }
            let inspection = try Self.inspect(source)
            let pending = folder.appending(path: "pending-restore.sqlite")
            let staging = folder.appending(path: ".restore-\(UUID().uuidString).partial")
            var config = Configuration(); config.readonly = true
            let queue = try DatabaseQueue(path: source.path, configuration: config)
            let target = try DatabaseQueue(path: staging.path)
            try queue.backup(to: target)
            try target.close(); try queue.close()
            guard try Self.inspect(staging) == inspection else { throw Failure.invalidBackup }
            if fm.fileExists(atPath: pending.path) {
                _ = try fm.replaceItemAt(pending, withItemAt: staging)
            } else { try fm.moveItem(at: staging, to: pending) }
            return inspection
        }
    }
    /// Called before opening the live pool, so no screen can retain stale database rows.
    func applyPendingRestore(to live: URL) throws {
        let pending = folder.appending(path: "pending-restore.sqlite")
        guard fm.fileExists(atPath: pending.path) else { return }
        _ = try Self.inspect(pending)
        let source = try DatabaseQueue(path: pending.path)
        // Test migrations on the candidate before touching the live database.
        try Schema.migrator.migrate(source)
        // Preserve even a damaged primary and WAL so recovery never erases evidence.
        let archive = folder.appending(path: "safety-live-\(UUID().uuidString)")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: live.path + suffix)
            if fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: archive.appending(path: live.lastPathComponent + suffix))
            }
        }
        let staged = folder.appending(path: ".validated-restore-\(UUID().uuidString).partial")
        let target = try DatabaseQueue(path: staged.path)
        try source.backup(to: target)
        try target.close(); try source.close()
        _ = try Self.inspect(staged)
        try check(.restoreValidated)
        let drafts = MetadataDraft.folder
        let hasDrafts = fm.fileExists(atPath: drafts.path)
        if hasDrafts { try fm.copyItem(at: drafts, to: archive.appending(path: "Drafts")) }
        // No live pool has been opened yet. Move the old files rather than deleting them.
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: live.path + suffix)
            if fm.fileExists(atPath: file.path) {
                try fm.moveItem(at: file, to: archive.appending(path: "original-" + live.lastPathComponent + suffix))
            }
        }
        try fm.moveItem(at: staged, to: live)
        _ = try Self.inspect(live)
        if hasDrafts { try fm.removeItem(at: drafts) }
        try fm.removeItem(at: pending)
    }
}
