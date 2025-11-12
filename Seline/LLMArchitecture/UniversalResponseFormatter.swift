import Foundation

/// Intelligently formats query results for display, deciding what to show and how
class UniversalResponseFormatter {
    static let shared = UniversalResponseFormatter()

    private init() {}

    // MARK: - Main Formatting

    /// Format a query result into displayable response and items
    @MainActor
    func format(
        _ result: QueryResult,
        rules: PresentationRules
    ) -> FormattedResponse {
        // Generate response text based on format
        let responseText = generateResponseText(result, rules: rules)

        // Intelligently decide which items to show
        let itemsToDisplay = selectItemsToDisplay(result, rules: rules)

        // Generate follow-up suggestions based on intent and data
        let suggestions = generateSuggestions(result, availableItems: itemsToDisplay)

        print("📝 Response Formatted:")
        print("   Format: \(rules.format)")
        print("   Items to show: \(itemsToDisplay.count)")
        print("   Suggestions: \(suggestions.count)")

        return FormattedResponse(
            text: responseText,
            items: itemsToDisplay,
            visualization: nil,
            suggestions: suggestions
        )
    }

    // MARK: - Response Text Generation

    /// Generate natural language response based on intent and data
    private func generateResponseText(_ result: QueryResult, rules: PresentationRules) -> String {
        switch rules.format {
        case .summary:
            return formatSummary(result)
        case .table:
            return formatComparison(result)
        case .list:
            return formatList(result)
        case .timeline:
            return formatTimeline(result)
        case .trend:
            return formatTrend(result)
        case .cards:
            return formatCardPreview(result)
        case .mixed:
            return formatMixed(result, rules)
        }
    }

    private func formatSummary(_ result: QueryResult) -> String {
        var summary = "**Summary**\n\n"

        // Add aggregations
        if !result.data.aggregations.isEmpty {
            summary += "📊 Key Metrics:\n"
            for agg in result.data.aggregations.prefix(5) {
                summary += "• \(agg.label): \(agg.value)\n"
            }
            summary += "\n"
        }

        // Add comparisons
        if !result.data.comparisons.isEmpty {
            summary += "🔄 Comparisons:\n"
            for comparison in result.data.comparisons {
                summary += "**\(comparison.dimension.capitalized)**\n"
                for (slice, value) in comparison.slices.sorted(by: { $0.key < $1.key }) {
                    summary += "• \(slice): \(value)\n"
                }
                summary += "\n"
            }
        }

        // Add trends
        if !result.data.trends.isEmpty {
            summary += "📈 Trends:\n"
            for trend in result.data.trends {
                summary += "**\(trend.metric.capitalized)** (\(trend.timeGranularity))\n"
                let entries = trend.data.sorted { a, b in a.key < b.key }
                for (time, value) in entries.prefix(5) {
                    summary += "• \(time): \(value)\n"
                }
                if trend.data.count > 5 {
                    summary += "• ...and \(trend.data.count - 5) more\n"
                }
                summary += "\n"
            }
        }

        if summary == "**Summary**\n\n" {
            summary = "Found \(result.data.items.count) items matching your query."
        }

        return summary
    }

    private func formatComparison(_ result: QueryResult) -> String {
        guard !result.data.comparisons.isEmpty else {
            return formatSummary(result)
        }

        var text = "**Comparison Results**\n\n"

        for comparison in result.data.comparisons {
            text += "📊 **\(comparison.dimension.capitalized) Comparison**\n\n"
            text += "| \(comparison.dimension.capitalized) | Value |\n"
            text += "|---|---|\n"

            for (slice, value) in comparison.slices.sorted(by: { $0.key < $1.key }) {
                text += "| \(slice) | \(value) |\n"
            }

            text += "\n"

            // Add analysis
            if let analysis = analyzeComparison(comparison) {
                text += "💡 \(analysis)\n\n"
            }
        }

        return text
    }

    private func formatList(_ result: QueryResult) -> String {
        var text = "**Found \(result.data.items.count) items**\n\n"

        let grouped = Dictionary(grouping: result.data.items) { item in
            item.category
        }

        for (category, items) in grouped.sorted(by: { $0.key < $1.key }) {
            text += "**\(category)** (\(items.count))\n"
            for item in items.sorted(by: { $0.date > $1.date }).prefix(3) {
                text += "• \(formatItemBrief(item))\n"
            }
            if items.count > 3 {
                text += "• ...and \(items.count - 3) more\n"
            }
            text += "\n"
        }

        return text
    }

    private func formatTimeline(_ result: QueryResult) -> String {
        var text = "**Timeline**\n\n"

        let sortedItems = result.data.items.sorted { $0.date > $1.date }
        let grouped = Dictionary(grouping: sortedItems) { item in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: item.date)
        }

        for (period, items) in grouped.sorted(by: { $0.key > $1.key }) {
            text += "📅 **\(period)**\n"
            for item in items.prefix(5) {
                text += "• \(formatItemBrief(item))\n"
            }
            if items.count > 5 {
                text += "• ...and \(items.count - 5) more\n"
            }
            text += "\n"
        }

        return text
    }

    private func formatTrend(_ result: QueryResult) -> String {
        guard !result.data.trends.isEmpty else {
            return formatSummary(result)
        }

        var text = "**Trend Analysis**\n\n"

        for trend in result.data.trends {
            text += "📈 **\(trend.metric.capitalized)** (\(trend.timeGranularity))\n\n"

            let sortedData = trend.data.sorted { a, b in a.key < b.key }
            for (time, value) in sortedData {
                text += "• \(time): \(value)\n"
            }

            if let analysis = analyzeTrend(trend) {
                text += "\n💡 \(analysis)\n"
            }

            text += "\n"
        }

        return text
    }

    private func formatCardPreview(_ result: QueryResult) -> String {
        let count = result.data.items.count
        return "Found \(count) item\(count == 1 ? "" : "s"). Showing details below."
    }

    private func formatMixed(_ result: QueryResult, _ rules: PresentationRules) -> String {
        var text = ""

        // Start with summary/comparison
        if !result.data.comparisons.isEmpty {
            text += formatComparison(result)
        } else if !result.data.aggregations.isEmpty {
            text += formatSummary(result)
        } else if !result.data.trends.isEmpty {
            text += formatTrend(result)
        } else {
            text += formatList(result)
        }

        // Add item count note if showing cards
        if !result.data.items.isEmpty && rules.includeIndividualItems {
            text += "\n📌 Related items: \(result.data.items.count)\n"
        }

        return text
    }

    // MARK: - Item Selection (Smart Decision Logic)

    /// Intelligently decide which items to show based on intent and presentation rules
    private func selectItemsToDisplay(
        _ result: QueryResult,
        rules: PresentationRules
    ) -> [RelatedItem] {
        // Decide if we should show individual items at all
        let shouldShowItems = shouldIncludeItemCards(result, rules: rules)

        guard shouldShowItems else {
            return []
        }

        // Filter items based on presentation rules
        var items = Array(result.data.items.prefix(rules.maxItemsToShow))

        // Sort by relevance based on intent
        items = sortItemsByIntent(items, intent: result.intent)

        // Convert to RelatedItem for display
        return items.map { item in
            RelatedItem(
                id: itemID(item),
                type: itemType(item),
                merchant: item.merchant,
                amount: item.amount,
                date: item.date,
                category: item.category,
                content: item.searchableContent,
                status: item.status
            )
        }
    }

    /// Determine if individual items should be shown based on intent and data
    private func shouldIncludeItemCards(_ result: QueryResult, rules: PresentationRules) -> Bool {
        // User explicitly doesn't want item cards
        if !rules.includeIndividualItems {
            return false
        }

        // DON'T show cards for aggregate/analysis queries
        switch result.intent {
        case .compare, .analyze, .summarize:
            return false
        case .predict:
            return false
        case .search, .explore, .track:
            // Show cards if result set is reasonable (< 20 items)
            return result.data.items.count < 20
        }
    }

    /// Sort items based on the user's intent
    private func sortItemsByIntent(_ items: [UniversalItem], intent: SemanticQueryIntent) -> [UniversalItem] {
        switch intent {
        case .search:
            // For search, sort by date descending (most recent first)
            return items.sorted { $0.date > $1.date }

        case .explore:
            // For exploration, show variety (mix dates and categories)
            return items.sorted { a, b in
                if a.category != b.category {
                    return a.category < b.category
                }
                return a.date > b.date
            }

        case .track:
            // For tracking, show most recent
            return items.sorted { $0.date > $1.date }

        case .compare, .analyze, .summarize, .predict:
            // Shouldn't get here (shouldIncludeItemCards returns false)
            return items
        }
    }

    // MARK: - Helper Formatting Functions

    private func formatItemBrief(_ item: UniversalItem) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short

        switch item {
        case .receipt(let receipt):
            let amount = String(format: "$%.2f", receipt.amount)
            return "\(receipt.title) - \(amount) (\(formatter.string(from: receipt.date)))"

        case .email(let email):
            return "\(email.subject) from \(email.sender.email)"

        case .event(let event):
            let status = event.isCompleted ? "✓" : "→"
            let date = event.targetDate ?? event.scheduledTime ?? event.createdAt
            return "\(status) \(event.title) (\(formatter.string(from: date)))"

        case .note(let note):
            let preview = note.content.prefix(40)
            return "\(note.title) - \(preview)..."

        case .location(let location):
            return "\(location.name) (\(location.category ?? "Place"))"
        }
    }

    private func itemID(_ item: UniversalItem) -> String {
        switch item {
        case .receipt(let receipt):
            return receipt.id.uuidString
        case .email(let email):
            return email.id
        case .event(let event):
            return event.id
        case .note(let note):
            return note.id.uuidString
        case .location(let location):
            return location.id.uuidString
        }
    }

    private func itemType(_ item: UniversalItem) -> String {
        switch item {
        case .receipt:
            return "receipt"
        case .email:
            return "email"
        case .event:
            return "event"
        case .note:
            return "note"
        case .location:
            return "location"
        }
    }

    // MARK: - Analysis Helpers

    private func analyzeComparison(_ comparison: ComparisonResult) -> String? {
        guard comparison.slices.count > 1 else { return nil }

        var maxValue = ""
        var maxKey = ""
        var minValue = ""
        var minKey = ""

        for (key, value) in comparison.slices {
            if let num = Double(value.replacingOccurrences(of: "$", with: "")) {
                if maxValue.isEmpty || num > Double(maxValue.replacingOccurrences(of: "$", with: "")) ?? 0 {
                    maxValue = value
                    maxKey = key
                }
                if minValue.isEmpty || num < Double(minValue.replacingOccurrences(of: "$", with: "")) ?? 0 {
                    minValue = value
                    minKey = key
                }
            }
        }

        if !maxKey.isEmpty && !minKey.isEmpty && maxKey != minKey {
            return "\(maxKey) has the highest \(comparison.dimension) at \(maxValue), while \(minKey) has the lowest at \(minValue)."
        }

        return nil
    }

    private func analyzeTrend(_ trend: TrendResult) -> String? {
        let values = trend.data.values.compactMap { value in
            Double(value.replacingOccurrences(of: "$", with: ""))
        }.sorted()

        guard values.count >= 2 else { return nil }

        let first = values.first ?? 0
        let last = values.last ?? 0
        let difference = last - first
        let percentChange = first > 0 ? (difference / first) * 100 : 0

        if percentChange > 10 {
            return "Upward trend detected - \(String(format: "%.0f%%", percentChange)) increase."
        } else if percentChange < -10 {
            return "Downward trend detected - \(String(format: "%.0f%%", abs(percentChange))) decrease."
        } else {
            return "Relatively stable trend."
        }
    }

    // MARK: - Suggestion Generation

    /// Generate contextual follow-up suggestions
    private func generateSuggestions(_ result: QueryResult, availableItems: [RelatedItem]) -> [String] {
        var suggestions: [String] = []

        switch result.intent {
        case .search:
            suggestions.append("Would you like to filter these results further?")
            suggestions.append("Show me details about a specific item?")

        case .compare:
            suggestions.append("Compare a different time period?")
            suggestions.append("Drill down into a specific category?")

        case .analyze:
            suggestions.append("Show me trends over time?")
            suggestions.append("What changed since last month?")

        case .explore:
            suggestions.append("Explore a different category?")
            suggestions.append("Tell me about your top items?")

        case .track:
            if let events = availableItems.filter({ $0.type == "event" }) as? [RelatedItem] {
                let incomplete = events.filter { $0.status == "upcoming" }
                if !incomplete.isEmpty {
                    suggestions.append("You have \(incomplete.count) pending items. Want to see them?")
                }
            }
            suggestions.append("What's next on your list?")

        case .summarize:
            suggestions.append("Want to dive deeper into any category?")
            suggestions.append("Compare this to a previous period?")

        case .predict:
            suggestions.append("What patterns do you want to understand better?")
            suggestions.append("Show me next month's forecast?")
        }

        return suggestions.prefix(2).map { $0 }
    }
}

// MARK: - Result Structures for Display

struct FormattedResponse {
    let text: String
    let items: [RelatedItem]
    let visualization: String?
    let suggestions: [String]
}

struct RelatedItem: Identifiable {
    let id: String
    let type: String  // "receipt", "email", "event", "note", "location"
    let merchant: String
    let amount: Double
    let date: Date
    let category: String
    let content: String
    let status: String

    var displayTitle: String {
        merchant
    }

    var displayAmount: String {
        if amount > 0 {
            return String(format: "$%.2f", amount)
        }
        return ""
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
