import Foundation
import CoreLocation

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

        print("⏱️  Starting background validation timer (30 sec interval)")
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

    /// Validate all active visits - check if user is still at location
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

        print("🔍 Validating \(activeVisits.count) active visit(s)...")

        for (placeId, visit) in activeVisits {
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
                print("✅ User still at \(place.displayName)")
                print("   Distance: \(String(format: "%.0f", distance))m, within \(String(format: "%.0f", radius))m radius")
            }
        }
    }

    // MARK: - Auto-Close Logic

    /// Auto-close a visit when user has left the geofence
    private func autoCloseVisit(
        _ placeId: UUID,
        geofenceManager: GeofenceManager
    ) async {
        guard var visit = geofenceManager.activeVisits[placeId] else {
            print("⚠️ Visit not found for auto-close")
            return
        }

        // Record exit
        visit.recordExit(exitTime: Date())

        // Filter out very short visits
        let durationMinutes = visit.durationMinutes ?? 0
        if durationMinutes < 5 {
            print("⏭️ Visit too short (\(durationMinutes) min), discarding")
            geofenceManager.activeVisits.removeValue(forKey: placeId)
            return
        }

        // Remove from active visits
        geofenceManager.activeVisits.removeValue(forKey: placeId)

        // Split at midnight if needed
        let visitsToSave = visit.splitAtMidnightIfNeeded()

        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT: Saving \(visitsToSave.count) records")
            for part in visitsToSave {
                await saveVisitToSupabase(part)
            }
        } else {
            print("✅ AUTO-CLOSED visit: \(visit.id.uuidString), Duration: \(durationMinutes) min")
            await updateVisitInSupabase(visit)
        }
    }

    // MARK: - Supabase Sync

    private func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user, cannot save visit")
            return
        }

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
}
