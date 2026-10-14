import Foundation
import GRDB

/// Card 6.3: one item of `GymApp-suggestions.json`, written by GymApp Studio into the backup
/// folder. Nothing changes in the app until a suggestion is accepted.
nonisolated struct StudioSuggestion: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case target, swap, note }

    /// `target`: weight × reps for the next session. `swap`: replace `from` with `to` in a day.
    nonisolated struct Change: Codable, Equatable, Sendable {
        var weight: Double?
        var unit: WeightUnit?
        var reps: Int?
        var from: String?
        var to: String?
    }

    var id: String
    var created: Date
    var kind: Kind
    var title: String
    var detail: String
    var reason: String
    var rule: String
    var exerciseId: String?
    var dayId: String?
    var change: Change?

    /// Load as entered in the studio, in hundredths.
    var loadHundredths: Int? { change?.weight.map { Int(($0 * 100).rounded()) } }

    var isValid: Bool {
        guard !id.isEmpty, !title.isEmpty else { return false }
        switch kind {
        case .target:
            guard let c = change, let w = c.weight, w.isFinite, c.unit != nil, let reps = c.reps, reps > 0 else { return false }
            return exerciseId != nil
        case .swap:
            guard let c = change, let from = c.from, let to = c.to, from != to else { return false }
            return dayId != nil
        case .note:
            return true
        }
    }
}

nonisolated enum StudioSuggestions {
    static let fileName = "GymApp-suggestions.json"
    static let decisionsFileName = "GymApp-suggestion-decisions.json"

    enum Failure: LocalizedError, Equatable {
        case alreadyDecided, notFound, changed
        var errorDescription: String? {
            switch self {
            case .alreadyDecided: "This suggestion was already decided."
            case .notFound: "The exercise or day in this suggestion is no longer in the app."
            case .changed: "The day no longer holds the exercise this suggestion would replace."
            }
        }
    }

    /// The file is a JSON list. Items the app can't act on (unknown kind, missing fields) are
    /// skipped rather than failing the whole file; a later id wins over an earlier duplicate.
    static func parse(_ data: Data) throws -> [StudioSuggestion] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: text) ?? fractional.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
            }
            return date
        }
        let items = try decoder.decode([Lenient].self, from: data).compactMap(\.value).filter(\.isValid)
        var byId: [String: StudioSuggestion] = [:]
        for item in items { byId[item.id] = item }
        return byId.values.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id < $1.id }
    }

    private struct Lenient: Decodable {
        var value: StudioSuggestion?
        init(from decoder: Decoder) throws { value = try? StudioSuggestion(from: decoder) }
    }

    /// Suggestions with no decision yet, in file order.
    static func pending(_ db: Database, _ suggestions: [StudioSuggestion]) throws -> [StudioSuggestion] {
        let decided = Set(try String.fetchAll(db, sql: "SELECT suggestionId FROM studioDecision"))
        return suggestions.filter { !decided.contains($0.id) }
    }

    static func accept(_ db: Database, _ s: StudioSuggestion, now: Date) throws {
        try ensureUndecided(db, s)
        switch s.kind {
        case .target:
            guard let id = s.exerciseId, try ExerciseRecord.fetchOne(db, key: id) != nil else { throw Failure.notFound }
        case .swap:
            guard let dayId = s.dayId, let from = s.change?.from, let to = s.change?.to,
                  try ProgramDayRecord.fetchOne(db, key: dayId) != nil,
                  try ExerciseRecord.fetchOne(db, key: to) != nil else { throw Failure.notFound }
            let items = try DayExerciseRecord.filter(Column("dayId") == dayId && Column("exerciseId") == from).fetchAll(db)
            guard !items.isEmpty else { throw Failure.changed }
            for var item in items {
                item.exerciseId = to
                try ProgramWrites.updateItem(db, item: item)
            }
        case .note:
            break
        }
        try record(db, s, .accepted, now: now)
    }

    static func dismiss(_ db: Database, _ s: StudioSuggestion, now: Date) throws {
        try ensureUndecided(db, s)
        try record(db, s, .dismissed, now: now)
    }

    private static func ensureUndecided(_ db: Database, _ s: StudioSuggestion) throws {
        guard try StudioDecisionRecord.fetchOne(db, key: s.id) == nil else { throw Failure.alreadyDecided }
    }

    private static func record(_ db: Database, _ s: StudioSuggestion, _ decision: StudioDecisionRecord.Decision, now: Date) throws {
        let target = s.kind == .target && decision == .accepted
        try StudioDecisionRecord(suggestionId: s.id, kind: s.kind, decision: decision, decidedAt: now, title: s.title,
                                 exerciseId: s.exerciseId ?? s.change?.to,
                                 loadHundredths: target ? s.loadHundredths : nil, unit: target ? s.change?.unit : nil,
                                 reps: target ? s.change?.reps : nil).insert(db)
    }

    /// The accepted target for an exercise, until a finished workout that includes the
    /// exercise starts after it was accepted: a target is for the next session only.
    static func activeTarget(_ db: Database, exerciseId: String) throws -> StudioDecisionRecord? {
        try StudioDecisionRecord.fetchOne(db, sql: """
            SELECT d.* FROM studioDecision d
            WHERE d.exerciseId = ? AND d.kind = 'target' AND d.decision = 'accepted'
              AND NOT EXISTS (SELECT 1 FROM workoutExercise we JOIN workout w ON w.id = we.workoutId
                              WHERE we.exerciseId = d.exerciseId AND w.endedAt IS NOT NULL AND w.startedAt > d.decidedAt)
            ORDER BY d.decidedAt DESC LIMIT 1
            """, arguments: [exerciseId])
    }

    /// What the studio reads back: every decision, oldest first.
    static func decisionsJSON(_ db: Database) throws -> Data {
        struct Out: Encodable { var id: String; var kind: String; var decision: String; var decidedAt: String }
        let iso = ISO8601DateFormatter()
        let rows = try StudioDecisionRecord.order(Column("decidedAt")).fetchAll(db)
            .map { Out(id: $0.suggestionId, kind: $0.kind.rawValue, decision: $0.decision.rawValue, decidedAt: iso.string(from: $0.decidedAt)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }
}
