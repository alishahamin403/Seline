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

    private static func buildReceiptMetadata(from notesManager: NotesManager) -> [ReceiptMetadata] {
        let receiptsFolderId = notesManager.getFolderIdByName("Receipts")

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

        return receiptNotes.map { receipt in
            let amount = extractAmountFromReceipt(receipt.content)
            let category = extractCategoryFromReceipt(receipt.title, content: receipt.content)
            let preview = String(receipt.content.prefix(50))

            return ReceiptMetadata(
                id: receipt.id,
                merchant: receipt.title,
                amount: amount ?? 0.0,
                date: receipt.dateCreated,
                category: category,
                preview: preview
            )
        }
    }

    // MARK: - Event Metadata Builder

    private static func buildEventMetadata(from taskManager: TaskManager) -> [EventMetadata] {
        var eventMetadata: [EventMetadata] = []

        for (_, tasks) in taskManager.tasks {
            for task in tasks {
                let recurrencePattern = task.recurrenceFrequency?.rawValue
                let completedDates = task.completedDates.isEmpty ? nil : task.completedDates

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
                    completedDates: completedDates
                )
                eventMetadata.append(metadata)
            }
        }

        return eventMetadata
    }

    // MARK: - Location Metadata Builder

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
                dateModified: location.dateModified
            )
        }
    }

    // MARK: - Note Metadata Builder

    private static func buildNoteMetadata(from notesManager: NotesManager) -> [NoteMetadata] {
        // Exclude receipts folder notes
        let receiptsFolderId = notesManager.getFolderIdByName("Receipts")

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

    private static func buildEmailMetadata(from emailService: EmailService) -> [EmailMetadata] {
        return emailService.emails.map { email in
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
