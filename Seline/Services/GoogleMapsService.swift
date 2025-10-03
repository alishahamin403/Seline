import Foundation
import UIKit

class GoogleMapsService: ObservableObject {
    static let shared = GoogleMapsService()

    // Google Places API Key
    private let apiKey = "AIzaSyBWw6VpZR5GFpQXj8oF5mT9vK3xL4eU8nQ" // Replace with actual key
    private let placesBaseURL = "https://maps.googleapis.com/maps/api/place"

    private init() {}

    enum MapsError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case apiError(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from API"
            case .decodingError:
                return "Failed to decode API response"
            case .apiError(let message):
                return "API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Search Places

    func searchPlaces(query: String) async throws -> [PlaceSearchResult] {
        guard !query.isEmpty else { return [] }

        // Use Text Search API
        let urlString = "\(placesBaseURL)/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw MapsError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorData["error_message"] as? String {
                        throw MapsError.apiError(errorMessage)
                    } else {
                        throw MapsError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            // Parse response
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = jsonResponse["results"] as? [[String: Any]] else {
                throw MapsError.decodingError
            }

            // Convert to PlaceSearchResult array
            let places = results.compactMap { result -> PlaceSearchResult? in
                guard let placeId = result["place_id"] as? String,
                      let name = result["name"] as? String,
                      let formattedAddress = result["formatted_address"] as? String,
                      let geometry = result["geometry"] as? [String: Any],
                      let location = geometry["location"] as? [String: Double],
                      let lat = location["lat"],
                      let lng = location["lng"] else {
                    return nil
                }

                let types = result["types"] as? [String] ?? []

                return PlaceSearchResult(
                    id: placeId,
                    name: name,
                    address: formattedAddress,
                    latitude: lat,
                    longitude: lng,
                    types: types
                )
            }

            return places

        } catch let error as MapsError {
            throw error
        } catch {
            throw MapsError.networkError(error)
        }
    }

    // MARK: - Get Place Details

    func getPlaceDetails(placeId: String) async throws -> PlaceDetails {
        let fields = "name,formatted_address,geometry,formatted_phone_number,photos,rating,types"
        let urlString = "\(placesBaseURL)/details/json?place_id=\(placeId)&fields=\(fields)&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw MapsError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorData["error_message"] as? String {
                        throw MapsError.apiError(errorMessage)
                    } else {
                        throw MapsError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            // Parse response
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = jsonResponse["result"] as? [String: Any] else {
                throw MapsError.decodingError
            }

            // Extract details
            let name = result["name"] as? String ?? ""
            let address = result["formatted_address"] as? String ?? ""
            let phone = result["formatted_phone_number"] as? String
            let rating = result["rating"] as? Double

            var latitude = 0.0
            var longitude = 0.0
            if let geometry = result["geometry"] as? [String: Any],
               let location = geometry["location"] as? [String: Double] {
                latitude = location["lat"] ?? 0.0
                longitude = location["lng"] ?? 0.0
            }

            // Extract photo references
            var photoURLs: [String] = []
            if let photos = result["photos"] as? [[String: Any]] {
                photoURLs = photos.prefix(5).compactMap { photo in
                    guard let photoReference = photo["photo_reference"] as? String else { return nil }
                    return getPhotoURL(photoReference: photoReference)
                }
            }

            let types = result["types"] as? [String] ?? []

            return PlaceDetails(
                name: name,
                address: address,
                phone: phone,
                latitude: latitude,
                longitude: longitude,
                photoURLs: photoURLs,
                rating: rating,
                types: types
            )

        } catch let error as MapsError {
            throw error
        } catch {
            throw MapsError.networkError(error)
        }
    }

    // MARK: - Get Photo URL

    private func getPhotoURL(photoReference: String, maxWidth: Int = 400) -> String {
        return "\(placesBaseURL)/photo?maxwidth=\(maxWidth)&photo_reference=\(photoReference)&key=\(apiKey)"
    }

    // MARK: - Open in Google Maps

    func openInGoogleMaps(place: SavedPlace) {
        // Try Google Maps app first
        if let googleMapsURL = place.googleMapsURL,
           UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
            print("✅ Opened in Google Maps app")
        }
        // Fallback to Apple Maps
        else if let appleMapsURL = place.appleMapsURL {
            UIApplication.shared.open(appleMapsURL)
            print("✅ Opened in Apple Maps (Google Maps not installed)")
        } else {
            print("❌ Could not open maps")
        }
    }

    func openInGoogleMaps(searchResult: PlaceSearchResult) {
        let query = searchResult.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let googleMapsURL = URL(string: "comgooglemaps://?q=\(query)&center=\(searchResult.latitude),\(searchResult.longitude)")
        let appleMapsURL = URL(string: "maps://?q=\(query)&ll=\(searchResult.latitude),\(searchResult.longitude)")

        if let googleMapsURL = googleMapsURL,
           UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
        } else if let appleMapsURL = appleMapsURL {
            UIApplication.shared.open(appleMapsURL)
        }
    }

    // MARK: - Get Recent Searches (Simulated Google Maps History)

    /// Returns most searched places from Google Maps
    /// In a real implementation, this would use Google Activity API to get actual search history
    /// For now, we return popular nearby places to simulate search history
    func getMostSearchedPlaces() async throws -> [PlaceSearchResult] {
        // Simulate getting user's most searched places
        // These are common searches that would appear in a typical Google Maps history
        let popularSearches = [
            "coffee shops near me",
            "gas station near me",
            "grocery store near me",
            "pharmacy near me",
            "restaurants near me",
            "atm near me",
            "parking near me",
            "hospital near me"
        ]

        var allPlaces: [PlaceSearchResult] = []

        // Get 2-3 results for each popular search to simulate history
        for query in popularSearches.prefix(4) {
            do {
                let places = try await searchPlaces(query: query)
                allPlaces.append(contentsOf: places.prefix(2))
            } catch {
                print("⚠️ Failed to fetch places for query '\(query)': \(error)")
            }
        }

        // Return up to 10 most recent searches
        return Array(allPlaces.prefix(10))
    }

    /// Get nearby places for the refresh button
    func getPopularPlaces() async throws -> [PlaceSearchResult] {
        return try await getMostSearchedPlaces()
    }
}

// MARK: - Place Details Model

struct PlaceDetails {
    let name: String
    let address: String
    let phone: String?
    let latitude: Double
    let longitude: Double
    let photoURLs: [String]
    let rating: Double?
    let types: [String]

    func toSavedPlace(googlePlaceId: String) -> SavedPlace {
        return SavedPlace(
            googlePlaceId: googlePlaceId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            phone: phone,
            photos: photoURLs,
            rating: rating
        )
    }
}
