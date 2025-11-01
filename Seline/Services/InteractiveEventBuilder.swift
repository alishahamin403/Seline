import Foundation

/// Manages interactive multi-turn event building through conversation
@MainActor
class InteractiveEventBuilder {
    static let shared = InteractiveEventBuilder()

    private init() {}

    // MARK: - Main Builder Interface

    /// Get the next action to ask the user about
    func getNextStep(for action: InteractiveAction) async -> BuilderStep {
        // If missing required fields, ask about them
        if !action.extractionState.missingRequiredFields.isEmpty {
            let missingField = action.extractionState.missingRequiredFields.first!
            return .askForMissingField(missingField, action: action)
        }

        // We have the minimum required info
        if !action.extractionState.isConfirming {
            return .confirmExtracted(action: action)
        }

        // After confirming, offer suggestions
        if action.extractionState.optionalFields.count > action.extractedInfo.eventReminders.count {
            return .offerOptionalFields(action: action)
        }

        return .readyToSave(action: action)
    }

    // MARK: - Generate Clarifying Questions

    /// Generate clarifying questions for missing or ambiguous info
    func generateClarifyingQuestions(for action: InteractiveAction) async -> [ClarifyingQuestion] {
        var questions: [ClarifyingQuestion] = []

        // Check what's missing
        for missingField in action.extractionState.missingRequiredFields {
            if let question = clarifyingQuestion(for: missingField, action: action) {
                questions.append(question)
            }
        }

        // Check what's ambiguous
        if let date = action.extractedInfo.eventDate, !action.extractedInfo.isAllDay, action.extractedInfo.eventStartTime == nil {
            questions.append(ClarifyingQuestion(
                field: "eventStartTime",
                question: "What time should the event start? (e.g., 6 PM, 14:30)",
                options: nil
            ))
        }

        return questions.prefix(3).map { $0 } // Max 3 questions at once
    }

    /// Generate suggestions for optional fields
    func generateOptionalSuggestions(for action: InteractiveAction) async -> [ActionSuggestion] {
        var suggestions: [ActionSuggestion] = []

        // Suggest reminder if there's a date/time
        if action.extractedInfo.eventDate != nil && action.extractedInfo.eventReminders.isEmpty {
            suggestions.append(ActionSuggestion(
                field: "eventReminders",
                suggestion: "1 hour before (60 minutes)",
                confidence: 0.7,
                reason: "Events usually benefit from a reminder"
            ))
        }

        // Suggest recurrence if title suggests it (meeting, weekly, etc.)
        if action.extractedInfo.eventRecurrence == nil,
           let title = action.extractedInfo.eventTitle,
           title.lowercased().contains("meeting") {
            suggestions.append(ActionSuggestion(
                field: "eventRecurrence",
                suggestion: "Weekly",
                confidence: 0.6,
                reason: "Meetings are often recurring"
            ))
        }

        // Suggest description if empty
        if (action.extractedInfo.eventDescription ?? "").isEmpty {
            suggestions.append(ActionSuggestion(
                field: "eventDescription",
                suggestion: "Add notes or details about the event?",
                confidence: 0.5,
                reason: "Helpful for remembering context"
            ))
        }

        return Array(suggestions.prefix(2))
    }

    // MARK: - Process User Response

    /// Process user's answer to a clarifying question
    func processResponse(
        _ response: String,
        to field: String,
        action: inout InteractiveAction
    ) async {
        switch field {
        case "eventTitle":
            if !response.trimmingCharacters(in: .whitespaces).isEmpty {
                action.extractedInfo.eventTitle = response.trimmingCharacters(in: .whitespaces)
                action.extractionState.confirmField("eventTitle")
            }

        case "eventDate":
            if let date = parseDate(response) {
                action.extractedInfo.eventDate = date
                action.extractionState.confirmField("eventDate")
            }

        case "eventStartTime":
            if let time = parseTime(response) {
                action.extractedInfo.eventStartTime = time
                action.extractionState.confirmField("eventStartTime")
            }

        case "isAllDay":
            let isAllDay = response.lowercased().contains("yes") || response.lowercased().contains("all day")
            action.extractedInfo.isAllDay = isAllDay
            action.extractionState.confirmField("isAllDay")

        case "eventReminders":
            if let minutes = parseReminderTime(response) {
                action.extractedInfo.eventReminders.append(EventReminder(minutesBefore: minutes))
                action.extractionState.confirmField("eventReminders")
            }

        default:
            break
        }

        action.conversationTurns += 1
    }

    // MARK: - User Confirmation Flow

    /// Get confirmation summary text
    func getConfirmationSummary(for action: InteractiveAction) -> String {
        var summary = "📅 \(action.extractedInfo.eventTitle ?? "Untitled Event")\n"

        if let date = action.extractedInfo.eventDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            summary += "📆 \(formatter.string(from: date))\n"
        }

        if let time = action.extractedInfo.eventStartTime {
            summary += "🕐 \(time)"
            if let endTime = action.extractedInfo.eventEndTime {
                summary += " - \(endTime)"
            }
            summary += "\n"
        } else if action.extractedInfo.isAllDay {
            summary += "🕐 All day\n"
        }

        if !action.extractedInfo.eventReminders.isEmpty {
            let reminderTexts = action.extractedInfo.eventReminders.map { $0.displayText }
            summary += "🔔 Reminders: \(reminderTexts.joined(separator: ", "))\n"
        }

        if let recurrence = action.extractedInfo.eventRecurrence {
            summary += "🔁 Repeats: \(recurrence.capitalized)\n"
        }

        if let description = action.extractedInfo.eventDescription, !description.isEmpty {
            summary += "📝 \(description)"
        }

        return summary
    }

    // MARK: - Helper Functions

    private func clarifyingQuestion(for field: String, action: InteractiveAction) -> ClarifyingQuestion? {
        switch field {
        case "eventTitle":
            return ClarifyingQuestion(
                field: "eventTitle",
                question: "What's the name of the event?",
                options: nil
            )

        case "eventDate":
            return ClarifyingQuestion(
                field: "eventDate",
                question: "What date? (e.g., tomorrow, next Monday, 2024-11-04)",
                options: nil
            )

        case "eventStartTime":
            return ClarifyingQuestion(
                field: "eventStartTime",
                question: "What time? (e.g., 6 PM, 18:00, or 'all day')",
                options: nil
            )

        default:
            return nil
        }
    }

    private func parseDate(_ text: String) -> Date? {
        let lower = text.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Quick checks for common phrases
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if lower.contains("today") {
            return today
        }
        if lower.contains("next week") || lower.contains("next week") {
            return calendar.date(byAdding: .day, value: 7, to: today)
        }
        if lower.contains("next monday") {
            let nextMonday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
            return nextMonday
        }

        // Try ISO8601 format
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) {
            return date
        }

        // Try parsing with DateFormatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        if let date = dateFormatter.date(from: text) {
            return date
        }

        return nil
    }

    private func parseTime(_ text: String) -> String? {
        let lower = text.lowercased()

        // Check for "all day"
        if lower.contains("all day") {
            return nil  // Caller should set isAllDay = true
        }

        // Try to extract HH:mm format
        if let regex = try? NSRegularExpression(pattern: "([0-2]?[0-9])\\s*:\\s*([0-5][0-9])", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                if let range = Range(match.range, in: text) {
                    return String(text[range])
                }
            }
        }

        // Try to parse AM/PM time
        if let regex = try? NSRegularExpression(pattern: "([0-2]?[0-9])\\s*(am|pm)", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                if let range = Range(match.range, in: text) {
                    let timeStr = String(text[range])
                    // Convert to 24-hour format
                    return convert12to24Hour(timeStr)
                }
            }
        }

        return nil
    }

    private func convert12to24Hour(_ time12: String) -> String {
        let lower = time12.lowercased()
        let components = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }

        guard let hour = Int(components.first ?? "0") else { return "" }

        var hour24 = hour
        if lower.contains("pm") && hour < 12 {
            hour24 += 12
        } else if lower.contains("am") && hour == 12 {
            hour24 = 0
        }

        let minutes = components.count > 1 ? components[1] : "00"
        return String(format: "%02d:%02d", hour24, Int(minutes) ?? 0)
    }

    private func parseReminderTime(_ text: String) -> Int? {
        let lower = text.lowercased()

        // Check for specific times
        if lower.contains("1 hour") || lower.contains("60 minute") {
            return 60
        }
        if lower.contains("30 minute") {
            return 30
        }
        if lower.contains("15 minute") {
            return 15
        }
        if lower.contains("5 minute") {
            return 5
        }
        if lower.contains("at time") || lower.contains("on time") {
            return 0
        }
        if lower.contains("1 day") || lower.contains("24 hour") {
            return 1440
        }

        // Try to extract minutes
        if let regex = try? NSRegularExpression(pattern: "([0-9]+)\\s*minute", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let matchRange = Range(match.range(at: 1), in: text),
               let minutes = Int(text[matchRange]) {
                return minutes
            }
        }

        return nil
    }
}

// MARK: - Builder Step (What to show user)

enum BuilderStep {
    case askForMissingField(String, action: InteractiveAction)
    case confirmExtracted(action: InteractiveAction)
    case offerOptionalFields(action: InteractiveAction)
    case readyToSave(action: InteractiveAction)
}
