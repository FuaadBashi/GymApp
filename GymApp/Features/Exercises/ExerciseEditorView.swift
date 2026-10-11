import SwiftUI

// Card 1.5 replaces this.
struct ExerciseEditorView: View {
    let db: AppDatabase
    let editing: ExerciseRecord?
    var template: ExerciseRecord? = nil
    var onCreate: ((ExerciseRecord) -> Void)? = nil
    var body: some View { Text("Editor arrives in card 1.5") }
}
