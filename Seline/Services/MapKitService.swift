import Foundation
import MapKit
import CoreLocation

class MapKitService: NSObject, ObservableObject {
    static let shared = MapKitService()

    @Published var location1ETA: String?
    @Published var location2ETA: String?
    @Published var location3ETA: String?
    @Published var location4ETA: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
    }

    // MARK: - Calculate ETA using MapKit (FREE - no API cost)

    func calculateETAs(
        locations: [(name: String, latitude: Double, longitude: Double)],
        from origin: CLLocationCoordinate2D
    ) async {
        isLoading = true
        defer { isLoading = false }

        // Calculate ETA for each location sequentially
        var eta1: String? = nil
        var eta2: String? = nil
        var eta3: String? = nil
        var eta4: String? = nil

        for (index, location) in locations.enumerated() where index < 4 {
            let destination = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )

            do {
                let eta = try await calculateSingleETA(from: origin, to: destination)
                switch index {
                case 0: eta1 = eta
                case 1: eta2 = eta
                case 2: eta3 = eta
                case 3: eta4 = eta
                default: break
                }
            } catch {
                print("❌ Failed to calculate ETA for \(location.name): \(error)")
                switch index {
                case 0: eta1 = "N/A"
                case 1: eta2 = "N/A"
                case 2: eta3 = "N/A"
                case 3: eta4 = "N/A"
                default: break
                }
            }
        }

        // Update published properties on main thread
        await MainActor.run {
            self.location1ETA = eta1
            self.location2ETA = eta2
            self.location3ETA = eta3
            self.location4ETA = eta4
            self.lastUpdated = Date()
        }
    }

    // MARK: - Single ETA Calculation

    private func calculateSingleETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> String {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)

        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let route = response?.routes.first else {
                    continuation.resume(returning: "--")
                    return
                }

                // Convert travel time (in seconds) to readable format
                let minutes = Int(route.expectedTravelTime / 60)
                let hours = minutes / 60
                let remainingMinutes = minutes % 60

                let timeString: String
                if hours > 0 {
                    timeString = "\(hours)h \(remainingMinutes)m"
                } else if minutes > 0 {
                    timeString = "\(minutes)m"
                } else {
                    timeString = "<1m"
                }

                continuation.resume(returning: timeString)
            }
        }
    }

    // MARK: - Save ETAs to Widget

    func saveETAsToWidget() {
        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(location1ETA, forKey: "widgetLocation1ETA")
            userDefaults.set(location2ETA, forKey: "widgetLocation2ETA")
            userDefaults.set(location3ETA, forKey: "widgetLocation3ETA")
            userDefaults.set(location4ETA, forKey: "widgetLocation4ETA")
            userDefaults.synchronize()
        }
    }
}

// MARK: - CLLocationManager Delegate

extension MapKitService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager error: \(error)")
    }
}
