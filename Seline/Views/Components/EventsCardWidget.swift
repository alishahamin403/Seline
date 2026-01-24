import SwiftUI

struct EventsCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @State private var selectedDate: Date
    @State private var selectedTask: TaskItem?
    @State private var showingEditTask = false
    @Binding var showingAddEventPopup: Bool

    init(showingAddEventPopup: Binding<Bool>) {
        self._showingAddEventPopup = showingAddEventPopup
        let calendar = Calendar.current
        _selectedDate = State(initialValue: calendar.startOfDay(for: Date()))
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var selectedDateEvents: [TaskItem] {
        taskManager.getTasksForDate(selectedDate)
    }

    private var sortedEvents: [TaskItem] {
        let calendar = Calendar.current

        // Sort: all-day events first, then timed events by TIME OF DAY only (ignore date component)
        return selectedDateEvents.sorted { task1, task2 in
            // All-day events (nil scheduledTime) come first
            if task1.scheduledTime == nil && task2.scheduledTime != nil {
                return true
            }
            if task1.scheduledTime != nil && task2.scheduledTime == nil {
                return false
            }

            // Both are all-day events - sort by creation date
            if task1.scheduledTime == nil && task2.scheduledTime == nil {
                return task1.createdAt < task2.createdAt
            }

            // Both have scheduled times - sort by TIME OF DAY ONLY (hour:minute)
            if let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                let hour1 = calendar.component(.hour, from: time1)
                let minute1 = calendar.component(.minute, from: time1)
                let hour2 = calendar.component(.hour, from: time2)
                let minute2 = calendar.component(.minute, from: time2)

                // Compare hours first, then minutes
                if hour1 != hour2 {
                    return hour1 < hour2
                }
                return minute1 < minute2
            }

            return false
        }
    }

    private var uniqueEventTypes: [(filterType: TimelineEventColorManager.FilterType, colorIndex: Int?)] {
        var seen: Set<String> = []
        var result: [(TimelineEventColorManager.FilterType, Int?)] = []

        for task in selectedDateEvents {
            let type = filterType(from: task)
            let colorIndex = getTagColorIndex(for: task)
            let key = "\(type)-\(colorIndex ?? -1)"

            if !seen.contains(key) {
                seen.insert(key)
                result.append((type, colorIndex))
            }
        }

        return result
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func filterDisplayName(for task: TaskItem) -> String {
        if task.id.hasPrefix("cal_") {
            return "Synced"
        } else if let tagId = task.tagId, !tagId.isEmpty {
            if let tag = tagManager.getTag(by: tagId) {
                return tag.name
            }
            return "Tag"
        } else {
            return "Personal"
        }
    }

    private func filterDisplayNameForType(_ filterType: TimelineEventColorManager.FilterType) -> String {
        switch filterType {
        case .personal:
            return "Personal"
        case .personalSync:
            return "Synced"
        case .tag(let tagId):
            if let tag = tagManager.getTag(by: tagId) {
                return tag.name
            }
            return "Tag"
        }
    }

    private func filterType(from task: TaskItem) -> TimelineEventColorManager.FilterType {
        TimelineEventColorManager.filterType(from: task)
    }

    private func getTagColorIndex(for task: TaskItem) -> Int? {
        guard case .tag(let tagId) = filterType(from: task) else { return nil }
        return tagManager.getTag(by: tagId)?.colorIndex
    }

    private var filterAccentColor: (TimelineEventColorManager.FilterType, Int?) -> Color {
        { filterType, colorIndex in
            TimelineEventColorManager.timelineEventAccentColor(
                filterType: filterType,
                colorScheme: colorScheme,
                tagColorIndex: colorIndex
            )
        }
    }

    private func tagColorIndicatorRow(_ type: TimelineEventColorManager.FilterType, colorIndex: Int?) -> some View {
        let color = filterAccentColor(type, colorIndex)
        return Text(filterDisplayNameForType(type))
            .font(FontManager.geist(size: 9, weight: .medium))
            .foregroundColor(.white) // Always white text in both dark and light mode
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
            )
    }

    private func eventRow(_ task: TaskItem) -> some View {
        let isTaskCompleted = task.isCompletedOn(date: selectedDate)
        let badgeFilterType = filterType(from: task)
        let colorIndex = getTagColorIndex(for: task)
        let circleColor = filterAccentColor(badgeFilterType, colorIndex)

        // Title row with checkmark and time
        return HStack(spacing: 10) {
            // Completion status icon - tappable
            Image(systemName: isTaskCompleted ? "checkmark.circle.fill" : "circle")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(isTaskCompleted ? circleColor : circleColor.opacity(0.4))
                .onTapGesture {
                    HapticManager.shared.selection()
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                }

            // Event title
            Text(task.title)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(isTaskCompleted ? (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)) : (colorScheme == .dark ? Color.white : Color.black))
                .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Event time
            if let scheduledTime = task.scheduledTime {
                Text(formatTime(scheduledTime))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(isTaskCompleted ? (colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)) : (colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65)))
                    .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.cardTap()
            selectedTask = task
        }
        .contextMenu {
            Button {
                HapticManager.shared.selection()
                taskManager.toggleTaskCompletion(task, forDate: selectedDate)
            } label: {
                Label(isTaskCompleted ? "Mark Incomplete" : "Mark Complete", 
                      systemImage: isTaskCompleted ? "arrow.uturn.backward" : "checkmark.circle")
            }
            
            Button {
                HapticManager.shared.selection()
                selectedTask = task
                showingEditTask = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                HapticManager.shared.warning()
                taskManager.deleteTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @AppStorage("dismissedOverdueTaskIds") private var dismissedTaskIdsString: String = ""
    
    private var dismissedTaskIds: [String] {
        dismissedTaskIdsString.split(separator: ",").map(String.init)
    }
    
    private func dismissTask(_ id: String) {
        var ids = dismissedTaskIds
        if !ids.contains(id) {
            ids.append(id)
            dismissedTaskIdsString = ids.joined(separator: ",")
        }
    }

    private var overdueEvents: [TaskItem] {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let flattened = taskManager.getAllFlattenedTasks()
        let dismissed = Set(dismissedTaskIds)
        
        return flattened.filter { task in
            // Must have a scheduled time (not all day)
            guard let scheduledTime = task.scheduledTime, let targetDate = task.targetDate else { return false }
            
            // Filter out completed, deleted, dismissed, and synced tasks
            if task.isCompleted || task.isDeleted || dismissed.contains(task.id) || task.id.hasPrefix("cal_") {
                return false
            }
            
            // Combine target date and scheduled time for accurate comparison
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            guard let taskDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                 minute: timeComponents.minute ?? 0,
                                                 second: 0,
                                                 of: targetDate) else { return false }
            
            // Must be strictly from a previous day (before today 00:00)
            return taskDateTime < today
        }.sorted { 
            // Sort by most recently overdue (closest to today)
            guard let d1 = $0.targetDate, let d2 = $1.targetDate else { return false }
            return d1 > d2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with "Todos"
            HStack(spacing: 12) {
                Text("Todos")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Image(systemName: "plus")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
                    .onTapGesture {
                        HapticManager.shared.selection()
                        showingAddEventPopup = true
                    }
            }
            
            // Overdue Tasks Alert
            if !overdueEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Overdue")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("\(overdueEvents.count)")
                            .font(FontManager.geist(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(colorScheme == .dark ? Color.white : Color.black))
                            
                        Spacer()
                    }
                    .padding(.bottom, 2)
                    
                    VStack(spacing: 2) {
                        ForEach(overdueEvents.prefix(3)) { task in
                            HStack(spacing: 10) {
                                // Checkbox - Matched size to standard row
                                Button(action: {
                                    HapticManager.shared.selection()
                                    // Complete the overdue task as of today
                                    taskManager.toggleTaskCompletion(task, forDate: Date())
                                }) {
                                    Image(systemName: "circle")
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                }
                                .buttonStyle(PlainButtonStyle())

                                // Task Info - Matched font to standard row
                                Text(task.title)
                                    .font(FontManager.geist(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if let targetDate = task.targetDate {
                                    Text(formatDateShort(targetDate))
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.65))
                                }
                                
                                // Dismiss button
                                Button(action: {
                                    HapticManager.shared.selection()
                                    dismissTask(task.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(FontManager.geist(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.cardTap()
                                selectedTask = task
                                showingEditTask = true // Directly open edit mode
                            }
                            .contextMenu {
                                Button {
                                    HapticManager.shared.selection()
                                    taskManager.toggleTaskCompletion(task, forDate: Date())
                                } label: {
                                    Label("Mark Complete", systemImage: "checkmark.circle")
                                }
                                
                                Button {
                                    HapticManager.shared.selection()
                                    selectedTask = task
                                    showingEditTask = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                
                                Divider()
                                
                                Button {
                                    HapticManager.shared.selection()
                                    dismissTask(task.id)
                                } label: {
                                    Label("Dismiss", systemImage: "xmark.circle")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    HapticManager.shared.warning()
                                    taskManager.deleteTask(task)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            
            // Tag color indicators - moved to separate line
            if !uniqueEventTypes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(uniqueEventTypes, id: \.filterType) { type, colorIndex in
                        tagColorIndicatorRow(type, colorIndex: colorIndex)
                    }
                    Spacer()
                }
            }

            // Events list for selected date
            // IMPORTANT: Avoid nested vertical ScrollView inside the home page ScrollView.
            // Nested vertical scrolling is a major source of "tap wins over scroll" behavior.
            VStack(alignment: .leading, spacing: 6) {
                if sortedEvents.isEmpty {
                    Text("No events")

                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                        .padding(.vertical, 8)
                } else {
                    ForEach(sortedEvents, id: \.id) { task in
                        eventRow(task)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .sheet(item: $selectedTask) { task in
            if showingEditTask {
                NavigationView {
                    EditTaskView(
                        task: task,
                        onSave: { updatedTask in
                            taskManager.editTask(updatedTask)
                            selectedTask = nil
                            showingEditTask = false
                        },
                        onCancel: {
                            selectedTask = nil
                            showingEditTask = false
                        },
                        onDelete: { taskToDelete in
                            taskManager.deleteTask(taskToDelete)
                            selectedTask = nil
                            showingEditTask = false
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            selectedTask = nil
                            showingEditTask = false
                        }
                    )
                }
            } else {
                NavigationView {
                    ViewEventView(
                        task: task,
                        onEdit: {
                            showingEditTask = true
                        },
                        onDelete: { taskToDelete in
                            taskManager.deleteTask(taskToDelete)
                            selectedTask = nil
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            taskManager.deleteRecurringTask(taskToDelete)
                            selectedTask = nil
                        }
                    )
                }
            }
        }
    .presentationBg()
        .onChange(of: selectedTask) { newValue in
            // Reset showingEditTask when a new task is selected or when dismissed
            if newValue != nil {
                showingEditTask = false
            } else {
                showingEditTask = false
            }
        }
    }
    
    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    VStack(spacing: 16) {
        EventsCardWidget(showingAddEventPopup: .constant(false))
    }
    .background(Color.shadcnBackground(.light))
}
