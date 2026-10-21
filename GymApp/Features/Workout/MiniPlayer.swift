import GRDB
import SwiftUI

/// The workout in progress, above the tab bar. Tapping it reopens the workout.
struct MiniPlayer: View {
    @Environment(ActiveWorkoutModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let snapshot = model.snapshot {
            HStack(spacing: 10) {
                clock(snapshot)
                VStack(alignment: .leading, spacing: 1) {
                    if placement != .inline {
                        Text(snapshot.workout.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(model.currentItem?.exercise.name ?? "All sets logged")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if placement != .inline, snapshot.workout.restEndsAt == nil, let setId = loggableSetId {
                    Button("Log") { Task { await model.log(setId) } }
                        .font(.caption.bold())
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, Tokens.Space.m).frame(height: 30)
                        .background(Theme.accent, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tokens.Space.m)
            .contentShape(.rect)
            .onTapGesture { model.isPresented = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the workout")
        }
    }

    private var loggableSetId: String? {
        guard let item = model.currentItem else { return nil }
        return item.sets.first { $0.id == model.selectedSetId && $0.completedAt == nil }?.id
    }

    @ViewBuilder private func clock(_ snapshot: WorkoutSnapshot) -> some View {
        if let end = snapshot.workout.restEndsAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(RestRing.clock(max(0, end.timeIntervalSince(context.date))))
                    .foregroundStyle(Theme.accent)
            }
            .font(.subheadline.bold().monospacedDigit())
        } else {
            Text(snapshot.workout.startedAt, style: .timer)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
