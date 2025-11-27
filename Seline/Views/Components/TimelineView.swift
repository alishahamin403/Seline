import SwiftUI

struct TimelineView: View {
    let date: Date
    let selectedTagId: String?
    let onTapTask: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void
    let onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)?
    let onEditEvent: ((TaskItem) -> Void)?
    let onDeleteEvent: ((TaskItem) -> Void)?
    @Binding var isCreatingEvent: Bool

    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTimeSlot: Date?
    @State private var newEventTitle = ""
    @State private var newEventTime: Date?
    @State private var showReminderOptions = false
    @State private var selectedReminder: ReminderTime = .none
    @FocusState private var isTextFieldFocused: Bool

    init(
        date: Date,
        selectedTagId: String? = nil,
        isCreatingEvent: Binding<Bool>,
        onTapTask: @escaping (TaskItem) -> Void,
        onToggleCompletion: @escaping (TaskItem) -> Void,
        onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)? = nil,
        onEditEvent: ((TaskItem) -> Void)? = nil,
        onDeleteEvent: ((TaskItem) -> Void)? = nil
    ) {
        self.date = date
        self.selectedTagId = selectedTagId
        self._isCreatingEvent = isCreatingEvent
        self.onTapTask = onTapTask
        self.onToggleCompletion = onToggleCompletion
        self.onAddEvent = onAddEvent
        self.onEditEvent = onEditEvent
        self.onDeleteEvent = onDeleteEvent
    }

    // MARK: - Compatibility Init (for backward compatibility)
    init(
        tasks: [TaskItem],
        date: Date,
        onTapTask: @escaping (TaskItem) -> Void,
        onToggleCompletion: @escaping (TaskItem) -> Void,
        onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)? = nil,
        onEditEvent: ((TaskItem) -> Void)? = nil,
        onDeleteEvent: ((TaskItem) -> Void)? = nil
    ) {
        self.init(
            date: date,
            selectedTagId: nil,
            isCreatingEvent: .constant(false),
            onTapTask: onTapTask,
            onToggleCompletion: onToggleCompletion,
            onAddEvent: onAddEvent,
            onEditEvent: onEditEvent,
            onDeleteEvent: onDeleteEvent
        )
    }

    // Hour height in points (60 points per hour)
    private let hourHeight: CGFloat = 60

    // Total timeline height (24 hours)
    private var totalHeight: CGFloat {
        hourHeight * 24
    }

    // Get all tasks for this date from TaskManager
    private var allTasksForDate: [TaskItem] {
        taskManager.getAllTasks(for: date)
    }

    // Filter tasks based on tag filter (same logic as CalendarPopupView)
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

    // Get filtered tasks for this date
    private var filteredTasksForDate: [TaskItem] {
        applyFilter(to: allTasksForDate)
    }

    // Tasks with scheduled times, sorted by start time for consistent layout
    private var scheduledTasks: [TaskItem] {
        let filtered = filteredTasksForDate.filter { $0.scheduledTime != nil }

        // Deduplicate tasks with the same title and time (prevent duplicate recurring events)
        // Keep only the first occurrence
        var seenEventKeys = Set<String>()
        var deduplicated: [TaskItem] = []

        for task in filtered {
            if let scheduledTime = task.scheduledTime {
                let calendar = Calendar.current
                let timeStr = calendar.component(.hour, from: scheduledTime).description + ":" + calendar.component(.minute, from: scheduledTime).description
                let eventKey = "\(task.title.lowercased())|\(timeStr)"

                if !seenEventKeys.contains(eventKey) {
                    deduplicated.append(task)
                    seenEventKeys.insert(eventKey)
                }
            } else {
                deduplicated.append(task)
            }
        }

        let sorted = deduplicated.sorted { task1, task2 in
            guard let time1 = task1.scheduledTime, let time2 = task2.scheduledTime else {
                return false
            }
            if time1 == time2 {
                // If same start time, sort by ID for consistency
                return task1.id < task2.id
            }
            return time1 < time2
        }

        return sorted
    }

    // Event layout information
    struct EventLayout {
        let task: TaskItem
        let column: Int
        let totalColumns: Int
    }

    // Compute layouts for all events, handling overlaps
    private var eventLayouts: [EventLayout] {
        let tasksToLayout = scheduledTasks

        guard !tasksToLayout.isEmpty else {
            return []
        }

        var layouts: [EventLayout] = []

        // Group tasks into overlapping sets
        var groups: [[TaskItem]] = []
        var assigned: Set<String> = []

        for task in tasksToLayout {
            if assigned.contains(task.id) {
                continue
            }

            // Start a new group with this task
            var group = [task]
            assigned.insert(task.id)

            // Keep expanding the group with overlapping tasks
            var i = 0
            while i < group.count {
                let currentTask = group[i]

                // Find all unassigned tasks that overlap with current task
                for otherTask in tasksToLayout {
                    if !assigned.contains(otherTask.id) && tasksOverlap(currentTask, otherTask) {
                        group.append(otherTask)
                        assigned.insert(otherTask.id)
                    }
                }
                i += 1
            }

            groups.append(group)
        }

        // For each group, assign columns
        for group in groups {
            // Sort by start time, then by duration (longer first), then by ID for consistency
            let sortedGroup = group.sorted { task1, task2 in
                guard let time1 = task1.scheduledTime, let time2 = task2.scheduledTime else {
                    return false
                }
                if time1 == time2 {
                    let dur1 = duration(for: task1)
                    let dur2 = duration(for: task2)
                    if dur1 == dur2 {
                        return task1.id < task2.id
                    }
                    return dur1 > dur2
                }
                return time1 < time2
            }

            // First pass: assign columns to tasks in this group
            var groupLayouts: [EventLayout] = []
            for task in sortedGroup {
                let column = groupLayouts.filter { layout in
                    return tasksOverlap(task, layout.task)
                }.count

                groupLayouts.append(EventLayout(
                    task: task,
                    column: column,
                    totalColumns: 1 // Temporary, will be updated
                ))
            }

            // Second pass: set totalColumns for all tasks in the group
            let maxColumn = groupLayouts.map { $0.column }.max() ?? 0
            let totalColumns = maxColumn + 1

            for i in 0..<groupLayouts.count {
                let layout = groupLayouts[i]
                layouts.append(EventLayout(
                    task: layout.task,
                    column: layout.column,
                    totalColumns: totalColumns
                ))
            }
        }

        return layouts
    }

    private func tasksOverlap(_ task1: TaskItem, _ task2: TaskItem) -> Bool {
        guard let start1 = task1.scheduledTime,
              let start2 = task2.scheduledTime else {
            return false
        }

        let cal = Calendar.current

        // Extract time components only (hour, minute)
        let time1Start = cal.dateComponents([.hour, .minute], from: start1)
        let time2Start = cal.dateComponents([.hour, .minute], from: start2)

        // Get end times
        let end1 = task1.endTime ?? cal.date(byAdding: .hour, value: 1, to: start1)!
        let end2 = task2.endTime ?? cal.date(byAdding: .hour, value: 1, to: start2)!

        let time1End = cal.dateComponents([.hour, .minute], from: end1)
        let time2End = cal.dateComponents([.hour, .minute], from: end2)

        // Convert to minutes since midnight for easy comparison
        let start1Minutes = (time1Start.hour ?? 0) * 60 + (time1Start.minute ?? 0)
        let end1Minutes = (time1End.hour ?? 0) * 60 + (time1End.minute ?? 0)
        let start2Minutes = (time2Start.hour ?? 0) * 60 + (time2Start.minute ?? 0)
        let end2Minutes = (time2End.hour ?? 0) * 60 + (time2End.minute ?? 0)

        // Events DON'T overlap if one ends before or when the other starts
        let overlaps = !(end1Minutes <= start2Minutes || end2Minutes <= start1Minutes)

        return overlaps
    }

    private func duration(for task: TaskItem) -> TimeInterval {
        guard let start = task.scheduledTime else { return 3600 }
        let end = task.endTime ?? Calendar.current.date(byAdding: .hour, value: 1, to: start)!
        return end.timeIntervalSince(start)
    }

    // Check if viewing today
    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    // Current time in minutes from midnight
    private var currentTimeMinutes: Int? {
        guard isToday else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    // Calculate Y position from time
    private func yPosition(for time: Date) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return CGFloat(minutes) / 60.0 * hourHeight
    }

    private var accentColor: Color {
        colorScheme == .dark ?
            Color.white : // White in dark mode
            Color.black   // Black in light mode
    }

    var body: some View {
        ZStack {
            if !isCreatingEvent {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                // Timeline background with hour markers
                                timelineBackground

                                // Clickable overlay for time slots
                                timeSlotClickableLayer
                                    .padding(.leading, 60) // Leave space for time labels

                                // Events layer
                                eventsLayer
                                    .padding(.leading, 60) // Leave space for time labels

                                // Show + indicator only (not inline creator)
                                if let selectedSlot = selectedTimeSlot {
                                    plusIndicator(at: selectedSlot)
                                        .padding(.leading, 60)
                                }

                                // Current time indicator
                                if let currentMinutes = currentTimeMinutes {
                                    currentTimeIndicator(minutes: currentMinutes)
                                }
                            }
                            .frame(height: totalHeight)
                            .id("timeline")
                        }
                        .onAppear {
                            if isToday, let currentMinutes = currentTimeMinutes {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo("timeline")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Full-screen event creator modal
            if isCreatingEvent, let eventTime = newEventTime {
                inlineEventCreator(at: eventTime)
                    .transition(.move(edge: .bottom))
            }
        }
    }

    private func handleTimelineTap(at timeSlot: Date) {
        // If creating event, cancel and optionally select new slot
        if isCreatingEvent {
            cancelEventCreation()
        }

        // If already selected, show inline creator
        if selectedTimeSlot == timeSlot {
            newEventTime = timeSlot
            isCreatingEvent = true
            selectedTimeSlot = nil
            HapticManager.shared.cardTap()
            // Auto-focus text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        } else {
            // First click - show + indicator
            selectedTimeSlot = timeSlot
            HapticManager.shared.selection()
        }
    }

    private func calculateTimeSlot(from yPosition: CGFloat) -> Date? {
        let totalMinutes = Int((yPosition / hourHeight) * 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        // Round to nearest 30 minutes
        let roundedMinutes = (minutes / 30) * 30

        // Create date with selected time
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hours
        components.minute = roundedMinutes

        return Calendar.current.date(from: components)
    }

    // MARK: - Timeline Background

    private var timelineBackground: some View {
        ZStack(alignment: .topLeading) {
            // Hour markers
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    // Hour label
                    Text(formatHour(hour))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(
                            colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
                        )
                        .frame(width: 50, alignment: .trailing)
                        .padding(.trailing, 10)
                        .offset(y: -6) // Align with line

                    // Hour line - thinner stroke
                    Rectangle()
                        .fill(
                            colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)
                        )
                        .frame(height: 0.5)
                }
                .offset(y: CGFloat(hour) * hourHeight)
            }
        }
    }

    // MARK: - Time Slot Clickable Layer

    private var timeSlotClickableLayer: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { half in
                        timeSlotButton(hour: hour, half: half)
                    }
                }
            }
        }
    }

    private func timeSlotButton(hour: Int, half: Int) -> some View {
        Button(action: {
            let minutes = (half == 0 ? 0 : 30)
            if let timeSlot = Calendar.current.date(bySettingHour: hour, minute: minutes, second: 0, of: date) {
                handleTimelineTap(at: timeSlot)
            }
        }) {
            Rectangle()
                .fill(Color.clear)
        }
        .frame(height: hourHeight / 2)
    }

    // MARK: - Events Layer

    private var eventsLayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(eventLayouts, id: \.task.id) { layout in
                    if let scheduledTime = layout.task.scheduledTime {
                        let availableWidth = geometry.size.width - 16
                        let gapWidth: CGFloat = 4
                        let totalGaps = CGFloat(max(0, layout.totalColumns - 1)) * gapWidth
                        let columnWidth = (availableWidth - totalGaps) / CGFloat(layout.totalColumns)
                        let xOffset = (columnWidth + gapWidth) * CGFloat(layout.column)
                        let yPos = yPosition(for: scheduledTime)

                        TimelineEventBlock(
                            task: layout.task,
                            date: date,
                            onTap: {
                                onTapTask(layout.task)
                            },
                            onToggleCompletion: {
                                onToggleCompletion(layout.task)
                            },
                            onEdit: onEditEvent != nil ? {
                                onEditEvent?(layout.task)
                            } : nil,
                            onDelete: onDeleteEvent != nil ? {
                                onDeleteEvent?(layout.task)
                            } : nil
                        )
                        .frame(width: columnWidth, height: nil, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: xOffset, y: yPos)
                    }
                }
            }
        }
    }

    // MARK: - Current Time Indicator

    private func currentTimeIndicator(minutes: Int) -> some View {
        HStack(spacing: 0) {
            // Current time label
            Text(formatCurrentTime())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.red)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 4)

            // Small circle on the left
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: Color.red.opacity(0.5), radius: 3, x: 0, y: 0)

            // Red line with gradient fade
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.red, Color.red.opacity(0.3)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .padding(.trailing, 20)
        }
        .offset(y: CGFloat(minutes) / 60.0 * hourHeight - 1) // -1 to center on the line
    }

    private func formatCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    // MARK: - Helper Methods

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }

    private func cancelEventCreation() {
        isCreatingEvent = false
        newEventTitle = ""
        newEventTime = nil
        selectedTimeSlot = nil
        isTextFieldFocused = false
    }

    // MARK: - Inline Event Creator

    private func inlineEventCreator(at time: Date) -> some View {
        VStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelEventCreation()
                }

            Spacer()

            // Modal Sheet
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    // Drag indicator
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                        .frame(width: 40, height: 5)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("New Event")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text(formatTime(time))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }

                // Input field
                HStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)

                    TextField("Event name", text: $newEventTitle)
                        .font(.system(size: 16, weight: .medium))
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .padding(.horizontal, 20)

                Spacer()
                    .frame(height: 12)

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { cancelEventCreation() }) {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                            )
                    }

                    Button(action: {
                        if !newEventTitle.isEmpty {
                            onAddEvent?(
                                newEventTitle,
                                nil,
                                date,
                                time,
                                nil,
                                .none,
                                false,
                                nil,
                                selectedTagId
                            )
                            cancelEventCreation()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))

                            Text("Create")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(newEventTitle.isEmpty ? Color.gray : (colorScheme == .dark ? Color.white : Color.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            newEventTitle.isEmpty ? Color.gray : accentColor,
                                            newEventTitle.isEmpty ? Color.gray.opacity(0.7) : accentColor.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    }
                    .disabled(newEventTitle.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white)
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func plusIndicator(at time: Date) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    colorScheme == .dark ? accentColor : accentColor.opacity(0.8),
                                    colorScheme == .dark ? accentColor.opacity(0.8) : accentColor.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 2)
                )
        }
        .offset(y: yPosition(for: time) - 16)
    }
}

#Preview {
    TimelineView(
        tasks: [],
        date: Date(),
        onTapTask: { _ in },
        onToggleCompletion: { _ in }
    )
}
