import Foundation
import UserNotifications
import UIKit

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let notificationType = userInfo["type"] as? String

        switch response.actionIdentifier {
        case "open":
            // Handle specific notification type
            handleNotificationNavigation(userInfo: userInfo, notificationType: notificationType)

        case "mark_read":
            // Mark emails as read (this would require additional implementation)
            print("Mark as read action tapped")

        case UNNotificationDefaultActionIdentifier:
            // Default tap - navigate based on notification type
            handleNotificationNavigation(userInfo: userInfo, notificationType: notificationType)

        default:
            break
        }

        completionHandler()
    }

    private func handleNotificationNavigation(userInfo: [AnyHashable: Any], notificationType: String?) {
        switch notificationType {
        case "new_email":
            // Navigate to email view with specific email if available
            NotificationCenter.default.post(name: .navigateToEmail, object: nil, userInfo: userInfo)

        case "task_reminder":
            // Navigate to task view
            NotificationCenter.default.post(name: .navigateToTask, object: nil, userInfo: userInfo)

        case "top_story":
            // Open article URL in Chrome
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                openInChrome(url: url)
            } else {
                print("⚠️ Top story notification has no URL")
            }

        default:
            print("Unknown notification type: \(notificationType ?? "nil")")
        }
    }

    private func openInChrome(url: URL) {
        // Chrome URL scheme: googlechrome://[url without scheme]
        var chromURLString = url.absoluteString.replacingOccurrences(of: "http://", with: "")
        chromURLString = chromURLString.replacingOccurrences(of: "https://", with: "")

        guard let chromeURL = URL(string: "googlechrome://\(chromURLString)") else {
            // Fallback to default browser if Chrome URL fails
            print("⚠️ Could not create Chrome URL, using default browser")
            UIApplication.shared.open(url)
            return
        }

        // Check if Chrome is installed
        if UIApplication.shared.canOpenURL(chromeURL) {
            UIApplication.shared.open(chromeURL)
            print("📱 Opened article in Chrome: \(url.host ?? "Unknown")")
        } else {
            // Fallback to Safari/default browser if Chrome is not installed
            print("📱 Chrome not installed, opening in default browser")
            UIApplication.shared.open(url)
        }
    }
}

// Notification names for navigation
extension Notification.Name {
    static let navigateToEmail = Notification.Name("navigateToEmail")
    static let navigateToTask = Notification.Name("navigateToTask")
}