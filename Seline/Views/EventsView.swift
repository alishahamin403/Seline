import SwiftUI

struct EventsView: View {
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTaskForRecurring: TaskItem?
    @State private var selectedTaskForViewing: TaskItem?
    @State private var selectedTaskForEditing: TaskItem?
    @State private var isTransitioningToEdit: Bool = false

    enum ActiveSheet: Identifiable {
        case calendar
        case recurring
        case viewTask
        case editTask

        var id: Int {
            hashValue
        }
    }

    private var next6Days: [(date: Date, weekday: WeekDay)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).compactMap { dayOffset in
            guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            let weekdayIndex = calendar.component(.weekday, from: futureDate)

            // Convert Calendar weekday (1=Sunday, 2=Monday, etc.) to WeekDay enum
            let weekday: WeekDay
            switch weekdayIndex {
            case 1: weekday = .sunday
            case 2: weekday = .monday
            case 3: weekday = .tuesday
            case 4: weekday = .wednesday
            case 5: weekday = .thursday
            case 6: weekday = .friday
            case 7: weekday = .saturday
            default: return nil
            }

            return (futureDate, weekday)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                    ForEach(Array(next6Days.enumerated()), id: \.element.weekday) { index, dayInfo in
                    DayCard(
                        weekday: dayInfo.weekday,
                        date: dayInfo.date,
                        tasks: taskManager.getTasksForDate(dayInfo.date).filter { task in
                            // For future dates (next week's Monday/Tuesday), only show uncompleted tasks
                            let calendar = Calendar.current
                            let today = calendar.startOfDay(for: Date())
                            let cardDate = calendar.startOfDay(for: dayInfo.date)

                            if cardDate > today {
                                // Future date - only show incomplete tasks
                                return !task.isCompleted
                            } else {
                                // Today or current week - show all tasks
                                return true
                            }
                        },
                        onAddTask: { title, scheduledTime, reminderTime in
                            taskManager.addTask(title: title, to: dayInfo.weekday, scheduledTime: scheduledTime, reminderTime: reminderTime)
                        },
                        onToggleTask: { task in
                            taskManager.toggleTaskCompletion(task)
                        },
                        onDeleteTask: { task in
                            taskManager.deleteTask(task)
                        },
                        onDeleteRecurringSeries: { task in
                            taskManager.deleteRecurringTask(task)
                        },
                        onMakeRecurring: { task in
                            selectedTaskForRecurring = task
                            activeSheet = .recurring
                        },
                        onViewTask: { task in
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        },
                        onEditTask: { task in
                            selectedTaskForEditing = task
                            activeSheet = .editTask
                        }
                    )

                    // Add separator line between days (but not after the last day)
                    if index < next6Days.count - 1 {
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }

                    // Bottom spacing for better scrolling experience
                    Spacer()
                        .frame(height: 100)
                }
            }
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
        }
        .overlay(
            // Floating calendar button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingCalendarButton {
                        activeSheet = .calendar
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30) // Match + icon spacing
                }
            }
        )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .calendar:
                CalendarPopupView()
            case .recurring:
                if let task = selectedTaskForRecurring {
                    NavigationView {
                        RecurringTaskSheet(task: task) { frequency in
                            taskManager.makeTaskRecurring(task, frequency: frequency)
                            selectedTaskForRecurring = nil
                        }
                    }
                } else {
                    // Fallback content to prevent blank screen
                    NavigationView {
                        VStack {
                            Text("Unable to load recurring task options")
                                .foregroundColor(.secondary)
                            Button("Close") {
                                activeSheet = nil
                            }
                            .padding()
                        }
                        .navigationTitle("Error")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            case .viewTask:
                if let task = selectedTaskForViewing {
                    NavigationView {
                        ViewEventView(
                            task: task,
                            onEdit: {
                                // Set task for editing and mark that we're transitioning
                                selectedTaskForEditing = task
                                isTransitioningToEdit = true
                                // Dismiss current sheet
                                activeSheet = nil
                                // Open edit sheet after a brief delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    activeSheet = .editTask
                                }
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                selectedTaskForViewing = nil
                                activeSheet = nil
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                selectedTaskForViewing = nil
                                activeSheet = nil
                            }
                        )
                    }
                } else {
                    // Fallback content to prevent blank screen
                    NavigationView {
                        VStack {
                            Text("Unable to load task details")
                                .foregroundColor(.secondary)
                            Button("Close") {
                                activeSheet = nil
                            }
                            .padding()
                        }
                        .navigationTitle("Error")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            case .editTask:
                if let task = selectedTaskForEditing {
                    NavigationView {
                        EditTaskView(
                            task: task,
                            onSave: { updatedTask in
                                taskManager.editTask(updatedTask)
                                selectedTaskForEditing = nil
                                activeSheet = nil
                            },
                            onCancel: {
                                selectedTaskForEditing = nil
                                activeSheet = nil
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                selectedTaskForEditing = nil
                                activeSheet = nil
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                selectedTaskForEditing = nil
                                activeSheet = nil
                            }
                        )
                    }
                } else {
                    // Fallback content to prevent blank screen
                    NavigationView {
                        VStack {
                            Text("Unable to load task for editing")
                                .foregroundColor(.secondary)
                            Button("Close") {
                                activeSheet = nil
                            }
                            .padding()
                        }
                        .navigationTitle("Error")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .onChange(of: activeSheet) { newValue in
            // Clear selected tasks when sheet is dismissed (unless transitioning to edit)
            if newValue == nil {
                selectedTaskForRecurring = nil
                selectedTaskForViewing = nil
                // Don't clear editing task if we're transitioning to edit mode
                if !isTransitioningToEdit {
                    selectedTaskForEditing = nil
                }
            } else if newValue == .editTask {
                // Reset transition flag once edit sheet is shown
                isTransitioningToEdit = false
            }
        }
    }
}

#Preview {
    EventsView()
}