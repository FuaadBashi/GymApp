import GRDB
import SwiftUI

struct ProgramDetailView: View {
    let db: AppDatabase
    let programId: String
    @Binding var path: [TrainRoute]
    @State private var program: ProgramRecord?
    @State private var days: [DayCardData] = []
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var addingDay = false
    @State private var deletingDay: ProgramDayRecord?
    @State private var lastError: String?

    var body: some View {
        List {
            Section {
                ForEach(days) { card in
                    Button { path.append(.day(card.id)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.detail.day.name).foregroundStyle(.primary)
                            Text("\(card.detail.day.focus.displayName) · \(card.detail.items.count) exercises · last \(card.lastDone.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "never")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Delete", role: .destructive) { deletingDay = card.detail.day } }
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    let target = to > source ? to - 1 : to
                    let id = programId
                    write { try ProgramWrites.moveDay($0, programId: id, from: source, to: target) }
                }
            } footer: {
                if program?.isActive == true { Text("This is your active program.") }
            }
        }
        .themedList()
        .navigationTitle(program?.name ?? "Program")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if program?.isActive == false {
                        Button("Make active", systemImage: "checkmark.circle") {
                            let id = programId
                            write { try ProgramWrites.setActive($0, programId: id) }
                        }
                    }
                    Button("Rename", systemImage: "pencil") { nameDraft = program?.name ?? ""; renaming = true }
                    Button("Add day", systemImage: "plus") { addingDay = true }
                }
            }
        }
        .alert("Rename program", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let id = programId, name = nameDraft
                write { try ProgramWrites.rename($0, programId: id, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $addingDay) {
            AddDaySheet { name, focus in
                let id = programId
                write { _ = try ProgramWrites.addDay($0, programId: id, name: name, focus: focus) }
            }
        }
        .confirmationDialog("Delete \(deletingDay?.name ?? "")?", isPresented: Binding(get: { deletingDay != nil }, set: { if !$0 { deletingDay = nil } }),
                            titleVisibility: .visible) {
            Button("Delete day", role: .destructive) {
                if let id = deletingDay?.id { write { try ProgramWrites.deleteDay($0, dayId: id) } }
            }
        } message: { Text("Workouts already logged on it are kept.") }
        .alert("Something went wrong", isPresented: Binding(get: { lastError != nil }, set: { if !$0 { lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(lastError ?? "") }
        .task { await reload() }
        .onAppear { Task { await reload() } }
    }

    private func reload() async {
        let id = programId
        do {
            (program, days) = try await db.reader.read { db in
                let settings = try AppSettings.load(db)
                return (try ProgramRecord.fetchOne(db, key: id),
                        try ProgramQueries.days(db, programId: id).map { try TrainViewModel.card(db, detail: $0, settings: settings, withLastTime: false) })
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func write(_ change: @escaping @Sendable (Database) throws -> Void) {
        Task {
            do { try await db.writer.write(change) } catch { lastError = error.localizedDescription }
            await reload()
        }
    }
}

struct AddDaySheet: View {
    let add: (String, DayFocus) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var focus = DayFocus.fullBody

    var body: some View {
        NavigationStack {
            Form {
                TextField("Day name", text: $name)
                Picker("Focus", selection: $focus) {
                    ForEach(DayFocus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            .themedList()
            .navigationTitle("Add day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(name, focus); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
