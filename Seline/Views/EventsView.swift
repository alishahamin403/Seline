import SwiftUI

struct EventsView: View {
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var tabAnimation
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
    @State private var isCreatingEvent = false
    @State private var calendarViewMode: CalendarViewMode = .week
    @State private var showAddEventPopup = false
    @State private var addEventDate: Date = Date()

    enum EventViewType: Hashable {
        case events
        case stats
    }

    enum ActiveSheet: Identifiable {
        case recurring
        case viewTask
        case editTask
        case photoImport
        case stats

        var id: Int {
            hashValue
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Events content
                    eventsContent
                }
                .background(
                    colorScheme == .dark ?
                        Color.black : Color.white
                )
            }
            .overlay(
                // Floating buttons
                Group {
                    if !isCreatingEvent {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                // Photo import button (stats button removed - ranking is now a tab)
                                Button(action: {
                                    showPhotoImportDialog = true
                                }) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.2)))
                                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                }
                                .buttonStyle(PlainButtonStyle())
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
            .presentationBg()
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
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
                    NavigationStack {
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
            case .stats:
                EventStatsView()
                }
            }
            .presentationBg()
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
        .sheet(isPresented: $showAddEventPopup) {
            AddEventPopupView(
                isPresented: $showAddEventPopup,
                onSave: { title, description, date, time, endTime, reminder, recurring, frequency, customDays, tagId, location in
                    addEventToCalendar(title: title, description: description, date: date, time: time, endTime: endTime, reminder: reminder, recurring: recurring, frequency: frequency, tagId: tagId, location: location)
                },
                initialDate: addEventDate,
                initialTime: nil
            )
            .presentationBg()
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
        return Color.gray // Personal (default) color
    }

    // Helper methods for filter button styling
    private func filterButtonTextColor(isSelected: Bool, accentColor: Color) -> Color {
        if isSelected {
            // Always use white text on colored buttons for both dark and light mode
            return Color.white
        } else {
            return Color.shadcnForeground(colorScheme)
        }
    }

    private func filterButtonBackground(isSelected: Bool, accentColor: Color) -> some View {
        Capsule()
            .fill(isSelected ?
                accentColor : // Use the actual tag/category color when selected
                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
    }

    // MARK: - Events Content

    private var eventsContent: some View {
        VStack(spacing: 0) {
            // Calendar header with month title and view mode toggle
            CalendarHeaderView(
                selectedDate: $selectedDate,
                viewMode: $calendarViewMode
            )

            // View content based on selected mode
            Group {
                switch calendarViewMode {
                case .week:
                    // For week view: filters as usual
                    VStack(spacing: 0) {
                        tagFilterButtons
                        weekViewContent
                    }
                    .transition(.opacity)
                case .month:
                    // For month view: filters as usual
                    VStack(spacing: 0) {
                        tagFilterButtons
                        monthViewContent
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
                case .ranking:
                    // Ranking view - no filters needed
                    rankingViewContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: calendarViewMode)
        }
        .background(
            colorScheme == .dark ?
                Color.black : Color.white
        )
    }
    
    // MARK: - Tag Filter Buttons
    
    private var tagFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = nil
                    }
                }) {
                    let isSelected = selectedTagId == nil
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme)

                    Text("All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // Personal button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = ""
                    }
                }) {
                    let isSelected = selectedTagId == ""
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme)

                    Text("Personal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // Sync button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = "cal_sync"
                    }
                }) {
                    let isSelected = selectedTagId == "cal_sync"
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme)

                    Text("Sync")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // User-created tags
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagId = tag.id
                        }
                    }) {
                        let isSelected = selectedTagId == tag.id
                        let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex)

                        Text(tag.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Week View Content
    
    private var weekViewContent: some View {
        CalendarWeekView(
            selectedDate: $selectedDate,
            selectedTagId: selectedTagId,
            onTapEvent: { task in
                selectedTaskForViewing = task
                activeSheet = .viewTask
            },
            onAddEvent: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                addEventToCalendar(title: title, description: description, date: date, time: time, endTime: endTime, reminder: reminder, recurring: recurring, frequency: frequency, tagId: tagId, location: nil)
            }
        )
    }
    
    // MARK: - Ranking View Content (Recurring Stats)
    
    private var rankingViewContent: some View {
        EventStatsView()
    }
    
    // MARK: - Month View Content
    
    private var monthViewContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Calendar month grid
                    CalendarMonthView(
                        selectedDate: $selectedDate,
                        selectedTagId: selectedTagId,
                        onTapEvent: { task in
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        },
                        onAddEvent: { date in
                            addEventDate = date
                            showAddEventPopup = true
                        }
                    )
                    
                    // Agenda view for selected date (no divider line)
                    CalendarAgendaView(
                        selectedDate: selectedDate,
                        selectedTagId: selectedTagId,
                        onTapEvent: { task in
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        },
                        onToggleCompletion: { task in
                            taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                        },
                        onAddEvent: { date in
                            addEventDate = date
                            showAddEventPopup = true
                        }
                    )
                    .id("agendaView") // ID for scrolling
                }
            }
            .onChange(of: selectedDate) { _ in
                // Scroll to agenda view when date is selected
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("agendaView", anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Add Event Helper
    
    private func addEventToCalendar(title: String, description: String?, date: Date, time: Date?, endTime: Date?, reminder: ReminderTime?, recurring: Bool, frequency: RecurrenceFrequency?, tagId: String?, location: String?) {
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
            location: location,
            isRecurring: recurring,
            recurrenceFrequency: frequency,
            tagId: tagId
        )
    }

}

#Preview {
    EventsView()
}