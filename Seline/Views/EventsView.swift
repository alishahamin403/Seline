import SwiftUI

struct EventsView: View, Searchable {
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTaskForRecurring: TaskItem?

    enum ActiveSheet: Identifiable {
        case calendar
        case recurring

        var id: Int {
            hashValue
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(WeekDay.allCases.enumerated()), id: \.element) { index, weekday in
                    DayCard(
                        weekday: weekday,
                        tasks: taskManager.getTasks(for: weekday),
                        onAddTask: { title, scheduledTime in
                            taskManager.addTask(title: title, to: weekday, scheduledTime: scheduledTime)
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
                        }
                    )

                    // Add separator line between days (but not after the last day)
                    if index < WeekDay.allCases.count - 1 {
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 2)
                            .padding(.vertical, 12)
                    }
                }

                // Bottom spacing for better scrolling experience
                Spacer()
                    .frame(height: 100)
            }
            .padding(.top, 20)
        }
        .background(
            colorScheme == .dark ?
                Color.gmailDarkBackground : Color.white
        )
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
                    .padding(.bottom, 60) // Match + icon spacing
                }
            }
        )
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .calendar:
                CalendarPopupView()
            case .recurring:
                if let task = selectedTaskForRecurring {
                    RecurringTaskSheet(task: task) { frequency in
                        taskManager.makeTaskRecurring(task, frequency: frequency)
                    }
                }
            }
        }
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .events)
        }
    }

    // MARK: - Searchable Protocol Implementation
    func getSearchableContent() -> [SearchableItem] {
        var searchableItems: [SearchableItem] = []

        // Add general events functionality
        searchableItems.append(SearchableItem(
            title: "Weekly Tasks",
            content: "Organize your weekly tasks from Monday to Friday with completion tracking.",
            type: .events,
            identifier: "events-main",
            metadata: ["category": "productivity", "feature": "weekly-planning"]
        ))

        searchableItems.append(SearchableItem(
            title: "Create Task",
            content: "Add new tasks to any weekday with quick input and organization.",
            type: .events,
            identifier: "events-create",
            metadata: ["feature": "create", "action": "add-task"]
        ))

        searchableItems.append(SearchableItem(
            title: "Task Management",
            content: "Mark tasks as complete, delete finished items, and track your weekly progress.",
            type: .events,
            identifier: "events-manage",
            metadata: ["feature": "management", "action": "complete-delete"]
        ))

        // Add tasks from each day as searchable content
        for weekday in WeekDay.allCases {
            let dayTasks = taskManager.getTasks(for: weekday)

            if !dayTasks.isEmpty {
                let taskTitles = dayTasks.map { $0.title }.joined(separator: ", ")
                searchableItems.append(SearchableItem(
                    title: "\(weekday.displayName) Tasks",
                    content: "Tasks for \(weekday.displayName): \(taskTitles)",
                    type: .events,
                    identifier: "events-\(weekday.rawValue)",
                    metadata: [
                        "weekday": weekday.rawValue,
                        "task_count": "\(dayTasks.count)",
                        "completed_count": "\(dayTasks.filter { $0.isCompleted }.count)"
                    ]
                ))
            }
        }

        return searchableItems
    }
}

#Preview {
    EventsView()
}