import Foundation
import Combine

@MainActor
class SearchService: ObservableObject {
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
    private var streamingMessageID: UUID? = nil

    // NEW: SelineChat integration flag
    @Published var useSelineChat: Bool = true  // Use new simplified chat system
    private var selineChat: SelineChat? = nil

    // DEPRECATED: Semantic query system removed - SelineChat handles all queries directly
    // @Published var useSemanticQueryFallback: Bool = false
    // NOTE: Semantic query system is being phased out in favor of simpler SelineChat approach
    // Reason: Semantic query parsing is complex, error-prone, and the LLM can handle all logic directly

    /// DEPRECATED: Semantic query system removed
    // func disableSemanticQuerySystem() {
    //     useSemanticQueryFallback = false
    // }

    // Track recently created items for context in follow-up actions
    private var lastCreatedEventTitle: String? = nil
    private var lastCreatedEventDate: String? = nil
    private var lastCreatedNoteTitle: String? = nil

    private var searchableProviders: [TabSelection: Searchable] = [:]
    private var cachedContent: [SearchableItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let queryRouter = QueryRouter.shared
    private let conversationActionHandler = ConversationActionHandler.shared
    private let infoExtractor = InformationExtractor.shared
    private let trackerStore = TrackerStore.shared
    private let trackerParserService = TrackerParserService.shared

    var chatLoadingStatusLabel: String {
        chatLoadingPhase.statusLabel
    }

    var isTrackerConversation: Bool {
        conversationKind == .tracker
    }

    private init() {
        // DEPRECATED: Semantic query system removed
        // disableSemanticQuerySystem()

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

    func registerSearchableProvider(_ provider: Searchable, for tab: TabSelection) {
        searchableProviders[tab] = provider
        refreshSearchableContent()
    }

    func unregisterSearchableProvider(for tab: TabSelection) {
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

    func navigateToResult(_ result: SearchResult) -> TabSelection {
        return result.item.type
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Semantic Query Processing (DEPRECATED - Moved to LLMArchitecture_deprecated/)
    // The entire semantic query system has been deprecated in favor of SelineChat + VectorContextBuilder.
    // SelineChat handles all query types directly without pre-processing.
    
    /*
    /// DEPRECATED: Try to process a query using the semantic query engine first
    func processWithSemanticQuery(_ userQuery: String) async -> (text: String, items: [RelatedDataItem])? {
        // Moved to LLMArchitecture_deprecated/
        return nil
    }

    /// DEPRECATED: Map RelatedItem type to RelatedDataItem.DataType
    private func mapItemType(_ type: String) -> RelatedDataItem.DataType {
        return .receipt
    }
    */

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

        // Always use SelineChat - legacy path removed
        await addConversationMessageWithSelineChat(trimmed, thinkStartTime: thinkStartTime)
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
    
    // MARK: - SelineChat Implementation (Phase 2)

    /// NEW simplified chat using SelineChat with proper streaming support
    private func addConversationMessageWithSelineChat(_ userMessage: String, thinkStartTime: Date, skipUserMessage: Bool = false) async {
        chatLoadingPhase = .retrieving
        VectorSearchService.shared.beginInteractiveRequest(reason: "chat")
        defer {
            VectorSearchService.shared.endInteractiveRequest(reason: "chat")
        }

        // Initialize SelineChat if needed
        if selineChat == nil {
            selineChat = SelineChat(appContext: SelineAppContext(), geminiService: GeminiService.shared)

            // IMPORTANT: Sync existing conversation history to SelineChat
            // This ensures historical chats retain context when reopened
            if !conversationHistory.isEmpty {
                for msg in conversationHistory {
                    let chatMsg = ChatMessage(
                        role: msg.isUser ? .user : .assistant,
                        content: msg.text,
                        timestamp: msg.timestamp
                    )
                    selineChat?.conversationHistory.append(chatMsg)
                }
                print("📝 Restored \(conversationHistory.count) messages to SelineChat context")
            }
        }

        guard let chat = selineChat else {
            print("❌ SelineChat initialization failed")
            DispatchQueue.main.async {
                self.isLoadingQuestionResponse = false
                self.chatLoadingPhase = .idle
            }
            return
        }
        
        // If skipUserMessage is true, don't add user message to SelineChat history
        // (it's already there from the previous interaction)
        if !skipUserMessage {
            // Check if last message in SelineChat is already this user message
            let shouldAddToChatHistory: Bool
            if let lastChatMsg = chat.conversationHistory.last, 
               lastChatMsg.role == .user && lastChatMsg.content == userMessage {
                shouldAddToChatHistory = false
            } else {
                shouldAddToChatHistory = true
            }
            
            if shouldAddToChatHistory {
                // Add user message to SelineChat history if not skipping
                let userMsg = ChatMessage(role: .user, content: userMessage, timestamp: Date())
                chat.conversationHistory.append(userMsg)
            }
        }

        // Prepare non-citation chat UI state (event creation cards, ETA cards).
        // Citation evidence now comes from VectorContextBuilder output to keep one source of truth.
        let effectiveQuery = chat.contextQueryForLatestUserTurn()
        await chat.appContext.prepareEventCreationInfoForChat(userQuery: effectiveQuery)

        setupSelineChatCallbacks(chat: chat, thinkStartTime: thinkStartTime)
        
        let response = await chat.sendMessage(userMessage, streaming: enableStreamingResponses)
        
        handleNonStreamingResponse(response: response, thinkStartTime: thinkStartTime)
    }
    
    // Wire up streaming callbacks common to both normal chat and briefing
    private func setupSelineChatCallbacks(chat: SelineChat, thinkStartTime: Date) {
        let streamingMessageID = UUID()
        weak var weakSelf = self
        var messageAdded = false
        var fullResponse = ""
        var didFinalizeStreaming = false

        func commitUpdate(with text: String) {
            guard weakSelf != nil else { return }
            if !messageAdded {
                let assistantMsg = ConversationMessage(
                    id: streamingMessageID,
                    isUser: false,
                    text: text,
                    timestamp: Date(),
                    intent: .general,
                    timeStarted: thinkStartTime,
                    locationInfo: chat.appContext.lastETALocationInfo,
                    eventCreationInfo: chat.appContext.lastEventCreationInfo,
                    relevantContent: chat.appContext.lastRelevantContent
                )
                conversationHistory.append(assistantMsg)
                messageAdded = true
                saveConversationLocally()
            } else if let lastIndex = conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                let updatedMsg = ConversationMessage(
                    id: streamingMessageID,
                    isUser: false,
                    text: text,
                    timestamp: conversationHistory[lastIndex].timestamp,
                    intent: conversationHistory[lastIndex].intent ?? .general,
                    timeStarted: conversationHistory[lastIndex].timeStarted,
                    locationInfo: chat.appContext.lastETALocationInfo,
                    eventCreationInfo: chat.appContext.lastEventCreationInfo,
                    relevantContent: chat.appContext.lastRelevantContent
                )
                conversationHistory[lastIndex] = updatedMsg
                lastMessageContentVersion += 1
                saveConversationLocally()
            }
        }

        func finalizeStreaming() {
            guard !didFinalizeStreaming else { return }
            didFinalizeStreaming = true

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !messageAdded {
                    commitUpdate(with: fullResponse)
                }
                // Update final message with completion time and fetch related data
                if let lastIndex = self.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                    let rawResponseText = self.conversationHistory[lastIndex].text
                    let aligned = self.alignCitationsWithRelevantContent(
                        in: rawResponseText,
                        relevantContent: chat.appContext.lastRelevantContent
                    )
                    let responseText = aligned.text

                    let updatedMsg = ConversationMessage(
                        id: streamingMessageID,
                        isUser: false,
                        text: responseText,
                        timestamp: self.conversationHistory[lastIndex].timestamp,
                        intent: self.conversationHistory[lastIndex].intent ?? .general,
                        timeStarted: self.conversationHistory[lastIndex].timeStarted,
                        locationInfo: chat.appContext.lastETALocationInfo,
                        eventCreationInfo: chat.appContext.lastEventCreationInfo,
                        relevantContent: aligned.relevantContent
                    )
                    chat.updateResolvedVisitPlace(from: aligned.relevantContent ?? chat.appContext.lastRelevantContent)
                    self.conversationHistory[lastIndex] = updatedMsg
                    self.lastMessageContentVersion += 1

                    // Fetch related data based on response
                    Task { [weak self] in
                        guard let self = self else { return }
                        let relatedData = await self.fetchRelatedDataForResponse(responseText)

                        DispatchQueue.main.async {
                            if let lastIndex = self.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                                let finalMsg = ConversationMessage(
                                    id: streamingMessageID,
                                    isUser: false,
                                    text: self.conversationHistory[lastIndex].text,
                                    timestamp: self.conversationHistory[lastIndex].timestamp,
                                    intent: self.conversationHistory[lastIndex].intent ?? .general,
                                    relatedData: relatedData.isEmpty ? nil : relatedData,
                                    timeStarted: self.conversationHistory[lastIndex].timeStarted,
                                    timeFinished: Date(),
                                    followUpSuggestions: nil,
                                    locationInfo: chat.appContext.lastETALocationInfo,
                                    eventCreationInfo: chat.appContext.lastEventCreationInfo,
                                    relevantContent: self.conversationHistory[lastIndex].relevantContent
                                )
                                self.conversationHistory[lastIndex] = finalMsg
                                self.lastMessageContentVersion += 1
                                self.saveConversationLocally()
                            }
                        }
                    }
                }

                self.isLoadingQuestionResponse = false
                self.chatLoadingPhase = .idle
                print("✅ SelineChat streaming completed")
            }
        }

        chat.onStreamingStateChanged = { [weak self] isStreaming in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if isStreaming {
                    self.chatLoadingPhase = .generating
                } else if !self.isLoadingQuestionResponse {
                    self.chatLoadingPhase = .idle
                }
            }
        }

        // Callback when a streaming chunk arrives (real-time token updates)
        chat.onStreamingChunk = { [weak self] chunk in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.chatLoadingPhase = .generating
                fullResponse += chunk
                commitUpdate(with: fullResponse)
            }
        }

        // Callback when streaming completes (finalize metadata and citations)
        chat.onStreamingComplete = { [weak self] in
            DispatchQueue.main.async {
                guard self != nil else { return }
                finalizeStreaming()
            }
        }
    }
    
    private func handleNonStreamingResponse(response: String, thinkStartTime: Date) {
        let aligned = alignCitationsWithRelevantContent(
            in: response,
            relevantContent: selineChat?.appContext.lastRelevantContent
        )
        let finalResponse = aligned.text
        selineChat?.updateResolvedVisitPlace(from: aligned.relevantContent ?? selineChat?.appContext.lastRelevantContent)

        if !enableStreamingResponses {
            Task {
                let relatedData = await fetchRelatedDataForResponse(finalResponse)
                
                await MainActor.run {
                    let assistantMsg = ConversationMessage(
                        id: UUID(),
                        isUser: false,
                        text: finalResponse,
                        timestamp: Date(),
                        intent: .general,
                        relatedData: relatedData.isEmpty ? nil : relatedData,
                        timeStarted: thinkStartTime,
                        timeFinished: Date(),
                        locationInfo: self.selineChat?.appContext.lastETALocationInfo,
                        eventCreationInfo: self.selineChat?.appContext.lastEventCreationInfo,
                        relevantContent: aligned.relevantContent
                    )
                    self.conversationHistory.append(assistantMsg)
                    self.isLoadingQuestionResponse = false
                    self.chatLoadingPhase = .idle
                    self.saveConversationLocally()
                    print("✅ SelineChat response added to history")
                }
            }
        }
    }

    private func alignCitationsWithRelevantContent(
        in responseText: String,
        relevantContent: [RelevantContentInfo]?
    ) -> (text: String, relevantContent: [RelevantContentInfo]?) {
        let normalizedText = normalizeCitationMarkers(in: responseText)
        let citationRegex = try! NSRegularExpression(pattern: "\\[\\s*(\\d+)\\s*\\]")
        let placeholderCitationRegex = try! NSRegularExpression(pattern: "\\[(?i:[a-z])\\]")
        let numericMatches = citationRegex.matches(in: normalizedText, range: NSRange(normalizedText.startIndex..., in: normalizedText))
        let placeholderMatches = placeholderCitationRegex.matches(in: normalizedText, range: NSRange(normalizedText.startIndex..., in: normalizedText))

        guard let content = relevantContent, !content.isEmpty else {
            return (stripCitationMarkers(from: normalizedText), nil)
        }

        guard !numericMatches.isEmpty || !placeholderMatches.isEmpty else {
            // Inline-only citation mode: no fallback source pills when model omitted citations.
            return (stripCitationMarkers(from: normalizedText), nil)
        }

        struct CitationReplacement {
            let range: NSRange
            let replacementText: String
        }

        enum CitationMatch {
            case numeric(NSTextCheckingResult)
            case placeholder(NSTextCheckingResult)

            var range: NSRange {
                switch self {
                case .numeric(let result), .placeholder(let result):
                    return result.range
                }
            }
        }

        var replacements: [CitationReplacement] = []
        var orderedContent: [RelevantContentInfo] = []
        var orderedIndexBySourceKey: [String: Int] = [:]
        var displayedCitationSourceKeys = Set<String>()
        let rawCitationIndexes: [Int] = numericMatches.compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: normalizedText) else { return nil }
            return Int(String(normalizedText[numberRange]))
        }
        let shouldTreatIndexesAsOneBased =
            !rawCitationIndexes.isEmpty &&
            !rawCitationIndexes.contains(0) &&
            rawCitationIndexes.allSatisfy { $0 >= 1 && $0 <= content.count }

        func replacement(for selectedItem: RelevantContentInfo, range: NSRange) -> CitationReplacement {
            let sourceKey = citationSourceIdentityKey(for: selectedItem)
            let mappedIndex: Int
            if let existing = orderedIndexBySourceKey[sourceKey] {
                mappedIndex = existing
            } else {
                mappedIndex = orderedContent.count
                orderedContent.append(selectedItem)
                orderedIndexBySourceKey[sourceKey] = mappedIndex
            }

            // Keep inline citations concise: render each source pill once per response.
            if displayedCitationSourceKeys.contains(sourceKey) {
                return CitationReplacement(range: range, replacementText: "")
            }
            displayedCitationSourceKeys.insert(sourceKey)

            return CitationReplacement(
                range: range,
                replacementText: "[[\(mappedIndex)]]"
            )
        }

        let allMatches = (
            numericMatches.map { CitationMatch.numeric($0) } +
            placeholderMatches.map { CitationMatch.placeholder($0) }
        ).sorted { lhs, rhs in
            lhs.range.location < rhs.range.location
        }

        for match in allMatches {
            switch match {
            case .numeric(let result):
                guard
                    let numberRange = Range(result.range(at: 1), in: normalizedText),
                    let parsedIndex = Int(String(normalizedText[numberRange]))
                else { continue }
                let citedIndex = shouldTreatIndexesAsOneBased ? parsedIndex - 1 : parsedIndex

                guard citedIndex >= 0, citedIndex < content.count else {
                    print("⚠️ Dropping citation [\(citedIndex)] - out of range for available sources (\(content.count))")
                    replacements.append(CitationReplacement(range: result.range, replacementText: ""))
                    continue
                }

                let selectedItem = content[citedIndex]
                let contextSnippet = citationContext(in: normalizedText, around: result.range)
                guard
                    let matchScore = citationMatchScore(for: selectedItem, context: contextSnippet),
                    matchScore >= minimumCitationScore(for: selectedItem)
                else {
                    print("⚠️ Dropping citation [\(citedIndex)] - source/context mismatch")
                    replacements.append(CitationReplacement(range: result.range, replacementText: ""))
                    continue
                }

                replacements.append(replacement(for: selectedItem, range: result.range))

            case .placeholder(let result):
                let contextSnippet = citationContext(in: normalizedText, around: result.range)
                let bestIndex = bestMatchingCitationSourceIndex(
                    in: content,
                    context: contextSnippet,
                    excluding: displayedCitationSourceKeys
                )

                guard let bestIndex else {
                    replacements.append(CitationReplacement(range: result.range, replacementText: ""))
                    continue
                }

                replacements.append(replacement(for: content[bestIndex], range: result.range))
            }
        }

        let mutableText = NSMutableString(string: normalizedText)
        for replacement in replacements.reversed() {
            mutableText.replaceCharacters(in: replacement.range, with: replacement.replacementText)
        }

        let cleanedText = cleanupCitationSpacing(in: mutableText as String)
        if orderedContent.isEmpty {
            return (cleanedText, nil)
        }
        return (cleanedText, orderedContent)
    }

    private func bestMatchingCitationSourceIndex(
        in content: [RelevantContentInfo],
        context: String,
        excluding displayedCitationSourceKeys: Set<String>
    ) -> Int? {
        var bestIndex: Int?
        var bestScore = Int.min
        var isAmbiguous = false

        for (index, item) in content.enumerated() {
            let sourceKey = citationSourceIdentityKey(for: item)
            guard !displayedCitationSourceKeys.contains(sourceKey) else { continue }

            guard let score = citationMatchScore(for: item, context: context) else {
                continue
            }

            if score > bestScore {
                bestScore = score
                bestIndex = index
                isAmbiguous = false
            } else if score == bestScore {
                isAmbiguous = true
            }
        }

        guard let bestIndex else { return nil }
        let bestItem = content[bestIndex]
        guard bestScore >= minimumCitationScore(for: bestItem), !isAmbiguous else {
            return nil
        }

        return bestIndex
    }

    private func displayTitleForCitation(_ item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email:
            return item.emailSubject ?? item.emailSender ?? "Email"
        case .note:
            return item.noteTitle ?? "Note"
        case .receipt:
            return item.receiptTitle ?? item.noteTitle ?? "Receipt"
        case .event:
            return item.eventTitle ?? "Event"
        case .location:
            return item.locationName ?? "Place"
        case .visit:
            return item.visitPlaceName ?? item.locationName ?? "Visit"
        case .person:
            return item.personName ?? "Person"
        }
    }

    private func isCitationLikelyValid(for item: RelevantContentInfo, context: String) -> Bool {
        guard let score = citationMatchScore(for: item, context: context) else {
            return false
        }
        return score >= minimumCitationScore(for: item)
    }

    private func citationMatchScore(for item: RelevantContentInfo, context: String) -> Int? {
        let normalizedContext = context.lowercased()
        let matchedTerms = sourceTerms(for: item).filter { normalizedContext.contains($0) }
        let matchedTermScore = matchedTerms.reduce(0) { partial, term in
            partial + min(term.count, 12)
        }
        let exactTitle = normalizedIdentityText(displayTitleForCitation(item))
        let exactTitleMatch = !exactTitle.isEmpty && normalizedContext.contains(exactTitle)

        switch item.contentType {
        case .location:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            return matchedTermScore + (exactTitleMatch ? 18 : 0)
        case .visit:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            let activityBoost = (normalizedContext.contains("visit") || normalizedContext.contains("went")) ? 4 : 0
            return matchedTermScore + (exactTitleMatch ? 18 : 0) + activityBoost
        case .event:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            let calendarBoost = (normalizedContext.contains("calendar") || normalizedContext.contains("event")) ? 4 : 0
            return matchedTermScore + (exactTitleMatch ? 18 : 0) + calendarBoost
        case .email:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            let emailBoost = (normalizedContext.contains("email") || normalizedContext.contains("inbox") || normalizedContext.contains("subject")) ? 4 : 0
            return matchedTermScore + (exactTitleMatch ? 18 : 0) + emailBoost
        case .note:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            let noteBoost: Int
            let lowerFolder = (item.noteFolder ?? "").lowercased()
            if lowerFolder.contains("journal") || lowerFolder.contains("weekly summary") || lowerFolder.contains("weekly recap") || lowerFolder.contains("recap") {
                noteBoost = (normalizedContext.contains("journal") || normalizedContext.contains("recap") || normalizedContext.contains("summary")) ? 4 : 0
            } else {
                noteBoost = normalizedContext.contains("note") ? 3 : 0
            }
            return matchedTermScore + (exactTitleMatch ? 18 : 0) + noteBoost
        case .receipt:
            let merchantPhrase = normalizedIdentityText(receiptMerchantLabel(for: item))
            let merchantPhraseMatch = !merchantPhrase.isEmpty && normalizedContext.contains(merchantPhrase)
            let amountMatch = contextMentionsReceiptAmount(item.receiptAmount, in: normalizedContext)
            let categoryMatch = contextMentionsReceiptCategory(item.receiptCategory, in: normalizedContext)
            guard merchantPhraseMatch || exactTitleMatch || !matchedTerms.isEmpty || (amountMatch && categoryMatch) else {
                return nil
            }

            var score = matchedTermScore
            if exactTitleMatch { score += 18 }
            if merchantPhraseMatch { score += 22 }
            if amountMatch { score += 20 }
            if categoryMatch { score += 8 }
            if amountMatch && (merchantPhraseMatch || exactTitleMatch || !matchedTerms.isEmpty) {
                score += 10
            }
            if normalizedContext.contains("receipt")
                || normalizedContext.contains("expense")
                || normalizedContext.contains("purchase")
                || normalizedContext.contains("paid")
                || normalizedContext.contains("spent") {
                score += 4
            }
            return score
        case .person:
            guard exactTitleMatch || !matchedTerms.isEmpty else { return nil }
            let withBoost = normalizedContext.contains("with") ? 3 : 0
            return matchedTermScore + (exactTitleMatch ? 18 : 0) + withBoost
        }
    }

    private func minimumCitationScore(for item: RelevantContentInfo) -> Int {
        switch item.contentType {
        case .receipt:
            return 18
        case .email:
            return 10
        case .note:
            return 8
        case .event, .location, .visit, .person:
            return 6
        }
    }

    private func receiptMerchantLabel(for item: RelevantContentInfo) -> String {
        let rawTitle = item.receiptTitle ?? item.noteTitle ?? ""
        for separator in [" - ", " — ", " – "] {
            if let range = rawTitle.range(of: separator) {
                let prefix = rawTitle[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return prefix
                }
            }
        }
        return rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func contextMentionsReceiptAmount(_ amount: Double?, in context: String) -> Bool {
        guard let amount else { return false }
        return extractCurrencyValues(from: context).contains { abs($0 - amount) < 0.011 }
    }

    private func contextMentionsReceiptCategory(_ category: String?, in context: String) -> Bool {
        let normalizedCategory = normalizedIdentityText(category)
        guard !normalizedCategory.isEmpty else { return false }

        let categoryTerms = normalizedCategory
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }

        if context.contains(normalizedCategory) {
            return true
        }

        return categoryTerms.contains { context.contains($0) }
    }

    private func extractCurrencyValues(from context: String) -> [Double] {
        let pattern = "\\$\\s*(\\d+(?:,\\d{3})*(?:\\.\\d{1,2})?)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: context, range: NSRange(context.startIndex..., in: context))

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: context) else { return nil }
            let rawValue = context[range].replacingOccurrences(of: ",", with: "")
            return Double(rawValue)
        }
    }

    private func citationSourceIdentityKey(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email:
            if let emailId = item.emailId, !emailId.isEmpty { return "email:\(emailId)" }
            return "email:\(normalizedIdentityText(item.emailSubject))|\(normalizedIdentityText(item.emailSender))|\(Int(item.emailDate?.timeIntervalSince1970 ?? 0))"
        case .note:
            if let noteId = item.noteId { return "note:\(noteId.uuidString.lowercased())" }
            return "note:\(normalizedIdentityText(item.noteTitle))|\(normalizedIdentityText(item.noteSnippet))"
        case .receipt:
            if let receiptId = item.receiptId { return "receipt:\(receiptId.uuidString.lowercased())" }
            if let noteId = item.noteId { return "receipt-note:\(noteId.uuidString.lowercased())" }
            let amountKey = item.receiptAmount.map { String(format: "%.2f", $0) } ?? "0.00"
            return "receipt:\(normalizedIdentityText(item.receiptTitle))|\(amountKey)|\(Int(item.receiptDate?.timeIntervalSince1970 ?? 0))"
        case .event:
            if let eventId = item.eventId { return "event:\(eventId.uuidString.lowercased())" }
            return "event:\(normalizedIdentityText(item.eventTitle))|\(Int(item.eventDate?.timeIntervalSince1970 ?? 0))"
        case .location:
            if let locationId = item.locationId { return "location:\(locationId.uuidString.lowercased())" }
            return "location:\(normalizedIdentityText(item.locationName))|\(normalizedIdentityText(item.locationAddress))"
        case .visit:
            if let visitId = item.visitId { return "visit:\(visitId.uuidString.lowercased())" }
            if let placeId = item.visitPlaceId { return "visit-place:\(placeId.uuidString.lowercased())|\(Int(item.visitEntryTime?.timeIntervalSince1970 ?? 0))" }
            return "visit:\(normalizedIdentityText(item.visitPlaceName))|\(Int(item.visitEntryTime?.timeIntervalSince1970 ?? 0))"
        case .person:
            if let personId = item.personId { return "person:\(personId.uuidString.lowercased())" }
            return "person:\(normalizedIdentityText(item.personName))|\(normalizedIdentityText(item.personRelationship))"
        }
    }

    private func normalizedIdentityText(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func sourceTerms(for item: RelevantContentInfo) -> [String] {
        let rawValue: String
        switch item.contentType {
        case .location:
            rawValue = "\(item.locationName ?? "") \(item.locationAddress ?? "")"
        case .visit:
            rawValue = "\(item.visitPlaceName ?? "") \(item.locationName ?? "") \(item.locationAddress ?? "") \(item.visitEntryTime?.description ?? "")"
        case .event:
            rawValue = "\(item.eventTitle ?? "") \(item.eventCategory ?? "")"
        case .email:
            rawValue = "\(item.emailSubject ?? "") \(item.emailSender ?? "")"
        case .note:
            rawValue = "\(item.noteTitle ?? "") \(item.noteSnippet ?? "") \(item.noteFolder ?? "")"
        case .receipt:
            rawValue = "\(receiptMerchantLabel(for: item)) \(item.receiptCategory ?? "")"
        case .person:
            rawValue = "\(item.personName ?? "") \(item.personRelationship ?? "")"
        }

        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "your", "you", "this", "that",
            "visit", "visited", "event", "note", "email", "calendar", "place",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]

        let tokens = rawValue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        return Array(Set(tokens)).sorted(by: { $0.count > $1.count })
    }

    private func citationContext(in text: String, around range: NSRange) -> String {
        guard let rangeInText = Range(range, in: text) else { return "" }
        let start = text.index(rangeInText.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(rangeInText.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).lowercased()
    }

    private func normalizeCitationMarkers(in text: String) -> String {
        let normalizedBrackets = text
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")

        let groupedCitationRegex = try! NSRegularExpression(pattern: "\\[(\\s*\\d+\\s*(?:,\\s*\\d+\\s*)+)\\]")
        let matches = groupedCitationRegex.matches(
            in: normalizedBrackets,
            range: NSRange(normalizedBrackets.startIndex..., in: normalizedBrackets)
        )

        guard !matches.isEmpty else { return normalizedBrackets }

        let mutable = NSMutableString(string: normalizedBrackets)
        for match in matches.reversed() {
            guard let contentRange = Range(match.range(at: 1), in: normalizedBrackets) else { continue }
            let numbers = normalizedBrackets[contentRange]
                .split(separator: ",")
                .compactMap { part in
                    Int(String(part).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            guard !numbers.isEmpty else {
                mutable.replaceCharacters(in: match.range, with: "")
                continue
            }

            let replacement = numbers
                .map { "[\($0)]" }
                .joined(separator: " ")
            mutable.replaceCharacters(in: match.range, with: replacement)
        }

        return mutable as String
    }

    private func stripCitationMarkers(from text: String) -> String {
        var stripped = normalizeCitationMarkers(in: text)
            .replacingOccurrences(of: "\\[\\s*\\d+\\s*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:[a-z])\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:see\\s+[^\\]]+)\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:from\\s+[^\\]]+)\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:sources?\\s*[^\\]]*)\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:user\\s+memory\\s*[^\\]]*)\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[(?i:relevant\\s+data\\s*[^\\]]*)\\]", with: "", options: .regularExpression)
        stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanupCitationSpacing(in: stripped)
    }

    private func cleanupCitationSpacing(in text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned
    }

    /// Generate a proactive morning briefing
    func generateMorningBriefing() async {
        guard conversationHistory.isEmpty else { return }
        
        if selineChat == nil {
            selineChat = SelineChat(appContext: SelineAppContext(), geminiService: GeminiService.shared)
        }
        guard let chat = selineChat else { return }
        
        // No loading state needed - response is instant
        await chat.generateMorningBriefing()
        
        // Sync the result from SelineChat to SearchService history
        if let lastMsg = chat.conversationHistory.last, lastMsg.role == .assistant {
            // Check if we haven't already added this message
            if conversationHistory.last?.text != lastMsg.content {
                let assistantMsg = ConversationMessage(
                    id: UUID(),
                    isUser: false,
                    text: lastMsg.content,
                    timestamp: lastMsg.timestamp,
                    intent: .general
                )
                
                await MainActor.run {
                    self.conversationHistory.append(assistantMsg)
                    self.saveConversationLocally()
                }
            }
        }
    }

    // MARK: - Legacy Implementation (DEPRECATED - Moved to LLMArchitecture_deprecated/)
    // addConversationMessageLegacy() has been deprecated in favor of SelineChat
    // Keeping the method signature but it now calls the active SelineChat path
    /*
    /// DEPRECATED: Old legacy chat system
    private func addConversationMessageLegacy(_ userMessage: String, thinkStartTime: Date) async {
        // Moved to LLMArchitecture_deprecated/
        // This path is never reached since useSelineChat is always true
    }
    */

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
        selineChat?.cancelStreaming()
        isLoadingQuestionResponse = false
        print("🛑 User cancelled the response")
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

        // Also remove the last assistant message from SelineChat's conversation history if it exists
        // This keeps the history in sync for regeneration
        if let chat = selineChat, !chat.conversationHistory.isEmpty {
            let lastMessage = chat.conversationHistory.last
            if lastMessage?.role == .assistant {
                chat.conversationHistory.removeLast()
                print("🔄 Removed last assistant message from SelineChat history for regeneration")
            }
        }

        // Save the updated conversation (without the old assistant message)
        saveConversationLocally()

        // Regenerate response without adding duplicate user message
        // The user message is already in the history at userMessageIndex, so we just regenerate the assistant response
        isLoadingQuestionResponse = true
        let thinkStartTime = Date()
        
        // Always use SelineChat for regeneration
        await addConversationMessageWithSelineChat(userMessage, thinkStartTime: thinkStartTime, skipUserMessage: true)
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

            defaults.set(encoded, forKey: "lastConversation")
        } catch {
            print("❌ Error saving conversation locally: \(error)")
        }
    }

    /// Load last conversation from local storage
    func loadLastConversation() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "lastConversation") else { return }

        do {
            conversationHistory = try JSONDecoder().decode([ConversationMessage].self, from: data)
            conversationTitle = provisionalConversationTitle(from: conversationHistory)
        } catch {
            print("❌ Error loading conversation: \(error)")
        }
    }

    /// Save conversation to Supabase
    func saveConversationToSupabase() async {
        guard !conversationHistory.isEmpty else { return }

        if conversationKind == .tracker, let currentTrackerThread {
            await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
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

            // Create a struct that conforms to Encodable
            struct ConversationData: Encodable {
                let user_id: UUID
                let title: String
                let messages: String
                let message_count: Int
                let first_message: String
                let created_at: String
            }

            let data = ConversationData(
                user_id: userId,
                title: titleToSave,
                messages: historyJson,
                message_count: conversationHistory.count,
                first_message: conversationHistory.first?.text ?? "",
                created_at: ISO8601DateFormatter().string(from: Date())
            )

            // Save to conversations table
            try await client
                .from("conversations")
                .insert(data)
                .execute()
        } catch {
            print("❌ Error saving conversation to Supabase: \(error)")
        }
    }

    /// Load conversations from Supabase (requires conversations table to be created)
    /// Currently disabled - can be implemented once Supabase table is fully set up
    /// For now, conversations are loaded from local UserDefaults via loadLastConversation()
    func loadConversationsFromSupabase() async -> [[String: Any]] {
        // To implement this:
        // 1. Create the conversations table in Supabase (using provided SQL)
        // 2. Use direct HTTP request or update Supabase SDK implementation
        return []
    }

    /// Load specific conversation from Supabase by ID
    /// Currently disabled - can be implemented once proper SDK support is available
    func loadConversationFromSupabase(id: String) async {
        // Not yet implemented - use loadLastConversation() for local persistence
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
                    trackerStateSnapshot: message.trackerStateSnapshot
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

            // Reset SelineChat so the next follow-up message re-initializes with this conversation's history.
            // Otherwise SelineChat keeps stale context and follow-ups get wrong/empty responses.
            selineChat = nil

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

    // MARK: - Related Data Fetching

    /// Fetches related data items (events, notes, locations, etc.) based on LLM response content
    /// Only shows items that are ACTUALLY RELEVANT to the response intent
    func fetchRelatedDataForResponse(_ responseText: String) async -> [RelatedDataItem] {
        var relatedItems: [RelatedDataItem] = []
        let lowerResponse = responseText.lowercased()

        // Check if response actually discusses the data type (not just mentioning it in passing)
        // Be conservative - only show items if they're clearly relevant to the response intent

        // MARK: - Events/Calendar Detection (Only if discussing specific events/times)
        let eventKeywords = ["event", "calendar", "meeting", "appointment", "scheduled", "when", "time"]
        let hasEventContext = eventKeywords.contains { keyword in
            // Make sure it's not just passing mention - look for context phrases
            let hasContext = lowerResponse.contains(keyword) &&
                (lowerResponse.contains("you have") || lowerResponse.contains("you're") ||
                 lowerResponse.contains("upcoming") || lowerResponse.contains("next ") ||
                 lowerResponse.contains("scheduled for") || lowerResponse.contains("at "))
            return hasContext
        } || lowerResponse.contains("📅") || lowerResponse.contains("calendar")

        if hasEventContext {

            // Fetch recent/upcoming events from TaskManager
            let taskManager = TaskManager.shared
            let allTasks = taskManager.getAllTasksIncludingArchived()
            let relevantEvents = allTasks
                .filter { task in
                    // Only include events that are from calendar
                    task.isFromCalendar &&
                    // And were created recently or are upcoming
                    {
                        if let targetDate = task.targetDate {
                            return abs(targetDate.timeIntervalSinceNow) < 7 * 24 * 60 * 60  // Last 7 days
                        } else if let scheduledTime = task.scheduledTime {
                            return abs(scheduledTime.timeIntervalSinceNow) < 7 * 24 * 60 * 60
                        } else {
                            return abs(task.createdAt.timeIntervalSinceNow) < 7 * 24 * 60 * 60
                        }
                    }()
                }
                .sorted { (task1, task2) in
                    let date1 = task1.targetDate ?? task1.scheduledTime ?? task1.createdAt
                    let date2 = task2.targetDate ?? task2.scheduledTime ?? task2.createdAt
                    return date1 > date2  // Most recent first
                }
                .prefix(3)

            for task in relevantEvents {
                let eventDate = task.targetDate ?? task.scheduledTime ?? task.createdAt
                relatedItems.append(RelatedDataItem(
                    type: .event,
                    title: task.title,
                    subtitle: task.description?.isEmpty == false ? task.description : nil,
                    date: eventDate
                ))
            }
        }

        // MARK: - Notes Detection (Only if discussing notes specifically)
        let noteKeywords = ["note", "notes", "memo", "reminder", "document"]
        let hasNoteContext = noteKeywords.contains { keyword in
            let hasContext = lowerResponse.contains(keyword) &&
                (lowerResponse.contains("you have") || lowerResponse.contains("saved") ||
                 lowerResponse.contains("found") || lowerResponse.contains("check your") ||
                 lowerResponse.contains("your notes") || lowerResponse.contains("note about"))
            return hasContext
        } || lowerResponse.contains("📝")

        if hasNoteContext {
            let notesManager = NotesManager.shared
            let allNotes = notesManager.notes
            // Get recent notes that might be relevant
            let recentNotes = allNotes
                .sorted { $0.dateCreated > $1.dateCreated }
                .prefix(3)

            for note in recentNotes {
                let contentPreview = String(note.content.prefix(50)).trimmingCharacters(in: .whitespaces)
                relatedItems.append(RelatedDataItem(
                    type: .note,
                    title: note.title,
                    subtitle: contentPreview + (note.content.count > 50 ? "..." : ""),
                    date: note.dateCreated
                ))
            }
        }

        // MARK: - Locations Detection (Only if discussing specific places)
        let locationKeywords = ["location", "place", "visit", "visited", "been to", "went to", "shop", "restaurant", "cafe"]
        let hasLocationContext = locationKeywords.contains { keyword in
            let hasContext = lowerResponse.contains(keyword) &&
                (lowerResponse.contains("you've") || lowerResponse.contains("you've been") ||
                 lowerResponse.contains("you visited") || lowerResponse.contains("near") ||
                 lowerResponse.contains("favorite") || lowerResponse.contains("saved place"))
            return hasContext
        } || lowerResponse.contains("📍")

        if hasLocationContext {
            let locationsManager = LocationsManager.shared
            let savedPlaces = locationsManager.savedPlaces
            // Get recent saved locations
            let recentLocations = savedPlaces
                .sorted { $0.dateCreated > $1.dateCreated }
                .prefix(3)

            for place in recentLocations {
                relatedItems.append(RelatedDataItem(
                    type: .location,
                    title: place.customName ?? place.name,
                    subtitle: place.customName != nil ? place.address : nil,
                    date: place.dateCreated
                ))
            }
        }

        // MARK: - Email Detection (Only if discussing specific emails)
        let emailKeywords = ["email", "mail", "message", "sent", "received", "inbox"]
        let hasEmailContext = emailKeywords.contains { keyword in
            let hasContext = lowerResponse.contains(keyword) &&
                (lowerResponse.contains("you received") || lowerResponse.contains("you have") ||
                 lowerResponse.contains("from ") || lowerResponse.contains("sent you") ||
                 lowerResponse.contains("check your") || lowerResponse.contains("your email"))
            return hasContext
        } || lowerResponse.contains("📧")

        if hasEmailContext {
            let emailService = EmailService.shared
            // Get recent emails from inbox and sent, sorted by date
            var recentEmails = emailService.inboxEmails + emailService.sentEmails
            recentEmails.sort { (email1: Email, email2: Email) in
                email1.timestamp > email2.timestamp
            }

            for email in recentEmails.prefix(3) {
                relatedItems.append(RelatedDataItem(
                    type: .email,
                    title: email.subject.isEmpty ? "No Subject" : email.subject,
                    subtitle: email.sender.displayName,
                    date: email.timestamp
                ))
            }
        }

        // MARK: - Receipts Detection
        if lowerResponse.contains("receipt") || lowerResponse.contains("spent") ||
           lowerResponse.contains("purchase") || lowerResponse.contains("bought") ||
           lowerResponse.contains("cost") || lowerResponse.contains("price") ||
           lowerResponse.contains("$") {

            // Try to fetch receipts - this would depend on your implementation
            // For now, we'll skip as it may not be available
            // Implement this once you have a ReceiptsManager
        }

        return relatedItems
    }

    /// Delete conversation from history
    func deleteConversation(withId id: UUID) {
        let isCurrentlyLoaded = currentlyLoadedConversationId == id

        if let conversation = savedConversations.first(where: { $0.id == id }),
           conversation.kind == .tracker,
           let trackerThreadId = conversation.trackerThreadId {
            trackerStore.deleteThread(id: trackerThreadId)
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
        savedConversations.removeAll()

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
        trackerIds.forEach { trackerStore.deleteThread(id: $0) }
        savedConversations.removeAll { ids.contains($0.id) }

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

        // Clear conversation storage from UserDefaults
        UserDefaults.standard.removeObject(forKey: "SavedConversations")

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
        selineChat = nil
        UserDefaults.standard.removeObject(forKey: "lastConversation")
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
