import Foundation

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

    // MARK: - Incomplete Visit Recovery

    /// Restore incomplete visits from Supabase to activeVisits
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
                .is("exit_time", value: "null")
                .order("entry_time", ascending: false)
                .limit(10)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            if visits.isEmpty {
                print("✅ No incomplete visits to restore")
                return
            }

            print("📋 Found \(visits.count) incomplete visit(s)")

            for visit in visits {
                // Deduplicate: Don't restore if already in activeVisits
                if geofenceManager.activeVisits[visit.savedPlaceId] != nil {
                    print("ℹ️ Visit already in activeVisits: \(visit.savedPlaceId.uuidString)")
                    continue
                }

                let hoursSinceEntry = Date().timeIntervalSince(visit.entryTime) / 3600

                if hoursSinceEntry > 24 {
                    // Auto-close very old visits
                    print("⚠️ Visit open >24h, auto-closing: \(visit.id.uuidString)")
                    await autoCloseVisit(visit)
                } else if hoursSinceEntry > 4 {
                    // Log long visits but restore them
                    print("⚠️ Visit open \(String(format: "%.1f", hoursSinceEntry))h: \(visit.id.uuidString)")
                    geofenceManager.activeVisits[visit.savedPlaceId] = visit
                } else {
                    // Restore short-duration visits silently
                    print("✅ Restored visit: \(visit.savedPlaceId.uuidString)")
                    geofenceManager.activeVisits[visit.savedPlaceId] = visit
                }
            }
        } catch {
            print("❌ Error restoring incomplete visits: \(error)")
        }
    }

    // MARK: - Stale Visit Auto-Close

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
                .is("exit_time", value: "null")
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
                .is("session_id", value: "null")
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let orphaned: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

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
