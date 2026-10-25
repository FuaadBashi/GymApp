import Charts
import SwiftUI

/// An exercise's progress chart and its records (card 3.4). Figures come from ExerciseStats.
struct ExerciseProgressView: View {
    let db: AppDatabase
    let points: [SessionPoint]
    let records: ExerciseRecords
    let loadMode: LoadMode
    var sessions: [ExerciseSession] = []
    var exercise: ExerciseRecord? = nil
    @State private var metric = Metric.e1RM
    @State private var range = Range.all
    @State private var selectedId: String?

    enum Metric: String, CaseIterable { case e1RM = "Est. 1RM", heaviest = "Heaviest", volume = "Volume" }
    enum Range: String, CaseIterable { case quarter = "3M", year = "1Y", all = "All" }

    private var hasLoadRecords: Bool { loadMode != .bodyweightPlus && loadMode != .repsOnly }
    private var metrics: [Metric] { hasLoadRecords ? Metric.allCases : [.volume] }

    private var shown: [(date: Date, value: Double, workoutId: String)] {
        let cutoff: Date? = switch range {
        case .quarter: Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
        case .all: nil
        }
        return points.filter { cutoff == nil || $0.date >= cutoff! }.compactMap { p in
            let value: Double? = switch metric {
            case .e1RM: p.bestE1RM
            case .heaviest: p.heaviestKg
            case .volume: p.volumeKg > 0 ? p.volumeKg : nil
            }
            return value.map { (p.date, $0, p.workoutId) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if points.isEmpty {
                Text("No finished sessions yet. Progress appears after the first one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                hero
                chart
                if let exercise, hasLoadRecords { GoalStandardsView(db: db, exercise: exercise, points: points) }
                recordsList
            }
        }
        .onAppear { if !hasLoadRecords { metric = .volume } }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            if metrics.count > 1 {
                Picker("Metric", selection: $metric) {
                    ForEach(metrics, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Picker("Range", selection: $range) {
                ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            let data = shown
            if data.isEmpty {
                Text("No sessions in this range.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let selected = data.first { $0.workoutId == selectedId }
                let peak = metric == .volume ? nil : data.map(\.value).max()
                let dots = setDots
                Chart {
                    ForEach(dots, id: \.id) { d in
                        PointMark(x: .value("Date", d.date), y: .value(metric.rawValue, d.e1RM))
                            .foregroundStyle(.secondary.opacity(0.35)).symbolSize(12)
                    }
                    ForEach(data, id: \.workoutId) { p in
                    if let peak, p.workoutId == data.first?.workoutId {
                        // §15: the best in this range, so a comeback reads as a climb back to it.
                        RuleMark(y: .value("Best", peak))
                            .foregroundStyle(Theme.accent.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Best \(Load.format((peak * 10).rounded() / 10)) kg").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                    LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(data.count > 60 ? 10 : 30)
                    if let selected, selected.workoutId == p.workoutId {
                        RuleMark(x: .value("Date", p.date)).foregroundStyle(.secondary.opacity(0.5))
                        PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                            .foregroundStyle(.white).symbolSize(110)
                            // Card 9.4: the tapped point lifts with its value.
                            .annotation(position: .top, spacing: 6) {
                                Text("\(Load.format((p.value * 10).rounded() / 10)) kg")
                                    .font(Theme.number(.caption, weight: .bold))
                                    .padding(.horizontal, Tokens.Space.s).padding(.vertical, Tokens.Space.xs)
                                    .background(Theme.raised, in: Capsule())
                            }
                    }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("kg")
                .chartOverlay { proxy in
                    // A tap, not chartXSelection: inside a scroll view that needs a long press.
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(.rect)
                            .gesture(SpatialTapGesture().onEnded { tap in
                                guard let plot = proxy.plotFrame else { return }
                                let x = tap.location.x - geo[plot].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedId = ExerciseStats.nearest(data, to: date, at: \.date)?.workoutId
                                }
                            })
                    }
                }
                .animation(.snappy(duration: 0.25), value: selectedId)
                .onChange(of: metric) { selectedId = nil }
                .onChange(of: range) { selectedId = nil }
                .frame(height: 220)
                .drawIn()
                .accessibilityLabel("\(metric.rawValue) over time, \(data.count) sessions, latest \(Load.format((data.last!.value * 10).rounded() / 10)) kg")
                if let selected {
                    selectedSession(selected)
                } else {
                    Text("Tap the chart to see a session.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Card 6.4: the tapped session's date and sets, with a link to the workout.
    private func selectedSession(_ p: (date: Date, value: Double, workoutId: String)) -> some View {
        let sets = sessions.filter { $0.workout.id == p.workoutId }.flatMap(\.sets)
        return NavigationLink {
            WorkoutDetailView(db: db, workoutId: p.workoutId)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                        .font(.subheadline.weight(.semibold))
                    Text("\(metric.rawValue) \(Load.format((p.value * 10).rounded() / 10)) kg").font(.caption).foregroundStyle(.secondary)
                    if !sets.isEmpty {
                        Text(SetFormat.line(sets, loadMode: loadMode)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(Tokens.Space.s)
            .background(Theme.row, in: .rect(cornerRadius: Tokens.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Records").font(.headline)
            if let m = records.heaviest { row("Heaviest", "\(Load.format(m.valueKg)) kg × \(m.reps ?? 0)", m); Divider() }
            if let m = records.bestE1RM { row("Best est. 1RM", "\(Load.format((m.valueKg * 10).rounded() / 10)) kg", m); Divider() }
            if let m = records.bestVolume { row("Best session volume", "\(Load.format(m.valueKg.rounded())) kg", m) }
            if !hasLoadRecords {
                Text("Body-weight and reps-only exercises have no load records (rulebook §5).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !records.repRecords.isEmpty {
                DisclosureGroup("Rep records by load (\(records.repRecords.count))") {
                    ForEach(records.repRecords, id: \.valueKg) { m in
                        row("\(Load.format(m.valueKg)) kg", "\(m.reps ?? 0) reps", m)
                    }
                }
                .font(.subheadline)
                .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Card 10.6: the one dominant figure, the best estimated 1RM (or best volume), with the
    /// latest session beside it for context.
    /// Every working set's e1RM in the shown range: faint dots behind the line of session bests.
    private var setDots: [(id: String, date: Date, e1RM: Double)] {
        guard metric == .e1RM, let first = shown.first?.date else { return [] }
        return sessions.filter { $0.workout.startedAt >= first }.flatMap { s in
            s.sets.compactMap { set -> (String, Date, Double)? in
                guard set.type == .working || set.type == .failed, let load = set.loadHundredths,
                      let e = TrainingMath.displayableE1RM(kg: Load(hundredths: load, unit: set.unit).kg, reps: set.reps, loadMode: loadMode)
                else { return nil }
                return (set.id, s.workout.startedAt, e)
            }
        }
    }

    private var plateau: TrainingMath.Plateau? {
        TrainingMath.plateau(sessions.compactMap { s in
            TrainingMath.progressScore(SetFormat.pastSets(s.sets), loadMode: loadMode).map { (s.workout.startedAt, $0) }
        }, now: .now)
    }

    private var rebuild: TrainingMath.Rebuild? {
        TrainingMath.rebuild(points.compactMap { p in p.bestE1RM.map { (p.date, $0) } }, now: .now)
    }

    @ViewBuilder private var hero: some View {
        let best = hasLoadRecords ? records.bestE1RM : records.bestVolume
        let latest = hasLoadRecords ? points.last?.bestE1RM : points.last?.volumeKg
        if let best {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasLoadRecords ? "Best estimated 1RM" : "Best session volume").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Load.format((best.valueKg * 10).rounded() / 10))
                        .font(Theme.number(.largeTitle, weight: .bold))
                    Text("kg").font(.title3).foregroundStyle(.secondary)
                }
                Text(best.date.formatted(.dateTime.day().month(.abbreviated).year())
                     + (latest.map { " · latest \(Load.format(($0 * 10).rounded() / 10)) kg" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                if hasLoadRecords, let r = rebuild { RebuildBar(rebuild: r).padding(.top, Tokens.Space.xs) }
                if let p = plateau {
                    Label("Stalled: " + PlateauText.line(p, loadMode: loadMode), systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(Theme.note).padding(.top, Tokens.Space.xs)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ title: String, _ value: String, _ mark: ExerciseRecords.Mark) -> some View {
        NavigationLink {
            WorkoutDetailView(db: db, workoutId: mark.workoutId)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(mark.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
