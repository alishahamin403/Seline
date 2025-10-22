import Foundation
import PostgREST

enum ReminderTime: String, CaseIterable, Codable {
    case fifteenMinutes = "15min"
    case oneHour = "1hour"
    case threeHours = "3hours"
    case oneDay = "1day"
    case none = "none"

    var displayName: String {
        switch self {
        case .fifteenMinutes: return "15 minutes before"
        case .oneHour: return "1 hour before"
        case .threeHours: return "3 hours before"
        case .oneDay: return "1 day before"
        case .none: return "No reminder"
        }
    }

    var minutes: Int {
        switch self {
        case .fifteenMinutes: return 15
        case .oneHour: return 60
        case .threeHours: return 180
        case .oneDay: return 1440
        case .none: return 0
        }
    }

    var icon: String {
        switch self {
        case .fifteenMinutes: return "bell.fill"
        case .oneHour: return "bell.fill"
        case .threeHours: return "bell.fill"
        case .oneDay: return "bell.fill"
        case .none: return "bell.slash.fill"
        }
    }
}

enum RecurrenceFrequency: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Repeats every day"
        case .weekly: return "Repeats every week"
        case .biweekly: return "Repeats every 2 weeks"
        case .monthly: return "Repeats every month"
        case .yearly: return "Repeats every year"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .biweekly: return "calendar.badge.plus"
        case .monthly: return "calendar.circle"
        case .yearly: return "calendar.badge.clock"
        }
    }
}

enum WeekDay: String, CaseIterable, Identifiable, Codable {
    case monday = "monday"
    case tuesday = "tuesday"
    case wednesday = "wednesday"
    case thursday = "thursday"
    case friday = "friday"
    case saturday = "saturday"
    case sunday = "sunday"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monday: return "MONDAY"
        case .tuesday: return "TUESDAY"
        case .wednesday: return "WEDNESDAY"
        case .thursday: return "THURSDAY"
        case .friday: return "FRIDAY"
        case .saturday: return "SATURDAY"
        case .sunday: return "SUNDAY"
        }
    }

    var calendarWeekday: Int {
        switch self {
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        case .sunday: return 1
        }
    }

    func dateForCurrentWeek() -> Date {
        let calendar = Calendar.current
        let today = Date()

        // Get current weekday (1=Sunday, 2=Monday, ..., 7=Saturday)
        let todayWeekday = calendar.component(.weekday, from: today)

        // Calculate days from Monday (where Monday = 0, Tuesday = 1, ..., Sunday = 6)
        let daysFromMonday = (todayWeekday + 5) % 7

        // Get Monday of current week
        let mondayOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today

        // Calculate offset from Monday for this weekday
        let dayOffset: Int
        switch self {
        case .monday: dayOffset = 0
        case .tuesday: dayOffset = 1
        case .wednesday: dayOffset = 2
        case .thursday: dayOffset = 3
        case .friday: dayOffset = 4
        case .saturday: dayOffset = 5
        case .sunday: dayOffset = 6
        }

        return calendar.date(byAdding: .day, value: dayOffset, to: mondayOfWeek) ?? today
    }

    func formattedDate() -> String {
        let date = dateForCurrentWeek()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    enum DayStatus {
        case past
        case current
        case future
    }

    var dayStatus: DayStatus {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)

        if self.calendarWeekday == todayWeekday {
            return .current
        }

        // Get this weekday's date for the current week
        let thisWeekdayDate = self.dateForCurrentWeek()

        // Compare dates at day level (ignore time)
        let comparison = calendar.compare(thisWeekdayDate, to: today, toGranularity: .day)

        switch comparison {
        case .orderedAscending:
            return .past
        case .orderedDescending:
            return .future
        case .orderedSame:
            return .current
        }
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var description: String? // Optional description field for additional event details
    var isCompleted: Bool
    var completedDate: Date?
    let weekday: WeekDay
    var createdAt: Date
    var isRecurring: Bool
    var recurrenceFrequency: RecurrenceFrequency?
    var recurrenceEndDate: Date?
    var parentRecurringTaskId: String? // For tracking which recurring task this belongs to
    var scheduledTime: Date? // Start time of the event
    var endTime: Date? // End time of the event
    var targetDate: Date? // Specific date this task is intended for
    var reminderTime: ReminderTime? // When to remind the user
    var isDeleted: Bool = false // Flag for soft deletion when Supabase deletion fails
    var completedDates: [Date] = [] // For recurring tasks: track which specific dates were completed

    // Email attachment fields
    var emailId: String?
    var emailSubject: String?
    var emailSenderName: String?
    var emailSenderEmail: String?
    var emailSnippet: String?
    var emailTimestamp: Date?
    var emailBody: String?
    var emailIsImportant: Bool = false
    var emailAiSummary: String?

    var hasEmailAttachment: Bool {
        return emailId != nil
    }

    // Check if this recurring task is completed on a specific date
    func isCompletedOn(date: Date) -> Bool {
        if !isRecurring {
            // For non-recurring tasks, use the regular isCompleted flag
            return isCompleted
        }

        // For recurring tasks, check if this specific date is in completedDates
        let calendar = Calendar.current
        return completedDates.contains { completedDate in
            calendar.isDate(completedDate, inSameDayAs: date)
        }
    }

    init(title: String, weekday: WeekDay, description: String? = nil, scheduledTime: Date? = nil, endTime: Date? = nil, targetDate: Date? = nil, reminderTime: ReminderTime? = nil, isRecurring: Bool = false, recurrenceFrequency: RecurrenceFrequency? = nil, parentRecurringTaskId: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.isCompleted = false
        self.completedDate = nil
        self.weekday = weekday
        self.createdAt = Date()
        self.scheduledTime = scheduledTime
        self.endTime = endTime
        self.targetDate = targetDate
        self.reminderTime = reminderTime
        self.isRecurring = isRecurring
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceEndDate = isRecurring ? Calendar.current.date(byAdding: .year, value: 10, to: Date()) : nil
        self.parentRecurringTaskId = parentRecurringTaskId
    }

    var formattedTime: String {
        guard let scheduledTime = scheduledTime else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: scheduledTime)
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if let start = scheduledTime, let end = endTime {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = scheduledTime {
            return formatter.string(from: start)
        }
        return ""
    }

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        return lhs.id == rhs.id
    }
}

@MainActor
class TaskManager: ObservableObject {
    static let shared = TaskManager()

    @Published var tasks: [WeekDay: [TaskItem]] = [:]

    private let userDefaults = UserDefaults.standard
    private let tasksKey = "SavedTasks"
    private let supabaseManager = SupabaseManager.shared
    private let authManager = AuthenticationManager.shared

    private init() {
        initializeEmptyDays()
        loadTasks()

        // Load tasks from Supabase if user is authenticated
        Task {
            await loadTasksFromSupabase()
        }
    }

    private func initializeEmptyDays() {
        for weekday in WeekDay.allCases {
            if tasks[weekday] == nil {
                tasks[weekday] = []
            }
        }
    }

    func addTask(title: String, to weekday: WeekDay, description: String? = nil, scheduledTime: Date? = nil, endTime: Date? = nil, targetDate: Date? = nil, reminderTime: ReminderTime? = nil, isRecurring: Bool = false, recurrenceFrequency: RecurrenceFrequency? = nil) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Use provided target date, or default to the current week's date for this weekday
        let finalTargetDate = targetDate ?? weekday.dateForCurrentWeek()
        let newTask = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            weekday: weekday,
            description: description,
            scheduledTime: scheduledTime,
            endTime: endTime,
            targetDate: finalTargetDate,
            reminderTime: reminderTime,
            isRecurring: isRecurring,
            recurrenceFrequency: recurrenceFrequency,
            parentRecurringTaskId: nil
        )
        tasks[weekday]?.append(newTask)
        saveTasks()

        // Schedule notification if reminder is set
        if let reminderTime = reminderTime, reminderTime != .none, let scheduledTime = scheduledTime {
            // Combine target date with scheduled time to get the full event date/time
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let eventDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                  minute: timeComponents.minute ?? 0,
                                                  second: 0,
                                                  of: finalTargetDate) {
                scheduleReminder(for: newTask, at: eventDateTime, reminderBefore: reminderTime)
            }
        }

        // Sync with Supabase
        Task {
            await saveTaskToSupabase(newTask)
        }
    }

    func toggleTaskCompletion(_ task: TaskItem, forDate: Date? = nil) {
        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else { return }

        // For recurring tasks, track completion per date instead of marking the task complete
        if task.isRecurring {
            let calendar = Calendar.current
            // Use the provided date or the task's target date or today
            let completionDate = calendar.startOfDay(for: forDate ?? task.targetDate ?? Date())


            // Check if this date is already in completedDates
            if let existingIndex = tasks[task.weekday]?[index].completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: completionDate) }) {
                // Remove the date (marking as incomplete)
                tasks[task.weekday]?[index].completedDates.remove(at: existingIndex)
            } else {
                // Add the date (marking as complete)
                tasks[task.weekday]?[index].completedDates.append(completionDate)
            }

            // IMPORTANT: Keep the parent task itself as incomplete
            tasks[task.weekday]?[index].isCompleted = false
            tasks[task.weekday]?[index].completedDate = nil
        } else {
            // For non-recurring tasks, use the original toggle logic
            tasks[task.weekday]?[index].isCompleted.toggle()

            // Set or clear completion date
            if tasks[task.weekday]?[index].isCompleted == true {
                tasks[task.weekday]?[index].completedDate = Date()
            } else {
                tasks[task.weekday]?[index].completedDate = nil
            }
        }

        saveTasks()

        // Trigger UI update to ensure views refresh with new completion status
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Sync with Supabase
        if let updatedTask = tasks[task.weekday]?[index] {
            Task {
                await updateTaskInSupabase(updatedTask)
            }
        }
    }

    func deleteTask(_ task: TaskItem) {
        // IMPORTANT: Don't allow deletion of recurring tasks through this method
        // Use deleteRecurringTask() instead
        if task.isRecurring {
            print("⚠️ Cannot delete recurring task using deleteTask() - use deleteRecurringTask() instead")
            print("⚠️ This prevents accidental deletion of recurring tasks")
            return
        }

        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else { return }

        let taskId = task.id

        // Cancel any pending reminders for this task
        NotificationService.shared.cancelTaskReminder(taskId: taskId)

        // First try to delete from Supabase, then handle locally
        Task {
            let success = await deleteTaskFromSupabase(taskId)
            await MainActor.run {
                if success {
                    // Remove completely if Supabase deletion succeeded
                    tasks[task.weekday]?.remove(at: index)
                    saveTasks()
                } else {
                    // Mark as deleted locally if Supabase deletion failed
                    tasks[task.weekday]?[index].isDeleted = true
                    saveTasks()
                    print("⚠️ Marked task as deleted locally, will retry Supabase deletion later")
                }
            }
        }
    }

    func editTask(_ task: TaskItem, newTitle: String, newDate: Date, newTime: Date?) {

        // Only allow editing non-recurring tasks
        guard !task.isRecurring && task.parentRecurringTaskId == nil else {
            print("❌ Cannot edit recurring tasks")
            return
        }

        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else {
            print("❌ Could not find task to edit")
            return
        }

        let calendar = Calendar.current
        let newWeekday = weekdayFromCalendarComponent(calendar.component(.weekday, from: newDate)) ?? task.weekday

        // Update the task
        var updatedTask = task
        updatedTask.title = newTitle
        updatedTask.targetDate = newDate
        updatedTask.scheduledTime = newTime

        // If the weekday changed, move the task to the new weekday
        if newWeekday != task.weekday {
            // Remove from old weekday
            tasks[task.weekday]?.remove(at: index)

            // Add to new weekday with updated weekday property
            let _ = updatedTask
            // Create a new task with the correct weekday since weekday is let
            let newTask = TaskItem(
                title: newTitle,
                weekday: newWeekday,
                scheduledTime: newTime,
                targetDate: newDate,
                isRecurring: false,
                recurrenceFrequency: nil,
                parentRecurringTaskId: nil
            )
            var finalTask = newTask
            finalTask.id = task.id
            finalTask.isCompleted = task.isCompleted
            finalTask.completedDate = task.completedDate
            finalTask.createdAt = task.createdAt
            finalTask.isDeleted = task.isDeleted

            // Ensure the weekday array exists
            if tasks[newWeekday] == nil {
                tasks[newWeekday] = []
            }
            tasks[newWeekday]?.append(finalTask)
        } else {
            // Update in place
            tasks[task.weekday]?[index] = updatedTask
        }

        saveTasks()

        // Trigger UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Sync with Supabase
        let taskToSync = newWeekday != task.weekday ?
            tasks[newWeekday]?.first(where: { $0.id == task.id }) ?? updatedTask :
            updatedTask


        Task {
            await updateTaskInSupabase(taskToSync)
        }
    }

    func editTask(_ updatedTask: TaskItem) {

        guard let weekdayTasks = tasks[updatedTask.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == updatedTask.id }) else {
            print("❌ Could not find task to edit")
            return
        }

        let originalTask = weekdayTasks[index]

        // Handle conversion from recurring to single event
        if originalTask.isRecurring && !updatedTask.isRecurring {
            // Remove this specific instance from all recurring instances
            // Keep only this one instance as a single event
            removeAllRecurringInstances(originalTask)
        }

        // Handle conversion from single event to recurring
        if !originalTask.isRecurring && updatedTask.isRecurring {
            // This will create new instances based on the recurrence frequency
        }

        // Handle updates to existing recurring tasks (title, time, date changes only)
        if originalTask.isRecurring && updatedTask.isRecurring {
            updateAllRecurringInstances(originalTask, with: updatedTask)
            return // Early return since we've handled all updates
        }

        // Frequency changes are not allowed - the UI prevents this
        // Users must delete and recreate recurring tasks to change frequency

        // Calculate new weekday from target date if provided
        var finalTask = updatedTask
        if let targetDate = updatedTask.targetDate {
            let calendar = Calendar.current
            let newWeekday = weekdayFromCalendarComponent(calendar.component(.weekday, from: targetDate)) ?? updatedTask.weekday

            if newWeekday != updatedTask.weekday {
                // Remove from old weekday
                tasks[updatedTask.weekday]?.remove(at: index)

                // Create task with correct weekday
                let newTask = TaskItem(
                    title: updatedTask.title,
                    weekday: newWeekday,
                    scheduledTime: updatedTask.scheduledTime,
                    targetDate: updatedTask.targetDate,
                    isRecurring: updatedTask.isRecurring,
                    recurrenceFrequency: updatedTask.recurrenceFrequency,
                    parentRecurringTaskId: updatedTask.parentRecurringTaskId
                )
                var finalTaskCopy = newTask
                finalTaskCopy.id = updatedTask.id
                finalTaskCopy.isCompleted = updatedTask.isCompleted
                finalTaskCopy.completedDate = updatedTask.completedDate
                finalTaskCopy.createdAt = updatedTask.createdAt
                finalTaskCopy.isDeleted = updatedTask.isDeleted

                // Ensure the weekday array exists
                if tasks[newWeekday] == nil {
                    tasks[newWeekday] = []
                }
                tasks[newWeekday]?.append(finalTaskCopy)
                finalTask = finalTaskCopy
            } else {
                // Update in place
                tasks[updatedTask.weekday]?[index] = finalTask
            }
        } else {
            // Update in place if no target date change
            tasks[updatedTask.weekday]?[index] = finalTask
        }

        saveTasks()

        // Cancel old reminder and schedule new one if needed
        NotificationService.shared.cancelTaskReminder(taskId: finalTask.id)
        if let reminderTime = finalTask.reminderTime,
           reminderTime != .none,
           let scheduledTime = finalTask.scheduledTime,
           let targetDate = finalTask.targetDate {
            // Combine target date with scheduled time
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let eventDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                  minute: timeComponents.minute ?? 0,
                                                  second: 0,
                                                  of: targetDate) {
                scheduleReminder(for: finalTask, at: eventDateTime, reminderBefore: reminderTime)
            }
        }

        // Trigger UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Sync with Supabase
        Task {
            await updateTaskInSupabase(finalTask)

            // If the task is now recurring, create future instances
            if finalTask.isRecurring, let frequency = finalTask.recurrenceFrequency {
                await createRecurringInstances(for: finalTask, frequency: frequency)
            }
        }
    }

    private func removeAllRecurringInstances(_ task: TaskItem) {
        // Remove all instances of this recurring task from all weekdays
        for weekday in WeekDay.allCases {
            tasks[weekday]?.removeAll { relatedTask in
                return relatedTask.id == task.id || relatedTask.parentRecurringTaskId == task.id
            }
        }
    }

    private func updateAllRecurringInstances(_ originalTask: TaskItem, with updatedTask: TaskItem) {

        var updatedTasks: [TaskItem] = []

        // Update all instances across all weekdays
        for weekday in WeekDay.allCases {
            guard let weekdayTasks = tasks[weekday] else { continue }

            for (index, task) in weekdayTasks.enumerated() {
                // Update the main recurring task
                if task.id == originalTask.id {
                    var updatedMainTask = updatedTask
                    updatedMainTask.id = originalTask.id
                    updatedMainTask.isCompleted = task.isCompleted
                    updatedMainTask.completedDate = task.completedDate
                    updatedMainTask.createdAt = task.createdAt

                    tasks[weekday]?[index] = updatedMainTask
                    updatedTasks.append(updatedMainTask)
                }
                // Update all instances that belong to this recurring task
                else if task.parentRecurringTaskId == originalTask.id {
                    var updatedInstance = task
                    updatedInstance.title = updatedTask.title

                    // Update scheduled time while keeping the target date
                    if let newScheduledTime = updatedTask.scheduledTime,
                       let instanceTargetDate = task.targetDate {
                        // Combine the new time with the existing instance date
                        let calendar = Calendar.current
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: newScheduledTime)
                        let updatedDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                          minute: timeComponents.minute ?? 0,
                                                          second: 0,
                                                          of: instanceTargetDate)
                        updatedInstance.scheduledTime = updatedDateTime
                    } else {
                        updatedInstance.scheduledTime = updatedTask.scheduledTime
                    }

                    tasks[weekday]?[index] = updatedInstance
                    updatedTasks.append(updatedInstance)
                }
            }
        }

        // Save changes locally
        saveTasks()

        // Trigger UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Sync all updated tasks to Supabase
        Task {
            for task in updatedTasks {
                await updateTaskInSupabase(task)
            }
        }

    }



    private func createRecurringInstances(for task: TaskItem, frequency: RecurrenceFrequency) async {
        // Create future instances based on the recurrence frequency
        // This would extend the existing recurring task creation logic

        guard let startDate = task.targetDate else { return }
        let calendar = Calendar.current

        // Create instances for the next month based on frequency
        var currentDate = startDate
        for _ in 0..<4 { // Create 4 future instances
            switch frequency {
            case .daily:
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            case .weekly:
                currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
            case .biweekly:
                currentDate = calendar.date(byAdding: .weekOfYear, value: 2, to: currentDate) ?? currentDate
            case .monthly:
                currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
            case .yearly:
                currentDate = calendar.date(byAdding: .year, value: 1, to: currentDate) ?? currentDate
            }

            let newWeekday = weekdayFromCalendarComponent(calendar.component(.weekday, from: currentDate)) ?? task.weekday

            // Check if an instance for this date already exists
            let existingInstanceExists = await MainActor.run {
                return tasks[newWeekday]?.contains { existingTask in
                    return existingTask.parentRecurringTaskId == task.id &&
                           existingTask.targetDate?.timeIntervalSince1970 == currentDate.timeIntervalSince1970
                } ?? false
            }

            if !existingInstanceExists {
                let newInstance = TaskItem(
                    title: task.title,
                    weekday: newWeekday,
                    scheduledTime: task.scheduledTime,
                    targetDate: currentDate,
                    isRecurring: false,  // Instances are not recurring themselves
                    recurrenceFrequency: nil,
                    parentRecurringTaskId: task.id
                )

                // Add to appropriate weekday
                await MainActor.run {
                    if tasks[newWeekday] == nil {
                        tasks[newWeekday] = []
                    }
                    tasks[newWeekday]?.append(newInstance)
                }

                // Sync to Supabase
                await saveTaskToSupabase(newInstance)
            } else {
                print("⚠️ Skipping duplicate instance for \(currentDate)")
            }
        }
    }

    func getTasks(for weekday: WeekDay) -> [TaskItem] {
        return (tasks[weekday] ?? []).filter { !$0.isDeleted }
    }

    func getTasksForDate(_ date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        // Get the weekday from the date
        let weekdayComponent = calendar.component(.weekday, from: date)
        guard let weekday = weekdayFromCalendarComponent(weekdayComponent) else {
            return []
        }

        // Get all tasks that should appear on this specific date
        let allTasks = tasks.values.flatMap { $0 }
        let recurringTasks = allTasks.filter { $0.isRecurring }

        if !recurringTasks.isEmpty {
        }

        let filteredTasks = allTasks.filter { task in
            // First filter out deleted tasks
            guard !task.isDeleted else { return false }

            // For recurring tasks, use the recurring logic
            if task.isRecurring {
                let shouldAppear = shouldRecurringTaskAppearOn(task: task, date: targetDate)
                if shouldAppear {
                }
                return shouldAppear
            } else {
                // For non-recurring tasks, check weekday match
                if task.weekday == weekday {
                    if let taskTargetDate = task.targetDate {
                        // For tasks with specific target dates, check if they match the requested date
                        return calendar.isDate(taskTargetDate, inSameDayAs: targetDate)
                    } else {
                        // For tasks without target dates (legacy tasks), check if they belong to the current week
                        let currentWeekDate = weekday.dateForCurrentWeek()
                        return calendar.isDate(currentWeekDate, inSameDayAs: targetDate)
                    }
                }
                return false
            }
        }

        if !recurringTasks.isEmpty {
            print("📋 Returning \(filteredTasks.count) tasks for \(weekday.displayName)")
        }

        return filteredTasks.sorted { task1, task2 in
            // Sort by scheduled time if available, otherwise by creation date
            if let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                return time1 < time2
            } else if task1.scheduledTime != nil {
                return true
            } else if task2.scheduledTime != nil {
                return false
            } else {
                return task1.createdAt < task2.createdAt
            }
        }
    }

    func getTasksForCurrentWeek(for weekday: WeekDay) -> [TaskItem] {
        let calendar = Calendar.current
        let currentWeekDate = weekday.dateForCurrentWeek()

        // Get all tasks that should appear on this specific weekday date
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            // First filter out deleted tasks
            guard !task.isDeleted else { return false }

            // For recurring tasks, use the recurring logic
            if task.isRecurring {
                return shouldRecurringTaskAppearOn(task: task, date: currentWeekDate)
            } else {
                // For non-recurring tasks, use the original logic
                if task.weekday == weekday {
                    if let targetDate = task.targetDate {
                        // For tasks with specific target dates, check if they match the current week's date for this weekday
                        return calendar.isDate(targetDate, inSameDayAs: currentWeekDate)
                    } else {
                        // For tasks without target dates (legacy tasks), include them in the current week
                        return true
                    }
                }
                return false
            }
        }.sorted { task1, task2 in
            // Sort by scheduled time if available, otherwise by creation date
            if let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                return time1 < time2
            } else if task1.scheduledTime != nil {
                return true
            } else if task2.scheduledTime != nil {
                return false
            } else {
                return task1.createdAt < task2.createdAt
            }
        }
    }

    func getTasksForToday() -> [TaskItem] {
        let calendar = Calendar.current
        let today = Date()

        // Get all tasks that should appear today (including recurring tasks)
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            // First filter out deleted tasks
            guard !task.isDeleted else { return false }

            // For recurring tasks, use the recurring logic
            if task.isRecurring {
                return shouldRecurringTaskAppearOn(task: task, date: today)
            } else {
                // For non-recurring tasks, use the original logic
                let todayWeekdayComponent = calendar.component(.weekday, from: today)
                guard let todayWeekday = weekdayFromCalendarComponent(todayWeekdayComponent),
                      task.weekday == todayWeekday else {
                    return false
                }

                if let targetDate = task.targetDate {
                    // For tasks with specific target dates, check if they match today
                    return calendar.isDate(targetDate, inSameDayAs: today)
                } else {
                    // For tasks without target dates (legacy tasks), check if they belong to today's week
                    let currentWeekDate = todayWeekday.dateForCurrentWeek()
                    return calendar.isDate(currentWeekDate, inSameDayAs: today)
                }
            }
        }.sorted { task1, task2 in
            // Sort by scheduled time if available, otherwise by creation date
            if let time1 = task1.scheduledTime, let time2 = task2.scheduledTime {
                return time1 < time2
            } else if task1.scheduledTime != nil {
                return true
            } else if task2.scheduledTime != nil {
                return false
            } else {
                return task1.createdAt < task2.createdAt
            }
        }
    }

    func getCompletedTasks(for date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            guard !task.isDeleted else { return false }

            // For recurring tasks, check if completed on this specific date
            if task.isRecurring {
                return task.isCompletedOn(date: date)
            }

            // For non-recurring tasks, check completion date as before
            guard task.isCompleted, let completedDate = task.completedDate else { return false }
            return calendar.isDate(completedDate, inSameDayAs: date)
        }.sorted { task1, task2 in
            // For recurring tasks, they don't have a specific completion date to sort by
            // So just sort by creation date
            if task1.isRecurring || task2.isRecurring {
                return task1.createdAt > task2.createdAt
            }

            guard let date1 = task1.completedDate,
                  let date2 = task2.completedDate else { return false }
            return date1 > date2 // Most recent first
        }
    }

    func getAllTasks(for date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            guard !task.isDeleted else { return false }

            // Check if task should appear on this date
            let shouldAppear: Bool
            if task.isRecurring {
                shouldAppear = shouldRecurringTaskAppearOn(task: task, date: date)
            } else {
                // For regular tasks, check target date if available, otherwise use weekday matching
                if let targetDate = task.targetDate {
                    shouldAppear = calendar.isDate(targetDate, inSameDayAs: date)
                } else {
                    // Fallback to weekday matching for tasks without target dates
                    let weekdayComponent = calendar.component(.weekday, from: date)
                    if let targetWeekday = weekdayFromCalendarComponent(weekdayComponent) {
                        shouldAppear = task.weekday == targetWeekday
                    } else {
                        shouldAppear = false
                    }
                }
            }

            return shouldAppear
        }.sorted { task1, task2 in
            // Check completion status for this specific date
            let isCompleted1 = task1.isCompletedOn(date: date)
            let isCompleted2 = task2.isCompletedOn(date: date)

            // Sort completed tasks first
            if isCompleted1 != isCompleted2 {
                return isCompleted1 && !isCompleted2
            }

            // Then by creation date
            return task1.createdAt > task2.createdAt
        }
    }

    private func shouldRecurringTaskAppearOn(task: TaskItem, date: Date) -> Bool {
        guard task.isRecurring,
              let frequency = task.recurrenceFrequency else { return false }

        let calendar = Calendar.current
        // Use targetDate if available (for tasks with specific start dates), otherwise use createdAt
        let taskStartDate = task.targetDate ?? task.createdAt
        let startDate = calendar.startOfDay(for: taskStartDate)
        let targetDate = calendar.startOfDay(for: date)

        // Don't show tasks before their start date
        guard targetDate >= startDate else { return false }

        // Check if the task is within its recurrence end date
        if let endDate = task.recurrenceEndDate, targetDate > endDate {
            return false
        }

        let daysDifference = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0

        switch frequency {
        case .daily:
            // Daily tasks appear every day (not just the original weekday)
            // Simply check if we're on or after the start date
            return daysDifference >= 0
        case .weekly:
            // Weekly tasks appear on the same weekday every week
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }
            // For weekly tasks, check if it's a multiple of 7 days from the start (including day 0 = original day)
            return daysDifference >= 0 && daysDifference % 7 == 0
        case .biweekly:
            // Bi-weekly tasks appear on the same weekday every 2 weeks
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }
            // For bi-weekly tasks, check if it's a multiple of 14 days from the start (including day 0 = original day)
            return daysDifference >= 0 && daysDifference % 14 == 0
        case .monthly:
            // Monthly tasks appear on the same weekday of the month
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }

            // For monthly tasks, check if this is the same weekday and appears on the same occurrence in the month
            // For example, if the original was "2nd Monday of the month", check for 2nd Monday of each month
            let startWeekOfMonth = calendar.component(.weekOfMonth, from: startDate)
            let dateWeekOfMonth = calendar.component(.weekOfMonth, from: targetDate)

            // Also check that we're at least in the same month as the original task or later
            return daysDifference >= 0 && startWeekOfMonth == dateWeekOfMonth
        case .yearly:
            // Yearly tasks appear on the same date every year
            let startMonth = calendar.component(.month, from: startDate)
            let startDay = calendar.component(.day, from: startDate)
            let targetMonth = calendar.component(.month, from: targetDate)
            let targetDay = calendar.component(.day, from: targetDate)

            // Check if the month and day match
            return daysDifference >= 0 && startMonth == targetMonth && startDay == targetDay
        }
    }


    func getCompletedTasks(between startDate: Date, endDate: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let allTasks = tasks.values.flatMap { $0 }

        var completedTasksInRange: [TaskItem] = []

        for task in allTasks {
            guard !task.isDeleted else { continue }

            if task.isRecurring {
                // For recurring tasks, check each date in the range
                var currentDate = calendar.startOfDay(for: startDate)
                let end = calendar.startOfDay(for: endDate)

                while currentDate <= end {
                    if task.isCompletedOn(date: currentDate) {
                        // Add this task once for the range (don't duplicate)
                        if !completedTasksInRange.contains(where: { $0.id == task.id }) {
                            completedTasksInRange.append(task)
                        }
                        break
                    }
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                }
            } else {
                // For non-recurring tasks, check completion date
                if task.isCompleted, let completedDate = task.completedDate {
                    if completedDate >= startDate && completedDate <= endDate {
                        completedTasksInRange.append(task)
                    }
                }
            }
        }

        return completedTasksInRange.sorted { task1, task2 in
            if task1.isRecurring || task2.isRecurring {
                return task1.createdAt > task2.createdAt
            }

            guard let date1 = task1.completedDate,
                  let date2 = task2.completedDate else { return false }
            return date1 > date2 // Most recent first
        }
    }

    func getAllCompletedTasks() -> [TaskItem] {
        let allTasks = tasks.values.flatMap { $0 }
        return allTasks.filter { $0.isCompleted }.sorted { task1, task2 in
            guard let date1 = task1.completedDate,
                  let date2 = task2.completedDate else { return false }
            return date1 > date2 // Most recent first
        }
    }

    func makeTaskRecurring(_ task: TaskItem, frequency: RecurrenceFrequency) {

        // First, make the original task recurring
        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else {
            print("❌ Could not find task to make recurring")
            return
        }

        // Check if task is already recurring
        if tasks[task.weekday]?[index].isRecurring == true {
            print("⚠️ Task is already recurring")
            return // Already recurring, don't create duplicates
        }

        // Ensure the original task has a target date set to current week
        if tasks[task.weekday]?[index].targetDate == nil {
            tasks[task.weekday]?[index].targetDate = task.weekday.dateForCurrentWeek()
        }

        // Mark the original task as recurring
        tasks[task.weekday]?[index].isRecurring = true
        tasks[task.weekday]?[index].recurrenceFrequency = frequency
        tasks[task.weekday]?[index].recurrenceEndDate = Calendar.current.date(byAdding: .year, value: 10, to: Date())

        print("   - isRecurring: \(tasks[task.weekday]?[index].isRecurring ?? false)")
        print("   - frequency: \(tasks[task.weekday]?[index].recurrenceFrequency?.rawValue ?? "nil")")
        print("   - targetDate: \(tasks[task.weekday]?[index].targetDate?.description ?? "nil")")

        // Note: The recurring logic in shouldRecurringTaskAppearOn will dynamically display
        // this task on the appropriate days based on the frequency. We don't need to
        // create duplicate instances since the display logic handles it automatically.

        saveTasks()
        print("💾 Task saved to local storage")

        // Sync the updated task to Supabase
        if let updatedTask = tasks[task.weekday]?[index] {
            Task {
                await updateTaskInSupabase(updatedTask)
                print("☁️ Task synced to Supabase")
            }
        }
    }

    private func generateRecurringInstances(for task: TaskItem, frequency: RecurrenceFrequency, parentTaskId: String) {
        let calendar = Calendar.current
        let startDate = task.createdAt
        let endDate = calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate

        switch frequency {
        case .daily:
            generateDailyTasks(for: task, parentTaskId: parentTaskId, from: startDate, to: endDate)
        case .weekly:
            generateWeeklyTasks(for: task, parentTaskId: parentTaskId, from: startDate, to: endDate)
        case .biweekly:
            generateBiweeklyTasks(for: task, parentTaskId: parentTaskId, from: startDate, to: endDate)
        case .monthly:
            generateMonthlyTasks(for: task, parentTaskId: parentTaskId, from: startDate, to: endDate)
        case .yearly:
            generateYearlyTasks(for: task, parentTaskId: parentTaskId, from: startDate, to: endDate)
        }
    }

    private func generateDailyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For daily tasks, we don't need to create individual instances
        // The logic will be handled dynamically in shouldRecurringTaskAppearOn
        // This prevents duplicate tasks from being created
    }

    private func generateWeeklyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For weekly tasks, we don't need to create individual instances
        // The logic will be handled dynamically in shouldRecurringTaskAppearOn
        // This prevents duplicate tasks from being created
    }

    private func generateBiweeklyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For bi-weekly tasks, we don't need to create individual instances
        // The logic will be handled dynamically in shouldRecurringTaskAppearOn
        // This prevents duplicate tasks from being created
    }

    private func generateMonthlyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For monthly tasks, we don't need to create individual instances
        // The logic will be handled dynamically in shouldRecurringTaskAppearOn
        // This prevents duplicate tasks from being created
    }

    private func generateYearlyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For yearly tasks, we don't need to create individual instances
        // The logic will be handled dynamically in shouldRecurringTaskAppearOn
        // This prevents duplicate tasks from being created
    }

    private func weekdayFromCalendarComponent(_ component: Int) -> WeekDay? {
        switch component {
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


    func deleteRecurringTask(_ task: TaskItem) {
        if task.isRecurring {
            // Delete the original task and all its instances
            deleteTaskAndInstances(with: task.id)
        } else if let parentId = task.parentRecurringTaskId {
            // Delete all instances of this recurring task
            deleteTaskAndInstances(with: parentId)
        } else {
            // Regular delete
            deleteTask(task)
        }
    }

    private func deleteTaskAndInstances(with parentId: String) {
        // Collect all tasks that will be deleted
        var tasksToDelete: [TaskItem] = []
        for weekday in WeekDay.allCases {
            let weekdayTasks = tasks[weekday] ?? []
            tasksToDelete.append(contentsOf: weekdayTasks.filter { task in
                task.id == parentId || task.parentRecurringTaskId == parentId
            })
        }

        // Delete from Supabase first
        Task {
            var allDeleted = true
            for task in tasksToDelete {
                let success = await deleteTaskFromSupabase(task.id)
                if !success {
                    allDeleted = false
                }
            }

            await MainActor.run {
                if allDeleted {
                    // Only remove locally if all Supabase deletions succeeded
                    for weekday in WeekDay.allCases {
                        tasks[weekday]?.removeAll { task in
                            task.id == parentId || task.parentRecurringTaskId == parentId
                        }
                    }
                    saveTasks()
                } else {
                    print("❌ Some deletions failed in Supabase, keeping tasks locally")
                }
            }
        }
    }

    private func saveTasks() {
        let allTasks = tasks.values.flatMap { $0 }
        if let encoded = try? JSONEncoder().encode(allTasks) {
            userDefaults.set(encoded, forKey: tasksKey)
        }
    }

    private func loadTasks() {
        guard let data = userDefaults.data(forKey: tasksKey),
              let savedTasks = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            print("📂 No saved tasks found in local storage, adding sample tasks")
            addSampleTasks()
            return
        }

        print("📂 Loading \(savedTasks.count) tasks from local storage")

        // Fix any recurring tasks that were accidentally marked as completed
        let fixedTasks = savedTasks.map { task -> TaskItem in
            var fixedTask = task
            if task.isRecurring && task.isCompleted {
                print("🔧 FIXING: Recurring task '\(task.title)' was marked complete - setting to incomplete")
                fixedTask.isCompleted = false
                fixedTask.completedDate = nil
            }
            return fixedTask
        }

        var tasksByWeekday: [WeekDay: [TaskItem]] = [:]
        for weekday in WeekDay.allCases {
            tasksByWeekday[weekday] = fixedTasks.filter { $0.weekday == weekday }
        }

        // Debug: Print recurring tasks
        let recurringTasks = fixedTasks.filter { $0.isRecurring }
        if !recurringTasks.isEmpty {
            for task in recurringTasks {
                print("   - '\(task.title)': \(task.recurrenceFrequency?.rawValue ?? "nil"), isCompleted: \(task.isCompleted)")
            }
        }

        self.tasks = tasksByWeekday
        initializeEmptyDays()

        // Save the fixed tasks back to storage if any were fixed
        let tasksToFix = fixedTasks.filter { task in
            savedTasks.first(where: { $0.id == task.id })?.isCompleted != task.isCompleted
        }

        if !tasksToFix.isEmpty {
            print("💾 Saving \(tasksToFix.count) fixed recurring tasks to local storage")
            saveTasks()

            // Also sync fixes to Supabase
            Task {
                for task in tasksToFix {
                    print("☁️ Syncing fixed recurring task '\(task.title)' to Supabase")
                    await updateTaskInSupabase(task)
                }
            }
        }
    }

    private func addSampleTasks() {
        addTask(title: "Gym run", to: .monday)
        addTask(title: "Read 10 pages", to: .monday)
        addTask(title: "Walk the dog", to: .monday)
        addTask(title: "Get groceries", to: .monday)
        addTask(title: "Design a to-do app (?)", to: .monday)

        // Mark the first task as completed and set completion date to today
        if tasks[.monday]?.first != nil {
            tasks[.monday]?[0].isCompleted = true
            tasks[.monday]?[0].completedDate = Date()
        }
    }

    // MARK: - Supabase Integration

    func loadTasksFromSupabase() async {
        guard authManager.isAuthenticated,
              let userId = authManager.supabaseUser?.id else {
            print("User not authenticated, loading local tasks only")
            return
        }

        do {
            let client = await supabaseManager.getPostgrestClient()
            let response = try await client
                .from("tasks")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .execute()

            let data = response.data
            if data.isEmpty {
                print("No tasks data received from Supabase")
                return
            }

            // Parse the response data into TaskItem objects
            if let tasksArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                var supabaseTasks: [TaskItem] = []

                for taskDict in tasksArray {
                    if let taskItem = parseTaskFromSupabase(taskDict) {
                        print("📥 Loaded task: '\(taskItem.title)' on \(taskItem.weekday), isRecurring: \(taskItem.isRecurring), frequency: \(taskItem.recurrenceFrequency?.rawValue ?? "nil"), targetDate: \(taskItem.targetDate?.description ?? "nil")")
                        supabaseTasks.append(taskItem)
                    }
                }

                // Update local tasks with Supabase data
                await MainActor.run {
                    var tasksByWeekday: [WeekDay: [TaskItem]] = [:]
                    for weekday in WeekDay.allCases {
                        tasksByWeekday[weekday] = supabaseTasks.filter { $0.weekday == weekday }
                    }

                    // Debug: Print recurring tasks loaded from Supabase
                    let recurringTasks = supabaseTasks.filter { $0.isRecurring }
                    if !recurringTasks.isEmpty {
                        for task in recurringTasks {
                            print("   - '\(task.title)': \(task.recurrenceFrequency?.rawValue ?? "nil"), isCompleted: \(task.isCompleted), targetDate: \(task.targetDate?.description ?? "nil")")
                        }
                    }

                    self.tasks = tasksByWeekday
                    initializeEmptyDays()

                    // IMPORTANT: Save loaded tasks to local cache so they persist across rebuilds
                    // This ensures email attachments and all data are available even if Supabase is unreachable
                    self.saveTasks()
                    print("💾 Cached \(supabaseTasks.count) tasks from Supabase to local storage")

                    // Check if any recurring tasks were fixed (marked incomplete)
                    let originalTasksArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
                    let tasksNeedingFix = supabaseTasks.filter { task in
                        if let originalArray = originalTasksArray,
                           let originalTask = originalArray.first(where: { ($0["id"] as? String) == task.id }),
                           let wasCompleted = originalTask["is_completed"] as? Bool {
                            return task.isRecurring && wasCompleted && !task.isCompleted
                        }
                        return false
                    }

                    if !tasksNeedingFix.isEmpty {
                        print("☁️ Syncing \(tasksNeedingFix.count) fixed recurring tasks back to Supabase")
                        Task {
                            for task in tasksNeedingFix {
                                await updateTaskInSupabase(task)
                            }
                        }
                    }
                }
            }

        } catch {
            print("❌ Failed to load tasks from Supabase: \(error)")
        }
    }

    private func parseTaskFromSupabase(_ taskDict: [String: Any]) -> TaskItem? {
        guard let id = taskDict["id"] as? String,
              let title = taskDict["title"] as? String,
              let isCompleted = taskDict["is_completed"] as? Bool,
              let weekdayString = taskDict["weekday"] as? String,
              let weekday = WeekDay(rawValue: weekdayString),
              let createdAtString = taskDict["created_at"] as? String,
              let createdAt = ISO8601DateFormatter().date(from: createdAtString) else {
            print("Failed to parse task from Supabase data")
            return nil
        }

        // Parse description
        let description = taskDict["description"] as? String

        var taskItem = TaskItem(title: title, weekday: weekday, description: description)
        taskItem.id = id
        taskItem.createdAt = createdAt

        // Check if this is a recurring task
        if let isRecurring = taskDict["is_recurring"] as? Bool, isRecurring {
            // IMPORTANT: Recurring tasks should NEVER be marked as completed
            // If a recurring task was accidentally marked complete, fix it
            if isCompleted {
                print("🔧 FIXING: Recurring task '\(title)' was marked complete - setting to incomplete")
                taskItem.isCompleted = false
                taskItem.completedDate = nil
            } else {
                taskItem.isCompleted = false
            }
        } else {
            // Regular tasks can be marked complete normally
            taskItem.isCompleted = isCompleted
        }

        // Parse optional fields
        // IMPORTANT: Don't set completed date for recurring tasks
        if !taskItem.isRecurring {
            if let completedDateString = taskDict["completed_date"] as? String {
                taskItem.completedDate = ISO8601DateFormatter().date(from: completedDateString)
            }
        }

        if let isRecurring = taskDict["is_recurring"] as? Bool {
            taskItem.isRecurring = isRecurring
        }

        if let frequencyString = taskDict["recurrence_frequency"] as? String {
            taskItem.recurrenceFrequency = RecurrenceFrequency(rawValue: frequencyString)
        }

        if let endDateString = taskDict["recurrence_end_date"] as? String {
            taskItem.recurrenceEndDate = ISO8601DateFormatter().date(from: endDateString)
        }

        if let parentId = taskDict["parent_recurring_task_id"] as? String {
            taskItem.parentRecurringTaskId = parentId
        }

        if let scheduledTimeString = taskDict["scheduled_time"] as? String {
            taskItem.scheduledTime = ISO8601DateFormatter().date(from: scheduledTimeString)
        }

        if let endTimeString = taskDict["end_time"] as? String {
            taskItem.endTime = ISO8601DateFormatter().date(from: endTimeString)
        }

        if let targetDateString = taskDict["target_date"] as? String {
            taskItem.targetDate = ISO8601DateFormatter().date(from: targetDateString)
        }

        if let reminderTimeString = taskDict["reminder_time"] as? String {
            taskItem.reminderTime = ReminderTime(rawValue: reminderTimeString)
        }

        // Parse email attachment fields
        if let emailId = taskDict["email_id"] as? String {
            taskItem.emailId = emailId
        }

        if let emailSubject = taskDict["email_subject"] as? String {
            taskItem.emailSubject = emailSubject
        }

        if let emailSenderName = taskDict["email_sender_name"] as? String {
            taskItem.emailSenderName = emailSenderName
        }

        if let emailSenderEmail = taskDict["email_sender_email"] as? String {
            taskItem.emailSenderEmail = emailSenderEmail
        }

        if let emailSnippet = taskDict["email_snippet"] as? String {
            taskItem.emailSnippet = emailSnippet
        }

        if let emailTimestampString = taskDict["email_timestamp"] as? String {
            taskItem.emailTimestamp = ISO8601DateFormatter().date(from: emailTimestampString)
        }

        if let emailBody = taskDict["email_body"] as? String {
            taskItem.emailBody = emailBody
        }

        if let emailIsImportant = taskDict["email_is_important"] as? Bool {
            taskItem.emailIsImportant = emailIsImportant
        }

        // Parse completed dates for recurring tasks
        if let completedDatesJson = taskDict["completed_dates_json"] as? String,
           let jsonData = completedDatesJson.data(using: .utf8),
           let dateStrings = try? JSONDecoder().decode([String].self, from: jsonData) {
            let formatter = ISO8601DateFormatter()
            taskItem.completedDates = dateStrings.compactMap { formatter.date(from: $0) }
        }

        // Note: email_ai_summary column doesn't exist in Supabase yet
        // if let emailAiSummary = taskDict["email_ai_summary"] as? String {
        //     taskItem.emailAiSummary = emailAiSummary
        // }

        // Note: is_deleted field is not in Supabase yet, so it defaults to false
        // if let isDeleted = taskDict["is_deleted"] as? Bool {
        //     taskItem.isDeleted = isDeleted
        // }

        return taskItem
    }

    private func saveTaskToSupabase(_ task: TaskItem) async {
        guard authManager.isAuthenticated,
              let userId = authManager.supabaseUser?.id else {
            print("⚠️ Cannot save task to Supabase: User not authenticated")
            return
        }

        do {
            let taskData = convertTaskToSupabaseFormat(task, userId: userId.uuidString)
            let client = await supabaseManager.getPostgrestClient()

            print("💾 Saving task to Supabase: '\(task.title)' - Recurring: \(task.isRecurring), Frequency: \(task.recurrenceFrequency?.rawValue ?? "none")")

            try await client
                .from("tasks")
                .upsert(taskData)
                .execute()


        } catch {
            print("❌ Failed to save task to Supabase: \(error)")
        }
    }

    private func updateTaskInSupabase(_ task: TaskItem) async {
        guard authManager.isAuthenticated,
              let userId = authManager.supabaseUser?.id else {
            return
        }

        do {
            let taskData = convertTaskToSupabaseFormat(task, userId: userId.uuidString)
            print("📤 Supabase update data: \(taskData)")
            let client = await supabaseManager.getPostgrestClient()

            try await client
                .from("tasks")
                .update(taskData)
                .eq("id", value: task.id)
                .execute()


        } catch {
            print("❌ Failed to update task in Supabase: \(error)")
        }
    }

    private func deleteTaskFromSupabase(_ taskId: String) async -> Bool {
        guard authManager.isAuthenticated else {
            print("❌ User not authenticated, cannot delete from Supabase")
            return false
        }

        do {
            let client = await supabaseManager.getPostgrestClient()
            try await client
                .from("tasks")
                .delete()
                .eq("id", value: taskId)
                .execute()

            return true

        } catch {
            print("❌ Failed to delete task from Supabase: \(error)")
            return false
        }
    }

    private func convertTaskToSupabaseFormat(_ task: TaskItem, userId: String) -> [String: AnyJSON] {
        let formatter = ISO8601DateFormatter()

        // IMPORTANT: Recurring tasks should NEVER be marked as completed
        let isCompleted = task.isRecurring ? false : task.isCompleted
        let completedDate = task.isRecurring ? nil : task.completedDate

        if task.isRecurring && (task.isCompleted || task.completedDate != nil) {
            print("🔧 FIXING: Preventing recurring task '\(task.title)' from being saved as complete")
        }

        var taskData: [String: AnyJSON] = [
            "id": AnyJSON.string(task.id),
            "user_id": AnyJSON.string(userId),
            "title": AnyJSON.string(task.title),
            "is_completed": AnyJSON.bool(isCompleted),
            "weekday": AnyJSON.string(task.weekday.rawValue),
            "created_at": AnyJSON.string(formatter.string(from: task.createdAt)),
            "is_recurring": AnyJSON.bool(task.isRecurring)
            // Note: is_deleted column doesn't exist in Supabase yet, so we don't sync it
        ]

        if let description = task.description {
            taskData["description"] = AnyJSON.string(description)
        } else {
            taskData["description"] = AnyJSON.null
        }

        if let completedDate = completedDate {
            taskData["completed_date"] = AnyJSON.string(formatter.string(from: completedDate))
        } else {
            taskData["completed_date"] = AnyJSON.null
        }

        if let frequency = task.recurrenceFrequency {
            taskData["recurrence_frequency"] = AnyJSON.string(frequency.rawValue)
        } else {
            taskData["recurrence_frequency"] = AnyJSON.null
        }

        if let endDate = task.recurrenceEndDate {
            taskData["recurrence_end_date"] = AnyJSON.string(formatter.string(from: endDate))
        } else {
            taskData["recurrence_end_date"] = AnyJSON.null
        }

        if let parentId = task.parentRecurringTaskId {
            taskData["parent_recurring_task_id"] = AnyJSON.string(parentId)
        } else {
            taskData["parent_recurring_task_id"] = AnyJSON.null
        }

        if let scheduledTime = task.scheduledTime {
            taskData["scheduled_time"] = AnyJSON.string(formatter.string(from: scheduledTime))
        } else {
            taskData["scheduled_time"] = AnyJSON.null
        }

        if let endTime = task.endTime {
            taskData["end_time"] = AnyJSON.string(formatter.string(from: endTime))
        } else {
            taskData["end_time"] = AnyJSON.null
        }

        if let targetDate = task.targetDate {
            taskData["target_date"] = AnyJSON.string(formatter.string(from: targetDate))
        } else {
            taskData["target_date"] = AnyJSON.null
        }

        if let reminderTime = task.reminderTime {
            taskData["reminder_time"] = AnyJSON.string(reminderTime.rawValue)
        } else {
            taskData["reminder_time"] = AnyJSON.null
        }

        // Add email attachment fields
        if let emailId = task.emailId {
            taskData["email_id"] = AnyJSON.string(emailId)
        } else {
            taskData["email_id"] = AnyJSON.null
        }

        if let emailSubject = task.emailSubject {
            taskData["email_subject"] = AnyJSON.string(emailSubject)
        } else {
            taskData["email_subject"] = AnyJSON.null
        }

        if let emailSenderName = task.emailSenderName {
            taskData["email_sender_name"] = AnyJSON.string(emailSenderName)
        } else {
            taskData["email_sender_name"] = AnyJSON.null
        }

        if let emailSenderEmail = task.emailSenderEmail {
            taskData["email_sender_email"] = AnyJSON.string(emailSenderEmail)
        } else {
            taskData["email_sender_email"] = AnyJSON.null
        }

        if let emailSnippet = task.emailSnippet {
            taskData["email_snippet"] = AnyJSON.string(emailSnippet)
        } else {
            taskData["email_snippet"] = AnyJSON.null
        }

        if let emailTimestamp = task.emailTimestamp {
            taskData["email_timestamp"] = AnyJSON.string(formatter.string(from: emailTimestamp))
        } else {
            taskData["email_timestamp"] = AnyJSON.null
        }

        if let emailBody = task.emailBody {
            taskData["email_body"] = AnyJSON.string(emailBody)
        } else {
            taskData["email_body"] = AnyJSON.null
        }

        taskData["email_is_important"] = AnyJSON.bool(task.emailIsImportant)

        // Save completed dates for recurring tasks (as JSON array of ISO8601 strings)
        if !task.completedDates.isEmpty {
            let completedDatesStrings = task.completedDates.map { formatter.string(from: $0) }
            if let jsonData = try? JSONEncoder().encode(completedDatesStrings),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                taskData["completed_dates_json"] = AnyJSON.string(jsonString)
            } else {
                taskData["completed_dates_json"] = AnyJSON.null
            }
        } else {
            taskData["completed_dates_json"] = AnyJSON.null
        }

        // Note: email_ai_summary column doesn't exist in Supabase yet, so we don't sync it
        // if let emailAiSummary = task.emailAiSummary {
        //     taskData["email_ai_summary"] = AnyJSON.string(emailAiSummary)
        // } else {
        //     taskData["email_ai_summary"] = AnyJSON.null
        // }

        return taskData
    }

    // Called when user signs in to load their tasks
    func syncTasksOnLogin() async {
        await loadTasksFromSupabase()
        await retryFailedDeletions()
    }

    // Retry any failed deletions that were marked as deleted locally
    private func retryFailedDeletions() async {
        let allTasks = tasks.values.flatMap { $0 }
        let deletedTasks = allTasks.filter { $0.isDeleted }

        if deletedTasks.isEmpty {
            return
        }


        for task in deletedTasks {
            let success = await deleteTaskFromSupabase(task.id)
            if success {
                // Remove the task completely now that Supabase deletion succeeded
                await MainActor.run {
                    if let weekdayTasks = tasks[task.weekday],
                       let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[task.weekday]?.remove(at: index)
                    }
                }
            }
        }

        await MainActor.run {
            saveTasks()
        }
    }

    // Called when user signs out to clear tasks
    func clearTasksOnLogout() {
        for weekday in WeekDay.allCases {
            tasks[weekday] = []
        }
        saveTasks() // Save empty state locally
    }

    // Debug function to test recurring logic
    func debugRecurringTask() {
        print("🔍 Debug: Testing recurring task logic...")

        // Create a sample task for Monday
        let testTask = TaskItem(title: "Study python 15 mins", weekday: .monday, scheduledTime: nil, targetDate: WeekDay.monday.dateForCurrentWeek(), isRecurring: true, recurrenceFrequency: .daily)

        // Test if it appears on different days
        let _ = Calendar.current
        for weekday in WeekDay.allCases {
            let date = weekday.dateForCurrentWeek()
            _ = shouldRecurringTaskAppearOn(task: testTask, date: date)
        }
    }

    // MARK: - Notification Scheduling
    private func scheduleReminder(for task: TaskItem, at scheduledTime: Date, reminderBefore: ReminderTime) {
        // Calculate the reminder time
        let reminderDate = Calendar.current.date(byAdding: .minute, value: -reminderBefore.minutes, to: scheduledTime)

        guard let reminderDate = reminderDate, reminderDate > Date() else {
            print("⏰ Reminder time is in the past, skipping notification")
            return
        }

        // Format the event time for the notification body
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let eventTimeString = timeFormatter.string(from: scheduledTime)

        let body = "Starts at \(eventTimeString)"

        // Use the notification service to schedule
        Task {
            await NotificationService.shared.scheduleTaskReminder(
                taskId: task.id,
                title: task.title,
                body: body,
                scheduledTime: reminderDate
            )
        }
    }

    // MARK: - Stats Methods

    /// Get all completed events for a specific month
    func getCompletedEventsForMonth(_ date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return []
        }

        let allTasks = tasks.values.flatMap { $0 }
        return allTasks.filter { task in
            guard !task.isDeleted,
                  task.isCompleted,
                  let completedDate = task.completedDate else { return false }
            return completedDate >= monthStart && completedDate <= monthEnd
        }.sorted { task1, task2 in
            guard let date1 = task1.completedDate,
                  let date2 = task2.completedDate else { return false }
            return date1 > date2
        }
    }

    /// Get monthly event breakdown (total, completed, incomplete)
    func getMonthlyEventBreakdown(_ date: Date) -> (total: Int, completed: Int, incomplete: Int) {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let nextMonthStart = calendar.date(byAdding: DateComponents(month: 1), to: monthStart),
              let monthEnd = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) else {
            return (0, 0, 0)
        }

        let allTasks = tasks.values.flatMap { $0 }
        var totalCount = 0
        var completedCount = 0

        // Iterate through all tasks and count instances in this month
        for task in allTasks {
            guard !task.isDeleted else { continue }

            if task.isRecurring {
                // For recurring tasks, check each date in the month
                var currentDate = monthStart
                while currentDate <= monthEnd {
                    if shouldRecurringTaskAppearOn(task: task, date: currentDate) {
                        totalCount += 1
                        if task.isCompletedOn(date: currentDate) {
                            completedCount += 1
                        }
                    }
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                }
            } else {
                // For non-recurring tasks, check if scheduled/targeted or completed in this month
                var includeTask = false

                // Include if completed in this month
                if task.isCompleted, let completedDate = task.completedDate {
                    if completedDate >= monthStart && completedDate <= monthEnd {
                        includeTask = true
                    }
                }

                // Include if scheduled/targeted for this month
                if let targetDate = task.targetDate {
                    if targetDate >= monthStart && targetDate <= monthEnd {
                        includeTask = true
                    }
                }

                if includeTask {
                    totalCount += 1
                    if task.isCompleted {
                        completedCount += 1
                    }
                }
            }
        }

        let incomplete = totalCount - completedCount
        return (totalCount, completedCount, incomplete)
    }

    /// Get recurring events stats (completed vs incomplete to date)
    func getRecurringEventsStats() -> (completed: Int, incomplete: Int, totalInstances: Int) {
        let allTasks = tasks.values.flatMap { $0 }
        let today = Calendar.current.startOfDay(for: Date())

        // Get all recurring events that should have occurred by now
        var completedCount = 0
        var incompleteCount = 0
        var totalInstancesCount = 0

        // Track parent recurring tasks we've already processed
        var processedParents: Set<String> = []

        for task in allTasks {
            guard !task.isDeleted else { continue }

            // Process main recurring tasks
            if task.isRecurring {
                // Avoid double counting
                if processedParents.contains(task.id) { continue }
                processedParents.insert(task.id)

                // Count instances of this recurring task that should have occurred by now
                let instancesUpToToday = countRecurringInstances(task: task, upToDate: today)
                totalInstancesCount += instancesUpToToday

                // Count completed instances
                let completedInstances = allTasks.filter { relatedTask in
                    // Check if this is the parent task itself or an instance of it
                    let isRelated = (relatedTask.id == task.id || relatedTask.parentRecurringTaskId == task.id)
                    let isCompletedBeforeToday = relatedTask.isCompleted &&
                                                 (relatedTask.targetDate ?? relatedTask.createdAt) <= today
                    return isRelated && isCompletedBeforeToday && !relatedTask.isDeleted
                }.count

                completedCount += completedInstances
                incompleteCount += (instancesUpToToday - completedInstances)
            }
        }

        return (completedCount, incompleteCount, totalInstancesCount)
    }

    /// Count how many instances of a recurring task should have occurred up to a given date
    private func countRecurringInstances(task: TaskItem, upToDate: Date) -> Int {
        guard task.isRecurring,
              let frequency = task.recurrenceFrequency else { return 0 }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: task.targetDate ?? task.createdAt)
        let endDate = calendar.startOfDay(for: upToDate)

        guard endDate >= startDate else { return 0 }

        let daysDifference = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        switch frequency {
        case .daily:
            return daysDifference + 1 // Include the start day
        case .weekly:
            return (daysDifference / 7) + 1
        case .biweekly:
            return (daysDifference / 14) + 1
        case .monthly:
            let monthsDifference = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0
            return monthsDifference + 1
        case .yearly:
            let yearsDifference = calendar.dateComponents([.year], from: startDate, to: endDate).year ?? 0
            return yearsDifference + 1
        }
    }

    // MARK: - Advanced Stats Methods for Recurring Events

    /// Get missed recurring events for a specific week
    func getMissedRecurringEventsForWeek(_ weekStartDate: Date) -> WeeklyMissedEventSummary {
        let calendar = Calendar.current
        let weekEndDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
        let allTasks = tasks.values.flatMap { $0 }

        var missedEvents: [WeeklyMissedEventSummary.MissedEventDetail] = []
        var processedParents: Set<String> = []

        for task in allTasks {
            guard !task.isDeleted, task.isRecurring else { continue }

            // Avoid double counting
            if processedParents.contains(task.id) { continue }
            processedParents.insert(task.id)

            // Count instances expected in this week
            var expectedCount = 0
            var missedCount = 0

            var currentDate = weekStartDate
            while currentDate <= weekEndDate {
                if shouldRecurringTaskAppearOn(task: task, date: currentDate) {
                    expectedCount += 1

                    // Check if completed on this specific date using the new per-date tracking
                    let wasCompleted = task.isCompletedOn(date: currentDate)

                    if !wasCompleted {
                        missedCount += 1
                    }
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }

            if missedCount > 0 {
                let detail = WeeklyMissedEventSummary.MissedEventDetail(
                    id: task.id,
                    eventName: task.title,
                    frequency: task.recurrenceFrequency ?? .daily,
                    missedCount: missedCount,
                    expectedCount: expectedCount
                )
                missedEvents.append(detail)
            }
        }

        let totalMissed = missedEvents.reduce(0) { $0 + $1.missedCount }

        return WeeklyMissedEventSummary(
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            missedEvents: missedEvents,
            totalMissedCount: totalMissed
        )
    }

    /// Get comprehensive monthly summary - shows what was actually completed
    func getMonthlySummary(_ date: Date) -> MonthlySummary {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let nextMonthStart = calendar.date(byAdding: DateComponents(month: 1), to: monthStart),
              let monthEnd = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) else {
            return MonthlySummary(
                monthDate: date,
                totalEvents: 0,
                completedEvents: 0,
                incompleteEvents: 0,
                completionRate: 0.0,
                recurringCompletedCount: 0,
                recurringMissedCount: 0,
                oneTimeCompletedCount: 0,
                topCompletedEvents: []
            )
        }

        let allTasks = tasks.values.flatMap { $0 }
        var completedTaskInstances: [(task: TaskItem, date: Date)] = []

        // Iterate through all tasks and count completed instances in this month
        for task in allTasks {
            guard !task.isDeleted else { continue }

            if task.isRecurring {
                // For recurring tasks, check each date in the month
                var currentDate = monthStart
                while currentDate <= monthEnd {
                    if shouldRecurringTaskAppearOn(task: task, date: currentDate) && task.isCompletedOn(date: currentDate) {
                        completedTaskInstances.append((task, currentDate))
                    }
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                }
            } else {
                // For non-recurring tasks, check if completed in this month
                if task.isCompleted, let completedDate = task.completedDate {
                    if completedDate >= monthStart && completedDate <= monthEnd {
                        completedTaskInstances.append((task, completedDate))
                    }
                }
            }
        }

        // Separate recurring from one-time based on completed instances
        let recurringCompleted = completedTaskInstances.filter { $0.task.isRecurring }.count
        let oneTimeCompleted = completedTaskInstances.filter { !$0.task.isRecurring }.count

        // Group by title and count occurrences for top events
        var eventCounts: [String: Int] = [:]
        for instance in completedTaskInstances {
            eventCounts[instance.task.title, default: 0] += 1
        }

        // Sort by count and get top 5
        let topEvents = eventCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        let totalCompleted = completedTaskInstances.count

        return MonthlySummary(
            monthDate: date,
            totalEvents: totalCompleted, // Just show completed count
            completedEvents: totalCompleted,
            incompleteEvents: 0, // Not tracking incomplete for this simple view
            completionRate: 1.0, // 100% of what we're showing is completed
            recurringCompletedCount: recurringCompleted,
            recurringMissedCount: 0, // Not tracking missed in this simple view
            oneTimeCompletedCount: oneTimeCompleted,
            topCompletedEvents: Array(topEvents)
        )
    }

    /// Get detailed recurring event breakdown for a specific month
    /// Only includes daily, weekly, and biweekly events
    func getRecurringEventBreakdownForMonth(_ date: Date) -> [RecurringEventStat] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let nextMonthStart = calendar.date(byAdding: DateComponents(month: 1), to: monthStart),
              let monthEnd = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) else {
            return []
        }

        let allTasks = tasks.values.flatMap { $0 }
        var stats: [RecurringEventStat] = []
        var processedParents: Set<String> = []

        for task in allTasks {
            guard !task.isDeleted, task.isRecurring else { continue }

            // Filter for only daily, weekly, and biweekly events
            guard let frequency = task.recurrenceFrequency,
                  (frequency == .daily || frequency == .weekly || frequency == .biweekly) else {
                continue
            }

            // Avoid double counting
            if processedParents.contains(task.id) { continue }
            processedParents.insert(task.id)

            // Count expected instances in this month
            var expectedCount = 0
            var completedCount = 0
            var missedDates: [Date] = []

            var currentDate = monthStart
            while currentDate <= monthEnd {
                if shouldRecurringTaskAppearOn(task: task, date: currentDate) {
                    expectedCount += 1

                    // Check if completed on this specific date using the new per-date tracking
                    let wasCompleted = task.isCompletedOn(date: currentDate)

                    if wasCompleted {
                        completedCount += 1
                    } else {
                        // Only add to missed dates if the date is in the past
                        if currentDate <= Date() {
                            missedDates.append(currentDate)
                        }
                    }
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }

            if expectedCount > 0 {
                let stat = RecurringEventStat(
                    id: task.id,
                    eventName: task.title,
                    frequency: frequency,
                    expectedCount: expectedCount,
                    completedCount: completedCount,
                    missedDates: missedDates
                )
                stats.append(stat)
            }
        }

        return stats.sorted { $0.eventName < $1.eventName }
    }
}