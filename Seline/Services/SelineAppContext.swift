import Foundation

/// Simple data context for LLM - collects all app data without pre-filtering
/// The LLM will handle filtering, reasoning, and natural language understanding
@MainActor
class SelineAppContext {
    // MARK: - Core Data

    private let taskManager: TaskManager
    private let tagManager: TagManager
    private let notesManager: NotesManager
    private let emailService: EmailService
    private let weatherService: WeatherService
    private let locationsManager: LocationsManager
    private let navigationService: NavigationService
    private let categorizationService: ReceiptCategorizationService

    // MARK: - Cached Data

    private(set) var events: [TaskItem] = []
    private(set) var receipts: [ReceiptStat] = []
    private(set) var notes: [Note] = []
    private(set) var emails: [Email] = []
    private(set) var customEmailFolders: [CustomEmailFolder] = []
    private(set) var savedEmailsByFolder: [UUID: [SavedEmail]] = [:]
    private(set) var locations: [SavedPlace] = []
    private(set) var currentDate: Date = Date()

    init(
        taskManager: TaskManager = TaskManager.shared,
        tagManager: TagManager = TagManager.shared,
        notesManager: NotesManager = NotesManager.shared,
        emailService: EmailService = EmailService.shared,
        weatherService: WeatherService = WeatherService.shared,
        locationsManager: LocationsManager = LocationsManager.shared,
        navigationService: NavigationService = NavigationService.shared,
        categorizationService: ReceiptCategorizationService = ReceiptCategorizationService.shared
    ) {
        self.taskManager = taskManager
        self.tagManager = tagManager
        self.notesManager = notesManager
        self.emailService = emailService
        self.weatherService = weatherService
        self.locationsManager = locationsManager
        self.navigationService = navigationService
        self.categorizationService = categorizationService

        // Note: refresh() is called asynchronously in buildContextPrompt()
        // to fetch custom email folders and saved emails
    }

    // MARK: - Data Collection

    /// Refresh all app data (call this at start of each conversation)
    func refresh() async {
        print("🔄 SelineAppContext.refresh() called")
        self.currentDate = Date()

        // Collect all events
        self.events = taskManager.tasks.values.flatMap { $0 }

        // Collect custom email folders and their saved emails
        do {
            self.customEmailFolders = try await emailService.fetchSavedFolders()
            print("📧 Found \(self.customEmailFolders.count) custom email folders")

            // Load emails for each folder
            for folder in self.customEmailFolders {
                do {
                    let savedEmails = try await emailService.fetchSavedEmails(in: folder.id)
                    self.savedEmailsByFolder[folder.id] = savedEmails
                    print("  • \(folder.name): \(savedEmails.count) emails")
                } catch {
                    print("  ⚠️  Error loading emails for folder '\(folder.name)': \(error)")
                    self.savedEmailsByFolder[folder.id] = []
                }
            }
        } catch {
            print("⚠️  Error loading custom email folders: \(error)")
        }

        // Debug: Log recurring events and their next occurrence
        let recurringEvents = self.events.filter { $0.isRecurring }
        if !recurringEvents.isEmpty {
            print("🔁 Recurring events found: \(recurringEvents.count)")
            for event in recurringEvents {
                let frequency = event.recurrenceFrequency?.rawValue ?? "?"
                let anchorDate = event.targetDate ?? event.createdAt
                let nextDate = getNextOccurrenceDate(for: event)

                print("   • \(event.title)")
                print("     Frequency: \(frequency)")
                print("     Anchor date: \(formatDate(anchorDate))")
                print("     Recurrence end: \(event.recurrenceEndDate.map { formatDate($0) } ?? "None")")

                if let nextDate = nextDate {
                    let isTomorrow = Calendar.current.isDateInTomorrow(nextDate)
                    let isToday = Calendar.current.isDateInToday(nextDate)
                    print("     Next occurrence: \(formatDate(nextDate))\(isTomorrow ? " (TOMORROW)" : "")\(isToday ? " (TODAY)" : "")")
                } else {
                    print("     Next occurrence: NONE (ended or invalid)")
                }
            }
        }

        // Collect all receipts from notes
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
        print("📂 Receipts folder ID: \(receiptsFolderId)")

        let receiptNotes = notesManager.notes.filter { note in
            isUnderReceiptsFolderHierarchy(folderId: note.folderId, receiptsFolderId: receiptsFolderId)
        }
        print("📝 Found \(receiptNotes.count) receipt notes in folder")

        // Extract transaction dates from receipt notes
        self.receipts = receiptNotes.compactMap { note -> ReceiptStat? in
            // Extract date from note title - that's the transaction date
            guard let transactionDate = extractDateFromTitle(note.title) else {
                // Skip receipts where we can't extract a date from the title
                // This prevents fallback to dateModified which could be from wrong month
                print("⚠️  Skipping receipt with no extractable date: \(note.title)")
                return nil
            }

            return ReceiptStat(from: note, date: transactionDate, category: "Other")
        }
        print("✅ Extracted \(self.receipts.count) receipts with valid dates")

        // Collect all notes
        self.notes = notesManager.notes

        // Collect all emails
        self.emails = emailService.inboxEmails + emailService.sentEmails

        // Collect all locations
        self.locations = locationsManager.savedPlaces

        print("📦 AppContext refreshed:")
        print("   Current date: \(formatDate(currentDate))")
        print("   Events: \(events.count)")
        print("   Receipts: \(receipts.count)")

        if !receipts.isEmpty {
            // Calculate current month range
            let calendar = Calendar.current
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate

            // Show current month receipts only
            let thisMonthReceipts = receipts.filter { $0.date >= startOfMonth && $0.date <= currentDate }
            let thisMonthTotal = thisMonthReceipts.reduce(0.0) { $0 + $1.amount }

            print("     THIS MONTH (Nov 1 - Nov 12): \(thisMonthReceipts.count) receipts, Total: $\(String(format: "%.2f", thisMonthTotal))")

            // Show ALL receipts counted as this month for verification
            print("     --- ALL NOVEMBER RECEIPTS ---")
            for receipt in thisMonthReceipts.sorted(by: { $0.date < $1.date }) {
                print("     • \(formatDate(receipt.date)): \(receipt.title) - $\(String(format: "%.2f", receipt.amount))")
            }
            print("     --- END ---")
        }
        print("   Notes: \(notes.count)")
        print("   Emails: \(emails.count)")
        print("   Locations: \(locations.count)")
    }

    // MARK: - Context Building for LLM

    /// Build a rich context string for the LLM with all app data
    // MARK: - Query Intent Extraction

    /// Extracts category/tag names from a user query
    private func extractCategoryFilter(from query: String) -> String? {
        let lowercaseQuery = query.lowercased()

        // Get all tags and check if any match the query
        for tag in tagManager.tags {
            if lowercaseQuery.contains(tag.name.lowercased()) {
                return tag.id
            }
        }

        return nil
    }

    /// Extracts time period from a user query
    private func extractTimePeriodFilter(from query: String) -> (startDate: Date, endDate: Date)? {
        let calendar = Calendar.current
        let lowercaseQuery = query.lowercased()

        if lowercaseQuery.contains("last week") || lowercaseQuery.contains("past week") {
            let endDate = currentDate
            let startDate = calendar.date(byAdding: .day, value: -7, to: currentDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("this week") {
            let startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate)) ?? currentDate
            let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("yesterday") {
            let endDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            let startDate = calendar.startOfDay(for: endDate)
            return (startDate, calendar.date(byAdding: .second, value: -1, to: calendar.startOfDay(for: currentDate)) ?? endDate)
        } else if lowercaseQuery.contains("today") {
            let startDate = calendar.startOfDay(for: currentDate)
            let endDate = currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("this month") {
            let startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate
            let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("last month") {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
            let startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: previousMonth)) ?? previousMonth
            let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? currentDate
            return (startDate, endDate)
        }

        return nil
    }

    /// Build context with intelligent filtering based on user query
    func buildContextPrompt(forQuery userQuery: String) async -> String {
        // Extract intent from the query
        let categoryFilter = extractCategoryFilter(from: userQuery)
        let timePeriodFilter = extractTimePeriodFilter(from: userQuery)

        // Refresh all data
        await refresh()

        // Filter events based on extracted intent
        var filteredEvents = events

        // Apply category filter if detected
        if let categoryId = categoryFilter {
            filteredEvents = filteredEvents.filter { $0.tagId == categoryId }
        }

        // Apply time period filter if detected
        if let timePeriod = timePeriodFilter {
            filteredEvents = filteredEvents.filter { event in
                let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate
                return eventDate >= timePeriod.startDate && eventDate <= timePeriod.endDate
            }
        }

        // Temporarily replace events with filtered version
        let originalEvents = self.events
        self.events = filteredEvents

        // Build context with filtered events (skip refresh since we just did it)
        var context = ""

        // Current date context
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        context += "=== CURRENT DATE ===\n"
        context += dateFormatter.string(from: currentDate) + "\n\n"

        // Data summary
        context += "=== DATA SUMMARY ===\n"
        context += "Total Events: \(events.count)\n"
        context += "Total Receipts: \(receipts.count)\n"
        context += "Total Notes: \(notes.count)\n"
        context += "Total Emails: \(emails.count)\n"
        context += "Total Locations: \(locations.count)\n\n"

        // Build events section from buildContextPromptInternal but without refresh
        let calendar = Calendar.current

        // Organize events by temporal proximity
        var today: [TaskItem] = []
        var tomorrow: [TaskItem] = []
        var thisWeek: [TaskItem] = []
        var upcoming: [TaskItem] = []
        var past: [TaskItem] = []

        for event in events {
            if event.isRecurring {
                let todayDate = currentDate
                let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                let dayAfterTomorrowDate = calendar.date(byAdding: .day, value: 2, to: currentDate)!

                if shouldEventOccurOn(event, date: todayDate) {
                    today.append(event)
                }

                if shouldEventOccurOn(event, date: tomorrowDate) {
                    tomorrow.append(event)
                }

                if shouldEventOccurOn(event, date: dayAfterTomorrowDate) {
                    thisWeek.append(event)
                } else {
                    var hasUpcomingOccurrence = false
                    for daysAhead in 3...7 {
                        if let checkDate = calendar.date(byAdding: .day, value: daysAhead, to: currentDate),
                           shouldEventOccurOn(event, date: checkDate) {
                            thisWeek.append(event)
                            hasUpcomingOccurrence = true
                            break
                        }
                    }

                    if !hasUpcomingOccurrence {
                        if let nextDate = getNextOccurrenceDate(for: event, after: calendar.date(byAdding: .day, value: 7, to: currentDate)!) {
                            upcoming.append(event)
                        }
                    }
                }
            } else {
                let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate

                if calendar.isDateInToday(eventDate) {
                    today.append(event)
                } else if calendar.isDateInTomorrow(eventDate) {
                    tomorrow.append(event)
                } else if calendar.isDate(eventDate, inSameDayAs: currentDate.addingTimeInterval(2*24*3600)) {
                    thisWeek.append(event)
                } else if eventDate > currentDate {
                    upcoming.append(event)
                } else {
                    past.append(event)
                }
            }
        }

        context += "=== EVENTS & CALENDAR ===\n"
        if !events.isEmpty {
            // TODAY
            if !today.isEmpty {
                context += "\n**TODAY** (\(today.count) events):\n"
                for event in today.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // TOMORROW
            if !tomorrow.isEmpty {
                context += "\n**TOMORROW** (\(tomorrow.count) events):\n"
                for event in tomorrow.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // THIS WEEK (next 3-7 days)
            if !thisWeek.isEmpty {
                context += "\n**THIS WEEK** (\(thisWeek.count) events):\n"
                for event in thisWeek.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week)
            if !upcoming.isEmpty {
                context += "\n**UPCOMING** (\(upcoming.count) events):\n"
                for event in upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
                }
            }

            // LAST WEEK EVENTS
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: currentDate)!
            let lastWeekEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate >= sevenDaysAgo && eventDate < currentDate
            }
            if !lastWeekEvents.isEmpty {
                context += "\n**LAST WEEK** (\(lastWeekEvents.count) events):\n"
                for event in lastWeekEvents.sorted(by: { ($0.targetDate ?? $0.completedDate ?? Date.distantPast) > ($1.targetDate ?? $1.completedDate ?? Date.distantPast) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
            }

            // OLDER PAST EVENTS
            let olderPastEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate < sevenDaysAgo
            }
            if !olderPastEvents.isEmpty {
                context += "\n**PAST EVENTS** (older than 1 week, showing last 5):\n"
                for event in olderPastEvents.suffix(5).reversed() {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
                if olderPastEvents.count > 5 {
                    context += "  ... and \(olderPastEvents.count - 5) more older past events\n"
                }
            }
        } else {
            context += "  No events\n"
        }

        // Restore original events
        self.events = originalEvents

        // Note: For brevity, not including receipts/notes/emails sections in filtered query response
        // Those would be added similarly if needed

        return context
    }

    func buildContextPrompt() async -> String {
        return await buildContextPromptInternal()
    }

    private func buildContextPromptInternal() async -> String {
        // Refresh all data including custom email folders
        await refresh()

        var context = ""

        // Current date context
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        context += "=== CURRENT DATE ===\n"
        context += dateFormatter.string(from: currentDate) + "\n\n"

        // Data summary
        context += "=== DATA SUMMARY ===\n"
        context += "Total Events: \(events.count)\n"
        context += "Total Receipts: \(receipts.count)\n"
        context += "Total Notes: \(notes.count)\n"
        context += "Total Emails: \(emails.count)\n"
        context += "Total Locations: \(locations.count)\n\n"

        // Events detail - Comprehensive with categories, temporal organization, and all-day status
        context += "=== EVENTS & CALENDAR ===\n"
        if !events.isEmpty {
            let calendar = Calendar.current

            // Organize events by temporal proximity
            var today: [TaskItem] = []
            var tomorrow: [TaskItem] = []
            var thisWeek: [TaskItem] = []
            var upcoming: [TaskItem] = []
            var past: [TaskItem] = []

            for event in events {
                if event.isRecurring {
                    // For recurring events, check which sections they appear in
                    // A daily event might appear in Today, Tomorrow, AND This Week, etc.

                    let todayDate = currentDate
                    let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                    let dayAfterTomorrowDate = calendar.date(byAdding: .day, value: 2, to: currentDate)!

                    if shouldEventOccurOn(event, date: todayDate) {
                        today.append(event)
                    }

                    if shouldEventOccurOn(event, date: tomorrowDate) {
                        tomorrow.append(event)
                    }

                    if shouldEventOccurOn(event, date: dayAfterTomorrowDate) {
                        thisWeek.append(event)
                    } else {
                        // If it doesn't occur in the next 2 days, check if it occurs within the week
                        var hasUpcomingOccurrence = false
                        for daysAhead in 3...7 {
                            if let checkDate = calendar.date(byAdding: .day, value: daysAhead, to: currentDate),
                               shouldEventOccurOn(event, date: checkDate) {
                                thisWeek.append(event)
                                hasUpcomingOccurrence = true
                                break
                            }
                        }

                        // If still no occurrence found, check further ahead
                        if !hasUpcomingOccurrence {
                            if let nextDate = getNextOccurrenceDate(for: event, after: calendar.date(byAdding: .day, value: 7, to: currentDate)!) {
                                upcoming.append(event)
                            }
                        }
                    }
                } else {
                    // For non-recurring events, use the original date logic
                    let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate

                    if calendar.isDateInToday(eventDate) {
                        today.append(event)
                    } else if calendar.isDateInTomorrow(eventDate) {
                        tomorrow.append(event)
                    } else if calendar.isDate(eventDate, inSameDayAs: currentDate.addingTimeInterval(2*24*3600)) {
                        thisWeek.append(event)
                    } else if eventDate > currentDate {
                        upcoming.append(event)
                    } else {
                        past.append(event)
                    }
                }
            }

            // TODAY
            if !today.isEmpty {
                context += "\n**TODAY** (\(today.count) events):\n"
                for event in today.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // TOMORROW
            if !tomorrow.isEmpty {
                context += "\n**TOMORROW** (\(tomorrow.count) events):\n"
                for event in tomorrow.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // THIS WEEK (next 3-7 days)
            if !thisWeek.isEmpty {
                context += "\n**THIS WEEK** (\(thisWeek.count) events):\n"
                for event in thisWeek.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week)
            if !upcoming.isEmpty {
                context += "\n**UPCOMING** (\(upcoming.count) events):\n"
                for event in upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
                }
            }

            // RECURRING EVENTS SUMMARY with monthly/yearly stats
            let recurringEvents = events.filter { $0.isRecurring }
            if !recurringEvents.isEmpty {
                context += "\n**RECURRING EVENTS SUMMARY** (\(recurringEvents.count) recurring):\n"
                for event in recurringEvents {
                    let currentMonth = calendar.dateComponents([.month, .year], from: currentDate)

                    let thisMonthCompletions = event.completedDates.filter { date in
                        let dateComponents = calendar.dateComponents([.month, .year], from: date)
                        return dateComponents.month == currentMonth.month && dateComponents.year == currentMonth.year
                    }

                    let categoryName = getCategoryName(for: event.tagId)
                    context += "  • \(event.title) [\(categoryName)]\n"
                    context += "    All-time: \(event.completedDates.count) completions\n"
                    context += "    This month: \(thisMonthCompletions.count) completions\n"

                    // Monthly breakdown
                    let monthlyStats = Dictionary(grouping: event.completedDates) { date in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMMM yyyy"
                        return formatter.string(from: date)
                    }

                    if !monthlyStats.isEmpty {
                        // Sort months by date (most recent first)
                        let sortedMonths = monthlyStats.keys.sorted { month1, month2 in
                            // Create dummy dates from the month strings for comparison
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MMMM yyyy"
                            let date1 = formatter.date(from: month1) ?? Date.distantPast
                            let date2 = formatter.date(from: month2) ?? Date.distantPast
                            return date1 > date2
                        }

                        context += "    Monthly stats:\n"
                        for month in sortedMonths.prefix(6) {
                            let count = monthlyStats[month]?.count ?? 0
                            context += "      \(month): \(count) completions\n"
                        }
                    }

                    if !thisMonthCompletions.isEmpty {
                        let dateStrings = thisMonthCompletions.sorted().map { formatDate($0) }
                        context += "    Dates completed this month: \(dateStrings.joined(separator: ", "))\n"
                    } else {
                        context += "    No completions this month\n"
                    }
                }
            }

            // LAST WEEK EVENTS
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: currentDate)!
            let lastWeekEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate >= sevenDaysAgo && eventDate < currentDate
            }
            if !lastWeekEvents.isEmpty {
                context += "\n**LAST WEEK** (\(lastWeekEvents.count) events):\n"
                for event in lastWeekEvents.sorted(by: { ($0.targetDate ?? $0.completedDate ?? Date.distantPast) > ($1.targetDate ?? $1.completedDate ?? Date.distantPast) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
            }

            // OLDER PAST EVENTS
            let olderPastEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate < sevenDaysAgo
            }
            if !olderPastEvents.isEmpty {
                context += "\n**PAST EVENTS** (older than 1 week, showing last 5):\n"
                for event in olderPastEvents.suffix(5).reversed() {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
                if olderPastEvents.count > 5 {
                    context += "  ... and \(olderPastEvents.count - 5) more older past events\n"
                }
            }
        } else {
            context += "  No events\n"
        }

        // Receipts detail - Group all receipts by month and show with real categorization
        context += "\n=== RECEIPTS & EXPENSES ===\n"
        if !receipts.isEmpty {
            // Group all receipts by month dynamically
            let receiptsByMonth = Dictionary(grouping: receipts) { receipt in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: receipt.date)
            }

            // Get current month for detection
            let calendar = Calendar.current
            let currentMonthFormatter = DateFormatter()
            currentMonthFormatter.dateFormat = "MMMM yyyy"
            let currentMonthStr = currentMonthFormatter.string(from: currentDate)

            // Sort months: current month first, then others by recency
            let sortedMonths = receiptsByMonth.keys.sorted { month1, month2 in
                if month1 == currentMonthStr { return true }
                if month2 == currentMonthStr { return false }
                return month1 > month2  // Most recent first
            }

            for (index, month) in sortedMonths.prefix(7).enumerated() {
                guard let items = receiptsByMonth[month] else { continue }

                let total = items.reduce(0.0) { $0 + $1.amount }
                let isCurrentMonth = (month == currentMonthStr)

                context += "\n**\(month)**\(isCurrentMonth ? " (Current Month)" : ""): \(items.count) receipts, Total: $\(String(format: "%.2f", total))\n"

                // Get real category breakdown for this month using ReceiptCategorizationService
                let categoryBreakdown = await categorizationService.getCategoryBreakdown(for: items)

                // Show categories and amounts
                for (category, receiptsInCategory) in categoryBreakdown.categoryReceipts.sorted(by: { $0.key < $1.key }) {
                    let categoryTotal = receiptsInCategory.reduce(0.0) { $0 + $1.amount }
                    context += "  **\(category)**: $\(String(format: "%.2f", categoryTotal)) (\(receiptsInCategory.count) items)\n"

                    // Show all items for current month, summary for previous months
                    if isCurrentMonth {
                        for receipt in receiptsInCategory.sorted(by: { $0.date > $1.date }) {
                            context += "    • \(receipt.title): $\(String(format: "%.2f", receipt.amount)) - \(formatDate(receipt.date))\n"
                        }
                    }
                }
            }
        } else {
            context += "  No receipts\n"
        }

        // Emails detail - Comprehensive with folder organization, metadata, and full content
        context += "\n=== EMAILS & MESSAGES ===\n"
        if !emails.isEmpty {
            // Group emails by labels (folders)
            let emailsByFolder = Dictionary(grouping: emails) { email in
                // Use labels to determine folder, default to "Inbox"
                if email.labels.contains("SENT") {
                    return "Sent"
                } else if email.labels.contains("DRAFT") {
                    return "Drafts"
                } else if email.labels.contains("ARCHIVED") {
                    return "Archive"
                } else if email.labels.contains("IMPORTANT") {
                    return "Important"
                } else if email.labels.contains("STARRED") {
                    return "Starred"
                } else {
                    return "Inbox"
                }
            }

            // Sort folders with Inbox first
            let sortedFolders = emailsByFolder.keys.sorted { folder1, folder2 in
                if folder1 == "Inbox" { return true }
                if folder2 == "Inbox" { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderEmails = emailsByFolder[folder] else { continue }

                context += "\n**\(folder)** (\(folderEmails.count) emails):\n"

                // Show most recent emails first, max 20 per folder
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

                    let senderDisplay = email.sender.displayName
                    let recipientDisplay = email.recipients.map { $0.displayName }.joined(separator: ", ")

                    context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                    // Add email metadata
                    context += "    Status: \(email.isRead ? "Read" : "Unread")\(email.isImportant ? ", Important" : "")\n"

                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    AI Summary: \(aiSummary)\n"
                    }

                    // Add full email body/content
                    if let body = email.body, !body.isEmpty {
                        context += "    Content:\n"
                        let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                        for line in bodyLines.prefix(50) {  // Show up to 50 lines of email content
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                context += "      \(trimmedLine)\n"
                            }
                        }
                        if bodyLines.count > 50 {
                            context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                        }
                    }

                    // Add attachments if present
                    if email.hasAttachments && !email.attachments.isEmpty {
                        context += "    Attachments: \(email.attachments.map { $0.name }.joined(separator: ", "))\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 20 {
                    context += "  ... and \(folderEmails.count - 20) more emails in this folder\n"
                }
            }

            context += "**Total Standard Folders Emails**: \(emails.count)\n"

            // CUSTOM EMAIL FOLDERS
            if !customEmailFolders.isEmpty {
                context += "\n**CUSTOM EMAIL FOLDERS** (\(customEmailFolders.count) folders):\n"

                for folder in customEmailFolders {
                    guard let folderEmails = savedEmailsByFolder[folder.id], !folderEmails.isEmpty else {
                        context += "\n**\(folder.name)** (0 emails)\n"
                        continue
                    }

                    context += "\n**\(folder.name)** (\(folderEmails.count) emails):\n"

                    // Show most recent emails first, max 15 per custom folder
                    for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(15) {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateStyle = .medium
                        dateFormatter.timeStyle = .short
                        let formattedDate = dateFormatter.string(from: email.timestamp)

                        let senderDisplay = email.senderName ?? email.senderEmail
                        let recipientDisplay = email.recipients.joined(separator: ", ")

                        context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                        // Add email metadata
                        if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                            context += "    AI Summary: \(aiSummary)\n"
                        }

                        // Add full email body/content
                        if let body = email.body, !body.isEmpty {
                            context += "    Content:\n"
                            let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                            for line in bodyLines.prefix(50) {  // Show up to 50 lines of email content
                                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                if !trimmedLine.isEmpty {
                                    context += "      \(trimmedLine)\n"
                                }
                            }
                            if bodyLines.count > 50 {
                                context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                            }
                        }

                        // Add attachments if present
                        if !email.attachments.isEmpty {
                            context += "    Attachments: \(email.attachments.map { $0.fileName }.joined(separator: ", "))\n"
                        }

                        context += "\n"
                    }

                    if folderEmails.count > 15 {
                        context += "  ... and \(folderEmails.count - 15) more emails in this folder\n"
                    }
                }
            }

            let totalEmails = emails.count + (savedEmailsByFolder.values.reduce(0) { $0 + $1.count })
            context += "\n**Total Emails**: \(totalEmails)\n"
        } else if !customEmailFolders.isEmpty {
            // Show custom folders even if no standard emails
            context += "\n**CUSTOM EMAIL FOLDERS** (\(customEmailFolders.count) folders):\n"

            for folder in customEmailFolders {
                guard let folderEmails = savedEmailsByFolder[folder.id] else {
                    context += "\n**\(folder.name)** (0 emails)\n"
                    continue
                }

                context += "\n**\(folder.name)** (\(folderEmails.count) emails):\n"

                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(15) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

                    let senderDisplay = email.senderName ?? email.senderEmail
                    let recipientDisplay = email.recipients.joined(separator: ", ")

                    context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    AI Summary: \(aiSummary)\n"
                    }

                    if let body = email.body, !body.isEmpty {
                        context += "    Content:\n"
                        let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                        for line in bodyLines.prefix(50) {
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                context += "      \(trimmedLine)\n"
                            }
                        }
                        if bodyLines.count > 50 {
                            context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                        }
                    }

                    if !email.attachments.isEmpty {
                        context += "    Attachments: \(email.attachments.map { $0.fileName }.joined(separator: ", "))\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 15 {
                    context += "  ... and \(folderEmails.count - 15) more emails in this folder\n"
                }
            }

            context += "\n**Total Custom Emails**: \(savedEmailsByFolder.values.reduce(0) { $0 + $1.count })\n"
        } else {
            context += "  No emails or custom folders\n"
        }

        // Notes detail - Comprehensive with folder, dates, and full content
        context += "\n=== NOTES ===\n"
        if !notes.isEmpty {
            // Group notes by folder
            let notesByFolder = Dictionary(grouping: notes) { note in
                notesManager.getFolderName(for: note.folderId)
            }

            // Sort folders with "Receipts" last (since it's for receipts, not general notes)
            let sortedFolders = notesByFolder.keys.sorted { folder1, folder2 in
                if folder1.lowercased().contains("receipt") { return false }
                if folder2.lowercased().contains("receipt") { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderNotes = notesByFolder[folder] else { continue }

                // Skip Receipts folder - already shown in expenses section
                if folder.lowercased().contains("receipt") {
                    continue
                }

                let folderLabel = folder == "Notes" ? "**Uncategorized Notes**" : "**\(folder)**"
                context += "\n\(folderLabel) (\(folderNotes.count) notes):\n"

                // Show most recently modified notes first, max 15 per folder
                for note in folderNotes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(15) {
                    let lastModified = formatDate(note.dateModified)
                    context += "  • **\(note.title)** (Updated: \(lastModified))\n"
                    context += "    Content:\n"

                    // Include full note content, formatted nicely
                    let contentLines = note.content.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                    let lineLimit = 1000  // Show up to 1000 lines per note (covers long statements and detailed notes)

                    for line in contentLines.prefix(lineLimit) {
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                        if !trimmedLine.isEmpty {
                            context += "    \(trimmedLine)\n"
                        }
                    }

                    if contentLines.count > lineLimit {
                        context += "    ... (note continues - \(contentLines.count - lineLimit) more lines)\n"
                    }
                    context += "\n"
                }

                if folderNotes.count > 15 {
                    context += "  ... and \(folderNotes.count - 15) more notes in this folder\n"
                }
            }

            let totalNotes = notes.count
            context += "\n**Total Notes**: \(totalNotes)\n"
        } else {
            context += "  No notes\n"
        }

        // Locations detail
        context += "\n=== LOCATIONS ===\n"
        if !locations.isEmpty {
            for location in locations.prefix(15) {
                let rating = location.userRating.map { "⭐ \($0)/10" } ?? "No rating"
                context += "  • \(location.displayName) - \(location.address) (\(rating))\n"
            }
            if locations.count > 15 {
                context += "  ... and \(locations.count - 15) more locations\n"
            }
        } else {
            context += "  No saved locations\n"
        }

        context += "\n"
        return context
    }

    /// Build detailed context with full data (send when needed)
    func buildDetailedDataContext() -> String {
        var context = ""

        // Full events JSON
        context += "=== COMPLETE EVENTS DATA ===\n"
        let eventData = events.map { event -> [String: Any] in
            [
                "id": event.id,
                "title": event.title,
                "targetDate": event.targetDate.map { formatDate($0) } ?? NSNull(),
                "isCompleted": event.isCompleted,
                "completedDates": event.completedDates.map { formatDate($0) },
                "isRecurring": event.isRecurring,
                "description": event.description ?? ""
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: eventData, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            context += jsonString + "\n\n"
        }

        // Full receipts JSON
        context += "=== COMPLETE RECEIPTS DATA ===\n"
        let receiptData = receipts.map { receipt -> [String: Any] in
            [
                "id": receipt.id.uuidString,
                "title": receipt.title,
                "amount": receipt.amount,
                "date": formatDate(receipt.date),
                "category": receipt.category
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: receiptData, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            context += jsonString + "\n\n"
        }

        return context
    }

    // MARK: - Helper Methods

    private func isUnderReceiptsFolderHierarchy(folderId: UUID?, receiptsFolderId: UUID) -> Bool {
        guard let folderId = folderId else { return false }

        if folderId == receiptsFolderId {
            return true
        }

        if let folder = notesManager.folders.first(where: { $0.id == folderId }),
           let parentId = folder.parentFolderId {
            return isUnderReceiptsFolderHierarchy(folderId: parentId, receiptsFolderId: receiptsFolderId)
        }

        return false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// Extract date from receipt note title
    /// The title contains the transaction date like "Mazaj Lounge - October 31, 2025"
    /// Searches for date patterns within the title, not the whole title as a date
    private func extractDateFromTitle(_ title: String) -> Date? {
        // Look for date pattern: "Month DD, YYYY" or "Month DD YYYY" within the title
        // Example: "Mazaj Lounge - October 31, 2025" → extract "October 31, 2025"

        let dateFormatter = DateFormatter()

        // Split by common separators and check each part for a date
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "-–—•"))

        for part in parts {
            let trimmedPart = part.trimmingCharacters(in: .whitespaces)

            // Try each date format on this part
            let formats = [
                "MMMM dd, yyyy",   // October 31, 2025
                "MMMM d, yyyy",    // October 1, 2025
                "MMMM dd yyyy",    // October 31 2025
                "MMMM d yyyy",     // October 1 2025
                "MMM dd, yyyy",    // Oct 31, 2025
                "MMM d, yyyy",     // Oct 1, 2025
                "MMM dd yyyy",     // Oct 31 2025
                "MMM d yyyy",      // Oct 1 2025
            ]

            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: trimmedPart) {
                    return date
                }
            }
        }

        // If no date found, return nil and let ReceiptStat use dateModified as fallback
        return nil
    }

    /// Get the category name for an event given its tagId
    private func getCategoryName(for tagId: String?) -> String {
        guard let tagId = tagId else { return "Personal" }
        return tagManager.getTag(by: tagId)?.name ?? "Personal"
    }

    /// Get formatted time info for an event
    private func getTimeInfo(_ event: TaskItem, isAllDay: Bool) -> String {
        if isAllDay {
            return "[All-day]"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if let start = event.scheduledTime, let end = event.endTime {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = event.scheduledTime {
            return formatter.string(from: start)
        }

        return ""
    }

    /// Check if a recurring event occurs on a specific date
    private func shouldEventOccurOn(_ event: TaskItem, date: Date) -> Bool {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return false }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, date > endDate {
            return false
        }

        // Check if event has started
        if date < anchorDate {
            return false
        }

        // Check frequency
        switch frequency {
        case .daily:
            // Daily events occur every day after the anchor date
            return date >= anchorDate

        case .weekly:
            // Weekly events occur on the same day of week
            let targetWeekday = calendar.component(.weekday, from: anchorDate)
            let dateWeekday = calendar.component(.weekday, from: date)
            return targetWeekday == dateWeekday

        case .biweekly:
            // Biweekly events occur every 2 weeks from anchor date
            let daysDifference = calendar.dateComponents([.day], from: anchorDate, to: date).day ?? 0
            return daysDifference >= 0 && daysDifference % 14 == 0

        case .monthly:
            // Monthly events occur on the same day of month
            let targetDay = calendar.component(.day, from: anchorDate)
            let dateDay = calendar.component(.day, from: date)
            return targetDay == dateDay

        case .yearly:
            // Yearly events occur on the same month and day
            let targetMonth = calendar.component(.month, from: anchorDate)
            let targetDay = calendar.component(.day, from: anchorDate)
            let dateMonth = calendar.component(.month, from: date)
            let dateDay = calendar.component(.day, from: date)
            return targetMonth == dateMonth && targetDay == dateDay
        }
    }

    /// Determine the next occurrence date for a recurring event after a given date
    private func getNextOccurrenceDate(for event: TaskItem, after minimumDate: Date = Date.distantPast) -> Date? {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return nil }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt
        let startDate = minimumDate > anchorDate ? minimumDate : anchorDate

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, startDate > endDate {
            return nil
        }

        // Search for the next occurrence in the next year
        var searchDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let searchLimit = calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate

        while searchDate <= searchLimit {
            if shouldEventOccurOn(event, date: searchDate) {
                return searchDate
            }
            searchDate = calendar.date(byAdding: .day, value: 1, to: searchDate) ?? searchDate
        }

        return nil
    }
}
