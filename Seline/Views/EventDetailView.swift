//
//  EventDetailView.swift
//  Seline
//
//  Created by Assistant on 2025-08-29.
//

import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    @ObservedObject var viewModel: ContentViewModel
    @State private var showingDeleteAlert = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with event title
                    headerSection
                    
                    // Main content
                    VStack(spacing: 24) {
                        // Time & Date Card
                        dateTimeCard
                        
                        // Location Card (if available)
                        if let location = event.location, !location.isEmpty {
                            locationCard(location: location)
                        }
                        
                        // Description Card (if available)
                        if let description = event.description, !description.isEmpty {
                            descriptionCard(description: description)
                        }
                        
                        // Meeting Link Card (if available)
                        if let meetingLink = event.meetingLink, !meetingLink.isEmpty {
                            meetingLinkCard(link: meetingLink)
                        }
                        
                        // Attendees Card (if available)
                        if !event.attendees.isEmpty {
                            attendeesCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .background(DesignSystem.Colors.background)
            .overlay(
                // Custom navigation bar
                VStack {
                    customNavigationBar
                    Spacer()
                }
            )
        }

            }
            .navigationBarHidden(true)

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
                Task {
                    await AuthenticationService.shared.signOut()
                }
            }
        } message: {
            Text(permissionAlertMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category label
            Text("EVENT DETAILS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .tracking(1.2)
            
            // Event title
            Text(event.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 80)
        .padding(.bottom, 32)
    }
    
    // MARK: - Custom Navigation Bar
    
    private var customNavigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Close")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.danger)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(
            DesignSystem.Colors.background
                .opacity(0.95)
                .blur(radius: 10)
        )
    }
    
    // MARK: - Content Cards
    
    private var dateTimeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.primaryGradient)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(event.startDate))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    if event.isAllDay {
                        Text("All day")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    } else {
                        Text("\(formatTime(event.startDate)) - \(formatTime(event.endDate))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                
                Spacer()
            }
            
            // Duration (if not all day)
            if !event.isAllDay {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "clock")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duration")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text(formatDuration(event.duration))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private func locationCard(location: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.secondaryGradient)
                    .frame(width: 48, height: 48)
                
                Image(systemName: "location")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark ? 
                            UIColor.black : UIColor.white
                        })
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text(location)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private func descriptionCard(description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.tertiaryGradient)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("Event details and information")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Spacer()
            }
            
            Text(description)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(nil)
                .lineSpacing(4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private func meetingLinkCard(link: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.primaryGradient)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "video")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Meeting")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("Join the online meeting")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Spacer()
            }
            
            Button(action: {
                if let url = URL(string: link) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Join Meeting")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.accent)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.secondaryGradient)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "person.2")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attendees")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("\(event.attendees.count) \(event.attendees.count == 1 ? "person" : "people")")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Spacer()
            }
            
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(event.attendees) { attendee in
                    HStack(spacing: 12) {
                        // Avatar placeholder
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.surfaceSecondary)
                                .frame(width: 36, height: 36)
                            
                            Text(String(attendee.name?.first ?? attendee.email.first ?? "?").uppercased())
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attendee.name ?? attendee.email)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            if attendee.name != nil {
                                Text(attendee.email)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Response status indicator
                        statusIndicator(for: attendee.responseStatus)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private func statusIndicator(for status: EventAttendee.ResponseStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 8, height: 8)
            
            Text(statusText(for: status))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
    }
    
    private func statusColor(for status: EventAttendee.ResponseStatus) -> Color {
        switch status {
        case .accepted:
            return DesignSystem.Colors.success
        case .declined:
            return DesignSystem.Colors.danger
        case .tentative:
            return DesignSystem.Colors.warning
        case .needsAction:
            return DesignSystem.Colors.textTertiary
        }
    }
    
    private func statusText(for status: EventAttendee.ResponseStatus) -> String {
        switch status {
        case .accepted:
            return "Going"
        case .declined:
            return "Not going"
        case .tentative:
            return "Maybe"
        case .needsAction:
            return "Pending"
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }
    
    private func deleteEvent() {
        Task {
            do {
                try await CalendarService.shared.deleteEvent(eventId: event.id)
                await viewModel.loadCategoryEmails()
                await MainActor.run {
                    dismiss()
                }
            } catch CalendarError.insufficientPermissions {
                await MainActor.run {
                    permissionAlertMessage = "The app needs additional permissions to delete calendar events. Please re-authenticate to grant full calendar access."
                    showingPermissionAlert = true
                }
            } catch {
                await MainActor.run {
                    permissionAlertMessage = "Failed to delete event: \(error.localizedDescription)"
                    showingPermissionAlert = true
                }
            }
        }
    }
}

struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEvent = CalendarEvent(
            id: "sample-id",
            title: "Team Meeting",
            description: "Weekly team sync to discuss project progress and upcoming deadlines.",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            timeZone: "America/New_York",
            location: "Conference Room A",
            attendees: [
                EventAttendee(email: "john@example.com", name: "John Doe", responseStatus: .accepted),
                EventAttendee(email: "jane@example.com", name: "Jane Smith", responseStatus: .accepted)
            ],
            isAllDay: false,
            recurrence: nil,
            meetingLink: "https://meet.google.com/abc-defg-hij",
            calendarId: "primary"
        )
        
        EventDetailView(event: sampleEvent, viewModel: ContentViewModel())
    }
}