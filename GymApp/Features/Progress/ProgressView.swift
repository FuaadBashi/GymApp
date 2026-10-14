import Charts
import GRDB
import SwiftUI

@Observable
final class ProgressModel {
    let db: AppDatabase
    private(set) var weeks: [WeekTotals] = []
    private(set) var thisWeekMuscles: [(muscle: Muscle, sets: Double)] = []
    private(set) var lastWeekMuscles: [(muscle: Muscle, sets: Double)] = []
    private(set) var records: [RecentRecord] = []
    private(set) var weights: [(date: String, kg: Double)] = []
    private(set) var steps: StepsSummary?
    private(set) var recovery: [(muscle: Muscle, sets: Double)] = []
    private(set) var patterns: [PatternTrend] = []
    private(set) var settings = AppSettings()
    private(set) var loaded = false

    init(db: AppDatabase) { self.db = db }

    func reload() async {
        let now = Date.now
        guard let result = try? await db.reader.read({ db in
            let settings = try AppSettings.load(db)
            let start = HistoryQueries.weekStart(of: now, weekStartsOn: settings.weekStartsOn)
            let calendar = HistoryQueries.calendar(settings.weekStartsOn)
            let from = calendar.date(byAdding: .weekOfYear, value: -11, to: start) ?? start
            let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
            let items = try HistoryQueries.items(db, from: from)
            return (settings,
                    ProgressQueries.weeks(items, weekStartsOn: settings.weekStartsOn, now: now),
                    try ProgressQueries.muscles(db, from: start, to: .distantFuture),
                    try ProgressQueries.muscles(db, from: lastStart, to: start),
                    try ProgressQueries.recentRecords(db),
                    try ProgressQueries.bodyWeights(db),
                    try ProgressQueries.steps(db, now: now, weekStartsOn: settings.weekStartsOn),
                    try ProgressQueries.recovery(db, now: now),
                    try ProgressQueries.patterns(db, now: now, weekStartsOn: settings.weekStartsOn))
        }) else { return }
        (settings, weeks, thisWeekMuscles, lastWeekMuscles, records, weights, steps, recovery, patterns) = result
        loaded = true
    }

    func addWeight(_ value: Double, unit: WeightUnit) async {
        try? await db.writer.write { try ProgressQueries.addWeight($0, value: value, unit: unit, on: .now) }
        await reload()
    }
}

struct ProgressTab: View {
    @State private var model: ProgressModel
    @State private var lastWeek = false
    @State private var addingWeight = false
    @Environment(ActiveWorkoutModel.self) private var workout

    init(db: AppDatabase) { _model = State(initialValue: ProgressModel(db: db)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekly
                    muscles
                    recovery
                    patterns
                    recentRecords
                    bodyWeight
                    stepsCard
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ReportsView(db: model.db) } label: { Label("Reports", systemImage: "doc.text.magnifyingglass") }
                }
            }
            .navigationDestination(for: String.self) { WorkoutDetailView(db: model.db, workoutId: $0) }
            .sheet(isPresented: $addingWeight) {
                AddWeightSheet(unit: model.settings.weightUnit) { value, unit in Task { await model.addWeight(value, unit: unit) } }
            }
            .task { await model.reload() }
            .onAppear { Task { await model.reload() } }
            .onReceive(NotificationCenter.default.publisher(for: HealthService.didSync)) { _ in Task { await model.reload() } }
            .onChange(of: workout.justFinishedWorkoutId) { Task { await model.reload() } }
        }
    }

    // MARK: Weekly

    private var weekly: some View {
        card("Last 12 weeks") {
            bars("Volume", unit: "kg", value: \.volumeKg) { Load.format($0.rounded()) + " kg" }
            bars("Sessions", unit: "", value: { Double($0.sessions) }) { "\(Int($0))" }
            bars("Training time", unit: "min", value: { $0.seconds / 60 }) { "\(Int($0.rounded())) min" }
        }
    }

    private func bars(_ title: String, unit: String, value: @escaping (WeekTotals) -> Double, format: @escaping (Double) -> String) -> some View {
        let current = model.weeks.last.map(value) ?? 0
        let previous = model.weeks.dropLast().last.map(value) ?? 0
        let change: String = previous > 0 ? String(format: "%+.0f%%", (current - previous) / previous * 100) : "–"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(format(current)).font(.subheadline.monospacedDigit()).rollingNumber(current)
                Text("vs last week \(change)").font(.caption).foregroundStyle(.secondary)
            }
            Chart(model.weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value(title, value(w)))
                    .foregroundStyle(w.id == model.weeks.last?.id ? Theme.accent : Theme.accent.opacity(0.45))
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
            .frame(height: 90)
            .accessibilityLabel("\(title) per week, this week \(format(current))")
        }
    }

    // MARK: Muscles

    private var muscles: some View {
        let list = lastWeek ? model.lastWeekMuscles : model.thisWeekMuscles
        let sets = Dictionary(uniqueKeysWithValues: list.map { ($0.muscle, $0.sets) })
        return card("Muscles") {
            Picker("Week", selection: $lastWeek) {
                Text("This week").tag(false)
                Text("Last week").tag(true)
            }
            .pickerStyle(.segmented)
            BodyMapView(sets: sets).frame(height: 260)
            HStack(spacing: 8) {
                ForEach(SetBand.allCases, id: \.self) { band in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(band.color).frame(width: 10, height: 10)
                        Text(band.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if list.isEmpty {
                Text("No hard sets \(lastWeek ? "last" : "this") week yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(list, id: \.muscle) { m in
                HStack {
                    Text(m.muscle.displayName).font(.subheadline)
                    Spacer()
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.row)
                            // The 10–20 target band.
                            Rectangle().fill(Theme.accent.opacity(0.15))
                                .frame(width: w * 10 / 25).offset(x: w * 10 / 25)
                            Capsule().fill(SetBand(m.sets).color).frame(width: max(4, w * min(m.sets, 25) / 25))
                        }
                    }
                    .frame(width: 120, height: 8)
                    Text(Load.format(m.sets)).font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
            Text("Hard sets: 1 per primary muscle, ½ per secondary. Shaded band: 10–20 a week.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Recovery (card 6.5)

    private var recovery: some View {
        let sets = Dictionary(uniqueKeysWithValues: model.recovery.map { ($0.muscle, $0.sets) })
        return card("Recovery · last 72 hours") {
            BodyMapView(sets: sets) { RecoveryBand($0).color }.frame(height: 260)
            HStack(spacing: 8) {
                ForEach(RecoveryBand.allCases, id: \.self) { band in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(band.color).frame(width: 10, height: 10)
                        Text(band.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if model.recovery.isEmpty {
                Text("Every muscle is fresh: no hard sets in the last 72 hours.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.recovery, id: \.muscle) { m in
                HStack {
                    Text(m.muscle.displayName).font(.subheadline)
                    Spacer()
                    Text(RecoveryBand(m.sets).label).font(.caption).foregroundStyle(.secondary)
                    Text(Load.format((m.sets * 10).rounded() / 10)).font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
            Text("Hard sets weighted by time since: a set counts fully when done and nothing after 72 hours.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Movement patterns (card 6.5)

    private var patterns: some View {
        card("Movement patterns · 8 weeks") {
            if model.patterns.isEmpty {
                Text("Patterns appear once a squat, hinge, push or pull lift is trained.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.patterns) { trend in
                HStack(spacing: 12) {
                    Text(trend.pattern.displayName).font(.subheadline).frame(width: 120, alignment: .leading)
                    Chart(trend.weeks, id: \.start) { w in
                        LineMark(x: .value("Week", w.start), y: .value("Change", w.change * 100)).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Week", w.start), y: .value("Change", w.change * 100)).foregroundStyle(Theme.accent).symbolSize(12)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXScale(domain: (model.patterns.flatMap { $0.weeks.map(\.start) }.min() ?? .now)...(model.patterns.flatMap { $0.weeks.map(\.start) }.max() ?? .now))
                    .frame(height: 32)
                    Text(trend.weeks.last.map { String(format: "%+.1f%%", $0.change * 100) } ?? "–")
                        .font(.subheadline.monospacedDigit()).frame(width: 64, alignment: .trailing)
                }
            }
            Text("Each week's best estimated 1RM against the lift's first week in the window, averaged over the pattern's lifts.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Records

    private var recentRecords: some View {
        card("Recent records") {
            if model.records.isEmpty {
                Text("Records appear when a session beats every earlier one.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.records) { r in
                NavigationLink(value: r.workoutId) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "trophy.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(r.kind.rawValue) · \(r.date.formatted(.dateTime.day().month(.abbreviated).year()))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Load.format((r.valueKg * 10).rounded() / 10)) kg").font(.subheadline.monospacedDigit())
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Body weight

    private var bodyWeight: some View {
        card("Body weight") {
            let unit = model.settings.weightUnit
            let factor = unit == .kg ? 1 : 1 / WeightUnit.kgPerLb
            let points = model.weights.compactMap { w in DayString.date(w.date).map { ($0, w.kg * factor) } }
            if points.isEmpty {
                Text("No weights yet. Body-weight exercises need one for volume.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(points, id: \.0) { p in
                    LineMark(x: .value("Date", p.0), y: .value("Weight", p.1)).foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", p.0), y: .value("Weight", p.1)).foregroundStyle(Theme.accent).symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                if let last = points.last {
                    Text("Latest \(Load.format((last.1 * 10).rounded() / 10)) \(unit.rawValue)").font(.subheadline.monospacedDigit())
                }
            }
            Button("Add weight", systemImage: "plus") { addingWeight = true }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsCard: some View {
        if let steps = model.steps, !steps.days.isEmpty {
            card("Steps · last 30 days") {
                let points = steps.days.compactMap { d in DayString.date(d.day).map { ($0, d.steps) } }
                Chart(points, id: \.0) { p in
                    BarMark(x: .value("Day", p.0, unit: .day), y: .value("Steps", p.1))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
                }
                .frame(height: 110)
                HStack(alignment: .firstTextBaseline) {
                    if let avg = steps.dailyAverage {
                        Text("\(avg.formatted()) a day").font(.subheadline.monospacedDigit())
                    }
                    Spacer()
                    if let this = steps.thisWeek {
                        let change = steps.lastWeek.flatMap { $0 > 0 ? String(format: "%+.0f%%", Double(this - $0) / Double($0) * 100) : nil } ?? "–"
                        Text("This week \(this.formatted())/day · vs last \(change)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }
}

private struct AddWeightSheet: View {
    @State var unit: WeightUnit
    let onSave: (Double, WeightUnit) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight", text: $text).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                Text("Saved for today. A second entry today replaces the first.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Body weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let value { onSave(value, unit); dismiss() } }.disabled(value == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
