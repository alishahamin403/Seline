import Combine
import Foundation

@MainActor
final class NotesHubState: ObservableObject {
    struct Inputs: Equatable {
        let searchText: String
        let selectedFolderId: UUID?
        let showUnfiledNotesOnly: Bool
    }

    @Published private(set) var filteredPinnedNotes: [Note] = []
    @Published private(set) var allUnpinnedNotes: [Note] = []
    @Published private(set) var recentNotes: [Note] = []
    @Published private(set) var notesByMonth: [(month: String, notes: [Note])] = []

    private let notesManager: NotesManager
    private var cancellables = Set<AnyCancellable>()
    private var inputs = Inputs(searchText: "", selectedFolderId: nil, showUnfiledNotesOnly: false)

    init(notesManager: NotesManager = .shared) {
        self.notesManager = notesManager

        notesManager.$notes
            .combineLatest(notesManager.$folders)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func updateInputs(
        searchText: String,
        selectedFolderId: UUID?,
        showUnfiledNotesOnly: Bool
    ) {
        let nextInputs = Inputs(
            searchText: searchText,
            selectedFolderId: selectedFolderId,
            showUnfiledNotesOnly: showUnfiledNotesOnly
        )

        guard nextInputs != inputs else { return }
        inputs = nextInputs
        refresh()
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
    }

    private static func isStandardNotesListNote(_ note: Note) -> Bool {
        !note.isJournalEntry && !note.isJournalWeeklyRecap
    }
}
