import GRDB
import SwiftUI

@Observable
final class ExerciseDetailViewModel {
    let db: AppDatabase
    let exerciseId: String
    private(set) var exercise: ExerciseRecord?
    private(set) var sessions: [ExerciseSession] = []
    private(set) var notes: [ExerciseNoteRecord] = []
    private(set) var libraryName: String?
    private(set) var points: [SessionPoint] = []
    private(set) var records = ExerciseRecords(repRecords: [])
    var lastError: String?

    init(db: AppDatabase, exerciseId: String) {
        self.db = db
        self.exerciseId = exerciseId
    }

    func reload() async {
        let id = exerciseId
        do {
            (exercise, sessions, notes, libraryName, points, records) = try await db.reader.read { db in
                let exercise = try ExerciseRecord.fetchOne(db, key: id)
                let library = try exercise?.libraryId.flatMap { try String.fetchOne(db, sql: "SELECT name FROM exercise WHERE id = ?", arguments: [$0]) }
                let sessions = try ExerciseQueries.sessions(db, exerciseId: id)
                let weight = try BodyQueries.weightLookup(db)
                let mode = exercise?.loadMode ?? .total
                return (exercise, sessions, try ExerciseQueries.notes(db, exerciseId: id), library,
                        ExerciseStats.points(sessions, loadMode: mode, bodyWeightKg: weight),
                        ExerciseStats.records(sessions, loadMode: mode, bodyWeightKg: weight))
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func write(_ change: @escaping @Sendable (Database) throws -> Void) {
        Task {
            do {
                try await db.writer.write(change)
                await reload()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func toggleFavorite() {
        guard let e = exercise else { return }
        let id = e.id, value = !e.isFavorite
        write { try ExerciseWrites.setFavorite($0, id: id, value) }
    }

    func setArchived(_ archived: Bool) {
        let id = exerciseId
        write { try ExerciseWrites.setArchived($0, id: id, archived) }
    }

    func saveStickyNote(_ text: String) {
        let id = exerciseId
        write { try ExerciseWrites.setStickyNote($0, id: id, text: text) }
    }

    func addNote(_ text: String) {
        let id = exerciseId
        write { try ExerciseWrites.addNote($0, exerciseId: id, text: text, date: .now) }
    }
}
