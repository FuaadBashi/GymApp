import Foundation
import GRDB
import Testing
@testable import GymApp

/// Proves the scaffolding works: the test target links, GRDB is importable, and app code is
/// reachable through @testable import. Keep this file; it is the first thing to check when
/// the project stops building.
struct SmokeTests {
    @Test func grdbOpensAnInMemoryDatabase() throws {
        let queue = try DatabaseQueue()
        let one = try queue.read { try Int.fetchOne($0, sql: "SELECT 1") }
        #expect(one == 1)
    }

    @Test func epleyGivesJEFITsFigureForFiftyKilosTimesTen() {
        // JEFIT's own history screen shows 66.67 for 50 kg × 10 (JEFIT_EXPORT.md).
        #expect(abs(TrainingMath.e1RM(kg: 50, reps: 10) - 66.6667) < 0.001)
    }
}
