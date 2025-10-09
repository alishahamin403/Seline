import Foundation
@preconcurrency import UserNotifications
import UIKit

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task {
            await checkAuthorizationStatus()
            configurePushNotificationCategories()
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("Error requesting notification authorization: \(error)")
            return false
        }
    }

    func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }

    // MARK: - Email Notifications

    func scheduleNewEmailNotification(emailCount: Int, latestSender: String?, latestSubject: String?, latestEmailId: String?) async {
        // Check if we have authorization
        guard isAuthorized else {
            print("Notification authorization not granted")
            return
        }

        let content = UNMutableNotificationContent()

        if emailCount == 1 {
            content.title = "New Email"
            if let sender = latestSender, let subject = latestSubject, !subject.isEmpty {
                content.body = "\(sender): \(subject)"
            } else if let sender = latestSender {
                content.body = sender
            } else {
                content.body = "You have a new email"
            }
        } else {
            content.title = "New Emails (\(emailCount))"
            if let sender = latestSender, let subject = latestSubject, !subject.isEmpty {
                content.body = "\(sender): \(subject)"
            } else if let sender = latestSender {
                content.body = sender
            } else {
                content.body = "You have \(emailCount) new emails"
            }
        }

        content.sound = .default
        content.badge = NSNumber(value: emailCount)
        content.categoryIdentifier = "email"

        // Add action buttons and email ID for deep linking
        var userInfo: [String: Any] = ["type": "new_email", "count": emailCount]
        if let emailId = latestEmailId {
            userInfo["emailId"] = emailId
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "new-email-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Show immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📧 Scheduled notification for \(emailCount) new emails")
        } catch {
            print("Failed to schedule email notification: \(error)")
        }
    }

    func configurePushNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "open",
            title: "Open Email",
            options: [.foreground]
        )

        let markReadAction = UNNotificationAction(
            identifier: "mark_read",
            title: "Mark as Read",
            options: []
        )

        let emailCategory = UNNotificationCategory(
            identifier: "email",
            actions: [openAction, markReadAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([emailCategory])
    }

    func updateAppBadge(count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }

    func clearEmailNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { [center] notifications in
            let emailNotificationIds = notifications
                .filter { $0.request.content.userInfo["type"] as? String == "new_email" }
                .map { $0.request.identifier }

            center.removeDeliveredNotifications(withIdentifiers: emailNotificationIds)
        }
    }

    // MARK: - Task Reminders

    func scheduleTaskReminder(taskId: String, title: String, body: String, scheduledTime: Date) async {
        // Check if we have authorization
        guard isAuthorized else {
            print("Notification authorization not granted")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Event Reminder"
        content.body = title  // Just show the event name
        content.sound = .default
        content.categoryIdentifier = "task_reminder"
        content.userInfo = ["type": "task_reminder", "taskId": taskId]

        // Create date components from the scheduled time
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduledTime
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "task-reminder-\(taskId)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("⏰ Scheduled reminder for '\(title)' at \(scheduledTime)")
        } catch {
            print("Failed to schedule task reminder: \(error)")
        }
    }

    func cancelTaskReminder(taskId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["task-reminder-\(taskId)"]
        )
    }
}