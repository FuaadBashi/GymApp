import Charts
import SwiftUI

/// An exercise's progress chart and its records (card 3.4). Figures come from ExerciseStats.
struct ExerciseProgressView: View {
    let db: AppDatabase
    let points: [SessionPoint]
    let records: ExerciseRecords
    let loadMode: LoadMode
    @State private var metric = Metric.e1RM
    @State private var range = Range.all

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
                chart
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
                Chart(data, id: \.workoutId) { p in
                    LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(data.count > 60 ? 10 : 30)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("kg")
                .frame(height: 220)
                .accessibilityLabel("\(metric.rawValue) over time, \(data.count) sessions, latest \(Load.format((data.last!.value * 10).rounded() / 10)) kg")
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECORDS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if let m = records.heaviest { row("Heaviest", "\(Load.format(m.valueKg)) kg × \(m.reps ?? 0)", m) }
            if let m = records.bestE1RM { row("Best est. 1RM", "\(Load.format((m.valueKg * 10).rounded() / 10)) kg", m) }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
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
