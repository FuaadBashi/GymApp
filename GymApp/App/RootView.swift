import GRDB
import SwiftUI

struct RootView: View {
    let db: AppDatabase
    @State private var workout: ActiveWorkoutModel
    @State private var launchReport: LaunchReport?
    @State private var tab = RootView.initialTab

    init(db: AppDatabase) {
        self.db = db
        _workout = State(initialValue: ActiveWorkoutModel(db: db))
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
                SigningExpiry.scheduleReminder(expiry: SigningExpiry.current())
                await importFromLaunchArgument()
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

    /// Simulator verification: `-importJEFIT <absolute path>` imports at launch.
    private func importFromLaunchArgument() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-importJEFIT"), flag + 1 < args.count else { return }
        if let report = try? await ImportService.importJEFIT(fileAt: URL(filePath: args[flag + 1]), into: db) {
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
