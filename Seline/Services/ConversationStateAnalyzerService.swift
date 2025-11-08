import Foundation

/// Analyzes conversation history to determine current context and avoid redundancy
class ConversationStateAnalyzerService {

    /// Analyze conversation history to determine current state
    static func analyzeConversationState(
        currentQuery: String,
        conversationHistory: [ConversationMessage]
    ) -> ConversationState {
        let topicsDiscussed = extractTopicsFromHistory(conversationHistory)
        let lastQuestionType = identifyLastQuestionType(conversationHistory)
        let isProbablyFollowUp = detectFollowUpQuestion(currentQuery, history: conversationHistory)
        let suggestedApproach = determineSuggestedApproach(
            query: currentQuery,
            topicsDiscussed: topicsDiscussed,
            isFollowUp: isProbablyFollowUp,
            lastQuestionType: lastQuestionType
        )

        return ConversationState(
            topicsDiscussed: topicsDiscussed,
            lastQuestionType: lastQuestionType,
            isProbablyFollowUp: isProbablyFollowUp,
            suggestedApproach: suggestedApproach
        )
    }

    // MARK: - Topic Extraction

    private static func extractTopicsFromHistory(_ history: [ConversationMessage]) -> [ConversationTopic] {
        var topics: [String: (context: String, count: Int, lastIndex: Int)] = [:]

        for (index, message) in history.enumerated() {
            let queryText = message.text.lowercased()

            // Detect topics based on keywords
            detectTopic("spending", in: queryText, index: index, into: &topics, keyword: "spend|cost|expensive|amount|total|paid|budget")
            detectTopic("restaurants", in: queryText, index: index, into: &topics, keyword: "restaurant|food|cuisine|dining|ate|lunch|dinner")
            detectTopic("events", in: queryText, index: index, into: &topics, keyword: "event|meeting|gym|workout|exercise|schedule|calendar")
            detectTopic("travel", in: queryText, index: index, into: &topics, keyword: "travel|trip|destination|flight|hotel|miles|eta")
            detectTopic("locations", in: queryText, index: index, into: &topics, keyword: "location|place|saved|distance|where")
            detectTopic("comparison", in: queryText, index: index, into: &topics, keyword: "vs|versus|compare|compared|difference|this month|last month")
            detectTopic("trends", in: queryText, index: index, into: &topics, keyword: "trend|increase|decrease|change|pattern|average")
            detectTopic("frequency", in: queryText, index: index, into: &topics, keyword: "often|frequent|how many|times|count")
        }

        // Convert to ConversationTopic array
        return topics.map { topic, data in
            ConversationTopic(
                topic: topic,
                context: data.context,
                messageCount: data.count,
                lastMentionedIndex: data.lastIndex
            )
        }
        .sorted { $0.lastMentionedIndex > $1.lastMentionedIndex }  // Most recent first
    }

    private static func detectTopic(
        _ topicName: String,
        in text: String,
        index: Int,
        into topics: inout [String: (context: String, count: Int, lastIndex: Int)],
        keyword pattern: String
    ) {
        if text.range(of: pattern, options: .regularExpression) != nil {
            if topics[topicName] == nil {
                topics[topicName] = (context: extractContext(from: text), count: 0, lastIndex: index)
            }
            topics[topicName]!.count += 1
            topics[topicName]!.lastIndex = index
        }
    }

    private static func extractContext(from text: String) -> String {
        // Extract first sentence as context
        let sentences = text.split(separator: ".")
        let context = String(sentences.first ?? "")
        return String(context.prefix(100))
    }

    // MARK: - Follow-up Detection

    private static func detectFollowUpQuestion(_ query: String, history: [ConversationMessage]) -> Bool {
        guard let lastMessage = history.last, !lastMessage.isUser else { return false }

        let queryLower = query.lowercased()

        // Explicit follow-up indicators
        let followUpKeywords = [
            "what about",
            "how about",
            "and",
            "also",
            "besides",
            "additionally",
            "another",
            "more about",
            "tell me more",
            "breakdown",
            "details",
            "specifically",
            "vs",
            "compared to",
            "instead",
            "rather"
        ]

        for keyword in followUpKeywords {
            if queryLower.hasPrefix(keyword) || queryLower.contains(" \(keyword) ") {
                return true
            }
        }

        // Check if query is asking about the same topic as last message
        let lastUserMessage = history.reversed().first(where: { $0.isUser })?.text.lowercased() ?? ""
        if isRelatedQuery(query, to: lastUserMessage) {
            return true
        }

        return false
    }

    private static func isRelatedQuery(_ current: String, to previous: String) -> Bool {
        let currentWords = Set(current.split(separator: " ").map { String($0).lowercased() })
        let previousWords = Set(previous.split(separator: " ").map { String($0).lowercased() })

        let common = currentWords.intersection(previousWords)
        return common.count > 3  // If 3+ words in common, probably related
    }

    // MARK: - Question Type Identification

    private static func identifyLastQuestionType(_ history: [ConversationMessage]) -> String? {
        guard let lastUserMessage = history.reversed().first(where: { $0.isUser }) else { return nil }

        let text = lastUserMessage.text.lowercased()

        if text.contains(regex: "spend|cost|budget|expensive|paid|amount|total") {
            return "spending"
        } else if text.contains(regex: "restaurant|food|cuisine|dining") {
            return "restaurant"
        } else if text.contains(regex: "event|meeting|gym|workout|schedule") {
            return "event"
        } else if text.contains(regex: "travel|trip|destination") {
            return "travel"
        } else if text.contains(regex: "location|place|saved") {
            return "location"
        } else if text.contains(regex: "compare|vs|versus|difference") {
            return "comparison"
        }

        return nil
    }

    // MARK: - Suggested Approach

    private static func determineSuggestedApproach(
        query: String,
        topicsDiscussed: [ConversationTopic],
        isFollowUp: Bool,
        lastQuestionType: String?
    ) -> String {
        var suggestions: [String] = []

        if isFollowUp && lastQuestionType != nil {
            // This is a follow-up
            suggestions.append("This is a FOLLOW-UP to previous question about \(lastQuestionType ?? "unknown").")
            suggestions.append("Don't repeat information already provided. Instead:")
            suggestions.append("- Provide deeper analysis or breakdown")
            suggestions.append("- Answer the specific aspect they're asking about")
            suggestions.append("- Offer comparison or related insights")
        } else {
            // New topic
            if topicsDiscussed.count > 3 {
                suggestions.append("User has asked about multiple topics: \(topicsDiscussed.map { $0.topic }.joined(separator: ", "))")
                suggestions.append("This is a NEW question - provide fresh analysis")
            } else {
                suggestions.append("User is exploring this topic for the first time")
                suggestions.append("Provide comprehensive answer with key insights")
            }
        }

        // Topic-specific suggestions
        if query.lowercased().contains(regex: "breakdown|detail|specific") {
            suggestions.append("User wants DETAILED breakdown - be specific and structured")
        }

        if query.lowercased().contains(regex: "compare|vs|versus|difference") {
            suggestions.append("User wants COMPARISON - clearly show differences side-by-side")
        }

        if query.lowercased().contains(regex: "trend|pattern|usually|average") {
            suggestions.append("User wants PATTERNS - focus on insights and trends, not just data")
        }

        return suggestions.joined(separator: "\n")
    }
}

// MARK: - Helper Extension

extension String {
    func contains(regex pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(self.startIndex..<self.endIndex, in: self)
            return regex.firstMatch(in: self, range: range) != nil
        } catch {
            return false
        }
    }
}
