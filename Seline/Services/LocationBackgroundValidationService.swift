import Foundation
import CoreLocation
import PostgREST
import WidgetKit

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
    
    // CRITICAL FIX: Continuous monitoring mode
    // When enabled, the timer keeps running even without active visits
    // to detect new location entries that iOS geofencing may have missed
    private var isContinuousMode = false
    private var savedPlacesRef: [SavedPlace] = []

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
        self.savedPlacesRef = savedPlaces

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
    
    /// CRITICAL FIX: Start continuous monitoring mode
    /// This keeps the timer running even without active visits to detect new entries
    /// Call this on app launch to ensure location changes are detected promptly
    func startContinuousMonitoring(
        geofenceManager: GeofenceManager,
        locationManager: SharedLocationManager,
        savedPlaces: [SavedPlace]
    ) {
        print("🔄 Starting CONTINUOUS location monitoring mode")
        
        self.geofenceManager = geofenceManager
        self.locationManager = locationManager
        self.savedPlacesRef = savedPlaces
        self.isContinuousMode = true
        
        guard !isRunning else {
            print("⚠️ Timer already running, enabled continuous mode")
            return
        }
        
        isRunning = true
        validationTimer = Timer.scheduledTimer(
            withTimeInterval: validationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.performContinuousValidation()
            }
        }
        
        print("✅ Continuous monitoring started (30 sec interval)")
    }

    /// Stop validation timer
    func stopValidationTimer() {
        // Don't stop if in continuous mode
        if isContinuousMode {
            print("⚠️ Cannot stop timer in continuous mode")
            return
        }
        
        guard isRunning else { return }

        validationTimer?.invalidate()
        validationTimer = nil
        isRunning = false

        print("⏹️  Stopped background validation timer")
    }
    
    /// Force stop timer even in continuous mode (for testing/debugging)
    func forceStopTimer() {
        validationTimer?.invalidate()
        validationTimer = nil
        isRunning = false
        isContinuousMode = false
        print("🛑 Force stopped validation timer")
    }
    
    /// Update saved places reference (call when places are added/removed)
    func updateSavedPlaces(_ places: [SavedPlace]) {
        self.savedPlacesRef = places
    }

    /// Check if timer is running
    func isValidationRunning() -> Bool {
        return isRunning
    }

    // MARK: - Continuous Validation (Entry + Exit Detection)
    
    /// Perform continuous validation - checks for both new entries AND validates active visits
    /// This runs every 30 seconds to catch location changes iOS geofencing might miss
    private func performContinuousValidation() async {
        guard let geofenceManager = geofenceManager,
              let locationManager = locationManager else {
            print("⚠️ Manager references lost in continuous validation")
            return
        }
        
        // Get current location
        guard let currentLocation = locationManager.currentLocation else {
            // DEBUG: Only log occasionally to reduce spam
            // print("⚠️ No current location available for continuous validation")
            return
        }
        
        let savedPlaces = savedPlacesRef.isEmpty ? LocationsManager.shared.savedPlaces : savedPlacesRef
        
        // Check each saved place
        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)
            
            let isInsideGeofence = distance <= radius
            let hasActiveVisit = geofenceManager.getActiveVisit(for: place.id) != nil
            
            if isInsideGeofence && !hasActiveVisit {
                // USER IS INSIDE BUT NO VISIT - iOS geofence entry was missed!
                print("\n🚨 ===== MISSED GEOFENCE ENTRY DETECTED =====")
                print("🚨 Location: \(place.displayName)")
                print("🚨 Distance: \(String(format: "%.0f", distance))m (within \(String(format: "%.0f", radius))m radius)")
                print("🚨 Creating visit now!")
                print("🚨 ==========================================\n")
                
                await createMissedVisit(for: place, currentLocation: currentLocation, geofenceManager: geofenceManager)
                
                // Only handle one entry at a time to avoid race conditions
                break
                
            } else if !isInsideGeofence && hasActiveVisit {
                // USER IS OUTSIDE BUT HAS VISIT - iOS geofence exit was missed!
                // Note: This is handled by validateActiveVisits, but we double-check here
                print("\n🚨 ===== MISSED GEOFENCE EXIT DETECTED =====")
                print("🚨 Location: \(place.displayName)")
                print("🚨 Distance: \(String(format: "%.0f", distance))m (outside \(String(format: "%.0f", radius))m radius)")
                print("🚨 Ending visit now!")
                print("🚨 ==========================================\n")
                
                await autoCloseVisit(place.id, geofenceManager: geofenceManager)
            }
        }
        
        // Also run standard validation for midnight checks
        await validateActiveVisits(with: savedPlaces)
    }
    
    /// Create a visit that was missed by iOS geofencing
    private func createMissedVisit(
        for place: SavedPlace,
        currentLocation: CLLocation,
        geofenceManager: GeofenceManager
    ) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID for visit tracking")
            return
        }
        
        // Double-check no existing visit (thread safety)
        if geofenceManager.getActiveVisit(for: place.id) != nil {
            print("ℹ️ Visit already exists, skipping")
            return
        }
        
        // Speed check - reject if user is moving too fast (passing by)
        let speed = currentLocation.speed
        let maxAllowedSpeed: Double = 5.5 // ~20 km/h
        
        if speed > 0 && speed > maxAllowedSpeed {
            print("⚠️ User moving too fast (\(String(format: "%.1f", speed * 3.6)) km/h) - skipping visit creation")
            return
        }
        
        // Accuracy check
        let accuracy = currentLocation.horizontalAccuracy
        if accuracy > 100 {
            print("⚠️ GPS accuracy too poor (\(String(format: "%.0f", accuracy))m) - skipping visit creation")
            return
        }
        
        // Create the visit
        let sessionId = UUID()
        let visit = LocationVisitRecord.create(
            userId: userId,
            savedPlaceId: place.id,
            entryTime: Date(),
            sessionId: sessionId,
            confidenceScore: 0.9, // Slightly lower confidence for missed detection
            mergeReason: "missed_geofence_entry"
        )
        
        // Add to active visits (thread-safe)
        geofenceManager.updateActiveVisit(visit, for: place.id)
        
        // Create session
        LocationSessionManager.shared.createSession(for: place.id, userId: userId)
        
        // CRITICAL: Use unified cache invalidation to keep all views in sync
        LocationVisitAnalytics.shared.invalidateAllVisitCaches()
        
        // Save to Supabase
        await geofenceManager.saveVisitToSupabase(visit)
        
        print("✅ Created missed visit for: \(place.displayName)")
        
        // Post notification (also posted by invalidateAllVisitCaches, but keep for explicit trigger)
        NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)
        
        // Refresh widgets
        WidgetCenter.shared.reloadAllTimelines()
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
            // No active visits
            if isContinuousMode {
                // In continuous mode, keep running to detect new entries
                // DEBUG: Commented out to reduce spam
                // print("✅ No active visits, but continuous mode enabled - keeping timer running")
            } else {
                // Not in continuous mode - stop timer
                print("✅ All visits closed, stopping validation timer")
                stopValidationTimer()
            }
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
            // CRITICAL: Check if we've reached or passed 11:59 PM of the entry day
            // This proactively closes visits at 11:59 PM instead of waiting until after midnight
            let calendar = Calendar.current
            let now = Date()
            
            // Calculate 11:59:59 PM of entry day
            var endOfEntryDayComponents = calendar.dateComponents([.year, .month, .day], from: visit.entryTime)
            endOfEntryDayComponents.hour = 23
            endOfEntryDayComponents.minute = 59
            endOfEntryDayComponents.second = 59
            
            guard let endOfEntryDay = calendar.date(from: endOfEntryDayComponents) else {
                print("❌ Failed to calculate end of entry day")
                continue
            }
            
            // Check if current time is >= 11:59:59 PM of entry day
            // OR if we've already crossed into the next day
            let entryDay = calendar.dateComponents([.year, .month, .day], from: visit.entryTime)
            let currentDay = calendar.dateComponents([.year, .month, .day], from: now)
            let hasReached1159PM = now >= endOfEntryDay
            let hasCrossedMidnight = entryDay != currentDay
            
            if hasReached1159PM || hasCrossedMidnight {
                print("🌙 CLOSING VISIT AT 11:59 PM for active visit at \(savedPlaces.first(where: { $0.id == placeId })?.displayName ?? "unknown")")
                print("   Entry: \(visit.entryTime), Current: \(now), End of day: \(endOfEntryDay)")

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

        // Calculate 12:00:00 AM of the NEXT day (day after entry day)
        // This ensures we always start the new visit on the correct day, even if called at 11:59 PM
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: endOfEntryDay) else {
            print("❌ Failed to calculate next day")
            // Remove old visit from active visits (thread-safe)
            geofenceManager.removeActiveVisit(for: placeId)
            return
        }
        
        var newDayComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
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

        // CRITICAL: Use unified cache invalidation to keep all views in sync after midnight split
        LocationVisitAnalytics.shared.invalidateAllVisitCaches()
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

        // AUTO-DELETE: Skip saving visits under 2 minutes (likely false positives)
        // Only check if visit is complete (has exit_time and duration)
        if let exitTime = visit.exitTime, let durationMinutes = visit.durationMinutes, durationMinutes < 2 {
            print("🗑️ Skipping save for short visit in BGValidation: \(visit.id.uuidString) (duration: \(durationMinutes) min < 2 min)")
            return
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

        // AUTO-DELETE: Delete visits under 2 minutes instead of updating them
        // Only check if visit is complete (has exit_time and duration)
        if let exitTime = visit.exitTime, let durationMinutes = visit.durationMinutes, durationMinutes < 2 {
            print("🗑️ Auto-deleting short visit in BGValidation instead of updating: \(visit.id.uuidString) (duration: \(durationMinutes) min < 2 min)")
            let geofenceManager = await GeofenceManager.shared
            await geofenceManager.deleteVisitFromSupabase(visit)
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

            // CRITICAL: Use unified cache invalidation to keep all views in sync
            LocationVisitAnalytics.shared.invalidateAllVisitCaches()
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
