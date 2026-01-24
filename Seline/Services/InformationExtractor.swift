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
            await extractUpdateEventInfo(userMessage, context: conversationContext, action: &updatedAction)
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
        // Use local timezone explicitly for today's date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: Date())
        let lastEventContext = context.lastEventCreated.map { "LAST EVENT CREATED: \($0)" } ?? ""

        let prompt = """
        The user wants to create an event. Extract the event details from their message.

        TODAY'S DATE: \(today)
        TIMEZONE: \(TimeZone.current.identifier)
        \(lastEventContext)

        Conversation history:
        \(context.historyText)

        Current user message: "\(message)"

        CRITICAL RULES FOR TITLE EXTRACTION:
        1. The title should be the ACTUAL EVENT NAME/DESCRIPTION, not meta-words like "for me", "for tom", "create", "schedule", etc.
        2. Remove date/time references from the title (e.g., "tomorrow", "5pm", "Monday")
        3. Remove category words from the title (e.g., "work", "health", "social")
        4. The title should describe WHAT the event is about, not WHEN or WHERE it is
        5. If the message says "for tom at 5 pm Telus representation call regarding payment dispute", the title should be "Telus representation call regarding payment dispute" (NOT "Me For Tom")

        PROCESS:
        1. READ: What is the user describing? (event name, date, time, etc.)
        2. DISCOVER: What details are explicitly mentioned vs. implied?
        3. REASON: Explain what you found and what's missing
        4. EXTRACT: Provide the structured data

        Example reasoning:
        "User said 'Can you create an event for me for tom at 5 pm Telus representation call regarding payment dispute'.
        - Title: Telus representation call regarding payment dispute (NOT 'Me For Tom' - ignore 'for me for tom')
        - Date: Tomorrow (tom) = \(today)
        - Start time: 17:00 (5pm in 24-hour format)
        - End time: Not specified
        - Category: Personal (default, no category mentioned)
        - Description: Representation call with Telus about payment dispute"

        "User said 'schedule a meeting with John about Q4 budget on Friday at 2pm'.
        - Title: Meeting with John - Q4 Budget
        - Date: Friday = November 14, 2025
        - Start time: 14:00 (2pm in 24-hour format)
        - End time: Not specified
        - Duration hint: 'meeting' typically 1 hour
        - Description: About Q4 budget discussion with John"

        Extract these fields if present:
        - title: Event title/name (the actual event description, NOT meta-words like "for me", "create", etc.)
        - date: Date in ISO8601 format (YYYY-MM-DD). Convert relative dates using today's date.
        - startTime: Start time in HH:mm format (24-hour). Infer from context if needed.
        - endTime: End time in HH:mm format, or null if not specified
        - isAllDay: true/false
        - reminder: Minutes before event for reminder, or null
        - recurrence: "daily", "weekly", "biweekly", "monthly", "yearly", or null
        - category: "Work", "Health", "Social", "Family", or "Personal" (extract if mentioned)
        - description: Additional context (people involved, purpose, notes)

        Return ONLY valid JSON with these fields. Use null for missing fields.
        Example: {"title":"Telus representation call regarding payment dispute","date":"2025-11-14","startTime":"17:00","endTime":null,"isAllDay":false,"reminder":null,"recurrence":null,"category":"Personal","description":"Call with Telus to discuss payment dispute"}
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are an event information extractor. Show your reasoning, then return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 400,
                temperature: 0.0
            )

            // Try to parse JSON from the response (it might have reasoning before the JSON)
            if let jsonData = extractJSON(from: response)?.data(using: .utf8),
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
                
                // Extract category if present
                if let category = extracted["category"] as? String, !category.isEmpty {
                    // Category is stored in eventDescription or we can add a new field
                    // For now, we'll note it in the description if not already there
                    if action.extractedInfo.eventDescription?.isEmpty ?? true {
                        action.extractedInfo.eventDescription = "Category: \(category)"
                    }
                }
            }
        } catch {
            print("Error extracting event info: \(error)")
        }
    }

    // MARK: - Update Event Extraction

    private func extractUpdateEventInfo(
        _ message: String,
        context: ConversationActionContext,
        action: inout InteractiveAction
    ) async {
        // Use local timezone explicitly for today's date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: Date())
        let lastEventContext = context.lastEventCreated.map { "LAST CREATED EVENT TO UPDATE: \($0)" } ?? ""

        let prompt = """
        The user wants to UPDATE an existing event. Extract what changes they want to make.
        TODAY'S DATE: \(today)
        TIMEZONE: \(TimeZone.current.identifier)
        \(lastEventContext)

        Conversation history:
        \(context.historyText)

        User message: "\(message)"

        PROCESS:
        1. READ: What event are they updating? (which one from the conversation?)
        2. DISCOVER: What specifically do they want to change? (date, time, title, description?)
        3. REASON: Explain what changes are requested
        4. EXTRACT: Provide the updated fields

        Extract only fields that are being changed:
        - title: The event title to update (if not specified, use the last created event)
        - newDate: New date in ISO8601 format (YYYY-MM-DD) if changing date. Convert relative dates using today's date.
        - newStartTime: New start time in HH:mm format if changing time
        - newDescription: Any new description or notes

        Return ONLY JSON: {"title":"event name","newDate":"2025-11-01 or null","newStartTime":"14:00 or null","newDescription":"reason or null"}
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are an update event extractor. Show your reasoning, then return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 400,
                temperature: 0.0
            )

            if let jsonData = extractJSON(from: response)?.data(using: .utf8),
               let extracted = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                // Update event title
                if let title = extracted["title"] as? String, !title.isEmpty {
                    action.extractedInfo.eventTitle = title
                    action.extractionState.confirmField("eventTitle")
                }

                // Update new date
                if let dateStr = extracted["newDate"] as? String, !dateStr.isEmpty {
                    if let date = parseDate(dateStr) {
                        action.extractedInfo.eventDate = date
                        action.extractionState.confirmField("eventDate")
                    }
                }

                // Update new time
                if let timeStr = extracted["newStartTime"] as? String, !timeStr.isEmpty {
                    action.extractedInfo.eventStartTime = timeStr
                    action.extractionState.confirmField("eventStartTime")
                }

                // Update description
                if let desc = extracted["newDescription"] as? String, !desc.isEmpty {
                    action.extractedInfo.eventDescription = desc
                }
            }
        } catch {
            print("Error extracting update event info: \(error)")
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

        PROCESS:
        1. READ: What is the user writing about? (topic, subject)
        2. DISCOVER: Is this a new note or adding to existing? What's the main content?
        3. REASON: Explain what you found and what the note should be about
        4. EXTRACT: Provide the structured note data

        Example:
        "User said 'add a note about my project timeline - Q4 goals are: increase revenue by 20%, launch new feature by Dec 15'.
        - Title: Project Timeline / Q4 Goals
        - Content: Increase revenue by 20%, launch new feature by Dec 15
        - Creating new note"

        Extract:
        - title: Note title (what is this note about? if creating new, suggest a title)
        - content: The full note content/body (preserve all the details the user provided)
        - isAddingMore: true if user said something like "yes add more" or "add this too", false if creating new

        Return JSON: {"title":"title here","content":"full content here","isAddingMore":false}
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are a note information extractor. Show your reasoning, then return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 400,
                temperature: 0.0
            )

            if let jsonData = extractJSON(from: response)?.data(using: .utf8),
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
        The user wants to delete something. Extract what they want to delete.

        Conversation history:
        \(context.historyText)

        User message: "\(message)"

        PROCESS:
        1. READ: What does the user want to delete? (which event, note, or item?)
        2. DISCOVER: Is it a one-time item or recurring? Should they delete all occurrences?
        3. REASON: Explain what you understand about what they want to delete
        4. EXTRACT: Provide the deletion target

        Extract:
        - targetTitle: What item to delete (event/note name) - reference from conversation if available
        - deleteAll: For recurring events, true if "delete all occurrences", false if "delete just this one"

        Return JSON: {"targetTitle":"name","deleteAll":false}
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are an information extractor. Show your reasoning, then return ONLY valid JSON.",
                userPrompt: prompt,
                maxTokens: 200,
                temperature: 0.0
            )

            if let jsonData = extractJSON(from: response)?.data(using: .utf8),
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

    // MARK: - JSON Extraction Helper

    /// Extract JSON object from text that may contain reasoning before the JSON
    private func extractJSON(from text: String) -> String? {
        // Look for the first '{' and find the matching '}'
        guard let startIndex = text.firstIndex(of: "{") else {
            // If no JSON found, try to return the text as-is (might be valid JSON)
            return text.trimmingCharacters(in: .whitespaces)
        }

        var braceCount = 0
        var endIndex: String.Index? = nil
        var currentIndex = startIndex

        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = text.index(after: currentIndex)
                    break
                }
            }
            currentIndex = text.index(after: currentIndex)
        }

        guard let end = endIndex else {
            return nil
        }

        return String(text[startIndex..<end])
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
            let title = try await DeepSeekService.shared.generateText(
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
