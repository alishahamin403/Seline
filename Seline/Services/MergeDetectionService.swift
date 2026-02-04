import Foundation
import CoreLocation
import PostgREST

// MARK: - MergeDetectionService
//
// Simple instant merge for location visits:
// - Any visit (open or closed) with gap < 5 minutes is automatically merged
// - Happens instantly and invisibly before creating new visit
// - No complicated scoring, just simple time-based merge

@MainActor
class MergeDetectionService {
    static let shared = MergeDetectionService()

    // In-memory cache of recently closed visits (10 minute TTL)
    private var recentlyClosedVisits: [UUID: LocationVisitRecord] = [:]

    private init() {}

    // MARK: - Core Merge Detection

    /// Find a mergeable visit (open or recently closed) for a geofence entry event
    /// Returns the visit record and confidence score if found, nil otherwise
    func findMergeCandidate(
        for placeId: UUID,
        currentLocation: CLLocationCoordinate2D,
        geofenceRadius: CLLocationDistance
    ) async -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {

        // First check: In-memory cache (fastest, handles app backgrounding scenario)
        if let result = await checkInMemoryClosed(placeId: placeId) {
            return result
        }

        // Second check: Query Supabase for recent visits
        return await querySupabaseForMergeCandidate(
            placeId: placeId,
            currentLocation: currentLocation,
            geofenceRadius: geofenceRadius
        )
    }

    // MARK: - Simple Merge Check

    /// Simple merge logic: If gap < 10 minutes, always merge
    /// No complicated scoring - just instant merge for quick returns
    /// CRITICAL: Never merge visits on different calendar days (preserves midnight splits)
    /// ENHANCED: Handles continuous visits (zero or negative gap due to clock drift)
    private func checkForMerge(
        _ visit: LocationVisitRecord
    ) -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {

        // Check open visits (no exit time) - always continue an open visit
        if visit.exitTime == nil {
            print("✅ MERGE: Continuing open visit (started \(visit.entryTime))")
            return (visit, 1.0, "open_visit")
        }

        // Check closed visits
        guard let exitTime = visit.exitTime else { return nil }

        let secondsSinceExit = Date().timeIntervalSince(exitTime)
        let minutesSinceExit = Int(secondsSinceExit / 60)

        // CRITICAL: Don't merge visits that are on different calendar days
        // This preserves midnight splits - even if gap is tiny (e.g., 11:59:59 PM → 12:00:00 AM)
        let calendar = Calendar.current
        let exitDay = calendar.dateComponents([.year, .month, .day], from: exitTime)
        let currentDay = calendar.dateComponents([.year, .month, .day], from: Date())

        if exitDay != currentDay {
            print("🚫 MERGE BLOCKED: Exit was on different calendar day")
            print("   Exit: \(exitTime), Current: \(Date())")
            return nil
        }

        // CRITICAL FIX: Handle continuous visits (zero or near-zero gap)
        // This catches cases where exit time == entry time or within a few seconds
        // Also handles negative gaps due to clock drift (exit recorded slightly in future)
        if secondsSinceExit < 30 && secondsSinceExit >= -30 {
            print("✅ MERGE: Continuous visit detected (gap: \(String(format: "%.1f", secondsSinceExit))s)")
            print("   → Keeping original start time: \(visit.entryTime)")
            return (visit, 1.0, "continuous_visit")
        }

        // Simple rule: Gap < 7 minutes = always merge (only within same calendar day)
        if minutesSinceExit < 7 && minutesSinceExit >= 0 {
            print("✅ MERGE: Gap is \(minutesSinceExit) min (< 7 min threshold)")
            print("   → Keeping original start time: \(visit.entryTime)")
            return (visit, 1.0, "quick_return")
        }

        return nil
    }

    // MARK: - In-Memory Cache Check

    /// Check in-memory cache of recently closed visits (fastest path)
    private func checkInMemoryClosed(
        placeId: UUID
    ) async -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {
        guard let recentVisit = recentlyClosedVisits[placeId] else {
            return nil
        }

        // Use simplified merge check
        return checkForMerge(recentVisit)
    }

    // MARK: - Supabase Query

    /// Query Supabase for merge candidates
    /// Order by entry_time DESC to get most recent visit (both open and closed)
    private func querySupabaseForMergeCandidate(
        placeId: UUID,
        currentLocation: CLLocationCoordinate2D,
        geofenceRadius: CLLocationDistance
    ) async -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, cannot check Supabase for merge candidates")
            return nil
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .order("entry_time", ascending: false) // Most recent first
                .limit(1)
                .execute()

            // CRITICAL FIX: Use supabaseDecoder to handle PostgreSQL timestamp format
            // Standard .iso8601 fails on "2025-12-17 18:13:00.948" format
            let decoder = JSONDecoder.supabaseDecoder()

            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            guard let visit = visits.first else {
                print("ℹ️ No recent visits found in Supabase for this location")
                return nil
            }

            // Use simplified merge check
            if let result = checkForMerge(visit) {
                return result
            }

            print("ℹ️ Most recent visit doesn't meet merge criteria (gap >= 5 min)")
            return nil

        } catch {
            print("❌ Error querying Supabase for merge candidates: \(error)")
            return nil
        }
    }

    // MARK: - Visit Merging

    /// Execute the merge: Update visit to reopen it with same session_id
    func executeMerge(
        _ visit: LocationVisitRecord,
        newSessionId: UUID? = nil,
        confidence: Double,
        reason: String
    ) async -> LocationVisitRecord? {

        var mergedVisit = visit

        // Update merge metadata
        mergedVisit.sessionId = newSessionId ?? visit.sessionId ?? UUID()
        mergedVisit.confidenceScore = confidence
        mergedVisit.mergeReason = reason

        // Reopen the visit - KEEP the original entry time (don't overwrite with current time)
        // This preserves the true start time when visits are merged within 10 minutes
        // mergedVisit.entryTime remains unchanged (original start time)
        mergedVisit.exitTime = nil
        mergedVisit.durationMinutes = nil
        mergedVisit.updatedAt = Date()

        // Sync to Supabase
        if await updateMergedVisitInSupabase(mergedVisit) {
            print("🔄 Visit merged successfully with reason: \(reason)")
            print("   Confidence: \(String(format: "%.0f%%", confidence * 100))")

            // Add to in-memory cache for future reference
            cacheClosedVisit(mergedVisit)

            return mergedVisit
        }

        return nil
    }

    /// Update merged visit in Supabase (atomic operation)
    private func updateMergedVisitInSupabase(_ visit: LocationVisitRecord) async -> Bool {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user, cannot update merged visit")
            return false
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // NOTE: We intentionally don't update entry_time here to preserve the original start time
        // When merging visits, we want to keep when the user first arrived, not when they returned
        let updateData: [String: PostgREST.AnyJSON] = [
            "session_id": .string((visit.sessionId ?? UUID()).uuidString),
            "exit_time": .null, // Reopen visit
            "duration_minutes": .null,
            "confidence_score": .double(visit.confidenceScore ?? 1.0),
            "merge_reason": .string(visit.mergeReason ?? "unknown"),
            // entry_time is NOT updated - preserving original start time
            "updated_at": .string(formatter.string(from: Date()))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("💾 Merged visit updated in Supabase: \(visit.id.uuidString)")
            return true
        } catch {
            print("❌ Error updating merged visit in Supabase: \(error)")
            return false
        }
    }

    // MARK: - Cache Management

    /// Add a closed visit to the in-memory cache (10-minute TTL)
    func cacheClosedVisit(_ visit: LocationVisitRecord) {
        recentlyClosedVisits[visit.savedPlaceId] = visit

        // Auto-remove after 10 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            self?.recentlyClosedVisits.removeValue(forKey: visit.savedPlaceId)
        }
    }

    /// Clear cache (for testing or manual cleanup)
    func clearCache() {
        recentlyClosedVisits.removeAll()
    }

    /// Get cache size (for debugging)
    func getCacheSize() -> Int {
        return recentlyClosedVisits.count
    }
}
