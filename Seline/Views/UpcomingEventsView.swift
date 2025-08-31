//
//  UpcomingEventsView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct UpcomingEventsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContentViewModel
    @State private var isLoading = true
    @State private var showingCreateEvent = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean header with proper SafeArea handling
            headerSection
            
            // Content
            if isLoading {
                loadingView
            } else if viewModel.upcomingEvents.isEmpty {
                emptyStateView
            } else {
                upcomingEventsList
            }
        }
        .linearBackground()
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(viewModel: viewModel)
        }
        .onAppear {
            Task {
                isLoading = true
                await viewModel.loadCategoryEmails() // This loads upcoming events
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Top SafeArea + navigation
            HStack {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                Text("Upcoming Events")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                // Create Event button
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showingCreateEvent = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Events count
            HStack {
                Text("\(viewModel.upcomingEvents.count) upcoming events")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Events List
    
    private var upcomingEventsList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(groupedEvents.keys.sorted(), id: \.self) { date in
                    VStack(spacing: 0) {
                        // Date header
                        HStack {
                            Text(formatDateHeader(date))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Spacer()
                            
                            Text("\((groupedEvents[date] ?? []).count) events")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        
                        // Events for this date
                        VStack(spacing: 8) {
                            ForEach(groupedEvents[date] ?? []) { event in
                                CalendarEventCard(event: event, viewModel: viewModel)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            isLoading = true
            await viewModel.loadCategoryEmails()
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            VStack(spacing: 12) {
                Text("No Upcoming Events")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Your calendar events will appear here when you have upcoming appointments.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            Button(action: {
                Task {
                    isLoading = true
                    await viewModel.loadCategoryEmails()
                    await MainActor.run {
                        isLoading = false
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                    Text("Refresh")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.Colors.accent)
            
            Text("Loading upcoming events...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - Helper Properties
    
    private var groupedEvents: [Date: [CalendarEvent]] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.upcomingEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return grouped
    }
    
    // MARK: - Helper Methods
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Calendar Event Card

struct CalendarEventCard: View {
    let event: CalendarEvent
    @State private var isPressed = false
    @State private var showingEventDetails = false
    @State private var showingDeleteAlert = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @ObservedObject private var viewModel: ContentViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    init(event: CalendarEvent, viewModel: ContentViewModel) {
        self.event = event
        self.viewModel = viewModel
    }
    
    var body: some View {
        Button(action: {
            // Open event details in-app instead of external calendar
            showingEventDetails = true
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    // Time indicator
                    VStack(spacing: 4) {
                        if event.isAllDay {
                            Text("All Day")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.accent)
                        } else {
                            Text(formatTime(event.startDate))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            if !event.isAllDay && event.duration > 0 {
                                Text(formatDuration(event.duration))
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    .frame(width: 70, alignment: .center)
                    
                    // Event details
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if let location = event.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "location")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Text(location)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        if let description = event.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineLimit(2)
                        }
                        
                        // Meeting link indicator
                        if let meetingLink = event.meetingLink, !meetingLink.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "video.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.accent)

                                Text("Meeting Link")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }

                        
                        // Attendees count
                        if !event.attendees.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Text("\(event.attendees.count) attendees")
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .scaleEffect(isPressed ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isPressed)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 4,
                    x: 0,
                    y: 2
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .contextMenu {
            Button(action: {
                showingEventDetails = true
            }) {
                Label("View Details", systemImage: "info.circle")
            }
            
            Button(role: .destructive, action: {
                showingDeleteAlert = true
            }) {
                Label("Delete Event", systemImage: "trash")
            }
        }
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .sheet(isPresented: $showingEventDetails) {
            EventDetailView(event: event, viewModel: viewModel)
        }
        .alert("Delete Event", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
        } message: {
            Text("Are you sure you want to delete '\(event.title)'? This will also remove it from your Google Calendar.")
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Re-authenticate") {
                // Trigger re-authentication
                Task {
                    await AuthenticationService.shared.signOut()
                    // The app will automatically show the onboarding/sign-in flow
                }
            }
        } message: {
            Text(permissionAlertMessage)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: date)
        // Replace spaces with non-breaking spaces to prevent wrapping
        return timeString.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func deleteEvent() {
        Task {
            do {
                try await CalendarService.shared.deleteEvent(eventId: event.id)
                await viewModel.loadCategoryEmails() // Refresh events list
            } catch CalendarError.insufficientPermissions {
                await MainActor.run {
                    permissionAlertMessage = "The app needs additional permissions to delete calendar events. Please re-authenticate to grant full calendar access."
                    showingPermissionAlert = true
                }
            } catch {
                // Handle other errors
                print("Failed to delete event: \(error.localizedDescription)")
                await MainActor.run {
                    permissionAlertMessage = "Failed to delete event: \(error.localizedDescription)"
                    showingPermissionAlert = true
                }
            }
        }
    }
}

// MARK: - Create Event View

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContentViewModel
    @State private var eventTitle = ""
    @State private var eventDescription = ""
    @State private var eventLocation = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600) // 1 hour later
    @State private var isCreatingEvent = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let calendarService = CalendarService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text("New Event")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    Button("Create") {
                        createEvent()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(eventTitle.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)
                    .disabled(eventTitle.isEmpty || isCreatingEvent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                Divider()
                    .background(DesignSystem.Colors.border.opacity(0.3))
                
                // Form
                ScrollView {
                    VStack(spacing: 24) {
                        // Event Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            TextField("Event title", text: $eventTitle)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Event Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            TextField("Event description (optional)", text: $eventDescription, axis: .vertical)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3...6)
                        }
                        
                        // Event Location
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            TextField("Event location (optional)", text: $eventLocation)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Start Date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start Date & Time")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            DatePicker("Start Date", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .onChange(of: startDate) { newStart in
                                    // Auto-adjust end date if it's before start date
                                    if endDate <= newStart {
                                        endDate = newStart.addingTimeInterval(3600) // 1 hour later
                                    }
                                }
                        }
                        
                        // End Date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("End Date & Time")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            DatePicker("End Date", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                
                Spacer()
            }
            .linearBackground()
        }
        .alert("Event Creation", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func createEvent() {
        guard !eventTitle.isEmpty else { return }
        
        isCreatingEvent = true
        
        Task {
            do {
                let _ = try await calendarService.createEvent(
                    title: eventTitle,
                    description: eventDescription.isEmpty ? nil : eventDescription,
                    startDate: startDate,
                    endDate: endDate,
                    location: eventLocation.isEmpty ? nil : eventLocation
                )
                
                await MainActor.run {
                    isCreatingEvent = false
                    alertMessage = "Event created successfully in your calendar!"
                    showingAlert = true
                }
                
                // Refresh the events list
                await viewModel.loadCategoryEmails()

                // Dismiss after showing alert
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                }
                
            } catch {
                await MainActor.run {
                    isCreatingEvent = false
                    alertMessage = "Failed to create event: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - Preview

struct UpcomingEventsView_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingEventsView(viewModel: ContentViewModel())
    }
}