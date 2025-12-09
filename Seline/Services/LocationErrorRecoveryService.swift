import Foundation
import PostgREST

// MARK: - Custom Date Decoder for Flexible Date Formats
extension JSONDecoder {
    static func supabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds and timezone
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds but with timezone
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601-style format without timezone (e.g., "2025-12-04T03:10:14.802")
            let isoNoTimezoneFormatter = DateFormatter()
            isoNoTimezoneFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            isoNoTimezoneFormatter.timeZone = TimeZone(abbreviation: "UTC")
            if let date = isoNoTimezoneFormatter.date(from: dateString) {
                return date
            }

            // Try ISO8601-style format without fractional seconds and without timezone
            isoNoTimezoneFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = isoNoTimezoneFormatter.date(from: dateString) {
                return date
            }

            // Try PostgreSQL timestamp format (YYYY-MM-DD HH:MM:SS.ffffff)
            let postgresFormatter = DateFormatter()
            postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            postgresFormatter.timeZone = TimeZone(abbreviation: "UTC")
            if let date = postgresFormatter.date(from: dateString) {
                return date
            }

            // Try PostgreSQL format without microseconds
            postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = postgresFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
        }
        return decoder
    }
}

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
        // DEBUG: Commented out to reduce console spam
        // print("\n🚀 ===== APP LAUNCH RECOVERY =====")

        // 0. CRITICAL: First close ALL stuck visits in Supabase to ensure clean slate
        // This fixes the issue where visits never left active state
        await closeAllStuckVisitsInSupabase(userId: userId)

        // 1. Recover sessions from Supabase
        await sessionManager.recoverSessionsOnAppLaunch(for: userId)

        // 2. Restore incomplete visits to activeVisits (only recent ones)
        await restoreIncompleteVisits(geofenceManager: geofenceManager)

        // 3. Clean up stale sessions
        await sessionManager.cleanupStaleSessions(olderThanHours: 4)

        // DEBUG: Commented out to reduce console spam
        // print("🚀 ===== RECOVERY COMPLETE =====\n")
    }

    /// CRITICAL FIX: Close all stuck visits that have been open for too long
    /// This runs on every app launch to clean up any visits that got stuck
    private func closeAllStuckVisitsInSupabase(userId: UUID) async {
        // DEBUG: Commented out to reduce console spam
        // print("🧹 Checking for stuck visits to close...")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch all visits and filter for incomplete ones (exit_time IS NULL) in Swift
            // This approach is more reliable than PostgREST NULL filtering
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for incomplete visits (exit_time = nil)
            let incompleteVisits = allVisits.filter { $0.exitTime == nil }

            if incompleteVisits.isEmpty {
                print("✅ No stuck visits found")
                return
            }

            print("⚠️ Found \(incompleteVisits.count) incomplete visit(s) - CLOSING ALL OF THEM")

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let now = Date()
            var closedCount = 0

            // AGGRESSIVE FIX: Close ALL incomplete visits on app launch
            // New visits will be created when geofence entry is detected
            for visit in incompleteVisits {
                let timeSinceEntry = now.timeIntervalSince(visit.entryTime)
                let hoursSinceEntry = timeSinceEntry / 3600
                let durationMinutes = Int(timeSinceEntry / 60)

                print("🧹 Closing visit: \(visit.id.uuidString) (was open \(String(format: "%.1f", hoursSinceEntry))h)")

                let updateData: [String: PostgREST.AnyJSON] = [
                    "exit_time": .string(formatter.string(from: now)),
                    "duration_minutes": .double(Double(durationMinutes)),
                    "updated_at": .string(formatter.string(from: now))
                ]

                do {
                    try await client
                        .from("location_visits")
                        .update(updateData)
                        .eq("id", value: visit.id.uuidString)
                        .execute()

                    closedCount += 1
                    print("✅ Successfully closed visit: \(visit.id.uuidString)")
                } catch {
                    print("❌ Failed to close visit \(visit.id.uuidString): \(error)")
                }
            }

            print("🧹 Closed \(closedCount)/\(incompleteVisits.count) stuck visit(s)")
        } catch {
            print("❌ Error closing stuck visits: \(error)")
        }
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
                .order("entry_time", ascending: false)
                .limit(20)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for incomplete visits (exit_time = nil) and get the most recent one
            guard let mostRecentVisit = allVisits.first(where: { $0.exitTime == nil }) else {
                return nil
            }

            // FIXED: Return ANY unresolved visit so it can be auto-closed
            // The previous logic skipped visits older than 4 hours, leaving them stuck forever
            // Now we return all unresolved visits regardless of age - they will be auto-closed
            // when a new geofence entry is detected
            let hoursSinceEntry = Date().timeIntervalSince(mostRecentVisit.entryTime) / 3600
            print("📋 Found unresolved visit: \(mostRecentVisit.id.uuidString), started \(String(format: "%.1f", hoursSinceEntry))h ago")

            return mostRecentVisit
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
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let fetchedVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for incomplete visits (exit_time = nil)
            let allVisits = fetchedVisits.filter { $0.exitTime == nil }

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

            let decoder = JSONDecoder.supabaseDecoder()
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

            let decoder = JSONDecoder.supabaseDecoder()
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
