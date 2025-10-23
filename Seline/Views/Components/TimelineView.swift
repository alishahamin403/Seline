import SwiftUI

struct TimelineView: View {
    let tasks: [TaskItem]
    let date: Date
    let onTapTask: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void
    let onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)?
    let onEditEvent: ((TaskItem) -> Void)?
    let onDeleteEvent: ((TaskItem) -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedTimeSlot: Date? // For showing + sign
    @State private var isCreatingEvent = false
    @State private var newEventTitle = ""
    @State private var newEventTime: Date?
    @State private var showReminderOptions = false
    @State private var selectedReminder: ReminderTime = .none
    @FocusState private var isTextFieldFocused: Bool

    init(
        tasks: [TaskItem],
        date: Date,
        onTapTask: @escaping (TaskItem) -> Void,
        onToggleCompletion: @escaping (TaskItem) -> Void,
        onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)? = nil,
        onEditEvent: ((TaskItem) -> Void)? = nil,
        onDeleteEvent: ((TaskItem) -> Void)? = nil
    ) {
        self.tasks = tasks
        self.date = date
        self.onTapTask = onTapTask
        self.onToggleCompletion = onToggleCompletion
        self.onAddEvent = onAddEvent
        self.onEditEvent = onEditEvent
        self.onDeleteEvent = onDeleteEvent
    }

    // Hour height in points (60 points per hour)
    private let hourHeight: CGFloat = 60

    // Total timeline height (24 hours)
    private var totalHeight: CGFloat {
        hourHeight * 24
    }

    // Tasks with scheduled times, sorted by start time for consistent layout
    private var scheduledTasks: [TaskItem] {
        tasks.filter { $0.scheduledTime != nil }
            .sorted { task1, task2 in
                guard let time1 = task1.scheduledTime, let time2 = task2.scheduledTime else {
                    return false
                }
                if time1 == time2 {
                    // If same start time, sort by ID for consistency
                    return task1.id < task2.id
                }
                return time1 < time2
            }
    }

    // Event layout information
    struct EventLayout {
        let task: TaskItem
        let column: Int
        let totalColumns: Int
    }

    // Calculate layouts for all events, handling overlaps
    private var eventLayouts: [EventLayout] {
        guard !scheduledTasks.isEmpty else { return [] }

        var layouts: [EventLayout] = []

        // Group tasks into overlapping sets
        var groups: [[TaskItem]] = []
        var assigned: Set<String> = []

        for task in scheduledTasks {
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
                for otherTask in scheduledTasks {
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

            // Assign columns using interval partitioning
            var columns: [[TaskItem]] = []

            for task in sortedGroup {
                var placed = false

                // Try to place in existing column
                for colIndex in 0..<columns.count {
                    let canFit = columns[colIndex].allSatisfy { !tasksOverlap(task, $0) }
                    if canFit {
                        columns[colIndex].append(task)
                        placed = true
                        break
                    }
                }

                // Create new column if needed
                if !placed {
                    columns.append([task])
                }
            }

            // Create layouts for this group
            let totalColumns = columns.count

            for (colIndex, column) in columns.enumerated() {
                for task in column {
                    layouts.append(EventLayout(
                        task: task,
                        column: colIndex,
                        totalColumns: totalColumns
                    ))
                }
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
            Color(red: 0.40, green: 0.65, blue: 0.80) : // #66A5C6
            Color(red: 0.20, green: 0.34, blue: 0.40)   // #345766
    }

    var body: some View {
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

                        // Show + indicator or inline event creator
                        if isCreatingEvent, let eventTime = newEventTime {
                            inlineEventCreator(at: eventTime)
                                .padding(.leading, 60)
                        } else if let selectedSlot = selectedTimeSlot {
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
                    scrollToCurrentTime(proxy: proxy)
                }
            }
        }
    }

    private func handleTimelineTap(at timeSlot: Date) {
        // If creating event, cancel and optionally select new slot
        if isCreatingEvent {
            cancelEventCreation()
            return
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

                    // Hour line
                    Rectangle()
                        .fill(
                            colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15)
                        )
                        .frame(height: 1)
                }
                .offset(y: CGFloat(hour) * hourHeight)
            }

            // Half-hour markers (positioned exactly at 30 minutes)
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: 50)
                        .padding(.trailing, 10)

                    Rectangle()
                        .fill(
                            colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
                        )
                        .frame(height: 1)
                }
                .offset(y: CGFloat(hour) * hourHeight + hourHeight / 2)
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
        let minutes = half * 30
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minutes

        return Group {
            if let timeSlot = Calendar.current.date(from: components) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: hourHeight / 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTimelineTap(at: timeSlot)
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: hourHeight / 2)
            }
        }
    }

    // MARK: - Plus Indicator

    private func plusIndicator(at timeSlot: Date) -> some View {
        Image(systemName: "plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .frame(height: hourHeight / 2)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: yPosition(for: timeSlot))
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTimeSlot)
    }

    // MARK: - Inline Event Creator

    private func inlineEventCreator(at timeSlot: Date) -> some View {
        HStack(spacing: 8) {
            // Text field for event title
            ZStack(alignment: .leading) {
                if newEventTitle.isEmpty {
                    Text("Event title")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                TextField("", text: $newEventTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .accentColor(colorScheme == .dark ?
                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                        Color(red: 0.20, green: 0.34, blue: 0.40))
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        createEvent()
                    }
            }

            // Reminder button
            Button(action: {
                showReminderOptions = true
            }) {
                Image(systemName: selectedReminder != .none ? "bell.fill" : "bell")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ?
                                Color.white.opacity(0.9) :
                                Color.black.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: hourHeight / 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .dark ?
                    Color(red: 0.40, green: 0.65, blue: 0.80) :
                    Color(red: 0.20, green: 0.34, blue: 0.40), lineWidth: 1.5)
        )
        .offset(y: yPosition(for: timeSlot))
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCreatingEvent)
        .confirmationDialog("Set Reminder", isPresented: $showReminderOptions, titleVisibility: .visible) {
            Button("None") {
                selectedReminder = .none
                createEvent()
            }

            Button("15 minutes before") {
                selectedReminder = .fifteenMinutes
                createEvent()
            }

            Button("1 hour before") {
                selectedReminder = .oneHour
                createEvent()
            }

            Button("3 hours before") {
                selectedReminder = .threeHours
                createEvent()
            }

            Button("1 day before") {
                selectedReminder = .oneDay
                createEvent()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose when to be reminded about this event")
        }
    }

    private func createEvent() {
        guard !newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let eventTime = newEventTime else {
            cancelEventCreation()
            return
        }

        let endTime = Calendar.current.date(byAdding: .minute, value: 30, to: eventTime)

        onAddEvent?(
            newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            nil,
            date,
            eventTime,
            endTime,
            selectedReminder != .none ? selectedReminder : nil,
            false,
            nil,
            nil // Personal (default) tag
        )

        // Reset state
        cancelEventCreation()
        HapticManager.shared.cardTap()
    }

    private func cancelEventCreation() {
        isCreatingEvent = false
        newEventTitle = ""
        newEventTime = nil
        selectedReminder = .none
        isTextFieldFocused = false
    }

    // MARK: - Events Layer

    private var eventsLayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(eventLayouts, id: \.task.id) { layout in
                    if let scheduledTime = layout.task.scheduledTime {
                        let availableWidth = geometry.size.width - 16 // Account for trailing padding
                        let gapWidth: CGFloat = 4 // Gap between columns
                        let totalGaps = CGFloat(max(0, layout.totalColumns - 1)) * gapWidth
                        let columnWidth = (availableWidth - totalGaps) / CGFloat(layout.totalColumns)
                        let xOffset = (columnWidth + gapWidth) * CGFloat(layout.column)

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
                        .fixedSize(horizontal: true, vertical: false) // Prevent horizontal expansion
                        .offset(x: xOffset, y: yPosition(for: scheduledTime))
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

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        if let currentMinutes = currentTimeMinutes {
            // Scroll to current time minus some offset to show context
            let _ = max(0, currentMinutes - 60) // 1 hour before
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    // Since we can't scroll to exact position, we'll scroll to the timeline start
                    // and let users manually scroll. A more sophisticated approach would use
                    // ScrollViewReader with identifiable hour markers
                    proxy.scrollTo("timeline", anchor: .top)
                }
            }
        } else if let firstTask = scheduledTasks.first,
                  firstTask.scheduledTime != nil {
            // If not today, scroll to first event
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    proxy.scrollTo("timeline", anchor: .top)
                }
            }
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let now = Date()

    let sampleTasks: [TaskItem] = [
        TaskItem(
            title: "Morning Standup",
            weekday: .monday,
            scheduledTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
            endTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)
        ),
        TaskItem(
            title: "Design Review Meeting",
            weekday: .monday,
            scheduledTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now),
            endTime: calendar.date(bySettingHour: 11, minute: 30, second: 0, of: now)
        ),
        TaskItem(
            title: "Lunch Break",
            weekday: .monday,
            scheduledTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now),
            endTime: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now)
        ),
        TaskItem(
            title: "Client Call",
            weekday: .monday,
            scheduledTime: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now),
            endTime: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now)
        ),
        TaskItem(
            title: "Code Review",
            weekday: .monday,
            scheduledTime: calendar.date(bySettingHour: 15, minute: 30, second: 0, of: now),
            endTime: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: now)
        )
    ]

    TimelineView(
        tasks: sampleTasks,
        date: now,
        onTapTask: { _ in },
        onToggleCompletion: { _ in }
    )
    .background(Color.shadcnBackground(.light))
}
