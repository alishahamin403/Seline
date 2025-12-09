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
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(colorScheme == .dark ? Color(white: 0.3) : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
            )
    }

    private func eventRow(_ task: TaskItem) -> some View {
        Button(action: {
            HapticManager.shared.cardTap()
            selectedTask = task
        }) {
            let isTaskCompleted = task.isCompletedOn(date: selectedDate)
            let badgeFilterType = filterType(from: task)
            let colorIndex = getTagColorIndex(for: task)
            let circleColor = filterAccentColor(badgeFilterType, colorIndex)
            let badge = filterDisplayName(for: task)
            let badgeColor = filterAccentColor(badgeFilterType, colorIndex)

            // Title row with checkmark and time
            HStack(spacing: 4) {
                // Completion status icon - tappable
                Button(action: {
                    HapticManager.shared.selection()
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                }) {
                    Image(systemName: isTaskCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(circleColor)
                }
                .buttonStyle(PlainButtonStyle())

                // Event title
                Text(task.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Event time
                if let scheduledTime = task.scheduledTime {
                    Text(formatTime(scheduledTime))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with "Todos" and tag color indicators
            HStack(spacing: 8) {
                Text("Todos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                // Tag color indicators
                if !uniqueEventTypes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(uniqueEventTypes, id: \.filterType) { type, colorIndex in
                            tagColorIndicatorRow(type, colorIndex: colorIndex)
                        }
                    }
                }

                Spacer()

                Button(action: {
                    HapticManager.shared.selection()
                    showingAddEventPopup = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 0)

            // Events list for selected date
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if sortedEvents.isEmpty {
                        Text("No events")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(sortedEvents, id: \.id) { task in
                            eventRow(task)
                        }
                    }
                }
                .padding(.horizontal, 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .cornerRadius(12)
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
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
}

#Preview {
    VStack(spacing: 16) {
        EventsCardWidget(showingAddEventPopup: .constant(false))
    }
    .background(Color.shadcnBackground(.light))
}
