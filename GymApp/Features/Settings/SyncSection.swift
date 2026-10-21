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
    @State private var exported: ExportedFile?
    @State private var confirmingDelete = false

    private struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        Section {
            TextField("Server, e.g. http://192.168.1.20:8080", text: $server)
                .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Account name", text: $account)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(enabled ? "Sync now" : "Turn on sync", systemImage: "arrow.triangle.2.circlepath") { sync() }
                .disabled(working || URL(string: server)?.host() == nil || account.isEmpty)
            if enabled {
                Button("Download server copy", systemImage: "arrow.down.doc") { exportServerCopy() }
                    .disabled(working)
                Button("Delete server copy…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .disabled(working)
            }
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
        .sheet(item: $exported) { BackupShareSheet(url: $0.url) }
        .confirmationDialog("Delete the server copy?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete server copy and turn off sync", role: .destructive) { deleteServerCopy() }
        } message: {
            Text("Removes your account and every row from the server. Your workouts on this phone are not touched.")
        }
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

    private var transport: HTTPSyncTransport? {
        URL(string: SyncError.cleanServer(server)).map { HTTPSyncTransport(base: $0, subject: account) }
    }

    private func exportServerCopy() {
        guard let transport else { return }
        working = true
        status = "Downloading…"
        Task {
            defer { working = false }
            do {
                let url = FileManager.default.temporaryDirectory.appending(path: "bashi-gym-server-copy.json")
                try await transport.exportAccount().write(to: url, options: .atomic)
                exported = ExportedFile(url: url)
                status = nil
            } catch {
                status = "Not downloaded: \(error.localizedDescription)"
            }
        }
    }

    private func deleteServerCopy() {
        guard let transport else { return }
        working = true
        status = "Deleting…"
        Task {
            defer { working = false; load() }
            do {
                try await transport.deleteAccount()
                try await db.writer.write(SyncEngine.disable)
                status = "Server copy deleted. Sync is off."
            } catch {
                status = "Not deleted: \(error.localizedDescription)"
            }
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
