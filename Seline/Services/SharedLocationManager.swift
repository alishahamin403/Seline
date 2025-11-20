import Foundation
import CoreLocation

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
            print("📍 Background location tracking enabled")
        } else {
            locationManager.stopUpdatingLocation()
            print("📍 Background location tracking disabled")
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

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latestLocation = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = latestLocation
            self.notifyLocationDelegates(latestLocation)
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
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor in
            self.notifyGeofenceEntry(region: circularRegion)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor in
            self.notifyGeofenceExit(region: circularRegion)
        }
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
