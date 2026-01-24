import Foundation

// MARK: - Expense Budget Models

enum ExpenseBudgetPeriod: String, Codable, CaseIterable {
    case weekly
    case monthly

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct ExpenseBudget: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var limit: Double
    var period: ExpenseBudgetPeriod
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        limit: Double,
        period: ExpenseBudgetPeriod,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.limit = limit
        self.period = period
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ExpenseBudgetStatus: Equatable {
    let spent: Double
    let limit: Double
    let progress: Double

    var remaining: Double {
        max(limit - spent, 0)
    }

    var isOverBudget: Bool {
        spent > limit
    }
}

// MARK: - Expense Reminder Models

enum ExpenseReminderFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct ExpenseReminder: Identifiable, Codable, Hashable {
    var id: UUID
    var expenseName: String
    var frequency: ExpenseReminderFrequency
    var hour: Int
    var minute: Int
    var weekday: Int?
    var dayOfMonth: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        expenseName: String,
        frequency: ExpenseReminderFrequency,
        hour: Int,
        minute: Int,
        weekday: Int? = nil,
        dayOfMonth: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.expenseName = expenseName
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
