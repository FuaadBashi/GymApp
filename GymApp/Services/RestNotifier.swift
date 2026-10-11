import Foundation
import UserNotifications

/// Rulebook §9: the end of rest is a local notification, so it sounds and vibrates with
/// the phone locked or another app in front. Local notifications need no paid entitlement.
struct RestNotifier {
    private let id = "rest-timer"
    private var center: UNUserNotificationCenter { .current() }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(at date: Date, body: String) {
        cancel()
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
