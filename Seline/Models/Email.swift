//
//  Email.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation

struct Email: Identifiable, Codable, Equatable {
    let id: String
    let threadId: String?
    let subject: String
    let sender: EmailContact
    let recipients: [EmailContact]
    let body: String
    let date: Date
    var isRead: Bool
    let isImportant: Bool
    let labels: [String]
    let attachments: [EmailAttachment]
    let isPromotional: Bool
    let hasCalendarEvent: Bool
    
    // Convenience initializer for backward compatibility
    init(id: String, threadId: String? = nil, subject: String, sender: EmailContact, recipients: [EmailContact], body: String, date: Date, isRead: Bool, isImportant: Bool, labels: [String], attachments: [EmailAttachment] = [], isPromotional: Bool? = nil, hasCalendarEvent: Bool? = nil) {
        self.id = id
        self.threadId = threadId
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.body = body
        self.date = date
        self.isRead = isRead
        self.isImportant = isImportant
        self.labels = labels
        // Safe array access for attachments and labels
        self.attachments = attachments.isEmpty ? [] : attachments
        self.isPromotional = isPromotional ?? (labels.isEmpty ? false : labels.contains("CATEGORY_PROMOTIONS"))
        // Detect calendar events from content if not explicitly provided
        self.hasCalendarEvent = hasCalendarEvent ?? Email.detectCalendarEvent(from: body, labels: labels)
    }
    
    // Helper function to detect calendar events in email content
    private static func detectCalendarEvent(from body: String, labels: [String]) -> Bool {
        // Check if email contains calendar-related keywords
        let calendarKeywords = ["meeting", "appointment", "calendar", "schedule", "invite", "event", "zoom", "teams", "conference", "call"]
        let lowercaseBody = body.lowercased()
        let hasCalendarKeywords = calendarKeywords.contains { keyword in
            lowercaseBody.contains(keyword)
        }
        
        // Check if email has calendar-related labels
        let hasCalendarLabel = labels.contains { label in
            label.lowercased().contains("calendar") || label.lowercased().contains("event")
        }
        
        return hasCalendarKeywords || hasCalendarLabel
    }
    
    /// Computed property to check if email has attachments
    var hasAttachments: Bool {
        return !attachments.isEmpty
    }
}

struct EmailContact: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String?
    let email: String
    
    init(name: String?, email: String) {
        self.id = UUID()
        self.name = name
        self.email = email
    }
    
    var displayName: String {
        name ?? email
    }
}

struct EmailAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int
    
    init(filename: String, mimeType: String, size: Int) {
        self.id = UUID()
        self.filename = filename
        self.mimeType = mimeType
        self.size = max(0, size) // Ensure size is never negative
    }
}

// MARK: - Email Safe Array Extensions

extension Email {
    /// Safe access to recipients array
    var safeRecipients: [EmailContact] {
        guard !recipients.isEmpty else {
            print("🔍 Email.safeRecipients: No recipients for email \(id)")
            return []
        }
        return recipients
    }
    
    /// Safe access to labels array
    var safeLabels: [String] {
        guard !labels.isEmpty else {
            print("🔍 Email.safeLabels: No labels for email \(id)")
            return []
        }
        return labels
    }
    
    /// Safe access to attachments array
    var safeAttachments: [EmailAttachment] {
        guard !attachments.isEmpty else {
            print("🔍 Email.safeAttachments: No attachments for email \(id)")
            return []
        }
        return attachments
    }
    
    /// Safe access to first recipient
    var primaryRecipient: EmailContact? {
        return recipients.safeElement(at: 0)
    }
    
    /// Safe attachment count
    var safeAttachmentCount: Int {
        return max(0, attachments.count)
    }
}
