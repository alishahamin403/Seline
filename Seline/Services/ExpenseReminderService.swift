import Foundation

@MainActor
class ExpenseReminderService: ObservableObject {
    static let shared = ExpenseReminderService()

    @Published private(set) var reminders: [ExpenseReminder] = []

    private let storageKey = "expenseReminders"
    private let notificationService = NotificationService.shared

    private init() {
        loadReminders()
    }

    func upsertReminder(
        expenseName: String,
        frequency: ExpenseReminderFrequency,
        hour: Int,
        minute: Int
    ) async -> ExpenseReminder {
        let trimmedName = expenseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let now = Date()

        let weekday = calendar.component(.weekday, from: now)
        let dayOfMonth = calendar.component(.day, from: now)

        if let existingIndex = reminders.firstIndex(where: { $0.expenseName.lowercased() == trimmedName.lowercased() }) {
            var updated = reminders[existingIndex]
            updated.frequency = frequency
            updated.hour = hour
            updated.minute = minute
            updated.weekday = weekday
            updated.dayOfMonth = dayOfMonth
            updated.updatedAt = Date()
            reminders[existingIndex] = updated
            saveReminders()
            await notificationService.scheduleExpenseReminder(reminder: updated)
            return updated
        }

        let reminder = ExpenseReminder(
            expenseName: trimmedName,
            frequency: frequency,
            hour: hour,
            minute: minute,
            weekday: weekday,
            dayOfMonth: dayOfMonth
        )
        reminders.insert(reminder, at: 0)
        saveReminders()
        await notificationService.scheduleExpenseReminder(reminder: reminder)
        return reminder
    }

    func reminder(for expenseName: String) -> ExpenseReminder? {
        reminders.first { $0.expenseName.lowercased() == expenseName.lowercased() }
    }

    func deleteReminder(id: UUID) {
        if let reminder = reminders.first(where: { $0.id == id }) {
            notificationService.cancelExpenseReminder(for: reminder)
        }
        reminders.removeAll { $0.id == id }
        saveReminders()
    }

    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            reminders = []
            return
        }
        do {
            reminders = try JSONDecoder().decode([ExpenseReminder].self, from: data)
        } catch {
            reminders = []
        }
    }

    private func saveReminders() {
        do {
            let data = try JSONEncoder().encode(reminders)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ Failed to save expense reminders: \(error)")
        }
    }
}
