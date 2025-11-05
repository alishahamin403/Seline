import Foundation
import CoreLocation
import MapKit

class NavigationService: ObservableObject {
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
                let durationText = self.formatETA(durationSeconds)
                let distanceMeters = Int(route.distance)
                let distanceText = self.formatDistance(distanceMeters)

                print("✅ MapKit ETA: \(durationText) for \(distanceText)")

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
        await MainActor.run {
            isLoading = true
        }

        // Calculate location 1 ETA
        if let location1 = location1 {
            do {
                let result = try await calculateETA(from: currentLocation, to: location1)
                await MainActor.run {
                    self.location1ETA = formatETA(result.durationSeconds)
                }
            } catch {
                print("❌ Failed to calculate location 1 ETA: \(error)")
                await MainActor.run {
                    self.location1ETA = nil
                }
            }
        } else {
            await MainActor.run {
                self.location1ETA = nil
            }
        }

        // Calculate location 2 ETA
        if let location2 = location2 {
            do {
                let result = try await calculateETA(from: currentLocation, to: location2)
                await MainActor.run {
                    self.location2ETA = formatETA(result.durationSeconds)
                }
            } catch {
                print("❌ Failed to calculate location 2 ETA: \(error)")
                await MainActor.run {
                    self.location2ETA = nil
                }
            }
        } else {
            await MainActor.run {
                self.location2ETA = nil
            }
        }

        // Calculate location 3 ETA
        if let location3 = location3 {
            do {
                let result = try await calculateETA(from: currentLocation, to: location3)
                await MainActor.run {
                    self.location3ETA = formatETA(result.durationSeconds)
                }
            } catch {
                print("❌ Failed to calculate location 3 ETA: \(error)")
                await MainActor.run {
                    self.location3ETA = nil
                }
            }
        } else {
            await MainActor.run {
                self.location3ETA = nil
            }
        }

        // Calculate location 4 ETA
        if let location4 = location4 {
            do {
                let result = try await calculateETA(from: currentLocation, to: location4)
                await MainActor.run {
                    self.location4ETA = formatETA(result.durationSeconds)
                }
            } catch {
                print("❌ Failed to calculate location 4 ETA: \(error)")
                await MainActor.run {
                    self.location4ETA = nil
                }
            }
        } else {
            await MainActor.run {
                self.location4ETA = nil
            }
        }

        await MainActor.run {
            isLoading = false
            lastUpdated = Date()

            // Save ETAs to shared UserDefaults for widget access
            if let userDefaults = UserDefaults(suiteName: "group.seline") {
                userDefaults.set(self.location1ETA, forKey: "widgetLocation1ETA")
                userDefaults.set(self.location2ETA, forKey: "widgetLocation2ETA")
                userDefaults.set(self.location3ETA, forKey: "widgetLocation3ETA")
                userDefaults.set(self.location4ETA, forKey: "widgetLocation4ETA")
                userDefaults.synchronize()
                print("✅ NavigationService: Saved ETAs to shared UserDefaults - L1: \(self.location1ETA ?? "---"), L2: \(self.location2ETA ?? "---"), L3: \(self.location3ETA ?? "---"), L4: \(self.location4ETA ?? "---")")
            } else {
                print("❌ NavigationService: Could not access shared UserDefaults group.seline")
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Format distance in meters to a readable string
    private func formatDistance(_ meters: Int) -> String {
        let kilometers = Double(meters) / 1000.0
        if kilometers < 1.0 {
            return "\(meters) m"
        }
        return String(format: "%.1f km", kilometers)
    }

    /// Format duration in seconds to a short string (e.g., "12 min", "1h 5m")
    private func formatETA(_ seconds: Int) -> String {
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
}

// MARK: - ETA Result Model

struct ETAResult {
    let durationSeconds: Int
    let durationText: String
    let distanceMeters: Int
    let distanceText: String
}
