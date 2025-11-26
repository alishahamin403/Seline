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

    private var amEvents: [TaskItem] {
        selectedDateEvents.filter { task in
            if let scheduledTime = task.scheduledTime {
                let hour = Calendar.current.component(.hour, from: scheduledTime)
                return hour < 12
            }
            return false
        }
    }

    private var pmEvents: [TaskItem] {
        selectedDateEvents.filter { task in
            if let scheduledTime = task.scheduledTime {
                let hour = Calendar.current.component(.hour, from: scheduledTime)
                return hour >= 12
            }
            return false
        }
    }

    private var allDayEvents: [TaskItem] {
        selectedDateEvents.filter { $0.scheduledTime == nil }
    }

    private var sortedEvents: [TaskItem] {
        // Combine all events in order: All Day first, then AM, then PM
        allDayEvents + amEvents + pmEvents
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
                    .font(.shadcnTextXs)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Event time
                if let scheduledTime = task.scheduledTime {
                    Text(formatTime(scheduledTime))
                        .font(.shadcnTextXs)
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with "Todos" and Add Event button
            HStack(spacing: 8) {
                Text("Todos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

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
            .padding(.horizontal, 4)

            // Events list for selected date
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if sortedEvents.isEmpty {
                        Text("No events")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(sortedEvents.enumerated()), id: \.element.id) { index, task in
                            eventRow(task)

                            // Add divider between different event categories
                            if index < sortedEvents.count - 1 {
                                let currentFilterType = filterType(from: task)
                                let nextFilterType = filterType(from: sortedEvents[index + 1])
                                if currentFilterType != nextFilterType {
                                    Divider()
                                        .frame(height: 0.5)
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                                        .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(12)
        .padding(.horizontal, 12)
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
