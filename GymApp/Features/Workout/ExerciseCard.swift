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
    @State private var showingPage = false
    @State private var showDemo = false
    @State private var showSticky = false
    @State private var showWorkoutNote = false

    private var done: Int { item.sets.filter { $0.completedAt != nil }.count }
    private var loadMode: LoadMode { item.exercise.loadMode }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isCurrent { expanded } else { collapsed }
        }
        .padding(Tokens.Space.m)
        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.card))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1) }
        }
        .sheet(isPresented: $showingPage) {
            NavigationStack {
                ExerciseDetailView(db: model.db, exerciseId: item.exercise.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingPage = false } } }
            }
            .onAppear { model.db.count("tap.exercisePage") }
        }
        .sheet(isPresented: Binding(get: { metadata != nil }, set: { if !$0 { metadata = nil } })) {
            if let metadata {
                WorkoutMetadataEditor(db: model.db, title: metadata.kind == .set ? "Set notes & labels" : "Exercise note",
                                      draft: metadata) { await model.refresh() }
            }
        }
    }

    /// Card 7.6: "Superset with Row" above a member's name.
    private var supersetLabel: some View {
        let others = model.snapshot?.items.filter {
            $0.id != item.id && $0.workoutExercise.supersetGroup == item.workoutExercise.supersetGroup
        }.map(\.exercise.name) ?? []
        return Label("Superset with \(others.joined(separator: ", "))", systemImage: "link")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
    }

    // MARK: Collapsed

    private var collapsed: some View {
        Button { model.select(itemId: item.id) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if item.workoutExercise.supersetGroup != nil { supersetLabel }
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
                if item.workoutExercise.supersetGroup != nil { supersetLabel }
                Button { showingPage = true } label: {
                    HStack(spacing: 4) {
                        Text(item.exercise.name).font(.title3.bold())
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the exercise page")
                MuscleTags(muscles: item.exercise.primaryMuscles)
            }
            Spacer()
            Menu {
                Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { onAction(.swap) }
                if [.total, .perHand, .perSide].contains(item.exercise.loadMode) {
                    let hasWarmUps = item.sets.contains { $0.type == .warmUp && $0.completedAt == nil }
                    Toggle(isOn: Binding(get: { hasWarmUps }, set: { on in Task { await model.setWarmUps(item.id, on: on) } })) {
                        Label("Warm-up sets", systemImage: "flame")
                    }
                }
                Menu("Superset with…", systemImage: "link") {
                    ForEach(model.snapshot?.items.filter { $0.id != item.id } ?? []) { other in
                        Button(other.exercise.name) { Task { await model.superset(item.id, with: other.id) } }
                    }
                }
                if item.workoutExercise.supersetGroup != nil {
                    Button("Remove from superset", systemImage: "link.badge.plus") { Task { await model.unsuperset(item.id) } }
                }
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
            .accessibilityLabel("Exercise options")
        }

        CueStrip(exerciseId: item.exercise.id)

        Text(todayLine).font(.caption.weight(.medium)).foregroundStyle(.secondary)

        VStack(spacing: 4) {
            header
            let labels = SetComparison.labels(item.sets)
            let previousSets = item.previous?.sets ?? []
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(set: set, label: labels[index], previous: previousSets[safe: index], loadMode: loadMode,
                       isSelected: model.selectedSetId == set.id,
                       best: model.snapshot?.bests[set.id],
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
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Tokens.Space.s)
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
                    if set.completedAt != nil {
                        // Card 7.4: a logged set is fixed in place; records follow because they are derived.
                        HStack {
                            Text("Logged. Changes save at once and records update.").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("Unlog") { Task { await model.unlog(set.id) } }
                            Button("Delete", role: .destructive) { Task { await model.deleteSet(set.id) } }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered).controlSize(.mini)
                    }

                    BestPanel(item: item, set: set) { onAction(.history) }
                        .padding(.horizontal, Tokens.Space.s).padding(.vertical, Tokens.Space.xs)
                    SetEditor(set: set, exercise: item.exercise) { edit in
                        Task { await model.updateDurably(set.id, edit: edit) }
                    }
                    .padding(.vertical, Tokens.Space.xs)
                    ReserveChips(reserve: set.repsInReserve) { value in
                        Task { await model.setReserve(set.id, value) }
                    }
                    .padding(.bottom, Tokens.Space.xs)
                }
            }
        }

        if let target = item.studioTarget, let unit = target.unit, let reps = target.reps {
            HStack {
                Label("Studio: \(Load.format(Double(target.loadHundredths ?? 0) / 100)) \(unit.rawValue) × \(reps)", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !item.plannedSets.isEmpty {
                    Button("Fill sets") { Task { await model.fillStudioTarget(item.id) } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(Tokens.Space.s)
            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: Tokens.Radius.row))
            .accessibilityElement(children: .combine)
        } else {
            TodaySuggestion(item: item)
        }

        Button("Add set", systemImage: "plus") { Task { await model.addSet(to: item.id) } }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

        // Redesign R.4: rare items below the sets, closed until asked for.
        HStack(spacing: 8) {
            extraChip(showDemo ? "Hide demonstration" : "Demonstration") { showDemo.toggle() }
            extraChip(item.exercise.stickyNote == nil ? "Sticky note" : (showSticky ? "Hide note" : "Sticky note")) {
                if item.exercise.stickyNote == nil { editNote() } else { showSticky.toggle() }
            }
            extraChip(item.workoutExercise.note == nil ? "Workout note" : (showWorkoutNote ? "Hide workout note" : "Workout note")) {
                if item.workoutExercise.note == nil {
                    metadata = MetadataDraft(kind: .exercise, id: item.id, note: "")
                } else { showWorkoutNote.toggle() }
            }
        }
        if showDemo { ExerciseMediaView(exercise: item.exercise) }
        if showSticky, let note = item.exercise.stickyNote {
            Button(action: editNote) {
                Label(note, systemImage: "pin.fill")
                    .font(.subheadline).foregroundStyle(Theme.note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Space.s)
                    .background(Theme.note.opacity(0.12), in: .rect(cornerRadius: Tokens.Radius.row))
            }
            .buttonStyle(.plain)
        }
        if showWorkoutNote, let note = item.workoutExercise.note {
            Button { metadata = MetadataDraft(kind: .exercise, id: item.id, note: note) } label: {
                Label(note, systemImage: "note.text").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func extraChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Tokens.Space.m).frame(minHeight: 36)
            .background(Theme.row, in: Capsule())
            .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: SetColumns.set, alignment: .leading)
            if loadMode != .repsOnly {
                Text(SetColumns.loadHeader(unit: item.sets.first?.unit ?? item.exercise.preferredUnit, loadMode: loadMode))
                    .frame(width: SetColumns.load, alignment: .leading)
            }
            Text("REPS").frame(width: SetColumns.reps, alignment: .leading)
            Spacer(minLength: 4)
            Text("LAST").frame(width: SetColumns.last, alignment: .trailing)
            Color.clear.frame(width: 14)
            Image(systemName: "checkmark").frame(width: 44)
        }
        .font(.caption2.weight(.bold))
        .lineLimit(1).minimumScaleFactor(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Tokens.Space.s)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // R.9: fixed columns
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
