import Foundation

/// Paths to test fixtures, built from this file's location so tests run from any directory.
nonisolated enum Fixtures {
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
    static let mini = folder.appending(path: "jefit_mini.csv")
    static let miniExpected = folder.appending(path: "jefit_mini_expected.json")
    static let realExpected = folder.appending(path: "jefit_expected.json")

    /// The real export lives in data/, outside git. Tests that need it skip without it.
    static let realExport = folder.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "data/jefit/jefit-export-2026-10-11.csv")
    static var hasRealExport: Bool { FileManager.default.fileExists(atPath: realExport.path) }
}
