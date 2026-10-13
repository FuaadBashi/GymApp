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

    /// Imported exercises take their library link from the bundled map, but an import never
    /// rewrites an exercise it already has. So when the map gains links, existing exercises
    /// get them here: only where the link is still empty, and only for JEFIT exercises, so a
    /// link set any other way is never overridden. Instructions come along when empty.
    @discardableResult
    static func linkImported(in db: Database, bundle: Bundle = .main) throws -> Int {
        var linked = 0
        for entry in try BundledExercises.jefitMap(bundle: bundle) {
            guard let libraryId = entry.libraryId else { continue }
            try db.execute(sql: """
                UPDATE exercise SET libraryId = ?,
                  instructions = CASE WHEN instructions = '[]'
                    THEN COALESCE((SELECT instructions FROM exercise WHERE id = ?), '[]') ELSE instructions END
                WHERE id = ? AND source = 'jefit' AND libraryId IS NULL
                  AND EXISTS (SELECT 1 FROM exercise WHERE id = ?)
                """, arguments: [libraryId, libraryId, entry.exerciseId, libraryId])
            linked += db.changesCount
        }
        return linked
    }
}
