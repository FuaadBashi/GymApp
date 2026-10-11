import GRDB
import SwiftUI

@Observable
final class ExercisesViewModel {
    let db: AppDatabase
    var filter = ExerciseFilter()
    private(set) var items: [ExerciseListItem] = []
    private(set) var loaded = false
    var lastError: String?

    init(db: AppDatabase) { self.db = db }

    func reload() async {
        let filter = filter
        do {
            items = try await db.reader.read { try ExerciseQueries.browse($0, filter: filter) }
            loaded = true
        } catch {
            lastError = error.localizedDescription
        }
    }
}
