import GRDB
import SwiftUI

@Observable
final class DayEditorViewModel {
    let db: AppDatabase
    let dayId: String
    private(set) var card: DayCardData?
    private(set) var settings = AppSettings()
    private(set) var copySources: [(program: ProgramRecord, days: [ProgramDayRecord])] = []
    var lastError: String?

    init(db: AppDatabase, dayId: String) {
        self.db = db
        self.dayId = dayId
    }

    func reload() async {
        let id = dayId
        do {
            let (card, settings, sources) = try await db.reader.read { db in
                let settings = try AppSettings.load(db)
                let card = try ProgramQueries.detail(db, dayId: id).map { try TrainViewModel.card(db, detail: $0, settings: settings, withLastTime: true) }
                let sources = try ProgramQueries.programs(db).map { summary in
                    (summary.program, try ProgramDayRecord.filter(Column("programId") == summary.program.id).order(Column("position")).fetchAll(db))
                }
                return (card, settings, sources)
            }
            self.card = card
            self.settings = settings
            self.copySources = sources.map { (program: $0.0, days: $0.1.filter { $0.id != id }) }.filter { !$0.days.isEmpty }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func write(_ change: @escaping @Sendable (Database) throws -> Void) {
        Task {
            do { try await db.writer.write(change) } catch { lastError = error.localizedDescription }
            await reload()
        }
    }
}
