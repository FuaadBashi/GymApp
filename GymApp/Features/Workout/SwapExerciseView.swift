import GRDB
import SwiftUI

/// A single-choice library picker for the workout: add an exercise, or swap one.
struct WorkoutExercisePicker<Header: View>: View {
    let title: String
    var initialFilter = ExerciseFilter()
    var excluded: Set<String> = []
    var sameMovement: MovementPattern? = nil   // offers a "Same movement" chip when set
    let onPick: (String) -> Void
    @ViewBuilder var header: () -> Header

    @Environment(ActiveWorkoutModel.self) private var workout
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExercisesViewModel?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if let model { list(model) } else { ProgressView() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task {
            if model == nil {
                let m = ExercisesViewModel(db: workout.db)
                m.filter = initialFilter
                model = m
            }
        }
    }

    private func list(_ model: ExercisesViewModel) -> some View {
        @Bindable var model = model
        return List {
            Section {
                header()
                Button("New exercise", systemImage: "plus") { creating = true }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    if let pattern = sameMovement {
                        Chip(title: "Same movement", isSelected: model.filter.movementPattern == pattern) {
                            model.filter.movementPattern = model.filter.movementPattern == nil ? pattern : nil
                        }
                    }
                    ExerciseFilterBar(filter: $model.filter)
                }
                .textCase(nil)
            }
            Section {
                ForEach(model.items.filter { !excluded.contains($0.id) }) { item in
                    Button {
                        onPick(item.id)
                        dismiss()
                    } label: {
                        ExerciseRow(item: item).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $model.filter.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .task(id: model.filter) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .sheet(isPresented: $creating) {
            ExerciseEditorView(db: model.db, editing: nil) { created in
                onPick(created.id)
                dismiss()
            }
        }
    }
}

extension WorkoutExercisePicker where Header == EmptyView {
    init(title: String, onPick: @escaping (String) -> Void) {
        self.init(title: title, onPick: onPick, header: { EmptyView() })
    }
}

/// Swap before logging: same movement by default, optionally changing the program day too.
struct SwapSheet: View {
    let item: WorkoutSnapshot.Item
    @Environment(ActiveWorkoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var alsoInProgram = false
    @State private var dayName: String?

    private var hasLogged: Bool { item.sets.contains { $0.completedAt != nil } }

    var body: some View {
        if hasLogged {
            NavigationStack {
                ContentUnavailableView("Swap before logging", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Sets are already logged for \(item.exercise.name). Add an exercise instead."))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
            .presentationDetents([.medium])
        } else {
            WorkoutExercisePicker(title: "Swap \(item.exercise.name)",
                                  initialFilter: ExerciseFilter(movementPattern: item.exercise.movementPattern),
                                  excluded: [item.exercise.id],
                                  sameMovement: item.exercise.movementPattern,
                                  onPick: { id in
                                      let alsoInProgram = alsoInProgram
                                      Task { await model.swap(item.id, to: id, alsoInProgram: alsoInProgram) }
                                  }) {
                if item.workoutExercise.dayExerciseId != nil {
                    Toggle("Also change it in \(dayName ?? "the program")", isOn: $alsoInProgram)
                }
            }
            .task {
                guard let dayId = model.snapshot?.workout.programDayId else { return }
                dayName = try? await model.db.reader.read { try ProgramDayRecord.fetchOne($0, key: dayId)?.name }
            }
        }
    }
}

/// The exercise's History, over the workout.
struct ExerciseHistorySheet: View {
    let db: AppDatabase
    let exerciseId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(db: db, exerciseId: exerciseId)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
