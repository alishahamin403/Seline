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
                VStack(alignment: .leading, spacing: 24) {
                    // Event Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Event Details")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(event.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(nil)
                    }
                    
                    // Time & Date
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDate(event.startDate))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                        }
                        
                        // Duration
                        if !event.isAllDay {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 16))
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .frame(width: 24)
                                
                                Text(formatDuration(event.duration))
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                            }
                        }
                    }
                    
                    // Location
                    if let location = event.location, !location.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "location")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Location")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Text(location)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .lineLimit(nil)
                            }
                        }
                    }
                    
                    // Description
                    if let description = event.description, !description.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Text(description)
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .lineLimit(nil)
                            }
                        }
                    }
                    
                    // Attendees
                    if !event.attendees.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.2")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Attendees (\(event.attendees.count))")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(event.attendees) { attendee in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(DesignSystem.Colors.accent.opacity(0.2))
                                                .frame(width: 6, height: 6)
                                            
                                            Text(attendee.name ?? attendee.email)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                            
                                            if attendee.name != nil {
                                                Text("(\(attendee.email))")
                                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Meeting Link
                    if let meetingLink = event.meetingLink, !meetingLink.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "video")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Meeting Link")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Button(action: {
                                    if let url = URL(string: meetingLink) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text("Join Meeting")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(DesignSystem.Colors.accent)
                                        )
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding(24)
            }
            .navigationBarHidden(true)
            .overlay(
                // Custom header
                VStack {
                    HStack {
                        Button("Close") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Spacer()
                        
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            )
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
        .linearBackground()
    }
    
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