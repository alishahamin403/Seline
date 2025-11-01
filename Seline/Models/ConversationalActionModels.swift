import Foundation

// MARK: - Action Type (moved from QueryRouter to avoid duplication)

enum ActionType: String, Codable {
    case createEvent
    case updateEvent
    case deleteEvent
    case createNote
    case updateNote
    case deleteNote

    var displayName: String {
        switch self {
        case .createEvent: return "Create Event"
        case .updateEvent: return "Update Event"
        case .deleteEvent: return "Delete Event"
        case .createNote: return "Create Note"
        case .updateNote: return "Update Note"
        case .deleteNote: return "Delete Note"
        }
    }
}

// MARK: - Interactive Action (Main State Container)

/// Represents an action being built through multi-turn conversation
struct InteractiveAction: Equatable {
    let id: UUID
    let type: ActionType
    var extractedInfo: ExtractedActionInfo
    var extractionState: ExtractionState
    var clarifyingQuestions: [ClarifyingQuestion] = []
    var suggestions: [ActionSuggestion] = []
    var conversationTurns: Int = 0

    init(type: ActionType) {
        self.id = UUID()
        self.type = type
        self.extractedInfo = ExtractedActionInfo(actionType: type)
        self.extractionState = ExtractionState(actionType: type)
    }
}

// MARK: - Extracted Information (What We Know So Far)

struct ExtractedActionInfo: Equatable {
    let actionType: ActionType

    // For events
    var eventTitle: String?
    var eventDescription: String?
    var eventDate: Date?
    var eventStartTime: String?
    var eventEndTime: String?
    var eventReminders: [EventReminder] = []
    var eventRecurrence: String?
    var isAllDay: Bool = false

    // For notes
    var noteTitle: String?
    var noteContent: String = ""
    var formattedContent: String?

    // For updates/deletes
    var targetItemTitle: String?
    var deleteAllOccurrences: Bool?
    var updateContent: String?

    init(actionType: ActionType) {
        self.actionType = actionType
    }

    /// Check if we have minimum required info to save
    func isComplete() -> Bool {
        switch actionType {
        case .createEvent:
            return eventTitle != nil && eventDate != nil
        case .updateEvent:
            return targetItemTitle != nil && (eventDate != nil || eventStartTime != nil)
        case .deleteEvent:
            return targetItemTitle != nil
        case .createNote:
            return noteTitle != nil && !noteContent.isEmpty
        case .updateNote:
            return targetItemTitle != nil && !noteContent.isEmpty
        case .deleteNote:
            return targetItemTitle != nil
        }
    }
}

// MARK: - Extraction State (What Needs Clarification)

struct ExtractionState: Equatable {
    let actionType: ActionType

    var isExtracting: Bool = true
    var isAskingClarifications: Bool = false
    var isShowingSuggestions: Bool = false
    var isConfirming: Bool = false
    var isComplete: Bool = false

    // What's been confirmed by user
    var confirmedFields: Set<String> = []

    // What still needs clarification
    var requiredFields: Set<String> = []
    var optionalFields: Set<String> = []

    // Current focus
    var currentFocusField: String?

    init(actionType: ActionType) {
        self.actionType = actionType

        // Initialize field requirements based on action type
        switch actionType {
        case .createEvent:
            self.requiredFields = ["eventTitle", "eventDate"]
            self.optionalFields = ["eventStartTime", "eventEndTime", "eventReminders", "eventRecurrence", "isAllDay"]

        case .updateEvent:
            self.requiredFields = ["targetItemTitle"]
            self.optionalFields = ["eventDate", "eventStartTime", "eventEndTime"]

        case .deleteEvent:
            self.requiredFields = ["targetItemTitle"]
            self.optionalFields = ["deleteAllOccurrences"]

        case .createNote:
            self.requiredFields = ["noteTitle", "noteContent"]
            self.optionalFields = []

        case .updateNote:
            self.requiredFields = ["targetItemTitle", "noteContent"]
            self.optionalFields = []

        case .deleteNote:
            self.requiredFields = ["targetItemTitle"]
            self.optionalFields = []
        }
    }

    mutating func confirmField(_ field: String) {
        confirmedFields.insert(field)
        requiredFields.remove(field)
        optionalFields.remove(field)
    }

    var missingRequiredFields: [String] {
        Array(requiredFields)
    }

    var nextFieldToConfirm: String? {
        requiredFields.first
    }
}

// MARK: - Clarifying Question

struct ClarifyingQuestion: Identifiable, Equatable {
    let id: UUID
    let field: String
    let question: String
    let options: [String]?
    let isYesNo: Bool

    init(field: String, question: String, options: [String]? = nil) {
        self.id = UUID()
        self.field = field
        self.question = question
        self.options = options
        self.isYesNo = options == nil || (options?.count == 2 && options?.contains("Yes") ?? false)
    }
}

// MARK: - Action Suggestion (LLM-Generated)

struct ActionSuggestion: Identifiable, Equatable {
    let id: UUID
    let field: String
    let suggestion: String
    let confidence: Double  // 0-1, how confident the suggestion is
    let reason: String?

    init(field: String, suggestion: String, confidence: Double = 0.8, reason: String? = nil) {
        self.id = UUID()
        self.field = field
        self.suggestion = suggestion
        self.confidence = confidence
        self.reason = reason
    }
}

// MARK: - Event Reminder

struct EventReminder: Equatable, Codable {
    let minutesBefore: Int  // How many minutes before event
    let type: String?  // "notification", "email", etc.

    init(minutesBefore: Int, type: String? = nil) {
        self.minutesBefore = minutesBefore
        self.type = type ?? "notification"
    }

    var displayText: String {
        if minutesBefore == 0 {
            return "At time of event"
        } else if minutesBefore < 60 {
            return "\(minutesBefore) minutes before"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            return "\(hours) hour\(hours > 1 ? "s" : "") before"
        } else {
            let days = minutesBefore / 1440
            return "\(days) day\(days > 1 ? "s" : "") before"
        }
    }
}

// MARK: - Conversation Action Context

/// Passed to action builders to provide full conversation context
struct ConversationActionContext {
    let conversationHistory: [ConversationMessage]
    let recentTopics: [String]
    let lastNoteCreated: String?
    let lastEventCreated: String?

    var historyText: String {
        conversationHistory
            .map { "\(($0.isUser ? "User" : "Assistant")): \($0.text)" }
            .joined(separator: "\n")
    }
}
