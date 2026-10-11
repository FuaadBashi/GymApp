import SwiftUI
import UserNotifications

@main
struct GymAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkoutStore()
    @State private var database = AppStartup.openDatabase()

    var body: some Scene {
        WindowGroup {
            Group {
                switch database {
                case .success(let db):
                    HomeView()
                        .environment(store)
                        .environment(\.appDatabase, db)
                case .failure(let error):
                    DatabaseErrorView(error: error)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// With the app open, the rest alert still needs its sound: the phone may be on the
    /// bench across the room.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum Theme {
    static let rest = Color(red: 0.29, green: 0.68, blue: 0.42)
    static let logged = Color(red: 0.36, green: 0.82, blue: 0.47)
    static let note = Color(red: 0.98, green: 0.83, blue: 0.38)
    static let card = Color(white: 0.11)
    static let row = Color(white: 0.16)
}
