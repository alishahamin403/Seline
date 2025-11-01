import Foundation

/// Orchestrates the multi-turn conversational action building flow
@MainActor
class ConversationActionHandler {
    static let shared = ConversationActionHandler()

    private init() {}

    private let infoExtractor = InformationExtractor.shared
    private let eventBuilder = InteractiveEventBuilder.shared
    private let noteBuilder = InteractiveNoteBuilder.shared

    // MARK: - Main Entry Points

    /// Start building an action based on initial user message
    func startAction(
        from userMessage: String,
        actionType: ActionType,
        conversationContext: ConversationActionContext
    ) async -> InteractiveAction {
        var action = InteractiveAction(type: actionType)

        // Extract initial info from the message
        action = await infoExtractor.extractFromMessage(
            userMessage,
            existingAction: action,
            conversationContext: conversationContext
        )

        return action
    }

    /// Process a follow-up message and update the action
    func processFollowUp(
        userMessage: String,
        action: InteractiveAction,
        conversationContext: ConversationActionContext
    ) async -> InteractiveAction {
        var updatedAction = action

        // Extract additional info from this message
        updatedAction = await infoExtractor.extractFromMessage(
            userMessage,
            existingAction: updatedAction,
            conversationContext: conversationContext
        )

        return updatedAction
    }

    // MARK: - Get Next User Prompt

    /// Determine what to ask the user next
    func getNextPrompt(
        for action: InteractiveAction,
        conversationContext: ConversationActionContext
    ) async -> String {
        switch action.type {
        case .createEvent, .updateEvent:
            return await getEventPrompt(for: action)

        case .createNote, .updateNote:
            return await getNotePrompt(for: action)

        case .deleteEvent, .deleteNote:
            return await getDeletePrompt(for: action)
        }
    }

    /// Get confirmation summary to show user
    func getConfirmationSummary(for action: InteractiveAction) -> String {
        switch action.type {
        case .createEvent, .updateEvent:
            return eventBuilder.getConfirmationSummary(for: action)

        case .createNote, .updateNote:
            let title = action.extractedInfo.noteTitle ?? "Note"
            return "📝 \(title)\n\n\(action.extractedInfo.noteContent)"

        case .deleteEvent:
            return "🗑️ Delete event: \(action.extractedInfo.targetItemTitle ?? "Unknown")"

        case .deleteNote:
            return "🗑️ Delete note: \(action.extractedInfo.targetItemTitle ?? "Unknown")"
        }
    }

    // MARK: - Event Flow

    private func getEventPrompt(for action: InteractiveAction) async -> String {
        let step = await eventBuilder.getNextStep(for: action)

        switch step {
        case .askForMissingField(let field, let theAction):
            if let question = generateEventQuestion(for: field, action: theAction) {
                return question
            }
            return "Tell me more about the event"

        case .confirmExtracted:
            return "Does this look correct? I have:\n\n\(eventBuilder.getConfirmationSummary(for: action))"

        case .offerOptionalFields:
            let suggestions = await eventBuilder.generateOptionalSuggestions(for: action)
            if suggestions.isEmpty {
                return "Ready to save this event?"
            }
            let suggestionText = suggestions.map { "• \($0.suggestion) (\($0.reason ?? "helpful"))" }.joined(separator: "\n")
            return "Would you like to add any of these?\n\n\(suggestionText)"

        case .readyToSave:
            return "All set! Ready to save this event?"
        }
    }

    private func getNotePrompt(for action: InteractiveAction) async -> String {
        let step = await noteBuilder.getNextStep(for: action)

        switch step {
        case .askForTitle:
            return "What would you like to name this note?"

        case .askForContent(let suggestedTitle):
            return "What should I write in your note '\(suggestedTitle)'?"

        case .askWhichNoteToUpdate:
            return "Which note would you like to update? (Tell me the name)"

        case .askWhatToAdd:
            return "What would you like to add to this note?"

        case .askAddMore(let currentContent):
            let preview = noteBuilder.formatNotePreview(content: currentContent)
            return "I have this so far:\n\n\(preview)\n\nWant to add more?"

        case .offerSuggestions(let theAction):
            let suggestions = await noteBuilder.generateSuggestions(for: theAction, context: ConversationActionContext(
                conversationHistory: [],
                recentTopics: [],
                lastNoteCreated: nil,
                lastEventCreated: nil
            ))

            if suggestions.isEmpty {
                return "Ready to save this note?"
            }

            let suggestionText = suggestions.map { "\($0.displayIcon) \($0.displayText): \($0.suggestion)" }.joined(separator: "\n\n")
            return "Here are some things I can help you add:\n\n\(suggestionText)"
        }
    }

    private func getDeletePrompt(for action: InteractiveAction) async -> String {
        if action.extractedInfo.targetItemTitle == nil {
            return "What would you like to delete?"
        }

        let itemType = action.type == .deleteEvent ? "event" : "note"
        let itemTitle = action.extractedInfo.targetItemTitle ?? "Unknown"

        if action.type == .deleteEvent {
            return "Delete the \(itemType) '\(itemTitle)'? This can't be undone."
        } else {
            return "Delete the \(itemType) '\(itemTitle)'? This can't be undone."
        }
    }

    // MARK: - Handle User Responses

    /// Process user's response to an action prompt
    func processUserResponse(
        _ response: String,
        to action: InteractiveAction,
        currentStep: String,
        conversationContext: ConversationActionContext
    ) async -> InteractiveAction {
        var updatedAction = action

        switch action.type {
        case .createEvent, .updateEvent:
            // Extract event info from response
            updatedAction = await infoExtractor.extractFromMessage(
                response,
                existingAction: updatedAction,
                conversationContext: conversationContext
            )

            // If response is a simple yes/no for confirmation
            if response.lowercased().contains("yes") || response.lowercased().contains("looks good") {
                updatedAction.extractionState.isConfirming = true
            }

        case .createNote, .updateNote:
            updatedAction = await infoExtractor.extractFromMessage(
                response,
                existingAction: updatedAction,
                conversationContext: conversationContext
            )

        case .deleteEvent, .deleteNote:
            if response.lowercased().contains("yes") || response.lowercased().contains("confirm") {
                updatedAction.extractionState.isConfirming = true
            }
        }

        return updatedAction
    }

    /// Check if the action is ready to execute
    func isReadyToSave(_ action: InteractiveAction) -> Bool {
        // Must have minimum required info
        if !action.extractedInfo.isComplete() {
            return false
        }

        // For confirmation, need explicit yes
        return action.extractionState.isConfirming || action.extractionState.isComplete
    }

    // MARK: - Compile Final Data

    /// Convert interactive action to concrete data for saving
    func compileEventData(from action: InteractiveAction) -> EventCreationData? {
        guard let title = action.extractedInfo.eventTitle,
              let date = action.extractedInfo.eventDate else {
            return nil
        }

        return EventCreationData(
            title: title,
            description: action.extractedInfo.eventDescription,
            date: date.toISO8601String(),
            time: action.extractedInfo.eventStartTime,
            endTime: action.extractedInfo.eventEndTime,
            recurrenceFrequency: action.extractedInfo.eventRecurrence,
            isAllDay: action.extractedInfo.isAllDay,
            requiresFollowUp: false
        )
    }

    func compileNoteData(from action: InteractiveAction) -> NoteCreationData? {
        guard let title = action.extractedInfo.noteTitle,
              !action.extractedInfo.noteContent.isEmpty else {
            return nil
        }

        return NoteCreationData(
            title: title,
            content: action.extractedInfo.noteContent,
            formattedContent: action.extractedInfo.noteContent
        )
    }

    func compileNoteUpdateData(from action: InteractiveAction) -> NoteUpdateData? {
        guard let noteTitle = action.extractedInfo.targetItemTitle,
              !action.extractedInfo.noteContent.isEmpty else {
            return nil
        }

        return NoteUpdateData(
            noteTitle: noteTitle,
            contentToAdd: action.extractedInfo.noteContent,
            formattedContentToAdd: action.extractedInfo.noteContent
        )
    }

    func compileDeletionData(from action: InteractiveAction) -> DeletionData? {
        guard let itemTitle = action.extractedInfo.targetItemTitle else {
            return nil
        }

        let itemType = action.type == .deleteEvent ? "event" : "note"
        return DeletionData(
            itemType: itemType,
            itemTitle: itemTitle,
            deleteAllOccurrences: action.extractedInfo.deleteAllOccurrences
        )
    }

    // MARK: - Helper Methods

    private func generateEventQuestion(for field: String, action: InteractiveAction) -> String? {
        switch field {
        case "eventTitle":
            return "What's the name of this event?"
        case "eventDate":
            return "When is the event? (e.g., tomorrow, next Monday, March 15)"
        case "eventStartTime":
            return "What time should it start? (e.g., 6 PM, 18:00)"
        default:
            return nil
        }
    }
}

// MARK: - Extension for Date ISO8601

extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - Old Data Models (for compatibility during transition)

struct EventCreationData: Codable, Equatable {
    let title: String
    let description: String?
    let date: String
    let time: String?
    let endTime: String?
    let recurrenceFrequency: String?
    let isAllDay: Bool
    let requiresFollowUp: Bool

    init(title: String, description: String? = nil, date: String, time: String? = nil, endTime: String? = nil, recurrenceFrequency: String? = nil, isAllDay: Bool = false, requiresFollowUp: Bool = false) {
        self.title = title
        self.description = description
        self.date = date
        self.time = time
        self.endTime = endTime
        self.recurrenceFrequency = recurrenceFrequency
        self.isAllDay = isAllDay
        self.requiresFollowUp = requiresFollowUp
    }
}

struct NoteCreationData: Codable, Equatable {
    let title: String
    let content: String
    let formattedContent: String

    init(title: String, content: String, formattedContent: String) {
        self.title = title
        self.content = content
        self.formattedContent = formattedContent
    }
}

struct NoteUpdateData: Codable, Equatable {
    let noteTitle: String
    let contentToAdd: String
    let formattedContentToAdd: String

    init(noteTitle: String, contentToAdd: String, formattedContentToAdd: String) {
        self.noteTitle = noteTitle
        self.contentToAdd = contentToAdd
        self.formattedContentToAdd = formattedContentToAdd
    }
}

struct DeletionData: Codable, Equatable {
    let itemType: String
    let itemTitle: String
    let deleteAllOccurrences: Bool?

    init(itemType: String, itemTitle: String, deleteAllOccurrences: Bool? = nil) {
        self.itemType = itemType
        self.itemTitle = itemTitle
        self.deleteAllOccurrences = deleteAllOccurrences
    }
}
