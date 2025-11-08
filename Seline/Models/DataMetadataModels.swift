import Foundation

// MARK: - Comprehensive Metadata Models for Intelligent LLM Filtering

/// Lightweight metadata for all data types - sent to LLM for intelligent filtering
struct AppDataMetadata: Codable {
    let receipts: [ReceiptMetadata]
    let events: [EventMetadata]
    let locations: [LocationMetadata]
    let notes: [NoteMetadata]
    let emails: [EmailMetadata]

    var isEmpty: Bool {
        receipts.isEmpty && events.isEmpty && locations.isEmpty && notes.isEmpty && emails.isEmpty
    }
}

// MARK: - Receipt Metadata

struct ReceiptMetadata: Codable, Identifiable {
    let id: UUID
    let merchant: String
    let amount: Double
    let date: Date
    let category: String? // food, gas, etc
    let preview: String? // First 50 chars of content

    var formattedAmount: String {
        String(format: "$%.2f", amount)
    }
}

// MARK: - Event Metadata

struct EventMetadata: Codable, Identifiable {
    let id: String
    let title: String
    let date: Date?
    let time: Date? // scheduled time
    let endTime: Date?
    let description: String? // description field
    let location: String? // location if available
    let reminder: String? // reminder time
    let isRecurring: Bool
    let recurrencePattern: String? // "daily", "weekly", "monthly"
    let isCompleted: Bool
    let completedDates: [Date]? // for recurring: which instances were completed

    var formattedDateTime: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        guard let eventDate = date else { return "No date" }
        return dateFormatter.string(from: eventDate)
    }
}

// MARK: - Location Metadata

struct LocationMetadata: Codable, Identifiable {
    let id: UUID
    let name: String
    let customName: String?
    let category: String // cuisine/category type
    let address: String
    let userRating: Int? // 1-10 user rating
    let notes: String? // user's notes about the restaurant
    let cuisine: String? // user's cuisine classification
    let dateCreated: Date
    let dateModified: Date

    var displayName: String {
        customName ?? name
    }

    var hasNotes: Bool {
        notes?.isEmpty == false
    }
}

// MARK: - Note Metadata

struct NoteMetadata: Codable, Identifiable {
    let id: UUID
    let title: String
    let preview: String // First 100 chars
    let dateCreated: Date
    let dateModified: Date
    let isPinned: Bool
    let folder: String? // folder name if applicable

    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: dateModified)
    }
}

// MARK: - Email Metadata

struct EmailMetadata: Codable, Identifiable {
    let id: String
    let from: String // sender email
    let subject: String
    let snippet: String // first line of email
    let date: Date
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool

    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

// MARK: - LLM Response Model

/// Response from LLM indicating which data it needs
struct DataFilteringResponse: Codable {
    let receiptIds: [UUID]?
    let eventIds: [String]?
    let locationIds: [UUID]?
    let noteIds: [UUID]?
    let emailIds: [String]?
    let reasoning: String? // why it selected these items

    var isEmpty: Bool {
        (receiptIds?.isEmpty ?? true) &&
        (eventIds?.isEmpty ?? true) &&
        (locationIds?.isEmpty ?? true) &&
        (noteIds?.isEmpty ?? true) &&
        (emailIds?.isEmpty ?? true)
    }
}
