import Foundation
import PostgREST
import SwiftUI

// Color palette for tags - minimalistic, unique colors for each tag
struct TagColorPalette {
    static let colors: [Color] = [
        Color(red: 0.4, green: 0.6, blue: 0.8),   // Muted blue
        Color(red: 0.8, green: 0.6, blue: 0.4),   // Muted orange
        Color(red: 0.8, green: 0.5, blue: 0.5),   // Muted red
        Color(red: 0.5, green: 0.75, blue: 0.6),  // Muted green
        Color(red: 0.5, green: 0.75, blue: 0.85), // Muted cyan
        Color(red: 0.7, green: 0.55, blue: 0.8),  // Muted purple
        Color(red: 0.85, green: 0.6, blue: 0.75), // Muted pink
        Color(red: 0.8, green: 0.75, blue: 0.5),  // Muted yellow
        Color(red: 0.6, green: 0.6, blue: 0.8),   // Muted indigo
        Color(red: 0.65, green: 0.5, blue: 0.7),  // Muted purple variant
        Color(red: 0.45, green: 0.65, blue: 0.6), // Muted teal
        Color(red: 0.7, green: 0.55, blue: 0.45), // Muted brown
    ]

    static func colorForIndex(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

// Tag model for organizing events
struct Tag: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let colorIndex: Int // Index into TagColorPalette.colors

    var color: Color {
        TagColorPalette.colorForIndex(colorIndex)
    }

    init(id: String = UUID().uuidString, name: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }

    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }
}

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
    var tagId: String? // Tag for organizing events (nil means "Personal" default tag)
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

    // MARK: - Custom Codable Implementation for Backward Compatibility

    enum CodingKeys: String, CodingKey {
        case id, title, description, isCompleted, completedDate, weekday, createdAt
        case isRecurring, recurrenceFrequency, recurrenceEndDate, parentRecurringTaskId
        case scheduledTime, endTime, targetDate, reminderTime, tagId, isDeleted, completedDates
        case emailId, emailSubject, emailSenderName, emailSenderEmail, emailSnippet
        case emailTimestamp, emailBody, emailIsImportant, emailAiSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        completedDate = try container.decodeIfPresent(Date.self, forKey: .completedDate)
        weekday = try container.decode(WeekDay.self, forKey: .weekday)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        recurrenceFrequency = try container.decodeIfPresent(RecurrenceFrequency.self, forKey: .recurrenceFrequency)
        recurrenceEndDate = try container.decodeIfPresent(Date.self, forKey: .recurrenceEndDate)
        parentRecurringTaskId = try container.decodeIfPresent(String.self, forKey: .parentRecurringTaskId)
        scheduledTime = try container.decodeIfPresent(Date.self, forKey: .scheduledTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        targetDate = try container.decodeIfPresent(Date.self, forKey: .targetDate)
        reminderTime = try container.decodeIfPresent(ReminderTime.self, forKey: .reminderTime)

        // Handle tagId - might be missing in old data, default to nil
        tagId = try container.decodeIfPresent(String.self, forKey: .tagId)

        // Handle isDeleted - might be missing in old data, default to false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false

        // Handle completedDates - CRITICAL: might be missing in old data, but should be preserved if present
        completedDates = try container.decodeIfPresent([Date].self, forKey: .completedDates) ?? []

        // Email fields
        emailId = try container.decodeIfPresent(String.self, forKey: .emailId)
        emailSubject = try container.decodeIfPresent(String.self, forKey: .emailSubject)
        emailSenderName = try container.decodeIfPresent(String.self, forKey: .emailSenderName)
        emailSenderEmail = try container.decodeIfPresent(String.self, forKey: .emailSenderEmail)
        emailSnippet = try container.decodeIfPresent(String.self, forKey: .emailSnippet)
        emailTimestamp = try container.decodeIfPresent(Date.self, forKey: .emailTimestamp)
        emailBody = try container.decodeIfPresent(String.self, forKey: .emailBody)
        emailIsImportant = try container.decodeIfPresent(Bool.self, forKey: .emailIsImportant) ?? false
        emailAiSummary = try container.decodeIfPresent(String.self, forKey: .emailAiSummary)

        // Log loaded recurring task with completion info
        if isRecurring {
            print("📥 Loaded recurring task '\(title)' with \(completedDates.count) completed dates, tagId: \(tagId ?? "nil")")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(completedDate, forKey: .completedDate)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encodeIfPresent(recurrenceFrequency, forKey: .recurrenceFrequency)
        try container.encodeIfPresent(recurrenceEndDate, forKey: .recurrenceEndDate)
        try container.encodeIfPresent(parentRecurringTaskId, forKey: .parentRecurringTaskId)
        try container.encodeIfPresent(scheduledTime, forKey: .scheduledTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(reminderTime, forKey: .reminderTime)
        try container.encodeIfPresent(tagId, forKey: .tagId)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(completedDates, forKey: .completedDates)

        try container.encodeIfPresent(emailId, forKey: .emailId)
        try container.encodeIfPresent(emailSubject, forKey: .emailSubject)
        try container.encodeIfPresent(emailSenderName, forKey: .emailSenderName)
        try container.encodeIfPresent(emailSenderEmail, forKey: .emailSenderEmail)
        try container.encodeIfPresent(emailSnippet, forKey: .emailSnippet)
        try container.encodeIfPresent(emailTimestamp, forKey: .emailTimestamp)
        try container.encodeIfPresent(emailBody, forKey: .emailBody)
        try container.encode(emailIsImportant, forKey: .emailIsImportant)
        try container.encodeIfPresent(emailAiSummary, forKey: .emailAiSummary)
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

        // Don't load from Supabase here - wait for authentication!
        // The app will call loadTasksFromSupabase() after user authenticates
        // This ensures EncryptionManager.setupEncryption() is called FIRST
    }

    private func initializeEmptyDays() {
        for weekday in WeekDay.allCases {
            if tasks[weekday] == nil {
                tasks[weekday] = []
            }
        }
    }

    func addTask(title: String, to weekday: WeekDay, description: String? = nil, scheduledTime: Date? = nil, endTime: Date? = nil, targetDate: Date? = nil, reminderTime: ReminderTime? = nil, isRecurring: Bool = false, recurrenceFrequency: RecurrenceFrequency? = nil, tagId: String? = nil) {
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
        var newTaskWithTag = newTask
        newTaskWithTag.tagId = tagId
        tasks[weekday]?.append(newTaskWithTag)
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
                scheduleReminder(for: newTaskWithTag, at: eventDateTime, reminderBefore: reminderTime)
            }
        }

        // Sync with Supabase
        Task {
            await saveTaskToSupabase(newTaskWithTag)
        }
    }

    /// Check if an event already exists with the same title, date, and time
    func doesEventExist(title: String, date: Date, time: Date, endTime: Date? = nil) -> Bool {
        let calendar = Calendar.current
        let eventDateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let eventTimeComponents = calendar.dateComponents([.hour, .minute], from: time)

        // Check all tasks across all weekdays
        for (_, weekdayTasks) in tasks {
            for task in weekdayTasks {
                // Compare titles (case-insensitive, trimmed)
                let titleMatch = task.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                                title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

                guard titleMatch else { continue }

                // Compare dates
                if let targetDate = task.targetDate {
                    let taskDateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
                    let dateMatch = eventDateComponents.year == taskDateComponents.year &&
                                   eventDateComponents.month == taskDateComponents.month &&
                                   eventDateComponents.day == taskDateComponents.day

                    if !dateMatch { continue }

                    // Compare times (if scheduled time exists)
                    if let scheduledTime = task.scheduledTime {
                        let taskTimeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)
                        let timeMatch = eventTimeComponents.hour == taskTimeComponents.hour &&
                                       eventTimeComponents.minute == taskTimeComponents.minute

                        if timeMatch {
                            return true
                        }
                    }
                }
            }
        }

        return false
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

        // Removed repetitive logging - this was printing hundreds of times per app session
        // if !recurringTasks.isEmpty {
        //     print("📋 Returning \(filteredTasks.count) tasks for \(weekday.displayName)")
        // }

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

        // Log all recurring tasks with their completed dates before saving
        let recurringTasks = allTasks.filter { $0.isRecurring }
        if !recurringTasks.isEmpty {
            for task in recurringTasks {
                if !task.completedDates.isEmpty {
                    print("💾 Saving recurring task '\(task.title)' with \(task.completedDates.count) completed dates:")
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    for date in task.completedDates {
                        print("   - \(dateFormatter.string(from: date))")
                    }
                }
            }
        }

        if let encoded = try? JSONEncoder().encode(allTasks) {
            userDefaults.set(encoded, forKey: tasksKey)

            // Sync today's tasks to widget after saving
            syncTodaysTasksToWidget(tags: TagManager.shared.tags)
        } else {
            print("❌ Failed to encode tasks for local storage")
        }
    }

    private func loadTasks() {
        guard let data = userDefaults.data(forKey: tasksKey),
              let savedTasks = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            print("📂 No saved tasks found in local storage, adding sample tasks")
            addSampleTasks()
            return
        }

        print("📂 Loaded \(savedTasks.count) tasks from cache")

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

        self.tasks = tasksByWeekday
        initializeEmptyDays()

        // Save the fixed tasks back to storage if any were fixed
        let tasksToFix = fixedTasks.filter { task in
            savedTasks.first(where: { $0.id == task.id })?.isCompleted != task.isCompleted
        }

        if !tasksToFix.isEmpty {
            saveTasks()

            // Also sync fixes to Supabase
            Task {
                for task in tasksToFix {
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

        // CRITICAL: Ensure encryption key is initialized before loading
        // Wait for EncryptionManager to be ready (max 5 seconds)
        var attempts = 0
        while EncryptionManager.shared.isKeyInitialized == false && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }

        if !EncryptionManager.shared.isKeyInitialized {
            print("⚠️ Encryption key not initialized after 5 seconds, cannot decrypt tasks safely")
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
                    if let taskItem = await parseTaskFromSupabase(taskDict) {
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

                    self.tasks = tasksByWeekday
                    initializeEmptyDays()

                    // IMPORTANT: Save loaded tasks to local cache so they persist across rebuilds
                    // This ensures email attachments and all data are available even if Supabase is unreachable
                    self.saveTasks()

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

    private func parseTaskFromSupabase(_ taskDict: [String: Any]) async -> TaskItem? {
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

        // DECRYPT task title and description after loading from Supabase
        let titleBeforeDecrypt = taskItem.title
        do {
            taskItem = try await decryptTaskAfterLoading(taskItem)
            if titleBeforeDecrypt != taskItem.title {
                print("✅ Successfully decrypted: '\(titleBeforeDecrypt.prefix(40))...' → '\(taskItem.title)'")
            }
        } catch {
            // Decryption error - task will be returned as-is (likely unencrypted legacy data)
            print("⚠️ Decryption failed for task, keeping encrypted: \(error)")
        }

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

        if let tagId = taskDict["tag_id"] as? String {
            taskItem.tagId = tagId
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
           !completedDatesJson.isEmpty,
           let jsonData = completedDatesJson.data(using: .utf8),
           let dateStrings = try? JSONDecoder().decode([String].self, from: jsonData) {
            let formatter = ISO8601DateFormatter()
            taskItem.completedDates = dateStrings.compactMap { formatter.date(from: $0) }
            if !taskItem.completedDates.isEmpty && taskItem.isRecurring {
                print("📥 Restored \(taskItem.completedDates.count) completed dates for recurring task '\(taskItem.title)' from Supabase")
            }
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
            // CRITICAL: Encrypt task before saving to Supabase
            let encryptedTask = try await encryptTaskBeforeSaving(task)
            let taskData = convertTaskToSupabaseFormat(encryptedTask, userId: userId.uuidString)
            let client = await supabaseManager.getPostgrestClient()

            try await client
                .from("tasks")
                .upsert(taskData)
                .execute()

            print("✅ Saved encrypted task to Supabase: '\(task.title)'")
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
            // CRITICAL: Encrypt task before updating in Supabase
            let encryptedTask = try await encryptTaskBeforeSaving(task)
            let taskData = convertTaskToSupabaseFormat(encryptedTask, userId: userId.uuidString)

            let client = await supabaseManager.getPostgrestClient()

            try await client
                .from("tasks")
                .update(taskData)
                .eq("id", value: task.id)
                .execute()

            print("✅ Updated encrypted task in Supabase: '\(task.title)'")
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

        if let tagId = task.tagId {
            taskData["tag_id"] = AnyJSON.string(tagId)
        } else {
            taskData["tag_id"] = AnyJSON.null
        }

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
        // CRITICAL: Decrypt cached tasks now that encryption key is ready
        // This must happen BEFORE background sync so UI shows plaintext immediately
        print("🔐 Decrypting cached tasks now that encryption key is initialized...")
        await decryptCachedTasks()

        // Sync in background - don't block the UI with Supabase operations
        // The app already has local cache loaded, so use that for instant display
        Task {
            await backgroundSyncWithSupabase()
        }
    }

    /// Decrypt all cached task titles/descriptions now that encryption key is ready
    private func decryptCachedTasks() async {
        let allCachedTasks = tasks.values.flatMap { $0 }

        guard !allCachedTasks.isEmpty else {
            print("✅ No cached tasks to decrypt")
            return
        }

        print("🔓 Attempting to decrypt \(allCachedTasks.count) cached tasks...")

        var decryptedTasks: [WeekDay: [TaskItem]] = [:]

        for weekday in WeekDay.allCases {
            var weekdayDecryptedTasks: [TaskItem] = []

            for task in (tasks[weekday] ?? []) {
                var decryptedTask = task

                // Try to decrypt title if it looks encrypted
                if task.title.count > 50 && (task.title.contains("+") || task.title.contains("/") || task.title.contains("=")) {
                    do {
                        let decrypted = try EncryptionManager.shared.decrypt(task.title)
                        print("🔓 Decrypted task title: '\(task.title.prefix(30))...' → '\(decrypted)'")
                        decryptedTask.title = decrypted
                    } catch {
                        print("⚠️ Failed to decrypt task title: \(error)")
                    }
                }

                // Try to decrypt description if it exists and looks encrypted
                if let description = task.description, description.count > 50 && (description.contains("+") || description.contains("/") || description.contains("=")) {
                    do {
                        decryptedTask.description = try EncryptionManager.shared.decrypt(description)
                    } catch {
                        // Keep original if decryption fails
                    }
                }

                weekdayDecryptedTasks.append(decryptedTask)
            }

            decryptedTasks[weekday] = weekdayDecryptedTasks
        }

        // Update the tasks array with decrypted versions
        await MainActor.run {
            self.tasks = decryptedTasks
            self.saveTasks()
            print("✅ Cached tasks decrypted and saved")
        }
    }

    /// Background sync that happens without blocking the UI
    private func backgroundSyncWithSupabase() async {
        print("🔄 Starting background sync with Supabase...")
        await loadTasksFromSupabase()
        await retryFailedDeletions()
        print("✅ Background sync complete")
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
        // Only schedule if reminder is not "none"
        guard reminderBefore != .none else {
            print("⏰ No reminder set for \(task.title)")
            return
        }

        // Calculate the reminder time (alert/notification before event)
        let reminderDate = Calendar.current.date(byAdding: .minute, value: -reminderBefore.minutes, to: scheduledTime)

        guard let reminderDate = reminderDate, reminderDate > Date() else {
            print("⏰ Reminder time is in the past, skipping notification")
            return
        }

        // Format the event time for the notification body
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let eventTimeString = timeFormatter.string(from: scheduledTime)

        // FIRST NOTIFICATION: Alert/reminder notification (e.g., 15 min before)
        let reminderBody = "\(reminderBefore.displayName) - Event starts at \(eventTimeString)"

        Task {
            // Schedule the alert reminder notification
            await NotificationService.shared.scheduleTaskReminder(
                taskId: task.id,
                title: task.title,
                body: reminderBody,
                scheduledTime: reminderDate,
                isAlertReminder: true
            )

            // SECOND NOTIFICATION: Event time notification (when event actually starts)
            if scheduledTime > Date() {
                let eventStartBody = "Starting now!"
                await NotificationService.shared.scheduleTaskReminder(
                    taskId: task.id,
                    title: task.title,
                    body: eventStartBody,
                    scheduledTime: scheduledTime,
                    isAlertReminder: false
                )
            }
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

                // Count completed instances based on completedDates array
                let completedInstances = task.completedDates.filter { completedDate in
                    completedDate <= today
                }.count

                completedCount += completedInstances
                incompleteCount += (instancesUpToToday - completedInstances)

                // Log stats for each recurring task for debugging
                if instancesUpToToday > 0 {
                    let percentage = Double(completedInstances) / Double(instancesUpToToday) * 100.0
                    print("📊 Recurring task '\(task.title)': \(completedInstances)/\(instancesUpToToday) (\(String(format: "%.1f", percentage))%)")
                }
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

    // MARK: - Calendar Sync Methods

    /// Sync calendar events from iPhone's native Calendar app
    /// Only syncs events from current month onwards (3-month rolling window)
    @MainActor
    func syncCalendarEvents() async {
        let newEvents = await CalendarSyncService.shared.fetchNewCalendarEvents()
        guard !newEvents.isEmpty else {
            return
        }

        // Convert EventKit events to TaskItems and add them
        var addedCount = 0
        for event in newEvents {
            let taskItem = CalendarSyncService.shared.convertEKEventToTaskItem(event)

            // Add the task to the appropriate weekday
            let weekday = taskItem.weekday
            if tasks[weekday] != nil {
                tasks[weekday]?.append(taskItem)
            } else {
                tasks[weekday] = [taskItem]
            }

            // Sync with Supabase
            await saveTaskToSupabase(taskItem)
            addedCount += 1
        }

        // Mark events as synced
        CalendarSyncService.shared.markEventsAsSynced(newEvents)

        // Save to local storage
        saveTasks()
    }

    /// Manually trigger calendar access request
    /// Call this if you want to prompt user for calendar permission
    func requestCalendarAccess() async -> Bool {
        return await CalendarSyncService.shared.requestCalendarAccess()
    }

    /// Delete all synced calendar events and reset sync tracking
    /// Use this when you want to remove previously synced calendar events and start fresh
    @MainActor
    func deleteSyncedCalendarEventsAndReset() {
        var deletedCount = 0

        // Delete synced events from all weekdays
        for weekday in WeekDay.allCases {
            if let taskList = tasks[weekday] {
                // Filter out synced calendar events (IDs starting with "cal_")
                let filteredTasks = taskList.filter { task in
                    !task.id.hasPrefix("cal_")
                }

                if filteredTasks.count < taskList.count {
                    deletedCount += taskList.count - filteredTasks.count
                    tasks[weekday] = filteredTasks
                }
            }
        }

        // Clear sync tracking so it will ask for permission again
        CalendarSyncService.shared.resetCalendarSync()

        // Save changes
        saveTasks()
    }

    // MARK: - Widget Support

    func syncTodaysTasksToWidget(tags: [Tag] = []) {
        let today = Date()
        let todaysTasks = getTasksForDate(today)

        // Convert to simple structures that can be encoded
        struct WidgetTask: Codable {
            let id: String
            let title: String
            let scheduledTime: Date?
            let isCompleted: Bool
            let tagId: String?
            let tagName: String?
        }

        let widgetTasks = todaysTasks.map { task in
            // Look up tag name if tags provided
            let tagName = tags.first { $0.id == task.tagId }?.name

            return WidgetTask(
                id: task.id,
                title: task.title,
                scheduledTime: task.scheduledTime,
                isCompleted: task.isCompletedOn(date: today),
                tagId: task.tagId,
                tagName: tagName
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let encoded = try? encoder.encode(widgetTasks) {
            let userDefaults = UserDefaults(suiteName: "group.seline")
            userDefaults?.set(encoded, forKey: "widgetTodaysTasks")

        }
    }
}

// MARK: - Tag Manager

@MainActor
class TagManager: ObservableObject {
    static let shared = TagManager()

    @Published var tags: [Tag] = []
    private let userDefaults = UserDefaults.standard
    private let tagsKey = "UserCreatedTags"
    private let supabaseManager = SupabaseManager.shared
    private let authManager = AuthenticationManager.shared

    private init() {
        loadTags()
    }

    func createTag(name: String) -> Tag? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Get the next available color index
        let nextColorIndex = tags.count % TagColorPalette.colors.count

        let newTag = Tag(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorIndex: nextColorIndex
        )

        tags.append(newTag)
        saveTags()

        // Sync to Supabase
        Task {
            await saveTagToSupabase(newTag)
        }

        return newTag
    }

    func deleteTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        saveTags()

        // Sync deletion to Supabase
        Task {
            await deleteTagFromSupabase(tag)
        }
    }

    func getTag(by id: String?) -> Tag? {
        guard let id = id else { return nil }
        return tags.first { $0.id == id }
    }

    // MARK: - Supabase Sync

    func loadTagsFromSupabase() async {
        guard let userId = supabaseManager.authClient.currentUser?.id else {
            print("⚠️ User not authenticated - skipping Supabase tag load")
            return
        }

        do {
            let postgrestClient = await supabaseManager.getPostgrestClient()
            let tagsData: [TagSupabaseModel] = try await postgrestClient
                .from("tags")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            let loadedTags = tagsData.map { Tag(id: $0.id, name: $0.name, colorIndex: $0.color_index) }

            await MainActor.run {
                self.tags = loadedTags
                self.saveTags()
            }
        } catch {
            print("❌ Error loading tags from Supabase: \(error.localizedDescription)")
            // Fall back to local storage
            print("📂 Falling back to local storage tags")
        }
    }

    private func saveTagToSupabase(_ tag: Tag) async {
        guard let userId = supabaseManager.authClient.currentUser?.id else {
            print("⚠️ User not authenticated - skipping Supabase tag save")
            return
        }

        do {
            let postgrestClient = await supabaseManager.getPostgrestClient()
            let tagModel = TagSupabaseModel(
                id: tag.id,
                user_id: userId.uuidString,
                name: tag.name,
                color_index: tag.colorIndex
            )

            _ = try await postgrestClient
                .from("tags")
                .insert(tagModel)
                .execute()

        } catch {
            print("❌ Error saving tag to Supabase: \(error.localizedDescription)")
        }
    }

    private func deleteTagFromSupabase(_ tag: Tag) async {
        guard let userId = supabaseManager.authClient.currentUser?.id else {
            print("⚠️ User not authenticated - skipping Supabase tag delete")
            return
        }

        do {
            let postgrestClient = await supabaseManager.getPostgrestClient()
            _ = try await postgrestClient
                .from("tags")
                .delete()
                .eq("id", value: tag.id)
                .eq("user_id", value: userId.uuidString)
                .execute()

        } catch {
            print("❌ Error deleting tag from Supabase: \(error.localizedDescription)")
        }
    }

    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tags) {
            userDefaults.set(encoded, forKey: tagsKey)
        }
    }

    private func loadTags() {
        guard let data = userDefaults.data(forKey: tagsKey),
              let loadedTags = try? JSONDecoder().decode([Tag].self, from: data) else {
            print("📂 No saved tags found in local storage")
            return
        }

        print("📂 Loading \(loadedTags.count) tags from local storage")
        self.tags = loadedTags
    }

    // MARK: - Clear Data on Logout

    func clearTagsOnLogout() {
        tags = []

        // Clear UserDefaults
        userDefaults.removeObject(forKey: tagsKey)

        print("🗑️ Cleared all tags on logout")
    }
}

// MARK: - Supabase Tag Model

struct TagSupabaseModel: Codable {
    let id: String
    let user_id: String
    let name: String
    let color_index: Int
}

// MARK: - Calendar Photo Import Models

enum ExtractionValidationStatus: String, Codable {
    case success = "success"           // All data extracted clearly
    case partial = "partial"           // Some fields unclear (but time/date available)
    case failed = "failed"             // Can't extract time/date
}

struct ExtractedEvent: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var startTime: Date
    var endTime: Date?
    var attendees: [String] = []
    var confidence: Double              // 0.0 to 1.0 - how confident AI is
    var titleConfidence: Bool           // true if title was clearly readable
    var timeConfidence: Bool            // true if time was clearly readable
    var dateConfidence: Bool            // true if date was clearly readable
    var notes: String = ""
    var isSelected: Bool = true         // User can deselect before creating
    var alreadyExists: Bool = false     // true if event already exists in calendar (not codable)

    // For display purposes
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startTime)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: startTime)
    }

    var durationText: String? {
        guard let endTime = endTime else { return nil }
        let minutes = Int(endTime.timeIntervalSince(startTime) / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
}

struct CalendarPhotoExtractionResponse: Codable {
    let status: ExtractionValidationStatus
    var events: [ExtractedEvent]
    let errorMessage: String?
    let extractionConfidence: Double    // Overall confidence (0.0 to 1.0)

    init(status: ExtractionValidationStatus, events: [ExtractedEvent] = [], errorMessage: String? = nil, confidence: Double = 1.0) {
        self.status = status
        self.events = events
        self.errorMessage = errorMessage
        self.extractionConfidence = confidence
    }
}