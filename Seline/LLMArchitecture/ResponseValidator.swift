import Foundation

/// Validates LLM responses against actual user data to prevent hallucinations
@MainActor
class ResponseValidator {
    static let shared = ResponseValidator()

    private init() {}

    // MARK: - Main Validation

    /// Validate LLM response against actual data
    func validateResponse(
        _ llmResponse: LLMResponse,
        against filteredContext: FilteredContext
    ) -> ValidationResult {
        var issues: [ValidationIssue] = []

        // Check confidence first
        if llmResponse.confidence < 0.75 {
            return .lowConfidence(llmResponse)
        }

        // If LLM says it needs clarification, ask the user
        if llmResponse.needsClarification {
            return .needsClarification(clarifyingQuestions: llmResponse.clarifyingQuestions)
        }

        // Validate data references
        if let dataRefs = llmResponse.dataReferences {
            issues.append(contentsOf: validateDataReferences(dataRefs, against: filteredContext))
        }

        // Check for hallucinations (mentions entities not in context)
        issues.append(contentsOf: detectHallucinations(in: llmResponse.response, against: filteredContext))

        // Determine validation result based on issues
        if issues.contains(where: { $0.severity == .critical }) {
            let criticalIssue = issues.first(where: { $0.severity == .critical })!
            return .hallucination(reason: criticalIssue.message)
        }

        let hasWarnings = issues.contains(where: { $0.severity == .warning })
        if hasWarnings {
            return .partiallyValid(llmResponse, issues: issues.map { $0.message })
        }

        // If we got here, response is valid
        return .valid(llmResponse)
    }

    // MARK: - Reference Validation

    /// Validate that referenced data IDs actually exist
    private func validateDataReferences(
        _ refs: LLMResponse.DataReferences,
        against context: FilteredContext
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Validate note IDs
        if let noteIds = refs.noteIds {
            let validNoteIds = Set(context.notes?.map { $0.note.id.uuidString } ?? [])
            for noteId in noteIds {
                if !validNoteIds.contains(noteId) {
                    issues.append(ValidationIssue(
                        severity: .critical,
                        message: "Referenced note '\(noteId)' not found in user's notes",
                        suggestion: "Remove reference to non-existent note"
                    ))
                }
            }
        }

        // Validate location IDs
        if let locationIds = refs.locationIds {
            let validLocationIds = Set(context.locations?.map { $0.place.id.uuidString } ?? [])
            for locationId in locationIds {
                if !validLocationIds.contains(locationId) {
                    issues.append(ValidationIssue(
                        severity: .critical,
                        message: "Referenced location '\(locationId)' not found in saved places",
                        suggestion: "Remove reference to non-existent location"
                    ))
                }
            }
        }

        // Validate task IDs
        if let taskIds = refs.taskIds {
            let validTaskIds = Set(context.tasks?.map { $0.task.id } ?? [])
            for taskId in taskIds {
                if !validTaskIds.contains(taskId) {
                    issues.append(ValidationIssue(
                        severity: .critical,
                        message: "Referenced task '\(taskId)' not found in calendar",
                        suggestion: "Remove reference to non-existent task"
                    ))
                }
            }
        }

        // Validate email IDs
        if let emailIds = refs.emailIds {
            let validEmailIds = Set(context.emails?.map { $0.email.id } ?? [])
            for emailId in emailIds {
                if !validEmailIds.contains(emailId) {
                    issues.append(ValidationIssue(
                        severity: .critical,
                        message: "Referenced email '\(emailId)' not found in inbox",
                        suggestion: "Remove reference to non-existent email"
                    ))
                }
            }
        }

        return issues
    }

    // MARK: - Hallucination Detection

    /// Detect if LLM hallucinated information not in the provided context
    private func detectHallucinations(
        in response: String,
        against context: FilteredContext
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let lowerResponse = response.lowercased()

        // Check for specific false claims
        if context.notes?.isEmpty ?? true {
            // If no notes in context, but response mentions specific notes by title
            let notePatterns = ["note", "notes", "mentioned in my notes", "wrote in my notes"]
            for pattern in notePatterns {
                if lowerResponse.contains(pattern) && lowerResponse.contains("titled") {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Response mentions notes but no notes were provided in context",
                        suggestion: "Ask user to be more specific or refine search"
                    ))
                    break
                }
            }
        }

        if context.locations?.isEmpty ?? true {
            // If no locations in context, but response mentions specific places
            let locationPatterns = ["location", "restaurant", "cafe", "store", "saved place"]
            for pattern in locationPatterns {
                if lowerResponse.contains(pattern) && lowerResponse.contains("you have") {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Response mentions locations but no locations were provided in context",
                        suggestion: "Ask user to clarify location-related query"
                    ))
                    break
                }
            }
        }

        if context.tasks?.isEmpty ?? true {
            // If no events in context, but response lists specific events
            if lowerResponse.contains("your schedule") || lowerResponse.contains("your events") {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Response mentions calendar events but no events were provided in context",
                    suggestion: "Clarify date range or check if user has events for that period"
                ))
            }
        }

        // Check for temporal hallucinations (mentioning events on wrong dates)
        issues.append(contentsOf: validateTemporalAccuracy(response, against: context))

        // Check for contradiction with provided data
        issues.append(contentsOf: checkForContradictions(response, against: context))

        return issues
    }

    /// Validate that mentioned times/dates are accurate
    private func validateTemporalAccuracy(
        _ response: String,
        against context: FilteredContext
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // If we filtered by date range, check response respects it
        if let dateRangeQueried = context.metadata.dateRangeQueried {
            // For "today" queries, response shouldn't mention tomorrow's events
            // For "this week" queries, response shouldn't mention next week's events
            // etc.

            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomorrowStr = formatDateForDetection(tomorrow)

            if dateRangeQueried.contains("today") && response.contains(tomorrowStr) {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Response mentions tomorrow's events when queried for today",
                    suggestion: "Filter response to only include today's events"
                ))
            }
        }

        return issues
    }

    /// Check if response contradicts the provided data
    private func checkForContradictions(
        _ response: String,
        against context: FilteredContext
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Example: If context shows 0 notes, but response says "You have 5 notes"
        if let notes = context.notes {
            if notes.isEmpty && (response.contains("You have") || response.contains("you have")) && response.contains("note") {
                issues.append(ValidationIssue(
                    severity: .critical,
                    message: "Response claims user has notes, but no notes in context",
                    suggestion: "Correct response to state 'No notes found'"
                ))
            }
        }

        // If filtering by date range and response lists items outside that range
        if let dateRange = context.metadata.dateRangeQueried {
            // Check if response mentions outside-range dates
            // This is more complex and would require date parsing
        }

        return issues
    }

    // MARK: - Helper Methods

    /// Format date for detection in text
    private func formatDateForDetection(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"  // "November 8"
        return formatter.string(from: date)
    }

    /// Get user-friendly message for validation result
    func getResultMessage(_ result: ValidationResult) -> String {
        switch result {
        case .valid:
            return ""  // No message needed, response is good

        case .lowConfidence(let response):
            let questions = response.clarifyingQuestions.prefix(2).joined(separator: " Or ")
            return "I'm not entirely sure. Could you clarify: \(questions)?"

        case .hallucination(let reason):
            return "I apologize, but I found an issue: \(reason). Could you rephrase your question?"

        case .partiallyValid(_, let issues):
            let issueList = issues.prefix(1).joined(separator: ". ")
            return "Note: \(issueList). Here's what I found:"

        case .needsClarification(let questions):
            return "I need more information: \(questions.first ?? "Could you be more specific?")"
        }
    }

    /// Should we show this response to the user?
    func shouldShowResponse(_ result: ValidationResult) -> Bool {
        switch result {
        case .valid, .partiallyValid:
            return true
        case .lowConfidence, .hallucination, .needsClarification:
            return false
        }
    }
}
