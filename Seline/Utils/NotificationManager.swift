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
    private let calendarEmailsEnabledKey = "calendarEmailsNotifications"

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

    var calendarEmailsEnabled: Bool {
        get { userDefaults.bool(forKey: calendarEmailsEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: calendarEmailsEnabledKey)
            ProductionLogger.logCoreDataEvent("Calendar email notifications \(newValue ? "enabled" : "disabled")")
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
        if userDefaults.object(forKey: calendarEmailsEnabledKey) == nil {
            calendarEmailsEnabled = true
        }
    }

    // MARK: - Email Notification Triggers

    /// Notify about new important emails
    func notifyNewImportantEmails(_ emails: [Email]) {
        guard notificationsEnabled && importantEmailsEnabled && !emails.isEmpty else { return }

        let count = emails.count
        let title = count == 1 ? "New Important Email" : "\(count) New Important Emails"
        let body = count == 1
            ? "From: \(emails[0].sender.displayName)"
            : "\(count) important emails waiting"

        scheduleNotification(
            identifier: "important_emails_\(Date().timeIntervalSince1970)",
            title: title,
            body: body,
            category: .importantEmails
        )

        ProductionLogger.logCoreDataEvent("Scheduled notification for \(count) important emails")
    }

    /// Notify about new promotional emails
    func notifyNewPromotionalEmails(_ emails: [Email]) {
        guard notificationsEnabled && promotionalEmailsEnabled && !emails.isEmpty else { return }

        let count = emails.count
        let title = count == 1 ? "New Promotional Email" : "\(count) New Promotional Emails"
        let body = count == 1
            ? "From: \(emails[0].sender.displayName)"
            : "\(count) promotional emails received"

        scheduleNotification(
            identifier: "promotional_emails_\(Date().timeIntervalSince1970)",
            title: title,
            body: body,
            category: .promotionalEmails
        )

        ProductionLogger.logCoreDataEvent("Scheduled notification for \(count) promotional emails")
    }

    /// Notify about new calendar emails
    func notifyNewCalendarEmails(_ emails: [Email]) {
        guard notificationsEnabled && calendarEmailsEnabled && !emails.isEmpty else { return }

        let count = emails.count
        let title = count == 1 ? "New Calendar Email" : "\(count) New Calendar Emails"
        let body = count == 1
            ? "From: \(emails[0].sender.displayName)"
            : "\(count) calendar invites and events"

        scheduleNotification(
            identifier: "calendar_emails_\(Date().timeIntervalSince1970)",
            title: title,
            body: body,
            category: .calendarEmails
        )

        ProductionLogger.logCoreDataEvent("Scheduled notification for \(count) calendar emails")
    }

    /// Notify about new unread emails (general)
    func notifyNewEmails(_ emails: [Email]) {
        guard notificationsEnabled && !emails.isEmpty else { return }

        let count = emails.count
        let title = count == 1 ? "New Email" : "\(count) New Emails"
        let body = count == 1
            ? "From: \(emails[0].sender.displayName)"
            : "\(count) new emails in your inbox"

        scheduleNotification(
            identifier: "new_emails_\(Date().timeIntervalSince1970)",
            title: title,
            body: body,
            category: .generalEmails
        )

        ProductionLogger.logCoreDataEvent("Scheduled notification for \(count) new emails")
    }

    // MARK: - Notification Scheduling

    private func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        category: EmailNotificationCategory,
        timeInterval: TimeInterval = 1
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

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        notificationCenter.add(request) { error in
            if let error = error {
                ProductionLogger.logError(error as NSError, context: "Failed to schedule notification")
            }
        }
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

        let calendarCategory = UNNotificationCategory(
            identifier: EmailNotificationCategory.calendarEmails.rawValue,
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
            calendarCategory,
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
    case calendarEmails = "calendar_emails"
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
