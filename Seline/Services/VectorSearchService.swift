import Foundation

/**
 * VectorSearchService - Semantic Search for LLM Context
 *
 * This service provides vector-based semantic search using OpenAI embeddings
 * stored in Supabase pgvector. It replaces keyword matching with AI-powered
 * similarity search for much more relevant context retrieval.
 *
 * Key features:
 * - Semantic search across notes, emails, tasks, and locations
 * - Automatic embedding generation and caching
 * - Background sync to keep embeddings up-to-date
 * - Efficient batch processing
 */
@MainActor
class VectorSearchService: ObservableObject {
    static let shared = VectorSearchService()
    
    // MARK: - Published State
    
    @Published var isIndexing = false
    @Published var lastSyncTime: Date?
    @Published var embeddingsCount: Int = 0
    
    // MARK: - Configuration

    private let maxBatchSize = 50 // Max documents per batch
    private let similarityThreshold: Float = 0.3 // Minimum similarity score
    private let defaultResultLimit = 10
    private let recentDaysThreshold = 30 // Only embed documents from last 30 days
    
    // MARK: - Cache
    
    private var lastSyncedHashes: [String: Int] = [:] // document_id -> content_hash
    
    // MARK: - Initialization
    
    private init() {
        // Start background sync on init
        Task {
            await syncEmbeddingsIfNeeded()
        }
    }
    
    // MARK: - Semantic Search
    
    /// Search for documents semantically similar to a query
    /// Returns the most relevant notes, emails, tasks, and locations
    func search(
        query: String,
        documentTypes: [DocumentType]? = nil,
        limit: Int = 10
    ) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        let requestBody: [String: Any] = [
            "action": "search",
            "query": query,
            "document_types": documentTypes?.map { $0.rawValue } ?? NSNull(),
            "limit": limit,
            "similarity_threshold": similarityThreshold
        ]
        
        let response: SearchResponse = try await makeRequest(body: requestBody)
        
        return response.results.map { result in
            SearchResult(
                documentType: DocumentType(rawValue: result.document_type) ?? .note,
                documentId: result.document_id,
                title: result.title,
                content: result.content,
                metadata: result.metadata,
                similarity: result.similarity
            )
        }
    }
    
    /// Search and return formatted context for LLM
    /// This is the main method used by SelineAppContext
    func getRelevantContext(
        forQuery query: String,
        limit: Int = 15
    ) async throws -> String {
        let results = try await search(query: query, limit: limit)
        
        guard !results.isEmpty else {
            return ""
        }
        
        var context = "=== RELEVANT DATA (Semantic Search) ===\n"
        context += "Query matched \(results.count) items by semantic similarity:\n\n"
        
        // Group by document type
        let grouped = Dictionary(grouping: results) { $0.documentType }
        
        for (type, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            context += "**\(type.displayName) (\(items.count) matches):**\n"
            
            for item in items {
                let similarity = String(format: "%.0f%%", item.similarity * 100)
                context += "• [\(similarity) match] "
                
                if let title = item.title, !title.isEmpty {
                    context += "**\(title)**\n"
                }
                
                // Add relevant content preview
                let preview = item.content.prefix(300)
                context += "  \(preview)"
                if item.content.count > 300 {
                    context += "..."
                }
                context += "\n"
                
                // Add metadata if present
                if let metadata = item.metadata {
                    if let date = metadata["date"] as? String {
                        context += "  📅 \(date)\n"
                    }
                    if let location = metadata["location"] as? String {
                        context += "  📍 \(location)\n"
                    }
                    if let sender = metadata["sender"] as? String {
                        context += "  👤 From: \(sender)\n"
                    }
                }
                context += "\n"
            }
        }
        
        return context
    }
    
    // MARK: - Embedding Sync
    
    /// Sync embeddings for all user data
    /// Call this on app launch and periodically
    func syncEmbeddingsIfNeeded() async {
        // Only sync if not already syncing
        guard !isIndexing else { return }
        
        // Check if we've synced recently (within 5 minutes)
        if let lastSync = lastSyncTime,
           Date().timeIntervalSince(lastSync) < 300 {
            print("⚡ Skipping embedding sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago")
            return
        }
        
        await syncAllEmbeddings()
    }
    
    /// Force sync all embeddings
    func syncAllEmbeddings() async {
        isIndexing = true
        defer { isIndexing = false }
        
        print("🔄 Starting embedding sync...")
        let startTime = Date()
        
        do {
            // Sync each document type - COMPREHENSIVE coverage
            let notesCount = await syncNoteEmbeddings()
            let emailsCount = await syncEmailEmbeddings()
            let tasksCount = await syncTaskEmbeddings()
            let locationsCount = await syncLocationEmbeddings()
            let receiptsCount = await syncReceiptEmbeddings()
            let visitsCount = await syncLocationVisitEmbeddings()
            let peopleCount = await syncPeopleEmbeddings()
            
            let totalCount = notesCount + emailsCount + tasksCount + locationsCount + receiptsCount + visitsCount + peopleCount
            embeddingsCount = totalCount
            lastSyncTime = Date()
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ Embedding sync complete: \(totalCount) documents in \(String(format: "%.1f", duration))s")
            print("   Notes: \(notesCount), Emails: \(emailsCount), Tasks: \(tasksCount), Locations: \(locationsCount), Receipts: \(receiptsCount), Visits: \(visitsCount), People: \(peopleCount)")
            
        } catch {
            print("❌ Embedding sync failed: \(error)")
        }
    }
    
    /// Sync note embeddings - only embed new/changed notes from last 30 days
    private func syncNoteEmbeddings() async -> Int {
        let allNotes = NotesManager.shared.notes
        guard !allNotes.isEmpty else { return 0 }

        // Filter to only recent notes (last 30 days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentDaysThreshold, to: Date())!
        let recentNotes = allNotes.filter { $0.dateModified >= cutoffDate }

        guard !recentNotes.isEmpty else {
            print("📝 Notes: No notes modified in last \(recentDaysThreshold) days, skipping")
            return 0
        }

        print("📝 Notes: Syncing \(recentNotes.count) of \(allNotes.count) (last \(recentDaysThreshold) days)")

        // Prepare documents for embedding
        let documents = recentNotes.map { note -> [String: Any] in
            let content = "\(note.title)\n\n\(note.content)"
            return [
                "document_type": "note",
                "document_id": note.id.uuidString,
                "title": note.title,
                "content": content,
                "metadata": [
                    "date": ISO8601DateFormatter().string(from: note.dateModified),
                    "folder_id": note.folderId?.uuidString ?? NSNull(),
                    "is_pinned": note.isPinned
                ] as [String: Any]
            ]
        }
        
        // Check which notes need embedding (content changed or new)
        do {
            let userId = try await SupabaseManager.shared.authClient.session.user.id
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes = documents.compactMap { doc -> Int64? in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "note",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else {
                print("📝 Notes: All \\(documents.count) already embedded, skipping")
                return 0
            }
            
            let neededSet = Set(neededIds)
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            print("📝 Notes: Embedding \\(docsToEmbed.count) of \\(documents.count) (\\(documents.count - docsToEmbed.count) unchanged)")
            return await batchEmbed(documents: docsToEmbed, type: "note")
        } catch {
            print("❌ Error checking note embeddings: \\(error)")
            // Fall back to full embed on error
            return await batchEmbed(documents: documents, type: "note")
        }
    }
    
    /// Sync email embeddings - only embed new/changed emails from last 30 days
    private func syncEmailEmbeddings() async -> Int {
        let allEmails = EmailService.shared.inboxEmails + EmailService.shared.sentEmails
        guard !allEmails.isEmpty else { return 0 }

        // Filter to only recent emails (last 30 days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentDaysThreshold, to: Date())!
        let recentEmails = allEmails.filter { $0.timestamp >= cutoffDate }

        guard !recentEmails.isEmpty else {
            print("📧 Emails: No emails from last \(recentDaysThreshold) days, skipping")
            return 0
        }

        print("📧 Emails: Syncing \(recentEmails.count) of \(allEmails.count) (last \(recentDaysThreshold) days)")
        
        let documents = recentEmails.map { email -> [String: Any] in
            let content = """
            Subject: \(email.subject)
            From: \(email.sender.displayName)
            \(email.aiSummary ?? email.snippet)
            """
            return [
                "document_type": "email",
                "document_id": email.id,
                "title": email.subject,
                "content": content,
                "metadata": [
                    "date": ISO8601DateFormatter().string(from: email.timestamp),
                    "sender": email.sender.displayName,
                    "sender_email": email.sender.email,
                    "is_important": email.isImportant,
                    "is_read": email.isRead
                ] as [String: Any]
            ]
        }
        
        // Check which emails need embedding (content changed or new)
        do {
            let userId = try await SupabaseManager.shared.authClient.session.user.id
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes = documents.compactMap { doc -> Int64? in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "email",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else {
                print("📧 Emails: All \(documents.count) already embedded, skipping")
                return 0
            }
            
            let neededSet = Set(neededIds)
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            print("📧 Emails: Embedding \(docsToEmbed.count) of \(documents.count) (\(documents.count - docsToEmbed.count) unchanged)")
            return await batchEmbed(documents: docsToEmbed, type: "email")
        } catch {
            print("❌ Error checking email embeddings: \(error)")
            // Fall back to full embed on error
            return await batchEmbed(documents: documents, type: "email")
        }
    }
    
    /// Sync task embeddings - only embed tasks from last 30 days
    private func syncTaskEmbeddings() async -> Int {
        let allTasks = TaskManager.shared.tasks.values
            .flatMap { $0 }
            .filter { !$0.isDeleted }
        guard !allTasks.isEmpty else { return 0 }

        // Filter to only recent tasks (created or scheduled in last 30 days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentDaysThreshold, to: Date())!
        let recentTasks = allTasks.filter { task in
            let relevantDate = task.scheduledTime ?? task.targetDate ?? task.createdAt
            return relevantDate >= cutoffDate
        }

        guard !recentTasks.isEmpty else {
            print("📅 Tasks: No tasks from last \(recentDaysThreshold) days, skipping")
            return 0
        }

        print("📅 Tasks: Syncing \(recentTasks.count) of \(allTasks.count) (last \(recentDaysThreshold) days)")

        let documents = recentTasks.map { task -> [String: Any] in
            let calendar = Calendar.current
            let iso = ISO8601DateFormatter()
            
            let tag = TagManager.shared.getTag(by: task.tagId)
            let tagName = tag?.name ?? "Personal"
            
            let start = task.scheduledTime ?? task.targetDate ?? task.createdAt
            let end = task.endTime
            let isAllDay = task.scheduledTime == nil && task.targetDate != nil
            let isMultiDay: Bool = {
                guard let end else { return false }
                return !calendar.isDate(start, inSameDayAs: end)
            }()
            
            // Completion history (critical for recurring events across months/years)
            let completedDatesSorted = task.completedDates.sorted()
            let completedDatesISO = completedDatesSorted.map { iso.string(from: $0) }
            let completedDatesByYear: [String: Int] = Dictionary(
                grouping: completedDatesSorted,
                by: { String(calendar.component(.year, from: $0)) }
            ).mapValues { $0.count }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .none
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            
            let startDateString = dateFormatter.string(from: start)
            let startTimeString = timeFormatter.string(from: start)
            let endTimeString = end.map { timeFormatter.string(from: $0) }
            
            var content = """
            Event: \(task.title)
            Category: \(tagName)
            """
            
            if isAllDay {
                content += "\nWhen: \(startDateString) (All-day)"
            } else if let end, let endTimeString {
                if isMultiDay {
                    let endDateString = dateFormatter.string(from: end)
                    content += "\nWhen: \(startDateString) \(startTimeString) → \(endDateString) \(endTimeString) (Multi-day)"
                } else {
                    content += "\nWhen: \(startDateString) \(startTimeString) – \(endTimeString)"
                }
            } else {
                content += "\nWhen: \(startDateString) \(startTimeString)"
            }
            
            if let location = task.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content += "\nLocation: \(location)"
            }
            
            if let description = task.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content += "\nDescription: \(description)"
            }
            
            if let reminder = task.reminderTime, reminder != .none {
                content += "\nReminder: \(reminder.displayName)"
            }
            
            if task.isRecurring {
                let freq = task.recurrenceFrequency?.displayName ?? "Recurring"
                content += "\nRecurring: Yes (\(freq))"
                if let customDays = task.customRecurrenceDays, !customDays.isEmpty {
                    content += "\nRecurs on: \(customDays.map { $0.shortDisplayName }.joined(separator: ", "))"
                }
                if let endDate = task.recurrenceEndDate {
                    content += "\nRecurs until: \(dateFormatter.string(from: endDate))"
                }
                if let parentId = task.parentRecurringTaskId {
                    content += "\nRecurring Series ID: \(parentId)"
                }
                
                // Include completion history summary for recurring events (so 2025 vs 2026 comparisons work)
                if !completedDatesSorted.isEmpty {
                    let lastN = completedDatesSorted.suffix(10)
                    let lastNStrings = lastN.map { dateFormatter.string(from: $0) }
                    content += "\nCompleted occurrences: \(completedDatesSorted.count)"
                    content += "\nCompleted by year: \(completedDatesByYear.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: ", "))"
                    content += "\nMost recent completions: \(lastNStrings.joined(separator: " • "))"
                } else {
                    content += "\nCompleted occurrences: 0"
                }
            } else {
                content += "\nRecurring: No"
            }
            
            // Calendar-synced vs app-created
            content += "\nSource: \(task.isFromCalendar ? "Calendar (read-only)" : "Seline")"
            
            // Email provenance (if created from email)
            if let emailSubject = task.emailSubject, !emailSubject.isEmpty {
                content += "\nRelated email subject: \(emailSubject)"
            }
            if let sender = task.emailSenderName, !sender.isEmpty {
                content += "\nEmail from: \(sender)"
            }
            
            return [
                "document_type": "task",
                "document_id": task.id,
                "title": task.title,
                "content": content,
                "metadata": [
                    "category": tagName,
                    "tag_id": task.tagId ?? NSNull(),
                    "is_personal": task.tagId == nil,
                    "start": iso.string(from: start),
                    "end": end.map { iso.string(from: $0) } ?? NSNull(),
                    "is_all_day": isAllDay,
                    "is_multi_day": isMultiDay,
                    "target_date": task.targetDate.map { iso.string(from: $0) } ?? NSNull(),
                    "scheduled_time": task.scheduledTime.map { iso.string(from: $0) } ?? NSNull(),
                    "end_time": task.endTime.map { iso.string(from: $0) } ?? NSNull(),
                    "weekday": task.weekday.rawValue,
                    "location": task.location ?? NSNull(),
                    "has_description": task.description != nil && !(task.description ?? "").isEmpty,
                    "reminder": task.reminderTime?.rawValue ?? NSNull(),
                    "is_completed": task.isCompleted,
                    "is_recurring": task.isRecurring,
                    "recurrence_frequency": task.recurrenceFrequency?.rawValue ?? NSNull(),
                    "recurrence_end_date": task.recurrenceEndDate.map { iso.string(from: $0) } ?? NSNull(),
                    "custom_recurrence_days": task.customRecurrenceDays?.map { $0.rawValue } ?? NSNull(),
                    "completed_date": task.completedDate.map { iso.string(from: $0) } ?? NSNull(),
                    "completed_dates": completedDatesISO.isEmpty ? NSNull() : completedDatesISO,
                    "completed_counts_by_year": completedDatesByYear.isEmpty ? NSNull() : completedDatesByYear,
                    "is_from_calendar": task.isFromCalendar,
                    "created_at": iso.string(from: task.createdAt)
                ] as [String: Any]
            ]
        }
        
        // Check which tasks need embedding (content changed or new)
        do {
            let userId = try await SupabaseManager.shared.authClient.session.user.id
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes = documents.compactMap { doc -> Int64? in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "task",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else {
                print("📅 Tasks: All \(documents.count) already embedded, skipping")
                return 0
            }
            
            let neededSet = Set(neededIds)
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            print("📅 Tasks: Embedding \(docsToEmbed.count) of \(documents.count) (\(documents.count - docsToEmbed.count) unchanged)")
            return await batchEmbed(documents: docsToEmbed, type: "task")
        } catch {
            print("❌ Error checking task embeddings: \(error)")
            // Fall back to full embed on error
            return await batchEmbed(documents: documents, type: "task")
        }
    }
    
    /// Sync location embeddings - ALL saved places (no date filter since locations don't expire)
    private func syncLocationEmbeddings() async -> Int {
        let locations = LocationsManager.shared.savedPlaces
        guard !locations.isEmpty else { return 0 }

        print("📍 Locations: Syncing all \(locations.count) saved places")
        
        let documents = locations.map { place -> [String: Any] in
            // Build comprehensive content for embedding
            var content = """
            Location: \(place.displayName)
            Address: \(place.address)
            Category: \(place.category)
            """
            
            // City/Province/Country
            if let city = place.city, !city.isEmpty {
                content += "\nCity: \(city)"
            }
            if let province = place.province, !province.isEmpty {
                content += "\nProvince/State: \(province)"
            }
            if let country = place.country, !country.isEmpty {
                content += "\nCountry: \(country)"
            }
            
            // Ratings
            if let userRating = place.userRating {
                content += "\nMy Rating: \(userRating)/10"
            }
            if let googleRating = place.rating {
                content += "\nGoogle Rating: \(String(format: "%.1f", googleRating))/5"
            }
            
            // User notes
            if let notes = place.userNotes, !notes.isEmpty {
                content += "\nMy Notes: \(notes)"
            }
            
            // Cuisine for restaurants
            if let cuisine = place.userCuisine, !cuisine.isEmpty {
                content += "\nCuisine: \(cuisine)"
            }
            
            // Favorite status
            if place.isFavourite {
                content += "\nMarked as Favorite"
            }
            
            // Phone number
            if let phone = place.phone, !phone.isEmpty {
                content += "\nPhone: \(phone)"
            }
            
            // Opening hours
            if let hours = place.openingHours, !hours.isEmpty {
                content += "\nOpening Hours:\n\(hours.joined(separator: "\n"))"
            }
            
            // Is open now
            if let isOpen = place.isOpenNow {
                content += "\nCurrently: \(isOpen ? "Open" : "Closed")"
            }
            
            return [
                "document_type": "location",
                "document_id": place.id.uuidString,
                "title": place.displayName,
                "content": content,
                "metadata": [
                    "category": place.category,
                    "city": place.city ?? NSNull(),
                    "province": place.province ?? NSNull(),
                    "country": place.country ?? NSNull(),
                    "is_favorite": place.isFavourite,
                    "user_rating": place.userRating ?? NSNull(),
                    "google_rating": place.rating ?? NSNull(),
                    "cuisine": place.userCuisine ?? NSNull(),
                    "latitude": place.latitude,
                    "longitude": place.longitude,
                    "has_notes": place.userNotes != nil && !place.userNotes!.isEmpty
                ] as [String: Any]
            ]
        }
        
        // Check which locations need embedding (content changed or new)
        do {
            let userId = try await SupabaseManager.shared.authClient.session.user.id
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes = documents.compactMap { doc -> Int64? in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "location",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else {
                print("📍 Locations: All \(documents.count) already embedded, skipping")
                return 0
            }
            
            let neededSet = Set(neededIds)
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            print("📍 Locations: Embedding \(docsToEmbed.count) of \(documents.count) (\(documents.count - docsToEmbed.count) unchanged)")
            return await batchEmbed(documents: docsToEmbed, type: "location")
        } catch {
            print("❌ Error checking location embeddings: \(error)")
            // Fall back to full embed on error
            return await batchEmbed(documents: documents, type: "location")
        }
    }
    
    /// Sync receipt embeddings - includes spending data, merchant info, categories from last 30 days
    private func syncReceiptEmbeddings() async -> Int {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

        do {
            // Receipts source-of-truth is Notes under the Receipts folder hierarchy.
            let notesManager = NotesManager.shared
            let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

            func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
                guard let folderId else { return false }
                if folderId == receiptsFolderId { return true }
                if let folder = notesManager.folders.first(where: { $0.id == folderId }),
                   let parentId = folder.parentFolderId {
                    return isUnderReceiptsFolderHierarchy(folderId: parentId)
                }
                return false
            }

            let allReceiptNotes = notesManager.notes.filter { note in
                isUnderReceiptsFolderHierarchy(folderId: note.folderId)
            }

            guard !allReceiptNotes.isEmpty else { return 0 }

            // Filter to only recent receipts (last 30 days based on extracted date or creation date)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentDaysThreshold, to: Date())!
            let recentReceiptNotes = allReceiptNotes.filter { note in
                let receiptDate = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                return receiptDate >= cutoffDate
            }

            guard !recentReceiptNotes.isEmpty else {
                print("💵 Receipts: No receipts from last \(recentDaysThreshold) days, skipping")
                return 0
            }

            print("💵 Receipts: Syncing \(recentReceiptNotes.count) of \(allReceiptNotes.count) (last \(recentDaysThreshold) days)")

            let iso = ISO8601DateFormatter()
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"

            let documents: [[String: Any]] = recentReceiptNotes.map { note in
                let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                
                var content = """
                Receipt: \(note.title)
                Total: $\(String(format: "%.2f", amount))
                Date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                Category: \(category)
                Month: \(monthYearFormatter.string(from: date))
                """
                
                if !note.content.isEmpty {
                    content += "\n\nDetails:\n\(note.content.prefix(900))"
                }
                
                return [
                    "document_type": "receipt",
                    "document_id": note.id.uuidString,
                    "title": "Receipt: \(note.title)",
                    "content": content,
                    "metadata": [
                        "merchant": note.title,
                        "amount": amount,
                        "category": category,
                        "date": iso.string(from: date),
                        "month_year": monthYearFormatter.string(from: date)
                    ] as [String: Any]
                ]
            }
            
            // Avoid re-embedding unchanged receipts (saves time + cost)
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes: [Int64] = documents.compactMap { doc in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "receipt",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else { return 0 }
            let neededSet = Set(neededIds)
            
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            guard !docsToEmbed.isEmpty else { return 0 }
            return await batchEmbed(documents: docsToEmbed, type: "receipt")
            
        } catch {
            print("❌ Error syncing receipt embeddings: \(error)")
            return 0
        }
    }

    // MARK: - Embedding Diffing (avoid re-embedding unchanged docs)
    
    private struct CheckNeededResponse: Decodable {
        let success: Bool
        let needs_embedding: [String]
        let count: Int
    }
    
    private func checkDocumentsNeedingEmbedding(
        userId: UUID,
        documentType: String,
        documentIds: [String],
        contentHashes: [Int64]
    ) async throws -> [String] {
        guard documentIds.count == contentHashes.count else { return [] }
        
        let requestBody: [String: Any] = [
            "action": "check_needed",
            "check_document_type": documentType,
            "document_ids": documentIds,
            "content_hashes": contentHashes
        ]
        
        let response: CheckNeededResponse = try await makeRequest(body: requestBody)
        return response.needs_embedding
    }
    
    /// Match the edge function's djb2 32-bit hash (signed int32), returned as Int64.
    private func hashContent32BitDjb2(_ content: String) -> Int64 {
        var hash: Int32 = 5381
        for scalar in content.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int32(scalar.value)
        }
        return Int64(hash)
    }
    
    /// Sync location visit embeddings - includes visit history, patterns, reasons from last 30 days
    private func syncLocationVisitEmbeddings() async -> Int {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

        do {
            // Embed PER-VISIT records so day queries can be answered precisely.
            // Only embed visits from last 30 days for performance
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -recentDaysThreshold, to: Date())!
            let iso = ISO8601DateFormatter()
            let cutoffISO = iso.string(from: cutoffDate)

            let client = await SupabaseManager.shared.getPostgrestClient()

            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: cutoffISO) // Only last 30 days
                .order("entry_time", ascending: false)
                .limit(2000)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            guard !visits.isEmpty else {
                print("📍 Visits: No visits from last \(recentDaysThreshold) days, skipping")
                return 0
            }

            print("📍 Visits: Syncing \(visits.count) visits (last \(recentDaysThreshold) days)")

            let locations = LocationsManager.shared.savedPlaces
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .short
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"
            
            // Build documents (one per visit)
            let documents: [[String: Any]] = visits.map { visit in
                let place = locations.first(where: { $0.id == visit.savedPlaceId })
                let placeName = place?.displayName ?? "Unknown Location"
                let placeCategory = place?.category ?? "Unknown"
                let address = place?.address
                
                let start = visit.entryTime
                let end = visit.exitTime
                let duration = visit.durationMinutes
                
                var content = """
                Location Visit: \(placeName)
                Category: \(placeCategory)
                """
                
                if let address, !address.isEmpty {
                    content += "\nAddress: \(address)"
                }
                
                if let end {
                    // If visit spans multiple days, include full timestamps to avoid ambiguity.
                    let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
                    if sameDay {
                        content += "\nWhen: \(dateFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
                    } else {
                        content += "\nWhen: \(dateFormatter.string(from: start)) → \(dateFormatter.string(from: end)) (Multi-day)"
                    }
                } else {
                    content += "\nWhen: \(dateFormatter.string(from: start)) (Ongoing or missing exit)"
                }
                
                if let duration {
                    content += "\nDuration: \(duration) minutes"
                }
                
                content += "\nDay: \(visit.dayOfWeek)"
                content += "\nTime of day: \(visit.timeOfDay)"
                
                if let notes = visit.visitNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content += "\nReason/Notes: \(notes)"
                }
                
                if let mergeReason = visit.mergeReason, !mergeReason.isEmpty {
                    content += "\nMerge info: \(mergeReason)"
                }
                
                if let score = visit.confidenceScore {
                    content += "\nConfidence: \(String(format: "%.2f", score))"
                }
                
                content += "\nMonth: \(monthYearFormatter.string(from: start))"
                
                return [
                    "document_type": "visit",
                    "document_id": visit.id.uuidString,
                    "title": "Visit: \(placeName)",
                    "content": content,
                    "metadata": [
                        "place_id": visit.savedPlaceId.uuidString,
                        "place_name": placeName,
                        "place_category": placeCategory,
                        "address": address ?? NSNull(),
                        "entry_time": iso.string(from: start),
                        "exit_time": end.map { iso.string(from: $0) } ?? NSNull(),
                        "duration_minutes": duration ?? NSNull(),
                        "day_of_week": visit.dayOfWeek,
                        "time_of_day": visit.timeOfDay,
                        "month": visit.month,
                        "year": visit.year,
                        "session_id": visit.sessionId?.uuidString ?? NSNull(),
                        "confidence_score": visit.confidenceScore ?? NSNull(),
                        "merge_reason": visit.mergeReason ?? NSNull(),
                        "visit_notes": visit.visitNotes ?? NSNull()
                    ] as [String: Any]
                ]
            }
            
            // Diff to embed only changed/new visits
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes: [Int64] = documents.compactMap { doc in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "visit",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else { return 0 }
            let neededSet = Set(neededIds)
            
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            guard !docsToEmbed.isEmpty else { return 0 }
            return await batchEmbed(documents: docsToEmbed, type: "visit")
            
        } catch {
            print("❌ Error syncing visit embeddings: \(error)")
            return 0
        }
    }
    
    /// Sync people embeddings - ALL saved people (no date filter since people don't expire)
    private func syncPeopleEmbeddings() async -> Int {
        let people = PeopleManager.shared.people
        guard !people.isEmpty else { return 0 }
        
        print("👥 People: Syncing all \(people.count) saved people")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        
        let documents = people.map { person -> [String: Any] in
            var content = """
            Person: \(person.name)
            Relationship: \(person.relationshipDisplayText)
            """
            
            // Nickname
            if let nickname = person.nickname, !nickname.isEmpty {
                content += "\nNickname: \(nickname)"
            }
            
            // Birthday
            if let birthday = person.birthday {
                content += "\nBirthday: \(dateFormatter.string(from: birthday))"
                if let age = person.age {
                    content += " (Age: \(age))"
                }
            }
            
            // Favourite food
            if let food = person.favouriteFood, !food.isEmpty {
                content += "\nFavourite Food: \(food)"
            }
            
            // Gift ideas
            if let gift = person.favouriteGift, !gift.isEmpty {
                content += "\nGift Ideas: \(gift)"
            }
            
            // Favourite color
            if let color = person.favouriteColor, !color.isEmpty {
                content += "\nFavourite Color: \(color)"
            }
            
            // Interests
            if let interests = person.interests, !interests.isEmpty {
                content += "\nInterests: \(interests.joined(separator: ", "))"
            }
            
            // Contact info
            if let phone = person.phone, !phone.isEmpty {
                content += "\nPhone: \(phone)"
            }
            if let email = person.email, !email.isEmpty {
                content += "\nEmail: \(email)"
            }
            if let address = person.address, !address.isEmpty {
                content += "\nAddress: \(address)"
            }
            
            // Social links
            if let instagram = person.instagram, !instagram.isEmpty {
                content += "\nInstagram: @\(instagram)"
            }
            if let linkedIn = person.linkedIn, !linkedIn.isEmpty {
                content += "\nLinkedIn: \(linkedIn)"
            }
            
            // How we met
            if let howWeMet = person.howWeMet, !howWeMet.isEmpty {
                content += "\nHow We Met: \(howWeMet)"
            }
            
            // Notes
            if let notes = person.notes, !notes.isEmpty {
                content += "\nNotes: \(notes)"
            }
            
            // Favorite status
            if person.isFavourite {
                content += "\nMarked as Favorite"
            }
            
            return [
                "document_type": "person",
                "document_id": person.id.uuidString,
                "title": person.name,
                "content": content,
                "metadata": [
                    "name": person.name,
                    "nickname": person.nickname ?? NSNull(),
                    "relationship": person.relationship.rawValue,
                    "birthday": person.formattedBirthday ?? NSNull(),
                    "favourite_food": person.favouriteFood ?? NSNull(),
                    "favourite_gift": person.favouriteGift ?? NSNull(),
                    "favourite_color": person.favouriteColor ?? NSNull(),
                    "is_favourite": person.isFavourite
                ] as [String: Any]
            ]
        }
        
        // Diff to embed only changed/new people
        do {
            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }
            
            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes: [Int64] = documents.compactMap { doc in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }
            
            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: "person",
                documentIds: ids,
                contentHashes: hashes
            )
            
            guard !neededIds.isEmpty else { return 0 }
            let neededSet = Set(neededIds)
            
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }
            
            guard !docsToEmbed.isEmpty else { return 0 }
            return await batchEmbed(documents: docsToEmbed, type: "person")
            
        } catch {
            print("❌ Error checking people embeddings: \(error)")
            // Fall back to full embed on error
            return await batchEmbed(documents: documents, type: "person")
        }
    }
    
    
    /// Batch embed documents
    private func batchEmbed(documents: [[String: Any]], type: String) async -> Int {
        guard !documents.isEmpty else { return 0 }
        
        // Process in batches
        var embedded = 0
        for batchStart in stride(from: 0, to: documents.count, by: maxBatchSize) {
            let batchEnd = min(batchStart + maxBatchSize, documents.count)
            let batch = Array(documents[batchStart..<batchEnd])
            
            let requestBody: [String: Any] = [
                "action": "batch_embed",
                "documents": batch
            ]
            
            do {
                let response: BatchEmbedResponse = try await makeRequest(body: requestBody)
                embedded += response.embedded
                
                if response.failed > 0 {
                    print("⚠️ \(response.failed) \(type)s failed to embed")
                    if let results = response.results {
                        let failedItems = results.filter { !$0.success }
                        for item in failedItems {
                            print("   — \(type) \(item.document_id): \(item.error ?? "unknown")")
                        }
                    }
                }
            } catch {
                print("❌ Batch embed error for \(type): \(error)")
            }
        }
        
        return embedded
    }
    
    // MARK: - Single Document Embedding
    
    /// Embed a single document (call after creating/updating)
    func embedDocument(
        type: DocumentType,
        id: String,
        title: String?,
        content: String,
        metadata: [String: Any] = [:]
    ) async throws {
        let requestBody: [String: Any] = [
            "action": "embed",
            "document_type": type.rawValue,
            "document_id": id,
            "title": title ?? NSNull(),
            "content": content,
            "metadata": metadata
        ]
        
        let _: EmbedResponse = try await makeRequest(body: requestBody)
        print("✅ Embedded \(type.rawValue): \(title ?? id)")
    }
    
    /// Delete embedding when document is deleted
    func deleteEmbedding(type: DocumentType, id: String) async {
        // Note: This is handled by CASCADE on foreign key
        // But we can also call the delete RPC directly if needed
        print("🗑️ Embedding will be deleted with document: \(type.rawValue)/\(id)")
    }
    
    // MARK: - Network
    
    private func makeRequest<T: Decodable>(body: [String: Any]) async throws -> T {
        let functionURL = "\(SupabaseManager.shared.url)/functions/v1/embeddings-proxy"
        
        guard let url = URL(string: functionURL) else {
            throw VectorSearchError.invalidURL
        }
        
        // Get auth token
        let token: String
        do {
            let session = try await SupabaseManager.shared.authClient.session
            token = session.accessToken
        } catch {
            throw VectorSearchError.notAuthenticated
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseManager.shared.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VectorSearchError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(VectorSearchErrorResponse.self, from: data) {
                throw VectorSearchError.apiError(errorResponse.error)
            }
            throw VectorSearchError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Types
    
    enum DocumentType: String, CaseIterable {
        case note = "note"
        case email = "email"
        case task = "task"
        case location = "location"
        case receipt = "receipt"
        case visit = "visit"
        case person = "person"
        
        var displayName: String {
            switch self {
            case .note: return "Notes"
            case .email: return "Emails"
            case .task: return "Events/Tasks"
            case .location: return "Locations"
            case .receipt: return "Receipts"
            case .visit: return "Visits"
            case .person: return "People"
            }
        }
    }
    
    struct SearchResult {
        let documentType: DocumentType
        let documentId: String
        let title: String?
        let content: String
        let metadata: [String: Any]?
        let similarity: Float
    }
    
    enum VectorSearchError: LocalizedError {
        case invalidURL
        case notAuthenticated
        case invalidResponse
        case apiError(String)
        case httpError(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .notAuthenticated: return "User not authenticated"
            case .invalidResponse: return "Invalid response from server"
            case .apiError(let message): return "API error: \(message)"
            case .httpError(let code): return "HTTP error: \(code)"
            }
        }
    }
}

// MARK: - Response Types

private struct SearchResponse: Decodable {
    let success: Bool
    let results: [SearchResultItem]
    let count: Int
    
    struct SearchResultItem: Decodable {
        let document_type: String
        let document_id: String
        let title: String?
        let content: String
        let metadata: [String: Any]?
        let similarity: Float
        
        enum CodingKeys: String, CodingKey {
            case document_type, document_id, title, content, metadata, similarity
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            document_type = try container.decode(String.self, forKey: .document_type)
            document_id = try container.decode(String.self, forKey: .document_id)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            content = try container.decode(String.self, forKey: .content)
            similarity = try container.decode(Float.self, forKey: .similarity)
            
            // Decode metadata as dictionary
            if let metadataDict = try? container.decode([String: VectorSearchAnyCodable].self, forKey: .metadata) {
                metadata = metadataDict.mapValues { $0.value }
            } else {
                metadata = nil
            }
        }
    }
}

private struct BatchEmbedResponse: Decodable {
    let success: Bool
    let total: Int
    let embedded: Int
    let failed: Int
    let results: [BatchEmbedResultItem]?
}

private struct BatchEmbedResultItem: Decodable {
    let document_id: String
    let success: Bool
    let error: String?
}

private struct EmbedResponse: Decodable {
    let success: Bool
    let document_id: String
    let dimensions: Int
}

private struct VectorSearchErrorResponse: Decodable {
    let error: String
}

// MARK: - VectorSearchAnyCodable Helper

private struct VectorSearchAnyCodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([VectorSearchAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: VectorSearchAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = "" // Fallback
        }
    }
}

