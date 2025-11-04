import Foundation

@MainActor
class ReceiptCategorizationService: ObservableObject {
    static let shared = ReceiptCategorizationService()

    private let openAIService = OpenAIService.shared
    private let userDefaults = UserDefaults.standard
    private let supabaseManager = SupabaseManager.shared
    private let categoryCache = NSMutableDictionary()
    private var currentUserId: String = ""

    private let validCategories = ["Food", "Services", "Transportation", "Healthcare", "Entertainment", "Shopping", "Other"]

    private init() {
        loadCategoryCache()
    }

    // MARK: - User Management

    /// Set the current user ID for cache isolation and load from Supabase
    func setCurrentUser(_ userId: String) {
        currentUserId = userId
        // Load from local cache first, then sync with Supabase
        loadCategoryCache()
        Task {
            await loadCategoriesFromSupabase()
        }
    }

    /// Get the user-specific cache key
    private func getCacheKey() -> String {
        if currentUserId.isEmpty {
            return "receiptCategories"
        }
        return "receiptCategories_\(currentUserId)"
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

            // Cache it locally
            categoryCache[title] = validCategory
            saveCategoryCache()

            // Save to Supabase for persistence
            await saveCategoryToSupabase(title, category: validCategory)

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
        userDefaults.set(dictionary, forKey: getCacheKey())
    }

    private func loadCategoryCache() {
        categoryCache.removeAllObjects()
        let cacheKey = getCacheKey()
        if let cached = userDefaults.dictionary(forKey: cacheKey) as? [String: String] {
            for (key, value) in cached {
                categoryCache[key] = value
            }
        }
    }

    func clearCache() {
        categoryCache.removeAllObjects()
        userDefaults.removeObject(forKey: getCacheKey())
    }

    /// Clear cache for a specific user (used during logout)
    func clearCacheForUser(_ userId: String) {
        let userCacheKey = "receiptCategories_\(userId)"
        userDefaults.removeObject(forKey: userCacheKey)
    }

    // MARK: - Supabase Persistence

    /// Load categories from Supabase into memory cache
    private func loadCategoriesFromSupabase() async {
        guard !currentUserId.isEmpty else { return }

        do {
            // Query receipt_categories table for current user
            let client = await supabaseManager.getPostgrestClient()
            let response = try await client
                .from("receipt_categories")
                .select()
                .eq("user_id", value: currentUserId)
                .execute()

            let data = response.data
            let decoder = JSONDecoder()
            let categories = try decoder.decode([ReceiptCategoryRecord].self, from: data)

            // Load into memory cache
            for category in categories {
                categoryCache[category.receipt_title] = category.category
            }

            print("✅ Loaded \(categories.count) categories from Supabase")
        } catch {
            print("⚠️ Failed to load categories from Supabase: \(error)")
            // Silently fail - use local cache if available
        }
    }

    /// Save a categorization to both local cache and Supabase
    private func saveCategoryToSupabase(_ title: String, category: String) async {
        guard !currentUserId.isEmpty else { return }

        do {
            let client = await supabaseManager.getPostgrestClient()
            let record = ReceiptCategoryRecord(
                id: UUID().uuidString,
                user_id: currentUserId,
                receipt_title: title,
                category: category,
                created_at: ISO8601DateFormatter().string(from: Date())
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(record)

            try await client
                .from("receipt_categories")
                .upsert(data)
                .execute()

            print("✅ Saved category to Supabase: \(title) → \(category)")
        } catch {
            print("⚠️ Failed to save category to Supabase: \(error)")
            // Continue anyway - local cache still works
        }
    }
}

// MARK: - Data Models for Supabase

struct ReceiptCategoryRecord: Codable {
    let id: String
    let user_id: String
    let receipt_title: String
    let category: String
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case receipt_title
        case category
        case created_at
    }
}
