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

    // Note refinement mode - for interactive note creation/updating
    @Published var isRefiningNote: Bool = false
    @Published var currentNoteBeingRefined: Note? = nil

    private var searchableProviders: [TabSelection: Searchable] = [:]
    private var cachedContent: [SearchableItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let queryRouter = QueryRouter.shared
    private let actionQueryHandler = ActionQueryHandler.shared

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
            await handleActionQuery(trimmedQuery, actionType: actionType)
        case .search:
            let results = await searchContent(query: trimmedQuery.lowercased())
            searchResults = results.sorted { $0.relevanceScore > $1.relevanceScore }
        case .question:
            // Handle questions with AI assistance (only if not detected as conversation question)
            await handleQuestionQuery(trimmedQuery)
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
                pendingNoteUpdate = await actionQueryHandler.parseNoteUpdate(
                    from: query,
                    existingNoteTitle: matchingNote.title
                )
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
    private func findNoteToUpdate(from query: String) -> Note? {
        let notesManager = NotesManager.shared
        let lowerQuery = query.lowercased()

        // Try exact title match first
        for note in notesManager.notes {
            if lowerQuery.contains(note.title.lowercased()) {
                return note
            }
        }

        // Try partial match
        for note in notesManager.notes {
            let words = note.title.lowercased().split(separator: " ")
            for word in words {
                if lowerQuery.contains(String(word)) && word.count > 3 {
                    return note
                }
            }
        }

        return nil
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
        case ambiguous
    }

    /// Classify a user message during note refinement using semantic understanding
    private func classifyRefinementMessage(_ userInput: String, noteTitle: String) async -> RefinementMessageType {
        let systemPrompt = """
        You are analyzing a user message during interactive note refinement. The user is adding details to a note titled "\(noteTitle)".

        Classify the user's message into ONE of these categories:
        1. "add_content" - User is providing content/details to add to the note (e.g., "add budget info", "include the deadline")
        2. "exit_refinement" - User wants to stop editing the note (e.g., "done", "that's it for now", "i'm finished", "no more", "that's all")
        3. "meta_instruction" - User is asking to modify/remove/change existing note content (e.g., "remove that part", "change the title", "delete the first line")
        4. "ambiguous" - The intent is unclear

        CRITICAL RULES:
        - "That's it for now" = exit_refinement (NOT add_content)
        - "Done with editing" = exit_refinement (NOT add_content)
        - Messages that ask to remove/delete/change content = meta_instruction (NOT add_content)
        - Brief affirmations like "yes", "ok", "sure" in context of exiting = exit_refinement
        - Actual new information or details = add_content

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
            let lowerInput = userInput.lowercased()
            let exitKeywords = ["done", "that's it", "finish", "all set", "no more", "that's all", "no more", "finished", "complete"]
            let exitDetected = exitKeywords.contains { keyword in lowerInput.contains(keyword) }
            return exitDetected ? .exitRefinement : .addContent
        }
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

            let exitMsg = ConversationMessage(
                isUser: false,
                text: "✓ Note updated! Is there anything else I can help you with?",
                intent: .notes
            )
            conversationHistory.append(exitMsg)
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

                NotesManager.shared.updateNote(updatedNote)
                currentNoteBeingRefined = updatedNote

                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "✓ Updated \"\(updatedNote.title)\". The note has been modified as requested. Anything else?",
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

        case .addContent, .ambiguous:
            // Update the note with new content
            var updatedNote = note
            let (updatedContent, delta, _) = applySmartNoteUpdate(
                originalContent: updatedNote.content,
                suggestedContent: userInput,
                query: userInput
            )

            updatedNote.content = updatedContent
            updatedNote.dateModified = Date()

            // Save the updated note and WAIT for Supabase sync to complete
            let updateSuccess = await NotesManager.shared.updateNoteAndWaitForSync(updatedNote)
            currentNoteBeingRefined = updatedNote

            // Show confirmation with what was added (only after save completes)
            let deltaPreview = delta.count > 200 ? String(delta.prefix(200)) + "..." : delta
            let statusText = updateSuccess ? "✓" : "⚠️ (Save in progress)"
            let confirmationMsg = ConversationMessage(
                isUser: false,
                text: "\(statusText) Added to \"\(updatedNote.title)\":\n\n\(deltaPreview)\n\nAnything else?",
                intent: .notes
            )
            conversationHistory.append(confirmationMsg)
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

                    // Smart update: detect if this is a replacement or addition
                    let (updatedContent, delta, updateType) = applySmartNoteUpdate(
                        originalContent: originalContent,
                        suggestedContent: updateData.contentToAdd,
                        query: query
                    )

                    note.content = updatedContent

                    // Update the note immediately
                    NotesManager.shared.updateNote(note)

                    // Add confirmation message with delta (only what changed)
                    let deltaPreview = delta.count > 200 ? String(delta.prefix(200)) + "..." : delta
                    let confirmationMsg = ConversationMessage(
                        isUser: false,
                        text: "✓ \(updateType): \"\(updateData.noteTitle)\"\n\n\(deltaPreview)",
                        intent: .notes
                    )
                    conversationHistory.append(confirmationMsg)
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
    }

    func confirmNoteUpdate() {
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
            // Update the note
            notesManager.updateNote(note)

            // If in conversation mode, add confirmation message
            if isInConversationMode {
                let confirmationMsg = ConversationMessage(
                    isUser: false,
                    text: "✓ Note updated: \"\(updateData.noteTitle)\"",
                    intent: .general
                )
                conversationHistory.append(confirmationMsg)
            }
        }

        // Clear pending data
        pendingNoteUpdate = nil
    }

    func cancelAction() {
        let hasAction = pendingEventCreation != nil || pendingNoteCreation != nil || pendingNoteUpdate != nil

        pendingEventCreation = nil
        pendingNoteCreation = nil
        pendingNoteUpdate = nil

        // If in conversation mode and had a pending action, add cancellation message
        if isInConversationMode && hasAction {
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

        return cachedContent.compactMap { item in
            let searchText = item.searchText.lowercased()
            let score = calculateRelevanceScore(searchText: searchText, queryWords: queryWords)

            if score > 0 {
                let matchedText = findMatchedText(in: item, queryWords: queryWords)
                return SearchResult(
                    item: item,
                    relevanceScore: score,
                    matchedText: matchedText
                )
            }
            return nil
        }
    }

    private func calculateRelevanceScore(searchText: String, queryWords: [String]) -> Double {
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

        return score
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

        // Enter conversation mode if not already in it
        if !isInConversationMode {
            isInConversationMode = true
        }

        // Add user message to history
        let userMsg = ConversationMessage(isUser: true, text: trimmed, intent: .general)
        conversationHistory.append(userMsg)

        // Update title based on conversation context
        updateConversationTitle()

        // REFINEMENT MODE: If user is adding details to a note, update it instead
        if isRefiningNote, let noteBeingRefined = currentNoteBeingRefined {
            await handleNoteRefinement(trimmed, for: noteBeingRefined)
            saveConversationLocally()
            return
        }

        // Check if this is an action query (create event, create note, etc.) BEFORE sending to AI
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

            // Process any pending note updates from historical conversations
            Task {
                await processPendingNoteUpdatesInHistory()
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

                            // Update the note
                            notesManager.updateNote(note)

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