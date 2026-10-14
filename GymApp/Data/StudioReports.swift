import Foundation

/// Card 7.9: weekly and monthly reports written by GymApp Studio (card 8.1) as
/// `GymApp-reports.json` in the backup folder: a JSON list of reports, newest first.
nonisolated struct StudioReport: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case week, month }
    nonisolated struct Section: Codable, Equatable, Sendable {
        var title: String
        var lines: [String]
    }
    var id: String            // "2026-W42" or "2026-10"
    var kind: Kind
    var title: String         // "Week of 12 Oct 2026"
    var from: String          // yyyy-MM-dd, inclusive
    var to: String            // yyyy-MM-dd, exclusive
    var headline: String      // one line for the list
    var sections: [Section]
}

nonisolated enum StudioReports {
    static let fileName = "GymApp-reports.json"

    /// Reports the app can't read are skipped, not fatal; a later duplicate id wins.
    static func parse(_ data: Data) throws -> [StudioReport] {
        struct Lenient: Decodable {
            var value: StudioReport?
            init(from decoder: Decoder) throws { value = try? StudioReport(from: decoder) }
        }
        let items = try JSONDecoder().decode([Lenient].self, from: data).compactMap(\.value)
            .filter { !$0.id.isEmpty && !$0.sections.isEmpty }
        var byId: [String: StudioReport] = [:]
        for item in items { byId[item.id] = item }
        return byId.values.sorted { $0.from != $1.from ? $0.from > $1.from : $0.kind.rawValue > $1.kind.rawValue }
    }
}
