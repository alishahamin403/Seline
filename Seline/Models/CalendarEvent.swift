//
//  CalendarEvent.swift
//  Seline
//
//  Created by Claude Code on 2025-09-04.
//

import Foundation

/// Basic calendar event model for Seline
struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let description: String?
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool
    let created: Date
    let modified: Date
    
    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        isAllDay: Bool = false,
        created: Date = Date(),
        modified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.isAllDay = isAllDay
        self.created = created
        self.modified = modified
    }
}

extension CalendarEvent {
    /// Duration of the event in seconds
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    /// Whether the event is happening today
    var isToday: Bool {
        Calendar.current.isDate(startDate, inSameDayAs: Date())
    }
    
    /// Whether the event is currently happening
    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && now <= endDate
    }
    
    /// Formatted time string for display
    var formattedTime: String {
        let formatter = DateFormatter()
        
        if isAllDay {
            return "All Day"
        } else if Calendar.current.isDate(startDate, inSameDayAs: Date()) {
            formatter.timeStyle = .short
            return formatter.string(from: startDate)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: startDate)
        }
    }
}