import Foundation
import GRDB

nonisolated struct FormCueRecord: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "formCue"
    enum Kind: String, Codable, CaseIterable { case setup, movement, mistake }
    enum Source: String, Codable { case library, owner }
    var id: String
    var exerciseId: String
    var kind: Kind
    var text: String
    var position: Int
    var showOnOpen: Bool
    var source: Source
}

/// Card 10.4: short form cues per exercise, seeded once from the library instructions and
/// then the owner's to edit.
nonisolated enum FormCues {
    static func cues(_ db: Database, exerciseId: String) throws -> [FormCueRecord] {
        try FormCueRecord.filter(Column("exerciseId") == exerciseId).order(Column("position")).fetchAll(db)
    }

    /// The cues chosen to show when the exercise opens in a workout.
    static func shownOnOpen(_ db: Database, exerciseId: String) throws -> [FormCueRecord] {
        try cues(db, exerciseId: exerciseId).filter(\.showOnOpen)
    }

    /// Seeds library cues the first time only; later calls change nothing.
    static func seedIfNeeded(_ db: Database, exerciseId: String) throws {
        guard try Int.fetchOne(db, sql: "SELECT 1 FROM formCueSeed WHERE exerciseId = ?", arguments: [exerciseId]) == nil,
              let exercise = try ExerciseRecord.fetchOne(db, key: exerciseId) else { return }
        try db.execute(sql: "INSERT INTO formCueSeed (exerciseId) VALUES (?)", arguments: [exerciseId])
        var position = try nextPosition(db, exerciseId: exerciseId)
        for (kind, text) in seedCues(exercise.instructions) {
            try FormCueRecord(id: UUID().uuidString, exerciseId: exerciseId, kind: kind, text: text,
                              position: position, showOnOpen: false, source: .library).insert(db)
            position += 1
        }
    }

    /// The first sentence of the first step as setup, the first sentence of the second step as
    /// movement. Mistakes are never invented.
    static func seedCues(_ instructions: [String]) -> [(FormCueRecord.Kind, String)] {
        let firsts = instructions.compactMap(firstSentence)
        return zip([FormCueRecord.Kind.setup, .movement], firsts).map { ($0, $1) }
    }

    static func firstSentence(_ step: String) -> String? {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let end = trimmed.range(of: ". ")?.lowerBound ?? trimmed.endIndex
        var sentence = String(trimmed[..<end]).trimmingCharacters(in: .whitespaces)
        if !sentence.hasSuffix(".") { sentence += "." }
        return sentence
    }

    @discardableResult
    static func add(_ db: Database, exerciseId: String, kind: FormCueRecord.Kind, text: String) throws -> FormCueRecord {
        var cue = FormCueRecord(id: UUID().uuidString, exerciseId: exerciseId, kind: kind,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                position: try nextPosition(db, exerciseId: exerciseId), showOnOpen: false, source: .owner)
        try cue.insert(db)
        return cue
    }

    static func update(_ db: Database, id: String, kind: FormCueRecord.Kind, text: String, showOnOpen: Bool) throws {
        guard var cue = try FormCueRecord.fetchOne(db, key: id) else { return }
        cue.kind = kind
        cue.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cue.showOnOpen = showOnOpen
        try cue.update(db)
    }

    static func delete(_ db: Database, id: String) throws {
        _ = try FormCueRecord.deleteOne(db, key: id)
    }

    /// Reorders an exercise's cues to the given ids; ids not listed keep their relative order after.
    static func reorder(_ db: Database, exerciseId: String, ids: [String]) throws {
        let current = try cues(db, exerciseId: exerciseId)
        let ordered = ids.compactMap { id in current.first { $0.id == id } } + current.filter { !ids.contains($0.id) }
        for (i, var cue) in ordered.enumerated() where cue.position != i {
            cue.position = i
            try cue.update(db)
        }
    }

    private static func nextPosition(_ db: Database, exerciseId: String) throws -> Int {
        (try Int.fetchOne(db, sql: "SELECT MAX(position) + 1 FROM formCue WHERE exerciseId = ?", arguments: [exerciseId])) ?? 0
    }
}
