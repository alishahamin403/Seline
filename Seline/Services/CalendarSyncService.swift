import EventKit
import Foundation

/// CalendarSyncService: READ-ONLY synchronization of iPhone calendar events
/// ⚠️ IMPORTANT: This service ONLY READS from the iPhone calendar.
/// It NEVER writes, modifies, or creates events in the iPhone calendar.
/// All synced events are stored in Seline app as "Personal" tasks.
class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    private let userDefaults = UserDefaults.standard

    // Key to track if we've already synced calendars on first launch
    private let lastSyncDateKey = "lastCalendarSyncDate"
    private let syncedEventIDsKey = "syncedCalendarEventIDs"

    private init() {}

    // MARK: - Calendar Authorization

    /// Request access to the user's calendar
    func requestCalendarAccess() async -> Bool {
        // Check current authorization status
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                return granted
            } catch {
                print("❌ Failed to request calendar access: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Event Fetching & Filtering (READ-ONLY)

    /// Fetch calendar events from current date onwards (not historical)
    /// This is a READ-ONLY operation - no modifications to the calendar
    /// - Returns: Array of calendar events from this month onwards
    func fetchCalendarEventsFromCurrentMonthOnwards() async -> [EKEvent] {
        // Get authorization first
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            print("❌ Calendar access not granted")
            return []
        }

        let calendar = Calendar.current
        let now = Date()

        // Get the first day of the current month
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        // Create a predicate to fetch events from current month onwards (READ-ONLY)
        // We'll fetch events for the next 2 years to be generous with the range
        let endDate = calendar.date(byAdding: .year, value: 2, to: currentMonthStart) ?? now

        let predicate = eventStore.predicateForEvents(withStart: currentMonthStart, end: endDate)

        // ⚠️ READ-ONLY: eventStore.events(matching:) only reads, does not modify
        let allEvents = eventStore.events(matching: predicate)

        // Filter out all-day events and events that don't have a time component
        let timedEvents = allEvents.filter { !$0.isAllDay }

        print("✅ Fetched \(timedEvents.count) calendar events from \(currentMonthStart) [READ-ONLY]")

        return timedEvents
    }

    /// Fetch only new events (not previously synced)
    func fetchNewCalendarEvents() async -> [EKEvent] {
        let allEvents = await fetchCalendarEventsFromCurrentMonthOnwards()
        let syncedEventIDs = getSyncedEventIDs()

        // Filter out events we've already synced
        let newEvents = allEvents.filter { event in
            !syncedEventIDs.contains(event.eventIdentifier)
        }

        print("✅ Found \(newEvents.count) new calendar events to sync")

        return newEvents
    }

    // MARK: - Event Conversion

    /// Convert an EKEvent to a TaskItem
    /// Creates a TaskItem marked as "Personal" (tagId: nil) for synced calendar events
    /// - Parameter event: The EventKit event to convert (READ-ONLY)
    /// - Returns: A TaskItem representing the calendar event
    func convertEKEventToTaskItem(_ event: EKEvent) -> TaskItem {
        let calendar = Calendar.current
        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate

        // Determine the weekday from the event's start date
        let weekday = WeekDay.from(date: startDate)

        // Create title with location if available
        var title = event.title ?? "Calendar Event"
        if let location = event.location, !location.isEmpty {
            title += " @ \(location)"
        }

        // Extract notes as description
        let description = event.notes

        // Create the TaskItem as Personal (tagId: nil = Personal tag)
        var taskItem = TaskItem(
            title: title,
            weekday: weekday,
            description: description,
            scheduledTime: startDate,
            endTime: endDate,
            targetDate: startDate,
            reminderTime: .none, // Let user set their own reminders
            isRecurring: event.hasRecurrenceRules,
            recurrenceFrequency: convertEKRecurrenceToFrequency(event.recurrenceRules)
        )

        // Mark as Personal - tagId: nil means default Personal category
        taskItem.tagId = nil

        // Store the original event ID for sync tracking
        taskItem.id = "cal_\(event.eventIdentifier)"

        return taskItem
    }

    /// Convert EventKit recurrence rules to our RecurrenceFrequency enum
    private func convertEKRecurrenceToFrequency(_ rules: [EKRecurrenceRule]?) -> RecurrenceFrequency? {
        guard let rules = rules, let firstRule = rules.first else { return nil }

        switch firstRule.frequency {
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .biweekly:
            return .biweekly
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        @unknown default:
            return nil
        }
    }

    // MARK: - Sync Tracking

    /// Mark events as synced by storing their IDs
    func markEventsAsSynced(_ events: [EKEvent]) {
        var syncedIDs = getSyncedEventIDs()
        let newIDs = events.map { $0.eventIdentifier }
        syncedIDs.append(contentsOf: newIDs)

        userDefaults.set(syncedIDs, forKey: syncedEventIDsKey)
        userDefaults.set(Date(), forKey: lastSyncDateKey)
    }

    /// Get the list of already-synced event IDs
    private func getSyncedEventIDs() -> [String] {
        return userDefaults.stringArray(forKey: syncedEventIDsKey) ?? []
    }

    /// Get the date of the last sync
    func getLastSyncDate() -> Date? {
        return userDefaults.object(forKey: lastSyncDateKey) as? Date
    }

    /// Clear sync tracking (for testing or manual reset)
    func clearSyncTracking() {
        userDefaults.removeObject(forKey: syncedEventIDsKey)
        userDefaults.removeObject(forKey: lastSyncDateKey)
    }
}

// MARK: - Helper Extensions

extension WeekDay {
    /// Get the WeekDay enum value for a given date
    static func from(date: Date) -> WeekDay {
        let calendar = Calendar.current
        let weekdayNumber = calendar.component(.weekday, from: date)

        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        // Convert to our WeekDay enum
        switch weekdayNumber {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}
