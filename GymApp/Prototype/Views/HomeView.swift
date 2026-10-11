import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.appDatabase) private var database
    @State private var showingWorkout = false
    @State private var choosingFile = false
    @State private var importing = false
    @State private var importResult: PresentedReport?
    @State private var importError: String?

    private struct PresentedReport: Identifiable {
        let id = UUID()
        let report: ImportReport
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = store.loadError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    if let session = store.active {
                        ResumeCard(session: session) { showingWorkout = true }
                    }
                    if let next = store.nextDay {
                        SectionTitle("Next up")
                        DayCard(day: next, expanded: true, canStart: store.active == nil) { start(next) }
                    }
                    let others = store.days.filter { $0.id != store.nextDay?.id }
                    if !others.isEmpty {
                        SectionTitle("Other days")
                        ForEach(others) { day in
                            DayCard(day: day, expanded: false, canStart: store.active == nil) { start(day) }
                        }
                    }
                    footer
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Train")
            .toolbar {
                Menu {
                    Button("Import JEFIT export…", systemImage: "square.and.arrow.down") { choosingFile = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            switch result {
            case .success(let url): runImport(url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .overlay {
            if importing {
                ProgressView("Importing…").padding(24).background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .sheet(item: $importResult) { presented in
            if let database { ImportReportView(report: presented.report, db: database) }
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .task { importFromLaunchArgument() }
        .fullScreenCover(isPresented: $showingWorkout) {
            ActiveWorkoutView { showingWorkout = false }
                .environment(store)
        }
    }

    private func runImport(_ url: URL) {
        guard let database else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                importResult = PresentedReport(report: try await ImportService.importJEFIT(fileAt: url, into: database))
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Simulator verification: `-importJEFIT <absolute path>` imports at launch.
    private func importFromLaunchArgument() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-importJEFIT"), flag + 1 < args.count {
            runImport(URL(filePath: args[flag + 1]))
        }
        #endif
    }

    private func start(_ day: RoutineDay) {
        store.start(day)
        showingWorkout = true
    }

    @ViewBuilder private var footer: some View {
        if let seed = store.seed {
            Text("Prototype. Routine and history from \(seed.source); body weight \(Load.format(seed.bodyWeightKg)) kg (\(seed.bodyWeightDate)). Workouts logged here stay on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

private struct ResumeCard: View {
    let session: WorkoutSession
    let resume: () -> Void

    var body: some View {
        Button(action: resume) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In progress · \(session.dayName)").font(.headline)
                    HStack(spacing: 6) {
                        Text(session.startedAt, style: .timer).monospacedDigit()
                        Text("· \(session.loggedSetCount) sets logged")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Resume").font(.headline)
            }
            .padding()
            .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct DayCard: View {
    @Environment(WorkoutStore.self) private var store
    let day: RoutineDay
    let expanded: Bool
    let canStart: Bool
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.name).font(.title2.bold())
                Spacer()
                if let last = store.lastDone(day) {
                    Text("Last \(last.formatted(.dateTime.day().month()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(day.exercises.count) exercises · est. \(estimatedMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if expanded {
                VStack(spacing: 10) {
                    ForEach(day.exercises) { exercise in
                        HStack(alignment: .firstTextBaseline) {
                            Text(exercise.name).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(lastSummary(exercise))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
            Button(action: start) {
                Text("Start \(day.name)").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStart)
        }
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    /// Rulebook §11 fallback: Σ over sets of (40 s + rest). The prototype has no
    /// per-day session durations yet to take a median from.
    private var estimatedMinutes: Int {
        let seconds = day.exercises.reduce(0) { $0 + $1.targetSets * (40 + $1.restSeconds) }
        return Int((Double(seconds) / 60).rounded())
    }

    private func lastSummary(_ exercise: PlannedExercise) -> String {
        guard let last = store.lastTime(for: exercise.id, dayId: day.id) else { return "new" }
        return last.entry.sets.filter { $0.type != .warmUp }.map(\.shortText).joined(separator: " · ")
    }
}
