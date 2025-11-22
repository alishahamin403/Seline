import Foundation
import EventKit

class RecurringExpenseCalendarService {
    static let shared = RecurringExpenseCalendarService()

    private let eventStore = EKEventStore()

    // MARK: - Calendar Access

    /// Explicitly request calendar permission (call this from UI for proper permission prompt context)
    func requestCalendarPermission() async -> Bool {
        print("📅 Requesting calendar permission...")
        let granted = await requestCalendarAccess()
        if granted {
            print("✅ Calendar permission granted")
        } else {
            print("❌ Calendar permission denied")
        }
        return granted
    }

    /// Auto-sync calendar events for existing recurring expenses (call on app launch)
    func autoSyncCalendarEventsForExistingExpenses() async {
        print("📅 Auto-syncing calendar events for existing recurring expenses...")

        // Check if we have calendar permission
        guard await requestCalendarAccess() else {
            print("⚠️ Calendar permission not available - skipping auto-sync")
            return
        }

        do {
            // Fetch all existing recurring expenses
            let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
            guard !expenses.isEmpty else {
                print("✅ No existing recurring expenses to sync")
                return
            }

            print("📅 Found \(expenses.count) existing recurring expenses")

            // Clean up old incorrectly-formatted events first
            print("🧹 Cleaning up old incorrectly-formatted calendar events...")
            await cleanupOldCalendarEvents(for: expenses)

            // Get the default calendar
            guard let calendar = getDefaultCalendar() else {
                print("❌ No default calendar found")
                return
            }

            var totalCreated = 0

            // Sync each existing expense
            for expense in expenses {
                do {
                    // Fetch instances for this expense
                    let instances = try await RecurringExpenseService.shared.fetchInstances(for: expense.id)

                    print("📅 Syncing \(instances.count) instances for \(expense.title)")

                    // Create calendar events for each instance
                    var successCount = 0
                    for instance in instances {
                        do {
                            try createAllDayEvent(
                                for: expense,
                                instance: instance,
                                in: calendar
                            )
                            successCount += 1
                        } catch {
                            // Silently skip if event already exists
                            if !error.localizedDescription.contains("already exist") {
                                print("⚠️ Skipped event (may already exist): \(expense.title) on \(instance.occurrenceDate)")
                            }
                        }
                    }

                    totalCreated += successCount
                    print("✅ Created/verified \(successCount)/\(instances.count) events for \(expense.title)")
                } catch {
                    print("⚠️ Failed to sync instances for \(expense.title): \(error.localizedDescription)")
                }
            }

            print("✅ Auto-sync complete: Created/verified \(totalCreated) total calendar events")

            // Verify events were created
            await verifyCalendarEvents(for: expenses)
        } catch {
            print("⚠️ Auto-sync failed: \(error.localizedDescription)")
        }
    }

    /// Verify that calendar events were created and show which calendars they're in
    private func verifyCalendarEvents(for expenses: [RecurringExpense]) async {
        let now = Date()
        let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let calendars = eventStore.calendars(for: .event)

        print("📅 Verifying calendar events...")
        print("📅 Calendars in iPhone Calendar app:")
        for calendar in calendars {
            let predicate = eventStore.predicateForEvents(withStart: now, end: twoYearsLater, calendars: [calendar])
            let events = eventStore.events(matching: predicate)
            let recurringExpenseEvents = events.filter { event in
                expenses.contains(where: { $0.title == event.title })
            }
            if !recurringExpenseEvents.isEmpty {
                print("   - \(calendar.title) (type: \(calendar.type)): \(recurringExpenseEvents.count) recurring expense events")
            }
        }
    }

    /// Clean up old incorrectly-formatted calendar events
    private func cleanupOldCalendarEvents(for expenses: [RecurringExpense]) async {
        let now = Date()
        let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: now, end: twoYearsLater, calendars: calendars)

        let allEvents = eventStore.events(matching: predicate)
        var deletedCount = 0

        // Find and delete events that match our recurring expense titles
        for event in allEvents {
            // Check if this event title matches any of our recurring expenses
            if expenses.contains(where: { $0.title == event.title }) {
                do {
                    try eventStore.remove(event, span: .thisEvent, commit: true)
                    deletedCount += 1
                    print("🗑️ Deleted old event: \(event.title)")
                } catch {
                    print("⚠️ Failed to delete event: \(error.localizedDescription)")
                }
            }
        }

        if deletedCount > 0 {
            print("✅ Cleaned up \(deletedCount) old incorrectly-formatted calendar events")
        }
    }

    /// Request calendar access and create all-day events for recurring expense instances
    func createCalendarEventsForRecurringExpense(
        _ expense: RecurringExpense,
        instances: [RecurringInstance]
    ) async {
        // Request calendar access
        let granted = await requestCalendarAccess()
        guard granted else {
            print("❌ Calendar access denied for recurring expense \(expense.title)")
            print("⚠️ User needs to grant calendar permission in Settings > Seline > Calendars")
            return
        }

        // Get the default calendar
        guard let calendar = getDefaultCalendar() else {
            print("❌ No default calendar found")
            print("⚠️ Make sure you have at least one calendar available in Calendar app")
            return
        }

        print("📅 Creating \(instances.count) calendar events for \(expense.title)")

        // Create an all-day event for each instance
        var successCount = 0
        for instance in instances {
            do {
                try createAllDayEvent(
                    for: expense,
                    instance: instance,
                    in: calendar
                )
                successCount += 1
            } catch {
                print("❌ Failed to create calendar event for instance: \(error.localizedDescription)")
            }
        }

        print("✅ Successfully created \(successCount)/\(instances.count) calendar events")
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

        // Normalize dates to midnight (local timezone) for all-day events
        let dateCalendar = Calendar.current
        let startOfDay = dateCalendar.startOfDay(for: instance.occurrenceDate)
        let endOfDay = dateCalendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        // Set as all-day event on the occurrence date
        event.title = expense.title
        event.startDate = startOfDay
        event.endDate = endOfDay
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        print("✅ Created all-day calendar event: \(expense.title) on \(dateFormatter.string(from: startOfDay)) in calendar '\(calendar.title)'")
    }

    // MARK: - Calendar Selection

    /// Get the default calendar (Calendar app's main calendar)
    private func getDefaultCalendar() -> EKCalendar? {
        // Try to get the default calendar
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            print("📅 Using default calendar: \(defaultCalendar.title) (type: \(defaultCalendar.type))")
            return defaultCalendar
        }

        // Get all available calendars and log them
        let calendars = eventStore.calendars(for: .event)
        print("📅 Available calendars: \(calendars.map { "\($0.title) (type: \($0.type))" }.joined(separator: ", "))")

        // Fallback: get first local calendar (most visible)
        if let localCalendar = calendars.first(where: { $0.type == .local }) {
            print("📅 Using local calendar: \(localCalendar.title)")
            return localCalendar
        }

        // Then try CalDAV
        if let caldavCalendar = calendars.first(where: { $0.type == .calDAV }) {
            print("📅 Using CalDAV calendar: \(caldavCalendar.title)")
            return caldavCalendar
        }

        // Last resort: any writable calendar
        if let writableCalendar = calendars.first(where: { !$0.isImmutable }) {
            print("📅 Using writable calendar: \(writableCalendar.title)")
            return writableCalendar
        }

        print("❌ No writable calendar found")
        return nil
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
