import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct GymAppWidgetsLiveActivity: Widget {
    private let volt = Color(red: 199 / 255, green: 242 / 255, blue: 66 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    ring(context).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutTitle).font(.caption).foregroundStyle(.secondary)
                        Text(context.state.exerciseName).font(.headline).lineLimit(1)
                    }
                    Spacer()
                    restStatus(context).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(volt)
                }
                HStack(spacing: 8) {
                    Text(context.state.nextSetText).font(.caption).lineLimit(2)
                    Spacer(minLength: 4)
                    if !context.isStale { restButtons }
                    logButton(context)
                }
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(volt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Rest over" : "Rest", systemImage: context.isStale ? "checkmark.circle" : "timer").foregroundStyle(volt)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    restStatus(context).foregroundStyle(volt)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.exerciseName).font(.headline)
                        Text(context.state.nextSetText).font(.caption)
                        HStack(spacing: 8) {
                            if !context.isStale { restButtons }
                            Spacer(minLength: 4)
                            logButton(context)
                        }
                    }
                }
            } compactLeading: {
                if context.isStale {
                    Image(systemName: "checkmark.circle").foregroundStyle(volt)
                } else {
                    ring(context).frame(width: 18, height: 18)
                }
            } compactTrailing: {
                if context.isStale {
                    Text("Ready").foregroundStyle(volt)
                } else {
                    restStatus(context).foregroundStyle(volt).frame(width: 48)
                }
            } minimal: {
                if context.isStale {
                    Image(systemName: "checkmark.circle").foregroundStyle(volt)
                } else {
                    ring(context)
                }
            }
            .keylineTint(volt)
        }
    }

    /// Rulebook §20: a ring that empties as the rest runs down (none for older activities).
    @ViewBuilder
    private func ring(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        if let start = context.state.restStartedAt, start < context.state.restEndsAt, !context.isStale {
            ProgressView(timerInterval: start...context.state.restEndsAt, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(volt)
        } else {
            Image(systemName: context.isStale ? "checkmark.circle" : "timer").foregroundStyle(volt)
        }
    }

    private var restButtons: some View {
        HStack(spacing: 6) {
            Button(intent: AdjustRestIntent(seconds: 30)) { Text("+30s").font(.subheadline.bold()) }
                .tint(.white.opacity(0.2)).foregroundStyle(.white)
            Button(intent: SkipRestIntent()) { Text("Skip").font(.subheadline.bold()) }
                .tint(.white.opacity(0.2)).foregroundStyle(.white)
        }
    }

    /// Logs the announced set without opening the app.
    @ViewBuilder
    private func logButton(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        if let id = context.state.nextSetId {
            Button(intent: LogSetIntent(setId: id)) {
                Label("Log", systemImage: "checkmark").font(.subheadline.bold())
            }
            .tint(volt)
            .foregroundStyle(.black)
        }
    }

    // iOS changes isStale at the rest deadline even while GymApp is suspended.
    @ViewBuilder
    private func restStatus(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        if context.isStale {
            Text("Rest over")
        } else {
            Text(timerInterval: min(Date.now, context.state.restEndsAt)...context.state.restEndsAt,
                 countsDown: true)
                .monospacedDigit()
        }
    }
}
