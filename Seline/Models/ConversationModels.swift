import Foundation
import SwiftUI

// MARK: - Conversation Models

struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let intent: QueryIntent?
    let relatedData: [RelatedDataItem]?

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), intent: QueryIntent? = nil, relatedData: [RelatedDataItem]? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.intent = intent
        self.relatedData = relatedData
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Query Intent

enum QueryIntent: String, Codable {
    case calendar = "calendar"
    case notes = "notes"
    case locations = "locations"
    case general = "general"

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .locations: return "map"
        case .general: return "bubble.left"
        }
    }

    var color: Color {
        switch self {
        case .calendar: return .blue
        case .notes: return .orange
        case .locations: return .green
        case .general: return .purple
        }
    }
}

// MARK: - Related Data

struct RelatedDataItem: Identifiable, Codable {
    let id: UUID
    let type: DataType
    let title: String
    let subtitle: String?
    let date: Date?

    enum DataType: String, Codable {
        case event
        case note
        case location
    }

    init(id: UUID = UUID(), type: DataType, title: String, subtitle: String? = nil, date: Date? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.date = date
    }
}

// MARK: - Voice Assistant State

enum VoiceAssistantState: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case error(String)

    static func == (lhs: VoiceAssistantState, rhs: VoiceAssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.listening, .listening),
             (.processing, .processing),
             (.speaking, .speaking):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "Tap to speak"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .speaking: return "Speaking..."
        case .error(let message): return "Error: \(message)"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "mic.fill"
        case .listening: return "waveform"
        case .processing: return "hourglass"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .blue
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .green
        case .error: return .red
        }
    }
}

// MARK: - OpenAI Response Models

struct VoiceQueryResponse: Codable {
    let intent: String
    let searchQuery: String?
    let dateRange: DateRangeQuery?
    let category: String?
    let response: String
    let action: String? // VoiceAction: "create_event", "update_event", "delete_event", "create_note", "update_note", "delete_note", "none"
    let eventData: EventCreationData?
    let eventUpdateData: EventUpdateData?
    let noteData: NoteCreationData?
    let noteUpdateData: NoteUpdateData?
    let deletionData: DeletionData?
    let followUpQuestion: String? // For handling ambiguous cases

    struct DateRangeQuery: Codable {
        let startDate: String?
        let endDate: String?
    }

    func getIntent() -> QueryIntent {
        return QueryIntent(rawValue: intent) ?? .general
    }

    func getAction() -> VoiceAction {
        guard let action = action else { return .none }
        return VoiceAction(rawValue: action) ?? .none
    }
}
