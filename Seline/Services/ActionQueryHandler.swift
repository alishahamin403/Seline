import Foundation

/// Handles parsing and preparing action confirmations from user queries
class ActionQueryHandler {
    static let shared = ActionQueryHandler()

    // MARK: - Event Creation Parsing

    /// Attempts to parse an event creation request
    /// Example: "add meeting with Sarah at 3pm tomorrow"
    func parseEventCreation(from query: String) -> EventCreationData? {
        var title = extractEventTitle(from: query)
        let time = extractTime(from: query)
        let date = extractDate(from: query)

        // If we couldn't extract a clear title, use a generic one
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

    /// Attempts to parse a note creation request
    /// Example: "create note about meeting with Sarah"
    func parseNoteCreation(from query: String) -> NoteCreationData? {
        let title = extractNoteTitle(from: query)

        return NoteCreationData(
            title: title.isEmpty ? "New Note" : title,
            content: "",
            formattedContent: ""
        )
    }

    // MARK: - Helper Methods

    private func extractEventTitle(from query: String) -> String {
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
        let pattern = "\\b([0-1]?[0-9])(:[0-5][0-9])?\\s*(am|pm)?\\b"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let nsQuery = query as NSString
        let range = NSRange(location: 0, length: nsQuery.length)

        if let match = regex?.firstMatch(in: query, options: [], range: range) {
            let matchedRange = match.range
            return nsQuery.substring(with: matchedRange)
        }

        return nil
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
