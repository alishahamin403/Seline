import Combine
import Foundation

@MainActor
final class NotesHubState: ObservableObject {
    struct Inputs: Equatable {
        let searchText: String
        let selectedFolderId: UUID?
        let showPinnedNotesOnly: Bool
        let showUnfiledNotesOnly: Bool
        let showsCurrentMonthOnly: Bool
    }

    @Published private(set) var filteredPinnedNotes: [Note] = []
    @Published private(set) var allUnpinnedNotes: [Note] = []
    @Published private(set) var recentNotes: [Note] = []
    @Published private(set) var notesByMonth: [(month: String, notes: [Note])] = []
    @Published private(set) var displayedNotes: [Note] = []
    @Published private(set) var looseNotesCount: Int = 0
    @Published private(set) var folderNotesCount: Int = 0
    @Published private(set) var journalEntries: [Note] = []
    @Published private(set) var latestJournalRecap: Note?
    @Published private(set) var journalOverviewStats: JournalStats = JournalStats(
        currentStreak: 0,
        longestStreak: 0,
        completedThisWeek: 0,
        totalEntries: 0,
        lastEntryDate: nil,
        todayStatus: .missing
    )
    /// Count of user-visible folders excluding system folders (Receipts, Journal).
    /// Pre-computed to avoid filtering notesManager.folders on every view render.
    @Published private(set) var dashboardFolderCount: Int = 0
    @Published private(set) var hubReceiptMonthlySummaries: [MonthlyReceiptSummary] = []
    @Published private(set) var hubReceiptTotal: Double = 0
    @Published private(set) var hubReceiptCount: Int = 0
    @Published private(set) var hubTopReceiptCategories: [(category: String, total: Double)] = []
    @Published private(set) var hubRecurringExpenses: [RecurringExpense] = []
    @Published private(set) var recurringHubTotal: Double = 0
    @Published private(set) var upcomingRecurringCount: Int = 0

    private let notesManager: NotesManager
    private let receiptManager: ReceiptManager
    private var cancellables = Set<AnyCancellable>()
    private var inputs = Inputs(
        searchText: "",
        selectedFolderId: nil,
        showPinnedNotesOnly: false,
        showUnfiledNotesOnly: false,
        showsCurrentMonthOnly: false
    )
    private var recurringExpenses: [RecurringExpense] = []
    private var refreshGeneration = 0

    init(notesManager: NotesManager? = nil) {
        self.notesManager = notesManager ?? .shared
        self.receiptManager = .shared

        self.notesManager.$notes
            .combineLatest(self.notesManager.$folders)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        self.receiptManager.$receipts
            .sink { [weak self] _ in
                self?.refresh(includeAggregates: true)
            }
            .store(in: &cancellables)
    }

    func updateInputs(
        searchText: String,
        selectedFolderId: UUID?,
        showPinnedNotesOnly: Bool,
        showUnfiledNotesOnly: Bool,
        showsCurrentMonthOnly: Bool,
        forceRefresh: Bool = false
    ) {
        let previousInputs = inputs
        let nextInputs = Inputs(
            searchText: searchText,
            selectedFolderId: selectedFolderId,
            showPinnedNotesOnly: showPinnedNotesOnly,
            showUnfiledNotesOnly: showUnfiledNotesOnly,
            showsCurrentMonthOnly: showsCurrentMonthOnly
        )

        guard forceRefresh || nextInputs != inputs else { return }
        inputs = nextInputs
        refresh(
            includeAggregates: forceRefresh || previousInputs.showsCurrentMonthOnly != nextInputs.showsCurrentMonthOnly
        )
    }

    func updateRecurringExpenses(_ expenses: [RecurringExpense]) {
        recurringExpenses = expenses
        refreshAggregates()
    }

    func refresh(includeAggregates: Bool = true) {
        let currentInputs = inputs
        let notesSnapshot = receiptManager.visibleNotes(notesManager.notes)
        let foldersSnapshot = notesManager.folders
        let pinnedNotesSnapshot = receiptManager.visibleNotes(notesManager.pinnedNotes)
        let recentNotesSnapshot = receiptManager.visibleNotes(notesManager.recentNotes)
        let searchedNotes = currentInputs.searchText.isEmpty ? nil : notesManager.searchNotes(query: currentInputs.searchText).filter { !receiptManager.isHiddenMigratedReceiptNote($0.id) }

        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let foldersById = Dictionary(uniqueKeysWithValues: foldersSnapshot.map { ($0.id, $0) })
            let receiptsFolderId = foldersSnapshot.first(where: { $0.name == "Receipts" })?.id
            let standardNoteFilter: (Note) -> Bool = { note in
                Self.isStandardNotesListNote(
                    note,
                    foldersById: foldersById,
                    receiptsFolderId: receiptsFolderId
                )
            }

            var pinned = (searchedNotes ?? pinnedNotesSnapshot)
                .filter { searchedNotes == nil ? true : $0.isPinned }
            var unpinned = (searchedNotes ?? recentNotesSnapshot)
                .filter { searchedNotes == nil ? true : !$0.isPinned }

            if currentInputs.showUnfiledNotesOnly {
                pinned = pinned.filter { $0.folderId == nil }
                unpinned = unpinned.filter { $0.folderId == nil }
            } else if let selectedFolderId = currentInputs.selectedFolderId {
                pinned = pinned.filter { $0.folderId == selectedFolderId }
                unpinned = unpinned.filter { $0.folderId == selectedFolderId }
            }

            pinned = pinned.filter(standardNoteFilter)
            unpinned = unpinned.filter(standardNoteFilter)

            let standardNotes = notesSnapshot
                .filter(standardNoteFilter)
                .sorted { $0.dateModified > $1.dateModified }
            let scopedStandardNotes: [Note]
            if currentInputs.showUnfiledNotesOnly {
                scopedStandardNotes = standardNotes.filter { !$0.isPinned && $0.folderId == nil }
            } else if let selectedFolderId = currentInputs.selectedFolderId {
                scopedStandardNotes = standardNotes.filter { $0.folderId == selectedFolderId }
            } else if currentInputs.showPinnedNotesOnly {
                scopedStandardNotes = standardNotes.filter { $0.isPinned }
            } else {
                scopedStandardNotes = standardNotes
            }

            let monthGroupedNotes: [Note]
            if currentInputs.showPinnedNotesOnly {
                monthGroupedNotes = scopedStandardNotes
            } else if currentInputs.showUnfiledNotesOnly || currentInputs.selectedFolderId != nil {
                monthGroupedNotes = scopedStandardNotes
            } else {
                monthGroupedNotes = scopedStandardNotes.filter { !$0.isPinned }
            }

            let calendar = Calendar.current
            let now = Date()
            let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            let recent = unpinned.filter { $0.dateModified >= oneWeekAgo }

            let monthYearFormatter = DateFormatter()
            monthYearFormatter.dateFormat = "MMMM yyyy"
            let grouped = Dictionary(grouping: monthGroupedNotes) { note in
                monthYearFormatter.string(from: note.dateModified)
            }
            let groupedByMonth = grouped
                .map { month, notes in
                    (
                        month: month,
                        notes: notes.sorted { $0.dateModified > $1.dateModified }
                    )
                }
                .sorted { lhs, rhs in
                    guard let leftDate = lhs.notes.first?.dateModified,
                          let rightDate = rhs.notes.first?.dateModified else {
                        return false
                    }
                    return leftDate > rightDate
                }

            let meaningfulJournalEntries = notesSnapshot.filter { $0.isJournalEntry && $0.isMeaningfulJournalEntry }
            let nextJournalOverviewStats = Self.journalStats(
                for: meaningfulJournalEntries,
                referenceDate: now,
                calendar: calendar
            )
            let nextLatestJournalRecap = notesSnapshot
                .filter { $0.isJournalWeeklyRecap }
                .sorted {
                    let lhs = $0.journalWeekStartDate ?? $0.dateModified
                    let rhs = $1.journalWeekStartDate ?? $1.dateModified
                    return lhs > rhs
                }
                .first

            let nextDisplayedNotes = scopedStandardNotes

            let nextLooseNotesCount = standardNotes.filter { $0.folderId == nil }.count
            let nextFolderNotesCount = currentInputs.selectedFolderId.map { selectedFolderId in
                standardNotes.filter { $0.folderId == selectedFolderId }.count
            } ?? 0
            let nextDashboardFolderCount = foldersSnapshot.filter { folder in
                folder.name != "Receipts" && folder.name != "Journal"
            }.count

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation, self.inputs == currentInputs else { return }

                if self.filteredPinnedNotes != pinned {
                    self.filteredPinnedNotes = pinned
                }

                if self.allUnpinnedNotes != unpinned {
                    self.allUnpinnedNotes = unpinned
                }

                if self.recentNotes != recent {
                    self.recentNotes = recent
                }

                let didChangeNotesByMonth = self.notesByMonth.count != groupedByMonth.count
                    || zip(self.notesByMonth, groupedByMonth).contains { pair in
                        pair.0.month != pair.1.month || pair.0.notes != pair.1.notes
                    }
                if didChangeNotesByMonth {
                    self.notesByMonth = groupedByMonth
                }

                if self.displayedNotes != nextDisplayedNotes {
                    self.displayedNotes = nextDisplayedNotes
                }

                self.looseNotesCount = nextLooseNotesCount
                self.folderNotesCount = nextFolderNotesCount
                self.dashboardFolderCount = nextDashboardFolderCount
                self.journalEntries = meaningfulJournalEntries
                    .sorted { ($0.journalDate ?? $0.dateModified) > ($1.journalDate ?? $1.dateModified) }
                self.latestJournalRecap = nextLatestJournalRecap
                self.journalOverviewStats = nextJournalOverviewStats

                if includeAggregates {
                    self.refreshAggregates()
                }
            }
        }
    }

    private static func isStandardNotesListNote(
        _ note: Note,
        foldersById: [UUID: NoteFolder],
        receiptsFolderId: UUID?
    ) -> Bool {
        !isReceiptNote(note, foldersById: foldersById, receiptsFolderId: receiptsFolderId)
            && !note.isJournalEntry
            && !note.isJournalWeeklyRecap
    }

    private static func isReceiptNote(
        _ note: Note,
        foldersById: [UUID: NoteFolder],
        receiptsFolderId: UUID?
    ) -> Bool {
        guard let receiptsFolderId, let folderId = note.folderId else { return false }

        var currentFolderId: UUID? = folderId
        while let currentId = currentFolderId {
            if currentId == receiptsFolderId {
                return true
            }
            currentFolderId = foldersById[currentId]?.parentFolderId
        }

        return false
    }

    private static func journalStats(
        for entries: [Note],
        referenceDate: Date,
        calendar: Calendar
    ) -> JournalStats {
        let uniqueEntryDays = Set(
            entries.compactMap { entry in
                entry.journalDate.map { calendar.startOfDay(for: $0) }
            }
        )

        let sortedDays = uniqueEntryDays.sorted(by: >)
        let today = calendar.startOfDay(for: referenceDate)
        let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        let completedThisWeek = uniqueEntryDays.filter { day in
            guard let currentWeekInterval else { return false }
            return currentWeekInterval.contains(day)
        }.count

        var currentStreak = 0
        var cursor = today
        while uniqueEntryDays.contains(cursor) {
            currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var longestStreak = 0
        var activeStreak = 0
        var previousDay: Date?
        for day in sortedDays.reversed() {
            if let previousDay,
               let expectedNext = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(expectedNext, inSameDayAs: day) {
                activeStreak += 1
            } else {
                activeStreak = 1
            }
            longestStreak = max(longestStreak, activeStreak)
            previousDay = day
        }

        return JournalStats(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            completedThisWeek: completedThisWeek,
            totalEntries: uniqueEntryDays.count,
            lastEntryDate: sortedDays.first,
            todayStatus: uniqueEntryDays.contains(today) ? .complete : .missing
        )
    }

    private func refreshAggregates() {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let yearlySummary = receiptManager.receiptStatistics(year: currentYear).first
            ?? receiptManager.receiptStatistics().first

        let nextMonthlySummaries: [MonthlyReceiptSummary]
        if let yearlySummary {
            if inputs.showsCurrentMonthOnly {
                nextMonthlySummaries = Array(yearlySummary.monthlySummaries.prefix(1))
            } else {
                nextMonthlySummaries = yearlySummary.monthlySummaries
            }
        } else {
            nextMonthlySummaries = []
        }

        let nextReceiptTotal = nextMonthlySummaries.reduce(0) { $0 + $1.monthlyTotal }
        let nextReceiptCount = nextMonthlySummaries.reduce(0) { $0 + $1.receipts.count }
        let receiptCategoryTotals = nextMonthlySummaries
            .flatMap(\.receipts)
            .reduce(into: [String: Double]()) { partialResult, receipt in
                let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(
                    title: receipt.title,
                    content: nil
                ) ?? "Other"
                partialResult[category, default: 0] += receipt.amount
            }
        let nextTopReceiptCategories = receiptCategoryTotals
            .map { (category: $0.key, total: $0.value) }
            .sorted { lhs, rhs in
                if lhs.total == rhs.total {
                    return lhs.category < rhs.category
                }
                return lhs.total > rhs.total
            }

        let activeRecurringExpenses = recurringExpenses
            .filter { expense in
                expense.isActive && (expense.endDate == nil || expense.endDate! >= now)
            }
            .sorted { $0.nextOccurrence < $1.nextOccurrence }

        let nextRecurringExpenses: [RecurringExpense]
        if inputs.showsCurrentMonthOnly {
            nextRecurringExpenses = activeRecurringExpenses.filter {
                calendar.isDate($0.nextOccurrence, equalTo: now, toGranularity: .month)
            }
        } else {
            nextRecurringExpenses = activeRecurringExpenses
        }

        let nextRecurringTotal: Double
        if inputs.showsCurrentMonthOnly {
            nextRecurringTotal = nextRecurringExpenses.reduce(0) { total, expense in
                total + Double(truncating: expense.amount as NSDecimalNumber)
            }
        } else {
            nextRecurringTotal = nextRecurringExpenses.reduce(0) { total, expense in
                total + Double(truncating: expense.yearlyAmount as NSDecimalNumber)
            }
        }

        let nextUpcomingRecurringCount: Int
        if inputs.showsCurrentMonthOnly {
            nextUpcomingRecurringCount = nextRecurringExpenses.filter {
                calendar.isDate($0.nextOccurrence, equalTo: now, toGranularity: .month)
            }.count
        } else {
            nextUpcomingRecurringCount = nextRecurringExpenses.count
        }

        hubReceiptMonthlySummaries = nextMonthlySummaries
        hubReceiptTotal = nextReceiptTotal
        hubReceiptCount = nextReceiptCount
        hubTopReceiptCategories = nextTopReceiptCategories
        hubRecurringExpenses = nextRecurringExpenses
        recurringHubTotal = nextRecurringTotal
        upcomingRecurringCount = nextUpcomingRecurringCount
    }
}
