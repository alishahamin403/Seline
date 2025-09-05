//
//  GmailQuotaManager.swift
//  Seline
//
//  Created by Claude on 2025-08-27.
//  Gmail API quota management and optimization
//

import Foundation

/// Gmail API quota limits and management
class GmailQuotaManager: ObservableObject {
    static let shared = GmailQuotaManager()
    
    // MARK: - Quota Configuration
    
    /// Maximum emails to fetch in initial load
    static let maxInitialEmails = 15
    
    /// Optimized limit for today's emails only
    static let todayEmailsLimit = 500
    
    /// Pagination size for "Load More"
    static let paginationSize = 25
    
    /// Maximum emails per category to avoid quota exhaustion
    static let maxCategoryEmails = 25
    
    /// Cache expiration time (30 minutes)
    static let cacheExpirationInterval: TimeInterval = 30 * 60
    
    /// Maximum API requests per minute (conservative estimate)
    static let maxRequestsPerMinute = 250
    
    /// Retry delay multiplier for exponential backoff
    static let retryBaseDelay: TimeInterval = 1.0
    
    // MARK: - Published State
    
    @Published var apiUsageToday: Int = 0
    @Published var requestsInLastMinute: Int = 0
    @Published var quotaStatus: QuotaStatus = .normal
    @Published var lastQuotaReset: Date = Date()
    
    // MARK: - Private State
    
    private var requestTimestamps: [Date] = []
    private let requestQueue = DispatchQueue(label: "gmail.quota", qos: .background)
    private let rateLimitSemaphore = DispatchSemaphore(value: 10) // Max 10 concurrent requests
    private var dailyResetTimer: Timer?
    private var metricsUpdateTimer: Timer?
    private var circuitBreakers: [String: CircuitBreaker] = [:]
    
    private init() {
        startQuotaMonitoring()
    }
    
    private func getCircuitBreaker(for operation: String) -> CircuitBreaker {
        if let breaker = circuitBreakers[operation] {
            return breaker
        } else {
            let newBreaker = CircuitBreaker()
            circuitBreakers[operation] = newBreaker
            return newBreaker
        }
    }
    
    // MARK: - Public API
    
    /// Check if we can make an API request without hitting limits
    func canMakeRequest() -> Bool {
        updateRequestMetrics()
        
        switch quotaStatus {
        case .normal:
            return requestsInLastMinute < Self.maxRequestsPerMinute
        case .warning:
            return requestsInLastMinute < (Self.maxRequestsPerMinute / 2)
        case .limited:
            return requestsInLastMinute < (Self.maxRequestsPerMinute / 4)
        case .exceeded:
            return false
        }
    }
    
    /// Pick a safe batch size based on current quota pressure
    func getOptimalBatchSize() -> Int {
        switch quotaStatus {
        case .normal:
            return Self.maxInitialEmails
        case .warning:
            return Self.maxInitialEmails / 2
        case .limited:
            return Self.paginationSize
        case .exceeded:
            return 0
        }
    }
    
    /// Record an API request for quota tracking
    func recordRequest() {
        requestQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            self.requestTimestamps.append(now)
            self.apiUsageToday += 1
            
            DispatchQueue.main.async {
                self.updateRequestMetrics()
                ProductionLogger.logNetworkOperation("Gmail API request", success: true)
            }
        }
    }
    
    /// Execute request with rate limiting and retry logic
    func executeWithQuotaControl<T>(
        operation: String,
        maxRetries: Int = 3,
        request: @escaping () async throws -> T
    ) async throws -> T {
        let circuitBreaker = getCircuitBreaker(for: operation)
        guard circuitBreaker.canAttemptRequest() else {
            throw GmailQuotaError.circuitBreakerOpen
        }
        
        guard canMakeRequest() else {
            throw GmailQuotaError.quotaExceeded
        }
        
        // Acquire semaphore for rate limiting without capturing self in the @Sendable closure
        let semaphore = rateLimitSemaphore
        let queue = requestQueue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                semaphore.wait()
                continuation.resume()
            }
        }
        
        defer {
            semaphore.signal()
        }
        
        // Execute with exponential backoff retry
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let result = try await request()
                recordRequest()
                circuitBreaker.recordSuccess()
                return result
            } catch {
                lastError = error
                circuitBreaker.recordFailure()
                
                // Check if it's a quota-related error
                if isQuotaError(error) {
                    updateQuotaStatus(.exceeded)
                    throw GmailQuotaError.quotaExceeded
                }
                
                // Exponential backoff for retries
                if attempt < maxRetries - 1 {
                    let delay = Self.retryBaseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        ProductionLogger.logNetworkError(lastError ?? GmailQuotaError.maxRetriesExceeded, request: operation)
        throw lastError ?? GmailQuotaError.maxRetriesExceeded
    }
    
    // MARK: - Private Methods
    
    private func startQuotaMonitoring() {
        // Reset quota metrics daily
        dailyResetTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.resetDailyQuota()
        }
        
        // Update request metrics every minute
        metricsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateRequestMetrics()
        }
    }
    
    deinit {
        dailyResetTimer?.invalidate()
        metricsUpdateTimer?.invalidate()
        dailyResetTimer = nil
        metricsUpdateTimer = nil
    }
    
    private func updateRequestMetrics() {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        // Clean old timestamps and count recent requests
        requestTimestamps = requestTimestamps.filter { $0 > oneMinuteAgo }
        requestsInLastMinute = requestTimestamps.count
        
        // Update quota status based on usage
        updateQuotaStatusBasedOnUsage()
    }
    
    private func updateQuotaStatusBasedOnUsage() {
        let usagePercentage = Double(requestsInLastMinute) / Double(Self.maxRequestsPerMinute)
        
        let newStatus: QuotaStatus
        if usagePercentage >= 1.0 {
            newStatus = .exceeded
        } else if usagePercentage >= 0.75 {
            newStatus = .limited
        } else if usagePercentage >= 0.5 {
            newStatus = .warning
        } else {
            newStatus = .normal
        }
        
        if newStatus != quotaStatus {
            quotaStatus = newStatus
            ProductionLogger.logNetworkOperation("Quota status changed to \(newStatus)", success: true)
        }
    }
    
    private func updateQuotaStatus(_ status: QuotaStatus) {
        DispatchQueue.main.async {
            self.quotaStatus = status
        }
    }
    
    private func resetDailyQuota() {
        apiUsageToday = 0
        lastQuotaReset = Date()
        quotaStatus = .normal
        ProductionLogger.logNetworkOperation("Daily quota reset", success: true)
    }
    
    private func isQuotaError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("quota") ||
               errorString.contains("rate limit") ||
               errorString.contains("429") ||
               errorString.contains("too many requests")
    }
}

// MARK: - Supporting Types

enum QuotaStatus: String, CaseIterable {
    case normal = "Normal"
    case warning = "Warning"
    case limited = "Limited"
    case exceeded = "Exceeded"
    
    var color: String {
        switch self {
        case .normal: return "green"
        case .warning: return "yellow"
        case .limited: return "orange"
        case .exceeded: return "red"
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "API usage is within normal limits"
        case .warning: return "API usage is elevated, reducing batch sizes"
        case .limited: return "API usage is high, using smaller batches"
        case .exceeded: return "API quota exceeded, using cached data"
        }
    }
}

enum GmailQuotaError: Error, LocalizedError {
    case quotaExceeded
    case rateLimitExceeded
    case maxRetriesExceeded
    case invalidResponse
    case circuitBreakerOpen
    
    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            return "Gmail API quota exceeded. Please try again later."
        case .rateLimitExceeded:
            return "Too many requests. Please wait before trying again."
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded."
        case .invalidResponse:
            return "Invalid response from Gmail API."
        case .circuitBreakerOpen:
            return "Circuit breaker is open. Please try again later."
        }
    }
}

// MARK: - Email Fetch Configuration

struct EmailFetchConfig {
    let maxResults: Int
    let query: String
    let includeBody: Bool
    let useCache: Bool
    
    static func forInbox(quotaManager: GmailQuotaManager) -> EmailFetchConfig {
        let maxResults = quotaManager.getOptimalBatchSize()
        return EmailFetchConfig(
            maxResults: maxResults,
            query: "is:unread OR (is:read newer_than:1d)",
            includeBody: false, // Only fetch body when opening email
            useCache: true
        )
    }
    
    static func forTodayOnly(quotaManager: GmailQuotaManager) -> EmailFetchConfig {
        let todaysDate = EmailFetchConfig.todaysDateString()
        return EmailFetchConfig(
            maxResults: GmailQuotaManager.todayEmailsLimit,
            query: "after:\(todaysDate)",
            includeBody: false,
            useCache: true
        )
    }
    
    static func forCategory(type: EmailCategoryType, quotaManager: GmailQuotaManager) -> EmailFetchConfig {
        let baseQuery: String
        switch type {
        case .important:
            // Prefer Gmail's Important label and also include starred as a signal
            // Limit to the last 7 days to reduce noise
            baseQuery = "(label:IMPORTANT OR label:STARRED)"
        case .promotional:
            baseQuery = "category:promotions"
        case .all:
            baseQuery = "in:inbox"
        case .unread:
            baseQuery = "is:unread in:inbox"
        @unknown default:
            baseQuery = "in:inbox"
        }
        
        return EmailFetchConfig(
            maxResults: min(GmailQuotaManager.maxCategoryEmails, quotaManager.getOptimalBatchSize()),
            query: "\(baseQuery) after:\(sevenDaysAgoString())",
            includeBody: false,
            useCache: true
        )
    }
    
    static func forSearch(query: String, quotaManager: GmailQuotaManager) -> EmailFetchConfig {
        return EmailFetchConfig(
            maxResults: GmailQuotaManager.paginationSize,
            query: "(\(query)) after:\(sevenDaysAgoString())",
            includeBody: false,
            useCache: false // Search results should be fresh
        )
    }
}

enum EmailCategoryType {
    case important
    case promotional
    case all
    case unread
}

// MARK: - Helper Functions

private func sevenDaysAgoString() -> String {
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter.string(from: sevenDaysAgo)
}

private func todaysDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter.string(from: Date())
}

extension EmailFetchConfig {
    static func todaysDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: Date())
    }
}

// Allow using this type inside @Sendable closures managed by dedicated queues
extension GmailQuotaManager: @unchecked Sendable {}
