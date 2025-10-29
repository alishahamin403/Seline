import SwiftUI

struct EventsView: View {
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var activeSheet: ActiveSheet?
    @State private var selectedTaskForRecurring: TaskItem?
    @State private var selectedTaskForViewing: TaskItem?
    @State private var selectedTaskForEditing: TaskItem?
    @State private var isTransitioningToEdit: Bool = false
    @State private var selectedView: EventViewType = .events
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedTagId: String? = nil // nil means show all, or specific tag ID
    @State private var showPhotoImportDialog = false
    @State private var showCameraActionSheet = false
    @State private var cameraSourceType: UIImagePickerController.SourceType = .camera
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false

    enum EventViewType: Hashable {
        case events
        case stats
    }

    enum ActiveSheet: Identifiable {
        case calendar
        case recurring
        case viewTask
        case editTask
        case photoImport

        var id: Int {
            hashValue
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let topPadding = CGFloat(4)

                VStack(spacing: 0) {
                    // Tab selector at the top
                    tabSelector
                        .padding(.horizontal, 20)
                        .padding(.top, topPadding)
                        .padding(.bottom, 12)
                        .background(
                            colorScheme == .dark ?
                                Color.black : Color.white
                        )

                    // Content based on selected view
                    if selectedView == .events {
                        eventsContent
                    } else {
                        EventStatsView()
                    }
                }
                .background(
                    colorScheme == .dark ?
                        Color.black : Color.white
                )
            }
            .overlay(
                // Floating buttons (only show in events view)
                Group {
                    if selectedView == .events {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    // Photo import button
                                    Button(action: {
                                        showPhotoImportDialog = true
                                    }) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 56, height: 56)
                                            .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.2)))
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // Calendar button
                                    FloatingCalendarButton {
                                        activeSheet = .calendar
                                    }
                                }
                                .padding(.trailing, 20)
                                .padding(.bottom, 30)
                            }
                        }
                    }
                }
            )
        }
        .confirmationDialog("Import Schedule", isPresented: $showPhotoImportDialog) {
            Button("Take Photo") {
                cameraSourceType = .camera
                showImagePicker = true
            }
            Button("Choose from Library") {
                cameraSourceType = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select a source to import your schedule")
        }
        .sheet(isPresented: $showImagePicker) {
            CameraAndLibraryPicker(image: $selectedImage, sourceType: cameraSourceType)
                .onDisappear {
                    if selectedImage != nil {
                        // Delay sheet presentation to allow image picker to fully dismiss
                        // This prevents blank screen from sheet transition conflict
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCameraActionSheet = true
                        }
                    }
                }
        }
        .sheet(isPresented: $showCameraActionSheet) {
            CameraActionSheetProcessing(
                selectedImage: $selectedImage,
                isPresented: $showCameraActionSheet
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .calendar:
                CalendarPopupView(selectedTagId: selectedTagId)
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
            case .photoImport:
                PhotoCalendarImportView()
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

    // MARK: - Helper Methods

    private func filteredTasks(from tasks: [TaskItem]) -> [TaskItem] {
        var result: [TaskItem] = []

        if selectedTagId == "" {
            // Personal filter - show events with nil tagId (default/personal events)
            result = tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
        } else if selectedTagId == "cal_sync" {
            // Personal - Sync filter - show only synced calendar events
            result = tasks.filter { $0.id.hasPrefix("cal_") }
            print("🔍 [EventsView] Personal - Sync filter:")
            print("   Total input tasks: \(tasks.count)")
            print("   Filtered synced events: \(result.count)")
            if !result.isEmpty {
                for (idx, task) in result.prefix(3).enumerated() {
                    print("   Event \(idx+1): \(task.title)")
                    print("      ID: \(task.id)")
                    print("      Has scheduledTime: \(task.scheduledTime != nil)")
                    print("      ScheduledTime: \(task.scheduledTime?.description ?? "nil")")
                }
            }
        } else if let tagId = selectedTagId, !tagId.isEmpty {
            // Filter by specific tag
            result = tasks.filter { $0.tagId == tagId }
        } else {
            // Show all tasks (selectedTagId == nil means "All")
            result = tasks
        }

        return result
    }

    private func getTagColor(for tagId: String?) -> Color {
        if let tagId = tagId, let tag = tagManager.getTag(by: tagId) {
            return tag.color
        }
        return Color.blue // Personal (default) color
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach([EventViewType.events, EventViewType.stats], id: \.self) { viewType in
                EventTabButton(
                    title: viewType == .events ? "Events" : "Stats",
                    viewType: viewType,
                    selectedView: $selectedView,
                    colorScheme: colorScheme
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.gray.opacity(0.08))
        )
    }

    // MARK: - Events Content

    private var eventsContent: some View {
        VStack(spacing: 0) {
            // Day slider
            DaySliderView(selectedDate: $selectedDate)

            // Filter buttons - Show "All", "Personal", and all user-created tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" button (neutral black/white, no color impact)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagId = nil
                        }
                    }) {
                        Text("All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedTagId == nil ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTagId == nil ?
                                        TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme).opacity(0.2) :
                                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Personal (default) button - using special marker ""
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagId = "" // Empty string to filter for personal events (nil tagId)
                        }
                    }) {
                        Text("Personal")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedTagId == "" ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTagId == "" ?
                                        TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme).opacity(0.2) :
                                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Personal - Sync button (Calendar synced events)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagId = "cal_sync" // Special marker for synced calendar events
                        }
                    }) {
                        Text("Personal - Sync")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedTagId == "cal_sync" ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTagId == "cal_sync" ?
                                        TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme).opacity(0.2) :
                                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // User-created tags
                    ForEach(tagManager.tags, id: \.id) { tag in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTagId = tag.id
                            }
                        }) {
                            Text(tag.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedTagId == tag.id ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTagId == tag.id ?
                                            TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme).opacity(0.2) :
                                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // All day events section
            AllDayEventsSection(
                tasks: filteredTasks(from: taskManager.getTasksForDate(selectedDate)),
                date: selectedDate,
                onTapTask: { task in
                    selectedTaskForViewing = task
                    activeSheet = .viewTask
                },
                onToggleCompletion: { task in
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                }
            )

            // Timeline view
            TimelineView(
                tasks: filteredTasks(from: taskManager.getTasksForDate(selectedDate)),
                date: selectedDate,
                onTapTask: { task in
                    selectedTaskForViewing = task
                    activeSheet = .viewTask
                },
                onToggleCompletion: { task in
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                },
                onAddEvent: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                    // Determine the weekday from the selected date
                    let calendar = Calendar.current
                    let weekdayIndex = calendar.component(.weekday, from: date)
                    let weekday: WeekDay
                    switch weekdayIndex {
                    case 1: weekday = .sunday
                    case 2: weekday = .monday
                    case 3: weekday = .tuesday
                    case 4: weekday = .wednesday
                    case 5: weekday = .thursday
                    case 6: weekday = .friday
                    case 7: weekday = .saturday
                    default: weekday = .monday
                    }

                    taskManager.addTask(
                        title: title,
                        to: weekday,
                        description: description,
                        scheduledTime: time,
                        endTime: endTime,
                        targetDate: date,
                        reminderTime: reminder,
                        isRecurring: recurring,
                        recurrenceFrequency: frequency,
                        tagId: tagId
                    )
                },
                onEditEvent: { task in
                    selectedTaskForEditing = task
                    activeSheet = .editTask
                },
                onDeleteEvent: { task in
                    if task.isRecurring {
                        taskManager.deleteRecurringTask(task)
                    } else {
                        taskManager.deleteTask(task)
                    }
                }
            )
        }
        .background(
            colorScheme == .dark ?
                Color.black : Color.white
        )
    }
}

struct EventTabButton: View {
    let title: String
    let viewType: EventsView.EventViewType
    @Binding var selectedView: EventsView.EventViewType
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedView == viewType
    }

    private var selectedColor: Color {
        // Matches + sign button fill color - #333333
        return Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    private var backgroundColor: Color {
        if isSelected {
            return selectedColor
        }
        return Color.clear
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedView = viewType
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(
                    isSelected ? .white : .gray
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    EventsView()
}