import Foundation

/// Advanced parser for extracting structured parameters from user queries
/// Handles specialized query types: counting, comparison, temporal, aggregation
class AdvancedQueryParser {
    static let shared = AdvancedQueryParser()

    // MARK: - Counting Query Detection

    /// Detects and extracts parameters from counting queries
    /// Examples: "How many times did I go gym?", "How often did I spend on coffee?"
    func parseCountingQuery(_ query: String) -> CountingQueryParameters? {
        let lowercased = query.lowercased()

        // Check for counting keywords
        let countingPatterns = [
            "how many times",
            "how many",
            "how often",
            "how much did i",
            "count.*",
            "total number of"
        ]

        var matchesCountPattern = false
        for pattern in countingPatterns {
            if lowercased.contains(pattern) || matches(lowercased, pattern: pattern) {
                matchesCountPattern = true
                break
            }
        }

        guard matchesCountPattern else { return nil }

        // Extract the subject (what are we counting?)
        let subject = extractCountingSubject(query)

        // Extract time frame if present
        let timeFrame = extractTimeFrame(query)

        // Extract filter terms
        let filterTerms = extractFilterTerms(query)

        return CountingQueryParameters(
            subject: subject,
            timeFrame: timeFrame,
            filterTerms: filterTerms,
            query: query
        )
    }

    // MARK: - Comparison Query Detection

    /// Detects and extracts parameters from comparison queries
    /// Examples: "Which was more expensive?", "Compare my spending this month vs last month"
    func parseComparisonQuery(_ query: String) -> ComparisonQueryParameters? {
        let lowercased = query.lowercased()

        // Check for comparison keywords
        let comparisonPatterns = [
            "which.*more",
            "which.*less",
            "compare",
            "vs",
            "versus",
            "more than",
            "less than",
            "better.*than",
            "worse.*than",
            "difference.*between"
        ]

        var matchesComparisonPattern = false
        for pattern in comparisonPatterns {
            if lowercased.contains(pattern) || matches(lowercased, pattern: pattern) {
                matchesComparisonPattern = true
                break
            }
        }

        guard matchesComparisonPattern else { return nil }

        // Extract comparison metric
        let metric = extractComparisonMetric(query)

        // Extract comparison dimensions (e.g., time periods, categories)
        let dimensions = extractComparisonDimensions(query)

        // Extract filter terms
        let filterTerms = extractFilterTerms(query)

        return ComparisonQueryParameters(
            metric: metric,
            dimensions: dimensions,
            filterTerms: filterTerms,
            query: query
        )
    }

    // MARK: - Temporal Query Detection

    /// Detects and extracts temporal parameters from queries
    /// Handles relative dates: "this month", "last week", "between X and Y"
    func parseTemporalQuery(_ query: String) -> TemporalQueryParameters? {
        let dateRange = extractDateRange(query)
        guard dateRange != nil else { return nil }

        return TemporalQueryParameters(
            dateRange: dateRange,
            query: query
        )
    }

    // MARK: - Helper Methods for Extraction

    private func extractCountingSubject(_ query: String) -> String {
        let lowercased = query.lowercased()

        // Remove common counting phrases
        var cleaned = lowercased
        let countingPhrases = ["how many times did i", "how many times", "how often did i", "how often", "how much did i spend on"]
        for phrase in countingPhrases {
            if cleaned.hasPrefix(phrase) {
                cleaned = String(cleaned.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Extract the main subject (first few words before "on", "this", "last", etc)
        let stopWords = ["on", "this", "last", "in", "at", "during"]
        for stopWord in stopWords {
            if let range = cleaned.range(of: " \(stopWord) ") {
                cleaned = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "?")).trimmingCharacters(in: .whitespaces)
    }

    private func extractComparisonMetric(_ query: String) -> String {
        let lowercased = query.lowercased()

        // Common metrics
        let metricPatterns = [
            ("expensive", "amount"),
            ("spending", "amount"),
            ("cost", "amount"),
            ("price", "amount"),
            ("frequent", "count"),
            ("often", "count"),
            ("times", "count"),
            ("healthy", "frequency"),
            ("active", "frequency"),
            ("productive", "frequency")
        ]

        for (pattern, metric) in metricPatterns {
            if lowercased.contains(pattern) {
                return metric
            }
        }

        return "amount" // default to amount for comparisons
    }

    private func extractComparisonDimensions(_ query: String) -> [String] {
        var dimensions: [String] = []

        // Check for time-based comparisons
        let timePatterns = ["this month", "last month", "this week", "last week", "today", "yesterday", "this year", "last year"]
        for pattern in timePatterns {
            if query.lowercased().contains(pattern) {
                dimensions.append(pattern)
            }
        }

        // If no time dimensions, might be comparing categories or merchants
        if dimensions.isEmpty {
            // Extract words after "vs" or "versus"
            let vsPatterns = ["vs", "versus"]
            for pattern in vsPatterns {
                if let range = query.lowercased().range(of: pattern) {
                    let afterVs = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    dimensions.append(contentsOf: afterVs.components(separatedBy: " and "))
                    break
                }
            }
        }

        return dimensions.filter { !$0.isEmpty }
    }

    private func extractFilterTerms(_ query: String) -> [String] {
        let lowercased = query.lowercased()
        var filters: [String] = []

        // Extract categories (words after "on", "for", "with")
        let filterPhrases = ["on", "for", "with", "at"]
        for phrase in filterPhrases {
            if let range = lowercased.range(of: " \(phrase) ") {
                let afterPhrase = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let words = afterPhrase.components(separatedBy: " ")
                if !words.isEmpty {
                    filters.append(words[0].trimmingCharacters(in: CharacterSet(charactersIn: "?,.!;:")))
                }
            }
        }

        return filters
    }

    private func extractTimeFrame(_ query: String) -> String? {
        let lowercased = query.lowercased()

        let timeFrames = [
            "this month", "last month", "next month",
            "this week", "last week", "next week",
            "today", "yesterday", "tomorrow",
            "this year", "last year", "next year",
            "past 30 days", "past week", "past month"
        ]

        for timeFrame in timeFrames {
            if lowercased.contains(timeFrame) {
                return timeFrame
            }
        }

        return nil
    }

    private func extractDateRange(_ query: String) -> DateRange? {
        let lowercased = query.lowercased()
        let now = Date()
        let calendar = Calendar.current

        // Check for relative date patterns
        let patterns = [
            ("this month", { (now: Date) -> DateRange in
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
                return DateRange(start: start, end: end, label: "this month")
            }),
            ("last month", { (now: Date) -> DateRange in
                let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let lastMonthEnd = calendar.date(byAdding: DateComponents(day: -1), to: currentMonthStart)!
                let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthEnd))!
                return DateRange(start: lastMonthStart, end: lastMonthEnd, label: "last month")
            }),
            ("this week", { (now: Date) -> DateRange in
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let weekEnd = calendar.date(byAdding: DateComponents(day: 6), to: weekStart)!
                return DateRange(start: weekStart, end: weekEnd, label: "this week")
            }),
            ("last week", { (now: Date) -> DateRange in
                let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let lastWeekEnd = calendar.date(byAdding: DateComponents(day: -1), to: thisWeekStart)!
                let lastWeekStart = calendar.date(byAdding: DateComponents(day: -6), to: lastWeekEnd)!
                return DateRange(start: lastWeekStart, end: lastWeekEnd, label: "last week")
            })
        ]

        for (pattern, calculator) in patterns {
            if lowercased.contains(pattern) {
                return calculator(now)
            }
        }

        return nil
    }

    // Simple regex matching for patterns
    private func matches(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            return false
        }
    }
}

// MARK: - Query Parameter Structures

struct CountingQueryParameters {
    let subject: String
    let timeFrame: String?
    let filterTerms: [String]
    let query: String
}

struct ComparisonQueryParameters {
    let metric: String
    let dimensions: [String]
    let filterTerms: [String]
    let query: String
}

struct TemporalQueryParameters {
    let dateRange: DateRange?
    let query: String
}

struct DateRange {
    let start: Date
    let end: Date
    let label: String
}
