//
//  OutlierDetectionService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation
import PostgREST

/// Service that uses statistical analysis to detect outlier visits that don't match
/// historical patterns for a location
@MainActor
class OutlierDetectionService: ObservableObject {
    static let shared = OutlierDetectionService()

    private let supabaseManager = SupabaseManager.shared

    // Statistical thresholds
    private let zScoreThreshold = 3.0      // Standard deviations from mean
    private let minimumSampleSize = 10     // Need at least 10 visits for reliable stats

    struct VisitStatistics {
        let mean: Double
        let standardDeviation: Double
        let median: Double
        let sampleSize: Int
        let durations: [Int]

        var isReliable: Bool {
            return sampleSize >= 10
        }
    }

    struct OutlierAnalysis {
        let isOutlier: Bool
        let zScore: Double
        let confidence: Double
        let reason: String
        let statistics: VisitStatistics?
    }

    private init() {}

    // MARK: - Outlier Detection

    /// Check if a visit is an outlier based on historical patterns
    func detectOutlier(
        placeId: UUID,
        duration: Int,
        entryTime: Date
    ) async -> OutlierAnalysis {
        // Fetch historical visit statistics
        guard let stats = await fetchVisitStatistics(for: placeId) else {
            return OutlierAnalysis(
                isOutlier: false,
                zScore: 0,
                confidence: 0.5,
                reason: "insufficient_data",
                statistics: nil
            )
        }

        // Not enough data for reliable detection
        if !stats.isReliable {
            return OutlierAnalysis(
                isOutlier: false,
                zScore: 0,
                confidence: 0.5,
                reason: "insufficient_samples",
                statistics: stats
            )
        }

        // Calculate z-score (how many standard deviations from mean)
        let zScore = abs((Double(duration) - stats.mean) / stats.standardDeviation)

        // Detect outliers (>3 standard deviations)
        let isOutlier = zScore > zScoreThreshold

        // Calculate confidence based on z-score
        let confidence: Double
        if zScore > 5.0 {
            confidence = 0.99 // Extremely confident
        } else if zScore > 4.0 {
            confidence = 0.95
        } else if zScore > 3.0 {
            confidence = 0.90
        } else if zScore > 2.0 {
            confidence = 0.70 // Somewhat unusual
        } else {
            confidence = 0.50 // Normal
        }

        // Determine reason
        var reason = ""
        if isOutlier {
            if duration > Int(stats.mean) {
                reason = "duration_too_long"
            } else {
                reason = "duration_too_short"
            }
        } else if zScore > 2.0 {
            reason = "duration_unusual"
        } else {
            reason = "normal"
        }

        print("📊 Outlier detection: duration=\(duration)min, mean=\(Int(stats.mean))min, z-score=\(String(format: "%.2f", zScore)), outlier=\(isOutlier)")

        return OutlierAnalysis(
            isOutlier: isOutlier,
            zScore: zScore,
            confidence: confidence,
            reason: reason,
            statistics: stats
        )
    }

    /// Batch detect outliers for multiple visits
    func detectOutliers(for visits: [LocationVisitRow]) async -> [UUID: OutlierAnalysis] {
        var results: [UUID: OutlierAnalysis] = [:]

        // Group visits by place
        let groupedVisits = Dictionary(grouping: visits) { $0.placeId }

        for (placeId, placeVisits) in groupedVisits {
            for visit in placeVisits {
                if let duration = visit.durationMinutes {
                    let analysis = await detectOutlier(
                        placeId: placeId,
                        duration: duration,
                        entryTime: visit.entryTime
                    )
                    results[visit.id] = analysis
                }
            }
        }

        return results
    }

    // MARK: - Statistics Calculation

    /// Fetch and calculate visit statistics for a location
    private func fetchVisitStatistics(for placeId: UUID) async -> VisitStatistics? {
        do {
            // Fetch recent visits (last 50 or 90 days, whichever is more)
            let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 3600)

            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("place_id", value: placeId.uuidString)
                .not("exit_time", operator: .is, value: "null")
                .gte("duration_minutes", value: 5)
                .gte("entry_time", value: ISO8601DateFormatter().string(from: ninetyDaysAgo))
                .order("entry_time", ascending: false)
                .limit(50)
                .execute()
                .value

            guard visits.count >= 3 else {
                return nil // Not enough data
            }

            let durations = visits.compactMap { $0.durationMinutes }

            // Calculate statistics
            let mean = durations.reduce(0, +) / durations.count
            let median = calculateMedian(durations)
            let stdDev = calculateStandardDeviation(durations, mean: Double(mean))

            return VisitStatistics(
                mean: Double(mean),
                standardDeviation: stdDev,
                median: Double(median),
                sampleSize: durations.count,
                durations: durations
            )

        } catch {
            print("❌ Error fetching visit statistics: \(error)")
            return nil
        }
    }

    /// Calculate median of integer array
    private func calculateMedian(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }

    /// Calculate standard deviation
    private func calculateStandardDeviation(_ values: [Int], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }

        let variance = values.reduce(0.0) { sum, value in
            let diff = Double(value) - mean
            return sum + (diff * diff)
        } / Double(values.count)

        return sqrt(variance)
    }

    // MARK: - Batch Processing

    /// Scan all recent visits and flag outliers
    func scanAndFlagOutliers(daysBack: Int = 30) async -> (flagged: Int, scanned: Int) {
        do {
            let startDate = Date().addingTimeInterval(-Double(daysBack * 24 * 3600))

            // Fetch all recent completed visits
            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .not("exit_time", operator: .is, value: "null")
                .gte("entry_time", value: ISO8601DateFormatter().string(from: startDate))
                .execute()
                .value

            print("📊 Scanning \(visits.count) visits for outliers...")

            var flaggedCount = 0

            // Group by place for efficient processing
            let groupedVisits = Dictionary(grouping: visits) { $0.placeId }

            for (placeId, placeVisits) in groupedVisits {
                for visit in placeVisits {
                    guard let duration = visit.durationMinutes else { continue }

                    let analysis = await detectOutlier(
                        placeId: placeId,
                        duration: duration,
                        entryTime: visit.entryTime
                    )

                    if analysis.isOutlier && analysis.confidence >= 0.9 {
                        // Flag in database
                        await flagVisitAsOutlier(visit.id)
                        flaggedCount += 1
                    }
                }
            }

            print("✅ Outlier scan complete: flagged \(flaggedCount) out of \(visits.count) visits")
            return (flaggedCount, visits.count)

        } catch {
            print("❌ Error scanning for outliers: \(error)")
            return (0, 0)
        }
    }

    /// Flag a visit as outlier in database
    private func flagVisitAsOutlier(_ visitId: UUID) async {
        do {
            let client = await supabaseManager.getPostgrestClient()
            let updateData: [String: PostgREST.AnyJSON] = ["is_outlier": .bool(true)]
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visitId.uuidString)
                .execute()

            print("🚩 Flagged visit \(visitId) as outlier")
        } catch {
            print("❌ Error flagging outlier: \(error)")
        }
    }

    /// Auto-delete outliers with high confidence
    func deleteHighConfidenceOutliers(minimumConfidence: Double = 0.95) async -> Int {
        do {
            // Fetch flagged outliers
            let client = await supabaseManager.getPostgrestClient()
            let outliers: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("is_outlier", value: true)
                .execute()
                .value

            var deletedCount = 0

            for outlier in outliers {
                guard let duration = outlier.durationMinutes else { continue }

                // Re-validate confidence
                let analysis = await detectOutlier(
                    placeId: outlier.placeId,
                    duration: duration,
                    entryTime: outlier.entryTime
                )

                if analysis.confidence >= minimumConfidence {
                    // Delete
                    let client = await supabaseManager.getPostgrestClient()
            try await client
                        .from("location_visits")
                        .delete()
                        .eq("id", value: outlier.id.uuidString)
                        .execute()

                    deletedCount += 1
                    print("🗑️ Deleted outlier visit: \(outlier.id)")
                }
            }

            print("✅ Deleted \(deletedCount) high-confidence outliers")
            return deletedCount

        } catch {
            print("❌ Error deleting outliers: \(error)")
            return 0
        }
    }

    // MARK: - Helper Methods

    /// Get human-readable summary of outlier analysis
    func getSummary(for analysis: OutlierAnalysis) -> String {
        if analysis.isOutlier {
            return "⚠️ Outlier detected (z-score: \(String(format: "%.1f", analysis.zScore)), confidence: \(Int(analysis.confidence * 100))%)"
        } else if analysis.zScore > 2.0 {
            return "⚡ Unusual visit (z-score: \(String(format: "%.1f", analysis.zScore)))"
        } else {
            return "✅ Normal visit"
        }
    }
}
