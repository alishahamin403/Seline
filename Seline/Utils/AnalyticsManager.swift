//
//  AnalyticsManager.swift
//  Seline
//
//  Created by Claude on 2025-08-25.
//

import Foundation
import UIKit
import Combine

/// Privacy-focused analytics manager for production monitoring
class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()
    
    // MARK: - Configuration
    
    private let configManager = ConfigurationManager.shared
    private let secureStorage = SecureStorage.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Properties
    
    @Published var isEnabled: Bool = false
    private var sessionID: String = UUID().uuidString
    private var appLaunchTime: Date = Date()
    private var eventQueue: [AnalyticsEvent] = []
    
    // MARK: - Event Limits (Privacy Protection)
    
    private let maxEventsPerSession = 100
    private let maxEventsInQueue = 50
    
    private init() {
        setupAnalytics()
    }
    
    // MARK: - Setup
    
    private func setupAnalytics() {
        isEnabled = configManager.isFeatureEnabled(.enableAnalytics)
        
        if isEnabled {
            // Start new session
            trackSessionStart()
            
            // Setup app lifecycle monitoring
            setupAppLifecycleTracking()
            
            // Setup periodic flush
            setupPeriodicFlush()
        }
    }
    
    private func setupAppLifecycleTracking() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.trackSessionBackground()
                self?.flushEvents()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.trackSessionForeground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.trackSessionEnd()
                self?.flushEvents()
            }
            .store(in: &cancellables)
    }
    
    private func setupPeriodicFlush() {
        Timer.publish(every: 300, on: .main, in: .common) // Every 5 minutes
            .autoconnect()
            .sink { [weak self] _ in
                self?.flushEventsIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Tracking Methods
    
    /// Track app launch
    func trackAppLaunch() {
        guard isEnabled else { return }
        
        track(event: AnalyticsEvent(
            name: "app_launch",
            category: .app,
            properties: [
                "app_version": configManager.getAppVersion(),
                "build_number": configManager.getBuildNumber(),
                "device_model": UIDevice.current.model,
                "os_version": UIDevice.current.systemVersion,
                "is_first_launch": isFirstLaunch()
            ]
        ))
    }
    
    /// Track search performed
    func trackSearch(query: String, searchType: SearchType, resultsCount: Int) {
        guard isEnabled else { return }
        
        // Privacy: Hash the query to protect user data
        let hashedQuery = hashString(query)
        
        track(event: AnalyticsEvent(
            name: "search_performed",
            category: .search,
            properties: [
                "query_hash": hashedQuery,
                "query_length": query.count,
                "search_type": searchType == .email ? "email" : "general",
                "results_count": resultsCount,
                "has_results": resultsCount > 0
            ]
        ))
    }
    
    /// Track email action
    func trackEmailAction(action: EmailAction, emailType: String? = nil) {
        guard isEnabled else { return }
        
        var properties: [String: Any] = [
            "action": action.rawValue
        ]
        
        if let emailType = emailType {
            properties["email_type"] = emailType
        }
        
        track(event: AnalyticsEvent(
            name: "email_action",
            category: .email,
            properties: properties
        ))
    }
    
    /// Track feature usage
    func trackFeatureUsed(_ feature: AppFeature) {
        guard isEnabled else { return }
        
        track(event: AnalyticsEvent(
            name: "feature_used",
            category: .feature,
            properties: [
                "feature": feature.rawValue,
                "session_duration": sessionDuration()
            ]
        ))
    }
    
    /// Track error occurrence
    func trackError(_ error: Error, context: String? = nil) {
        guard isEnabled else { return }
        
        var properties: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "error_description": error.localizedDescription
        ]
        
        if let context = context {
            properties["context"] = context
        }
        
        track(event: AnalyticsEvent(
            name: "error_occurred",
            category: .error,
            properties: properties
        ))
    }
    
    /// Track performance metric
    func trackPerformance(metric: String, duration: TimeInterval, context: String? = nil) {
        guard isEnabled else { return }
        
        var properties: [String: Any] = [
            "metric": metric,
            "duration_ms": Int(duration * 1000)
        ]
        
        if let context = context {
            properties["context"] = context
        }
        
        track(event: AnalyticsEvent(
            name: "performance_metric",
            category: .performance,
            properties: properties
        ))
    }
    
    /// Track user onboarding step
    func trackOnboardingStep(step: String, completed: Bool) {
        guard isEnabled else { return }
        
        track(event: AnalyticsEvent(
            name: "onboarding_step",
            category: .onboarding,
            properties: [
                "step": step,
                "completed": completed,
                "step_duration": sessionDuration()
            ]
        ))
    }
    
    // MARK: - Session Tracking
    
    private func trackSessionStart() {
        appLaunchTime = Date()
        sessionID = UUID().uuidString
        
        track(event: AnalyticsEvent(
            name: "session_start",
            category: .session,
            properties: [:]
        ))
    }
    
    private func trackSessionEnd() {
        track(event: AnalyticsEvent(
            name: "session_end",
            category: .session,
            properties: [
                "session_duration": sessionDuration(),
                "events_tracked": eventQueue.count
            ]
        ))
    }
    
    private func trackSessionBackground() {
        track(event: AnalyticsEvent(
            name: "session_background",
            category: .session,
            properties: [
                "foreground_duration": sessionDuration()
            ]
        ))
    }
    
    private func trackSessionForeground() {
        track(event: AnalyticsEvent(
            name: "session_foreground",
            category: .session,
            properties: [:]
        ))
    }
    
    // MARK: - Private Methods
    
    private func track(event: AnalyticsEvent) {
        guard isEnabled && eventQueue.count < maxEventsPerSession else { return }
        
        var eventWithMetadata = event
        eventWithMetadata.sessionID = sessionID
        eventWithMetadata.timestamp = Date()
        
        eventQueue.append(eventWithMetadata)
        
        if eventQueue.count >= maxEventsInQueue {
            flushEvents()
        }
    }
    
    private func flushEventsIfNeeded() {
        if eventQueue.count > 10 { // Flush if we have more than 10 events
            flushEvents()
        }
    }
    
    private func flushEvents() {
        guard !eventQueue.isEmpty else { return }
        
        // In production, send events to analytics service
        // For now, we'll just log them locally for privacy
        logEventsLocally(eventQueue)
        
        eventQueue.removeAll()
    }
    
    private func logEventsLocally(_ events: [AnalyticsEvent]) {
        // Log events locally for development
        // In production, replace with actual analytics service
        
        let summary = events.reduce(into: [String: Int]()) { result, event in
            result[event.name, default: 0] += 1
        }
        
        print("Analytics Summary: \(summary)")
    }
    
    private func sessionDuration() -> TimeInterval {
        return Date().timeIntervalSince(appLaunchTime)
    }
    
    private func isFirstLaunch() -> Bool {
        let key = "has_launched_before"
        let hasLaunched = UserDefaults.standard.bool(forKey: key)
        
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: key)
        }
        
        return !hasLaunched
    }
    
    private func hashString(_ string: String) -> String {
        // Simple hash for privacy - in production use proper cryptographic hash
        return String(string.hashValue)
    }
}

// MARK: - Analytics Event Model

struct AnalyticsEvent {
    let name: String
    let category: EventCategory
    let properties: [String: Any]
    var sessionID: String = ""
    var timestamp: Date = Date()
    
    enum EventCategory: String {
        case app = "app"
        case search = "search"
        case email = "email"
        case feature = "feature"
        case error = "error"
        case performance = "performance"
        case onboarding = "onboarding"
        case session = "session"
    }
}

// MARK: - Event Type Enums

enum EmailAction: String {
    case viewed = "viewed"
    case replied = "replied"
    case forwarded = "forwarded"
    case archived = "archived"
    case deleted = "deleted"
    case marked_read = "marked_read"
    case marked_unread = "marked_unread"
    case marked_important = "marked_important"
}

enum AppFeature: String {
    case email_search = "email_search"
    case ai_search = "ai_search"
    case email_categorization = "email_categorization"
    case swipe_actions = "swipe_actions"
    case pull_to_refresh = "pull_to_refresh"
    case search_suggestions = "search_suggestions"
    case voice_search = "voice_search"
    case dark_mode = "dark_mode"
    case notifications = "notifications"
}

// SearchType is defined in OpenAIService.swift

// MARK: - Performance Monitoring

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var startTimes: [String: Date] = [:]
    private let analytics = AnalyticsManager.shared
    
    private init() {}
    
    /// Start timing an operation
    func startTiming(_ operation: String) {
        startTimes[operation] = Date()
    }
    
    /// End timing and track performance
    func endTiming(_ operation: String, context: String? = nil) {
        guard let startTime = startTimes[operation] else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        startTimes.removeValue(forKey: operation)
        
        analytics.trackPerformance(metric: operation, duration: duration, context: context)
    }
    
    /// Measure execution time of a closure
    func measure<T>(_ operation: String, context: String? = nil, block: () throws -> T) rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation, context: context) }
        return try block()
    }
    
    /// Measure execution time of an async closure
    func measureAsync<T>(_ operation: String, context: String? = nil, block: () async throws -> T) async rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation, context: context) }
        return try await block()
    }
}

// MARK: - Privacy Utilities

extension AnalyticsManager {
    /// Check if user has consented to analytics
    var hasUserConsent: Bool {
        get {
            UserDefaults.standard.bool(forKey: "analytics_consent")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "analytics_consent")
            isEnabled = newValue && configManager.isFeatureEnabled(.enableAnalytics)
        }
    }
    
    /// Reset all analytics data
    func resetAnalyticsData() {
        eventQueue.removeAll()
        sessionID = UUID().uuidString
        UserDefaults.standard.removeObject(forKey: "analytics_consent")
        UserDefaults.standard.removeObject(forKey: "has_launched_before")
    }
}