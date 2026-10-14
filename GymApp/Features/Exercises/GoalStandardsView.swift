import GRDB
import SwiftUI

/// Card 7.8: an exercise's goal with a projected date, and where it sits against gym lifters.
struct GoalStandardsView: View {
    let db: AppDatabase
    let exercise: ExerciseRecord
    let points: [SessionPoint]
    @State private var goal: Load?
    @State private var settings = AppSettings()
    @State private var bodyWeightKg: Double?
    @State private var editingGoal = false

    private var best: Double? { points.compactMap(\.bestE1RM).max() }
    /// The last 12 months of session bests, for the projection.
    private var recent: [(date: Date, value: Double)] {
        let from = Date.now.addingTimeInterval(-365 * 86_400)
        return points.filter { $0.date >= from }.compactMap { p in p.bestE1RM.map { (p.date, $0) } }
    }

    var body: some View {
        VStack(spacing: 14) {
            goalCard
            standardsCard
        }
        .task { await load() }
        .sheet(isPresented: $editingGoal) {
            GoalSheet(initial: goal, unit: settings.weightUnit) { new in
                let id = exercise.id
                Task {
                    try? await db.writer.write { try GoalQueries.setGoal($0, exerciseId: id, goal: new) }
                    goal = new
                }
            }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GOAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button(goal == nil ? "Set a goal" : "Change") { editingGoal = true }.font(.subheadline)
            }
            if let goal {
                let target = goal.kg
                Text("Est. 1RM \(BestHintLine.kg(target))").font(Theme.number(.title3, weight: .bold)).rollingNumber(target)
                if let best {
                    Text(best >= target ? "Reached: your best is \(BestHintLine.kg(best))" : "\(BestHintLine.kg(target - best)) to go from \(BestHintLine.kg(best))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(projectionText(target)).font(.subheadline)
                Text("From this lift's last 12 months, fitted to a curve that slows over time. A guide, not a promise.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Set a target estimated 1RM to see when your current rate would reach it.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private func projectionText(_ target: Double) -> String {
        let month = Date.FormatStyle.dateTime.month(.abbreviated).year()
        switch Projection.outcome(goal: target, points: recent) {
        case .notEnoughData: return "Not enough data yet: needs \(Projection.minimumSessions) sessions over 8 weeks in the last year."
        case .reached: return "Already reached."
        case .unreachable(let ceiling): return "Not reachable at the current rate: the curve levels off near \(BestHintLine.kg(ceiling))."
        case .projected(let date, let earliest, let latest):
            let range = latest.map { "between \(earliest.formatted(month)) and \($0.formatted(month))" } ?? "from \(earliest.formatted(month)), maybe later"
            return "Around \(date.formatted(month)), \(range)."
        }
    }

    @ViewBuilder private var standardsCard: some View {
        if let standards = StrengthStandards.bundled, let lift = standards.lift(for: exercise) {
            VStack(alignment: .leading, spacing: 8) {
                Text("STANDARDS · GYM LIFTERS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if settings.sex.isEmpty || bodyWeightKg == nil {
                    Text("Set your sex in Settings → Profile and log a body weight to compare this lift.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if let best, let bw = bodyWeightKg,
                          let p = standards.percentile(lift: lift, sex: settings.sex, bodyWeightKg: bw, e1RM: best) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(StrengthStandards.tier(p)).font(.title3.bold())
                        Spacer()
                        Text("stronger than \(Int(p.rounded()))%").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.accent)
                    }
                    ProgressView(value: p, total: 100).tint(Theme.accent)
                    Text("Best est. 1RM \(BestHintLine.kg(best)) at \(Load.format((bw * 10).rounded() / 10)) kg body weight, against \(standards.lifts[lift]?.label.lowercased() ?? lift) lifters of your sex and weight class. Self-reported gym lifts; not adjusted for age.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No estimated 1RM for this lift yet.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let url = URL(string: standards.url) {
                    Link(standards.attribution, destination: url).font(.caption2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
        }
    }

    private func load() async {
        let id = exercise.id
        let result = try? await db.reader.read { db in
            (try GoalQueries.goal(db, exerciseId: id), try AppSettings.load(db), try BodyQueries.weightKg(db, onOrBefore: .now))
        }
        if let result { (goal, settings, bodyWeightKg) = result }
    }
}

private struct GoalSheet: View {
    let initial: Load?
    @State var unit: WeightUnit
    let onSave: (Load?) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    init(initial: Load?, unit: WeightUnit, onSave: @escaping (Load?) -> Void) {
        self.initial = initial
        _unit = State(initialValue: initial?.unit ?? unit)
        self.onSave = onSave
        _text = State(initialValue: initial.map { Load.format(Double($0.hundredths) / 100) } ?? "")
    }

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Target estimated 1RM", text: $text).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                if initial != nil {
                    Button("Remove goal", role: .destructive) { onSave(nil); dismiss() }
                }
            }
            .themedList()
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value { onSave(Load(hundredths: Int((value * 100).rounded()), unit: unit)); dismiss() }
                    }
                    .disabled(value == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
