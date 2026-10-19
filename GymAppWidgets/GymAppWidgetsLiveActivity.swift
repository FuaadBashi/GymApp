import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct GymAppWidgetsLiveActivity: Widget {
    private let volt = Color(red: 199 / 255, green: 242 / 255, blue: 66 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.workoutTitle).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(context.state.exerciseName).font(.headline)
                    Spacer()
                    restStatus(context).font(.title.bold()).foregroundStyle(volt)
                }
                HStack {
                    Text(context.state.nextSetText).font(.caption)
                    Spacer(minLength: 8)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.state.exerciseName).font(.headline)
                            Text(context.state.nextSetText).font(.caption)
                        }
                        Spacer(minLength: 8)
                        logButton(context)
                    }
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "checkmark.circle" : "timer").foregroundStyle(volt)
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
                    restStatus(context).foregroundStyle(volt).font(.caption2)
                }
            }
            .keylineTint(volt)
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
