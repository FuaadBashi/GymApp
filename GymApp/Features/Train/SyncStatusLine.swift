import GRDB
import SwiftUI

/// Train's one-line sync status, live from the database. Hidden while sync is off.
struct SyncStatusLine: View {
    let db: AppDatabase
    @State private var status: SyncStatus?

    var body: some View {
        Group {
            if let status {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Label(status.line(now: context.date),
                          systemImage: status.refused > 0 ? "exclamationmark.icloud" : status.pending > 0 ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                        .font(.caption).foregroundStyle(status.refused > 0 ? Theme.danger : .secondary)
                }
            }
        }
        .task {
            do {
                for try await value in ValueObservation.tracking(SyncEngine.status).values(in: db.reader) { status = value }
            } catch {
                status = nil
            }
        }
    }
}
