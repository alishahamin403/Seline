import Combine
import Foundation

@MainActor
final class HomeDashboardState: ObservableObject {
    struct UpcomingBirthdayItem: Identifiable, Equatable {
        let person: Person
        let date: Date

        var id: UUID { person.id }
    }

    @Published private(set) var unreadEmailCount: Int = 0
    @Published private(set) var todayTaskCount: Int = 0
    @Published private(set) var pinnedNotesCount: Int = 0
    @Published private(set) var todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] = []
    @Published private(set) var hasPendingLocationSuggestion = false
    @Published private(set) var flattenedTasks: [TaskItem] = []
    @Published private(set) var todayTasks: [TaskItem] = []
    @Published private(set) var missedOneTimeTodos: [TaskItem] = []
    @Published private(set) var upcomingRecurringExpenses: [RecurringExpense] = []
    @Published private(set) var upcomingBirthdays: [UpcomingBirthdayItem] = []

    private let emailService: EmailService
    private let taskManager: TaskManager
    private let notesManager: NotesManager
    private let visitState: VisitStateManager
    private let locationSuggestionService: LocationSuggestionService
    private let peopleManager: PeopleManager
    private let recurringExpenseService: RecurringExpenseService
    private let tagManager: TagManager
    private var cancellables = Set<AnyCancellable>()
    private let dismissedMissedTodoStorageKey = "dismissedHomeMissedTodoKeys"
    private static let missedTodoKeyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let missedTodoKeyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(
        emailService: EmailService? = nil,
        taskManager: TaskManager? = nil,
        notesManager: NotesManager? = nil,
        visitState: VisitStateManager? = nil,
        locationSuggestionService: LocationSuggestionService? = nil,
        peopleManager: PeopleManager? = nil,
        recurringExpenseService: RecurringExpenseService? = nil,
        tagManager: TagManager? = nil
    ) {
        self.emailService = emailService ?? .shared
        self.taskManager = taskManager ?? .shared
        self.notesManager = notesManager ?? .shared
        self.visitState = visitState ?? .shared
        self.locationSuggestionService = locationSuggestionService ?? .shared
        self.peopleManager = peopleManager ?? .shared
        self.recurringExpenseService = recurringExpenseService ?? .shared
        self.tagManager = tagManager ?? .shared

        bind()
        refreshAll()
    }

    private func bind() {
        emailService.$inboxEmails
            .sink { [weak self] _ in
                self?.refreshUnreadEmails()
            }
            .store(in: &cancellables)

        taskManager.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTasks()
            }
            .store(in: &cancellables)

        notesManager.$notes
            .sink { [weak self] _ in
                self?.refreshPinnedNotes()
            }
            .store(in: &cancellables)

        visitState.$todaysVisits
            .sink { [weak self] visits in
                self?.todaysVisits = visits
            }
            .store(in: &cancellables)

        locationSuggestionService.$hasPendingSuggestion
            .sink { [weak self] hasPendingSuggestion in
                self?.hasPendingLocationSuggestion = hasPendingSuggestion
            }
            .store(in: &cancellables)

        peopleManager.$people
            .sink { [weak self] _ in
                self?.refreshUpcomingBirthdays()
            }
            .store(in: &cancellables)
    }

    func refreshAll() {
        refreshUnreadEmails()
        refreshTasks()
        refreshPinnedNotes()
        todaysVisits = visitState.todaysVisits
        hasPendingLocationSuggestion = locationSuggestionService.hasPendingSuggestion
        refreshUpcomingBirthdays()
        refreshRecurringExpenses()
    }

    func dismissMissedTodo(_ task: TaskItem) {
        var keys = dismissedMissedTodoKeys
        keys.insert(Self.missedTodoOccurrenceKey(for: task))
        dismissedMissedTodoKeys = keys
        refreshTasks()
    }

    func resolveMissedTodo(_ task: TaskItem) {
        dismissMissedTodo(task)
    }

    private func refreshUnreadEmails() {
        unreadEmailCount = emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private func refreshTasks() {
        let allTasks = taskManager.getAllFlattenedTasks()
        flattenedTasks = allTasks
        todayTasks = taskManager.getTasksForDate(Calendar.current.startOfDay(for: Date()))
        todayTaskCount = taskManager.getTasksForToday().count
        missedOneTimeTodos = buildMissedOneTimeTodos(from: allTasks)
    }

    private func refreshPinnedNotes() {
        pinnedNotesCount = notesManager.pinnedNotes.count
    }

    private func refreshUpcomingBirthdays() {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentDay = calendar.component(.day, from: now)
        let currentYear = calendar.component(.year, from: now)

        upcomingBirthdays = peopleManager.people.compactMap { person in
            guard let birthday = person.birthday else { return nil }

            let month = calendar.component(.month, from: birthday)
            let day = calendar.component(.day, from: birthday)
            guard month == currentMonth, day >= currentDay else { return nil }

            let candidate = calendar.date(
                from: DateComponents(year: currentYear, month: month, day: day)
            ) ?? birthday

            return UpcomingBirthdayItem(person: person, date: candidate)
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.person.displayName.localizedCaseInsensitiveCompare(rhs.person.displayName) == .orderedAscending
            }
            return lhs.date < rhs.date
        }
    }

    private func refreshRecurringExpenses() {
        let recurringExpenseService = recurringExpenseService
        Task { @MainActor in
            do {
                let expenses = try await recurringExpenseService.fetchActiveRecurringExpenses()
                let now = Date()
                let filtered = expenses
                    .filter { expense in
                        expense.isActive && (expense.endDate == nil || expense.endDate! >= now)
                    }
                    .sorted { $0.nextOccurrence < $1.nextOccurrence }

                upcomingRecurringExpenses = filtered
            } catch {
                upcomingRecurringExpenses = []
            }
        }
    }

    private func buildMissedOneTimeTodos(from tasks: [TaskItem]) -> [TaskItem] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let dismissedKeys = dismissedMissedTodoKeys
        var seenKeys = Set<String>()

        return tasks
            .filter { task in
                guard !task.isDeleted else { return false }
                guard !task.isRecurring else { return false }
                guard task.parentRecurringTaskId == nil else { return false }
                guard !isRecurringExpenseTask(task) else { return false }
                guard task.targetDate != nil else { return false }
                guard !task.isCompleted else { return false }

                let occurrenceKey = Self.missedTodoOccurrenceKey(for: task)
                guard !dismissedKeys.contains(occurrenceKey) else { return false }
                guard dueDate(for: task) < todayStart else { return false }
                guard seenKeys.insert(occurrenceKey).inserted else { return false }

                return true
            }
            .sorted { dueDate(for: $0) > dueDate(for: $1) }
    }

    private func isRecurringExpenseTask(_ task: TaskItem) -> Bool {
        if task.id.hasPrefix("recurring_") {
            return true
        }

        if let tagId = task.tagId,
           let tag = tagManager.getTag(by: tagId),
           tag.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "recurring" {
            return true
        }

        if let description = task.description?.lowercased(),
           description.contains("amount:") && description.contains("category:") {
            return true
        }

        return false
    }

    private func dueDate(for task: TaskItem) -> Date {
        guard let targetDate = task.targetDate else { return task.createdAt }

        guard let scheduledTime = task.scheduledTime else {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: targetDate) ?? targetDate
        }

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: scheduledTime)
        return Calendar.current.date(
            bySettingHour: components.hour ?? 12,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDate
        ) ?? targetDate
    }

    private var dismissedMissedTodoKeys: Set<String> {
        get {
            let values = UserDefaults.standard.stringArray(forKey: dismissedMissedTodoStorageKey) ?? []
            return Set(values)
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: dismissedMissedTodoStorageKey)
        }
    }

    private static func missedTodoOccurrenceKey(for task: TaskItem) -> String {
        let calendar = Calendar.current
        let dueDate = task.targetDate ?? task.createdAt
        let normalizedDay = calendar.startOfDay(for: dueDate)
        let dayText = missedTodoKeyDayFormatter.string(from: normalizedDay)
        let timeText = task.scheduledTime.map { scheduledTime in
            missedTodoKeyTimeFormatter.string(from: scheduledTime)
        } ?? "untimed"

        let title = normalizeMissedTodoField(task.title)
        let description = normalizeMissedTodoField(task.description ?? "")
        let location = normalizeMissedTodoField(task.location ?? "")
        let calendarTitle = normalizeMissedTodoField(task.calendarTitle ?? "")

        return [dayText, timeText, title, description, location, calendarTitle]
            .joined(separator: "|")
    }

    private static func normalizeMissedTodoField(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
