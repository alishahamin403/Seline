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
    let onCameraAction: (() -> Void)?
    
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

    @State private var cachedEvents: [TaskItem] = []
    
    private var eventsForDate: [TaskItem] {
        cachedEvents
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
                LazyVStack(spacing: 16) {
                    ForEach(groupedEvents, id: \.period) { group in
                        sectionView(period: group.period, events: group.events)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(backgroundColor)
        .onAppear {
            updateCache(for: selectedDate)
        }
        .onChange(of: selectedDate) { newDate in
            updateCache(for: newDate)
        }
        .onChange(of: selectedTagId) { _ in
            updateCache(for: selectedDate)
        }
        .onChange(of: taskManager.tasks) { _ in
            updateCache(for: selectedDate)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            // Event count on the left
            Text("\(eventsForDate.count) event\(eventsForDate.count == 1 ? "" : "s")")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(primaryTextColor)
            
            Spacer()
            
            // Pill buttons on the right
            HStack(spacing: 8) {
                // Camera button
                if let onCameraAction = onCameraAction {
                    Button(action: {
                        HapticManager.shared.selection()
                        onCameraAction()
                    }) {
                        Image(systemName: "camera.fill")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Add event button
                if let onAddEvent = onAddEvent {
                    Button(action: {
                        HapticManager.shared.selection()
                        onAddEvent(selectedDate)
                    }) {
                        Text("Add")
                            .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
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
            .padding(.horizontal, 12)
            
            // Event Cards
            VStack(spacing: 8) {
                ForEach(events) { event in
                    eventCard(event: event)
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Event Card (Concept 2 Design)
    
    private func eventCard(event: TaskItem) -> some View {
        let isCompleted = event.isCompletedOn(date: selectedDate)
        let isAllDay = event.scheduledTime == nil
        let categoryLabel = labelForEventCategory(event)
        
        return Button(action: { onTapEvent(event) }) {
            HStack(spacing: 0) {
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

                        if event.hasEmailAttachment {
                            Image(systemName: "envelope.fill")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                    
                    Text(event.title)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .strikethrough(isCompleted, color: primaryTextColor.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if let categoryLabel {
                            Text(categoryLabel)
                                .font(FontManager.geist(size: 10, weight: .semibold))
                                .foregroundColor(primaryTextColor.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08))
                                )
                        }

                        if event.isRecurring, let frequency = event.recurrenceFrequency {
                            Text(frequency.rawValue.lowercased())
                                .font(FontManager.geist(size: 10, weight: .medium))
                                .foregroundColor(tertiaryTextColor)
                        }
                    }
                    
                    // Description if present
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                Spacer(minLength: 0)
                
                // Completion checkbox
                Button(action: { 
                    onToggleCompletion(event)
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(FontManager.geist(size: 24, weight: .regular))
                        .foregroundColor(isCompleted ? primaryTextColor : secondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
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

    private func labelForEventCategory(_ event: TaskItem) -> String? {
        if let tagId = event.tagId, let tag = tagManager.getTag(by: tagId) {
            return tag.name
        }
        if event.id.hasPrefix("cal_") || event.isFromCalendar || event.calendarEventId != nil || event.tagId == "cal_sync" {
            return "Sync"
        }
        return nil
    }
    
    private func applyFilter(to tasks: [TaskItem]) -> [TaskItem] {
        if let tagId = selectedTagId {
            if tagId == "" {
                return tasks.filter { task in
                    task.tagId == nil && !isSyncedCalendarTask(task)
                }
            } else if tagId == "cal_sync" {
                return tasks.filter { task in
                    isSyncedCalendarTask(task)
                }
            } else {
                return tasks.filter { $0.tagId == tagId }
            }
        }
        return tasks
    }

    private func isSyncedCalendarTask(_ task: TaskItem) -> Bool {
        task.id.hasPrefix("cal_")
            || task.isFromCalendar
            || task.calendarEventId != nil
            || task.tagId == "cal_sync"
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
    }
    
}

#Preview {
    CalendarAgendaView(
        selectedDate: Date(),
        selectedTagId: nil,
        onTapEvent: { _ in },
        onToggleCompletion: { _ in },
        onAddEvent: { _ in },
        onCameraAction: { }
    )
    .preferredColorScheme(.dark)
}
