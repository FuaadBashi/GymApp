import Foundation
import UserNotifications

/// Decision #3: a free Apple ID signs the app for 7 days. The app reads its own expiry from
/// the embedded provisioning profile and warns two days ahead, so it never lapses unnoticed
/// before a gym session.
nonisolated enum SigningExpiry {
    static let notificationId = "signing-expiry"
    static let warningLead: TimeInterval = 2 * 86_400

    enum State: Equatable {
        case fine, expiringSoon(Date), expired(Date)
    }

    /// The profile is a CMS-signed plist: the dictionary sits between `<?xml` and `</plist>`.
    static func expirationDate(fromProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let dict = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else { return nil }
        return dict["ExpirationDate"] as? Date
    }

    /// The installed app's expiry; nil on the simulator, which has no profile.
    static func current(bundle: Bundle = .main, now: Date = .now) -> Date? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-signingExpiry"), i + 1 < args.count, let days = Double(args[i + 1]) {
            return now.addingTimeInterval(days * 86_400)
        }
        #endif
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(fromProfile: data)
    }

    static func warningStart(for expiry: Date) -> Date { expiry.addingTimeInterval(-warningLead) }

    static func state(expiry: Date?, now: Date) -> State {
        guard let expiry else { return .fine }
        if now >= expiry { return .expired(expiry) }
        if now >= warningStart(for: expiry) { return .expiringSoon(expiry) }
        return .fine
    }

    /// Rescheduled at every launch, so a reinstall moves it to the new expiry.
    static func scheduleReminder(expiry: Date?, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        guard let expiry else { return }
        let fire = warningStart(for: expiry)
        let interval = fire.timeIntervalSince(now)
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "GymApp expires in 2 days"
        content.body = "Reinstall from Xcode before \(expiry.formatted(.dateTime.weekday(.wide).hour().minute())) to keep training without interruption."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: notificationId, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }
}
