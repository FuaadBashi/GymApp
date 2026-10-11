import GRDB
import SwiftUI

struct ImportReportView: View {
    let report: ImportReport
    let db: AppDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var totals: (workouts: Int, sets: Int, exercises: Int)?

    var body: some View {
        NavigationStack {
            List {
                section("Imported", report.inserted)
                section("Already in the app", report.alreadyPresent)
                section("Skipped", report.skipped)
                if !report.unmappedExercises.isEmpty {
                    Section("Unmapped exercises") {
                        ForEach(report.unmappedExercises, id: \.self) { Text($0) }
                    }
                }
                Section {
                    if let totals {
                        Text("Database now holds \(totals.workouts.formatted()) workouts, \(totals.sets.formatted()) sets and \(totals.exercises.formatted()) exercises.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("JEFIT import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                totals = try? await db.reader.read { db in
                    (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout") ?? 0,
                     try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workoutSet") ?? 0,
                     try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise WHERE source != 'library'") ?? 0)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ values: [String: Int]) -> some View {
        let rows = values.filter { $0.value > 0 }.sorted { $0.key < $1.key }
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows, id: \.key) { key, count in
                    LabeledContent(key) { Text(count.formatted()).monospacedDigit() }
                }
            }
        }
    }
}
