import SwiftUI

/// Card 6.2: Settings → Apple Health. The permission sheet is only ever shown from here.
struct AppleHealthSection: View {
    let db: AppDatabase
    @State private var connected = HealthService.shared.isConnected
    @State private var lastSync = HealthService.shared.lastSync
    @State private var days: Int?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Section {
            if !HealthService.shared.isAvailable {
                Text("Apple Health isn't available on this device.").foregroundStyle(.secondary)
            } else if connected {
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { sync() }
                    .disabled(working)
                Button("Disconnect", systemImage: "heart.slash", role: .destructive) {
                    HealthService.shared.disconnect()
                    connected = false
                }
            } else {
                Button("Connect Apple Health", systemImage: "heart") { connect() }
                    .disabled(working)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var parts = ["Reads daily steps and body weight. Nothing is written to Health."]
        if connected, let lastSync {
            parts.append("Last synced \(lastSync.formatted(.relative(presentation: .named)))" + (days.map { ", \($0) days." } ?? "."))
        }
        if connected {
            parts.append("To change access, open the Health app → your profile → Apps → GymApp.")
        }
        return parts.joined(separator: " ")
    }

    private func connect() {
        working = true
        Task {
            defer { working = false }
            do {
                try await HealthService.shared.connect()
                connected = true
                await run()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func sync() {
        working = true
        Task {
            defer { working = false }
            await run()
        }
    }

    private func run() async {
        do {
            days = try await HealthService.shared.sync(into: db)
            lastSync = HealthService.shared.lastSync
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
