import Foundation
import CoreLocation

class NavigationService: ObservableObject {
    static let shared = NavigationService()

    // Google Maps API Key (same as GoogleMapsService)
    private let apiKey = "AIzaSyDL864Gd2OuJBIuL9380kQFbb0jJAJilQ8"
    private let routesBaseURL = "https://routes.googleapis.com/directions/v2:computeRoutes"

    @Published var location1ETA: String?
    @Published var location2ETA: String?
    @Published var location3ETA: String?
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

    // MARK: - Calculate ETA

    /// Calculate driving ETA from current location to a destination
    func calculateETA(from origin: CLLocation, to destination: CLLocationCoordinate2D) async throws -> ETAResult {
        guard let url = URL(string: routesBaseURL) else {
            throw NavigationError.invalidURL
        }

        // Create request body for Routes API v2 (computeRoutes)
        let requestBody: [String: Any] = [
            "origin": [
                "location": [
                    "latLng": [
                        "latitude": origin.coordinate.latitude,
                        "longitude": origin.coordinate.longitude
                    ]
                ]
            ],
            "destination": [
                "location": [
                    "latLng": [
                        "latitude": destination.latitude,
                        "longitude": destination.longitude
                    ]
                ]
            ],
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
            "routeModifiers": [
                "avoidTolls": true,
                "avoidHighways": false,
                "avoidFerries": false
            ],
            "computeAlternativeRoutes": false,
            "languageCode": "en-US",
            "units": "METRIC"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw NavigationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline", forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Routes API HTTP Status: \(httpResponse.statusCode)")

                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("❌ Error response: \(errorData)")
                        if let error = errorData["error"] as? [String: Any],
                           let errorMessage = error["message"] as? String {
                            throw NavigationError.apiError(errorMessage)
                        }
                    }
                    throw NavigationError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }

            // Parse response - computeRoutes API returns routes array
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Routes API Response: \(String(responseString.prefix(500)))")
                }
                throw NavigationError.apiError("Invalid JSON response")
            }

            guard let routes = jsonResponse["routes"] as? [[String: Any]],
                  let firstRoute = routes.first else {
                // Log response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Routes API Response: \(String(responseString.prefix(500)))")
                }
                print("❌ No routes found in response")
                throw NavigationError.apiError("No route found")
            }

            return try parseRouteResult(firstRoute)

        } catch let error as NavigationError {
            throw error
        } catch {
            throw NavigationError.networkError(error)
        }
    }

    private func parseRouteResult(_ route: [String: Any]) throws -> ETAResult {
        // Get duration (in seconds with 's' suffix like "123s")
        var durationSeconds = 0
        var durationText = ""

        if let duration = route["duration"] as? String {
            // Remove 's' suffix and convert to int
            let cleanDuration = duration.replacingOccurrences(of: "s", with: "")
            durationSeconds = Int(cleanDuration) ?? 0
            durationText = formatETA(durationSeconds)
        } else {
            print("⚠️ No duration in route result")
            throw NavigationError.apiError("No duration available")
        }

        // Get distance
        var distanceMeters = 0
        var distanceText = ""
        if let distance = route["distanceMeters"] as? Int {
            distanceMeters = distance
            distanceText = formatDistance(distanceMeters)
        } else if let distanceString = route["distanceMeters"] as? String,
                  let distance = Int(distanceString) {
            distanceMeters = distance
            distanceText = formatDistance(distanceMeters)
        } else {
            print("⚠️ No distance in route result")
        }

        print("✅ ETA calculated: \(durationText), Distance: \(distanceText)")

        return ETAResult(
            durationSeconds: durationSeconds,
            durationText: durationText,
            distanceMeters: distanceMeters,
            distanceText: distanceText
        )
    }

    private func formatDistance(_ meters: Int) -> String {
        let kilometers = Double(meters) / 1000.0
        if kilometers < 1.0 {
            return "\(meters) m"
        }
        return String(format: "%.1f km", kilometers)
    }

    /// Update ETAs for all 3 location slots
    func updateETAs(currentLocation: CLLocation, location1: CLLocationCoordinate2D?, location2: CLLocationCoordinate2D?, location3: CLLocationCoordinate2D?) async {
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

        await MainActor.run {
            isLoading = false
            lastUpdated = Date()
        }
    }

    // MARK: - Formatting Helpers

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
