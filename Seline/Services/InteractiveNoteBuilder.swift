import Foundation

/// Manages interactive note building with LLM suggestions and context awareness
@MainActor
class InteractiveNoteBuilder {
    static let shared = InteractiveNoteBuilder()

    private init() {}

    // MARK: - Main Builder Interface

    /// Get the next step in note building
    func getNextStep(for action: InteractiveAction) async -> NoteBuilderStep {
        // If this is a new note, need title and content
        if action.type == .createNote {
            if action.extractedInfo.noteTitle == nil {
                return .askForTitle
            }
            if action.extractedInfo.noteContent.isEmpty {
                return .askForContent(suggestedTitle: action.extractedInfo.noteTitle ?? "New Note")
            }
        }

        // For updates, need the target note and content to add
        if action.type == .updateNote {
            if action.extractedInfo.targetItemTitle == nil {
                return .askWhichNoteToUpdate
            }
            if action.extractedInfo.noteContent.isEmpty {
                return .askWhatToAdd
            }
        }

        // Have the basics, ask if they want to add more
        if !action.extractionState.isShowingSuggestions {
            return .askAddMore(currentContent: action.extractedInfo.noteContent)
        }

        // Ready to generate suggestions
        return .offerSuggestions(action: action)
    }

    // MARK: - Generate Smart Suggestions

    /// Generate LLM-powered suggestions for enhancing the note
    func generateSuggestions(
        for action: InteractiveAction,
        context: ConversationActionContext
    ) async -> [NoteSuggestion] {
        var suggestions: [NoteSuggestion] = []

        guard let noteContent = action.extractedInfo.noteContent as String? else {
            return suggestions
        }

        let prompt = """
        The user just created/updated a note. Based on the note content, suggest helpful additions they might want to include.

        Note content: "\(noteContent)"

        Conversation history: \(context.historyText)

        Generate 2-3 helpful suggestions for what could be added to this note. Consider:
        - Related information they might want to look up
        - Actionable items or reminders
        - Additional context or details
        - Structured formatting they might like

        Return JSON array with objects having:
        - "type": "lookup" (search for info), "remind" (add a reminder), "details" (add more details), or "format" (suggest formatting)
        - "suggestion": The actual suggestion text
        - "followUp": Optional question to ask user

        Example: [{"type":"lookup","suggestion":"Would you like me to look up dog walking best practices?","followUp":"Look up dog care tips?"},{"type":"remind","suggestion":"Add reminder to do this tomorrow?","followUp":null}]

        Return ONLY the JSON array.
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are a helpful note assistant. Return ONLY valid JSON array.",
                userPrompt: prompt,
                maxTokens: 400,
                temperature: 0.7
            )

            if let jsonData = response.data(using: .utf8),
               let suggestionsArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {

                for suggestionDict in suggestionsArray.prefix(2) {  // Max 2 suggestions
                    if let type = suggestionDict["type"] as? String,
                       let suggestion = suggestionDict["suggestion"] as? String {
                        suggestions.append(NoteSuggestion(
                            type: NoteSuggestionType(rawValue: type) ?? .details,
                            suggestion: suggestion,
                            followUp: suggestionDict["followUp"] as? String
                        ))
                    }
                }
            }
        } catch {
            print("Error generating suggestions: \(error)")
        }

        return suggestions
    }

    /// Generate content to add based on user's suggestion type
    func generateContentForSuggestion(
        type: NoteSuggestionType,
        currentContent: String,
        relatedText: String?
    ) async -> String {
        let prompt: String

        switch type {
        case .lookup:
            prompt = """
            Based on this note content, provide relevant information they might want to add:

            Note: "\(currentContent)"
            Related topic: "\(relatedText ?? "")"

            Return ONLY the information they might find useful to add to their note (2-3 sentences).
            """

        case .remind:
            prompt = """
            Based on this note, suggest when they should be reminded or what follow-up action to take:

            Note: "\(currentContent)"

            Return ONLY a reminder or action suggestion (1 sentence).
            """

        case .details:
            prompt = """
            Suggest what additional details would be helpful to add to this note:

            Note: "\(currentContent)"

            Return ONLY the suggested additional details (2-3 sentences).
            """

        case .format:
            prompt = """
            Reformat this note to be more organized and clearer. Use bullet points or structure as needed:

            Original: "\(currentContent)"

            Return ONLY the reformatted content.
            """
        }

        do {
            let content = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are a helpful note assistant. Return ONLY the content to add, no explanations.",
                userPrompt: prompt,
                maxTokens: 200,
                temperature: 0.7
            )
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Error generating content: \(error)")
            return ""
        }
    }

    // MARK: - Process User Response

    /// Process user's response to note building prompts
    func processResponse(
        _ response: String,
        to step: NoteBuilderStep,
        action: inout InteractiveAction
    ) async {
        switch step {
        case .askForTitle:
            let title = response.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                action.extractedInfo.noteTitle = title
                action.extractionState.confirmField("noteTitle")
            }

        case .askForContent:
            let content = response.trimmingCharacters(in: .whitespaces)
            if !content.isEmpty {
                action.extractedInfo.noteContent = content
                action.extractionState.confirmField("noteContent")
            }

        case .askWhichNoteToUpdate:
            let targetTitle = response.trimmingCharacters(in: .whitespaces)
            if !targetTitle.isEmpty {
                action.extractedInfo.targetItemTitle = targetTitle
                action.extractionState.confirmField("targetItemTitle")
            }

        case .askWhatToAdd:
            let contentToAdd = response.trimmingCharacters(in: .whitespaces)
            if !contentToAdd.isEmpty {
                action.extractedInfo.noteContent = contentToAdd
                action.extractionState.confirmField("noteContent")
            }

        case .askAddMore:
            let shouldAddMore = response.lowercased().contains("yes") ||
                              response.lowercased().contains("want to add") ||
                              response.lowercased().contains("have more")

            if shouldAddMore {
                action.extractionState.isShowingSuggestions = true
            } else {
                action.extractionState.isComplete = true
            }

        case .offerSuggestions:
            // User responded to a suggestion
            if response.lowercased().contains("yes") {
                action.extractionState.isShowingSuggestions = false
                action.extractionState.isComplete = true
            }
        }

        action.conversationTurns += 1
    }

    // MARK: - Helper Methods

    /// Get a friendly message for the current step
    func getPromptMessage(for step: NoteBuilderStep) -> String {
        switch step {
        case .askForTitle:
            return "What would you like to name this note?"

        case .askForContent(let suggestedTitle):
            return "What should I write in your note '\(suggestedTitle)'?"

        case .askWhichNoteToUpdate:
            return "Which note would you like to update?"

        case .askWhatToAdd:
            return "What would you like to add to this note?"

        case .askAddMore:
            return "Want to add anything else to this note?"

        case .offerSuggestions:
            return "Here are some things I can help you add:"
        }
    }

    /// Format note content for display
    func formatNotePreview(content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 3 {
            return lines.prefix(3).joined(separator: "\n") + "..."
        }
        return content
    }
}

// MARK: - Note Builder Step

enum NoteBuilderStep {
    case askForTitle
    case askForContent(suggestedTitle: String)
    case askWhichNoteToUpdate
    case askWhatToAdd
    case askAddMore(currentContent: String)
    case offerSuggestions(action: InteractiveAction)
}

// MARK: - Note Suggestion

struct NoteSuggestion: Identifiable, Equatable {
    let id: UUID
    let type: NoteSuggestionType
    let suggestion: String
    let followUp: String?

    init(type: NoteSuggestionType, suggestion: String, followUp: String? = nil) {
        self.id = UUID()
        self.type = type
        self.suggestion = suggestion
        self.followUp = followUp
    }

    var displayIcon: String {
        switch type {
        case .lookup: return "🔍"
        case .remind: return "🔔"
        case .details: return "📝"
        case .format: return "📋"
        }
    }

    var displayText: String {
        switch type {
        case .lookup: return "Look Up Info"
        case .remind: return "Add Reminder"
        case .details: return "Add Details"
        case .format: return "Format"
        }
    }
}

enum NoteSuggestionType: String {
    case lookup = "lookup"
    case remind = "remind"
    case details = "details"
    case format = "format"
}
