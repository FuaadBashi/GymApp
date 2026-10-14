import SwiftUI

/// Card 7.9: the studio's weekly and monthly reports, under Progress.
struct ReportsView: View {
    let db: AppDatabase
    @State private var inbox = StudioInbox.shared

    var body: some View {
        List {
            if inbox.reports.isEmpty {
                Text("No reports yet. GymApp Studio writes them to your backup folder each week and month.")
                    .foregroundStyle(.secondary)
            }
            ForEach([StudioReport.Kind.week, .month], id: \.self) { kind in
                let list = inbox.reports.filter { $0.kind == kind }
                if !list.isEmpty {
                    Section(kind == .week ? "Weeks" : "Months") {
                        ForEach(list) { report in
                            NavigationLink { ReportDetailView(report: report) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(report.title).font(.headline)
                                    Text(report.headline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Reports")
        .refreshable { await inbox.reload(db) }
        .task { await inbox.reload(db) }
    }
}

struct ReportDetailView: View {
    let report: StudioReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(report.headline).font(.title3.weight(.semibold))
                ForEach(report.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
