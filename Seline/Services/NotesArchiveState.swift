import Combine
import Foundation

struct NotesArchiveMonthGroup: Identifiable, Equatable {
    let month: String
    let notes: [Note]

    var id: String { month }
}

@MainActor
final class NotesArchiveState: ObservableObject {
    @Published private(set) var monthGroups: [NotesArchiveMonthGroup] = []
    @Published private(set) var totalVisibleNotes: Int = 0

    private let notesManager: NotesManager
    private var cancellables = Set<AnyCancellable>()
    private var refreshGeneration = 0

    init(notesManager: NotesManager? = nil) {
        self.notesManager = notesManager ?? .shared

        self.notesManager.$notes
            .combineLatest(self.notesManager.$folders)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    func refresh() {
        let notesSnapshot = notesManager.notes
        let foldersSnapshot = notesManager.folders

        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let foldersById = Dictionary(uniqueKeysWithValues: foldersSnapshot.map { ($0.id, $0) })
            let receiptsFolderId = foldersSnapshot.first(where: { $0.name == "Receipts" })?.id
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"

            let standardNotes = notesSnapshot
                .filter { note in
                    Self.isStandardArchiveNote(
                        note,
                        foldersById: foldersById,
                        receiptsFolderId: receiptsFolderId
                    )
                }

            let grouped = Dictionary(grouping: standardNotes) { note in
                monthFormatter.string(from: note.dateModified)
            }

            let nextMonthGroups = grouped
                .map { month, notes in
                    NotesArchiveMonthGroup(
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
            let nextTotalVisibleNotes = nextMonthGroups.reduce(0) { $0 + $1.notes.count }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation else { return }

                if self.monthGroups != nextMonthGroups {
                    self.monthGroups = nextMonthGroups
                }
                self.totalVisibleNotes = nextTotalVisibleNotes
            }
        }
    }

    private static func isStandardArchiveNote(
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
}
