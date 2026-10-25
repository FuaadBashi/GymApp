import WidgetKit
import SwiftUI

@main
struct GymAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GymAppWidgetsLiveActivity()
        StartWorkoutControl()
        StartWorkoutWidget()
    }
}
