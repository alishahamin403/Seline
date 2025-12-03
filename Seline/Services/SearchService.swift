import Foundation
import Combine

@MainActor
class SearchService: ObservableObject {
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

    // Conversation state
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var isInConversationMode: Bool = false
    @Published var conversationTitle: String = "New Conversation"
    @Published var savedConversations: [SavedConversation] = []
    @Published var isNewConversation: Bool = false  // Track if this is a new conversation (not loaded from history)
    private var currentlyLoadedConversationId: UUID? = nil

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

    // DEPRECATION: Phase 3 - Disable semantic query system (fallback to direct conversation)
    @Published var useSemanticQueryFallback: Bool = false  // DEPRECATED: Keep disabled, only use if SelineChat fails
    // NOTE: Semantic query system is being phased out in favor of simpler SelineChat approach
    // Reason: Semantic query parsing is complex, error-prone, and the LLM can handle all logic directly

    /// Disable semantic query system completely (Phase 3.2)
    /// Called on initialization to ensure semantic queries are not used
    func disableSemanticQuerySystem() {
        useSemanticQueryFallback = false
    }

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

    private init() {
        // Phase 3.2: Disable semantic query system on initialization
        disableSemanticQuerySystem()

        // Load saved conversations from local storage
        loadConversationHistoryLocally()

        // Auto-refresh search when query changes with debounce
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
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
            if let dateRange = temporalRange, let itemDate = item.date {
                if itemDate < dateRange.startDate || itemDate > dateRange.endDate {
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
                let batchScores = try await OpenAIService.shared.getSemanticSimilarityScores(
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

    // MARK: - Semantic Query Processing (Universal Intent System)

    /// Try to process a query using the semantic query engine first
    /// This handles queries across all app data types, not just expenses
    /// Returns (success, formattedResponse, relatedItems) or nil if semantic query didn't apply
    func processWithSemanticQuery(_ userQuery: String) async -> (text: String, items: [RelatedDataItem])? {
        // Step 1: Generate semantic query from user input
        guard let semanticQuery = await OpenAIService.shared.generateSemanticQuery(from: userQuery) else {
            print("⚠️ Semantic query generation failed, falling back to conversation")
            return nil
        }

        // Check if we have reasonable confidence
        guard semanticQuery.confidence > 0.5 else {
            print("⚠️ Low confidence semantic query (\(String(format: "%.0f%%", semanticQuery.confidence * 100))), falling back to conversation")
            return nil
        }

        // Step 2: Execute the semantic query
        let queryResult = await UniversalQueryExecutor.shared.execute(semanticQuery)

        // Step 3: Format the response intelligently
        let formattedResponse = UniversalResponseFormatter.shared.format(queryResult, rules: semanticQuery.presentation)

        // Step 4: Convert formatted items to RelatedDataItem for UI
        var relatedItems: [RelatedDataItem] = []
        for item in formattedResponse.items {
            // Convert string ID to UUID
            let uuid = UUID(uuidString: item.id) ?? UUID()
            relatedItems.append(RelatedDataItem(
                id: uuid,
                type: mapItemType(item.type),
                title: item.displayTitle,
                subtitle: item.category,
                date: item.date,
                amount: item.amount > 0 ? item.amount : nil,
                merchant: item.merchant
            ))
        }

        print("✅ Semantic query succeeded:")
        print("   Intent: \(semanticQuery.intent)")
        print("   Response: \(formattedResponse.text.prefix(100))...")
        print("   Items to show: \(relatedItems.count)")

        return (text: formattedResponse.text, items: relatedItems)
    }

    /// Map RelatedItem type to RelatedDataItem.DataType
    private func mapItemType(_ type: String) -> RelatedDataItem.DataType {
        switch type {
        case "receipt":
            return .receipt
        case "email":
            return .email
        case "event":
            return .event
        case "note":
            return .note
        case "location":
            return .location
        default:
            return .receipt
        }
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

        // Enter conversation mode if not already in it
        if !isInConversationMode {
            isInConversationMode = true
        }

        // Add user message to history for conversation
        addMessageToHistory(trimmed, isUser: true, intent: .general)

        // Don't update title during new conversations - keep it hidden until saved
        // Only update title for existing conversations
        if !isNewConversation {
            updateConversationTitle()
        }

        // Get AI response with full conversation history for context
        isLoadingQuestionResponse = true
        let thinkStartTime = Date()  // Track when LLM starts thinking

        if useSelineChat {
            // NEW: Use simplified SelineChat approach
            await addConversationMessageWithSelineChat(trimmed, thinkStartTime: thinkStartTime)
        } else {
            // OLD: Use legacy system (fallback)
            await addConversationMessageLegacy(trimmed, thinkStartTime: thinkStartTime)
        }
    }

    // MARK: - SelineChat Implementation (Phase 2)

    /// NEW simplified chat using SelineChat with proper streaming support
    private func addConversationMessageWithSelineChat(_ userMessage: String, thinkStartTime: Date) async {
        // Initialize SelineChat if needed
        if selineChat == nil {
            selineChat = SelineChat(appContext: SelineAppContext(), openAIService: OpenAIService.shared)

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
            }
            return
        }

        // MARK: - Wire up streaming callbacks for real-time UI updates
        let streamingMessageID = UUID()
        var messageAdded = false
        var fullResponse = ""

        // Callback when a streaming chunk arrives
        chat.onStreamingChunk = { [weak self] chunk in
            fullResponse += chunk

            // Dispatch to main thread for UI updates
            DispatchQueue.main.async {
                // Add message on first chunk
                if !messageAdded {
                    let assistantMsg = ConversationMessage(
                        id: streamingMessageID,
                        isUser: false,
                        text: fullResponse,
                        timestamp: Date(),
                        intent: .general,
                        timeStarted: thinkStartTime
                    )
                    self?.conversationHistory.append(assistantMsg)
                    messageAdded = true
                    self?.saveConversationLocally()
                } else {
                    // Update the last message with accumulated response
                    if let lastIndex = self?.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                        let updatedMsg = ConversationMessage(
                            id: streamingMessageID,
                            isUser: false,
                            text: fullResponse,
                            timestamp: self?.conversationHistory[lastIndex].timestamp ?? Date(),
                            intent: self?.conversationHistory[lastIndex].intent ?? .general,
                            timeStarted: self?.conversationHistory[lastIndex].timeStarted
                        )
                        self?.conversationHistory[lastIndex] = updatedMsg
                        self?.saveConversationLocally()
                    }
                }
            }
        }

        // Callback when streaming completes
        chat.onStreamingComplete = { [weak self] in
            DispatchQueue.main.async {
                // Update final message with completion time and fetch related data
                if let lastIndex = self?.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                    let responseText = self?.conversationHistory[lastIndex].text ?? ""

                    // Fetch related data based on response
                    Task {
                        let relatedData = await self?.fetchRelatedDataForResponse(responseText) ?? []

                        DispatchQueue.main.async {
                            if let lastIndex = self?.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                                let finalMsg = ConversationMessage(
                                    id: streamingMessageID,
                                    isUser: false,
                                    text: self?.conversationHistory[lastIndex].text ?? "",
                                    timestamp: self?.conversationHistory[lastIndex].timestamp ?? Date(),
                                    intent: self?.conversationHistory[lastIndex].intent ?? .general,
                                    relatedData: relatedData.isEmpty ? nil : relatedData,
                                    timeStarted: self?.conversationHistory[lastIndex].timeStarted,
                                    timeFinished: Date()
                                )
                                self?.conversationHistory[lastIndex] = finalMsg
                                self?.saveConversationLocally()
                            }
                        }
                    }
                }

                self?.isLoadingQuestionResponse = false
                print("✅ SelineChat streaming completed")
            }
        }

        // Send message through SelineChat (handles both streaming and non-streaming based on enableStreamingResponses)
        let response = await chat.sendMessage(userMessage, streaming: enableStreamingResponses)

        // For non-streaming responses, add message synchronously with related data
        if !enableStreamingResponses {
            let relatedData = await fetchRelatedDataForResponse(response)

            DispatchQueue.main.async {
                let assistantMsg = ConversationMessage(
                    id: UUID(),
                    isUser: false,
                    text: response,
                    timestamp: Date(),
                    intent: .general,
                    relatedData: relatedData.isEmpty ? nil : relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date()
                )
                self.conversationHistory.append(assistantMsg)
                self.isLoadingQuestionResponse = false
                self.saveConversationLocally()
                print("✅ SelineChat response added to history")
            }
        }
    }

    // MARK: - Legacy Implementation (Phase 3: To Be Removed)

    /// OLD legacy chat system (fallback for compatibility)
    /// NOTE: This method is DEPRECATED. Use SelineChat via useSelineChat flag instead.
    /// This fallback is kept for compatibility but should not be used in normal flow.
    private func addConversationMessageLegacy(_ userMessage: String, thinkStartTime: Date) async {
        do {
            // DEPRECATED: Semantic query is disabled by default. Only use if explicitly enabled.
            // The new SelineChat system handles all query types directly without pre-processing.
            var semanticQueryResult: (text: String, items: [RelatedDataItem])? = nil
            if useSemanticQueryFallback {  // Only try if explicitly enabled
                if let result = await processWithSemanticQuery(userMessage) {
                    semanticQueryResult = result
                }
            }

            // STEP 2: If semantic query succeeded, use its response
            if let (responseText, relatedItems) = semanticQueryResult {
                DispatchQueue.main.async {
                    let assistantMsg = ConversationMessage(
                        id: UUID(),
                        isUser: false,
                        text: responseText,
                        timestamp: Date(),
                        intent: .general,
                        relatedData: relatedItems.isEmpty ? nil : relatedItems,
                        timeStarted: thinkStartTime,
                        timeFinished: Date()
                    )
                    self.conversationHistory.append(assistantMsg)
                    self.isLoadingQuestionResponse = false
                    self.saveConversationLocally()
                }
                return
            }

            // STEP 3: Fall back to traditional OpenAI conversation if semantic query failed
            if enableStreamingResponses {
                // Use streaming response
                var fullResponse = ""
                let streamingMessageID = UUID()
                self.streamingMessageID = streamingMessageID
                var messageAdded = false

                try await OpenAIService.shared.answerQuestionWithStreaming(
                    query: userMessage,
                    taskManager: TaskManager.shared,
                    notesManager: NotesManager.shared,
                    emailService: EmailService.shared,
                    weatherService: WeatherService.shared,
                    locationsManager: LocationsManager.shared,
                    navigationService: NavigationService.shared,
                    conversationHistory: Array(conversationHistory.dropLast(1)), // All messages except user message
                    onChunk: { chunk in
                        fullResponse += chunk

                        // MUST dispatch to main thread - streaming chunks come from background thread
                        DispatchQueue.main.async {
                            // Add message on first chunk (don't show empty box)
                            if !messageAdded {
                                let assistantMsg = ConversationMessage(
                                    id: streamingMessageID,
                                    isUser: false,
                                    text: fullResponse,
                                    timestamp: Date(),
                                    intent: .general,
                                    timeStarted: thinkStartTime
                                )
                                self.conversationHistory.append(assistantMsg)
                                messageAdded = true
                            } else {
                                // Update the last message with the accumulated response
                                if let lastIndex = self.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                                    // Since ConversationMessage is immutable, create a new one
                                    let updatedMsg = ConversationMessage(
                                        id: streamingMessageID,
                                        isUser: false,
                                        text: fullResponse,
                                        timestamp: self.conversationHistory[lastIndex].timestamp,
                                        intent: self.conversationHistory[lastIndex].intent,
                                        timeStarted: self.conversationHistory[lastIndex].timeStarted
                                    )
                                    self.conversationHistory[lastIndex] = updatedMsg
                                }
                                self.saveConversationLocally()
                            }
                        }
                    }
                )

                // Mark when LLM finishes thinking (after streaming completes)
                // Also extract any related items (receipts, notes, etc.) from the response
                // Dispatch to main thread to ensure UI updates happen on main thread
                DispatchQueue.main.async {
                    if let lastIndex = self.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
                        // Extract related data from OpenAIService's lastSearchAnswer
                        var relatedData: [RelatedDataItem]? = nil
                        if let searchAnswer = OpenAIService.shared.lastSearchAnswer {
                            var items: [RelatedDataItem] = []

                            // Add related receipts
                            for receipt in searchAnswer.relatedReceipts {
                                items.append(RelatedDataItem(
                                    id: receipt.id,
                                    type: .receipt,
                                    title: receipt.title,
                                    subtitle: receipt.category,
                                    date: receipt.date,
                                    amount: receipt.amount,
                                    merchant: receipt.title
                                ))
                            }

                            if !items.isEmpty {
                                relatedData = items
                            }
                        }

                        let finalMsg = ConversationMessage(
                            id: streamingMessageID,
                            isUser: false,
                            text: self.conversationHistory[lastIndex].text,
                            timestamp: self.conversationHistory[lastIndex].timestamp,
                            intent: self.conversationHistory[lastIndex].intent,
                            relatedData: relatedData,
                            timeStarted: self.conversationHistory[lastIndex].timeStarted,
                            timeFinished: Date()
                        )
                        self.conversationHistory[lastIndex] = finalMsg
                        self.saveConversationLocally()
                    }
                }
            } else {
                // Non-streaming response
                let response = try await OpenAIService.shared.answerQuestion(
                    query: userMessage,
                    taskManager: TaskManager.shared,
                    notesManager: NotesManager.shared,
                    emailService: EmailService.shared,
                    weatherService: WeatherService.shared,
                    locationsManager: LocationsManager.shared,
                    navigationService: NavigationService.shared,
                    conversationHistory: conversationHistory.dropLast() // All messages except the current user message
                )

                // Extract related data from OpenAIService's lastSearchAnswer
                var relatedData: [RelatedDataItem]? = nil
                if let searchAnswer = OpenAIService.shared.lastSearchAnswer {
                    var items: [RelatedDataItem] = []

                    // Add related receipts
                    for receipt in searchAnswer.relatedReceipts {
                        items.append(RelatedDataItem(
                            id: receipt.id,
                            type: .receipt,
                            title: receipt.title,
                            subtitle: receipt.category,
                            date: receipt.date,
                            amount: receipt.amount,
                            merchant: receipt.title
                        ))
                    }

                    if !items.isEmpty {
                        relatedData = items
                    }
                }

                let assistantMsg = ConversationMessage(
                    id: UUID(),
                    isUser: false,
                    text: response,
                    timestamp: Date(),
                    intent: .general,
                    relatedData: relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date()
                )
                conversationHistory.append(assistantMsg)
                saveConversationLocally()
            }
        } catch {
            print("❌ Error in addConversationMessage: \(error)")
            print("❌ Error description: \(error.localizedDescription)")
            let errorMsg = ConversationMessage(
                id: UUID(),
                isUser: false,
                text: "I couldn't answer that question. Please try again or rephrase your question.",
                timestamp: Date(),
                intent: .general
            )
            conversationHistory.append(errorMsg)
            saveConversationLocally()
        }

        isLoadingQuestionResponse = false
    }

    /// Generate quick reply suggestions for follow-up questions
    /// Clear conversation state completely (called when user dismisses conversation modal)
    func clearConversation() {
        // Save to history before clearing (if there's content)
        if !conversationHistory.isEmpty {
            // Check if this is an existing conversation being updated
            if let loadedId = currentlyLoadedConversationId,
               let index = savedConversations.firstIndex(where: { $0.id == loadedId }) {
                // Update existing conversation
                savedConversations[index] = SavedConversation(
                    id: loadedId,
                    title: conversationTitle,
                    messages: conversationHistory,
                    createdAt: savedConversations[index].createdAt
                )
                saveConversationHistoryLocally()
            } else {
                // Create new conversation only if it's not an existing one
                saveConversationToHistory()
            }
        }

        conversationHistory = []
        isInConversationMode = false
        isLoadingQuestionResponse = false
        questionResponse = nil
        conversationTitle = "New Conversation"
        currentlyLoadedConversationId = nil
        isNewConversation = false
    }

    /// Start a new blank conversation (user will type first message)
    func startNewConversation() {
        clearConversation()
        currentlyLoadedConversationId = nil  // Ensure we're not treating this as an existing conversation
        isInConversationMode = true
        isNewConversation = true  // Mark as new conversation (will hide title until finalized)
        updateConversationTitle()
    }

    /// Stop/cancel the currently streaming response
    func stopCurrentRequest() {
        selineChat?.cancelStreaming()
        isLoadingQuestionResponse = false
        print("🛑 User cancelled the response")
    }

    /// Start a conversation with an initial question
    func startConversation(with initialQuestion: String) async {
        startNewConversation()
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
            if let deletionData = conversationActionHandler.compileDeletionData(from: action) {
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
            if let deletionData = conversationActionHandler.compileDeletionData(from: action) {
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
        // Keep title blank - user finds truncated titles unhelpful
        conversationTitle = ""
    }

    /// Generate a conversation title based on the full conversation summary
    /// Called when user exits the conversation
    func generateFinalConversationTitle() async {
        guard !conversationHistory.isEmpty else { return }

        // Build conversation context with both user and AI messages
        var conversationContext = ""
        for message in conversationHistory {
            let speaker = message.isUser ? "User" : "Assistant"
            conversationContext += "\(speaker): \(message.text)\n"
        }

        guard !conversationContext.isEmpty else { return }

        do {
            // First, create a brief summary of the conversation
            let summaryPrompt = """
            Summarize this conversation in 1-2 sentences focusing on the main topic or goal:

            \(conversationContext)

            Respond with ONLY the summary, no additional text.
            """

            let summaryResponse = try await OpenAIService.shared.generateText(
                systemPrompt: "You are an expert at creating concise conversation summaries.",
                userPrompt: summaryPrompt,
                maxTokens: 100,
                temperature: 0.5
            )

            let conversationSummary = summaryResponse.trimmingCharacters(in: .whitespacesAndNewlines)

            // Now generate a smart title based on the summary
            let titlePrompt = """
            Based on this conversation summary, generate a concise 3-6 word title that captures the main topic or action. Make it specific and meaningful:

            Summary: \(conversationSummary)

            Respond with ONLY the title, no additional text, quotes, or punctuation.
            """

            let titleResponse = try await OpenAIService.shared.generateText(
                systemPrompt: "You are an expert at creating concise, descriptive, and smart conversation titles that accurately reflect the conversation content.",
                userPrompt: titlePrompt,
                maxTokens: 50,
                temperature: 0.3
            )

            let cleanedTitle = titleResponse
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")

            if !cleanedTitle.isEmpty && cleanedTitle.count < 60 {
                conversationTitle = cleanedTitle
                return  // Successfully generated a title, return early
            }
        } catch {
            // If AI fails, continue to fallback logic
        }

        // Fallback 1: Try to extract from first user message
        if let firstMessage = conversationHistory.first(where: { $0.isUser }) {
            let words = firstMessage.text.split(separator: " ").prefix(5).joined(separator: " ")
            let fallbackTitle = String(words.isEmpty ? "" : words)
            if !fallbackTitle.isEmpty {
                conversationTitle = fallbackTitle
                return
            }
        }

        // Fallback 2: Extract from first AI message if available
        if let firstAIMessage = conversationHistory.first(where: { !$0.isUser }) {
            let words = firstAIMessage.text.split(separator: " ").prefix(5).joined(separator: " ")
            let fallbackTitle = String(words.isEmpty ? "" : words)
            if !fallbackTitle.isEmpty {
                conversationTitle = fallbackTitle
                return
            }
        }

        // Fallback 3: Use timestamp-based title as last resort
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        conversationTitle = "Chat on \(formatter.string(from: Date()))"
    }

    /// Save conversation to local storage
    private func saveConversationLocally() {
        let defaults = UserDefaults.standard
        do {
            let encoded = try JSONEncoder().encode(conversationHistory)
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
            if let firstUserMessage = conversationHistory.first(where: { $0.isUser }) {
                let words = firstUserMessage.text.split(separator: " ").prefix(4).joined(separator: " ")
                conversationTitle = String(words.isEmpty ? "New Conversation" : words)
            }
        } catch {
            print("❌ Error loading conversation: \(error)")
        }
    }

    /// Save conversation to Supabase
    func saveConversationToSupabase() async {
        guard !conversationHistory.isEmpty else { return }

        do {
            let supabaseManager = SupabaseManager.shared
            let client = await supabaseManager.getPostgrestClient()

            // Prepare conversation data
            var historyJson = "[]"
            if let encoded = try? JSONEncoder().encode(conversationHistory),
               let jsonString = String(data: encoded, encoding: .utf8) {
                historyJson = jsonString
            }

            // Create a struct that conforms to Encodable
            struct ConversationData: Encodable {
                let title: String
                let messages: String
                let message_count: Int
                let first_message: String
                let created_at: String
            }

            let data = ConversationData(
                title: conversationTitle,
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

        let saved = SavedConversation(
            id: UUID(),
            title: conversationTitle,
            messages: conversationHistory,
            createdAt: Date()
        )

        savedConversations.insert(saved, at: 0)  // Add to beginning for chronological order
        saveConversationHistoryLocally()
    }

    /// Load all saved conversations from local storage
    func loadConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "conversationHistory") else { return }

        do {
            savedConversations = try JSONDecoder().decode([SavedConversation].self, from: data)
        } catch {
            print("❌ Error loading conversation history: \(error)")
        }
    }

    /// Save all conversations to local storage
    private func saveConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        do {
            let encoded = try JSONEncoder().encode(savedConversations)
            defaults.set(encoded, forKey: "conversationHistory")
        } catch {
            print("❌ Error saving conversation history: \(error)")
        }
    }

    /// Load specific conversation by ID
    func loadConversation(withId id: UUID) {
        if let saved = savedConversations.first(where: { $0.id == id }) {
            conversationHistory = saved.messages
            conversationTitle = saved.title
            isInConversationMode = true
            isNewConversation = false  // This is a loaded conversation, show title immediately
            currentlyLoadedConversationId = id  // Track which conversation is loaded

            // Restore the note being edited from conversation context
            restoreNoteContextFromConversation()

            // Process any pending note updates from historical conversations
            Task {
                await processPendingNoteUpdatesInHistory()
            }
        }
    }

    /// Restore which note was being edited by scanning conversation for note updates
    private func restoreNoteContextFromConversation() {
        let notesManager = NotesManager.shared

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
    func fetchRelatedDataForResponse(_ responseText: String) async -> [RelatedDataItem] {
        var relatedItems: [RelatedDataItem] = []
        let lowerResponse = responseText.lowercased()

        // MARK: - Events/Calendar Detection
        if lowerResponse.contains("event") || lowerResponse.contains("calendar") ||
           lowerResponse.contains("meeting") || lowerResponse.contains("appointment") ||
           lowerResponse.contains("scheduled") || lowerResponse.contains("time") {

            // Fetch recent/upcoming events from TaskManager
            let taskManager = TaskManager.shared
            let allTasks = taskManager.tasks.values.flatMap { $0 }
            let relevantEvents = allTasks
                .filter { task in
                    // Only include events that are from calendar
                    task.isFromCalendar &&
                    // And were created recently or are upcoming
                    (abs(task.dueDate.timeIntervalSinceNow) < 7 * 24 * 60 * 60)  // Last 7 days
                }
                .prefix(3)

            for task in relevantEvents {
                relatedItems.append(RelatedDataItem(
                    type: .event,
                    title: task.title,
                    subtitle: task.description?.isEmpty == false ? task.description : nil,
                    date: task.dueDate
                ))
            }
        }

        // MARK: - Notes Detection
        if lowerResponse.contains("note") || lowerResponse.contains("notes") ||
           lowerResponse.contains("memo") || lowerResponse.contains("reminder") {

            let notesManager = NotesManager.shared
            let allNotes = notesManager.notes
            // Get recent notes that might be relevant
            let recentNotes = allNotes
                .sorted { $0.createdDate > $1.createdDate }
                .prefix(3)

            for note in recentNotes {
                relatedItems.append(RelatedDataItem(
                    type: .note,
                    title: note.title,
                    subtitle: note.content.prefix(50).trimmingCharacters(in: .whitespaces) + (note.content.count > 50 ? "..." : ""),
                    date: note.createdDate
                ))
            }
        }

        // MARK: - Locations Detection
        if lowerResponse.contains("location") || lowerResponse.contains("place") ||
           lowerResponse.contains("visited") || lowerResponse.contains("been to") ||
           lowerResponse.contains("went to") || lowerResponse.contains("@") {

            let locationsManager = LocationsManager.shared
            let savedLocations = locationsManager.savedLocations
            // Get recent saved locations
            let recentLocations = savedLocations
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3)

            for location in recentLocations {
                relatedItems.append(RelatedDataItem(
                    type: .location,
                    title: location.customName ?? location.address,
                    subtitle: location.customName != nil ? location.address : nil,
                    date: location.timestamp
                ))
            }
        }

        // MARK: - Email Detection
        if lowerResponse.contains("email") || lowerResponse.contains("mail") ||
           lowerResponse.contains("message") || lowerResponse.contains("sent") {

            let emailService = EmailService.shared
            if let emails = await emailService.fetchRecentEmails(limit: 3) {
                for email in emails {
                    relatedItems.append(RelatedDataItem(
                        type: .email,
                        title: email.subject ?? "No Subject",
                        subtitle: email.from,
                        date: email.date
                    ))
                }
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
        savedConversations.removeAll { $0.id == id }
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
        isNewConversation = false
        currentlyLoadedConversationId = nil
        cancellables.removeAll()

        // Clear conversation storage from UserDefaults
        UserDefaults.standard.removeObject(forKey: "SavedConversations")

        print("🗑️ Cleared all search and conversation data on logout")
    }
}

// MARK: - Saved Conversation Model

struct SavedConversation: Identifiable, Codable {
    let id: UUID
    let title: String
    let messages: [ConversationMessage]
    let createdAt: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}