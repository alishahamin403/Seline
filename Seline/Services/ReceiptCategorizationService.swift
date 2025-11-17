import Foundation

@MainActor
class ReceiptCategorizationService: ObservableObject {
    static let shared = ReceiptCategorizationService()

    private let openAIService = OpenAIService.shared
    private let userDefaults = UserDefaults.standard
    private let supabaseManager = SupabaseManager.shared
    private let categoryCache = NSMutableDictionary()
    private var currentUserId: String = ""

    private let validCategories = [
        "Food & Dining",
        "Transportation",
        "Healthcare",
        "Entertainment",
        "Shopping",
        "Software & Subscriptions",
        "Accommodation & Travel",
        "Utilities & Internet",
        "Professional Services",
        "Auto & Vehicle",
        "Home & Maintenance",
        "Memberships",
        "Other"
    ]

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

            // Save to Supabase for persistence (background task, don't block)
            Task {
                await self.saveCategoryToSupabase(title, category: validCategory)
            }

            return validCategory
        } catch {
            print("❌ Error categorizing receipt '\(title)': \(error)")
            return "Other"
        }
    }

    /// Get category breakdown for a list of receipts
    func getCategoryBreakdown(for receipts: [ReceiptStat]) async -> YearlyCategoryBreakdown {
        // Initialize all categories with both totals and receipts
        var categoryMap: [String: (total: Double, count: Int)] = [:]
        var categoryReceipts: [String: [ReceiptStat]] = [:]
        var categorizedReceipts: [ReceiptStat] = []

        for category in validCategories {
            categoryMap[category] = (0, 0)
            categoryReceipts[category] = []
        }

        var totalAmount: Double = 0

        for receipt in receipts {
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
        guard !currentUserId.isEmpty, let userUUID = UUID(uuidString: currentUserId) else { return }

        do {
            // Query receipt_categories table for current user
            let client = await supabaseManager.getPostgrestClient()
            let response = try await client
                .from("receipt_categories")
                .select()
                .eq("user_id", value: userUUID.uuidString)
                .execute()

            let data = response.data
            let decoder = JSONDecoder()
            let categories = try decoder.decode([ReceiptCategoryRecord].self, from: data)

            // Load into memory cache
            for category in categories {
                categoryCache[category.receipt_title] = category.category
            }
        } catch {
            print("⚠️ Failed to load categories from Supabase: \(error)")
            // Silently fail - use local cache if available
        }
    }

    /// Save a categorization to both local cache and Supabase
    private func saveCategoryToSupabase(_ title: String, category: String) async {
        guard !currentUserId.isEmpty, let userUUID = UUID(uuidString: currentUserId) else { return }

        do {
            let client = await supabaseManager.getPostgrestClient()

            // Create record with proper UUID types
            let record = ReceiptCategoryRecord(
                id: UUID(),
                user_id: userUUID,
                receipt_title: title,
                category: category,
                created_at: ISO8601DateFormatter().string(from: Date())
            )

            // Pass the Codable object directly to upsert (PostgrestClient handles encoding)
            try await client
                .from("receipt_categories")
                .upsert([record])
                .execute()
        } catch {
            print("❌ Failed to save category to Supabase: \(error)")
            // Local cache is the source of truth; Supabase sync is an optimization
        }
    }

    // MARK: - Migration: Recategorize Old "Services" to New Categories

    /// Check if migration has already been completed
    func hasCompletedMigration() -> Bool {
        return userDefaults.bool(forKey: "receipt_categories_migration_completed")
    }

    /// Migrate all receipts from old "Services" category to new 13-category system
    /// This is a one-time operation that re-categorizes existing receipts
    func migrateOldServices() async {
        // Check if already migrated
        if hasCompletedMigration() {
            print("✅ Migration already completed")
            return
        }

        print("🔄 Starting category migration for old 'Services' receipts...")

        do {
            let client = await supabaseManager.getPostgrestClient()

            // Fetch all receipts with "Services" category from Supabase
            let response = try await client
                .from("receipt_categories")
                .select()
                .eq("category", value: "Services")
                .execute()

            let decoder = JSONDecoder()
            let records = try decoder.decode([ReceiptCategoryRecord].self, from: response.data)

            guard !records.isEmpty else {
                print("✅ No 'Services' category receipts found to migrate")
                markMigrationComplete()
                return
            }

            print("📋 Found \(records.count) receipts to migrate...")

            var migratedCount = 0
            var failedCount = 0

            // Re-categorize each receipt
            for (index, record) in records.enumerated() {
                do {
                    // Re-categorize using the updated system
                    let newCategory = try await openAIService.categorizeReceipt(title: record.receipt_title)
                    let validCategory = validCategories.contains(newCategory) ? newCategory : "Other"

                    // Update in Supabase using upsert
                    let updatedRecord = ReceiptCategoryRecord(
                        id: record.id,
                        user_id: record.user_id,
                        receipt_title: record.receipt_title,
                        category: validCategory,
                        created_at: record.created_at
                    )

                    try await client
                        .from("receipt_categories")
                        .upsert([updatedRecord])
                        .execute()

                    migratedCount += 1
                    let progress = ((index + 1) * 100) / records.count
                    print("  [\(progress)%] Migrated: \(record.receipt_title) → \(validCategory)")

                    // Small delay to avoid rate limiting
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                } catch {
                    failedCount += 1
                    print("  ❌ Failed to migrate '\(record.receipt_title)': \(error)")
                }
            }

            print("✅ Migration complete: \(migratedCount) migrated, \(failedCount) failed")
            markMigrationComplete()

        } catch {
            print("❌ Migration failed: \(error)")
        }
    }

    /// Mark migration as complete
    private func markMigrationComplete() {
        userDefaults.set(true, forKey: "receipt_categories_migration_completed")
        print("✅ Migration status saved")
    }

    /// Reset migration flag (for testing only)
    func resetMigrationFlag() {
        userDefaults.set(false, forKey: "receipt_categories_migration_completed")
        print("🔄 Migration flag reset")
    }
}

// MARK: - Data Models for Supabase

struct ReceiptCategoryRecord: Codable {
    let id: UUID
    let user_id: UUID
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
