///
//  EmailCacheManager.swift
//  Seline
//
//  Created by Claude on 2025-08-27.
//  Intelligent email caching for performance optimization
//

import Foundation

/// High-performance email caching system
class EmailCacheManager: ObservableObject {
    static let shared = EmailCacheManager()
    
    // MARK: - Cache Configuration
    
    private let maxCacheSize = 200 // Maximum emails to cache in memory
    private let cacheExpirationTime: TimeInterval = 30 * 60 // 30 minutes
    private let previewCacheSize = 100 // Email previews (without full body)
    
    // MARK: - Cache Storage
    
    private var emailCache: [String: CachedEmail] = [:]
    private var previewCache: [String: EmailPreview] = [:]
    private var cacheAccessOrder: [String] = [] // LRU tracking
    private var lastCacheCleanup = Date()
    
    private let cacheQueue = DispatchQueue(label: "email.cache", qos: .userInitiated)
    private let cleanupQueue = DispatchQueue(label: "email.cache.cleanup", qos: .utility)
    private var cleanupTimer: Timer?
    
    // MARK: - Published State
    
    @Published var cacheHitRate: Double = 0.0
    @Published var totalCacheRequests: Int = 0
    @Published var cacheHits: Int = 0
    @Published var currentCacheSize: Int = 0
    
    private init() {
        startPeriodicCleanup()
    }
    
    // MARK: - Email Caching
    
    /// Get email from cache or return nil if not cached/expired
    func getCachedEmail(id: String) -> Email? {
        return cacheQueue.sync {
            guard let cached = emailCache[id] else {
                recordCacheRequest(hit: false)
                return nil
            }
            
            // Check if cache entry is expired
            if cached.isExpired {
                emailCache.removeValue(forKey: id)
                cacheAccessOrder.removeAll { $0 == id }
                recordCacheRequest(hit: false)
                return nil
            }
            
            // Update access order for LRU
            updateAccessOrder(id: id)
            recordCacheRequest(hit: true)
            return cached.email
        }
    }
    
    /// Cache an email
    func cacheEmail(_ email: Email, includeFullBody: Bool = false) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure cache size doesn't exceed limit
            self.ensureCacheCapacity()
            
            let cachedEmail = CachedEmail(
                email: email,
                timestamp: Date(),
                hasFullBody: includeFullBody
            )
            
            self.emailCache[email.id] = cachedEmail
            self.updateAccessOrder(id: email.id)
            
            // Also cache as preview if we have the data
            self.cacheEmailPreview(email)
            
            DispatchQueue.main.async {
                self.currentCacheSize = self.emailCache.count
            }
        }
    }
    
    /// Cache multiple emails efficiently
    func cacheEmails(_ emails: [Email], includeFullBody: Bool = false) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            for email in emails {
                // Ensure cache capacity before adding each email
                self.ensureCacheCapacity()
                
                let cachedEmail = CachedEmail(
                    email: email,
                    timestamp: Date(),
                    hasFullBody: includeFullBody
                )
                
                self.emailCache[email.id] = cachedEmail
                self.updateAccessOrder(id: email.id)
                self.cacheEmailPreview(email)
            }
            
            DispatchQueue.main.async {
                self.currentCacheSize = self.emailCache.count
                ProductionLogger.logEmailOperation("Cached \(emails.count) emails", count: emails.count)
            }
        }
    }
    
    // MARK: - Email Preview Caching (Lightweight)
    
    /// Get email preview (without full body)
    func getCachedPreview(id: String) -> EmailPreview? {
        return cacheQueue.sync {
            guard let preview = previewCache[id] else { return nil }
            
            if preview.isExpired {
                previewCache.removeValue(forKey: id)
                return nil
            }
            
            return preview
        }
    }
    
    /// Cache email preview for quick list display
    private func cacheEmailPreview(_ email: Email) {
        let preview = EmailPreview(
            id: email.id,
            subject: email.subject,
            sender: email.sender.displayName,
            date: email.date,
            isRead: email.isRead,
            isImportant: email.isImportant,
            attachmentCount: email.attachments.count,
            bodyPreview: String(email.body.prefix(200)), // First 200 characters
            timestamp: Date()
        )
        
        previewCache[email.id] = preview
        
        // Keep preview cache size manageable
        if previewCache.count > previewCacheSize {
            let oldestKey = previewCache.min { $0.value.timestamp < $1.value.timestamp }?.key
            if let key = oldestKey {
                previewCache.removeValue(forKey: key)
            }
        }
    }
    
    // MARK: - Cache Categories
    
    /// Cache emails by category for quick access
    func cacheEmailsByCategory(_ emails: [Email], category: EmailCategoryType) {
        cacheQueue.async { [weak self] in
            // Category-specific caching with priority
            self?.cacheEmails(emails, includeFullBody: false)
            ProductionLogger.logEmailOperation("Cached \(category) emails", count: emails.count)
        }
    }
    
    /// Get all cached emails for a specific category
    func getCachedEmailsForCategory(_ category: EmailCategoryType) -> [Email] {
        return cacheQueue.sync {
            let categoryEmails = emailCache.values
                .compactMap { cached -> Email? in
                    guard !cached.isExpired else { return nil }
                    return cached.email
                }
                .filter { email in
                    switch category {
                    case .important:
                        return email.isImportant
                    case .promotional:
                        return email.isPromotional
                    case .all:
                        return true
                    case .unread:
                        return !email.isRead
                    }
                }
                .sorted { $0.date > $1.date }
            
            return categoryEmails
        }
    }
    
    // MARK: - Cache Management
    
    private func updateAccessOrder(id: String) {
        cacheAccessOrder.removeAll { $0 == id }
        cacheAccessOrder.append(id)
    }
    
    private func ensureCacheCapacity() {
        while emailCache.count >= maxCacheSize && !cacheAccessOrder.isEmpty {
            let oldestId = cacheAccessOrder.removeFirst()
            emailCache.removeValue(forKey: oldestId)
        }
    }
    
    private func recordCacheRequest(hit: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.totalCacheRequests += 1
            if hit {
                self.cacheHits += 1
            }
            self.cacheHitRate = Double(self.cacheHits) / Double(self.totalCacheRequests)
        }
    }
    
    private func startPeriodicCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }
    
    private func cleanupExpiredEntries() {
        cleanupQueue.async { [weak self] in
            guard let self = self else { return }
            
            var expiredIds: [String] = []
            
            for (id, cached) in self.emailCache {
                if cached.isExpired {
                    expiredIds.append(id)
                }
            }
            
            for id in expiredIds {
                self.emailCache.removeValue(forKey: id)
                self.cacheAccessOrder.removeAll { $0 == id }
            }
            
            let expiredPreviews = self.previewCache.filter { $0.value.isExpired }.keys
            for id in expiredPreviews {
                self.previewCache.removeValue(forKey: id)
            }
            
            DispatchQueue.main.async {
                self.currentCacheSize = self.emailCache.count
                ProductionLogger.logEmailOperation("Cleaned up expired cache entries", count: expiredIds.count)
            }
        }
    }
    
    /// Clear all cache
    func clearCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.emailCache.removeAll()
            self.previewCache.removeAll()
            self.cacheAccessOrder.removeAll()
            
            DispatchQueue.main.async {
                self.currentCacheSize = 0
                self.totalCacheRequests = 0
                self.cacheHits = 0
                self.cacheHitRate = 0.0
                ProductionLogger.logEmailOperation("Cleared email cache")
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - Supporting Structures

/// Cached email with metadata
private struct CachedEmail {
    let email: Email
    let timestamp: Date
    let hasFullBody: Bool
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > (30 * 60) // 30 minutes
    }
}

/// Lightweight email preview for list display
struct EmailPreview {
    let id: String
    let subject: String
    let sender: String
    let date: Date
    let isRead: Bool
    let isImportant: Bool
    let attachmentCount: Int
    let bodyPreview: String
    let timestamp: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > (30 * 60) // 30 minutes
    }
}

