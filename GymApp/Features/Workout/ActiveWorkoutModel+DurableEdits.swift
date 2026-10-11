import Foundation
import GRDB

extension ActiveWorkoutModel {
    /// Retain the entered numbers/type if the database can't accept the edit yet.
    func updateDurably(_ setId: String, edit: SetEdit) async {
        let draft = MetadataDraft(kind: .values, id: setId, note: "", edit: edit)
        do {
            try draft.persist()
            try await db.writer.write { try draft.apply($0) }
            try draft.clearIfCurrent()
            await refresh()
        } catch {
            lastError = "Your edit could not be saved. A recovery draft is retained when storage permits: " + error.localizedDescription
        }
    }
}
