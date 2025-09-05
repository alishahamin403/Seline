//
//  EmailSummaryCacheManager.swift
//  Seline
//
//  Caches AI-generated email summaries to avoid redundant API calls
//

import Foundation
import Combine

@MainActor
class EmailSummaryCacheManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let cacheKey = "emailSummaryCache"
    private let maxCacheAge: TimeInterval = 86400 * 7 // 7 days
    private let maxCacheSize = 1000 // Maximum number of cached summaries
    
    @Published private var summaryCache: [String: CachedSummary] = [:]
    private let cleanupTimer = ActorSafeTimer()
    
    init() {
        loadCache()
        setupPeriodicCleanup()
    }
    
    private func setupPeriodicCleanup() {
        // Clean expired entries every hour
        cleanupTimer.schedule(withTimeInterval: 3600, repeats: true) {
            Task {
                await self.cleanExpiredEntries()
            }
        }
    }
    
    func stop() {
        cleanupTimer.invalidate()
    }
    
    /// Get cached summary for email ID
    func getSummary(for emailId: String) async -> String? {
        return summaryCache[emailId]?.summary
    }
    
    /// Cache a summary for email ID
    func cacheSummary(_ summary: String, for emailId: String) async {
        let cachedSummary = CachedSummary(
            summary: summary,
            timestamp: Date(),
            emailId: emailId
        )
        
        summaryCache[emailId] = cachedSummary
        saveCache()
        
        print("💾 Cached summary for email: \(emailId)")
    }
    
    /// Check if summary exists in cache
    func hasSummary(for emailId: String) -> Bool {
        guard let cached = summaryCache[emailId] else { return false }
        
        // Check if cache entry is still valid (not expired)
        let age = Date().timeIntervalSince(cached.timestamp)
        return age < maxCacheAge
    }
    
    /// Clear all cached summaries
    func clearCache() async {
        summaryCache.removeAll()
        userDefaults.removeObject(forKey: cacheKey)
        print("🗑️ Cleared email summary cache")
    }
    
    /// Clear expired cache entries
    func cleanExpiredEntries() async {
        let now = Date()
        var removedCount = 0
        
        summaryCache = summaryCache.filter { (_, cached) in
            let age = now.timeIntervalSince(cached.timestamp)
            let shouldKeep = age < maxCacheAge
            if !shouldKeep {
                removedCount += 1
            }
            return shouldKeep
        }
        
        if removedCount > 0 {
            saveCache()
            print("🧹 Cleaned \(removedCount) expired summary cache entries")
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> CacheStats {
        let now = Date()
        let validEntries = summaryCache.values.filter { cached in
            let age = now.timeIntervalSince(cached.timestamp)
            return age < maxCacheAge
        }
        
        return CacheStats(
            totalEntries: summaryCache.count,
            validEntries: validEntries.count,
            expiredEntries: summaryCache.count - validEntries.count,
            cacheSize: summaryCache.count,
            maxCacheSize: maxCacheSize
        )
    }
    
    // MARK: - Private Methods
    
    private func loadCache() {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            print("📂 No cached email summaries found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode([String: CachedSummary].self, from: data)
            
            // Filter out expired entries during load
            let now = Date()
            summaryCache = cached.filter { (_, cachedSummary) in
                let age = now.timeIntervalSince(cachedSummary.timestamp)
                return age < maxCacheAge
            }
            
            print("📂 Loaded \(summaryCache.count) cached email summaries")
        } catch {
            print("❌ Failed to load email summary cache: \(error)")
            summaryCache = [:]
        }
    }
    
    private func saveCache() {
        // Limit cache size
        if summaryCache.count > maxCacheSize {
            // Remove oldest entries
            let sortedEntries = summaryCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let entriesToRemove = sortedEntries.prefix(summaryCache.count - maxCacheSize)
            
            for (key, _) in entriesToRemove {
                summaryCache.removeValue(forKey: key)
            }
            
            print("📦 Trimmed cache to \(summaryCache.count) entries")
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summaryCache)
            userDefaults.set(data, forKey: cacheKey)
        } catch {
            print("❌ Failed to save email summary cache: \(error)")
        }
    }
}


// MARK: - Data Models

struct CachedSummary: Codable {
    let summary: String
    let timestamp: Date
    let emailId: String
}

struct CacheStats {
    let totalEntries: Int
    let validEntries: Int
    let expiredEntries: Int
    let cacheSize: Int
    let maxCacheSize: Int
    
    var hitRate: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(validEntries) / Double(totalEntries)
    }
    
    var description: String {
        return """
        Cache Stats:
        - Total entries: \(totalEntries)
        - Valid entries: \(validEntries)
        - Expired entries: \(expiredEntries)
        - Cache size: \(cacheSize)/\(maxCacheSize)
        - Hit rate: \(String(format: "%.1f%%", hitRate * 100))
        """
    }
}
