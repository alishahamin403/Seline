import SwiftUI

// MARK: - Time Period Enum
enum DayTimePeriod: String, CaseIterable {
    case allDay = "All Day"
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    
    var iconName: String {
        switch self {
        case .allDay: return "calendar"
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }
    
    var timeRange: String {
        switch self {
        case .allDay: return ""
        case .morning: return "Before 12 PM"
        case .afternoon: return "12 PM - 5 PM"
        case .evening: return "After 5 PM"
        }
    }
    
    static func period(for time: Date?) -> DayTimePeriod {
        guard let time = time else { return .allDay }
        let hour = Calendar.current.component(.hour, from: time)
        if hour < 12 {
            return .morning
        } else if hour < 17 {
            return .afternoon
        } else {
            return .evening
        }
    }
}

struct CalendarAgendaView: View {
    let selectedDate: Date
    let selectedTagId: String?
    let onTapEvent: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void
    let onAddEvent: ((Date) -> Void)?
    
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }
    
    private var sectionHeaderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    }
    
    // Cache for events to avoid recomputing on every render
    @State private var cachedEvents: [TaskItem] = []
    @State private var cachedDate: Date?
    @State private var cachedTagId: String?
    
    private var eventsForDate: [TaskItem] {
        let calendar = Calendar.current
        
        // CRITICAL: Always check if the filter has changed
        let filterChanged = cachedTagId != selectedTagId
        
        // Return cached if date matches AND filter hasn't changed
        if !filterChanged, let cached = cachedDate, calendar.isDate(cached, inSameDayAs: selectedDate) {
            return cachedEvents
        }
        
        // Compute fresh events when filter or date changes
        let allTasks = taskManager.getAllTasks(for: selectedDate)
        let filtered = applyFilter(to: allTasks)
        let sorted = filtered.sorted { task1, task2 in
            let hasTime1 = task1.scheduledTime != nil
            let hasTime2 = task2.scheduledTime != nil
            if hasTime1 != hasTime2 { return !hasTime1 }
            if hasTime1, let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                return time1 < time2
            }
            return false
        }
        return sorted
    }
    
    // Group events by time period
    private var groupedEvents: [(period: DayTimePeriod, events: [TaskItem])] {
        var groups: [DayTimePeriod: [TaskItem]] = [:]
        
        for event in eventsForDate {
            let period = DayTimePeriod.period(for: event.scheduledTime)
            if groups[period] == nil {
                groups[period] = []
            }
            groups[period]?.append(event)
        }
        
        // Return in order: All Day, Morning, Afternoon, Evening (only non-empty groups)
        return DayTimePeriod.allCases.compactMap { period in
            guard let events = groups[period], !events.isEmpty else { return nil }
            return (period: period, events: events)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: selectedDate)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
            
            if eventsForDate.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(groupedEvents, id: \.period) { group in
                            sectionView(period: group.period, events: group.events)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(backgroundColor)
        .id("\(selectedDate.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when date or filter changes
        .onChange(of: selectedDate) { newDate in
            updateCache(for: newDate)
        }
        .onChange(of: selectedTagId) { _ in
            updateCache(for: selectedDate)
        }
        .onAppear {
            updateCache(for: selectedDate)
        }
        .onChange(of: taskManager.tasks) { _ in
            updateCache(for: selectedDate)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : formattedDate)
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                if isToday {
                    Text(formattedDate)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text("\(eventsForDate.count) event\(eventsForDate.count == 1 ? "" : "s")")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(secondaryTextColor)
                
                if let onAddEvent = onAddEvent {
                    Button(action: {
                        HapticManager.shared.selection()
                        onAddEvent(selectedDate)
                    }) {
                        Image(systemName: "plus")
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(cardBackgroundColor)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(FontManager.geist(size: 32, weight: .light))
                .foregroundColor(secondaryTextColor)
            Text("No events")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Section View (Morning/Afternoon/Evening)
    
    private func sectionView(period: DayTimePeriod, events: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: period.iconName)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
                
                Text(period.rawValue)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                
                if !period.timeRange.isEmpty {
                    Text("·")
                        .foregroundColor(tertiaryTextColor)
                    Text(period.timeRange)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(tertiaryTextColor)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Event Cards
            VStack(spacing: 8) {
                ForEach(events) { event in
                    eventCard(event: event)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Event Card (Concept 2 Design)
    
    private func eventCard(event: TaskItem) -> some View {
        let filterType = TimelineEventColorManager.filterType(from: event)
        let colorIndex = event.tagId.flatMap { tagId in
            tagManager.getTag(by: tagId)?.colorIndex
        }
        let tagColor = TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: colorIndex
        )
        let isCompleted = event.isCompletedOn(date: selectedDate)
        let isAllDay = event.scheduledTime == nil
        
        return Button(action: { onTapEvent(event) }) {
            HStack(spacing: 0) {
                // Colored accent bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(tagColor)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Time row - horizontal format
                    HStack(spacing: 4) {
                        if isAllDay {
                            Text("All day")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                        } else if let time = event.scheduledTime {
                            Text(formatTimeRange(start: time, end: event.endTime))
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        // Category tag pill
                        if let tagId = event.tagId, let tag = tagManager.getTag(by: tagId) {
                            Text(tag.name)
                                .font(FontManager.geist(size: 10, weight: .semibold))
                                .foregroundColor(tag.color(for: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(tag.color(for: colorScheme).opacity(0.15))
                                )
                        } else if event.id.hasPrefix("cal_") {
                            // Synced calendar event
                            Text("Sync")
                                .font(FontManager.geist(size: 10, weight: .semibold))
                                .foregroundColor(TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme).opacity(0.15))
                                )
                        }
                    }
                    
                    // Event title with icon
                    HStack(spacing: 8) {
                        // Event type icon
                        if event.hasEmailAttachment {
                            Image(systemName: "envelope.fill")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(tagColor)
                        } else if event.isRecurring {
                            Image(systemName: "repeat")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(tagColor)
                        }
                        
                        Text(event.title)
                            .font(FontManager.geist(size: 15, weight: .medium))
                            .foregroundColor(primaryTextColor)
                            .strikethrough(isCompleted, color: primaryTextColor.opacity(0.5))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Description if present
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    
                    // Recurring indicator
                    if event.isRecurring, let frequency = event.recurrenceFrequency {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(FontManager.geist(size: 10, weight: .medium))
                            Text(frequency.rawValue)
                                .font(FontManager.geist(size: 10, weight: .medium))
                        }
                        .foregroundColor(tertiaryTextColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                Spacer(minLength: 0)
                
                // Completion checkbox
                Button(action: { onToggleCompletion(event) }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(FontManager.geist(size: 24, weight: .regular))
                        .foregroundColor(isCompleted ? tagColor : secondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func formatTimeRange(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        let startStr = formatter.string(from: start)
        
        if let end = end {
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr)"
        }
        
        return startStr
    }
    
    private func applyFilter(to tasks: [TaskItem]) -> [TaskItem] {
        if let tagId = selectedTagId {
            if tagId == "" {
                return tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
            } else if tagId == "cal_sync" {
                return tasks.filter { $0.id.hasPrefix("cal_") }
            } else {
                return tasks.filter { $0.tagId == tagId }
            }
        }
        return tasks
    }
    
    private func updateCache(for date: Date) {
        let allTasks = taskManager.getAllTasks(for: date)
        let filtered = applyFilter(to: allTasks)
        cachedEvents = filtered.sorted { task1, task2 in
            let hasTime1 = task1.scheduledTime != nil
            let hasTime2 = task2.scheduledTime != nil
            if hasTime1 != hasTime2 { return !hasTime1 }
            if hasTime1, let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                return time1 < time2
            }
            return false
        }
        cachedDate = date
        cachedTagId = selectedTagId
    }
}

#Preview {
    CalendarAgendaView(
        selectedDate: Date(),
        selectedTagId: nil,
        onTapEvent: { _ in },
        onToggleCompletion: { _ in },
        onAddEvent: { _ in }
    )
    .preferredColorScheme(.dark)
}
