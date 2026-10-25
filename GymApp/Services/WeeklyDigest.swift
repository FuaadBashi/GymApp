import Foundation
import GRDB
import UserNotifications

/// A once-a-week notification with the week's totals, on the last evening of the training week
/// (Settings' week start). Re-scheduled each time the app opens or closes, so it carries the
/// newest figures; a week with no app use repeats nothing stale because the date moves on.
nonisolated enum WeeklyDigest {
    static let identifier = "weekly-digest"
    static let hour = 19

    /// 19:00 on the last day of the week containing `now`; the next week's if that has passed.
    static func fireDate(now: Date, weekStartsOn: WeekStart, calendar: Calendar = .current) -> Date {
        let start = HistoryQueries.weekStart(of: now, weekStartsOn: weekStartsOn, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: lastDay) ?? lastDay
        return fire > now ? fire : calendar.date(byAdding: .day, value: 7, to: fire) ?? fire
    }

    /// The text, from the recap figures (RecapQueries), for the week that ends at `fire`.
    static func message(_ recap: Recap) -> (title: String, body: String) {
        guard recap.workouts > 0 else {
            return ("Your training week", "No workouts logged this week. Next up is waiting on Train.")
        }
        var parts = ["\(recap.workouts) workout\(recap.workouts == 1 ? "" : "s")",
                     "\(recap.sets) set\(recap.sets == 1 ? "" : "s")",
                     "\(Load.format(recap.volumeKg.rounded())) kg lifted"]
        if recap.records > 0 { parts.append("\(recap.records) record\(recap.records == 1 ? "" : "s")") }
        var body = parts.joined(separator: " · ") + "."
        if let muscle = recap.topMuscle {
            body += " Most trained: \(muscle.displayName.lowercased()) (\(Load.format((recap.topMuscleSets * 10).rounded() / 10)) hard sets)."
        }
        return ("Your training week", body)
    }

    static func content(_ db: Database, now: Date) throws -> (fire: Date, title: String, body: String) {
        let settings = try AppSettings.load(db)
        let fire = fireDate(now: now, weekStartsOn: settings.weekStartsOn)
        let start = HistoryQueries.weekStart(of: fire, weekStartsOn: settings.weekStartsOn)
        let recap = try RecapQueries.recap(db, from: start, to: fire, weekStartsOn: settings.weekStartsOn, byMonth: false)
        let m = message(recap)
        return (fire, m.title, m.body)
    }

    static func schedule(_ db: AppDatabase, now: Date = .now) async {
        guard let c = try? await db.reader.read({ try content($0, now: now) }) else { return }
        let request = UNNotificationRequest(identifier: identifier, content: {
            let n = UNMutableNotificationContent()
            n.title = c.title
            n.body = c.body
            return n
        }(), trigger: UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: c.fire), repeats: false))
        try? await UNUserNotificationCenter.current().add(request)   // same identifier replaces the last one
    }
}
