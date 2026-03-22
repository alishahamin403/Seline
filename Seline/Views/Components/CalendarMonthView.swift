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
    private let rowHeight: CGFloat = 58
    private static let cacheKeyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
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
        Color.appTextPrimary(colorScheme)
    }
    
    private var secondaryTextColor: Color {
        Color.emailGlassMutedText(colorScheme)
    }
    
    private var backgroundColor: Color {
        Color.clear
    }
    
    // MARK: - Date Calculations
    
    // Only show days from 1st to end of month, no extra days
    private var daysInMonth: [Date] {
        daysInMonth(for: currentMonth)
    }

    private var weeksInMonth: [[Date?]] {
        weeksInMonth(for: currentMonth)
    }

    private var previousMonthWeeks: [[Date?]] {
        weeksInMonth(for: monthOffset(-1))
    }

    private var nextMonthWeeks: [[Date?]] {
        weeksInMonth(for: monthOffset(1))
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
            if !calendar.isDate(newDate, equalTo: currentMonth, toGranularity: .month) {
                withAnimation(.easeInOut(duration: 0.26)) {
                    currentMonth = newDate
                }
            }
        }
        .onChange(of: currentMonth) { _ in
            rebuildCacheForCurrentMonth()
            monthPageSelection = 1
        }
        .onChange(of: selectedTagId) { _ in
            rebuildCacheForCurrentMonth()
        }
        .onChange(of: taskManager.tasks) { _ in
            rebuildCacheForCurrentMonth()
        }
        .onAppear {
            rebuildCacheForCurrentMonth()
        }
    }
    
    // MARK: - Month Navigation Header
    
    private var monthNavigationHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.26)) {
                    previousMonth()
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text(monthYearString)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Button(action: {
                let today = calendar.startOfDay(for: Date())
                withAnimation(.easeInOut(duration: 0.26)) {
                    selectedDate = today
                    currentMonth = today
                }
                HapticManager.shared.selection()
            }) {
                Text("Today")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.26)) {
                    nextMonth()
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
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
        Self.monthYearFormatter.string(from: currentMonth)
    }
    
    // MARK: - Weekday Headers
    
    private var weekdayHeaders: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        TabView(selection: $monthPageSelection) {
            monthGrid(weeks: previousMonthWeeks)
                .frame(height: CGFloat(previousMonthWeeks.count) * rowHeight, alignment: .top)
                .tag(0)

            monthGrid(weeks: weeksInMonth)
                .frame(height: CGFloat(weeksInMonth.count) * rowHeight, alignment: .top)
                .tag(1)

            monthGrid(weeks: nextMonthWeeks)
                .frame(height: CGFloat(nextMonthWeeks.count) * rowHeight, alignment: .top)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: CGFloat(weeksInMonth.count) * rowHeight)
        .padding(.bottom, 10)
        .onChange(of: monthPageSelection) { newSelection in
            guard newSelection != 1 else { return }

            withAnimation(.easeInOut(duration: 0.26)) {
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

    private func monthGrid(weeks: [[Date?]]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                weekRow(week: week, weekIndex: weekIndex)
            }
        }
    }
    
    // MARK: - Week Row
    
    private func weekRow(week: [Date?], weekIndex: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, date in
                if let date = date {
                    dayCell(date: date, in: currentMonth)
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
    
    private func dayCell(date: Date, in month: Date) -> some View {
        let normalizedDate = calendar.startOfDay(for: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let events = getFilteredEvents(for: date)
        let isInCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = normalizedDate
            }
            HapticManager.shared.selection()
        }) {
            VStack(spacing: 5) {
                Text(dayNumber(date))
                    .font(FontManager.geist(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? .black : .white) :
                        !isInCurrentMonth ? (colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35)) :
                        (colorScheme == .dark ? Color.white : Color.black)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(colorScheme == .dark ? Color.white : Color.black)
                            } else if isToday {
                                Circle().stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3),
                                    lineWidth: 1.5
                                )
                            }
                        }
                    )

                if !events.isEmpty {
                    Text(eventCountLabel(for: events.count))
                        .font(FontManager.geist(size: 8, weight: .medium))
                        .foregroundColor(
                            isSelected
                            ? (colorScheme == .dark ? .black : .white)
                            : (colorScheme == .dark ? Color.white.opacity(0.74) : Color.black.opacity(0.72))
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                    ? (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                                    : (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                )
                        )
                } else {
                    Color.clear
                        .frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func dayNumber(_ date: Date) -> String {
        Self.dayNumberFormatter.string(from: date)
    }

    private func eventCountLabel(for count: Int) -> String {
        "\(count) event\(count == 1 ? "" : "s")"
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
        
        if let cached = cachedEventsForMonth[dateKey] {
            return cached
        }

        let allTasks = taskManager.getAllTasks(for: date)
        return applyFilter(to: allTasks)
    }
    
    private func rebuildCacheForCurrentMonth() {
        let dates = daysInMonth(for: monthOffset(-1)) + daysInMonth + daysInMonth(for: monthOffset(1))
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
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
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
