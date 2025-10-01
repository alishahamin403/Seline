import SwiftUI

struct EventsView: View, Searchable {
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTaskForRecurring: TaskItem?
    @State private var selectedTaskForEditing: TaskItem?
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    enum ActiveSheet: Identifiable {
        case calendar
        case recurring
        case editTask

        var id: Int {
            hashValue
        }
    }

    private var filteredTasks: [TaskItem] {
        let allTasks = taskManager.tasks.values.flatMap { $0 }.filter { !$0.isDeleted }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        return allTasks.filter { task in
            task.title.localizedCaseInsensitiveContains(searchText)
        }.sorted { task1, task2 in
            if let date1 = task1.targetDate, let date2 = task2.targetDate {
                return date1 > date2
            } else if task1.targetDate != nil {
                return true
            } else if task2.targetDate != nil {
                return false
            } else {
                return task1.createdAt > task2.createdAt
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Spacer for fixed header
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: isSearchExpanded ? (searchText.isEmpty ? 60 : 250) : 60)

                    ForEach(Array(WeekDay.allCases.enumerated()), id: \.element) { index, weekday in
                    DayCard(
                        weekday: weekday,
                        tasks: taskManager.getTasksForCurrentWeek(for: weekday),
                        onAddTask: { title, scheduledTime, reminderTime in
                            taskManager.addTask(title: title, to: weekday, scheduledTime: scheduledTime, reminderTime: reminderTime)
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
                        onEditTask: { task in
                            selectedTaskForEditing = task
                            activeSheet = .editTask
                        }
                    )

                    // Add separator line between days (but not after the last day)
                    if index < WeekDay.allCases.count - 1 {
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

            // Fixed header with expandable search
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if !isSearchExpanded {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSearchExpanded = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isSearchFieldFocused = true
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.leading, 20)
                    } else {
                        // Expanded search bar
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            TextField("Search events...", text: $searchText)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .focused($isSearchFieldFocused)

                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                }
                            }

                            Button(action: {
                                searchText = ""
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSearchExpanded = false
                                }
                                isSearchFieldFocused = false
                            }) {
                                Text("Cancel")
                                    .font(.shadcnTextBase)
                                    .foregroundColor(Color.shadcnPrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                .fill(
                                    colorScheme == .dark ?
                                        Color.black.opacity(0.3) : Color.gray.opacity(0.1)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .stroke(
                                            colorScheme == .dark ?
                                                Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground : Color.white
                )

                // Inline search results
                if isSearchExpanded && !searchText.isEmpty {
                    ScrollView {
                        if filteredTasks.isEmpty {
                            Text("No results found")
                                .font(.shadcnTextSm)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                .padding(.vertical, 20)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredTasks.prefix(5)) { task in
                                    CompactEventSearchRow(
                                        task: task,
                                        colorScheme: colorScheme,
                                        onTap: {
                                            // Close search
                                            searchText = ""
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                isSearchExpanded = false
                                            }
                                            // Open edit sheet for the task
                                            selectedTaskForEditing = task
                                            activeSheet = .editTask
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(maxHeight: 190)
                    .background(
                        colorScheme == .dark ?
                            Color.gmailDarkBackground : Color.white
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)
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
            // Clear selected tasks when sheet is dismissed
            if newValue == nil {
                selectedTaskForRecurring = nil
                selectedTaskForEditing = nil
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

struct CompactEventSearchRow: View {
    let task: TaskItem
    let colorScheme: ColorScheme
    let onTap: () -> Void

    private var formattedDate: String {
        guard let targetDate = task.targetDate else {
            return "No date"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: targetDate)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? Color.shadcnPrimary : Color.shadcnMutedForeground(colorScheme))
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formattedDate)
                            .font(.shadcnTextXs)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                        if !task.formattedTime.isEmpty {
                            Text("•")
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            Text(task.formattedTime)
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        }

                        if task.isRecurring, let frequency = task.recurrenceFrequency {
                            Text("•")
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            HStack(spacing: 2) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 8))
                                Text(frequency.displayName)
                                    .font(.shadcnTextXs)
                            }
                            .foregroundColor(Color.shadcnPrimary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(
                        colorScheme == .dark ?
                            Color.black.opacity(0.2) : Color.gray.opacity(0.05)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EventsView()
}