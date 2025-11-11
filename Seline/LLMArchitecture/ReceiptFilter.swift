import Foundation

/// Receipt with relevance score for expense queries
struct ReceiptWithRelevance: Codable {
    let receipt: ReceiptStat
    let relevanceScore: Double  // 0.0 - 1.0
    let matchType: MatchType
    let categoryMatch: Bool
    let merchantType: String?  // NEW: What kind of merchant (Pizzeria, Coffee Shop, etc)
    let merchantProducts: [String]?  // NEW: What products they sell

    enum MatchType: String, Codable {
        case date_range_match
        case category_match
        case amount_range_match
        case merchant_match
    }
}

/// Filters and ranks receipts based on relevance to user query
@MainActor
class ReceiptFilter {
    static let shared = ReceiptFilter()

    private init() {}

    // MARK: - Main Filtering

    /// Filter receipts based on intent and date range
    /// Now includes merchant intelligence for better product identification
    func filterReceiptsForQuery(
        intent: IntentContext,
        receipts: [ReceiptStat]
    ) async -> [ReceiptWithRelevance] {
        var scored: [ReceiptWithRelevance] = []

        // Only process if expense intent detected
        guard intent.intent == .expenses || intent.subIntents.contains(.expenses) else {
            return []
        }

        // Get merchant intelligence for all unique merchants
        let uniqueMerchants = Array(Set(receipts.map { $0.title }))
        let merchantInfo = await MerchantIntelligenceLayer.shared.getMerchantTypes(uniqueMerchants)

        for receipt in receipts {
            var score: Double = 0
            var matchType: ReceiptWithRelevance.MatchType = .date_range_match
            var categoryMatch = false
            var merchantType: String? = nil
            var merchantProducts: [String]? = nil

            // Get merchant intelligence
            if let info = merchantInfo[receipt.title] {
                merchantType = info.type
                merchantProducts = info.products
            }

            // Date range filtering
            if let dateRange = intent.dateRange {
                if receipt.date >= dateRange.start && receipt.date <= dateRange.end {
                    score += 5.0
                    matchType = .date_range_match
                } else {
                    // Receipt is outside the requested date range, skip it
                    continue
                }
            }

            // Category filtering
            if let locationFilter = intent.locationFilter, let filterCategory = locationFilter.category {
                let receiptCategory = receipt.category.lowercased()
                if receiptCategory.contains(filterCategory.lowercased()) {
                    score += 3.0
                    matchType = .category_match
                    categoryMatch = true
                }
            }

            // Enhanced merchant matching: keyword + merchant intelligence
            let lowerMerchant = receipt.title.lowercased()

            for entity in intent.entities {
                let lowerEntity = entity.lowercased()

                // Keyword match in merchant name
                if lowerMerchant.contains(lowerEntity) {
                    score += 2.0
                    matchType = .merchant_match
                }

                // Semantic match via merchant intelligence
                // (e.g., user asked for "pizza" and merchant type is "Pizzeria")
                if let info = merchantInfo[receipt.title] {
                    if MerchantIntelligenceLayer.shared.likelyToSell(info, product: lowerEntity) {
                        score += 1.5  // Slightly lower confidence than explicit match
                        matchType = .merchant_match
                        merchantKeywordMatch = true
                    }
                }
            }

            // Amount range filtering (if user asks for receipts over/under certain amount)
            if let amountClue = detectAmountClue(from: intent.entities) {
                let (minAmount, maxAmount) = amountClue

                if receipt.amount >= minAmount && receipt.amount <= maxAmount {
                    score += 2.0
                    matchType = .amount_range_match
                } else {
                    // Amount outside requested range, skip
                    continue
                }
            }

            // Only include receipts with some relevance or within date range
            if score > 0 {
                scored.append(ReceiptWithRelevance(
                    receipt: receipt,
                    relevanceScore: min(score / 5.0, 1.0),
                    matchType: matchType,
                    categoryMatch: categoryMatch,
                    merchantType: merchantType,
                    merchantProducts: merchantProducts
                ))
            }
        }

        // Sort by date (most recent first)
        scored.sort { $0.receipt.date > $1.receipt.date }

        // Don't limit - return ALL receipts in the requested range
        return scored
    }

    // MARK: - Helper Methods

    /// Detect amount constraints from user query entities
    /// Examples: "over $50", "under $100", "$20-$50"
    private func detectAmountClue(from entities: [String]) -> (min: Double, max: Double)? {
        // Look for patterns like "over", "under", "more than", "less than"
        for entity in entities {
            let lower = entity.lowercased()

            // Check for "over X" or "above X"
            if lower.contains("over") || lower.contains("above") || lower.contains("more") {
                // Extract the number
                if let amount = extractAmount(from: entity) {
                    return (min: amount, max: 1_000_000)  // No upper limit
                }
            }

            // Check for "under X" or "below X"
            if lower.contains("under") || lower.contains("below") || lower.contains("less") {
                if let amount = extractAmount(from: entity) {
                    return (min: 0, max: amount)  // No lower limit
                }
            }

            // Check for "between X and Y"
            if lower.contains("between") {
                // This is more complex, skip for now
                continue
            }
        }

        return nil
    }

    /// Extract dollar amount from text
    private func extractAmount(from text: String) -> Double? {
        let pattern = "\\$(\\d+(?:\\.\\d{2})?)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)),
               let range = Range(match.range(at: 1), in: text) {
                let amountStr = String(text[range])
                return Double(amountStr)
            }
        }
        return nil
    }

    // MARK: - Receipt Statistics

    /// Calculate total, average, and breakdown by category
    func calculateReceiptStatistics(from receipts: [ReceiptWithRelevance]) -> ReceiptStatistics {
        let total = receipts.reduce(0.0) { $0 + $1.receipt.amount }
        let count = receipts.count
        let average = count > 0 ? total / Double(count) : 0

        // Group by category
        var byCategory: [String: (total: Double, count: Int)] = [:]
        for receipt in receipts {
            let category = receipt.receipt.category
            if byCategory[category] != nil {
                byCategory[category]!.total += receipt.receipt.amount
                byCategory[category]!.count += 1
            } else {
                byCategory[category] = (total: receipt.receipt.amount, count: 1)
            }
        }

        // Sort categories by total amount descending
        let sortedCategories = byCategory.sorted { $0.value.total > $1.value.total }

        return ReceiptStatistics(
            totalAmount: total,
            totalCount: count,
            averageAmount: average,
            highestAmount: receipts.map { $0.receipt.amount }.max() ?? 0,
            lowestAmount: receipts.map { $0.receipt.amount }.min() ?? 0,
            byCategory: sortedCategories.map { category, stats in
                CategoryBreakdown(
                    category: category,
                    total: stats.total,
                    count: stats.count,
                    percentage: count > 0 ? (Double(stats.count) / Double(count)) * 100 : 0
                )
            }
        )
    }

    /// Get top N receipts by amount
    func getTopReceiptsByAmount(_ receipts: [ReceiptWithRelevance], limit: Int = 10) -> [ReceiptWithRelevance] {
        return receipts
            .sorted { $0.receipt.amount > $1.receipt.amount }
            .prefix(limit)
            .map { $0 }
    }

    /// Get receipts for a specific month
    func filterByMonth(_ receipts: [ReceiptWithRelevance], month: Int, year: Int) -> [ReceiptWithRelevance] {
        return receipts.filter { receipt in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: receipt.receipt.date)
            return components.year == year && components.month == month
        }
    }
}

// MARK: - Statistics Models

struct ReceiptStatistics {
    let totalAmount: Double
    let totalCount: Int
    let averageAmount: Double
    let highestAmount: Double
    let lowestAmount: Double
    let byCategory: [CategoryBreakdown]

    func formatted() -> String {
        var result = "💰 Spending Summary\n"
        result += "━━━━━━━━━━━━━━━━━━━━━━━\n"
        result += "Total: **$\(String(format: "%.2f", totalAmount))**\n"
        result += "Transactions: \(totalCount)\n"
        result += "Average: **$\(String(format: "%.2f", averageAmount))**\n"
        result += "Range: $\(String(format: "%.2f", lowestAmount)) - $\(String(format: "%.2f", highestAmount))\n"
        result += "\n📊 By Category:\n"

        for category in byCategory {
            result += "• **\(category.category)**: $\(String(format: "%.2f", category.total)) (\(category.count) transactions, \(String(format: "%.0f", category.percentage))%)\n"
        }

        return result
    }
}

struct CategoryBreakdown {
    let category: String
    let total: Double
    let count: Int
    let percentage: Double
}
