import Foundation

// MARK: - Voice Action Types

enum VoiceAction: String, Codable {
    case createEvent = "create_event"
    case updateEvent = "update_event"
    case deleteEvent = "delete_event"
    case createNote = "create_note"
    case updateNote = "update_note"
    case deleteNote = "delete_note"
    case none = "none"
}

// MARK: - Event Creation Data

struct EventCreationData: Codable, Equatable {
    let title: String
    let description: String?
    let date: String // ISO8601 date string
    let time: String? // Time in "HH:mm" format
    let endTime: String? // End time in "HH:mm" format
    let recurrenceFrequency: String? // "daily", "weekly", "biweekly", "monthly", "yearly"
    let isAllDay: Bool
    let requiresFollowUp: Bool // True if user needs to clarify ambiguous details

    init(
        title: String,
        description: String? = nil,
        date: String,
        time: String? = nil,
        endTime: String? = nil,
        recurrenceFrequency: String? = nil,
        isAllDay: Bool = false,
        requiresFollowUp: Bool = false
    ) {
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

// MARK: - Note Creation Data

struct NoteCreationData: Codable, Equatable {
    let title: String
    let content: String
    let formattedContent: String // Auto-formatted version with bullets, headings, etc.

    init(title: String, content: String, formattedContent: String) {
        self.title = title
        self.content = content
        self.formattedContent = formattedContent
    }
}

// MARK: - Note Update Data

struct NoteUpdateData: Codable {
    let noteTitle: String // The existing note to update
    let contentToAdd: String // New content to append
    let formattedContentToAdd: String // Formatted version

    init(noteTitle: String, contentToAdd: String, formattedContentToAdd: String) {
        self.noteTitle = noteTitle
        self.contentToAdd = contentToAdd
        self.formattedContentToAdd = formattedContentToAdd
    }
}

// MARK: - Event Update Data

struct EventUpdateData: Codable {
    let eventTitle: String // The existing event title to match
    let newDate: String // New ISO8601 date string
    let newTime: String? // New time in "HH:mm" format (optional)
    let newEndTime: String? // New end time in "HH:mm" format (optional)

    init(eventTitle: String, newDate: String, newTime: String? = nil, newEndTime: String? = nil) {
        self.eventTitle = eventTitle
        self.newDate = newDate
        self.newTime = newTime
        self.newEndTime = newEndTime
    }
}

// MARK: - Deletion Data

struct DeletionData: Codable {
    let itemType: String // "event" or "note"
    let itemTitle: String // The title of the item to delete
    let deleteAllOccurrences: Bool? // For recurring events, whether to delete all occurrences

    init(itemType: String, itemTitle: String, deleteAllOccurrences: Bool? = nil) {
        self.itemType = itemType
        self.itemTitle = itemTitle
        self.deleteAllOccurrences = deleteAllOccurrences
    }
}
