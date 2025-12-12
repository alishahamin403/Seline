//
//  SignalQualityTracker.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation
import CoreLocation

/// Service that tracks GPS and network signal quality during visits
/// to identify low-quality data that should be filtered or flagged
@MainActor
class SignalQualityTracker: ObservableObject {
    static let shared = SignalQualityTracker()

    // Track signal events
    private var signalDropEvents: [SignalEvent] = []
    private var lowAccuracyEvents: [SignalEvent] = []

    // Current signal quality
    @Published private(set) var currentAccuracy: CLLocationAccuracy = 0
    @Published private(set) var signalQuality: SignalQuality = .unknown

    struct SignalEvent {
        let timestamp: Date
        let eventType: EventType
        let accuracy: CLLocationAccuracy?
        let placeId: UUID?

        enum EventType {
            case signalLost
            case lowAccuracy
            case signalRestored
            case highAccuracy
        }
    }

    enum SignalQuality {
        case excellent  // <10m
        case good       // 10-30m
        case fair       // 30-65m
        case poor       // >65m
        case unknown

        var description: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            case .unknown: return "Unknown"
            }
        }

        var confidence: Double {
            switch self {
            case .excellent: return 1.0
            case .good: return 0.9
            case .fair: return 0.7
            case .poor: return 0.5
            case .unknown: return 0.6
            }
        }
    }

    private init() {
        // Start cleanup timer
        startPeriodicCleanup()
    }

    // MARK: - Signal Monitoring

    /// Record a location update with accuracy
    func recordLocationUpdate(accuracy: CLLocationAccuracy, for placeId: UUID? = nil) {
        currentAccuracy = accuracy
        signalQuality = getSignalQuality(for: accuracy)

        // Record events based on accuracy changes
        if accuracy < 0 {
            // Signal lost
            recordEvent(.signalLost, accuracy: accuracy, placeId: placeId)
        } else if accuracy > 65 {
            // Poor accuracy
            recordEvent(.lowAccuracy, accuracy: accuracy, placeId: placeId)
        } else if accuracy <= 10 {
            // Excellent accuracy
            recordEvent(.highAccuracy, accuracy: accuracy, placeId: placeId)
        } else if accuracy <= 30 {
            // Good accuracy - signal restored if was poor before
            if let lastEvent = signalDropEvents.last,
               lastEvent.timestamp.timeIntervalSinceNow > -300 {
                recordEvent(.signalRestored, accuracy: accuracy, placeId: placeId)
            }
        }
    }

    /// Record signal drop event
    func recordSignalDrop(at time: Date = Date(), placeId: UUID? = nil) {
        recordEvent(.signalLost, accuracy: nil, placeId: placeId)
    }

    /// Record low accuracy event
    func recordLowAccuracy(accuracy: CLLocationAccuracy, at time: Date = Date(), placeId: UUID? = nil) {
        recordEvent(.lowAccuracy, accuracy: accuracy, placeId: placeId)
    }

    private func recordEvent(_ type: SignalEvent.EventType, accuracy: CLLocationAccuracy?, placeId: UUID?) {
        let event = SignalEvent(
            timestamp: Date(),
            eventType: type,
            accuracy: accuracy,
            placeId: placeId
        )

        switch type {
        case .signalLost:
            signalDropEvents.append(event)
        case .lowAccuracy:
            lowAccuracyEvents.append(event)
        case .signalRestored, .highAccuracy:
            // Just log, don't store
            break
        }

        print("📡 Signal Event: \(type) at \(Date()), accuracy: \(accuracy ?? -1)m")
    }

    // MARK: - Quality Analysis

    /// Get signal quality classification
    private func getSignalQuality(for accuracy: CLLocationAccuracy) -> SignalQuality {
        if accuracy < 0 {
            return .unknown
        } else if accuracy <= 10 {
            return .excellent
        } else if accuracy <= 30 {
            return .good
        } else if accuracy <= 65 {
            return .fair
        } else {
            return .poor
        }
    }

    /// Get confidence score for a visit based on signal quality
    func getVisitConfidence(from entryTime: Date, to exitTime: Date) -> (confidence: Double, signalDrops: Int) {
        // Count signal drops during visit
        let drops = signalDropEvents.filter { event in
            event.timestamp >= entryTime && event.timestamp <= exitTime
        }

        let lowAccuracy = lowAccuracyEvents.filter { event in
            event.timestamp >= entryTime && event.timestamp <= exitTime
        }

        let dropCount = drops.count
        let lowAccuracyCount = lowAccuracy.count

        // Calculate confidence based on signal issues
        var confidence = 1.0

        // Penalize for signal drops
        if dropCount == 0 {
            confidence = 1.0
        } else if dropCount <= 2 {
            confidence = 0.95
        } else if dropCount <= 5 {
            confidence = 0.85
        } else if dropCount <= 10 {
            confidence = 0.7
        } else {
            confidence = 0.5 // Very unstable signal
        }

        // Further penalize for sustained low accuracy
        if lowAccuracyCount > 10 {
            confidence -= 0.1
        } else if lowAccuracyCount > 5 {
            confidence -= 0.05
        }

        return (max(0.0, confidence), dropCount)
    }

    /// Get stationary percentage during visit (from signal quality)
    func getStationaryPercentage(from entryTime: Date, to exitTime: Date) -> Double {
        // Count high-quality location updates (implies stationary)
        let allEvents = signalDropEvents + lowAccuracyEvents
        let relevantEvents = allEvents.filter { $0.timestamp >= entryTime && $0.timestamp <= exitTime }

        guard !relevantEvents.isEmpty else {
            return 1.0 // No signal issues = assume stationary
        }

        let duration = exitTime.timeIntervalSince(entryTime)
        let expectedSamples = Int(duration / 30) // Sample every 30 seconds

        // If we have fewer signal events than expected, signal was stable (stationary)
        let stablePercentage = 1.0 - (Double(relevantEvents.count) / Double(max(1, expectedSamples)))

        return max(0.0, min(1.0, stablePercentage))
    }

    /// Check if signal quality is acceptable for geofence entry
    func isAcceptableForEntry() -> Bool {
        return currentAccuracy >= 0 && currentAccuracy <= 30
    }

    /// Check if visit should be flagged due to poor signal
    func shouldFlagVisit(from entryTime: Date, to exitTime: Date) -> Bool {
        let (confidence, drops) = getVisitConfidence(from: entryTime, to: exitTime)

        // Flag if confidence < 0.7 or more than 5 drops
        return confidence < 0.7 || drops > 5
    }

    // MARK: - Statistics

    /// Get signal drop count for a specific visit
    func getSignalDropCount(from entryTime: Date, to exitTime: Date) -> Int {
        return signalDropEvents.filter { event in
            event.timestamp >= entryTime && event.timestamp <= exitTime
        }.count
    }

    /// Get average accuracy during visit
    func getAverageAccuracy(from entryTime: Date, to exitTime: Date) -> CLLocationAccuracy? {
        let events = (signalDropEvents + lowAccuracyEvents).filter { event in
            event.timestamp >= entryTime &&
            event.timestamp <= exitTime &&
            event.accuracy != nil
        }

        guard !events.isEmpty else { return nil }

        let totalAccuracy = events.compactMap { $0.accuracy }.reduce(0, +)
        return totalAccuracy / Double(events.count)
    }

    /// Get signal quality summary for visit
    func getQualitySummary(from entryTime: Date, to exitTime: Date) -> String {
        let (confidence, drops) = getVisitConfidence(from: entryTime, to: exitTime)
        let avgAccuracy = getAverageAccuracy(from: entryTime, to: exitTime)

        if let accuracy = avgAccuracy {
            return "Confidence: \(Int(confidence * 100))%, Drops: \(drops), Avg Accuracy: \(Int(accuracy))m"
        } else {
            return "Confidence: \(Int(confidence * 100))%, Drops: \(drops)"
        }
    }

    // MARK: - Cleanup

    /// Clean up old signal events (keep last 24 hours)
    private func cleanupOldEvents() {
        let oneDayAgo = Date().addingTimeInterval(-86400)

        signalDropEvents.removeAll { $0.timestamp < oneDayAgo }
        lowAccuracyEvents.removeAll { $0.timestamp < oneDayAgo }
    }

    /// Start periodic cleanup timer
    private func startPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldEvents()
            }
        }
    }

    /// Manual cleanup
    func clearOldEvents() {
        cleanupOldEvents()
    }

    /// Clear all events
    func clearAll() {
        signalDropEvents.removeAll()
        lowAccuracyEvents.removeAll()
    }
}
