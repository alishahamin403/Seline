import Foundation
import Combine

/// Tracks conversation context including recent searches, topics, and user intent
/// to improve search results and provide better contextual understanding
class ConversationContextService: ObservableObject {
    static let shared = ConversationContextService()

    private init() {}

    // MARK: - Models

    struct SearchContext {
        let query: String
        let timestamp: Date
        let topics: [String]  // Extracted topics from the query
        let foundResults: Int  // How many results matched
        let selectedResult: String?  // Which result the user selected, if any
    }

    // MARK: - State Management

    @Published private(set) var recentSearches: [SearchContext] = []
    @Published private(set) var currentTopics: [String] = []  // Topics being discussed
    @Published private(set) var conversationHistory: [String] = []  // Recent search queries

    private let maxRecentSearches = 20
    private let maxHistoryItems = 100

    // MARK: - Public API

    /// Track a new search query
    func trackSearch(
        query: String,
        topics: [String],
        resultCount: Int,
        selectedResult: String? = nil
    ) {
        let context = SearchContext(
            query: query,
            timestamp: Date(),
            topics: topics,
            foundResults: resultCount,
            selectedResult: selectedResult
        )

        recentSearches.insert(context, at: 0)
        if recentSearches.count > maxRecentSearches {
            recentSearches.removeLast()
        }

        // Update current topics (aggregate from recent searches)
        updateCurrentTopics()

        // Add to conversation history
        conversationHistory.insert(query, at: 0)
        if conversationHistory.count > maxHistoryItems {
            conversationHistory.removeLast()
        }
    }

    /// Get context-aware query expansion based on recent conversation
    /// Examples:
    /// - If user just searched for "budget", and now searches "expenses" → they're related
    /// - If user searched "doctor", then "medical" → offer health-related items
    func getContextualSearchBoost() -> [String] {
        // Return topics that are currently being discussed
        return currentTopics
    }

    /// Check if current search is related to recent searches
    func isRelatedToRecentContext(_ query: String) -> Bool {
        let lowerQuery = query.lowercased()

        // Check if query contains any recent topics
        for topic in currentTopics {
            if lowerQuery.contains(topic.lowercased()) {
                return true
            }
        }

        // Check if query is similar to any recent search
        for context in recentSearches.prefix(5) {
            let similarity = calculateStringSimilarity(query, context.query)
            if similarity > 0.5 {
                return true
            }
        }

        return false
    }

    /// Get related search suggestions based on conversation context
    func getRelatedSearchSuggestions() -> [String] {
        var suggestions: [String] = []

        // Get unique topics from recent searches
        var topicCounts: [String: Int] = [:]
        for context in recentSearches {
            for topic in context.topics {
                topicCounts[topic, default: 0] += 1
            }
        }

        // Sort by frequency and return top suggestions
        suggestions = topicCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        return suggestions
    }

    /// Extract potential search topics/entities from a query
    func extractTopicsFromQuery(_ query: String) -> [String] {
        var topics: [String] = []
        let lowerQuery = query.lowercased()

        // Extract hashtags
        let hashtagPattern = "#[a-zA-Z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let nsString = query as NSString
            let matches = regex.matches(in: query, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range, in: query) {
                    let hashtag = String(query[range]).lowercased().dropFirst()
                    topics.append(String(hashtag))
                }
            }
        }

        // Extract category keywords
        let categoryKeywords = [
            "finance", "expense", "budget", "cost", "money",
            "health", "doctor", "medical", "appointment",
            "work", "meeting", "project", "deadline",
            "travel", "trip", "flight", "hotel",
            "personal", "family", "friend", "home",
            "shopping", "store", "purchase", "order"
        ]

        for keyword in categoryKeywords {
            if lowerQuery.contains(keyword) {
                topics.append(keyword)
            }
        }

        return Array(Set(topics))  // Remove duplicates
    }

    /// Boost scoring for items related to current conversation context
    func getContextBoost(for itemTopics: [String]) -> Double {
        let relevantTopics = itemTopics.filter { currentTopics.contains($0) }

        if !relevantTopics.isEmpty {
            // Boost by 1.0-2.0 points depending on how many topics match
            return Double(relevantTopics.count) * 0.5 + 0.5
        }

        return 0.0
    }

    /// Clear conversation context (called when user exits search mode or starts new conversation)
    func clearContext() {
        currentTopics = []
        conversationHistory = []
        recentSearches = []
    }

    /// Check if this search could be a follow-up or refinement to a previous search
    func isPossibleFollowUp(_ newQuery: String) -> SearchContext? {
        let lowerNewQuery = newQuery.lowercased()

        // Look at most recent searches
        for context in recentSearches.prefix(3) {
            let lowerOldQuery = context.query.lowercased()

            // Check for common phrases (user refining search)
            if lowerNewQuery.contains("more") || lowerNewQuery.contains("also") ||
               lowerNewQuery.contains("another") || lowerNewQuery.contains("and") {

                // This might be a refinement - check if it's related
                let similarity = calculateStringSimilarity(newQuery, context.query)
                if similarity > 0.3 {
                    return context
                }
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    private func updateCurrentTopics() {
        var topicCounts: [String: Int] = [:]

        // Get topics from recent 5 searches (weighted by recency)
        for (index, context) in recentSearches.prefix(5).enumerated() {
            let weight = 5 - index  // More recent = higher weight
            for topic in context.topics {
                topicCounts[topic, default: 0] += weight
            }
        }

        // Keep topics that appeared multiple times or recently
        currentTopics = topicCounts.filter { $0.value >= 2 }.map { $0.key }
    }

    /// Calculate string similarity (Levenshtein distance)
    private func calculateStringSimilarity(_ str1: String, _ str2: String) -> Double {
        let distance = levenshteinDistance(str1.lowercased(), str2.lowercased())
        let maxLength = max(str1.count, str2.count)

        if maxLength == 0 {
            return 1.0
        }

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        let m = s1.count
        let n = s2.count

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            dp[i][0] = i
        }
        for j in 0...n {
            dp[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                if s1[i - 1] == s2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(
                        dp[i - 1][j],
                        dp[i][j - 1],
                        dp[i - 1][j - 1]
                    )
                }
            }
        }

        return dp[m][n]
    }
}
