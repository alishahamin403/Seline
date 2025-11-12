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
    let timeStarted: Date?      // When LLM started thinking
    let timeFinished: Date?     // When LLM finished thinking

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), intent: QueryIntent? = nil, relatedData: [RelatedDataItem]? = nil, timeStarted: Date? = nil, timeFinished: Date? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.intent = intent
        self.relatedData = relatedData
        self.timeStarted = timeStarted
        self.timeFinished = timeFinished
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Time taken by LLM to generate response in seconds
    var timeTakenSeconds: Int? {
        guard !isUser, let started = timeStarted, let finished = timeFinished else { return nil }
        return Int(finished.timeIntervalSince(started).rounded())
    }

    /// Formatted time taken string (e.g., "2 seconds", "1 minute 30 seconds")
    var timeTakenFormatted: String? {
        guard let seconds = timeTakenSeconds else { return nil }
        if seconds < 60 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds == 0 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s")"
            } else {
                return "\(minutes) minute\(minutes == 1 ? "" : "s") \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")"
            }
        }
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
    let amount: Double?  // For receipts
    let merchant: String?  // For receipts

    enum DataType: String, Codable {
        case event
        case note
        case location
        case receipt
        case email
    }

    init(id: UUID = UUID(), type: DataType, title: String, subtitle: String? = nil, date: Date? = nil, amount: Double? = nil, merchant: String? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.amount = amount
        self.merchant = merchant
    }
}

// MARK: - Conversation Summary (for smart memory)

/// Summarized version of a conversation message for older context
struct ConversationSummary: Codable {
    let originalMessageId: UUID
    let userQuestion: String  // What the user asked
    let keyPoints: [String]   // Key facts from the response
    let dataTypes: [String]   // What types of data were discussed
    let timestamp: Date
}

/// Extended conversation message with optional summary
struct ConversationMessageWithSummary {
    let message: ConversationMessage
    let summary: ConversationSummary?  // Non-nil if this is a summarized message
}

// MARK: - Conversation State Tracking

/// Tracks the current state of a conversation to avoid redundancy
struct ConversationState {
    let topicsDiscussed: [ConversationTopic]  // What's been talked about
    let lastQuestionType: String?  // Type of last question (spending, events, etc.)
    let isProbablyFollowUp: Bool  // Is this likely a follow-up to the last question?
    let suggestedApproach: String  // How should LLM approach this response?
}

struct ConversationTopic {
    let topic: String  // "spending", "restaurants", "events", etc.
    let context: String  // Brief context of what was discussed
    let messageCount: Int  // How many messages about this topic
    let lastMentionedIndex: Int  // Index of last mention in conversation
}

