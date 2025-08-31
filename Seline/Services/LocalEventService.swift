//
//  LocalEventService.swift
//  Seline
//
//  Created for in-app event creation and local storage
//

import Foundation
import Combine

/// Service for managing locally created calendar events
class LocalEventService {
    static let shared = LocalEventService()

    private let userDefaults = UserDefaults.standard
    private let eventsKey = "localCalendarEvents"

    @Published private(set) var localEvents: [LocalCalendarEvent] = []

    private init() {
        loadLocalEvents()
    }

    // MARK: - Event Management

    /// Save a new event locally
    func saveEvent(_ event: CalendarEvent) async {
        let localEvent = convertToLocalCalendarEvent(event)
        var updatedEvents = localEvents
        updatedEvents.append(localEvent)
        localEvents = updatedEvents
        saveToStorage()
    }

    /// Update an existing event
    func updateEvent(_ updatedEvent: CalendarEvent) async {
        let localEvent = convertToLocalCalendarEvent(updatedEvent)
        var updatedEvents = localEvents
        if let index = updatedEvents.firstIndex(where: { $0.id == updatedEvent.id }) {
            updatedEvents[index] = localEvent
            localEvents = updatedEvents
            saveToStorage()
        }
    }

    /// Delete an event
    func deleteEvent(_ eventId: String) async {
        localEvents = localEvents.filter { $0.id != eventId }
        saveToStorage()
    }

    /// Get all upcoming events (both local and synced)
    func getUpcomingEvents(days: Int = 14) -> [CalendarEvent] {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now

        return localEvents.filter { event in
            event.startDate >= now && event.startDate <= futureDate
        }.map { $0.asCalendarEvent }
        .sorted { $0.startDate < $1.startDate }
    }

    /// Get events for a specific date
    func getEventsForDate(_ date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return localEvents.filter { event in
            event.startDate >= startOfDay && event.startDate < endOfDay
        }.map { $0.asCalendarEvent }
        .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Storage

    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(localEvents)
            userDefaults.set(data, forKey: eventsKey)
        } catch {
            print("❌ Failed to save local events: \(error.localizedDescription)")
        }
    }

    private func loadLocalEvents() {
        guard let data = userDefaults.data(forKey: eventsKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            localEvents = try decoder.decode([LocalCalendarEvent].self, from: data)
        } catch {
            print("❌ Failed to load local events: \(error.localizedDescription)")
            localEvents = []
        }
    }

    // MARK: - Sync Status

    /// Mark an event as synced to Google Calendar
    func markEventAsSynced(_ eventId: String) async {
        if let index = localEvents.firstIndex(where: { $0.id == eventId }) {
            var event = localEvents[index]
            event.isLocalOnly = false
            localEvents[index] = event
            saveToStorage()
        }
    }

    /// Get events that need syncing
    func getUnsyncedEvents() -> [CalendarEvent] {
        return localEvents.filter { $0.isLocalOnly == true }.map { $0.asCalendarEvent }
    }

    /// Convert CalendarEvent to LocalCalendarEvent
    private func convertToLocalCalendarEvent(_ event: CalendarEvent) -> LocalCalendarEvent {
        return LocalCalendarEvent(
            id: event.id,
            title: event.title,
            description: event.description,
            startDate: event.startDate,
            endDate: event.endDate,
            timeZone: event.timeZone,
            location: event.location,
            attendees: event.attendees,
            isAllDay: event.isAllDay,
            recurrence: event.recurrence,
            meetingLink: event.meetingLink,
            calendarId: event.calendarId,
            isLocalOnly: true,
            createdLocally: true // Since we're saving it locally, mark as created locally
        )
    }

    // MARK: - Cleanup

    /// Remove events older than specified days
    func cleanupOldEvents(olderThan days: Int = 30) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        localEvents = localEvents.filter { event in
            // Keep upcoming events and recent past events
            event.startDate >= cutoffDate || event.startDate >= Date()
        }

        saveToStorage()
    }
}

// MARK: - CalendarEvent Extensions

extension CalendarEvent {
    /// Whether this event exists only locally (not synced to Google Calendar)
    var isLocalOnly: Bool {
        return LocalEventService.shared.localEvents.contains { $0.id == self.id && $0.isLocalOnly }
    }

    /// Whether this event was created locally in the app
    var createdLocally: Bool {
        return LocalEventService.shared.localEvents.contains { $0.id == self.id && $0.createdLocally }
    }
}

/// Extended CalendarEvent for local storage with additional metadata
struct LocalCalendarEvent: Codable {
    let id: String
    let title: String
    let description: String?
    let startDate: Date
    let endDate: Date
    let timeZone: String
    let location: String?
    let attendees: [EventAttendee]
    let isAllDay: Bool
    let recurrence: [String]?
    let meetingLink: String?
    let calendarId: String
    var isLocalOnly: Bool
    let createdLocally: Bool

    // Convert to CalendarEvent
    var asCalendarEvent: CalendarEvent {
        return CalendarEvent(
            id: id,
            title: title,
            description: description,
            startDate: startDate,
            endDate: endDate,
            timeZone: timeZone,
            location: location,
            attendees: attendees,
            isAllDay: isAllDay,
            recurrence: recurrence,
            meetingLink: meetingLink,
            calendarId: calendarId
        )
    }
}

// MARK: - Helper Extensions

extension Array where Element == CalendarEvent {
    /// Convert LocalCalendarEvent array to CalendarEvent array
    static func fromLocalEvents(_ localEvents: [LocalCalendarEvent]) -> [CalendarEvent] {
        return localEvents.map { $0.asCalendarEvent }
    }
}
