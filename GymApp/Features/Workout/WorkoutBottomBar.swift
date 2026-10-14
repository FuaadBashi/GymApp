import GRDB
import SwiftUI

/// Rest countdown while resting; otherwise the one big action for what comes next.
struct WorkoutBottomBar: View {
    @Environment(ActiveWorkoutModel.self) private var model
    @State private var bellShowing = false
    @State private var restEnded = 0

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let end = snapshot.workout.restEndsAt {
                resting(end: end, duration: snapshot.workout.restDurationSeconds ?? 0)
            } else {
                action
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Card 9.1: a floating control, so Liquid Glass; the content under it stays opaque.
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .sensoryFeedback(.warning, trigger: restEnded)
        .task(id: model.snapshot?.workout.restEndsAt) {
            guard let end = model.snapshot?.workout.restEndsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            restEnded += 1
            withAnimation { bellShowing = true }
            await model.restDidEnd()
            try? await Task.sleep(for: .seconds(4))
            withAnimation { bellShowing = false }
        }
    }

    private func resting(end: Date, duration: Double) -> some View {
        HStack(spacing: 14) {
            RestRing(end: end, duration: duration)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest").font(.headline)
                if let next = nextLine { Text(next).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            restButton("−15") { await model.adjustRest(by: -15) }
            restButton("+15") { await model.adjustRest(by: 15) }
            Button("Skip") { Task { await model.skipRest() } }
                .font(.subheadline.bold())
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(.plain)
        }
    }

    private func restButton(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .font(.subheadline.bold().monospacedDigit())
            .frame(width: 48, height: 40)
            .background(Theme.row, in: Capsule())
            .buttonStyle(.plain)
    }

    private var nextLine: String? {
        guard let item = model.currentItem, let set = item.sets.first(where: { $0.id == model.selectedSetId }) else { return nil }
        return "Next: \(item.exercise.name) · \(SetFormat.long(set, loadMode: item.exercise.loadMode))"
    }

    @ViewBuilder private var action: some View {
        if let item = model.currentItem, let set = item.sets.first(where: { $0.id == model.selectedSetId && $0.completedAt == nil }) {
            let number = SetComparison.labels(item.sets)[item.sets.firstIndex(of: set) ?? 0]
            HStack(spacing: 10) {
                if bellShowing {
                    // Card 9.3: rest is over.
                    Image(systemName: "bell.fill").font(.title3).foregroundStyle(Theme.accent)
                        .symbolEffect(.wiggle, options: .nonRepeating, value: restEnded)
                        .accessibilityLabel("Rest over")
                        .transition(.scale.combined(with: .opacity))
                }
                Button {
                    Task { await model.log(set.id) }
                } label: {
                    Text("Log set \(number) · \(SetFormat.long(set, loadMode: item.exercise.loadMode))").lineLimit(1)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } else if let next = model.snapshot?.items.first(where: { !$0.plannedSets.isEmpty }) {
            Button("Next: \(next.exercise.name)") { model.select(itemId: next.id) }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button("Finish workout") { Task { await model.finish() } }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

/// Remaining rest, recomputed from the stored end time, never by counting down (rulebook §9).
struct RestRing: View {
    let end: Date
    let duration: Double
    var size: CGFloat = 52

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, end.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(Theme.row, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: duration > 0 ? min(1, remaining / duration) : 0)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(RestRing.clock(remaining))
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded).monospacedDigit())
                    .rollingNumber(Int(remaining.rounded(.up)))
            }
        }
        .frame(width: size, height: size)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
