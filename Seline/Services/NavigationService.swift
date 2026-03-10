import Foundation
import CoreLocation
import MapKit

class NavigationService: ObservableObject {
    private struct ETARequestFingerprint: Equatable {
        let originLatitude: Int
        let originLongitude: Int
        let destinations: [String]
    }

    static let shared = NavigationService()

    // COST OPTIMIZATION: Using MapKit instead of Google Routes API
    // MapKit is FREE (native iOS framework)
    // Google Routes API was costing $0.12 per request (~$10-15/month)
    private let mapKitService = MapKitService.shared

    @Published var location1ETA: String? {
        didSet { mapKitService.location1ETA = location1ETA }
    }
    @Published var location2ETA: String? {
        didSet { mapKitService.location2ETA = location2ETA }
    }
    @Published var location3ETA: String? {
        didSet { mapKitService.location3ETA = location3ETA }
    }
    @Published var location4ETA: String? {
        didSet { mapKitService.location4ETA = location4ETA }
    }
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    private var lastRefreshFingerprint: ETARequestFingerprint?

    // Movement tracking for auto-refresh
    private var lastRefreshLocation: CLLocationCoordinate2D?
    private let minimumDistanceForRefresh: CLLocationDistance = 5000 // 5 km in meters
    private let minimumRefreshInterval: TimeInterval = 60

    private init() {}

    enum NavigationError: Error, LocalizedError {
        case invalidURL
        case noData
        case apiError(String)
        case networkError(Error)
        case noCurrentLocation
        case noDestination

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from API"
            case .apiError(let message):
                return "API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            case .noCurrentLocation:
                return "Current location not available"
            case .noDestination:
                return "Destination not set"
            }
        }
    }

    // MARK: - Save ETAs to Widget

    /// Save current ETA values to shared UserDefaults for widget access
    func saveETAsToWidget() {
        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(self.location1ETA, forKey: "widgetLocation1ETA")
            userDefaults.set(self.location2ETA, forKey: "widgetLocation2ETA")
            userDefaults.set(self.location3ETA, forKey: "widgetLocation3ETA")
            userDefaults.set(self.location4ETA, forKey: "widgetLocation4ETA")
            userDefaults.synchronize()
            print("✅ NavigationService: Saved current ETAs to widget - L1: \(self.location1ETA ?? "---"), L2: \(self.location2ETA ?? "---"), L3: \(self.location3ETA ?? "---"), L4: \(self.location4ETA ?? "---")")
        } else {
            print("❌ NavigationService: Could not access shared UserDefaults group.seline")
        }
    }

    // MARK: - Calculate ETA (Using MapKit - FREE)

    /// Calculate driving ETA from current location to a destination using native MapKit
    /// No API cost - uses Apple's built-in routing
    func calculateETA(from origin: CLLocation, to destination: CLLocationCoordinate2D) async throws -> ETAResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)

        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let error = error {
                    print("❌ MapKit error: \(error)")
                    continuation.resume(throwing: NavigationError.networkError(error))
                    return
                }

                guard let route = response?.routes.first else {
                    print("❌ No route found via MapKit")
                    continuation.resume(throwing: NavigationError.apiError("No route found"))
                    return
                }

                let durationSeconds = Int(route.expectedTravelTime)
                let durationText = Self.formatETA(durationSeconds)
                let distanceMeters = Int(route.distance)
                let distanceText = Self.formatDistance(distanceMeters)

                // DEBUG: Commented out to reduce console spam
                // print("✅ MapKit ETA: \(durationText) for \(distanceText)")

                continuation.resume(returning: ETAResult(
                    durationSeconds: durationSeconds,
                    durationText: durationText,
                    distanceMeters: distanceMeters,
                    distanceText: distanceText
                ))
            }
        }
    }

    /// Update ETAs for all 4 location slots
    func updateETAs(currentLocation: CLLocation, location1: CLLocationCoordinate2D?, location2: CLLocationCoordinate2D?, location3: CLLocationCoordinate2D?, location4: CLLocationCoordinate2D?) async {
        let fingerprint = etaFingerprint(
            origin: currentLocation.coordinate,
            destinations: [location1, location2, location3, location4]
        )

        let shouldSkipRefresh = await MainActor.run { () -> Bool in
            if let lastRefreshFingerprint,
               lastRefreshFingerprint == fingerprint,
               let lastUpdated,
               Date().timeIntervalSince(lastUpdated) < minimumRefreshInterval {
                return true
            }

            isLoading = true
            self.lastRefreshFingerprint = fingerprint
            return false
        }

        guard !shouldSkipRefresh else { return }

        async let eta1 = calculateFormattedETA(from: currentLocation, to: location1, label: "1")
        async let eta2 = calculateFormattedETA(from: currentLocation, to: location2, label: "2")
        async let eta3 = calculateFormattedETA(from: currentLocation, to: location3, label: "3")
        async let eta4 = calculateFormattedETA(from: currentLocation, to: location4, label: "4")

        let resolvedETAs = await (eta1, eta2, eta3, eta4)

        await MainActor.run {
            self.location1ETA = resolvedETAs.0
            self.location2ETA = resolvedETAs.1
            self.location3ETA = resolvedETAs.2
            self.location4ETA = resolvedETAs.3
            self.isLoading = false
            self.lastUpdated = Date()
            saveETAsToWidget()
        }
    }

    private func calculateFormattedETA(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D?,
        label: String
    ) async -> String? {
        guard let destination else { return nil }

        do {
            let result = try await calculateETA(from: origin, to: destination)
            return Self.formatETA(result.durationSeconds)
        } catch {
            print("❌ Failed to calculate location \(label) ETA: \(error)")
            return nil
        }
    }

    private func etaFingerprint(
        origin: CLLocationCoordinate2D,
        destinations: [CLLocationCoordinate2D?]
    ) -> ETARequestFingerprint {
        ETARequestFingerprint(
            originLatitude: Int((origin.latitude * 1000).rounded()),
            originLongitude: Int((origin.longitude * 1000).rounded()),
            destinations: destinations.map { destination in
                guard let destination else { return "nil" }
                let latitude = Int((destination.latitude * 1000).rounded())
                let longitude = Int((destination.longitude * 1000).rounded())
                return "\(latitude),\(longitude)"
            }
        )
    }

    // MARK: - Formatting Helpers

    /// Format distance in meters to a readable string
    private static func formatDistance(_ meters: Int) -> String {
        let kilometers = Double(meters) / 1000.0
        if kilometers < 1.0 {
            return "\(meters) m"
        }
        return String(format: "%.1f km", kilometers)
    }

    /// Format duration in seconds to a short string (e.g., "12 min", "1h 5m")
    private static func formatETA(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours)h"
        }

        return "\(minutes) min"
    }

    // MARK: - Auto-Refresh on Movement

    /// Check if user has moved 5km+ and trigger refresh if so
    func checkAndRefreshIfNeeded(currentLocation: CLLocation, location1: CLLocationCoordinate2D?, location2: CLLocationCoordinate2D?, location3: CLLocationCoordinate2D?, location4: CLLocationCoordinate2D?) async {
        // If no previous refresh location, set it and trigger refresh
        guard let previousRefreshCoordinate = lastRefreshLocation else {
            lastRefreshLocation = currentLocation.coordinate
            await updateETAs(currentLocation: currentLocation, location1: location1, location2: location2, location3: location3, location4: location4)
            return
        }

        // Calculate distance from last refresh location
        let lastLocation = CLLocation(latitude: previousRefreshCoordinate.latitude, longitude: previousRefreshCoordinate.longitude)
        let distanceMoved = currentLocation.distance(from: lastLocation)

        // If moved 5km+, refresh ETAs
        if distanceMoved >= minimumDistanceForRefresh {
            print("📍 User moved \(Int(distanceMoved)) meters (5km+ threshold). Refreshing ETAs...")
            lastRefreshLocation = currentLocation.coordinate
            await updateETAs(currentLocation: currentLocation, location1: location1, location2: location2, location3: location3, location4: location4)
        }
    }
}

// MARK: - ETA Result Model

struct ETAResult {
    let durationSeconds: Int
    let durationText: String
    let distanceMeters: Int
    let distanceText: String
}
