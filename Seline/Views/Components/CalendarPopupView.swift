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
    @State private var tasksForDate: [TaskItem] = []
    @State private var selectedTaskForEditing: TaskItem?
    @State private var showingViewTaskSheet = false
    @State private var showingEditTaskSheet = false
    @State private var isTransitioningToEdit = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Shadcn-style custom calendar (compact)
                ShadcnCalendar(
                    selectedDate: $selectedDate,
                    taskManager: taskManager,
                    colorScheme: colorScheme,
                    selectedTagId: localSelectedTagId,
                    onDateChange: { newDate in
                        updateTasksForDate(for: newDate)
                    }
                )
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 16)

                // Filter buttons - Show "All", "Personal", and all user-created tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" button (neutral black/white, no color impact)
                        Button(action: {
                            localSelectedTagId = nil
                            updateTasksForDate(for: selectedDate)
                        }) {
                            Text("All")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == nil ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(localSelectedTagId == nil ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme).opacity(0.2) :
                                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Personal (default) button - using special marker ""
                        Button(action: {
                            localSelectedTagId = "" // Empty string to filter for personal events (nil tagId)
                            updateTasksForDate(for: selectedDate)
                        }) {
                            Text("Personal")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == "" ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(localSelectedTagId == "" ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme).opacity(0.2) :
                                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Personal - Sync button (Calendar synced events)
                        Button(action: {
                            localSelectedTagId = "cal_sync" // Special marker for synced calendar events
                            updateTasksForDate(for: selectedDate)
                        }) {
                            Text("Personal - Sync")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(localSelectedTagId == "cal_sync" ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(localSelectedTagId == "cal_sync" ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme).opacity(0.2) :
                                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // User-created tags
                        ForEach(tagManager.tags, id: \.id) { tag in
                            Button(action: {
                                localSelectedTagId = tag.id
                                updateTasksForDate(for: selectedDate)
                            }) {
                                Text(tag.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(localSelectedTagId == tag.id ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(localSelectedTagId == tag.id ?
                                                TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex).opacity(0.2) :
                                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
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

                // Completed tasks section
                VStack(alignment: .leading, spacing: 8) {

                    if tasksForDate.isEmpty {
                        // Empty state
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Text("No tasks")
                                .font(.shadcnTextSm)
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Text("Tasks for this date will appear here")
                                .font(.shadcnTextXs)
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Tasks list
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tasksForDate) { task in
                                    TaskRowCalendar(
                                        task: task,
                                        selectedDate: selectedDate,
                                        onView: {
                                            selectedTaskForEditing = task
                                            showingViewTaskSheet = true
                                        },
                                        onEdit: {
                                            selectedTaskForEditing = task
                                            showingEditTaskSheet = true
                                        },
                                        onDelete: {
                                            taskManager.deleteTask(task)
                                            updateTasksForDate(for: selectedDate)
                                        },
                                        onDeleteRecurringSeries: {
                                            taskManager.deleteRecurringTask(task)
                                            updateTasksForDate(for: selectedDate)
                                        },
                                        onCompletionToggled: {
                                            updateTasksForDate(for: selectedDate)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                Spacer()
            }
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
        }
        .onAppear {
            // Initialize local filter state with passed value (if any)
            localSelectedTagId = selectedTagId
            updateTasksForDate(for: selectedDate)
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
                            updateTasksForDate(for: selectedDate)
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            showingViewTaskSheet = false
                            updateTasksForDate(for: selectedDate)
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
                            updateTasksForDate(for: selectedDate)
                        },
                        onCancel: {
                            showingEditTaskSheet = false
                        },
                        onDelete: { taskToDelete in
                            taskManager.deleteTask(taskToDelete)
                            showingEditTaskSheet = false
                            updateTasksForDate(for: selectedDate)
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            showingEditTaskSheet = false
                            updateTasksForDate(for: selectedDate)
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

    private func updateTasksForDate(for date: Date) {
        let allTasks = taskManager.getAllTasks(for: date)
        tasksForDate = applyFilter(to: allTasks)
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
                .font(.system(size: 18, weight: .medium))
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
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 20, weight: .medium))

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
                        .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .frame(maxWidth: .infinity)

                // Today button
                Button(action: {
                    selectedDate = Date()
                    currentMonth = Date()
                    onDateChange(Date())
                }) {
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 16, weight: .medium))
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
                        .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
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