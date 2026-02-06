import SwiftUI

struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    let selectedTagId: String?
    let onTapEvent: (TaskItem) -> Void
    let onAddEvent: ((Date) -> Void)?
    
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentMonth: Date
    @State private var dragOffset: CGFloat = 0
    @State private var cachedEventsForMonth: [String: [TaskItem]] = [:] // Cache: dateKey -> filtered events
    @State private var cachedMonthKey: String = "" // Track which month is cached
    @State private var cachedTagId: String? = nil // Track which tag filter is cached
    
    private let calendar = Calendar.current
    private let maxEventsPerCell = 2
    
    init(
        selectedDate: Binding<Date>,
        selectedTagId: String?,
        onTapEvent: @escaping (TaskItem) -> Void,
        onAddEvent: ((Date) -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.selectedTagId = selectedTagId
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self._currentMonth = State(initialValue: selectedDate.wrappedValue)
    }
    
    // MARK: - Colors
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var todayHighlightColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    // MARK: - Date Calculations
    
    // Only show days from 1st to end of month, no extra days
    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        var dates: [Date] = []
        var date = monthInterval.start
        
        // Add all days from the first day of the month to the last day
        while date < monthInterval.end {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return dates
    }
    
    private var weeksInMonth: [[Date?]] {
        let days = daysInMonth
        guard !days.isEmpty else {
            return []
        }
        
        // Get the weekday of the first day (1 = Sunday, 7 = Saturday)
        let firstDay = days.first!
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        // Convert to 0-based index (0 = first day of week)
        let firstDayIndex = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = []
        
        // Pad the first week with nil (empty cells)
        for _ in 0..<firstDayIndex {
            currentWeek.append(nil)
        }
        
        // Add all days from the month
        for date in days {
            currentWeek.append(date)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        
        // Add the last week if it has days (may have nil padding at the end)
        if !currentWeek.isEmpty {
            // Pad to 7 days with nil if needed
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }
        
        return weeks
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Month navigation header with buttons
            monthNavigationHeader
            
            // Weekday headers
            weekdayHeaders
            
            // Calendar grid
            calendarGrid
                .id("\(currentMonth.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when month or filter changes
        }
        .background(backgroundColor)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    // Only track horizontal drag, not vertical
                    if abs(value.translation.width) > abs(value.translation.height) {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    // Only change month for horizontal swipes
                    if abs(value.translation.width) > abs(value.translation.height) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if value.translation.width > threshold {
                                previousMonth()
                                HapticManager.shared.selection()
                            } else if value.translation.width < -threshold {
                                nextMonth()
                                HapticManager.shared.selection()
                            }
                            dragOffset = 0
                        }
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onChange(of: selectedDate) { newDate in
            // Update current month when selected date changes
            if !calendar.isDate(newDate, equalTo: currentMonth, toGranularity: .month) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    currentMonth = newDate
                }
            }
        }
        .onChange(of: currentMonth) { _ in
            // Rebuild cache when month changes
            rebuildCacheForCurrentMonth()
            cachedMonthKey = monthKeyFor(currentMonth)
        }
        .onChange(of: selectedTagId) { newTagId in
            // CRITICAL: Update cached tag ID FIRST before clearing cache
            // This ensures getFilteredEvents knows the filter matches when rebuilding
            cachedTagId = newTagId

            // Clear old cache - UI updates immediately with new filter state
            cachedEventsForMonth.removeAll()

            // Rebuild cache on background thread for smooth UI
            Task.detached(priority: .userInitiated) {
                await rebuildCacheAsync()
            }
        }
        .onChange(of: taskManager.tasks) { _ in
            // Rebuild cache when tasks change
            rebuildCacheForCurrentMonth()
        }
        .onAppear {
            // Build initial cache
            rebuildCacheForCurrentMonth()
            cachedMonthKey = monthKeyFor(currentMonth)
            cachedTagId = selectedTagId
        }
    }
    
    // MARK: - Month Navigation Header
    
    private var monthNavigationHeader: some View {
        HStack {
            // Previous month button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    previousMonth()
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Month name
            Text(monthYearString)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(primaryTextColor)
            
            Spacer()
            
            // Today button
            let isCurrentMonth = calendar.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
            Button(action: {
                let today = calendar.startOfDay(for: Date())
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedDate = today
                    currentMonth = today
                }
                HapticManager.shared.selection()
            }) {
                Text("Today")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(isCurrentMonth ? primaryTextColor : primaryTextColor.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Next month button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    nextMonth()
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
    
    // MARK: - Weekday Headers
    
    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(weeksInMonth.enumerated()), id: \.offset) { weekIndex, week in
                weekRow(week: week, weekIndex: weekIndex)
            }
        }
        .offset(x: dragOffset * 0.3)
        .id("\(currentMonth.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when month or filter changes
    }
    
    // MARK: - Week Row
    
    private func weekRow(week: [Date?], weekIndex: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, date in
                if let date = date {
                    dayCell(date: date)
                        .frame(maxWidth: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16) // Match weekday header padding
        .frame(minHeight: 100) // Increased height for bigger calendar
    }
    
    // MARK: - Day Cell
    
    private func dayCell(date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let events = getFilteredEvents(for: date)
        
        return VStack(alignment: .leading, spacing: 2) {
                // Day number - center aligned
                HStack {
                    Spacer()
                    if isToday {
                        // Today: white circle outline (no fill), outline color = camera icon color
                        Text(dayNumber(date))
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .stroke(Color(red: 0.2, green: 0.2, blue: 0.2), lineWidth: 2)
                            )
                    } else if isSelected {
                        // Selected (not today): filled circle with camera icon color
                        Text(dayNumber(date))
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(Color.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.2)))
                    } else {
                        // Not selected, not today
                        Text(dayNumber(date))
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 24, height: 24)
                    }
                    Spacer()
                }
                .padding(.top, 4)
                
                // Events - not clickable, just for display
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(events.prefix(maxEventsPerCell).enumerated()), id: \.element.id) { index, event in
                        eventChip(event: event)
                    }
                    
                    // More indicator if there are more events than displayed
                    if events.count > maxEventsPerCell {
                        Text("+\(events.count - maxEventsPerCell) more")
                            .font(FontManager.geist(size: 9, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 4)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                isSelected && !isToday ?
                    (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)) :
                    Color.clear
            )
            .cornerRadius(ShadcnRadius.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDate = date
                }
                HapticManager.shared.selection()
            }
    }
    
    // MARK: - Event Chip
    
    private func eventChip(event: TaskItem) -> some View {
        let filterType = TimelineEventColorManager.filterType(from: event)
        let tagColorIndex: Int?
        if case .tag(let tagId) = filterType {
            tagColorIndex = tagManager.getTag(by: tagId)?.colorIndex
        } else {
            tagColorIndex = nil
        }
        
        let tagColor = TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
        
        let textColor: Color
        if case .tag(_) = filterType, let tagColorIndex = tagColorIndex {
            textColor = TimelineEventColorManager.tagColorTextColor(colorIndex: tagColorIndex, colorScheme: colorScheme)
        } else {
            textColor = TimelineEventColorManager.timelineEventTextColor(
                filterType: filterType,
                colorScheme: colorScheme,
                tagColorIndex: tagColorIndex
            )
        }
        
        // Fixed size chip - no button, just display
        return Text(event.title)
            .font(FontManager.geist(size: 10, weight: .medium))
            .foregroundColor(textColor)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(height: 18) // Fixed height for consistency
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(tagColor) // Solid color, no line
            )
    }
    
    // MARK: - Helper Methods
    
    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private func getFilteredEvents(for date: Date) -> [TaskItem] {
        // Create cache key for this date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = calendar.timeZone
        let dateKey = dateFormatter.string(from: calendar.startOfDay(for: date))
        
        // CRITICAL FIX: Always compare against the current selectedTagId property, not cached state
        // If they don't match, we MUST compute fresh results - never use cache
        let filterMatches = (cachedTagId == nil && selectedTagId == nil) || (cachedTagId == selectedTagId)
        
        // If filter changed or no cached data, compute fresh
        if !filterMatches {
            // Filter has changed - compute fresh results, don't cache (will be rebuilt by onChange)
            let allTasks = taskManager.getAllTasks(for: date)
            return applyFilter(to: allTasks)
        }
        
        // Filter matches - check cache
        if let cached = cachedEventsForMonth[dateKey] {
            return cached
        }
        
        // No cache for this date - compute and cache
        let allTasks = taskManager.getAllTasks(for: date)
        let filtered = applyFilter(to: allTasks)
        cachedEventsForMonth[dateKey] = filtered
        return filtered
    }
    
    private func monthKeyFor(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: month)
    }
    
    private func rebuildCacheForCurrentMonth() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = calendar.timeZone

        // Get all dates in the current month
        let dates = daysInMonth

        // Batch compute events for all dates in the month
        // Use the current selectedTagId from the closure context
        for date in dates {
            let dateKey = dateFormatter.string(from: calendar.startOfDay(for: date))
            let allTasks = taskManager.getAllTasks(for: date)
            let filtered = applyFilter(to: allTasks)
            cachedEventsForMonth[dateKey] = filtered
        }
    }

    private func rebuildCacheAsync() async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = calendar.timeZone

        let dates = daysInMonth
        let currentTagId = selectedTagId

        // Compute on background thread
        var newCache: [String: [TaskItem]] = [:]
        for date in dates {
            let dateKey = dateFormatter.string(from: calendar.startOfDay(for: date))
            let allTasks = taskManager.getAllTasks(for: date)
            let filtered = applyFilter(to: allTasks, tagId: currentTagId)
            newCache[dateKey] = filtered
        }

        // Update cache on main thread
        await MainActor.run {
            // Only update if filter hasn't changed during computation
            if cachedTagId == currentTagId {
                cachedEventsForMonth = newCache
            }
        }
    }

    private func applyFilter(to tasks: [TaskItem], tagId: String? = nil) -> [TaskItem] {
        // Use provided tagId or fall back to current selectedTagId
        let filterTagId = tagId ?? selectedTagId

        if let tagId = filterTagId {
            if tagId == "" {
                // Personal filter - show events with nil tagId (default/personal events) AND excluding synced calendar events
                return tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
            } else if tagId == "cal_sync" {
                // Personal - Sync filter - show only synced calendar events
                return tasks.filter { $0.id.hasPrefix("cal_") }
            } else {
                // Specific tag filter
                return tasks.filter { $0.tagId == tagId }
            }
        }
        // No filter - show all tasks
        return tasks
    }
    
    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
            HapticManager.shared.light()
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
            HapticManager.shared.light()
        }
    }
}

#Preview {
    CalendarMonthView(
        selectedDate: .constant(Date()),
        selectedTagId: nil,
        onTapEvent: { _ in }
    )
}

