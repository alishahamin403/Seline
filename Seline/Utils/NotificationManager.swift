//
//  NotificationManager.swift
//  Seline
//
//  Created to enable email notifications for quick access categories
//

import Foundation
import UserNotifications
import UIKit

/// Manages local notifications for new emails in quick access categories
class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let userDefaults = UserDefaults.standard

    // Notification settings keys
    private let notificationsEnabledKey = "notificationsEnabled"
    private let importantEmailsEnabledKey = "importantEmailsNotifications"
    private let promotionalEmailsEnabledKey = "promotionalEmailsNotifications"
    

    private override init() {
        super.init()
        notificationCenter.delegate = self
        setupDefaultSettings()
    }

    // MARK: - Permission Management

    /// Request notification permissions from user
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await notificationCenter.requestAuthorization(options: options)

            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            ProductionLogger.logAuthEvent("Notification permissions \(granted ? "granted" : "denied")")
            return granted
        } catch {
            ProductionLogger.logError(error as NSError, context: "Failed to request notification permissions")
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.notificationSettings().authorizationStatus
    }

    // MARK: - Settings Management

    var notificationsEnabled: Bool {
        get { userDefaults.bool(forKey: notificationsEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: notificationsEnabledKey)
            ProductionLogger.logCoreDataEvent("Notifications \(newValue ? "enabled" : "disabled")")
        }
    }

    var importantEmailsEnabled: Bool {
        get { userDefaults.bool(forKey: importantEmailsEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: importantEmailsEnabledKey)
            ProductionLogger.logCoreDataEvent("Important email notifications \(newValue ? "enabled" : "disabled")")
        }
    }

    var promotionalEmailsEnabled: Bool {
        get { userDefaults.bool(forKey: promotionalEmailsEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: promotionalEmailsEnabledKey)
            ProductionLogger.logCoreDataEvent("Promotional email notifications \(newValue ? "enabled" : "disabled")")
        }
    }

    

    private func setupDefaultSettings() {
        // Enable all notifications by default (user can disable in settings)
        if userDefaults.object(forKey: notificationsEnabledKey) == nil {
            notificationsEnabled = true
        }
        if userDefaults.object(forKey: importantEmailsEnabledKey) == nil {
            importantEmailsEnabled = true
        }
        if userDefaults.object(forKey: promotionalEmailsEnabledKey) == nil {
            promotionalEmailsEnabled = true
        }
        
    }

    // MARK: - Notification Scheduling

    /// Notify about new unread emails (general)
    func notifyNewEmails(_ emails: [Email]) {
        guard notificationsEnabled && !emails.isEmpty else { return }

        scheduleIndividualEmailNotifications(for: emails)
    }

    /// Schedule individual notifications for a list of emails
    func scheduleIndividualEmailNotifications(for emails: [Email]) {
        guard notificationsEnabled && !emails.isEmpty else { return }

        for email in emails {
            // Ensure we haven't already sent a notification for this email
            guard !NotifiedEmailTracker.shared.hasBeenNotified(id: email.id) else {
                continue
            }

            let title = "New from \(email.sender.displayName)"
            let body = email.subject
            let identifier = "email_\(email.id)"

            scheduleNotification(
                identifier: identifier,
                title: title,
body: body,
                category: .generalEmails
            )

            // Track that this email has been notified
            NotifiedEmailTracker.shared.addNotifiedEmail(id: email.id)
        }

        ProductionLogger.logCoreDataEvent("Scheduled individual notifications for \(emails.count) new emails")
    }
    
    func scheduleTodoNotification(for todo: TodoItem) {
        guard notificationsEnabled, let reminderDate = todo.reminderDate else { return }
        
        let title = "Todo Reminder"
        let body = todo.title
        
        scheduleNotification(
            identifier: "todo_\(todo.id)",
            title: title,
            body: body,
            category: .generalEmails,
            scheduleDate: reminderDate
        )
    }
    
    

    private func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        category: EmailNotificationCategory,
        scheduleDate: Date? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        content.categoryIdentifier = category.rawValue

        // Add custom data
        content.userInfo = [
            "notificationType": category.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        let trigger: UNNotificationTrigger
        if let scheduleDate = scheduleDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduleDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        notificationCenter.add(request) { error in
            if let error = error {
                ProductionLogger.logError(error as NSError, context: "Failed to schedule notification")
            }
        }
    }

    func cancelNotification(identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelTodoNotification(for todo: TodoItem) {
        cancelNotification(identifier: "todo_\(todo.id)")
    }

    

    // MARK: - Category Management

    func setupNotificationCategories() {
        let importantAction = UNNotificationAction(
            identifier: "mark_important_read",
            title: "Mark as Read",
            options: .foreground
        )

        let viewAction = UNNotificationAction(
            identifier: "view_email",
            title: "View",
            options: .foreground
        )

        let importantCategory = UNNotificationCategory(
            identifier: EmailNotificationCategory.importantEmails.rawValue,
            actions: [importantAction, viewAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let promotionalCategory = UNNotificationCategory(
            identifier: EmailNotificationCategory.promotionalEmails.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        

        let generalCategory = UNNotificationCategory(
            identifier: EmailNotificationCategory.generalEmails.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        notificationCenter.setNotificationCategories([
            importantCategory,
            promotionalCategory,
            
            generalCategory
        ])
    }

    // MARK: - Badge Management

    func updateBadgeCount() {
        Task {
            let unreadCount = await getTotalUnreadCount()
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = unreadCount
            }
        }
    }

    private func getTotalUnreadCount() async -> Int {
        // This would typically query Core Data for unread count
        // For now, return a placeholder
        return 0
    }

    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

// MARK: - Notification Categories

enum EmailNotificationCategory: String {
    case importantEmails = "important_emails"
    case promotionalEmails = "promotional_emails"
    
    case generalEmails = "general_emails"
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let _ = response.notification.request.content.userInfo // Could be used for additional context

        // Handle notification actions
        switch response.actionIdentifier {
        case "mark_important_read":
            // Handle marking important email as read
            ProductionLogger.logCoreDataEvent("User tapped 'Mark as Read' from notification")
        case "view_email":
            // Handle viewing email
            ProductionLogger.logCoreDataEvent("User tapped 'View' from notification")
        case UNNotificationDefaultActionIdentifier:
            // Handle default tap
            ProductionLogger.logCoreDataEvent("User tapped notification")
        default:
            break
        }

        completionHandler()
    }
}
