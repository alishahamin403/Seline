import Foundation
import CoreLocation
import UIKit

@MainActor
class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var locationName: String = "Unknown Location"
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    static let shared = LocationService()

    // App lifecycle tracking
    private var appIsInForeground = true

    // Debouncing for location updates
    private var pendingLocationDebounceTask: Task<Void, Never>?
    private var lastPublishedLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 50 // Increased from 10m to reduce frequency

        // Listen for app lifecycle changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appWillEnterForeground() {
        appIsInForeground = true
        print("📱 App entered foreground - resuming location updates")
        startLocationUpdates()
    }

    @objc private func appDidEnterBackground() {
        appIsInForeground = false
        print("📱 App entered background - stopping location updates")
        stopLocationUpdates()
    }

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable in Settings."
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        @unknown default:
            break
        }
    }

    private func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }

        isLoading = true
        locationManager.startUpdatingLocation()
    }

    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }

    func refreshLocation() {
        startLocationUpdates()
    }

    private func reverseGeocode(location: CLLocation) {
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    self.errorMessage = "Failed to get location name: \(error.localizedDescription)"
                    return
                }

                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? ""
                    let state = placemark.administrativeArea ?? ""
                    let country = placemark.country ?? ""

                    if !city.isEmpty && !state.isEmpty {
                        self.locationName = "\(city), \(state)"
                    } else if !city.isEmpty {
                        self.locationName = city
                    } else if !state.isEmpty && !country.isEmpty {
                        self.locationName = "\(state), \(country)"
                    } else {
                        self.locationName = "Current Location"
                    }
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }

            // Only process if app is in foreground
            guard self.appIsInForeground else {
                print("📍 Location update ignored - app is in background")
                return
            }

            // Only update if the location is recent and accurate
            let age = abs(location.timestamp.timeIntervalSinceNow)
            if age < 5.0 && location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 {
                // Debounce location updates - wait 500ms before publishing
                self.pendingLocationDebounceTask?.cancel()
                self.pendingLocationDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                    await MainActor.run {
                        // Check if location has significantly changed
                        let hasSignificantChange = self.lastPublishedLocation == nil ||
                            location.distance(from: self.lastPublishedLocation!) > 50 // More than 50m change

                        if hasSignificantChange {
                            self.currentLocation = location
                            self.lastPublishedLocation = location
                            self.isLoading = false
                            self.errorMessage = nil

                            // Reverse geocode to get location name
                            self.reverseGeocode(location: location)

                            print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: \(location.horizontalAccuracy)m)")
                        } else {
                            print("📍 Location received but no significant change (< 50m)")
                        }
                    }
                }
            } else {
                print("⚠️ Ignoring inaccurate or stale location (age: \(age)s, accuracy: \(location.horizontalAccuracy)m)")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.errorMessage = "Location error: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startLocationUpdates()
            case .denied, .restricted:
                self.errorMessage = "Location access denied. Please enable in Settings."
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}