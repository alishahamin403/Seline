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

/// Heuristic router for classifying user queries without ML/LLM
class QueryRouter {
    static let shared = QueryRouter()

    // MARK: - Keywords for action detection
    private let createKeywords = ["add", "create", "schedule", "new", "make", "set"]
    private let updateKeywords = ["update", "modify", "change", "edit", "reschedule", "move", "set"]
    private let deleteKeywords = ["delete", "remove", "cancel", "clear", "erase"]

    private let eventKeywords = ["event", "meeting", "appointment", "task", "reminder", "call", "conference", "deadline"]
    private let noteKeywords = ["note", "memo", "reminder", "write", "record", "jot"]

    private let questionKeywords = ["what", "when", "where", "how", "why", "am i", "can i", "do i", "show", "find", "give", "list", "tell"]

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
    private func detectAction(_ query: String) -> ActionType? {
        // Check for event-related actions
        if containsAny(of: eventKeywords, in: query) {
            if containsAny(of: createKeywords, in: query) {
                return .createEvent
            } else if containsAny(of: updateKeywords, in: query) {
                return .updateEvent
            } else if containsAny(of: deleteKeywords, in: query) {
                return .deleteEvent
            }
        }

        // Check for note-related actions
        if containsAny(of: noteKeywords, in: query) {
            if containsAny(of: createKeywords, in: query) {
                return .createNote
            } else if containsAny(of: updateKeywords, in: query) {
                return .updateNote
            } else if containsAny(of: deleteKeywords, in: query) {
                return .deleteNote
            }
        }

        return nil
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
