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

        // Classify the query
        currentQueryType = queryRouter.classifyQuery(trimmedQuery)

        // Handle based on query type
        switch currentQueryType {
        case .action(let actionType):
            // Use new conversational action system
            isInConversationMode = true
            await startConversationalAction(userMessage: trimmedQuery, actionType: actionType)
        case .search:
            let results = await searchContent(query: trimmedQuery.lowercased())
            searchResults = results.sorted { $0.relevanceScore > $1.relevanceScore }
        case .question:
            // This should rarely happen now since questions are caught above
            // But if it does, send to conversation
            await startConversation(with: trimmedQuery)
            isSearching = false
            return
        }

        isSearching = false
    }

    // MARK: - Action Query Handling

    // MARK: - Multi-Action Helper

    private func processNextMultiAction() async {
        // Check if there are more actions to process
        let nextIndex = currentMultiActionIndex + 1
        if nextIndex < pendingMultiActions.count {
            currentMultiActionIndex = nextIndex
            let nextAction = pendingMultiActions[nextIndex]

            // Add a separator message
            let separatorMsg = ConversationMessage(
                isUser: false,
                text: "Processing next action...",
                intent: .general
            )
            conversationHistory.append(separatorMsg)

            // Process the next action with new conversational system
            await startConversationalAction(userMessage: nextAction.query, actionType: nextAction.actionType)
            saveConversationLocally()
        } else {
            // All actions completed
            let completionMsg = ConversationMessage(
                isUser: false,
                text: "✓ All actions completed!",
                intent: .general
            )
            conversationHistory.append(completionMsg)

            // Clear multi-action state
            pendingMultiActions = []
            currentMultiActionIndex = 0
            originalMultiActionQuery = ""
            saveConversationLocally()
        }
    }

    // MARK: - Action Confirmation Methods

    func confirmEventCreation() {
        guard let eventData = pendingEventCreation else { return }

        let taskManager = TaskManager.shared

        // Parse the date and time
        let dateFormatter = ISO8601DateFormatter()
        let targetDate = dateFormatter.date(from: eventData.date) ?? Date()

        // Parse the time properly - extract hours and minutes from time string
        let calendar = Calendar.current
        var scheduledTime: Date? = nil
        if let timeStr = eventData.time, !timeStr.isEmpty {
            // Try multiple time format parsers
            let timeFormatters: [DateFormatter] = {
                let f1 = DateFormatter()
                f1.dateFormat = "HH:mm"  // 24-hour format (15:00)

                let f2 = DateFormatter()
                f2.dateFormat = "h:mm a" // 12-hour format (3:00 PM)

                let f3 = DateFormatter()
                f3.timeStyle = .short    // System short time
                f3.dateStyle = .none

                return [f1, f2, f3]
            }()

            // Try each formatter until one succeeds
            for formatter in timeFormatters {
                if let parsedTime = formatter.date(from: timeStr) {
                    // Extract hour and minute from parsed time
                    let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)

                    // Create a new date with the target date but the parsed time
                    if let scheduledDate = calendar.date(
                        bySettingHour: timeComponents.hour ?? 0,
                        minute: timeComponents.minute ?? 0,
                        second: 0,
                        of: targetDate
                    ) {
                        scheduledTime = scheduledDate
                        break
                    }
                }
            }
        }

        // Determine the weekday from the date
        let weekdayIndex = calendar.component(.weekday, from: targetDate)

        let weekday: WeekDay
        switch weekdayIndex {
        case 1: weekday = .sunday
        case 2: weekday = .monday
        case 3: weekday = .tuesday
        case 4: weekday = .wednesday
        case 5: weekday = .thursday
        case 6: weekday = .friday
        case 7: weekday = .saturday
        default: weekday = .monday
        }

        // Create the task
        taskManager.addTask(
            title: eventData.title,
            to: weekday,
            description: eventData.description,
            scheduledTime: scheduledTime,
            endTime: nil,
            targetDate: targetDate,
            reminderTime: .none,
            isRecurring: false,
            recurrenceFrequency: nil,
            tagId: nil
        )

        // Store context for follow-up actions (e.g., "move the event to today")
        lastCreatedEventTitle = eventData.title
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateStyle = .medium
        lastCreatedEventDate = displayDateFormatter.string(from: targetDate)

        // Clear pending data
        pendingEventCreation = nil

        // Check if there are more multi-actions to process
        Task {
            await processNextMultiAction()
        }
    }

    func confirmNoteCreation() {
        guard let noteData = pendingNoteCreation else { return }

        let notesManager = NotesManager.shared
        let note = Note(title: noteData.title, content: noteData.content)
        notesManager.addNote(note)

        // Store context for follow-up actions
        lastCreatedNoteTitle = noteData.title

        // Clear pending data
        pendingNoteCreation = nil

        // Check if there are more multi-actions to process
        Task {
            await processNextMultiAction()
        }
    }

    func confirmNoteUpdate() {
        Task {
            await confirmNoteUpdateAsync()
        }
    }

    /// Async version of confirmNoteUpdate that waits for sync to complete
    private func confirmNoteUpdateAsync() async {
        guard let updateData = pendingNoteUpdate else { return }

        let notesManager = NotesManager.shared

        // Find the note to update
        if let index = notesManager.notes.firstIndex(where: { $0.title == updateData.noteTitle }) {
            var note = notesManager.notes[index]
            // Append the new content to existing content
            if !note.content.isEmpty {
                note.content += "\n\n" + updateData.contentToAdd
            } else {
                note.content = updateData.contentToAdd
            }
            note.dateModified = Date()

            // CRITICAL: Wait for sync to complete before showing success message
            let updateSuccess = await notesManager.updateNoteAndWaitForSync(note)
        }

        // Clear pending data
        pendingNoteUpdate = nil

        // Check if there are more multi-actions to process
        await processNextMultiAction()
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

        // Get semantic similarity scores for all items
        let semanticScores = await getSemanticSimilarityScores(query: query, for: cachedContent)

        for item in cachedContent {
            // TEMPORAL FILTERING: Skip items outside the requested date range
            if let dateRange = temporalRange, let itemDate = item.date {
                if itemDate < dateRange.startDate || itemDate > dateRange.endDate {
                    continue  // Skip this item, it's outside the time range
                }
            }

            let searchText = item.searchText.lowercased()
            let keywordScore = calculateRelevanceScore(
                searchText: searchText,
                queryWords: queryWords,
                item: item,
                relatedItemTitles: relatedItemTitles
            )

            // Get semantic score for this item
            let semanticScore = semanticScores[item.identifier] ?? 0.0

            // CONVERSATION CONTEXT BOOST: Boost items related to current topic
            let contextBoost = ConversationContextService.shared.getContextBoost(for: item.tags)

            // Combine all scoring factors:
            // 70% keyword-based, 30% semantic similarity, + context boost
            var combinedScore = (keywordScore * 0.7) + (semanticScore * 0.3) + contextBoost

            if combinedScore > 0 {
                let matchedText = findMatchedText(in: item, queryWords: queryWords)
                results.append(SearchResult(
                    item: item,
                    relevanceScore: combinedScore,
                    matchedText: matchedText
                ))
            }
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
                print("⚠️ Error getting semantic scores: \(error)")
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

        // Check if this is a single action query (create event, create note, etc.)
        var queryType = queryRouter.classifyQuery(trimmed)

        // If keyword matching didn't detect action, try semantic classification
        if case .action = queryType {
            // Action detected via keywords
        } else {
            // Try semantic LLM fallback for ambiguous cases
            if let semanticAction = await queryRouter.classifyIntentWithLLM(trimmed) {
                queryType = .action(semanticAction)
            }
        }

        if case .action(let actionType) = queryType {
            // Handle action query with new conversational system
            if currentInteractiveAction != nil {
                // Continue existing action - message will be added in continueConversationalAction
                await continueConversationalAction(userMessage: trimmed)
            } else {
                // Start new action - message will be added in startConversationalAction
                await startConversationalAction(userMessage: trimmed, actionType: actionType)
            }
            saveConversationLocally()
            return
        }

        // Not an action - add user message to history for normal conversation
        addMessageToHistory(trimmed, isUser: true, intent: .general)

        // Update title based on conversation context
        updateConversationTitle()

        // Get AI response with full conversation history for context
        isLoadingQuestionResponse = true
        do {
            let response = try await OpenAIService.shared.answerQuestion(
                query: trimmed,
                taskManager: TaskManager.shared,
                notesManager: NotesManager.shared,
                emailService: EmailService.shared,
                weatherService: WeatherService.shared,
                locationsManager: LocationsManager.shared,
                navigationService: NavigationService.shared,
                newsService: NewsService.shared,
                conversationHistory: conversationHistory.dropLast() // All messages except the current user message
            )

            let assistantMsg = ConversationMessage(isUser: false, text: response, intent: .general)
            conversationHistory.append(assistantMsg)
            saveConversationLocally()
        } catch {
            let errorMsg = ConversationMessage(
                isUser: false,
                text: "I couldn't answer that question. Please try again or rephrase your question.",
                intent: .general
            )
            conversationHistory.append(errorMsg)
            saveConversationLocally()
        }

        isLoadingQuestionResponse = false
    }

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
    }

    /// Start a conversation with an initial question
    func startConversation(with initialQuestion: String) async {
        clearConversation()
        currentlyLoadedConversationId = nil  // Ensure we're not treating this as an existing conversation
        isInConversationMode = true
        updateConversationTitle()
        await addConversationMessage(initialQuestion)
    }

    // MARK: - Conversational Action System

    /// Start a new conversational action from a user's initial message
    func startConversationalAction(
        userMessage: String,
        actionType: ActionType
    ) async {
        // Add user message directly to history without reprocessing
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        addMessageToHistory(trimmed, isUser: true)

        // Initialize new interactive action
        let conversationContext = ConversationActionContext(
            conversationHistory: conversationHistory,
            recentTopics: [],
            lastNoteCreated: lastCreatedNoteTitle,
            lastEventCreated: lastCreatedEventTitle
        )

        var action = await conversationActionHandler.startAction(
            from: userMessage,
            actionType: actionType,
            conversationContext: conversationContext
        )

        // Store the action
        currentInteractiveAction = action

        // Get next prompt
        let prompt = await conversationActionHandler.getNextPrompt(
            for: action,
            conversationContext: conversationContext
        )

        // Add the initial prompt to conversation history so user can see it
        if !prompt.isEmpty {
            let promptMsg = ConversationMessage(isUser: false, text: prompt, intent: .general)
            conversationHistory.append(promptMsg)
        }

        actionPrompt = prompt
        isWaitingForActionResponse = true
    }

    /// Process a user's response to an action prompt
    func continueConversationalAction(userMessage: String) async {
        guard var action = currentInteractiveAction else { return }

        // Add user message directly to history without reprocessing
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        addMessageToHistory(trimmed, isUser: true)

        // Build conversation context
        let conversationContext = ConversationActionContext(
            conversationHistory: conversationHistory,
            recentTopics: [],
            lastNoteCreated: lastCreatedNoteTitle,
            lastEventCreated: lastCreatedEventTitle
        )

        // Process the response
        action = await conversationActionHandler.processUserResponse(
            userMessage,
            to: action,
            currentStep: actionPrompt ?? "",
            conversationContext: conversationContext
        )

        currentInteractiveAction = action

        // Check if ready to save
        if conversationActionHandler.isReadyToSave(action) {
            await executeConversationalAction(action)
            return
        }

        // Get next prompt
        actionPrompt = await conversationActionHandler.getNextPrompt(
            for: action,
            conversationContext: conversationContext
        )

        // Add assistant response
        if let prompt = actionPrompt {
            let assistantMsg = ConversationMessage(isUser: false, text: prompt, intent: .general)
            conversationHistory.append(assistantMsg)
        }
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
    private func updateConversationTitle() {
        guard !conversationHistory.isEmpty else {
            conversationTitle = "New Conversation"
            return
        }

        // If we have multiple messages, use recent context for better title
        if conversationHistory.count >= 4 {
            // Get the last user message for context
            if let lastUserMessage = conversationHistory.reversed().first(where: { $0.isUser }) {
                let words = lastUserMessage.text.split(separator: " ").prefix(4).joined(separator: " ")
                let newTitle = String(words.isEmpty ? "Conversation" : words)

                // Only update if it's meaningfully different
                if newTitle != conversationTitle {
                    conversationTitle = newTitle
                }
                return
            }
        }

        // Fall back to first user message for new conversations
        if let firstUserMessage = conversationHistory.first(where: { $0.isUser }) {
            let words = firstUserMessage.text.split(separator: " ").prefix(4).joined(separator: " ")
            conversationTitle = String(words.isEmpty ? "New Conversation" : words)
        } else {
            conversationTitle = "New Conversation"
        }
    }

    /// Generate a conversation title based on the full conversation summary
    /// Called when user exits the conversation
    func generateFinalConversationTitle() async {
        guard conversationHistory.count >= 2 else { return }

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

            if !cleanedTitle.isEmpty && cleanedTitle.count < 60 && !cleanedTitle.contains("conversation") {
                conversationTitle = cleanedTitle
                print("✓ Generated title: \(cleanedTitle)")
            } else if !cleanedTitle.isEmpty && cleanedTitle.count < 60 {
                conversationTitle = cleanedTitle
            }
        } catch {
            // If AI fails, fall back to creating a title from first and last user message
            if let firstMessage = conversationHistory.first(where: { $0.isUser }) {
                let words = firstMessage.text.split(separator: " ").prefix(5).joined(separator: " ")
                conversationTitle = String(words.isEmpty ? "Conversation" : words)
                print("⚠ Fallback title: \(conversationTitle)")
            }
        }
    }

    /// Save conversation to local storage
    private func saveConversationLocally() {
        let defaults = UserDefaults.standard
        do {
            let encoded = try JSONEncoder().encode(conversationHistory)
            defaults.set(encoded, forKey: "lastConversation")
        } catch {
            print("Error saving conversation locally: \(error)")
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
            print("Error loading conversation: \(error)")
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

            print("✓ Conversation saved to Supabase")
        } catch {
            print("Error saving conversation to Supabase: \(error)")
        }
    }

    /// Load conversations from Supabase (requires conversations table to be created)
    /// Currently disabled - can be implemented once Supabase table is fully set up
    /// For now, conversations are loaded from local UserDefaults via loadLastConversation()
    func loadConversationsFromSupabase() async -> [[String: Any]] {
        // To implement this:
        // 1. Create the conversations table in Supabase (using provided SQL)
        // 2. Use direct HTTP request or update Supabase SDK implementation
        print("Note: Load conversations from Supabase not yet implemented. Use Supabase dashboard to view saved conversations.")
        return []
    }

    /// Load specific conversation from Supabase by ID
    /// Currently disabled - can be implemented once proper SDK support is available
    func loadConversationFromSupabase(id: String) async {
        print("Note: Load conversation from Supabase not yet implemented. Use loadLastConversation() for local persistence.")
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
            print("Error loading conversation history: \(error)")
        }
    }

    /// Save all conversations to local storage
    private func saveConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        do {
            let encoded = try JSONEncoder().encode(savedConversations)
            defaults.set(encoded, forKey: "conversationHistory")
        } catch {
            print("Error saving conversation history: \(error)")
        }
    }

    /// Load specific conversation by ID
    func loadConversation(withId id: UUID) {
        if let saved = savedConversations.first(where: { $0.id == id }) {
            conversationHistory = saved.messages
            conversationTitle = saved.title
            isInConversationMode = true
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
                            print("✅ Applied pending note update for: \(noteTitle)")
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
        savedConversations.removeAll { $0.id == id }
        saveConversationHistoryLocally()
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