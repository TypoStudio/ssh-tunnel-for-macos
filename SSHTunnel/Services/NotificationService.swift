import Foundation
import UserNotifications

enum NotificationService {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyConnected(name: String) {
        send(
            title: String(localized: "Tunnel Connected"),
            body: displayBody(name: name, fallback: String(localized: "Connection established."))
        )
    }

    static func notifyFailed(name: String, reason: String) {
        let label = name.isEmpty ? reason : "\(name): \(reason)"
        send(title: String(localized: "Tunnel Failed"), body: label)
    }

    static func notifyDisconnected(name: String) {
        send(
            title: String(localized: "Tunnel Disconnected"),
            body: displayBody(name: name, fallback: String(localized: "Connection closed."))
        )
    }

    private static func displayBody(name: String, fallback: String) -> String {
        name.isEmpty ? fallback : name
    }

    private static func send(title: String, body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
