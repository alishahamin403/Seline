import Foundation

/// Simple service that provides the LLM with access to all user app data
/// allowing it to understand context and make connections across topics
class AppContextService {
    static let shared = AppContextService()

    // MARK: - Get Full App Context

    /// Returns formatted string of all user data for LLM context
    /// This is injected into prompts so the LLM can reference any data in the app
    func getFullAppContext() -> String {
        var context = ""

        // Events/Tasks
        let events = TaskManager.shared.allTasks
        if !events.isEmpty {
            context += "**Events & Tasks:**\n"
            for event in events.sorted(by: { ($0.scheduledTime ?? $0.targetDate ?? Date()) < ($1.scheduledTime ?? $1.targetDate ?? Date()) }) {
                context += formatEvent(event)
            }
        }

        // Notes
        let notes = NotesManager.shared.notes
        if !notes.isEmpty {
            context += "\n**Notes:**\n"
            for note in notes.sorted(by: { $0.dateCreated > $1.dateCreated }) {
                context += formatNote(note)
            }
        }

        // Emails
        let emails = EmailService.shared.emails
        if !emails.isEmpty {
            context += "\n**Recent Emails:**\n"
            for email in emails.prefix(10) {
                context += formatEmail(email)
            }
        }

        // Locations
        let locations = LocationsManager.shared.savedPlaces
        if !locations.isEmpty {
            context += "\n**Saved Places:**\n"
            for location in locations {
                context += formatLocation(location)
            }
        }

        return context
    }

    // MARK: - Get Context for Specific Query

    /// Finds relevant app data related to the query
    /// Helps LLM make connections when answering or taking actions
    func getRelevantContext(for query: String) -> String {
        let keywords = extractKeywords(from: query)
        var matches: [String] = []

        // Find matching events
        for event in TaskManager.shared.allTasks {
            if keywordsMatch(keywords, in: event.title) || (event.description != nil && keywordsMatch(keywords, in: event.description!)) {
                matches.append(formatEvent(event))
            }
        }

        // Find matching notes
        for note in NotesManager.shared.notes {
            if keywordsMatch(keywords, in: note.title) || keywordsMatch(keywords, in: note.content) {
                matches.append(formatNote(note))
            }
        }

        // Find matching emails
        for email in EmailService.shared.emails {
            if keywordsMatch(keywords, in: email.subject) || keywordsMatch(keywords, in: email.summary ?? "") {
                matches.append(formatEmail(email))
            }
        }

        // Find matching locations
        for location in LocationsManager.shared.savedPlaces {
            if keywordsMatch(keywords, in: location.name) || (location.customName != nil && keywordsMatch(keywords, in: location.customName!)) {
                matches.append(formatLocation(location))
            }
        }

        if matches.isEmpty {
            return "" // Return empty if no matches, don't pollute context
        }

        return "Relevant app data found:\n" + matches.joined(separator: "\n")
    }

    // MARK: - Formatting Helpers

    private func formatEvent(_ event: TaskItem) -> String {
        let dateStr = (event.scheduledTime ?? event.targetDate).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No date"
        let completed = event.isCompleted ? "✓ DONE" : "○ TODO"
        let recurring = event.isRecurring ? " (recurring: \(event.recurrenceFrequency ?? ""))" : ""

        var formatted = "- [\(completed)] **\(event.title)**\n  📅 \(dateStr)\(recurring)\n"

        if let desc = event.description, !desc.isEmpty {
            formatted += "  📝 \(desc)\n"
        }

        if let email = event.emailSubject {
            formatted += "  📧 Email: \(email)\n"
        }

        return formatted
    }

    private func formatNote(_ note: Note) -> String {
        let preview = note.content.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
        let dateStr = note.dateModified.formatted(date: .abbreviated, time: .omitted)
        let pinned = note.isPinned ? "📌 " : ""

        var formatted = "- \(pinned)**\(note.title)**\n  💾 \(dateStr)\n"

        if !preview.isEmpty {
            formatted += "  Preview: \(preview)...\n"
        }

        return formatted
    }

    private func formatEmail(_ email: Email) -> String {
        let dateStr = email.timestamp.formatted(date: .abbreviated, time: .shortened)
        let important = email.isImportant ? "⭐ " : ""

        let formatted = "- \(important)**\(email.subject)**\n  From: \(email.senderName)\n  📅 \(dateStr)\n  Summary: \(email.summary ?? email.snippet)\n"

        return formatted
    }

    private func formatLocation(_ location: SavedPlace) -> String {
        let displayName = location.customName ?? location.name
        let rating = location.userRating.map { "⭐ \($0)/10" } ?? "Not rated"

        var formatted = "- **\(displayName)**\n  📍 \(location.address)\n  \(rating)\n"

        if let category = location.category {
            formatted += "  Category: \(category)\n"
        }

        if let notes = location.userNotes, !notes.isEmpty {
            formatted += "  Notes: \(notes)\n"
        }

        return formatted
    }

    // MARK: - Helper Methods

    private func extractKeywords(from text: String) -> [String] {
        return text
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private func keywordsMatch(_ keywords: [String], in text: String) -> Bool {
        let lowerText = text.lowercased()
        return keywords.contains { keyword in
            lowerText.contains(keyword)
        }
    }
}
