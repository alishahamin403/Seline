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

        refresh()
    }

    // MARK: - Data Collection

    /// Refresh all app data (call this at start of each conversation)
    func refresh() {
        print("🔄 SelineAppContext.refresh() called")
        self.currentDate = Date()

        // Collect all events
        self.events = taskManager.tasks.values.flatMap { $0 }

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
    func buildContextPrompt() async -> String {
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
                // Determine the reference date for this event
                var eventDate: Date

                if event.isRecurring {
                    // For recurring events, determine the next occurrence date
                    eventDate = getNextOccurrenceDate(for: event) ?? currentDate
                } else {
                    eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate
                }

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
                context += "\n**UPCOMING** (\(upcoming.count) events, showing first 15):\n"
                for event in upcoming.prefix(15).sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
                }
                if upcoming.count > 15 {
                    context += "  ... and \(upcoming.count - 15) more upcoming events\n"
                }
            }

            // RECURRING EVENTS SUMMARY
            let recurringEvents = events.filter { $0.isRecurring }
            if !recurringEvents.isEmpty {
                context += "\n**RECURRING EVENTS SUMMARY** (\(recurringEvents.count) recurring):\n"
                for event in recurringEvents.prefix(10) {
                    let currentMonth = calendar.dateComponents([.month, .year], from: currentDate)

                    let thisMonthCompletions = event.completedDates.filter { date in
                        let dateComponents = calendar.dateComponents([.month, .year], from: date)
                        return dateComponents.month == currentMonth.month && dateComponents.year == currentMonth.year
                    }

                    let categoryName = getCategoryName(for: event.tagId)
                    context += "  • \(event.title) [\(categoryName)]\n"
                    context += "    This month: \(thisMonthCompletions.count) completions\n"
                    context += "    All-time: \(event.completedDates.count) completions\n"

                    if !thisMonthCompletions.isEmpty {
                        let dateStrings = thisMonthCompletions.sorted().map { formatDate($0) }
                        context += "    Completed on: \(dateStrings.joined(separator: ", "))\n"
                    } else {
                        context += "    No completions this month\n"
                    }
                }
            }

            // PAST EVENTS
            if !past.isEmpty {
                context += "\n**PAST EVENTS** (showing last 5):\n"
                for event in past.suffix(5).reversed() {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
                if past.count > 5 {
                    context += "  ... and \(past.count - 5) more past events\n"
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

        // Notes detail
        context += "\n=== NOTES ===\n"
        if !notes.isEmpty {
            for note in notes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(10) {
                let preview = String(note.content.prefix(100)).replacingOccurrences(of: "\n", with: " ")
                context += "  • **\(note.title)**: \(preview)...\n"
            }
            if notes.count > 10 {
                context += "  ... and \(notes.count - 10) more notes\n"
            }
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

    /// Determine the next occurrence date for a recurring event
    private func getNextOccurrenceDate(for event: TaskItem) -> Date? {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return nil }

        let calendar = Calendar.current

        // Check if event has reached its end date
        if let endDate = event.recurrenceEndDate, currentDate > endDate {
            return nil
        }

        // Use the original targetDate as the anchor date
        let anchorDate = event.targetDate ?? event.createdAt

        // Calculate the next occurrence based on frequency
        switch frequency {
        case .daily:
            // Daily events occur every day after the anchor date
            if currentDate >= anchorDate {
                return currentDate // Occurs today
            }
            return anchorDate // Hasn't started yet

        case .weekly:
            // Weekly events occur on the same day of week
            let targetWeekday = calendar.component(.weekday, from: anchorDate)
            let currentWeekday = calendar.component(.weekday, from: currentDate)

            if targetWeekday == currentWeekday && currentDate >= anchorDate {
                return currentDate // This week
            }

            // Calculate next occurrence on the target weekday
            var daysToAdd = (targetWeekday - currentWeekday + 7) % 7
            if daysToAdd == 0 && currentDate >= anchorDate {
                daysToAdd = 0 // Today is the day
            } else if daysToAdd == 0 {
                daysToAdd = 7 // Next week
            }

            if let nextOccurrence = calendar.date(byAdding: .day, value: daysToAdd, to: currentDate),
               nextOccurrence >= anchorDate {
                return nextOccurrence
            }
            return nil

        case .biweekly:
            // Biweekly events occur every 2 weeks on the same day
            let daysDifference = calendar.dateComponents([.day], from: anchorDate, to: currentDate).day ?? 0

            if daysDifference >= 0 && daysDifference % 14 == 0 {
                return currentDate // Today
            }

            // Calculate next biweekly occurrence
            let daysUntilNext = 14 - (daysDifference % 14)
            if let nextOccurrence = calendar.date(byAdding: .day, value: daysUntilNext, to: currentDate) {
                return nextOccurrence
            }
            return nil

        case .monthly:
            // Monthly events occur on the same day of month
            let targetDay = calendar.component(.day, from: anchorDate)
            let currentDay = calendar.component(.day, from: currentDate)

            if targetDay == currentDay && currentDate >= anchorDate {
                return currentDate // This month
            }

            // Calculate next monthly occurrence
            var nextDate = currentDate
            if targetDay > currentDay {
                // It's later this month
                if let date = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: currentDate),
                   let adjusted = calendar.date(byAdding: .day, value: targetDay - currentDay, to: date) {
                    nextDate = adjusted
                }
            } else {
                // It's next month
                if let date = calendar.date(byAdding: .month, value: 1, to: currentDate),
                   let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
                   let adjusted = calendar.date(byAdding: .day, value: targetDay - 1, to: first) {
                    nextDate = adjusted
                }
            }

            return nextDate >= anchorDate ? nextDate : nil

        case .yearly:
            // Yearly events occur on the same month and day
            let targetMonth = calendar.component(.month, from: anchorDate)
            let targetDay = calendar.component(.day, from: anchorDate)
            let currentMonth = calendar.component(.month, from: currentDate)
            let currentDay = calendar.component(.day, from: currentDate)

            if targetMonth == currentMonth && targetDay == currentDay && currentDate >= anchorDate {
                return currentDate // This year
            }

            // Calculate next yearly occurrence
            var nextDate = calendar.date(from: DateComponents(year: calendar.component(.year, from: currentDate),
                                                             month: targetMonth,
                                                             day: targetDay)) ?? currentDate

            if nextDate <= currentDate {
                nextDate = calendar.date(byAdding: .year, value: 1, to: nextDate) ?? currentDate
            }

            return nextDate >= anchorDate ? nextDate : nil
        }
    }
}
