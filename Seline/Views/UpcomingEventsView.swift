//
//  UpcomingEventsView.swift
//  Seline
//
//  Created by Claude Code on 2025-09-05.
//

import SwiftUI

struct UpcomingEventsView: View {
    @StateObject private var calendarService = CalendarService.shared
    @ObservedObject var viewModel: ContentViewModel
    @State private var showingAddEvent = false
    @State private var selectedTab = "upcoming"
    
    // Use shared ViewModel data instead of separate state
    private var events: [CalendarEvent] {
        // Filter to next 7 days on rolling basis
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: daysToShow, to: startDate) ?? startDate
        
        return viewModel.upcomingEvents.filter { event in
            event.startDate >= startDate && event.startDate <= endDate
        }
    }
    
    private var isLoading: Bool {
        viewModel.isLoading
    }
    
    private var errorMessage: String? {
        viewModel.errorMessage
    }
    
    private let daysToShow = 7
    
    init(viewModel: ContentViewModel? = nil) {
        self.viewModel = viewModel ?? ContentViewModel()
    }
    
    var body: some View {
        ZStack {
            ShadcnTabs(tabs: [
                ShadcnTab(id: "upcoming", title: "Upcoming") {
                    VStack(spacing: 0) {
                        if isLoading {
                            loadingView
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if events.isEmpty {
                            emptyStateView
                        } else {
                            eventsListView
                        }
                    }
                },
                ShadcnTab(id: "completed", title: "Completed") {
                    CompletedEventsCalendarView()
                }
            ], selectedTabId: $selectedTab)
            
            // Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionButton(icon: "plus") {
                        showingAddEvent = true
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 20) // Position right above tab bar
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .task {
            // Data loading is now handled by shared ViewModel
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingAddEvent) {
            AddCalendarEventView {
                Task {
                    await viewModel.loadCategoryEmails()
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.accent))
            
            Text("Loading your calendar events...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Unable to Load Events")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(error)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: {
                Task { await viewModel.refresh() }
            }) {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.accent)
                    )
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Upcoming Events")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("You have no events scheduled for the next \(daysToShow) days")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Events List View
    
    private var eventsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedEvents.keys.sorted(), id: \.self) { date in
                    if let dayEvents = groupedEvents[date] {
                        daySection(date: date, events: dayEvents)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Day Section
    
    private func daySection(date: Date, events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(formatSectionDate(date))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                    )
            }
            .padding(.top, 20)
            
            // Events for this day
            VStack(spacing: 12) {
                ForEach(events.sorted(by: { $0.startDate < $1.startDate }), id: \.id) { event in
                    EventCard(event: event)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await deleteEvent(event)
                                }
                            } label: {
                                Label("Delete Event", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func deleteEvent(_ event: CalendarEvent) async {
        do {
            try await calendarService.deleteEvent(id: event.id)
            // Refresh the shared ViewModel data to reflect changes
            await viewModel.loadCategoryEmails()
        } catch {
            print("Error deleting event: \(error)")
            // Could show an alert here instead of setting errorMessage
        }
    }
    
    // MARK: - Helper Methods
    
    private var groupedEvents: [Date: [CalendarEvent]] {
        let calendar = Calendar.current
        var grouped: [Date: [CalendarEvent]] = [:]
        
        for event in events {
            let dayStart = calendar.startOfDay(for: event.startDate)
            if grouped[dayStart] == nil {
                grouped[dayStart] = []
            }
            grouped[dayStart]?.append(event)
        }
        
        return grouped
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    // Event loading is now handled by shared ContentViewModel
    
    private func getErrorMessage(for error: Error) -> String {
        if let calendarError = error as? CalendarError {
            switch calendarError {
            case .notAuthenticated:
                return "Please sign in to view your calendar events"
            case .authenticationFailed:
                return "Authentication failed. Please try signing in again"
            case .networkError:
                return "No internet connection. Please check your network and try again"
            case .apiError(let code):
                if code == 403 {
                    return "Calendar access denied. Please enable calendar permissions in Settings"
                } else {
                    return "Calendar service error (\(code))"
                }
            case .unknownError(let error):
                return "An unknown error occurred: \(error.localizedDescription)"
            default:
                return "Unable to load calendar events"
            }
        } else {
            return "An unexpected error occurred"
        }
    }
}

// MARK: - Event Card Component

struct EventCard: View {
    let event: CalendarEvent
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Time indicator
            VStack(alignment: .leading, spacing: 4) {
                if event.isAllDay {
                    Text("All Day")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                } else {
                    Text(formatTime(event.startDate))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    if !Calendar.current.isDate(event.startDate, equalTo: event.endDate, toGranularity: .minute) {
                        Text(formatTime(event.endDate))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .frame(width: 80, alignment: .leading)
            
            // Event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text(location)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Status indicator
            if event.isHappeningNow {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: colorScheme == .light ? Color.black.opacity(0.04) : Color.clear,
                    radius: 4,
                    x: 0,
                    y: 2
                )
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

struct UpcomingEventsView_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingEventsView(viewModel: ContentViewModel())
    }
}