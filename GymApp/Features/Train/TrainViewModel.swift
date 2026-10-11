import GRDB
import SwiftUI

nonisolated struct DayCardData: Identifiable, Equatable {
    var detail: DayDetail
    var lastDone: Date?
    var lastTime: [String: String]  // dayExercise id → "20×10 · 50×10"
    var id: String { detail.id }
}

@Observable
final class TrainViewModel {
    let db: AppDatabase
    private(set) var program: ProgramRecord?
    private(set) var next: DayCardData?
    private(set) var others: [DayCardData] = []
    private(set) var loaded = false
    var lastError: String?

    init(db: AppDatabase) { self.db = db }

    func reload() async {
        do {
            let result = try await db.reader.read { db -> (ProgramRecord?, DayCardData?, [DayCardData]) in
                guard let program = try ProgramQueries.activeProgram(db) else { return (nil, nil, []) }
                let settings = try AppSettings.load(db)
                let nextId = try ProgramQueries.nextDay(db, programId: program.id)?.id
                var next: DayCardData?
                var others: [DayCardData] = []
                for detail in try ProgramQueries.days(db, programId: program.id) {
                    let card = try Self.card(db, detail: detail, settings: settings, withLastTime: detail.id == nextId)
                    if detail.id == nextId { next = card } else { others.append(card) }
                }
                return (program, next, others)
            }
            (program, next, others) = result
            loaded = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Last-time summaries follow rulebook §7: the day's lineage first when that is the setting.
    nonisolated static func card(_ db: Database, detail: DayDetail, settings: AppSettings, withLastTime: Bool) throws -> DayCardData {
        let lineage = Set(try ProgramQueries.lineage(db, dayId: detail.id))
        var lastTime: [String: String] = [:]
        if withLastTime {
            for item in detail.items {
                let prefer = settings.lastTimeSource == .sameDay ? lineage : []
                if let last = try ExerciseQueries.lastSession(db, exerciseId: item.exercise.id, preferringDays: prefer) {
                    let working = last.session.sets.filter { $0.type != .warmUp }
                    lastTime[item.id] = SetFormat.line(working, loadMode: item.exercise.loadMode)
                }
            }
        }
        return DayCardData(detail: detail, lastDone: try ProgramQueries.lastDone(db, dayId: detail.id), lastTime: lastTime)
    }
}
