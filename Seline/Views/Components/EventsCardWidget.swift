import SwiftUI

struct EventsCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared

    @State private var selectedTask: TaskItem?
    @State private var showingEditTask = false

    @Binding var showingAddEventPopup: Bool
    var onTaskSelected: ((TaskItem) -> Void)?
    var onOpenEvents: (() -> Void)?

    init(
        showingAddEventPopup: Binding<Bool>,
        onTaskSelected: ((TaskItem) -> Void)? = nil,
        onOpenEvents: (() -> Void)? = nil
    ) {
        self._showingAddEventPopup = showingAddEventPopup
        self.onTaskSelected = onTaskSelected
        self.onOpenEvents = onOpenEvents
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var upcomingTasks: [TaskItem] {
        taskManager.getAllFlattenedTasks()
            .filter { task in
                guard !task.isDeleted else { return false }
                guard let targetDate = task.targetDate else { return false }
                if task.isCompletedOn(date: targetDate) { return false }
                return dueDate(for: task) >= todayStart
            }
            .sorted { dueDate(for: $0) < dueDate(for: $1) }
    }

    private var overdueTasks: [TaskItem] {
        taskManager.getAllFlattenedTasks()
            .filter { task in
                guard !task.isDeleted else { return false }
                guard let targetDate = task.targetDate else { return false }
                if task.isCompletedOn(date: targetDate) { return false }
                return dueDate(for: task) < todayStart
            }
            .sorted { dueDate(for: $0) > dueDate(for: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if upcomingTasks.isEmpty {
                Text("No upcoming events")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.52))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        nextUpRow(task)

                        if index < min(upcomingTasks.count, 3) - 1 {
                            Divider()
                                .overlay(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1))
                        }
                    }
                }
            }

            if !overdueTasks.isEmpty {
                Divider()
                    .overlay(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1))

                HStack(spacing: 8) {
                    Text("Overdue")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("\(overdueTasks.count)")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(overdueTasks.prefix(2), id: \.id) { task in
                        Button(action: {
                            selectedTask = task
                            HapticManager.shared.cardTap()
                        }) {
                            HStack(spacing: 8) {
                                Text(formatDateShort(dueDate(for: task)))
                                    .font(FontManager.geist(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                    .frame(width: 70, alignment: .leading)

                                Text(task.title)
                                    .font(FontManager.geist(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.82))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .allowsParentScrolling()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 10,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
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
            if newValue == nil {
                showingEditTask = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next Up")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text("Upcoming tasks and reminders")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
            }

            Spacer()

            Button(action: {
                HapticManager.shared.selection()
                onOpenEvents?()
            }) {
                Text("View all")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .allowsParentScrolling()

            Button(action: {
                HapticManager.shared.selection()
                showingAddEventPopup = true
            }) {
                Image(systemName: "plus")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .allowsParentScrolling()
        }
    }

    private func nextUpRow(_ task: TaskItem) -> some View {
        Button(action: {
            onTaskSelected?(task)
            selectedTask = task
            HapticManager.shared.cardTap()
        }) {
            HStack(spacing: 8) {
                Text(timeLabel(for: task))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.65))
                    .frame(width: 72, alignment: .leading)

                Text(task.title)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private func dueDate(for task: TaskItem) -> Date {
        guard let targetDate = task.targetDate else { return task.createdAt }

        guard let scheduledTime = task.scheduledTime else {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: targetDate) ?? targetDate
        }

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: scheduledTime)
        return Calendar.current.date(
            bySettingHour: components.hour ?? 12,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDate
        ) ?? targetDate
    }

    private func timeLabel(for task: TaskItem) -> String {
        let due = dueDate(for: task)
        let calendar = Calendar.current

        if calendar.isDateInToday(due) {
            if task.scheduledTime == nil {
                return "Today"
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: due)
        }

        if calendar.isDateInTomorrow(due) {
            return "Tomorrow"
        }

        return formatDateShort(due)
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
