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
            sender: email.sender,
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
                    case .calendar:
                        return email.hasCalendarEvent
                    }
                }
                .sorted { $0.date > $1.date }
            
            return categoryEmails
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached data
    func clearCache() {
        cacheQueue.async { [weak self] in
            self?.emailCache.removeAll()
            self?.previewCache.removeAll()
            self?.cacheAccessOrder.removeAll()
            
            DispatchQueue.main.async {
                self?.currentCacheSize = 0
                ProductionLogger.logEmailOperation("Cache cleared")
            }
        }
    }
    
    /// Clear expired cache entries
    func clearExpiredEntries() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            var removedCount = 0
            
            // Remove expired emails
            let expiredEmailIds = self.emailCache.compactMap { key, cached in
                cached.isExpired ? key : nil
            }
            
            for id in expiredEmailIds {
                self.emailCache.removeValue(forKey: id)
                self.cacheAccessOrder.removeAll { $0 == id }
                removedCount += 1
            }
            
            // Remove expired previews
            let expiredPreviewIds = self.previewCache.compactMap { key, preview in
                preview.isExpired ? key : nil
            }
            
            for id in expiredPreviewIds {
                self.previewCache.removeValue(forKey: id)
                removedCount += 1
            }
            
            DispatchQueue.main.async {
                self.currentCacheSize = self.emailCache.count
                if removedCount > 0 {
                    ProductionLogger.logEmailOperation("Removed \(removedCount) expired cache entries")
                }
            }
        }
    }
    
    /// Pre-load email content for visible emails
    func preloadEmailContent(for emailIds: [String], priority: TaskPriority = .medium) {
        Task(priority: priority) {
            for emailId in emailIds {
                // Only preload if not already cached with full body
                if let cached = getCachedEmail(id: emailId), !cached.body.isEmpty {
                    continue // Already have full content
                }
                
                // Request full email content in background
                // This would integrate with GmailService to fetch full content
                await preloadSingleEmail(id: emailId)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func ensureCacheCapacity() {
        while emailCache.count >= maxCacheSize && !cacheAccessOrder.isEmpty {
            // Remove least recently used email
            let lruId = cacheAccessOrder.removeFirst()
            emailCache.removeValue(forKey: lruId)
        }
    }
    
    private func updateAccessOrder(id: String) {
        // Remove from current position
        cacheAccessOrder.removeAll { $0 == id }
        // Add to end (most recently used)
        cacheAccessOrder.append(id)
    }
    
    private func recordCacheRequest(hit: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.totalCacheRequests += 1
            if hit {
                self.cacheHits += 1
            }
            
            self.cacheHitRate = self.totalCacheRequests > 0 ?
                Double(self.cacheHits) / Double(self.totalCacheRequests) : 0.0
        }
    }
    
    private func startPeriodicCleanup() {
        // Clean up expired entries every 5 minutes
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.cleanupQueue.async {
                self?.clearExpiredEntries()
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    private func preloadSingleEmail(id: String) async {
        // This would integrate with GmailService to fetch full email content
        // For now, we'll just update the cache timestamp to indicate preloading attempt
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            if var cached = self.emailCache[id] {
                cached.lastAccessed = Date()
                self.emailCache[id] = cached
            }
        }
    }
}

// MARK: - Supporting Types

private struct CachedEmail {
    let email: Email
    let timestamp: Date
    let hasFullBody: Bool
    var lastAccessed: Date
    
    init(email: Email, timestamp: Date, hasFullBody: Bool) {
        self.email = email
        self.timestamp = timestamp
        self.hasFullBody = hasFullBody
        self.lastAccessed = timestamp
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > GmailQuotaManager.cacheExpirationInterval
    }
}

struct EmailPreview {
    let id: String
    let subject: String
    let sender: EmailContact
    let date: Date
    let isRead: Bool
    let isImportant: Bool
    let attachmentCount: Int
    let bodyPreview: String
    let timestamp: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > GmailQuotaManager.cacheExpirationInterval
    }
}

// Allow using this type inside @Sendable closures managed by dedicated queues
extension EmailCacheManager: @unchecked Sendable {}
