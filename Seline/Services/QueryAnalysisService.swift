import Foundation

/// Analyzes user queries to determine complexity and required data preprocessing
/// Handles complex aggregations, comparisons, and pattern analysis BEFORE sending to LLM
class QueryAnalysisService {

    /// Analyze user's question to determine if it needs special preprocessing
    static func analyzeQuery(_ query: String) -> QueryAnalysis {
        let lowerQuery = query.lowercased()

        // Detect query complexity and type
        let isAggregation = detectAggregation(lowerQuery)
        let isComparison = detectComparison(lowerQuery)
        let isRanking = detectRanking(lowerQuery)
        let isFrequency = detectFrequency(lowerQuery)
        let timeframes = extractTimeframes(lowerQuery)
        let categories = extractCategories(lowerQuery)
        let keywords = extractKeywords(lowerQuery)

        let complexity: QueryComplexity = {
            if isAggregation || isComparison { return .high }
            if isRanking || isFrequency { return .medium }
            return .low
        }()

        return QueryAnalysis(
            originalQuery: query,
            complexity: complexity,
            isAggregation: isAggregation,
            isComparison: isComparison,
            isRanking: isRanking,
            isFrequency: isFrequency,
            timeframes: timeframes,
            categories: categories,
            keywords: keywords,
            suggestedPreprocessing: suggestPreprocessing(isAggregation, isComparison, isRanking, isFrequency)
        )
    }

    // MARK: - Detection Methods

    private static func detectAggregation(_ query: String) -> Bool {
        let patterns = [
            "total", "sum", "count", "how many",
            "by category", "by type", "breakdown",
            "all expenses", "all spending", "all visits",
            "average", "overall", "in total"
        ]
        return patterns.contains { query.contains($0) }
    }

    private static func detectComparison(_ query: String) -> Bool {
        let patterns = [
            "vs", "versus", "compared to", "compared with",
            "this month", "last month", "this week", "last week",
            "more than", "less than", "increase", "decrease",
            "higher", "lower", "more", "fewer"
        ]
        return patterns.contains { query.contains($0) }
    }

    private static func detectRanking(_ query: String) -> Bool {
        let patterns = [
            "most", "least", "top", "highest", "lowest",
            "favorite", "best", "worst", "frequent",
            "rank", "order by", "sorted by"
        ]
        return patterns.contains { query.contains($0) }
    }

    private static func detectFrequency(_ query: String) -> Bool {
        let patterns = [
            "how often", "frequency", "times", "instances",
            "occurence", "occurrences", "repeating",
            "every day", "each week", "per month"
        ]
        return patterns.contains { query.contains($0) }
    }

    private static func extractTimeframes(_ query: String) -> [String] {
        let patterns = [
            "this week", "last week", "next week",
            "this month", "last month", "next month",
            "this year", "last year",
            "today", "yesterday", "tomorrow",
            "past 7 days", "past 30 days", "past month"
        ]
        return patterns.filter { query.contains($0) }
    }

    private static func extractCategories(_ query: String) -> [String] {
        var categories: [String] = []

        // Expense categories
        if query.contains("food") { categories.append("food") }
        if query.contains("gas") || query.contains("fuel") { categories.append("gas") }
        if query.contains("grocery") { categories.append("groceries") }
        if query.contains("restaurant") { categories.append("restaurant") }
        if query.contains("shopping") { categories.append("shopping") }

        // Event types
        if query.contains("work") || query.contains("meeting") { categories.append("work") }
        if query.contains("personal") { categories.append("personal") }
        if query.contains("gym") || query.contains("exercise") { categories.append("fitness") }

        return categories
    }

    private static func extractKeywords(_ query: String) -> [String] {
        let stopwords = Set(["how", "many", "times", "did", "i", "the", "a", "is", "are", "was", "were", "my", "your", "to", "in", "on", "at"])

        // Split and filter
        return query
            .split(separator: " ")
            .map { String($0).lowercased() }
            .filter { !stopwords.contains($0) && $0.count > 2 }
    }

    private static func suggestPreprocessing(_ isAgg: Bool, _ isComp: Bool, _ isRank: Bool, _ isFreq: Bool) -> [PreprocessingStep] {
        var steps: [PreprocessingStep] = []

        if isAgg {
            steps.append(.aggregateByCategory)
            steps.append(.calculateTotals)
        }

        if isComp {
            steps.append(.calculateComparisonMetrics)
            steps.append(.filterByTimeframe)
        }

        if isRank {
            steps.append(.sortByFrequency)
            steps.append(.rankItems)
        }

        if isFreq {
            steps.append(.countOccurrences)
            steps.append(.calculateFrequency)
        }

        return steps
    }
}

// MARK: - Models

enum QueryComplexity {
    case low      // Simple queries (single item retrieval)
    case medium   // Medium complexity (ranking, frequency)
    case high     // Complex (aggregations, comparisons)
}

enum PreprocessingStep {
    case filterByCategory
    case filterByTimeframe
    case aggregateByCategory
    case calculateTotals
    case countOccurrences
    case calculateFrequency
    case sortByFrequency
    case rankItems
    case calculateComparisonMetrics
    case normalizeAmounts
    case groupByMonth
    case groupByWeek
}

struct QueryAnalysis {
    let originalQuery: String
    let complexity: QueryComplexity
    let isAggregation: Bool
    let isComparison: Bool
    let isRanking: Bool
    let isFrequency: Bool
    let timeframes: [String]
    let categories: [String]
    let keywords: [String]
    let suggestedPreprocessing: [PreprocessingStep]
}

// MARK: - Enriched Metadata with Aggregations

/// Summary metadata for complex queries - includes aggregated data
struct EnrichedMetadata: Codable {
    let baseMetadata: AppDataMetadata

    // Expense aggregations
    let expenseByCategory: [String: (count: Int, total: Double)]?
    let expenseByMonth: [String: (count: Int, total: Double)]?
    let topExpenseCategory: (name: String, total: Double)?

    // Event aggregations
    let eventsByType: [String: Int]?
    let recurringEventCounts: [String: (title: String, thisMonth: Int, lastMonth: Int)]?
    let completionRates: [String: Double]?

    // Location aggregations
    let locationVisitCounts: [String: Int]?
    let topLocations: [String]?
    let visitFrequency: [String: String]? // "restaurant name" → "visited 5 times"
}

// MARK: - Query-Specific Context Builders

extension QueryAnalysisService {

    /// Build specialized context for aggregation queries
    @MainActor
    static func buildAggregationContext(
        _ analysis: QueryAnalysis,
        receipts: [ReceiptMetadata]
    ) -> String {
        var context = ""

        // Group by category
        var byCategory: [String: (count: Int, total: Double)] = [:]
        for receipt in receipts {
            let cat = receipt.category ?? "uncategorized"
            if byCategory[cat] == nil {
                byCategory[cat] = (0, 0)
            }
            byCategory[cat]!.count += 1
            byCategory[cat]!.total += receipt.amount
        }

        // Sort by total
        let sorted = byCategory.sorted { $0.value.total > $1.value.total }

        context += "EXPENSE BREAKDOWN:\n"
        for (category, data) in sorted {
            let pct = receipts.isEmpty ? 0 : (data.total / receipts.reduce(0) { $0 + $1.amount }) * 100
            context += "• \(category.uppercased()): $\(String(format: "%.2f", data.total)) (\(data.count) transactions, \(String(format: "%.0f", pct))%)\n"
        }

        return context
    }

    /// Build specialized context for frequency/comparison queries
    @MainActor
    static func buildFrequencyContext(
        _ analysis: QueryAnalysis,
        events: [EventMetadata]
    ) -> String {
        var context = ""

        // Group recurring events by title
        let recurringEvents = events.filter { $0.isRecurring }

        // Get this month and last month dates
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let lastMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let lastYear = currentMonth == 1 ? currentYear - 1 : currentYear

        for event in recurringEvents {
            guard let completedDates = event.completedDates else { continue }

            let thisMonthCount = completedDates.filter { date in
                let month = calendar.component(.month, from: date)
                let year = calendar.component(.year, from: date)
                return month == currentMonth && year == currentYear
            }.count

            let lastMonthCount = completedDates.filter { date in
                let month = calendar.component(.month, from: date)
                let year = calendar.component(.year, from: date)
                return month == lastMonth && year == lastYear
            }.count

            if thisMonthCount > 0 || lastMonthCount > 0 {
                context += "• \(event.title):\n"
                context += "  This month: \(thisMonthCount) times\n"
                context += "  Last month: \(lastMonthCount) times\n"
            }
        }

        return context
    }
}
