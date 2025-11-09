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

        /// Extract year and month from folder hierarchy (Receipts/YYYY/MonthName/Note)
        func extractYearAndMonthFromFolders(_ folderId: UUID?) -> (year: String?, month: String?) {
            guard let folderId = folderId else { return (nil, nil) }

            // Get the month folder (first level - direct parent)
            guard let monthFolder = notesManager.folders.first(where: { $0.id == folderId }) else {
                return (nil, nil)
            }

            let monthName = monthFolder.name

            // Get the year folder (second level - parent of month folder)
            guard let yearFolder = notesManager.folders.first(where: { $0.id == monthFolder.parentFolderId }) else {
                return (nil, monthName)
            }

            let yearString = yearFolder.name
            return (yearString, monthName)
        }

        let receiptNotes = notesManager.notes.filter { note in
            isUnderReceiptsFolderHierarchy(folderId: note.folderId)
        }

        print("📦 ReceiptMetadata: Found \(receiptNotes.count) receipts under Receipts folder")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        var totalAmount = 0.0
        let result = receiptNotes.map { receipt in
            // Use CurrencyParser for robust amount extraction (finds largest amount, handles multiple formats)
            let amount = CurrencyParser.extractAmount(from: receipt.content.isEmpty ? receipt.title : receipt.content)
            totalAmount += amount
            let category = extractCategoryFromReceipt(receipt.title, content: receipt.content)
            let preview = String(receipt.content.prefix(50))

            // Extract month/year from folder hierarchy, fallback to dateCreated if not found
            let (folderYear, folderMonth) = extractYearAndMonthFromFolders(receipt.folderId)
            let monthYear = folderMonth.map { month in
                folderYear.map { "\($0) \(month)" } ?? month
            } ?? dateFormatter.string(from: receipt.dateCreated)

            let dayOfWeek = getDayOfWeekName(receipt.dateCreated)

            // Debug log for each receipt
            if folderMonth == nil {
                print("⚠️ Receipt '\(receipt.title)' ($\(String(format: "%.2f", amount))) - folder extraction failed, using dateCreated")
            }

            return ReceiptMetadata(
                id: receipt.id,
                merchant: receipt.title,
                amount: amount,
                date: receipt.dateCreated,
                category: category,
                preview: preview,
                monthYear: monthYear,
                dayOfWeek: dayOfWeek
            )
        }

        // Group by month for summary logging
        var byMonth: [String: Double] = [:]
        for metadata in result {
            let key = metadata.monthYear ?? "Unknown"
            byMonth[key, default: 0.0] += metadata.amount
        }

        print("📦 ReceiptMetadata: Total amount across all receipts: $\(String(format: "%.2f", totalAmount))")
        print("📦 ReceiptMetadata: Breakdown by month:")
        for (month, amount) in byMonth.sorted(by: { $0.key > $1.key }) {
            print("   - \(month): $\(String(format: "%.2f", amount))")
        }

        return result
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

        print("📅 Task categories available: \(taskManager.tasks.keys.map { $0.rawValue }.joined(separator: ", "))")

        for (category, tasks) in taskManager.tasks {
            print("📅 Processing category '\(category.rawValue)' with \(tasks.count) events")
            for task in tasks {
                let dateStr = task.targetDate.map { DateFormatter().string(from: $0) } ?? "No date"
                print("  - Event: \(task.title) | Date: \(dateStr)")
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
            let (city, province, country) = extractLocationParts(from: location.address)
            let (folderCity, folderProvince, folderCountry) = extractLocationPartsFromFolder(from: location.category)

            print("📍 Location: \(location.name)")
            print("   Address: \(location.address) → City: \(city ?? "N/A"), Province: \(province ?? "N/A")")
            print("   Folder: \(location.category) → FolderCity: \(folderCity ?? "N/A"), FolderProvince: \(folderProvince ?? "N/A")")

            return LocationMetadata(
                id: location.id,
                name: location.name,
                customName: location.customName,
                category: location.category,
                address: location.address,
                city: city,
                province: province,
                country: country,
                folderCity: folderCity,
                folderProvince: folderProvince,
                folderCountry: folderCountry,
                userRating: location.userRating,
                notes: location.userNotes,
                cuisine: location.userCuisine,
                dateCreated: location.dateCreated,
                dateModified: location.dateModified,
                visitCount: nil,
                lastVisited: nil,
                isFrequent: nil
            )
        }
    }

    /// Extract city, province/state, and country from an address string
    /// Handles formats like: "Street, City, Province, Country" or "Street, City, State"
    private static func extractLocationParts(from address: String) -> (city: String?, province: String?, country: String?) {
        let parts = address.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        // Common Canadian provinces/territories
        let canadianProvinces = ["ON", "QC", "BC", "AB", "MB", "SK", "NS", "NB", "PE", "NL", "YT", "NT", "NU",
                                "Ontario", "Quebec", "British Columbia", "Alberta", "Manitoba", "Saskatchewan",
                                "Nova Scotia", "New Brunswick", "Prince Edward Island", "Newfoundland and Labrador",
                                "Yukon", "Northwest Territories", "Nunavut"]

        // Common US states
        let usStates = ["CA", "NY", "TX", "FL", "IL", "PA", "OH", "GA", "NC", "MI", "NJ", "VA", "WA", "AZ", "MA", "TN", "IN", "MD", "MO", "WI", "CO", "MN", "SC", "AL", "LA", "KY", "OR", "OK", "CT", "UT", "IA", "NV", "AR", "KS", "MS", "NM", "NE", "ID", "HI", "NH", "ME", "MT", "RI", "DE", "SD", "ND", "VT", "AK", "WY", "DC",
                            "California", "New York", "Texas", "Florida", "Illinois", "Pennsylvania", "Ohio", "Georgia", "North Carolina", "Michigan", "New Jersey", "Virginia", "Washington", "Arizona", "Massachusetts", "Tennessee", "Indiana", "Maryland", "Missouri", "Wisconsin", "Colorado", "Minnesota", "South Carolina", "Alabama", "Louisiana", "Kentucky", "Oregon", "Oklahoma", "Connecticut", "Utah", "Iowa", "Nevada", "Arkansas", "Kansas", "Mississippi", "New Mexico", "Nebraska", "Idaho", "Hawaii", "New Hampshire", "Maine", "Montana", "Rhode Island", "Delaware", "South Dakota", "North Dakota", "Vermont", "Alaska", "Wyoming", "District of Columbia"]

        var city: String? = nil
        var province: String? = nil
        var country: String? = nil

        if parts.count >= 2 {
            city = parts[parts.count - 2]  // Second to last is usually city
            let lastPart = parts.last ?? ""

            // Check if last part is a province/state or country
            if canadianProvinces.contains(lastPart) {
                province = lastPart
                country = "Canada"
            } else if usStates.contains(lastPart) {
                province = lastPart
                country = "USA"
            } else {
                // Could be country name
                country = lastPart
            }
        }

        return (city, province, country)
    }

    /// Extract city, province/state, and country from a folder/category name
    /// Handles formats like: "Hamilton Restaurants", "Toronto Ontario", "Vancouver BC Canada"
    private static func extractLocationPartsFromFolder(from folder: String) -> (city: String?, province: String?, country: String?) {
        let canadianProvinces = ["ON", "QC", "BC", "AB", "MB", "SK", "NS", "NB", "PE", "NL", "YT", "NT", "NU",
                                "Ontario", "Quebec", "British Columbia", "Alberta", "Manitoba", "Saskatchewan",
                                "Nova Scotia", "New Brunswick", "Prince Edward Island", "Newfoundland and Labrador",
                                "Yukon", "Northwest Territories", "Nunavut"]

        let usStates = ["CA", "NY", "TX", "FL", "IL", "PA", "OH", "GA", "NC", "MI", "NJ", "VA", "WA", "AZ", "MA", "TN", "IN", "MD", "MO", "WI", "CO", "MN", "SC", "AL", "LA", "KY", "OR", "OK", "CT", "UT", "IA", "NV", "AR", "KS", "MS", "NM", "NE", "ID", "HI", "NH", "ME", "MT", "RI", "DE", "SD", "ND", "VT", "AK", "WY", "DC",
                            "California", "New York", "Texas", "Florida", "Illinois", "Pennsylvania", "Ohio", "Georgia", "North Carolina", "Michigan", "New Jersey", "Virginia", "Washington", "Arizona", "Massachusetts", "Tennessee", "Indiana", "Maryland", "Missouri", "Wisconsin", "Colorado", "Minnesota", "South Carolina", "Alabama", "Louisiana", "Kentucky", "Oregon", "Oklahoma", "Connecticut", "Utah", "Iowa", "Nevada", "Arkansas", "Kansas", "Mississippi", "New Mexico", "Nebraska", "Idaho", "Hawaii", "New Hampshire", "Maine", "Montana", "Rhode Island", "Delaware", "South Dakota", "North Dakota", "Vermont", "Alaska", "Wyoming", "District of Columbia"]

        let commonCountries = ["Canada", "USA", "United States", "Mexico", "UK", "England", "France", "Germany", "Spain", "Italy", "Australia", "New Zealand", "Japan", "China", "India"]

        // Parse folder name - split by common separators
        let parts = folder.split(separator: " ").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",-")) }

        var city: String? = nil
        var province: String? = nil
        var country: String? = nil

        // Try to identify country, province, and city in order
        for (index, part) in parts.enumerated() {
            // Check if this part is a country
            if commonCountries.contains(part) {
                country = part
            }
            // Check if this part is a Canadian province
            else if canadianProvinces.contains(part) {
                province = part
                if country == nil {
                    country = "Canada"
                }
            }
            // Check if this part is a US state
            else if usStates.contains(part) {
                province = part
                if country == nil {
                    country = "USA"
                }
            }
            // Otherwise, assume it's a city if we haven't found one yet
            else if city == nil && index < parts.count - 1 {
                // Only consider as city if it's not a category keyword (like "Restaurants", "Cafes", etc.)
                let categoryKeywords = ["restaurant", "restaurants", "cafe", "cafes", "coffee", "coffee shops", "bar", "bars", "gym", "gyms", "fitness", "park", "parks", "shop", "shops", "store", "stores", "location", "locations", "place", "places"]
                if !categoryKeywords.contains(part.lowercased()) {
                    city = part
                }
            }
        }

        return (city, province, country)
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
