//
//  CalendarService.swift
//  Seline
//
//  Created by Claude Code on 2025-09-04.
//

import Foundation

/// Service for managing calendar operations, including Google Calendar integration
@MainActor
class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isLoading: Bool = false
    
    private let authService = AuthenticationService.shared
    
    private init() {}
    
    /// Fetches upcoming events from Google Calendar
    func getUpcomingEvents(days: Int = 14) async throws -> [CalendarEvent] {
        return try await fetchUpcomingEvents(days: days)
    }
    
    /// Fetches upcoming events from Google Calendar API
    func fetchUpcomingEvents(days: Int = 14) async throws -> [CalendarEvent] {
        isLoading = true
        defer { isLoading = false }
        
        guard authService.isAuthenticated, let user = authService.user else {
            throw CalendarError.notAuthenticated
        }
        
        // Refresh token if needed
        if user.isTokenExpired {
            do {
                try await authService.refreshTokenIfNeeded()
            } catch {
                throw CalendarError.authenticationFailed
            }
        }
        
        guard let accessToken = authService.user?.accessToken else {
            throw CalendarError.noAccessToken
        }
        
        // Set up date range
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        
        let dateFormatter = ISO8601DateFormatter()
        let timeMin = dateFormatter.string(from: startDate)
        let timeMax = dateFormatter.string(from: endDate)
        
        // Build Google Calendar API URL
        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        
        guard let url = urlComponents.url else {
            throw CalendarError.invalidURL
        }
        
        // Make API request
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    throw CalendarError.apiError(httpResponse.statusCode)
                }
            }
            
            // Parse response
            let calendarResponse = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)
            
            // Convert to CalendarEvent objects
            let events = calendarResponse.items.compactMap { googleEvent in
                convertGoogleEventToCalendarEvent(googleEvent)
            }
            
            await MainActor.run {
                isConnected = true
            }
            
            return events
            
        } catch {
            if error is DecodingError {
                throw CalendarError.decodingError
            } else if error is URLError {
                throw CalendarError.networkError
            } else {
                throw error
            }
        }
    }
    
    /// Creates a new event in Google Calendar
    func createEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        guard authService.isAuthenticated, let accessToken = authService.user?.accessToken else {
            throw CalendarError.notAuthenticated
        }
        
        // For now, return the event as-is (placeholder)
        // In a full implementation, this would POST to Google Calendar API
        return event
    }
    
    /// Updates an existing event in Google Calendar
    func updateEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        guard authService.isAuthenticated, let accessToken = authService.user?.accessToken else {
            throw CalendarError.notAuthenticated
        }
        
        // For now, return the event as-is (placeholder)
        // In a full implementation, this would PUT to Google Calendar API
        return event
    }
    
    /// Deletes an event from Google Calendar
    func deleteEvent(id: String) async throws {
        guard authService.isAuthenticated, let accessToken = authService.user?.accessToken else {
            throw CalendarError.notAuthenticated
        }
        
        // For now, do nothing (placeholder)
        // In a full implementation, this would DELETE from Google Calendar API
    }
    
    /// Initializes the calendar service (sets up Google Calendar connection)
    func initialize() async throws {
        await MainActor.run {
            isConnected = authService.isAuthenticated
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func convertGoogleEventToCalendarEvent(_ googleEvent: GoogleCalendarEvent) -> CalendarEvent? {
        guard let title = googleEvent.summary else { return nil }
        
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        
        // Parse start and end dates
        if let startDateTime = googleEvent.start.dateTime {
            startDate = parseGoogleDateTime(startDateTime) ?? Date()
            endDate = parseGoogleDateTime(googleEvent.end.dateTime ?? startDateTime) ?? startDate
            isAllDay = false
        } else if let startDateOnly = googleEvent.start.date {
            startDate = parseGoogleDate(startDateOnly) ?? Date()
            endDate = parseGoogleDate(googleEvent.end.date ?? startDateOnly) ?? startDate
            isAllDay = true
        } else {
            return nil
        }
        
        return CalendarEvent(
            id: googleEvent.id,
            title: title,
            description: googleEvent.description,
            startDate: startDate,
            endDate: endDate,
            location: googleEvent.location,
            isAllDay: isAllDay,
            created: parseGoogleDateTime(googleEvent.created) ?? Date(),
            modified: parseGoogleDateTime(googleEvent.updated) ?? Date()
        )
    }
    
    private func parseGoogleDateTime(_ dateTimeString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateTimeString)
    }
    
    private func parseGoogleDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - Error Types

enum CalendarError: Error {
    case notAuthenticated
    case authenticationFailed
    case noAccessToken
    case invalidURL
    case networkError
    case apiError(Int)
    case decodingError
}

// MARK: - Google Calendar API Models

struct GoogleCalendarResponse: Codable {
    let items: [GoogleCalendarEvent]
}

struct GoogleCalendarEvent: Codable {
    let id: String
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleCalendarDateTime
    let end: GoogleCalendarDateTime
    let created: String
    let updated: String
}

struct GoogleCalendarDateTime: Codable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}