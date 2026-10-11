import GRDB
import SwiftUI

struct RootView: View {
    let db: AppDatabase
    @State private var launchReport: LaunchReport?

    private struct LaunchReport: Identifiable {
        let id = UUID()
        let report: ImportReport
    }

    var body: some View {
        tabs
            .sheet(item: $launchReport) { ImportReportView(report: $0.report, db: db) }
            .task { await importFromLaunchArgument() }
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
        TabView {
            Tab("Train", systemImage: "figure.strengthtraining.traditional") {
                TrainView(db: db)
            }
            Tab("History", systemImage: "calendar") {
                HistoryPlaceholder(db: db)
            }
            Tab("Exercises", systemImage: "dumbbell") {
                ExercisesView(db: db)
            }
            Tab("Progress", systemImage: "chart.xyaxis.line") {
                ContentUnavailableView("Progress arrives in phase 3", systemImage: "chart.xyaxis.line")
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(db: db)
            }
        }
    }
}

private struct HistoryPlaceholder: View {
    let db: AppDatabase
    @State private var finished: Int?

    var body: some View {
        ContentUnavailableView("History arrives in phase 3", systemImage: "calendar",
                               description: Text(finished.map { "\($0.formatted()) finished workouts are waiting." } ?? ""))
            .task {
                finished = try? await db.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout WHERE endedAt IS NOT NULL") }
            }
    }
}
