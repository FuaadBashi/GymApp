import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (and Action button) control: one tap starts the next training day.
struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fuaadshurie.GymApp.startWorkout") {
            ControlWidgetButton(action: StartNextWorkoutIntent()) {
                Label("Start workout", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .displayName("Start workout")
        .description("Starts your next training day.")
    }
}

private struct StartEntry: TimelineEntry { let date: Date }

private struct StartProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartEntry { StartEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StartEntry) -> Void) { completion(StartEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StartEntry>) -> Void) {
        completion(Timeline(entries: [StartEntry(date: .now)], policy: .never))
    }
}

/// Lock-screen widget: tap to open Bashi Gym on the next workout.
struct StartWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.fuaadshurie.GymApp.startWidget", provider: StartProvider()) { _ in
            StartWorkoutWidgetView()
        }
        .configurationDisplayName("Start workout")
        .description("Opens your next training day.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct StartWorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "figure.strengthtraining.traditional").font(.title2)
                }
            } else {
                Label("Start workout", systemImage: "figure.strengthtraining.traditional").font(.headline)
            }
        }
        .widgetURL(URL(string: "bashigym://start"))
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel("Start workout")
    }
}
