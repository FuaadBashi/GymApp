import Foundation
import GRDB
import CryptoKit

nonisolated struct MetadataDraft: Codable, Equatable, Sendable {
    enum Kind: String, Codable { case set, exercise, sticky, summary, values }
    var kind: Kind
    var id: String
    var note: String
    var reserve: Int?
    var annotations: [SetAnnotation] = []
    var effort: Int?
    var edit: SetEdit?

    private static let lock = NSLock()
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "GymApp/Drafts") }
    private var file: URL {
        let digest = SHA256.hash(data: Data((kind.rawValue + id).utf8)).map { String(format: "%02x", $0) }.joined()
        return Self.folder.appending(path: digest + ".json")
    }
    func persist() throws {
        try Self.lock.withLock {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: file, options: .atomic)
        }
    }
    func clearIfCurrent() throws {
        try Self.lock.withLock {
            guard let data = try? Data(contentsOf: file), try JSONDecoder().decode(Self.self, from: data) == self else { return }
            try FileManager.default.removeItem(at: file)
        }
    }
    func apply(_ db: Database) throws {
        switch kind {
        case .values:
            guard let edit else { throw WorkoutError.notFound }
            try WorkoutWrites.updateSet(db, setId: id, edit: edit)
        case .set: try WorkoutWrites.setMetadata(db, setId: id, note: note, reserve: reserve, annotations: annotations)
        case .exercise: try WorkoutWrites.setExerciseNote(db, itemId: id, note: note)
        case .sticky: try ExerciseWrites.setStickyNote(db, id: id, text: note)
        case .summary: try WorkoutWrites.setNoteAndEffort(db, workoutId: id, note: note, effort: effort)
        }
    }
    static func replay(into app: AppDatabase) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            do {
                let draft = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
                try app.writer.write { try draft.apply($0) }
                try draft.clearIfCurrent()
            } catch { app.recovery?.record(error) }
        }
    }
}
