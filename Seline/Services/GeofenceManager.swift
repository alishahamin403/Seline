import Foundation
import CoreLocation
import PostgREST

// MARK: - LocationVisitRecord Model

struct LocationVisitRecord: Codable, Identifiable {
    var id: UUID
    let userId: UUID
    let savedPlaceId: UUID
    var entryTime: Date
    var exitTime: Date?
    var durationMinutes: Int?
    var dayOfWeek: String
    var timeOfDay: String
    var month: Int
    var year: Int
    var sessionId: UUID? // Groups related visits (app restart, GPS loss) - NEW
    var confidenceScore: Double? // 1.0 (certain), 0.95, 0.85 (app restart/GPS) - NEW
    var mergeReason: String? // "app_restart", "gps_reconnect", "quick_return" - NEW
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case savedPlaceId = "saved_place_id"
        case entryTime = "entry_time"
        case exitTime = "exit_time"
        case durationMinutes = "duration_minutes"
        case dayOfWeek = "day_of_week"
        case timeOfDay = "time_of_day"
        case month, year
        case sessionId = "session_id" // NEW
        case confidenceScore = "confidence_score" // NEW
        case mergeReason = "merge_reason" // NEW
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func create(
        userId: UUID,
        savedPlaceId: UUID,
        entryTime: Date,
        sessionId: UUID? = nil,
        confidenceScore: Double? = 1.0,
        mergeReason: String? = nil
    ) -> LocationVisitRecord {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .month, .year], from: entryTime)

        let dayOfWeek = Self.dayOfWeekName(for: components.weekday ?? 1)
        let timeOfDay = Self.timeOfDayName(for: entryTime)
        let month = components.month ?? 1
        let year = components.year ?? 2024

        return LocationVisitRecord(
            id: UUID(),
            userId: userId,
            savedPlaceId: savedPlaceId,
            entryTime: entryTime,
            exitTime: Optional<Date>.none,
            durationMinutes: Optional<Int>.none,
            dayOfWeek: dayOfWeek,
            timeOfDay: timeOfDay,
            month: month,
            year: year,
            sessionId: sessionId ?? UUID(), // NEW: Create new session if not provided
            confidenceScore: confidenceScore, // NEW: Default 1.0 (high confidence)
            mergeReason: mergeReason, // NEW: No merge reason for new visits
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    mutating func recordExit(exitTime: Date) {
        self.exitTime = exitTime
        let minutes = Int(exitTime.timeIntervalSince(entryTime) / 60)
        self.durationMinutes = max(minutes, 1) // At least 1 minute
        self.updatedAt = Date()
    }

    /// Checks if the visit spans across midnight (entry and exit on different calendar days)
    func spansMidnight() -> Bool {
        guard let exit = exitTime else { return false }
        let calendar = Calendar.current
        let entryDay = calendar.dateComponents([.year, .month, .day], from: entryTime)
        let exitDay = calendar.dateComponents([.year, .month, .day], from: exit)
        return entryDay != exitDay
    }

    /// Splits the visit into two records at midnight if it spans across days
    /// Returns an array with 1 or 2 visits depending on whether midnight was crossed
    func splitAtMidnightIfNeeded() -> [LocationVisitRecord] {
        guard spansMidnight(), let exit = exitTime else {
            return [self]
        }

        let calendar = Calendar.current

        // Find midnight between entry and exit
        var midnightComponents = calendar.dateComponents([.year, .month, .day], from: entryTime)
        midnightComponents.hour = 23
        midnightComponents.minute = 59
        midnightComponents.second = 59

        guard let midnightOfEntryDay = calendar.date(from: midnightComponents) else {
            return [self]
        }

        // Visit 1: Entry to end of entry day (11:59:59 PM)
        var visit1 = self
        visit1.id = UUID() // New ID for split visit
        visit1.exitTime = midnightOfEntryDay
        let minutes1 = Int(midnightOfEntryDay.timeIntervalSince(entryTime) / 60)
        visit1.durationMinutes = max(minutes1, 1)
        visit1.updatedAt = Date()

        // Visit 2: Start of exit day (12:00:00 AM) to exit
        var visit2 = self
        visit2.id = UUID() // New ID for split visit

        var midnightOfExitDay = calendar.dateComponents([.year, .month, .day], from: exit)
        midnightOfExitDay.hour = 0
        midnightOfExitDay.minute = 0
        midnightOfExitDay.second = 0

        guard let midnightStart = calendar.date(from: midnightOfExitDay) else {
            return [self]
        }

        visit2.entryTime = midnightStart
        visit2.exitTime = exit
        let minutes2 = Int(exit.timeIntervalSince(midnightStart) / 60)
        visit2.durationMinutes = max(minutes2, 1)
        let exitComponents = calendar.dateComponents([.weekday, .month, .year], from: exit)
        visit2.dayOfWeek = Self.dayOfWeekName(for: exitComponents.weekday ?? 1)
        visit2.timeOfDay = Self.timeOfDayName(for: exit)
        visit2.month = exitComponents.month ?? 1
        visit2.year = exitComponents.year ?? 2024
        visit2.updatedAt = Date()

        return [visit1, visit2]
    }

    private static func dayOfWeekName(for dayIndex: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        // dayIndex from Calendar.dateComponents is 1-7 (1=Sunday), but array is 0-indexed
        if dayIndex >= 1 && dayIndex <= 7 {
            return days[dayIndex - 1]
        }
        return "Unknown"
    }

    private static func timeOfDayName(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }
}

// MARK: - GeofenceManager

@MainActor
class GeofenceManager: NSObject, ObservableObject {
    static let shared = GeofenceManager()

    // OPTIMIZATION: Use SharedLocationManager instead of creating own instance
    // This consolidates CLLocationManager to reduce battery drain and redundancy
    private let sharedLocationManager = SharedLocationManager.shared

    private var monitoredRegions: [String: CLCircularRegion] = [:] // [placeId: region]
    var activeVisits: [UUID: LocationVisitRecord] = [:] // [placeId: visit]
    // DEPRECATED: recentlyClosedVisits cache moved to MergeDetectionService.shared

    // Thread safety: Protect activeVisits dictionary from race conditions
    // Ensures atomic access during simultaneous geofence entry/exit events
    private let activeVisitsLock = NSLock()

    @Published var isMonitoring = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let geofenceRadius: CLLocationDistance = 300 // Used for fallback in some contexts (increased from 200m)
    // Note: Smart radius detection is now handled by GeofenceRadiusManager.shared

    override init() {
        super.init()
        // Subscribe to shared location manager updates
        authorizationStatus = sharedLocationManager.authorizationStatus
    }

    /// Handle geofence entry from SharedLocationManager
    nonisolated func handleGeofenceEntry(region: CLCircularRegion) async {
        await self.locationManager(CLLocationManager(), didEnterRegion: region)
    }

    /// Handle geofence exit from SharedLocationManager
    nonisolated func handleGeofenceExit(region: CLCircularRegion) async {
        await self.locationManager(CLLocationManager(), didExitRegion: region)
    }

    // MARK: - Permission Handling

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // Request background location permission (Always)
            sharedLocationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            errorMessage = "Background location access required for visit tracking. Please enable in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Geofence Management

    /// Setup geofences for all saved locations
    func setupGeofences(for places: [SavedPlace]) {
        // DEBUG: Commented out to reduce console spam
        // print("\n🔍 ===== SETTING UP GEOFENCES =====")
        // print("🔍 Total locations to track: \(places.count)")

        // Only proceed if we have background location authorization
        guard authorizationStatus == .authorizedAlways else {
            print("⚠️ Background location authorization not yet granted. Waiting for permission...")
            print("⚠️ Current status: \(authorizationStatus.rawValue)")
            print("🔍 ===================================\n")
            return
        }

        // Remove existing geofences
        // DEBUG: Commented out to reduce console spam
        // print("🔨 Removing \(monitoredRegions.count) existing geofences...")
        monitoredRegions.forEach { sharedLocationManager.stopMonitoring(region: $0.value) }
        monitoredRegions.removeAll()

        // Add new geofences for all saved locations
        let locationsToTrack = places

        for place in locationsToTrack {
            // NEW: Use smart radius detection (user override or auto-detect)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)

            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                radius: radius, // Use smart radius instead of fixed 200m
                identifier: place.id.uuidString
            )

            region.notifyOnEntry = true
            region.notifyOnExit = true

            sharedLocationManager.startMonitoring(region: region)
            monitoredRegions[place.id.uuidString] = region

            // Removed excessive geofence logging
        }

        if !locationsToTrack.isEmpty {
            isMonitoring = true
            // DEBUG: Commented out to reduce console spam
            // print("✅ GEOFENCES SETUP COMPLETE - Now monitoring \(locationsToTrack.count) locations")

            // SOLUTION 4: Check for proximity collisions (commented out to reduce console spam)
            // GeofenceRadiusManager.shared.printProximityCollisionReport(for: places)
        }
        print("🔍 ===================================\n")
    }

    /// Stop monitoring all geofences
    func stopMonitoring() {
        print("🛑 Stopping all geofence monitoring")
        monitoredRegions.forEach { sharedLocationManager.stopMonitoring(region: $0.value) }
        monitoredRegions.removeAll()
        activeVisitsLock.lock()
        activeVisits.removeAll()
        activeVisitsLock.unlock()
        MergeDetectionService.shared.clearCache() // Clear merge detection cache
        DwellTimeValidator.shared.cancelAllPendingEntries() // SOLUTION 5: Cancel pending dwell validations
        LocationBackgroundValidationService.shared.stopValidationTimer()
        isMonitoring = false
    }

    /// Update background location tracking based on user preference
    func updateBackgroundLocationTracking(enabled: Bool) {
        sharedLocationManager.enableBackgroundLocationTracking(enabled)
    }

    /// Update geofence radius for a place (when user changes radius or category)
    /// NEW: Called by GeofenceRadiusManager when radius changes
    func updateGeofenceRadius(for place: SavedPlace) {
        guard let existingRegion = monitoredRegions[place.id.uuidString] else {
            print("⚠️ Geofence not found for place: \(place.id.uuidString)")
            return
        }

        // Get new radius
        let newRadius = GeofenceRadiusManager.shared.getRadius(for: place)

        // Create new region with updated radius
        let newRegion = CLCircularRegion(
            center: existingRegion.center,
            radius: newRadius,
            identifier: existingRegion.identifier
        )
        newRegion.notifyOnEntry = true
        newRegion.notifyOnExit = true

        // Stop old region and start new one
        sharedLocationManager.stopMonitoring(region: existingRegion)
        sharedLocationManager.startMonitoring(region: newRegion)
        monitoredRegions[place.id.uuidString] = newRegion

        print("🔄 Updated geofence radius for \(place.displayName): \(Int(newRadius))m")
    }

    // MARK: - Geofence Event Handling (called by SharedLocationManager)

    nonisolated private func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            print("\n✅ ===== GEOFENCE ENTRY EVENT FIRED =====")
            print("✅ Entered geofence: \(region.identifier)")
            print("✅ ========================================\n")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
                print("⚠️ No user ID for visit tracking")
                return
            }

            // Check location accuracy - reject entry if accuracy is poor (> 30m)
            guard let currentLocation = self.sharedLocationManager.currentLocation else {
                print("⚠️ No recent location data available, cannot determine best-match location")
                return
            }

            let horizontalAccuracy = currentLocation.horizontalAccuracy
            if horizontalAccuracy > 30 {
                print("⚠️ GEOFENCE ENTRY REJECTED: GPS accuracy too low (\(String(format: "%.1f", horizontalAccuracy))m > 30m threshold)")
                return
            } else {
                print("✅ GPS accuracy acceptable: \(String(format: "%.1f", horizontalAccuracy))m")
            }

            // SOLUTION 3: BEST-MATCH LOCATION SELECTION
            // Find all nearby locations within their geofence radius and pick the closest one
            // This prevents recording visits at wrong locations when geofences overlap
            let allPlaces = LocationsManager.shared.savedPlaces
            var nearbyPlaces: [(place: SavedPlace, distance: CLLocationDistance)] = []

            for place in allPlaces {
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLocation.distance(from: placeLocation)
                let radius = GeofenceRadiusManager.shared.getRadius(for: place)

                // Check if we're within this place's geofence
                if distance <= radius {
                    nearbyPlaces.append((place: place, distance: distance))
                }
            }

            // If no places are nearby (shouldn't happen since geofence triggered), bail out
            guard !nearbyPlaces.isEmpty else {
                print("⚠️ No nearby places found despite geofence entry - GPS drift?")
                return
            }

            // Find the CLOSEST place
            let closestPlace = nearbyPlaces.min(by: { $0.distance < $1.distance })!

            // Log all nearby places for debugging
            if nearbyPlaces.count > 1 {
                print("\n🎯 BEST-MATCH SELECTION (Multiple overlapping geofences detected)")
                print("🎯 Nearby places within geofence:")
                for (place, dist) in nearbyPlaces.sorted(by: { $0.distance < $1.distance }) {
                    let marker = place.id == closestPlace.place.id ? "✅ SELECTED" : "  "
                    print("   \(marker) \(place.displayName): \(String(format: "%.1f", dist))m away")
                }
                print("🎯 ==========================================\n")
            }

            // Override placeId with the closest place
            let bestMatchPlaceId = closestPlace.place.id

            // If the triggered geofence was NOT the closest place, we ignore this event
            // (We'll pick it up when the closest place's geofence triggers)
            if placeId != bestMatchPlaceId {
                print("⏭️ SKIPPING: Geofence triggered for \(region.identifier) but closest place is \(closestPlace.place.displayName)")
                return
            }

            print("✅ BEST-MATCH CONFIRMED: Recording visit for \(closestPlace.place.displayName) (\(String(format: "%.1f", closestPlace.distance))m away)")

            // Check if we already have an active visit for this location
            // This prevents duplicate sessions if geofence is re-triggered while user is still in location
            // THREAD SAFETY: Use lock to prevent race conditions during simultaneous entry/exit
            activeVisitsLock.lock()
            let hasExistingVisit = self.activeVisits[placeId] != nil
            activeVisitsLock.unlock()

            if hasExistingVisit {
                print("ℹ️ Active visit already exists for place: \(placeId), skipping duplicate entry")
                return
            }

            // SOLUTION 5: DWELL TIME VALIDATION
            // Check if dwell time validation is enabled - if so, register pending entry
            // instead of immediately creating visit
            if DwellTimeValidator.shared.isEnabled {
                // Check if there's already a pending entry
                if DwellTimeValidator.shared.hasPendingEntry(for: bestMatchPlaceId) {
                    print("ℹ️ Pending dwell time validation already exists for place: \(bestMatchPlaceId)")
                    return
                }

                // Register pending entry - will create visit after dwell time expires
                DwellTimeValidator.shared.registerPendingEntry(
                    placeId: bestMatchPlaceId,
                    placeName: closestPlace.place.displayName,
                    currentLocation: currentLocation,
                    geofenceRadius: closestPlace.place.customGeofenceRadius ?? GeofenceRadiusManager.shared.getRadius(for: closestPlace.place),
                    locationManager: self.sharedLocationManager
                ) { validatedPlaceId in
                    // This closure is called after dwell time validation passes
                    Task { @MainActor in
                        await self.createVisitAfterDwellValidation(for: validatedPlaceId)
                    }
                }

                print("⏳ Dwell time validation started for \(closestPlace.place.displayName)")
                return
            }

            // SOLUTION 2: Close any existing active visits (in-memory) before starting new one
            // CRITICAL: Only ONE visit can be active at any time
            activeVisitsLock.lock()
            let existingActiveVisits = self.activeVisits.filter { $0.key != placeId }
            activeVisitsLock.unlock()

            if !existingActiveVisits.isEmpty {
                print("⚠️ CLOSING \(existingActiveVisits.count) existing in-memory visit(s) before new entry")
                for (existingPlaceId, var existingVisit) in existingActiveVisits {
                    existingVisit.recordExit(exitTime: Date())

                    activeVisitsLock.lock()
                    self.activeVisits.removeValue(forKey: existingPlaceId)
                    activeVisitsLock.unlock()

                    // Update in Supabase
                    await self.updateVisitInSupabase(existingVisit)
                    LocationVisitAnalytics.shared.invalidateCache(for: existingPlaceId)
                    print("   ✅ Closed visit for: \(existingPlaceId)")
                }
            }

            // SOLUTION 2: Check if there's an unresolved visit in Supabase (from different app session)
            // This prevents multiple active visits across different places
            if let unresolvedVisit = await LocationErrorRecoveryService.shared.hasUnresolvedVisits(geofenceManager: self) {
                // Skip if this is the same location we're entering (might be a merge candidate)
                if unresolvedVisit.savedPlaceId != placeId {
                    let hoursSinceEntry = Date().timeIntervalSince(unresolvedVisit.entryTime) / 3600
                    print("⚠️ SOLUTION 2 - Unresolved visit exists at different location")
                    print("   Location: \(unresolvedVisit.savedPlaceId.uuidString)")
                    print("   Started: \(String(format: "%.1f", hoursSinceEntry))h ago")
                    print("   Action: Auto-closing old visit to allow new one")

                    // Auto-close the old unresolved visit
                    await LocationErrorRecoveryService.shared.autoCloseUnresolvedVisit(unresolvedVisit)

                    // Remove from activeVisits if it's there (with lock protection)
                    activeVisitsLock.lock()
                    self.activeVisits.removeValue(forKey: unresolvedVisit.savedPlaceId)
                    activeVisitsLock.unlock()

                    // Invalidate cache for the location that was auto-closed
                    LocationVisitAnalytics.shared.invalidateCache(for: unresolvedVisit.savedPlaceId)
                }
            }

            // NEW: Use MergeDetectionService for 3-scenario merge logic
            let currentCoords = self.sharedLocationManager.currentLocation?.coordinate ?? CLLocationCoordinate2D()

            if let (mergeCandidate, confidence, reason) = await MergeDetectionService.shared.findMergeCandidate(
                for: placeId,
                currentLocation: currentCoords,
                geofenceRadius: self.geofenceRadius
            ) {
                print("\n🔄 ===== MERGING VISITS (Confidence: \(String(format: "%.0f%%", confidence * 100))) =====")
                print("🔄 Reason: \(reason)")
                print("🔄 Previous visit: \(mergeCandidate.entryTime) to \(mergeCandidate.exitTime?.description ?? "ongoing")")

                // Use atomic merge to ensure data consistency
                let sessionId = mergeCandidate.sessionId ?? UUID()
                if await LocationErrorRecoveryService.shared.executeAtomicMerge(
                    mergeCandidate,
                    sessionId: sessionId,
                    confidence: confidence,
                    reason: reason,
                    geofenceManager: self,
                    sessionManager: LocationSessionManager.shared
                ) {
                    print("🔄 ============================\n")

                    // Add to merge detection cache for future reference
                    MergeDetectionService.shared.cacheClosedVisit(mergeCandidate)
                }
            } else {
                // Create a new visit record with new session
                let sessionId = UUID()
                var visit = LocationVisitRecord.create(
                    userId: userId,
                    savedPlaceId: placeId,
                    entryTime: Date(),
                    sessionId: sessionId,
                    confidenceScore: 1.0,
                    mergeReason: nil
                )

                // Add to activeVisits with lock protection
                activeVisitsLock.lock()
                self.activeVisits[placeId] = visit
                activeVisitsLock.unlock()

                // Create session and save to Supabase
                LocationSessionManager.shared.createSession(for: placeId, userId: userId)

                print("📝 Started tracking visit for place: \(placeId)")
                print("📝 New session: \(sessionId.uuidString)")

                // Invalidate analytics cache since a new active visit was created
                LocationVisitAnalytics.shared.invalidateCache(for: placeId)

                // Save to Supabase
                await self.saveVisitToSupabase(visit)

                // Notify that visits have been updated so UI can refresh
                NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)
            }

            // Start background validation timer if not already running
            if !LocationBackgroundValidationService.shared.isValidationRunning() {
                LocationBackgroundValidationService.shared.startValidationTimer(
                    geofenceManager: self,
                    locationManager: self.sharedLocationManager,
                    savedPlaces: LocationsManager.shared.savedPlaces
                )
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            print("\n⛔️ ===== GEOFENCE EXIT EVENT FIRED =====")
            print("⛔️ Exited geofence: \(region.identifier)")
            print("⛔️ Active visits in memory: \(self.activeVisits.count)")
            print("⛔️ =====================================\n")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            // SOLUTION 5: Cancel pending dwell time validation if user left early
            if DwellTimeValidator.shared.hasPendingEntry(for: placeId) {
                DwellTimeValidator.shared.cancelPendingEntry(for: placeId)
                print("⏭️ Cancelled pending dwell time validation (user left early)")
                return
            }

            // First, check if we have an active visit in memory
            // THREAD SAFETY: Use lock to prevent race conditions during simultaneous entry/exit
            activeVisitsLock.lock()
            let visit = self.activeVisits.removeValue(forKey: placeId)
            activeVisitsLock.unlock()

            if var visit = visit {
                visit.recordExit(exitTime: Date())

                // Filter out visits shorter than 10 minutes (noise from brief location hiccups and passing by)
                let durationMinutes = visit.durationMinutes ?? 0
                if durationMinutes < 10 {
                    print("⏭️ VISIT FILTERED OUT: Duration too short (\(durationMinutes) min < 10 min minimum)")
                    // FIX: Delete the visit from Supabase since it was already saved during entry
                    await self.deleteVisitFromSupabase(visit)
                    return
                }

                // NEW: Store in MergeDetectionService cache for merge detection
                // This handles the scenario where app backgrounded and re-enters within 30 minutes
                MergeDetectionService.shared.cacheClosedVisit(visit)

                // Check if visit spans midnight and split if needed
                let visitsToSave = visit.splitAtMidnightIfNeeded()

                if visitsToSave.count > 1 {
                    print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
                    for visitPart in visitsToSave {
                        print("  - \(visitPart.dayOfWeek): \(visitPart.entryTime) to \(visitPart.exitTime?.description ?? "nil") (\(visitPart.durationMinutes ?? 0) min)")
                        await self.saveVisitToSupabase(visitPart)
                    }
                } else {
                    print("✅ Finished tracking visit for place: \(placeId), duration: \(visit.durationMinutes ?? 0) min")
                    await self.updateVisitInSupabase(visit)
                }

                // Close session when all visits for this place are done
                LocationSessionManager.shared.closeSession(visit.sessionId ?? UUID())
            } else {
                // If not in memory (app was backgrounded/killed), fetch from Supabase
                print("⚠️ Visit not found in memory, fetching from Supabase...")
                await self.findAndCloseIncompleteVisit(for: placeId)
            }
        }
    }

    // MARK: - SOLUTION 5: Dwell Time Validation

    /// Create a visit after dwell time validation passes
    /// This is called by DwellTimeValidator after user has been continuously present for required time
    private func createVisitAfterDwellValidation(for placeId: UUID) async {
        print("\n📝 ===== CREATING VISIT AFTER DWELL VALIDATION =====")

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID for visit tracking")
            return
        }

        // Check if we already have an active visit (shouldn't happen, but safety check)
        activeVisitsLock.lock()
        let hasExistingVisit = self.activeVisits[placeId] != nil
        activeVisitsLock.unlock()

        if hasExistingVisit {
            print("ℹ️ Active visit already exists for place: \(placeId), skipping")
            return
        }

        // Close any existing active visits before starting new one
        activeVisitsLock.lock()
        let existingActiveVisits = self.activeVisits.filter { $0.key != placeId }
        activeVisitsLock.unlock()

        if !existingActiveVisits.isEmpty {
            print("⚠️ CLOSING \(existingActiveVisits.count) existing visit(s) before new entry")
            for (existingPlaceId, var existingVisit) in existingActiveVisits {
                existingVisit.recordExit(exitTime: Date())

                activeVisitsLock.lock()
                self.activeVisits.removeValue(forKey: existingPlaceId)
                activeVisitsLock.unlock()

                await self.updateVisitInSupabase(existingVisit)
                LocationVisitAnalytics.shared.invalidateCache(for: existingPlaceId)
            }
        }

        // Check for merge candidates
        let currentCoords = self.sharedLocationManager.currentLocation?.coordinate ?? CLLocationCoordinate2D()

        if let (mergeCandidate, confidence, reason) = await MergeDetectionService.shared.findMergeCandidate(
            for: placeId,
            currentLocation: currentCoords,
            geofenceRadius: self.geofenceRadius
        ) {
            print("🔄 MERGING VISITS after dwell validation")
            let sessionId = mergeCandidate.sessionId ?? UUID()
            if await LocationErrorRecoveryService.shared.executeAtomicMerge(
                mergeCandidate,
                sessionId: sessionId,
                confidence: confidence,
                reason: reason,
                geofenceManager: self,
                sessionManager: LocationSessionManager.shared
            ) {
                MergeDetectionService.shared.cacheClosedVisit(mergeCandidate)
            }
        } else {
            // Create new visit
            let sessionId = UUID()
            let visit = LocationVisitRecord.create(
                userId: userId,
                savedPlaceId: placeId,
                entryTime: Date(),
                sessionId: sessionId,
                confidenceScore: 1.0,
                mergeReason: nil
            )

            activeVisitsLock.lock()
            self.activeVisits[placeId] = visit
            activeVisitsLock.unlock()

            LocationSessionManager.shared.createSession(for: placeId, userId: userId)
            LocationVisitAnalytics.shared.invalidateCache(for: placeId)

            await self.saveVisitToSupabase(visit)

            NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)

            print("✅ Visit created after dwell validation: \(placeId)")
        }

        // Start background validation if needed
        if !LocationBackgroundValidationService.shared.isValidationRunning() {
            LocationBackgroundValidationService.shared.startValidationTimer(
                geofenceManager: self,
                locationManager: self.sharedLocationManager,
                savedPlaces: LocationsManager.shared.savedPlaces
            )
        }

        print("📝 ==============================================\n")
    }

    // DEPRECATED: Merge detection has been moved to MergeDetectionService
    // See: MergeDetectionService.shared.findMergeCandidate()
    // This provides three-scenario merge logic:
    // - Scenario A: Open visit <5 min (app restart, 100% confidence)
    // - Scenario B: Closed visit <3 min (quick return, 95% confidence)
    // - Scenario C: Closed visit 3-10 min in geofence (GPS reconnect, 85% confidence)

    /// Fetches the most recent incomplete visit for a location and closes it
    private func findAndCloseIncompleteVisit(for placeId: UUID) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, cannot close incomplete visit")
            return
        }

        do {
            print("🔍 Querying Supabase for incomplete visit - Place: \(placeId), User: \(userId.uuidString)")

            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .order("entry_time", ascending: false)
                .limit(1)
                .execute()

            // FIXED: Use supabaseDecoder to handle PostgreSQL timestamp format
            // Standard .iso8601 fails on "2025-12-02 23:34:08.948" format
            let decoder = JSONDecoder.supabaseDecoder()

            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            if var visit = visits.first {
                print("📋 Found visit in Supabase - ID: \(visit.id), Entry: \(visit.entryTime), Exit: \(visit.exitTime?.description ?? "nil")")

                // Only close if it doesn't already have an exit time
                if visit.exitTime == nil {
                    visit.recordExit(exitTime: Date())

                    // Filter out visits shorter than 10 minutes (noise from brief location hiccups and passing by)
                    let durationMinutes = visit.durationMinutes ?? 0
                    if durationMinutes < 10 {
                        print("⏭️ VISIT FILTERED OUT: Duration too short (\(durationMinutes) min < 10 min minimum)")
                        // FIX: Delete the visit from Supabase since it was already saved
                        await self.deleteVisitFromSupabase(visit)
                        return
                    }

                    // NEW: Store in MergeDetectionService cache for merge detection (for backgrounded app scenario)
                    MergeDetectionService.shared.cacheClosedVisit(visit)

                    // Check if visit spans midnight and split if needed
                    let visitsToSave = visit.splitAtMidnightIfNeeded()

                    if visitsToSave.count > 1 {
                        print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
                        for visitPart in visitsToSave {
                            print("  - \(visitPart.dayOfWeek): \(visitPart.entryTime) to \(visitPart.exitTime?.description ?? "nil") (\(visitPart.durationMinutes ?? 0) min)")
                            await self.saveVisitToSupabase(visitPart)
                        }
                    } else {
                        print("✅ CLOSED INCOMPLETE VISIT - Place: \(placeId), Duration: \(visit.durationMinutes ?? 0) min")
                        await self.updateVisitInSupabase(visit)
                    }
                } else {
                    print("ℹ️ Most recent visit already has exit time at \(visit.exitTime?.description ?? "unknown"), skipping")
                }
            } else {
                print("⚠️ No visit found in Supabase for place: \(placeId)")
            }
        } catch {
            print("❌ Error finding incomplete visit: \(error)")
        }
    }

    /// Sync authorization status from SharedLocationManager
    func observeAuthorizationChanges() {
        // In the future, this could use Combine to observe changes
        // For now, it's called from requestLocationPermission
    }

    /// Handle authorization changes (internal use, sync with SharedLocationManager)
    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        self.authorizationStatus = status

        switch status {
        case .authorizedAlways:
            // DEBUG: Commented out to reduce console spam
            // print("✅ Background location authorization granted")

            // Enable background location updates based on user preference
            let locationTrackingMode = UserDefaults.standard.string(forKey: "locationTrackingMode") ?? "active"
            sharedLocationManager.enableBackgroundLocationTracking(locationTrackingMode == "background")

            setupGeofences(for: LocationsManager.shared.savedPlaces)
        case .authorizedWhenInUse:
            print("⚠️ Only 'When In Use' authorization granted. Geofencing requires 'Always' permission.")
            self.errorMessage = "Geofencing requires 'Always' location permission"
        case .denied, .restricted:
            print("❌ Location authorization denied")
            self.errorMessage = "Location access denied"
            stopMonitoring()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Supabase Integration

    /// Load incomplete visits from Supabase and restore them to activeVisits
    /// Called on app startup to resume tracking
    /// NEW: Delegates to LocationErrorRecoveryService for unified recovery handling
    func loadIncompleteVisitsFromSupabase() async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping incomplete visits load")
            return
        }

        await LocationErrorRecoveryService.shared.recoverOnAppLaunch(
            userId: userId,
            geofenceManager: self,
            sessionManager: LocationSessionManager.shared
        )

        // CRITICAL: Check if user is already inside a saved location
        // iOS geofencing doesn't fire entry events if you're already inside when monitoring starts
        await checkIfAlreadyInsideLocation(userId: userId)
    }

    /// Check if user is currently inside any saved location and create visit if needed
    /// This handles the iOS limitation where geofence entry events don't fire if already inside
    private func checkIfAlreadyInsideLocation(userId: UUID) async {
        // DEBUG: Commented out to reduce console spam
        // print("\n📍 ===== CHECKING IF ALREADY INSIDE A LOCATION =====")

        guard let currentLocation = sharedLocationManager.currentLocation else {
            print("⚠️ No current location available")
            return
        }

        let savedPlaces = LocationsManager.shared.savedPlaces
        // DEBUG: Commented out to reduce console spam
        // print("📍 Current location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
        // print("📍 Checking against \(savedPlaces.count) saved places...")

        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)

            if distance <= radius {
                // DEBUG: Commented out to reduce console spam
                // print("✅ User is INSIDE: \(place.displayName) (distance: \(String(format: "%.0f", distance))m, radius: \(String(format: "%.0f", radius))m)")

                // Check if we already have an active visit for this place
                activeVisitsLock.lock()
                let hasActiveVisit = activeVisits[place.id] != nil
                activeVisitsLock.unlock()

                if hasActiveVisit {
                    // DEBUG: Commented out to reduce console spam
                    // print("ℹ️ Already have an active visit for \(place.displayName), skipping")
                    continue
                }

                // Create a new visit since user is inside but no active visit exists
                // DEBUG: Commented out to reduce console spam
                // print("📝 Creating new visit for \(place.displayName) (user was already inside)")

                let sessionId = UUID()
                let visit = LocationVisitRecord.create(
                    userId: userId,
                    savedPlaceId: place.id,
                    entryTime: Date(),
                    sessionId: sessionId,
                    confidenceScore: 0.9,  // Slightly lower confidence since detected on app launch
                    mergeReason: "app_launch_inside"
                )

                activeVisitsLock.lock()
                activeVisits[place.id] = visit
                activeVisitsLock.unlock()

                LocationSessionManager.shared.createSession(for: place.id, userId: userId)
                LocationVisitAnalytics.shared.invalidateCache(for: place.id)

                await saveVisitToSupabase(visit)

                // DEBUG: Commented out to reduce console spam
                // print("✅ Created visit for \(place.displayName)")

                // Notify that visits have been updated so UI can refresh
                NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)

                // Start validation timer
                if !LocationBackgroundValidationService.shared.isValidationRunning() {
                    LocationBackgroundValidationService.shared.startValidationTimer(
                        geofenceManager: self,
                        locationManager: sharedLocationManager,
                        savedPlaces: savedPlaces
                    )
                }

                // Only create one visit at a time
                break
            } else {
                // DEBUG: Commented out to reduce console spam
                // print("📍 Not inside \(place.displayName) (distance: \(String(format: "%.0f", distance))m > radius: \(String(format: "%.0f", radius))m)")
            }
        }

        // DEBUG: Commented out to reduce console spam
        // print("📍 ===== CHECK COMPLETE =====\n")
    }

    /// Force cleanup of stale visits in memory
    /// Call this if you suspect visits are stuck
    func forceCleanupStaleVisits(olderThanMinutes: Int = 240) async {
        print("\n🧹 ===== FORCE CLEANUP STALE VISITS (IN MEMORY) =====")
        print("🧹 Threshold: \(olderThanMinutes) minutes")
        print("🧹 Current active visits: \(activeVisits.count)")

        let staleThreshold: TimeInterval = Double(olderThanMinutes) * 60
        let now = Date()
        var cleanedCount = 0

        for (placeId, var visit) in activeVisits {
            let visitDuration = now.timeIntervalSince(visit.entryTime)
            if visitDuration > staleThreshold {
                print("🧹 Cleaning up: \(visit.savedPlaceId) (open for \(Int(visitDuration / 60)) minutes)")
                visit.recordExit(exitTime: now)
                activeVisits.removeValue(forKey: placeId)
                await updateVisitInSupabase(visit)
                cleanedCount += 1
            }
        }

        print("🧹 Cleaned up: \(cleanedCount) visits")
        print("🧹 Remaining active visits: \(activeVisits.count)")
        print("🧹 ====================================================\n")
    }

    /// Cleanup incomplete visits directly in Supabase database
    /// This finds ALL incomplete visits older than threshold and closes them
    /// Use this to fix visits that got stuck before the auto-cleanup code was added
    func cleanupIncompleteVisitsInSupabase(olderThanMinutes: Int = 180) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, cannot cleanup incomplete visits in Supabase")
            return
        }

        // DEBUG: Commented out to reduce console spam
        // print("\n🗑️ ===== CLEANUP INCOMPLETE VISITS IN SUPABASE =====")
        // print("🗑️ Threshold: \(olderThanMinutes) minutes")
        // print("🗑️ User: \(userId.uuidString)")

        do{
            let client = await SupabaseManager.shared.getPostgrestClient()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Calculate threshold time (now - olderThanMinutes)
            let thresholdDate = Date(timeIntervalSinceNow: -Double(olderThanMinutes) * 60)
            let thresholdString = formatter.string(from: thresholdDate)

            // DEBUG: Commented out to reduce console spam
            // print("🗑️ Looking for incomplete visits before: \(thresholdString)")

            // First, fetch all visits older than threshold, then filter for incomplete ones in Swift
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .lt("entry_time", value: thresholdString)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let allOldVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for incomplete visits (exit_time = nil)
            let staleVisits = allOldVisits.filter { $0.exitTime == nil }

            print("🗑️ Found \(staleVisits.count) incomplete visits to close")

            var closedCount = 0
            var deletedCount = 0
            // Close each stale visit by setting exit_time = now and duration
            for var visit in staleVisits {
                visit.recordExit(exitTime: Date())

                // FIX: Filter out short visits (< 10 min) - delete instead of update
                let durationMinutes = visit.durationMinutes ?? 0
                if durationMinutes < 10 {
                    print("🗑️ Deleting short visit: \(visit.id.uuidString) (duration: \(durationMinutes)min < 10min)")
                    await deleteVisitFromSupabase(visit)
                    deletedCount += 1
                    continue
                }

                let updateData: [String: PostgREST.AnyJSON] = [
                    "exit_time": .string(formatter.string(from: visit.exitTime!)),
                    "duration_minutes": .double(Double(visit.durationMinutes ?? 0)),
                    "updated_at": .string(formatter.string(from: Date()))
                ]

                do {
                    try await client
                        .from("location_visits")
                        .update(updateData)
                        .eq("id", value: visit.id.uuidString)
                        .execute()

                    print("🗑️ Closed: \(visit.id.uuidString) (entry: \(visit.entryTime), duration: \(visit.durationMinutes ?? 0)min)")
                    closedCount += 1
                } catch {
                    print("❌ Failed to close visit \(visit.id.uuidString): \(error)")
                }
            }

            print("🗑️ Successfully closed: \(closedCount)/\(staleVisits.count) visits")
            print("🗑️ Deleted short visits: \(deletedCount)")
            print("🗑️ ==================================================\n")
        } catch {
            print("❌ Error cleanup incomplete visits: \(error)")
        }
    }

    func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        print("🔍 saveVisitToSupabase called - checking user...")
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user ID, skipping Supabase visit save")
            return
        }

        print("👤 Current user found: \(user.id.uuidString)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // FIXED: Include session_id, confidence_score, merge_reason which were missing
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

        print("📤 Preparing to insert visit into Supabase: \(visitData)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .insert(visitData)
                .execute()

            print("✅ Visit saved to Supabase: \(visit.id.uuidString)")
        } catch {
            print("❌ Error saving visit to Supabase: \(error)")
        }
    }

    private func updateVisitInSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase visit update")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let updateData: [String: PostgREST.AnyJSON] = [
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        do {
            print("💾 Updating visit in Supabase - ID: \(visit.id.uuidString), ExitTime: \(visit.exitTime?.description ?? "nil"), Duration: \(visit.durationMinutes ?? 0)min")

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ VISIT UPDATE SUCCESSFUL - ID: \(visit.id.uuidString)")

            // OPTIMIZATION: Invalidate cached stats for this location
            // so next query fetches fresh data
            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error updating visit in Supabase: \(error)")
        }
    }

    /// Delete a visit from Supabase (used for filtering out short/invalid visits)
    func deleteVisitFromSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase visit delete")
            return
        }

        do {
            print("🗑️ Deleting short visit from Supabase - ID: \(visit.id.uuidString), Duration: \(visit.durationMinutes ?? 0)min")

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .delete()
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ Short visit deleted from Supabase: \(visit.id.uuidString)")

            // Invalidate cache for this location
            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error deleting visit from Supabase: \(error)")
        }
    }

    /// Merges a reopened visit by clearing exit_time and duration_minutes (continuous session)
    // DEPRECATED: Atomic merge operations have been moved to LocationErrorRecoveryService
    // See: LocationErrorRecoveryService.shared.executeAtomicMerge()
    // This ensures all-or-nothing operation preventing race conditions

    /// Auto-complete any active visits if user has moved too far from the location
    func autoCompleteVisitsIfOutOfRange(currentLocation: CLLocation, savedPlaces: [SavedPlace]) async {
        // Check each active visit
        for (placeId, var visit) in activeVisits {
            // Find the location for this visit
            if let place = savedPlaces.first(where: { $0.id == placeId }) {
                // NEW: Use smart radius detection (user override or auto-detect)
                let radius = GeofenceRadiusManager.shared.getRadius(for: place)
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLocation.distance(from: placeLocation)

                // If user has moved beyond geofence radius, auto-complete the visit
                if distance > radius {
                    print("\n🚀 ===== AUTO-COMPLETING VISIT (OUT OF RANGE) =====")
                    print("🚀 Location: \(place.displayName)")
                    print("🚀 Distance from location: \(String(format: "%.1f", distance))m (beyond \(Int(radius))m geofence)")
                    print("🚀 Active visit duration: \(Int(Date().timeIntervalSince(visit.entryTime) / 60)) minutes")
                    print("🚀 ===================================================\n")

                    // Record the exit and remove from active visits
                    visit.recordExit(exitTime: Date())
                    activeVisits.removeValue(forKey: placeId)

                    // FIX: Filter out short visits (< 10 min) - delete instead of update
                    let durationMinutes = visit.durationMinutes ?? 0
                    if durationMinutes < 10 {
                        print("⏭️ VISIT FILTERED OUT (auto-complete): Duration too short (\(durationMinutes) min < 10 min minimum)")
                        await deleteVisitFromSupabase(visit)
                    } else {
                        // Update in Supabase
                        await updateVisitInSupabase(visit)
                    }
                }
            }
        }

        // FALLBACK: Clean up stale visits that have been open for > 4 hours (unlikely to be real)
        // This handles cases where geofence exit events didn't fire
        let staleThreshold: TimeInterval = 4 * 3600 // 4 hours
        let now = Date()

        for (placeId, var visit) in activeVisits {
            let visitDuration = now.timeIntervalSince(visit.entryTime)
            if visitDuration > staleThreshold {
                if let place = savedPlaces.first(where: { $0.id == placeId }) {
                    print("\n⚠️ ===== AUTO-COMPLETING STALE VISIT =====")
                    print("⚠️ Location: \(place.displayName)")
                    print("⚠️ Visit was open for: \(Int(visitDuration / 3600)) hours \(Int((visitDuration.truncatingRemainder(dividingBy: 3600)) / 60)) minutes")
                    print("⚠️ Reason: Geofence exit event likely didn't fire")
                    print("⚠️ ========================================\n")

                    visit.recordExit(exitTime: now)
                    activeVisits.removeValue(forKey: placeId)

                    // FIX: Filter out short visits (< 10 min) - delete instead of update
                    let durationMinutes = visit.durationMinutes ?? 0
                    if durationMinutes < 10 {
                        print("⏭️ VISIT FILTERED OUT (stale cleanup): Duration too short (\(durationMinutes) min < 10 min minimum)")
                        await deleteVisitFromSupabase(visit)
                    } else {
                        await updateVisitInSupabase(visit)
                    }
                }
            }
        }
    }
}
