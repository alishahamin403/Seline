import Foundation

enum QueryType {
    case action(ActionType)
    case search
    case question
    case counting(CountingQueryParameters)
    case comparison(ComparisonQueryParameters)
    case temporal(TemporalQueryParameters)
}

/// Router for classifying user queries with keyword heuristics + semantic LLM analysis
class QueryRouter {
    static let shared = QueryRouter()

    // Cache for recent intent classifications to avoid redundant API calls
    private var intentCache: [String: ActionType?] = [:]
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

        // Check for specialized query types (counting, comparison, temporal)
        let advancedParser = AdvancedQueryParser.shared

        // Check for counting queries
        if let countingParams = advancedParser.parseCountingQuery(query) {
            return .counting(countingParams)
        }

        // Check for comparison queries
        if let comparisonParams = advancedParser.parseComparisonQuery(query) {
            return .comparison(comparisonParams)
        }

        // Check for temporal queries (with specific date extraction)
        if let temporalParams = advancedParser.parseTemporalQuery(query) {
            return .temporal(temporalParams)
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
            return cachedResult
        }

        // Try keyword matching first (fast path)
        if let keywordBasedAction = detectActionByKeywords(query) {
            intentCache[cacheKey] = keywordBasedAction
            return keywordBasedAction
        }

        // If keywords are ambiguous, use semantic analysis
        // (This will be called asynchronously in SearchService)
        return nil
    }

    /// Keyword-based action detection
    private func detectActionByKeywords(_ query: String) -> ActionType? {
        // Check for note-related actions FIRST (explicit priority over events)
        if containsAny(of: noteKeywords, in: query) {
            // Smart handling of "add" keyword - it can mean create OR update
            // "add to my X note" = update (existing note)
            // "add a new note" = create (new note)
            let lowercasedQuery = query.lowercased()

            let hasExistingNoteReference = lowercasedQuery.contains("my ") ||
                                          lowercasedQuery.contains("the ") ||
                                          lowercasedQuery.contains("existing ") ||
                                          lowercasedQuery.contains("to ") ||
                                          lowercasedQuery.contains("this ")

            let hasAddKeyword = containsAny(of: ["add"], in: query)
            let hasCreateOnlyKeyword = containsAny(of: ["create", "new", "make"], in: query)

            // If "add" is used with reference to existing note, treat as update
            if hasAddKeyword && hasExistingNoteReference && !hasCreateOnlyKeyword {
                return .updateNote
            }

            // Check if query mentions "update" or "modify" - these are always updates
            if containsAny(of: updateKeywords, in: query) {
                return .updateNote
            }

            // Otherwise use standard logic
            if containsAny(of: createKeywords, in: query) {
                return .createNote
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
        if intentCache[cacheKey] != nil {
            return intentCache[cacheKey] ?? nil
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
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: query,
                maxTokens: 10,
                temperature: 0.0
            )

            let classified = response.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
            let result: ActionType? = parseSemanticClassification(classified)

            // Cache the result
            intentCache[cacheKey] = result

            return result
        } catch {
            print("Error classifying intent semantically: \(error)")
            return nil
        }
    }

    /// Parse semantic classification string to ActionType
    private func parseSemanticClassification(_ classification: String) -> ActionType? {
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
        return nil
    }

    /// Detect multiple actions in a single query using LLM
    /// Returns an array of (ActionType, query) tuples if multiple actions are detected
    func detectMultipleActions(_ query: String) async -> [(actionType: ActionType, query: String)] {
        let lowercased = query.lowercased()

        // Quick check for separator keywords that indicate multiple actions
        let separators = [" and ", " plus ", " also ", " additionally "]
        let hasMultipleActions = separators.contains { lowercased.contains($0) }

        if !hasMultipleActions {
            return []
        }

        let systemPrompt = """
        You are an action parser. Analyze this user query and extract ALL distinct actions they want to perform.
        Return a JSON array of actions, where each action has "type" and "query" fields.

        Types must be one of: "create_note", "create_event", "update_note", "update_event", "delete_note", "delete_event"

        Example input: add telus bill $82 and update sum in monthly expenses note
        Example output: [{"type":"create_note","query":"add telus bill $82"},{"type":"update_note","query":"update sum in monthly expenses note"}]

        Return ONLY valid JSON array, nothing else. No markdown, no extra text.
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: query,
                maxTokens: 300,
                temperature: 0.0
            )

            print("DEBUG: Multi-action LLM response: \(response)")

            // Try to extract JSON from response (LLM might include markdown or extra text)
            let jsonString = extractJSON(from: response)

            if let data = jsonString.data(using: String.Encoding.utf8),
               let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                var actions: [(actionType: ActionType, query: String)] = []
                for actionDict in jsonArray {
                    if let typeStr = actionDict["type"], let actionQuery = actionDict["query"] {
                        if let actionType = parseSemanticClassification(typeStr) {
                            print("DEBUG: Detected action - type: \(actionType), query: \(actionQuery)")
                            actions.append((actionType: actionType, query: actionQuery))
                        }
                    }
                }

                if !actions.isEmpty {
                    return actions
                }
            }
        } catch {
            print("Error detecting multiple actions: \(error)")
        }

        // Fallback: manual parsing if LLM fails
        print("DEBUG: LLM parsing failed, attempting manual split")
        return manuallyParseMultipleActions(query)
    }

    /// Extract JSON array from response (handles markdown code blocks, extra text, etc)
    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code block markers
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON array
        if let startIndex = cleaned.firstIndex(of: "["),
           let endIndex = cleaned.lastIndex(of: "]") {
            return String(cleaned[startIndex...endIndex])
        }

        return cleaned
    }

    /// Fallback: manually parse multiple actions by splitting on separators
    private func manuallyParseMultipleActions(_ query: String) -> [(actionType: ActionType, query: String)] {
        let separators = [" and ", " plus ", " also ", " additionally "]
        var parts: [String] = [query]

        // Split on each separator
        for separator in separators {
            var newParts: [String] = []
            for part in parts {
                let split = part.components(separatedBy: separator)
                newParts.append(contentsOf: split)
            }
            parts = newParts
        }

        var actions: [(actionType: ActionType, query: String)] = []

        for part in parts {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPart.isEmpty else { continue }

            // Detect action type for this part
            if let actionType = detectAction(trimmedPart) {
                print("DEBUG: Manual parse - detected action type: \(actionType), query: \(trimmedPart)")
                actions.append((actionType: actionType, query: trimmedPart))
            }
        }

        // Only return if we found multiple distinct actions
        return actions.count > 1 ? actions : []
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
