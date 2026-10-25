import Foundation
import GRDB
import UserNotifications

/// Reads what BreakGuard needs and schedules its one reminder (same identifier, so it moves).
nonisolated enum BreakGuardService {
    static let identifier = "break-guard"

    static func status(_ db: Database, now: Date) throws -> BreakGuard.Status? {
        guard let program = try ProgramQueries.activeProgram(db) else { return nil }
        let settings = try AppSettings.load(db)
        let since = now.addingTimeInterval(-14 * 7 * 86_400)
        let starts = try Date.fetchAll(db, sql: "SELECT startedAt FROM workout WHERE endedAt IS NOT NULL AND startedAt >= ? ORDER BY startedAt", arguments: [since])
        return BreakGuard.status(workouts: starts, goal: program.sessionsPerWeekGoal, now: now,
                                 weekStart: { HistoryQueries.weekStart(of: $0, weekStartsOn: settings.weekStartsOn) })
    }

    static func schedule(_ db: AppDatabase, now: Date = .now) async {
        let plan = try? await db.reader.read { db -> (Date, Int)? in
            guard let program = try ProgramQueries.activeProgram(db) else { return nil }
            let starts = try Date.fetchAll(db, sql: "SELECT startedAt FROM workout WHERE endedAt IS NOT NULL ORDER BY startedAt DESC LIMIT 10").reversed()
            guard let date = BreakGuard.nudgeDate(lastWorkout: starts.last, goal: program.sessionsPerWeekGoal,
                                                  usualHour: BreakGuard.usualHour(Array(starts)), now: now) else { return nil }
            return (date, program.sessionsPerWeekGoal)
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let (date, _) = plan ?? nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for a session"
        content.body = "A few days since your last workout. Even 20 minutes keeps the run going."
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
