import CryptoKit
import Foundation
import GRDB

nonisolated enum ImportService {
    /// Reads, parses and imports a JEFIT export in one write transaction, off the main actor:
    /// the real export takes a noticeable moment and the UI must keep drawing.
    @concurrent
    static func importJEFIT(fileAt url: URL, into db: AppDatabase) async throws -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let export = try JEFITExport(data: data)
        let map = try BundledExercises.jefitMap()
        return try await db.writer.write { db in
            try JEFITImporter.run(export, map: map, in: db, now: .now,
                                  fileName: url.lastPathComponent, fileSHA256: sha)
        }
    }

    /// Settings' one import button: a Strong or Hevy workout CSV if its header says so,
    /// otherwise a JEFIT export.
    static func importFile(at url: URL, into db: AppDatabase) async throws -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let format: LogCSVImporter.Format, rows: [LogCSVImporter.SetRow]
        do {
            (format, rows) = try LogCSVImporter.parse(data)
        } catch LogCSVImportError.unrecognised {
            return try await importJEFIT(fileAt: url, into: db)
        }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try await db.writer.write { db in
            try LogCSVImporter.run(format, rows, in: db, now: .now, fileName: url.lastPathComponent, fileSHA256: sha)
        }
    }
}

