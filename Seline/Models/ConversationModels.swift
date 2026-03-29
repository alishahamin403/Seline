import Foundation
import SwiftUI

struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let intent: QueryIntent?
    let timeStarted: Date?      // When LLM started thinking
    let timeFinished: Date?     // When LLM finished thinking
    var trackerThreadId: UUID?
    var trackerOperationDraft: TrackerOperationDraft?
    var trackerStateSnapshot: TrackerDerivedState?

    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date(), intent: QueryIntent? = nil, timeStarted: Date? = nil, timeFinished: Date? = nil, trackerThreadId: UUID? = nil, trackerOperationDraft: TrackerOperationDraft? = nil, trackerStateSnapshot: TrackerDerivedState? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.intent = intent
        self.timeStarted = timeStarted
        self.timeFinished = timeFinished
        self.trackerThreadId = trackerThreadId
        self.trackerOperationDraft = trackerOperationDraft
        self.trackerStateSnapshot = trackerStateSnapshot
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

    // For receipts
    let receiptId: UUID?
    let receiptTitle: String?
    let receiptAmount: Double?
    let receiptDate: Date?
    let receiptCategory: String?
    
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

    // For visits
    let visitId: UUID?
    let visitEntryTime: Date?
    let visitExitTime: Date?
    let visitDurationMinutes: Int?
    let visitPlaceId: UUID?
    let visitPlaceName: String?

    // For people
    let personId: UUID?
    let personName: String?
    let personRelationship: String?

    enum ContentType: String, Codable {
        case email
        case note
        case receipt
        case event
        case location
        case visit
        case person
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
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: nil, personName: nil, personRelationship: nil
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
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: nil, personName: nil, personRelationship: nil
        )
    }

    static func receipt(id: UUID, title: String, amount: Double?, date: Date?, category: String?) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .receipt,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: id,
            noteTitle: title,
            noteSnippet: nil,
            noteFolder: "Receipts",
            receiptId: id,
            receiptTitle: title,
            receiptAmount: amount,
            receiptDate: date,
            receiptCategory: category,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: nil, personName: nil, personRelationship: nil
        )
    }

    static func event(id: UUID, title: String, date: Date, category: String) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .event,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: id,
            eventTitle: title,
            eventDate: date,
            eventCategory: category,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: nil, personName: nil, personRelationship: nil
        )
    }

    static func location(id: UUID, name: String, address: String, category: String) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .location,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: id,
            locationName: name,
            locationAddress: address,
            locationCategory: category,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: nil, personName: nil, personRelationship: nil
        )
    }

    static func visit(
        id: UUID,
        placeId: UUID?,
        placeName: String?,
        address: String? = nil,
        entryTime: Date?,
        exitTime: Date?,
        durationMinutes: Int?
    ) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .visit,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: placeId,
            locationName: placeName,
            locationAddress: address,
            locationCategory: nil,
            visitId: id,
            visitEntryTime: entryTime,
            visitExitTime: exitTime,
            visitDurationMinutes: durationMinutes,
            visitPlaceId: placeId,
            visitPlaceName: placeName,
            personId: nil, personName: nil, personRelationship: nil
        )
    }

    static func person(id: UUID, name: String, relationship: String?) -> RelevantContentInfo {
        RelevantContentInfo(
            id: UUID(),
            contentType: .person,
            emailId: nil, emailSubject: nil, emailSender: nil, emailSnippet: nil, emailDate: nil,
            noteId: nil, noteTitle: nil, noteSnippet: nil, noteFolder: nil,
            receiptId: nil, receiptTitle: nil, receiptAmount: nil, receiptDate: nil, receiptCategory: nil,
            eventId: nil, eventTitle: nil, eventDate: nil, eventCategory: nil,
            locationId: nil, locationName: nil, locationAddress: nil, locationCategory: nil,
            visitId: nil, visitEntryTime: nil, visitExitTime: nil, visitDurationMinutes: nil, visitPlaceId: nil, visitPlaceName: nil,
            personId: id,
            personName: name,
            personRelationship: relationship
        )
    }
}

// MARK: - Event Creation Info (for Event Card display in chat)

struct EventCreationInfo: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: Date
    let endDate: Date?
    let hasTime: Bool
    let reminderMinutes: Int?  // nil = no reminder, 0 = at time, 5/10/15/30/60 = before
    let category: String
    let tagId: String?
    let recurrenceFrequency: RecurrenceFrequency?
    let location: String?
    let notes: String?
    var isConfirmed: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        endDate: Date? = nil,
        hasTime: Bool = true,
        reminderMinutes: Int? = nil,
        category: String = "Personal",
        tagId: String? = nil,
        recurrenceFrequency: RecurrenceFrequency? = nil,
        location: String? = nil,
        notes: String? = nil,
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.endDate = endDate
        self.hasTime = hasTime
        self.reminderMinutes = reminderMinutes
        self.category = category
        self.tagId = tagId
        self.recurrenceFrequency = recurrenceFrequency
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
        case .notes: return .primary
        case .locations: return .green
        case .general: return .purple
        }
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
/// Renamed from ConversationState to ConversationContext to avoid conflict with ConversationState class
struct ConversationContext {
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
