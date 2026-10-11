import Foundation
import GRDB

nonisolated enum LibrarySeeder {
    /// Inserts the bundled library. Existing ids are left alone, so seeding at every launch
    /// is harmless and never overwrites anything. Returns the number of rows inserted.
    @discardableResult
    static func seed(in db: Database, bundle: Bundle = .main, now: Date) throws -> Int {
        var inserted = 0
        for entry in try BundledExercises.library(bundle: bundle) {
            let record = ExerciseRecord(
                id: entry.id, name: entry.name, equipment: entry.equipment, loadMode: entry.loadMode,
                primaryMuscles: entry.primaryMuscles, secondaryMuscles: entry.secondaryMuscles,
                force: entry.force, mechanic: entry.mechanic, category: entry.category,
                bodyRegion: entry.bodyRegion, movementPattern: entry.movementPattern,
                instructions: entry.instructions, source: .library, libraryId: nil, stickyNote: nil,
                defaultRestSeconds: 60, preferredUnit: .kg, isFavorite: false, isArchived: false, createdAt: now)
            try record.insert(db, onConflict: .ignore)
            inserted += db.changesCount
        }
        return inserted
    }
}
