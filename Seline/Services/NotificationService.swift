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
        isAuthorized = settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional ||
            settings.authorizationStatus == .ephemeral
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

    func scheduleTaskReminder(taskId: String, title: String, body: String, scheduledTime: Date, isAlertReminder: Bool = true) async {
        // Check if we have authorization
        guard isAuthorized else {
            print("Notification authorization not granted")
            return
        }

        let content = UNMutableNotificationContent()
        // Show event name as title
        content.title = title.isEmpty ? (isAlertReminder ? "Event Reminder" : "Event Starting") : title
        // Show reminder details in body
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "task_reminder"
        content.userInfo = ["type": "task_reminder", "taskId": taskId, "isAlertReminder": isAlertReminder]

        // Create date components from the scheduled time
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduledTime
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        // Create unique identifier for each notification type
        let notificationType = isAlertReminder ? "alert" : "start"
        let request = UNNotificationRequest(
            identifier: "task-reminder-\(taskId)-\(notificationType)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            let type = isAlertReminder ? "alert reminder" : "event start"
            print("⏰ Scheduled \(type) for '\(title)' at \(scheduledTime)")
        } catch {
            print("Failed to schedule task reminder: \(error)")
        }
    }

    func cancelTaskReminder(taskId: String) {
        // Cancel both alert reminder and event start notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "task-reminder-\(taskId)-alert",
                "task-reminder-\(taskId)-start",
                "task-reminder-\(taskId)"  // Legacy format for backward compatibility
            ]
        )
    }

    // MARK: - Top Stories Notifications

    func scheduleTopStoryNotification(title: String, category: String, url: String? = nil) async {
        // Check if we have authorization
        guard isAuthorized else {
            print("Notification authorization not granted")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "New Top Story"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "top_story"

        // Store URL in userInfo for deep linking
        var userInfo: [AnyHashable: Any] = ["type": "top_story", "category": category]
        if let url = url {
            userInfo["url"] = url
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "top-story-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Show immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📰 Scheduled notification for new top story: \(title)")
        } catch {
            print("Failed to schedule top story notification: \(error)")
        }
    }

    // MARK: - Location-Based Notifications

    /// Schedule arrival notification with contextual information
    func scheduleArrivalNotification(
        locationName: String,
        unreadEmailCount: Int,
        upcomingEventsCount: Int,
        weatherInfo: String? = nil,
        sessionId: UUID? = nil
    ) async {
        guard isAuthorized else {
            print("Notification authorization not granted")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Welcome to \(locationName)"

        // Build context summary
        var contextParts: [String] = []
        if unreadEmailCount > 0 {
            contextParts.append("\(unreadEmailCount) unread email\(unreadEmailCount == 1 ? "" : "s")")
        }
        if upcomingEventsCount > 0 {
            contextParts.append("\(upcomingEventsCount) event\(upcomingEventsCount == 1 ? "" : "s") today")
        }
        if let weather = weatherInfo {
            contextParts.append(weather)
        }

        content.body = contextParts.isEmpty ? "You have arrived" : contextParts.joined(separator: " • ")
        content.sound = .default
        content.categoryIdentifier = "location_arrival"
        content.userInfo = ["type": "location_arrival", "locationName": locationName]

        // Use sessionId in identifier for deduplication - if same session triggers multiple times,
        // the notification will replace the previous one instead of creating duplicates
        let identifier = sessionId != nil ? "arrival-\(sessionId!.uuidString)" : "arrival-\(Date().timeIntervalSince1970)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📍 Scheduled arrival notification for \(locationName) (session: \(sessionId?.uuidString.prefix(8) ?? "none"))")
        } catch {
            print("Failed to schedule arrival notification: \(error)")
        }
    }

    // MARK: - Daily Briefing Notifications

    /// Schedule daily briefing notification
    func scheduleDailyBriefing(
        emailCount: Int,
        eventsToday: Int,
        upcomingExpenses: [(String, Double)],
        weather: String?
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good Morning"

        var summary: [String] = []
        if eventsToday > 0 {
            summary.append("\(eventsToday) event\(eventsToday == 1 ? "" : "s") today")
        }
        if emailCount > 0 {
            summary.append("\(emailCount) unread email\(emailCount == 1 ? "" : "s")")
        }
        if !upcomingExpenses.isEmpty {
            let total = upcomingExpenses.reduce(0) { $0 + $1.1 }
            summary.append("$\(String(format: "%.0f", total)) in upcoming expenses")
        }
        if let weather = weather {
            summary.append(weather)
        }

        content.body = summary.isEmpty ? "Have a great day!" : summary.joined(separator: " • ")
        content.sound = .default
        content.categoryIdentifier = "daily_briefing"
        content.userInfo = ["type": "daily_briefing"]

        let request = UNNotificationRequest(
            identifier: "daily-briefing-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🌅 Scheduled daily briefing notification")
        } catch {
            print("Failed to schedule daily briefing: \(error)")
        }
    }

    /// Schedule daily briefing for a specific time
    func scheduleDailyBriefingAt(hour: Int, minute: Int = 0) async {
        guard isAuthorized else { return }

        // Create date components for the trigger
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        // This will trigger every day at the specified time
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Daily Briefing"
        content.body = "Tap to see your day ahead"
        content.sound = .default
        content.categoryIdentifier = "daily_briefing_scheduled"
        content.userInfo = ["type": "daily_briefing_scheduled"]

        let request = UNNotificationRequest(
            identifier: "daily-briefing-scheduled",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🌅 Scheduled recurring daily briefing at \(hour):\(String(format: "%02d", minute))")
        } catch {
            print("Failed to schedule daily briefing: \(error)")
        }
    }

    // MARK: - Smart Event Reminders

    /// Schedule smart reminder with travel time consideration
    func scheduleSmartEventReminder(
        eventTitle: String,
        eventTime: Date,
        travelMinutes: Int,
        currentLocation: String?
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Leave Soon"

        var body = "Leave in \(travelMinutes) min to arrive on time for '\(eventTitle)'"
        if let location = currentLocation {
            body = "Leave \(location) in \(travelMinutes) min for '\(eventTitle)'"
        }

        content.body = body
        content.sound = .default
        content.categoryIdentifier = "smart_reminder"
        content.userInfo = [
            "type": "smart_reminder",
            "eventTitle": eventTitle,
            "travelMinutes": travelMinutes
        ]

        // Schedule for travel time before event
        let notificationTime = eventTime.addingTimeInterval(-Double(travelMinutes * 60))
        let timeComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: timeComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "smart-reminder-\(eventTime.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("⏰ Scheduled smart reminder for '\(eventTitle)' with \(travelMinutes) min travel time")
        } catch {
            print("Failed to schedule smart reminder: \(error)")
        }
    }

    // MARK: - Habit & Streak Notifications

    /// Schedule habit streak notification
    func scheduleHabitStreakNotification(
        locationName: String,
        streakDays: Int,
        habitType: String
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "🎉 \(streakDays)-Day Streak!"
        content.body = "You've visited \(locationName) \(streakDays) days in a row. Keep it up!"
        content.sound = .default
        content.categoryIdentifier = "habit_streak"
        content.userInfo = [
            "type": "habit_streak",
            "locationName": locationName,
            "streakDays": streakDays,
            "habitType": habitType
        ]

        let request = UNNotificationRequest(
            identifier: "streak-\(locationName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔥 Scheduled streak notification for \(locationName)")
        } catch {
            print("Failed to schedule streak notification: \(error)")
        }
    }

    /// Schedule habit reminder based on patterns
    func scheduleHabitReminderNotification(
        locationName: String,
        usualTime: String,
        daysActive: Int
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Habit Reminder"
        content.body = "You usually visit \(locationName) around \(usualTime). \(daysActive) visits logged."
        content.sound = .default
        content.categoryIdentifier = "habit_reminder"
        content.userInfo = [
            "type": "habit_reminder",
            "locationName": locationName
        ]

        let request = UNNotificationRequest(
            identifier: "habit-reminder-\(locationName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("💪 Scheduled habit reminder for \(locationName)")
        } catch {
            print("Failed to schedule habit reminder: \(error)")
        }
    }

    // MARK: - Spending Alert Notifications

    /// Schedule spending alert notification
    func scheduleSpendingAlert(category: String, amount: Double, threshold: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Spending Alert"
        content.body = "You've spent $\(String(format: "%.0f", amount)) on \(category) this week (avg: $\(String(format: "%.0f", threshold)))"
        content.sound = .default
        content.categoryIdentifier = "spending_alert"
        content.userInfo = [
            "type": "spending_alert",
            "category": category,
            "amount": amount
        ]

        let request = UNNotificationRequest(
            identifier: "spending-alert-\(category)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("💰 Scheduled spending alert for \(category)")
        } catch {
            print("Failed to schedule spending alert: \(error)")
        }
    }

    // MARK: - Expense Reminders

    func scheduleExpenseReminder(reminder: ExpenseReminder) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Spending Reminder"
        content.body = "Check your \(reminder.expenseName) spending"
        content.sound = .default
        content.categoryIdentifier = "expense_reminder"
        content.userInfo = [
            "type": "expense_reminder",
            "expenseName": reminder.expenseName
        ]

        var dateComponents = DateComponents()
        dateComponents.hour = reminder.hour
        dateComponents.minute = reminder.minute

        switch reminder.frequency {
        case .daily:
            break
        case .weekly:
            dateComponents.weekday = reminder.weekday ?? Calendar.current.component(.weekday, from: Date())
        case .monthly:
            dateComponents.day = reminder.dayOfMonth ?? Calendar.current.component(.day, from: Date())
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = expenseReminderIdentifier(for: reminder)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 Scheduled expense reminder for \(reminder.expenseName)")
        } catch {
            print("Failed to schedule expense reminder: \(error)")
        }
    }

    func cancelExpenseReminder(for reminder: ExpenseReminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [expenseReminderIdentifier(for: reminder)])
    }

    private func expenseReminderIdentifier(for reminder: ExpenseReminder) -> String {
        let normalized = reminder.expenseName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "expense-reminder-\(normalized)"
    }

    // MARK: - Utility Methods

    /// Cancel all pending notifications of a specific type
    func cancelNotifications(ofType type: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiersToRemove = requests
                .filter { $0.content.userInfo["type"] as? String == type }
                .map { $0.identifier }

            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            print("🗑️ Cancelled \(identifiersToRemove.count) notifications of type '\(type)'")
        }
    }
}
