import Combine
import Foundation

@MainActor
final class NotesHubState: ObservableObject {
    struct Inputs: Equatable {
        let searchText: String
        let selectedFolderId: UUID?
        let showUnfiledNotesOnly: Bool
        let showsCurrentMonthOnly: Bool
    }

    @Published private(set) var filteredPinnedNotes: [Note] = []
    @Published private(set) var allUnpinnedNotes: [Note] = []
    @Published private(set) var recentNotes: [Note] = []
    @Published private(set) var notesByMonth: [(month: String, notes: [Note])] = []
    @Published private(set) var hubReceiptMonthlySummaries: [MonthlyReceiptSummary] = []
    @Published private(set) var hubReceiptTotal: Double = 0
    @Published private(set) var hubReceiptCount: Int = 0
    @Published private(set) var hubTopReceiptCategories: [(category: String, total: Double)] = []
    @Published private(set) var hubRecurringExpenses: [RecurringExpense] = []
    @Published private(set) var recurringHubTotal: Double = 0
    @Published private(set) var upcomingRecurringCount: Int = 0

    private let notesManager: NotesManager
    private var cancellables = Set<AnyCancellable>()
    private var inputs = Inputs(
        searchText: "",
        selectedFolderId: nil,
        showUnfiledNotesOnly: false,
        showsCurrentMonthOnly: false
    )
    private var recurringExpenses: [RecurringExpense] = []

    init(notesManager: NotesManager? = nil) {
        self.notesManager = notesManager ?? .shared

        self.notesManager.$notes
            .combineLatest(self.notesManager.$folders)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func updateInputs(
        searchText: String,
        selectedFolderId: UUID?,
        showUnfiledNotesOnly: Bool,
        showsCurrentMonthOnly: Bool
    ) {
        let nextInputs = Inputs(
            searchText: searchText,
            selectedFolderId: selectedFolderId,
            showUnfiledNotesOnly: showUnfiledNotesOnly,
            showsCurrentMonthOnly: showsCurrentMonthOnly
        )

        guard nextInputs != inputs else { return }
        inputs = nextInputs
        refresh()
    }

    func updateRecurringExpenses(_ expenses: [RecurringExpense]) {
        recurringExpenses = expenses
        refreshAggregates()
    }

    func refresh() {
        let searchText = inputs.searchText
        let selectedFolderId = inputs.selectedFolderId
        let showUnfiledNotesOnly = inputs.showUnfiledNotesOnly

        let searchedNotes = searchText.isEmpty ? nil : notesManager.searchNotes(query: searchText)

        var pinned = (searchedNotes ?? notesManager.pinnedNotes)
            .filter { searchedNotes == nil ? true : $0.isPinned }

        var unpinned = (searchedNotes ?? notesManager.recentNotes)
            .filter { searchedNotes == nil ? true : !$0.isPinned }

        if showUnfiledNotesOnly {
            pinned = pinned.filter { $0.folderId == nil }
            unpinned = unpinned.filter { $0.folderId == nil }
        } else if let selectedFolderId {
            pinned = pinned.filter { $0.folderId == selectedFolderId }
            unpinned = unpinned.filter { $0.folderId == selectedFolderId }
        }

        pinned = pinned.filter(Self.isStandardNotesListNote)
        unpinned = unpinned.filter(Self.isStandardNotesListNote)

        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = unpinned.filter { $0.dateModified >= oneWeekAgo }
        let olderNotes = unpinned.filter { $0.dateModified < oneWeekAgo }

        let grouped = Dictionary(grouping: olderNotes) { note in
            FormatterCache.monthYear.string(from: note.dateModified)
        }
        let groupedByMonth = grouped
            .map { (month: $0.key, notes: $0.value) }
            .sorted { lhs, rhs in
                guard let leftDate = lhs.notes.first?.dateModified,
                      let rightDate = rhs.notes.first?.dateModified else {
                    return false
                }
                return leftDate > rightDate
            }

        filteredPinnedNotes = pinned
        allUnpinnedNotes = unpinned
        recentNotes = recent
        notesByMonth = groupedByMonth
        refreshAggregates()
    }

    private static func isStandardNotesListNote(_ note: Note) -> Bool {
        !note.isJournalEntry && !note.isJournalWeeklyRecap
    }

    private func refreshAggregates() {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let yearlySummary = notesManager.getReceiptStatistics(year: currentYear).first
            ?? notesManager.getReceiptStatistics().first

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
