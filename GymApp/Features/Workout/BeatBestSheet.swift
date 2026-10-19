import SwiftUI

/// Card 7.3: the line under the selected set comparing it with the exercise's bests.
struct BestHintLine: View {
    let set: WorkoutSetRecord
    let hint: WorkoutSnapshot.BestHint
    let loadMode: LoadMode
    /// Opens the beat table for the tapped best: its title and estimated 1RM.
    let open: (_ title: String, _ best: Double) -> Void

    private var e1RM: Double? {
        self.set.loadHundredths.flatMap { TrainingMath.displayableE1RM(kg: Load(hundredths: $0, unit: self.set.unit).kg, reps: self.set.reps, loadMode: loadMode) }
    }

    var body: some View {
        if let best = hint.allTime {
            VStack(alignment: .leading, spacing: 8) {
                // The set as typed now, estimated live from the editor's values (rulebook §5b).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("This set").font(.subheadline).foregroundStyle(.secondary)
                    Text(e1RM.map(Self.kg) ?? "—").font(Theme.number(.title3, weight: .bold))
                    Text(e1RM == nil ? "no estimate outside 1–12 reps" : "est. 1RM").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("this-set-e1rm")
                HStack(spacing: 8) {
                    tile("All-time best", best, hint.allTimeSet, colour: Theme.accent)
                    if let months = hint.windowMonths, let windowBest = hint.windowBest {
                        tile("\(months)-month best", windowBest, hint.windowSet, colour: Theme.gold)
                    }
                }
            }
        }
    }

    private func tile(_ title: String, _ best: Double, _ source: WorkoutSetRecord?, colour: Color) -> some View {
        Button { open(title, best) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(colour)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
                }
                Text(Self.kg(best)).font(Theme.number(.headline, weight: .bold))
                if let source { Text(SetFormat.short(source, loadMode: loadMode)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                if let e1RM { Text(Self.delta(e1RM - best)).font(.caption.weight(.semibold)).foregroundStyle(e1RM - best > 0.01 ? Theme.accent : .secondary) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Theme.row, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the weight and reps that beat it")
        .accessibilityIdentifier(title == "All-time best" ? "best-all-time" : "best-window")
    }

    static func kg(_ value: Double) -> String { "\(Load.format((value * 10).rounded() / 10)) kg" }

    /// "2.1 kg above" or "48.7 kg below"; a word as well as a colour (DESIGN.md).
    static func delta(_ d: Double) -> String {
        abs(d) <= 0.01 ? "level with it" : "\(Load.format((abs(d) * 10).rounded() / 10)) kg \(d > 0 ? "above" : "below")"
    }
}

/// Card 7.3: the lightest load for each rep count that beats the best.
struct BeatBestSheet: View {
    let exerciseName: String
    var title = "Best"
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
                    Text("\(title): est. 1RM \(Load.format((bestInUnit * 10).rounded() / 10)) \(unit.rawValue)")
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
