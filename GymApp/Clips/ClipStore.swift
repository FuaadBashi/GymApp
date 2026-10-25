import Foundation
import GRDB

nonisolated struct SetClipRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "setClip"
    var id: String
    var setId: String
    var fileName: String
    var createdAt: Date
    var analysis: String?

    var result: FormResult? { analysis.flatMap { try? JSONDecoder().decode(FormResult.self, from: Data($0.utf8)) } }
}

/// Clip files live in Application Support/GymApp/Clips, named by clip id. The database row and
/// the file are created and removed together; `removeOrphans` cleans files whose set is gone.
nonisolated enum ClipStore {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "GymApp/Clips", directoryHint: .isDirectory) }

    static func url(_ clip: SetClipRecord, in folder: URL = folder) -> URL { folder.appending(path: clip.fileName) }

    /// Copies the picked video in and attaches it to the set, replacing any earlier clip.
    static func attach(_ source: URL, toSet setId: String, db: AppDatabase, folder: URL = folder, now: Date = .now) async throws -> SetClipRecord {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let name = id + "." + (source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: folder.appending(path: name))
        let clip = SetClipRecord(id: id, setId: setId, fileName: name, createdAt: now, analysis: nil)
        let old = try await db.writer.write { db -> SetClipRecord? in
            let old = try SetClipRecord.filter(Column("setId") == setId).fetchOne(db)
            try old?.delete(db)
            try clip.insert(db)
            return old
        }
        if let old { try? FileManager.default.removeItem(at: url(old, in: folder)) }
        return clip
    }

    static func saveAnalysis(_ result: FormResult, clipId: String, db: AppDatabase) async throws {
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        try await db.writer.write { try $0.execute(sql: "UPDATE setClip SET analysis = ? WHERE id = ?", arguments: [json, clipId]) }
    }

    static func remove(_ clip: SetClipRecord, db: AppDatabase, folder: URL = folder) async throws {
        _ = try await db.writer.write { try clip.delete($0) }
        try? FileManager.default.removeItem(at: url(clip, in: folder))
    }

    /// Files with no row (the set or workout was deleted, which cascades the row away).
    static func removeOrphans(db: AppDatabase, folder: URL = folder) async {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let kept = Set((try? await db.reader.read { try String.fetchAll($0, sql: "SELECT fileName FROM setClip") }) ?? [])
        for name in names where !kept.contains(name) { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
    }

    static func clips(_ db: Database, setIds: [String]) throws -> [String: SetClipRecord] {
        Dictionary(uniqueKeysWithValues: try SetClipRecord.filter(setIds.contains(Column("setId"))).fetchAll(db).map { ($0.setId, $0) })
    }
}
