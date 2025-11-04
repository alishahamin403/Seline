import Foundation

@MainActor
class ReceiptCategorizationService: ObservableObject {
    static let shared = ReceiptCategorizationService()

    private let openAIService = OpenAIService.shared
    private let userDefaults = UserDefaults.standard
    private let categoryCache = NSMutableDictionary()
    private let categoryKey = "receiptCategories"

    private let validCategories = ["Food", "Services", "Transportation", "Healthcare", "Entertainment", "Shopping", "Other"]

    private init() {
        loadCategoryCache()
    }

    // MARK: - Categorization

    /// Categorize a receipt and cache the result
    func categorizeReceipt(_ title: String) async -> String {
        // Check cache first
        if let cached = categoryCache[title] as? String {
            return cached
        }

        do {
            let category = try await openAIService.categorizeReceipt(title: title)
            let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

            // Ensure the category is valid
            let validCategory = validCategories.contains(cleanCategory) ? cleanCategory : "Other"

            // Cache it
            categoryCache[title] = validCategory
            saveCategoryCache()

            return validCategory
        } catch {
            print("❌ Error categorizing receipt '\(title)': \(error)")
            return "Other"
        }
    }

    /// Get category breakdown for a list of receipts
    func getCategoryBreakdown(for receipts: [ReceiptStat]) async -> YearlyCategoryBreakdown {
        print("📊 Starting category breakdown for \(receipts.count) receipts")

        // Initialize all categories with both totals and receipts
        var categoryMap: [String: (total: Double, count: Int)] = [:]
        var categoryReceipts: [String: [ReceiptStat]] = [:]
        var categorizedReceipts: [ReceiptStat] = []

        for category in validCategories {
            categoryMap[category] = (0, 0)
            categoryReceipts[category] = []
        }

        var totalAmount: Double = 0

        for (index, receipt) in receipts.enumerated() {
            let category = await categorizeReceipt(receipt.title)
            let current = categoryMap[category] ?? (0, 0)
            categoryMap[category] = (current.total + receipt.amount, current.count + 1)

            // Create a new receipt with category set
            var updatedReceipt = receipt
            updatedReceipt.category = category

            // Track which receipts belong to this category
            if categoryReceipts[category] != nil {
                categoryReceipts[category]?.append(updatedReceipt)
            } else {
                categoryReceipts[category] = [updatedReceipt]
            }

            categorizedReceipts.append(updatedReceipt)
            totalAmount += receipt.amount
            print("✓ [\(index + 1)/\(receipts.count)] '\(receipt.title)' → \(category)")
        }

        // Convert to CategoryStat array
        let categoryStats = validCategories
            .compactMap { category -> CategoryStat? in
                guard let (total, count) = categoryMap[category], total > 0 else {
                    return nil
                }
                return CategoryStat(category: category, total: total, count: count)
            }

        let breakdown = YearlyCategoryBreakdown(
            year: Calendar.current.component(.year, from: Date()),
            categories: categoryStats,
            yearlyTotal: totalAmount,
            categoryReceipts: categoryReceipts,
            allReceipts: categorizedReceipts
        )

        // Log summary
        print("✅ Category breakdown complete!")
        for stat in breakdown.sortedCategories {
            print("   \(stat.category): \(stat.count) receipts = \(CurrencyParser.formatAmount(stat.total))")
        }

        return breakdown
    }

    // MARK: - Caching

    private func saveCategoryCache() {
        let dictionary = categoryCache.copy() as! [String: String]
        userDefaults.set(dictionary, forKey: categoryKey)
    }

    private func loadCategoryCache() {
        if let cached = userDefaults.dictionary(forKey: categoryKey) as? [String: String] {
            for (key, value) in cached {
                categoryCache[key] = value
            }
        }
    }

    func clearCache() {
        categoryCache.removeAllObjects()
        userDefaults.removeObject(forKey: categoryKey)
    }
}
