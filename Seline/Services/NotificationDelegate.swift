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

        default:
            print("Unknown notification type: \(notificationType ?? "nil")")
        }
    }
}

// Notification names for navigation
extension Notification.Name {
    static let navigateToEmail = Notification.Name("navigateToEmail")
    static let navigateToTask = Notification.Name("navigateToTask")
}