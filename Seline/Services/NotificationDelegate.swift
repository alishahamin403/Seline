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

        switch response.actionIdentifier {
        case "open":
            // Navigate to email view
            NotificationCenter.default.post(name: .navigateToEmail, object: nil, userInfo: userInfo)

        case "mark_read":
            // Mark emails as read (this would require additional implementation)
            print("Mark as read action tapped")

        case UNNotificationDefaultActionIdentifier:
            // Default tap - navigate to email view
            NotificationCenter.default.post(name: .navigateToEmail, object: nil, userInfo: userInfo)

        default:
            break
        }

        completionHandler()
    }
}

// Notification name for navigation
extension Notification.Name {
    static let navigateToEmail = Notification.Name("navigateToEmail")
}