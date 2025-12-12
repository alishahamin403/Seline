//
//  MotionDetectionService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation
import CoreMotion

/// Service that uses device motion sensors to validate user presence at locations
/// Helps eliminate false positives from traffic stops, drive-throughs, etc.
@MainActor
class MotionDetectionService: ObservableObject {
    static let shared = MotionDetectionService()

    private let motionActivityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    // Track current activity
    @Published private(set) var currentActivity: CMMotionActivity?
    @Published private(set) var isStationary: Bool = false

    // Track stationary percentage during visit
    private var activitySamples: [ActivitySample] = []

    struct ActivitySample {
        let timestamp: Date
        let isStationary: Bool
        let isAutomotive: Bool
        let isWalking: Bool
        let confidence: CMMotionActivityConfidence
    }

    private init() {
        startMonitoring()
    }

    // MARK: - Monitoring

    /// Start continuous motion activity monitoring
    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ Motion activity not available on this device")
            return
        }

        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }

            self.currentActivity = activity
            self.isStationary = activity.stationary && !activity.automotive && !activity.walking

            // Record sample for later analysis
            self.recordActivitySample(activity)

            print("📱 Motion: Stationary=\(activity.stationary), Auto=\(activity.automotive), Walking=\(activity.walking), Confidence=\(activity.confidence.rawValue)")
        }
    }

    /// Stop motion monitoring
    func stopMonitoring() {
        motionActivityManager.stopActivityUpdates()
    }

    // MARK: - Activity Recording

    private func recordActivitySample(_ activity: CMMotionActivity) {
        let sample = ActivitySample(
            timestamp: Date(),
            isStationary: activity.stationary,
            isAutomotive: activity.automotive,
            isWalking: activity.walking,
            confidence: activity.confidence
        )

        activitySamples.append(sample)

        // Keep only last hour of samples
        let oneHourAgo = Date().addingTimeInterval(-3600)
        activitySamples.removeAll { $0.timestamp < oneHourAgo }
    }

    // MARK: - Validation Methods

    /// Check if user is currently stationary (not moving)
    func isUserStationary() async -> Bool {
        // Return cached value if available
        if let activity = currentActivity {
            return activity.stationary && !activity.automotive && !activity.walking
        }

        // Otherwise query current activity
        return await withCheckedContinuation { continuation in
            motionActivityManager.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { activities, error in
                guard let activities = activities, let latest = activities.last else {
                    continuation.resume(returning: false)
                    return
                }

                let stationary = latest.stationary && !latest.automotive && !latest.walking
                continuation.resume(returning: stationary)
            }
        }
    }

    /// Check if user is in a vehicle (automotive motion)
    func isUserDriving() async -> Bool {
        if let activity = currentActivity {
            return activity.automotive
        }

        return await withCheckedContinuation { continuation in
            motionActivityManager.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { activities, error in
                guard let activities = activities, let latest = activities.last else {
                    continuation.resume(returning: false)
                    return
                }

                continuation.resume(returning: latest.automotive)
            }
        }
    }

    /// Calculate percentage of time user was stationary during a visit
    /// Returns value between 0.0 (never stationary) and 1.0 (always stationary)
    func getStationaryPercentage(from entryTime: Date, to exitTime: Date) -> Double {
        let relevantSamples = activitySamples.filter { sample in
            sample.timestamp >= entryTime && sample.timestamp <= exitTime
        }

        guard !relevantSamples.isEmpty else {
            // No data available - assume stationary (benefit of doubt)
            return 1.0
        }

        let stationaryCount = relevantSamples.filter { $0.isStationary }.count
        return Double(stationaryCount) / Double(relevantSamples.count)
    }

    /// Validate if motion pattern supports a genuine visit
    /// Returns confidence score 0.0-1.0
    func validateVisitMotion(entryTime: Date, exitTime: Date, duration: TimeInterval) -> (valid: Bool, confidence: Double, stationaryPercentage: Double) {
        let stationaryPct = getStationaryPercentage(from: entryTime, to: exitTime)

        // Calculate confidence based on stationary percentage and duration
        var confidence = stationaryPct

        // Longer visits with high stationary % get higher confidence
        if duration >= 1800 && stationaryPct >= 0.8 { // 30+ min, 80%+ stationary
            confidence = min(1.0, stationaryPct + 0.1)
        } else if duration >= 600 && stationaryPct >= 0.6 { // 10+ min, 60%+ stationary
            confidence = stationaryPct
        } else if stationaryPct < 0.3 { // Mostly moving - likely false positive
            confidence = stationaryPct * 0.5 // Penalize
        }

        // Valid if confidence >= 0.6 (60% stationary or better)
        let valid = confidence >= 0.6

        return (valid, confidence, stationaryPct)
    }

    /// Check if user was driving during dwell time (eliminates traffic stops)
    func wasDrivingDuringDwell(from startTime: Date, duration: TimeInterval) async -> Bool {
        let endTime = startTime.addingTimeInterval(duration)

        let drivingSamples = activitySamples.filter { sample in
            sample.timestamp >= startTime &&
            sample.timestamp <= endTime &&
            sample.isAutomotive &&
            sample.confidence != .low
        }

        // If >50% of samples show driving, user was likely in transit
        let totalSamples = activitySamples.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }.count
        guard totalSamples > 0 else { return false }

        let drivingPercentage = Double(drivingSamples.count) / Double(totalSamples)
        return drivingPercentage > 0.5
    }

    /// Clear old samples to free memory
    func clearOldSamples() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        activitySamples.removeAll { $0.timestamp < oneHourAgo }
    }

    // MARK: - Permission Check

    /// Check if motion activity permission is authorized
    func checkAuthorization() -> Bool {
        return CMMotionActivityManager.isActivityAvailable()
    }
}

// MARK: - Motion Activity Confidence Extension
extension CMMotionActivityConfidence {
    var description: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        @unknown default: return "Unknown"
        }
    }
}
