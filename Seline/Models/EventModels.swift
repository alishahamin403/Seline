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

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Repeats every day"
        case .weekly: return "Repeats every week"
        case .biweekly: return "Repeats every 2 weeks"
        case .monthly: return "Repeats every month"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .biweekly: return "calendar.badge.plus"
        case .monthly: return "calendar.circle"
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
    var isCompleted: Bool
    var completedDate: Date?
    let weekday: WeekDay
    var createdAt: Date
    var isRecurring: Bool
    var recurrenceFrequency: RecurrenceFrequency?
    var recurrenceEndDate: Date?
    var parentRecurringTaskId: String? // For tracking which recurring task this belongs to
    var scheduledTime: Date?
    var targetDate: Date? // Specific date this task is intended for
    var reminderTime: ReminderTime? // When to remind the user
    var isDeleted: Bool = false // Flag for soft deletion when Supabase deletion fails

    init(title: String, weekday: WeekDay, scheduledTime: Date? = nil, targetDate: Date? = nil, reminderTime: ReminderTime? = nil, isRecurring: Bool = false, recurrenceFrequency: RecurrenceFrequency? = nil, parentRecurringTaskId: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.isCompleted = false
        self.completedDate = nil
        self.weekday = weekday
        self.createdAt = Date()
        self.scheduledTime = scheduledTime
        self.targetDate = targetDate
        self.reminderTime = reminderTime
        self.isRecurring = isRecurring
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceEndDate = isRecurring ? Calendar.current.date(byAdding: .year, value: 1, to: Date()) : nil
        self.parentRecurringTaskId = parentRecurringTaskId
    }

    var formattedTime: String {
        guard let scheduledTime = scheduledTime else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: scheduledTime)
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

    func addTask(title: String, to weekday: WeekDay, scheduledTime: Date? = nil, targetDate: Date? = nil, reminderTime: ReminderTime? = nil) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Use provided target date, or default to the current week's date for this weekday
        let finalTargetDate = targetDate ?? weekday.dateForCurrentWeek()
        let newTask = TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), weekday: weekday, scheduledTime: scheduledTime, targetDate: finalTargetDate, reminderTime: reminderTime)
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

    func toggleTaskCompletion(_ task: TaskItem) {
        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else { return }

        tasks[task.weekday]?[index].isCompleted.toggle()

        // Set or clear completion date
        if tasks[task.weekday]?[index].isCompleted == true {
            tasks[task.weekday]?[index].completedDate = Date()
        } else {
            tasks[task.weekday]?[index].completedDate = nil
        }

        saveTasks()

        // Sync with Supabase
        if let updatedTask = tasks[task.weekday]?[index] {
            Task {
                await updateTaskInSupabase(updatedTask)
            }
        }
    }

    func deleteTask(_ task: TaskItem) {
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
                    print("✅ Task deleted successfully from both Supabase and local storage")
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
        print("🔄 Editing task: '\(task.title)' -> '\(newTitle)'")
        print("🔄 Date change: \(task.targetDate?.description ?? "nil") -> \(newDate.description)")

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
            print("🔄 Moving task from \(task.weekday) to \(newWeekday)")
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
        print("✅ Task saved locally")

        // Trigger UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        // Sync with Supabase
        let taskToSync = newWeekday != task.weekday ?
            tasks[newWeekday]?.first(where: { $0.id == task.id }) ?? updatedTask :
            updatedTask

        print("🔄 Syncing to Supabase: '\(taskToSync.title)' on \(taskToSync.weekday)")

        Task {
            await updateTaskInSupabase(taskToSync)
        }
    }

    func editTask(_ updatedTask: TaskItem) {
        print("🔄 Editing task: '\(updatedTask.title)'")
        print("🔄 Recurring: \(updatedTask.isRecurring), Frequency: \(updatedTask.recurrenceFrequency?.rawValue ?? "none")")

        guard let weekdayTasks = tasks[updatedTask.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == updatedTask.id }) else {
            print("❌ Could not find task to edit")
            return
        }

        let originalTask = weekdayTasks[index]

        // Handle conversion from recurring to single event
        if originalTask.isRecurring && !updatedTask.isRecurring {
            print("🔄 Converting recurring task to single event")
            // Remove this specific instance from all recurring instances
            // Keep only this one instance as a single event
            removeAllRecurringInstances(originalTask)
        }

        // Handle conversion from single event to recurring
        if !originalTask.isRecurring && updatedTask.isRecurring {
            print("🔄 Converting single event to recurring task")
            // This will create new instances based on the recurrence frequency
        }

        // Handle updates to existing recurring tasks (title, time, date changes only)
        if originalTask.isRecurring && updatedTask.isRecurring {
            print("🔄 Updating recurring task and all its instances")
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
                print("🔄 Moving task from \(updatedTask.weekday) to \(newWeekday)")
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
        print("✅ Task updated locally")

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
        print("🔄 Syncing updated task to Supabase")
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
        print("🔄 Updating main recurring task and all instances")

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
                    print("✅ Updated main recurring task: \(updatedMainTask.title)")
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
                    print("✅ Updated instance: \(updatedInstance.title) on \(weekday)")
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

        print("✅ Updated \(updatedTasks.count) recurring tasks and instances")
    }



    private func createRecurringInstances(for task: TaskItem, frequency: RecurrenceFrequency) async {
        // Create future instances based on the recurrence frequency
        // This would extend the existing recurring task creation logic
        print("🔄 Creating recurring instances for updated task")

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
            guard !task.isDeleted,
                  task.isCompleted,
                  let completedDate = task.completedDate else { return false }
            return calendar.isDate(completedDate, inSameDayAs: date)
        }.sorted { task1, task2 in
            guard let date1 = task1.completedDate,
                  let date2 = task2.completedDate else { return false }
            return date1 > date2 // Most recent first
        }
    }

    func getAllTasks(for date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            if task.isCompleted {
                // For completed tasks, check completion date
                guard let completedDate = task.completedDate else { return false }
                return calendar.isDate(completedDate, inSameDayAs: date)
            } else {
                // For incomplete tasks, check if they should appear on this date
                if task.isRecurring {
                    // For recurring tasks, check if this date should have this task
                    return shouldRecurringTaskAppearOn(task: task, date: date)
                } else {
                    // For regular tasks, check target date if available, otherwise use weekday matching
                    if let targetDate = task.targetDate {
                        return calendar.isDate(targetDate, inSameDayAs: date)
                    } else {
                        // Fallback to weekday matching for tasks without target dates
                        let weekdayComponent = calendar.component(.weekday, from: date)
                        if let targetWeekday = weekdayFromCalendarComponent(weekdayComponent) {
                            return task.weekday == targetWeekday
                        }
                    }
                }
                return false
            }
        }.sorted { task1, task2 in
            // Sort completed tasks first, then by completion/creation date
            if task1.isCompleted != task2.isCompleted {
                return task1.isCompleted && !task2.isCompleted
            }

            if task1.isCompleted && task2.isCompleted {
                guard let date1 = task1.completedDate,
                      let date2 = task2.completedDate else { return false }
                return date1 > date2
            } else {
                return task1.createdAt > task2.createdAt
            }
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
            // Check if the task should appear on this date regardless of weekday
            return targetDate >= startDate
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
        }
    }


    func getCompletedTasks(between startDate: Date, endDate: Date) -> [TaskItem] {
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            guard task.isCompleted,
                  let completedDate = task.completedDate else { return false }
            return completedDate >= startDate && completedDate <= endDate
        }.sorted { task1, task2 in
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
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else { return }

        // Check if task is already recurring
        if tasks[task.weekday]?[index].isRecurring == true {
            return // Already recurring, don't create duplicates
        }

        let parentTaskId = task.id

        // Ensure the original task has a target date set to current week
        if tasks[task.weekday]?[index].targetDate == nil {
            tasks[task.weekday]?[index].targetDate = task.weekday.dateForCurrentWeek()
        }

        // Mark the original task as recurring
        tasks[task.weekday]?[index].isRecurring = true
        tasks[task.weekday]?[index].recurrenceFrequency = frequency
        tasks[task.weekday]?[index].recurrenceEndDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())

        // Note: The recurring logic in shouldRecurringTaskAppearOn will dynamically display
        // this task on the appropriate days based on the frequency. We don't need to
        // create duplicate instances since the display logic handles it automatically.

        saveTasks()

        // Sync the updated task to Supabase
        if let updatedTask = tasks[task.weekday]?[index] {
            Task {
                await updateTaskInSupabase(updatedTask)
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
                    print("✅ All recurring task instances deleted successfully")
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
            addSampleTasks()
            return
        }

        var tasksByWeekday: [WeekDay: [TaskItem]] = [:]
        for weekday in WeekDay.allCases {
            tasksByWeekday[weekday] = savedTasks.filter { $0.weekday == weekday }
        }

        self.tasks = tasksByWeekday
        initializeEmptyDays()
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
                        print("📥 Loaded task: '\(taskItem.title)' on \(taskItem.weekday), targetDate: \(taskItem.targetDate?.description ?? "nil")")
                        supabaseTasks.append(taskItem)
                    }
                }

                // Update local tasks with Supabase data
                await MainActor.run {
                    var tasksByWeekday: [WeekDay: [TaskItem]] = [:]
                    for weekday in WeekDay.allCases {
                        tasksByWeekday[weekday] = supabaseTasks.filter { $0.weekday == weekday }
                    }

                    self.tasks = tasksByWeekday
                    initializeEmptyDays()
                    print("✅ Loaded \(supabaseTasks.count) tasks from Supabase")
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

        var taskItem = TaskItem(title: title, weekday: weekday)
        taskItem.id = id
        taskItem.isCompleted = isCompleted
        taskItem.createdAt = createdAt

        // Parse optional fields
        if let completedDateString = taskDict["completed_date"] as? String {
            taskItem.completedDate = ISO8601DateFormatter().date(from: completedDateString)
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

        if let targetDateString = taskDict["target_date"] as? String {
            taskItem.targetDate = ISO8601DateFormatter().date(from: targetDateString)
        }

        if let reminderTimeString = taskDict["reminder_time"] as? String {
            taskItem.reminderTime = ReminderTime(rawValue: reminderTimeString)
        }

        // Note: is_deleted field is not in Supabase yet, so it defaults to false
        // if let isDeleted = taskDict["is_deleted"] as? Bool {
        //     taskItem.isDeleted = isDeleted
        // }

        return taskItem
    }

    private func saveTaskToSupabase(_ task: TaskItem) async {
        guard authManager.isAuthenticated,
              let userId = authManager.supabaseUser?.id else {
            return
        }

        do {
            let taskData = convertTaskToSupabaseFormat(task, userId: userId.uuidString)
            let client = await supabaseManager.getPostgrestClient()

            try await client
                .from("tasks")
                .upsert(taskData)
                .execute()

            print("✅ Saved task to Supabase: \(task.title)")

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

            print("✅ Updated task in Supabase: \(task.title)")

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

            print("✅ Deleted task from Supabase: \(taskId)")
            return true

        } catch {
            print("❌ Failed to delete task from Supabase: \(error)")
            return false
        }
    }

    private func convertTaskToSupabaseFormat(_ task: TaskItem, userId: String) -> [String: AnyJSON] {
        let formatter = ISO8601DateFormatter()

        var taskData: [String: AnyJSON] = [
            "id": AnyJSON.string(task.id),
            "user_id": AnyJSON.string(userId),
            "title": AnyJSON.string(task.title),
            "is_completed": AnyJSON.bool(task.isCompleted),
            "weekday": AnyJSON.string(task.weekday.rawValue),
            "created_at": AnyJSON.string(formatter.string(from: task.createdAt)),
            "is_recurring": AnyJSON.bool(task.isRecurring)
            // Note: is_deleted column doesn't exist in Supabase yet, so we don't sync it
        ]

        if let completedDate = task.completedDate {
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

        print("🔄 Retrying \(deletedTasks.count) failed deletions...")

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
            let shouldAppear = shouldRecurringTaskAppearOn(task: testTask, date: date)
            print("📅 Should '\(testTask.title)' appear on \(weekday.displayName)? \(shouldAppear)")
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
}