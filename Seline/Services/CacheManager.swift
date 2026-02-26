import Foundation

/// Generic cache manager with TTL (Time To Live) support
class CacheManager {
    static let shared = CacheManager()

    private init() {}

    // MARK: - Cache Entry

    private struct CacheEntry<T> {
        let value: T
        let expirationDate: Date

        var isExpired: Bool {
            Date() > expirationDate
        }
    }

    // MARK: - Storage

    private var cache: [String: Any] = [:]
    private let queue = DispatchQueue(label: "com.seline.cachemanager", attributes: .concurrent)

    // MARK: - Public Methods

    /// Store a value in cache with a TTL
    /// - Parameters:
    ///   - value: The value to cache
    ///   - key: Unique identifier for this cache entry
    ///   - ttl: Time to live in seconds
    func set<T>(_ value: T, forKey key: String, ttl: TimeInterval) {
        let entry = CacheEntry(value: value, expirationDate: Date().addingTimeInterval(ttl))
        queue.async(flags: .barrier) {
            self.cache[key] = entry
        }
    }

    /// Retrieve a value from cache
    /// - Parameter key: The cache key
    /// - Returns: The cached value if it exists and hasn't expired, nil otherwise
    func get<T>(forKey key: String) -> T? {
        var result: T?
        queue.sync {
            guard let entry = cache[key] as? CacheEntry<T> else {
                return
            }

            if entry.isExpired {
                // Remove expired entry
                queue.async(flags: .barrier) {
                    self.cache.removeValue(forKey: key)
                }
                return
            }

            result = entry.value
        }
        return result
    }

    /// Get cached value or compute and cache it if missing/expired
    /// - Parameters:
    ///   - key: The cache key
    ///   - ttl: Time to live in seconds
    ///   - compute: Closure to compute the value if not cached
    /// - Returns: The cached or computed value
    func getOrCompute<T>(forKey key: String, ttl: TimeInterval, compute: () -> T) -> T {
        if let cached: T = get(forKey: key) {
            return cached
        }

        let value = compute()
        set(value, forKey: key, ttl: ttl)
        return value
    }

    /// Async version of getOrCompute for async operations
    func getOrCompute<T>(forKey key: String, ttl: TimeInterval, compute: () async -> T) async -> T {
        if let cached: T = get(forKey: key) {
            return cached
        }

        let value = await compute()
        set(value, forKey: key, ttl: ttl)
        return value
    }

    /// Invalidate a specific cache entry
    func invalidate(forKey key: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: key)
        }
    }

    /// Invalidate all cache entries matching a prefix
    func invalidate(keysWithPrefix prefix: String) {
        queue.async(flags: .barrier) {
            let keysToRemove = self.cache.keys.filter { $0.hasPrefix(prefix) }
            keysToRemove.forEach { self.cache.removeValue(forKey: $0) }
        }
    }

    /// Clear all cache entries
    func clearAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }

    /// Clean up expired entries
    func cleanupExpired() {
        queue.async(flags: .barrier) {
            let expiredKeys = self.cache.compactMap { key, value -> String? in
                guard let entry = value as? CacheEntry<Any> else { return nil }
                return entry.isExpired ? key : nil
            }
            expiredKeys.forEach { self.cache.removeValue(forKey: $0) }
        }
    }
}

// MARK: - Cache Keys

extension CacheManager {
    /// Standard cache keys used across the app
    enum CacheKey {
        static let allFlattenedTasks = "cache.tasks.allFlattened"
        static func tasksForDate(_ date: Date) -> String {
            let dateString = ISO8601DateFormatter().string(from: date)
            return "cache.tasks.date.\(dateString)"
        }

        // Receipts
        static let todaysReceipts = "cache.receipts.today"
        static let todaysSpending = "cache.spending.today"
        static func receiptStats(year: Int) -> String {
            return "cache.receipts.stats.\(year)"
        }
        static func categoryBreakdown(year: Int, month: Int) -> String {
            return "cache.receipts.categoryBreakdown.\(year).\(month)"
        }

        // Recurring Expenses
        static let activeRecurringExpenses = "cache.recurringExpenses.active"
        static let allRecurringExpenses = "cache.recurringExpenses.all"
        static func recurringExpenseInstances(expenseId: UUID) -> String {
            return "cache.recurringExpenses.instances.\(expenseId.uuidString)"
        }
        static let recurringExpensesUpcoming = "cache.recurringExpenses.upcoming"

        // Other
        static let birthdaysThisWeek = "cache.birthdays.week"
        static let todaysVisits = "cache.visits.today"
        static func locationStats(_ placeId: String) -> String {
            return "cache.location.stats.\(placeId)"
        }
        static func visitHistory(_ placeId: String) -> String {
            return "cache.visits.history.\(placeId)"
        }
        
        // Maps/Locations
        static let topLocations = "cache.maps.topLocations"
        static let recentlyVisitedPlaces = "cache.maps.recentlyVisited"
        static let allLocationsRanking = "cache.maps.allLocationsRanking"
        static let weeklyVisitsSummary = "cache.maps.weeklyVisitsSummary"
        static func categoryPlaces(_ category: String) -> String {
            return "cache.maps.category.\(category)"
        }
        
        static let upcomingNoteReminders = "cache.notes.reminders.upcoming"
        
        // Email Profile Pictures
        static func emailProfilePicture(_ email: String) -> String {
            return "cache.email.profilePicture.v2.\(email.lowercased())"
        }
    }

    /// Standard TTL values (in seconds)
    enum TTL {
        static let short: TimeInterval = 60 // 1 minute
        static let medium: TimeInterval = 300 // 5 minutes
        static let long: TimeInterval = 3600 // 1 hour
        static let veryLong: TimeInterval = 86400 // 24 hours
        static let persistent: TimeInterval = 31536000 * 100 // ~100 years - effectively infinite
    }
}
