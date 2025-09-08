//
//  LocalEventService.swift
//  Seline
//
//  Created by Claude Code on 2025-09-04.
//

import Foundation
import Combine

/// Service for managing local calendar events
class LocalEventService {
    static let shared = LocalEventService()
    
    @Published private var events: [CalendarEvent] = []
    
    private init() {
        loadSampleEvents()
    }
    
    /// Load sample events for demonstration purposes
    private func loadSampleEvents() {
        let calendar = Calendar.current
        let now = Date()
        
        // Add some sample upcoming events
        var sampleEvents: [CalendarEvent] = []
        
        // Today's events
        if let todayMeeting = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now) {
            sampleEvents.append(CalendarEvent(
                title: "Team Standup",
                description: "Daily team standup meeting",
                startDate: todayMeeting,
                endDate: calendar.date(byAdding: .minute, value: 30, to: todayMeeting) ?? todayMeeting,
                location: "Conference Room A"
            ))
        }
        
        // Tomorrow's events
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrowLunch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) {
            sampleEvents.append(CalendarEvent(
                title: "Client Lunch",
                description: "Lunch meeting with potential client",
                startDate: tomorrowLunch,
                endDate: calendar.date(byAdding: .hour, value: 2, to: tomorrowLunch) ?? tomorrowLunch,
                location: "Downtown Restaurant"
            ))
        }
        
        // Next week events
        if let nextWeek = calendar.date(byAdding: .day, value: 5, to: now),
           let nextWeekWorkshop = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextWeek) {
            sampleEvents.append(CalendarEvent(
                title: "iOS Development Workshop",
                description: "Learn the latest iOS development techniques",
                startDate: nextWeekWorkshop,
                endDate: calendar.date(byAdding: .hour, value: 4, to: nextWeekWorkshop) ?? nextWeekWorkshop,
                location: "Tech Center",
                isAllDay: false
            ))
        }
        
        // Past events for completed calendar
        if let lastWeek = calendar.date(byAdding: .day, value: -7, to: now),
           let pastMeeting = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: lastWeek) {
            sampleEvents.append(CalendarEvent(
                title: "Project Kickoff",
                description: "Initial project planning meeting",
                startDate: pastMeeting,
                endDate: calendar.date(byAdding: .hour, value: 1, to: pastMeeting) ?? pastMeeting,
                location: "Office Building"
            ))
        }
        
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           let pastEvent = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday) {
            sampleEvents.append(CalendarEvent(
                title: "Morning Workout",
                description: "Personal training session",
                startDate: pastEvent,
                endDate: calendar.date(byAdding: .hour, value: 1, to: pastEvent) ?? pastEvent,
                location: "Local Gym"
            ))
        }
        
        events = sampleEvents
        
        #if DEBUG
        print("📅 LocalEventService: Loaded \(sampleEvents.count) sample events")
        #endif
    }
    
    /// Returns upcoming calendar events for the next specified number of days
    func getUpcomingEvents(days: Int) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        
        return events.filter { $0.startDate >= startDate && $0.startDate <= endDate }
    }
    
    /// Returns past calendar events for a specific month
    func getPastEvents(for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let monthEnd = calendar.dateInterval(of: .month, for: date)?.end ?? date
        let now = Date()
        
        return events.filter { event in
            event.startDate >= monthStart && 
            event.startDate <= monthEnd &&
            event.startDate < now  // Only show past events
        }
    }
    
    /// Adds a new local event
    func addEvent(_ event: CalendarEvent) async throws {
        // In a real implementation, this would save to Core Data
        events.append(event)
    }
    
    /// Updates an existing local event
    func updateEvent(_ event: CalendarEvent) async throws {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        }
    }
    
    /// Deletes a local event
    func deleteEvent(id: String) async throws {
        events.removeAll { $0.id == id }
    }
}