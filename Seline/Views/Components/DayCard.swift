import SwiftUI

struct DayCard: View {
    let weekday: WeekDay
    let date: Date?
    let tasks: [TaskItem]
    let onAddTask: (String, Date?, ReminderTime?) -> Void
    let onToggleTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteRecurringSeries: (TaskItem) -> Void
    let onMakeRecurring: (TaskItem) -> Void
    let onViewTask: (TaskItem) -> Void
    let onEditTask: (TaskItem) -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var newTaskText: String = ""
    @State private var isAddingTask: Bool = false
    @State private var isExpanded: Bool
    @State private var selectedTime: Date = Date()
    @State private var selectedReminder: ReminderTime = .none
    @State private var showReminderPicker: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    init(weekday: WeekDay, date: Date?, tasks: [TaskItem], onAddTask: @escaping (String, Date?, ReminderTime?) -> Void, onToggleTask: @escaping (TaskItem) -> Void, onDeleteTask: @escaping (TaskItem) -> Void, onDeleteRecurringSeries: @escaping (TaskItem) -> Void, onMakeRecurring: @escaping (TaskItem) -> Void, onViewTask: @escaping (TaskItem) -> Void, onEditTask: @escaping (TaskItem) -> Void) {
        self.weekday = weekday
        self.date = date
        self.tasks = tasks
        self.onAddTask = onAddTask
        self.onToggleTask = onToggleTask
        self.onDeleteTask = onDeleteTask
        self.onDeleteRecurringSeries = onDeleteRecurringSeries
        self.onMakeRecurring = onMakeRecurring
        self.onViewTask = onViewTask
        self.onEditTask = onEditTask

        // Expand the current day by default
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cardDate = date.map { calendar.startOfDay(for: $0) } ?? weekday.dateForCurrentWeek()
        self._isExpanded = State(initialValue: calendar.isDate(cardDate, inSameDayAs: today))
    }

    private var shouldShowAddTaskInput: Bool {
        weekday == .monday || isAddingTask
    }

    private var dayStatus: WeekDay.DayStatus {
        guard let date = date else {
            return weekday.dayStatus
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cardDate = calendar.startOfDay(for: date)

        if cardDate == today {
            return .current
        } else if cardDate < today {
            return .past
        } else {
            return .future
        }
    }

    private var canAddTasks: Bool {
        dayStatus != .past
    }

    private var grayColor: Color {
        colorScheme == .dark ?
            Color.white.opacity(0.6) :
            Color.black.opacity(0.5)
    }

    private var dayTitleColor: Color {
        switch dayStatus {
        case .past:
            return colorScheme == .dark ?
                Color.white.opacity(0.4) :
                Color.black.opacity(0.4)
        case .current:
            return colorScheme == .dark ?
                Color.white :
                Color.black
        case .future:
            return Color.shadcnForeground(colorScheme)
        }
    }

    private var dayDateColor: Color {
        switch dayStatus {
        case .past:
            return colorScheme == .dark ?
                Color.white.opacity(0.3) :
                Color.black.opacity(0.3)
        case .current:
            return colorScheme == .dark ?
                Color.white.opacity(0.8) :
                Color.black.opacity(0.8)
        case .future:
            return colorScheme == .dark ? Color.white : Color.black
        }
    }

    private var formattedDate: String {
        guard let date = date else {
            return weekday.formattedDate()
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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
                        .font(FontManager.geist(size: 37, weight: .regular))
                        .foregroundColor(dayTitleColor)

                    // Only show date when expanded
                    if isExpanded {
                        Text(formattedDate)
                            .font(FontManager.geist(size: 14, weight: .regular))
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
                            date: date,
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
                            onView: {
                                onViewTask(task)
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
                    .font(FontManager.geist(size: 18, weight: .medium))

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
                        .font(FontManager.geist(size: 16, weight: .medium))
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
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .foregroundColor(selectedReminder == reminder ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray)
                                    .frame(width: 20)

                                Text(reminder.displayName)
                                    .font(.shadcnTextSm)
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                                Spacer()

                                if selectedReminder == reminder {
                                    Image(systemName: "checkmark")
                                        .font(FontManager.geist(size: 14, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnRadius.sm)
                                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.05))
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
                    .font(FontManager.geist(size: 18, weight: .medium))

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
                date: Date(),
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
                onViewTask: { _ in },
                onEditTask: { _ in }
            )

            DayCard(
                weekday: .tuesday,
                date: Date(),
                tasks: [],
                onAddTask: { _, _, _ in },
                onToggleTask: { _ in },
                onDeleteTask: { _ in },
                onDeleteRecurringSeries: { _ in },
                onMakeRecurring: { _ in },
                onViewTask: { _ in },
                onEditTask: { _ in }
            )
        }
        .padding(.vertical)
    }
    .background(Color.shadcnBackground(.light))
}