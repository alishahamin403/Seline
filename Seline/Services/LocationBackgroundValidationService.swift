import Foundation
import CoreLocation
import PostgREST

// MARK: - LocationBackgroundValidationService
//
// Periodically validates that user is still at location for active visits
// Runs 30-second timer only when active visits exist (battery-efficient)

@MainActor
class LocationBackgroundValidationService {
    static let shared = LocationBackgroundValidationService()

    private var validationTimer: Timer?
    private let validationInterval: TimeInterval = 30 // Check every 30 seconds
    private var isRunning = false

    private weak var geofenceManager: GeofenceManager?
    private weak var locationManager: SharedLocationManager?

    private init() {}

    // MARK: - Timer Management

    /// Start validation timer (only if not already running)
    func startValidationTimer(
        geofenceManager: GeofenceManager,
        locationManager: SharedLocationManager,
        savedPlaces: [SavedPlace]
    ) {
        guard !isRunning else {
            print("⚠️ Validation timer already running")
            return
        }

        // DEBUG: Commented out to reduce console spam
        // print("⏱️  Starting background validation timer (30 sec interval)")
        self.geofenceManager = geofenceManager
        self.locationManager = locationManager

        isRunning = true
        validationTimer = Timer.scheduledTimer(
            withTimeInterval: validationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.validateActiveVisits(with: savedPlaces)
            }
        }
    }

    /// Stop validation timer
    func stopValidationTimer() {
        guard isRunning else { return }

        validationTimer?.invalidate()
        validationTimer = nil
        isRunning = false

        print("⏹️  Stopped background validation timer")
    }

    /// Check if timer is running
    func isValidationRunning() -> Bool {
        return isRunning
    }

    // MARK: - Validation Logic

    /// Validate all active visits - check if user is still at location AND check for midnight crossings
    private func validateActiveVisits(with savedPlaces: [SavedPlace]) async {
        guard let geofenceManager = geofenceManager,
              let locationManager = locationManager else {
            print("⚠️ Manager references lost")
            return
        }

        let activeVisits = geofenceManager.activeVisits
        guard !activeVisits.isEmpty else {
            // No active visits - stop timer
            print("✅ All visits closed, stopping validation timer")
            stopValidationTimer()
            return
        }

        // Get current location
        guard let currentLocation = locationManager.currentLocation else {
            print("⚠️ No current location available")
            return
        }

        // DYNAMIC GEOFENCING: Update which 20 locations are monitored if user moved far
        // This ensures we always monitor the 20 closest locations even with 100+ saved
        geofenceManager.updateGeofencesIfNeeded(currentLocation: currentLocation, savedPlaces: savedPlaces)

        // PERFORMANCE FIX: Proactive high-accuracy mode when approaching saved locations
        // Check if user is within 500m of any saved location (outside geofence but approaching)
        checkProximityToLocations(currentLocation: currentLocation, savedPlaces: savedPlaces)

        // DEBUG: Commented out to reduce console spam
        // print("🔍 Validating \(activeVisits.count) active visit(s)...")

        for (placeId, visit) in activeVisits {
            // CRITICAL: Check if midnight has been crossed for this active visit
            // If yes, force-close current visit and start new one for next day
            let calendar = Calendar.current
            let entryDay = calendar.dateComponents([.year, .month, .day], from: visit.entryTime)
            let currentDay = calendar.dateComponents([.year, .month, .day], from: Date())

            if entryDay != currentDay {
                print("🌙 MIDNIGHT CROSSED for active visit at \(savedPlaces.first(where: { $0.id == placeId })?.displayName ?? "unknown")")
                print("   Entry: \(visit.entryTime), Current: \(Date())")

                // Force-close the visit at 11:59:59 PM of entry day and start new visit at 12:00:00 AM
                await handleMidnightCrossing(placeId, visit: visit, geofenceManager: geofenceManager)
                continue // Skip location check for this visit as it's been replaced
            }

            // Find the saved place
            guard let place = savedPlaces.first(where: { $0.id == placeId }) else {
                print("⚠️ Saved place not found for visit")
                continue
            }

            // Get geofence radius (smart auto-detect)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)

            // Calculate distance to location
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)

            // Check if user has left the geofence
            if distance > radius {
                print("⚠️ USER LEFT LOCATION: \(place.displayName)")
                print("   Distance: \(String(format: "%.0f", distance))m > Radius: \(String(format: "%.0f", radius))m")

                // Auto-close the visit
                await autoCloseVisit(placeId, geofenceManager: geofenceManager)
            } else {
                // DEBUG: Commented out to reduce console spam
                // print("✅ User still at \(place.displayName)")
                // print("   Distance: \(String(format: "%.0f", distance))m, within \(String(format: "%.0f", radius))m radius")
            }
        }
    }

    // MARK: - Midnight Crossing Logic

    /// Handle midnight crossing for an active visit
    /// Closes the old visit at 11:59:59 PM and creates a new visit at 12:00:00 AM
    private func handleMidnightCrossing(
        _ placeId: UUID,
        visit: LocationVisitRecord,
        geofenceManager: GeofenceManager
    ) async {
        let calendar = Calendar.current

        // Calculate 11:59:59 PM of entry day
        var midnightComponents = calendar.dateComponents([.year, .month, .day], from: visit.entryTime)
        midnightComponents.hour = 23
        midnightComponents.minute = 59
        midnightComponents.second = 59

        guard let endOfEntryDay = calendar.date(from: midnightComponents) else {
            print("❌ Failed to calculate end of entry day")
            return
        }

        // Close the old visit at 11:59:59 PM
        var oldVisit = visit
        oldVisit.recordExit(exitTime: endOfEntryDay)

        // Save the old visit
        let durationMinutes = oldVisit.durationMinutes ?? 0
        print("💾 Saving old visit (before midnight): \(durationMinutes) min")
        await updateVisitInSupabase(oldVisit)

        // Calculate 12:00:00 AM of current day
        let currentDay = Date()
        var newDayComponents = calendar.dateComponents([.year, .month, .day], from: currentDay)
        newDayComponents.hour = 0
        newDayComponents.minute = 0
        newDayComponents.second = 0

        guard let startOfNewDay = calendar.date(from: newDayComponents) else {
            print("❌ Failed to calculate start of new day")
            // Remove old visit from active visits (thread-safe)
            geofenceManager.removeActiveVisit(for: placeId)
            return
        }

        // Create new visit starting at 12:00:00 AM
        let newVisit = LocationVisitRecord.create(
            userId: visit.userId,
            savedPlaceId: visit.savedPlaceId,
            entryTime: startOfNewDay,
            sessionId: visit.sessionId,
            confidenceScore: visit.confidenceScore,
            mergeReason: "midnight_split"
        )

        print("🌅 Creating new visit (after midnight) starting at \(startOfNewDay)")

        // Update active visits with new visit (thread-safe)
        geofenceManager.updateActiveVisit(newVisit, for: placeId)

        // Save new visit to Supabase
        await saveVisitToSupabase(newVisit)

        // Invalidate cache for this location to reflect the midnight split
        LocationVisitAnalytics.shared.invalidateCache(for: placeId)
    }

    // MARK: - Auto-Close Logic

    /// Auto-close a visit when user has left the geofence
    private func autoCloseVisit(
        _ placeId: UUID,
        geofenceManager: GeofenceManager
    ) async {
        guard var visit = geofenceManager.getActiveVisit(for: placeId) else {
            print("⚠️ Visit not found for auto-close")
            return
        }

        // Record exit
        visit.recordExit(exitTime: Date())

        let durationMinutes = visit.durationMinutes ?? 0
        print("✅ AUTO-CLOSED visit: \(visit.id.uuidString), Duration: \(durationMinutes) min")

        // Remove from active visits (thread-safe)
        geofenceManager.removeActiveVisit(for: placeId)

        // Split at midnight if needed
        let spansMidnight = visit.spansMidnight()
        print("🕐 Checking midnight span (auto-close): Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")
        let visitsToSave = visit.splitAtMidnightIfNeeded()

        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT: Saving \(visitsToSave.count) records")
            // Delete the original visit before saving split visits
            await geofenceManager.deleteVisitFromSupabase(visit)
            for part in visitsToSave {
                await saveVisitToSupabase(part)
            }
        } else {
            await updateVisitInSupabase(visit)
        }
    }

    // MARK: - Supabase Sync

    private func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user, cannot save visit")
            return
        }

        // CRITICAL: Check if visit spans midnight BEFORE saving
        if let exitTime = visit.exitTime, visit.spansMidnight() {
            print("🌙 MIDNIGHT SPLIT in BGValidation saveVisitToSupabase: Visit spans midnight, splitting before save")
            let visitsToSave = visit.splitAtMidnightIfNeeded()
            
            if visitsToSave.count > 1 {
                let geofenceManager = await GeofenceManager.shared
                for (index, splitVisit) in visitsToSave.enumerated() {
                    print("  - Saving split visit \(index + 1): \(splitVisit.entryTime) to \(splitVisit.exitTime?.description ?? "nil")")
                    await geofenceManager.saveVisitToSupabase(splitVisit)
                }
                return
            }
        }

        // No split needed - save directly
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let visitData: [String: PostgREST.AnyJSON] = [
            "id": .string(visit.id.uuidString),
            "user_id": .string(visit.userId.uuidString),
            "saved_place_id": .string(visit.savedPlaceId.uuidString),
            "session_id": visit.sessionId != nil ? .string(visit.sessionId!.uuidString) : .null,
            "entry_time": .string(formatter.string(from: visit.entryTime)),
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "day_of_week": .string(visit.dayOfWeek),
            "time_of_day": .string(visit.timeOfDay),
            "month": .double(Double(visit.month)),
            "year": .double(Double(visit.year)),
            "confidence_score": visit.confidenceScore != nil ? .double(visit.confidenceScore!) : .null,
            "merge_reason": visit.mergeReason != nil ? .string(visit.mergeReason!) : .null,
            "created_at": .string(formatter.string(from: visit.createdAt)),
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .insert(visitData)
                .execute()

            print("💾 Visit saved to Supabase: \(visit.id.uuidString)")
        } catch {
            print("❌ Error saving visit: \(error)")
        }
    }

    private func updateVisitInSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user, cannot update visit")
            return
        }

        // CRITICAL: Check if visit spans midnight and needs to be split
        let spansMidnight = visit.spansMidnight()
        print("🕐 Checking midnight span (BGValidation update): Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")

        let visitsToSave = visit.splitAtMidnightIfNeeded()

        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT in BGValidation updateVisit: Splitting into \(visitsToSave.count) records")
            // Delete the original visit and save the split parts
            let geofenceManager = await GeofenceManager.shared
            await geofenceManager.deleteVisitFromSupabase(visit)
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

            print("✅ Visit updated in Supabase: \(visit.id.uuidString)")

            // Invalidate cache
            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error updating visit: \(error)")
        }
    }

    // MARK: - PERFORMANCE FIX: Proactive Location Polling

    private var isHighAccuracyEnabled = false
    private let approachingThreshold: CLLocationDistance = 600 // Within 600m of a saved location

    /// Check if user is approaching any saved location and enable high-accuracy mode
    private func checkProximityToLocations(currentLocation: CLLocation, savedPlaces: [SavedPlace]) {
        var isApproachingAnyLocation = false

        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let geofenceRadius = GeofenceRadiusManager.shared.getRadius(for: place)

            // Check if approaching but not yet inside geofence
            if distance > geofenceRadius && distance <= approachingThreshold {
                isApproachingAnyLocation = true
                print("🎯 Approaching \(place.displayName) (\(String(format: "%.0f", distance))m away)")
                break
            }
        }

        // Enable/disable high accuracy mode based on proximity
        if isApproachingAnyLocation && !isHighAccuracyEnabled {
            locationManager?.enableHighAccuracyMode()
            isHighAccuracyEnabled = true
        } else if !isApproachingAnyLocation && isHighAccuracyEnabled {
            locationManager?.disableHighAccuracyMode()
            isHighAccuracyEnabled = false
        }
    }
}
