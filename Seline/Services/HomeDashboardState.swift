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
    @Published private(set) var upcomingBirthdays: [UpcomingBirthdayItem] = []

    private let emailService: EmailService
    private let taskManager: TaskManager
    private let notesManager: NotesManager
    private let visitState: VisitStateManager
    private let locationSuggestionService: LocationSuggestionService
    private let peopleManager: PeopleManager
    private var cancellables = Set<AnyCancellable>()

    init(
        emailService: EmailService = .shared,
        taskManager: TaskManager = .shared,
        notesManager: NotesManager = .shared,
        visitState: VisitStateManager = .shared,
        locationSuggestionService: LocationSuggestionService = .shared,
        peopleManager: PeopleManager = .shared
    ) {
        self.emailService = emailService
        self.taskManager = taskManager
        self.notesManager = notesManager
        self.visitState = visitState
        self.locationSuggestionService = locationSuggestionService
        self.peopleManager = peopleManager

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
    }

    private func refreshUnreadEmails() {
        unreadEmailCount = emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private func refreshTasks() {
        flattenedTasks = taskManager.getAllFlattenedTasks()
        todayTasks = taskManager.getTasksForDate(Calendar.current.startOfDay(for: Date()))
        todayTaskCount = taskManager.getTasksForToday().count
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
}
