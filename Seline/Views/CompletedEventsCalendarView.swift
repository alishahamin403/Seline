
//
//  CompletedEventsCalendarView.swift
//  Seline
//
//  Created by Gemini on 2025-09-05.
//

import SwiftUI

struct CompletedEventsCalendarView: View {
    @StateObject private var calendarService = CalendarService.shared
    @State private var pastEvents: [CalendarEvent] = []
    @State private var selectedDate: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.accent))
                    
                    Text("Loading calendar events...")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text("Error Loading Events")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        fetchPastEvents()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background)
                .padding()
            } else {
                VStack(spacing: 0) {
                    ShadcnCalendar(
                        items: pastEvents,
                        itemDateKeyPath: \.startDate,
                        selectedDate: selectedDate,
                        onDateSelected: { date in
                            selectedDate = date
                        },
                        onMonthChanged: { date in
                            fetchPastEvents(for: date)
                        }
                    )
                    
                    eventsForSelectedDateView
                }
                .background(DesignSystem.Colors.background)
            }
        }
        .onAppear {
            fetchPastEvents()
        }
    }


    
    

    @ViewBuilder
    private var eventsForSelectedDateView: some View {
        if let selectedDate = selectedDate {
            let events = pastEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
            
            VStack(alignment: .leading, spacing: 0) {
                if events.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text("No events for this day")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DesignSystem.Spacing.lg)
                } else {
                    List(events) { event in
                        EventCard(event: event)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            // Placeholder to maintain consistent layout during initialization
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                
                Text("Select a date to view events")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(maxHeight: .infinity)
        }
    }

    private func fetchPastEvents(for date: Date = Date()) {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                let events = try await calendarService.fetchPastEvents(for: date)
                await MainActor.run {
                    self.pastEvents = events
                    isLoading = false
                    
                    #if DEBUG
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM"
                    print("📅 CompletedEvents: Loaded \(events.count) past events for \(formatter.string(from: date))")
                    #endif
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = getErrorMessage(for: error)
                    print("❌ CompletedEvents: Error fetching past events: \(error)")
                }
            }
        }
    }
    
    private func getErrorMessage(for error: Error) -> String {
        if let calendarError = error as? CalendarError {
            switch calendarError {
            case .notAuthenticated:
                return "Please sign in to view past events"
            case .authenticationFailed:
                return "Authentication failed. Please try signing in again"
            case .networkError:
                return "No internet connection"
            case .calendarScopeNotGranted:
                return "Calendar access not granted. Enable calendar permissions in Settings"
            default:
                return "Unable to load past events"
            }
        }
        return "An error occurred while loading events"
    }



}


struct CompletedEventsCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CompletedEventsCalendarView()
    }
}
