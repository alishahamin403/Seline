import Foundation
import CoreLocation
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
        print("\n🚀 ===== APP LAUNCH RECOVERY =====")

        // FIXED: Smart recovery - restore visits if user still at location, close if not
        await smartRecoverIncompleteVisits(userId: userId, geofenceManager: geofenceManager)

        // 1. Recover sessions from Supabase
        await sessionManager.recoverSessionsOnAppLaunch(for: userId)

        // 2. Clean up stale sessions
        await sessionManager.cleanupStaleSessions(olderThanHours: 4)

        print("🚀 ===== RECOVERY COMPLETE =====\n")
    }

    /// SMART RECOVERY: Restore visits if user still at location, close if not
    /// This fixes the issue where visits disappear on force close
    private func smartRecoverIncompleteVisits(userId: UUID, geofenceManager: GeofenceManager) async {
        print("🔍 Smart recovery: Checking incomplete visits...")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch all incomplete visits
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
                print("✅ No incomplete visits found")
                return
            }

            print("📋 Found \(incompleteVisits.count) incomplete visit(s)")

            // Get current location
            guard let currentLocation = SharedLocationManager.shared.currentLocation else {
                print("⚠️ No current location - will close all incomplete visits")
                // If we can't get location, close all old visits to be safe
                for visit in incompleteVisits {
                    await closeVisitInSupabase(visit)
                }
                return
            }

            let savedPlaces = LocationsManager.shared.savedPlaces
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let now = Date()

            var restoredCount = 0
            var closedCount = 0

            for visit in incompleteVisits {
                // Check if visit location exists
                guard let place = savedPlaces.first(where: { $0.id == visit.savedPlaceId }) else {
                    print("⚠️ Location not found for visit: \(visit.id.uuidString) - closing")
                    await closeVisitInSupabase(visit)
                    closedCount += 1
                    continue
                }

                let timeSinceEntry = now.timeIntervalSince(visit.entryTime)
                let hoursSinceEntry = timeSinceEntry / 3600

                // Calculate distance to location
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLocation.distance(from: placeLocation)
                let radius = GeofenceRadiusManager.shared.getRadius(for: place)

                print("\n📍 Visit: \(place.displayName)")
                print("   Open for: \(String(format: "%.1f", hoursSinceEntry))h")
                print("   Distance: \(String(format: "%.0f", distance))m, Radius: \(String(format: "%.0f", radius))m")

                // Decision logic:
                if distance <= radius {
                    // User is STILL at location - restore visit
                    print("   ✅ RESTORING: User still at location")
                    geofenceManager.activeVisits[visit.savedPlaceId] = visit
                    restoredCount += 1
                } else if hoursSinceEntry >= 12 {
                    // Visit is very old - definitely close it
                    print("   🗑️ CLOSING: Visit too old (>12h)")
                    await closeVisitInSupabase(visit)
                    closedCount += 1
                } else if distance > radius * 2 {
                    // User is far away - close visit
                    print("   🗑️ CLOSING: User far from location (\(String(format: "%.0f", distance))m > \(String(format: "%.0f", radius * 2))m)")
                    await closeVisitInSupabase(visit)
                    closedCount += 1
                } else {
                    // User nearby but not inside - close visit (probably left)
                    print("   🗑️ CLOSING: User left location")
                    await closeVisitInSupabase(visit)
                    closedCount += 1
                }
            }

            print("\n📊 Recovery Summary:")
            print("   ✅ Restored: \(restoredCount)")
            print("   🗑️ Closed: \(closedCount)")

            // CRITICAL: Start validation timer if we restored any visits
            if restoredCount > 0 {
                print("🔄 Starting validation timer for restored visit(s)")
                if !LocationBackgroundValidationService.shared.isValidationRunning() {
                    LocationBackgroundValidationService.shared.startValidationTimer(
                        geofenceManager: geofenceManager,
                        locationManager: SharedLocationManager.shared,
                        savedPlaces: savedPlaces
                    )
                }
            }
        } catch {
            print("❌ Error in smart recovery: \(error)")
        }
    }

    /// Helper method to close a visit in Supabase
    /// Uses CLVisit departure data if available for accurate exit times
    private func closeVisitInSupabase(_ visit: LocationVisitRecord) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Get the saved place to check for CLVisit departure time
        let savedPlaces = LocationsManager.shared.savedPlaces
        guard let place = savedPlaces.first(where: { $0.id == visit.savedPlaceId }) else {
            print("⚠️ Cannot find saved place for visit - using current time")
            return
        }

        let placeCoordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let radius = GeofenceRadiusManager.shared.getRadius(for: place)

        // Try to get cached CLVisit departure time (search within 2x radius for safety)
        let exitTime: Date
        if let cachedDeparture = SharedLocationManager.shared.getCachedDepartureTime(near: placeCoordinate, within: radius * 2) {
            // Use CLVisit departure time (accurate!)
            exitTime = cachedDeparture
            print("✅ Using CLVisit departure time: \(cachedDeparture)")
        } else {
            // Fallback to current time (less accurate)
            exitTime = Date()
            print("⚠️ No CLVisit data - using app reopen time (may be inaccurate)")
        }

        let timeSinceEntry = exitTime.timeIntervalSince(visit.entryTime)
        let durationMinutes = Int(timeSinceEntry / 60)

        let updateData: [String: PostgREST.AnyJSON] = [
            "exit_time": .string(formatter.string(from: exitTime)),
            "duration_minutes": .double(Double(durationMinutes)),
            "updated_at": .string(formatter.string(from: Date()))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ Visit closed with exit time: \(exitTime)")
        } catch {
            print("❌ Failed to close visit \(visit.id.uuidString): \(error)")
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
    // DEPRECATED: Replaced by smartRecoverIncompleteVisits() which checks if user is still at location

    // MARK: - Stale Visit Auto-Close

    /// Public method to auto-close a specific unresolved visit (used by SOLUTION 2)
    func autoCloseUnresolvedVisit(_ visit: LocationVisitRecord) async {
        var closedVisit = visit
        closedVisit.recordExit(exitTime: Date())

        let visitsToSave = closedVisit.splitAtMidnightIfNeeded()
        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
            // Delete the original visit before saving split visits
            await deleteVisitFromSupabase(visit)
            for part in visitsToSave {
                await saveVisitToSupabase(part)
            }
        } else {
            await updateVisitInSupabase(closedVisit)
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
                let originalVisit = staleVisits[i]
                staleVisits[i].recordExit(exitTime: Date())

                // Split at midnight if needed
                let visitsToSave = staleVisits[i].splitAtMidnightIfNeeded()

                if visitsToSave.count > 1 {
                    print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
                    // Delete the original visit before saving split visits
                    await deleteVisitFromSupabase(originalVisit)
                    for part in visitsToSave {
                        await saveVisitToSupabase(part)
                    }
                } else {
                    await updateVisitInSupabase(staleVisits[i])
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
        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
            // Delete the original visit before saving split visits
            await deleteVisitFromSupabase(visit)
            for part in visitsToSave {
                await saveVisitToSupabase(part)
            }
        } else {
            await updateVisitInSupabase(closedVisit)
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

        // CRITICAL: Check if visit spans midnight and needs to be split
        let spansMidnight = visit.spansMidnight()
        print("🕐 Checking midnight span (ErrorRecovery update): Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")

        let visitsToSave = visit.splitAtMidnightIfNeeded()

        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT in ErrorRecovery updateVisit: Splitting into \(visitsToSave.count) records")
            // Delete the original visit and save the split parts
            await deleteVisitFromSupabase(visit)
            for part in visitsToSave {
                await saveVisitToSupabase(part)
            }
            return
        }

        // No split needed - proceed with normal update
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

    private func deleteVisitFromSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user")
            return
        }

        do {
            print("🗑️ Deleting visit from Supabase before split - ID: \(visit.id.uuidString)")

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .delete()
                .eq("id", value: visit.id.uuidString)
                .execute()

            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error deleting visit: \(error)")
        }
    }

    private func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user")
            return
        }

        // CRITICAL: Check if visit spans midnight BEFORE saving
        if let exitTime = visit.exitTime, visit.spansMidnight() {
            print("🌙 MIDNIGHT SPLIT in ErrorRecovery saveVisitToSupabase: Visit spans midnight, splitting before save")
            let visitsToSave = visit.splitAtMidnightIfNeeded()
            
            if visitsToSave.count > 1 {
                for (index, splitVisit) in visitsToSave.enumerated() {
                    print("  - Saving split visit \(index + 1): \(splitVisit.entryTime) to \(splitVisit.exitTime?.description ?? "nil")")
                    await saveVisitToSupabaseDirectly(splitVisit)
                }
                return
            }
        }

        // No split needed - save directly
        await saveVisitToSupabaseDirectly(visit)
    }
    
    /// Internal method that actually saves to Supabase (without midnight check)
    private func saveVisitToSupabaseDirectly(_ visit: LocationVisitRecord) async {
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let visitData: [String: PostgREST.AnyJSON] = [
            "id": .string(visit.id.uuidString),
            "user_id": .string(user.id.uuidString),
            "saved_place_id": .string(visit.savedPlaceId.uuidString),
            "entry_time": .string(formatter.string(from: visit.entryTime)),
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "day_of_week": .string(visit.dayOfWeek),
            "time_of_day": .string(visit.timeOfDay),
            "month": .double(Double(visit.month)),
            "year": .double(Double(visit.year)),
            "session_id": visit.sessionId != nil ? .string(visit.sessionId!.uuidString) : .null,
            "confidence_score": visit.confidenceScore != nil ? .double(visit.confidenceScore!) : .null,
            "merge_reason": visit.mergeReason != nil ? .string(visit.mergeReason!) : .null,
            "signal_drops": visit.signalDrops != nil ? .double(Double(visit.signalDrops!)) : .null,
            "motion_validated": visit.motionValidated != nil ? .bool(visit.motionValidated!) : .null,
            "stationary_percentage": visit.stationaryPercentage != nil ? .double(visit.stationaryPercentage!) : .null,
            "wifi_matched": visit.wifiMatched != nil ? .bool(visit.wifiMatched!) : .null,
            "is_outlier": visit.isOutlier != nil ? .bool(visit.isOutlier!) : .null,
            "is_commute_stop": visit.isCommuteStop != nil ? .bool(visit.isCommuteStop!) : .null,
            "semantic_valid": visit.semanticValid != nil ? .bool(visit.semanticValid!) : .null,
            "created_at": .string(formatter.string(from: visit.createdAt)),
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .insert(visitData)
                .execute()

            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error saving visit: \(error)")
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
