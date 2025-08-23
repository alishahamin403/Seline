//
//  CalendarService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
// import GoogleAPIClientForREST

protocol CalendarServiceProtocol {
    func fetchUpcomingEvents(days: Int) async throws -> [CalendarEvent]
    func fetchTodaysEvents() async throws -> [CalendarEvent]
    func fetchEventsForDate(_ date: Date) async throws -> [CalendarEvent]
}

class CalendarService: CalendarServiceProtocol {
    static let shared = CalendarService()
    
    private let authService = AuthenticationService.shared
    // private var service: GTLRCalendarService
    
    private init() {
        // TODO: Initialize Calendar service when packages are added
        /*
        service = GTLRCalendarService()
        service.shouldFetchNextPages = true
        service.isRetryEnabled = true
        */
    }
    
    private func setupAuthorizationIfNeeded() async {
        // TODO: Setup authorization with access token
        /*
        if let accessToken = authService.user?.accessToken {
            service.authorizer = GTMFetcherAuthorizationProtocol(accessToken: accessToken)
        }
        */
    }
    
    // MARK: - Public API Methods
    
    func fetchUpcomingEvents(days: Int = 7) async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Calendar API call
        /*
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        
        query.timeMin = GTLRDateTime(date: now)
        query.timeMax = GTLRDateTime(date: endDate)
        query.singleEvents = true
        query.orderBy = "startTime"
        query.maxResults = 50
        
        let response = try await executeQuery(query)
        return convertGTLREventsToCalendarEvents(response.items ?? [])
        */
        
        // Mock implementation for development
        return try await fetchMockUpcomingEvents(days: days)
    }
    
    func fetchTodaysEvents() async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Calendar API call
        /*
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        
        query.timeMin = GTLRDateTime(date: today)
        query.timeMax = GTLRDateTime(date: tomorrow)
        query.singleEvents = true
        query.orderBy = "startTime"
        
        let response = try await executeQuery(query)
        return convertGTLREventsToCalendarEvents(response.items ?? [])
        */
        
        // Mock implementation
        let upcomingEvents = try await fetchMockUpcomingEvents(days: 1)
        return upcomingEvents.filter { Calendar.current.isDateInToday($0.startDate) }
    }
    
    func fetchEventsForDate(_ date: Date) async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Calendar API call
        /*
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        query.timeMin = GTLRDateTime(date: startOfDay)
        query.timeMax = GTLRDateTime(date: endOfDay)
        query.singleEvents = true
        query.orderBy = "startTime"
        
        let response = try await executeQuery(query)
        return convertGTLREventsToCalendarEvents(response.items ?? [])
        */
        
        // Mock implementation
        let upcomingEvents = try await fetchMockUpcomingEvents(days: 7)
        return upcomingEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }
    
    // MARK: - Helper Methods
    
    private func refreshTokenIfNeeded() async throws {
        if authService.user?.isTokenExpired == true {
            await authService.refreshTokenIfNeeded()
        }
        
        guard authService.isAuthenticated else {
            throw CalendarError.notAuthenticated
        }
        
        await setupAuthorizationIfNeeded()
    }
    
    /*
    private func executeQuery<T>(_ query: T) async throws -> T.Response where T: GTLRQuery {
        return try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { ticket, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result as? T.Response {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: CalendarError.invalidResponse)
                }
            }
        }
    }
    
    private func convertGTLREventsToCalendarEvents(_ events: [GTLRCalendar_Event]) -> [CalendarEvent] {
        return events.compactMap { event in
            guard let eventId = event.identifier,
                  let summary = event.summary else { return nil }
            
            let startDate: Date
            let endDate: Date
            
            // Handle all-day events
            if let startDate = event.start?.date?.date {
                startDate = startDate
                endDate = event.end?.date?.date ?? startDate
            } else if let startDateTime = event.start?.dateTime?.date {
                startDate = startDateTime
                endDate = event.end?.dateTime?.date ?? startDate
            } else {
                return nil
            }
            
            let timeZone = event.start?.timeZone ?? TimeZone.current.identifier
            
            return CalendarEvent(
                id: eventId,
                title: summary,
                description: event.descriptionProperty,
                startDate: startDate,
                endDate: endDate,
                timeZone: timeZone,
                location: event.location,
                attendees: event.attendees?.compactMap { attendee in
                    guard let email = attendee.email else { return nil }
                    return EventAttendee(
                        email: email,
                        name: attendee.displayName,
                        responseStatus: convertResponseStatus(attendee.responseStatus)
                    )
                } ?? [],
                isAllDay: event.start?.date != nil,
                recurrence: event.recurrence,
                meetingLink: extractMeetingLink(from: event.descriptionProperty ?? ""),
                calendarId: event.organizer?.email ?? "primary"
            )
        }
    }
    
    private func convertResponseStatus(_ status: String?) -> EventAttendeeStatus {
        switch status {
        case "accepted":
            return .accepted
        case "declined":
            return .declined
        case "tentative":
            return .tentative
        default:
            return .needsAction
        }
    }
    */
    
    private func extractMeetingLink(from description: String) -> String? {
        let patterns = [
            "https://zoom.us/j/[0-9]+",
            "https://meet.google.com/[a-z-]+",
            "https://teams.microsoft.com/l/meetup-join/[^\\s]+",
            "https://[^\\s]*webex[^\\s]*"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)) {
                return String(description[Range(match.range, in: description)!])
            }
        }
        
        return nil
    }
    
    // MARK: - Mock Data (for development)
    
    private func fetchMockUpcomingEvents(days: Int) async throws -> [CalendarEvent] {
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let now = Date()
        let calendar = Calendar.current
        
        return [
            CalendarEvent(
                id: "calendar_1",
                title: "Team Standup",
                description: "Daily team standup meeting to discuss progress and blockers",
                startDate: calendar.date(byAdding: .hour, value: 2, to: now) ?? now,
                endDate: calendar.date(byAdding: .hour, value: 2, to: now)?.addingTimeInterval(1800) ?? now,
                timeZone: TimeZone.current.identifier,
                location: nil,
                attendees: [
                    EventAttendee(email: "john@company.com", name: "John Doe", responseStatus: .accepted),
                    EventAttendee(email: "jane@company.com", name: "Jane Smith", responseStatus: .accepted)
                ],
                isAllDay: false,
                recurrence: ["RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR"],
                meetingLink: "https://zoom.us/j/123456789",
                calendarId: "primary"
            ),
            CalendarEvent(
                id: "calendar_2",
                title: "Client Presentation",
                description: "Quarterly business review presentation for ABC Corp",
                startDate: calendar.date(byAdding: .hour, value: 4, to: now) ?? now,
                endDate: calendar.date(byAdding: .hour, value: 5, to: now) ?? now,
                timeZone: TimeZone.current.identifier,
                location: "Conference Room A",
                attendees: [
                    EventAttendee(email: "client@abccorp.com", name: "Client Representative", responseStatus: .accepted),
                    EventAttendee(email: "sales@company.com", name: "Sales Team", responseStatus: .accepted)
                ],
                isAllDay: false,
                recurrence: nil,
                meetingLink: nil,
                calendarId: "primary"
            ),
            CalendarEvent(
                id: "calendar_3",
                title: "Project Planning Workshop",
                description: "Q1 2025 project planning and resource allocation workshop. Please bring your project proposals and timeline estimates.",
                startDate: calendar.date(byAdding: .day, value: 1, to: now) ?? now,
                endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(10800) ?? now,
                timeZone: TimeZone.current.identifier,
                location: "Main Conference Room",
                attendees: [
                    EventAttendee(email: "pm@company.com", name: "Project Manager", responseStatus: .accepted),
                    EventAttendee(email: "lead@company.com", name: "Tech Lead", responseStatus: .tentative)
                ],
                isAllDay: false,
                recurrence: nil,
                meetingLink: "https://meet.google.com/abc-defg-hij",
                calendarId: "primary"
            ),
            CalendarEvent(
                id: "calendar_4",
                title: "Company All-Hands",
                description: "Monthly company all-hands meeting with updates from leadership",
                startDate: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
                endDate: calendar.date(byAdding: .day, value: 2, to: now)?.addingTimeInterval(3600) ?? now,
                timeZone: TimeZone.current.identifier,
                location: "Virtual",
                attendees: [],
                isAllDay: false,
                recurrence: ["RRULE:FREQ=MONTHLY"],
                meetingLink: "https://zoom.us/j/987654321",
                calendarId: "primary"
            )
        ]
    }
}

// MARK: - Models

struct CalendarEvent: Identifiable, Codable {
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
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        if isAllDay {
            return "All day"
        } else {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(startDate)
    }
    
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(startDate)
    }
    
    var isUpcoming: Bool {
        startDate > Date()
    }
}

struct EventAttendee: Identifiable, Codable {
    let id: UUID
    let email: String
    let name: String?
    let responseStatus: EventAttendeeStatus
    
    init(email: String, name: String?, responseStatus: EventAttendeeStatus) {
        self.id = UUID()
        self.email = email
        self.name = name
        self.responseStatus = responseStatus
    }
    
    var displayName: String {
        name ?? email
    }
}

enum EventAttendeeStatus: String, Codable, CaseIterable {
    case needsAction = "needsAction"
    case declined = "declined"
    case tentative = "tentative"
    case accepted = "accepted"
    
    var displayText: String {
        switch self {
        case .needsAction:
            return "No response"
        case .declined:
            return "Declined"
        case .tentative:
            return "Maybe"
        case .accepted:
            return "Accepted"
        }
    }
}

// MARK: - Errors

enum CalendarError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case networkError
    case rateLimitExceeded
    case insufficientPermissions
    case calendarNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated with Google Calendar"
        case .invalidResponse:
            return "Invalid response from Calendar API"
        case .networkError:
            return "Network error while accessing Calendar"
        case .rateLimitExceeded:
            return "Calendar API rate limit exceeded"
        case .insufficientPermissions:
            return "Insufficient permissions to access Calendar"
        case .calendarNotFound:
            return "Calendar not found"
        }
    }
}