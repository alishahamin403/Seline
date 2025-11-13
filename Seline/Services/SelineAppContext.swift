import Foundation

/// Simple data context for LLM - collects all app data without pre-filtering
/// The LLM will handle filtering, reasoning, and natural language understanding
@MainActor
class SelineAppContext {
    // MARK: - Core Data

    private let taskManager: TaskManager
    private let notesManager: NotesManager
    private let emailService: EmailService
    private let weatherService: WeatherService
    private let locationsManager: LocationsManager
    private let navigationService: NavigationService

    // MARK: - Cached Data

    private(set) var events: [TaskItem] = []
    private(set) var receipts: [ReceiptStat] = []
    private(set) var notes: [Note] = []
    private(set) var emails: [Email] = []
    private(set) var locations: [SavedPlace] = []
    private(set) var currentDate: Date = Date()

    init(
        taskManager: TaskManager = TaskManager.shared,
        notesManager: NotesManager = NotesManager.shared,
        emailService: EmailService = EmailService.shared,
        weatherService: WeatherService = WeatherService.shared,
        locationsManager: LocationsManager = LocationsManager.shared,
        navigationService: NavigationService = NavigationService.shared
    ) {
        self.taskManager = taskManager
        self.notesManager = notesManager
        self.emailService = emailService
        self.weatherService = weatherService
        self.locationsManager = locationsManager
        self.navigationService = navigationService

        refresh()
    }

    // MARK: - Data Collection

    /// Refresh all app data (call this at start of each conversation)
    func refresh() {
        self.currentDate = Date()

        // Collect all events
        self.events = taskManager.tasks.values.flatMap { $0 }

        // Collect all receipts from notes
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
        let receiptNotes = notesManager.notes.filter { note in
            isUnderReceiptsFolderHierarchy(folderId: note.folderId, receiptsFolderId: receiptsFolderId)
        }

        // Extract transaction dates from receipt notes
        self.receipts = receiptNotes.map { note in
            // Try to extract the actual transaction date from the note content/title
            let transactionDate = extractTransactionDate(from: note)
            let finalDate = transactionDate ?? note.dateModified

            // Debug: Show if extraction failed
            if transactionDate == nil {
                print("⚠️  Date extraction FAILED for: \(note.title)")
                print("   Using fallback dateModified: \(formatDate(finalDate))")
                print("   Note content: \(note.content.prefix(100))")
            }

            return ReceiptStat(from: note, date: transactionDate, category: "Receipt")
        }

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
            let minDate = receipts.min(by: { $0.date < $1.date })?.date ?? Date()
            let maxDate = receipts.max(by: { $0.date < $1.date })?.date ?? Date()
            print("     Date range: \(formatDate(minDate)) to \(formatDate(maxDate))")
            // Show sample of receipt dates
            let sampleDates = receipts.prefix(5).map { "\(formatDate($0.date)): \($0.title) ($\(String(format: "%.2f", $0.amount)))" }
            print("     Sample: \(sampleDates.joined(separator: "\n              "))")
        }
        print("   Notes: \(notes.count)")
        print("   Emails: \(emails.count)")
        print("   Locations: \(locations.count)")
    }

    // MARK: - Context Building for LLM

    /// Build a rich context string for the LLM with all app data
    func buildContextPrompt() -> String {
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

        // Events detail
        context += "=== EVENTS ===\n"
        if !events.isEmpty {
            // Separate recurring and non-recurring events
            let recurring = events.filter { $0.isRecurring }
            let nonRecurring = events.filter { !$0.isRecurring }

            if !recurring.isEmpty {
                context += "\n**Recurring Events** (\(recurring.count) events)\n"
                for event in recurring.prefix(20) {  // Show up to 20 recurring events
                    let currentMonth = Calendar.current.dateComponents([.month, .year], from: currentDate)

                    // Filter completions for THIS MONTH
                    let thisMonthCompletions = event.completedDates.filter { date in
                        let dateComponents = Calendar.current.dateComponents([.month, .year], from: date)
                        return dateComponents.month == currentMonth.month && dateComponents.year == currentMonth.year
                    }.sorted()

                    let allTimeCompletions = event.completedDates.count
                    let thisMonthCount = thisMonthCompletions.count

                    context += "  • \(event.title):\n"
                    context += "    This month: \(thisMonthCount) completions\n"
                    context += "    All-time: \(allTimeCompletions) completions\n"

                    // Show ALL completions for this month (not just last 3)
                    if !thisMonthCompletions.isEmpty {
                        let dateStrings = thisMonthCompletions.map { formatDate($0) }
                        context += "    Completed on: \(dateStrings.joined(separator: ", "))\n"
                    } else {
                        context += "    No completions this month\n"
                    }

                    // Show recent completions across all time
                    if !event.completedDates.isEmpty {
                        let recent = event.completedDates.sorted().suffix(3).reversed()
                        let dateStr = recent.map { formatDate($0) }.joined(separator: ", ")
                        context += "    Recent (all-time): \(dateStr)\n"
                    }

                    // Show target date if it exists
                    if let targetDate = event.targetDate {
                        context += "    Original date: \(formatDate(targetDate))\n"
                    }
                }
            }

            if !nonRecurring.isEmpty {
                context += "\n**One-time Events** (\(nonRecurring.count) events)\n"
                for event in nonRecurring.prefix(20) {  // Show up to 20 one-time events
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let dateStr: String

                    // Try to get a date from various sources
                    if let targetDate = event.targetDate {
                        dateStr = formatDate(targetDate)
                    } else if let scheduledTime = event.scheduledTime {
                        dateStr = formatDate(scheduledTime) + " (scheduled)"
                    } else if let completedDate = event.completedDate {
                        dateStr = formatDate(completedDate) + " (completed)"
                    } else {
                        dateStr = "No date set"
                    }

                    context += "  \(status): \(event.title) - \(dateStr)\n"

                    // Add description if available
                    if let description = event.description, !description.isEmpty {
                        context += "    Description: \(description)\n"
                    }
                }
            }
        } else {
            context += "  No events\n"
        }

        // Receipts detail
        context += "\n=== RECEIPTS & EXPENSES ===\n"
        if !receipts.isEmpty {
            // First, identify current month and year safely
            let currentMonthComponents = Calendar.current.dateComponents([.month, .year], from: currentDate)
            let currentMonth = currentMonthComponents.month ?? 0
            let currentYear = currentMonthComponents.year ?? 0

            let currentMonthFormatter = DateFormatter()
            currentMonthFormatter.dateFormat = "MMMM yyyy"
            let currentMonthStr = currentMonthFormatter.string(from: currentDate)

            // Debug: Log the current month/year we're filtering for
            print("📅 Filtering receipts for: \(currentMonthStr) (Month: \(currentMonth), Year: \(currentYear))")

            // Separate current month from other months - SAFE COMPARISON
            let currentMonthReceipts = receipts.filter { receipt in
                let receiptMonthComponents = Calendar.current.dateComponents([.month, .year], from: receipt.date)
                let receiptMonth = receiptMonthComponents.month ?? 0
                let receiptYear = receiptMonthComponents.year ?? 0
                let isCurrentMonth = (receiptMonth == currentMonth && receiptYear == currentYear)
                return isCurrentMonth
            }

            let otherMonthsReceipts = receipts.filter { receipt in
                let receiptMonthComponents = Calendar.current.dateComponents([.month, .year], from: receipt.date)
                let receiptMonth = receiptMonthComponents.month ?? 0
                let receiptYear = receiptMonthComponents.year ?? 0
                let isCurrentMonth = (receiptMonth == currentMonth && receiptYear == currentYear)
                return !isCurrentMonth
            }

            // Debug output
            print("💰 Current month receipts: \(currentMonthReceipts.count)")
            print("📋 Other month receipts: \(otherMonthsReceipts.count)")

            // CURRENT MONTH - Show all details
            if !currentMonthReceipts.isEmpty {
                let currentMonthTotal = currentMonthReceipts.reduce(0.0) { $0 + $1.amount }
                context += "\n**\(currentMonthStr)** (Current Month): \(currentMonthReceipts.count) receipts, Total: $\(String(format: "%.2f", currentMonthTotal))\n"

                // Group by category for current month
                let byCategory = Dictionary(grouping: currentMonthReceipts) { $0.category }
                for (category, items) in byCategory.sorted(by: { $0.key < $1.key }) {
                    let categoryTotal = items.reduce(0.0) { $0 + $1.amount }
                    context += "  **\(category)**: $\(String(format: "%.2f", categoryTotal)) (\(items.count) items)\n"

                    // List all items in this category
                    for receipt in items.sorted(by: { $0.date > $1.date }) {
                        context += "    • \(receipt.title): $\(String(format: "%.2f", receipt.amount)) - \(formatDate(receipt.date))\n"
                    }
                }
            }

            // PREVIOUS MONTHS - Show summary
            if !otherMonthsReceipts.isEmpty {
                context += "\n**Previous Months Summary**:\n"

                // Group by month
                let byMonth = Dictionary(grouping: otherMonthsReceipts) { receipt in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMMM yyyy"
                    return formatter.string(from: receipt.date)
                }

                for (month, items) in byMonth.sorted(by: { $0.key > $1.key }).prefix(6) {
                    let total = items.reduce(0.0) { $0 + $1.amount }

                    // Show category breakdown for each month
                    let byCategory = Dictionary(grouping: items) { $0.category }
                    var categoryBreakdown = byCategory.map { cat, catItems in
                        let catTotal = catItems.reduce(0.0) { $0 + $1.amount }
                        return "\(cat): $\(String(format: "%.2f", catTotal))"
                    }.sorted()

                    context += "  **\(month)**: $\(String(format: "%.2f", total)) total - \(categoryBreakdown.joined(separator: ", "))\n"
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

    /// Extract the actual transaction date from a receipt note
    /// Searches note title and content for date patterns like "November 25, 2025"
    private func extractTransactionDate(from note: Note) -> Date? {
        let searchText = note.title + " " + note.content

        // Regex to find dates like "Month DD, YYYY" or "Month DD YYYY"
        // More flexible: allows 0+ spaces, optional comma, handles both cases
        let monthNames = "January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
        let datePattern = "(\(monthNames))\\s+(\\d{1,2})\\s*,?\\s*(\\d{4})"

        guard let regex = try? NSRegularExpression(pattern: datePattern, options: [.caseInsensitive]) else {
            print("⚠️  Regex compilation failed")
            return nil
        }

        let range = NSRange(searchText.startIndex..., in: searchText)
        guard let match = regex.firstMatch(in: searchText, options: [], range: range) else {
            return nil
        }

        // Extract the matched date string
        let matchedRange = match.range
        guard let matchedString = Range(matchedRange, in: searchText).map({ String(searchText[$0]) }) else {
            return nil
        }

        // Try to parse the extracted date string
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")  // Use standard locale

        // Try multiple format variations
        let formats = [
            "MMMM d, yyyy",    // November 25, 2025
            "MMMM d yyyy",     // November 25 2025
            "MMMM  d, yyyy",   // November  25, 2025 (double space)
            "MMMM  d yyyy",    // November  25 2025
            "MMM d, yyyy",     // Nov 25, 2025
            "MMM d yyyy",      // Nov 25 2025
            "MMM  d, yyyy",    // Nov  25, 2025
            "MMM  d yyyy",     // Nov  25 2025
        ]

        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: matchedString) {
                return date
            }
        }

        print("⚠️  Could not parse extracted date '\(matchedString)' - tried \(formats.count) formats")
        return nil
    }
}
