import GRDB
import SwiftUI

/// Adds exercises to a day. The library opens narrowed to the day's focus (decision #21),
/// with "Show all" one toggle away.
struct ExercisePickerView: View {
    let day: DayDetail
    @State private var model: ExercisesViewModel
    @State private var selected: [String] = []   // in tap order: that is the order they're added
    @State private var onlyFocus = true
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss

    init(db: AppDatabase, day: DayDetail) {
        self.day = day
        _model = State(initialValue: ExercisesViewModel(db: db))
    }

    private var hasFocusRule: Bool { ![.fullBody, .custom].contains(day.day.focus) }
    private var inDay: Set<String> { Set(day.items.map(\.exercise.id)) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    if hasFocusRule {
                        Toggle("Only \(day.day.focus.displayName.lowercased()) exercises", isOn: $onlyFocus)
                    }
                    Button("New exercise", systemImage: "plus") { creating = true }
                } header: {
                    ExerciseFilterBar(filter: $model.filter).textCase(nil)
                }
                Section {
                    ForEach(model.items) { item in
                        row(item)
                    }
                }
            }
            .navigationTitle("Add to \(day.day.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.filter.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add \(selected.count) exercise\(selected.count == 1 ? "" : "s")") { add() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selected.isEmpty)
                    .padding()
                    .background(.bar)
            }
            .sheet(isPresented: $creating) {
                ExerciseEditorView(db: model.db, editing: nil) { created in
                    selected.append(created.id)
                    Task { await model.reload() }
                }
            }
            .onChange(of: onlyFocus, initial: true) {
                model.filter.focus = hasFocusRule && onlyFocus ? day.day.focus : nil
            }
            .task(id: model.filter) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await model.reload()
            }
        }
    }

    private func row(_ item: ExerciseListItem) -> some View {
        let already = inDay.contains(item.id)
        let chosen = selected.contains(item.id)
        return Button {
            if let i = selected.firstIndex(of: item.id) { selected.remove(at: i) } else { selected.append(item.id) }
        } label: {
            HStack {
                ExerciseRow(item: item)
                if already {
                    Text("In this day").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chosen ? Theme.accent : Color.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(already)
        .opacity(already ? 0.5 : 1)
    }

    private func add() {
        let ids = selected, dayId = day.id
        Task {
            do {
                try await model.db.writer.write { db in
                    try ProgramWrites.addExercises(db, dayId: dayId, exerciseIds: ids, settings: try AppSettings.load(db))
                }
                dismiss()
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }
}
