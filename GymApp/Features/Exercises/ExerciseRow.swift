import SwiftUI

struct ExerciseRow: View {
    let item: ExerciseListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.exercise.name).font(.headline).lineLimit(1)
                    if item.exercise.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 6) {
                    MuscleTags(muscles: Array(item.exercise.primaryMuscles.prefix(2)))
                    Text(item.exercise.equipment.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let last = item.lastDoneAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(last, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .foregroundStyle(.secondary)
                    if let best = SetFormat.best(item.lastSets, loadMode: item.exercise.loadMode) {
                        Text(SetFormat.short(best, loadMode: item.exercise.loadMode))
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
    }
}
