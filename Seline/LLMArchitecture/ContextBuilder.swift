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
        // Build metadata
        let metadata = StructuredLLMContext.ContextMetadata(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            currentWeather: filteredContext.metadata.currentWeather,
            userTimezone: filteredContext.metadata.userTimezone,
            intent: filteredContext.metadata.queryIntent,
            dateRangeQueried: filteredContext.metadata.dateRangeQueried
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

        return tasks.map { taskWithRelevance in
            let duration: Int? = {
                if let scheduled = taskWithRelevance.task.scheduledTime,
                   let end = taskWithRelevance.task.endTime {
                    return Int(end.timeIntervalSince(scheduled) / 60)
                }
                return nil
            }()

            return StructuredLLMContext.ContextData.TaskJSON(
                id: taskWithRelevance.task.id,
                title: taskWithRelevance.task.title,
                scheduledTime: taskWithRelevance.task.scheduledTime.map { ISO8601DateFormatter().string(from: $0) },
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
                timestamp: ISO8601DateFormatter().string(from: emailWithRelevance.email.timestamp),
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
                date: ISO8601DateFormatter().string(from: receiptWithRelevance.receipt.date),
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
