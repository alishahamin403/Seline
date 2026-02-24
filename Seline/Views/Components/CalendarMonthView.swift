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
    @State private var monthPageSelection: Int = 1
    @State private var cachedEventsForMonth: [String: [TaskItem]] = [:] // Cache: dateKey -> filtered events
    @State private var cachedTagId: String? = nil // Track which tag filter is cached
    
    private let calendar = Calendar.current
    private let maxEventsPerCell = 1
    private let rowHeight: CGFloat = 64
    private static let cacheKeyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
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
        daysInMonth(for: currentMonth)
    }

    private var weeksInMonth: [[Date?]] {
        weeksInMonth(for: currentMonth)
    }

    private func daysInMonth(for month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
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

    private func weeksInMonth(for month: Date) -> [[Date?]] {
        let days = daysInMonth(for: month)
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
        }
        .background(backgroundColor)
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
            monthPageSelection = 1
        }
        .onChange(of: selectedTagId) { _ in
            rebuildCacheForCurrentMonth()
        }
        .onChange(of: taskManager.tasks) { _ in
            // Rebuild cache when tasks change
            rebuildCacheForCurrentMonth()
        }
        .onAppear {
            // Build initial cache
            rebuildCacheForCurrentMonth()
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
        .padding(.horizontal, 12)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        TabView(selection: $monthPageSelection) {
            monthGrid(for: monthOffset(-1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(-1)).count) * rowHeight, alignment: .top)
                .tag(0)

            monthGrid(for: currentMonth)
                .frame(height: CGFloat(weeksInMonth.count) * rowHeight, alignment: .top)
                .tag(1)

            monthGrid(for: monthOffset(1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(1)).count) * rowHeight, alignment: .top)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: CGFloat(weeksInMonth.count) * rowHeight)
        .onChange(of: monthPageSelection) { newSelection in
            guard newSelection != 1 else { return }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if newSelection == 0 {
                    previousMonth()
                } else {
                    nextMonth()
                }
            }

            DispatchQueue.main.async {
                monthPageSelection = 1
            }
        }
    }

    private func monthGrid(for month: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(weeksInMonth(for: month).enumerated()), id: \.offset) { weekIndex, week in
                weekRow(week: week, weekIndex: weekIndex)
            }
        }
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
        .padding(.horizontal, 12) // Match weekday header padding
        .frame(height: rowHeight)
    }
    
    // MARK: - Day Cell
    
    private func dayCell(date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let events = getFilteredEvents(for: date)
        
        return VStack(alignment: .leading, spacing: 1) {
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
                .padding(.top, 1)
                
                // Events - not clickable, just for display
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(events.prefix(maxEventsPerCell).enumerated()), id: \.element.id) { index, event in
                        eventChip(event: event)
                    }
                    
                    // More indicator if there are more events than displayed
                    if events.count > maxEventsPerCell {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(secondaryTextColor.opacity(0.8))
                                .frame(width: 3, height: 3)
                            Circle()
                                .fill(secondaryTextColor.opacity(0.8))
                                .frame(width: 3, height: 3)
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 4)
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
            .font(FontManager.geist(size: 9, weight: .medium))
            .foregroundColor(textColor)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(height: 16)
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
        let dateKey = dateCacheKey(for: date)
        
        // CRITICAL FIX: Always compare against the current selectedTagId property, not cached state
        // If they don't match, we MUST compute fresh results - never use cache
        let filterMatches = (cachedTagId == nil && selectedTagId == nil) || (cachedTagId == selectedTagId)
        
        // If filter changed, avoid expensive per-cell recomputation during transition.
        // onChange(selectedTagId) immediately rebuilds cache for the new filter.
        if !filterMatches {
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
    
    private func rebuildCacheForCurrentMonth() {
        let dates = daysInMonth
        let currentTagId = selectedTagId
        var nextCache: [String: [TaskItem]] = [:]
        nextCache.reserveCapacity(dates.count)

        for date in dates {
            let dateKey = dateCacheKey(for: date)
            let allTasks = taskManager.getAllTasks(for: date)
            let filtered = applyFilter(to: allTasks, tagId: currentTagId)
            nextCache[dateKey] = filtered
        }

        cachedEventsForMonth = nextCache
        cachedTagId = currentTagId
    }

    private func dateCacheKey(for date: Date) -> String {
        Self.cacheKeyDateFormatter.timeZone = calendar.timeZone
        return Self.cacheKeyDateFormatter.string(from: calendar.startOfDay(for: date))
    }

    private func applyFilter(to tasks: [TaskItem], tagId: String? = nil) -> [TaskItem] {
        // Use provided tagId or fall back to current selectedTagId
        let filterTagId = tagId ?? selectedTagId

        if let tagId = filterTagId {
            if tagId == "" {
                // Personal filter - show events with nil tagId (default/personal events) AND excluding synced calendar events
                return tasks.filter { task in
                    task.tagId == nil && !isSyncedCalendarTask(task)
                }
            } else if tagId == "cal_sync" {
                // Personal - Sync filter - show only synced calendar events
                return tasks.filter { task in
                    isSyncedCalendarTask(task)
                }
            } else {
                // Specific tag filter
                return tasks.filter { $0.tagId == tagId }
            }
        }
        // No filter - show all tasks
        return tasks
    }

    private func isSyncedCalendarTask(_ task: TaskItem) -> Bool {
        task.id.hasPrefix("cal_")
            || task.isFromCalendar
            || task.calendarEventId != nil
            || task.tagId == "cal_sync"
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

    private func monthOffset(_ value: Int) -> Date {
        calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
    }
}

#Preview {
    CalendarMonthView(
        selectedDate: .constant(Date()),
        selectedTagId: nil,
        onTapEvent: { _ in }
    )
}
