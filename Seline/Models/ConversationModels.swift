import Foundation
import SwiftUI

// MARK: - Proactive Question Info (defined early for use in ConversationMessage)

struct ProactiveQuestionInfo: Codable {
    let locationId: UUID
    let locationName: String
    let question: String
    let isFirstVisit: Bool
}

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
    let followUpSuggestions: [FollowUpSuggestion]?  // Suggested follow-up questions/actions
    let locationInfo: ETALocationInfo?  // For ETA/directions queries - shows map card
    var eventCreationInfo: [EventCreationInfo]?  // For event creation - shows confirmation card
    var relevantContent: [RelevantContentInfo]?  // For displaying inline email/note/event cards
    var proactiveQuestion: ProactiveQuestionInfo?  // For proactive questions after location visits

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), intent: QueryIntent? = nil, relatedData: [RelatedDataItem]? = nil, timeStarted: Date? = nil, timeFinished: Date? = nil, followUpSuggestions: [FollowUpSuggestion]? = nil, locationInfo: ETALocationInfo? = nil, eventCreationInfo: [EventCreationInfo]? = nil, relevantContent: [RelevantContentInfo]? = nil, proactiveQuestion: ProactiveQuestionInfo? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.intent = intent
        self.relatedData = relatedData
        self.timeStarted = timeStarted
        self.timeFinished = timeFinished
        self.followUpSuggestions = followUpSuggestions
        self.locationInfo = locationInfo
        self.eventCreationInfo = eventCreationInfo
        self.relevantContent = relevantContent
        self.proactiveQuestion = proactiveQuestion
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

// MARK: - ETA Location Info (for Map Card display)

struct ETALocationInfo: Codable {
    let originName: String?
    let originAddress: String?
    let originLatitude: Double?
    let originLongitude: Double?
    let destinationName: String
    let destinationAddress: String
    let destinationLatitude: Double
    let destinationLongitude: Double
    let driveTime: String?
    let distance: String?
    
    /// Opens directions in Apple Maps or Google Maps
    func openInMaps(preferGoogleMaps: Bool = false) {
        let destLat = destinationLatitude
        let destLon = destinationLongitude
        
        if preferGoogleMaps {
            // Try Google Maps first
            var urlString = "comgooglemaps://?daddr=\(destLat),\(destLon)&directionsmode=driving"
            if let originLat = originLatitude, let originLon = originLongitude {
                urlString = "comgooglemaps://?saddr=\(originLat),\(originLon)&daddr=\(destLat),\(destLon)&directionsmode=driving"
            }
            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        
        // Fall back to Apple Maps
        var urlString = "http://maps.apple.com/?daddr=\(destLat),\(destLon)&dirflg=d"
        if let originLat = originLatitude, let originLon = originLongitude {
            urlString = "http://maps.apple.com/?saddr=\(originLat),\(originLon)&daddr=\(destLat),\(destLon)&dirflg=d"
        }
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Relevant Content Info (for displaying emails, notes, events inline)

struct RelevantContentInfo: Codable, Identifiable {
    let id: UUID
    let contentType: ContentType
    
    // For emails
    let emailId: String?
    let emailSubject: String?
    let emailSender: String?
    let emailSnippet: String?
    let emailDate: Date?
    
    // For notes
    let noteId: UUID?
    let noteTitle: String?
    let noteSnippet: String?
    let noteFolder: String?
    
    // For events
    let eventId: UUID?
    let eventTitle: String?
    let eventDate: Date?
    let eventCategory: String?
    
    // For locations
    let locationId: UUID?
    let locationName: String?
    let locationAddress: String?
    let locationCategory: String?
    
    enum ContentType: String, Codable {
        case email
        case note
        case event
        case location
    }
    
    // Convenience initializers
    static func email(id: String, subject: String, sender: String, snippet: String, date: Date) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .email,
            emailId: id,
            emailSubject: subject,
            emailSender: sender,
            emailSnippet: snippet,
            emailDate: date,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil
        )
    }
    
    static func note(id: UUID, title: String, snippet: String, folder: String) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .note,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: id,
            noteTitle: title,
            noteSnippet: snippet,
            noteFolder: folder,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil
        )
    }
    
    static func event(id: UUID, title: String, date: Date, category: String) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .event,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            eventId: id,
            eventTitle: title,
            eventDate: date,
            eventCategory: category,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil
        )
    }
    
    static func location(id: UUID, name: String, address: String, category: String) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .location,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: id,
            locationName: name,
            locationAddress: address,
            locationCategory: category
        )
    }
}

// MARK: - Event Creation Info (for Event Card display in chat)

struct EventCreationInfo: Codable, Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let hasTime: Bool
    let reminderMinutes: Int?  // nil = no reminder, 0 = at time, 5/10/15/30/60 = before
    let category: String
    let location: String?
    let notes: String?
    var isConfirmed: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        hasTime: Bool = true,
        reminderMinutes: Int? = nil,
        category: String = "Personal",
        location: String? = nil,
        notes: String? = nil,
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.reminderMinutes = reminderMinutes
        self.category = category
        self.location = location
        self.notes = notes
        self.isConfirmed = isConfirmed
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var formattedTime: String {
        guard hasTime else { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDateTime: String {
        if hasTime {
            return "\(formattedDate) at \(formattedTime)"
        } else {
            return "\(formattedDate) (All day)"
        }
    }
    
    var reminderText: String {
        guard let minutes = reminderMinutes else { return "No reminder" }
        switch minutes {
        case 0: return "At time of event"
        case 5: return "5 minutes before"
        case 10: return "10 minutes before"
        case 15: return "15 minutes before"
        case 30: return "30 minutes before"
        case 60: return "1 hour before"
        case 1440: return "1 day before"
        default: return "\(minutes) minutes before"
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

// MARK: - Follow-Up Suggestions

struct FollowUpSuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String  // "Show me the receipt" or "What about last week?"
    let emoji: String  // 💡, 📊, 🔍, etc.
    let category: SuggestionCategory  // For grouping/filtering

    enum SuggestionCategory: String, Codable, Hashable {
        case moreDetails = "more_details"      // "Show me the receipt details"
        case relatedData = "related_data"      // "What about last week?"
        case action = "action"                 // "Should we set a budget?"
        case discovery = "discovery"           // "Want to dig deeper?"
        case clarification = "clarification"   // "Email folders or note folders?"
    }

    init(text: String, emoji: String, category: SuggestionCategory, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.emoji = emoji
        self.category = category
    }
}

