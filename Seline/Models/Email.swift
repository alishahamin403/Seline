//
//  Email.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation

struct Email: Identifiable, Codable {
    let id: String
    let subject: String
    let sender: EmailContact
    let recipients: [EmailContact]
    let body: String
    let date: Date
    let isRead: Bool
    let isImportant: Bool
    let labels: [String]
    let attachments: [EmailAttachment]
    
    var isPromotional: Bool {
        labels.contains("CATEGORY_PROMOTIONS")
    }
    
    var hasCalendarEvent: Bool {
        labels.contains("CALENDAR") || body.contains("calendar") || body.contains("meeting")
    }
}

struct EmailContact: Identifiable, Codable {
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

struct EmailAttachment: Identifiable, Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int
    
    init(filename: String, mimeType: String, size: Int) {
        self.id = UUID()
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
    }
}