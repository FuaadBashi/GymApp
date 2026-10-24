import GRDB
import SwiftUI

struct RootView: View {
    let db: AppDatabase
    @State private var workout: ActiveWorkoutModel
    @State private var launchReport: LaunchReport?
    @State private var tab = RootView.initialTab
    @Environment(\.scenePhase) private var scenePhase

    init(db: AppDatabase) {
        self.db = db
        _workout = State(initialValue: WorkoutHub.model(for: db))
    }

    private struct LaunchReport: Identifiable {
        let id = UUID()
        let report: ImportReport
    }

    var body: some View {
        tabs
            .fullScreenCover(isPresented: Binding(
                get: { workout.isPresented || workout.justFinishedWorkoutId != nil },
                set: { if !$0 { workout.isPresented = false; workout.clearJustFinished() } }
            )) {
                Group {
                    if let finished = workout.justFinishedWorkoutId {
                        SummaryView(workoutId: finished) { workout.clearJustFinished() }
                    } else {
                        WorkoutView()
                    }
                }
                .environment(workout)
            }
            .environment(workout)
            .sheet(item: $launchReport) { ImportReportView(report: $0.report, db: db) }
            .task {
                await workout.resumeIfNeeded()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTestFixture"), workout.snapshot != nil { workout.isPresented = true }
                #endif
                SigningExpiry.scheduleReminder(expiry: SigningExpiry.current())
                await importFromLaunchArgument()
            }
            .onChange(of: scenePhase) { _, phase in
                // Launch counts too: the scene becomes active once at start.
                if phase == .background { BackgroundSync.schedule() }
                if phase == .active {
                    Task { await workout.returnedToForeground() }
                    Task { try? await HealthService.shared.sync(into: db) }
                    Task { await StudioInbox.shared.reload(db) }
                    Task { await SyncScheduler.shared.kick(db) }
                }
            }
    }

    /// Simulator verification: `-tab <0–4>` opens on that tab.
    private static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return 0
    }

    /// Debug builds: `-importJEFIT <path>` imports at launch. A relative path is inside the
    /// app's home, so a file copied onto a cabled phone (`devicectl device copy to`) imports too.
    private func importFromLaunchArgument() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-importJEFIT"), flag + 1 < args.count else { return }
        let path = args[flag + 1]
        let url = path.hasPrefix("/") ? URL(filePath: path) : URL(filePath: NSHomeDirectory()).appending(path: path)
        if let report = try? await ImportService.importJEFIT(fileAt: url, into: db) {
            launchReport = LaunchReport(report: report)
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Train", systemImage: "figure.strengthtraining.traditional", value: 0) {
                TrainView(db: db)
            }
            Tab("History", systemImage: "calendar", value: 1) {
                HistoryView(db: db)
            }
            Tab("Exercises", systemImage: "dumbbell", value: 2) {
                ExercisesView(db: db)
            }
            Tab("Progress", systemImage: "chart.xyaxis.line", value: 3) {
                ProgressTab(db: db)
            }
            Tab("Settings", systemImage: "gearshape", value: 4) {
                SettingsView(db: db)
            }
        }
        .tabViewBottomAccessory(isEnabled: workout.snapshot != nil) {
            MiniPlayer()
        }
    }
}
