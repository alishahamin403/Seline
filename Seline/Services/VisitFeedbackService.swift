//
//  VisitFeedbackService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation

/// Service that collects user feedback on visit accuracy and uses it to improve
/// the tracking system through adaptive learning
@MainActor
class VisitFeedbackService: ObservableObject {
    static let shared = VisitFeedbackService()

    private let supabaseManager = SupabaseManager.shared
    private let adaptiveDurationService = AdaptiveDurationService.shared

    enum FeedbackType: String, CaseIterable {
        case tooShort = "too_short"
        case wrongLocation = "wrong_location"
        case justPassingBy = "just_passing_by"
        case incorrectTime = "incorrect_time"
        case duplicate = "duplicate"
        case correct = "correct"

        var displayName: String {
            switch self {
            case .tooShort: return "Visit too short"
            case .wrongLocation: return "Wrong location"
            case .justPassingBy: return "Just passing by"
            case .incorrectTime: return "Incorrect time"
            case .duplicate: return "Duplicate visit"
            case .correct: return "Correct visit"
            }
        }

        var icon: String {
            switch self {
            case .tooShort: return "⏱️"
            case .wrongLocation: return "📍"
            case .justPassingBy: return "🚶"
            case .incorrectTime: return "🕐"
            case .duplicate: return "📋"
            case .correct: return "✅"
            }
        }
    }

    struct VisitFeedback: Codable {
        let id: UUID
        let userId: UUID
        let visitId: UUID
        let feedbackType: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case visitId = "visit_id"
            case feedbackType = "feedback_type"
            case createdAt = "created_at"
        }
    }

    private init() {}

    // MARK: - Submit Feedback

    /// Submit feedback for a visit
    func submitFeedback(
        visitId: UUID,
        placeId: UUID,
        feedbackType: FeedbackType,
        visitDuration: Int
    ) async -> Bool {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID for feedback")
            return false
        }

        do {
            // 1. Save feedback to database
            let feedback = VisitFeedback(
                id: UUID(),
                userId: userId,
                visitId: visitId,
                feedbackType: feedbackType.rawValue,
                createdAt: Date()
            )

            let client = await supabaseManager.getPostgrestClient()
            try await client
                .from("visit_feedback")
                .insert(feedback)
                .execute()

            print("✅ Feedback submitted: \(feedbackType.rawValue)")

            // 2. Learn from feedback
            await applyFeedbackLearning(
                placeId: placeId,
                feedbackType: feedbackType,
                visitDuration: visitDuration,
                visitId: visitId
            )

            return true

        } catch {
            print("❌ Error submitting feedback: \(error)")
            return false
        }
    }

    // MARK: - Learning from Feedback

    /// Apply machine learning adjustments based on feedback
    private func applyFeedbackLearning(
        placeId: UUID,
        feedbackType: FeedbackType,
        visitDuration: Int,
        visitId: UUID
    ) async {
        switch feedbackType {
        case .tooShort:
            // User thinks visit was too short to count
            // Action: Increase minimum duration threshold
            await adaptiveDurationService.updateFromFeedback(
                placeId: placeId,
                feedbackType: "too_short",
                visitDuration: visitDuration
            )

            print("📚 Learning: Increased min duration for this location")

        case .justPassingBy:
            // User was just passing by, not actually visiting
            // Action: Increase dwell time requirement
            await adaptiveDurationService.updateFromFeedback(
                placeId: placeId,
                feedbackType: "just_passing_by",
                visitDuration: visitDuration
            )

            print("📚 Learning: Increased dwell time for this location")

        case .wrongLocation:
            // Geofence detected wrong location (overlap issue)
            // Action: Suggest geofence radius adjustment
            await suggestGeofenceAdjustment(placeId: placeId, decrease: true)

            print("📚 Learning: Suggested tighter geofence")

        case .correct:
            // User confirmed visit is correct
            // Action: Validate thresholds are not too strict
            await adaptiveDurationService.updateFromFeedback(
                placeId: placeId,
                feedbackType: "correct",
                visitDuration: visitDuration
            )

            print("📚 Learning: Validated current thresholds")

        case .incorrectTime:
            // Visit time is wrong
            // Action: Log for debugging, might indicate GPS/merge issues
            print("⚠️ Incorrect time reported - possible GPS/merge issue")

        case .duplicate:
            // Visit is duplicate
            // Action: Improve merge detection for this location
            print("⚠️ Duplicate reported - review merge logic")
        }

        // Delete the visit if it's not correct
        if feedbackType != .correct {
            await deleteIncorrectVisit(visitId)
        }
    }

    /// Delete visit marked as incorrect
    private func deleteIncorrectVisit(_ visitId: UUID) async {
        do {
            let client = await supabaseManager.getPostgrestClient()
            try await client
                .from("location_visits")
                .delete()
                .eq("id", value: visitId.uuidString)
                .execute()

            print("🗑️ Deleted incorrect visit: \(visitId)")
        } catch {
            print("❌ Error deleting visit: \(error)")
        }
    }

    /// Suggest geofence radius adjustment
    private func suggestGeofenceAdjustment(placeId: UUID, decrease: Bool) async {
        // TODO: Integrate with GeofenceRadiusManager
        // For now, just log the suggestion
        print("💡 Suggestion: \(decrease ? "Decrease" : "Increase") geofence radius for place \(placeId)")
    }

    // MARK: - Feedback Stats

    /// Get feedback statistics for a location
    func getFeedbackStats(for placeId: UUID) async -> [FeedbackType: Int] {
        do {
            // Fetch all feedback for visits at this location
            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("place_id", value: placeId.uuidString)
                .execute()
                .value

            let visitIds = visits.map { $0.id.uuidString }
            guard !visitIds.isEmpty else { return [:] }

            let feedback: [VisitFeedback] = try await client
                .from("visit_feedback")
                .select()
                .in("visit_id", values: visitIds)
                .execute()
                .value

            // Count by type
            var stats: [FeedbackType: Int] = [:]
            for fb in feedback {
                if let type = FeedbackType(rawValue: fb.feedbackType) {
                    stats[type, default: 0] += 1
                }
            }

            return stats

        } catch {
            print("❌ Error fetching feedback stats: \(error)")
            return [:]
        }
    }

    /// Get overall feedback summary
    func getOverallStats() async -> (total: Int, byType: [FeedbackType: Int], accuracy: Double) {
        do {
            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
                return (0, [:], 0)
            }

            let client = await supabaseManager.getPostgrestClient()
            let feedback: [VisitFeedback] = try await client
                .from("visit_feedback")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            var byType: [FeedbackType: Int] = [:]
            for fb in feedback {
                if let type = FeedbackType(rawValue: fb.feedbackType) {
                    byType[type, default: 0] += 1
                }
            }

            let correctCount = byType[.correct] ?? 0
            let total = feedback.count
            let accuracy = total > 0 ? Double(correctCount) / Double(total) : 0

            return (total, byType, accuracy)

        } catch {
            print("❌ Error fetching overall stats: \(error)")
            return (0, [:], 0)
        }
    }

    // MARK: - Bulk Operations

    /// Mark all visits on a day as correct
    func markDayAsCorrect(date: Date) async -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        do {
            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return 0 }

            // Fetch all visits for the day
            let client = await supabaseManager.getPostgrestClient()
            let visits: [LocationVisitRow] = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: ISO8601DateFormatter().string(from: startOfDay))
                .lt("entry_time", value: ISO8601DateFormatter().string(from: endOfDay))
                .execute()
                .value

            var markedCount = 0

            for visit in visits {
                let success = await submitFeedback(
                    visitId: visit.id,
                    placeId: visit.placeId,
                    feedbackType: .correct,
                    visitDuration: visit.durationMinutes ?? 0
                )

                if success {
                    markedCount += 1
                }
            }

            print("✅ Marked \(markedCount) visits as correct for \(startOfDay)")
            return markedCount

        } catch {
            print("❌ Error marking day as correct: \(error)")
            return 0
        }
    }
}
