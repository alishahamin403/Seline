import Foundation

/// Handles parsing and preparing action confirmations from user queries
class ActionQueryHandler {
    static let shared = ActionQueryHandler()

    // MARK: - Event Creation Parsing

    /// Attempts to parse an event creation request with LLM-generated title
    /// Example: "add meeting with Sarah at 3pm tomorrow"
    /// Uses weather, locations, and destination context for smarter title generation
    @MainActor
    func parseEventCreation(
        from query: String,
        weatherService: WeatherService? = nil,
        locationsManager: LocationsManager? = nil,
        navigationService: NavigationService? = nil
    ) async -> EventCreationData? {
        let time = extractTime(from: query)
        let date = extractDate(from: query)

        // Use LLM to generate a better title with context
        var title = await generateEventTitle(
            from: query,
            extractedTime: time,
            extractedDate: date,
            weatherService: weatherService,
            locationsManager: locationsManager,
            navigationService: navigationService
        )

        if title.isEmpty {
            title = "New Event"
        }

        return EventCreationData(
            title: title,
            description: "",
            date: date?.toISO8601String() ?? Date().toISO8601String(),
            time: time ?? formatTime(Date()),
            endTime: nil,
            recurrenceFrequency: nil,
            isAllDay: time == nil,
            requiresFollowUp: false
        )
    }

    /// Attempts to parse a note creation request with LLM-generated title and content
    /// Example: "create note about meeting with Sarah"
    @MainActor
    func parseNoteCreation(from query: String) async -> NoteCreationData? {
        var title = extractNoteTitle(from: query)
        var content = ""

        // Use LLM to generate better title and add context-aware content
        let llmGeneratedTitle = await generateNoteTitle(from: query)
        if !llmGeneratedTitle.isEmpty {
            title = llmGeneratedTitle
        }

        // Generate detailed content based on the query
        let generatedContent = await generateNoteContent(from: query)
        if !generatedContent.isEmpty {
            content = generatedContent
        }

        if title.isEmpty {
            title = "New Note"
        }

        return NoteCreationData(
            title: title,
            content: content,
            formattedContent: content
        )
    }

    /// Uses LLM to generate a concise note title
    private func generateNoteTitle(from query: String) async -> String {
        let systemPrompt = """
        You are a helpful assistant that generates concise note titles from user input.
        Generate a SHORT, CLEAR note title (max 6 words) based on what the user wants to note.
        Only return the title itself, nothing else. Do not include any explanation.
        """

        let userPrompt = """
        User input: "\(query)"

        Generate a clear, concise note title from this input.
        Ignore action keywords like "add", "create", "write", "note", "memo".
        Return ONLY the title, nothing else.
        """

        do {
            let title = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: 20,
                temperature: 0.7
            )
            return title.trimmingCharacters(in: .whitespaces)
        } catch {
            print("Error generating note title with LLM: \(error). Using fallback method.")
            return extractNoteTitle(from: query)
        }
    }

    /// Uses LLM to generate detailed note content
    private func generateNoteContent(from query: String) async -> String {
        let systemPrompt = """
        You are a helpful assistant that expands brief notes into useful, detailed content.
        Based on the user's input, generate a brief but detailed note (2-4 sentences).
        Include relevant context, key details, and actionable information.
        Write naturally and conversationally.
        """

        let userPrompt = """
        User input: "\(query)"

        Based on this input, generate a detailed note (2-4 sentences) that includes:
        - Key information from the input
        - Any important context or details
        - Actionable items if applicable

        Write the content, nothing else. No titles or labels needed.
        """

        do {
            let content = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: 100,
                temperature: 0.7
            )
            return content.trimmingCharacters(in: .whitespaces)
        } catch {
            print("Error generating note content with LLM: \(error).")
            return ""
        }
    }

    // MARK: - Helper Methods

    /// Generates a concise event title using LLM based on user's input with contextual data
    private func generateEventTitle(
        from query: String,
        extractedTime: String?,
        extractedDate: Date?,
        weatherService: WeatherService?,
        locationsManager: LocationsManager?,
        navigationService: NavigationService?
    ) async -> String {
        // Build contextual information
        var contextInfo = ""
        if let weatherService = weatherService,
           let locationsManager = locationsManager {
            contextInfo = await MainActor.run {
                OpenAIService.shared.buildContextForAction(
                    weatherService: weatherService,
                    locationsManager: locationsManager,
                    navigationService: navigationService
                )
            }
        }

        let systemPrompt = """
        You are a helpful assistant that extracts event titles from user input.
        Generate a SHORT, CONCISE event title (max 5 words) based on what the user wants to create.
        Consider the context provided (weather, locations, destinations) to generate better, more relevant titles.
        Only return the title itself, nothing else. Do not include any explanation.
        """

        let userPrompt = """
        \(contextInfo.isEmpty ? "" : "CONTEXT:\n\(contextInfo)\n\n")User input: "\(query)"

        Generate a clear, concise event title from this input.
        Ignore action keywords like "add", "create", "schedule".
        Ignore the time and date components.
        Use the context above (if provided) to make better decisions about the title.
        Return ONLY the title, nothing else.
        """

        do {
            let title = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: 20,
                temperature: 0.7
            )
            return title.trimmingCharacters(in: .whitespaces)
        } catch {
            // Fallback to pattern-based extraction if LLM fails
            print("Error generating title with LLM: \(error). Using fallback method.")
            return extractEventTitleFallback(from: query)
        }
    }

    /// Fallback method for extracting event title if LLM fails
    private func extractEventTitleFallback(from query: String) -> String {
        let actionKeywords = ["add", "create", "schedule", "new"]
        var query = query.lowercased()

        // Remove action keywords
        for keyword in actionKeywords {
            if query.hasPrefix(keyword) {
                query.removeFirst(keyword.count)
            }
        }

        // Remove common event keywords
        let eventKeywords = ["event", "meeting", "appointment", "task", "reminder", "call"]
        for keyword in eventKeywords {
            query = query.replacingOccurrences(of: keyword, with: "")
        }

        // Extract the part before time indicators
        let timeIndicators = ["at", "on", "tomorrow", "today", "next"]
        for indicator in timeIndicators {
            if let range = query.range(of: indicator) {
                query = String(query[..<range.lowerBound])
            }
        }

        return query.trimmingCharacters(in: .whitespaces).capitalized
    }

    private func extractNoteTitle(from query: String) -> String {
        let actionKeywords = ["add", "create", "write", "make", "note", "memo"]
        var query = query.lowercased()

        // Remove action keywords
        for keyword in actionKeywords {
            query = query.replacingOccurrences(of: keyword, with: "")
        }

        return query.trimmingCharacters(in: .whitespaces).capitalized
    }

    private func extractTime(from query: String) -> String? {
        let lowercased = query.lowercased()

        // Handle natural language time references first
        let timeReferences: [String: String] = [
            "morning": "09:00",
            "afternoon": "14:00",
            "evening": "18:00",
            "night": "21:00",
            "midnight": "00:00",
            "noon": "12:00",
            "lunch": "12:00",
            "breakfast": "08:00",
            "dinner": "19:00"
        ]

        for (reference, time) in timeReferences {
            if lowercased.contains(reference) {
                return time
            }
        }

        // Pattern for: "3pm", "3:00pm", "3:00 pm", "3 pm", "15:30", "15:30pm", etc.
        let patterns = [
            "([0-2]?[0-9])\\s*:\\s*([0-5][0-9])\\s*(am|pm)?",  // HH:MM or HH:MM am/pm
            "([0-2]?[0-9])\\s*(am|pm)",                         // HH am/pm (12-hour)
            "([0-2][0-3])\\s*h\\s*([0-5][0-9])?",             // 23h30 (24-hour French format)
        ]

        let nsQuery = query as NSString
        let range = NSRange(location: 0, length: nsQuery.length)

        for patternString in patterns {
            if let regex = try? NSRegularExpression(pattern: patternString, options: .caseInsensitive) {
                if let match = regex.firstMatch(in: query, options: [], range: range) {
                    let matchedRange = match.range
                    var timeString = nsQuery.substring(with: matchedRange)

                    // Normalize the extracted time
                    timeString = normalizeTimeFormat(timeString)
                    if !timeString.isEmpty {
                        return timeString
                    }
                }
            }
        }

        return nil
    }

    /// Normalize extracted time string to HH:mm format
    private func normalizeTimeFormat(_ timeString: String) -> String {
        let lowercased = timeString.lowercased().trimmingCharacters(in: .whitespaces)

        // Already in HH:mm format
        if lowercased.contains(":") && !lowercased.contains("am") && !lowercased.contains("pm") {
            return lowercased
        }

        // Extract components
        let components = lowercased.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard components.count >= 1 else { return "" }

        var hours = Int(components[0]) ?? 0
        var minutes = components.count > 1 ? Int(components[1]) ?? 0 : 0

        // Handle 12-hour format
        if lowercased.contains("pm") && hours < 12 {
            hours += 12
        } else if lowercased.contains("am") && hours == 12 {
            hours = 0
        }

        // Validate
        guard hours >= 0 && hours < 24 && minutes >= 0 && minutes < 60 else { return "" }

        return String(format: "%02d:%02d", hours, minutes)
    }

    private func extractDate(from query: String) -> Date? {
        let lowercased = query.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today)
        } else if lowercased.contains("today") {
            return today
        } else if lowercased.contains("next week") {
            return calendar.date(byAdding: .day, value: 7, to: today)
        }

        return today
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Extension for Date ISO8601 formatting
extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
