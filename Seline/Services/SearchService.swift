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
            print("🟦 [SearchService] Question detected, starting conversation: \(trimmedQuery)")
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
            print("🟦 [SearchService] Question type detected via router, starting conversation: \(trimmedQuery)")
            await startConversation(with: trimmedQuery)
            isSearching = false
            return
        }

        isSearching = false
    }

    // MARK: - Action Query Handling

    private func handleActionQuery(_ query: String, actionType: ActionType) async {
        switch actionType {
        case .createEvent:
            pendingEventCreation = await actionQueryHandler.parseEventCreation(from: query)
            searchResults = []
        case .createNote:
            pendingNoteCreation = await actionQueryHandler.parseNoteCreation(from: query)
            searchResults = []
        case .updateNote:
            // Find the note to update
            if let matchingNote = findNoteToUpdate(from: query) {
                // Check if this is a computational/analytical request
                let computationalKeywords = ["sum", "total", "calculate", "add up", "count", "analyze", "summarize", "summarise", "average", "mean", "median", "breakdown", "extract", "compile"]
                let isComputational = computationalKeywords.contains { keyword in
                    query.lowercased().contains(keyword)
                }

                if isComputational {
                    // Use LLM to compute the result
                    let computePrompt = """
                    The user is asking you to process their note and provide a computed result.

                    Current note content:
                    "\(matchingNote.content)"

                    User request: "\(query)"

                    Analyze the note content and fulfill their request. Return ONLY the result/answer they asked for, without explanation. For example:
                    - If they ask "sum up all expenses", return something like "Total: $3,080"
                    - If they ask "count items", return something like "Total items: 5"
                    - If they ask "summarize", provide a concise summary

                    Return the computed result ready to add to the note.
                    """

                    do {
                        let computedResult = try await OpenAIService.shared.generateText(
                            systemPrompt: "You are a note processor. Analyze note content and provide computed results based on user requests.",
                            userPrompt: computePrompt,
                            maxTokens: 500,
                            temperature: 0.0
                        )

                        // Store pending update with computed result
                        pendingNoteUpdate = NoteUpdateData(
                            noteTitle: matchingNote.title,
                            contentToAdd: computedResult,
                            formattedContentToAdd: computedResult
                        )
                    } catch {
                        // Fallback: use regular parsing
                        pendingNoteUpdate = await actionQueryHandler.parseNoteUpdate(
                            from: query,
                            existingNoteTitle: matchingNote.title
                        )
                    }
                } else {
                    // Regular update: parse as before
                    pendingNoteUpdate = await actionQueryHandler.parseNoteUpdate(
                        from: query,
                        existingNoteTitle: matchingNote.title
                    )
                }
                searchResults = []
            } else {
                // Show search results if no matching note found
                let results = await searchContent(query: query.lowercased())
                searchResults = results.sorted { $0.relevanceScore > $1.relevanceScore }
            }
        default:
            // For other action types, show search results for now
            let results = await searchContent(query: query.lowercased())
            searchResults = results.sorted { $0.relevanceScore > $1.relevanceScore }
        }
    }

    /// Finds an event that matches the user's intent to update
    private func findEventToUpdate(from query: String) -> TaskItem? {
        let taskManager = TaskManager.shared
        let lowerQuery = query.lowercased()

        // Try exact title match first
        for (_, taskItems) in taskManager.tasks {
            for taskItem in taskItems {
                if lowerQuery.contains(taskItem.title.lowercased()) {
                    return taskItem
                }
            }
        }

        // Try partial match
        for (_, taskItems) in taskManager.tasks {
            for taskItem in taskItems {
                let words = taskItem.title.lowercased().split(separator: " ")
                for word in words {
                    if lowerQuery.contains(String(word)) && word.count > 3 {
                        return taskItem
                    }
                }
            }
        }

        return nil
    }

    /// Finds a note that matches the user's intent to update
    /// Uses multi-strategy matching: exact match → keyword match → fuzzy match
    private func findNoteToUpdate(from query: String) -> Note? {
        let notesManager = NotesManager.shared
        let lowerQuery = query.lowercased()

        // Strategy 1: Try exact title match first (fastest, highest confidence)
        for note in notesManager.notes {
            if lowerQuery.contains(note.title.lowercased()) {
                print("🎯 [Note Match] Exact title match: \(note.title)")
                return note
            }
        }

        // Strategy 2: Try keyword matching (original method)
        for note in notesManager.notes {
            let words = note.title.lowercased().split(separator: " ")
            for word in words {
                if lowerQuery.contains(String(word)) && word.count > 3 {
                    print("🎯 [Note Match] Keyword match: \(note.title)")
                    return note
                }
            }
        }

        // Strategy 3: Try fuzzy matching (handles typos and variations)
        var bestFuzzyMatch: (note: Note, score: Double)? = nil
        for note in notesManager.notes {
            let similarity = calculateStringSimilarity(lowerQuery, note.title.lowercased())
            // Use 0.7 threshold for fuzzy matching (70% similarity)
            if similarity > 0.7, similarity > (bestFuzzyMatch?.score ?? 0) {
                bestFuzzyMatch = (note, similarity)
            }
        }

        if let fuzzyMatch = bestFuzzyMatch {
            print("🎯 [Note Match] Fuzzy match: \(fuzzyMatch.note.title) (similarity: \(String(format: "%.0f", fuzzyMatch.score * 100))%)")
            return fuzzyMatch.note
        }

        return nil
    }

    /// Calculate string similarity using Levenshtein distance
    /// Returns 0-1 where 1 is identical and 0 is completely different
    private func calculateStringSimilarity(_ str1: String, _ str2: String) -> Double {
        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)

        if maxLength == 0 {
            return 1.0
        }

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein distance between two strings
    /// This is the minimum number of single-character edits (insertions, deletions, substitutions)
    /// needed to transform one string into another
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        let m = s1.count
        let n = s2.count

        // Create a 2D array for dynamic programming
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize base cases
        for i in 0...m {
            dp[i][0] = i
        }
        for j in 0...n {
            dp[0][j] = j
        }

        // Fill the DP table
        for i in 1...m {
            for j in 1...n {
                if s1[i - 1] == s2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(
                        dp[i - 1][j],      // deletion
                        dp[i][j - 1],      // insertion
                        dp[i - 1][j - 1]   // substitution
                    )
                }
            }
        }

        return dp[m][n]
    }

    // MARK: - Question Query Handling

    private func handleQuestionQuery(_ query: String) async {
        isLoadingQuestionResponse = true
        questionResponse = nil
        searchResults = []

        do {
            let response = try await OpenAIService.shared.answerQuestion(
                query: query,
                taskManager: TaskManager.shared,
                notesManager: NotesManager.shared,
                emailService: EmailService.shared,
                weatherService: WeatherService.shared,
                locationsManager: LocationsManager.shared,
                navigationService: NavigationService.shared,
                newsService: NewsService.shared
            )
            questionResponse = response
        } catch {
            questionResponse = "I couldn't answer that question. Please try again or rephrase your question."
            print("Error answering question: \(error)")
        }

        isLoadingQuestionResponse = false
    }

    // MARK: - Note Refinement Mode

    /// Classification for messages during note refinement
    enum RefinementMessageType {
        case addContent
        case exitRefinement
        case metaInstruction
        case confirmUpdate      // User is asking to apply/save/finalize the update
        case ambiguous
    }

    /// Classify a user message during note refinement using semantic understanding
    private func classifyRefinementMessage(_ userInput: String, noteTitle: String) async -> RefinementMessageType {
        let lowerInput = userInput.lowercased().trimmingCharacters(in: .whitespaces)

        // EARLY DETECTION: Check for common patterns BEFORE using LLM
        // This catches simple cases more reliably

        // CONFIRM/APPLY UPDATE: User wants to finalize/apply pending updates
        let confirmUpdatePatterns = [
            "can you update",
            "can you apply",
            "can you save",
            "please update",
            "please apply",
            "go ahead and update",
            "just update",
            "just apply",
            "update it",
            "apply it",
            "save it",
            "finalize",
            "let's update",
            "let's apply"
        ]
        for pattern in confirmUpdatePatterns {
            if lowerInput.contains(pattern) {
                return .confirmUpdate
            }
        }

        // Single word rejections
        if lowerInput == "no" || lowerInput == "nope" || lowerInput == "nah" {
            return .exitRefinement
        }

        // Explicit rejection of adding content to the note
        let rejectionPatterns = [
            "that's a question",
            "that's the question",
            "question to",
            "question for llm",
            "that's not for the note",
            "don't add that",
            "don't add this",
            "that's not a note",
            "that's not note content",
            "ask the llm",
            "ask the ai",
            "just asking",
            "just a question",
            "not note related",
            "not about the note"
        ]

        for pattern in rejectionPatterns {
            if lowerInput.contains(pattern) {
                return .exitRefinement
            }
        }

        // Check for question marks with short responses - likely rejecting the suggestion
        if lowerInput.contains("?") && lowerInput.count < 100 {
            return .exitRefinement
        }

        // Check for explicit exit keywords before LLM call
        let exitKeywords = ["done", "that's it", "finish", "all set", "no more", "that's all", "finished", "complete", "nothing else", "nothing more", "never mind", "scratch that"]
        if exitKeywords.contains(where: { keyword in lowerInput.contains(keyword) }) {
            return .exitRefinement
        }

        let systemPrompt = """
        You are analyzing a user message during interactive note refinement. The user is adding details to a note titled "\(noteTitle)".

        Classify the user's message into ONE of these categories:
        1. "add_content" - User is providing content/details to add to the note (e.g., "add budget info", "include the deadline", specific data or facts)
        2. "exit_refinement" - User wants to stop editing the note OR is rejecting the note editing mode (e.g., "done", "that's it for now", "i'm finished", "no more", "that's all", simple "no", or clarifying this is a general question not note content)
        3. "meta_instruction" - User is asking to modify/remove/change existing note content (e.g., "remove that part", "change the title", "delete the first line")
        4. "ambiguous" - The intent is unclear

        CRITICAL RULES FOR EXIT DETECTION:
        - "No" or "Nope" = exit_refinement (User rejecting the suggestion to add to note)
        - "That's the question" or "That's a question" = exit_refinement (User clarifying they're asking a general question, not editing)
        - "Just asking" = exit_refinement (User clarifying this is conversational, not note editing)
        - Simple rejections or one-word responses after a suggestion = exit_refinement
        - "That's it for now" = exit_refinement
        - "Done with editing" = exit_refinement
        - Messages asking to remove/delete/change content = meta_instruction
        - When user clarifies the message is for the LLM or is a general question = exit_refinement
        - Actual new information or specific details = add_content

        Return ONLY: "add_content", "exit_refinement", "meta_instruction", or "ambiguous"
        """

        do {
            let response = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userInput,
                maxTokens: 10,
                temperature: 0.0
            )

            let classified = response.lowercased().trimmingCharacters(in: .whitespaces)

            if classified.contains("exit") {
                return .exitRefinement
            } else if classified.contains("meta") {
                return .metaInstruction
            } else if classified.contains("add") {
                return .addContent
            } else {
                return .ambiguous
            }
        } catch {
            print("Error classifying refinement message: \(error)")
            // Fallback to simple keyword matching
            return .addContent
        }
    }

    /// Check if user should exit refinement mode based on conversation context
    /// Analyzes recent conversation history to detect if the user is asking a meta-question
    /// or follow-up about a previous action, rather than trying to add content to the note
    private func shouldExitRefinementBasedOnContext(userMessage: String) -> Bool {
        let lowerMessage = userMessage.lowercased()

        // SPECIAL CASE: "Can you..." followed by note action verbs = COMMAND, not exit
        // These are confirmations/commands to apply updates, not meta-questions
        if lowerMessage.contains("can you ") {
            let noteActionVerbs = ["update", "add", "apply", "modify", "change", "delete", "remove", "save", "edit", "append"]
            let isNoteActionCommand = noteActionVerbs.contains { verb in
                lowerMessage.contains("can you " + verb)
            }
            if isNoteActionCommand {
                // This is a command to update the note, not an exit request
                return false
            }
        }

        // PATTERN 1: Meta-question patterns indicating system inquiry, not content addition
        // These are questions about how the system works, not note content
        let metaQuestionPatterns = [
            "update properly",    // "Can you update properly"
            "why ",               // "Why didn't it..."
            "how do",             // "How do I..."
            "can you ",           // "Can you..." (general request for help - only if not a note action)
            "how come",           // "How come..."
            "what went",          // "What went wrong"
            "not working",        // "It's not working"
            "didn't work",        // "Didn't work"
            "not updated",        // "Not updated"
            "don't see",          // "I don't see"
            "where",              // "Where is..."
            "when should",        // "When should..."
            "how can i",          // "How can I..."
        ]

        for pattern in metaQuestionPatterns {
            if lowerMessage.contains(pattern) {
                print("🚪 [Context] Detected meta-question pattern: '\(pattern)'")
                return true
            }
        }

        // PATTERN 2: Check if previous message was a system action confirmation
        // If so, follow-up messages are likely about that action, not new content
        if !conversationHistory.isEmpty {
            let previousMessage = conversationHistory.last!.text.lowercased()

            // System action indicators
            let actionIndicators = ["updated", "created", "added", "modified", "✓"]
            let isLastMessageAction = actionIndicators.contains { indicator in
                previousMessage.contains(indicator)
            }

            // If the last message was a system action and current message is a question
            if isLastMessageAction && lowerMessage.contains("?") {
                print("🚪 [Context] Follow-up question after system action")
                return true
            }

            // If user seems dissatisfied with previous action
            let dissatisfactionPatterns = ["not", "still", "problem", "issue", "wrong", "incorrect", "bad"]
            if isLastMessageAction && dissatisfactionPatterns.contains(where: { pattern in lowerMessage.contains(pattern) }) {
                print("🚪 [Context] User expressing dissatisfaction with previous action")
                return true
            }
        }

        // PATTERN 3: Direct complaints or clarifications
        let complaintPatterns = [
            "i'm confused",
            "help",
            "what do you mean",
            "i don't understand",
            "explain",
            "be more careful",
            "properly",
            "correctly",
            "accurate"
        ]

        for pattern in complaintPatterns {
            if lowerMessage.contains(pattern) && lowerMessage.count < 50 {
                print("🚪 [Context] Detected complaint/clarification: '\(pattern)'")
                return true
            }
        }

        return false
    }

    /// Handle user input when refining a note - update note content interactively
    private func handleNoteRefinement(_ userInput: String, for note: Note) async {
        // Classify the user's message to understand their intent
        let messageType = await classifyRefinementMessage(userInput, noteTitle: note.title)

        switch messageType {
        case .exitRefinement:
            // Exit refinement mode without adding the exit message to note
            isRefiningNote = false
            currentNoteBeingRefined = nil

            // Check if the exit message itself contains a question or is asking for something
            // e.g., "No that's the question to llm" - the user is trying to ask something
            let containsQuestion = userInput.contains("?") ||
                                   userInput.lowercased().contains("question") ||
                                   userInput.lowercased().contains("ask") ||
                                   isQuestion(userInput)

            if containsQuestion {
                // User is exiting refinement AND asking a conversational question
                // Process their message as a general conversational query
                // Extract the actual question part (remove the rejection/clarification)
                var actualQuestion = userInput
                let rejectionPatterns = ["that's a question", "that's the question", "question to", "question for llm", "just asking", "just a question"]

                // Try to extract just the substantive part
                for pattern in rejectionPatterns {
                    if let range = actualQuestion.lowercased().range(of: pattern) {
                        // Remove the pattern but keep the context before it
                        let beforePattern = actualQuestion[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                        // If there's meaningful content before the pattern, use that as the question
                        if !beforePattern.isEmpty && beforePattern != "no" {
                            actualQuestion = beforePattern
                            break
                        }
                    }
                }

                // If we didn't extract a specific question, acknowledge the exit and offer help
                if actualQuestion.trimmingCharacters(in: .whitespaces) == userInput.trimmingCharacters(in: .whitespaces) {
                    let exitMsg = ConversationMessage(
                        isUser: false,
                        text: "✓ Exited note editing. What would you like to know?",
                        intent: .notes
                    )
                    conversationHistory.append(exitMsg)
                } else {
                    // User had a question - let's process it conversationally
                    // Add a note that we're exiting refinement, then process the question
                    let exitMsg = ConversationMessage(
                        isUser: false,
                        text: "✓ Got it, exiting note editing. ",
                        intent: .notes
                    )
                    conversationHistory.append(exitMsg)

                    // Now process the actual question conversationally
                    await startConversation(with: actualQuestion)
                }
            } else {
                // Simple exit, no follow-up question
                let exitMsg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note updated! Is there anything else I can help you with?",
                    intent: .notes
                )
                conversationHistory.append(exitMsg)
            }
            return

        case .metaInstruction:
            // User is asking to modify/remove content from the note
            // Use LLM to understand what to change
            let metaPrompt = """
            The user wants to modify a note titled "\(note.title)".
            Current note content: "\(note.content)"
            User instruction: "\(userInput)"

            Apply the user's requested change to the note content. Return the updated content.
            """

            do {
                let updatedContent = try await OpenAIService.shared.generateText(
                    systemPrompt: "You are a note editor. Apply the user's edits to note content.",
                    userPrompt: metaPrompt,
                    maxTokens: 500,
                    temperature: 0.0
                )

                var updatedNote = note
                updatedNote.content = updatedContent.trimmingCharacters(in: .whitespaces)
                updatedNote.dateModified = Date()

                // CRITICAL: Wait for sync to complete before showing success
                let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(updatedNote)
                currentNoteBeingRefined = updatedNote

                let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "\(statusText) Updated \"\(updatedNote.title)\". The note has been modified as requested. Anything else?",
                    intent: .notes
                )
                conversationHistory.append(confirmationMsg)
            } catch {
                let errorMsg = ConversationMessage(
                    isUser: false,
                    text: "I couldn't apply that change. Could you clarify what you'd like to modify?",
                    intent: .notes
                )
                conversationHistory.append(errorMsg)
            }

        case .confirmUpdate:
            // User is asking to finalize/apply/save the note update
            // This is a request to confirm and exit refinement mode
            isRefiningNote = false
            currentNoteBeingRefined = nil

            // If there's pending content to add, add it now
            if let pendingContent = pendingRefinementContent {
                var updatedNote = note
                let finalContent = updatedNote.content.isEmpty ?
                    pendingContent :
                    updatedNote.content + "\n\n" + pendingContent

                updatedNote.content = finalContent
                updatedNote.dateModified = Date()

                // Save and wait for sync
                let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(updatedNote)
                pendingRefinementContent = nil

                let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "\(statusText) Updated \"\(updatedNote.title)\"",
                    intent: .notes
                )
                conversationHistory.append(confirmationMsg)
            } else {
                // No pending content, just acknowledge the finalization
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note finalized. Is there anything else I can help with?",
                    intent: .notes
                )
                conversationHistory.append(confirmationMsg)
            }
            return

        case .addContent, .ambiguous:
            // Check if user is confirming a pending addition
            let confirmationKeywords = ["yes", "yep", "yup", "yeah", "yea", "sure", "ok", "okay", "go", "add it", "confirm", "please", "do it", "add", "true", "affirmative"]
            let isConfirming = pendingRefinementContent != nil && confirmationKeywords.contains { keyword in
                userInput.lowercased().contains(keyword)
            }

            if isConfirming, let pendingContent = pendingRefinementContent {
                // User confirmed - add the pending content to the note
                var updatedNote = note
                let finalContent = updatedNote.content.isEmpty ?
                    pendingContent :
                    updatedNote.content + "\n\n" + pendingContent

                updatedNote.content = finalContent
                updatedNote.dateModified = Date()

                // Save and wait for sync - CRUCIAL to fetch latest version
                let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(updatedNote)
                currentNoteBeingRefined = updatedNote
                pendingRefinementContent = nil  // Clear pending

                // Show confirmation
                let previewText = pendingContent.count > 200 ? String(pendingContent.prefix(200)) + "..." : pendingContent
                let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "\(statusText) Added to \"\(updatedNote.title)\":\n\n\(previewText)\n\nAnything else?",
                    intent: .notes
                )
                conversationHistory.append(confirmationMsg)
            } else {
                // Check if this is a computational/analytical request
                let computationalKeywords = ["sum", "total", "calculate", "add up", "count", "analyze", "summarize", "summarise", "average", "mean", "median", "breakdown", "extract", "compile"]
                let isComputational = computationalKeywords.contains { keyword in
                    userInput.lowercased().contains(keyword)
                }

                if isComputational {
                    // Use LLM to process the computational request
                    let computePrompt = """
                    The user is asking you to process their note and provide a computed result.

                    Current note content:
                    "\(note.content)"

                    User request: "\(userInput)"

                    Analyze the note content and fulfill their request. Return ONLY the result/answer they asked for, without explanation. For example:
                    - If they ask "sum up all expenses", return something like "Total: $3,080"
                    - If they ask "count items", return something like "Total items: 5"
                    - If they ask "summarize", provide a concise summary

                    Return the computed result ready to add to the note.
                    """

                    do {
                        let computedResult = try await OpenAIService.shared.generateText(
                            systemPrompt: "You are a note processor. Analyze note content and provide computed results based on user requests.",
                            userPrompt: computePrompt,
                            maxTokens: 500,
                            temperature: 0.0
                        )

                        // Store the computed content and ask for confirmation
                        pendingRefinementContent = computedResult

                        // Show what was computed and ask for confirmation
                        let previewText = computedResult.count > 200 ? String(computedResult.prefix(200)) + "..." : computedResult
                        let confirmationMsg = ConversationMessage(
                            isUser: false,
                            text: "I computed this result:\n\n\(previewText)\n\nShould I add this to the note?",
                            intent: .notes
                        )
                        conversationHistory.append(confirmationMsg)
                    } catch {
                        let errorMsg = ConversationMessage(
                            isUser: false,
                            text: "I couldn't process that calculation. Could you rephrase your request?",
                            intent: .notes
                        )
                        conversationHistory.append(errorMsg)
                    }
                } else {
                    // Regular content addition - ask for confirmation before adding
                    // Store the content and ask for confirmation
                    pendingRefinementContent = userInput

                    // Show what will be added and ask for confirmation
                    let previewText = userInput.count > 200 ? String(userInput.prefix(200)) + "..." : userInput
                    let confirmationMsg = ConversationMessage(
                        isUser: false,
                        text: "I'll add this to \"\(note.title)\":\n\n\(previewText)\n\nOK?",
                        intent: .notes
                    )
                    conversationHistory.append(confirmationMsg)
                }
            }
        }
    }

    // MARK: - Conversation Action Handling

    private func handleConversationActionQuery(_ query: String, actionType: ActionType) async {
        switch actionType {
        case .createEvent:
            pendingEventCreation = await actionQueryHandler.parseEventCreation(from: query)
        case .updateEvent:
            // Find the event to update
            if let matchingEvent = findEventToUpdate(from: query) {
                // Parse the updated event details based on the query
                if let updatedEvent = await actionQueryHandler.parseEventCreation(from: query) {
                    // If the parsed event doesn't have a title, use the existing one
                    if updatedEvent.title.isEmpty {
                        // Create a new EventCreationData with the existing event's title
                        let eventWithTitle = EventCreationData(
                            title: matchingEvent.title,
                            description: updatedEvent.description,
                            date: updatedEvent.date,
                            time: updatedEvent.time,
                            endTime: updatedEvent.endTime,
                            recurrenceFrequency: updatedEvent.recurrenceFrequency,
                            isAllDay: updatedEvent.isAllDay,
                            requiresFollowUp: updatedEvent.requiresFollowUp
                        )
                        pendingEventCreation = eventWithTitle
                    } else {
                        pendingEventCreation = updatedEvent
                    }
                }
            } else {
                // If no matching event, ask AI to handle it as a question
                isLoadingQuestionResponse = true
                do {
                    let response = try await OpenAIService.shared.answerQuestion(
                        query: query,
                        taskManager: TaskManager.shared,
                        notesManager: NotesManager.shared,
                        emailService: EmailService.shared,
                        weatherService: WeatherService.shared,
                        locationsManager: LocationsManager.shared,
                        navigationService: NavigationService.shared,
                        newsService: NewsService.shared,
                        conversationHistory: conversationHistory.dropLast()
                    )

                    let assistantMsg = ConversationMessage(isUser: false, text: response, intent: .general)
                    conversationHistory.append(assistantMsg)
                } catch {
                    let errorMsg = ConversationMessage(
                        isUser: false,
                        text: "I couldn't process that request. Please try again.",
                        intent: .general
                    )
                    conversationHistory.append(errorMsg)
                }
                isLoadingQuestionResponse = false
            }
        case .createNote:
            // Parse note creation details
            if let noteData = await actionQueryHandler.parseNoteCreation(from: query) {
                // Create the note immediately
                let newNote = Note(
                    title: noteData.title,
                    content: noteData.content
                )
                NotesManager.shared.addNote(newNote)

                // Enter note refinement mode for interactive updates
                isRefiningNote = true
                currentNoteBeingRefined = newNote

                // Add confirmation message
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "✓ Created note \"\(noteData.title)\"\n\nWhat else would you like to add to this note?",
                    intent: .notes
                )
                conversationHistory.append(confirmationMsg)
            }
        case .updateNote:
            // Find the note to update
            if let matchingNote = findNoteToUpdate(from: query) {
                // Parse the note update content from the conversation
                let updateData = await actionQueryHandler.parseNoteUpdate(
                    from: query,
                    existingNoteTitle: matchingNote.title
                )

                // Auto-apply the note update during conversation
                if let updateData = updateData {
                    var note = matchingNote
                    let originalContent = note.content

                    // Check if this is a computational/analytical request that needs LLM processing
                    let computationalKeywords = ["sum", "total", "calculate", "add up", "count", "analyze", "summarize", "summarise", "average", "mean", "median", "breakdown", "extract", "compile"]
                    let isComputational = computationalKeywords.contains { keyword in
                        query.lowercased().contains(keyword)
                    }

                    var updatedContent: String
                    var delta: String
                    var updateType: String

                    if isComputational {
                        // Use LLM to process the computational request
                        let computePrompt = """
                        The user is asking you to process their note and provide a computed result.

                        Current note content:
                        "\(originalContent)"

                        User request: "\(query)"

                        Analyze the note content and fulfill their request. Return ONLY the result/answer they asked for, without explanation. For example:
                        - If they ask "sum up all expenses", return something like "Total: $3,080"
                        - If they ask "count items", return something like "Total items: 5"
                        - If they ask "summarize", provide a concise summary

                        Return the computed result ready to add to the note.
                        """

                        do {
                            let computedResult = try await OpenAIService.shared.generateText(
                                systemPrompt: "You are a note processor. Analyze note content and provide computed results based on user requests.",
                                userPrompt: computePrompt,
                                maxTokens: 500,
                                temperature: 0.0
                            )

                            // Store pending update and ask for confirmation instead of immediately saving
                            pendingRefinementContent = computedResult

                            // Enter refinement mode and ask for confirmation
                            isRefiningNote = true
                            currentNoteBeingRefined = note

                            let previewText = computedResult.count > 200 ? String(computedResult.prefix(200)) + "..." : computedResult
                            let confirmationMsg = ConversationMessage(
                                isUser: false,
                                text: "I computed this result:\n\n\(previewText)\n\nShould I add this to \"\(note.title)\"?",
                                intent: .notes
                            )
                            conversationHistory.append(confirmationMsg)
                        } catch {
                            let errorMsg = ConversationMessage(
                                isUser: false,
                                text: "I couldn't process that calculation. Could you rephrase your request?",
                                intent: .notes
                            )
                            conversationHistory.append(errorMsg)
                        }
                    } else {
                        // Smart update: add content then have LLM clean up and format the entire note
                        let (content, deltaStr, type) = applySmartNoteUpdate(
                            originalContent: originalContent,
                            suggestedContent: updateData.contentToAdd,
                            query: query
                        )

                        // Now use LLM to clean up and format the entire note nicely
                        let cleanupPrompt = """
                        The user is adding information to their note. Please clean up and format the note content nicely.

                        Current note content:
                        "\(originalContent)"

                        New content being added:
                        "\(deltaStr)"

                        Combined note:
                        "\(content)"

                        Please reformat and organize this note nicely:
                        1. Keep all information from both original and new content
                        2. Organize into logical sections if it makes sense
                        3. Use bullet points or numbering where appropriate
                        4. Clean up formatting and remove redundancy
                        5. Keep the tone consistent with the original
                        6. Return ONLY the formatted note content, nothing else
                        """

                        do {
                            let formattedContent = try await OpenAIService.shared.generateText(
                                systemPrompt: "You are a note formatting assistant. Clean up and organize note content to make it clear and well-structured.",
                                userPrompt: cleanupPrompt,
                                maxTokens: 1000,
                                temperature: 0.3
                            )

                            updatedContent = formattedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            delta = deltaStr
                            updateType = type

                            note.content = updatedContent

                            // Update the note and WAIT for Supabase sync to complete
                            let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(note)

                            // Add confirmation message with delta (only what changed, after sync completes)
                            let deltaPreview = delta.count > 200 ? String(delta.prefix(200)) + "..." : delta
                            let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                            let confirmationMsg = ConversationMessage(
                                isUser: false,
                                text: "\(statusText) \(updateType): \"\(updateData.noteTitle)\"\n\n\(deltaPreview)",
                                intent: .notes
                            )
                            conversationHistory.append(confirmationMsg)
                        } catch {
                            // Fallback: use the content without LLM formatting
                            updatedContent = content
                            delta = deltaStr
                            updateType = type

                            note.content = updatedContent

                            let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(note)

                            let deltaPreview = delta.count > 200 ? String(delta.prefix(200)) + "..." : delta
                            let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                            let confirmationMsg = ConversationMessage(
                                isUser: false,
                                text: "\(statusText) \(updateType): \"\(updateData.noteTitle)\"\n\n\(deltaPreview)",
                                intent: .notes
                            )
                            conversationHistory.append(confirmationMsg)
                        }
                    }
                }
            } else {
                // If no matching note, ask AI to handle it as a question
                isLoadingQuestionResponse = true
                do {
                    let response = try await OpenAIService.shared.answerQuestion(
                        query: query,
                        taskManager: TaskManager.shared,
                        notesManager: NotesManager.shared,
                        emailService: EmailService.shared,
                        weatherService: WeatherService.shared,
                        locationsManager: LocationsManager.shared,
                        navigationService: NavigationService.shared,
                        newsService: NewsService.shared,
                        conversationHistory: conversationHistory.dropLast()
                    )

                    let assistantMsg = ConversationMessage(isUser: false, text: response, intent: .general)
                    conversationHistory.append(assistantMsg)
                } catch {
                    let errorMsg = ConversationMessage(
                        isUser: false,
                        text: "I couldn't process that request. Please try again.",
                        intent: .general
                    )
                    conversationHistory.append(errorMsg)
                }
                isLoadingQuestionResponse = false
            }
        default:
            // For other action types, ask AI to handle it
            isLoadingQuestionResponse = true
            do {
                let response = try await OpenAIService.shared.answerQuestion(
                    query: query,
                    taskManager: TaskManager.shared,
                    notesManager: NotesManager.shared,
                    emailService: EmailService.shared,
                    weatherService: WeatherService.shared,
                    locationsManager: LocationsManager.shared,
                    navigationService: NavigationService.shared,
                    newsService: NewsService.shared,
                    conversationHistory: conversationHistory.dropLast()
                )

                let assistantMsg = ConversationMessage(isUser: false, text: response, intent: .general)
                conversationHistory.append(assistantMsg)
            } catch {
                let errorMsg = ConversationMessage(
                    isUser: false,
                    text: "I couldn't answer that question. Please try again or rephrase your question.",
                    intent: .general
                )
                conversationHistory.append(errorMsg)
            }
            isLoadingQuestionResponse = false
        }
    }

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

            // Process the next action
            await handleConversationActionQuery(nextAction.query, actionType: nextAction.actionType)
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

        // If in conversation mode, add confirmation message
        if isInConversationMode {
            let formattedDate = dateFormatter.string(from: targetDate)
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let timeText = scheduledTime.map { timeFormatter.string(from: $0) } ?? "all day"
            let confirmationMsg = ConversationMessage(
                isUser: false,
                text: "✓ Event created: \"\(eventData.title)\" on \(formattedDate) at \(timeText)",
                intent: .general
            )
            conversationHistory.append(confirmationMsg)
        }

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

        // If in conversation mode, add confirmation message
        if isInConversationMode {
            let confirmationMsg = ConversationMessage(
                isUser: false,
                text: "✓ Note created: \"\(noteData.title)\"",
                intent: .general
            )
            conversationHistory.append(confirmationMsg)
        }

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

            // If in conversation mode, add confirmation message
            if isInConversationMode {
                let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "\(statusText) Note updated: \"\(updateData.noteTitle)\"",
                    intent: .general
                )
                conversationHistory.append(confirmationMsg)
            }
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

    /// Add a message to the conversation and process it
    func addConversationMessage(_ userMessage: String) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        print("🔵 [SearchService] addConversationMessage called with: \(trimmed)")

        // Enter conversation mode if not already in it
        if !isInConversationMode {
            isInConversationMode = true
        }

        // Add user message to history
        let userMsg = ConversationMessage(isUser: true, text: trimmed, intent: .general)
        conversationHistory.append(userMsg)
        print("✅ [SearchService] User message added to history. Total messages: \(conversationHistory.count)")

        // Update title based on conversation context
        updateConversationTitle()

        // CONTEXT-AWARE REFINEMENT EXIT: Check if user should exit refinement based on conversation context
        if isRefiningNote, let noteBeingRefined = currentNoteBeingRefined {
            if shouldExitRefinementBasedOnContext(userMessage: trimmed) {
                print("🔄 [SearchService] User intent suggests exiting refinement mode based on context")
                isRefiningNote = false
                currentNoteBeingRefined = nil
                // Continue processing as normal conversation instead of note refinement
            } else {
                // REFINEMENT MODE: If user is adding details to a note, update it instead
                print("🔄 [SearchService] In refinement mode, handling note refinement")
                await handleNoteRefinement(trimmed, for: noteBeingRefined)
                saveConversationLocally()
                return
            }
        }

        // DISABLED: Multi-action splitting was causing context loss
        // Instead, pass full query to action handlers so they can understand complex requests
        print("ℹ️ [SearchService] Checking for single action with full context...")

        // Check if this is a single action query (create event, create note, etc.) BEFORE sending to AI
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
            // Handle action query in conversation
            await handleConversationActionQuery(trimmed, actionType: actionType)
            saveConversationLocally()
            return
        }

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
        // Initialize new interactive action
        let conversationContext = ConversationActionContext(
            conversationHistory: conversationHistory,
            recentTopics: [],
            lastNoteCreated: nil,
            lastEventCreated: nil
        )

        var action = await conversationActionHandler.startAction(
            from: userMessage,
            actionType: actionType,
            conversationContext: conversationContext
        )

        // Store the action
        currentInteractiveAction = action

        // Add user message to conversation
        await addConversationMessage(userMessage)

        // Get next prompt
        actionPrompt = await conversationActionHandler.getNextPrompt(
            for: action,
            conversationContext: conversationContext
        )
        isWaitingForActionResponse = true
    }

    /// Process a user's response to an action prompt
    func continueConversationalAction(userMessage: String) async {
        guard var action = currentInteractiveAction else { return }

        // Add user message to conversation
        await addConversationMessage(userMessage)

        // Build conversation context
        let conversationContext = ConversationActionContext(
            conversationHistory: conversationHistory,
            recentTopics: [],
            lastNoteCreated: nil,
            lastEventCreated: nil
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
            await addConversationMessage(prompt, isUser: false)
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

        // Get all user messages for context
        let userMessages = conversationHistory.filter { $0.isUser }.map { $0.text }.joined(separator: " | ")

        guard !userMessages.isEmpty else { return }

        do {
            // Use AI to generate a concise summary title
            let userPrompt = """
            Based on this conversation summary, generate a concise 3-5 word title that captures the main topic or action:
            \(userMessages)

            Respond with ONLY the title, no additional text or punctuation.
            """

            let response = try await OpenAIService.shared.generateText(
                systemPrompt: "You are an expert at creating concise, descriptive conversation titles.",
                userPrompt: userPrompt,
                maxTokens: 50,
                temperature: 0.5
            )
            let cleanedTitle = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanedTitle.isEmpty && cleanedTitle.count < 50 {
                conversationTitle = cleanedTitle
            }
        } catch {
            // If AI fails, fall back to last user message
            if let lastUserMessage = conversationHistory.reversed().first(where: { $0.isUser }) {
                let words = lastUserMessage.text.split(separator: " ").prefix(4).joined(separator: " ")
                conversationTitle = String(words.isEmpty ? "Conversation" : words)
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