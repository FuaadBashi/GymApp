import GRDB
import SwiftUI

/// One exercise in the workout list: a summary line when collapsed, the set table when current.
struct ExerciseCard: View {
    let item: WorkoutSnapshot.Item
    let isCurrent: Bool
    var onAction: (ExerciseCardAction) -> Void = { _ in }

    @Environment(ActiveWorkoutModel.self) private var model
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var metadata: MetadataDraft?

    private var done: Int { item.sets.filter { $0.completedAt != nil }.count }
    private var loadMode: LoadMode { item.exercise.loadMode }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCurrent { expanded } else { collapsed }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1) }
        }
        .sheet(isPresented: Binding(get: { metadata != nil }, set: { if !$0 { metadata = nil } })) {
            if let metadata {
                WorkoutMetadataEditor(db: model.db, title: metadata.kind == .set ? "Set notes & labels" : "Exercise note",
                                      draft: metadata) { await model.refresh() }
            }
        }
    }

    // MARK: Collapsed

    private var collapsed: some View {
        Button { model.select(itemId: item.id) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.exercise.name).font(.headline).foregroundStyle(.primary)
                    if let previous = item.previous {
                        Text("Previous: " + SetFormat.line(previous.sets, loadMode: loadMode))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("\(done)/\(item.sets.count)").monospacedDigit()
                    if done == item.sets.count && !item.sets.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Expanded

    @ViewBuilder private var expanded: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.exercise.name).font(.title3.bold())
                MuscleTags(muscles: item.exercise.primaryMuscles)
            }
            Spacer()
            Menu {
                Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { onAction(.swap) }
                Button("History", systemImage: "clock.arrow.circlepath") { onAction(.history) }
                if [.barbell, .ezBar, .smith].contains(item.exercise.equipment) {
                    Button("Plate calculator", systemImage: "circle.grid.2x1") { onAction(.plates) }
                }
                Button("Session exercise note", systemImage: "note.text") {
                    metadata = MetadataDraft(kind: .exercise, id: item.id, note: item.workoutExercise.note ?? "")
                }
                Button(item.exercise.stickyNote == nil ? "Add sticky note" : "Edit sticky note", systemImage: "note.text") { editNote() }
                Divider()
                Button("Remove", systemImage: "trash", role: .destructive) {
                    Task { await model.removeExercise(item.id) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 36, height: 36).background(Theme.row, in: Circle())
            }
        }

        if let note = item.exercise.stickyNote {
            Button(action: editNote) {
                Label(note, systemImage: "pin.fill")
                    .font(.subheadline).foregroundStyle(Theme.note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.note.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }

        ExerciseMediaView(exercise: item.exercise)
        Button {
            metadata = MetadataDraft(kind: .exercise, id: item.id, note: item.workoutExercise.note ?? "")
        } label: {
            Label(item.workoutExercise.note ?? "Add a note for this workout", systemImage: "note.text")
                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(todayLine).font(.caption.weight(.medium)).foregroundStyle(.secondary)

        VStack(spacing: 4) {
            header
            let labels = SetComparison.labels(item.sets)
            let previousSets = item.previous?.sets ?? []
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(set: set, label: labels[index], previous: previousSets[safe: index], loadMode: loadMode,
                       isSelected: model.selectedSetId == set.id,
                       onSelect: { model.select(setId: set.id) },
                       onToggle: { Task { set.completedAt == nil ? await model.log(set.id) : await model.unlog(set.id) } })
                    .contextMenu {
                        Button("Notes & labels…", systemImage: "note.text") {
                            metadata = MetadataDraft(kind: .set, id: set.id, note: set.note ?? "",
                                                     reserve: set.repsInReserve, annotations: set.annotations)
                        }
                        ForEach(SetType.allCases, id: \.self) { type in
                            Button(type.label) {
                                Task { await model.updateDurably(set.id, edit: SetEdit(loadHundredths: set.loadHundredths, unit: set.unit, reps: set.reps, type: type)) }
                            }
                        }
                        Button("Delete set", systemImage: "trash", role: .destructive) { Task { await model.deleteSet(set.id) } }
                    }
                if !set.metadataText.isEmpty {
                    Text(set.metadataText).font(.caption).foregroundStyle(Theme.note)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                }
                if model.selectedSetId == set.id {
                    HStack {
                        Menu("Set type: " + set.type.label) {
                            ForEach(SetType.allCases, id: \.self) { type in
                                Button(type.label) { Task { await model.updateDurably(set.id, edit: SetEdit(loadHundredths: set.loadHundredths, unit: set.unit, reps: set.reps, type: type)) } }
                            }
                        }
                        Spacer()
                        Button("Notes & labels") {
                            metadata = MetadataDraft(kind: .set, id: set.id, note: set.note ?? "", reserve: set.repsInReserve, annotations: set.annotations)
                        }
                    }.font(.caption)

                    SetEditor(set: set, exercise: item.exercise) { edit in
                        Task { await model.updateDurably(set.id, edit: edit) }
                    }
                    .padding(.vertical, 4)
                    ReserveChips(reserve: set.repsInReserve) { value in
                        Task { await model.setReserve(set.id, value) }
                    }
                    .padding(.bottom, 4)
                }
            }
        }

        Button("Add set", systemImage: "plus") { Task { await model.addSet(to: item.id) } }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: SetColumns.set, alignment: .leading)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            if loadMode != .repsOnly {
                Text(SetColumns.loadHeader(unit: item.sets.first?.unit ?? item.exercise.preferredUnit, loadMode: loadMode))
                    .frame(width: SetColumns.load, alignment: .trailing)
            }
            Text("REPS").frame(width: SetColumns.reps, alignment: .trailing)
            Color.clear.frame(width: 14)
            Image(systemName: "checkmark").frame(width: 44)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }

    private var todayLine: String {
        var parts: [String] = []
        let we = item.workoutExercise
        if let sets = we.targetSets, let lo = we.repMin, let hi = we.repMax {
            parts.append("Target \(sets) × \(lo == hi ? "\(lo)" : "\(lo)–\(hi)")")
        }
        if let previous = item.previous {
            let date = previous.workout.startedAt.formatted(.dateTime.day().month(.abbreviated))
            parts.append("Previous \(date) (\(item.previousIsSameDay ? "same day" : "another day"))")
        } else {
            parts.append("No history yet")
        }
        return parts.joined(separator: " · ")
    }

    private func editNote() {
        metadata = MetadataDraft(kind: .sticky, id: item.exercise.id, note: item.exercise.stickyNote ?? "")
    }
}

enum ExerciseCardAction { case swap, history, plates }

extension SetType {
    var label: String {
        switch self {
        case .working: "Working"
        case .warmUp: "Warm-up"
        case .failed: "Failed"
        case .drop: "Drop set"
        }
    }
}
