import Foundation
import Combine

/// Lightweight app-wide search/action draft state.
@MainActor
class SearchService: ObservableObject {
    static let shared = SearchService()

    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var pendingEventCreation: EventCreationData? = nil
    @Published var pendingNoteCreation: NoteCreationData? = nil
    @Published var pendingNoteUpdate: NoteUpdateData? = nil

    private init() {}

    func registerSearchableProvider(_ provider: Any) {}
    func clearSearch() { searchQuery = "" }
    func clearSearchOnLogout() {
        searchQuery = ""
        pendingEventCreation = nil
        pendingNoteCreation = nil
        pendingNoteUpdate = nil
    }
}
