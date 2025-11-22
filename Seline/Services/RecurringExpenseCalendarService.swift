import Foundation
import EventKit

class RecurringExpenseCalendarService {
    static let shared = RecurringExpenseCalendarService()

    private let eventStore = EKEventStore()

    // MARK: - Calendar Access

    /// Request calendar access and create all-day events for recurring expense instances
    func createCalendarEventsForRecurringExpense(
        _ expense: RecurringExpense,
        instances: [RecurringInstance]
    ) async {
        // Request calendar access
        let granted = await requestCalendarAccess()
        guard granted else {
            print("❌ Calendar access denied for recurring expense \(expense.title)")
            return
        }

        // Get the default calendar
        guard let calendar = getDefaultCalendar() else {
            print("❌ No default calendar found")
            return
        }

        // Create an all-day event for each instance
        for instance in instances {
            do {
                try createAllDayEvent(
                    for: expense,
                    instance: instance,
                    in: calendar
                )
            } catch {
                print("❌ Failed to create calendar event for instance: \(error.localizedDescription)")
            }
        }
    }

    /// Request full calendar access (iOS 17+)
    private func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                if granted {
                    print("✅ Calendar access granted")
                }
                return granted
            } catch {
                print("❌ Failed to request calendar access: \(error.localizedDescription)")
                return false
            }
        } else {
            // Fallback for iOS 16 and earlier
            return await requestCalendarAccessLegacy()
        }
    }

    /// Fallback for iOS 16 and earlier
    private func requestCalendarAccessLegacy() async -> Bool {
        return await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error = error {
                    print("❌ Failed to request calendar access: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Event Creation

    /// Create an all-day calendar event for a recurring expense instance
    private func createAllDayEvent(
        for expense: RecurringExpense,
        instance: RecurringInstance,
        in calendar: EKCalendar
    ) throws {
        let event = EKEvent(eventStore: eventStore)

        // Set as all-day event on the occurrence date
        event.title = expense.title
        event.startDate = instance.occurrenceDate
        event.endDate = instance.occurrenceDate
        event.isAllDay = true

        // Add description with amount and category info
        var description = "Recurring expense due: \(expense.formattedAmount)"
        if let category = expense.category {
            description += "\nCategory: \(category)"
        }
        if let desc = expense.description, !desc.isEmpty {
            description += "\n\n\(desc)"
        }
        event.notes = description

        // Set calendar
        event.calendar = calendar

        // Save event
        try eventStore.save(event, span: .thisEvent, commit: true)
        print("✅ Created all-day calendar event: \(expense.title) on \(instance.occurrenceDate)")
    }

    // MARK: - Calendar Selection

    /// Get the default calendar (Calendar app's main calendar)
    private func getDefaultCalendar() -> EKCalendar? {
        // Try to get the default calendar
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            return defaultCalendar
        }

        // Fallback: get first calendar that supports events
        let calendars = eventStore.calendars(for: .event)
        return calendars.first(where: { $0.type == .local || $0.type == .calDAV })
    }

    /// Delete calendar events for a recurring expense
    func deleteCalendarEventsForRecurringExpense(_ expenseId: UUID) async {
        let granted = await requestCalendarAccess()
        guard granted else {
            print("❌ Calendar access denied")
            return
        }

        // Create a predicate to find events related to this expense
        let now = Date()
        let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: now, end: twoYearsLater, calendars: calendars)

        let allEvents = eventStore.events(matching: predicate)

        // Find and delete events created for this recurring expense
        for event in allEvents {
            // Check if event notes contain the expense ID
            if let notes = event.notes, notes.contains(expenseId.uuidString) {
                do {
                    try eventStore.remove(event, span: .thisEvent, commit: true)
                    print("✅ Deleted calendar event: \(event.title)")
                } catch {
                    print("❌ Failed to delete calendar event: \(error.localizedDescription)")
                }
            }
        }
    }
}
