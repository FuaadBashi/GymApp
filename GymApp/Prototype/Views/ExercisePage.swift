import SwiftUI

struct ExercisePage: View {
    @Environment(WorkoutStore.self) private var store
    let exerciseIndex: Int

    @State private var noteExpanded = false
    @State private var editing: Field?
    @State private var draft = ""

    private enum Field { case load, reps }

    var body: some View {
        if let exercise = store.active?.exercises[safe: exerciseIndex] {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(exercise)
                    if let note = exercise.note {
                        noteCard(note, date: exercise.noteDate)
                    }
                    setTable(exercise)
                    if exercise.sets.indices.contains(exercise.selected) {
                        editor(exercise, set: exercise.selected)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: Header

    private func header(_ exercise: ExerciseInWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name).font(.title2.bold())
            HStack {
                Menu {
                    ForEach([30, 45, 60, 90, 120, 150, 180], id: \.self) { seconds in
                        Button(Self.clock(seconds)) { store.setRest(seconds: seconds, exercise: exerciseIndex) }
                    }
                } label: {
                    Label("Rest \(Self.clock(exercise.restSeconds))", systemImage: "timer")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.row, in: Capsule())
                }
                Text(exercise.equipment.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let set = exercise.sets[safe: exercise.selected],
                   let e1rm = TrainingMath.displayableE1RM(kg: set.load.kg, reps: set.reps, loadMode: exercise.equipment.loadMode) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Est. 1RM").font(.caption2).foregroundStyle(.secondary)
                        Text(Load.format((e1rm * 10).rounded() / 10)).font(.headline.monospacedDigit())
                    }
                }
            }
        }
    }

    private func noteCard(_ text: String, date: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text").foregroundStyle(Theme.note)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).lineLimit(noteExpanded ? nil : 3)
                if let date {
                    Text("Note from \(date)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(12)
        .background(Theme.note.opacity(0.12), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .onTapGesture { withAnimation { noteExpanded.toggle() } }
    }

    // MARK: Set table

    private func setTable(_ exercise: ExerciseInWorkout) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(lastTimeCaption(exercise)).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 4)
            HStack {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("LAST").frame(maxWidth: .infinity, alignment: .leading)
                Text(exercise.sets.first?.load.unit.rawValue.uppercased() ?? "KG").frame(width: 76, alignment: .trailing)
                Text("REPS").frame(width: 50, alignment: .trailing)
                Color.clear.frame(width: 44, height: 1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                row(exercise, set: set, index: index)
            }

            Button { withAnimation { store.addSet(exercise: exerciseIndex) } } label: {
                Label("Add set", systemImage: "plus").font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            }
        }
    }

    private func row(_ exercise: ExerciseInWorkout, set: SetEntry, index: Int) -> some View {
        let last = exercise.lastTime?.sets[safe: index]
        let ink = set.isLogged ? Color.primary : Color.secondary
        return HStack {
            Text(setLabel(exercise, index: index))
                .font(.headline)
                .foregroundStyle(set.type == .warmUp ? Color.orange : set.type == .failed ? Color.red : Color.primary)
                .frame(width: 34, alignment: .leading)
            HStack(spacing: 4) {
                Text(last?.shortText ?? "—").foregroundStyle(.secondary)
                if set.isLogged, let last { comparison(set, last, equipment: exercise.equipment) }
            }
            .font(.subheadline.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(set.load.formatted).frame(width: 76, alignment: .trailing).foregroundStyle(ink)
            Text("\(set.reps)").frame(width: 50, alignment: .trailing).foregroundStyle(ink)
            Button { withAnimation { store.toggleLogged(exercise: exerciseIndex, set: index) } } label: {
                Image(systemName: set.isLogged ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isLogged ? Theme.accent : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(set.isLogged ? "Un-log set \(index + 1)" : "Log set \(index + 1)")
        }
        .font(.title3.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(index == exercise.selected ? Theme.row : Color.clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { store.select(set: index, in: exerciseIndex) }
        .contextMenu {
            Button("Working set", systemImage: "circle") { store.setType(.working, exercise: exerciseIndex, set: index) }
            Button("Warm-up", systemImage: "flame") { store.setType(.warmUp, exercise: exerciseIndex, set: index) }
            Button("Failed / partial", systemImage: "xmark.circle") { store.setType(.failed, exercise: exerciseIndex, set: index) }
            Divider()
            Button("Delete set", systemImage: "trash", role: .destructive) {
                withAnimation { store.deleteSet(exercise: exerciseIndex, set: index) }
            }
        }
    }

    /// Warm-ups read "W" and don't take a number, so set 1 is the first set that counts.
    private func setLabel(_ exercise: ExerciseInWorkout, index: Int) -> String {
        if exercise.sets[index].type == .warmUp { return "W" }
        let number = exercise.sets[..<index].filter { $0.type != .warmUp }.count + 1
        return "\(number)"
    }

    /// Did this set beat the same row last time? Compared by estimated 1RM so that
    /// 60 × 10 beats 60 × 8 (rulebook §8's notion of progress).
    @ViewBuilder
    private func comparison(_ set: SetEntry, _ last: PastSet, equipment: ProtoEquipment) -> some View {
        let now = equipment == .assisted ? set.load.kg : TrainingMath.e1RM(kg: set.load.kg, reps: set.reps)
        let then = equipment == .assisted ? last.kg : TrainingMath.e1RM(kg: last.kg, reps: last.reps)
        if now > then + 0.01 {
            Image(systemName: "arrow.up").foregroundStyle(Theme.accent)
        } else if now < then - 0.01 {
            Image(systemName: "arrow.down").foregroundStyle(.orange)
        } else {
            Image(systemName: "equal").foregroundStyle(.secondary)
        }
    }

    private func lastTimeCaption(_ exercise: ExerciseInWorkout) -> String {
        guard let last = exercise.lastTime else { return "No history yet" }
        let when = last.date.formatted(.dateTime.day().month().year())
        return exercise.lastTimeIsSameDay ? "Last time on this day · \(when)" : "Last time (another day) · \(when)"
    }

    // MARK: Editor

    private func editor(_ exercise: ExerciseInWorkout, set index: Int) -> some View {
        let set = exercise.sets[index]
        let unit = set.load.unit.rawValue
        return VStack(alignment: .leading, spacing: 8) {
            Text("Set \(setLabel(exercise, index: index))\(set.isLogged ? " · logged" : "")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                StepperField(title: unit, value: set.load.formatted,
                             minus: { store.stepLoad(-1, exercise: exerciseIndex, set: index) },
                             plus: { store.stepLoad(1, exercise: exerciseIndex, set: index) },
                             edit: { draft = set.load.formatted; editing = .load })
                StepperField(title: "reps", value: "\(set.reps)",
                             minus: { store.setReps(set.reps - 1, exercise: exerciseIndex, set: index) },
                             plus: { store.setReps(set.reps + 1, exercise: exerciseIndex, set: index) },
                             edit: { draft = "\(set.reps)"; editing = .reps })
            }
        }
        .padding(.top, 4)
        .alert(editing == .load ? "Weight (\(unit))" : "Reps", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField(editing == .load ? unit : "reps", text: $draft)
                .keyboardType(editing == .load ? .decimalPad : .numberPad)
            Button("Set") { commit(set: index) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func commit(set index: Int) {
        let text = draft.replacingOccurrences(of: ",", with: ".")
        switch editing {
        case .load: if let value = Double(text) { store.setLoad(value, exercise: exerciseIndex, set: index) }
        case .reps: if let reps = Int(text) { store.setReps(reps, exercise: exerciseIndex, set: index) }
        case nil: break
        }
        editing = nil
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct StepperField: View {
    let title: String
    let value: String
    let minus: () -> Void
    let plus: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                stepButton("minus", action: minus)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture(perform: edit)
                stepButton("plus", action: plus)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Theme.row, in: Circle())
        }
        .buttonRepeatBehavior(.enabled)
    }
}
