import GRDB
import SwiftUI

/// One exercise, big numbers: for heavy sets where the list is too much to read.
struct FocusView: View {
    var onAction: (ExerciseCardAction, WorkoutSnapshot.Item) -> Void = { _, _ in }
    @Environment(ActiveWorkoutModel.self) private var model
    @State private var metadata: MetadataDraft?

    var body: some View {
        if let snapshot = model.snapshot, let item = model.currentItem ?? snapshot.items.first {
            content(snapshot, item)
                .sheet(isPresented: Binding(get: { metadata != nil }, set: { if !$0 { metadata = nil } })) {
                    if let metadata { WorkoutMetadataEditor(db: model.db, title: "Notes & labels", draft: metadata) { await model.refresh() } }
                }
        } else {
            ContentUnavailableView("No exercises yet", systemImage: "dumbbell",
                                   description: Text("Add one from the menu."))
        }
    }

    private func content(_ snapshot: WorkoutSnapshot, _ item: WorkoutSnapshot.Item) -> some View {
        let set = item.sets.first { $0.id == model.selectedSetId } ?? item.plannedSets.first ?? item.sets.last
        let labels = SetComparison.labels(item.sets)
        let working = item.sets.filter { $0.type == .working || $0.type == .failed }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.exercise.name).font(.largeTitle.bold()).lineLimit(2).minimumScaleFactor(0.6)
                    if let set, let index = item.sets.firstIndex(of: set) {
                        Text(set.completedAt == nil ? "Set \(labels[index]) of \(working)" : "All sets logged")
                            .font(.headline).foregroundStyle(Theme.accent)
                    }
                }

                if let set {
                    SetEditor(set: set, exercise: item.exercise, onChange: { edit in
                        Task { await model.updateDurably(set.id, edit: edit) }
                    }, large: true)
                    .disabled(set.completedAt != nil)
                    ReserveChips(reserve: set.repsInReserve, large: true) { value in
                        Task { await model.setReserve(set.id, value) }
                    }
                }

                ExerciseMediaView(exercise: item.exercise)
                Button("Exercise note") { metadata = MetadataDraft(kind: .exercise, id: item.id, note: item.workoutExercise.note ?? "") }
                if let note = item.workoutExercise.note { Text(note).font(.caption).foregroundStyle(Theme.note) }
                if let set {
                    Menu("Set type: " + set.type.label) {
                        ForEach(SetType.allCases, id: \.self) { type in
                            Button(type.label) { Task { await model.updateDurably(set.id, edit: SetEdit(loadHundredths: set.loadHundredths, unit: set.unit, reps: set.reps, type: type)) } }
                        }
                    }
                    Button("Set notes & labels") {
                        metadata = MetadataDraft(kind: .set, id: set.id, note: set.note ?? "", reserve: set.repsInReserve, annotations: set.annotations)
                    }
                    if !set.metadataText.isEmpty { Text(set.metadataText).font(.caption).foregroundStyle(Theme.note) }
                }
                Text(contextLine(item, set: set)).font(.subheadline).foregroundStyle(.secondary)
                if let note = item.exercise.stickyNote {
                    Label(note, systemImage: "pin.fill").font(.subheadline).foregroundStyle(Theme.note)
                }

                let done = item.sets.enumerated().filter { $0.element.completedAt != nil }
                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DONE").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(done, id: \.element.id) { index, s in
                            HStack {
                                Text(labels[index]).frame(width: 24, alignment: .leading).foregroundStyle(.secondary)
                                Text(SetFormat.short(s, loadMode: item.exercise.loadMode))
                                Spacer()
                                if let previous = item.previous?.sets[safe: index],
                                   let order = SetComparison.compare(s, previous, loadMode: item.exercise.loadMode) {
                                    switch order {
                                    case .orderedDescending: Image(systemName: "arrow.up").foregroundStyle(Theme.accent)
                                    case .orderedAscending: Image(systemName: "arrow.down").foregroundStyle(Theme.warning)
                                    case .orderedSame: Text("=").foregroundStyle(.secondary)
                                    }
                                }
                                Button { Task { await model.unlog(s.id) } } label: {
                                    Image(systemName: "arrow.uturn.backward").font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unlog")
                            }
                            .font(.body.monospacedDigit())
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                }

                if let next = nextItem(snapshot, after: item) {
                    Button { model.select(itemId: next.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("UP NEXT").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(next.exercise.name).font(.headline)
                                if let previous = next.previous {
                                    Text(SetFormat.line(previous.sets, loadMode: next.exercise.loadMode))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Theme.card, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            move(snapshot, from: item, by: value.translation.width < 0 ? 1 : -1)
        })
        .animation(.snappy, value: model.currentItemId)
    }

    private func contextLine(_ item: WorkoutSnapshot.Item, set: WorkoutSetRecord?) -> String {
        var parts: [String] = []
        if let set, let index = item.sets.firstIndex(of: set), let previous = item.previous?.sets[safe: index] {
            parts.append("Previous \(SetFormat.short(previous, loadMode: item.exercise.loadMode))")
        }
        if let lo = item.workoutExercise.repMin, let hi = item.workoutExercise.repMax {
            parts.append("Target \(lo == hi ? "\(lo)" : "\(lo)–\(hi)")")
        }
        return parts.isEmpty ? "No history yet" : parts.joined(separator: " · ")
    }

    private func nextItem(_ snapshot: WorkoutSnapshot, after item: WorkoutSnapshot.Item) -> WorkoutSnapshot.Item? {
        guard let i = snapshot.items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return snapshot.items[(i + 1)...].first { !$0.plannedSets.isEmpty } ?? snapshot.items[safe: i + 1]
    }

    private func move(_ snapshot: WorkoutSnapshot, from item: WorkoutSnapshot.Item, by step: Int) {
        guard let i = snapshot.items.firstIndex(where: { $0.id == item.id }),
              let target = snapshot.items[safe: i + step] else { return }
        model.select(itemId: target.id)
    }
}
