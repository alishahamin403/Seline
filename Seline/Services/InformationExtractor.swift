import Foundation

/// Intelligently extracts action information from user messages using conversation context
@MainActor
class InformationExtractor {
    static let shared = InformationExtractor()

    private init() {}

    // MARK: - Main Extraction

    /// Extract and update action info from a user message, considering conversation history
    func extractFromMessage(
        _ userMessage: String,
        existingAction: InteractiveAction,
        conversationContext: ConversationActionContext
    ) async -> InteractiveAction {
        var updatedAction = existingAction

        switch existingAction.type {
        case .createEvent:
            await extractEventInfo(userMessage, context: conversationContext, action: &updatedAction)
        case .updateEvent:
            await extractEventInfo(userMessage, context: conversationContext, action: &updatedAction)
        case .deleteEvent:
            await extractDeleteInfo(userMessage, context: conversationContext, action: &updatedAction)

        case .createNote:
            await extractNoteInfo(userMessage, context: conversationContext, action: &updatedAction)
        case .updateNote:
            await extractNoteInfo(userMessage, context: conversationContext, action: &updatedAction)
        case .deleteNote:
            await extractDeleteInfo(userMessage, context: conversationContext, action: &updatedAction)
        }

        return updatedAction
    }

    // MARK: - Event Extraction

    private func extractEventInfo(
        _ message: String,
        context: ConversationActionContext,
        action: inout InteractiveAction
    ) async {
        let today = ISO8601DateFormatter().string(from: Date()).split(separator: "T")[0]
        let prompt = """
        Extract event information from this user message. Consider the conversation history for context.
        TODAY'S DATE: \(today)
        Use this to convert relative dates like "tomorrow", "next Monday", "tom", etc to ISO8601 format.

        Conversation history:
        \(context.historyText)

        Current user message: "\(message)"

        Extract the following fields if present:
        - title: Event title/name
        - date: Date in ISO8601 format (YYYY-MM-DD), or null if not mentioned. Convert relative dates like "tomorrow", "tom", "next Monday" etc using today's date.
        - startTime: Start time in HH:mm format (24-hour), or null
        - endTime: End time in HH:mm format, or null
        - isAllDay: true/false
        - reminder: Minutes before event for reminder, or null
        - recurrence: "daily", "weekly", "biweekly", "monthly", "yearly", or null
        - description: Any additional details

        Return ONLY valid JSON with these fields. Use null for missing fields.
        Example: {"title":"Dog walk","date":"2024-11-04","startTime":"18:00","endTime":null,"isAllDay":false,"reminder":60,"recurrence":null,"description":"Take my dog for a poop"}
        """

        do {
            let response = try await OpenAIService.shared.generateText(
                systemPrompt: "You are an information extractor. Return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 300,
                temperature: 0.0
            )

            if let jsonData = response.data(using: .utf8),
               let extracted = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                // Update extracted info
                if let title = extracted["title"] as? String, !title.isEmpty {
                    action.extractedInfo.eventTitle = title
                    action.extractionState.confirmField("eventTitle")
                }

                if let dateStr = extracted["date"] as? String, !dateStr.isEmpty {
                    if let date = parseDate(dateStr) {
                        action.extractedInfo.eventDate = date
                        action.extractionState.confirmField("eventDate")
                    }
                }

                if let timeStr = extracted["startTime"] as? String, !timeStr.isEmpty {
                    action.extractedInfo.eventStartTime = timeStr
                    action.extractionState.confirmField("eventStartTime")
                }

                if let endTimeStr = extracted["endTime"] as? String, !endTimeStr.isEmpty {
                    action.extractedInfo.eventEndTime = endTimeStr
                    action.extractionState.confirmField("eventEndTime")
                }

                if let isAllDay = extracted["isAllDay"] as? Bool {
                    action.extractedInfo.isAllDay = isAllDay
                    action.extractionState.confirmField("isAllDay")
                }

                if let reminder = extracted["reminder"] as? Int {
                    action.extractedInfo.eventReminders.append(EventReminder(minutesBefore: reminder))
                    action.extractionState.confirmField("eventReminders")
                }

                if let recurrence = extracted["recurrence"] as? String, !recurrence.isEmpty {
                    action.extractedInfo.eventRecurrence = recurrence
                    action.extractionState.confirmField("eventRecurrence")
                }

                if let description = extracted["description"] as? String, !description.isEmpty {
                    action.extractedInfo.eventDescription = description
                }
            }
        } catch {
            print("Error extracting event info: \(error)")
        }
    }

    // MARK: - Note Extraction

    private func extractNoteInfo(
        _ message: String,
        context: ConversationActionContext,
        action: inout InteractiveAction
    ) async {
        let prompt = """
        The user is providing information for a note. Extract the note details.

        Conversation history:
        \(context.historyText)

        Current user message: "\(message)"

        Extract:
        - title: Note title (if creating new note or referenced in message)
        - content: The note content/body
        - isAddingMore: true if user said something like "yes add more" or "add this too", false otherwise

        Return JSON: {"title":"title or null","content":"content here","isAddingMore":false}
        """

        do {
            let response = try await OpenAIService.shared.generateText(
                systemPrompt: "You are a note information extractor. Return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 300,
                temperature: 0.0
            )

            if let jsonData = response.data(using: .utf8),
               let extracted = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                if let title = extracted["title"] as? String, !title.isEmpty {
                    action.extractedInfo.noteTitle = title
                    action.extractionState.confirmField("noteTitle")
                }

                if let content = extracted["content"] as? String, !content.isEmpty {
                    action.extractedInfo.noteContent = content
                    action.extractionState.confirmField("noteContent")
                }
            }
        } catch {
            print("Error extracting note info: \(error)")
        }
    }

    // MARK: - Delete Extraction

    private func extractDeleteInfo(
        _ message: String,
        context: ConversationActionContext,
        action: inout InteractiveAction
    ) async {
        let prompt = """
        Extract deletion target from user message.

        Conversation history:
        \(context.historyText)

        User message: "\(message)"

        Extract:
        - targetTitle: What item to delete (event/note name)
        - deleteAll: For recurring events, true if "delete all occurrences", false for just this one

        Return JSON: {"targetTitle":"name","deleteAll":false}
        """

        do {
            let response = try await OpenAIService.shared.generateText(
                systemPrompt: "You are an information extractor. Return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 100,
                temperature: 0.0
            )

            if let jsonData = response.data(using: .utf8),
               let extracted = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                if let targetTitle = extracted["targetTitle"] as? String, !targetTitle.isEmpty {
                    action.extractedInfo.targetItemTitle = targetTitle
                    action.extractionState.confirmField("targetItemTitle")
                }

                if let deleteAll = extracted["deleteAll"] as? Bool {
                    action.extractedInfo.deleteAllOccurrences = deleteAll
                }
            }
        } catch {
            print("Error extracting delete info: \(error)")
        }
    }

        // MARK: - Date Parsing Helper

    /// Parse dates in multiple formats (YYYY-MM-DD or full ISO8601)
    private func parseDate(_ dateStr: String) -> Date? {
        // Try full ISO8601 format first (2025-11-01T12:00:00Z or 2025-11-01T12:00:00)
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateStr) {
            return date
        }

        // Try date-only format (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: dateStr) {
            return date
        }

        // Try other common formats
        let formats = ["MM/dd/yyyy", "dd/MM/yyyy", "MM-dd-yyyy", "dd-MM-yyyy"]
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateStr) {
                return date
            }
        }

        return nil
    }

// MARK: - Title Generation (Fallback)

    /// Generate a title if extraction failed, using LLM
    func generateTitleFromContext(
        _ userMessage: String,
        context: ConversationActionContext,
        actionType: ActionType
    ) async -> String {
        let prompt = """
        Generate a short \(actionType.displayName) title from this message.

        Message: "\(userMessage)"

        Return ONLY the title (max 10 words), nothing else.
        """

        do {
            let title = try await OpenAIService.shared.generateText(
                systemPrompt: "You generate concise titles. Return ONLY the title.",
                userPrompt: prompt,
                maxTokens: 20,
                temperature: 0.7
            )
            return title.trimmingCharacters(in: .whitespaces)
        } catch {
            print("Error generating title: \(error)")
            return "New \(actionType.displayName)"
        }
    }
}
