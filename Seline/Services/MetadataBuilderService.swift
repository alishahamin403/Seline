import Foundation

/// Service that compiles lightweight metadata from all data sources
/// This enables intelligent LLM filtering without pre-filtering in the backend
class MetadataBuilderService {

    /// Build complete metadata context from all data sources
    @MainActor
    static func buildAppMetadata(
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        locationsManager: LocationsManager
    ) -> AppDataMetadata {
        let receipts = buildReceiptMetadata(from: notesManager)
        let events = buildEventMetadata(from: taskManager)
        let locations = buildLocationMetadata(from: locationsManager)
        let notes = buildNoteMetadata(from: notesManager)
        let emails = buildEmailMetadata(from: emailService)

        return AppDataMetadata(
            receipts: receipts,
            events: events,
            locations: locations,
            notes: notes,
            emails: emails
        )
    }

    // MARK: - Receipt Metadata Builder

    @MainActor
    private static func buildReceiptMetadata(from notesManager: NotesManager) -> [ReceiptMetadata] {
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

        func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
            guard let folderId = folderId else { return false }

            if folderId == receiptsFolderId {
                return true
            }

            // Check if parent folder (recursively) is receipts
            if let folder = notesManager.folders.first(where: { $0.id == folderId }),
               let parentId = folder.parentFolderId {
                return isUnderReceiptsFolderHierarchy(folderId: parentId)
            }

            return false
        }

        let receiptNotes = notesManager.notes.filter { note in
            isUnderReceiptsFolderHierarchy(folderId: note.folderId)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        let calendar = Calendar.current

        return receiptNotes.map { receipt in
            let amount = extractAmountFromReceipt(receipt.content)
            let category = extractCategoryFromReceipt(receipt.title, content: receipt.content)
            let preview = String(receipt.content.prefix(50))
            let monthYear = dateFormatter.string(from: receipt.dateCreated)
            let dayOfWeek = getDayOfWeekName(receipt.dateCreated)

            return ReceiptMetadata(
                id: receipt.id,
                merchant: receipt.title,
                amount: amount ?? 0.0,
                date: receipt.dateCreated,
                category: category,
                preview: preview,
                monthYear: monthYear,
                dayOfWeek: dayOfWeek
            )
        }
    }

    private static func getDayOfWeekName(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: date)
    }

    // MARK: - Event Metadata Builder

    @MainActor
    private static func buildEventMetadata(from taskManager: TaskManager) -> [EventMetadata] {
        var eventMetadata: [EventMetadata] = []

        print("📅 Task categories available: \(taskManager.tasks.keys.joined(separator: ", "))")

        for (category, tasks) in taskManager.tasks {
            print("📅 Processing category '\(category)' with \(tasks.count) events")
            for task in tasks {
                print("  - Event: \(task.title)")
                let recurrencePattern = task.recurrenceFrequency?.rawValue
                let completedDates = task.completedDates.isEmpty ? nil : task.completedDates
                let eventType = inferEventType(from: task.title, description: task.description)

                let metadata = EventMetadata(
                    id: task.id,
                    title: task.title,
                    date: task.targetDate,
                    time: task.scheduledTime,
                    endTime: task.endTime,
                    description: task.description,
                    location: nil, // TODO: add location field if available in TaskItem
                    reminder: task.reminderTime?.displayName,
                    isRecurring: task.isRecurring,
                    recurrencePattern: recurrencePattern,
                    isCompleted: task.isCompleted,
                    completedDates: completedDates,
                    eventType: eventType,
                    priority: nil // TODO: extract from TaskItem if available
                )
                eventMetadata.append(metadata)
            }
        }

        print("📅 Total events compiled: \(eventMetadata.count)")
        return eventMetadata
    }

    private static func inferEventType(from title: String, description: String?) -> String? {
        let combined = (title + " " + (description ?? "")).lowercased()

        if combined.contains("gym") || combined.contains("workout") || combined.contains("exercise") || combined.contains("fitness") {
            return "fitness"
        } else if combined.contains("meeting") || combined.contains("call") || combined.contains("standup") || combined.contains("sync") {
            return "work"
        } else if combined.contains("birthday") || combined.contains("dinner") || combined.contains("lunch") || combined.contains("party") {
            return "personal"
        } else if combined.contains("doctor") || combined.contains("appointment") || combined.contains("dentist") {
            return "health"
        }

        return nil
    }

    // MARK: - Location Metadata Builder

    @MainActor
    private static func buildLocationMetadata(from locationsManager: LocationsManager) -> [LocationMetadata] {
        return locationsManager.savedPlaces.map { location in
            LocationMetadata(
                id: location.id,
                name: location.name,
                customName: location.customName,
                category: location.category,
                address: location.address,
                userRating: location.userRating,
                notes: location.userNotes, // This is the description field
                cuisine: location.userCuisine,
                dateCreated: location.dateCreated,
                dateModified: location.dateModified,
                visitCount: nil, // TODO: Count from receipts or notes mentioning this location
                lastVisited: nil, // TODO: Track from recent receipts/notes
                isFrequent: nil // TODO: Determine from visitCount
            )
        }
    }

    // MARK: - Note Metadata Builder

    @MainActor
    private static func buildNoteMetadata(from notesManager: NotesManager) -> [NoteMetadata] {
        // Exclude receipts folder notes
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

        func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
            guard let folderId = folderId else { return false }

            if folderId == receiptsFolderId {
                return true
            }

            if let folder = notesManager.folders.first(where: { $0.id == folderId }),
               let parentId = folder.parentFolderId {
                return isUnderReceiptsFolderHierarchy(folderId: parentId)
            }

            return false
        }

        return notesManager.notes
            .filter { !isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
            .map { note in
                let folderName = notesManager.folders.first(where: { $0.id == note.folderId })?.name

                return NoteMetadata(
                    id: note.id,
                    title: note.title,
                    preview: note.preview,
                    dateCreated: note.dateCreated,
                    dateModified: note.dateModified,
                    isPinned: note.isPinned,
                    folder: folderName
                )
            }
    }

    // MARK: - Email Metadata Builder

    @MainActor
    private static func buildEmailMetadata(from emailService: EmailService) -> [EmailMetadata] {
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        print("📧 Building email metadata - Inbox: \(emailService.inboxEmails.count), Sent: \(emailService.sentEmails.count)")
        for email in allEmails {
            print("  📧 Email ID: \(email.id) | From: \(email.sender.displayName) | Subject: \(email.subject)")
        }

        return allEmails.map { email in
            EmailMetadata(
                id: email.id,
                from: email.sender.displayName,
                subject: email.subject,
                snippet: email.snippet,
                date: email.timestamp,
                isRead: email.isRead,
                isImportant: email.isImportant,
                hasAttachments: email.hasAttachments
            )
        }
    }

    // MARK: - Helper Functions

    static func extractAmountFromNote(_ content: String) -> Double? {
        let pattern = "\\$([0-9]+\\.?[0-9]*)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            if let match = regex.firstMatch(in: content, range: range),
               let amountRange = Range(match.range(at: 1), in: content) {
                return Double(content[amountRange])
            }
        }
        return nil
    }

    private static func extractAmountFromReceipt(_ content: String) -> Double? {
        let pattern = "\\$([0-9]+\\.?[0-9]*)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            if let match = regex.firstMatch(in: content, range: range),
               let amountRange = Range(match.range(at: 1), in: content) {
                return Double(content[amountRange])
            }
        }
        return nil
    }

    private static func extractCategoryFromReceipt(_ title: String, content: String) -> String? {
        let lower = (title + " " + content).lowercased()

        if lower.contains("coffee") || lower.contains("starbucks") || lower.contains("tim horton") {
            return "food"
        } else if lower.contains("gas") || lower.contains("shell") || lower.contains("esso") {
            return "gas"
        } else if lower.contains("grocery") || lower.contains("metro") || lower.contains("loblaws") {
            return "groceries"
        } else if lower.contains("restaurant") || lower.contains("oche king") {
            return "food"
        }

        return nil
    }
}
