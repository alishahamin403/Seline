import Foundation

// MARK: - Recurring Expense Models

// Note: RecurrenceFrequency is imported from EventModels.swift
// This avoids duplication with existing task/event recurrence logic

/// Reminder options for recurring expenses
enum ReminderOption: String, Codable, CaseIterable {
    case none = "none"
    case oneDayBefore = "1day_before"
    case threeDaysBefore = "3days_before"
    case oneWeekBefore = "1week_before"
    case onTheDay = "on_the_day"

    var displayName: String {
        switch self {
        case .none:
            return "No reminder"
        case .oneDayBefore:
            return "1 day before"
        case .threeDaysBefore:
            return "3 days before"
        case .oneWeekBefore:
            return "1 week before"
        case .onTheDay:
            return "On the day"
        }
    }
}

/// Represents a single recurring expense template
struct RecurringExpense: Identifiable, Codable, Hashable {
    var id: UUID
    var userId: String
    var title: String
    var description: String?
    var amount: Decimal
    var category: String?
    var frequency: RecurrenceFrequency
    var startDate: Date
    var endDate: Date?
    var nextOccurrence: Date
    var reminderOption: ReminderOption
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case amount
        case category
        case frequency
        case startDate = "start_date"
        case endDate = "end_date"
        case nextOccurrence = "next_occurrence"
        case reminderOption = "reminder_option"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: String,
        title: String,
        description: String? = nil,
        amount: Decimal,
        category: String? = nil,
        frequency: RecurrenceFrequency,
        startDate: Date,
        endDate: Date? = nil,
        nextOccurrence: Date,
        reminderOption: ReminderOption = .none,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.amount = amount
        self.category = category
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.nextOccurrence = nextOccurrence
        self.reminderOption = reminderOption
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedAmount: String {
        CurrencyParser.formatAmount(Double(truncating: amount as NSDecimalNumber))
    }

    var statusBadge: String {
        if !isActive {
            return "Paused"
        } else if let endDate = endDate, endDate < Date() {
            return "Ended"
        } else {
            return "Active"
        }
    }

    var yearlyAmount: Decimal {
        let multiplier: Decimal
        switch frequency {
        case .daily:
            multiplier = 365
        case .weekly:
            multiplier = 52
        case .biweekly:
            multiplier = 26
        case .monthly:
            multiplier = 12
        case .yearly:
            multiplier = 1
        }
        return amount * multiplier
    }

    var formattedYearlyAmount: String {
        CurrencyParser.formatAmount(Double(truncating: yearlyAmount as NSDecimalNumber))
    }
}

/// Represents a single instance of a recurring expense
struct RecurringInstance: Identifiable, Codable, Hashable {
    var id: UUID
    var recurringExpenseId: UUID
    var occurrenceDate: Date
    var amount: Decimal
    var noteId: UUID?
    var status: InstanceStatus
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recurringExpenseId = "recurring_expense_id"
        case occurrenceDate = "occurrence_date"
        case amount
        case noteId = "note_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        recurringExpenseId: UUID,
        occurrenceDate: Date,
        amount: Decimal,
        noteId: UUID? = nil,
        status: InstanceStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.recurringExpenseId = recurringExpenseId
        self.occurrenceDate = occurrenceDate
        self.amount = amount
        self.noteId = noteId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedAmount: String {
        CurrencyParser.formatAmount(Double(truncating: amount as NSDecimalNumber))
    }
}

/// Status of a recurring instance
enum InstanceStatus: String, Codable, CaseIterable, Hashable {
    case pending = "pending"
    case completed = "completed"
    case skipped = "skipped"

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .completed:
            return "Completed"
        case .skipped:
            return "Skipped"
        }
    }

    var color: String {
        switch self {
        case .pending:
            return "#FFA500" // Orange
        case .completed:
            return "#34C759" // Green
        case .skipped:
            return "#8E8E93" // Gray
        }
    }
}

// MARK: - Helper Functions

extension RecurringExpense {
    /// Calculate the next occurrence date based on frequency
    static func calculateNextOccurrence(from startDate: Date, frequency: RecurrenceFrequency) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)

        // If start date is today or in the future, that's the next occurrence
        if startDay >= today {
            return startDate
        }

        // Otherwise, calculate forward from start date until we reach or pass today
        var nextOccurrence = startDate
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
        }

        while calendar.startOfDay(for: nextOccurrence) < today {
            nextOccurrence = calendar.date(byAdding: components, to: nextOccurrence) ?? nextOccurrence
        }

        return nextOccurrence
    }

    /// Get reminder date based on selected option
    func getReminderDate() -> Date? {
        var components = DateComponents()

        switch reminderOption {
        case .none:
            return nil
        case .oneDayBefore:
            components.day = -1
        case .threeDaysBefore:
            components.day = -3
        case .oneWeekBefore:
            components.day = -7
        case .onTheDay:
            return nextOccurrence
        }

        return Calendar.current.date(byAdding: components, to: nextOccurrence)
    }
}
