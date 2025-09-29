import SwiftUI

struct CalendarPopupView: View {
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var selectedDate = Date()
    @State private var tasksForDate: [TaskItem] = []
    @State private var showingAddTaskSheet = false
    @State private var newTaskTitle = ""
    @State private var selectedTime = Date()
    @State private var isRecurring = false
    @State private var selectedFrequency = RecurrenceFrequency.weekly
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Calendar picker
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .accentColor(Color.shadcnPrimary)
                .tint(Color.shadcnPrimary)
                .scaleEffect(0.85) // Make calendar numbers smaller
                .padding(.horizontal, 20)
                .padding(.top, -30) // Move calendar higher
                .onChange(of: selectedDate) { newDate in
                    updateTasksForDate(for: newDate)
                }


                // Completed tasks section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Tasks")
                            .font(.shadcnTextLgSemibold)
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()

                        if canAddTaskToSelectedDate {
                            Button(action: {
                                showingAddTaskSheet = true
                            }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .font(.system(size: 18, weight: .medium))
                            }
                        }

                        Text(formattedSelectedDate)
                            .font(.shadcnTextSm)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .padding(.horizontal, 20)

                    if tasksForDate.isEmpty {
                        // Empty state
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 32))
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            Text("No tasks")
                                .font(.shadcnTextSm)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            Text("Tasks for this date will appear here")
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Tasks list
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tasksForDate) { task in
                                    TaskRowCalendar(task: task)
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
            .navigationTitle("Task Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color.shadcnPrimary)
                }
            }
        }
        .onAppear {
            updateTasksForDate(for: selectedDate)
        }
        .sheet(isPresented: $showingAddTaskSheet) {
            NavigationView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(Color.shadcnPrimary)
                                .font(.system(size: 20, weight: .medium))

                            Text("Add New Task")
                                .font(.shadcnTextLgSemibold)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()
                        }

                        Text("Adding to \(formattedSelectedDate)")
                            .font(.shadcnTextSm)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Form content
                    VStack(spacing: 20) {
                        // Task title input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Task")
                                .font(.shadcnTextSmMedium)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            TextField("Enter task title...", text: $newTaskTitle)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                        .fill(
                                            colorScheme == .dark ?
                                                Color.black.opacity(0.3) : Color.gray.opacity(0.1)
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
                                .focused($isTextFieldFocused)
                        }

                        // Time selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time")
                                .font(.shadcnTextSmMedium)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            HStack {
                                DatePicker("Select time", selection: $selectedTime, displayedComponents: [.hourAndMinute])
                                    .labelsHidden()
                                    .foregroundColor(Color.shadcnForeground(colorScheme))

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color.black.opacity(0.3) : Color.gray.opacity(0.1)
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
                        }

                        // Recurring options
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recurring")
                                    .font(.shadcnTextSmMedium)
                                    .foregroundColor(Color.shadcnForeground(colorScheme))

                                Spacer()

                                Toggle("", isOn: $isRecurring)
                                    .tint(Color.shadcnPrimary)
                            }

                            if isRecurring {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Frequency")
                                        .font(.shadcnTextXs)
                                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                        ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                            FrequencyOptionButton(
                                                frequency: frequency,
                                                isSelected: selectedFrequency == frequency,
                                                onTap: {
                                                    selectedFrequency = frequency
                                                }
                                            )
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // Add button
                    Button(action: addTask) {
                        Text("Add Task")
                            .font(.shadcnTextBaseMedium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                    .fill(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.5) : Color.shadcnPrimary)
                            )
                    }
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground : Color.white
                )
                .navigationTitle("New Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingAddTaskSheet = false
                        }
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDate)
    }

    private func updateTasksForDate(for date: Date) {
        tasksForDate = taskManager.getAllTasks(for: date)
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

    private var canAddTaskToSelectedDate: Bool {
        Calendar.current.compare(selectedDate, to: Date(), toGranularity: .day) != .orderedAscending
    }

    private func addTask() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let weekday = weekdayFromDate(selectedDate) else { return }

        taskManager.addTask(title: trimmedTitle, to: weekday, scheduledTime: selectedTime)

        // If recurring, make the task recurring after adding it
        if isRecurring {
            // Find the task we just added
            if let addedTask = taskManager.getTasks(for: weekday).last {
                taskManager.makeTaskRecurring(addedTask, frequency: selectedFrequency)
            }
        }

        // Reset form
        newTaskTitle = ""
        selectedTime = Date()
        isRecurring = false
        selectedFrequency = .weekly
        isTextFieldFocused = false
        showingAddTaskSheet = false

        // Refresh tasks for the selected date
        updateTasksForDate(for: selectedDate)
    }
}

struct TaskRowCalendar: View {
    let task: TaskItem

    @Environment(\.colorScheme) var colorScheme


    private var timeString: String {
        if task.isCompleted, let completedDate = task.completedDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Completed at \(formatter.string(from: completedDate))"
        } else {
            return "Scheduled"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (completed or incomplete)
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? Color.shadcnPrimary : Color.shadcnMutedForeground(colorScheme))
                .font(.system(size: 18, weight: .medium))

            VStack(alignment: .leading, spacing: 2) {
                // Task title
                Text(task.title)
                    .font(.shadcnTextSm)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .strikethrough(task.isCompleted, color: Color.shadcnMutedForeground(colorScheme))

                // Weekday and status
                HStack(spacing: 8) {
                    Text(task.weekday.displayName)
                        .font(.shadcnTextXs)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                    Text("•")
                        .font(.shadcnTextXs)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                    Text(timeString)
                        .font(.shadcnTextXs)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                .fill(Color.clear)
        )
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

#Preview {
    CalendarPopupView()
}