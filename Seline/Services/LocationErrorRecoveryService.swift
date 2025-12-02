import Foundation
import PostgREST

// MARK: - LocationErrorRecoveryService
//
// Handles app launch recovery, stale visit cleanup, and atomic merge operations
// Ensures data integrity and prevents race conditions

@MainActor
class LocationErrorRecoveryService {
    static let shared = LocationErrorRecoveryService()

    private init() {}

    // MARK: - App Launch Recovery

    /// Called on app launch to recover incomplete sessions
    func recoverOnAppLaunch(
        userId: UUID,
        geofenceManager: GeofenceManager,
        sessionManager: LocationSessionManager
    ) async {
        print("\n🚀 ===== APP LAUNCH RECOVERY =====")

        // 1. Recover sessions from Supabase
        await sessionManager.recoverSessionsOnAppLaunch(for: userId)

        // 2. Restore incomplete visits to activeVisits
        await restoreIncompleteVisits(geofenceManager: geofenceManager)

        // 3. Clean up stale sessions
        await sessionManager.cleanupStaleSessions(olderThanHours: 4)

        print("🚀 ===== RECOVERY COMPLETE =====\n")
    }

    // MARK: - Unresolved Visit Check (SOLUTION 2)

    /// Check if there are any unresolved visits globally
    /// SOLUTION 2: Prevents new visits from starting if an old incomplete visit exists
    func hasUnresolvedVisits(geofenceManager: GeofenceManager) async -> LocationVisitRecord? {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return nil
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .filter("exit_time", operator: "is", value: "null")
                .order("entry_time", ascending: false)
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            guard let mostRecentVisit = visits.first else {
                return nil
            }

            let hoursSinceEntry = Date().timeIntervalSince(mostRecentVisit.entryTime) / 3600

            // Return unresolved visit if it's been open more than a threshold (e.g., 10 seconds)
            // This catches cases where:
            // - App crash just created a visit
            // - GPS loss left a visit hanging
            // - User entered location but geofence exit didn't fire
            if hoursSinceEntry < 4 {  // Less than 4 hours is considered active
                return mostRecentVisit
            }

            return nil
        } catch {
            print("❌ Error checking for unresolved visits: \(error)")
            return nil
        }
    }

    // MARK: - Incomplete Visit Recovery

    /// Restore incomplete visits from Supabase to activeVisits
    /// SOLUTION 1: Only restore the most recent visit and auto-close all others
    private func restoreIncompleteVisits(geofenceManager: GeofenceManager) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .filter("exit_time", operator: "is", value: "null")
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            if allVisits.isEmpty {
                print("✅ No incomplete visits to restore")
                return
            }

            print("📋 Found \(allVisits.count) incomplete visit(s)")

            var hasRestoredOneVisit = false

            for visit in allVisits {
                // Deduplicate: Don't process if already in activeVisits
                if geofenceManager.activeVisits[visit.savedPlaceId] != nil {
                    print("ℹ️ Visit already in activeVisits: \(visit.savedPlaceId.uuidString)")
                    continue
                }

                let hoursSinceEntry = Date().timeIntervalSince(visit.entryTime) / 3600

                // SOLUTION 1: Auto-close all visits except the single most recent one
                if hasRestoredOneVisit {
                    // Auto-close all older visits
                    print("🔴 SOLUTION 1 - Auto-closing older incomplete visit: \(visit.id.uuidString) (started \(String(format: "%.1f", hoursSinceEntry))h ago)")
                    await autoCloseVisit(visit)
                } else if hoursSinceEntry > 24 {
                    // Auto-close very old visits (>24h)
                    print("⚠️ Visit open >24h, auto-closing: \(visit.id.uuidString)")
                    await autoCloseVisit(visit)
                } else if hoursSinceEntry > 4 {
                    // Log long visits but restore the most recent one
                    print("⚠️ Visit open \(String(format: "%.1f", hoursSinceEntry))h: \(visit.id.uuidString) - RESTORING as most recent")
                    geofenceManager.activeVisits[visit.savedPlaceId] = visit
                    hasRestoredOneVisit = true
                } else {
                    // Restore only the single most recent short-duration visit
                    print("✅ Restored visit (most recent): \(visit.savedPlaceId.uuidString)")
                    geofenceManager.activeVisits[visit.savedPlaceId] = visit
                    hasRestoredOneVisit = true
                }
            }
        } catch {
            print("❌ Error restoring incomplete visits: \(error)")
        }
    }

    // MARK: - Stale Visit Auto-Close

    /// Public method to auto-close a specific unresolved visit (used by SOLUTION 2)
    func autoCloseUnresolvedVisit(_ visit: LocationVisitRecord) async {
        var closedVisit = visit
        closedVisit.recordExit(exitTime: Date())

        let visitsToSave = closedVisit.splitAtMidnightIfNeeded()
        for part in visitsToSave {
            await updateVisitInSupabase(part)
        }

        print("🔴 SOLUTION 2 - Auto-closed unresolved visit: \(visit.id.uuidString)")
    }

    /// Auto-close visits that have been open too long
    func autoCloseStaleVisits(
        olderThanHours: Int = 4,
        geofenceManager: GeofenceManager
    ) async {
        print("\n🧹 ===== AUTO-CLOSING STALE VISITS =====")

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID")
            return
        }

        let thresholdTime = Date(timeIntervalSinceNow: -Double(olderThanHours) * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .lt("entry_time", value: formatter.string(from: thresholdTime))
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var staleVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            print("Found \(staleVisits.count) stale visit(s)")

            for i in 0..<staleVisits.count {
                staleVisits[i].recordExit(exitTime: Date())

                // Split at midnight if needed
                let visitsToSave = staleVisits[i].splitAtMidnightIfNeeded()

                for part in visitsToSave {
                    await updateVisitInSupabase(part)
                }

                // Remove from active visits
                geofenceManager.activeVisits.removeValue(forKey: staleVisits[i].savedPlaceId)

                print("🧹 Closed stale visit: \(staleVisits[i].id.uuidString)")
            }

            print("🧹 ===== AUTO-CLOSE COMPLETE =====\n")
        } catch {
            print("❌ Error auto-closing stale visits: \(error)")
        }
    }

    // MARK: - Atomic Merge Operations

    /// Execute an atomic visit merge (all-or-nothing operation)
    /// This prevents race conditions where merge succeeds in Supabase but fails in memory
    func executeAtomicMerge(
        _ visit: LocationVisitRecord,
        sessionId: UUID,
        confidence: Double,
        reason: String,
        geofenceManager: GeofenceManager,
        sessionManager: LocationSessionManager
    ) async -> Bool {

        // Step 1: Save merge data to Supabase first
        var mergedVisit = visit
        mergedVisit.sessionId = sessionId
        mergedVisit.confidenceScore = confidence
        mergedVisit.mergeReason = reason
        mergedVisit.entryTime = Date()
        mergedVisit.exitTime = nil
        mergedVisit.durationMinutes = nil

        // Attempt Supabase update
        guard await updateMergedVisitInSupabase(mergedVisit) else {
            print("❌ Atomic merge failed: Supabase update unsuccessful")
            return false
        }

        // Step 2: Update in-memory state
        geofenceManager.activeVisits[visit.savedPlaceId] = mergedVisit
        sessionManager.addVisitToSession(sessionId, visitRecord: mergedVisit)

        print("✅ Atomic merge complete: \(visit.id.uuidString)")
        print("   Session: \(sessionId.uuidString)")
        print("   Confidence: \(String(format: "%.0f%%", confidence * 100))")
        print("   Reason: \(reason)")

        return true
    }

    // MARK: - Supabase Sync

    private func autoCloseVisit(_ visit: LocationVisitRecord) async {
        var closedVisit = visit
        closedVisit.recordExit(exitTime: Date())

        let visitsToSave = closedVisit.splitAtMidnightIfNeeded()
        for part in visitsToSave {
            await updateVisitInSupabase(part)
        }
    }

    private func updateMergedVisitInSupabase(_ visit: LocationVisitRecord) async -> Bool {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user")
            return false
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let updateData: [String: PostgREST.AnyJSON] = [
            "session_id": .string((visit.sessionId ?? UUID()).uuidString),
            "exit_time": .null,
            "duration_minutes": .null,
            "confidence_score": .double(visit.confidenceScore ?? 1.0),
            "merge_reason": .string(visit.mergeReason ?? "unknown"),
            "entry_time": .string(formatter.string(from: visit.entryTime)),
            "updated_at": .string(formatter.string(from: Date()))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            return true
        } catch {
            print("❌ Error updating merged visit: \(error)")
            return false
        }
    }

    private func updateVisitInSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let updateData: [String: PostgREST.AnyJSON] = [
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "updated_at": .string(formatter.string(from: Date()))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error updating visit: \(error)")
        }
    }

    // MARK: - Data Integrity Checks

    /// Verify session integrity in Supabase
    func verifySessionIntegrity(for userId: UUID) async -> Int {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Query to find orphaned visits (session_id is null)
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for orphaned visits (session_id is nil)
            let orphaned = allVisits.filter { $0.sessionId == nil }

            if !orphaned.isEmpty {
                print("⚠️ Found \(orphaned.count) orphaned visits (session_id = null)")
                print("   These should not exist - indicates migration issue")
            }

            return orphaned.count
        } catch {
            print("❌ Error verifying session integrity: \(error)")
            return -1
        }
    }
}
