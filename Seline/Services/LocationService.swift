import Foundation
import CoreLocation

@MainActor
class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var locationName: String = "Unknown Location"
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    static let shared = LocationService()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        locationManager.distanceFilter = 1000 // Update every 1km
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

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
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

            self.currentLocation = location
            self.isLoading = false
            self.errorMessage = nil

            // Reverse geocode to get location name
            self.reverseGeocode(location: location)

            // Stop updating after getting the first location
            self.stopLocationUpdates()
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