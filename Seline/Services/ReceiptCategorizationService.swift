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
        // Initialize all categories
        var categoryMap: [String: (total: Double, count: Int)] = [:]
        for category in validCategories {
            categoryMap[category] = (0, 0)
        }

        var totalAmount: Double = 0

        for receipt in receipts {
            let category = await categorizeReceipt(receipt.title)
            let current = categoryMap[category] ?? (0, 0)
            categoryMap[category] = (current.total + receipt.amount, current.count + 1)
            totalAmount += receipt.amount
        }

        // Convert to CategoryStat array
        let categoryStats = validCategories
            .compactMap { category -> CategoryStat? in
                guard let (total, count) = categoryMap[category], total > 0 else {
                    return nil
                }
                return CategoryStat(category: category, total: total, count: count)
            }

        return YearlyCategoryBreakdown(
            year: Calendar.current.component(.year, from: Date()),
            categories: categoryStats,
            yearlyTotal: totalAmount
        )
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
