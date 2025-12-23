import Foundation
import UserNotifications
import UIKit

class RecurringExpenseManager {
    static let shared = RecurringExpenseManager()

    // MARK: - Instance Generation

    /// Generate instances for a recurring expense based on its frequency
    /// Creates instances from start date through specified number of future months
    func generateInstances(
        for expense: RecurringExpense,
        futureMonths: Int = 12
    ) -> [RecurringInstance] {
        var instances: [RecurringInstance] = []
        var currentDate = expense.startDate

        let calendar = Calendar.current
        let endDate = expense.endDate ?? calendar.date(byAdding: .month, value: futureMonths, to: expense.startDate) ?? Date()

        while currentDate <= endDate {
            let instance = RecurringInstance(
                recurringExpenseId: expense.id,
                occurrenceDate: currentDate,
                amount: expense.amount,
                status: .pending
            )
            instances.append(instance)

            // Calculate next occurrence
            currentDate = calculateNextDate(from: currentDate, frequency: expense.frequency)
        }

        return instances
    }

    /// Calculate next occurrence date based on frequency
    private func calculateNextDate(from date: Date, frequency: RecurrenceFrequency) -> Date {
        var components = DateComponents()

        switch frequency {
        case .daily:
            components.day = 1
        case .weekly:
            components.day = 7
        case .biweekly:
            components.day = 14
        case .monthly:
            components.month = 1
        case .yearly:
            components.year = 1
        case .custom:
            // For custom frequency, advance by 1 week as a fallback
            // Note: This is an approximation; full implementation would require customRecurrenceDays
            components.day = 7
        }

        return Calendar.current.date(byAdding: components, to: date) ?? date
    }

    // MARK: - Reminder Scheduling

    /// Get the reminder date for an expense based on its reminder option
    func getReminderDate(for expense: RecurringExpense) -> Date? {
        guard expense.reminderOption != .none else { return nil }

        let calendar = Calendar.current
        var components = DateComponents()

        switch expense.reminderOption {
        case .none:
            return nil
        case .oneDayBefore:
            components.day = -1
        case .threeDaysBefore:
            components.day = -3
        case .oneWeekBefore:
            components.day = -7
        case .onTheDay:
            return expense.nextOccurrence
        }

        return calendar.date(byAdding: components, to: expense.nextOccurrence)
    }

    /// Schedule a local notification for a recurring expense
    func scheduleReminder(for expense: RecurringExpense) {
        guard let reminderDate = getReminderDate(for: expense) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recurring Expense Due"
        content.body = "\(expense.title) - \(expense.formattedAmount)"
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        // Add category for custom actions
        content.categoryIdentifier = "RECURRING_EXPENSE"
        content.userInfo = [
            "expenseId": expense.id.uuidString,
            "expenseTitle": expense.title
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: expense.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule reminder: \(error.localizedDescription)")
            } else {
                print("✅ Reminder scheduled for \(expense.title) at \(reminderDate)")
            }
        }
    }

    /// Cancel reminder for an expense
    func cancelReminder(for expenseId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [expenseId.uuidString]
        )
    }

    // MARK: - Utility Functions

    /// Check if an instance is overdue
    func isInstanceOverdue(_ instance: RecurringInstance) -> Bool {
        return instance.occurrenceDate < Date() && instance.status == .pending
    }

    /// Get upcoming instances (within next 30 days)
    func getUpcomingInstances(_ instances: [RecurringInstance]) -> [RecurringInstance] {
        let calendar = Calendar.current
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        return instances.filter { instance in
            instance.status == .pending &&
                instance.occurrenceDate >= Date() &&
                instance.occurrenceDate <= thirtyDaysFromNow
        }
        .sorted { $0.occurrenceDate < $1.occurrenceDate }
    }

    /// Get overdue instances
    func getOverdueInstances(_ instances: [RecurringInstance]) -> [RecurringInstance] {
        return instances.filter { instance in
            isInstanceOverdue(instance)
        }
        .sorted { $0.occurrenceDate < $1.occurrenceDate }
    }

    /// Mark instance as completed
    func markAsCompleted(_ instance: inout RecurringInstance) {
        instance.status = .completed
        instance.updatedAt = Date()
    }

    /// Mark instance as skipped
    func markAsSkipped(_ instance: inout RecurringInstance) {
        instance.status = .skipped
        instance.updatedAt = Date()
    }

    // MARK: - Statistics

    /// Calculate total for a specific month
    func getTotalForMonth(
        _ month: Int,
        year: Int,
        instances: [RecurringInstance]
    ) -> Decimal {
        let calendar = Calendar.current
        let startOfMonth = DateComponents(calendar: calendar, year: year, month: month, day: 1).date ?? Date()
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? Date()

        return instances
            .filter { instance in
                instance.occurrenceDate >= startOfMonth &&
                    instance.occurrenceDate <= endOfMonth &&
                    instance.status == .pending
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Get summary statistics
    func getStatistics(
        for expenses: [RecurringExpense],
        instances: [RecurringInstance]
    ) -> RecurringExpenseStatistics {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let monthlyTotal = getTotalForMonth(currentMonth, year: currentYear, instances: instances)
        let yearlyTotal = (1...12).reduce(0) { total, month in
            total + getTotalForMonth(month, year: currentYear, instances: instances)
        }

        let activeCount = expenses.filter { $0.isActive }.count
        let upcomingCount = getUpcomingInstances(instances).count
        let overdueCount = getOverdueInstances(instances).count

        return RecurringExpenseStatistics(
            activeExpenseCount: activeCount,
            monthlyTotal: monthlyTotal,
            yearlyTotal: yearlyTotal,
            upcomingInstanceCount: upcomingCount,
            overdueInstanceCount: overdueCount
        )
    }
}

// MARK: - Statistics Model

struct RecurringExpenseStatistics {
    let activeExpenseCount: Int
    let monthlyTotal: Decimal
    let yearlyTotal: Decimal
    let upcomingInstanceCount: Int
    let overdueInstanceCount: Int

    var monthlyTotalFormatted: String {
        CurrencyParser.formatAmountNoDecimals(Double(truncating: monthlyTotal as NSDecimalNumber))
    }

    var yearlyTotalFormatted: String {
        CurrencyParser.formatAmount(Double(truncating: yearlyTotal as NSDecimalNumber))
    }
}
