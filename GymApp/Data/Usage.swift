import Foundation
import GRDB
import SwiftUI

/// Redesign card R.0: local counts of screens opened and buttons tapped, so the redesign can
/// be checked against real use. Never sent anywhere; Settings exports them as CSV.
nonisolated enum Usage {
    static func record(_ db: Database, key: String, now: Date) throws {
        try db.execute(sql: """
            INSERT INTO usageCount (key, count, lastAt) VALUES (?, 1, ?)
            ON CONFLICT(key) DO UPDATE SET count = count + 1, lastAt = excluded.lastAt
            """, arguments: [key, now])
    }

    static func csv(_ db: Database) throws -> String {
        let rows = try Row.fetchAll(db, sql: "SELECT key, count, lastAt FROM usageCount ORDER BY count DESC, key")
        return (["key,count,last"] + rows.map { "\($0["key"] as String),\($0["count"] as Int),\($0["lastAt"] as String)" })
            .joined(separator: "\n") + "\n"
    }

    static func write(_ db: Database, now: Date = .now) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GymApp-usage-\(DayString.from(now)).csv")
        try Data(try csv(db).utf8).write(to: url, options: .atomic)
        return url
    }
}

extension AppDatabase {
    /// Counts one use; a failure only loses a count, never data.
    func count(_ key: String) {
        Task { try? await writer.write { try Usage.record($0, key: key, now: .now) } }
    }
}

extension View {
    /// Counts each time this screen appears.
    func countsUsage(_ key: String) -> some View { modifier(UsageCounter(key: key)) }
}

private struct UsageCounter: ViewModifier {
    @Environment(\.appDatabase) private var db
    let key: String
    func body(content: Content) -> some View { content.onAppear { db?.count(key) } }
}
