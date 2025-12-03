import Foundation

/// Service for enhancing conversation with insights, patterns, and smart formatting
/// Provides tone adaptation, insight detection, and follow-up suggestion generation
@MainActor
class ConversationEnhancementService {
    static let shared = ConversationEnhancementService()

    // MARK: - Tone Adaptation

    /// Detects the query type to apply appropriate tone
    func detectQueryType(from message: String) -> QueryType {
        let lowercased = message.lowercased()

        // Analytics/Insights queries
        if lowercased.contains("pattern") || lowercased.contains("trend") ||
           lowercased.contains("compare") || lowercased.contains("most") {
            return .analytics
        }

        // Achievement/Completion queries
        if lowercased.contains("completed") || lowercased.contains("finished") ||
           lowercased.contains("done") || lowercased.contains("accomplished") {
            return .achievement
        }

        // Warning/Concern queries
        if lowercased.contains("overdue") || lowercased.contains("missed") ||
           lowercased.contains("warning") || lowercased.contains("late") {
            return .warning
        }

        // Planning queries
        if lowercased.contains("plan") || lowercased.contains("schedule") ||
           lowercased.contains("prepare") || lowercased.contains("next") {
            return .planning
        }

        // Money-related queries
        if lowercased.contains("spend") || lowercased.contains("expense") ||
           lowercased.contains("cost") || lowercased.contains("budget") ||
           lowercased.contains("$") {
            return .money
        }

        // Exploration/Discovery queries
        if lowercased.contains("show") || lowercased.contains("explore") ||
           lowercased.contains("tell me about") || lowercased.contains("what") {
            return .exploration
        }

        return .general
    }

    enum QueryType {
        case analytics      // Pattern-focused, curious tone
        case achievement    // Celebratory, encouraging tone
        case warning        // Empathetic, helpful tone
        case planning       // Supportive, practical tone
        case money          // Clear, non-judgmental tone
        case exploration    // Conversational, discovery tone
        case general        // Neutral, helpful tone
    }

    // MARK: - Follow-Up Suggestion Generation

    /// Generates contextual follow-up suggestions based on response content and query type
    func generateFollowUpSuggestions(
        for message: String,
        queryType: QueryType,
        dataTypes: [String]
    ) -> [FollowUpSuggestion] {
        var suggestions: [FollowUpSuggestion] = []

        let lowercased = message.lowercased()

        // Add suggestions based on query type
        switch queryType {
        case .analytics:
            if lowercased.contains("trend") {
                suggestions.append(
                    FollowUpSuggestion(
                        text: "Show me the specific dates",
                        emoji: "📅",
                        category: .moreDetails
                    )
                )
            }
            if lowercased.contains("compare") {
                suggestions.append(
                    FollowUpSuggestion(
                        text: "What about last month?",
                        emoji: "📊",
                        category: .relatedData
                    )
                )
            }

        case .money:
            if lowercased.contains("spent") {
                suggestions.append(
                    FollowUpSuggestion(
                        text: "Should we set a budget?",
                        emoji: "💰",
                        category: .action
                    )
                )
            }
            if lowercased.contains("spending") {
                suggestions.append(
                    FollowUpSuggestion(
                        text: "Break down by category",
                        emoji: "📊",
                        category: .moreDetails
                    )
                )
            }

        case .planning:
            suggestions.append(
                FollowUpSuggestion(
                    text: "How can I help you prepare?",
                    emoji: "🎯",
                    category: .action
                )
            )

        case .achievement:
            suggestions.append(
                FollowUpSuggestion(
                    text: "Keep up the momentum!",
                    emoji: "🚀",
                    category: .discovery
                )
            )

        case .warning:
            suggestions.append(
                FollowUpSuggestion(
                    text: "Help me catch up",
                    emoji: "⚡",
                    category: .action
                )
            )

        case .exploration:
            suggestions.append(
                FollowUpSuggestion(
                    text: "Dig deeper",
                    emoji: "🔍",
                    category: .discovery
                )
            )

        case .general:
            suggestions.append(
                FollowUpSuggestion(
                    text: "Tell me more",
                    emoji: "💬",
                    category: .discovery
                )
            )
        }

        // Add data-type specific suggestions
        if dataTypes.contains("receipt") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Show receipt details",
                    emoji: "🧾",
                    category: .moreDetails
                )
            )
        }

        if dataTypes.contains("event") || dataTypes.contains("calendar") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "What's coming up?",
                    emoji: "⏰",
                    category: .relatedData
                )
            )
        }

        if dataTypes.contains("location") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Where else have I been?",
                    emoji: "📍",
                    category: .relatedData
                )
            )
        }

        // Limit to 1-2 suggestions max (not 3) for better UX
        return Array(suggestions.prefix(2))
    }

    /// Generates smart follow-up suggestions based on the LLM's actual response content
    /// This creates more relevant suggestions by analyzing what was actually returned
    func generateResponseBasedSuggestions(
        for responseContent: String,
        originalQuery: String,
        queryType: QueryType
    ) -> [FollowUpSuggestion] {
        var suggestions: [FollowUpSuggestion] = []
        let response = responseContent.lowercased()
        let query = originalQuery.lowercased()

        // Detect numbers/data in response and suggest drilling down
        if response.contains("$") && response.contains("%") {
            // Spending data with percentages - suggest breakdown
            suggestions.append(
                FollowUpSuggestion(
                    text: "Which category should I focus on?",
                    emoji: "🔍",
                    category: .moreDetails
                )
            )
        }

        // Detect time periods and suggest comparison
        if (response.contains("this month") || response.contains("last month") ||
            response.contains("this week") || response.contains("last week")) &&
           !query.contains("compare") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "How does this compare to last period?",
                    emoji: "📊",
                    category: .relatedData
                )
            )
        }

        // Detect patterns and suggest investigation
        if response.contains("pattern") || response.contains("trend") || response.contains("increasing") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Why do you think that's happening?",
                    emoji: "🤔",
                    category: .discovery
                )
            )
        }

        // Detect warnings and suggest action
        if response.contains("above") || response.contains("unusual") || response.contains("higher than") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Should I adjust my spending?",
                    emoji: "⚠️",
                    category: .action
                )
            )
        }

        // Detect schedule/calendar info and suggest next steps
        if response.contains("scheduled") || response.contains("upcoming") || response.contains("calendar") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Help me prepare for this",
                    emoji: "📝",
                    category: .action
                )
            )
        }

        // Detect locations and suggest related queries
        if response.contains("@") || response.contains("location") || response.contains("visited") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "When was I last there?",
                    emoji: "📍",
                    category: .relatedData
                )
            )
        }

        // If response shows limited data, suggest broader search
        if response.contains("don't have") || response.contains("not much") || response.contains("no data") {
            suggestions.append(
                FollowUpSuggestion(
                    text: "Try searching a different timeframe",
                    emoji: "📅",
                    category: .moreDetails
                )
            )
        }

        // Limit to 1 suggestion max to avoid overwhelming
        return Array(suggestions.prefix(1))
    }

    // MARK: - Pattern Detection & Insights

    /// Detects potential insights or patterns in user's data
    func detectPotentialInsights(from conversation: [ConversationMessage]) -> [String] {
        var insights: [String] = []

        let recentMessages = conversation.suffix(5)

        // Check if user is asking about similar topics repeatedly
        let topics = recentMessages.map { $0.text.lowercased() }
        let topicCounts = Dictionary(grouping: topics, by: { $0 })
        let repeatingTopics = topicCounts.filter { $0.value.count > 1 }.keys

        if !repeatingTopics.isEmpty {
            insights.append("You've asked about this a few times - want me to summarize what we've covered?")
        }

        return insights
    }

    /// Generates contextual proactive suggestions based on patterns
    func generateProactiveInsight(from context: String) -> String? {
        let lowercased = context.lowercased()

        // Coffee spending pattern
        if lowercased.contains("coffee") && lowercased.contains("daily") {
            return "You're a consistent coffee drinker! ☕ Ever thought about a subscription?"
        }

        // High spending pattern
        if lowercased.contains("high") || lowercased.contains("above") {
            return "You're spending above your usual pace. Want to review the details?"
        }

        // Productivity milestone
        if lowercased.contains("100%") || lowercased.contains("all") && lowercased.contains("completed") {
            return "Perfect week! You crushed every goal! 🎉"
        }

        return nil
    }

    // MARK: - Format Enhancement

    /// Adds visual markers to response text for better readability
    func enhanceFormattingWithMarkers(_ text: String) -> String {
        var result = text

        // Add markers for key patterns (these are suggestions for the LLM)
        // The LLM should naturally include these in responses following the system prompt

        return result
    }

    /// Generates a visual progress indicator
    func generateProgressBar(completed: Int, total: Int, width: Int = 10) -> String {
        let percentage = Double(completed) / Double(total)
        let filledCount = Int(percentage * Double(width))

        var bar = ""
        for i in 0..<width {
            bar += i < filledCount ? "█" : "░"
        }

        return "\(bar) \(completed)/\(total)"
    }

    /// Formats a trend with emoji indicator
    func formatTrend(current: Double, previous: Double) -> String {
        let change = current - previous
        let percentChange = (change / previous) * 100

        if change > 0 {
            return "📈 +\(String(format: "%.0f", percentChange))%"
        } else if change < 0 {
            return "📉 \(String(format: "%.0f", percentChange))%"
        } else {
            return "➡️ No change"
        }
    }
}
