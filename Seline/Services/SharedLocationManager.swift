import Foundation
import CoreLocation
import WidgetKit

/// Shared CLLocationManager to consolidate multiple location tracking services
/// This prevents redundant location manager instances and reduces battery drain
@MainActor
class SharedLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SharedLocationManager()

    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Delegate registries - services register themselves to receive updates
    private var locationDelegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var authorizationDelegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()

    // CLVisit tracking for accurate departure times
    // Maps location coordinates (rounded to 4 decimals) to CLVisit departure dates
    private var visitDepartureCache: [String: Date] = [:]
    private let visitCacheExpirationHours: TimeInterval = 12 // Keep visits for 12 hours

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Configuration

    /// Configure location manager for background tracking
    func enableBackgroundLocationTracking(_ enabled: Bool) {
        locationManager.allowsBackgroundLocationUpdates = enabled

        if enabled {
            locationManager.startUpdatingLocation()
            // DEBUG: Commented out to reduce console spam
            // print("📍 Background location tracking enabled")
        } else {
            locationManager.stopUpdatingLocation()
            print("📍 Background location tracking disabled")
        }
    }

    // MARK: - PERFORMANCE FIX: Proactive Location Updates

    /// Temporarily increase location update accuracy when approaching saved locations
    /// This helps ensure geofences trigger promptly by waking up the app more frequently
    func enableHighAccuracyMode() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10 // Update every 10 meters
        print("🎯 High accuracy mode enabled (approaching saved location)")
    }

    /// Return to normal accuracy mode
    func disableHighAccuracyMode() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        print("📍 Returned to normal accuracy mode")
    }

    /// Wait for a valid location update (with timeout)
    /// Returns current location immediately if available, otherwise waits for next update
    func waitForLocation(timeout: TimeInterval = 10.0) async -> CLLocation? {
        // If we already have a recent location, return it immediately
        if let location = currentLocation {
            let locationAge = abs(location.timestamp.timeIntervalSinceNow)
            if locationAge < 30 { // Location less than 30 seconds old
                print("📍 Using cached location (age: \(String(format: "%.1f", locationAge))s)")
                return location
            }
        }

        // Request fresh location update
        print("📍 Requesting fresh location...")
        locationManager.startUpdatingLocation()

        // Wait for location update with timeout
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if let location = currentLocation {
                let locationAge = abs(location.timestamp.timeIntervalSinceNow)
                if locationAge < 5 { // Very recent location
                    print("📍 Got fresh location (accuracy: ±\(String(format: "%.0f", location.horizontalAccuracy))m)")
                    return location
                }
            }
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Timeout - return whatever we have (might be nil or old)
        if let location = currentLocation {
            print("⚠️ Location timeout - using stale location")
            return location
        } else {
            print("❌ Location timeout - no location available")
            return nil
        }
    }

    /// Request location permission (Always or WhenInUse)
    func requestLocationPermission(alwaysAuthorization: Bool = false) {
        if alwaysAuthorization {
            locationManager.requestAlwaysAuthorization()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Request always authorization for background tracking
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Start/stop location updates
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
        print("📍 Location updates started")
    }

    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        print("📍 Location updates stopped")
    }

    // MARK: - Monitoring Geofences

    /// Add a geofence region to monitor
    func startMonitoring(region: CLCircularRegion) {
        if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            locationManager.startMonitoring(for: region)
        }
    }

    /// Stop monitoring a geofence region
    func stopMonitoring(region: CLCircularRegion) {
        locationManager.stopMonitoring(for: region)
    }

    // MARK: - CLVisit Monitoring (for accurate departure times)

    /// Start monitoring visits for accurate departure time tracking
    func startVisitMonitoring() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringVisits()
            print("🔍 CLVisit monitoring started")
        } else {
            print("⚠️ Visit monitoring not available on this device")
        }
    }

    // MARK: - Significant Location Change Monitoring (PERFORMANCE FIX)

    /// Start monitoring significant location changes (500m+ movements)
    /// This provides a fallback mechanism when geofences don't trigger quickly
    /// Uses minimal battery while providing faster detection than geofences alone
    func startSignificantLocationChangeMonitoring() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
            print("📍 Significant location change monitoring started (battery-efficient fallback)")
        } else {
            print("⚠️ Significant location change monitoring not available")
        }
    }

    /// Stop monitoring significant location changes
    func stopSignificantLocationChangeMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        print("📍 Significant location change monitoring stopped")
    }

    /// Stop monitoring visits
    func stopVisitMonitoring() {
        locationManager.stopMonitoringVisits()
        print("🔍 CLVisit monitoring stopped")
    }

    /// Get cached departure time for a location (if available)
    /// - Parameter coordinate: The coordinate to check
    /// - Returns: The departure date if found in cache, nil otherwise
    func getCachedDepartureTime(near coordinate: CLLocationCoordinate2D, within meters: Double = 100) -> Date? {
        // Check cache for nearby departures
        let currentTime = Date()

        // Clean up expired entries first
        visitDepartureCache = visitDepartureCache.filter { _, departureDate in
            currentTime.timeIntervalSince(departureDate) < (visitCacheExpirationHours * 3600)
        }

        // Search for nearby cached departures
        for (cacheKey, departureDate) in visitDepartureCache {
            let components = cacheKey.split(separator: ",")
            guard components.count == 2,
                  let cachedLat = Double(components[0]),
                  let cachedLon = Double(components[1]) else {
                continue
            }

            let cachedLocation = CLLocation(latitude: cachedLat, longitude: cachedLon)
            let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = cachedLocation.distance(from: targetLocation)

            if distance <= meters {
                print("✅ Found cached departure time: \(departureDate) (distance: \(String(format: "%.0f", distance))m)")
                return departureDate
            }
        }

        return nil
    }

    /// Helper to create cache key from coordinate
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // Round to 4 decimal places (~11m precision)
        let lat = String(format: "%.4f", coordinate.latitude)
        let lon = String(format: "%.4f", coordinate.longitude)
        return "\(lat),\(lon)"
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latestLocation = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = latestLocation
            self.notifyLocationDelegates(latestLocation)
            
            // CRITICAL FIX: On every location update, check if user entered/exited any saved locations
            // This helps catch geofence events that iOS may have delayed
            await self.checkLocationAgainstSavedPlaces(latestLocation)
        }
    }
    
    /// Check current location against saved places to catch missed geofence events
    /// This runs on every location update to provide faster detection than iOS geofencing alone
    private func checkLocationAgainstSavedPlaces(_ location: CLLocation) async {
        let savedPlaces = LocationsManager.shared.savedPlaces
        guard !savedPlaces.isEmpty else { return }
        
        // Only check if accuracy is reasonable
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 else {
            return
        }
        
        let geofenceManager = GeofenceManager.shared
        
        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = location.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)
            
            let isInside = distance <= radius
            let hasActiveVisit = geofenceManager.getActiveVisit(for: place.id) != nil
            
            // Detect missed entry
            if isInside && !hasActiveVisit {
                // Check speed - ignore if moving fast (passing by)
                if location.speed > 0 && location.speed > 5.5 { // > 20 km/h
                    continue
                }
                
                print("📍 Location update detected user inside \(place.displayName) - triggering entry check")
                
                // Create a synthetic geofence entry
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                    radius: radius,
                    identifier: place.id.uuidString
                )
                await geofenceManager.handleGeofenceEntry(region: region)
                
                // Only handle one at a time
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("❌ Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            // Notify GeofenceManager of authorization change
            GeofenceManager.shared.handleAuthorizationChange(manager.authorizationStatus)
            self.notifyAuthorizationDelegates(manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        print("🚨🚨🚨 GEOFENCE ENTRY DETECTED BY iOS 🚨🚨🚨")
        print("   Region: \(region.identifier)")
        print("   App was woken in background!")
        
        // IMMEDIATE: Refresh widgets as soon as iOS detects location change
        // This ensures widget updates even before full visit processing completes
        WidgetCenter.shared.reloadAllTimelines()
        print("   🔄 Widget refresh triggered immediately!")
        
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor in
            self.notifyGeofenceEntry(region: circularRegion)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        print("🚨🚨🚨 GEOFENCE EXIT DETECTED BY iOS 🚨🚨🚨")
        print("   Region: \(region.identifier)")
        print("   App was woken in background!")
        
        // IMMEDIATE: Refresh widgets as soon as iOS detects location change
        // This clears the current location from widget ASAP
        WidgetCenter.shared.reloadAllTimelines()
        print("   🔄 Widget refresh triggered immediately!")
        
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor in
            self.notifyGeofenceExit(region: circularRegion)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didVisit visit: CLVisit
    ) {
        Task { @MainActor in
            await self.handleCLVisit(visit)
        }
    }

    // MARK: - CLVisit Handling

    private func handleCLVisit(_ visit: CLVisit) async {
        // Only process departures (not arrivals)
        let departureDate = visit.departureDate

        // CLVisit uses distantFuture for ongoing visits (no departure yet)
        if departureDate == Date.distantFuture {
            print("🔍 CLVisit: User arrived at location (no departure yet)")
            return
        }

        // Cache the departure time
        let key = cacheKey(for: visit.coordinate)
        visitDepartureCache[key] = departureDate

        print("🔍 CLVisit: User departed at \(departureDate)")
        print("   Coordinate: (\(visit.coordinate.latitude), \(visit.coordinate.longitude))")
        print("   Accuracy: ±\(String(format: "%.0f", visit.horizontalAccuracy))m")
        print("   Cached for future recovery")
    }

    // MARK: - Delegate Notification (for future service integration)

    private func notifyLocationDelegates(_ location: CLLocation) {
        // For now, we publish via @Published currentLocation
        // Services can observe this using Combine if needed
    }

    private func notifyAuthorizationDelegates(_ status: CLAuthorizationStatus) {
        // For now, we publish via @Published authorizationStatus
        // Services can observe this using Combine if needed
    }

    private func notifyGeofenceEntry(region: CLCircularRegion) {
        // Delegate to GeofenceManager for actual handling
        // This maintains separation of concerns
        Task {
            await GeofenceManager.shared.handleGeofenceEntry(region: region)
        }
    }

    private func notifyGeofenceExit(region: CLCircularRegion) {
        // Delegate to GeofenceManager for actual handling
        Task {
            await GeofenceManager.shared.handleGeofenceExit(region: region)
        }
    }
}
