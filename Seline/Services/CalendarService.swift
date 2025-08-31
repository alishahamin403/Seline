//
//  CalendarService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import UIKit
// import GoogleAPIClientForREST

protocol CalendarServiceProtocol {
    func fetchUpcomingEvents(days: Int) async throws -> [CalendarEvent]
    func fetchTodaysEvents() async throws -> [CalendarEvent]
    func fetchEventsForDate(_ date: Date) async throws -> [CalendarEvent]
    func createEvent(title: String, description: String?, startDate: Date, endDate: Date, location: String?) async throws -> CalendarEvent
    func updateEvent(eventId: String, title: String, description: String?, startDate: Date, endDate: Date, location: String?) async throws -> CalendarEvent
    func deleteEvent(eventId: String) async throws
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
        print("📅 Fetching real calendar events for next \(days) days (no mock fallback)")
        return try await fetchRealCalendarEvents(days: days)
    }
    
    func fetchTodaysEvents() async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded()
        print("📅 Fetching today's real calendar events (no mock fallback)")
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        
        return try await fetchRealCalendarEventsForDateRange(from: today, to: tomorrow)
    }
    
    func fetchEventsForDate(_ date: Date) async throws -> [CalendarEvent] {
        try await refreshTokenIfNeeded()
        print("📅 Fetching real calendar events for \(date) (no mock fallback)")
        
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return try await fetchRealCalendarEventsForDateRange(from: startOfDay, to: endOfDay)
    }
    
    func createEvent(title: String, description: String? = nil, startDate: Date, endDate: Date, location: String? = nil) async throws -> CalendarEvent {
        print("📅 Creating new calendar event: \(title)")

        // Create event locally first
        let localEvent = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            description: description,
            startDate: startDate,
            endDate: endDate,
            timeZone: TimeZone.current.identifier,
            location: location,
            attendees: [],
            isAllDay: false,
            recurrence: nil,
            meetingLink: nil,
            calendarId: "primary"
        )

        // Store locally
        await LocalEventService.shared.saveEvent(localEvent)

        // Try to sync to Google Calendar if authenticated
        if authService.isAuthenticated {
            Task { @MainActor in
                do {
                    try await syncEventToGoogleCalendar(localEvent)
                    print("📅 Event synced to Google Calendar successfully")
                } catch {
                    print("📅 Failed to sync event to Google Calendar: \(error.localizedDescription)")
                    // Event remains local-only, which is fine
                }
            }
        }

        return localEvent
    }
    
    func updateEvent(eventId: String, title: String, description: String? = nil, startDate: Date, endDate: Date, location: String? = nil) async throws -> CalendarEvent {
        print("📅 Updating calendar event: \(eventId)")
        
        try await refreshTokenIfNeeded()
        
        // Try to update in Google Calendar first if authenticated
        if authService.isAuthenticated {
            try await updateEventInGoogleCalendar(eventId: eventId, title: title, description: description, startDate: startDate, endDate: endDate, location: location)
        }
        
        // Update locally as well
        let updatedEvent = CalendarEvent(
            id: eventId,
            title: title,
            description: description,
            startDate: startDate,
            endDate: endDate,
            timeZone: TimeZone.current.identifier,
            location: location,
            attendees: [],
            isAllDay: false,
            recurrence: nil,
            meetingLink: nil,
            calendarId: "primary"
        )
        
        await LocalEventService.shared.updateEvent(updatedEvent)
        
        return updatedEvent
    }
    
    func deleteEvent(eventId: String) async throws {
        print("📅 Deleting calendar event: \(eventId)")
        
        try await refreshTokenIfNeeded()
        
        // Check if this is a locally created event
        let isLocalEvent = LocalEventService.shared.localEvents.contains { $0.id == eventId }
        print("📅 Event type check - isLocalEvent: \(isLocalEvent)")
        
        // Try to delete from Google Calendar first if authenticated
        if authService.isAuthenticated {
            do {
                try await deleteEventFromGoogleCalendar(eventId: eventId)
                print("📅 Successfully deleted event from Google Calendar")
            } catch {
                // Check if this is a scope/permission error
                if let calendarError = error as? CalendarServiceError,
                   case .apiError(let message) = calendarError,
                   message.contains("403") || message.contains("insufficientPermissions") {
                    throw CalendarError.insufficientPermissions
                }
                
                // If deletion fails and this is a local event, it might not exist in Google Calendar
                if isLocalEvent {
                    print("📅 Local event deletion from Google Calendar failed (expected): \(error.localizedDescription)")
                } else {
                    // Re-throw the error for Google Calendar events
                    print("📅 Google Calendar event deletion failed: \(error.localizedDescription)")
                    throw error
                }
            }
        } else {
            print("📅 Not authenticated, skipping Google Calendar deletion")
        }
        
        // Delete locally as well
        await LocalEventService.shared.deleteEvent(eventId)
    }
    
    private func updateEventInGoogleCalendar(eventId: String, title: String, description: String?, startDate: Date, endDate: Date, location: String?) async throws {
        guard let accessToken = await getGoogleAccessToken() else {
            throw CalendarServiceError.noAccessToken
        }
        
        // URL encode the event ID to handle special characters
        guard let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw CalendarServiceError.invalidURL
        }
        
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedEventId)"
        
        guard let url = URL(string: urlString) else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        let eventData: [String: Any] = [
            "summary": title,
            "description": description ?? "",
            "location": location ?? "",
            "start": [
                "dateTime": formatter.string(from: startDate),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: endDate),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.apiError("Invalid response from Calendar API")
        }
        
        print("📅 UPDATE API Response - Status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw CalendarServiceError.apiError("Failed to update calendar event. Status: \(httpResponse.statusCode), Response: \(responseBody)")
        }
        
        print("📅 Event updated in Google Calendar successfully")
    }
    
    private func deleteEventFromGoogleCalendar(eventId: String) async throws {
        guard let accessToken = await getGoogleAccessToken() else {
            throw CalendarServiceError.noAccessToken
        }
        
        // URL encode the event ID to handle special characters
        guard let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw CalendarServiceError.invalidURL
        }
        
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedEventId)"
        
        guard let url = URL(string: urlString) else {
            throw CalendarServiceError.invalidURL
        }
        
        print("📅 DELETE URL: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.apiError("Invalid response from Calendar API")
        }
        
        print("📅 DELETE API Response - Status: \(httpResponse.statusCode)")
        
        // Log response data for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📅 DELETE API Response Body: \(responseString)")
        }
        
        // Google Calendar API returns 204 for successful deletion, but some events might return 200
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw CalendarServiceError.apiError("Failed to delete calendar event. Status: \(httpResponse.statusCode), Response: \(responseBody)")
        }
        
        print("📅 Event deleted from Google Calendar successfully")
    }

    private func syncEventToGoogleCalendar(_ event: CalendarEvent) async throws {
        guard let accessToken = await getGoogleAccessToken() else {
            throw CalendarServiceError.noAccessToken
        }
        
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        
        guard let url = URL(string: urlString) else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        var eventData: [String: Any] = [
            "summary": event.title,
            "start": [
                "dateTime": formatter.string(from: event.startDate),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: event.endDate),
                "timeZone": TimeZone.current.identifier
            ]
        ]
        
        if let description = event.description, !description.isEmpty {
            eventData["description"] = description
        }
        
        if let location = event.location, !location.isEmpty {
            eventData["location"] = location
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.apiError("Invalid response from Calendar API")
        }
        
        print("📅 CREATE API Response - Status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw CalendarServiceError.apiError("Failed to create calendar event. Status: \(httpResponse.statusCode), Response: \(responseBody)")
        }
        
        print("📅 Event created in Google Calendar successfully")
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
               let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)),
               let range = Range(match.range, in: description) {
                return String(description[range])
            }
        }
        
        return nil
    }
    
    // MARK: - Real Calendar API Integration
    
    private func fetchRealCalendarEvents(days: Int) async throws -> [CalendarEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return try await fetchRealCalendarEventsForDateRange(from: now, to: endDate)
    }
    
    private func fetchRealCalendarEventsForDateRange(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        guard let accessToken = await getGoogleAccessToken() else {
            throw CalendarServiceError.noAccessToken
        }
        
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: startDate)
        let timeMax = formatter.string(from: endDate)
        
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=50"
        
        guard let url = URL(string: urlString) else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CalendarServiceError.apiError("Failed to fetch calendar events")
        }
        
        let calendarEventsList = try JSONDecoder().decode(GoogleCalendarEventsList.self, from: data)
        
        guard let events = calendarEventsList.items, !events.isEmpty else {
            print("📅 No calendar events found")
            return []
        }
        
        print("📅 Found \(events.count) calendar events")
        return events.compactMap { convertGoogleEventToCalendarEvent($0) }
    }
    
    private func getGoogleAccessToken() async -> String? {
        return await GoogleOAuthService.shared.getValidAccessToken()
    }
    
    private func convertGoogleEventToCalendarEvent(_ googleEvent: GoogleCalendarEvent) -> CalendarEvent? {
        guard let title = googleEvent.summary else { return nil }
        
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        
        if let startDateTime = googleEvent.start.dateTime {
            startDate = parseDateTime(startDateTime) ?? Date()
            endDate = parseDateTime(googleEvent.end.dateTime ?? "") ?? startDate.addingTimeInterval(3600)
            isAllDay = false
        } else if let startDateStr = googleEvent.start.date {
            startDate = parseDate(startDateStr) ?? Date()
            endDate = parseDate(googleEvent.end.date ?? "") ?? startDate.addingTimeInterval(86400)
            isAllDay = true
        } else {
            return nil
        }
        
        let attendees = googleEvent.attendees?.compactMap { attendee in
            EventAttendee(
                email: attendee.email,
                name: attendee.displayName,
                responseStatus: parseResponseStatus(attendee.responseStatus)
            )
        } ?? []
        
        let meetingLink = extractMeetingLink(from: googleEvent.description ?? "")
        
        return CalendarEvent(
            id: googleEvent.id,
            title: title,
            description: googleEvent.description,
            startDate: startDate,
            endDate: endDate,
            timeZone: googleEvent.start.timeZone ?? TimeZone.current.identifier,
            location: googleEvent.location,
            attendees: attendees,
            isAllDay: isAllDay,
            recurrence: googleEvent.recurrence,
            meetingLink: meetingLink,
            calendarId: "primary"
        )
    }
    
    private func parseDateTime(_ dateTimeString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateTimeString)
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func parseResponseStatus(_ status: String?) -> EventAttendeeStatus {
        switch status?.lowercased() {
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
    
    // MARK: - Create Event Helper
    
    private func createGoogleCalendarURL(title: String, description: String?, startDate: Date, endDate: Date, location: String?) -> URL? {
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "calendar.google.com"
        urlComponents.path = "/calendar/render"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "action", value: "TEMPLATE"))
        queryItems.append(URLQueryItem(name: "text", value: title))
        queryItems.append(URLQueryItem(name: "dates", value: "\(startDateString)/\(endDateString)"))
        
        if let description = description, !description.isEmpty {
            queryItems.append(URLQueryItem(name: "details", value: description))
        }
        
        if let location = location, !location.isEmpty {
            queryItems.append(URLQueryItem(name: "location", value: location))
        }
        
        urlComponents.queryItems = queryItems
        
        return urlComponents.url
    }
    
    // MARK: - Google Calendar API Data Models
    
    struct GoogleCalendarEventsList: Codable {
        let items: [GoogleCalendarEvent]?
        let nextPageToken: String?
    }
    
    struct GoogleCalendarEvent: Codable {
        let id: String
        let summary: String?
        let description: String?
        let location: String?
        let start: GoogleCalendarDateTime
        let end: GoogleCalendarDateTime
        let attendees: [GoogleCalendarAttendee]?
        let recurrence: [String]?
    }
    
    struct GoogleCalendarDateTime: Codable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
    }
    
    struct GoogleCalendarAttendee: Codable {
        let email: String
        let displayName: String?
        let responseStatus: String?
    }
    
    // MARK: - Error Types
    
    enum CalendarServiceError: LocalizedError {
        case noAccessToken
        case invalidURL
        case apiError(String)
        case decodingError
        
        var errorDescription: String? {
            switch self {
            case .noAccessToken:
                return "No valid access token available"
            case .invalidURL:
                return "Invalid Calendar API URL"
            case .apiError(let message):
                return "Calendar API error: \(message)"
            case .decodingError:
                return "Failed to decode Calendar API response"
            }
        }
    }
    
    // MARK: - Mock Data Removed
    // All mock data fallbacks have been removed to use only real Calendar API data
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

    // Computed properties (not stored, so they don't affect Codable)
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