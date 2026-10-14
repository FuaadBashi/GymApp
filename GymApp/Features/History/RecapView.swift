import Charts
import GRDB
import SwiftUI

/// Card 6.6: years since 2022, each a "Year in training" page with its months.
struct RecapsView: View {
    let db: AppDatabase
    @State private var years: [Int] = []
    @State private var thisMonth: Date = .now

    var body: some View {
        List {
            Section {
                NavigationLink("This month") { RecapView(db: db, kind: .month(thisMonth)) }
                NavigationLink("Last month") {
                    RecapView(db: db, kind: .month(Calendar.current.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth))
                }
            }
            Section("Year in training") {
                if years.isEmpty { Text("No workouts since \(String(RecapQueries.firstYear)) yet.").foregroundStyle(.secondary) }
                ForEach(years, id: \.self) { year in
                    NavigationLink(String(year)) { RecapView(db: db, kind: .year(year)) }
                }
            }
        }
        .navigationTitle("Recaps")
        .task { years = (try? await db.reader.read { try RecapQueries.years($0) }) ?? [] }
    }
}

struct RecapView: View {
    enum Kind: Hashable { case year(Int), month(Date) }
    let db: AppDatabase
    let kind: Kind
    @State private var recap: Recap?

    private var title: String {
        switch kind {
        case .year(let y): "\(String(y)) in training"
        case .month(let d): d.formatted(.dateTime.month(.wide).year())
        }
    }

    var body: some View {
        ScrollView {
            if let r = recap {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        tile("Workouts", "\(r.workouts)")
                        tile("Time", Self.hours(r.seconds))
                        tile("Volume", "\(Load.format((r.volumeKg / 1000 * 10).rounded() / 10)) t")
                        tile("Sets", r.sets.formatted())
                        tile("Records", "\(r.records)")
                        tile("Longest streak", "\(r.longestStreakWeeks) wk")
                    }
                    if let muscle = r.topMuscle {
                        tile("Most trained", "\(muscle.displayName) · \(Load.format(r.topMuscleSets.rounded())) sets")
                    }
                    if !r.months.isEmpty { months(r) }
                }
                .padding(16)
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Theme.background)
        .navigationTitle(title)
        .task { await load() }
    }

    private func months(_ r: Recap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BY MONTH").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Chart(r.months) { m in
                BarMark(x: .value("Month", m.start, unit: .month), y: .value("Workouts", m.workouts))
                    .foregroundStyle(Theme.accent)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
            .frame(height: 120)
            ForEach(r.months.filter { $0.workouts > 0 }) { m in
                NavigationLink {
                    RecapView(db: db, kind: .month(m.start))
                } label: {
                    HStack {
                        Text(m.start.formatted(.dateTime.month(.wide))).font(.subheadline)
                        Spacer()
                        Text("\(m.workouts) workouts · \(Load.format(m.volumeKg.rounded())) kg")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(Theme.number(.title3)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    static func hours(_ seconds: TimeInterval) -> String {
        let h = Int(seconds / 3600), m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    private func load() async {
        let kind = kind
        recap = try? await db.reader.read { db in
            let settings = try AppSettings.load(db)
            switch kind {
            case .year(let y): return try RecapQueries.year(db, y, weekStartsOn: settings.weekStartsOn)
            case .month(let d): return try RecapQueries.month(db, containing: d, weekStartsOn: settings.weekStartsOn)
            }
        }
    }
}
