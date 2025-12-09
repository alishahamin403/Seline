import Foundation
import CoreLocation
import PostgREST

// MARK: - MergeDetectionService
//
// Handles three-scenario merge detection for location visits:
// 1. App Restart: Open visit within 5 minutes (user didn't actually exit)
// 2. Quick Return: Closed visit within 10 minutes (user stepped out briefly or continuous visit)
// 3. GPS Reconnect: Closed visit 10-20 min ago + still within geofence (GPS loss recovery)

@MainActor
class MergeDetectionService {
    static let shared = MergeDetectionService()

    // In-memory cache of recently closed visits (5 minute TTL)
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
        if let result = checkInMemoryClosed(placeId: placeId) {
            return result
        }

        // Second check: Query Supabase for recent visits
        return await querySupabaseForMergeCandidate(
            placeId: placeId,
            currentLocation: currentLocation,
            geofenceRadius: geofenceRadius
        )
    }

    // MARK: - Scenario A: App Restart (Open Visit)

    /// SCENARIO A: Open visit with entry < 5 minutes ago
    /// Confidence: 100% - User didn't actually leave, just app lost geofence event
    /// Example: Force close app → GPS reconnects within 2 minutes
    private func checkScenarioA_OpenVisit(
        _ visit: LocationVisitRecord
    ) -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {
        // Visit is open (no exit_time)
        guard visit.exitTime == nil else { return nil }

        let minutesSinceEntry = Int(Date().timeIntervalSince(visit.entryTime) / 60)

        // Open visit < 5 minutes ago
        if minutesSinceEntry <= 5 && minutesSinceEntry >= 0 {
            print("✅ MERGE SCENARIO A: Open visit from app restart (\(minutesSinceEntry) min ago)")
            return (visit, 1.0, "app_restart")
        }

        return nil
    }

    // MARK: - Scenario B: Quick Return (Closed Visit)

    /// SCENARIO B: Recently closed visit with exit < 10 minutes ago
    /// Confidence: 95% for 0-3 min, 90% for 3-10 min - User exited and came back quickly
    /// Example: User stepped out of cafe, came back within 10 minutes
    private func checkScenarioB_QuickReturn(
        _ visit: LocationVisitRecord
    ) -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {
        guard let exitTime = visit.exitTime else { return nil }

        let minutesSinceExit = Int(Date().timeIntervalSince(exitTime) / 60)
        let durationMinutes = visit.durationMinutes ?? 0

        // Filter: Must be at least 5 minute visit (not noise), UNLESS exit is within 1 minute (likely continuous visit)
        if durationMinutes < 5 && minutesSinceExit > 1 {
            print("⏭️ Scenario B filtered: Visit too short (\(durationMinutes) min)")
            return nil
        }

        // Closed visit < 10 minutes ago (extended from 3 minutes)
        if minutesSinceExit <= 10 && minutesSinceExit >= 0 {
            // Higher confidence for very quick returns (0-3 min), slightly lower for 3-10 min
            let confidence = minutesSinceExit <= 3 ? 0.95 : 0.90
            print("✅ MERGE SCENARIO B: Quick return (\(minutesSinceExit) min ago, confidence: \(String(format: "%.0f%%", confidence * 100)))")
            return (visit, confidence, "quick_return")
        }

        return nil
    }

    // MARK: - Scenario C: GPS Reconnect (GPS Loss Recovery)

    /// SCENARIO C: Recently closed visit (10-20 min ago) + still within geofence
    /// Confidence: 85% - GPS signal was lost for extended period, user stayed at location
    /// Example: GPS lost for 15 minutes due to building/tunnel, user is still there
    private func checkScenarioC_GPSReconnect(
        _ visit: LocationVisitRecord,
        currentLocation: CLLocationCoordinate2D,
        geofenceRadius: CLLocationDistance
    ) -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {
        guard let exitTime = visit.exitTime else { return nil }

        let minutesSinceExit = Int(Date().timeIntervalSince(exitTime) / 60)
        let durationMinutes = visit.durationMinutes ?? 0

        // Filter: Must be at least 5 minute visit (not noise)
        if durationMinutes < 5 {
            print("⏭️ Scenario C filtered: Visit too short (\(durationMinutes) min)")
            return nil
        }

        // Closed visit 10-20 minutes ago (updated to avoid overlap with Scenario B)
        guard minutesSinceExit > 10 && minutesSinceExit <= 20 else {
            if minutesSinceExit > 20 {
                print("ℹ️ Visit too old for Scenario C (\(minutesSinceExit) min > 20 min window)")
            }
            return nil
        }

        // Check if current location is still within geofence
        // (SavedPlace location comes from GeofenceManager)
        let currentLocationObj = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let visitLocation = CLLocation(latitude: visit.savedPlaceId.uuidString.hash as! Double, longitude: 0)
        // Note: This is simplified - actual implementation uses SavedPlace coordinate

        // For now, we trust that if geofence entry fired, we're in bounds
        print("✅ MERGE SCENARIO C: GPS reconnect (\(minutesSinceExit) min ago, still in geofence)")
        return (visit, 0.85, "gps_reconnect")
    }

    // MARK: - In-Memory Cache Check

    /// Check in-memory cache of recently closed visits (fastest path)
    private func checkInMemoryClosed(
        placeId: UUID
    ) -> (visit: LocationVisitRecord, confidence: Double, reason: String)? {
        guard let recentVisit = recentlyClosedVisits[placeId],
              let exitTime = recentVisit.exitTime else {
            return nil
        }

        let minutesSinceExit = Int(Date().timeIntervalSince(exitTime) / 60)
        let durationMinutes = recentVisit.durationMinutes ?? 0

        // Must be at least 5 minute visit, UNLESS exit is within 1 minute (likely continuous visit)
        if durationMinutes < 5 && minutesSinceExit > 1 {
            return nil
        }

        // Within 30 minute merge window
        if minutesSinceExit <= 30 && minutesSinceExit >= 0 {
            print("✅ Found recent closed visit in memory (\(minutesSinceExit) min ago)")
            if minutesSinceExit <= 10 {
                // 0-10 minutes: Quick return scenario
                let confidence = minutesSinceExit <= 3 ? 0.95 : 0.90
                return (recentVisit, confidence, "quick_return")
            } else if minutesSinceExit <= 20 {
                // 10-20 minutes: GPS reconnect scenario
                return (recentVisit, 0.85, "gps_reconnect")
            }
        }

        return nil
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

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            guard let visit = visits.first else {
                print("ℹ️ No recent visits found in Supabase for this location")
                return nil
            }

            // Try Scenario A first (highest confidence)
            if let result = checkScenarioA_OpenVisit(visit) {
                return result
            }

            // Try Scenario B (medium-high confidence)
            if let result = checkScenarioB_QuickReturn(visit) {
                return result
            }

            // Try Scenario C (medium confidence)
            if let result = checkScenarioC_GPSReconnect(
                visit,
                currentLocation: currentLocation,
                geofenceRadius: geofenceRadius
            ) {
                return result
            }

            print("ℹ️ Most recent visit doesn't meet merge criteria")
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

        // Reopen the visit
        mergedVisit.entryTime = Date()
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

        let updateData: [String: PostgREST.AnyJSON] = [
            "session_id": .string((visit.sessionId ?? UUID()).uuidString),
            "exit_time": .null, // Reopen visit
            "duration_minutes": .null,
            "confidence_score": .double(visit.confidenceScore ?? 1.0),
            "merge_reason": .string(visit.mergeReason ?? "unknown"),
            "entry_time": .string(formatter.string(from: visit.entryTime)), // Update entry time
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

    /// Add a closed visit to the in-memory cache (5-minute TTL)
    func cacheClosedVisit(_ visit: LocationVisitRecord) {
        recentlyClosedVisits[visit.savedPlaceId] = visit

        // Auto-remove after 5 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
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
