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
    
    private init() {}
    
    /// Returns upcoming calendar events for the next specified number of days
    func getUpcomingEvents(days: Int) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        
        return events.filter { $0.startDate >= startDate && $0.startDate <= endDate }
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