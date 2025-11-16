import Foundation

/// Structured context data ready for LLM consumption (JSON serializable)
struct StructuredLLMContext: Encodable {
    let metadata: ContextMetadata
    let context: ContextData
    let conversationHistory: [ConversationMessageJSON]

    struct ContextMetadata: Encodable {
        let timestamp: String
        let currentWeather: String?
        let userTimezone: String
        let intent: String
        let dateRangeQueried: String?
        let temporalContext: TemporalContextJSON?
        let followUpContext: FollowUpContextJSON?

        struct TemporalContextJSON: Encodable {
            let requestedPeriod: String
            let startDate: String
            let endDate: String
            let periodType: String  // "thisMonth", "lastWeek", etc.
        }

        struct FollowUpContextJSON: Encodable {
            let isFollowUp: Bool
            let previousTopic: String?
            let previousTimeframe: String?
            let relatedQueries: [String]?
        }
    }

    struct ContextData: Encodable {
        let notes: [NoteJSON]?
        let locations: [LocationJSON]?
        let tasks: [TaskJSON]?
        let emails: [EmailJSON]?
        let receipts: [ReceiptJSON]?
        let receiptSummary: ReceiptSummaryJSON?

        struct NoteJSON: Encodable {
            let id: String
            let title: String
            let excerpt: String
            let relevanceScore: Double
            let matchType: String
        }

        struct LocationJSON: Encodable {
            let id: String
            let name: String
            let category: String?
            let city: String?
            let province: String?
            let country: String?
            let userRating: Double?
            let relevanceScore: Double
            let matchType: String
            let distanceFromLocation: String?
        }

        struct TaskJSON: Encodable {
            let id: String
            let title: String
            let scheduledTime: String?
            let dayOfWeek: String?  // Explicit day of week to prevent LLM confusion
            let duration: Int?  // minutes
            let isCompleted: Bool
            let relevanceScore: Double
            let matchType: String
        }

        struct EmailJSON: Encodable {
            let id: String
            let from: String
            let subject: String
            let timestamp: String
            let isRead: Bool
            let excerpt: String
            let relevanceScore: Double
            let matchType: String
            let importanceIndicators: [String]
        }

        struct ReceiptJSON: Encodable {
            let id: String
            let merchant: String
            let amount: Double
            let date: String
            let category: String?
            let month: Int
            let year: Int
            let relevanceScore: Double
            let matchType: String
            let merchantType: String?  // NEW: Type of merchant (Pizzeria, Coffee Shop, etc)
            let merchantProducts: [String]?  // NEW: What products they sell
        }

        struct ReceiptSummaryJSON: Encodable {
            let totalAmount: Double
            let totalCount: Int
            let averageAmount: Double
            let highestAmount: Double
            let lowestAmount: Double
            let byCategory: [CategoryBreakdownJSON]

            struct CategoryBreakdownJSON: Encodable {
                let category: String
                let total: Double
                let count: Int
                let percentage: Double
            }
        }
    }

    struct ConversationMessageJSON: Encodable {
        let role: String  // "user" or "assistant"
        let content: String
    }
}

// MARK: - ContextBuilder Service

@MainActor
class ContextBuilder {
    static let shared = ContextBuilder()

    private init() {}

    // MARK: - Main Context Building

    /// Build structured context from filtered data and conversation history
    /// NOTE: This includes some pre-filtered data, but the LLM will do the final discovery
    /// of what's actually relevant, so we're not too aggressive with filtering
    func buildStructuredContext(
        from filteredContext: FilteredContext,
        conversationHistory: [ConversationMessage]
    ) -> StructuredLLMContext {
        // Analyze temporal context
        let temporalContext = extractTemporalContext(from: filteredContext)

        // Analyze follow-up context from conversation history
        let followUpContext = analyzeFollowUpContext(from: conversationHistory)

        // Build metadata
        let metadata = StructuredLLMContext.ContextMetadata(
            timestamp: formatLocalDateForLLM(Date()),
            currentWeather: filteredContext.metadata.currentWeather,
            userTimezone: filteredContext.metadata.userTimezone,
            intent: filteredContext.metadata.queryIntent,
            dateRangeQueried: filteredContext.metadata.dateRangeQueried,
            temporalContext: temporalContext,
            followUpContext: followUpContext
        )

        // Build context data - LLM will discover what's relevant
        // We provide data with relevance scores, but the LLM doesn't rely on them for discovery
        let contextData = StructuredLLMContext.ContextData(
            notes: buildNotesJSON(from: filteredContext.notes),
            locations: buildLocationsJSON(from: filteredContext.locations),
            tasks: buildTasksJSON(from: filteredContext.tasks),
            emails: buildEmailsJSON(from: filteredContext.emails),
            receipts: buildReceiptsJSON(from: filteredContext.receipts),
            receiptSummary: buildReceiptSummaryJSON(from: filteredContext.receiptStatistics)
        )

        // Build conversation history - LLM uses this for context
        let conversationJSON = buildConversationHistoryJSON(from: conversationHistory)

        return StructuredLLMContext(
            metadata: metadata,
            context: contextData,
            conversationHistory: conversationJSON
        )
    }

    /// Serialize structured context to JSON string for LLM
    func serializeToJSON(_ context: StructuredLLMContext) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(context)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("❌ Error serializing context to JSON: \(error)")
            return "{}"
        }
    }

    /// Build a compact version for token efficiency (removes some fields)
    func buildCompactJSON(_ context: StructuredLLMContext) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(context)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("❌ Error serializing compact context to JSON: \(error)")
            return "{}"
        }
    }

    // MARK: - JSON Builders

    /// Build notes JSON from filtered notes
    private func buildNotesJSON(from notes: [NoteWithRelevance]?) -> [StructuredLLMContext.ContextData.NoteJSON]? {
        guard let notes = notes, !notes.isEmpty else { return nil }

        return notes.map { noteWithRelevance in
            StructuredLLMContext.ContextData.NoteJSON(
                id: noteWithRelevance.note.id.uuidString,
                title: noteWithRelevance.note.title,
                excerpt: extractExcerpt(from: noteWithRelevance.note.content, maxLength: 200),
                relevanceScore: noteWithRelevance.relevanceScore,
                matchType: noteWithRelevance.matchType.rawValue
            )
        }
    }

    /// Build locations JSON from filtered locations
    private func buildLocationsJSON(from locations: [SavedPlaceWithRelevance]?) -> [StructuredLLMContext.ContextData.LocationJSON]? {
        guard let locations = locations, !locations.isEmpty else { return nil }

        return locations.map { locationWithRelevance in
            StructuredLLMContext.ContextData.LocationJSON(
                id: locationWithRelevance.place.id.uuidString,
                name: locationWithRelevance.place.name,
                category: locationWithRelevance.place.category,
                city: locationWithRelevance.place.city,
                province: locationWithRelevance.place.province,
                country: locationWithRelevance.place.country,
                userRating: locationWithRelevance.place.rating,
                relevanceScore: locationWithRelevance.relevanceScore,
                matchType: locationWithRelevance.matchType.rawValue,
                distanceFromLocation: locationWithRelevance.distanceFromLocation
            )
        }
    }

    /// Build tasks JSON from filtered tasks
    private func buildTasksJSON(from tasks: [TaskItemWithRelevance]?) -> [StructuredLLMContext.ContextData.TaskJSON]? {
        guard let tasks = tasks, !tasks.isEmpty else { return nil }

        let calendar = Calendar.current
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"  // Full weekday name (Monday, Tuesday, etc.)

        return tasks.map { taskWithRelevance in
            let duration: Int? = {
                if let scheduled = taskWithRelevance.task.scheduledTime,
                   let end = taskWithRelevance.task.endTime {
                    return Int(end.timeIntervalSince(scheduled) / 60)
                }
                return nil
            }()

            // Extract day of week from scheduled time
            let dayOfWeek: String? = taskWithRelevance.task.scheduledTime.map { date in
                weekdayFormatter.string(from: date)
            }

            return StructuredLLMContext.ContextData.TaskJSON(
                id: taskWithRelevance.task.id,
                title: taskWithRelevance.task.title,
                scheduledTime: taskWithRelevance.task.scheduledTime.map { formatLocalDateForLLM($0) },
                dayOfWeek: dayOfWeek,
                duration: duration,
                isCompleted: taskWithRelevance.task.isCompleted,
                relevanceScore: taskWithRelevance.relevanceScore,
                matchType: taskWithRelevance.matchType.rawValue
            )
        }
    }

    /// Build emails JSON from filtered emails
    private func buildEmailsJSON(from emails: [EmailWithRelevance]?) -> [StructuredLLMContext.ContextData.EmailJSON]? {
        guard let emails = emails, !emails.isEmpty else { return nil }

        return emails.map { emailWithRelevance in
            let senderName = emailWithRelevance.email.sender.name ?? emailWithRelevance.email.sender.email

            return StructuredLLMContext.ContextData.EmailJSON(
                id: emailWithRelevance.email.id,
                from: senderName,
                subject: emailWithRelevance.email.subject,
                timestamp: formatLocalDateForLLM(emailWithRelevance.email.timestamp),
                isRead: emailWithRelevance.email.isRead,
                excerpt: extractExcerpt(from: emailWithRelevance.email.body ?? "", maxLength: 300),
                relevanceScore: emailWithRelevance.relevanceScore,
                matchType: emailWithRelevance.matchType.rawValue,
                importanceIndicators: emailWithRelevance.importanceIndicators
            )
        }
    }

    /// Build receipts JSON from filtered receipts (includes merchant intelligence)
    private func buildReceiptsJSON(from receipts: [ReceiptWithRelevance]?) -> [StructuredLLMContext.ContextData.ReceiptJSON]? {
        guard let receipts = receipts, !receipts.isEmpty else { return nil }

        let calendar = Calendar.current

        return receipts.map { receiptWithRelevance in
            let dateComponents = calendar.dateComponents([.month, .year], from: receiptWithRelevance.receipt.date)
            let month = dateComponents.month ?? 0
            let year = dateComponents.year ?? 0

            return StructuredLLMContext.ContextData.ReceiptJSON(
                id: receiptWithRelevance.receipt.id.uuidString,
                merchant: receiptWithRelevance.receipt.title,
                amount: receiptWithRelevance.receipt.amount,
                date: formatLocalDateForLLM(receiptWithRelevance.receipt.date),
                category: receiptWithRelevance.receipt.category,
                month: month,
                year: year,
                relevanceScore: receiptWithRelevance.relevanceScore,
                matchType: receiptWithRelevance.matchType.rawValue,
                merchantType: receiptWithRelevance.merchantType,  // NEW: Merchant intelligence
                merchantProducts: receiptWithRelevance.merchantProducts  // NEW: What they sell
            )
        }
    }

    /// Build receipt summary JSON from statistics
    private func buildReceiptSummaryJSON(from stats: ReceiptStatistics?) -> StructuredLLMContext.ContextData.ReceiptSummaryJSON? {
        guard let stats = stats else { return nil }

        return StructuredLLMContext.ContextData.ReceiptSummaryJSON(
            totalAmount: stats.totalAmount,
            totalCount: stats.totalCount,
            averageAmount: stats.averageAmount,
            highestAmount: stats.highestAmount,
            lowestAmount: stats.lowestAmount,
            byCategory: stats.byCategory.map { category in
                StructuredLLMContext.ContextData.ReceiptSummaryJSON.CategoryBreakdownJSON(
                    category: category.category,
                    total: category.total,
                    count: category.count,
                    percentage: category.percentage
                )
            }
        )
    }

    /// Build conversation history JSON
    private func buildConversationHistoryJSON(from history: [ConversationMessage]) -> [StructuredLLMContext.ConversationMessageJSON] {
        return history.map { message in
            StructuredLLMContext.ConversationMessageJSON(
                role: message.isUser ? "user" : "assistant",
                content: message.text
            )
        }
    }

    // MARK: - Helper Methods

    /// Format a date in user's local timezone for LLM consumption
    /// Returns format like: "2025-11-12T14:00:00-05:00" (includes timezone offset)
    /// This ensures the LLM sees the exact local time with timezone info embedded
    private func formatLocalDateForLLM(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]  // Includes timezone offset
        return formatter.string(from: date)
    }

    /// Extract excerpt from text
    private func extractExcerpt(from text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }

        let truncated = String(text.prefix(maxLength))
        // Find the last space to avoid cutting in the middle of a word
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated + "..."
    }

    // MARK: - Temporal & Follow-up Context Analysis

    /// Extract temporal context from filtered context
    private func extractTemporalContext(from filteredContext: FilteredContext) -> StructuredLLMContext.ContextMetadata.TemporalContextJSON? {
        // Get the date range from metadata if available
        guard let dateRangeQueried = filteredContext.metadata.dateRangeQueried else {
            return nil
        }

        // Try to identify the period type
        let periodType = identifyRelativePeriod(dateRangeQueried)

        // Get start and end dates
        let (startDate, endDate) = getDateBoundsForPeriod(periodType)

        return StructuredLLMContext.ContextMetadata.TemporalContextJSON(
            requestedPeriod: dateRangeQueried,
            startDate: formatLocalDateForLLM(startDate),
            endDate: formatLocalDateForLLM(endDate),
            periodType: periodType
        )
    }

    /// Get date bounds for a given period
    private func getDateBoundsForPeriod(_ period: String) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current

        switch period.lowercased() {
        case "thismonth":
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return (start, end)

        case "lastmonth":
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let lastMonthEnd = calendar.date(byAdding: DateComponents(day: -1), to: currentMonthStart)!
            let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthEnd))!
            return (lastMonthStart, lastMonthEnd)

        case "nextmonth":
            let nextMonthStart = calendar.date(byAdding: DateComponents(month: 1), to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)!
            let nextMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: nextMonthStart)!
            return (nextMonthStart, nextMonthEnd)

        case "thisweek":
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = calendar.date(byAdding: DateComponents(day: 6), to: weekStart)!
            return (weekStart, weekEnd)

        case "lastweek":
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekEnd = calendar.date(byAdding: DateComponents(day: -1), to: thisWeekStart)!
            let lastWeekStart = calendar.date(byAdding: DateComponents(day: -6), to: lastWeekEnd)!
            return (lastWeekStart, lastWeekEnd)

        case "nextweek":
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let nextWeekStart = calendar.date(byAdding: DateComponents(day: 7), to: thisWeekStart)!
            let nextWeekEnd = calendar.date(byAdding: DateComponents(day: 6), to: nextWeekStart)!
            return (nextWeekStart, nextWeekEnd)

        case "today":
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
            return (start, end)

        case "yesterday":
            let yesterday = calendar.date(byAdding: DateComponents(day: -1), to: now)!
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
            return (start, end)

        case "tomorrow":
            let tomorrow = calendar.date(byAdding: DateComponents(day: 1), to: now)!
            let start = calendar.startOfDay(for: tomorrow)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
            return (start, end)

        default:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
            return (start, end)
        }
    }

    /// Analyze follow-up context from conversation history
    private func analyzeFollowUpContext(from conversationHistory: [ConversationMessage]) -> StructuredLLMContext.ContextMetadata.FollowUpContextJSON? {
        guard conversationHistory.count > 1 else {
            return StructuredLLMContext.ContextMetadata.FollowUpContextJSON(
                isFollowUp: false,
                previousTopic: nil,
                previousTimeframe: nil,
                relatedQueries: nil
            )
        }

        // Get the last user message(s) to detect topics
        var userMessages: [String] = []
        var assistantMessages: [String] = []

        for message in conversationHistory {
            if message.isUser {
                userMessages.append(message.text)
            } else {
                assistantMessages.append(message.text)
            }
        }

        // Detect if current query is a follow-up
        let isFollowUp = userMessages.count > 1
        var previousTopic: String?
        var relatedQueries: [String] = []

        // Extract topics from previous messages
        if userMessages.count > 1 {
            previousTopic = extractTopic(from: userMessages[userMessages.count - 2])
            relatedQueries = extractRelatedQueries(from: userMessages.dropLast(1).map { $0 })
        }

        // Detect common timeframes used in conversation
        let previousTimeframe = detectPreviousTimeframe(from: userMessages.dropLast(1).map { $0 })

        return StructuredLLMContext.ContextMetadata.FollowUpContextJSON(
            isFollowUp: isFollowUp,
            previousTopic: previousTopic,
            previousTimeframe: previousTimeframe,
            relatedQueries: relatedQueries.isEmpty ? nil : relatedQueries
        )
    }

    /// Identify relative period (e.g., "thisMonth", "lastWeek")
    private func identifyRelativePeriod(_ dateRange: String) -> String {
        let lower = dateRange.lowercased()

        if lower.contains("this month") { return "thisMonth" }
        if lower.contains("last month") { return "lastMonth" }
        if lower.contains("next month") { return "nextMonth" }
        if lower.contains("this week") { return "thisWeek" }
        if lower.contains("last week") { return "lastWeek" }
        if lower.contains("next week") { return "nextWeek" }
        if lower.contains("today") { return "today" }
        if lower.contains("yesterday") { return "yesterday" }
        if lower.contains("tomorrow") { return "tomorrow" }
        if lower.contains("this year") { return "thisYear" }
        if lower.contains("last year") { return "lastYear" }
        if lower.contains("past 30 days") { return "past30Days" }

        return "custom"
    }

    /// Extract the main topic from a user query
    private func extractTopic(from query: String) -> String? {
        let lower = query.lowercased()

        // Common topic keywords
        let topicPatterns = [
            ("gym", "fitness"),
            ("coffee", "coffee"),
            ("spend", "spending"),
            ("expense", "expenses"),
            ("email", "emails"),
            ("event", "events"),
            ("meeting", "meetings"),
            ("location", "locations"),
            ("restaurant", "dining"),
            ("travel", "travel")
        ]

        for (pattern, topic) in topicPatterns {
            if lower.contains(pattern) {
                return topic
            }
        }

        // Return first meaningful word
        let words = query.split(separator: " ")
        if words.count > 2 {
            return String(words[2])
        }

        return nil
    }

    /// Extract related queries from previous messages
    private func extractRelatedQueries(from messages: [String]) -> [String] {
        return messages.filter { msg in
            msg.contains("?") || msg.lowercased().contains("how") || msg.lowercased().contains("what")
        }.suffix(3).map { $0 } // Get last 3 queries
    }

    /// Detect timeframes mentioned in previous queries
    private func detectPreviousTimeframe(from messages: [String]) -> String? {
        let timeframePatterns = ["this month", "last month", "this week", "last week", "today", "yesterday", "this year", "last year"]

        for message in messages {
            let lower = message.lowercased()
            for timeframe in timeframePatterns {
                if lower.contains(timeframe) {
                    return timeframe
                }
            }
        }

        return nil
    }
}

// MARK: - Extension for Token Counting

extension StructuredLLMContext {
    /// Estimate token count (rough approximation: 1 token ≈ 4 characters)
    var estimatedTokenCount: Int {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            return max(1, jsonString.count / 4)  // Rough estimate
        } catch {
            return 0
        }
    }
}
