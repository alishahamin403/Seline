import SwiftUI

enum NotesFloatingActionPage {
    case notes
    case receipts
    case recurring
}

enum MapsFloatingActionMode {
    case places
    case people
}

final class FloatingActionCoordinator: ObservableObject {
    static let shared = FloatingActionCoordinator()

    @Published var isNotesFloatingActionVisible = true
    @Published var notesFloatingActionPage: NotesFloatingActionPage = .notes
    @Published var isMapsFloatingActionVisible = true
    @Published var mapsFloatingActionMode: MapsFloatingActionMode = .places

    private init() {}

    func updateNotes(isVisible: Bool, page: NotesFloatingActionPage) {
        if isNotesFloatingActionVisible != isVisible {
            isNotesFloatingActionVisible = isVisible
        }

        if notesFloatingActionPage != page {
            notesFloatingActionPage = page
        }
    }

    func updateMaps(isVisible: Bool, mode: MapsFloatingActionMode) {
        if isMapsFloatingActionVisible != isVisible {
            isMapsFloatingActionVisible = isVisible
        }

        if mapsFloatingActionMode != mode {
            mapsFloatingActionMode = mode
        }
    }
}

extension Notification.Name {
    static let notesShellAddRequested = Notification.Name("NotesShellAddRequested")
    static let notesShellNewNoteRequested = Notification.Name("NotesShellNewNoteRequested")
    static let notesShellNewJournalRequested = Notification.Name("NotesShellNewJournalRequested")
    static let mapsShellAddRequested = Notification.Name("MapsShellAddRequested")
    static let mapsShellNewFolderRequested = Notification.Name("MapsShellNewFolderRequested")
    static let openReceiptsFromMainApp = Notification.Name("OpenReceiptsFromMainApp")
    static let openRecurringFromMainApp = Notification.Name("OpenRecurringFromMainApp")
}
