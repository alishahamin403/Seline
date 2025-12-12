//
//  AdaptiveDurationService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation

/// Service that learns optimal minimum duration thresholds per location
/// based on historical visit patterns and user feedback
@MainActor
class AdaptiveDurationService: ObservableObject {
    static let shared = AdaptiveDurationService()

    private let supabaseManager = SupabaseManager.shared

    // In-memory cache of thresholds
    private var thresholdCache: [UUID: LocationThreshold] = [:]
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    struct LocationThreshold {
        let placeId: UUID
        var minDurationMinutes: Int
        var dwellTimeSeconds: Int
        var learnedFromFeedback: Bool
        var feedbackCount: Int

        init(placeId: UUID, minDurationMinutes: Int = 10, dwellTimeSeconds: Int = 180) {
            self.placeId = placeId
            self.minDurationMinutes = minDurationMinutes
            self.dwellTimeSeconds = dwellTimeSeconds
            self.learnedFromFeedback = false
            self.feedbackCount = 0
        }
    }

    private init() {}

    // MARK: - Fetch Thresholds

    /// Get minimum duration threshold for a location
    func getMinimumDuration(for placeId: UUID) async -> Int {
        // Check cache first
        if let cached = getCachedThreshold(for: placeId) {
            return cached.minDurationMinutes
        }

        // Fetch from database or learn from history
        let threshold = await fetchOrLearnThreshold(for: placeId)
        return threshold.minDurationMinutes
    }

    /// Get dwell time threshold for a location
    func getDwellTime(for placeId: UUID) async -> Int {
        if let cached = getCachedThreshold(for: placeId) {
            return cached.dwellTimeSeconds
        }

        let threshold = await fetchOrLearnThreshold(for: placeId)
        return threshold.dwellTimeSeconds
    }

    /// Get full threshold object
    func getThreshold(for placeId: UUID) async -> LocationThreshold {
        if let cached = getCachedThreshold(for: placeId) {
            return cached
        }

        return await fetchOrLearnThreshold(for: placeId)
    }

    // MARK: - Cache Management

    private func getCachedThreshold(for placeId: UUID) -> LocationThreshold? {
        // Check if cache is still valid
        if let timestamp = cacheTimestamp, Date().timeIntervalSince(timestamp) < cacheTTL {
            return thresholdCache[placeId]
        }
        return nil
    }

    private func cacheThreshold(_ threshold: LocationThreshold) {
        thresholdCache[threshold.placeId] = threshold
        cacheTimestamp = Date()
    }

    func clearCache() {
        thresholdCache.removeAll()
        cacheTimestamp = nil
    }

    // MARK: - Learning Algorithm

    /// Fetch threshold from database or learn from visit history
    private func fetchOrLearnThreshold(for placeId: UUID) async -> LocationThreshold {
        // Try to fetch existing threshold from database
        if let existing = await fetchThresholdFromDatabase(for: placeId) {
            cacheThreshold(existing)
            return existing
        }

        // Learn from historical visits
        let learned = await learnThresholdFromHistory(for: placeId)
        cacheThreshold(learned)

        // Save to database for future use
        await saveThreshold(learned)

        return learned
    }

    /// Fetch threshold from Supabase
    private func fetchThresholdFromDatabase(for placeId: UUID) async -> LocationThreshold? {
        do {
            let client = await supabaseManager.getPostgrestClient()
            let response: [LocationThresholdRow] = try await client
                .from("location_thresholds")
                .select()
                .eq("place_id", value: placeId.uuidString)
                .execute()
                .value

            guard let row = response.first else { return nil }

            return LocationThreshold(
                placeId: placeId,
                minDurationMinutes: row.minDurationMinutes,
                dwellTimeSeconds: row.dwellTimeSeconds
            )
        } catch {
            print("❌ Error fetching threshold: \(error)")
            return nil
        }
    }

    /// Learn optimal threshold from historical visit data
    private func learnThresholdFromHistory(for placeId: UUID) async -> LocationThreshold {
        do {
            // Fetch recent completed visits (last 50)
            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("place_id", value: placeId.uuidString)
                .not("exit_time", operator: .is, value: "null")
                .gte("duration_minutes", value: 5)
                .order("entry_time", ascending: false)
                .limit(50)
                .execute()
                .value

            guard !visits.isEmpty else {
                // No history - use defaults
                return LocationThreshold(placeId: placeId)
            }

            // Calculate statistics
            let durations = visits.map { $0.durationMinutes ?? 10 }
            let avgDuration = durations.reduce(0, +) / durations.count
            let sortedDurations = durations.sorted()

            // Use 25th percentile or 25% of average, whichever is smaller
            let percentile25 = sortedDurations[sortedDurations.count / 4]
            let quarterAverage = avgDuration / 4

            // Clamp between 5 and 15 minutes
            let minDuration = max(5, min(15, min(percentile25, quarterAverage)))

            // Dwell time = 50% of minimum duration, clamped to 60-300 seconds
            let dwellTime = max(60, min(300, minDuration * 30)) // 30 sec per minute

            print("📊 Learned threshold for place \(placeId): min=\(minDuration)min, dwell=\(dwellTime)s (from \(visits.count) visits, avg=\(avgDuration)min)")

            return LocationThreshold(
                placeId: placeId,
                minDurationMinutes: minDuration,
                dwellTimeSeconds: dwellTime
            )

        } catch {
            print("❌ Error learning threshold: \(error)")
            return LocationThreshold(placeId: placeId)
        }
    }

    // MARK: - Save & Update

    /// Save threshold to database
    func saveThreshold(_ threshold: LocationThreshold) async {
        do {
            let row = LocationThresholdRow(
                placeId: threshold.placeId,
                minDurationMinutes: threshold.minDurationMinutes,
                dwellTimeSeconds: threshold.dwellTimeSeconds,
                learnedFromFeedback: threshold.learnedFromFeedback,
                feedbackCount: threshold.feedbackCount
            )

            let client = await supabaseManager.getPostgrestClient()
            try await client
                .from("location_thresholds")
                .upsert(row)
                .execute()

            print("✅ Saved threshold for place \(threshold.placeId)")
        } catch {
            print("❌ Error saving threshold: \(error)")
        }
    }

    /// Update threshold based on user feedback
    func updateFromFeedback(placeId: UUID, feedbackType: String, visitDuration: Int) async {
        var threshold = await getThreshold(for: placeId)

        switch feedbackType {
        case "too_short":
            // User said visit was too short - increase minimum
            threshold.minDurationMinutes = min(30, threshold.minDurationMinutes + 5)
            threshold.dwellTimeSeconds = min(300, threshold.dwellTimeSeconds + 30)

        case "just_passing_by":
            // User was just passing by - increase dwell time
            threshold.dwellTimeSeconds = min(300, threshold.dwellTimeSeconds + 60)

        case "wrong_location":
            // Wrong location detected - might need tighter geofence
            // Don't adjust duration thresholds
            break

        case "correct":
            // Visit was correct - validate thresholds are not too strict
            if visitDuration < threshold.minDurationMinutes {
                threshold.minDurationMinutes = max(5, visitDuration - 2)
            }

        default:
            break
        }

        threshold.learnedFromFeedback = true
        threshold.feedbackCount += 1

        // Save updated threshold
        await saveThreshold(threshold)

        // Update cache
        cacheThreshold(threshold)

        print("✅ Updated threshold from feedback: min=\(threshold.minDurationMinutes)min, dwell=\(threshold.dwellTimeSeconds)s")
    }

    /// Manually set threshold (override learning)
    func setManualThreshold(placeId: UUID, minDurationMinutes: Int, dwellTimeSeconds: Int) async {
        let threshold = LocationThreshold(
            placeId: placeId,
            minDurationMinutes: minDurationMinutes,
            dwellTimeSeconds: dwellTimeSeconds
        )

        await saveThreshold(threshold)
        cacheThreshold(threshold)
    }

    // MARK: - Batch Operations

    /// Learn thresholds for all locations with sufficient history
    func learnAllThresholds() async {
        do {
            // Get all places with at least 10 visits
            let client = await supabaseManager.getPostgrestClient()
            let places: [PlaceRow] = try await client
                .from("saved_places")
                .select()
                .execute()
                .value

            print("📊 Learning thresholds for \(places.count) places...")

            for place in places {
                let _ = await fetchOrLearnThreshold(for: place.id)
            }

            print("✅ Threshold learning complete")
        } catch {
            print("❌ Error learning all thresholds: \(error)")
        }
    }
}

// MARK: - Database Models

struct LocationThresholdRow: Codable {
    let placeId: UUID
    let minDurationMinutes: Int
    let dwellTimeSeconds: Int
    let learnedFromFeedback: Bool
    let feedbackCount: Int

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case minDurationMinutes = "min_duration_minutes"
        case dwellTimeSeconds = "dwell_time_seconds"
        case learnedFromFeedback = "learned_from_feedback"
        case feedbackCount = "feedback_count"
    }
}
