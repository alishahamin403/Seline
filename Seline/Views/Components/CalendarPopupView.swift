import SwiftUI

struct CalendarPopupView: View {
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    // Binding to parent's selected date - syncs calendar selection back to EventsView
    @Binding var selectedDate: Date

    // Filter support - passed from parent, but we use local state to allow changes within calendar
    var selectedTagId: String?
    @State private var localSelectedTagId: String? = nil
    @State private var selectedTaskForEditing: TaskItem?
    @State private var showingViewTaskSheet = false
    @State private var showingEditTaskSheet = false
    @State private var isTransitioningToEdit = false
    @State private var isAnimating = false

    // Computed property for filtered tasks - automatically updates when tasks, date, or filter changes
    private var tasksForDate: [TaskItem] {
        let allTasks = taskManager.getAllTasks(for: selectedDate)
        return applyFilter(to: allTasks)
    }

    private var sortedTasksByTime: [TaskItem] {
        tasksForDate.sorted { task1, task2 in
            let hasTime1 = task1.scheduledTime != nil
            let hasTime2 = task2.scheduledTime != nil

            // Events with time come before all-day events
            if hasTime1 != hasTime2 {
                return hasTime1
            }

            // Both have time or both don't have time
            if hasTime1, let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                // Extract just the time components (hour and minute) for comparison
                let calendar = Calendar.current
                let components1 = calendar.dateComponents([.hour, .minute], from: time1)
                let components2 = calendar.dateComponents([.hour, .minute], from: time2)

                let minutes1 = (components1.hour ?? 0) * 60 + (components1.minute ?? 0)
                let minutes2 = (components2.hour ?? 0) * 60 + (components2.minute ?? 0)

                return minutes1 < minutes2
            }

            // Both are all-day events, maintain order
            return false
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Shadcn-style custom calendar (compact)
                ShadcnCalendar(
                    selectedDate: $selectedDate,
                    taskManager: taskManager,
                    colorScheme: colorScheme,
                    selectedTagId: localSelectedTagId,
                    onDateChange: { _ in
                        // No manual refresh needed - tasksForDate is now a computed property
                    }
                )
                .padding(.top, 12)
                .padding(.bottom, 16)

                // Filter buttons - Show "All", "Personal", and all user-created tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" button (neutral black/white, no color impact)
                        Button(action: {
                            localSelectedTagId = nil
                        }) {
                            Text("All")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == nil ? Color.shadcnForeground(colorScheme) : Color.shadcnForeground(colorScheme).opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .fill(localSelectedTagId == nil ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.15 : 0.12) :
                                            Color.shadcnTileBackground(colorScheme).opacity(0.5)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .stroke(
                                            localSelectedTagId == nil ?
                                                TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme).opacity(0.3) :
                                                (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Personal (default) button - using special marker ""
                        Button(action: {
                            localSelectedTagId = "" // Empty string to filter for personal events (nil tagId)
                        }) {
                            Text("Personal")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == "" ? Color.shadcnForeground(colorScheme) : Color.shadcnForeground(colorScheme).opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .fill(localSelectedTagId == "" ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.15 : 0.12) :
                                            Color.shadcnTileBackground(colorScheme).opacity(0.5)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .stroke(
                                            localSelectedTagId == "" ?
                                                TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme).opacity(0.3) :
                                                (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Personal - Sync button (Calendar synced events)
                        Button(action: {
                            localSelectedTagId = "cal_sync" // Special marker for synced calendar events
                        }) {
                            Text("Personal - Sync")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == "cal_sync" ? Color.shadcnForeground(colorScheme) : Color.shadcnForeground(colorScheme).opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .fill(localSelectedTagId == "cal_sync" ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.15 : 0.12) :
                                            Color.shadcnTileBackground(colorScheme).opacity(0.5)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .stroke(
                                            localSelectedTagId == "cal_sync" ?
                                                TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme).opacity(0.3) :
                                                (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // User-created tags
                        ForEach(tagManager.tags, id: \.id) { tag in
                            Button(action: {
                                localSelectedTagId = tag.id
                            }) {
                                Text(tag.name)
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                    .foregroundColor(localSelectedTagId == tag.id ? Color.shadcnForeground(colorScheme) : Color.shadcnForeground(colorScheme).opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                            .fill(localSelectedTagId == tag.id ?
                                                TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex).opacity(colorScheme == .dark ? 0.15 : 0.12) :
                                                Color.shadcnTileBackground(colorScheme).opacity(0.5)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                            .stroke(
                                                localSelectedTagId == tag.id ?
                                                    TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex).opacity(0.3) :
                                                    (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)

                // Events section - Vertical scrolling cards with animation
                VStack(alignment: .leading, spacing: 12) {
                    if tasksForDate.isEmpty {
                        // Empty state
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(FontManager.geist(size: 24, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                            Text("No events")
                                .font(.shadcnTextXs)
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .offset(y: isAnimating ? 0 : 20)
                        .opacity(isAnimating ? 1 : 0)
                    } else {
                        // Vertical scrolling event cards, sorted by time
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(Array(sortedTasksByTime.enumerated()), id: \.element.id) { index, task in
                                    EventCardCompact(
                                        task: task,
                                        selectedDate: selectedDate,
                                        onTap: {
                                            selectedTaskForEditing = task
                                            showingViewTaskSheet = true
                                        },
                                        onToggleCompletion: {
                                            taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                    .offset(y: isAnimating ? 0 : 20)
                                    .opacity(isAnimating ? 1 : 0)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)

                Spacer()
            }
            .background(
                colorScheme == .dark ?
                    Color.black : Color.white
            )
        }
        .onAppear {
            // Initialize local filter state with passed value (if any)
            localSelectedTagId = selectedTagId

            // Trigger slide-up animation
            withAnimation(.easeOut(duration: 0.4)) {
                isAnimating = true
            }
        }
        .sheet(isPresented: $showingViewTaskSheet) {
            if let task = selectedTaskForEditing {
                NavigationView {
                    ViewEventView(
                        task: task,
                        onEdit: {
                            // Mark that we're transitioning to edit
                            isTransitioningToEdit = true
                            showingViewTaskSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingEditTaskSheet = true
                            }
                        },
                        onDelete: { taskToDelete in
                            taskManager.deleteTask(taskToDelete)
                            showingViewTaskSheet = false
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            showingViewTaskSheet = false
                        }
                    )
                }
            }
        }
    .presentationBg()
        .sheet(isPresented: $showingEditTaskSheet) {
            if let task = selectedTaskForEditing {
                NavigationView {
                    EditTaskView(
                        task: task,
                        onSave: { updatedTask in
                            taskManager.editTask(updatedTask)
                            showingEditTaskSheet = false
                        },
                        onCancel: {
                            showingEditTaskSheet = false
                        },
                        onDelete: { taskToDelete in
                            taskManager.deleteTask(taskToDelete)
                            showingEditTaskSheet = false
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            showingEditTaskSheet = false
                        }
                    )
                }
            }
        }
    .presentationBg()
        .onChange(of: showingViewTaskSheet) { isShowing in
            // Clear task when view sheet is dismissed (unless transitioning to edit)
            if !isShowing && !isTransitioningToEdit {
                selectedTaskForEditing = nil
            }
        }
        .onChange(of: showingEditTaskSheet) { isShowing in
            // Reset transition flag and clear task when edit sheet is dismissed
            if !isShowing {
                isTransitioningToEdit = false
                selectedTaskForEditing = nil
            } else {
                // Reset flag when edit sheet opens
                isTransitioningToEdit = false
            }
        }
    }

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }

    /// Apply the current filter to tasks
    private func applyFilter(to tasks: [TaskItem]) -> [TaskItem] {
        if let tagId = localSelectedTagId {
            if tagId == "" {
                // Personal filter - show events with nil tagId (default/personal events)
                return tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
            } else if tagId == "cal_sync" {
                // Personal - Sync filter - show only synced calendar events
                return tasks.filter { $0.id.hasPrefix("cal_") }
            } else {
                // Specific tag filter
                return tasks.filter { $0.tagId == tagId }
            }
        } else {
            // No filter - show all tasks
            return tasks
        }
    }

    private func weekdayFromDate(_ date: Date) -> WeekDay? {
        let calendar = Calendar.current
        let weekdayComponent = calendar.component(.weekday, from: date)

        switch weekdayComponent {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }


}

struct TaskRowCalendar: View {
    let task: TaskItem
    let selectedDate: Date
    let onView: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onDeleteRecurringSeries: (() -> Void)?
    let onCompletionToggled: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @State private var showingDeleteAlert = false

    // Check if task is completed on this specific date
    private var isTaskCompleted: Bool {
        return task.isCompletedOn(date: selectedDate)
    }

    // Check if this is an iPhone calendar event (synced from iPhone calendar)
    private var isIPhoneCalendarEvent: Bool {
        return task.id.hasPrefix("cal_")
    }

    // Get filter type to determine color
    private var filterType: TimelineEventColorManager.FilterType {
        TimelineEventColorManager.filterType(from: task)
    }

    // Get the actual colorIndex from the tag for consistent colors
    private var tagColorIndex: Int? {
        guard case .tag(let tagId) = filterType else { return nil }
        return tagManager.getTag(by: tagId)?.colorIndex
    }

    // Get accent color for the filter
    private var accentColor: Color {
        TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (completed or incomplete) - always use filter color
            // Only make interactive for non-iPhone calendar events
            Image(systemName: isTaskCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isIPhoneCalendarEvent ? accentColor.opacity(0.5) : accentColor)
                .font(FontManager.geist(size: 18, weight: .medium))
                .onTapGesture {
                    // Toggle completion only if NOT an iPhone calendar event
                    if !isIPhoneCalendarEvent {
                        taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                        onCompletionToggled?()
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                // Task title
                Text(task.title)
                    .font(.shadcnTextSm)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white : Color.black)

                // Show only time if there's a scheduled time
                if !task.formattedTime.isEmpty {
                    Text(task.formattedTime)
                        .font(.shadcnTextXs)
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }

            Spacer()

            // Recurring indicator
            if task.isRecurring {
                Image(systemName: "repeat")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: {
            // Tap opens view mode (read-only) - but not if tapping the circle
            onView?()
        })
        .contextMenu {
            // Context menu "Edit" opens edit mode directly
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
            }

            // Show delete option
            Button(role: .destructive, action: {
                if task.isRecurring || task.parentRecurringTaskId != nil {
                    showingDeleteAlert = true
                } else {
                    onDelete?()
                }
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Event", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
            Button("Delete This Event Only", role: .destructive) {
                onDelete?()
            }

            if task.isRecurring {
                Button("Delete All Recurring Events", role: .destructive) {
                    onDeleteRecurringSeries?()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(task.isRecurring ? "This is a recurring event. What would you like to delete?" : "Delete this event?")
        }
    }
}

struct FrequencyOptionButton: View {
    let frequency: RecurrenceFrequency
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: frequency.icon)
                    .foregroundColor(isSelected ? Color.shadcnPrimary : Color.shadcnMutedForeground(colorScheme))
                    .font(FontManager.geist(size: 20, weight: .medium))

                Text(frequency.displayName)
                    .font(.shadcnTextXs)
                    .foregroundColor(isSelected ? Color.shadcnPrimary : Color.shadcnMutedForeground(colorScheme))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(
                        isSelected ?
                            (colorScheme == .dark ? Color.shadcnPrimary.opacity(0.2) : Color.shadcnPrimary.opacity(0.1)) :
                            (colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnRadius.md)
                            .stroke(
                                isSelected ? Color.shadcnPrimary : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ShadcnCalendar: View {
    @Binding var selectedDate: Date
    let taskManager: TaskManager
    let colorScheme: ColorScheme
    let selectedTagId: String?
    let onDateChange: (Date) -> Void

    @State private var currentMonth = Date()
    @State private var dragStartX: CGFloat = 0

    private var calendar: Calendar {
        Calendar.current
    }

    /// Get event count for a specific date with current filter applied
    private func getEventCountForDate(_ date: Date) -> Int {
        let allTasks = taskManager.getAllTasks(for: date)
        let filteredTasks = applyFilter(to: allTasks)
        return filteredTasks.count
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var dates: [Date] = []
        var date = monthFirstWeek.start

        while date < monthInterval.end {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        // Pad to complete weeks
        while calendar.component(.weekday, from: dates.last ?? Date()) != 1 {
            if let lastDate = dates.last,
               let nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate) {
                dates.append(nextDate)
            } else {
                break
            }
        }

        return dates
    }

    private let weekdaySymbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    var body: some View {
        VStack(spacing: 6) {
            // Header with navigation
            HStack(spacing: 8) {
                // Previous month button
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Month and year
                Text(monthYearFormatter.string(from: currentMonth))
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .frame(maxWidth: .infinity)

                // Today button
                Button(action: {
                    selectedDate = Date()
                    currentMonth = Date()
                    onDateChange(Date())
                }) {
                    Text("Today")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.sm)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Next month button
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(daysInMonth, id: \.self) { date in
                    let eventCount = getEventCountForDate(date)

                    ShadcnDayCell(
                        date: date,
                        selectedDate: $selectedDate,
                        currentMonth: currentMonth,
                        eventCount: eventCount,
                        colorScheme: colorScheme,
                        onTap: {
                            selectedDate = date
                            onDateChange(date)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragStartX = value.location.x
                    }
                    .onEnded { value in
                        let dragDistance = value.location.x - dragStartX
                        let threshold: CGFloat = 50

                        if dragDistance > threshold {
                            // Swiped right - previous month
                            previousMonth()
                        } else if dragDistance < -threshold {
                            // Swiped left - next month
                            nextMonth()
                        }
                    }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .padding(.horizontal, 12)
    }

    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }

    /// Apply the current filter to tasks
    private func applyFilter(to tasks: [TaskItem]) -> [TaskItem] {
        if let tagId = selectedTagId {
            if tagId == "" {
                // Personal filter - show events with nil tagId (default/personal events)
                return tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
            } else if tagId == "cal_sync" {
                // Personal - Sync filter - show only synced calendar events
                return tasks.filter { $0.id.hasPrefix("cal_") }
            } else {
                // Specific tag filter
                return tasks.filter { $0.tagId == tagId }
            }
        } else {
            // No filter - show all tasks
            return tasks
        }
    }
}

struct ShadcnDayCell: View {
    let date: Date
    @Binding var selectedDate: Date
    let currentMonth: Date
    let eventCount: Int
    let colorScheme: ColorScheme
    let onTap: () -> Void

    private var calendar: Calendar {
        Calendar.current
    }

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var isSelected: Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private var isInCurrentMonth: Bool {
        calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(FontManager.geist(size: 13, systemWeight: isToday ? .semibold : .regular))
                    .foregroundColor(textColor)

                // Show dots if there are events
                if eventCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(dotColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    // Empty space to maintain consistent height
                    HStack(spacing: 2) {}
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(backgroundColor)
            .cornerRadius(ShadcnRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var textColor: Color {
        if isSelected {
            // In dark mode: white background with black text
            // In light mode: black background with white text
            return colorScheme == .dark ? Color.black : Color.white
        } else if isToday {
            // Today: white/black per theme instead of blue
            return colorScheme == .dark ? Color.white : Color.black
        } else if !isInCurrentMonth {
            return (colorScheme == .dark ? Color.white : Color.black).opacity(0.4)
        } else {
            return Color.shadcnForeground(colorScheme)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            // In dark mode: white fill for selected day with black text
            // In light mode: black fill for selected day with white text
            return colorScheme == .dark ? Color.white : Color.black
        } else if isToday {
            // Today: light gray indicator instead of blue
            return (colorScheme == .dark ? Color.white : Color.black).opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var dotColor: Color {
        // Use accent color based on theme
        return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selectedDate = Date()

        var body: some View {
            CalendarPopupView(selectedDate: $selectedDate, selectedTagId: nil)
        }
    }

    return PreviewContainer()
}
