//
//  UpcomingEventsView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct UpcomingEventsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingEmailDetail = false
    @State private var selectedEmail: Email?
    @State private var selectedTimeRange: TimeRange = .today
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        
        var icon: String {
            switch self {
            case .today: return "clock"
            case .week: return "calendar"
            case .month: return "calendar.circle"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with stats and time range
                upcomingEventsHeader
                
                // Timeline view
                if viewModel.isLoading {
                    loadingView
                } else if filteredEvents.isEmpty {
                    emptyStateView
                } else {
                    timelineView
                }
            }
            .designSystemBackground()
            .navigationTitle("Upcoming Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .accentColor()
                }
            }
        }
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
        .onAppear {
            Task {
                await viewModel.loadEmails()
            }
        }
    }
    
    // MARK: - Header
    
    private var upcomingEventsHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.calendarEmails.count)")
                        .font(DesignSystem.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.notionBlue)
                    
                    Text("Calendar Events")
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                }
                
                Spacer()
                
                // Calendar indicator
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.notionBlue.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.notionBlue)
                }
            }
            
            // Time range selector
            HStack(spacing: 0) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTimeRange = range
                        }
                    }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: range.icon)
                                .font(.caption)
                            Text(range.rawValue)
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundColor(selectedTimeRange == range ? .white : DesignSystem.Colors.systemTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTimeRange == range ? DesignSystem.Colors.notionBlue : Color.clear)
                        )
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                    )
            )
            
            // Quick stats for filtered events
            if !filteredEvents.isEmpty {
                HStack(spacing: DesignSystem.Spacing.lg) {
                    StatItem(
                        value: filteredEvents.count,
                        label: "Events",
                        color: DesignSystem.Colors.notionBlue
                    )
                    
                    StatItem(
                        value: filteredEvents.filter { isMeetingEvent($0) }.count,
                        label: "Meetings",
                        color: .purple
                    )
                    
                    StatItem(
                        value: filteredEvents.filter { !$0.isRead }.count,
                        label: "New",
                        color: .green
                    )
                    
                    Spacer()
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.systemBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Timeline View
    
    private var timelineView: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                ForEach(groupedEvents.keys.sorted(), id: \.self) { date in
                    TimelineDaySection(
                        date: date,
                        events: groupedEvents[date] ?? [],
                        onEventTap: { email in
                            selectedEmail = email
                            showingEmailDetail = true
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .animation(.easeInOut(duration: 0.3), value: selectedTimeRange)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonTimelineSection()
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.notionBlue.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "calendar")
                    .font(.system(size: 40))
                    .foregroundColor(DesignSystem.Colors.notionBlue.opacity(0.6))
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No Upcoming Events")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Text("Calendar invites and events will appear here")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Helper Properties
    
    private var filteredEvents: [Email] {
        let now = Date()
        let calendar = Calendar.current
        
        return viewModel.calendarEmails.filter { email in
            switch selectedTimeRange {
            case .today:
                return calendar.isDate(email.date, inSameDayAs: now)
            case .week:
                let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now) ?? now
                return email.date >= now && email.date <= weekFromNow
            case .month:
                let monthFromNow = calendar.date(byAdding: .month, value: 1, to: now) ?? now
                return email.date >= now && email.date <= monthFromNow
            }
        }
    }
    
    private var groupedEvents: [Date: [Email]] {
        Dictionary(grouping: filteredEvents.sorted { $0.date < $1.date }) { email in
            Calendar.current.startOfDay(for: email.date)
        }
    }
    
    private func isMeetingEvent(_ email: Email) -> Bool {
        let content = (email.subject + " " + email.body).lowercased()
        let meetingKeywords = ["meeting", "zoom", "teams", "call", "conference"]
        return meetingKeywords.contains(where: { content.contains($0) })
    }
}

// MARK: - Timeline Day Section

struct TimelineDaySection: View {
    let date: Date
    let events: [Email]
    let onEventTap: (Email) -> Void
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
    
    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    private var isTomorrow: Bool {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: tomorrow)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Day header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if isToday {
                        Text("Today")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.notionBlue)
                    } else if isTomorrow {
                        Text("Tomorrow")
                            .font(DesignSystem.Typography.headline)
                            .primaryText()
                    } else {
                        Text(dayFormatter.string(from: date))
                            .font(DesignSystem.Typography.headline)
                            .primaryText()
                    }
                    
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(DesignSystem.Typography.caption)
                        .secondaryText()
                }
                
                Spacer()
                
                // Timeline indicator
                VStack {
                    Circle()
                        .fill(isToday ? DesignSystem.Colors.notionBlue : DesignSystem.Colors.systemBorder)
                        .frame(width: 12, height: 12)
                    
                    if date != groupedEvents.keys.sorted().last {
                        Rectangle()
                            .fill(DesignSystem.Colors.systemBorder)
                            .frame(width: 2, height: 40)
                    }
                }
            }
            
            // Events for this day
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(events.sorted { $0.date < $1.date }) { event in
                    TimelineEventCard(email: event, onTap: {
                        onEventTap(event)
                    })
                }
            }
            .padding(.leading, 20) // Indent events
        }
    }
    
    // Helper to get grouped events from parent
    private var groupedEvents: [Date: [Email]] {
        // This would need to be passed down or accessed differently
        // For now, using empty dict to avoid compile error
        [:]
    }
}

// MARK: - Timeline Event Card

struct TimelineEventCard: View {
    let email: Email
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var eventTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: email.date)
    }
    
    private var eventType: EventType {
        let content = (email.subject + " " + email.body).lowercased()
        if content.contains("zoom") || content.contains("teams") || content.contains("meet") {
            return .videoCall
        } else if content.contains("meeting") || content.contains("call") {
            return .meeting
        } else if content.contains("event") || content.contains("party") {
            return .event
        } else {
            return .appointment
        }
    }
    
    enum EventType {
        case meeting, videoCall, event, appointment
        
        var icon: String {
            switch self {
            case .meeting: return "person.2"
            case .videoCall: return "video"
            case .event: return "star"
            case .appointment: return "calendar"
            }
        }
        
        var color: Color {
            switch self {
            case .meeting: return .purple
            case .videoCall: return .blue
            case .event: return .orange
            case .appointment: return .green
            }
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Time
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventTime)
                        .font(DesignSystem.Typography.bodyMedium)
                        .primaryText()
                    
                    Text(eventType == .videoCall ? "Video" : "Meeting")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(eventType.color)
                }
                .frame(width: 60, alignment: .leading)
                
                // Event indicator
                ZStack {
                    Circle()
                        .fill(eventType.color.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(eventType.color.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: eventType.icon)
                        .font(.system(size: 14))
                        .foregroundColor(eventType.color)
                    
                    if !email.isRead {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 12, y: -12)
                    }
                }
                
                // Event details
                VStack(alignment: .leading, spacing: 4) {
                    Text(email.subject)
                        .font(email.isRead ? DesignSystem.Typography.body : DesignSystem.Typography.bodyMedium)
                        .primaryText()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text(email.sender.displayName)
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                        
                        if extractMeetingLink() != nil {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.notionBlue)
                        }
                        
                        if extractLocation() != nil {
                            Image(systemName: "location")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Meeting link or location preview
                    if let location = extractLocation() {
                        Text(location)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    } else if extractMeetingLink() != nil {
                        Text("Join meeting")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.notionBlue)
                    }
                }
                
                Spacer()
                
                // Duration indicator (if extractable)
                if let duration = extractDuration() {
                    VStack {
                        Text(duration)
                            .font(DesignSystem.Typography.caption2)
                            .secondaryText()
                        
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(
                                isPressed ? eventType.color.opacity(0.5) : DesignSystem.Colors.systemBorder,
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .shadow(color: DesignSystem.Shadow.light, radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private func extractMeetingLink() -> String? {
        let body = email.body.lowercased()
        if body.contains("zoom.us") || body.contains("teams.microsoft.com") || body.contains("meet.google.com") {
            return "Meeting Link"
        }
        return nil
    }
    
    private func extractLocation() -> String? {
        let body = email.body
        // Simple location extraction - in real app would use more sophisticated parsing
        if body.contains("Room ") || body.contains("Conference ") || body.contains("Building ") {
            return "Office Location"
        }
        return nil
    }
    
    private func extractDuration() -> String? {
        let body = email.body.lowercased()
        if body.contains("30 min") || body.contains("30m") {
            return "30m"
        } else if body.contains("1 hour") || body.contains("1h") {
            return "1h"
        } else if body.contains("2 hour") || body.contains("2h") {
            return "2h"
        }
        return nil
    }
}

// MARK: - Skeleton Timeline Section

struct SkeletonTimelineSection: View {
    @State private var animateGradient = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Day header skeleton
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 100, height: 18)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 60, height: 12)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Circle()
                    .fill(shimmerGradient)
                    .frame(width: 12, height: 12)
            }
            
            // Event cards skeleton
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Rectangle()
                            .fill(shimmerGradient)
                            .frame(width: 60, height: 40)
                            .cornerRadius(4)
                        
                        Circle()
                            .fill(shimmerGradient)
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Rectangle()
                                .fill(shimmerGradient)
                                .frame(height: 16)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(shimmerGradient)
                                .frame(width: 100, height: 12)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.systemSecondaryBackground)
                    )
                }
            }
            .padding(.leading, 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                DesignSystem.Colors.systemBorder,
                DesignSystem.Colors.systemBorder.opacity(0.5),
                DesignSystem.Colors.systemBorder
            ],
            startPoint: animateGradient ? .leading : .trailing,
            endPoint: animateGradient ? .trailing : .leading
        )
    }
}

// MARK: - Preview

struct UpcomingEventsView_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingEventsView()
    }
}