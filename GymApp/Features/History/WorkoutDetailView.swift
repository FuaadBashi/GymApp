import GRDB
import SwiftUI

/// A finished workout: every exercise and set, its figures, and corrections (rulebook §10).
/// Every figure is reloaded from `SummaryQueries` after each change, so nothing goes stale.
struct WorkoutDetailView: View {
    let db: AppDatabase
    let workoutId: String
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WorkoutSummary?
    @State private var editing = false
    @State private var selectedSetId: String?
    @State private var title = ""
    @State private var note = ""
    @State private var effort: Int?
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var missing = false

    var body: some View {
        Group {
            if let summary { content(summary) }
            else if missing { ContentUnavailableView("Workout not found", systemImage: "questionmark.circle") }
            else { ProgressView() }
        }
        .background(Theme.background)
        .navigationTitle(summary?.workout.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "Done" : "Edit") { editing ? finishEditing() : startEditing() }
                    .disabled(summary == nil)
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) { deleteWorkout() }
        } message: {
            Text("Its \(summary?.setCount ?? 0) sets are removed from your history and every figure built on them.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .task { await reload() }
    }

    // MARK: Content

    private func content(_ s: WorkoutSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(s)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("Duration", WorkoutRow.duration(s.duration))
                    tile("Volume", "\(Load.format(s.volumeKg.rounded())) kg",
                         s.previousVolumeKg.map { "last time \(Load.format($0.rounded())) kg" })
                    tile("Sets", "\(s.setCount)")
                    tile("Records", "\(s.records.count)")
                }
                if !s.records.isEmpty {
                    card("Records") {
                        ForEach(s.records) { r in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "trophy.fill").foregroundStyle(Theme.accent)
                                Text("\(r.exercise.name) · \(r.kind.rawValue)").font(.subheadline)
                                Spacer()
                                Text("\(Load.format((r.valueKg * 10).rounded() / 10)) kg").font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
                ForEach(s.exercises) { line in exercise(line) }
                if editing {
                    Button("Delete workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private func header(_ s: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing {
                TextField("Title", text: $title).font(.title2.bold())
                    .padding(8).background(Theme.row, in: .rect(cornerRadius: 10))
            } else {
                Text(s.workout.title).font(.title2.bold())
            }
            Text(s.workout.startedAt.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
            if editing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Effort").font(.caption).foregroundStyle(.secondary)
                        ForEach(1...10, id: \.self) { n in
                            Chip(title: "\(n)", isSelected: effort == n) { effort = effort == n ? nil : n }
                        }
                    }
                }
                TextField("Note", text: $note, axis: .vertical).lineLimit(2...5)
                    .padding(8).background(Theme.row, in: .rect(cornerRadius: 10))
            } else {
                if let e = s.workout.effort { Text("Effort \(e)/10").font(.subheadline) }
                if let n = s.workout.note { Text(n).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }

    private func exercise(_ line: WorkoutSummary.ExerciseLine) -> some View {
        let labels = SetComparison.labels(line.sets)
        return card(line.exercise.name) {
            if let note = line.note { Text(note).font(.caption).foregroundStyle(Theme.note) }
            ForEach(Array(line.sets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 6) {
                    HStack {
                        Text(labels[index]).font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(set.type == .warmUp || set.type == .drop ? Theme.note : .primary)
                            .frame(width: 28, alignment: .leading)
                        Text(SetFormat.short(set, loadMode: line.exercise.loadMode)).font(.body.monospacedDigit())
                        if set.type == .failed { Text("failed").font(.caption).foregroundStyle(.red) }
                        Spacer()
                        if let e = TrainingMath.displayableE1RM(kg: SetFormat.kg(set), reps: set.reps, loadMode: line.exercise.loadMode),
                           set.type != .warmUp {
                            Text("e1RM \(Load.format((e * 10).rounded() / 10))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if editing {
                            Menu {
                                ForEach(SetType.allCases, id: \.self) { type in
                                    Button(type.label) { update(set, type: type) }
                                }
                                Divider()
                                Button("Delete set", systemImage: "trash", role: .destructive) { deleteSet(set) }
                            } label: {
                                Image(systemName: "ellipsis.circle").frame(width: 32, height: 32)
                            }
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { if editing { selectedSetId = selectedSetId == set.id ? nil : set.id } }
                    .padding(.vertical, 2)
                    .background(editing && selectedSetId == set.id ? Theme.row : Color.clear, in: .rect(cornerRadius: 8))
                    if editing && selectedSetId == set.id {
                        SetEditor(set: set, exercise: line.exercise) { edit in apply(set, edit) }
                    }
                }
            }
            if editing, let we = workoutExerciseId(for: line) {
                Button("Add set", systemImage: "plus") { addSet(we) }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    // MARK: Data

    private func workoutExerciseId(for line: WorkoutSummary.ExerciseLine) -> String? {
        line.sets.first?.workoutExerciseId
    }

    private func reload() async {
        let id = workoutId
        do {
            summary = try await db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
        } catch {
            missing = true
            summary = nil
        }
    }

    private func change(_ body: @escaping @Sendable (Database) throws -> Void) {
        Task {
            do { try await db.writer.write(body) } catch { self.error = ActiveWorkoutModel.message(for: error) }
            await reload()
        }
    }

    private func apply(_ set: WorkoutSetRecord, _ edit: SetEdit) {
        let id = set.id
        change { try WorkoutWrites.updateSet($0, setId: id, edit: edit) }
    }

    private func update(_ set: WorkoutSetRecord, type: SetType) {
        apply(set, SetEdit(loadHundredths: set.loadHundredths, unit: set.unit, reps: set.reps, type: type))
    }

    private func addSet(_ workoutExerciseId: String) {
        change { db in
            _ = try WorkoutWrites.addLoggedSet(db, workoutExerciseId: workoutExerciseId, settings: try AppSettings.load(db))
        }
    }

    private func deleteSet(_ set: WorkoutSetRecord) {
        let id = set.id
        if selectedSetId == id { selectedSetId = nil }
        change { try WorkoutWrites.deleteLoggedSet($0, setId: id) }
    }

    private func startEditing() {
        guard let w = summary?.workout else { return }
        title = w.title; note = w.note ?? ""; effort = w.effort
        editing = true
    }

    private func finishEditing() {
        let id = workoutId, title = title, note = note, effort = effort
        editing = false
        selectedSetId = nil
        change { db in
            try WorkoutWrites.rename(db, workoutId: id, title: title)
            try WorkoutWrites.setNoteAndEffort(db, workoutId: id, note: note, effort: effort)
        }
    }

    private func deleteWorkout() {
        let id = workoutId
        Task {
            do {
                try await db.writer.write { try WorkoutWrites.deleteFinished($0, workoutId: id) }
                dismiss()
            } catch {
                self.error = ActiveWorkoutModel.message(for: error)
            }
        }
    }
}
