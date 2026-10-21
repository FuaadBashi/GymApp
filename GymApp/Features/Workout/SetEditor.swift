import GRDB
import SwiftUI

/// Steppers for the selected set's load and reps. Values are tappable to type.
struct SetEditor: View {
    let set: WorkoutSetRecord
    let exercise: ExerciseRecord
    let onChange: (SetEdit) -> Void
    var large = false

    @State private var typing: Field?
    @State private var draft = ""

    enum Field { case load, reps }

    private var edit: SetEdit {
        SetEdit(loadHundredths: set.loadHundredths, unit: set.unit, reps: set.reps, type: set.type)
    }

    static func step(_ exercise: ExerciseRecord, unit: WeightUnit) -> Double {
        unit == .lb ? 5 : exercise.equipment.stepKg
    }

    var body: some View {
        HStack(spacing: large ? 12 : 10) {
            if exercise.loadMode != .repsOnly {
                panel(title: SetColumns.loadHeader(unit: set.unit, loadMode: exercise.loadMode),
                      value: Load.format(Double(set.loadHundredths ?? 0) / 100), field: .load,
                      minus: { stepLoad(-1) }, plus: { stepLoad(1) }) {
                    Button(set.unit == .kg ? "kg" : "lb") {
                        var e = edit
                        e.unit = set.unit == .kg ? .lb : .kg   // rulebook §1: the number stays as entered
                        onChange(e)
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            panel(title: "REPS", value: "\(set.reps)", field: .reps,
                  minus: { stepReps(-1) }, plus: { stepReps(1) }) { EmptyView() }
        }
        .alert(typing == .load ? "Weight (\(set.unit.rawValue))" : "Reps", isPresented: Binding(
            get: { typing != nil }, set: { if !$0 { typing = nil } }
        )) {
            TextField(typing == .load ? set.unit.rawValue : "reps", text: $draft)
                .keyboardType(typing == .load ? .decimalPad : .numberPad)
            Button("Set") { commitTyped() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func panel<Extra: View>(title: String, value: String, field: Field, minus: @escaping () -> Void,
                                    plus: @escaping () -> Void, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: large ? 10 : 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                extra()
            }
            HStack(spacing: 6) {
                stepButton("minus", label: field == .load ? "Less weight" : "Fewer reps", action: minus)
                Button {
                    draft = field == .load ? Load.format(Double(set.loadHundredths ?? 0) / 100) : "\(set.reps)"
                    typing = field
                } label: {
                    Text(value)
                        .font(.system(size: large ? Tokens.Size.stepperFigureLarge : Tokens.Size.stepperFigure, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .rollingNumber(value)
                }
                .buttonStyle(.plain)
                stepButton("plus", label: field == .load ? "More weight" : "More reps", action: plus)
            }
        }
        .padding(large ? 16 : 10)
        .frame(maxWidth: .infinity)
        .background(Theme.row, in: .rect(cornerRadius: Tokens.Radius.row))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: large ? 48 : 36, height: large ? 48 : 36)
                .background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func stepLoad(_ direction: Double) {
        let current = Double(set.loadHundredths ?? 0) / 100
        var next = current + direction * Self.step(exercise, unit: set.unit)
        if exercise.loadMode != .bodyweightPlus { next = max(0, next) }
        var e = edit
        e.loadHundredths = Int((next * 100).rounded())
        onChange(e)
    }

    private func stepReps(_ delta: Int) {
        var e = edit
        e.reps = max(0, set.reps + delta)
        onChange(e)
    }

    private func commitTyped() {
        let text = draft.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var e = edit
        switch typing {
        case .load:
            guard let value = Double(text) else { return }
            e.loadHundredths = Int((value * 100).rounded())
        case .reps:
            guard let value = Int(text), value >= 0 else { return }
            e.reps = value
        case nil: return
        }
        onChange(e)
    }
}
