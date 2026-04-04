import Foundation

/**
 * VectorSearchService - Semantic Search for LLM Context
 *
 * This service provides vector-based semantic search using OpenAI text-embedding-3-small
 * (1536 dimensions) stored in Supabase pgvector with HNSW indexing.
 * It replaces keyword matching with AI-powered similarity search.
 *
 * Key features:
 * - 1536-dimension embeddings (supports HNSW index for fast search)
 * - Semantic search across notes, emails, tasks, locations, receipts, visits, people,
 *   recurring expenses, attachments, trackers, and budgets/reminders
 * - Automatic embedding generation and caching
 * - Background sync to keep embeddings up-to-date
 * - Efficient batch processing
 *
 * IMPORTANT: After updating embedding model, run syncEmbeddingsImmediately() to re-index all documents
 */
class VectorSearchService: ObservableObject {
    static let shared = VectorSearchService()

    // MARK: - Published State
    // @MainActor on each @Published property ensures mutations happen on the main thread
    // while heavy embedding/search computation can run on background threads.

    @MainActor @Published var isIndexing = false
    @MainActor @Published var lastSyncTime: Date?
    @MainActor @Published var embeddingsCount: Int = 0

    // MARK: - Embedding Progress Tracking
    @MainActor @Published var embeddingProgress: Double = 0.0 // 0.0 to 1.0
    @MainActor @Published var embeddingStatus: String = "Ready" // Status message
    @MainActor @Published var hasCompletedFirstSync: Bool = false // Track if first sync done
    
    // MARK: - Configuration

    private let maxBatchSize = 50 // Max documents per batch
    private let similarityThreshold: Float = 0.22 // Higher precision to reduce noisy context contamination
    private let defaultResultLimit = 15 // Reduced from 50 to 15 for better UI performance
    private let searchCandidateMultiplier = 3
    private let historicalSearchCandidateMultiplier = 8
    private let historicalBackfillPageSize = 50
    private let historicalBackfillPagesPerMailbox = 12
    private let historicalBackfillCoverageYears = 1
    private let historicalBackfillRefreshInterval: TimeInterval = 60 * 60 * 6
    private let visitEmbeddingRefreshCooldown: TimeInterval = 60
    // Removed recentDaysThreshold - now embedding ALL historical data
    
    // MARK: - Cache

    private var lastSyncedHashes: [String: Int] = [:] // document_id -> content_hash
    private var memoryAnnotationCache: [String: String] = [:] // title -> annotated title
    private var cachedMemories: [MemorySupabaseData] = []
    private var lastMemoryFetchTime: Date?
    private var cachedHistoricalEmailsForEmbedding: [(email: Email, mailbox: String)] = []
    private var lastHistoricalEmailBackfill: Date?
    private var lastVisitEmbeddingRefresh: Date?
    private var interactiveRequestCount = 0
    private var pendingFullSyncRequested = false
    private let gmailAPIClient = GmailAPIClient.shared
    private let keywordStopWords: Set<String> = [
        "a", "an", "all", "am", "and", "any", "are", "as", "at",
        "be", "been", "being", "both", "but", "by",
        "can", "count",
        "did", "do", "does", "done",
        "each", "ever",
        "for", "from",
        "give", "had", "has", "have", "having", "how",
        "i", "id", "if", "in", "into", "is", "it", "its", "ive",
        "just",
        "list",
        "me", "more", "most", "my",
        "of", "on", "or", "our", "out", "over",
        "please",
        "show",
        "tell", "than", "that", "the", "their", "them", "then", "there", "these", "they", "this", "those", "to",
        "up",
        "was", "we", "were", "what", "when", "where", "which", "who", "with",
        "you", "your"
    ]

    enum RetrievalMode: String {
        case topK = "top_k"
        case exhaustive = "exhaustive"
    }

    enum ContextPresentation: Equatable {
        case detailed
        case compactTimeline
        case latestOnly
    }

    struct RetrievalAdmission {
        let maxSearchQueries: Int
        let maxMergedResults: Int
        let maxPreviewCharacters: Int
        let maxCanonicalRecords: Int
        let maxEvidenceItems: Int
        let minimumAnchorMatches: Int
        let perTypeCaps: [DocumentType: Int]
    }
    
    // MARK: - Initialization
    
    private init() {
        // Restore last sync time from disk so the cooldown survives app kills/restarts.
        // Without this, lastSyncTime is always nil on launch and a full sync fires immediately.
        if let savedInterval = UserDefaults.standard.object(forKey: "vectorSearch.lastSyncTime") as? TimeInterval {
            let restored = Date(timeIntervalSince1970: savedInterval)
            Task { @MainActor in
                self.lastSyncTime = restored
            }
        }
        // Start background sync on init
        Task {
            await syncEmbeddingsIfNeeded()
        }
    }

    private struct NotesSnapshot {
        let notes: [Note]
        let folderNamesById: [UUID: String]
        let notesById: [UUID: Note]
    }

    private struct BudgetSnapshot {
        let budgets: [(budget: ExpenseBudget, status: ExpenseBudgetStatus)]
        let reminders: [ExpenseReminder]
    }

    private struct LinkedReceiptContext {
        let parsedDate: Date
        let category: String?
    }

    private func notesSnapshot() async -> NotesSnapshot {
        await MainActor.run {
            let notesManager = NotesManager.shared
            let notes = notesManager.notes
            return NotesSnapshot(
                notes: notes,
                folderNamesById: Dictionary(
                    uniqueKeysWithValues: notesManager.folders.map { ($0.id, $0.name) }
                ),
                notesById: Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            )
        }
    }

    private func emailSnapshot() async -> [(email: Email, mailbox: String)] {
        await MainActor.run {
            let emailService = EmailService.shared
            return emailService.inboxEmails.map { ($0, "inbox") } +
                emailService.sentEmails.map { ($0, "sent") }
        }
    }

    private func taskSnapshot() async -> [TaskItem] {
        await MainActor.run {
            TaskManager.shared.tasks.values
                .flatMap { $0 }
                .filter { !$0.isDeleted }
        }
    }

    private func tagsByIdSnapshot() async -> [String: Tag] {
        await MainActor.run {
            let tagsById: [String: Tag] = Dictionary(
                uniqueKeysWithValues: TagManager.shared.tags.map { ($0.id, $0) }
            )
            return tagsById
        }
    }

    private func budgetSnapshot() async -> BudgetSnapshot {
        await MainActor.run {
            let budgetService = ExpenseBudgetService.shared
            return BudgetSnapshot(
                budgets: budgetService.budgets.map { ($0, budgetService.status(for: $0)) },
                reminders: ExpenseReminderService.shared.reminders
            )
        }
    }

    private func trackerThreadsSnapshot() async -> [TrackerThread] {
        await MainActor.run {
            TrackerStore.shared.threads
        }
    }

    private func receiptStatsSnapshot() async -> [ReceiptStat] {
        await MainActor.run {
            ReceiptManager.shared.receipts
        }
    }

    private func linkedReceiptContextByNoteId(
        noteIds: Set<UUID>,
        notesById: [UUID: Note]
    ) async -> [UUID: LinkedReceiptContext] {
        guard !noteIds.isEmpty else { return [:] }

        return await MainActor.run {
            let notesManager = NotesManager.shared
            let categorizationService = ReceiptCategorizationService.shared

            return noteIds.reduce(into: [UUID: LinkedReceiptContext]()) { partialResult, noteId in
                guard let note = notesById[noteId] else { return }
                partialResult[noteId] = LinkedReceiptContext(
                    parsedDate: notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated,
                    category: categorizationService.quickCategorizeReceipt(
                        title: note.title,
                        content: note.content
                    )
                )
            }
        }
    }

    private func isIndexingSnapshot() async -> Bool {
        await MainActor.run { self.isIndexing }
    }

    private func lastSyncTimeSnapshot() async -> Date? {
        await MainActor.run { self.lastSyncTime }
    }

    private func beginSyncState() async {
        await MainActor.run {
            self.isIndexing = true
            self.embeddingProgress = 0.0
            self.embeddingStatus = "Starting sync..."
        }
    }

    private func updateSyncState(status: String? = nil, progress: Double? = nil) async {
        await MainActor.run {
            if let status {
                self.embeddingStatus = status
            }
            if let progress {
                self.embeddingProgress = progress
            }
        }
    }

    private func completeSyncState(totalCount: Int, completedAt: Date) async {
        await MainActor.run {
            self.isIndexing = false
            self.embeddingProgress = 1.0
            self.embeddingStatus = "Complete"
            self.embeddingsCount = totalCount
            self.lastSyncTime = completedAt
            self.hasCompletedFirstSync = true
            // Persist so the cooldown survives app kills
            UserDefaults.standard.set(completedAt.timeIntervalSince1970, forKey: "vectorSearch.lastSyncTime")
        }
    }
    
    // MARK: - Semantic Search
    
    /// Search for documents semantically similar to a query
    /// Returns the most relevant notes, emails, tasks, and locations
    func search(
        query: String,
        documentTypes: [DocumentType]? = nil,
        limit: Int = 15,
        dateRange: (start: Date, end: Date)? = nil,
        preferHistorical: Bool = false,
        retrievalMode: RetrievalMode = .topK,
        admission: RetrievalAdmission? = nil
    ) async throws -> [SearchResult] {
        let normalizedQuery = normalizeWhitespace(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let candidateMultiplier = candidateMultiplier(
            for: retrievalMode,
            preferHistorical: preferHistorical
        )
        let expandedQueries = await expandedSearchQueries(
            for: normalizedQuery,
            retrievalMode: retrievalMode
        )
        let searchQueries = Array(
            expandedQueries.prefix(
                max(1, admission?.maxSearchQueries ?? defaultSearchQueryLimit(for: retrievalMode))
            )
        )
        let computedServerResultLimit = serverResultLimit(
            for: limit,
            candidateMultiplier: candidateMultiplier,
            retrievalMode: retrievalMode,
            preferHistorical: preferHistorical
        )
        let serverResultLimit = min(
            computedServerResultLimit,
            max(limit, (admission?.maxMergedResults ?? computedServerResultLimit) * 2)
        )

        var mergedRawResults: [String: SearchResponse.SearchResultItem] = [:]
        for searchQuery in searchQueries {
            let rawResults = try await semanticSearchResults(
                query: searchQuery,
                documentTypes: documentTypes,
                limit: serverResultLimit,
                dateRange: dateRange
            )

            for result in rawResults {
                let key = "\(result.document_type)::\(result.document_id)"
                if let existing = mergedRawResults[key] {
                    if result.similarity > existing.similarity {
                        mergedRawResults[key] = result
                    }
                } else {
                    mergedRawResults[key] = result
                }
            }
        }

        let effectiveCap = effectiveResultCap(
            for: limit,
            retrievalMode: retrievalMode,
            preferHistorical: preferHistorical
        )
        let resultCap: Int = {
            guard let admission else { return effectiveCap }
            if admission.minimumAnchorMatches > 0 {
                return min(effectiveCap, max(admission.maxMergedResults * 3, admission.maxMergedResults))
            }
            return min(effectiveCap, max(1, admission.maxMergedResults))
        }()

        var rawResults = mergedRawResults.values.sorted { $0.similarity > $1.similarity }
        rawResults = Array(rawResults.prefix(resultCap))

        // Log search results and similarity scores
        if !rawResults.isEmpty {
            print("🔍 Vector search returned \(rawResults.count) results (threshold: \(similarityThreshold)):")
            for (index, result) in rawResults.prefix(5).enumerated() {
                let similarityPercent = Int(result.similarity * 100)
                print("   \(index + 1). [\(similarityPercent)%] \(result.title ?? result.document_type) - \(result.content.prefix(60))...")
            }
            if rawResults.count > 5 {
                print("   ... and \(rawResults.count - 5) more results")
            }
        } else {
            print("🔍 Vector search returned 0 results (threshold: \(similarityThreshold)) - no matches found")
        }

        // Apply query-aware recency boost to vector results
        let recencyWeight = recencyWeight(
            for: normalizedQuery,
            dateRange: dateRange,
            preferHistorical: preferHistorical,
            retrievalMode: retrievalMode
        )
        let vectorResults = rawResults.map { result -> SearchResult in
            let baseScore = result.similarity
            let recencyScore = calculateRecencyScore(metadata: result.metadata)
            let boostedScore = ((1 - recencyWeight) * baseScore) + (recencyWeight * recencyScore)

            return SearchResult(
                documentType: DocumentType(rawValue: result.document_type) ?? .note,
                documentId: result.document_id,
                title: result.title,
                content: result.content,
                metadata: result.metadata,
                similarity: boostedScore
            )
        }

        // Hybrid keyword search (in-memory) for better recall
        let keywordResults = await keywordSearch(
            queries: searchQueries,
            dateRange: dateRange,
            documentTypes: documentTypes,
            recencyWeight: recencyWeight,
            retrievalMode: retrievalMode
        )

        // Merge results (dedupe by type + id, keep highest score)
        var merged: [String: SearchResult] = [:]
        for result in vectorResults + keywordResults {
            let key = "\(result.documentType.rawValue)::\(result.documentId)"
            if let existing = merged[key] {
                if result.similarity > existing.similarity {
                    merged[key] = result
                }
            } else {
                merged[key] = result
            }
        }

        var rankedResults = merged.values.sorted { $0.similarity > $1.similarity }
        if let admission, admission.minimumAnchorMatches > 0 {
            let anchorTokens = anchorTokens(from: searchQueries)
            if !anchorTokens.isEmpty {
                let filteredResults = rankedResults
                    .compactMap { result -> (SearchResult, Int)? in
                        let matchCount = anchorMatchCount(for: result, anchorTokens: anchorTokens)
                        guard matchCount >= admission.minimumAnchorMatches else { return nil }
                        return (result, matchCount)
                    }
                    .sorted { lhs, rhs in
                        if lhs.1 == rhs.1 {
                            return lhs.0.similarity > rhs.0.similarity
                        }
                        return lhs.1 > rhs.1
                    }
                    .map(\.0)

                if !filteredResults.isEmpty {
                    rankedResults = filteredResults
                }
            }
        }

        let mergedResults = Array(
            rankedResults
                .prefix(max(1, admission?.maxMergedResults ?? Int.max))
        )
        logSearchDiagnostics(
            query: normalizedQuery,
            preferHistorical: preferHistorical,
            dateRange: dateRange,
            results: mergedResults,
            retrievalMode: retrievalMode,
            searchQueries: searchQueries
        )
        return mergedResults
    }
    
    /// Search and return formatted context + exact evidence used by the context.
    func getRelevantContext(
        forQuery query: String,
        limit: Int = 50,  // Increased from 15 to 50 for better historical data retrieval
        documentTypes: [DocumentType]? = nil,
        dateRange: (start: Date, end: Date)? = nil,
        preferHistorical: Bool = false,
        retrievalMode: RetrievalMode = .topK,
        presentation: ContextPresentation = .detailed,
        admission: RetrievalAdmission? = nil
    ) async throws -> RelevantContextResult {
        let results = try await search(
            query: query,
            documentTypes: documentTypes,
            limit: limit,
            dateRange: dateRange,
            preferHistorical: preferHistorical,
            retrievalMode: retrievalMode,
            admission: admission
        )

        let admittedResults = admitResults(results, admission: admission)
        guard !admittedResults.isEmpty else {
            return RelevantContextResult(context: "", evidence: [])
        }

        let memories = await fetchAllMemories()
        if presentation != .detailed {
            return buildCompactTimelineContext(
                from: admittedResults,
                preferHistorical: preferHistorical,
                presentation: presentation,
                admission: admission,
                memories: memories
            )
        }

        let contextLabel = retrievalMode == .exhaustive ? "Exhaustive Retrieval" : "Semantic Search"
        var context = "=== RELEVANT DATA (\(contextLabel)) ===\n"
        context += "Query matched \(admittedResults.count) items after retrieval and ranking:\n\n"
        var evidence: [RelevantContentInfo] = []
        var seenEvidenceKeys = Set<String>()

        // Group by document type with per-type caps
        let grouped = Dictionary(grouping: admittedResults) { $0.documentType }
        var perTypeCaps: [DocumentType: Int]
        switch (retrievalMode, preferHistorical) {
        case (.exhaustive, true):
            perTypeCaps = [
                .email: 24,
                .task: 22,
                .visit: 22,
                .receipt: 20,
                .note: 18,
                .tracker: 16,
                .attachment: 14,
                .recurringExpense: 14,
                .budget: 12,
                .location: 12,
                .person: 12
            ]
        case (.exhaustive, false):
            perTypeCaps = [
                .email: 16,
                .task: 18,
                .visit: 18,
                .receipt: 16,
                .note: 14,
                .tracker: 12,
                .attachment: 10,
                .recurringExpense: 10,
                .budget: 8,
                .location: 10,
                .person: 10
            ]
        case (.topK, true):
            perTypeCaps = [
                .email: 18,
                .task: 16,
                .visit: 16,
                .receipt: 14,
                .note: 14,
                .tracker: 12,
                .attachment: 10,
                .recurringExpense: 10,
                .budget: 8,
                .location: 10,
                .person: 10
            ]
        case (.topK, false):
            perTypeCaps = [
                .email: 8,
                .task: 10,
                .visit: 10,
                .receipt: 8,
                .note: 8,
                .tracker: 6,
                .attachment: 6,
                .recurringExpense: 6,
                .budget: 4,
                .location: 6,
                .person: 6
            ]
        }

        if let admission {
            for (type, cap) in admission.perTypeCaps {
                perTypeCaps[type] = cap
            }
        }

        for (type, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let cap = perTypeCaps[type] ?? 6
            let limitedItems = Array(items.prefix(cap))
            context += "**\(type.displayName) (\(limitedItems.count) matches):**\n"

            for item in limitedItems {
                let similarity = String(format: "%.0f%%", item.similarity * 100)
                context += "• [\(similarity) match] "

                if let title = item.title, !title.isEmpty {
                    // ENHANCEMENT: Annotate with memory context (using batched memories)
                    let annotatedTitle = annotateWithMemory(title, memories: memories)
                    context += "**\(annotatedTitle)**\n"
                }

                let previewLength = min(
                    retrievalMode == .exhaustive ? 220 : 800,
                    max(80, admission?.maxPreviewCharacters ?? Int.max)
                )
                let preview = item.content.prefix(previewLength)
                context += "  \(preview)"
                if item.content.count > previewLength {
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

                if let mappedEvidence = mapResultToEvidence(item) {
                    let evidenceKey = evidenceDedupKey(for: mappedEvidence)
                    if !seenEvidenceKeys.contains(evidenceKey),
                       evidence.count < max(1, admission?.maxEvidenceItems ?? Int.max) {
                        seenEvidenceKeys.insert(evidenceKey)
                        evidence.append(mappedEvidence)
                    }
                }
            }
        }

        return RelevantContextResult(context: context, evidence: evidence)
    }

    private struct CompactTimelineRecord {
        let day: Date?
        let label: String
        var sourceTypes: Set<DocumentType>
        var bestScore: Float
        var sourceCount: Int
        var totalSpend: Double
        var receiptCount: Int
        var evidence: [RelevantContentInfo]
    }

    private func buildCompactTimelineContext(
        from results: [SearchResult],
        preferHistorical: Bool,
        presentation: ContextPresentation,
        admission: RetrievalAdmission?,
        memories: [MemorySupabaseData]
    ) -> RelevantContextResult {
        let calendar = Calendar.current
        var groupedRecords: [String: CompactTimelineRecord] = [:]

        for result in results {
            let day = extractDateForRecency(from: result.metadata ?? [:]).map { calendar.startOfDay(for: $0) }
            if day == nil && (result.documentType == .location || result.documentType == .person) {
                continue
            }

            let label = compactTimelineLabel(for: result, memories: memories)
            guard !label.isEmpty else { continue }

            let normalizedLabel = normalizeAliasText(label)
            guard !normalizedLabel.isEmpty else { continue }

            let dayKey = day.map { String(Int($0.timeIntervalSince1970)) } ?? "undated"
            let key = "\(dayKey)::\(normalizedLabel)"
            let mappedEvidence = mapResultToEvidence(result)
            let spendAmount = mappedEvidence?.receiptAmount ?? metadataDouble(result.metadata?["amount"]) ?? extractCurrencyAmount(from: result.content) ?? 0

            if var existing = groupedRecords[key] {
                existing.sourceTypes.insert(result.documentType)
                existing.bestScore = max(existing.bestScore, result.similarity)
                existing.sourceCount += 1
                existing.totalSpend += spendAmount
                if result.documentType == .receipt {
                    existing.receiptCount += 1
                }
                if let mappedEvidence,
                   existing.evidence.count < 3,
                   !existing.evidence.contains(where: { evidenceDedupKey(for: $0) == evidenceDedupKey(for: mappedEvidence) }) {
                    existing.evidence.append(mappedEvidence)
                }
                groupedRecords[key] = existing
            } else {
                groupedRecords[key] = CompactTimelineRecord(
                    day: day,
                    label: label,
                    sourceTypes: [result.documentType],
                    bestScore: result.similarity,
                    sourceCount: 1,
                    totalSpend: spendAmount,
                    receiptCount: result.documentType == .receipt ? 1 : 0,
                    evidence: mappedEvidence.map { [$0] } ?? []
                )
            }
        }

        var compactRecords = groupedRecords.values
            .filter { record in
                if record.day == nil && record.sourceTypes == Set([.location]) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                switch (lhs.day, rhs.day) {
                case let (leftDate?, rightDate?):
                    if leftDate == rightDate {
                        return lhs.bestScore > rhs.bestScore
                    }
                    return preferHistorical ? (leftDate < rightDate) : (leftDate > rightDate)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.bestScore > rhs.bestScore
                }
            }

        if presentation == .latestOnly, let latestRecord = compactRecords.first {
            compactRecords = [latestRecord]
        }

        let defaultMaxRecords = presentation == .latestOnly ? 1 : (preferHistorical ? 60 : 40)
        let maxRecords = min(defaultMaxRecords, max(1, admission?.maxCanonicalRecords ?? defaultMaxRecords))
        let totalCanonicalRecords = compactRecords.count
        let displayedRecords = Array(compactRecords.prefix(maxRecords))
        let isTruncated = totalCanonicalRecords > displayedRecords.count

        var context = "=== CANONICAL MATCHES ===\n"
        context += "Canonical records found: \(totalCanonicalRecords)\n"
        context += "Each line merges duplicate notes, receipts, visits, emails, and tasks for the same day/topic.\n"
        if isTruncated {
            context += "Showing the first \(displayedRecords.count) canonical records within the context budget.\n"
        }
        context += "\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        var evidence: [RelevantContentInfo] = []
        var seenEvidenceKeys = Set<String>()
        let evidenceLimit = max(1, admission?.maxEvidenceItems ?? Int.max)

        for record in displayedRecords {
            let dateLabel = record.day.map { formatter.string(from: $0) } ?? "Undated"
            let typesLabel = record.sourceTypes
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map(\.displayName)
                .joined(separator: ", ")
            context += "- \(dateLabel): \(record.label)"
            if !typesLabel.isEmpty {
                context += " [\(typesLabel)]"
            }
            if record.sourceCount > 1 {
                context += " (\(record.sourceCount) sources)"
            }
            if record.totalSpend > 0 {
                if record.receiptCount <= 1 {
                    context += " - $\(String(format: "%.2f", record.totalSpend))"
                } else {
                    context += " - total $\(String(format: "%.2f", record.totalSpend))"
                }
            }
            context += "\n"

            for item in record.evidence {
                let key = evidenceDedupKey(for: item)
                if !seenEvidenceKeys.contains(key), evidence.count < evidenceLimit {
                    seenEvidenceKeys.insert(key)
                    evidence.append(item)
                }
            }
        }

        return RelevantContextResult(context: context, evidence: evidence)
    }

    private func candidateMultiplier(
        for retrievalMode: RetrievalMode,
        preferHistorical: Bool
    ) -> Int {
        let baseMultiplier = preferHistorical ? historicalSearchCandidateMultiplier : searchCandidateMultiplier

        switch retrievalMode {
        case .topK:
            return baseMultiplier
        case .exhaustive:
            return max(baseMultiplier, preferHistorical ? 9 : 5)
        }
    }

    private func defaultSearchQueryLimit(for retrievalMode: RetrievalMode) -> Int {
        switch retrievalMode {
        case .topK:
            return 2
        case .exhaustive:
            return 3
        }
    }

    private func admitResults(
        _ results: [SearchResult],
        admission: RetrievalAdmission?
    ) -> [SearchResult] {
        guard let admission else { return results }
        return Array(results.prefix(max(1, admission.maxMergedResults)))
    }

    private func anchorTokens(from queries: [String]) -> [String] {
        keywordTokens(from: queries).filter { token in
            token.count >= 3
        }
    }

    private func anchorMatchCount(for result: SearchResult, anchorTokens: [String]) -> Int {
        let searchable = searchableAnchorText(for: result)
        guard !searchable.isEmpty else { return 0 }
        return anchorTokens.reduce(into: 0) { count, token in
            if searchable.contains(token) {
                count += 1
            }
        }
    }

    private func searchableAnchorText(for result: SearchResult) -> String {
        var fragments: [String] = []
        if let title = result.title, !title.isEmpty {
            fragments.append(title)
        }
        fragments.append(result.content)

        if let metadata = result.metadata {
            for key in [
                "merchant",
                "place_name",
                "location",
                "address",
                "sender",
                "subject",
                "category",
                "aliases"
            ] {
                if let value = metadata[key] as? String, !value.isEmpty {
                    fragments.append(value)
                } else if let values = metadata[key] as? [String], !values.isEmpty {
                    fragments.append(values.joined(separator: " "))
                }
            }
        }

        return normalizeWhitespace(fragments.joined(separator: " ").lowercased())
    }

    private func serverResultLimit(
        for limit: Int,
        candidateMultiplier: Int,
        retrievalMode: RetrievalMode,
        preferHistorical: Bool
    ) -> Int {
        let proposedLimit = max(limit, 1) * max(candidateMultiplier, 1)

        switch (retrievalMode, preferHistorical) {
        case (.exhaustive, true):
            return min(proposedLimit, 160)
        case (.exhaustive, false):
            return min(proposedLimit, 120)
        case (.topK, true):
            return min(proposedLimit, 180)
        case (.topK, false):
            return min(proposedLimit, 60)
        }
    }

    private func effectiveResultCap(
        for limit: Int,
        retrievalMode: RetrievalMode,
        preferHistorical: Bool
    ) -> Int {
        switch (retrievalMode, preferHistorical) {
        case (.exhaustive, true):
            return min(max(limit * 2, limit + 24), 140)
        case (.exhaustive, false):
            return min(max(limit * 2, limit + 16), 90)
        case (.topK, true):
            return limit * 2
        case (.topK, false):
            return limit
        }
    }

    private func semanticSearchResults(
        query: String,
        documentTypes: [DocumentType]?,
        limit: Int,
        dateRange: (start: Date, end: Date)?
    ) async throws -> [SearchResponse.SearchResultItem] {
        var requestBody: [String: Any] = [
            "action": "search",
            "query": query,
            "document_types": documentTypes?.map { $0.rawValue } ?? NSNull(),
            "limit": limit,
            "similarity_threshold": similarityThreshold
        ]

        if let dateRange {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            requestBody["date_range_start"] = iso.string(from: dateRange.start)
            requestBody["date_range_end"] = iso.string(from: dateRange.end)
        }

        let response: SearchResponse = try await makeRequest(body: requestBody)

        var rawResults = response.results
        let beforeFilterCount = rawResults.count
        if let dateRange {
            rawResults = rawResults.filter { result in
                matchesDateRange(metadata: result.metadata, dateRange: dateRange)
            }
        }

        if dateRange != nil {
            print("🔍 Vector search[\(query.prefix(48))]: \(beforeFilterCount) raw results, \(rawResults.count) after date filter")
            if beforeFilterCount > 0 && rawResults.count == 0 {
                print("⚠️ ALL results filtered by date - metadata may be missing date fields")
            }
        }

        return rawResults
    }

    private func expandedSearchQueries(
        for query: String,
        retrievalMode: RetrievalMode
    ) async -> [String] {
        let normalizedQuery = normalizeWhitespace(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var orderedQueries = [normalizedQuery]
        var seenQueries = Set([normalizedQuery.lowercased()])
        let maxExpansionCount = retrievalMode == .exhaustive ? 2 : 1
        let expansions = await UserMemoryService.shared.expandQuery(normalizedQuery)
        let normalizedExpansions = expansions
            .prefix(maxExpansionCount)
            .map { normalizeWhitespace($0) }
            .filter { isMeaningfulAliasPhrase($0) }

        if retrievalMode == .exhaustive {
            if let firstExpansion = normalizedExpansions.first {
                let combinedVariant = normalizeWhitespace(
                    "\(normalizedQuery) \(normalizedExpansions.joined(separator: " "))"
                )
                let variants = [combinedVariant, firstExpansion]
                for variant in variants {
                    let key = variant.lowercased()
                    guard !variant.isEmpty, !seenQueries.contains(key) else { continue }
                    seenQueries.insert(key)
                    orderedQueries.append(variant)
                }
            }
        } else {
            for normalizedExpansion in normalizedExpansions {
                let variant = normalizeWhitespace("\(normalizedQuery) \(normalizedExpansion)")
                let key = variant.lowercased()
                guard !variant.isEmpty, !seenQueries.contains(key) else { continue }
                seenQueries.insert(key)
                orderedQueries.append(variant)
            }
        }

        if orderedQueries.count > 1 {
            print("🧠 Expanded semantic queries: \(orderedQueries)")
        }

        return orderedQueries
    }

    private func compactTimelineLabel(for result: SearchResult, memories: [MemorySupabaseData]) -> String {
        let candidateTexts: [String] = [
            result.title ?? "",
            result.metadata?["merchant"] as? String ?? "",
            result.metadata?["place_name"] as? String ?? "",
            result.metadata?["location"] as? String ?? "",
            result.metadata?["sender"] as? String ?? "",
            result.metadata?["name"] as? String ?? "",
            result.metadata?["thread_title"] as? String ?? "",
            result.metadata?["file_name"] as? String ?? ""
        ].filter { !$0.isEmpty }

        if let memoryLabel = memoryCanonicalLabel(for: candidateTexts + [String(result.content.prefix(120))], memories: memories) {
            return memoryLabel
        }

        if let title = result.title, !title.isEmpty {
            return simplifyTimelineLabel(title, fallbackType: result.documentType)
        }

        if let merchant = result.metadata?["merchant"] as? String, !merchant.isEmpty {
            return simplifyTimelineLabel(merchant, fallbackType: result.documentType)
        }

        if let placeName = result.metadata?["place_name"] as? String, !placeName.isEmpty {
            return simplifyTimelineLabel(placeName, fallbackType: result.documentType)
        }

        return result.documentType.displayName
    }

    private func memoryCanonicalLabel(for seedTexts: [String], memories: [MemorySupabaseData]) -> String? {
        let normalizedSeeds = seedTexts
            .map(normalizeAliasText)
            .filter { !$0.isEmpty }
        guard !normalizedSeeds.isEmpty else { return nil }

        let sortedMemories = memories.sorted { $0.confidence > $1.confidence }
        for memory in sortedMemories where memory.confidence >= 0.7 {
            let normalizedKey = normalizeAliasText(memory.key)
            let normalizedValue = normalizeAliasText(memory.value)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }

            for seed in normalizedSeeds {
                if seed.contains(normalizedKey) || seed.contains(normalizedValue) {
                    let cleanedValue = simplifyTimelineLabel(memory.value, fallbackType: nil)
                    if !cleanedValue.isEmpty {
                        return cleanedValue
                    }
                }
            }
        }

        return nil
    }

    private func simplifyTimelineLabel(_ text: String, fallbackType: DocumentType?) -> String {
        var cleaned = text
            .replacingOccurrences(of: #"^(Receipt|Visit|Subject|Note|Event|Tracker|Attachment|Budget|Reminder|Recurring Expense):\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = normalizeAliasText(cleaned)
        let looksEncoded = cleaned.count > 72 && !normalized.contains(" ")
        if cleaned.isEmpty || looksEncoded {
            return fallbackType?.displayName ?? ""
        }

        if cleaned.count > 48 {
            cleaned = String(cleaned.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    /// Refresh journal-specific note embeddings on demand so historical journal queries
    /// do not depend on a full corpus sync having already completed.
    func ensureJournalNoteEmbeddingsCurrent() async {
        let notesData = await notesSnapshot()
        let journalNotes = notesData.notes.filter { $0.isJournalEntry || $0.isJournalWeeklyRecap }
        guard !journalNotes.isEmpty else { return }

        let documents = journalNotes.map { note -> [String: Any] in
            let folderName = note.folderId.flatMap { id in
                notesData.folderNamesById[id]
            }
            let content = note.embeddingContent(resolvedFolderName: folderName)
            return [
                "document_type": "note",
                "document_id": note.id.uuidString,
                "title": note.title,
                "content": content,
                "metadata": note.embeddingMetadata(resolvedFolderName: folderName)
            ]
        }

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

            guard !neededIds.isEmpty else { return }

            let neededSet = Set(neededIds)
            let docsToEmbed = documents.filter { doc in
                guard let id = doc["document_id"] as? String else { return false }
                return neededSet.contains(id)
            }

            guard !docsToEmbed.isEmpty else { return }

            print("📝 Journal notes: Refreshing \(docsToEmbed.count) journal embeddings on demand")
            _ = await batchEmbed(documents: docsToEmbed, type: "note")
        } catch {
            print("⚠️ Failed to refresh journal note embeddings on demand: \(error)")
        }
    }

    private func evidenceDedupKey(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email:
            return "email::\(item.emailId ?? item.id.uuidString)"
        case .note:
            return "note::\(item.noteId?.uuidString ?? item.id.uuidString)"
        case .receipt:
            return "receipt::\(item.receiptId?.uuidString ?? item.id.uuidString)"
        case .event:
            return "event::\(item.eventId?.uuidString ?? item.id.uuidString)"
        case .location:
            return "location::\(item.locationId?.uuidString ?? item.id.uuidString)"
        case .visit:
            return "visit::\(item.visitId?.uuidString ?? item.id.uuidString)"
        case .person:
            return "person::\(item.personId?.uuidString ?? item.id.uuidString)"
        }
    }

    func evidenceItem(from result: SearchResult) -> RelevantContentInfo? {
        mapResultToEvidence(result)
    }

    private func mapResultToEvidence(_ result: SearchResult) -> RelevantContentInfo? {
        switch result.documentType {
        case .email:
            let subject = result.title?.isEmpty == false ? result.title! : "Email"
            let sender = (result.metadata?["sender"] as? String) ?? "Unknown Sender"
            let snippet = String(result.content.prefix(120))
            let date = parseISODate(result.metadata?["date"]) ?? Date()
            return .email(id: result.documentId, subject: subject, sender: sender, snippet: snippet, date: date)

        case .task:
            guard let eventId = UUID(uuidString: result.documentId) else { return nil }
            let title = result.title?.isEmpty == false ? result.title! : "Event"
            let date = parseISODate(result.metadata?["start"])
                ?? parseISODate(result.metadata?["scheduled_time"])
                ?? parseISODate(result.metadata?["target_date"])
                ?? parseISODate(result.metadata?["created_at"])
                ?? Date()
            let category = (result.metadata?["category"] as? String) ?? "Personal"
            return .event(id: eventId, title: title, date: date, category: category)

        case .note:
            guard let noteId = UUID(uuidString: result.documentId) else { return nil }
            let title = result.title?.isEmpty == false ? result.title! : "Note"
            let noteKind = (result.metadata?["note_kind"] as? String) ?? ""
            let folder: String
            if noteKind == NoteKind.journalEntry.rawValue {
                folder = "Journal"
            } else if noteKind == NoteKind.journalWeeklyRecap.rawValue {
                folder = "Journal Weekly Summary"
            } else {
                folder = (result.metadata?["folder_name"] as? String) ?? "Notes"
            }
            return .note(id: noteId, title: title, snippet: String(result.content.prefix(120)), folder: folder)

        case .receipt:
            guard let receiptId = UUID(uuidString: result.documentId) else { return nil }
            let title = result.title?.replacingOccurrences(of: "Receipt: ", with: "") ?? "Receipt"
            let amount = metadataDouble(result.metadata?["amount"]) ?? extractCurrencyAmount(from: result.content)
            let date = parseISODate(result.metadata?["date"])
            let category = result.metadata?["category"] as? String
            let legacyNoteId = (result.metadata?["legacy_note_id"] as? String).flatMap(UUID.init(uuidString:))
            return .receipt(
                id: receiptId,
                title: title,
                amount: amount,
                date: date,
                category: category,
                legacyNoteId: legacyNoteId
            )

        case .location:
            guard let placeId = UUID(uuidString: result.documentId) else { return nil }
            let name = result.title?.isEmpty == false ? result.title! : "Place"
            let address = (result.metadata?["address"] as? String) ?? ""
            let category = (result.metadata?["place_category"] as? String) ?? ""
            return .location(id: placeId, name: name, address: address, category: category)

        case .visit:
            guard let visitId = UUID(uuidString: result.documentId) else { return nil }
            let placeId = (result.metadata?["place_id"] as? String).flatMap { UUID(uuidString: $0) }
            let placeName = (result.metadata?["place_name"] as? String) ?? result.title?.replacingOccurrences(of: "Visit: ", with: "")
            let address = result.metadata?["address"] as? String
            let entry = parseISODate(result.metadata?["entry_time"])
            let exit = parseISODate(result.metadata?["exit_time"])
            let duration = metadataInt(result.metadata?["duration_minutes"])
            return .visit(
                id: visitId,
                placeId: placeId,
                placeName: placeName,
                address: address,
                entryTime: entry,
                exitTime: exit,
                durationMinutes: duration
            )

        case .person:
            guard let personId = UUID(uuidString: result.documentId) else { return nil }
            let name = result.title?.isEmpty == false ? result.title! : ((result.metadata?["person"] as? String) ?? "Person")
            let relationship = result.metadata?["relationship"] as? String
            return .person(id: personId, name: name, relationship: relationship)

        case .recurringExpense, .attachment, .tracker, .budget:
            return nil
        }
    }

    private func metadataDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let intValue = value as? Int { return Double(intValue) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }

    private func metadataInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String, let intValue = Int(stringValue) { return intValue }
        return nil
    }

    // MARK: - Date Filtering Helpers

    private func matchesDateRange(metadata: [String: Any]?, dateRange: (start: Date, end: Date)) -> Bool {
        // Date-range query: unknown-date items are excluded to prevent cross-period leakage.
        guard let metadata = metadata else { return false }

        // Journal entries: use the journal day.
        if let journalDate = parseISODate(metadata["journal_date"]) {
            return journalDate >= dateRange.start && journalDate < dateRange.end
        }

        // Weekly recaps: treat the recap as spanning the whole week.
        if let weekStart = parseISODate(metadata["journal_week_start_date"]) {
            let weekEnd = parseISODate(metadata["journal_week_end_date"])
                ?? Calendar.current.date(byAdding: .day, value: 7, to: weekStart)
                ?? weekStart
            return weekStart < dateRange.end && weekEnd > dateRange.start
        }

        // Prefer explicit date fields when available
        if let date = parseISODate(metadata["date"]) {
            return date >= dateRange.start && date < dateRange.end
        }

        // Visits: use entry/exit overlap
        if let entry = parseISODate(metadata["entry_time"]) {
            let exit = parseISODate(metadata["exit_time"]) ?? entry
            return entry < dateRange.end && exit >= dateRange.start
        }

        // Tasks/events: use start/target/scheduled times
        if let start = parseISODate(metadata["start"]) {
            return start >= dateRange.start && start < dateRange.end
        }
        if let target = parseISODate(metadata["target_date"]) {
            return target >= dateRange.start && target < dateRange.end
        }
        if let scheduled = parseISODate(metadata["scheduled_time"]) {
            return scheduled >= dateRange.start && scheduled < dateRange.end
        }

        // Fallbacks
        if let createdAt = parseISODate(metadata["created_at"]) {
            return createdAt >= dateRange.start && createdAt < dateRange.end
        }

        // No parseable date fields
        return false
    }

    private func parseISODate(_ value: Any?) -> Date? {
        guard let rawString = value as? String else { return nil }
        let dateString = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dateString.isEmpty else { return nil }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: dateString) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            return date
        }

        // Fallback format (YYYY-MM-DD)
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.timeZone = TimeZone.current
        return fallback.date(from: dateString)
    }

    // MARK: - Hybrid Keyword Search

    private func keywordSearch(
        queries: [String],
        dateRange: (start: Date, end: Date)?,
        documentTypes: [DocumentType]?,
        recencyWeight: Float,
        retrievalMode: RetrievalMode
    ) async -> [SearchResult] {
        let tokens = keywordTokens(from: queries)
        let minimumHitCount = tokens.count <= 1 ? 1 : 2

        guard !tokens.isEmpty else { return [] }

        let typeFilter = documentTypes.map { Set($0) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let memories = await fetchAllMemories()

        func score(for text: String) -> Float {
            let lower = text.lowercased()
            var hits = 0
            for token in tokens {
                if lower.contains(token) {
                    hits += 1
                }
            }
            if hits < minimumHitCount { return 0 }
            let baseFloor: Float = retrievalMode == .exhaustive ? 0.50 : 0.55
            let hitWeight: Float = retrievalMode == .exhaustive ? 0.06 : 0.05
            let base = min(0.90, baseFloor + (hitWeight * Float(hits)))
            return base
        }

        func blendWithRecency(baseScore: Float, metadata: [String: Any]?) -> Float {
            let recencyScore = calculateRecencyScore(metadata: metadata)
            return ((1 - recencyWeight) * baseScore) + (recencyWeight * recencyScore)
        }

        var results: [SearchResult] = []
        let notesData: NotesSnapshot? = if typeFilter == nil || typeFilter?.contains(.note) == true || typeFilter?.contains(.attachment) == true {
            await notesSnapshot()
        } else {
            nil
        }
        let emailTuples: [(email: Email, mailbox: String)] = if typeFilter == nil || typeFilter?.contains(.email) == true {
            await emailSnapshot()
        } else {
            []
        }
        let taskItems: [TaskItem] = if typeFilter == nil || typeFilter?.contains(.task) == true {
            await taskSnapshot()
        } else {
            []
        }
        let budgetData: BudgetSnapshot? = if typeFilter == nil || typeFilter?.contains(.budget) == true {
            await budgetSnapshot()
        } else {
            nil
        }
        let trackerThreads: [TrackerThread] = if typeFilter == nil || typeFilter?.contains(.tracker) == true {
            await trackerThreadsSnapshot()
        } else {
            []
        }

        // Notes
        if let notesData, typeFilter == nil || typeFilter?.contains(.note) == true {
            for note in notesData.notes {
                let folderName = note.folderId.flatMap { id in
                    notesData.folderNamesById[id]
                }
                let content = note.embeddingContent(resolvedFolderName: folderName)
                let s = score(for: content)
                if s > 0 {
                    let metadata = note.embeddingMetadata(resolvedFolderName: folderName)
                    if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                        let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                        results.append(SearchResult(
                            documentType: .note,
                            documentId: note.id.uuidString,
                            title: note.title,
                            content: content,
                            metadata: metadata,
                            similarity: boosted
                        ))
                    }
                }
            }
        }

        // Emails
        if typeFilter == nil || typeFilter?.contains(.email) == true {
            for (email, mailbox) in emailTuples {
                var content = """
                Subject: \(email.subject)
                From: \(email.sender.displayName) <\(email.sender.email)>
                Snippet: \(email.snippet)
                """

                if let body = email.body, !body.isEmpty {
                    content += "\nBody: \(String(body.prefix(4000)))"
                }
                if let summary = email.aiSummary, !summary.isEmpty {
                    content += "\nAI Summary: \(summary)"
                }
                if !email.labels.isEmpty {
                    content += "\nLabels: \(email.labels.joined(separator: ", "))"
                }

                let s = score(for: content)
                if s > 0 {
                    let threadIDValue: Any = email.threadId ?? email.gmailThreadId ?? NSNull()
                    let metadata: [String: Any] = [
                        "date": iso.string(from: email.timestamp),
                        "sender": email.sender.displayName,
                        "sender_email": email.sender.email,
                        "mailbox": mailbox,
                        "is_read": email.isRead,
                        "has_attachments": email.hasAttachments,
                        "thread_id": threadIDValue,
                        "labels": email.labels.isEmpty ? NSNull() : email.labels
                    ]
                    if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                        let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                        results.append(SearchResult(
                            documentType: .email,
                            documentId: email.id,
                            title: email.subject,
                            content: content,
                            metadata: metadata,
                            similarity: boosted
                        ))
                    }
                }
            }
        }

        // Tasks
        if typeFilter == nil || typeFilter?.contains(.task) == true {
            for task in taskItems {
                var content = task.title
                if let desc = task.description, !desc.isEmpty {
                    content += "\n\(desc)"
                }
                if let location = task.location, !location.isEmpty {
                    content += "\nLocation: \(location)"
                }

                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "start": task.scheduledTime.map { iso.string(from: $0) } ?? NSNull(),
                        "target_date": task.targetDate.map { iso.string(from: $0) } ?? NSNull(),
                        "scheduled_time": task.scheduledTime.map { iso.string(from: $0) } ?? NSNull(),
                        "created_at": iso.string(from: task.createdAt)
                    ]
                    if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                        let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                        results.append(SearchResult(
                            documentType: .task,
                            documentId: task.id,
                            title: task.title,
                            content: content,
                            metadata: metadata,
                            similarity: boosted
                        ))
                    }
                }
            }
        }

        // Locations
        if typeFilter == nil || typeFilter?.contains(.location) == true {
            let places = LocationsManager.shared.savedPlaces
            for place in places {
                var content = "\(place.displayName)\n\(place.address)\n\(place.category)"
                let aliases = memoryAliases(for: [place.displayName, place.name], memories: memories)
                if !aliases.isEmpty {
                    content += "\nAliases: \(aliases.joined(separator: ", "))"
                }
                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "location": place.displayName,
                        "aliases": aliases.isEmpty ? NSNull() : aliases
                    ]
                    let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                    results.append(SearchResult(
                        documentType: .location,
                        documentId: place.id.uuidString,
                        title: place.displayName,
                        content: content,
                        metadata: metadata,
                        similarity: boosted
                    ))
                }
            }
        }

        // Receipts (notes under receipts folder)
        if typeFilter == nil || typeFilter?.contains(.receipt) == true {
            await ReceiptManager.shared.ensureLoaded()
            let receiptStats = await receiptStatsSnapshot()

            for receipt in receiptStats {
                var content = receipt.searchableText
                let aliases = memoryAliases(for: [receipt.title, receipt.merchant], memories: memories)
                if !aliases.isEmpty {
                    content += "\nAliases: \(aliases.joined(separator: ", "))"
                }
                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "date": iso.string(from: receipt.date),
                        "merchant": receipt.merchant,
                        "category": receipt.category,
                        "amount": receipt.amount,
                        "legacy_note_id": receipt.legacyNoteId?.uuidString ?? NSNull(),
                        "aliases": aliases.isEmpty ? NSNull() : aliases
                    ]
                    if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                        let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                        results.append(SearchResult(
                            documentType: .receipt,
                            documentId: receipt.id.uuidString,
                            title: "Receipt: \(receipt.title)",
                            content: content,
                            metadata: metadata,
                            similarity: boosted
                        ))
                    }
                }
            }
        }

        // Visits (direct DB fetch for lexical fallback when embedding recall misses)
        if typeFilter == nil || typeFilter?.contains(.visit) == true {
            if let userId = SupabaseManager.shared.getCurrentUser()?.id {
                do {
                    let client = await SupabaseManager.shared.getPostgrestClient()
                    var queryBuilder = client
                        .from("location_visits")
                        .select()
                        .eq("user_id", value: userId.uuidString)

                    if let dateRange {
                        queryBuilder = queryBuilder
                            .gte("entry_time", value: iso.string(from: dateRange.start))
                            .lt("entry_time", value: iso.string(from: dateRange.end))
                    }

                    let response = try await queryBuilder
                        .order("entry_time", ascending: false)
                        .limit(1200)
                        .execute()
                    let visits: [LocationVisitRecord] = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
                    let placesById = Dictionary(uniqueKeysWithValues: LocationsManager.shared.savedPlaces.map { ($0.id, $0) })
                    let visitPeopleMap = await PeopleManager.shared.getPeopleForVisits(visitIds: visits.map(\.id))

                    for visit in visits {
                        let place = placesById[visit.savedPlaceId]
                        let placeName = place?.displayName ?? "Unknown Location"
                        let people = visitPeopleMap[visit.id] ?? []
                        let aliases = memoryAliases(for: [placeName], memories: memories)
                        var content = """
                        Visit: \(placeName)
                        Address: \(place?.address ?? "")
                        City: \(place?.city ?? "")
                        Province: \(place?.province ?? "")
                        Country: \(place?.country ?? "")
                        With: \(people.map(\.name).joined(separator: ", "))
                        Day: \(visit.dayOfWeek)
                        Time: \(visit.timeOfDay)
                        Notes: \(visit.visitNotes ?? "")
                        """
                        if !aliases.isEmpty {
                            content += "\nAliases: \(aliases.joined(separator: ", "))"
                        }
                        let s = score(for: content)
                        if s > 0 {
                            let metadata: [String: Any] = [
                                "entry_time": iso.string(from: visit.entryTime),
                                "exit_time": visit.exitTime.map { iso.string(from: $0) } ?? NSNull(),
                                "duration_minutes": visit.durationMinutes ?? NSNull(),
                                "place_id": visit.savedPlaceId.uuidString,
                                "place_name": placeName,
                                "place_category": place?.category ?? NSNull(),
                                "address": place?.address ?? NSNull(),
                                "city": place?.city ?? NSNull(),
                                "province": place?.province ?? NSNull(),
                                "country": place?.country ?? NSNull(),
                                "people": people.isEmpty ? NSNull() : people.map(\.name),
                                "people_ids": people.isEmpty ? NSNull() : people.map { $0.id.uuidString },
                                "aliases": aliases.isEmpty ? NSNull() : aliases
                            ]
                            if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                                let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                                results.append(SearchResult(
                                    documentType: .visit,
                                    documentId: visit.id.uuidString,
                                    title: "Visit: \(placeName)",
                                    content: content,
                                    metadata: metadata,
                                    similarity: boosted
                                ))
                            }
                        }
                    }
                } catch {
                    print("⚠️ Keyword visit search failed: \(error)")
                }
            }
        }

        // People
        if typeFilter == nil || typeFilter?.contains(.person) == true {
            for person in PeopleManager.shared.people {
                var content = "\(person.name)\n\(person.relationshipDisplayText)"
                if let nickname = person.nickname, !nickname.isEmpty {
                    content += "\nNickname: \(nickname)"
                }
                if let food = person.favouriteFood, !food.isEmpty {
                    content += "\nFavourite Food: \(food)"
                }
                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "person": person.name
                    ]
                    let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                    results.append(SearchResult(
                        documentType: .person,
                        documentId: person.id.uuidString,
                        title: person.name,
                        content: content,
                        metadata: metadata,
                        similarity: boosted
                    ))
                }
            }
        }

        // Recurring expenses
        if typeFilter == nil || typeFilter?.contains(.recurringExpense) == true {
            do {
                let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
                for expense in expenses {
                    let monthlyEstimate = NSDecimalNumber(decimal: expense.yearlyAmount).doubleValue / 12.0
                    var content = """
                    Recurring Expense: \(expense.title)
                    Amount: \(expense.formattedAmount)
                    Frequency: \(expense.frequency.rawValue)
                    Status: \(expense.statusBadge)
                    Reminder: \(expense.reminderOption.displayName)
                    Monthly estimate: \(CurrencyParser.formatAmount(monthlyEstimate))
                    """
                    if let description = expense.description, !description.isEmpty {
                        content += "\nDescription: \(description)"
                    }
                    if let category = expense.category, !category.isEmpty {
                        content += "\nCategory: \(category)"
                    }

                    let s = score(for: content)
                    if s > 0 {
                        let metadata: [String: Any] = [
                            "date": iso.string(from: expense.nextOccurrence),
                            "next_occurrence": iso.string(from: expense.nextOccurrence),
                            "start_date": iso.string(from: expense.startDate),
                            "updated_at": iso.string(from: expense.updatedAt),
                            "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
                            "category": expense.category ?? NSNull(),
                            "frequency": expense.frequency.rawValue,
                            "status": expense.statusBadge
                        ]
                        if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                            let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                            results.append(SearchResult(
                                documentType: .recurringExpense,
                                documentId: expense.id.uuidString,
                                title: expense.title,
                                content: content,
                                metadata: metadata,
                                similarity: boosted
                            ))
                        }
                    }
                }
            } catch {
                print("⚠️ Keyword recurring expense search failed: \(error)")
            }
        }

        // Budgets and reminders
        if let budgetData, typeFilter == nil || typeFilter?.contains(.budget) == true {
            for budgetEntry in budgetData.budgets {
                let budget = budgetEntry.budget
                let status = budgetEntry.status
                let content = """
                Expense Budget: \(budget.name)
                Period: \(budget.period.displayName)
                Limit: \(CurrencyParser.formatAmount(budget.limit))
                Current spend: \(CurrencyParser.formatAmount(status.spent))
                Remaining: \(CurrencyParser.formatAmount(status.remaining))
                """
                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "date": iso.string(from: budget.updatedAt),
                        "updated_at": iso.string(from: budget.updatedAt),
                        "subtype": "budget",
                        "name": budget.name,
                        "remaining": status.remaining,
                        "period": budget.period.rawValue
                    ]
                    let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                    results.append(SearchResult(
                        documentType: .budget,
                        documentId: "budget_\(budget.id.uuidString)",
                        title: "Budget: \(budget.name)",
                        content: content,
                        metadata: metadata,
                        similarity: boosted
                    ))
                }
            }

            for reminder in budgetData.reminders {
                let content = """
                Expense Reminder: \(reminder.expenseName)
                Frequency: \(reminder.frequency.displayName)
                Time: \(String(format: "%02d:%02d", reminder.hour, reminder.minute))
                """
                let s = score(for: content)
                if s > 0 {
                    let metadata: [String: Any] = [
                        "date": iso.string(from: reminder.updatedAt),
                        "updated_at": iso.string(from: reminder.updatedAt),
                        "subtype": "reminder",
                        "name": reminder.expenseName,
                        "frequency": reminder.frequency.rawValue
                    ]
                    let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                    results.append(SearchResult(
                        documentType: .budget,
                        documentId: "reminder_\(reminder.id.uuidString)",
                        title: "Reminder: \(reminder.expenseName)",
                        content: content,
                        metadata: metadata,
                        similarity: boosted
                    ))
                }
            }
        }

        // Tracker threads
        if typeFilter == nil || typeFilter?.contains(.tracker) == true {
            for thread in trackerThreads {
                let sortedChanges = thread.memorySnapshot.changeLog.sorted { lhs, rhs in
                    if lhs.effectiveAt == rhs.effectiveAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.effectiveAt > rhs.effectiveAt
                }
                var content = """
                Tracker: \(thread.title)
                Status: \(thread.status.rawValue)
                Rules: \(thread.memorySnapshot.normalizedRulesText)
                Current summary: \(thread.memorySnapshot.normalizedSummaryText)
                """
                if !thread.memorySnapshot.quickFacts.isEmpty {
                    content += "\nQuick facts: \(thread.memorySnapshot.quickFacts.joined(separator: " | "))"
                }
                for change in sortedChanges.prefix(6) {
                    content += "\nChange: \(formattedTrackerChangeLine(change))"
                }

                let s = score(for: content)
                if s > 0 {
                    let latestDate = sortedChanges.first?.effectiveAt ?? thread.updatedAt
                    let metadata: [String: Any] = [
                        "date": iso.string(from: latestDate),
                        "effective_at": iso.string(from: latestDate),
                        "updated_at": iso.string(from: thread.updatedAt),
                        "status": thread.status.rawValue,
                        "change_count": thread.memorySnapshot.changeLog.count
                    ]
                    let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                    results.append(SearchResult(
                        documentType: .tracker,
                        documentId: thread.id.uuidString,
                        title: thread.title,
                        content: content,
                        metadata: metadata,
                        similarity: boosted
                    ))
                }
            }
        }

        // Attachments / extracted documents
        if typeFilter == nil || typeFilter?.contains(.attachment) == true,
           let userId = SupabaseManager.shared.getCurrentUser()?.id {
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                let attachmentRows: [AttachmentSupabaseData] = try await client
                    .from("attachments")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value

                let extractedRows: [ExtractedDataSupabaseData] = try await client
                    .from("extracted_data")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value

                let attachments = attachmentRows.compactMap(NoteAttachment.init(from:))
                let extractedByAttachmentId = Dictionary(
                    uniqueKeysWithValues: extractedRows.compactMap { row -> (UUID, ExtractedData)? in
                        guard let extracted = ExtractedData(from: row) else { return nil }
                        return (extracted.attachmentId, extracted)
                    }
                )
                let notesById = notesData?.notesById ?? [:]

                for attachment in attachments {
                    let extracted = extractedByAttachmentId[attachment.id]
                    let noteTitle = notesById[attachment.noteId]?.title ?? "Unknown note"
                    let summary = extractedSummaryText(extracted) ?? ""
                    let rawText = extracted?.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    var content = """
                    Attachment: \(attachment.fileName)
                    File type: \(attachment.fileType)
                    Note: \(noteTitle)
                    """
                    if !summary.isEmpty {
                        content += "\nSummary: \(summary)"
                    }
                    if !rawText.isEmpty {
                        content += "\nExtracted text: \(String(rawText.prefix(4000)))"
                    }

                    let s = score(for: content)
                    if s > 0 {
                        let documentDate = extracted?.updatedAt ?? attachment.updatedAt
                        let metadata: [String: Any] = [
                            "date": iso.string(from: documentDate),
                            "created_at": iso.string(from: attachment.createdAt),
                            "updated_at": iso.string(from: documentDate),
                            "file_name": attachment.fileName,
                            "file_type": attachment.fileType,
                            "note_title": noteTitle,
                            "document_type_label": attachment.documentType ?? extracted?.documentType ?? NSNull()
                        ]
                        if dateRange == nil || matchesDateRange(metadata: metadata, dateRange: dateRange!) {
                            let boosted = blendWithRecency(baseScore: s, metadata: metadata)
                            results.append(SearchResult(
                                documentType: .attachment,
                                documentId: attachment.id.uuidString,
                                title: "Attachment: \(attachment.fileName)",
                                content: content,
                                metadata: metadata,
                                similarity: boosted
                            ))
                        }
                    }
                }
            } catch {
                print("⚠️ Keyword attachment search failed: \(error)")
            }
        }

        return results
    }

    private func keywordTokens(from queries: [String]) -> [String] {
        var seenTokens = Set<String>()
        var orderedTokens: [String] = []

        for query in queries {
            let normalizedQuery = normalizeWhitespace(query.lowercased())
            guard !normalizedQuery.isEmpty else { continue }

            let rawTokens = normalizedQuery.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for rawToken in rawTokens {
                for token in normalizedTokenVariants(for: rawToken) {
                    guard !seenTokens.contains(token) else { continue }
                    seenTokens.insert(token)
                    orderedTokens.append(token)
                }
            }
        }

        return orderedTokens
    }

    private func normalizedTokenVariants(for rawToken: String) -> [String] {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else { return [] }
        guard token.count >= 3 || Int(token) != nil else { return [] }
        guard !keywordStopWords.contains(token) else { return [] }

        var orderedVariants: [String] = [token]

        if token.hasSuffix("ies"), token.count > 4 {
            orderedVariants.append(String(token.dropLast(3)) + "y")
        } else if token.hasSuffix("es"), token.count > 4, !token.hasSuffix("sses") {
            orderedVariants.append(String(token.dropLast(2)))
        } else if token.hasSuffix("s"), token.count > 4, !token.hasSuffix("ss") {
            orderedVariants.append(String(token.dropLast()))
        }

        var uniqueVariants: [String] = []
        var seen = Set<String>()
        for variant in orderedVariants where !seen.contains(variant) {
            seen.insert(variant)
            uniqueVariants.append(variant)
        }

        return uniqueVariants
    }

    private func extractCurrencyAmount(from text: String) -> Double? {
        let patterns = [
            #"(?i)\btotal\s*:\s*\$?\s*([0-9]+(?:\.[0-9]{2})?)"#,
            #"\$\s*([0-9]+(?:\.[0-9]{2})?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard
                let match = regex.firstMatch(in: text, range: range),
                let amountRange = Range(match.range(at: 1), in: text),
                let amount = Double(text[amountRange])
            else {
                continue
            }
            return amount
        }

        return nil
    }

    private func recencyWeight(
        for query: String,
        dateRange: (start: Date, end: Date)?,
        preferHistorical: Bool,
        retrievalMode: RetrievalMode
    ) -> Float {
        if preferHistorical {
            return 0.0
        }

        if retrievalMode == .exhaustive {
            return 0.05
        }

        let lower = query.lowercased()
        let historicalHints = [
            "which weekend", "what weekend", "that weekend", "weekend before",
            "when did", "trip", "stay", "last year", "years ago", "ago", "oldest", "earliest", "historical"
        ]
        let recentHints = ["today", "this week", "recent", "latest", "now", "currently"]

        if recentHints.contains(where: { lower.contains($0) }) {
            return 0.30
        }

        if historicalHints.contains(where: { lower.contains($0) }) {
            return 0.08
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        if let explicitYear = extractExplicitYear(from: lower), explicitYear < currentYear {
            return 0.05
        }

        if let dateRange {
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            if dateRange.end < sevenDaysAgo {
                return 0.08
            }
        }

        return 0.18
    }

    private func extractExplicitYear(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20\d{2})\b"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let yearRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[yearRange])
    }

    /// Calculate recency boost score (1.0 for today, decays to 0.1 for 1+ year ago)
    private func calculateRecencyScore(metadata: [String: Any]?) -> Float {
        guard let metadata = metadata,
              let parsedDate = extractDateForRecency(from: metadata) else {
            // No date metadata, assume recent (neutral score)
            return 0.5
        }

        // Calculate age in days
        let ageInDays = Date().timeIntervalSince(parsedDate) / (60 * 60 * 24)

        // Exponential decay: 1.0 today, 0.5 at 30 days, 0.1 at 365 days
        if ageInDays < 1 {
            return 1.0  // Today
        } else if ageInDays < 30 {
            return Float(0.5 + (0.5 * (30 - ageInDays) / 30))  // Linear 1.0 → 0.5
        } else if ageInDays < 365 {
            return Float(0.1 + (0.4 * (365 - ageInDays) / 335))  // Linear 0.5 → 0.1
        } else {
            return 0.1  // 1+ year old
        }
    }

    private func extractDateForRecency(from metadata: [String: Any]) -> Date? {
        let candidateKeys = [
            "date",
            "entry_time",
            "start",
            "scheduled_time",
            "target_date",
            "created_at",
            "updated_at"
        ]

        for key in candidateKeys {
            guard let rawValue = metadata[key] as? String, !rawValue.isEmpty else { continue }
            if let parsed = parseMetadataDate(rawValue) {
                return parsed
            }
        }
        return nil
    }

    private func parseMetadataDate(_ value: String) -> Date? {
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd"
        fallbackFormatter.timeZone = TimeZone.current
        return fallbackFormatter.date(from: value)
    }

    private func logSearchDiagnostics(
        query: String,
        preferHistorical: Bool,
        dateRange: (start: Date, end: Date)?,
        results: [SearchResult],
        retrievalMode: RetrievalMode,
        searchQueries: [String]
    ) {
        guard !results.isEmpty else {
            print("📊 Search diagnostics | mode=\(preferHistorical ? "historical" : "default") | retrieval=\(retrievalMode.rawValue) | results=0")
            return
        }

        let datedResults = results.compactMap { result -> Date? in
            guard let metadata = result.metadata else { return nil }
            return extractDateForRecency(from: metadata)
        }
        let oldest = datedResults.min()
        let newest = datedResults.max()
        let distribution = Dictionary(grouping: results, by: { $0.documentType })
            .map { "\($0.key.rawValue):\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")

        let formatter = ISO8601DateFormatter()
        let oldestLabel = oldest.map { formatter.string(from: $0) } ?? "unknown"
        let newestLabel = newest.map { formatter.string(from: $0) } ?? "unknown"
        let rangeLabel: String = {
            guard let dateRange else { return "none" }
            return "\(formatter.string(from: dateRange.start))→\(formatter.string(from: dateRange.end))"
        }()

        print(
            "📊 Search diagnostics | mode=\(preferHistorical ? "historical" : "default") | retrieval=\(retrievalMode.rawValue) | query=\"\(query.prefix(80))\" | queries=\(searchQueries.count) | results=\(results.count) | range=\(rangeLabel) | oldest=\(oldestLabel) | newest=\(newestLabel) | distribution=\(distribution)"
        )
    }

    /// Batch fetch all memories for annotation (call once before annotating multiple titles)
    private func fetchAllMemories() async -> [MemorySupabaseData] {
        if let lastMemoryFetchTime,
           Date().timeIntervalSince(lastMemoryFetchTime) < 120,
           !cachedMemories.isEmpty {
            return cachedMemories
        }

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("🧠 Memory fetch skipped: No user ID")
            return []
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch all memories for this user once
            let response = try await client
                .from("user_memory")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("confidence", value: 0.5)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let data: [MemorySupabaseData] = try decoder.decode([MemorySupabaseData].self, from: response.data)

            print("🧠 Fetched \(data.count) memories for batch annotation")
            cachedMemories = data
            lastMemoryFetchTime = Date()
            return data
        } catch {
            print("⚠️ Memory fetch failed: \(error)")
            return []
        }
    }

    /// Annotate a result title with memory context (e.g., "Jvmesmrvo" → "Jvmesmrvo (Haircut)")
    /// Uses pre-fetched memories for efficient batch processing
    private func annotateWithMemory(_ title: String, memories: [MemorySupabaseData]) -> String {
        // Quick cache check - avoid processing if we've already checked this title
        let cacheKey = title.lowercased()
        if let cached = memoryAnnotationCache[cacheKey] {
            return cached
        }

        // Find matching memory
        for memoryData in memories {
            if title.lowercased().contains(memoryData.key.lowercased()) {
                let annotated = "\(title) (\(memoryData.value))"
                memoryAnnotationCache[cacheKey] = annotated
                print("🧠 ✅ Annotated result: '\(title)' → '\(annotated)'")
                return annotated
            }
        }

        memoryAnnotationCache[cacheKey] = title  // Cache negative result
        return title
    }
    
    // MARK: - Embedding Sync

    var isInteractiveRequestActive: Bool {
        interactiveRequestCount > 0
    }

    func beginInteractiveRequest(reason: String) {
        interactiveRequestCount += 1
        if interactiveRequestCount == 1 {
            print("⏸️ Chat-priority mode enabled (\(reason))")
        }
    }

    func endInteractiveRequest(reason: String) {
        interactiveRequestCount = max(0, interactiveRequestCount - 1)
        if interactiveRequestCount == 0 {
            print("▶️ Chat-priority mode cleared (\(reason))")
            if pendingFullSyncRequested {
                Task {
                    guard !(await self.isIndexingSnapshot()) else { return }
                    self.pendingFullSyncRequested = false
                    await self.syncAllEmbeddings()
                }
            }
        }
    }

    private func deferFullSync(reason: String) {
        pendingFullSyncRequested = true
        print("⏸️ Deferring embedding sync (\(reason)) while chat is active")
    }
    
    /// Sync embeddings for all user data
    /// Call this on app launch and periodically
    func syncEmbeddingsIfNeeded() async {
        // Only sync if not already syncing
        guard !(await isIndexingSnapshot()) else { return }
        guard !isInteractiveRequestActive else {
            deferFullSync(reason: "syncEmbeddingsIfNeeded")
            return
        }
        
        // Skip if synced within 5 minutes — reduces redundant calls from foreground/background overlap
        if let lastSync = await lastSyncTimeSnapshot(),
           Date().timeIntervalSince(lastSync) < 5 * 60 {
            print("⚡ Skipping embedding sync - synced \(Int(Date().timeIntervalSince(lastSync)))s ago")
            return
        }
        
        await syncAllEmbeddings()
    }
    
    /// Force immediate sync (bypasses cooldown) - useful for immediate embedding after create/update
    func syncEmbeddingsImmediately() async {
        // Only sync if not already syncing
        guard !(await isIndexingSnapshot()) else { return }
        guard !isInteractiveRequestActive else {
            deferFullSync(reason: "syncEmbeddingsImmediately")
            return
        }
        
        await syncAllEmbeddings()
    }

    /// Incremental refresh for visit embeddings after visit/link mutations.
    func refreshVisitEmbeddingsIncremental(reason: String) async {
        let now = Date()
        if let lastRefresh = lastVisitEmbeddingRefresh,
           now.timeIntervalSince(lastRefresh) < visitEmbeddingRefreshCooldown {
            print("⚡️ Skipping visit embedding refresh (\(reason)) - cooldown active")
            return
        }

        lastVisitEmbeddingRefresh = now

        guard !isInteractiveRequestActive else {
            deferFullSync(reason: "refreshVisitEmbeddingsIncremental:\(reason)")
            return
        }

        guard !(await isIndexingSnapshot()) else {
            print("⚡️ Skipping visit embedding refresh (\(reason)) - full sync in progress")
            return
        }

        let refreshed = await syncLocationVisitEmbeddings()
        if refreshed > 0 {
            print("✅ Visit embeddings refreshed (\(reason)): \(refreshed) updated")
        } else {
            print("ℹ️ Visit embeddings already up-to-date (\(reason))")
        }
    }
    
    /// Force sync all embeddings
    @discardableResult
    func syncAllEmbeddings() async -> Bool {
        guard !isInteractiveRequestActive else {
            deferFullSync(reason: "syncAllEmbeddings")
            return false
        }

        await beginSyncState()

        print("🔄 Starting embedding sync...")
        print("⚠️  NOTE: Embedding sync requires 'embeddings-proxy' edge function to be deployed")
        let startTime = Date()
        
        let phases: [(status: String, run: () async -> Int)] = [
            ("Syncing notes...", { await self.syncNoteEmbeddings() }),
            ("Syncing emails...", { await self.syncEmailEmbeddings() }),
            ("Syncing tasks...", { await self.syncTaskEmbeddings() }),
            ("Syncing locations...", { await self.syncLocationEmbeddings() }),
            ("Syncing receipts...", { await self.syncReceiptEmbeddings() }),
            ("Syncing visits...", { await self.syncLocationVisitEmbeddings() }),
            ("Syncing people...", { await self.syncPeopleEmbeddings() }),
            ("Syncing recurring expenses...", { await self.syncRecurringExpenseEmbeddings() }),
            ("Syncing attachments...", { await self.syncAttachmentEmbeddings() }),
            ("Syncing trackers...", { await self.syncTrackerEmbeddings() }),
            ("Syncing budgets...", { await self.syncBudgetEmbeddings() })
        ]

        var phaseCounts: [String: Int] = [:]

        for (index, phase) in phases.enumerated() {
            await updateSyncState(status: phase.status)
            phaseCounts[phase.status] = await phase.run()
            await updateSyncState(progress: Double(index + 1) / Double(phases.count))
        }

        let totalCount = phaseCounts.values.reduce(0, +)
        let completedAt = Date()
        await completeSyncState(totalCount: totalCount, completedAt: completedAt)

        let duration = Date().timeIntervalSince(startTime)
        print("✅ Embedding sync complete: \(totalCount) documents in \(String(format: "%.1f", duration))s")
        print(
            """
               Notes: \(phaseCounts["Syncing notes..."] ?? 0), Emails: \(phaseCounts["Syncing emails..."] ?? 0), Tasks: \(phaseCounts["Syncing tasks..."] ?? 0), Locations: \(phaseCounts["Syncing locations..."] ?? 0), Receipts: \(phaseCounts["Syncing receipts..."] ?? 0), Visits: \(phaseCounts["Syncing visits..."] ?? 0), People: \(phaseCounts["Syncing people..."] ?? 0), Recurring: \(phaseCounts["Syncing recurring expenses..."] ?? 0), Attachments: \(phaseCounts["Syncing attachments..."] ?? 0), Trackers: \(phaseCounts["Syncing trackers..."] ?? 0), Budgets: \(phaseCounts["Syncing budgets..."] ?? 0)
            """
        )
        
        // Log any potential issues
        if totalCount == 0 {
            print("⚠️ WARNING: No documents were embedded. This might indicate:")
            print("   - All documents are already embedded (check database)")
            print("   - No documents exist in the app")
            print("   - Authentication issues")
        }
        return true
    }
    
    /// Sync note embeddings - embed ALL notes (no date limit)
    private func syncNoteEmbeddings() async -> Int {
        let notesData = await notesSnapshot()
        let allNotes = notesData.notes
        guard !allNotes.isEmpty else { return 0 }

        print("📝 Notes: Syncing all \(allNotes.count) notes (no date limit)")

        // Prepare documents for embedding
        let documents = allNotes.map { note -> [String: Any] in
            let folderName = note.folderId.flatMap { id in
                notesData.folderNamesById[id]
            }
            let content = note.embeddingContent(resolvedFolderName: folderName)
            return [
                "document_type": "note",
                "document_id": note.id.uuidString,
                "title": note.title,
                "content": content,
                "metadata": note.embeddingMetadata(resolvedFolderName: folderName)
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
    
    /// Sync email embeddings
    private func syncEmailEmbeddings() async -> Int {
        let allEmails = await collectLiveEmailsForEmbedding()
        let iso = ISO8601DateFormatter()
        let liveEmailDocuments = allEmails.map { (email, mailbox) -> [String: Any] in
            var content = """
            Subject: \(email.subject)
            From: \(email.sender.displayName) <\(email.sender.email)>
            Snippet: \(email.snippet)
            """

            if !email.recipients.isEmpty {
                let recipientNames = email.recipients
                    .map { "\($0.displayName) <\($0.email)>" }
                    .joined(separator: ", ")
                content += "\nTo: \(recipientNames)"
            }
            if !email.ccRecipients.isEmpty {
                let ccNames = email.ccRecipients
                    .map { "\($0.displayName) <\($0.email)>" }
                    .joined(separator: ", ")
                content += "\nCC: \(ccNames)"
            }
            if let body = email.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content += "\nBody: \(String(body.prefix(6000)))"
            }
            if let aiSummary = email.aiSummary, !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content += "\nAI Summary: \(aiSummary)"
            }
            if !email.labels.isEmpty {
                content += "\nLabels: \(email.labels.joined(separator: ", "))"
            }
            if email.hasAttachments {
                content += "\nHas attachments: Yes"
            }

            return [
                "document_type": "email",
                "document_id": email.id,
                "title": email.subject,
                "content": content,
                "metadata": [
                    "date": iso.string(from: email.timestamp),
                    "sender": email.sender.displayName,
                    "sender_email": email.sender.email,
                    "mailbox": mailbox,
                    "is_read": email.isRead,
                    "is_important": email.isImportant,
                    "has_attachments": email.hasAttachments,
                    "thread_id": (email.threadId ?? email.gmailThreadId ?? NSNull()) as Any,
                    "gmail_message_id": email.gmailMessageId ?? NSNull(),
                    "labels": email.labels.isEmpty ? NSNull() : email.labels,
                    "created_at": iso.string(from: email.timestamp)
                ] as [String: Any]
            ]
        }

        let liveGmailMessageIds = Set(allEmails.compactMap { $0.email.gmailMessageId })
        let savedEmailDocuments = await buildSavedEmailDocumentsForEmbedding(
            existingGmailMessageIds: liveGmailMessageIds
        )

        let documents = liveEmailDocuments + savedEmailDocuments
        guard !documents.isEmpty else {
            print("📧 Emails: No email documents available for embedding")
            return 0
        }

        print(
            "📧 Emails: Syncing \(documents.count) documents (\(liveEmailDocuments.count) live + \(savedEmailDocuments.count) saved-folder)"
        )

        if let oldest = documents
            .compactMap({ doc -> Date? in
                guard
                    let metadata = doc["metadata"] as? [String: Any],
                    let dateString = metadata["date"] as? String
                else { return nil }
                return parseMetadataDate(dateString)
            })
            .min() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            print("📧 Emails: Oldest document date in sync batch = \(formatter.string(from: oldest))")
        }

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
            return await batchEmbed(documents: documents, type: "email")
        }
    }

    private func collectLiveEmailsForEmbedding() async -> [(email: Email, mailbox: String)] {
        var merged = dedupeEmailTuples(await emailSnapshot())

        let hasFreshCachedBackfill = {
            guard
                let lastBackfill = lastHistoricalEmailBackfill,
                Date().timeIntervalSince(lastBackfill) < historicalBackfillRefreshInterval,
                !cachedHistoricalEmailsForEmbedding.isEmpty
            else {
                return false
            }
            return true
        }()

        if hasFreshCachedBackfill {
            print("📧 Emails: Reusing cached historical backfill (\(cachedHistoricalEmailsForEmbedding.count) docs)")
            merged = dedupeEmailTuples(merged + cachedHistoricalEmailsForEmbedding)
            return merged
        }

        guard shouldBackfillHistoricalEmails(for: merged) else {
            return merged
        }

        let fetchedHistorical = await fetchHistoricalEmailsFromGmail()
        guard !fetchedHistorical.isEmpty else {
            return merged
        }

        cachedHistoricalEmailsForEmbedding = fetchedHistorical
        lastHistoricalEmailBackfill = Date()
        merged = dedupeEmailTuples(merged + fetchedHistorical)
        return merged
    }

    private func shouldBackfillHistoricalEmails(for emails: [(email: Email, mailbox: String)]) -> Bool {
        guard !emails.isEmpty else { return true }

        let oldestDate = emails.map { $0.email.timestamp }.min() ?? Date()
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let hasShallowHistory = oldestDate > oneYearAgo
        let hasLowVolume = emails.count < 350

        return hasShallowHistory || hasLowVolume
    }

    private func fetchHistoricalEmailsFromGmail() async -> [(email: Email, mailbox: String)] {
        let coverageTargetDate = Calendar.current.date(
            byAdding: .year,
            value: -historicalBackfillCoverageYears,
            to: Date()
        ) ?? .distantPast

        async let inbox = fetchHistoricalMailboxEmails(
            folder: .inbox,
            maxPages: historicalBackfillPagesPerMailbox,
            pageSize: historicalBackfillPageSize,
            coverageTargetDate: coverageTargetDate
        )
        async let sent = fetchHistoricalMailboxEmails(
            folder: .sent,
            maxPages: historicalBackfillPagesPerMailbox,
            pageSize: historicalBackfillPageSize,
            coverageTargetDate: coverageTargetDate
        )

        let inboxEmails = await inbox
        let sentEmails = await sent
        let combined = inboxEmails + sentEmails
        let deduped = dedupeEmailTuples(combined)
        print("📧 Emails: Historical backfill fetched \(deduped.count) emails from Gmail")
        return deduped
    }

    private func fetchHistoricalMailboxEmails(
        folder: EmailFolder,
        maxPages: Int,
        pageSize: Int,
        coverageTargetDate: Date
    ) async -> [(email: Email, mailbox: String)] {
        let mailbox = folder == .inbox ? "inbox" : "sent"
        var results: [(email: Email, mailbox: String)] = []
        var pageToken: String? = nil
        var pagesFetched = 0

        while pagesFetched < maxPages {
            do {
                let response: (emails: [Email], nextPageToken: String?)
                switch folder {
                case .inbox:
                    response = try await gmailAPIClient.fetchInboxEmails(maxResults: pageSize, pageToken: pageToken)
                case .sent:
                    response = try await gmailAPIClient.fetchSentEmails(maxResults: pageSize, pageToken: pageToken)
                default:
                    return results
                }

                guard !response.emails.isEmpty else { break }
                results.append(contentsOf: response.emails.map { ($0, mailbox) })
                pageToken = response.nextPageToken
                pagesFetched += 1

                let oldestInPage = response.emails.map(\.timestamp).min() ?? Date()
                if oldestInPage <= coverageTargetDate || pageToken == nil {
                    break
                }
            } catch {
                print("⚠️ Emails: Historical \(mailbox) backfill stopped: \(error)")
                break
            }
        }

        return results
    }

    private func dedupeEmailTuples(_ emails: [(email: Email, mailbox: String)]) -> [(email: Email, mailbox: String)] {
        var seenIds = Set<String>()
        var deduped: [(email: Email, mailbox: String)] = []

        for tuple in emails.sorted(by: { $0.email.timestamp > $1.email.timestamp }) {
            let stableId = tuple.email.gmailMessageId ?? tuple.email.id
            if seenIds.insert(stableId).inserted {
                deduped.append(tuple)
            }
        }

        return deduped
    }

    private func buildSavedEmailDocumentsForEmbedding(
        existingGmailMessageIds: Set<String>
    ) async -> [[String: Any]] {
        let emailFolderService = EmailFolderService.shared
        let iso = ISO8601DateFormatter()
        var documents: [[String: Any]] = []
        var seenSavedGmailIds = Set<String>()

        do {
            let folders = try await emailFolderService.fetchFolders()
            guard !folders.isEmpty else { return [] }

            for folder in folders {
                let savedEmails = try await emailFolderService.fetchEmailsInFolder(folderId: folder.id)
                for email in savedEmails {
                    if existingGmailMessageIds.contains(email.gmailMessageId) { continue }
                    if !seenSavedGmailIds.insert(email.gmailMessageId).inserted { continue }

                    var content = """
                    Subject: \(email.subject)
                    From: \((email.senderName?.isEmpty == false ? email.senderName! : email.senderEmail)) <\(email.senderEmail)>
                    Snippet: \(email.snippet ?? "")
                    """

                    if !email.recipients.isEmpty {
                        content += "\nTo: \(email.recipients.joined(separator: ", "))"
                    }
                    if !email.ccRecipients.isEmpty {
                        content += "\nCC: \(email.ccRecipients.joined(separator: ", "))"
                    }
                    if let body = email.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        content += "\nBody: \(String(body.prefix(6000)))"
                    }
                    if let aiSummary = email.aiSummary, !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        content += "\nAI Summary: \(aiSummary)"
                    }
                    if !email.attachments.isEmpty {
                        content += "\nAttachments: \(email.attachments.map(\.fileName).joined(separator: ", "))"
                    }

                    let documentId = "saved_\(email.id.uuidString)"
                    documents.append([
                        "document_type": "email",
                        "document_id": documentId,
                        "title": email.subject,
                        "content": content,
                        "metadata": [
                            "date": iso.string(from: email.timestamp),
                            "sender": (email.senderName?.isEmpty == false ? email.senderName! : email.senderEmail),
                            "sender_email": email.senderEmail,
                            "mailbox": "saved_folder",
                            "folder_name": folder.name,
                            "gmail_message_id": email.gmailMessageId,
                            "has_attachments": !email.attachments.isEmpty,
                            "saved_email_id": email.id.uuidString,
                            "created_at": iso.string(from: email.timestamp)
                        ] as [String: Any]
                    ])
                }
            }
        } catch {
            print("⚠️ Emails: Failed loading saved-folder emails for embeddings: \(error)")
        }

        return documents
    }

    /// Sync task embeddings - embed ALL tasks (no date limit)
    private func syncTaskEmbeddings() async -> Int {
        let allTasks = await taskSnapshot()
        guard !allTasks.isEmpty else { return 0 }
        let tagsById = await tagsByIdSnapshot()

        print("📅 Tasks: Syncing all \(allTasks.count) tasks (no date limit)")

        let documents = allTasks.map { task -> [String: Any] in
            let calendar = Calendar.current
            let iso = ISO8601DateFormatter()
            
            let tag = task.tagId.flatMap { tagsById[$0] }
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
            if task.isFromCalendar {
                content += "\nSource: iPhone Calendar"
                if let calendarTitle = task.calendarTitle {
                    content += " (\(calendarTitle))"
                }
                if let sourceType = task.calendarSourceType {
                    content += " - \(sourceType)"
                }
            } else {
                content += "\nSource: Seline"
            }

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
                    "calendar_event_id": task.calendarEventId ?? NSNull(),
                    "calendar_identifier": task.calendarIdentifier ?? NSNull(),
                    "calendar_title": task.calendarTitle ?? NSNull(),
                    "calendar_source_type": task.calendarSourceType ?? NSNull(),
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
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }
        let locations = LocationsManager.shared.savedPlaces
        guard !locations.isEmpty else { return 0 }

        print("📍 Locations: Syncing all \(locations.count) saved places")
        let memories = await fetchAllMemories()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let visitDateFormatter = DateFormatter()
        visitDateFormatter.dateStyle = .medium
        visitDateFormatter.timeStyle = .short

        var visitsByPlaceId: [UUID: [LocationVisitRecord]] = [:]
        var visitPeopleMap: [UUID: [Person]] = [:]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            visitsByPlaceId = Dictionary(grouping: visits, by: \.savedPlaceId)
            visitPeopleMap = await PeopleManager.shared.getPeopleForVisits(visitIds: visits.map(\.id))
        } catch {
            print("⚠️ Failed to load visit context for location embeddings: \(error)")
        }
        
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

            let aliases = memoryAliases(
                for: [place.displayName, place.name],
                memories: memories
            )
            if !aliases.isEmpty {
                content += "\nAliases: \(aliases.joined(separator: ", "))"
            }

            let placeVisits = visitsByPlaceId[place.id] ?? []
            let sortedVisits = placeVisits.sorted { $0.entryTime > $1.entryTime }
            let lastVisit = sortedVisits.first?.entryTime
            let notedVisits = sortedVisits.filter {
                guard let notes = $0.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !notes.isEmpty
            }
            let recentVisitNotes = notedVisits.prefix(3).compactMap { visit -> String? in
                guard let notes = visit.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
                    return nil
                }
                return "\(visitDateFormatter.string(from: visit.entryTime)): \(notes)"
            }

            var peopleCounts: [UUID: (person: Person, count: Int)] = [:]
            for visit in placeVisits {
                for person in visitPeopleMap[visit.id] ?? [] {
                    if let existing = peopleCounts[person.id] {
                        peopleCounts[person.id] = (person: existing.person, count: existing.count + 1)
                    } else {
                        peopleCounts[person.id] = (person: person, count: 1)
                    }
                }
            }
            let frequentPeople = peopleCounts.values
                .sorted {
                    if $0.count == $1.count {
                        return $0.person.name < $1.person.name
                    }
                    return $0.count > $1.count
                }
                .prefix(5)

            if !placeVisits.isEmpty {
                content += "\nVisit count: \(placeVisits.count)"
            }
            if let lastVisit {
                content += "\nLast visited: \(visitDateFormatter.string(from: lastVisit))"
            }
            if !frequentPeople.isEmpty {
                let peopleSummary = frequentPeople.map { "\($0.person.name) (\($0.count)x)" }.joined(separator: ", ")
                content += "\nPeople often with me here: \(peopleSummary)"
            }
            if !recentVisitNotes.isEmpty {
                content += "\nRecent visit reasons:"
                for note in recentVisitNotes {
                    content += "\n- \(note)"
                }
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
                    "has_notes": place.userNotes != nil && !place.userNotes!.isEmpty,
                    "aliases": aliases.isEmpty ? NSNull() : aliases,
                    "visit_count": placeVisits.count,
                    "last_visit": lastVisit.map { iso.string(from: $0) } ?? NSNull(),
                    "frequent_people": frequentPeople.isEmpty ? NSNull() : frequentPeople.map { $0.person.name },
                    "frequent_people_ids": frequentPeople.isEmpty ? NSNull() : frequentPeople.map { $0.person.id.uuidString },
                    "recent_visit_notes": recentVisitNotes.isEmpty ? NSNull() : recentVisitNotes
                ] as [String: Any]
            ]
        }
        
        // Check which locations need embedding (content changed or new)
        do {
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
            await ReceiptManager.shared.ensureLoaded()
            let allReceipts = await receiptStatsSnapshot()
            let notesData = await notesSnapshot()

            guard !allReceipts.isEmpty else { return 0 }

            print("💵 Receipts: Syncing all \(allReceipts.count) unified receipts (no date limit)")
            let memories = await fetchAllMemories()

            let iso = ISO8601DateFormatter()
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"

            let documents: [[String: Any]] = allReceipts.map { receipt in
                let date = receipt.date
                let amount = receipt.amount
                let category = receipt.category
                let legacyContent = receipt.legacyNoteId.flatMap { notesData.notesById[$0]?.content } ?? ""
                
                var content = """
                Receipt: \(receipt.title)
                Total: $\(String(format: "%.2f", amount))
                Date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                Category: \(category)
                Month: \(monthYearFormatter.string(from: date))
                """
                
                if !legacyContent.isEmpty {
                    content += "\n\nLegacy Details:\n\(legacyContent.prefix(900))"
                } else if !receipt.searchableText.isEmpty {
                    content += "\n\nDetails:\n\(receipt.searchableText.prefix(900))"
                }

                let aliases = memoryAliases(for: [receipt.title, receipt.merchant], memories: memories)
                if !aliases.isEmpty {
                    content += "\nAliases: \(aliases.joined(separator: ", "))"
                }
                
                return [
                    "document_type": "receipt",
                    "document_id": receipt.id.uuidString,
                    "title": "Receipt: \(receipt.title)",
                    "content": content,
                    "metadata": [
                        "merchant": receipt.merchant,
                        "amount": amount,
                        "category": category,
                        "date": iso.string(from: date),
                        "month_year": monthYearFormatter.string(from: date),
                        "legacy_note_id": receipt.legacyNoteId?.uuidString ?? NSNull(),
                        "aliases": aliases.isEmpty ? NSNull() : aliases
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

    private func embedDocumentsIfNeeded(
        _ documents: [[String: Any]],
        type: String
    ) async -> Int {
        guard !documents.isEmpty else { return 0 }

        do {
            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

            let ids = documents.compactMap { $0["document_id"] as? String }
            let hashes: [Int64] = documents.compactMap { doc in
                guard let content = doc["content"] as? String else { return nil }
                return hashContent32BitDjb2(content)
            }

            let neededIds = try await checkDocumentsNeedingEmbedding(
                userId: userId,
                documentType: type,
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
            return await batchEmbed(documents: docsToEmbed, type: type)
        } catch {
            print("❌ Error checking \(type) embeddings: \(error)")
            return await batchEmbed(documents: documents, type: type)
        }
    }
    
    private func normalizeWhitespace(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeAliasText(_ text: String) -> String {
        normalizeWhitespace(
            text
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        )
    }

    private func isMeaningfulAliasPhrase(_ text: String) -> Bool {
        let ignoredTokens: Set<String> = [
            "what", "when", "where", "who", "why", "how",
            "this", "that", "these", "those", "them", "they",
            "about", "all", "every", "list", "amount", "amounts",
            "pay", "paid", "spent", "spend", "total",
            "receipt", "receipts", "visit", "visits", "trip", "trips"
        ]
        let tokens = normalizeAliasText(text)
            .split(separator: " ")
            .map(String.init)
        guard !tokens.isEmpty else { return false }
        return tokens.contains(where: { $0.count >= 3 && !ignoredTokens.contains($0) })
    }

    private func memoryAliases(for seedTexts: [String], memories: [MemorySupabaseData]) -> [String] {
        let normalizedSeeds = seedTexts
            .map(normalizeAliasText)
            .filter { !$0.isEmpty }
        guard !normalizedSeeds.isEmpty else { return [] }

        var aliases = Set<String>()

        for memory in memories where memory.confidence >= 0.7 {
            let normalizedKey = normalizeAliasText(memory.key)
            let normalizedValue = normalizeAliasText(memory.value)

            guard isMeaningfulAliasPhrase(normalizedKey), isMeaningfulAliasPhrase(normalizedValue) else {
                continue
            }

            for seed in normalizedSeeds {
                if seed.contains(normalizedKey) || normalizedKey.contains(seed) {
                    if normalizedValue != seed {
                        aliases.insert(memory.value.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                if seed.contains(normalizedValue) || normalizedValue.contains(seed) {
                    if normalizedKey != seed {
                        aliases.insert(memory.key.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }

        return aliases
            .filter { !$0.isEmpty }
            .sorted()
    }
    
    /// Match the edge function's djb2 32-bit hash (signed int32), returned as Int64.
    private func hashContent32BitDjb2(_ content: String) -> Int64 {
        var hash: Int32 = 5381
        for scalar in content.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int32(scalar.value)
        }
        return Int64(hash)
    }
    
    /// Sync location visit embeddings - includes visit history, patterns, reasons (ALL visits, no date limit)
    private func syncLocationVisitEmbeddings() async -> Int {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

        do {
            // Embed PER-VISIT records so day queries can be answered precisely.
            // Embed ALL visits (no date limit) for complete historical context
            let client = await SupabaseManager.shared.getPostgrestClient()

            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                // No hard limit - trust database performance and let Postgres handle it
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            guard !visits.isEmpty else {
                print("📍 Visits: No visits found, skipping")
                return 0
            }

            print("📍 Visits: Syncing all \(visits.count) visits (no date limit)")

            let locations = LocationsManager.shared.savedPlaces
            let notesData = await notesSnapshot()
            let notesById = notesData.notesById
            let visitReceiptLinks = VisitReceiptLinkStore.allLinks()
            let linkedReceiptContexts = await linkedReceiptContextByNoteId(
                noteIds: Set(visitReceiptLinks.values),
                notesById: notesById
            )
            let iso = ISO8601DateFormatter()
            let memories = await fetchAllMemories()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .short
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            
            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"
            
            // Build documents (one per visit) - break up complex expression
            var documents: [[String: Any]] = []
            
            // Pre-fetch people for all visits in one query to avoid N round-trips.
            let batchedVisitPeople = await PeopleManager.shared.getPeopleForVisits(
                visitIds: visits.map(\.id)
            )
            let visitPeopleMap = batchedVisitPeople.reduce(into: [String: [Person]]()) { partialResult, entry in
                if !entry.value.isEmpty {
                    partialResult[entry.key.uuidString] = entry.value
                }
            }
            
            for visit in visits {
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
                if let city = place?.city, !city.isEmpty {
                    content += "\nCity: \(city)"
                }
                if let province = place?.province, !province.isEmpty {
                    content += "\nProvince: \(province)"
                }
                if let country = place?.country, !country.isEmpty {
                    content += "\nCountry: \(country)"
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
                
                // Add people who were at this visit
                if let people = visitPeopleMap[visit.id.uuidString], !people.isEmpty {
                    let personNames = people.map { $0.name }.joined(separator: ", ")
                    content += "\nWith: \(personNames)"
                    // Also add relationship context for better semantic search
                    let relationships = people.map { $0.relationshipDisplayText }.joined(separator: ", ")
                    content += " (\(relationships))"
                }
                
                if let notes = visit.visitNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content += "\nReason/Notes: \(notes)"
                }

                let linkedReceiptId = visitReceiptLinks[visit.id]
                let linkedReceiptNote = linkedReceiptId.flatMap { notesById[$0] }
                let linkedReceiptAmount: Double? = {
                    guard let linkedReceiptNote else { return nil }
                    let amountSource = linkedReceiptNote.content.isEmpty ? linkedReceiptNote.title : linkedReceiptNote.content
                    return CurrencyParser.extractAmount(from: amountSource)
                }()
                let linkedReceiptContext = linkedReceiptNote.flatMap { linkedReceiptContexts[$0.id] }
                let linkedReceiptDate = linkedReceiptContext?.parsedDate
                let linkedReceiptCategory = linkedReceiptContext?.category
                if let linkedReceiptNote {
                    content += "\nLinked receipt: \(linkedReceiptNote.title)"
                    if let amount = linkedReceiptAmount {
                        content += " ($\(String(format: "%.2f", amount)))"
                    }
                    if let category = linkedReceiptCategory {
                        content += " [\(category)]"
                    }
                }
                
                if let mergeReason = visit.mergeReason, !mergeReason.isEmpty {
                    content += "\nMerge info: \(mergeReason)"
                }
                
                if let score = visit.confidenceScore {
                    content += "\nConfidence: \(String(format: "%.2f", score))"
                }
                
                content += "\nMonth: \(monthYearFormatter.string(from: start))"

                let aliases = memoryAliases(
                    for: [placeName, linkedReceiptNote?.title ?? ""],
                    memories: memories
                )
                if !aliases.isEmpty {
                    content += "\nAliases: \(aliases.joined(separator: ", "))"
                }
                
                // Get people names for metadata
                let peopleNames = visitPeopleMap[visit.id.uuidString]?.map { $0.name } ?? []
                let peopleIds = visitPeopleMap[visit.id.uuidString]?.map { $0.id.uuidString } ?? []
                
                let document: [String: Any] = [
                    "document_type": "visit",
                    "document_id": visit.id.uuidString,
                    "title": "Visit: \(placeName)",
                    "content": content,
                    "metadata": [
                        "place_id": visit.savedPlaceId.uuidString,
                        "place_name": placeName,
                        "place_category": placeCategory,
                        "address": address ?? NSNull(),
                        "city": place?.city ?? NSNull(),
                        "province": place?.province ?? NSNull(),
                        "country": place?.country ?? NSNull(),
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
                        "visit_notes": visit.visitNotes ?? NSNull(),
                        "people": peopleNames.isEmpty ? NSNull() : peopleNames,
                        "people_ids": peopleIds.isEmpty ? NSNull() : peopleIds,
                        "aliases": aliases.isEmpty ? NSNull() : aliases,
                        "linked_receipt_id": linkedReceiptId?.uuidString ?? NSNull(),
                        "linked_receipt_title": linkedReceiptNote?.title ?? NSNull(),
                        "linked_receipt_amount": linkedReceiptAmount ?? NSNull(),
                        "linked_receipt_date": linkedReceiptDate.map { iso.string(from: $0) } ?? NSNull(),
                        "linked_receipt_category": linkedReceiptCategory ?? NSNull()
                    ] as [String: Any]
                ]
                documents.append(document)
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
        
        // Pre-fetch visit IDs for all people to include in embeddings
        var personVisitsMap: [UUID: [UUID]] = [:]
        for person in people {
            let visitIds = await PeopleManager.shared.getVisitIdsForPerson(personId: person.id)
            if !visitIds.isEmpty {
                personVisitsMap[person.id] = visitIds
            }
        }
        
        // Pre-fetch location names for visits
        let allVisitIds = personVisitsMap.values.flatMap { $0 }
        var visitLocationsMap: [UUID: String] = [:]
        let locations = LocationsManager.shared.savedPlaces
        
        // Get all visits from Supabase to find location names
        if !allVisitIds.isEmpty {
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                let response = try await client
                    .from("location_visits")
                    .select("id, saved_place_id")
                    .in("id", values: allVisitIds.map { $0.uuidString })
                    .execute()
                
                // Parse as generic JSON to avoid needing a new struct
                if let jsonArray = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] {
                    for record in jsonArray {
                        if let idStr = record["id"] as? String,
                           let id = UUID(uuidString: idStr),
                           let placeIdStr = record["saved_place_id"] as? String,
                           let placeId = UUID(uuidString: placeIdStr),
                           let place = locations.first(where: { $0.id == placeId }) {
                            visitLocationsMap[id] = place.displayName
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to fetch visit locations for people: \(error)")
            }
        }
        
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
            
            // Add visit history - places they've been together
            if let visitIds = personVisitsMap[person.id], !visitIds.isEmpty {
                let locationNames = visitIds.compactMap { visitLocationsMap[$0] }
                if !locationNames.isEmpty {
                    content += "\nPlaces visited together: \(locationNames.joined(separator: ", "))"
                }
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
                    "is_favourite": person.isFavourite,
                    "visit_count": personVisitsMap[person.id]?.count ?? 0
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

    private func syncRecurringExpenseEmbeddings() async -> Int {
        do {
            let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
            guard !expenses.isEmpty else { return 0 }

            let iso = ISO8601DateFormatter()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none

            let documents: [[String: Any]] = expenses.map { expense in
                let monthlyEstimate = NSDecimalNumber(decimal: expense.yearlyAmount).doubleValue / 12.0
                var content = """
                Recurring Expense: \(expense.title)
                Status: \(expense.statusBadge)
                Amount: \(expense.formattedAmount)
                Frequency: \(expense.frequency.rawValue)
                Next occurrence: \(dateFormatter.string(from: expense.nextOccurrence))
                Start date: \(dateFormatter.string(from: expense.startDate))
                Reminder: \(expense.reminderOption.displayName)
                Monthly estimate: \(CurrencyParser.formatAmount(monthlyEstimate))
                """

                if let description = expense.description, !description.isEmpty {
                    content += "\nDescription: \(description)"
                }
                if let category = expense.category, !category.isEmpty {
                    content += "\nCategory: \(category)"
                }
                if let endDate = expense.endDate {
                    content += "\nEnd date: \(dateFormatter.string(from: endDate))"
                }

                return [
                    "document_type": "recurring_expense",
                    "document_id": expense.id.uuidString,
                    "title": expense.title,
                    "content": content,
                    "metadata": [
                        "title": expense.title,
                        "amount": NSDecimalNumber(decimal: expense.amount).doubleValue,
                        "category": expense.category ?? NSNull(),
                        "frequency": expense.frequency.rawValue,
                        "status": expense.statusBadge,
                        "is_active": expense.isActive,
                        "date": iso.string(from: expense.nextOccurrence),
                        "next_occurrence": iso.string(from: expense.nextOccurrence),
                        "start_date": iso.string(from: expense.startDate),
                        "end_date": expense.endDate.map { iso.string(from: $0) } ?? NSNull(),
                        "updated_at": iso.string(from: expense.updatedAt)
                    ] as [String: Any]
                ]
            }

            return await embedDocumentsIfNeeded(documents, type: "recurring_expense")
        } catch {
            print("❌ Error syncing recurring expense embeddings: \(error)")
            return 0
        }
    }

    private func syncAttachmentEmbeddings() async -> Int {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let attachmentRows: [AttachmentSupabaseData] = try await client
                .from("attachments")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            let attachments = attachmentRows.compactMap(NoteAttachment.init(from:))
            guard !attachments.isEmpty else { return 0 }

            let extractedRows: [ExtractedDataSupabaseData] = try await client
                .from("extracted_data")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            let extractedByAttachmentId = Dictionary(
                uniqueKeysWithValues: extractedRows.compactMap { row -> (UUID, ExtractedData)? in
                    guard let extracted = ExtractedData(from: row) else { return nil }
                    return (extracted.attachmentId, extracted)
                }
            )
            let notesById = await notesSnapshot().notesById
            let iso = ISO8601DateFormatter()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none

            let documents: [[String: Any]] = attachments.map { attachment in
                let note = notesById[attachment.noteId]
                let extracted = extractedByAttachmentId[attachment.id]
                let documentTypeLabel = attachment.documentType ?? extracted?.documentType ?? "document"

                var content = """
                Attachment: \(attachment.fileName)
                File type: \(attachment.fileType)
                Document type: \(documentTypeLabel)
                Note: \(note?.title ?? "Unknown note")
                Uploaded: \(dateFormatter.string(from: attachment.uploadedAt))
                """

                if let summary = extractedSummaryText(extracted), !summary.isEmpty {
                    content += "\nSummary: \(summary)"
                }
                if let rawText = extracted?.rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty {
                    content += "\nExtracted text:\n\(String(rawText.prefix(6000)))"
                }

                let documentDate = extracted?.updatedAt ?? attachment.updatedAt
                return [
                    "document_type": "attachment",
                    "document_id": attachment.id.uuidString,
                    "title": "Attachment: \(attachment.fileName)",
                    "content": content,
                    "metadata": [
                        "file_name": attachment.fileName,
                        "file_type": attachment.fileType,
                        "document_type_label": documentTypeLabel,
                        "note_id": attachment.noteId.uuidString,
                        "note_title": note?.title ?? NSNull(),
                        "date": iso.string(from: documentDate),
                        "created_at": iso.string(from: attachment.createdAt),
                        "updated_at": iso.string(from: documentDate),
                        "has_extracted_text": extracted?.rawText?.isEmpty == false
                    ] as [String: Any]
                ]
            }

            return await embedDocumentsIfNeeded(documents, type: "attachment")
        } catch {
            print("❌ Error syncing attachment embeddings: \(error)")
            return 0
        }
    }

    private func syncTrackerEmbeddings() async -> Int {
        let threads = await trackerThreadsSnapshot()
        guard !threads.isEmpty else { return 0 }

        let iso = ISO8601DateFormatter()
        let documents: [[String: Any]] = threads.map { thread in
            let sortedChanges = thread.memorySnapshot.changeLog.sorted { lhs, rhs in
                if lhs.effectiveAt == rhs.effectiveAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.effectiveAt > rhs.effectiveAt
            }
            let latestEffectiveAt = sortedChanges.first?.effectiveAt ?? thread.updatedAt
            let actors = Array(Set(sortedChanges.flatMap { $0.context?.actors ?? [] })).sorted()
            let tags = Array(Set(sortedChanges.flatMap { $0.context?.tags ?? [] })).sorted()

            var content = """
            Tracker: \(thread.title)
            Status: \(thread.status.rawValue)
            Rules:
            \(thread.memorySnapshot.normalizedRulesText)

            Current summary:
            \(thread.memorySnapshot.normalizedSummaryText)
            """

            if !thread.memorySnapshot.quickFacts.isEmpty {
                content += "\nQuick facts: \(thread.memorySnapshot.quickFacts.joined(separator: " | "))"
            }
            if let cachedState = thread.cachedState {
                content += "\nHeadline: \(cachedState.headline)"
                if !cachedState.blockers.isEmpty {
                    content += "\nBlockers: \(cachedState.blockers.joined(separator: ", "))"
                }
                if !cachedState.warnings.isEmpty {
                    content += "\nWarnings: \(cachedState.warnings.joined(separator: ", "))"
                }
            }
            if let notes = thread.memorySnapshot.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                content += "\nNotes: \(notes)"
            }
            if !sortedChanges.isEmpty {
                content += "\nRecent changes:"
                for change in sortedChanges.prefix(8) {
                    content += "\n- \(formattedTrackerChangeLine(change))"
                }
            }

            return [
                "document_type": "tracker",
                "document_id": thread.id.uuidString,
                "title": thread.title,
                "content": content,
                "metadata": [
                    "thread_title": thread.title,
                    "status": thread.status.rawValue,
                    "change_count": thread.memorySnapshot.changeLog.count,
                    "date": iso.string(from: latestEffectiveAt),
                    "effective_at": iso.string(from: latestEffectiveAt),
                    "updated_at": iso.string(from: thread.updatedAt),
                    "actors": actors.isEmpty ? NSNull() : actors,
                    "tags": tags.isEmpty ? NSNull() : tags
                ] as [String: Any]
            ]
        }

        return await embedDocumentsIfNeeded(documents, type: "tracker")
    }

    private func syncBudgetEmbeddings() async -> Int {
        let budgetData = await budgetSnapshot()
        let budgets = budgetData.budgets
        let reminders = budgetData.reminders
        guard !budgets.isEmpty || !reminders.isEmpty else { return 0 }

        let iso = ISO8601DateFormatter()
        var documents: [[String: Any]] = []

        for budgetEntry in budgets {
            let budget = budgetEntry.budget
            let status = budgetEntry.status
            let content = """
            Expense Budget: \(budget.name)
            Period: \(budget.period.displayName)
            Limit: \(CurrencyParser.formatAmount(budget.limit))
            Current spend: \(CurrencyParser.formatAmount(status.spent))
            Remaining: \(CurrencyParser.formatAmount(status.remaining))
            Progress: \(Int(status.progress * 100))%
            Active: \(budget.isActive ? "Yes" : "No")
            """

            documents.append([
                "document_type": "budget",
                "document_id": "budget_\(budget.id.uuidString)",
                "title": "Budget: \(budget.name)",
                "content": content,
                "metadata": [
                    "subtype": "budget",
                    "name": budget.name,
                    "period": budget.period.rawValue,
                    "limit": budget.limit,
                    "spent": status.spent,
                    "remaining": status.remaining,
                    "is_active": budget.isActive,
                    "date": iso.string(from: budget.updatedAt),
                    "updated_at": iso.string(from: budget.updatedAt)
                ] as [String: Any]
            ])
        }

        for reminder in reminders {
            let schedule = String(format: "%02d:%02d", reminder.hour, reminder.minute)
            var content = """
            Expense Reminder: \(reminder.expenseName)
            Frequency: \(reminder.frequency.displayName)
            Scheduled time: \(schedule)
            """

            if let weekday = reminder.weekday {
                content += "\nWeekday: \(weekday)"
            }
            if let dayOfMonth = reminder.dayOfMonth {
                content += "\nDay of month: \(dayOfMonth)"
            }

            documents.append([
                "document_type": "budget",
                "document_id": "reminder_\(reminder.id.uuidString)",
                "title": "Reminder: \(reminder.expenseName)",
                "content": content,
                "metadata": [
                    "subtype": "reminder",
                    "name": reminder.expenseName,
                    "frequency": reminder.frequency.rawValue,
                    "hour": reminder.hour,
                    "minute": reminder.minute,
                    "date": iso.string(from: reminder.updatedAt),
                    "updated_at": iso.string(from: reminder.updatedAt)
                ] as [String: Any]
            ])
        }

        return await embedDocumentsIfNeeded(documents, type: "budget")
    }

    private func extractedSummaryText(_ extracted: ExtractedData?) -> String? {
        guard let extracted else { return nil }
        if let summary = extracted.extractedFields["summary"]?.value as? String {
            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func formattedTrackerChangeLine(_ change: TrackerChange) -> String {
        var fragments: [String] = []
        let headline = change.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let headline, !headline.isEmpty {
            fragments.append(headline)
        }

        let normalizedContent = change.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedContent.isEmpty && normalizedContent != (headline ?? "") {
            fragments.append(normalizedContent)
        }

        if let context = change.context {
            if !context.actors.isEmpty {
                fragments.append("actors: \(context.actors.joined(separator: ", "))")
            }
            if let subject = context.subject, !subject.isEmpty {
                fragments.append("subject: \(subject)")
            }
            if let amount = context.amount {
                fragments.append("amount: \(formattedTrackerMetric(amount, unit: context.unit))")
            }
            if let resultingValue = context.resultingValue {
                fragments.append("result: \(formattedTrackerMetric(resultingValue, unit: context.unit))")
            }
            if let periodLabel = context.periodLabel, !periodLabel.isEmpty {
                fragments.append("period: \(periodLabel)")
            }
            if !context.tags.isEmpty {
                fragments.append("tags: \(context.tags.joined(separator: ", "))")
            }
        }

        return fragments.joined(separator: " | ")
    }

    private func formattedTrackerMetric(_ value: Double, unit: String?) -> String {
        if let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            let lowered = unit.lowercased()
            if lowered == "$" || lowered == "cad" || lowered == "usd" || lowered.contains("dollar") {
                return CurrencyParser.formatAmount(value)
            }
            if unit == "%" {
                return "\(String(format: "%.2f", value))%"
            }
            return "\(String(format: "%.2f", value)) \(unit)"
        }

        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
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
                    print("⚠️ \(response.failed) \(type)s failed to embed (out of \(response.total))")
                    if let results = response.results {
                        let failedItems = results.filter { !$0.success }
                        for item in failedItems {
                            print("   — \(type) \(item.document_id): \(item.error ?? "unknown error")")
                        }
                    }
                } else {
                    print("✅ Successfully embedded \(response.embedded) \(type)s")
                }
            } catch {
                print("❌ Batch embed error for \(type): \(error)")
                print("   Error details: \(error.localizedDescription)")
                if let vectorError = error as? VectorSearchError {
                    print("   VectorSearchError: \(vectorError.errorDescription ?? "unknown")")
                }
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
        LLMDiagnostics.logEmbeddingRequest(body)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw VectorSearchError.invalidResponse
                }

                if httpResponse.statusCode != 200 {
                    if shouldRetryHTTPStatus(httpResponse.statusCode), attempt < maxAttempts {
                        let delayNs = retryDelayNanoseconds(forAttempt: attempt)
                        print("⚠️ embeddings-proxy HTTP \(httpResponse.statusCode), retrying attempt \(attempt + 1)/\(maxAttempts)")
                        try? await Task.sleep(nanoseconds: delayNs)
                        continue
                    }

                    if let errorResponse = try? JSONDecoder().decode(VectorSearchErrorResponse.self, from: data) {
                        throw VectorSearchError.apiError(errorResponse.error)
                    }
                    throw VectorSearchError.httpError(httpResponse.statusCode)
                }

                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                lastError = error
                if isTransientNetworkError(error), attempt < maxAttempts {
                    let delayNs = retryDelayNanoseconds(forAttempt: attempt)
                    print("⚠️ embeddings-proxy transient network error, retrying attempt \(attempt + 1)/\(maxAttempts): \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? VectorSearchError.invalidResponse
    }

    private func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let baseSeconds = 0.35
        let multiplier = pow(2.0, Double(max(0, attempt - 1)))
        let seconds = min(baseSeconds * multiplier, 1.4)
        return UInt64(seconds * 1_000_000_000)
    }

    private func shouldRetryHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost,
                 .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorResourceUnavailable:
                return true
            default:
                return false
            }
        }

        return false
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
        case recurringExpense = "recurring_expense"
        case attachment = "attachment"
        case tracker = "tracker"
        case budget = "budget"
        
        var displayName: String {
            switch self {
            case .note: return "Notes"
            case .email: return "Emails"
            case .task: return "Events/Tasks"
            case .location: return "Locations"
            case .receipt: return "Receipts"
            case .visit: return "Visits"
            case .person: return "People"
            case .recurringExpense: return "Recurring Expenses"
            case .attachment: return "Attachments"
            case .tracker: return "Trackers"
            case .budget: return "Budgets & Reminders"
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

    struct RelevantContextResult {
        let context: String
        let evidence: [RelevantContentInfo]
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

// MARK: - MemorySupabaseData Helper (for annotation)

private struct MemorySupabaseData: Codable {
    let id: String
    let memory_type: String
    let key: String
    let value: String
    let confidence: Float
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
