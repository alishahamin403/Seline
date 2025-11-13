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
        self.receipts = receiptNotes.map { ReceiptStat(from: $0, category: "Receipt") }

        // Collect all notes
        self.notes = notesManager.notes

        // Collect all emails
        self.emails = emailService.inboxEmails + emailService.sentEmails

        // Collect all locations
        self.locations = locationsManager.savedPlaces

        print("📦 AppContext refreshed:")
        print("   Events: \(events.count)")
        print("   Receipts: \(receipts.count)")
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
            // Group by category for summary
            let byCategory = Dictionary(grouping: events) { $0.category.rawValue }
            for (category, items) in byCategory.sorted(by: { $0.key < $1.key }) {
                context += "\n**\(category.capitalized)** (\(items.count) events)\n"

                // Show recurring events with completion info
                let recurring = items.filter { $0.isRecurring }
                let nonRecurring = items.filter { !$0.isRecurring }

                if !recurring.isEmpty {
                    context += "  Recurring:\n"
                    for event in recurring.prefix(10) {
                        let completed = event.completedDates.count
                        let upcoming = event.isCompleted ? "Completed" : "Upcoming"
                        context += "    • \(event.title): \(completed) completions total [\(upcoming)]\n"

                        // Show recent completions
                        if !event.completedDates.isEmpty {
                            let recent = event.completedDates.sorted().suffix(3)
                            let dateStr = recent.map { formatDate($0) }.joined(separator: ", ")
                            context += "      Last completions: \(dateStr)\n"
                        }
                    }
                }

                if !nonRecurring.isEmpty {
                    context += "  One-time:\n"
                    for event in nonRecurring.prefix(10) {
                        let dateStr = event.targetDate.map { formatDate($0) } ?? "No date"
                        let status = event.isCompleted ? "✓" : "○"
                        context += "    \(status) \(event.title) - \(dateStr)\n"
                    }
                }
            }
        } else {
            context += "  No events\n"
        }

        // Receipts detail
        context += "\n=== RECEIPTS ===\n"
        if !receipts.isEmpty {
            // Group by month
            let byMonth = Dictionary(grouping: receipts) { receipt in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: receipt.date)
            }

            for (month, items) in byMonth.sorted(by: { $0.key > $1.key }).prefix(6) {
                let total = items.reduce(0.0) { $0 + $1.amount }
                context += "\n**\(month)**: \(items.count) receipts, Total: $\(String(format: "%.2f", total))\n"

                for receipt in items.sorted(by: { $0.date > $1.date }).prefix(5) {
                    context += "  • \(receipt.title): $\(String(format: "%.2f", receipt.amount)) - \(formatDate(receipt.date))\n"
                }
                if items.count > 5 {
                    context += "  ... and \(items.count - 5) more\n"
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
                "targetDate": event.targetDate.map { formatDate($0) } ?? nil as Any,
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
                "category": receipt.category,
                "content": String(receipt.content.prefix(500))
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
}
