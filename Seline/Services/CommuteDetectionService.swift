//
//  CommuteDetectionService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation
import PostgREST

/// Service that detects commute patterns and filters out brief stops during commutes
/// (gas stations, traffic lights, drive-throughs, etc.)
@MainActor
class CommuteDetectionService: ObservableObject {
    static let shared = CommuteDetectionService()

    private let supabaseManager = SupabaseManager.shared

    // Commute detection parameters
    private let morningCommuteStart = 6   // 6 AM
    private let morningCommuteEnd = 10    // 10 AM
    private let eveningCommuteStart = 16  // 4 PM
    private let eveningCommuteEnd = 20    // 8 PM
    private let maxCommuteStopDuration = 15 // minutes
    private let maxCommuteDuration = 120    // 2 hours

    struct CommutePattern {
        let startVisit: LocationVisitRow
        let endVisit: LocationVisitRow
        let intermediateStops: [LocationVisitRow]
        let isHomeToWork: Bool
        let isWorkToHome: Bool
        let totalDuration: Int
        let confidence: Double
    }

    struct CommuteAnalysis {
        let isCommuteStop: Bool
        let confidence: Double
        let reason: String
        let commutePattern: CommutePattern?
    }

    private init() {}

    // MARK: - Commute Detection

    /// Detect if a visit is a brief stop during a commute
    func detectCommuteStop(
        visit: LocationVisitRow,
        category: String?
    ) async -> CommuteAnalysis {
        // Quick filters
        guard let duration = visit.durationMinutes else {
            return CommuteAnalysis(isCommuteStop: false, confidence: 0, reason: "no_duration", commutePattern: nil)
        }

        // Stops longer than 15 minutes are not commute stops
        if duration > maxCommuteStopDuration {
            return CommuteAnalysis(isCommuteStop: false, confidence: 1.0, reason: "too_long", commutePattern: nil)
        }

        let hour = Calendar.current.component(.hour, from: visit.entryTime)

        // Check if within commute hours
        let isMorningCommute = hour >= morningCommuteStart && hour <= morningCommuteEnd
        let isEveningCommute = hour >= eveningCommuteStart && hour <= eveningCommuteEnd

        if !isMorningCommute && !isEveningCommute {
            return CommuteAnalysis(isCommuteStop: false, confidence: 0.8, reason: "outside_commute_hours", commutePattern: nil)
        }

        // Fetch nearby visits to identify commute pattern
        if let pattern = await detectCommutePattern(around: visit) {
            // Visit is part of a commute pattern
            let confidence = calculateCommuteConfidence(
                stop: visit,
                pattern: pattern,
                category: category
            )

            return CommuteAnalysis(
                isCommuteStop: confidence >= 0.7,
                confidence: confidence,
                reason: pattern.isHomeToWork ? "morning_commute" : "evening_commute",
                commutePattern: pattern
            )
        }

        return CommuteAnalysis(isCommuteStop: false, confidence: 0.5, reason: "no_pattern", commutePattern: nil)
    }

    /// Detect commute pattern around a visit
    private func detectCommutePattern(around visit: LocationVisitRow) async -> CommutePattern? {
        do {
            // Fetch visits in a 3-hour window around this visit
            let windowStart = visit.entryTime.addingTimeInterval(-3 * 3600)
            let windowEnd = visit.entryTime.addingTimeInterval(3 * 3600)

            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .gte("entry_time", value: ISO8601DateFormatter().string(from: windowStart))
                .lte("entry_time", value: ISO8601DateFormatter().string(from: windowEnd))
                .order("entry_time", ascending: true)
                .execute()
                .value

            guard visits.count >= 3 else { return nil }

            // Identify home and work visits
            let homeVisit = visits.first { isHomeLocation(placeId: $0.placeId) }
            let workVisit = visits.first { isWorkLocation(placeId: $0.placeId) }

            guard let home = homeVisit, let work = workVisit else {
                return nil
            }

            // Determine direction
            let isHomeToWork = home.entryTime < work.entryTime
            let isWorkToHome = work.entryTime < home.entryTime

            guard isHomeToWork || isWorkToHome else { return nil }

            let (startVisit, endVisit) = isHomeToWork ? (home, work) : (work, home)

            // Find intermediate stops
            let intermediateStops = visits.filter { v in
                v.id != startVisit.id &&
                v.id != endVisit.id &&
                v.entryTime > startVisit.entryTime &&
                v.entryTime < endVisit.entryTime &&
                (v.durationMinutes ?? 0) <= maxCommuteStopDuration
            }

            let totalDuration = Int((endVisit.entryTime.timeIntervalSince(startVisit.entryTime)) / 60)

            // Validate commute duration
            guard totalDuration <= maxCommuteDuration else { return nil }

            // Calculate confidence
            let confidence = calculatePatternConfidence(
                startVisit: startVisit,
                endVisit: endVisit,
                intermediateStops: intermediateStops,
                totalDuration: totalDuration
            )

            return CommutePattern(
                startVisit: startVisit,
                endVisit: endVisit,
                intermediateStops: intermediateStops,
                isHomeToWork: isHomeToWork,
                isWorkToHome: isWorkToHome,
                totalDuration: totalDuration,
                confidence: confidence
            )

        } catch {
            print("❌ Error detecting commute pattern: \(error)")
            return nil
        }
    }

    // MARK: - Confidence Calculation

    /// Calculate confidence that a stop is part of commute
    private func calculateCommuteConfidence(
        stop: LocationVisitRow,
        pattern: CommutePattern,
        category: String?
    ) -> Double {
        var confidence = 0.0

        // Factor 1: Short duration (40% weight)
        let duration = stop.durationMinutes ?? 0
        if duration <= 5 {
            confidence += 0.4
        } else if duration <= 10 {
            confidence += 0.25
        } else if duration <= 15 {
            confidence += 0.15
        }

        // Factor 2: Category suggests transient stop (30% weight)
        if let cat = category?.lowercased() {
            if ["gas station", "traffic", "parking"].contains(cat) {
                confidence += 0.3
            } else if ["drive-through", "atm", "toll"].contains(cat) {
                confidence += 0.25
            } else if ["coffee", "cafe"].contains(cat) && duration <= 10 {
                confidence += 0.15 // Quick coffee stop
            }
        }

        // Factor 3: Position in commute sequence (20% weight)
        let isInSequence = pattern.intermediateStops.contains { $0.id == stop.id }
        if isInSequence {
            confidence += 0.2
        }

        // Factor 4: Time of day (10% weight)
        let hour = Calendar.current.component(.hour, from: stop.entryTime)
        let isMorningCommute = hour >= morningCommuteStart && hour <= morningCommuteEnd
        let isEveningCommute = hour >= eveningCommuteStart && hour <= eveningCommuteEnd

        if (pattern.isHomeToWork && isMorningCommute) ||
           (pattern.isWorkToHome && isEveningCommute) {
            confidence += 0.1
        }

        return min(1.0, confidence)
    }

    /// Calculate confidence in commute pattern
    private func calculatePatternConfidence(
        startVisit: LocationVisitRow,
        endVisit: LocationVisitRow,
        intermediateStops: [LocationVisitRow],
        totalDuration: Int
    ) -> Double {
        var confidence = 0.5 // Base confidence

        // More confidence if reasonable commute duration
        if totalDuration >= 10 && totalDuration <= 60 {
            confidence += 0.3
        } else if totalDuration > 60 && totalDuration <= 120 {
            confidence += 0.1
        }

        // More confidence if there are intermediate stops
        if !intermediateStops.isEmpty {
            confidence += 0.2
        }

        return min(1.0, confidence)
    }

    // MARK: - Location Helpers

    /// Check if place is home location
    private func isHomeLocation(placeId: UUID) -> Bool {
        // TODO: Implement check against Place.isHome or category
        // For now, this is a placeholder
        return false
    }

    /// Check if place is work location
    private func isWorkLocation(placeId: UUID) -> Bool {
        // TODO: Implement check against Place.category == "work"
        // For now, this is a placeholder
        return false
    }

    // MARK: - Batch Processing

    /// Scan and flag commute stops
    func scanAndFlagCommuteStops(daysBack: Int = 30) async -> (flagged: Int, scanned: Int) {
        do {
            let startDate = Date().addingTimeInterval(-Double(daysBack * 24 * 3600))

            // Fetch short visits during commute hours
            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .not("exit_time", operator: .is, value: "null")
                .lte("duration_minutes", value: maxCommuteStopDuration)
                .gte("entry_time", value: ISO8601DateFormatter().string(from: startDate))
                .execute()
                .value

            print("📊 Scanning \(visits.count) short visits for commute stops...")

            var flaggedCount = 0

            for visit in visits {
                let analysis = await detectCommuteStop(visit: visit, category: nil)

                if analysis.isCommuteStop && analysis.confidence >= 0.7 {
                    // Flag in database
                    let client = await supabaseManager.getPostgrestClient()
                    let updateData: [String: PostgREST.AnyJSON] = ["is_commute_stop": .bool(true)]
                    try await client
                        .from("location_visits")
                        .update(updateData)
                        .eq("id", value: visit.id.uuidString)
                        .execute()

                    flaggedCount += 1
                }
            }

            print("✅ Commute scan complete: flagged \(flaggedCount) out of \(visits.count) visits")
            return (flaggedCount, visits.count)

        } catch {
            print("❌ Error scanning for commute stops: \(error)")
            return (0, 0)
        }
    }

    /// Delete flagged commute stops
    func deleteCommuteStops() async -> Int {
        do {
            let client = await supabaseManager.getPostgrestClient()
            let commuteStops: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("is_commute_stop", value: true)
                .execute()
                .value

            for stop in commuteStops {
                let client = await supabaseManager.getPostgrestClient()
                try await client
                    .from("location_visits")
                    .delete()
                    .eq("id", value: stop.id.uuidString)
                    .execute()
            }

            print("✅ Deleted \(commuteStops.count) commute stops")
            return commuteStops.count

        } catch {
            print("❌ Error deleting commute stops: \(error)")
            return 0
        }
    }

    // MARK: - Summary

    /// Get human-readable summary
    func getSummary(for analysis: CommuteAnalysis) -> String {
        if analysis.isCommuteStop {
            return "🚗 Commute stop detected (\(analysis.reason), confidence: \(Int(analysis.confidence * 100))%)"
        } else {
            return "✅ Not a commute stop"
        }
    }
}
