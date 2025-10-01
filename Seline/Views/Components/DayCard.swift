import SwiftUI

struct DayCard: View {
    let weekday: WeekDay
    let tasks: [TaskItem]
    let onAddTask: (String, Date?, ReminderTime?) -> Void
    let onToggleTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteRecurringSeries: (TaskItem) -> Void
    let onMakeRecurring: (TaskItem) -> Void
    let onEditTask: (TaskItem) -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var newTaskText: String = ""
    @State private var isAddingTask: Bool = false
    @State private var isExpanded: Bool = false
    @State private var selectedTime: Date = Date()
    @State private var selectedReminder: ReminderTime = .none
    @State private var showReminderPicker: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    private var shouldShowAddTaskInput: Bool {
        weekday == .monday || isAddingTask
    }

    private var canAddTasks: Bool {
        weekday.dayStatus != .past
    }

    private var grayColor: Color {
        colorScheme == .dark ?
            Color.white.opacity(0.6) :
            Color.black.opacity(0.5)
    }

    private var dayTitleColor: Color {
        switch weekday.dayStatus {
        case .past:
            return colorScheme == .dark ?
                Color.white.opacity(0.4) :
                Color.black.opacity(0.4)
        case .current:
            // Match exact tab icon fill color
            return colorScheme == .dark ?
                Color(red: 0.518, green: 0.792, blue: 0.914) : // #84cae9 (light blue for dark mode)
                Color(red: 0.20, green: 0.34, blue: 0.40)      // #345766 (dark blue for light mode)
        case .future:
            return Color.shadcnForeground(colorScheme)
        }
    }

    private var dayDateColor: Color {
        switch weekday.dayStatus {
        case .past:
            return colorScheme == .dark ?
                Color.white.opacity(0.3) :
                Color.black.opacity(0.3)
        case .current:
            // Match exact tab icon fill color with slight opacity
            return colorScheme == .dark ?
                Color(red: 0.518, green: 0.792, blue: 0.914).opacity(0.8) : // #84cae9 with opacity
                Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.8)      // #345766 with opacity
        case .future:
            return colorScheme == .dark ? Color.white : Color.black
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header - tappable to expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekday.displayName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(dayTitleColor)

                    // Only show date when expanded
                    if isExpanded {
                        Text(weekday.formattedDate())
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Tasks list - only show when expanded
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        TaskRow(
                            task: task,
                            onToggleCompletion: {
                                onToggleTask(task)
                            },
                            onDelete: {
                                onDeleteTask(task)
                            },
                            onDeleteRecurringSeries: {
                                onDeleteRecurringSeries(task)
                            },
                            onMakeRecurring: {
                                onMakeRecurring(task)
                            },
                            onEdit: {
                                onEditTask(task)
                            }
                        )
                    }

                    // Add task input - always show for Monday (if not past), show for others when isAddingTask is true
                    if shouldShowAddTaskInput && canAddTasks {
                        addTaskRow
                    }

                    // Add task button for other days (if not past)
                    if weekday != .monday && !isAddingTask && canAddTasks {
                        addTaskButton
                    }

                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.clear)
        .padding(.horizontal, 20)
    }

    private var addTaskRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .font(.system(size: 18, weight: .medium))

                TextField("Add a new task...", text: $newTaskText)
                    .font(.shadcnTextSm)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        addTask()
                    }

                Spacer()

                DatePicker("Time", selection: $selectedTime, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .scaleEffect(0.9)
                    .foregroundColor(grayColor)

                Button(action: {
                    showReminderPicker.toggle()
                }) {
                    Image(systemName: selectedReminder == .none ? "bell.slash" : "bell.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(selectedReminder == .none ? grayColor : Color.shadcnPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(Color.clear)
            )
            .onTapGesture {
                isTextFieldFocused = true
            }

            // Reminder picker
            if showReminderPicker {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remind me")
                        .font(.shadcnTextXsMedium)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .padding(.horizontal, 16)

                    ForEach(ReminderTime.allCases, id: \.self) { reminder in
                        Button(action: {
                            selectedReminder = reminder
                            showReminderPicker = false
                        }) {
                            HStack {
                                Image(systemName: reminder.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(selectedReminder == reminder ? Color.shadcnPrimary : Color.shadcnMutedForeground(colorScheme))
                                    .frame(width: 20)

                                Text(reminder.displayName)
                                    .font(.shadcnTextSm)
                                    .foregroundColor(selectedReminder == reminder ? Color.shadcnPrimary : Color.shadcnForeground(colorScheme))

                                Spacer()

                                if selectedReminder == reminder {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color.shadcnPrimary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnRadius.sm)
                                    .fill(selectedReminder == reminder ? Color.shadcnPrimary.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnRadius.md)
                        .fill(
                            colorScheme == .dark ?
                                Color.black.opacity(0.3) : Color.gray.opacity(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                .stroke(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var addTaskButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAddingTask = true
            }
            // Small delay to ensure animation completes before focusing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .font(.system(size: 18, weight: .medium))

                Text("Add a new task...")
                    .font(.shadcnTextSm)
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }


    private func addTask() {
        let trimmedText = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        onAddTask(trimmedText, selectedTime, selectedReminder == .none ? nil : selectedReminder)
        newTaskText = ""
        selectedTime = Date() // Reset to current time
        selectedReminder = .none // Reset reminder
        showReminderPicker = false
        isTextFieldFocused = false

        // Hide the input for non-Monday days
        if weekday != .monday {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAddingTask = false
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            DayCard(
                weekday: .monday,
                tasks: [
                    TaskItem(title: "Gym run", weekday: .monday),
                    TaskItem(title: "Read 10 pages", weekday: .monday),
                    TaskItem(title: "Walk the dog", weekday: .monday)
                ],
                onAddTask: { _, _, _ in },
                onToggleTask: { _ in },
                onDeleteTask: { _ in },
                onDeleteRecurringSeries: { _ in },
                onMakeRecurring: { _ in },
                onEditTask: { _ in }
            )

            DayCard(
                weekday: .tuesday,
                tasks: [],
                onAddTask: { _, _, _ in },
                onToggleTask: { _ in },
                onDeleteTask: { _ in },
                onDeleteRecurringSeries: { _ in },
                onMakeRecurring: { _ in },
                onEditTask: { _ in }
            )
        }
        .padding(.vertical)
    }
    .background(Color.shadcnBackground(.light))
}