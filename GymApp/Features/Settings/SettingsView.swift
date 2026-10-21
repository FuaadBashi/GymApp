import GRDB
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class SettingsModel {
    let db: AppDatabase
    var settings = AppSettings()
    var totals: (workouts: Int, sets: Int, exercises: Int)?
    var lastError: String?

    init(db: AppDatabase) { self.db = db }

    func reload() async {
        do {
            settings = try await db.reader.read { try AppSettings.load($0) }
            totals = try await db.reader.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout WHERE endedAt IS NOT NULL") ?? 0,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutSet WHERE completedAt IS NOT NULL") ?? 0,
                 try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise WHERE source != 'library' AND isArchived = 0") ?? 0)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save() {
        let snapshot = settings
        Task {
            do { try await db.writer.write { try snapshot.save($0) } } catch { lastError = error.localizedDescription }
        }
    }
}

struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var choosingFile = false
    @State private var importing = false
    @State private var report: PresentedReport?
    @State private var csv: SharedFile?

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct PresentedReport: Identifiable {
        let id = UUID()
        let report: ImportReport
    }

    init(db: AppDatabase) { _model = State(initialValue: SettingsModel(db: db)) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight", selection: $model.settings.weightUnit) {
                        Text("kg").tag(WeightUnit.kg)
                        Text("lb").tag(WeightUnit.lb)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Sex", selection: $model.settings.sex) {
                        Text("Not set").tag("")
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    Picker("Born", selection: $model.settings.birthYear) {
                        Text("Not set").tag(0)
                        ForEach((1940...2012).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Height", selection: $model.settings.heightCm) {
                        Text("Not set").tag(0)
                        ForEach(140...215, id: \.self) { Text("\($0) cm").tag($0) }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Used for strength standards on each lift's Progress page. Body weight comes from your entries or Apple Health. Kept on this phone.")
                }
                Section("Calendar") {
                    Picker("Week starts on", selection: $model.settings.weekStartsOn) {
                        Text("Sunday").tag(WeekStart.sunday)
                        Text("Monday").tag(WeekStart.monday)
                    }
                }
                Section("New exercises") {
                    Stepper("Sets: \(model.settings.defaultSets)", value: $model.settings.defaultSets, in: 1...10)
                    Stepper("Reps from \(model.settings.defaultRepMin)", value: Binding(
                        get: { model.settings.defaultRepMin },
                        set: { model.settings.defaultRepMin = $0; model.settings.defaultRepMax = max(model.settings.defaultRepMax, $0) }
                    ), in: 1...50)
                    Stepper("Reps to \(model.settings.defaultRepMax)", value: Binding(
                        get: { model.settings.defaultRepMax },
                        set: { model.settings.defaultRepMax = $0; model.settings.defaultRepMin = min(model.settings.defaultRepMin, $0) }
                    ), in: 1...50)
                    Picker("Rest", selection: $model.settings.defaultRestSeconds) {
                        ForEach(Array(stride(from: 30, through: 300, by: 15)), id: \.self) { Text(RestFormat.clock($0)).tag($0) }
                    }
                }
                Section {
                    Picker("Last time shows", selection: $model.settings.lastTimeSource) {
                        Text("Same day").tag(LastTimeSource.sameDay)
                        Text("Any workout").tag(LastTimeSource.anyWorkout)
                    }
                } footer: {
                    Text("Same day compares with the last time you did this routine day, falling back to any workout.")
                }
                AppleHealthSection(db: model.db)
                SyncSection(db: model.db)
                Section("Data") {
                    NavigationLink("Backups & recovery") { RecoveryView(db: model.db) }
                    Button("Import from JEFIT, Strong or Hevy…", systemImage: "square.and.arrow.down") { choosingFile = true }
                    Button("Export sets as CSV", systemImage: "tablecells") { exportCSV() }
                    Button("Export usage counts", systemImage: "hand.tap") { exportUsage() }
                    if let totals = model.totals {
                        Text("\(totals.workouts.formatted()) workouts · \(totals.sets.formatted()) sets · \(totals.exercises.formatted()) of your exercises")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .themedList()
            .navigationTitle("Settings")
            .onChange(of: model.settings) { model.save() }
            .sheet(item: $csv) { BackupShareSheet(url: $0.url) }
            .countsUsage("screen.settings")
            .task { await model.reload() }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
                if case .success(let url) = result { runImport(url) }
                if case .failure(let error) = result { model.lastError = error.localizedDescription }
            }
            .overlay {
                if importing {
                    ProgressView("Importing…").padding(Tokens.Space.xl).background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.card))
                }
            }
            .sheet(item: $report, onDismiss: { Task { await model.reload() } }) {
                ImportReportView(report: $0.report, db: model.db)
            }
            .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.lastError ?? "")
            }
        }
    }

    /// Every completed set, Strong-compatible columns first (docs/EXPORT_FORMAT.md).
    private func exportCSV() {
        Task {
            do {
                let url = try await model.db.reader.read { try CSVExport.write($0) }
                csv = SharedFile(url: url)
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }

    /// Redesign R.0: how often each screen and button is used, for checking the redesign.
    private func exportUsage() {
        Task {
            do {
                let url = try await model.db.reader.read { try Usage.write($0) }
                csv = SharedFile(url: url)
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }

    private func runImport(_ url: URL) {
        importing = true
        Task {
            defer { importing = false }
            do {
                report = PresentedReport(report: try await ImportService.importFile(at: url, into: model.db))
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }
}

nonisolated enum RestFormat {
    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
