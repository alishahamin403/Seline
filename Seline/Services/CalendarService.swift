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
        return try await self.fetchUpcomingEvents(days: days)
    }
    
    /// Fetches upcoming events from Google Calendar API only
    private func fetchGoogleCalendarEvents(days: Int = 14) async throws -> [CalendarEvent] {
        isLoading = true
        defer { isLoading = false }
        
        guard authService.isAuthenticated, let user = authService.user else {
            throw CalendarError.notAuthenticated
        }
        
        // Validate calendar scope before making API calls
        guard hasCalendarScope() else {
            print("⚠️ Calendar scope not available, requesting scope upgrade")
            throw CalendarError.calendarScopeNotGranted
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
                    // Special handling for 401/403 errors (authentication/authorization issues)
                    if httpResponse.statusCode == 401 {
                        print("🔒 Calendar API returned 401 - possible scope or token issue")
                        print("   Requesting token refresh and scope validation")
                        throw CalendarError.calendarScopeNotGranted
                    } else if httpResponse.statusCode == 403 {
                        print("🔒 Calendar API returned 403 - insufficient permissions")
                        print("   User needs to re-authenticate with calendar scope")
                        throw CalendarError.calendarScopeNotGranted
                    }
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
            print("Error during calendar fetch: \(error)")
            
            // Handle specific calendar errors
            if let calendarError = error as? CalendarError {
                if case .calendarScopeNotGranted = calendarError {
                    print("🗓️ Calendar scope not granted - skipping Google Calendar integration")
                    print("   Continuing without Google Calendar access to avoid forced logout")
                    // Don't call requestCalendarScopeUpgrade() to avoid forced logout
                }
                throw calendarError
            }
            
            if error is DecodingError {
                throw CalendarError.decodingError
            } else if error is URLError {
                throw CalendarError.networkError
            } else {
                throw CalendarError.unknownError(error)
            }
        }
    }
    
    /// Fetches upcoming events from both local storage and Google Calendar API
    func fetchUpcomingEvents(days: Int = 14) async throws -> [CalendarEvent] {
        isLoading = true
        defer { isLoading = false }
        
        // Always get local events first
        var allEvents = LocalEventService.shared.getUpcomingEvents(days: days)
        
        // Try to get Google Calendar events if authenticated
        if authService.isAuthenticated, let user = authService.user, !user.isTokenExpired {
            do {
                let googleEvents = try await fetchGoogleCalendarEvents(days: days)
                allEvents.append(contentsOf: googleEvents)
            } catch {
                // Handle specific calendar errors
                if let calendarError = error as? CalendarError {
                    if case .calendarScopeNotGranted = calendarError {
                        print("🗓️ Calendar scope not granted during fetch - using local events only")
                        print("   Avoiding forced logout to maintain user session")
                        // Don't call requestCalendarScopeUpgrade() to avoid forced logout
                    }
                }
                
                // Log error but don't fail - we have local events
                print("⚠️ Google Calendar fetch failed: \(error)")
                // Still mark as connected if we got local events
                await MainActor.run {
                    isConnected = !allEvents.isEmpty
                }
            }
        } else {
            // Not authenticated, just use local events
            print("📅 Using local events only (not authenticated)")
            await MainActor.run {
                isConnected = !allEvents.isEmpty
            }
        }
        
        // Sort by date and remove duplicates based on title and start time
        let uniqueEvents = Dictionary(grouping: allEvents) { event in
            "\(event.title)_\(event.startDate.timeIntervalSince1970)"
        }.values.compactMap { $0.first }
        
        return uniqueEvents.sorted(by: { $0.startDate < $1.startDate })
    }

    /// Fetches past events from both local storage and Google Calendar for a specific month
    func fetchPastEvents(for date: Date) async throws -> [CalendarEvent] {
        isLoading = true
        defer { isLoading = false }
        
        // Always get local events first
        var allEvents = LocalEventService.shared.getPastEvents(for: date)
        
        // Try to get Google Calendar events if authenticated
        if authService.isAuthenticated, let user = authService.user, !user.isTokenExpired {
            do {
                let googleEvents = try await fetchGooglePastEvents(for: date)
                allEvents.append(contentsOf: googleEvents)
            } catch {
                // Handle specific calendar errors
                if let calendarError = error as? CalendarError {
                    if case .calendarScopeNotGranted = calendarError {
                        print("🗓️ Calendar scope not granted during past events fetch - using local events only")
                    }
                }
                
                // Log error but don't fail - we have local events
                print("⚠️ Google Calendar past events fetch failed: \(error)")
            }
        } else {
            // Not authenticated, just use local events
            print("📅 Using local past events only (not authenticated)")
        }
        
        // Sort by date and remove duplicates
        let uniqueEvents = Dictionary(grouping: allEvents) { event in
            "\(event.title)_\(event.startDate.timeIntervalSince1970)"
        }.values.compactMap { $0.first }
        
        await MainActor.run {
            isConnected = !allEvents.isEmpty
        }
        
        return uniqueEvents.sorted(by: { $0.startDate < $1.startDate })
    }
    
    /// Fetches past events from Google Calendar API only for a specific month
    private func fetchGooglePastEvents(for date: Date) async throws -> [CalendarEvent] {
        guard authService.isAuthenticated, let user = authService.user else {
            throw CalendarError.notAuthenticated
        }

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

        let calendar = Calendar.current
        guard let monthStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEndDate = calendar.date(byAdding: .month, value: 1, to: monthStartDate) else {
            return []
        }

        let dateFormatter = ISO8601DateFormatter()
        let timeMin = dateFormatter.string(from: monthStartDate)
        let timeMax = dateFormatter.string(from: monthEndDate)

        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250")
        ]

        guard let url = urlComponents.url else {
            throw CalendarError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // Handle 403 errors specifically for past events
                if httpResponse.statusCode == 403 {
                    print("🔒 Calendar API returned 403 for past events - insufficient permissions")
                    throw CalendarError.calendarScopeNotGranted
                } else if httpResponse.statusCode == 401 {
                    print("🔒 Calendar API returned 401 for past events - authentication issue")
                    throw CalendarError.calendarScopeNotGranted
                }
                throw CalendarError.apiError(httpResponse.statusCode)
            }

            let calendarResponse = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)
            let events = calendarResponse.items.compactMap { convertGoogleEventToCalendarEvent($0) }

            await MainActor.run {
                isConnected = true
            }

            return events
        } catch {
            print("Error fetching past events: \(error)")
            
            // Handle specific calendar errors
            if let calendarError = error as? CalendarError {
                if case .calendarScopeNotGranted = calendarError {
                    print("🗓️ Calendar scope not granted for past events - skipping Google Calendar access")
                    print("   Using local calendar data only to avoid session disruption")
                    // Don't call requestCalendarScopeUpgrade() to avoid forced logout
                }
                throw calendarError
            }
            
            if error is DecodingError {
                throw CalendarError.decodingError
            } else if error is URLError {
                throw CalendarError.networkError
            } else {
                throw CalendarError.unknownError(error)
            }
        }
    }
    
    /// Creates a new event in Google Calendar
    func createEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        guard authService.isAuthenticated, let accessToken = authService.user?.accessToken else {
            throw CalendarError.notAuthenticated
        }
        
        // Save to local service
        try await LocalEventService.shared.addEvent(event)
        
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

        let urlString = "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)"
        guard let url = URL(string: urlString) else {
            throw CalendarError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 204 {
            throw CalendarError.apiError(httpResponse.statusCode)
        }
    }
    
    /// Initializes the calendar service (sets up Google Calendar connection)
    func initialize() async throws {
        await MainActor.run {
            isConnected = authService.isAuthenticated
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Checks if the current user has calendar scope permissions
    private func hasCalendarScope() -> Bool {
        guard let user = authService.user, !user.accessToken.isEmpty else {
            print("❌ No user or access token available")
            return false
        }
        
        // Check if token is expired
        if user.isTokenExpired {
            print("❌ Access token is expired")
            return false
        }
        
        // For now, we'll check if the user was authenticated through GoogleOAuthService
        // which includes calendar scope, or if they need to upgrade their permissions
        let googleOAuthService = GoogleOAuthService.shared
        let configuredScopes = googleOAuthService.getConfiguredScopes()
        let hasCalendarInConfig = configuredScopes.contains("https://www.googleapis.com/auth/calendar")
        
        if !hasCalendarInConfig {
            print("❌ Calendar scope not configured in GoogleOAuthService")
            return false
        }
        
        // If we have a recent authentication through GoogleOAuthService, assume scopes are valid
        if googleOAuthService.isAuthenticated {
            print("✅ User authenticated through GoogleOAuthService with calendar scope")
            return true
        }
        
        print("⚠️ User may need to re-authenticate to get calendar scope")
        return false
    }
    
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
    case calendarScopeNotGranted
    case invalidURL
    case networkError
    case apiError(Int)
    case decodingError
    case unknownError(Error)
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