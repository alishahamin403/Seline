import SwiftUI

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
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : formattedDate)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    if isToday {
                        Text(formattedDate)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("\(eventsForDate.count) event\(eventsForDate.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                    
                    if let onAddEvent = onAddEvent {
                        Button(action: {
                            HapticManager.shared.selection()
                            onAddEvent(selectedDate)
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(cardBackgroundColor)
            
            // No divider line
            
            if eventsForDate.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(secondaryTextColor)
                    Text("No events")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(eventsForDate) { event in
                            eventRow(event: event)
                        }
                    }
                }
            }
        }
        .background(backgroundColor)
        .id("\(selectedDate.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when date or filter changes
        .onChange(of: selectedDate) { newDate in
            // Update cache when date changes
            let allTasks = taskManager.getAllTasks(for: newDate)
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
            cachedDate = newDate
            cachedTagId = selectedTagId
        }
        .onChange(of: selectedTagId) { newTagId in
            // Update cache when filter changes
            let allTasks = taskManager.getAllTasks(for: selectedDate)
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
            cachedTagId = newTagId
        }
        .onAppear {
            // Initialize cache
            let allTasks = taskManager.getAllTasks(for: selectedDate)
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
            cachedDate = selectedDate
            cachedTagId = selectedTagId
        }
        .onChange(of: taskManager.tasks) { _ in
            // Rebuild cache when tasks change
            let allTasks = taskManager.getAllTasks(for: selectedDate)
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
    
    private func eventRow(event: TaskItem) -> some View {
        // Get filter color using TimelineEventColorManager to match filter colors
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
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    if isAllDay {
                        Text("All day")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    } else if let time = event.scheduledTime {
                        Text(formatTime(time))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(primaryTextColor)
                        if let endTime = event.endTime {
                            Text(formatTime(endTime))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                .frame(width: 55, alignment: .trailing)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(tagColor)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .strikethrough(isCompleted)
                        .lineLimit(2)
                    
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if event.isRecurring {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 10, weight: .medium))
                                Text(event.recurrenceFrequency?.rawValue ?? "Recurring")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(secondaryTextColor)
                        }
                        
                        if let tagId = event.tagId, let tag = tagManager.getTag(by: tagId) {
                            Text(tag.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(tag.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: ShadcnRadius.sm).fill(tag.color.opacity(0.15)))
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { onToggleCompletion(event) }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(isCompleted ? tagColor : secondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Divider().background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
            alignment: .bottom
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
    
}

