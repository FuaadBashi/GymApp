import Foundation
import GRDB

/// Card 6.3: reads `GymApp-suggestions.json` from the chosen backup folder, where GymApp Studio
/// publishes it, and writes the decisions back beside it. The app's own Documents folder is
/// read too, so a file copied over the cable works without iCloud.
@MainActor
@Observable
final class StudioInbox {
    static let shared = StudioInbox()
    private(set) var suggestions: [StudioSuggestion] = []
    private(set) var pending: [StudioSuggestion] = []
    /// Card 7.9: the studio's weekly and monthly reports.
    private(set) var reports: [StudioReport] = []
    private(set) var lastError: String?

    func reload(_ db: AppDatabase) async {
        let recovery = db.recovery
        let found = await Task.detached { Self.readAll(recovery) }.value
        reports = await Task.detached { Self.readReports(recovery) }.value
        suggestions = found.suggestions
        lastError = found.error
        pending = (try? await db.reader.read { [found] in try StudioSuggestions.pending($0, found.suggestions) }) ?? []
    }

    func accept(_ s: StudioSuggestion, db: AppDatabase) async throws {
        try await db.writer.write { try StudioSuggestions.accept($0, s, now: .now) }
        await finishDecision(db)
    }

    func dismiss(_ s: StudioSuggestion, db: AppDatabase) async throws {
        try await db.writer.write { try StudioSuggestions.dismiss($0, s, now: .now) }
        await finishDecision(db)
    }

    private func finishDecision(_ db: AppDatabase) async {
        pending = (try? await db.reader.read { [suggestions] in try StudioSuggestions.pending($0, suggestions) }) ?? []
        guard let data = try? await db.reader.read({ try StudioSuggestions.decisionsJSON($0) }) else { return }
        let recovery = db.recovery
        await Task.detached { Self.writeDecisions(data, recovery) }.value
    }

    private nonisolated static var documents: URL { URL.documentsDirectory }

    private nonisolated static func readAll(_ recovery: RecoveryStore?) -> (suggestions: [StudioSuggestion], error: String?) {
        var all: [StudioSuggestion] = []
        var failure: String?
        func read(_ folder: URL) {
            let url = folder.appending(path: StudioSuggestions.fileName)
            guard let data = coordinatedRead(url) else { return }
            do { all += try StudioSuggestions.parse(data) } catch { failure = "The studio's suggestions file could not be read." }
        }
        _ = try? recovery?.withExternalFolder { read($0) }
        read(documents)
        var byId: [String: StudioSuggestion] = [:]
        for s in all where byId[s.id].map({ $0.created < s.created }) ?? true { byId[s.id] = s }
        return (byId.values.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id < $1.id }, failure)
    }

    /// The newest-dated reports file wins between the backup folder and Documents.
    private nonisolated static func readReports(_ recovery: RecoveryStore?) -> [StudioReport] {
        var found: [[StudioReport]] = []
        _ = try? recovery?.withExternalFolder { folder in
            if let data = coordinatedRead(folder.appending(path: StudioReports.fileName)), let r = try? StudioReports.parse(data) { found.append(r) }
        }
        if let data = coordinatedRead(documents.appending(path: StudioReports.fileName)), let r = try? StudioReports.parse(data) { found.append(r) }
        return found.max { ($0.first?.from ?? "") < ($1.first?.from ?? "") } ?? []
    }

    /// File-provider folders (iCloud Drive) may hold a placeholder; coordinating the read
    /// downloads it first.
    private nonisolated static func coordinatedRead(_ url: URL) -> Data? {
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { data = try? Data(contentsOf: $0) }
        return data
    }

    private nonisolated static func writeDecisions(_ data: Data, _ recovery: RecoveryStore?) {
        let name = StudioSuggestions.decisionsFileName
        _ = try? recovery?.withExternalFolder { folder in
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: folder.appending(path: name), options: .forReplacing, error: &error) {
                try? data.write(to: $0, options: .atomic)
            }
        }
        try? data.write(to: documents.appending(path: name), options: .atomic)
    }
}
