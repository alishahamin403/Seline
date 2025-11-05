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

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private var dayAfterTomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 2, to: today) ?? today
    }

    private var tomorrowDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: tomorrow)
    }

    private var dayAfterTomorrowDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: dayAfterTomorrow)
    }

    private var todayDateNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: today)
    }

    private var tomorrowDateNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: tomorrow)
    }

    private var dayAfterDateNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dayAfterTomorrow)
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

    private func isDateSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: date)
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

    private var filterAccentColor: (TimelineEventColorManager.FilterType) -> Color {
        { filterType in
            TimelineEventColorManager.timelineEventAccentColor(
                filterType: filterType,
                colorScheme: colorScheme
            )
        }
    }

    private func eventRow(_ task: TaskItem) -> some View {
        Button(action: {
            HapticManager.shared.cardTap()
            selectedTask = task
        }) {
            HStack(spacing: 4) {
                // Completion status icon - tappable
                Button(action: {
                    HapticManager.shared.selection()
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                }) {
                    let isTaskCompleted = task.isCompletedOn(date: selectedDate)
                    let badgeFilterType = filterType(from: task)
                    let circleColor = filterAccentColor(badgeFilterType)

                    Image(systemName: isTaskCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(circleColor)
                }
                .buttonStyle(PlainButtonStyle())

                // Event title
                let isTaskCompleted = task.isCompletedOn(date: selectedDate)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.shadcnTextXs)
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .strikethrough(isTaskCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Filter badge
                    let badge = filterDisplayName(for: task)
                    let badgeFilterType = filterType(from: task)
                    let badgeColor = filterAccentColor(badgeFilterType)

                    HStack(spacing: 2) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 6, weight: .medium))
                        Text(badge)
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(badgeColor.opacity(0.15))
                    )
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

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
            // Header with 3-day selector and Add Event button
            HStack(spacing: 8) {
                // Column 1: Today
                VStack(spacing: 4) {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button(action: {
                        HapticManager.shared.selection()
                        selectedDate = today
                    }) {
                        Text(todayDateNumber)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isDateSelected(today) ? Color.white : (colorScheme == .dark ? Color.white : Color.black))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(
                                        isDateSelected(today) ?
                                            Color(red: 0.2, green: 0.2, blue: 0.2) :
                                            Color.clear
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)

                // Column 2: Tomorrow
                VStack(spacing: 4) {
                    Text("Tomorrow")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button(action: {
                        HapticManager.shared.selection()
                        selectedDate = tomorrow
                    }) {
                        Text(tomorrowDateNumber)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isDateSelected(tomorrow) ? Color.white : (colorScheme == .dark ? Color.white : Color.black))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(
                                        isDateSelected(tomorrow) ?
                                            Color(red: 0.2, green: 0.2, blue: 0.2) :
                                            Color.clear
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)

                // Column 3: Day after tomorrow's name
                VStack(spacing: 4) {
                    Text(dayAfterTomorrowDayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button(action: {
                        HapticManager.shared.selection()
                        selectedDate = dayAfterTomorrow
                    }) {
                        Text(dayAfterDateNumber)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isDateSelected(dayAfterTomorrow) ? Color.white : (colorScheme == .dark ? Color.white : Color.black))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(
                                        isDateSelected(dayAfterTomorrow) ?
                                            Color(red: 0.2, green: 0.2, blue: 0.2) :
                                            Color.clear
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)

                // Add Event button column
                VStack(spacing: 4) {
                    // Empty text to match vertical alignment
                    Text(" ")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0)

                    Button(action: {
                        HapticManager.shared.selection()
                        showingAddEventPopup = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 24, height: 24)

                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            // Events list for selected date
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if sortedEvents.isEmpty {
                        Text("No events")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(sortedEvents) { task in
                            eventRow(task)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            .padding(.top, 2)
        }
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
