import GRDB
import SwiftUI

/// Settings → Sync (beta): docs/backend/01-plan.md §6. Sends logged sets to the practice server.
struct SyncSection: View {
    let db: AppDatabase
    @State private var server = ""
    @State private var account = ""
    @State private var enabled = false
    @State private var pending = 0
    @State private var refused = 0
    @State private var working = false
    @State private var status: String?

    var body: some View {
        Section {
            TextField("Server, e.g. http://192.168.1.20:8080", text: $server)
                .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Account name", text: $account)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(enabled ? "Sync now" : "Turn on sync", systemImage: "arrow.triangle.2.circlepath") { sync() }
                .disabled(working || URL(string: server)?.host() == nil || account.isEmpty)
            if let status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Sync (beta)")
        } footer: {
            Text(enabled ? "\(pending) changes waiting to send" + (refused > 0 ? ", \(refused) refused by the server" : "")
                           + ". Everything is saved on this phone first; sync never blocks logging."
                         : "Sends your sets to your own server. Off until you turn it on.")
        }
        .task { load() }
    }

    private func load() {
        try? db.reader.read { db in
            enabled = try SyncEngine.isEnabled(db)
            pending = try SyncEngine.pending(db)
            refused = try SyncEngine.refused(db)
            server = try SyncEngine.value(db, "server") ?? server
            account = try SyncEngine.value(db, "account") ?? account
        }
    }

    private func sync() {
        working = true
        server = SyncError.cleanServer(server)
        status = "Syncing…"
        Task {
            defer { working = false; load() }
            do {
                try await db.writer.write { [server, account] db in
                    try SyncEngine.set(db, "server", server)
                    try SyncEngine.set(db, "account", account)
                    try SyncEngine.enable(db)
                }
                guard let engine = SyncEngine.configured(db) else { return }
                try await engine.syncOnce()
                status = "Synced \(Date.now.formatted(date: .omitted, time: .shortened))."
            } catch {
                status = "Not synced: \(error.localizedDescription). Your sets are safe on this phone and will be sent later."
            }
        }
    }
}
