import SwiftUI
import UserNotifications

@main
struct GymAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var database = AppStartup.openDatabase()

    var body: some Scene {
        WindowGroup {
            Group {
                switch database {
                case .success(let db):
                    RootView(db: db)
                        .environment(\.appDatabase, db)
                case .failure(let error):
                    DatabaseErrorView(error: error)
                }
            }
            .tint(Theme.accent)
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
