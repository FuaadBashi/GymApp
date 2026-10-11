import GRDB
import SwiftUI

struct ProgramsListView: View {
    let db: AppDatabase
    @Binding var path: [TrainRoute]
    @State private var programs: [ProgramSummary] = []
    @State private var deleting: ProgramRecord?
    @State private var lastError: String?

    var body: some View {
        List {
            section("Active", programs.filter { $0.program.isActive })
            section("Programs", programs.filter { !$0.program.isActive && !$0.program.isArchived })
            section("Archived", programs.filter { $0.program.isArchived })
        }
        .navigationTitle("Programs")
        .task { await reload() }
        .onAppear { Task { await reload() } }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id { write { try ProgramWrites.deleteProgram($0, programId: id) } }
            }
        } message: {
            Text("Workouts you logged with it are kept.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { lastError != nil }, set: { if !$0 { lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(lastError ?? "") }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [ProgramSummary]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    Button { path.append(.program(row.id)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.program.name).foregroundStyle(.primary)
                            Text("\(row.dayCount) \(row.dayCount == 1 ? "day" : "days")\(row.program.source == .jefit ? " · JEFIT" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        let id = row.id
                        if row.program.source == .app {
                            Button("Delete", role: .destructive) { deleting = row.program }
                        }
                        Button(row.program.isArchived ? "Unarchive" : "Archive") {
                            let archive = !row.program.isArchived
                            write { try ProgramWrites.setArchived($0, programId: id, archive) }
                        }
                        .tint(.gray)
                    }
                }
            }
        }
    }

    private func reload() async {
        programs = (try? await db.reader.read { try ProgramQueries.programs($0) }) ?? []
    }

    private func write(_ change: @escaping @Sendable (Database) throws -> Void) {
        Task {
            do { try await db.writer.write(change) } catch { lastError = error.localizedDescription }
            await reload()
        }
    }
}
