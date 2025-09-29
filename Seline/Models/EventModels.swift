import Foundation

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
    let id: String
    var title: String
    var isCompleted: Bool
    var completedDate: Date?
    let weekday: WeekDay
    let createdAt: Date
    var isRecurring: Bool
    var recurrenceFrequency: RecurrenceFrequency?
    var recurrenceEndDate: Date?
    let parentRecurringTaskId: String? // For tracking which recurring task this belongs to
    var scheduledTime: Date?
    var targetDate: Date? // Specific date this task is intended for

    init(title: String, weekday: WeekDay, scheduledTime: Date? = nil, targetDate: Date? = nil, isRecurring: Bool = false, recurrenceFrequency: RecurrenceFrequency? = nil, parentRecurringTaskId: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.isCompleted = false
        self.completedDate = nil
        self.weekday = weekday
        self.createdAt = Date()
        self.scheduledTime = scheduledTime
        self.targetDate = targetDate
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

    private init() {
        initializeEmptyDays()
        loadTasks()
    }

    private func initializeEmptyDays() {
        for weekday in WeekDay.allCases {
            if tasks[weekday] == nil {
                tasks[weekday] = []
            }
        }
    }

    func addTask(title: String, to weekday: WeekDay, scheduledTime: Date? = nil) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Set the target date to the current week's date for this weekday
        let targetDate = weekday.dateForCurrentWeek()
        let newTask = TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), weekday: weekday, scheduledTime: scheduledTime, targetDate: targetDate)
        tasks[weekday]?.append(newTask)
        saveTasks()
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
    }

    func deleteTask(_ task: TaskItem) {
        guard let weekdayTasks = tasks[task.weekday],
              let index = weekdayTasks.firstIndex(where: { $0.id == task.id }) else { return }

        tasks[task.weekday]?.remove(at: index)
        saveTasks()
    }

    func getTasks(for weekday: WeekDay) -> [TaskItem] {
        return tasks[weekday] ?? []
    }

    func getCompletedTasks(for date: Date) -> [TaskItem] {
        let calendar = Calendar.current
        let allTasks = tasks.values.flatMap { $0 }

        return allTasks.filter { task in
            guard task.isCompleted,
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
        let startDate = calendar.startOfDay(for: task.createdAt)
        let targetDate = calendar.startOfDay(for: date)

        // Don't show tasks before their creation date
        guard targetDate >= startDate else { return false }

        // Check if the task is within its recurrence end date
        if let endDate = task.recurrenceEndDate, targetDate > endDate {
            return false
        }

        let daysDifference = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0

        switch frequency {
        case .daily:
            // Daily tasks appear every day (not just the original weekday)
            return daysDifference >= 0
        case .weekly:
            // Weekly tasks appear on the same weekday every week
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }
            return daysDifference >= 0 && daysDifference % 7 == 0
        case .biweekly:
            // Bi-weekly tasks appear on the same weekday every 2 weeks
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }
            return daysDifference >= 0 && daysDifference % 14 == 0
        case .monthly:
            // Monthly tasks appear on the same weekday of the month
            let taskWeekdayComponent = calendar.component(.weekday, from: date)
            guard let dateWeekday = weekdayFromCalendarComponent(taskWeekdayComponent),
                  dateWeekday == task.weekday else { return false }
            let startWeekOfMonth = calendar.component(.weekOfMonth, from: startDate)
            let dateWeekOfMonth = calendar.component(.weekOfMonth, from: targetDate)
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
        tasks[task.weekday]?[index].isRecurring = true
        tasks[task.weekday]?[index].recurrenceFrequency = frequency
        tasks[task.weekday]?[index].recurrenceEndDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())

        // Generate recurring instances for the year
        generateRecurringInstances(for: task, frequency: frequency, parentTaskId: parentTaskId)
        saveTasks()
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
        // For weekly tasks, create the same task on the same weekday every week for a year
        let calendar = Calendar.current
        var currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate) ?? startDate

        while currentDate <= endDate {
            let newTask = TaskItem(
                title: task.title,
                weekday: task.weekday, // Same weekday as original
                scheduledTime: task.scheduledTime,
                isRecurring: false,
                parentRecurringTaskId: parentTaskId
            )
            tasks[task.weekday]?.append(newTask)

            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
        }
    }

    private func generateBiweeklyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For bi-weekly tasks, create the same task on the same weekday every 2 weeks for a year
        let calendar = Calendar.current
        var currentDate = calendar.date(byAdding: .weekOfYear, value: 2, to: startDate) ?? startDate

        while currentDate <= endDate {
            let newTask = TaskItem(
                title: task.title,
                weekday: task.weekday, // Same weekday as original
                scheduledTime: task.scheduledTime,
                isRecurring: false,
                parentRecurringTaskId: parentTaskId
            )
            tasks[task.weekday]?.append(newTask)

            currentDate = calendar.date(byAdding: .weekOfYear, value: 2, to: currentDate) ?? currentDate
        }
    }

    private func generateMonthlyTasks(for task: TaskItem, parentTaskId: String, from startDate: Date, to endDate: Date) {
        // For monthly tasks, create the same task on the same weekday every month for a year
        let calendar = Calendar.current
        var currentDate = calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate

        while currentDate <= endDate {
            let newTask = TaskItem(
                title: task.title,
                weekday: task.weekday, // Always use the same weekday as original
                scheduledTime: task.scheduledTime,
                isRecurring: false,
                parentRecurringTaskId: parentTaskId
            )
            tasks[task.weekday]?.append(newTask)

            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        }
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
        for weekday in WeekDay.allCases {
            tasks[weekday]?.removeAll { task in
                task.id == parentId || task.parentRecurringTaskId == parentId
            }
        }
        saveTasks()
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
        if let firstTask = tasks[.monday]?.first {
            tasks[.monday]?[0].isCompleted = true
            tasks[.monday]?[0].completedDate = Date()
        }
    }
}