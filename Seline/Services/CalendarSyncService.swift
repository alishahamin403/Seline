import EventKit
import Foundation

/// CalendarSyncService: Synchronization of iPhone calendar events to Supabase
/// ⚠️ IMPORTANT: This service ONLY READS from the iPhone calendar.
/// It NEVER writes, modifies, or creates events in the iPhone calendar.
/// All synced events are saved to Supabase as tasks and can be marked complete.
class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    private let userDefaults = UserDefaults.standard
    private let preferences = CalendarSyncPreferences.load()

    // Key to track if we've already synced calendars on first launch
    private let lastSyncDateKey = "lastCalendarSyncDate"
    private let originalSyncDateKey = "originalCalendarSyncDate" // Date when user first synced (retain all events from this date)
    private let syncedEventIDsKey = "syncedCalendarEventIDs"
    private let monthsToSkipKey = "calendarSyncMonthsToSkip"
    private let syncWindowVersionKey = "calendarSyncWindowVersion"
    private let currentSyncWindowVersion = 3 // Increment when fetch window changes

    // Months to skip during sync: (year, month) tuples
    // Example: [(2026, 2)] skips February 2026
    private var monthsToSkip: Set<String> = []

    private init() {
        loadMonthsToSkip()
        handleSyncWindowMigration()
    }

    // MARK: - Sync Window Migration

    /// Handle migration when fetch window changes
    /// Clears old synced event IDs when the sync window version changes
    private func handleSyncWindowMigration() {
        let savedVersion = userDefaults.integer(forKey: syncWindowVersionKey)

        if savedVersion != currentSyncWindowVersion {
            print("🔄 Calendar sync window changed - clearing old sync tracking")
            clearSyncTracking()
            
            // Also widen the historical fetch window on migration.
            // If the original sync date is too recent, move it back so we can fetch last weeks/months.
            let calendar = Calendar.current
            let now = Date()
            let widenedStart = calendar.date(byAdding: .month, value: -3, to: now).map { calendar.startOfDay(for: $0) }
            if let widenedStart, let existingOriginalDate = getOriginalSyncDate(), existingOriginalDate > widenedStart {
                userDefaults.set(widenedStart, forKey: originalSyncDateKey)
                print("🔄 [CalendarSync] Updated original sync date back to: \(widenedStart)")
            }
            userDefaults.set(currentSyncWindowVersion, forKey: syncWindowVersionKey)
        }
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

    // MARK: - Calendar Discovery & Selection

    /// Fetch all available calendars from iPhone
    /// Returns calendars grouped by source type
    func fetchAvailableCalendars() async -> [CalendarMetadata] {
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            print("❌ Calendar access not granted")
            return []
        }

        let calendars = eventStore.calendars(for: .event)
        let metadata = calendars.map { $0.toMetadata() }

        print("📅 Found \(metadata.count) calendars:")
        for cal in metadata {
            print("  - \(cal.title) (\(cal.sourceDescription))")
        }

        return metadata
    }

    /// Get selected calendars from preferences
    func getSelectedCalendars() async -> [CalendarMetadata] {
        let allCalendars = await fetchAvailableCalendars()
        return allCalendars.filter { preferences.isSelected(calendarId: $0.id) }
    }

    /// Get calendar preferences
    func getPreferences() -> CalendarSyncPreferences {
        return preferences
    }

    /// Save calendar selection preferences
    func savePreferences(_ newPreferences: CalendarSyncPreferences) {
        newPreferences.save()
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

    /// Fetch calendar events from the original sync date onwards for the next 3 months
    /// This is a READ-ONLY operation - no modifications to the calendar
    /// Retains historical events from the original sync date (first time user syncs)
    /// Filters events to only include those from selected calendars
    /// - Parameter userEmail: Optional user email to filter events (backward compatibility, now deprecated in favor of calendar selection)
    /// - Returns: Array of calendar events from original sync date to next 3 months, filtered by selected calendars
    func fetchCalendarEventsFromCurrentMonthOnwards(userEmail: String? = nil) async -> [EKEvent] {
        // Get authorization first
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            print("❌ Calendar access not granted")
            return []
        }

        let calendar = Calendar.current
        let now = Date()

        // Get or set the original sync date (first time user synced)
        // If not set, default to a backfill window so "last week" works immediately.
        let originalSyncDate: Date
        if let existingOriginalDate = getOriginalSyncDate() {
            originalSyncDate = existingOriginalDate
        } else {
            // First time syncing - backfill 3 months for better history coverage
            originalSyncDate = calendar.date(byAdding: .month, value: -3, to: now).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
            setOriginalSyncDate(originalSyncDate)
            print("📅 [CalendarSync] First sync - setting original sync date to: \(originalSyncDate)")
        }

        // Create a predicate to fetch events from ORIGINAL SYNC DATE to 3 MONTHS AHEAD (READ-ONLY)
        // This ensures we retain all historical events from the first sync date
        let startDate = originalSyncDate
        let endDate = calendar.date(byAdding: .month, value: 3, to: now) ?? now

        // Get selected calendars from preferences
        let allCalendars = eventStore.calendars(for: .event)
        let selectedCalendarIds = preferences.selectedCalendarIds

        // Filter to only selected calendars
        let calendarsToSync: [EKCalendar]
        if selectedCalendarIds.isEmpty {
            // If no calendars selected, use backward compatible email filtering
            calendarsToSync = allCalendars
            print("⚠️ [CalendarSync] No calendars selected, using all calendars (backward compatibility)")
        } else {
            calendarsToSync = allCalendars.filter { selectedCalendarIds.contains($0.calendarIdentifier) }
            print("📅 [CalendarSync] Syncing from \(calendarsToSync.count) selected calendars:")
            for cal in calendarsToSync {
                print("  - \(cal.title) (\(cal.source.title))")
            }
        }

        guard !calendarsToSync.isEmpty else {
            print("⚠️ [CalendarSync] No calendars to sync")
            return []
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendarsToSync)

        // ⚠️ READ-ONLY: eventStore.events(matching:) only reads, does not modify
        let allEvents = eventStore.events(matching: predicate)

        // Apply email filter only if provided (backward compatibility)
        let filteredEvents: [EKEvent]
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty, selectedCalendarIds.isEmpty {
            filteredEvents = allEvents.filter { event in
                isEventAssociatedWithEmail(event: event, email: userEmail)
            }
            print("📅 [CalendarSync] Fetched \(allEvents.count) events, filtered to \(filteredEvents.count) events associated with \(userEmail)")
        } else {
            filteredEvents = allEvents
            print("📅 [CalendarSync] Fetched \(allEvents.count) events from \(startDate) to \(endDate)")
        }

        return filteredEvents
    }
    
    /// Check if a calendar event is associated with the given email address
    /// Checks organizer, attendees, and calendar source
    private func isEventAssociatedWithEmail(event: EKEvent, email: String) -> Bool {
        let lowerEmail = email.lowercased()
        
        // Check if user is the organizer
        if let organizer = event.organizer {
            let organizerURLString = organizer.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
            if organizerURLString == lowerEmail {
                return true
            }
        }
        
        // Check if user is in attendees list
        if let attendees = event.attendees {
            for attendee in attendees {
                let attendeeURLString = attendee.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
                if attendeeURLString == lowerEmail {
                    return true
                }
            }
        }
        
        // Check if the calendar source/title contains the email domain
        // This catches calendars like "user@gmail.com" or calendars synced from that email
        if let eventCalendar = event.calendar {
            let calendarTitle = eventCalendar.title.lowercased()
            if calendarTitle.contains(lowerEmail) {
                return true
            }
            
            // Check calendar source identifier (often contains email)
            if let source = eventCalendar.source {
                let sourceTitle = source.title.lowercased()
                if sourceTitle.contains(lowerEmail) {
                    return true
                }
            }
        }
        
        // If event has no organizer/attendees and calendar doesn't match, exclude it
        // This prevents syncing events from other people's calendars
        return false
    }
    
    // MARK: - Original Sync Date Management
    
    /// Get the original sync date (when user first synced calendar)
    /// This date determines how far back we fetch historical events
    private func getOriginalSyncDate() -> Date? {
        return userDefaults.object(forKey: originalSyncDateKey) as? Date
    }
    
    /// Set the original sync date (called on first sync)
    private func setOriginalSyncDate(_ date: Date) {
        userDefaults.set(date, forKey: originalSyncDateKey)
    }
    
    /// Get the original sync date (public access)
    func getOriginalSyncDatePublic() -> Date? {
        return getOriginalSyncDate()
    }

    /// Fetch only new events (not previously synced)
    /// - Parameter userEmail: Optional user email to filter events
    func fetchNewCalendarEvents(userEmail: String? = nil) async -> [EKEvent] {
        let allEvents = await fetchCalendarEventsFromCurrentMonthOnwards(userEmail: userEmail)
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

        // Create title
        let title = event.title ?? "Calendar Event"

        // Extract notes as description
        let description = event.notes

        // Get calendar metadata
        let eventCalendar = event.calendar
        let calendarTitle = eventCalendar?.title ?? "Unknown Calendar"
        let sourceType = eventCalendar?.source.sourceType
        let calendarSourceType = sourceType != nil ? CalendarSourceType.from(ekSourceType: sourceType!).rawValue : "Unknown"

        // Create the TaskItem as Personal (tagId: nil = Personal tag)
        var taskItem = TaskItem(
            title: title,
            weekday: weekday,
            description: description,
            // For all-day events, avoid showing as "12:00 AM". Represent as all-day by
            // leaving scheduledTime nil and using targetDate for the day.
            scheduledTime: event.isAllDay ? nil : startDate,
            endTime: endDate,
            targetDate: startDate,
            reminderTime: .none, // Let user set their own reminders
            location: event.location, // Map location directly
            isRecurring: event.hasRecurrenceRules,
            recurrenceFrequency: convertEKRecurrenceToFrequency(event.recurrenceRules)
        )

        // Mark as Personal - tagId: nil means default Personal category
        taskItem.tagId = nil

        // Mark as calendar event (now saved to Supabase)
        taskItem.isFromCalendar = true

        // Store calendar metadata
        taskItem.calendarEventId = event.eventIdentifier
        taskItem.calendarIdentifier = eventCalendar?.calendarIdentifier
        taskItem.calendarTitle = calendarTitle
        taskItem.calendarSourceType = calendarSourceType

        // Store a unique ID for this occurrence
        // For recurring events, EventKit returns multiple instances with the SAME eventIdentifier
        // We need to make each occurrence unique by including the start date
        let occurrenceTimestamp = Int(startDate.timeIntervalSince1970)
        taskItem.id = "cal_\(event.eventIdentifier)_\(occurrenceTimestamp)"

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
    /// Note: This does NOT clear the original sync date - we want to retain historical events
    func clearSyncTracking() {
        userDefaults.removeObject(forKey: syncedEventIDsKey)
        userDefaults.removeObject(forKey: lastSyncDateKey)
        // Do NOT clear originalSyncDateKey - we want to keep fetching from the original date
    }
    
    /// Clear the original sync date (use with caution - this will affect historical event fetching)
    func clearOriginalSyncDate() {
        userDefaults.removeObject(forKey: originalSyncDateKey)
    }

    /// Reset calendar sync completely (delete all tracking and request permission again)
    func resetCalendarSync() {
        clearSyncTracking()
        // Reset authorization status by clearing the event store
        // Note: This doesn't actually revoke permission, user must do that in Settings
        print("⚠️ To fully reset: Go to Settings > Seline > Calendars and toggle OFF, then ON")
    }
    
    /// Manual resync: Clear all synced event IDs and force a fresh sync
    /// This will re-sync all events (filtered by user email if provided)
    /// - Parameter userEmail: Optional user email to filter events during resync
    func manualResync(userEmail: String? = nil) {
        print("🔄 [CalendarSync] Manual resync triggered (userEmail: \(userEmail ?? "none"))")
        clearSyncTracking()
        // Note: The actual sync will happen when syncCalendarEvents() is called next
        // This just clears the tracking so all events are treated as new
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
