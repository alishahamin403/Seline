//
//  EmailContentModels.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation

// MARK: - Email Content Analysis Models

struct EmailContentStructure {
    var meetingInfo: MeetingInfo?
    var actionItems: [ActionItem] = []
    var dates: [ImportantDate] = []
    var contacts: [String] = [] // For EnhancedTextRenderer compatibility
    
    init() {
        self.meetingInfo = nil
        self.actionItems = []
        self.dates = []
        self.contacts = []
    }
}

struct MeetingInfo {
    var title: String?
    var time: String?
    var joinUrl: String?
    var date: Date?
    var location: String?
    var attendees: [String] = []
    
    init() {
        self.title = nil
        self.time = nil
        self.joinUrl = nil
        self.date = nil
        self.location = nil
        self.attendees = []
    }
}

struct ActionItem {
    let id: UUID
    let text: String
    let isCompleted: Bool
    
    init(text: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
    }
}

struct ImportantDate {
    let id: UUID
    let date: Date
    let description: String
    
    init(date: Date, description: String) {
        self.id = UUID()
        self.date = date
        self.description = description
    }
}