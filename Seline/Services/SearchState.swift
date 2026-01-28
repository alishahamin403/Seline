import Foundation

/**
 * SearchState - Focused state for search functionality
 *
 * Split from SearchService to reduce over-subscription.
 * Views that only care about search can subscribe to just this.
 */
@MainActor
class SearchState: ObservableObject {
    // MARK: - Published Properties

    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var currentQueryType: QueryType = .search

    // Streaming response support
    @Published var enableStreamingResponses: Bool = true
    @Published var questionResponse: String?

    // MARK: - Private State

    private var streamingMessageID: UUID?

    // MARK: - Public Methods

    func startSearch(query: String, type: QueryType = .search) {
        self.searchQuery = query
        self.currentQueryType = type
        isSearching = true
    }

    func updateResults(_ results: [SearchResult]) {
        self.searchResults = results
        isSearching = false
    }

    func clearResults() {
        searchResults = []
        searchQuery = ""
        questionResponse = nil
    }

    func setQuestionResponse(_ response: String) {
        questionResponse = response
    }

    func startStreaming(messageId: UUID) {
        streamingMessageID = messageId
    }

    func stopStreaming() {
        streamingMessageID = nil
    }
}
