import SwiftUI
import GRDB
import UniformTypeIdentifiers

struct RecoveryView: View {
    let db: AppDatabase
    @State private var status = RecoveryStore.Status()
    @State private var copies: [URL] = []
    @State private var choosingFolder = false
    @State private var choosingRestore = false
    @State private var restoreFile: URL?
    @State private var inspection: RecoveryStore.Inspection?
    @State private var shareFile: URL?
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        recoveryForm
        .navigationTitle("Backups & recovery")
        .task { refresh() }
        .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
        .disabled(busy)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { handleFolder($0) }
        .fileImporter(isPresented: $choosingRestore, allowedContentTypes: [.data]) { handleRestore($0) }
        .sheet(isPresented: Binding(get: { shareFile != nil }, set: { if !$0 { shareFile = nil } })) {
            if let shareFile { BackupShareSheet(url: shareFile) }
        }
        .alert("Backups & recovery", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .confirmationDialog("Restore this backup next launch?", isPresented: Binding(get: { restoreFile != nil && inspection != nil }, set: { if !$0 { restoreFile = nil; inspection = nil } }), titleVisibility: .visible) {
            Button("Schedule restore", role: .destructive) { scheduleRestore() }
            Button("Cancel", role: .cancel) { restoreFile = nil; inspection = nil }
        } message: { Text(restoreDescription) }
    }

    private var recoveryForm: some View {
        Form {
            Section {
                Label("Edits saved on this iPhone", systemImage: "iphone")
                dateRow("Local recovery", status.localAt)
                dateRow("External copy checked", status.externalAt)
                if status.externalPending {
                    Label("External backup pending", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                }
                if let error = status.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                Button("Choose backup folder…") { choosingFolder = true }
                Button("Back up now / retry") { run {
                    guard let store = db.recovery else { return }
                    _ = try await db.reader.read { try store.capture($0) }
                } }
            } header: { Text("Protection") } footer: {
                Text("Local copies protect edits and unfinished sessions. Choose a folder outside GymApp for protection against app deletion. A cloud folder needs its provider to upload the file; this app verifies the copied file, not delivery to a cloud server.")
            }
            Section {
                ForEach(copies, id: \.self) { url in
                    Menu {
                        Button("Share full backup") { run { shareFile = try db.recovery?.export(url) } }
                        Button("Restore this copy…") { inspect(url) }
                    } label: {
                        Text(copyTitle(url)).font(.subheadline).lineLimit(2)
                    }
                }
                Button("Restore from file…") { choosingRestore = true }
            } header: { Text("Recovery copies") } footer: {
                Text("Keeps the latest 30 local copies plus one per month. Restore is applied next launch after making a safety copy of the current data. Full backups contain your private training history and notes.")
            }
        }
    }
    private var restoreDescription: String {
        guard let inspection else { return "" }
        return "\(inspection.workouts) workouts, \(inspection.sets) sets, \(inspection.unfinished) unfinished. This replaces the current data on next launch."
    }
    private func copyTitle(_ url: URL) -> String {
        guard let value = url.lastPathComponent.split(separator: "-").dropFirst().first,
              let milliseconds = Double(value) else { return "Recovery copy" }
        return Date(timeIntervalSince1970: milliseconds / 1000).formatted(date: .abbreviated, time: .standard)
    }
    private func handleFolder(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): run { try db.recovery?.chooseExternalFolder(url); try db.recovery?.retryExternal() }
        case .failure(let error): message = error.localizedDescription
        }
    }
    private func handleRestore(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): inspect(url)
        case .failure(let error): message = error.localizedDescription
        }
    }
    private func scheduleRestore() {
        guard let url = restoreFile else { return }
        run {
            _ = try db.recovery?.stageRestore(url)
            restoreFile = nil; inspection = nil
            message = "Backup checked. Close GymApp and reopen it to restore. The current data will be preserved in a safety copy."
        }
    }
    private func dateRow(_ title: String, _ date: Date?) -> some View {
        LabeledContent(title, value: date?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
    }
    private func refresh() {
        status = db.recovery?.status ?? RecoveryStore.Status()
        copies = (try? db.recovery?.snapshots()) ?? []
    }
    private func inspect(_ url: URL) {
        run {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            inspection = try RecoveryStore.inspect(url)
            restoreFile = url
        }
    }
    private func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false; refresh() }
            do { try await operation() } catch { message = error.localizedDescription }
        }
    }
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
