import Foundation
import Combine

// MARK: - Conversation Message Model

struct ConversationMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date = Date()
}

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

    private var searchableProviders: [TabSelection: Searchable] = [:]
    private var cachedContent: [SearchableItem] = []
    private var cancellables = Set<AnyCancellable>()
    private let queryRouter = QueryRouter.shared
    private let actionQueryHandler = ActionQueryHandler.shared

    private init() {
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

        isSearching = true

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

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
            // Handle questions with AI assistance
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
                navigationService: NavigationService.shared
            )
            questionResponse = response
        } catch {
            questionResponse = "I couldn't answer that question. Please try again or rephrase your question."
            print("Error answering question: \(error)")
        }

        isLoadingQuestionResponse = false
    }

    // MARK: - Action Confirmation Methods

    func confirmEventCreation() {
        guard let eventData = pendingEventCreation else { return }

        let taskManager = TaskManager.shared

        // Parse the date and time
        let dateFormatter = ISO8601DateFormatter()
        let targetDate = dateFormatter.date(from: eventData.date) ?? Date()

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let scheduledTime = (eventData.time ?? "").isEmpty ? nil : timeFormatter.date(from: eventData.time ?? "")

        // Determine the weekday from the date
        let calendar = Calendar.current
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

        // Clear pending data
        pendingEventCreation = nil
    }

    func confirmNoteCreation() {
        guard let noteData = pendingNoteCreation else { return }

        let notesManager = NotesManager.shared
        let note = Note(title: noteData.title, content: noteData.content)
        notesManager.addNote(note)

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
        }

        // Clear pending data
        pendingNoteUpdate = nil
    }

    func cancelAction() {
        pendingEventCreation = nil
        pendingNoteCreation = nil
        pendingNoteUpdate = nil
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
        let userMsg = ConversationMessage(content: trimmed, isUser: true)
        conversationHistory.append(userMsg)

        // Get AI response
        isLoadingQuestionResponse = true
        do {
            let response = try await OpenAIService.shared.answerQuestion(
                query: trimmed,
                taskManager: TaskManager.shared,
                notesManager: NotesManager.shared,
                emailService: EmailService.shared,
                weatherService: WeatherService.shared,
                locationsManager: LocationsManager.shared,
                navigationService: NavigationService.shared
            )

            let assistantMsg = ConversationMessage(content: response, isUser: false)
            conversationHistory.append(assistantMsg)
        } catch {
            let errorMsg = ConversationMessage(
                content: "I couldn't answer that question. Please try again or rephrase your question.",
                isUser: false
            )
            conversationHistory.append(errorMsg)
            print("Error in conversation: \(error)")
        }

        isLoadingQuestionResponse = false
    }

    /// Clear conversation state completely (called when user dismisses conversation modal)
    func clearConversation() {
        conversationHistory = []
        isInConversationMode = false
        isLoadingQuestionResponse = false
        questionResponse = nil
    }

    /// Start a conversation with an initial question
    func startConversation(with initialQuestion: String) async {
        clearConversation()
        isInConversationMode = true
        await addConversationMessage(initialQuestion)
    }
}