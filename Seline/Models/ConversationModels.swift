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

