import GRDB
import SwiftUI

@Observable
final class HistoryViewModel {
    let db: AppDatabase
    private(set) var weeks: [HistoryWeek] = []
    private(set) var monthDays: [Date: [String?]] = [:]
    private(set) var thisWeek: (done: Int, goal: Int?) = (0, nil)
    private(set) var settings = AppSettings()
    private(set) var dayOrder: [String] = []   // program day ids, for stable dot colours
    var month = Date.now
    private(set) var loaded = false
    var lastError: String?

    init(db: AppDatabase) { self.db = db }

    func reload() async {
        let month = month
        do {
            let result = try await db.reader.read { db in
                let settings = try AppSettings.load(db)
                return (settings,
                        try HistoryQueries.weeks(db, settings: settings),
                        try HistoryQueries.workoutDays(db, inMonthOf: month),
                        try HistoryQueries.sessionsThisWeek(db, settings: settings, now: .now),
                        try String.fetchAll(db, sql: "SELECT id FROM programDay ORDER BY programId, position"))
            }
            (settings, weeks, monthDays, thisWeek, dayOrder) = result
            loaded = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func showMonth(_ date: Date) async {
        month = date
        let month = date
        monthDays = (try? await db.reader.read { try HistoryQueries.workoutDays($0, inMonthOf: month) }) ?? [:]
    }

    /// A stable colour per program day; grey for workouts with no current day.
    func color(for dayId: String?) -> Color {
        guard let dayId, let index = dayOrder.firstIndex(of: dayId) else { return .gray }
        let palette: [Color] = [Theme.accent, Theme.upper, Theme.lower, Theme.core, .pink, .teal, .yellow, .mint]
        return palette[index % palette.count]
    }
}
