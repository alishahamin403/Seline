import Foundation
import CoreLocation
import PostgREST
import WidgetKit

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
    var sessionId: UUID? // Groups related visits (app restart, GPS loss)
    var confidenceScore: Double? // 1.0 (certain), 0.95, 0.85 (app restart/GPS)
    var mergeReason: String? // "app_restart", "gps_reconnect", "quick_return"

    // ENHANCEMENT: Advanced tracking fields
    var signalDrops: Int? // Number of GPS signal drops during visit
    var motionValidated: Bool? // Whether motion sensors validated stationary behavior
    var stationaryPercentage: Double? // Percentage of time user was stationary
    var wifiMatched: Bool? // Whether WiFi networks matched known fingerprints
    var isOutlier: Bool? // Whether visit is a statistical outlier
    var isCommuteStop: Bool? // Whether visit is a brief stop during commute
    var semanticValid: Bool? // Whether visit makes semantic sense
    var visitNotes: String? // User's notes about why they visited (extracted from natural language)

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
        case sessionId = "session_id"
        case confidenceScore = "confidence_score"
        case mergeReason = "merge_reason"

        // Advanced tracking fields
        case signalDrops = "signal_drops"
        case motionValidated = "motion_validated"
        case stationaryPercentage = "stationary_percentage"
        case wifiMatched = "wifi_matched"
        case isOutlier = "is_outlier"
        case isCommuteStop = "is_commute_stop"
        case semanticValid = "semantic_valid"
        case visitNotes = "visit_notes"

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
            signalDrops: nil,
            motionValidated: nil,
            stationaryPercentage: nil,
            wifiMatched: nil,
            isOutlier: nil,
            isCommuteStop: nil,
            semanticValid: nil,
            visitNotes: nil,
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
    /// CRITICAL: Sets merge_reason to "midnight_split_part1" and "midnight_split_part2" for proper tracking
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
        visit1.mergeReason = "midnight_split_part1" // CRITICAL: Tag as midnight split
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
        visit2.mergeReason = "midnight_split_part2" // CRITICAL: Tag as midnight split
        // Use the entry time (midnight) for day/time classification, not exit time
        let entryComponents = calendar.dateComponents([.weekday, .month, .year], from: midnightStart)
        visit2.dayOfWeek = Self.dayOfWeekName(for: entryComponents.weekday ?? 1)
        visit2.timeOfDay = Self.timeOfDayName(for: midnightStart)
        visit2.month = entryComponents.month ?? 1
        visit2.year = entryComponents.year ?? 2024
        visit2.updatedAt = Date()

        return [visit1, visit2]
    }

    static func dayOfWeekName(for dayIndex: Int) -> String {
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
    
    // Track which visits have already received arrival notifications to prevent duplicates
    private var notifiedVisitSessions: Set<UUID> = []
    private let notificationTrackingLock = NSLock()

    @Published var isMonitoring = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let geofenceRadius: CLLocationDistance = 300 // Used for fallback in some contexts (increased from 200m)
    // Note: Smart radius detection is now handled by GeofenceRadiusManager.shared

    // Dynamic geofencing: Track last location where geofences were updated
    // Used to re-evaluate which 20 locations to monitor as user moves around
    private var lastGeofenceUpdateLocation: CLLocation?
    private let geofenceUpdateThreshold: CLLocationDistance = 10000 // 10km - re-evaluate when user moves this far

    private let notificationService = NotificationService.shared

    override init() {
        super.init()
        // Subscribe to shared location manager updates
        authorizationStatus = sharedLocationManager.authorizationStatus
    }

    // MARK: - Thread-Safe Active Visits Management

    /// Thread-safe method to update an active visit
    func updateActiveVisit(_ visit: LocationVisitRecord, for placeId: UUID) {
        activeVisitsLock.lock()
        activeVisits[placeId] = visit
        activeVisitsLock.unlock()
    }

    /// Thread-safe method to remove an active visit
    func removeActiveVisit(for placeId: UUID) {
        activeVisitsLock.lock()
        activeVisits.removeValue(forKey: placeId)
        activeVisitsLock.unlock()
    }

    /// Thread-safe method to get an active visit
    func getActiveVisit(for placeId: UUID) -> LocationVisitRecord? {
        activeVisitsLock.lock()
        let visit = activeVisits[placeId]
        activeVisitsLock.unlock()
        return visit
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
        print("\n🔐 ===== CHECKING LOCATION AUTHORIZATION =====")
        print("🔐 Current status: \(authorizationStatus)")

        switch authorizationStatus {
        case .notDetermined:
            print("❓ Permission not determined - requesting Always authorization...")
            // Request background location permission (Always)
            sharedLocationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("❌ Permission DENIED - background geofencing will NOT work!")
            errorMessage = "Background location access required for visit tracking. Please enable in Settings."
        case .authorizedAlways:
            // CRITICAL FIX: If permission is already granted, immediately set up geofences
            // This ensures background monitoring works even on app launch
            print("✅ Permission GRANTED (Always) - setting up geofences NOW...")
            sharedLocationManager.enableBackgroundLocationTracking(true)
            setupGeofences(for: LocationsManager.shared.savedPlaces)
        case .authorizedWhenInUse:
            print("⚠️ Permission is 'When In Use' - requesting 'Always' for background tracking...")
            sharedLocationManager.requestAlwaysAuthorization()
        @unknown default:
            print("⚠️ Unknown authorization status")
            break
        }
        print("🔐 ==========================================\n")
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

        // iOS LIMIT: Maximum 20 monitored regions per app
        // SMART APPROACH: Prioritize the 20 closest locations to current position
        var locationsToTrack = places
        if places.count > 20 {
            print("📍 You have \(places.count) saved locations - iOS limits monitoring to 20")

            // Get current location to determine which 20 to monitor
            if let currentLocation = sharedLocationManager.currentLocation {
                // Sort by distance from current location (closest first)
                let sortedByDistance = places.map { place -> (place: SavedPlace, distance: CLLocationDistance) in
                    let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                    let distance = currentLocation.distance(from: placeLocation)
                    return (place: place, distance: distance)
                }.sorted { $0.distance < $1.distance }

                // Take the 20 closest
                locationsToTrack = sortedByDistance.prefix(20).map { $0.place }

                let maxDistance = sortedByDistance[19].distance / 1000 // Convert to km
                print("📍 Smart geofencing: Monitoring 20 closest locations (within \(String(format: "%.1f", maxDistance))km)")

                // Store last update location for periodic re-evaluation
                lastGeofenceUpdateLocation = currentLocation
            } else {
                print("⚠️ No current location - monitoring first 20 locations")
                locationsToTrack = Array(places.prefix(20))
            }
        }

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

            print("📍 Registered geofence: \(place.displayName) (radius: \(Int(radius))m)")
        }

        if !locationsToTrack.isEmpty {
            isMonitoring = true
            print("✅ GEOFENCES SETUP COMPLETE - Now monitoring \(locationsToTrack.count) locations")
            print("   Background location: ENABLED")
            print("   Authorization: \(authorizationStatus)")

            // PERFORMANCE FIX: Start significant location change monitoring as fallback
            // This triggers when user moves 500m+, providing faster detection if geofences are delayed
            sharedLocationManager.startSignificantLocationChangeMonitoring()
        }
        print("🔍 ===================================\n")
    }

    /// Check if geofences need updating based on user movement
    /// Called periodically by LocationBackgroundValidationService
    func updateGeofencesIfNeeded(currentLocation: CLLocation, savedPlaces: [SavedPlace]) {
        // Skip if we don't have many locations (no need for dynamic updates)
        guard savedPlaces.count > 20 else { return }

        // Check if we've moved far enough to warrant re-evaluation
        if let lastLocation = lastGeofenceUpdateLocation {
            let distanceMoved = currentLocation.distance(from: lastLocation)

            // Only update if moved more than 10km
            if distanceMoved > geofenceUpdateThreshold {
                print("📍 User moved \(String(format: "%.1f", distanceMoved/1000))km - updating geofences")
                setupGeofences(for: savedPlaces)
            }
        } else {
            // First time - set up geofences
            setupGeofences(for: savedPlaces)
        }
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
        sharedLocationManager.stopSignificantLocationChangeMonitoring() // PERFORMANCE FIX: Stop fallback monitoring
        isMonitoring = false
    }

    /// Debug function: Print status of all monitored geofences
    func printGeofenceStatus() {
        print("\n🔍 ===== GEOFENCE STATUS DEBUG =====")
        print("📍 Authorization: \(authorizationStatus)")
        print("📍 Total monitored regions: \(monitoredRegions.count)")
        print("📍 Active visits: \(activeVisits.count)")

        if monitoredRegions.isEmpty {
            print("⚠️ WARNING: No geofences are being monitored!")
        } else {
            print("\n📋 Monitored Geofences:")
            let savedPlaces = LocationsManager.shared.savedPlaces
            for (placeId, region) in monitoredRegions {
                if let place = savedPlaces.first(where: { $0.id.uuidString == placeId }) {
                    print("   ✅ \(place.displayName) - radius: \(String(format: "%.0f", region.radius))m")
                } else {
                    print("   ⚠️ Unknown place: \(placeId)")
                }
            }
        }

        if !activeVisits.isEmpty {
            print("\n🏠 Active Visits:")
            let savedPlaces = LocationsManager.shared.savedPlaces
            for (placeId, visit) in activeVisits {
                if let place = savedPlaces.first(where: { $0.id == placeId }) {
                    let duration = Date().timeIntervalSince(visit.entryTime) / 60
                    print("   📍 \(place.displayName) - duration: \(String(format: "%.0f", duration)) min")
                } else {
                    print("   ⚠️ Unknown place: \(placeId)")
                }
            }
        }

        if let currentLocation = sharedLocationManager.currentLocation {
            print("\n📍 Current Location:")
            print("   Lat: \(currentLocation.coordinate.latitude)")
            print("   Lon: \(currentLocation.coordinate.longitude)")
            print("   Accuracy: ±\(String(format: "%.0f", currentLocation.horizontalAccuracy))m")
            print("   Age: \(String(format: "%.1f", abs(currentLocation.timestamp.timeIntervalSinceNow)))s")
        } else {
            print("\n⚠️ No current location available")
        }

        print("🔍 =====================================\n")
    }

    /// Update background location tracking based on user preference
    /// NOTE: This is deprecated - background tracking must ALWAYS be enabled for geofencing
    /// Keeping for backward compatibility but it now always enables background tracking
    func updateBackgroundLocationTracking(enabled: Bool) {
        // CRITICAL: Always enable background tracking for geofencing to work
        // Ignore the 'enabled' parameter - geofencing requires background updates
        sharedLocationManager.enableBackgroundLocationTracking(true)
        print("⚠️ Background location tracking forced ON for geofencing (ignoring user preference)")
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

            // CRITICAL: Check if we already have an active visit for this place
            // This prevents duplicate visit creation and duplicate notifications
            activeVisitsLock.lock()
            let hasActiveVisit = self.activeVisits[placeId] != nil
            activeVisitsLock.unlock()
            
            if hasActiveVisit {
                print("ℹ️ Active visit already exists for place: \(placeId), skipping duplicate entry")
                return
            }

            // Check location accuracy - reject entry if accuracy is poor (> 30m)
            guard let currentLocation = self.sharedLocationManager.currentLocation else {
                print("⚠️ No recent location data available, cannot determine best-match location")
                return
            }

            let horizontalAccuracy = currentLocation.horizontalAccuracy
            let verticalAccuracy = currentLocation.verticalAccuracy

            // ENHANCEMENT: Track signal quality
            SignalQualityTracker.shared.recordLocationUpdate(accuracy: horizontalAccuracy, for: placeId)

            // TALL BUILDING FIX: Get place to check if it's a Work location
            let allPlacesForCheck = LocationsManager.shared.savedPlaces
            let targetPlace = allPlacesForCheck.first(where: { $0.id == placeId })
            let isWorkLocation = targetPlace?.category.lowercased().contains("work") ?? false ||
                                  targetPlace?.category.lowercased().contains("office") ?? false

            // PERFORMANCE FIX: Relaxed accuracy threshold on entry to prevent GPS acquisition delays
            // CRITICAL: We accept entries with lower accuracy, but dwell time validation ensures it's real
            var accuracyThreshold: Double = 65 // Relaxed from 30m to 65m for faster detection

            // Further relax threshold for Work locations (tall buildings, underground parking common)
            if isWorkLocation {
                accuracyThreshold = 100
                print("📍 Work location detected - using very relaxed accuracy threshold: \(Int(accuracyThreshold))m")
            }

            // TALL BUILDING FIX: If vertical accuracy is good but horizontal is poor, it's likely a tall building
            // In tall buildings, GPS struggles with horizontal positioning but vertical can be more reliable
            let inTallBuilding = verticalAccuracy > 0 && verticalAccuracy < 20 && horizontalAccuracy > 30

            if inTallBuilding {
                print("🏢 Tall building detected (vertical: \(String(format: "%.1f", verticalAccuracy))m, horizontal: \(String(format: "%.1f", horizontalAccuracy))m)")
                // For tall buildings, we'll accept the entry but with dwell time validation
                // This gives time to confirm the user is actually at this location
                print("   → Will use dwell time validation to confirm visit")
            } else if horizontalAccuracy > accuracyThreshold {
                print("⚠️ GEOFENCE ENTRY REJECTED: GPS accuracy too low (\(String(format: "%.1f", horizontalAccuracy))m > \(Int(accuracyThreshold))m threshold)")
                print("   → Note: Entry will be retried when GPS improves or after 30s dwell validation")
                SignalQualityTracker.shared.recordLowAccuracy(accuracy: horizontalAccuracy, placeId: placeId)
                return
            } else {
                print("✅ GPS accuracy acceptable: \(String(format: "%.1f", horizontalAccuracy))m (threshold: \(Int(accuracyThreshold))m)")
                if verticalAccuracy > 0 {
                    print("   Vertical accuracy: \(String(format: "%.1f", verticalAccuracy))m")
                }
            }

            // SOLUTION: SPEED-BASED FILTERING
            // Reject geofence entries if user is moving too fast (likely driving/passing by)
            // Speed is in m/s: 5.5 m/s ≈ 20 km/h, 11 m/s ≈ 40 km/h
            let speed = currentLocation.speed // m/s (negative if invalid)
            let maxAllowedSpeed: Double = 5.5 // ~20 km/h (walking/running speed)

            if speed > 0 && speed > maxAllowedSpeed {
                print("⚠️ GEOFENCE ENTRY REJECTED: User moving too fast (\(String(format: "%.1f", speed * 3.6)) km/h > \(String(format: "%.1f", maxAllowedSpeed * 3.6)) km/h)")
                print("   → Likely driving/passing by, not an actual visit")
                return
            } else if speed > 0 {
                print("✅ Speed check passed: \(String(format: "%.1f", speed * 3.6)) km/h (walking/stationary)")
            }

            // SOLUTION 3: BEST-MATCH LOCATION SELECTION WITH WEIGHTED CONFIDENCE
            // Find all nearby locations within their geofence radius and pick the best match
            // IMPROVEMENT: Use weighted scoring that considers distance-to-radius ratio
            // A small store you're clearly inside (10m from center, 60m radius = 83% confidence)
            // beats a large mall where you're near edge (400m from center, 500m radius = 20% confidence)
            let allPlaces = LocationsManager.shared.savedPlaces
            
            struct PlaceMatch {
                let place: SavedPlace
                let distance: CLLocationDistance
                let radius: CLLocationDistance
                let confidenceScore: Double // Higher = better match (1.0 = at center, 0.0 = at edge)
                let penetrationRatio: Double // How deep inside the geofence (0.0 = edge, 1.0 = center)
            }
            
            var nearbyPlaces: [PlaceMatch] = []

            for place in allPlaces {
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLocation.distance(from: placeLocation)
                let radius = GeofenceRadiusManager.shared.getRadius(for: place)

                // Check if we're within this place's geofence
                if distance <= radius {
                    // Calculate how deep inside the geofence we are
                    // penetrationRatio: 1.0 = at center, 0.0 = at edge
                    let penetrationRatio = 1.0 - (distance / radius)
                    
                    // Calculate confidence score
                    // Weight formula: penetration² gives more weight to being near center
                    // Small stores with tight placement score higher
                    let confidenceScore = pow(penetrationRatio, 2)
                    
                    nearbyPlaces.append(PlaceMatch(
                        place: place,
                        distance: distance,
                        radius: radius,
                        confidenceScore: confidenceScore,
                        penetrationRatio: penetrationRatio
                    ))
                }
            }

            // If no places are nearby (shouldn't happen since geofence triggered), bail out
            guard !nearbyPlaces.isEmpty else {
                print("⚠️ No nearby places found despite geofence entry - GPS drift?")
                return
            }

            // Sort by confidence score (highest first), then by distance (closest first) as tiebreaker
            let sortedMatches = nearbyPlaces.sorted { match1, match2 in
                if abs(match1.confidenceScore - match2.confidenceScore) > 0.1 {
                    // Significant confidence difference - use confidence
                    return match1.confidenceScore > match2.confidenceScore
                } else {
                    // Similar confidence - prefer closer distance
                    return match1.distance < match2.distance
                }
            }
            
            let bestMatch = sortedMatches.first!

            // Log all nearby places for debugging
            if nearbyPlaces.count > 1 {
                print("\n🎯 BEST-MATCH SELECTION (Multiple overlapping geofences detected)")
                print("🎯 Using weighted confidence scoring (higher = better match)")
                print("🎯 Nearby places within geofence:")
                for match in sortedMatches {
                    let marker = match.place.id == bestMatch.place.id ? "✅ SELECTED" : "  "
                    let penetrationPct = Int(match.penetrationRatio * 100)
                    let confidencePct = Int(match.confidenceScore * 100)
                    print("   \(marker) \(match.place.displayName): \(String(format: "%.0f", match.distance))m from center (radius: \(Int(match.radius))m, \(penetrationPct)% inside, confidence: \(confidencePct)%)")
                }
                print("🎯 ==========================================\n")
            }

            // Override placeId with the best match
            let bestMatchPlaceId = bestMatch.place.id

            // If the triggered geofence was NOT the best match, we ignore this event
            // (We'll pick it up when the best match's geofence triggers)
            if placeId != bestMatchPlaceId {
                print("⏭️ SKIPPING: Geofence triggered for \(region.identifier) but best match is \(bestMatch.place.displayName)")
                return
            }

            print("✅ BEST-MATCH CONFIRMED: Recording visit for \(bestMatch.place.displayName) (\(String(format: "%.0f", bestMatch.distance))m from center, \(Int(bestMatch.confidenceScore * 100))% confidence)")

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
            // Check if dwell time validation is enabled OR if we detected a tall building
            // PERFORMANCE FIX: Skip dwell validation for trusted locations (Home, Work) for instant entry
            // TALL BUILDING FIX: Force dwell validation for tall buildings even if not globally enabled
            let isTrustedLocation = DwellTimeValidator.shared.shouldSkipDwellValidation(for: bestMatch.place.category)
            let shouldUseDwellValidation = !isTrustedLocation && (DwellTimeValidator.shared.isEnabled || inTallBuilding)

            if isTrustedLocation {
                print("⚡️ TRUSTED LOCATION (\(bestMatch.place.category)) - Skipping dwell validation for instant entry")
            } else if shouldUseDwellValidation {
                // Check if there's already a pending entry
                if DwellTimeValidator.shared.hasPendingEntry(for: bestMatchPlaceId) {
                    print("ℹ️ Pending dwell time validation already exists for place: \(bestMatchPlaceId)")
                    return
                }

                if inTallBuilding {
                    print("🏢 Forcing dwell time validation for tall building scenario")
                }

                // Register pending entry - will create visit after dwell time expires
                DwellTimeValidator.shared.registerPendingEntry(
                    placeId: bestMatchPlaceId,
                    placeName: bestMatch.place.displayName,
                    currentLocation: currentLocation,
                    geofenceRadius: bestMatch.place.customGeofenceRadius ?? GeofenceRadiusManager.shared.getRadius(for: bestMatch.place),
                    locationManager: self.sharedLocationManager
                ) { validatedPlaceId in
                    // This closure is called after dwell time validation passes
                    Task { @MainActor in
                        await self.createVisitAfterDwellValidation(for: validatedPlaceId)
                    }
                }

                print("⏳ Dwell time validation started for \(bestMatch.place.displayName)")
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
                // CRITICAL SAFETY CHECK: Before creating a new visit, explicitly check Supabase
                // for any open visits that might have been missed by merge detection
                // This prevents overwriting existing visits when the app restarts or memory is cleared
                if let existingOpenVisit = await self.findOpenVisitInSupabase(for: placeId, userId: userId) {
                    print("\n⚠️ ===== FOUND EXISTING OPEN VISIT IN SUPABASE =====")
                    print("⚠️ Existing visit ID: \(existingOpenVisit.id)")
                    print("⚠️ Entry time: \(existingOpenVisit.entryTime)")
                    print("⚠️ This visit should have been found by merge detection!")
                    print("⚠️ Merging with existing visit instead of creating new one")
                    print("⚠️ ================================================\n")
                    
                    // Merge with the existing open visit
                    let sessionId = existingOpenVisit.sessionId ?? UUID()
                    if await LocationErrorRecoveryService.shared.executeAtomicMerge(
                        existingOpenVisit,
                        sessionId: sessionId,
                        confidence: 1.0,
                        reason: "recovered_open_visit",
                        geofenceManager: self,
                        sessionManager: LocationSessionManager.shared
                    ) {
                        // Add to merge detection cache
                        MergeDetectionService.shared.cacheClosedVisit(existingOpenVisit)
                        print("✅ Successfully merged with existing open visit")
                    } else {
                        print("❌ Failed to merge with existing open visit - this should not happen")
                    }
                } else {
                    // No existing open visit found - safe to create new one
                    // Create a new visit record with new session
                    let sessionId = UUID()
                    let visit = LocationVisitRecord.create(
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

                    // CRITICAL FIX: Reload widgets so they show the new location immediately
                    // This ensures the widget updates even when the app is in the background
                    WidgetCenter.shared.reloadAllTimelines()
                    print("🔄 Widget timelines reloaded after visit creation")

                    // Send arrival notification with context (only once per visit session)
                    if let place = allPlaces.first(where: { $0.id == placeId }) {
                        // Check if we've already sent a notification for this visit session
                        let sessionId = visit.sessionId ?? UUID()
                        notificationTrackingLock.lock()
                        let alreadyNotified = notifiedVisitSessions.contains(sessionId)
                        if !alreadyNotified {
                            notifiedVisitSessions.insert(sessionId)
                        }
                        notificationTrackingLock.unlock()
                        
                        if !alreadyNotified {
                            Task {
                                await self.sendArrivalNotification(for: place)
                            }
                        } else {
                            print("ℹ️ Arrival notification already sent for visit session: \(sessionId)")
                        }
                    }
                }
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

                // Clean up notification tracking for this visit session
                if let sessionId = visit.sessionId {
                    notificationTrackingLock.lock()
                    notifiedVisitSessions.remove(sessionId)
                    notificationTrackingLock.unlock()
                    print("🧹 Cleaned up notification tracking for session: \(sessionId)")
                }

                let durationMinutes = visit.durationMinutes ?? 0
                let entryTime = visit.entryTime
                let exitTime = visit.exitTime ?? Date()

                // CRITICAL FIX: Cache visit IMMEDIATELY for instant merge detection
                // This must happen BEFORE any async operations (commute detection, etc.)
                // to prevent race condition where user re-enters before caching completes
                MergeDetectionService.shared.cacheClosedVisit(visit)
                print("💾 Visit cached for merge detection (ended at \(exitTime))")

                // Get place details for category (used by commute detection)
                let place = LocationsManager.shared.savedPlaces.first { $0.id == placeId }
                let category = place?.category

                // ENHANCEMENT: Signal quality tracking
                let signalQuality = SignalQualityTracker.shared.getVisitConfidence(from: entryTime, to: exitTime)
                visit.signalDrops = signalQuality.signalDrops

                if signalQuality.confidence < 0.6 {
                    print("⚠️ Signal quality poor: \(signalQuality.signalDrops) drops, confidence: \(String(format: "%.0f%%", signalQuality.confidence * 100))")
                }

                // ENHANCEMENT: Commute detection
                let commuteAnalysis = await CommuteDetectionService.shared.detectCommuteStop(
                    visit: LocationVisitRow(
                        id: visit.id,
                        userId: visit.userId,
                        placeId: placeId,
                        entryTime: entryTime,
                        exitTime: exitTime,
                        durationMinutes: durationMinutes,
                        sessionId: visit.sessionId,
                        dayOfWeek: visit.dayOfWeek,
                        timeOfDay: visit.timeOfDay,
                        month: visit.month,
                        year: visit.year,
                        confidenceScore: visit.confidenceScore,
                        mergeReason: visit.mergeReason,
                        signalDrops: visit.signalDrops,
                        motionValidated: visit.motionValidated,
                        stationaryPercentage: visit.stationaryPercentage,
                        wifiMatched: visit.wifiMatched,
                        isOutlier: visit.isOutlier,
                        isCommuteStop: visit.isCommuteStop,
                        semanticValid: visit.semanticValid,
                        createdAt: visit.createdAt,
                        updatedAt: visit.updatedAt
                    ),
                    category: category
                )

                visit.isCommuteStop = commuteAnalysis.isCommuteStop

                if commuteAnalysis.isCommuteStop && commuteAnalysis.confidence >= 0.8 {
                    print("🚗 COMMUTE STOP DETECTED: \(commuteAnalysis.reason) (confidence: \(String(format: "%.0f%%", commuteAnalysis.confidence * 100)))")
                    print("⏭️ VISIT FILTERED OUT: Brief stop during commute")
                    await self.deleteVisitFromSupabase(visit)
                    // NOTE: Visit remains in cache but deleted from DB - merge detection will fail
                    // when querying Supabase, which is correct behavior for filtered visits
                    return
                }

                // NOTE: Visit already cached at line 790 for immediate merge detection
                // No need to cache again here - caching happens BEFORE async operations

                // Check if visit spans midnight and split if needed
                let spansMidnight = visit.spansMidnight()
                print("🕐 Checking midnight span: Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")
                let visitsToSave = visit.splitAtMidnightIfNeeded()

                if visitsToSave.count > 1 {
                    print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
                    
                    // IDEMPOTENCY CHECK: Before creating split visits, check if they already exist
                    let existingSplits = await checkForExistingSplitVisits(
                        placeId: placeId,
                        entryTime: visit.entryTime,
                        exitTime: visit.exitTime ?? Date()
                    )
                    
                    if !existingSplits.isEmpty {
                        print("⚠️ IDEMPOTENCY: Found \(existingSplits.count) existing split visit(s), skipping duplicate creation")
                        print("   Existing IDs: \(existingSplits.map { $0.id.uuidString })")
                        return
                    }

                    // CRITICAL FIX: Save split visits FIRST, then delete original
                    // This prevents data loss if save fails
                    var savedCount = 0
                    for visitPart in visitsToSave {
                        print("  - \(visitPart.dayOfWeek): \(visitPart.entryTime) to \(visitPart.exitTime?.description ?? "nil") (\(visitPart.durationMinutes ?? 0) min)")
                        await self.saveVisitToSupabase(visitPart)
                        savedCount += 1

                        // ENHANCEMENT: Check if visit is an outlier
                        if let duration = visitPart.durationMinutes {
                            let outlierAnalysis = await OutlierDetectionService.shared.detectOutlier(
                                placeId: placeId,
                                duration: duration,
                                entryTime: visitPart.entryTime
                            )

                            if outlierAnalysis.isOutlier {
                                print("📊 OUTLIER DETECTED: z-score=\(String(format: "%.2f", outlierAnalysis.zScore)), reason=\(outlierAnalysis.reason)")
                                // Flag in database
                                visit.isOutlier = true
                            }
                        }
                    }

                    // Only delete original AFTER all splits are saved
                    if savedCount == visitsToSave.count {
                        print("✅ All \(savedCount) split visits saved, now deleting original")
                        await self.deleteVisitFromSupabase(visit)
                    } else {
                        print("⚠️ Only \(savedCount)/\(visitsToSave.count) splits saved, keeping original as backup")
                    }
                } else {
                    print("✅ Finished tracking visit for place: \(placeId), duration: \(visit.durationMinutes ?? 0) min")

                    // ENHANCEMENT: Check if visit is an outlier
                    if let duration = visit.durationMinutes {
                        let outlierAnalysis = await OutlierDetectionService.shared.detectOutlier(
                            placeId: placeId,
                            duration: duration,
                            entryTime: visit.entryTime
                        )

                        visit.isOutlier = outlierAnalysis.isOutlier

                        if outlierAnalysis.isOutlier {
                            print("📊 OUTLIER DETECTED: z-score=\(String(format: "%.2f", outlierAnalysis.zScore)), reason=\(outlierAnalysis.reason)")
                        }
                    }

                    await self.updateVisitInSupabase(visit)
                }

                // Reload widgets so they reflect the visit has ended
                WidgetCenter.shared.reloadAllTimelines()
                print("🔄 Widget timelines reloaded after visit exit")

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
            // CRITICAL SAFETY CHECK: Before creating a new visit, explicitly check Supabase
            // for any open visits that might have been missed by merge detection
            if let existingOpenVisit = await self.findOpenVisitInSupabase(for: placeId, userId: userId) {
                print("\n⚠️ ===== FOUND EXISTING OPEN VISIT IN SUPABASE (DWELL VALIDATION) =====")
                print("⚠️ Existing visit ID: \(existingOpenVisit.id)")
                print("⚠️ Entry time: \(existingOpenVisit.entryTime)")
                print("⚠️ Merging with existing visit instead of creating new one")
                print("⚠️ ===============================================================\n")
                
                // Merge with the existing open visit
                let sessionId = existingOpenVisit.sessionId ?? UUID()
                if await LocationErrorRecoveryService.shared.executeAtomicMerge(
                    existingOpenVisit,
                    sessionId: sessionId,
                    confidence: 1.0,
                    reason: "recovered_open_visit_dwell",
                    geofenceManager: self,
                    sessionManager: LocationSessionManager.shared
                ) {
                    MergeDetectionService.shared.cacheClosedVisit(existingOpenVisit)
                    print("✅ Successfully merged with existing open visit after dwell validation")
                } else {
                    print("❌ Failed to merge with existing open visit - this should not happen")
                }
            } else {
                // No existing open visit found - safe to create new one
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

                // Reload widgets so they show the new location
                WidgetCenter.shared.reloadAllTimelines()

                print("✅ Visit created after dwell validation: \(placeId)")
            }
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

    /// Find any open visit (exit_time IS NULL) in Supabase for a place
    /// This is a safety check to prevent creating duplicate visits
    /// ENHANCED: Also checks for recently closed visits to catch race conditions
    private func findOpenVisitInSupabase(for placeId: UUID, userId: UUID) async -> LocationVisitRecord? {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // First check for open visits
            let openResponse = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .is("exit_time", value: nil) // Only open visits (no exit time)
                .order("entry_time", ascending: false) // Most recent first
                .limit(1)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let openVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: openResponse.data)

            if let openVisit = openVisits.first {
                print("🔍 Found open visit in Supabase: ID=\(openVisit.id), Entry=\(openVisit.entryTime)")
                return openVisit
            }

            // CRITICAL FIX: Also check for very recent visits (within 2 minutes) to catch duplicates
            // This prevents race conditions where multiple geofence entries create duplicate visits
            let twoMinutesAgo = Date().addingTimeInterval(-120)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let recentResponse = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .gte("entry_time", value: formatter.string(from: twoMinutesAgo))
                .order("entry_time", ascending: false) // Most recent first
                .limit(1)
                .execute()

            let recentVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: recentResponse.data)

            if let recentVisit = recentVisits.first {
                let secondsSinceCreation = Date().timeIntervalSince(recentVisit.entryTime)

                // If the visit was created within the last 30 seconds, it's likely a duplicate
                if secondsSinceCreation < 30 {
                    print("🔍 Found very recent visit in Supabase (likely duplicate): ID=\(recentVisit.id)")
                    print("   Entry=\(recentVisit.entryTime), Created \(String(format: "%.1f", secondsSinceCreation))s ago")
                    return recentVisit
                }
            }

            return nil
        } catch {
            print("❌ Error querying Supabase for open visits: \(error)")
            return nil
        }
    }

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

                    // NEW: Store in MergeDetectionService cache for merge detection (for backgrounded app scenario)
                    MergeDetectionService.shared.cacheClosedVisit(visit)

                    // Check if visit spans midnight and split if needed
                    let spansMidnight = visit.spansMidnight()
                    print("🕐 Checking midnight span (incomplete visit): Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")
                    let visitsToSave = visit.splitAtMidnightIfNeeded()

                    if visitsToSave.count > 1 {
                        print("🌙 MIDNIGHT SPLIT: Visit spans 2 days, splitting into \(visitsToSave.count) records")
                        
                        // IDEMPOTENCY CHECK: Before creating split visits, check if they already exist
                        let existingSplits = await checkForExistingSplitVisits(
                            placeId: placeId,
                            entryTime: visit.entryTime,
                            exitTime: visit.exitTime ?? Date()
                        )
                        
                        if !existingSplits.isEmpty {
                            print("⚠️ IDEMPOTENCY: Found \(existingSplits.count) existing split visit(s), skipping duplicate creation")
                            print("   Existing IDs: \(existingSplits.map { $0.id.uuidString })")
                            return
                        }
                        
                        // Delete the original visit before saving split visits
                        await self.deleteVisitFromSupabase(visit)
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
                    
                    // CRITICAL: Even if visit already has exit time, check if it spans midnight and needs splitting
                    if visit.spansMidnight() {
                        print("🌙 Found completed visit that spans midnight - will be fixed by background task")
                        // Trigger background fix (non-blocking)
                        Task.detached(priority: .utility) {
                            await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
                        }
                    }
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

            // CRITICAL: Always enable background location updates for geofencing to work
            // Geofencing REQUIRES allowsBackgroundLocationUpdates = true to wake app in background
            sharedLocationManager.enableBackgroundLocationTracking(true)

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

        // Start CLVisit monitoring for accurate departure times
        sharedLocationManager.startVisitMonitoring()

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
        print("\n📍 ===== CHECKING IF ALREADY INSIDE A LOCATION =====")

        // CRITICAL FIX: Wait for location to be available (handles app launch race condition)
        guard let currentLocation = await sharedLocationManager.waitForLocation(timeout: 10.0) else {
            print("❌ Could not get current location after 10s timeout")
            print("📍 ===== CHECK FAILED =====\n")
            return
        }

        let savedPlaces = LocationsManager.shared.savedPlaces
        print("📍 Checking against \(savedPlaces.count) saved places...")

        // CRITICAL: First check if we already have ANY active visits from recovery
        activeVisitsLock.lock()
        let existingActiveVisitsCount = activeVisits.count
        activeVisitsLock.unlock()

        if existingActiveVisitsCount > 0 {
            print("ℹ️ Already have \(existingActiveVisitsCount) active visit(s) from recovery - skipping duplicate check")
            print("📍 ===== CHECK COMPLETE =====\n")
            return
        }

        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)

            if distance <= radius {
                print("✅ User is INSIDE: \(place.displayName) (distance: \(String(format: "%.0f", distance))m, radius: \(String(format: "%.0f", radius))m)")

                // Double-check we don't have an active visit (thread safety)
                activeVisitsLock.lock()
                let hasActiveVisit = activeVisits[place.id] != nil
                activeVisitsLock.unlock()

                if hasActiveVisit {
                    print("ℹ️ Already have an active visit for \(place.displayName), skipping")
                    continue
                }

                // CRITICAL SAFETY CHECK: Before creating a new visit, explicitly check Supabase
                // for any open visits that might exist from a previous session
                if let existingOpenVisit = await self.findOpenVisitInSupabase(for: place.id, userId: userId) {
                    print("\n⚠️ ===== FOUND EXISTING OPEN VISIT IN SUPABASE (APP LAUNCH) =====")
                    print("⚠️ Existing visit ID: \(existingOpenVisit.id)")
                    print("⚠️ Entry time: \(existingOpenVisit.entryTime)")
                    print("⚠️ Restoring existing visit instead of creating new one")
                    print("⚠️ ===========================================================\n")
                    
                    // Restore the existing open visit to memory
                    activeVisitsLock.lock()
                    activeVisits[place.id] = existingOpenVisit
                    activeVisitsLock.unlock()
                    
                    // Add to session manager
                    if let sessionId = existingOpenVisit.sessionId {
                        LocationSessionManager.shared.addVisitToSession(sessionId, visitRecord: existingOpenVisit)
                    }
                    
                    print("✅ Restored existing open visit for \(place.displayName)")
                } else {
                    // No existing open visit found - safe to create new one
                    // Create a new visit since user is inside but no active visit exists
                    print("📝 Creating new visit for \(place.displayName) (user was already inside)")

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
                }

                print("✅ Created visit for \(place.displayName)")

                // Notify that visits have been updated so UI can refresh
                NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)

                // Reload widgets so they show the new location
                WidgetCenter.shared.reloadAllTimelines()

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
            }
        }

        print("📍 ===== CHECK COMPLETE =====\n")

        // Print debug status to help diagnose issues
        printGeofenceStatus()
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
            // Custom date decoder to handle both ISO8601 and PostgreSQL timestamp formats
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Try ISO8601 with fractional seconds first
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso8601Formatter.date(from: dateString) {
                    return date
                }

                // Try ISO8601 without fractional seconds
                iso8601Formatter.formatOptions = [.withInternetDateTime]
                if let date = iso8601Formatter.date(from: dateString) {
                    return date
                }

                // Try PostgreSQL timestamp format: "YYYY-MM-DD HH:MM:SS"
                let postgresFormatter = DateFormatter()
                postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                postgresFormatter.timeZone = TimeZone(identifier: "UTC")
                if let date = postgresFormatter.date(from: dateString) {
                    return date
                }

                // Try PostgreSQL timestamp with fractional seconds: "YYYY-MM-DD HH:MM:SS.ffffff"
                postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
                if let date = postgresFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
            }

            let allOldVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Filter for incomplete visits (exit_time = nil)
            let staleVisits = allOldVisits.filter { $0.exitTime == nil }

            print("🗑️ Found \(staleVisits.count) incomplete visits to close")

            var closedCount = 0
            var deletedCount = 0
            // Close each stale visit by setting exit_time = now and duration
            for var visit in staleVisits {
                visit.recordExit(exitTime: Date())

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

        // CRITICAL: Check if visit spans midnight BEFORE saving
        // This ensures NO midnight-spanning visits are ever saved to the database
        if let exitTime = visit.exitTime, visit.spansMidnight() {
            print("🌙 MIDNIGHT SPLIT in saveVisitToSupabase: Visit spans midnight, splitting before save")
            let visitsToSave = visit.splitAtMidnightIfNeeded()
            
            if visitsToSave.count > 1 {
                // Save each split visit separately
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
    /// This is called after midnight splitting is done
    private func saveVisitToSupabaseDirectly(_ visit: LocationVisitRecord) async {
        // AUTO-DELETE: Skip saving visits under 2 minutes (likely false positives)
        // Only check if visit is complete (has exit_time and duration)
        if let exitTime = visit.exitTime, let durationMinutes = visit.durationMinutes, durationMinutes < 2 {
            print("🗑️ Skipping save for short visit: \(visit.id.uuidString) (duration: \(durationMinutes) min < 2 min)")
            return
        }
        
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

        print("📤 Preparing to insert visit into Supabase: \(visit.id.uuidString)")

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

        // CRITICAL: Check if visit spans midnight and needs to be split
        let spansMidnight = visit.spansMidnight()
        print("🕐 Checking midnight span (update): Entry=\(visit.entryTime), Exit=\(visit.exitTime?.description ?? "nil"), Spans=\(spansMidnight)")

        let visitsToSave = visit.splitAtMidnightIfNeeded()

        if visitsToSave.count > 1 {
            print("🌙 MIDNIGHT SPLIT in updateVisit: Splitting into \(visitsToSave.count) records")
            
            // IDEMPOTENCY CHECK: Before creating split visits, check if they already exist
            let existingSplits = await checkForExistingSplitVisits(
                placeId: visit.savedPlaceId,
                entryTime: visit.entryTime,
                exitTime: visit.exitTime ?? Date()
            )
            
            if !existingSplits.isEmpty {
                // Verify splits cover the expected time range before deleting original
                let expectedDuration = visit.durationMinutes ?? 0
                let splitsDuration = existingSplits.compactMap { $0.durationMinutes }.reduce(0, +)
                let durationMatch = abs(expectedDuration - splitsDuration) < 5 // 5 min tolerance

                if durationMatch && existingSplits.count >= 2 {
                    print("⚠️ IDEMPOTENCY: Found \(existingSplits.count) valid split visit(s)")
                    print("   Existing IDs: \(existingSplits.map { $0.id.uuidString })")
                    print("   Duration match: \(splitsDuration)min vs expected \(expectedDuration)min")
                    print("🧹 CLEANUP: Deleting orphaned original visit...")
                    await deleteVisitFromSupabase(visit)
                } else {
                    print("⚠️ Splits exist but incomplete (duration: \(splitsDuration) vs \(expectedDuration)), keeping original")
                }
                return
            }

            // CRITICAL FIX: Save split parts FIRST, then delete original
            var savedCount = 0
            for part in visitsToSave {
                await saveVisitToSupabase(part)
                savedCount += 1
            }

            // Only delete original after all splits are confirmed saved
            if savedCount == visitsToSave.count {
                print("✅ All \(savedCount) split visits saved, deleting original")
                await deleteVisitFromSupabase(visit)
            } else {
                print("⚠️ Only \(savedCount)/\(visitsToSave.count) splits saved, keeping original")
            }
            return
        }

        // AUTO-DELETE: Delete visits under 2 minutes instead of updating them
        // Only check if visit is complete (has exit_time and duration)
        if let exitTime = visit.exitTime, let durationMinutes = visit.durationMinutes, durationMinutes < 2 {
            print("🗑️ Auto-deleting short visit instead of updating: \(visit.id.uuidString) (duration: \(durationMinutes) min < 2 min)")
            await deleteVisitFromSupabase(visit)
            return
        }

        // No split needed - proceed with normal update
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

    /// Update visit notes in Supabase
    func updateVisitNotesInSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase visit notes update")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let updateData: [String: PostgREST.AnyJSON] = [
            "visit_notes": visit.visitNotes != nil ? .string(visit.visitNotes!) : .null,
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        do {
            print("📝 Updating visit notes in Supabase - ID: \(visit.id.uuidString), Notes: \(visit.visitNotes ?? "nil")")

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ Visit notes updated in Supabase: \(visit.id.uuidString)")
        } catch {
            print("❌ Error updating visit notes in Supabase: \(error)")
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

    /// Fetch recent visits for a user from Supabase
    func fetchRecentVisits(userId: UUID, since: Date, limit: Int = 10) async -> [LocationVisitRecord] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Format date for PostgreSQL
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let sinceString = formatter.string(from: since)

            let response: [LocationVisitRecord] = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: sinceString)
                .order("entry_time", ascending: false)
                .limit(limit)
                .execute()
                .value

            return response
        } catch {
            print("❌ Error fetching recent visits from Supabase: \(error)")
            return []
        }
    }

    /// Check if midnight-split visits already exist for the given time range
    /// This prevents duplicate splits when the function is called multiple times
    private func checkForExistingSplitVisits(placeId: UUID, entryTime: Date, exitTime: Date) async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let calendar = Calendar.current
            
            // Calculate the midnight boundary
            let midnightStart = calendar.startOfDay(for: exitTime)
            
            // Format dates for PostgreSQL
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let midnightString = formatter.string(from: midnightStart)
            
            // Query for visits that:
            // 1. Are at the same place
            // 2. Start at midnight (12:00 AM)
            // 3. Have merge_reason containing "midnight_split"
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .eq("entry_time", value: midnightString)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            
            // Filter for midnight splits
            let splitVisits = visits.filter { visit in
                visit.mergeReason?.contains("midnight_split") == true
            }
            
            return splitVisits
        } catch {
            print("❌ Error checking for existing split visits: \(error)")
            return []
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

                    // Update in Supabase
                    await updateVisitInSupabase(visit)
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

                    // Update visit in Supabase
                    await updateVisitInSupabase(visit)
                }
            }
        }
    }

    // MARK: - Arrival Notifications

    /// Send arrival notification with contextual information
    private func sendArrivalNotification(for place: SavedPlace) async {
        // Get the active visit to use its sessionId for notification identifier
        activeVisitsLock.lock()
        let visit = self.activeVisits[place.id]
        let sessionId = visit?.sessionId ?? UUID()
        activeVisitsLock.unlock()
        
        // Get unread email count
        let emailService = EmailService.shared
        let unreadEmailCount = emailService.inboxEmails.filter { !$0.isRead }.count

        // Get today's events count (filtered by user email)
        let calendarService = CalendarSyncService.shared
        let userEmail = await MainActor.run { AuthenticationManager.shared.currentUser?.profile?.email }
        let todaysEvents = await calendarService.fetchCalendarEventsFromCurrentMonthOnwards(userEmail: userEmail)
        let calendar = Calendar.current
        let eventsToday = todaysEvents.filter { event in
            calendar.isDateInToday(event.startDate)
        }.count

        // Get weather info (optional - if weather service is available)
        var weatherInfo: String? = nil
        // TODO: Integrate with WeatherService if needed

        // Send the notification with sessionId-based identifier for deduplication
        await notificationService.scheduleArrivalNotification(
            locationName: place.displayName,
            unreadEmailCount: unreadEmailCount,
            upcomingEventsCount: eventsToday,
            weatherInfo: weatherInfo,
            sessionId: sessionId
        )
    }
    
    // MARK: - People Connection Methods
    
    /// Link people to a visit - convenience method that delegates to PeopleManager
    /// - Parameters:
    ///   - visitId: The ID of the visit
    ///   - personIds: Array of person IDs to link to the visit
    func linkPeopleToVisit(visitId: UUID, personIds: [UUID]) async {
        await PeopleManager.shared.linkPeopleToVisit(visitId: visitId, personIds: personIds)
    }
    
    /// Get people associated with a visit - convenience method that delegates to PeopleManager
    /// - Parameter visitId: The ID of the visit
    /// - Returns: Array of Person objects associated with the visit
    func getPeopleForVisit(visitId: UUID) async -> [Person] {
        return await PeopleManager.shared.getPeopleForVisit(visitId: visitId)
    }
    
    /// Get all visits that a person was part of
    /// - Parameter personId: The ID of the person
    /// - Returns: Array of visit UUIDs
    func getVisitsForPerson(personId: UUID) async -> [UUID] {
        return await PeopleManager.shared.getVisitIdsForPerson(personId: personId)
    }
}
