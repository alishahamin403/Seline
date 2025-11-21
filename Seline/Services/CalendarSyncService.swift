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
    private let monthsToSkipKey = "calendarSyncMonthsToSkip"

    // Months to skip during sync: (year, month) tuples
    // Example: [(2026, 2)] skips February 2026
    private var monthsToSkip: Set<String> = []

    private init() {
        loadMonthsToSkip()
    }

    // MARK: - Testing/Debug: Month Skipping

    /// Set a month to skip during calendar sync (for testing purposes)
    /// - Parameters:
    ///   - year: The year (e.g., 2026)
    ///   - month: The month (1-12, e.g., 2 for February)
    func skipMonth(year: Int, month: Int) {
        let key = "\(year)-\(String(format: "%02d", month))"
        monthsToSkip.insert(key)
        saveMonthsToSkip()
    }

    /// Clear a month skip
    func unskipMonth(year: Int, month: Int) {
        let key = "\(year)-\(String(format: "%02d", month))"
        monthsToSkip.remove(key)
        saveMonthsToSkip()
    }

    /// Clear all month skips
    func clearAllMonthSkips() {
        monthsToSkip.removeAll()
        userDefaults.removeObject(forKey: monthsToSkipKey)
    }

    /// Get list of months being skipped
    func getSkippedMonths() -> [String] {
        return Array(monthsToSkip).sorted()
    }

    private func saveMonthsToSkip() {
        let array = Array(monthsToSkip)
        userDefaults.set(array, forKey: monthsToSkipKey)
    }

    private func loadMonthsToSkip() {
        if let saved = userDefaults.stringArray(forKey: monthsToSkipKey) {
            monthsToSkip = Set(saved)
        }
    }

    private func isMonthSkipped(year: Int, month: Int) -> Bool {
        let key = "\(year)-\(String(format: "%02d", month))"
        return monthsToSkip.contains(key)
    }

    private func monthName(_ month: Int) -> String {
        let months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return months[max(0, min(11, month - 1))]
    }

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
                // iOS 17.0+: Use requestFullAccessToEvents for full calendar access
                if #available(iOS 17.0, *) {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    return granted
                } else {
                    // iOS 16.x and earlier: Use requestAccess with completion handler
                    // Wrap in async/await using withCheckedThrowingContinuation
                    return try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }
            } catch {
                print("❌ Failed to request calendar access: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Event Fetching & Filtering (READ-ONLY)

    /// Fetch calendar events from 6 months back to 1 year ahead
    /// This is a READ-ONLY operation - no modifications to the calendar
    /// Fetches 6 months back to allow searching historical events + 1 year forward
    /// - Returns: Array of calendar events from past 6 months + next 1 year
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

        // Create a predicate to fetch events from 6 MONTHS BACK to 1 YEAR AHEAD (READ-ONLY)
        // Include 6 months back to find recent historical events
        // Plus 1 year ahead for upcoming events
        let startDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let endDate = calendar.date(byAdding: .month, value: 12, to: currentMonthStart) ?? now

        // Get all calendars (nil = all calendars)
        let allCalendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: allCalendars)

        // ⚠️ READ-ONLY: eventStore.events(matching:) only reads, does not modify
        let allEvents = eventStore.events(matching: predicate)

        // Filter out all-day events and events that don't have a time component
        let timedEvents = allEvents.filter { !$0.isAllDay }

        return timedEvents
    }

    /// Fetch only new events (not previously synced)
    func fetchNewCalendarEvents() async -> [EKEvent] {
        let allEvents = await fetchCalendarEventsFromCurrentMonthOnwards()
        let syncedEventIDs = getSyncedEventIDs()

        // Filter out events we've already synced AND events from skipped months
        let calendar = Calendar.current

        let newEvents = allEvents.filter { event in
            let isAlreadySynced = syncedEventIDs.contains(event.eventIdentifier)

            // Check if event is in a skipped month
            let components = calendar.dateComponents([.year, .month], from: event.startDate)
            let isInSkippedMonth = isMonthSkipped(year: components.year ?? 0, month: components.month ?? 0)

            return !isAlreadySynced && !isInSkippedMonth
        }

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

        // Mark as calendar event (read-only, not saved to Supabase)
        taskItem.isFromCalendar = true

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
            // Check if interval is 2 (bi-weekly) or 1 (weekly)
            if firstRule.interval == 2 {
                return .biweekly
            } else {
                return .weekly
            }
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
        // Map event IDs and filter out any nils to ensure [String] type
        let newIDs = events.compactMap { $0.eventIdentifier }
        syncedIDs.append(contentsOf: newIDs)

        userDefaults.set(syncedIDs, forKey: syncedEventIDsKey)
        userDefaults.set(Date(), forKey: lastSyncDateKey)
    }

    /// Get the list of already-synced event IDs
    private func getSyncedEventIDs() -> [String] {
        return userDefaults.stringArray(forKey: syncedEventIDsKey) ?? []
    }

    /// Get the list of synced event IDs (public for cleanup)
    func getSyncedEventIDsPublic() -> [String] {
        return getSyncedEventIDs()
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

    /// Reset calendar sync completely (delete all tracking and request permission again)
    func resetCalendarSync() {
        clearSyncTracking()
        // Reset authorization status by clearing the event store
        // Note: This doesn't actually revoke permission, user must do that in Settings
        print("⚠️ To fully reset: Go to Settings > Seline > Calendars and toggle OFF, then ON")
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
