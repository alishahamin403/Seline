import Foundation

enum QueryType {
    case action(ActionType)
    case search
    case question
}

enum ActionType {
    case createEvent
    case updateEvent
    case deleteEvent
    case createNote
    case updateNote
    case deleteNote
    case unknown
}

/// Router for classifying user queries with keyword heuristics + semantic LLM analysis
class QueryRouter {
    static let shared = QueryRouter()

    // Cache for recent intent classifications to avoid redundant API calls
    private var intentCache: [String: ActionType] = [:]
    private let cacheTimeout: TimeInterval = 3600 // 1 hour

    // MARK: - Keywords for action detection
    private let createKeywords = ["add", "create", "schedule", "new", "make", "set"]
    private let updateKeywords = ["update", "modify", "change", "edit", "reschedule", "move", "set"]
    private let deleteKeywords = ["delete", "remove", "cancel", "clear", "erase"]

    private let eventKeywords = ["event", "meeting", "appointment", "task", "reminder", "call", "conference", "deadline"]
    private let noteKeywords = ["note", "memo", "reminder", "write", "record", "jot"]

    private let questionKeywords = ["what", "when", "where", "how", "why", "am i", "can i", "can you", "could you", "would you", "do i", "is there", "are there", "show", "find", "give", "list", "tell", "summarize", "explain", "describe"]

    // MARK: - Public API

    /// Classifies a user query and returns the type
    func classifyQuery(_ query: String) -> QueryType {
        let lowercased = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Check for action keywords first
        if let actionType = detectAction(lowercased) {
            return .action(actionType)
        }

        // Check for question keywords
        if isQuestion(lowercased) {
            return .question
        }

        // Default to search
        return .search
    }

    /// Returns true if the query appears to be a question
    func isQuestion(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Check for question marks
        if query.contains("?") {
            return true
        }

        // Check for question keywords
        for keyword in questionKeywords {
            if lowercased.hasPrefix(keyword) {
                return true
            }
        }

        return false
    }

    /// Attempts to detect what action the user wants to perform
    /// Uses keyword matching first, falls back to semantic LLM analysis for ambiguous cases
    private func detectAction(_ query: String) -> ActionType? {
        let cacheKey = query.lowercased()

        // Check cache first
        if let cachedResult = intentCache[cacheKey] {
            return cachedResult != .unknown ? cachedResult : nil
        }

        // Try keyword matching first (fast path)
        if let keywordBasedAction = detectActionByKeywords(query) {
            return keywordBasedAction
        }

        // If keywords are ambiguous, use semantic analysis
        // (This will be called asynchronously in SearchService)
        return nil
    }

    /// Keyword-based action detection
    private func detectActionByKeywords(_ query: String) -> ActionType? {
        // Check for note-related actions FIRST (explicit priority over events)
        // When user says "create a note", we should ALWAYS create a note, not an event
        if containsAny(of: noteKeywords, in: query) {
            if containsAny(of: createKeywords, in: query) {
                return .createNote
            } else if containsAny(of: updateKeywords, in: query) {
                return .updateNote
            } else if containsAny(of: deleteKeywords, in: query) {
                return .deleteNote
            }
        }

        // Check for event-related actions only if no note keywords found
        if containsAny(of: eventKeywords, in: query) {
            if containsAny(of: createKeywords, in: query) {
                return .createEvent
            } else if containsAny(of: updateKeywords, in: query) {
                return .updateEvent
            } else if containsAny(of: deleteKeywords, in: query) {
                return .deleteEvent
            }
        }

        return nil
    }

    /// Semantic intent classification using LLM (for ambiguous cases)
    /// This is async and should be called when keyword matching is unclear
    func classifyIntentWithLLM(_ query: String) async -> ActionType? {
        let cacheKey = query.lowercased()

        // Check cache first
        if let cachedResult = intentCache[cacheKey] {
            return cachedResult != .unknown ? cachedResult : nil
        }

        let systemPrompt = """
        You are an intent classifier. Analyze the user query and determine if they want to:
        1. Create/add a NOTE (personal notes, memos, recordings)
        2. Create/add an EVENT (meetings, appointments, tasks, deadlines, reminders)
        3. Update a NOTE or EVENT
        4. Delete a NOTE or EVENT
        5. General question or search

        Return ONLY one of: "create_note", "create_event", "update_note", "update_event", "delete_note", "delete_event", or "other"
        Consider context and semantics, NOT just keywords.

        If user says "new note", respond "create_note"
        If user says "schedule meeting", respond "create_event"
        If user says "add details to my note", respond "update_note"
        """

        do {
            let response = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: query,
                maxTokens: 10,
                temperature: 0.0
            )

            let classified = response.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
            let result: ActionType = parseSemanticClassification(classified)

            // Cache the result
            intentCache[cacheKey] = result

            return result != .unknown ? result : nil
        } catch {
            print("Error classifying intent semantically: \(error)")
            return nil
        }
    }

    /// Parse semantic classification string to ActionType
    private func parseSemanticClassification(_ classification: String) -> ActionType {
        if classification.contains("create_note") {
            return .createNote
        } else if classification.contains("create_event") {
            return .createEvent
        } else if classification.contains("update_note") {
            return .updateNote
        } else if classification.contains("update_event") {
            return .updateEvent
        } else if classification.contains("delete_note") {
            return .deleteNote
        } else if classification.contains("delete_event") {
            return .deleteEvent
        }
        return .unknown
    }

    /// Helper to check if string contains any of the keywords
    private func containsAny(of keywords: [String], in text: String) -> Bool {
        for keyword in keywords {
            if text.contains(keyword) {
                return true
            }
        }
        return false
    }
}
