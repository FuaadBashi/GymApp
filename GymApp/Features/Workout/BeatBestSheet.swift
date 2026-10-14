import SwiftUI

/// Card 7.3: the line under the selected set comparing it with the exercise's bests.
struct BestHintLine: View {
    let set: WorkoutSetRecord
    let hint: WorkoutSnapshot.BestHint
    let loadMode: LoadMode
    let open: () -> Void

    private var e1RM: Double? {
        self.set.loadHundredths.flatMap { TrainingMath.displayableE1RM(kg: Load(hundredths: $0, unit: self.set.unit).kg, reps: self.set.reps, loadMode: loadMode) }
    }

    var body: some View {
        if let best = hint.allTime {
            Button(action: open) {
                HStack(spacing: 6) {
                    if let e1RM { Text("e1RM \(Self.kg(e1RM))") }
                    Text("·").foregroundStyle(.tertiary)
                    Label("best \(Self.kg(best))", systemImage: "trophy.fill").foregroundStyle(Theme.accent)
                    if let months = hint.windowMonths, let windowBest = hint.windowBest {
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(months)-mo best \(Self.kg(windowBest))").foregroundStyle(Theme.gold)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(.caption.monospacedDigit())
                .labelStyle(.titleAndIcon)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what beats your best")
        }
    }

    static func kg(_ value: Double) -> String { "\(Load.format((value * 10).rounded() / 10)) kg" }
}

/// Card 7.3: the lightest load for each rep count that beats the best.
struct BeatBestSheet: View {
    let exerciseName: String
    let best: Double
    let reps: ClosedRange<Int>
    let step: Double
    let unit: WeightUnit
    let onPick: (_ kg: Double, _ reps: Int) -> Void
    let onHistory: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// The table is in the set's unit, so a filled set keeps the unit it was entered in.
    private var bestInUnit: Double { unit == .kg ? best : best / WeightUnit.kgPerLb }
    private var stepInUnit: Double { unit == .kg ? step : max(2.5, ((step / WeightUnit.kgPerLb) / 2.5).rounded() * 2.5) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TrainingMath.beatTable(best: bestInUnit, reps: reps, step: stepInUnit), id: \.reps) { row in
                        Button {
                            onPick(row.kg, row.reps)
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(row.reps) reps").font(.body.monospacedDigit())
                                Spacer()
                                Text("\(Load.format(row.kg)) \(unit.rawValue)").font(.body.weight(.semibold).monospacedDigit())
                                Text("→ \(Load.format((TrainingMath.e1RM(kg: row.kg, reps: row.reps) * 10).rounded() / 10)) \(unit.rawValue)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Best est. 1RM \(Load.format((bestInUnit * 10).rounded() / 10)) \(unit.rawValue)")
                } footer: {
                    Text("The lightest load in \(Load.format(stepInUnit)) \(unit.rawValue) steps that beats it at each rep count. Tap one to fill the set.")
                }
                Section {
                    Button("Exercise history", systemImage: "clock.arrow.circlepath") {
                        dismiss()
                        onHistory()
                    }
                }
            }
            .themedList()
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
