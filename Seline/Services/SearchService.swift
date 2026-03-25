import Foundation
import Combine

/// Wraps any Decodable so an array decode can recover from individual element failures.
private struct AnySafeDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

@MainActor
class SearchService: ObservableObject {
    private static let lastConversationStorageKey = "lastConversation"
    private static let lastActiveConversationIdStorageKey = "lastActiveConversationId"

    enum ChatLoadingPhase: Equatable {
        case idle
        case retrieving
        case generating

        var statusLabel: String {
            switch self {
            case .idle:
                return "Thinking..."
            case .retrieving:
                return "Retrieving data..."
            case .generating:
                return "Generating answer..."
            }
        }
    }

    static let shared = SearchService()

    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var currentQueryType: QueryType = .search
    @Published var pendingEventCreation: EventCreationData?
    @Published var pendingNoteCreation: NoteCreationData?
    @Published var pendingNoteUpdate: NoteUpdateData?
    @Published var questionResponse: String? = nil
    @Published var isLoadingQuestionResponse: Bool = false
    @Published var chatLoadingPhase: ChatLoadingPhase = .idle

    // Conversation state
    @Published var conversationHistory: [ConversationMessage] = []
    /// Incremented when the last message is updated in place (e.g. eventCreationInfo/source pills) so the chat can re-scroll to show new content.
    @Published var lastMessageContentVersion: Int = 0
    @Published var isInConversationMode: Bool = false
    @Published var conversationTitle: String = "New Conversation"
    @Published var conversationKind: ConversationKind = .standard
    @Published var savedConversations: [SavedConversation] = []
    @Published var isNewConversation: Bool = false  // Track if this is a new conversation (not loaded from history)
    @Published var currentTrackerThread: TrackerThread? = nil
    @Published var pendingTrackerDraft: TrackerOperationDraft? = nil
    private var currentlyLoadedConversationId: UUID? = nil
    private var lastGeneratedTitleMessageCount: Int = 0

    // NEW: Conversational action system
    @Published var currentInteractiveAction: InteractiveAction?
    @Published var actionPrompt: String? = nil
    @Published var isWaitingForActionResponse: Bool = false
    @Published var actionSuggestions: [NoteSuggestion] = []

    // Note refinement mode - for interactive note creation/updating
    @Published var isRefiningNote: Bool = false
    @Published var currentNoteBeingRefined: Note? = nil
    @Published var pendingRefinementContent: String? = nil  // Computed content waiting for user confirmation

    // Multi-action support
    @Published var pendingMultiActions: [(actionType: ActionType, query: String)] = []
    @Published var currentMultiActionIndex: Int = 0
    private var originalMultiActionQuery: String = ""  // Track original query for context

    // Streaming response support
    @Published var enableStreamingResponses: Bool = true  // Toggle for streaming vs non-streaming

    private let chatAgent = ChatAgentService.shared
    private var currentConversationAnchorState: ConversationAnchorState?

    // Track recently created items for context in follow-up actions
    private var lastCreatedEventTitle: String? = nil
    private var lastCreatedEventDate: String? = nil
    private var lastCreatedNoteTitle: String? = nil

    private var searchableProviders: [SearchDestination: Searchable] = [:]
    private var cachedContent: [SearchableItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let conversationActionHandler = ConversationActionHandler.shared
    private let infoExtractor = InformationExtractor.shared
    private let trackerStore = TrackerStore.shared
    private let trackerParserService = TrackerParserService.shared
    private let locationsManager = LocationsManager.shared
    private let mapsService = GoogleMapsService.shared

    var chatLoadingStatusLabel: String {
        chatLoadingPhase.statusLabel
    }

    var currentConversationId: UUID? {
        currentlyLoadedConversationId
    }

    var isTrackerConversation: Bool {
        conversationKind == .tracker
    }

    private init() {
        // Load saved conversations from local storage
        loadConversationHistoryLocally()
        trackerStore.loadLocalThreads()

        // Auto-refresh search when query changes with debounce
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
            .store(in: &cancellables)

        Task {
            await refreshTrackerThreadsFromSupabase()
        }

    }

    // MARK: - Registration

    func registerSearchableProvider(_ provider: Searchable, for tab: SearchDestination) {
        searchableProviders[tab] = provider
        refreshSearchableContent()
    }

    func unregisterSearchableProvider(for tab: SearchDestination) {
        searchableProviders.removeValue(forKey: tab)
        refreshSearchableContent()
    }

    // MARK: - Search Operations

    func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            currentQueryType = .search
            isSearching = false
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if this is a question that should use conversation mode
        // ALL questions should go to conversation, not search results
        if isQuestion(trimmedQuery) {
            // Start conversation instead of normal search
            await startConversation(with: trimmedQuery)
            return
        }

        isSearching = true

        // DISABLED: Action creation behavior (create note/event from chat)
        // All queries now go to analysis/conversation mode only
        // No automatic note/event creation from chat responses

        // Treat all queries as questions/analysis - no action mode
        await startConversation(with: trimmedQuery)
        isSearching = false
    }

    // MARK: - Action Query Handling

    // MARK: - Multi-Action Helper (DISABLED)

    // Action creation behavior has been disabled
    // This method is no longer called

    private func processNextMultiAction() async {
        // DISABLED: No longer processing multi-actions
        print("⚠️ Action creation disabled - multi-action processing skipped")
        return
    }

    // MARK: - Action Confirmation Methods (DISABLED)

    // Action creation has been disabled
    // These methods are no longer called and do nothing

    func confirmEventCreation() {
        // DISABLED: Event creation from chat disabled
        print("⚠️ Action creation disabled - event creation skipped")
        return
    }

    func confirmNoteCreation() {
        // DISABLED: Note creation from chat disabled
        print("⚠️ Action creation disabled - note creation skipped")
        return
    }

    func confirmNoteUpdate() {
        // DISABLED: Note updates from chat disabled
        print("⚠️ Action creation disabled - note update skipped")
        return
    }

    /// Async version of confirmNoteUpdate that waits for sync to complete
    private func confirmNoteUpdateAsync() async {
        // DISABLED: No note updates from chat
        return
    }

    func cancelAction() {
        let hasAction = pendingEventCreation != nil || pendingNoteCreation != nil || pendingNoteUpdate != nil

        pendingEventCreation = nil
        pendingNoteCreation = nil
        pendingNoteUpdate = nil

        // Cancel multi-actions as well
        let hasMultiActions = !pendingMultiActions.isEmpty
        if hasMultiActions {
            pendingMultiActions = []
            currentMultiActionIndex = 0
            originalMultiActionQuery = ""
        }

        // If in conversation mode and had a pending action, add cancellation message
        if isInConversationMode && (hasAction || hasMultiActions) {
            let cancelMsg = ConversationMessage(
                isUser: false,
                text: "Okay, I cancelled that action. What else can I help you with?",
                intent: .general
            )
            conversationHistory.append(cancelMsg)
        }
    }

    private func searchContent(query: String) async -> [SearchResult] {
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else { return [] }

        // Extract related items from the query (if user searches for something, find related items)
        let relatedItemTitles = extractReferencedItemTitles(from: query)

        // Extract temporal range if mentioned in query
        let temporalRange = TemporalUnderstandingService.shared.extractTemporalRange(from: query)
        let temporalBounds = temporalRange.map {
            TemporalUnderstandingService.shared.normalizedBounds(for: $0)
        }

        // Extract topics from this search for conversation context
        let extractedTopics = ConversationContextService.shared.extractTopicsFromQuery(query)

        var results: [SearchResult] = []

        // OPTIMIZATION: Only compute semantic scores for top keyword matches
        // This avoids expensive semantic scoring on all 500+ cached items
        // First pass: keyword-based filtering to get top candidates
        let maxSemanticCandidates = 50
        var keywordResults: [SearchResult] = []

        for item in cachedContent {
            let searchText = item.searchText.lowercased()
            let keywordScore = calculateRelevanceScore(
                searchText: searchText,
                queryWords: queryWords,
                item: item,
                relatedItemTitles: relatedItemTitles
            )

            if keywordScore > 0 {
                keywordResults.append(SearchResult(
                    item: item,
                    relevanceScore: keywordScore,
                    matchedText: findMatchedText(in: item, queryWords: queryWords)
                ))
            }
        }

        // Sort by keyword score and take top candidates for semantic scoring
        keywordResults.sort { $0.relevanceScore > $1.relevanceScore }
        let candidatesForSemanticScoring = Array(keywordResults.prefix(maxSemanticCandidates))

        // Get semantic similarity scores only for top candidates
        let semanticScores = await getSemanticSimilarityScores(
            query: query,
            for: candidatesForSemanticScoring.map { $0.item }
        )

        // Process only the candidates we scored semantically
        for result in candidatesForSemanticScoring {
            let item = result.item

            // TEMPORAL FILTERING: Skip items outside the requested date range
            if let temporalBounds, let itemDate = item.date {
                if itemDate < temporalBounds.start || itemDate >= temporalBounds.end {
                    continue  // Skip this item, it's outside the time range
                }
            }

            let keywordScore = result.relevanceScore

            // Get semantic score for this item
            let semanticScore = semanticScores[item.identifier] ?? 0.0

            // CONVERSATION CONTEXT BOOST: Boost items related to current topic
            let contextBoost = ConversationContextService.shared.getContextBoost(for: item.tags)

            // Combine all scoring factors:
            // 70% keyword-based, 30% semantic similarity, + context boost
            let combinedScore = (keywordScore * 0.7) + (semanticScore * 0.3) + contextBoost

            let matchedText = result.matchedText
            results.append(SearchResult(
                item: item,
                relevanceScore: combinedScore,
                matchedText: matchedText
            ))
        }

        // Track this search in conversation context (for follow-up understanding)
        ConversationContextService.shared.trackSearch(
            query: query,
            topics: extractedTopics,
            resultCount: results.count
        )

        // Sort by combined score
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Get semantic similarity scores for all items in parallel
    private func getSemanticSimilarityScores(
        query: String,
        for items: [SearchableItem]
    ) async -> [String: Double] {
        var scores: [String: Double] = [:]

        // Process items in batches to avoid overwhelming the API
        let batchSize = 5
        for i in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[i..<min(i + batchSize, items.count)])
            let batchItems = batch.map { ($0.identifier, $0.searchText) }

            do {
                let batchScores = try await GeminiService.shared.getSemanticSimilarityScores(
                    query: query,
                    contents: batchItems
                )
                scores.merge(batchScores) { _, new in new }
            } catch {
                // Fallback: return zero scores, keyword matching will still work
            }
        }

        return scores
    }

    private func calculateRelevanceScore(
        searchText: String,
        queryWords: [String],
        item: SearchableItem,
        relatedItemTitles: [String]
    ) -> Double {
        var score: Double = 0
        let words = searchText.components(separatedBy: .whitespacesAndNewlines)

        for queryWord in queryWords {
            // Exact word match (highest score)
            if words.contains(queryWord) {
                score += 3.0
            }
            // Partial word match
            else if words.contains(where: { $0.contains(queryWord) }) {
                score += 2.0
            }
            // Substring match anywhere in text
            else if searchText.contains(queryWord) {
                score += 1.0
            }
        }

        // Bonus for multiple query words found
        if queryWords.count > 1 && score > 0 {
            score *= 1.2
        }

        // NEW: Bonus for tag matches (category/topic relevance)
        for tag in item.tags {
            let lowerTag = tag.lowercased()
            if queryWords.contains(where: { lowerTag.contains($0) || $0.contains(lowerTag) }) {
                score += 2.5  // Strong boost for tag matches
            }
        }

        // NEW: Bonus for related items (cross-references)
        for relatedTitle in relatedItemTitles {
            if item.title.lowercased().contains(relatedTitle.lowercased()) ||
               item.content.lowercased().contains(relatedTitle.lowercased()) {
                score += 1.5  // Connection bonus
            }
        }

        return score
    }

    /// Extract referenced item titles from the query (cross-reference detection)
    private func extractReferencedItemTitles(from query: String) -> [String] {
        let lowerQuery = query.lowercased()
        var referencedTitles: [String] = []

        // Check all cached items to see if their titles are mentioned in the query
        for item in cachedContent {
            let lowerTitle = item.title.lowercased()
            // Only add if the title is meaningful (longer than 2 chars) and mentioned in query
            if lowerTitle.count > 2 && lowerQuery.contains(lowerTitle) {
                referencedTitles.append(item.title)
            }
        }

        return referencedTitles
    }

    private func findMatchedText(in item: SearchableItem, queryWords: [String]) -> String {
        // Try to find the best matching text from title or content
        for queryWord in queryWords {
            if item.title.lowercased().contains(queryWord) {
                return item.title
            }
        }

        // If no title match, use first part of content
        let contentWords = item.content.components(separatedBy: .whitespacesAndNewlines)
        let preview = contentWords.prefix(10).joined(separator: " ")
        return preview.isEmpty ? item.title : preview
    }

    // MARK: - Content Management

    private func refreshSearchableContent() {
        cachedContent = searchableProviders.values.flatMap { provider in
            provider.getSearchableContent()
        }
    }

    func refreshContent() {
        refreshSearchableContent()

        // Re-run search if there's an active query
        if !searchQuery.isEmpty {
            Task {
                await performSearch(query: searchQuery)
            }
        }
    }

    // MARK: - Navigation Helpers

    func navigateToResult(_ result: SearchResult) -> SearchDestination {
        return result.item.type
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Conversation Management

    /// Check if a query should trigger conversation mode
    func isQuestion(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Check for question mark
        if lowercased.contains("?") {
            return true
        }

        // Check for question keywords
        let questionKeywords = ["why", "how", "what", "when", "where", "who", "compare", "summarize", "explain", "analyze", "between", "difference", "which", "tell me", "show me", "list"]
        for keyword in questionKeywords {
            if lowercased.hasPrefix(keyword) || lowercased.contains(" " + keyword + " ") {
                return true
            }
        }

        return false
    }

    /// Simple helper: Add message to history without reprocessing
    private func addMessageToHistory(_ text: String, isUser: Bool, intent: QueryIntent = .general) {
        let msg = ConversationMessage(isUser: isUser, text: text, intent: intent)
        conversationHistory.append(msg)
    }

    /// Add a message to the conversation and process it
    func addConversationMessage(_ userMessage: String) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !ChatUsageTracker.shared.isLimitReached else {
            print("🚫 Daily chat limit reached; ignoring new message")
            return
        }

        // Enter conversation mode if not already in it
        if !isInConversationMode {
            isInConversationMode = true
        }

        if conversationKind == .tracker {
            await addTrackerConversationMessage(trimmed)
            return
        }

        // Check if the last message is already this user message (prevents duplicates on regeneration)
        let shouldAddUserMessage: Bool
        if let lastMessage = conversationHistory.last, lastMessage.isUser && lastMessage.text == trimmed {
            shouldAddUserMessage = false
        } else {
            shouldAddUserMessage = true
        }

        // Add user message to history for conversation (only if not duplicate)
        if shouldAddUserMessage {
            addMessageToHistory(trimmed, isUser: true, intent: .general)
        }

        // Don't update title during new conversations - keep it hidden until saved
        // Only update title for existing conversations
        if !isNewConversation {
            updateConversationTitle()
        }

        // Get AI response with full conversation history for context
        isLoadingQuestionResponse = true
        chatLoadingPhase = .retrieving
        let thinkStartTime = Date()  // Track when LLM starts thinking

        // Standard chat runs only through the new ChatAgentService path.
        await addConversationMessageWithChatAgent(trimmed, thinkStartTime: thinkStartTime)
    }

    private func addTrackerConversationMessage(_ userMessage: String) async {
        let lower = userMessage.lowercased()

        if pendingTrackerDraft != nil {
            if isTrackerConfirmationMessage(lower) {
                applyPendingTrackerDraft()
                return
            }
            if isTrackerCancellationMessage(lower) {
                cancelPendingTrackerDraft()
                return
            }
        }

        let shouldAddUserMessage = !(conversationHistory.last?.isUser == true && conversationHistory.last?.text == userMessage)
        if shouldAddUserMessage {
            let userMessageRecord = ConversationMessage(
                isUser: true,
                text: userMessage,
                intent: .general,
                trackerThreadId: currentTrackerThread?.id
            )
            conversationHistory.append(userMessageRecord)
        }

        isLoadingQuestionResponse = true
        chatLoadingPhase = .generating

        let outcome = await trackerParserService.handleMessage(
            userMessage,
            in: currentTrackerThread,
            conversationHistory: conversationHistory
        )

        pendingTrackerDraft = outcome.draft

        if outcome.shouldPersistAssistantMessage {
            let assistantMessage = ConversationMessage(
                isUser: false,
                text: outcome.responseText,
                intent: .general,
                trackerThreadId: currentTrackerThread?.id,
                trackerOperationDraft: outcome.draft,
                trackerStateSnapshot: outcome.derivedState
            )
            conversationHistory.append(assistantMessage)
        }

        if outcome.commitsProjectedStateToThread,
           let projectedState = outcome.derivedState {
            updateTrackerSubtitle(from: projectedState)
        }

        isLoadingQuestionResponse = false
        chatLoadingPhase = .idle
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }
    
    // MARK: - ChatAgent Implementation

    private func addConversationMessageWithChatAgent(_ userMessage: String, thinkStartTime: Date) async {
        chatLoadingPhase = .retrieving
        VectorSearchService.shared.beginInteractiveRequest(reason: "chat")
        defer {
            VectorSearchService.shared.endInteractiveRequest(reason: "chat")
        }

        let assistantId = UUID()
        var streamStarted = false
        var accumulatedStreamText = ""

        let turnInput = AgentTurnInput(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            anchorState: currentConversationAnchorState,
            allowLiveSearch: true
        )

        let turnResult = await chatAgent.respond(
            turn: turnInput,
            onSynthesisChunk: { [weak self] chunk in
                guard let self else { return }
                accumulatedStreamText += chunk
                if !streamStarted {
                    streamStarted = true
                    self.chatLoadingPhase = .generating
                    let placeholder = ConversationMessage(
                        id: assistantId,
                        isUser: false,
                        text: accumulatedStreamText,
                        timestamp: Date(),
                        intent: .general,
                        timeStarted: thinkStartTime
                    )
                    self.conversationHistory.append(placeholder)
                } else if let index = self.conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                    self.conversationHistory[index] = ConversationMessage(
                        id: assistantId,
                        isUser: false,
                        text: accumulatedStreamText,
                        timestamp: self.conversationHistory[index].timestamp,
                        intent: .general,
                        timeStarted: thinkStartTime
                    )
                    self.lastMessageContentVersion += 1
                }
            }
        )

        currentConversationAnchorState = turnResult.evidenceBundle.anchorState
        await applyAgentTurnResult(
            turnResult,
            thinkStartTime: thinkStartTime,
            existingMessageId: streamStarted ? assistantId : nil
        )
    }

    private func applyAgentTurnResult(
        _ turnResult: AgentTurnResult,
        thinkStartTime: Date,
        existingMessageId: UUID? = nil
    ) async {
        let citationProjection = projectedCitations(
            in: turnResult.responseText,
            from: turnResult.evidenceBundle
        )
        let relevantContent = citationProjection.relevantContent
        let relatedData = citationProjection.relatedData
        let displayResponseText = citationProjection.responseText
        let presentedEventDrafts = turnResult.presentation?.eventDraftCard ?? turnResult.actionDraft?.eventDrafts

        // If real streaming already appended the placeholder, just do the final update.
        if let assistantId = existingMessageId {
            if let index = conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                conversationHistory[index] = ConversationMessage(
                    id: assistantId,
                    isUser: false,
                    text: displayResponseText,
                    timestamp: conversationHistory[index].timestamp,
                    intent: .general,
                    relatedData: relatedData.isEmpty ? nil : relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date(),
                    locationInfo: turnResult.locationInfo,
                    eventCreationInfo: presentedEventDrafts,
                    relevantContent: relevantContent,
                    evidenceBundle: turnResult.evidenceBundle,
                    toolTrace: turnResult.toolTrace,
                    actionDraft: turnResult.actionDraft,
                    presentation: turnResult.presentation
                )
                lastMessageContentVersion += 1
            }
        } else if enableStreamingResponses {
            // Fallback fake-streaming (used when synthesis was skipped, e.g. draft responses).
            let assistantId = UUID()
            let baseMessage = ConversationMessage(
                id: assistantId,
                isUser: false,
                text: "",
                timestamp: Date(),
                intent: .general,
                timeStarted: thinkStartTime,
                locationInfo: turnResult.locationInfo,
                eventCreationInfo: presentedEventDrafts,
                relevantContent: relevantContent,
                evidenceBundle: turnResult.evidenceBundle,
                toolTrace: turnResult.toolTrace,
                actionDraft: turnResult.actionDraft,
                presentation: turnResult.presentation
            )
            conversationHistory.append(baseMessage)

            var renderedText = ""
            for chunk in streamingChunks(from: displayResponseText) {
                renderedText += chunk
                if let index = conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                    conversationHistory[index] = ConversationMessage(
                        id: assistantId,
                        isUser: false,
                        text: renderedText,
                        timestamp: conversationHistory[index].timestamp,
                        intent: .general,
                        timeStarted: thinkStartTime,
                        locationInfo: turnResult.locationInfo,
                        eventCreationInfo: presentedEventDrafts,
                        relevantContent: relevantContent,
                        evidenceBundle: turnResult.evidenceBundle,
                        toolTrace: turnResult.toolTrace,
                        actionDraft: turnResult.actionDraft,
                        presentation: turnResult.presentation
                    )
                    lastMessageContentVersion += 1
                }
                saveConversationLocally()
                try? await Task.sleep(nanoseconds: 12_000_000)
            }

            if let index = conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                conversationHistory[index] = ConversationMessage(
                    id: assistantId,
                    isUser: false,
                    text: displayResponseText,
                    timestamp: conversationHistory[index].timestamp,
                    intent: .general,
                    relatedData: relatedData.isEmpty ? nil : relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date(),
                    locationInfo: turnResult.locationInfo,
                    eventCreationInfo: presentedEventDrafts,
                    relevantContent: relevantContent,
                    evidenceBundle: turnResult.evidenceBundle,
                    toolTrace: turnResult.toolTrace,
                    actionDraft: turnResult.actionDraft,
                    presentation: turnResult.presentation
                )
                lastMessageContentVersion += 1
            }
        } else {
            let assistantMessage = ConversationMessage(
                isUser: false,
                text: displayResponseText,
                timestamp: Date(),
                intent: .general,
                relatedData: relatedData.isEmpty ? nil : relatedData,
                timeStarted: thinkStartTime,
                timeFinished: Date(),
                locationInfo: turnResult.locationInfo,
                eventCreationInfo: presentedEventDrafts,
                relevantContent: relevantContent,
                evidenceBundle: turnResult.evidenceBundle,
                toolTrace: turnResult.toolTrace,
                actionDraft: turnResult.actionDraft,
                presentation: turnResult.presentation
            )
            conversationHistory.append(assistantMessage)
        }

        isLoadingQuestionResponse = false
        chatLoadingPhase = .idle
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    private struct CitationProjection {
        let responseText: String
        let relevantContent: [RelevantContentInfo]?
        let relatedData: [RelatedDataItem]
    }

    func confirmActionDraft(
        for messageId: UUID,
        confirmedEvents: [EventCreationInfo]? = nil,
        folderName: String? = nil
    ) async {
        guard let index = conversationHistory.firstIndex(where: { $0.id == messageId }),
              let draft = conversationHistory[index].actionDraft else {
            return
        }

        switch draft.type {
        case .createEvent:
            let eventsToCreate = confirmedEvents ?? draft.eventDrafts ?? []
            guard !eventsToCreate.isEmpty else { return }
            await createEventsFromDraft(eventsToCreate)
            updateActionDraftStatus(for: messageId, status: .confirmed)
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: eventsToCreate.count == 1
                        ? "I created the event."
                        : "I created \(eventsToCreate.count) events.",
                    intent: .calendar
                )
            )
        case .createNote:
            guard let noteDraft = draft.noteDraft else { return }
            pendingNoteCreation = NoteCreationData(
                title: noteDraft.title,
                content: noteDraft.content,
                formattedContent: noteDraft.content,
                folderId: noteDraft.folderId,
                folderName: noteDraft.folderName
            )
            updateActionDraftStatus(for: messageId, status: .confirmed)
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: "I opened the note draft so you can make final edits before saving.",
                    intent: .notes
                )
            )
        case .latestEmail:
            return
        case .saveLocation:
            guard let placeDraft = draft.placeDraft else { return }
            let trimmedRequestedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDraftFolder = placeDraft.folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedFolder: String? = {
                if let trimmedRequestedFolder, !trimmedRequestedFolder.isEmpty { return trimmedRequestedFolder }
                if let trimmedDraftFolder, !trimmedDraftFolder.isEmpty { return trimmedDraftFolder }
                return nil
            }()
            guard let resolvedFolder else { return }

            if locationsManager.isPlaceSaved(googlePlaceId: placeDraft.place.id) {
                updateActionDraftStatus(for: messageId, status: .confirmed)
                conversationHistory.append(
                    ConversationMessage(
                        isUser: false,
                        text: "\(placeDraft.place.name) is already saved.",
                        intent: .locations
                    )
                )
                break
            }

            if !locationsManager.categories.contains(resolvedFolder) && !locationsManager.userFolders.contains(resolvedFolder) {
                locationsManager.addFolder(resolvedFolder)
            }

            let savedPlace: SavedPlace
            if !placeDraft.place.id.hasPrefix("mapkit:"),
               let details = try? await mapsService.getPlaceDetails(placeId: placeDraft.place.id) {
                savedPlace = {
                    var place = details.toSavedPlace(googlePlaceId: placeDraft.place.id)
                    place.category = resolvedFolder
                    return place
                }()
            } else {
                savedPlace = {
                    var place = SavedPlace(
                        googlePlaceId: placeDraft.place.id,
                        name: placeDraft.place.name,
                        address: placeDraft.place.address,
                        latitude: placeDraft.place.latitude,
                        longitude: placeDraft.place.longitude,
                        photos: placeDraft.place.photoURL.map { [$0] } ?? []
                    )
                    place.category = resolvedFolder
                    return place
                }()
            }

            locationsManager.addPlace(savedPlace)
            updateActionDraftStatus(
                for: messageId,
                status: .confirmed,
                folderName: resolvedFolder
            )
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: "Saved \(savedPlace.displayName) at \(savedPlace.address) to \(resolvedFolder).",
                    intent: .locations
                )
            )
        }

        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func cancelActionDraft(for messageId: UUID) {
        updateActionDraftStatus(for: messageId, status: .cancelled)
        conversationHistory.append(
            ConversationMessage(
                isUser: false,
                text: "Okay, I cancelled that draft.",
                intent: .general
            )
        )
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    private func updateActionDraftStatus(
        for messageId: UUID,
        status: AgentActionDraftStatus,
        folderName: String? = nil
    ) {
        guard let index = conversationHistory.firstIndex(where: { $0.id == messageId }),
              let draft = conversationHistory[index].actionDraft else {
            return
        }

        let updatedPlaceDraft: SavedPlaceDraftInfo?
        if let placeDraft = draft.placeDraft {
            updatedPlaceDraft = SavedPlaceDraftInfo(place: placeDraft.place, folderName: folderName ?? placeDraft.folderName)
        } else {
            updatedPlaceDraft = nil
        }

        conversationHistory[index].actionDraft = AgentActionDraft(
            id: draft.id,
            type: draft.type,
            status: status,
            requiresConfirmation: draft.requiresConfirmation,
            eventDrafts: draft.eventDrafts,
            noteDraft: draft.noteDraft,
            emailPreview: draft.emailPreview,
            placeDraft: updatedPlaceDraft
        )

        if let presentation = conversationHistory[index].presentation,
           let livePlaceCard = presentation.livePlaceCard,
           let updatedPlaceDraft {
            conversationHistory[index].presentation = AgentPresentation(
                eventDraftCard: presentation.eventDraftCard,
                noteDraftCard: presentation.noteDraftCard,
                emailPreviewCard: presentation.emailPreviewCard,
                livePlaceCard: LivePlacePreviewInfo(
                    results: livePlaceCard.results,
                    selectedPlaceId: updatedPlaceDraft.place.id,
                    prompt: livePlaceCard.prompt
                )
            )
        }

        lastMessageContentVersion += 1
    }

    private func createEventsFromDraft(_ events: [EventCreationInfo]) async {
        let taskManager = TaskManager.shared
        let calendar = Calendar.current

        for event in events {
            let weekday = weekdayFromNumber(calendar.component(.weekday, from: event.date))
            taskManager.addTask(
                title: event.title,
                to: weekday,
                description: event.notes,
                scheduledTime: event.hasTime ? event.date : nil,
                endTime: event.endDate,
                targetDate: event.date,
                reminderTime: reminderTime(for: event.reminderMinutes),
                location: event.location,
                isRecurring: event.recurrenceFrequency != nil,
                recurrenceFrequency: event.recurrenceFrequency,
                customRecurrenceDays: nil,
                tagId: tagId(forCategory: event.category) ?? event.tagId
            )
        }
    }

    private func reminderTime(for minutes: Int?) -> ReminderTime? {
        guard let minutes else { return nil }
        switch minutes {
        case ..<15:
            return .fifteenMinutes
        case ..<60:
            return .oneHour
        case ..<180:
            return .threeHours
        default:
            return .oneDay
        }
    }

    private func weekdayFromNumber(_ number: Int) -> WeekDay {
        switch number {
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

    private func tagId(forCategory category: String) -> String? {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.lowercased() != "personal" else { return nil }

        let tagManager = TagManager.shared
        if let existing = tagManager.tags.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return existing.id
        }

        return tagManager.createTag(name: normalized)?.id
    }

    private func citedEvidenceRecords(
        in responseText: String,
        from evidenceBundle: EvidenceBundle
    ) -> [EvidenceRecord] {
        let indices = citationIndices(
            in: responseText,
            maxIndex: evidenceBundle.records.count - 1
        )

        guard !indices.isEmpty else {
            return []
        }

        return indices.compactMap { index in
            guard evidenceBundle.records.indices.contains(index) else { return nil }
            return evidenceBundle.records[index]
        }
    }

    private func projectedCitations(
        in responseText: String,
        from evidenceBundle: EvidenceBundle
    ) -> CitationProjection {
        let indices = citationIndices(
            in: responseText,
            maxIndex: evidenceBundle.records.count - 1
        )

        guard !indices.isEmpty else {
            return CitationProjection(
                responseText: normalizedEvidenceCitationText(responseText),
                relevantContent: nil,
                relatedData: []
            )
        }

        var flattenedRelevantContent: [RelevantContentInfo] = []
        var seenContentKeys = Set<String>()
        var relatedDataItems: [RelatedDataItem] = []
        var localCitationIndexByEvidenceIndex: [Int: Int] = [:]

        for index in indices {
            guard evidenceBundle.records.indices.contains(index) else { continue }
            let record = evidenceBundle.records[index]

            if let related = relatedData(from: record) {
                relatedDataItems.append(related)
            }

            let items = relevantContentItems(from: record)
            // Deduplicate across ALL cited records, not just within a single record's relations.
            let dedupedItems = items.filter { seenContentKeys.insert(relevantContentDedupKey(for: $0)).inserted }
            guard !dedupedItems.isEmpty else { continue }
            localCitationIndexByEvidenceIndex[index] = flattenedRelevantContent.count
            flattenedRelevantContent.append(contentsOf: dedupedItems)
        }

        return CitationProjection(
            responseText: remappedCitationText(
                responseText,
                localCitationIndexByEvidenceIndex: localCitationIndexByEvidenceIndex,
                maxEvidenceIndex: evidenceBundle.records.count - 1
            ),
            relevantContent: flattenedRelevantContent.isEmpty ? nil : flattenedRelevantContent,
            relatedData: relatedDataItems
        )
    }

    private func citationIndices(in responseText: String, maxIndex: Int) -> [Int] {
        guard maxIndex >= 0 else { return [] }

        let normalized = normalizedEvidenceCitationText(responseText)
        let pattern = #"\[(\d+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, options: [], range: nsRange)
        var orderedIndices: [Int] = []
        var seen = Set<Int>()

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0,
                value <= maxIndex,
                seen.insert(value).inserted
            else {
                continue
            }
            orderedIndices.append(value)
        }

        return orderedIndices
    }

    private func remappedCitationText(
        _ responseText: String,
        localCitationIndexByEvidenceIndex: [Int: Int],
        maxEvidenceIndex: Int
    ) -> String {
        let normalized = normalizedEvidenceCitationText(responseText)
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else {
            return normalized
        }

        let mutable = NSMutableString(string: normalized)
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized))

        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0
            else {
                // Strip anything that doesn't parse as a valid non-negative integer
                mutable.replaceCharacters(in: match.range, with: "")
                continue
            }

            if value <= maxEvidenceIndex, let localIndex = localCitationIndexByEvidenceIndex[value] {
                mutable.replaceCharacters(in: match.range, with: "[\(localIndex)]")
            } else {
                // Out-of-range or unmapped citation — strip it rather than leaving literal [N]
                mutable.replaceCharacters(in: match.range, with: "")
            }
        }

        return (mutable as String)
            .components(separatedBy: "\n")
            .map { line in
                let leading = String(line.prefix { $0 == " " || $0 == "\t" })
                let remainder = String(line.dropFirst(leading.count))
                    .replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
                return leading + remainder
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedEvidenceCitationText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")

        let replacements: [(pattern: String, template: String)] = [
            (#"\[\s*(?:evidenceBundle\.)?records\.(\d+)\s*\]"#, "[$1]"),
            (#"\[\s*(?:evidenceBundle\.)?citations\.(\d+)\s*\]"#, "[$1]")
        ]
        for replacement in replacements {
            normalized = normalized.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }

        let stripPatterns = [
            #"\[\s*(?:evidenceBundle\.)?aggregates\.\d+\s*\]"#,
            #"\[\s*(?:evidenceBundle\.)?aggregate_rows\.\d+\s*\]"#
        ]
        for pattern in stripPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return normalized
    }

    private func relevantContent(from records: [EvidenceRecord]) -> [RelevantContentInfo]? {
        let mapped = records.flatMap { record in
            relevantContentItems(from: record)
        }
        return mapped.isEmpty ? nil : mapped
    }

    private func relatedData(from records: [EvidenceRecord]) -> [RelatedDataItem] {
        let mapped = records.compactMap { record in
            relatedData(from: record)
        }
        return Array(mapped.prefix(6))
    }

    private func relevantContentItems(from record: EvidenceRecord) -> [RelevantContentInfo] {
        if record.ref.type == .daySummary {
            return daySummaryRelevantContent(from: record)
        }

        if let item = relevantContent(from: record) {
            return [item]
        }

        return []
    }

    private func relevantContent(from record: EvidenceRecord) -> RelevantContentInfo? {
        switch record.ref.type {
        case .email:
            return RelevantContentInfo.email(
                id: record.ref.id,
                subject: record.title,
                sender: record.attributes["sender"] ?? "Email",
                snippet: record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value) ?? Date()
            )
        case .note:
            guard let noteId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.note(
                id: noteId,
                title: record.title,
                snippet: record.summary,
                folder: record.attributes["folder"] ?? "Notes"
            )
        case .receipt:
            guard let receiptId = UUID(uuidString: record.ref.id) else { return nil }
            let amount = record.attributes["amount"].flatMap { CurrencyParser.extractAmount(from: $0) }
            return RelevantContentInfo.receipt(
                id: receiptId,
                title: record.title,
                amount: amount,
                date: parseEvidenceDate(record.timestamps.first?.value),
                category: record.attributes["category"]
            )
        case .event:
            guard let eventId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.event(
                id: eventId,
                title: record.title,
                date: parseEvidenceDate(record.timestamps.first?.value) ?? Date(),
                category: record.attributes["calendar"] ?? "Personal"
            )
        case .location, .nearbyPlace:
            guard let locationId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.location(
                id: locationId,
                name: record.title,
                address: record.attributes["address"] ?? record.summary,
                category: record.attributes["category"] ?? "Place"
            )
        case .visit:
            guard let visitId = UUID(uuidString: record.ref.id) else { return nil }
            let placeRelation = record.relations.first(where: { $0.type == "place" })
            let placeId = placeRelation.flatMap { UUID(uuidString: $0.target.id) }
            return RelevantContentInfo.visit(
                id: visitId,
                placeId: placeId,
                placeName: placeRelation?.target.title ?? record.title,
                address: record.attributes["address"] ?? record.summary,
                entryTime: parseEvidenceDate(record.timestamps.first(where: { $0.label == "entry" })?.value),
                exitTime: parseEvidenceDate(record.timestamps.first(where: { $0.label == "exit" })?.value),
                durationMinutes: Int(record.attributes["duration_minutes"] ?? "")
            )
        case .person:
            guard let personId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.person(
                id: personId,
                name: record.title,
                relationship: record.attributes["relationship"]
            )
        case .daySummary, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func daySummaryRelevantContent(from record: EvidenceRecord) -> [RelevantContentInfo] {
        var items: [RelevantContentInfo] = []
        var seen = Set<String>()

        for relation in record.relations {
            guard let item = relevantContent(from: relation) else { continue }
            let key = relevantContentDedupKey(for: item)
            guard seen.insert(key).inserted else { continue }
            items.append(item)
        }

        return Array(items.prefix(8))
    }

    private func relevantContent(from relation: EvidenceRelation) -> RelevantContentInfo? {
        switch relation.target.type {
        case .email:
            return RelevantContentInfo.email(
                id: relation.target.id,
                subject: relation.target.title ?? relation.label ?? "Email",
                sender: relation.label ?? "Email",
                snippet: relation.label ?? "",
                date: Date()
            )
        case .note:
            guard let noteId = UUID(uuidString: relation.target.id) else { return nil }
            let folderName: String
            switch relation.type {
            case "journal":
                folderName = "Journal"
            case "weekly_recap":
                folderName = "Journal Weekly Summary"
            default:
                folderName = relation.label ?? "Notes"
            }
            return RelevantContentInfo.note(
                id: noteId,
                title: relation.target.title ?? relation.label ?? "Note",
                snippet: relation.label ?? "",
                folder: folderName
            )
        case .receipt:
            guard let receiptId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.receipt(
                id: receiptId,
                title: relation.target.title ?? relation.label ?? "Receipt",
                amount: nil,
                date: nil,
                category: relation.label
            )
        case .event:
            guard let eventId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.event(
                id: eventId,
                title: relation.target.title ?? relation.label ?? "Event",
                date: Date(),
                category: relation.label ?? "Calendar"
            )
        case .location:
            guard let locationId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.location(
                id: locationId,
                name: relation.target.title ?? relation.label ?? "Place",
                address: relation.label ?? "",
                category: "Place"
            )
        case .visit:
            guard let visitId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.visit(
                id: visitId,
                placeId: nil,
                placeName: relation.target.title ?? relation.label ?? "Visit",
                address: nil,
                entryTime: nil,
                exitTime: nil,
                durationMinutes: nil
            )
        case .person:
            guard let personId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.person(
                id: personId,
                name: relation.target.title ?? relation.label ?? "Person",
                relationship: relation.label
            )
        case .daySummary, .nearbyPlace, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func relevantContentDedupKey(for item: RelevantContentInfo) -> String {
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

    private func relatedData(from record: EvidenceRecord) -> RelatedDataItem? {
        switch record.ref.type {
        case .email:
            return RelatedDataItem(
                type: .email,
                title: record.title,
                subtitle: record.attributes["sender"] ?? record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value)
            )
        case .note:
            return RelatedDataItem(
                type: .note,
                title: record.title,
                subtitle: record.summary.isEmpty ? record.attributes["folder"] : record.summary
            )
        case .receipt:
            return RelatedDataItem(
                type: .receipt,
                title: record.title,
                subtitle: record.attributes["category"],
                date: parseEvidenceDate(record.timestamps.first?.value),
                amount: record.attributes["amount"].flatMap { CurrencyParser.extractAmount(from: $0) },
                merchant: record.title
            )
        case .event:
            return RelatedDataItem(
                type: .event,
                title: record.title,
                subtitle: record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value)
            )
        case .location:
            return RelatedDataItem(
                type: .location,
                title: record.title,
                subtitle: record.attributes["address"] ?? record.summary
            )
        case .visit, .person, .daySummary, .nearbyPlace, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func parseEvidenceDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        return iso.date(from: raw)
    }

    private func streamingChunks(from text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > 18 else {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk: [Substring] = []
        for word in words {
            currentChunk.append(word)
            if currentChunk.count >= 12 {
                chunks.append(currentChunk.joined(separator: " ") + " ")
                currentChunk.removeAll(keepingCapacity: true)
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        return chunks
    }
    
    /// Generate a proactive morning briefing
    func generateMorningBriefing() async {
        guard conversationHistory.isEmpty else { return }

        isInConversationMode = true
        isLoadingQuestionResponse = true
        chatLoadingPhase = .retrieving

        let turnResult = await chatAgent.respond(
            turn: AgentTurnInput(
                userMessage: """
                Give me a concise morning briefing for today using only my Seline data. Cover today's schedule, important follow-ups, spending or receipts that matter, recent visits or routines, and anything time-sensitive. If a category has no evidence, skip it instead of guessing.
                """,
                conversationHistory: conversationHistory,
                anchorState: currentConversationAnchorState,
                allowLiveSearch: false
            )
        )
        currentConversationAnchorState = turnResult.evidenceBundle.anchorState
        await applyAgentTurnResult(turnResult, thinkStartTime: Date())
    }

    private func persistCurrentConversationIfNeeded() {
        guard !conversationHistory.isEmpty else { return }
        _ = upsertCurrentConversationInHistory()

        if conversationKind == .tracker, let currentTrackerThread {
            Task {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
        }
    }

    /// Generate quick reply suggestions for follow-up questions
    /// Clear conversation state completely (called when user dismisses conversation modal)
    func clearConversation() {
        persistCurrentConversationIfNeeded()

        conversationHistory = []
        isInConversationMode = false
        isLoadingQuestionResponse = false
        questionResponse = nil
        conversationTitle = "New Conversation"
        conversationKind = .standard
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        currentlyLoadedConversationId = nil
        lastGeneratedTitleMessageCount = 0
        isNewConversation = false
        currentConversationAnchorState = nil
    }

    /// Start a new blank conversation (user will type first message)
    func startNewConversation(kind: ConversationKind = .standard) {
        clearConversation()
        currentlyLoadedConversationId = nil  // Ensure we're not treating this as an existing conversation
        isInConversationMode = true
        isNewConversation = true  // Mark as new conversation (will hide title until finalized)
        conversationKind = kind
        if kind == .tracker {
            conversationTitle = "New Tracker"
        } else {
            updateConversationTitle()
        }
    }

    func startNewTrackerConversation() {
        startNewConversation(kind: .tracker)
    }

    /// Stop/cancel the currently streaming response
    func stopCurrentRequest() {
        isLoadingQuestionResponse = false
        chatLoadingPhase = .idle
    }

    /// Regenerate response for a given assistant message
    /// Finds the previous user message and re-sends it to get a new response
    func regenerateResponse(for assistantMessageId: UUID) async {
        guard !ChatUsageTracker.shared.isLimitReached else {
            print("🚫 Daily chat limit reached; regeneration blocked")
            return
        }

        if conversationKind == .tracker {
            print("ℹ️ Tracker responses are deterministic; regeneration is not supported.")
            return
        }

        // Find the assistant message in history
        guard let assistantIndex = conversationHistory.firstIndex(where: { $0.id == assistantMessageId && !$0.isUser }) else {
            print("❌ Could not find assistant message to regenerate")
            return
        }

        // Find the previous user message (should be right before the assistant message)
        guard assistantIndex > 0 else {
            print("❌ No previous user message found")
            return
        }

        let userMessageIndex = assistantIndex - 1
        guard conversationHistory[userMessageIndex].isUser else {
            print("❌ Previous message is not a user message")
            return
        }

        let userMessage = conversationHistory[userMessageIndex].text

        // Remove the assistant message from conversation history
        conversationHistory.remove(at: assistantIndex)

        // Save the updated conversation (without the old assistant message)
        saveConversationLocally()

        // Regenerate response without adding duplicate user message
        // The user message is already in the history at userMessageIndex, so we just regenerate the assistant response
        isLoadingQuestionResponse = true
        let thinkStartTime = Date()
        
        await addConversationMessageWithChatAgent(userMessage, thinkStartTime: thinkStartTime)
    }

    /// Start a conversation with an initial question
    func startConversation(with initialQuestion: String) async {
        guard !ChatUsageTracker.shared.isLimitReached else {
            print("🚫 Daily chat limit reached; startConversation blocked")
            return
        }

        startNewConversation(kind: .standard)
        await addConversationMessage(initialQuestion)
    }

    // MARK: - Conversational Action System

    /// Start a new conversational action from a user's initial message
    func startConversationalAction(
        userMessage: String,
        actionType: ActionType
    ) async {
        // DISABLED: Action creation from chat is disabled
        // This function no longer does anything
        print("⚠️ Action creation disabled - cannot start conversational action")
        return
    }

    /// Process a user's response to an action prompt
    func continueConversationalAction(userMessage: String) async {
        // DISABLED: Action continuation disabled
        print("⚠️ Action creation disabled - action continuation skipped")
        return
    }

    /// Execute the built action (save to database)
    private func executeConversationalAction(_ action: InteractiveAction) async {
        switch action.type {
        case .createEvent:
            if let eventData = conversationActionHandler.compileEventData(from: action) {
                pendingEventCreation = eventData
                confirmEventCreation()
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Event '\(eventData.title)' created!",
                    intent: .calendar
                )
                conversationHistory.append(msg)
            }

        case .updateEvent:
            if let eventData = conversationActionHandler.compileEventData(from: action) {
                pendingEventCreation = eventData
                confirmEventCreation()
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Event updated!",
                    intent: .calendar
                )
                conversationHistory.append(msg)
            }

        case .deleteEvent:
            if conversationActionHandler.compileDeletionData(from: action) != nil {
                // Handle deletion
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Event deleted!",
                    intent: .calendar
                )
                conversationHistory.append(msg)
            }

        case .createNote:
            if let noteData = conversationActionHandler.compileNoteData(from: action) {
                pendingNoteCreation = noteData
                confirmNoteCreation()
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note '\(noteData.title)' created!",
                    intent: .notes
                )
                conversationHistory.append(msg)
            }

        case .updateNote:
            if let updateData = conversationActionHandler.compileNoteUpdateData(from: action) {
                pendingNoteUpdate = updateData
                confirmNoteUpdate()
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note updated!",
                    intent: .notes
                )
                conversationHistory.append(msg)
            }

        case .deleteNote:
            if conversationActionHandler.compileDeletionData(from: action) != nil {
                // Handle deletion
                let msg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note deleted!",
                    intent: .notes
                )
                conversationHistory.append(msg)
            }
        }

        // Clear current action
        currentInteractiveAction = nil
        actionPrompt = nil
        isWaitingForActionResponse = false
    }

    /// Update conversation title based on conversation context
    /// Updates as conversation progresses to better reflect the topic
    /// NOTE: Currently set to blank - titles are not helpful
    private func updateConversationTitle() {
        if conversationKind == .tracker {
            conversationTitle = currentTrackerThread?.title ?? "New Tracker"
            return
        }
        // Keep title blank - user finds truncated titles unhelpful
        conversationTitle = ""
    }

    /// Generate a conversation title based on the full conversation summary
    /// Called when user exits the conversation
    func generateFinalConversationTitle() async {
        guard !conversationHistory.isEmpty else { return }

        if conversationKind == .tracker {
            conversationTitle = currentTrackerThread?.title ?? conversationTitle
            _ = upsertCurrentConversationInHistory()
            if let currentTrackerThread {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
            return
        }

        let currentMessageCount = conversationHistory.count
        let shouldRegenerateTitle =
            isWeakConversationTitle(conversationTitle) ||
            currentMessageCount >= (lastGeneratedTitleMessageCount + 6)

        if shouldRegenerateTitle {
            if let generatedTitle = await generateConversationTitleWithGemini(from: conversationHistory) {
                conversationTitle = generatedTitle
            } else {
                conversationTitle = provisionalConversationTitle(from: conversationHistory)
            }
            lastGeneratedTitleMessageCount = currentMessageCount
        }

        _ = upsertCurrentConversationInHistory()
    }

    private func generateConversationTitleWithGemini(from messages: [ConversationMessage]) async -> String? {
        guard !messages.isEmpty else { return nil }

        let compactTranscript = messages
            .prefix(10)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                let compact = message.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(role): \(compact)"
            }
            .joined(separator: "\n")

        let prompt = """
        Create ONE specific chat title from this transcript.

        Rules:
        - 4 to 8 words
        - Concrete and descriptive
        - Include key topic/timeframe when relevant
        - DO NOT start with generic phrasing like "Tell me", "What did I do", "Can you"
        - No quotes, no markdown, no trailing punctuation

        Transcript:
        \(compactTranscript)

        Title:
        """

        do {
            let rawTitle = try await GeminiService.shared.generateText(
                systemPrompt: "You create concise, specific conversation titles.",
                userPrompt: prompt,
                maxTokens: 24,
                temperature: 0.25,
                operationType: "conversation_title"
            )
            let cleaned = sanitizeConversationTitle(rawTitle)
            guard !cleaned.isEmpty, cleaned.count <= 80, !isWeakConversationTitle(cleaned) else { return nil }
            return cleaned
        } catch {
            return nil
        }
    }

    private func provisionalConversationTitle(from messages: [ConversationMessage]) -> String {
        if conversationKind == .tracker {
            return currentTrackerThread?.title ?? "Tracker"
        }
        if let firstUserMessage = messages.first(where: { $0.isUser }) {
            let compact = firstUserMessage.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if compact.isEmpty { return "New chat" }
            return compact.count > 80 ? String(compact.prefix(79)) + "…" : compact
        }
        return "New chat"
    }

    private func sanitizeConversationTitle(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "Title:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".!?-–— "))
        return cleaned
    }

    private func isWeakConversationTitle(_ title: String) -> Bool {
        if conversationKind == .tracker {
            return title.isEmpty || title == "New Tracker" || title == "Tracker"
        }
        let lower = title.lowercased()
        if title.isEmpty || title == "New Conversation" || title == "New chat" { return true }
        if lower.hasPrefix("tell me") || lower.hasPrefix("what did i do") || lower.hasPrefix("can you") { return true }
        if lower.hasPrefix("chat on ") { return true }
        return false
    }

    @discardableResult
    private func upsertCurrentConversationInHistory() -> UUID {
        let finalTitle = isWeakConversationTitle(conversationTitle)
            ? provisionalConversationTitle(from: conversationHistory)
            : conversationTitle
        let subtitle = currentConversationSubtitle()
        let updatedAt = Date()

        if let loadedId = currentlyLoadedConversationId,
           let index = savedConversations.firstIndex(where: { $0.id == loadedId }) {
            savedConversations[index] = SavedConversation(
                id: loadedId,
                title: finalTitle,
                kind: conversationKind,
                trackerThreadId: currentTrackerThread?.id,
                subtitle: subtitle,
                messages: conversationHistory,
                createdAt: savedConversations[index].createdAt,
                updatedAt: updatedAt
            )
            persistLastActiveConversationId(loadedId)
            saveConversationHistoryLocally()
            return loadedId
        }

        if let firstMessageId = conversationHistory.first?.id,
           let existingIndex = savedConversations.firstIndex(where: { $0.messages.first?.id == firstMessageId }) {
            let existingId = savedConversations[existingIndex].id
            savedConversations[existingIndex] = SavedConversation(
                id: existingId,
                title: finalTitle,
                kind: conversationKind,
                trackerThreadId: currentTrackerThread?.id,
                subtitle: subtitle,
                messages: conversationHistory,
                createdAt: savedConversations[existingIndex].createdAt,
                updatedAt: updatedAt
            )
            currentlyLoadedConversationId = existingId
            persistLastActiveConversationId(existingId)
            saveConversationHistoryLocally()
            return existingId
        }

        let newId = UUID()
        let saved = SavedConversation(
            id: newId,
            title: finalTitle,
            kind: conversationKind,
            trackerThreadId: currentTrackerThread?.id,
            subtitle: subtitle,
            messages: conversationHistory,
            createdAt: Date(),
            updatedAt: updatedAt
        )
        savedConversations.insert(saved, at: 0)
        currentlyLoadedConversationId = newId
        persistLastActiveConversationId(newId)
        saveConversationHistoryLocally()
        return newId
    }

    /// Save conversation to local storage
    private func saveConversationLocally() {
        let defaults = UserDefaults.standard
        do {
            // Keep local cache bounded so UserDefaults never approaches the 4MB platform limit.
            var snapshot = Array(conversationHistory.suffix(120))
            var encoded = try JSONEncoder().encode(snapshot)

            if encoded.count > 1_000_000 {
                snapshot = Array(conversationHistory.suffix(40))
                encoded = try JSONEncoder().encode(snapshot)
            }

            defaults.set(encoded, forKey: Self.lastConversationStorageKey)
        } catch {
            print("❌ Error saving conversation locally: \(error)")
        }
    }

    /// Load last conversation from local storage
    func loadLastConversation() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.lastConversationStorageKey) else { return }

        do {
            conversationHistory = try JSONDecoder().decode([ConversationMessage].self, from: data)
            guard !conversationHistory.isEmpty else { return }
            conversationTitle = provisionalConversationTitle(from: conversationHistory)
            conversationKind = .standard
            currentTrackerThread = nil
            pendingTrackerDraft = nil
            isInConversationMode = true
            isNewConversation = false
            currentlyLoadedConversationId = nil
            lastGeneratedTitleMessageCount = conversationHistory.count
            currentConversationAnchorState = conversationHistory.last(where: { !$0.isUser })?.evidenceBundle?.anchorState
        } catch {
            print("❌ Error loading conversation: \(error)")
        }
    }

    func restoreMostRecentConversationIfNeeded() {
        if !conversationHistory.isEmpty {
            isInConversationMode = true
            return
        }

        loadConversationHistoryLocally()

        if let loadedId = currentlyLoadedConversationId,
           savedConversations.contains(where: { $0.id == loadedId }) {
            loadConversation(withId: loadedId)
            return
        }

        if let lastActiveId = persistedLastActiveConversationId(),
           savedConversations.contains(where: { $0.id == lastActiveId }) {
            loadConversation(withId: lastActiveId)
            return
        }

        if let mostRecentConversation = savedConversations.first {
            loadConversation(withId: mostRecentConversation.id)
            return
        }

        loadLastConversation()
    }

    /// Save conversation to Supabase
    func saveConversationToSupabase() async {
        guard !conversationHistory.isEmpty else { return }

        if conversationKind == .tracker, let currentTrackerThread {
            await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            return
        }

        let conversationID = upsertCurrentConversationInHistory()
        guard let localConversation = savedConversations.first(where: { $0.id == conversationID }) else {
            return
        }

        let titleToSave = isWeakConversationTitle(conversationTitle)
            ? provisionalConversationTitle(from: conversationHistory)
            : conversationTitle

        do {
            let supabaseManager = SupabaseManager.shared
            let client = await supabaseManager.getPostgrestClient()

            // Get current user ID
            guard let session = try? await supabaseManager.authClient.session else {
                print("❌ No authenticated user to save conversation")
                return
            }
            let userId = session.user.id

            // Prepare conversation data
            var historyJson = "[]"
            if let encoded = try? JSONEncoder().encode(conversationHistory),
               let jsonString = String(data: encoded, encoding: .utf8) {
                historyJson = jsonString
            }

            struct ConversationData: Encodable {
                let id: UUID
                let user_id: UUID
                let title: String
                let messages: String
                let message_count: Int
                let first_message: String
                let created_at: String
            }

            let data = ConversationData(
                id: conversationID,
                user_id: userId,
                title: titleToSave,
                messages: historyJson,
                message_count: conversationHistory.count,
                first_message: conversationHistory.first?.text ?? "",
                created_at: ISO8601DateFormatter().string(from: localConversation.updatedAt)
            )

            try await client
                .from("conversations")
                .upsert(data, onConflict: "id")
                .execute()
        } catch {
            print("❌ Error saving conversation to Supabase: \(error)")
        }
    }

    /// Load standard conversations from Supabase and merge them into local history.
    @discardableResult
    func loadConversationsFromSupabase() async -> [SavedConversation] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("conversations")
                .select("id,title,messages,created_at")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()

            let records = try JSONDecoder.supabaseDecoder().decode([RemoteConversationRecord].self, from: response.data)
            let remoteConversations = deduplicatedRemoteStandardConversations(from: records)
            mergeRemoteStandardConversations(remoteConversations)
            return remoteConversations
        } catch {
            print("❌ Error loading conversations from Supabase: \(error)")
            return []
        }
    }

    /// Load specific conversation from Supabase by ID
    func loadConversationFromSupabase(id: String) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("conversations")
                .select("id,title,messages,created_at")
                .eq("user_id", value: userId.uuidString)
                .eq("id", value: id)
                .limit(1)
                .execute()

            let records = try JSONDecoder.supabaseDecoder().decode([RemoteConversationRecord].self, from: response.data)
            guard let remoteConversation = deduplicatedRemoteStandardConversations(from: records).first else { return }

            mergeRemoteStandardConversations([remoteConversation])
            if let resolvedConversation = savedConversations.first(where: { conversation in
                conversation.kind == .standard && remoteConversation.messages.first?.id == conversation.messages.first?.id
            }) ?? savedConversations.first(where: { $0.id == remoteConversation.id }) {
                loadConversation(withId: resolvedConversation.id)
            }
        } catch {
            print("❌ Error loading conversation \(id) from Supabase: \(error)")
        }
    }

    /// Save current conversation to history
    func saveConversationToHistory() {
        guard !conversationHistory.isEmpty else { return }
        _ = upsertCurrentConversationInHistory()
    }

    /// Load all saved conversations from local storage
    func loadConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "conversationHistory") else { return }

        do {
            savedConversations = try JSONDecoder().decode([SavedConversation].self, from: data)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("❌ Error loading conversation history: \(error)")
        }
    }

    /// Save all conversations to local storage
    private func saveConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        do {
            let compact = Array(savedConversations.prefix(30)).map { conversation in
                SavedConversation(
                    id: conversation.id,
                    title: conversation.title,
                    kind: conversation.kind,
                    trackerThreadId: conversation.trackerThreadId,
                    subtitle: conversation.subtitle,
                    messages: Array(conversation.messages.suffix(80)),
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt
                )
            }
            let encoded = try JSONEncoder().encode(compact)
            defaults.set(encoded, forKey: "conversationHistory")
        } catch {
            print("❌ Error saving conversation history: \(error)")
        }
    }

    private func currentConversationSubtitle() -> String? {
        if conversationKind == .tracker {
            return currentTrackerThread?.subtitle ?? currentTrackerThread?.cachedState?.summaryLine
        }
        return nil
    }

    private func persistedLastActiveConversationId() -> UUID? {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.lastActiveConversationIdStorageKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func persistLastActiveConversationId(_ id: UUID?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id.uuidString, forKey: Self.lastActiveConversationIdStorageKey)
        } else {
            defaults.removeObject(forKey: Self.lastActiveConversationIdStorageKey)
        }
    }

    private func deduplicatedRemoteStandardConversations(from records: [RemoteConversationRecord]) -> [SavedConversation] {
        var bestConversationsByKey: [String: SavedConversation] = [:]

        for record in records {
            guard let conversation = remoteStandardConversation(from: record) else { continue }
            let dedupeKey = conversation.messages.first?.id.uuidString ?? record.id.uuidString

            if let existing = bestConversationsByKey[dedupeKey] {
                let shouldReplace =
                    conversation.messages.count > existing.messages.count
                    || (conversation.messages.count == existing.messages.count && conversation.updatedAt > existing.updatedAt)
                if shouldReplace {
                    bestConversationsByKey[dedupeKey] = conversation
                }
            } else {
                bestConversationsByKey[dedupeKey] = conversation
            }
        }

        return bestConversationsByKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func remoteStandardConversation(from record: RemoteConversationRecord) -> SavedConversation? {
        let messagesData = record.messages.data(using: .utf8) ?? Data("[]".utf8)
        let decoder = JSONDecoder()
        // Decode each message individually so one malformed message doesn't silently
        // wipe the entire conversation and produce a blank history page.
        let messages: [ConversationMessage]
        if let all = try? decoder.decode([ConversationMessage].self, from: messagesData) {
            messages = all
        } else if let raws = try? decoder.decode([AnySafeDecodable<ConversationMessage>].self, from: messagesData) {
            messages = raws.compactMap(\.value)
        } else {
            messages = []
        }
        let title = sanitizedStandardConversationTitle(record.title, messages: messages)

        return SavedConversation(
            id: record.id,
            title: title,
            kind: .standard,
            messages: messages,
            createdAt: record.created_at,
            updatedAt: record.created_at
        )
    }

    private func mergeRemoteStandardConversations(_ remoteConversations: [SavedConversation]) {
        guard !remoteConversations.isEmpty else { return }

        for remoteConversation in remoteConversations {
            if let index = savedConversations.firstIndex(where: { $0.kind == .standard && $0.id == remoteConversation.id }) {
                savedConversations[index] = mergedStandardConversation(local: savedConversations[index], remote: remoteConversation)
                continue
            }

            if let firstMessageID = remoteConversation.messages.first?.id,
               let index = savedConversations.firstIndex(where: {
                   $0.kind == .standard && $0.messages.first?.id == firstMessageID
               }) {
                savedConversations[index] = mergedStandardConversation(local: savedConversations[index], remote: remoteConversation)
                continue
            }

            savedConversations.append(remoteConversation)
        }

        savedConversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversationHistoryLocally()
    }

    private func mergedStandardConversation(local: SavedConversation, remote: SavedConversation) -> SavedConversation {
        let remoteIsNewer = remote.updatedAt > local.updatedAt
        let preferredMessages: [ConversationMessage]

        if remote.messages.count > local.messages.count {
            preferredMessages = remote.messages
        } else if remote.messages.count < local.messages.count {
            preferredMessages = local.messages
        } else {
            preferredMessages = remoteIsNewer ? remote.messages : local.messages
        }

        let title = remoteIsNewer
            ? preferredStandardConversationTitle(local: local.title, remote: remote.title, messages: preferredMessages)
            : preferredStandardConversationTitle(local: remote.title, remote: local.title, messages: preferredMessages)

        return SavedConversation(
            id: local.id,
            title: title,
            kind: .standard,
            messages: preferredMessages,
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func preferredStandardConversationTitle(local: String, remote: String, messages: [ConversationMessage]) -> String {
        let localTitle = sanitizedStandardConversationTitle(local, messages: messages)
        let remoteTitle = sanitizedStandardConversationTitle(remote, messages: messages)
        let localIsWeak = isWeakStandardConversationTitle(localTitle)
        let remoteIsWeak = isWeakStandardConversationTitle(remoteTitle)

        switch (localIsWeak, remoteIsWeak) {
        case (true, false):
            return remoteTitle
        case (false, true):
            return localTitle
        default:
            return localTitle
        }
    }

    private func sanitizedStandardConversationTitle(_ rawTitle: String, messages: [ConversationMessage]) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !isWeakStandardConversationTitle(trimmed) {
            return trimmed
        }

        if let firstUserMessage = messages.first(where: { $0.isUser })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUserMessage.isEmpty {
            return firstUserMessage.count > 80 ? String(firstUserMessage.prefix(79)) + "…" : firstUserMessage
        }

        return trimmed.isEmpty ? "New chat" : trimmed
    }

    private func isWeakStandardConversationTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        if title.isEmpty || title == "New Conversation" || title == "New chat" { return true }
        if lower.hasPrefix("tell me") || lower.hasPrefix("what did i do") || lower.hasPrefix("can you") { return true }
        if lower.hasPrefix("chat on ") { return true }
        return false
    }

    private func updateTrackerSubtitle(from state: TrackerDerivedState) {
        guard conversationKind == .tracker else { return }
        if var thread = currentTrackerThread {
            thread.cachedState = state
            thread.subtitle = state.summaryLine
            currentTrackerThread = thread
            trackerStore.upsertThread(thread)
        }
    }

    private func isTrackerConfirmationMessage(_ lower: String) -> Bool {
        ["confirm", "yes", "looks good", "save it", "apply it"].contains(lower)
    }

    private func isTrackerCancellationMessage(_ lower: String) -> Bool {
        ["cancel", "never mind", "stop", "discard"].contains(lower)
    }

    func draftUndoLastTrackerChange() async {
        guard conversationKind == .tracker, let currentTrackerThread else { return }

        if pendingTrackerDraft != nil {
            appendTrackerAssistantMessage(
                "Confirm or cancel the current tracker draft before undoing another change."
            )
            saveConversationLocally()
            _ = upsertCurrentConversationInHistory()
            return
        }

        let userMessage = ConversationMessage(
            isUser: true,
            text: "Undo the last change.",
            intent: .general,
            trackerThreadId: currentTrackerThread.id
        )
        conversationHistory.append(userMessage)

        isLoadingQuestionResponse = true
        chatLoadingPhase = .generating

        let outcome = await trackerParserService.draftUndoLastChange(
            in: currentTrackerThread,
            conversationHistory: conversationHistory
        )

        pendingTrackerDraft = outcome.draft

        if outcome.shouldPersistAssistantMessage {
            appendTrackerAssistantMessage(
                outcome.responseText,
                draft: outcome.draft,
                stateSnapshot: outcome.derivedState
            )
        }

        if outcome.commitsProjectedStateToThread,
           let projectedState = outcome.derivedState {
            updateTrackerSubtitle(from: projectedState)
        }

        isLoadingQuestionResponse = false
        chatLoadingPhase = .idle
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func applyPendingTrackerDraft() {
        guard let pendingTrackerDraft else { return }

        let applyResult = trackerParserService.applyDraft(pendingTrackerDraft, to: currentTrackerThread)
        self.pendingTrackerDraft = nil

        if let thread = applyResult.thread {
            conversationKind = .tracker
            conversationTitle = thread.title
            currentTrackerThread = thread
            trackerStore.upsertThread(thread)
            conversationHistory = conversationHistory.map { message in
                ConversationMessage(
                    id: message.id,
                    isUser: message.isUser,
                    text: message.text,
                    timestamp: message.timestamp,
                    intent: message.intent,
                    relatedData: message.relatedData,
                    timeStarted: message.timeStarted,
                    timeFinished: message.timeFinished,
                    followUpSuggestions: message.followUpSuggestions,
                    locationInfo: message.locationInfo,
                    eventCreationInfo: message.eventCreationInfo,
                    relevantContent: message.relevantContent,
                    proactiveQuestion: message.proactiveQuestion,
                    trackerThreadId: thread.id,
                    trackerOperationDraft: message.trackerOperationDraft,
                    trackerStateSnapshot: message.trackerStateSnapshot,
                    evidenceBundle: message.evidenceBundle,
                    toolTrace: message.toolTrace,
                    actionDraft: message.actionDraft,
                    presentation: message.presentation
                )
            }
        }

        let assistantMessage = ConversationMessage(
            isUser: false,
            text: applyResult.message,
            intent: .general,
            trackerThreadId: currentTrackerThread?.id,
            trackerStateSnapshot: currentTrackerThread?.cachedState
        )
        conversationHistory.append(assistantMessage)
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()

        if let currentTrackerThread {
            Task {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
        }
    }

    func cancelPendingTrackerDraft() {
        guard pendingTrackerDraft != nil else { return }
        pendingTrackerDraft = nil
        let assistantMessage = ConversationMessage(
            isUser: false,
            text: "Tracker draft cancelled.",
            intent: .general,
            trackerThreadId: currentTrackerThread?.id,
            trackerStateSnapshot: currentTrackerThread?.cachedState
        )
        conversationHistory.append(assistantMessage)
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    private func appendTrackerAssistantMessage(
        _ text: String,
        draft: TrackerOperationDraft? = nil,
        stateSnapshot: TrackerDerivedState? = nil
    ) {
        let assistantMessage = ConversationMessage(
            isUser: false,
            text: text,
            intent: .general,
            trackerThreadId: currentTrackerThread?.id,
            trackerOperationDraft: draft,
            trackerStateSnapshot: stateSnapshot ?? currentTrackerThread?.cachedState
        )
        conversationHistory.append(assistantMessage)
    }

    func refreshTrackerThreadsFromSupabase() async {
        let bundles = await trackerStore.refreshFromSupabase()
        guard !bundles.isEmpty else { return }

        for bundle in bundles {
            let existingIndex = savedConversations.firstIndex(where: { $0.trackerThreadId == bundle.thread.id })
            let resolvedMessages: [ConversationMessage]
            if !bundle.messages.isEmpty {
                resolvedMessages = bundle.messages
            } else {
                resolvedMessages = existingIndex.flatMap { savedConversations[$0].messages } ?? []
            }

            let saved = SavedConversation(
                id: existingIndex.map { savedConversations[$0].id } ?? UUID(),
                title: bundle.thread.title,
                kind: .tracker,
                trackerThreadId: bundle.thread.id,
                subtitle: bundle.thread.cachedState?.summaryLine ?? bundle.thread.subtitle,
                messages: resolvedMessages,
                createdAt: existingIndex.map { savedConversations[$0].createdAt } ?? bundle.thread.createdAt,
                updatedAt: bundle.thread.updatedAt
            )

            let shouldApplyRemote: Bool
            if let existingIndex {
                if saved.updatedAt >= savedConversations[existingIndex].updatedAt {
                    savedConversations[existingIndex] = saved
                    shouldApplyRemote = true
                } else {
                    shouldApplyRemote = false
                }
            } else {
                savedConversations.append(saved)
                shouldApplyRemote = true
            }

            if shouldApplyRemote,
               currentTrackerThread?.id == bundle.thread.id {
                currentTrackerThread = bundle.thread
                if conversationKind == .tracker,
                   currentlyLoadedConversationId == saved.id {
                    conversationHistory = resolvedMessages
                    pendingTrackerDraft = resolvedMessages.last(where: { !$0.isUser })?.trackerOperationDraft
                    conversationTitle = bundle.thread.title
                }
            }
        }

        savedConversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversationHistoryLocally()
    }

    /// Load specific conversation by ID
    func loadConversation(withId id: UUID) {
        if let saved = savedConversations.first(where: { $0.id == id }) {
            conversationHistory = saved.messages
            conversationTitle = saved.title
            conversationKind = saved.kind
            isInConversationMode = true
            isNewConversation = false  // This is a loaded conversation, show title immediately
            currentlyLoadedConversationId = id  // Track which conversation is loaded
            lastGeneratedTitleMessageCount = conversationHistory.count
            pendingTrackerDraft = saved.messages.last(where: { !$0.isUser })?.trackerOperationDraft
            currentTrackerThread = trackerStore.thread(id: saved.trackerThreadId)
            currentConversationAnchorState = saved.messages.last(where: { !$0.isUser })?.evidenceBundle?.anchorState
            persistLastActiveConversationId(id)
            saveConversationLocally()

            if saved.kind == .standard {
                // Restore the note being edited from conversation context
                restoreNoteContextFromConversation()

                // Process any pending note updates from historical conversations
                Task {
                    await processPendingNoteUpdatesInHistory()
                }
            }
        }
    }

    /// Restore which note was being edited by scanning conversation for note updates
    private func restoreNoteContextFromConversation() {
        // Scan conversation history to find the most recent note mention
        for message in conversationHistory.reversed() {
            guard !message.isUser else { continue }

            let messageText = message.text
            let notesManager = NotesManager.shared

            // Look for note title patterns in messages like "Updated 'Monthly expenses'" or "Note updated: Monthly expenses"
            for note in notesManager.notes {
                if messageText.lowercased().contains(note.title.lowercased()) {
                    // Found the note being edited - restore it as the current context
                    currentNoteBeingRefined = note
                    isRefiningNote = true
                    pendingRefinementContent = nil  // Clear any pending to start fresh
                    return
                }
            }
        }
    }

    /// Process historical conversations to apply any pending note updates
    private func processPendingNoteUpdatesInHistory() async {
        var updatedHistory = conversationHistory
        var hasChanges = false

        // Iterate through conversation messages to find note updates
        for (index, message) in updatedHistory.enumerated() {
            // Skip user messages and already-confirmed updates
            guard !message.isUser else { continue }
            guard !message.text.contains("✓ Updated your note") else { continue }

            // Check if message indicates a note update (e.g., contains a note title and content)
            let messageText = message.text.lowercased()
            let noteKeywords = ["note", "update", "has been updated", "following"]

            if noteKeywords.allSatisfy({ messageText.contains($0) }) {
                // This looks like a note update response from LLM
                // Try to extract the note title and apply the update
                if let noteTitle = extractNoteTitle(from: message.text) {
                    let notesManager = NotesManager.shared
                    if let noteIndex = notesManager.notes.firstIndex(where: { $0.title == noteTitle }) {
                        var note = notesManager.notes[noteIndex]

                        // Extract and append the content from the LLM response
                        if let contentToAdd = extractNoteContent(from: message.text) {
                            if !note.content.isEmpty {
                                note.content += "\n\n" + contentToAdd
                            } else {
                                note.content = contentToAdd
                            }

                            // CRITICAL: Wait for sync to complete before confirming
                            note.dateModified = Date()
                            let _ = await notesManager.updateNoteAndWaitForSync(note)

                            // Add confirmation message after the update message
                            let confirmationMsg = ConversationMessage(
                                isUser: false,
                                text: "✓ Updated your note: \"\(noteTitle)\"",
                                intent: .notes
                            )

                            // Insert confirmation right after the update message
                            if index + 1 < updatedHistory.count {
                                updatedHistory.insert(confirmationMsg, at: index + 1)
                            } else {
                                updatedHistory.append(confirmationMsg)
                            }

                            hasChanges = true
                        }
                    }
                }
            }
        }

        // Update conversation history if changes were made
        if hasChanges {
            await MainActor.run {
                self.conversationHistory = updatedHistory
                self.saveConversationLocally()
            }
        }
    }

    /// Extract note title from LLM response
    private func extractNoteTitle(from text: String) -> String? {
        // Look for patterns like: Your "Note Title" note has been updated
        // or: Updated "Note Title" to the following:
        let patterns = [
            "\"([^\"]+)\"\\s+note",  // "Title" note
            "Updated\\s+\"([^\"]+)\"",  // Updated "Title"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = text as NSString
                if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                    if let range = Range(match.range(at: 1), in: text) {
                        return String(text[range])
                    }
                }
            }
        }

        return nil
    }

    /// Extract note content from LLM response
    private func extractNoteContent(from text: String) -> String? {
        // Find content after "following:" or similar markers
        let markers = ["following:", "following\n", ":\n\n"]

        for marker in markers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                let content = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    return content
                }
            }
        }

        return nil
    }

    /// Smart note update that detects if content should replace existing text or be added
    /// Returns: (updatedContent, delta, updateType) where delta is only what changed
    private func applySmartNoteUpdate(
        originalContent: String,
        suggestedContent: String,
        query: String
    ) -> (updatedContent: String, delta: String, updateType: String) {
        let lowerQuery = query.lowercased()

        // Check if this is a replacement/change operation based on keywords
        let replacementKeywords = ["change", "replace", "update to", "modify", "swap", "remove", "delete", "update"]
        let isReplacement = replacementKeywords.contains { keyword in
            lowerQuery.contains(keyword)
        }

        if isReplacement {
            // Try to detect pattern: "change/replace X to/with Y"
            let patterns = [
                "(?:change|replace|update|modify)\\s+[\"']?([^\"']+?)[\"']?\\s+(?:to|with)\\s+[\"']?([^\"']+?)[\"']?\\s*$",
                "(?:change|replace|update|modify)\\s+([^\\n]+?)\\s+(?:to|with)\\s+([^\\n]+)"
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let nsString = query as NSString
                    if let match = regex.firstMatch(in: query, options: [], range: NSRange(location: 0, length: nsString.length)) {
                        if match.numberOfRanges >= 3,
                           let range1 = Range(match.range(at: 1), in: query),
                           let range2 = Range(match.range(at: 2), in: query) {
                            let textToReplace = String(query[range1]).trimmingCharacters(in: .whitespaces)
                            let replacementText = String(query[range2]).trimmingCharacters(in: .whitespaces)

                            // Check if the text to replace exists in original content
                            if originalContent.lowercased().contains(textToReplace.lowercased()) {
                                let updatedContent = originalContent.replacingOccurrences(
                                    of: textToReplace,
                                    with: replacementText,
                                    options: .caseInsensitive
                                )

                                return (
                                    updatedContent: updatedContent,
                                    delta: "Changed \"\(textToReplace)\" to \"\(replacementText)\"",
                                    updateType: "Changed"
                                )
                            }
                        }
                    }
                }
            }

            // Fallback for replacement: replace entire content
            return (
                updatedContent: suggestedContent,
                delta: suggestedContent,
                updateType: "Updated"
            )
        } else {
            // Addition: only add if content doesn't already exist
            let originalLower = originalContent.lowercased()
            let suggestedLower = suggestedContent.lowercased()

            if !originalLower.contains(suggestedLower) && !suggestedLower.contains(originalLower) {
                // Content is new, add it
                let updatedContent = originalContent.isEmpty ?
                    suggestedContent :
                    originalContent + "\n\n" + suggestedContent

                return (
                    updatedContent: updatedContent,
                    delta: suggestedContent,
                    updateType: "Added"
                )
            } else {
                // Content already exists, don't duplicate
                return (
                    updatedContent: originalContent,
                    delta: "(Content already in note)",
                    updateType: "Already exists"
                )
            }
        }
    }

    /// Delete conversation from history
    func deleteConversation(withId id: UUID) {
        let isCurrentlyLoaded = currentlyLoadedConversationId == id

        if let conversation = savedConversations.first(where: { $0.id == id }),
           conversation.kind == .tracker,
           let trackerThreadId = conversation.trackerThreadId {
            trackerStore.deleteThread(id: trackerThreadId)
        } else {
            Task {
                await deleteStandardConversationsFromSupabase(ids: [id])
            }
        }
        savedConversations.removeAll { $0.id == id }

        if isCurrentlyLoaded {
            resetDeletedConversationState()
        }

        saveConversationHistoryLocally()
    }
    
    /// Delete all conversations from history
    func deleteAllConversations() {
        let trackerIds = savedConversations.compactMap(\.trackerThreadId)
        trackerIds.forEach { trackerStore.deleteThread(id: $0) }
        let standardConversationIDs = savedConversations
            .filter { $0.kind == .standard }
            .map(\.id)
        savedConversations.removeAll()

        if !standardConversationIDs.isEmpty {
            Task {
                await deleteStandardConversationsFromSupabase(ids: standardConversationIDs)
            }
        }

        if currentlyLoadedConversationId != nil {
            resetDeletedConversationState()
        }

        saveConversationHistoryLocally()
    }
    
    /// Delete multiple conversations by their IDs
    func deleteConversations(withIds ids: Set<UUID>) {
        let shouldResetLoadedConversation = currentlyLoadedConversationId.map(ids.contains) ?? false
        let trackerIds = savedConversations
            .filter { ids.contains($0.id) }
            .compactMap(\.trackerThreadId)
        let standardConversationIDs = savedConversations
            .filter { ids.contains($0.id) && $0.kind == .standard }
            .map(\.id)
        trackerIds.forEach { trackerStore.deleteThread(id: $0) }
        savedConversations.removeAll { ids.contains($0.id) }

        if !standardConversationIDs.isEmpty {
            Task {
                await deleteStandardConversationsFromSupabase(ids: standardConversationIDs)
            }
        }

        if shouldResetLoadedConversation {
            resetDeletedConversationState()
        }

        saveConversationHistoryLocally()
    }

    // MARK: - Clear Data on Logout

    func clearSearchOnLogout() {
        searchResults = []
        searchQuery = ""
        conversationHistory = []
        savedConversations = []
        pendingEventCreation = nil
        pendingNoteCreation = nil
        pendingNoteUpdate = nil
        questionResponse = nil
        currentInteractiveAction = nil
        cachedContent = []
        isInConversationMode = false
        conversationTitle = "New Conversation"
        conversationKind = .standard
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        isNewConversation = false
        currentlyLoadedConversationId = nil
        cancellables.removeAll()
        trackerStore.clearLocalData()
        currentConversationAnchorState = nil

        // Clear conversation storage from UserDefaults
        UserDefaults.standard.removeObject(forKey: "SavedConversations")
        UserDefaults.standard.removeObject(forKey: Self.lastConversationStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.lastActiveConversationIdStorageKey)

        print("🗑️ Cleared all search and conversation data on logout")
    }

    private func resetDeletedConversationState() {
        conversationHistory = []
        isInConversationMode = false
        isLoadingQuestionResponse = false
        questionResponse = nil
        conversationTitle = "New Conversation"
        conversationKind = .standard
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        isNewConversation = false
        currentlyLoadedConversationId = nil
        lastGeneratedTitleMessageCount = 0
        currentConversationAnchorState = nil
        UserDefaults.standard.removeObject(forKey: Self.lastConversationStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.lastActiveConversationIdStorageKey)
    }

    private func deleteStandardConversationsFromSupabase(ids: [UUID]) async {
        guard !ids.isEmpty, let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("conversations")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .in("id", values: ids.map(\.uuidString))
                .execute()
        } catch {
            print("❌ Failed deleting conversations from Supabase: \(error)")
        }
    }
}

// MARK: - Saved Conversation Model

struct SavedConversation: Identifiable, Codable {
    let id: UUID
    let title: String
    let kind: ConversationKind
    let trackerThreadId: UUID?
    let subtitle: String?
    let messages: [ConversationMessage]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case trackerThreadId
        case subtitle
        case messages
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        title: String,
        kind: ConversationKind = .standard,
        trackerThreadId: UUID? = nil,
        subtitle: String? = nil,
        messages: [ConversationMessage],
        createdAt: Date,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.trackerThreadId = trackerThreadId
        self.subtitle = subtitle
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(ConversationKind.self, forKey: .kind) ?? .standard
        trackerThreadId = try container.decodeIfPresent(UUID.self, forKey: .trackerThreadId)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        messages = try container.decode([ConversationMessage].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }
}

private struct RemoteConversationRecord: Decodable {
    let id: UUID
    let title: String
    let messages: String
    let created_at: Date
}
