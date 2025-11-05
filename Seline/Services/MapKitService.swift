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

        var etas: [String?] = [nil, nil, nil, nil]

        // Calculate ETA for each location sequentially
        for (index, location) in locations.enumerated() where index < 4 {
            let destination = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )

            do {
                let eta = try await calculateSingleETA(from: origin, to: destination)
                etas[index] = eta
            } catch {
                print("❌ Failed to calculate ETA for \(location.name): \(error)")
                etas[index] = "N/A"
            }
        }

        // Update published properties on main thread
        await MainActor.run {
            location1ETA = etas.count > 0 ? etas[0] : nil
            location2ETA = etas.count > 1 ? etas[1] : nil
            location3ETA = etas.count > 2 ? etas[2] : nil
            location4ETA = etas.count > 3 ? etas[3] : nil
            lastUpdated = Date()
            print("✅ MapKit ETAs updated: L1=\(location1ETA ?? "---"), L2=\(location2ETA ?? "---"), L3=\(location3ETA ?? "---"), L4=\(location4ETA ?? "---")")
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
            print("✅ MapKit: Saved ETAs to widget")
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
