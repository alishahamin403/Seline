import Foundation
import UIKit
import CoreLocation

class GoogleMapsService: ObservableObject {
    static let shared = GoogleMapsService()

    // Google Places API Key - loaded from Config.swift (not committed to git)
    private let apiKey = Config.googleMapsAPIKey
    private let placesBaseURL = "https://places.googleapis.com/v1"

    // Search results cache
    private struct SearchCacheEntry {
        let results: [PlaceSearchResult]
        let timestamp: Date
    }

    private var searchCache: [String: SearchCacheEntry] = [:] // Key: search query
    private var detailsCache: [String: PlaceDetails] = [:] // Key: place ID - persistent cache
    private let searchCacheDurationSeconds: TimeInterval = 300 // 5 minutes

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

    // MARK: - Cache Helpers

    private func isSearchCacheValid(_ entry: SearchCacheEntry) -> Bool {
        return Date().timeIntervalSince(entry.timestamp) < searchCacheDurationSeconds
    }

    // MARK: - Search Places

    func searchPlaces(query: String, currentLocation: CLLocation? = nil) async throws -> [PlaceSearchResult] {
        guard !query.isEmpty else { return [] }

        let normalizedQuery = query
            .replacingOccurrences(of: "near me", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let queryToSearch = normalizedQuery.isEmpty ? query : normalizedQuery

        let cacheKey: String = {
            guard let currentLocation else { return queryToSearch.lowercased() }
            let roundedLat = String(format: "%.2f", currentLocation.coordinate.latitude)
            let roundedLon = String(format: "%.2f", currentLocation.coordinate.longitude)
            return "\(queryToSearch.lowercased())@\(roundedLat),\(roundedLon)"
        }()

        // Check cache first
        if let cachedEntry = searchCache[cacheKey], isSearchCacheValid(cachedEntry) {
            return cachedEntry.results
        }

        // Use new Places API (Text Search)
        let urlString = "\(placesBaseURL)/places:searchText"

        guard let url = URL(string: urlString) else {
            throw MapsError.invalidURL
        }

        // Create request body for new API
        var requestBody: [String: Any] = [
            "textQuery": queryToSearch,
            "maxResultCount": 20
        ]

        if let currentLocation {
            requestBody["locationBias"] = [
                "circle": [
                    "center": [
                        "latitude": currentLocation.coordinate.latitude,
                        "longitude": currentLocation.coordinate.longitude
                    ],
                    "radius": 30000.0
                ]
            ]
            requestBody["rankPreference"] = "DISTANCE"
        }

        let lowerQuery = queryToSearch.lowercased()
        if lowerQuery.contains("supercharger") || lowerQuery.contains("ev charger") || lowerQuery.contains("charging station") {
            requestBody["includedType"] = "electric_vehicle_charging_station"
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw MapsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.types,places.photos", forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = errorData["error"] as? [String: Any],
                           let errorMessage = error["message"] as? String {
                            throw MapsError.apiError(errorMessage)
                        }
                    }
                    throw MapsError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }

            // Parse response
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MapsError.decodingError
            }

            guard let places = jsonResponse["places"] as? [[String: Any]] else {
                throw MapsError.decodingError
            }

            // Convert to PlaceSearchResult array
            let searchResults = places.compactMap { place -> PlaceSearchResult? in
                guard let placeId = place["id"] as? String,
                      let displayName = place["displayName"] as? [String: Any],
                      let name = displayName["text"] as? String,
                      let formattedAddress = place["formattedAddress"] as? String,
                      let location = place["location"] as? [String: Double],
                      let lat = location["latitude"],
                      let lng = location["longitude"] else {
                    return nil
                }

                let types = place["types"] as? [String] ?? []
                
                // Extract first photo URL if available
                var photoURL: String? = nil
                if let photos = place["photos"] as? [[String: Any]],
                   let firstPhoto = photos.first,
                   let photoName = firstPhoto["name"] as? String {
                    // Google Places API returns photo resource names
                    // Format: https://places.googleapis.com/v1/{resourceName}/media?maxHeightPx=200&maxWidthPx=200&key={apiKey}
                    photoURL = "https://places.googleapis.com/v1/\(photoName)/media?maxHeightPx=200&maxWidthPx=200&key=\(apiKey)"
                }

                return PlaceSearchResult(
                    id: placeId,
                    name: name,
                    address: formattedAddress,
                    latitude: lat,
                    longitude: lng,
                    types: types,
                    photoURL: photoURL
                )
            }

            // Cache the results
            self.searchCache[cacheKey] = SearchCacheEntry(results: searchResults, timestamp: Date())

            return searchResults

        } catch let error as MapsError {
            throw error
        } catch {
            throw MapsError.networkError(error)
        }
    }

    // MARK: - Get Place Details

    func getPlaceDetails(placeId: String, minimizeFields: Bool = false) async throws -> PlaceDetails {
        // Check persistent cache first - location details never expire unless manually removed
        if !minimizeFields, let cachedDetails = detailsCache[placeId] {
            return cachedDetails
        }

        // The new Places API expects the full resource name format: places/{placeId}
        // But the search returns just the ID, so we need to construct the full path
        let resourceName = placeId.hasPrefix("places/") ? placeId : "places/\(placeId)"
        let urlString = "\(placesBaseURL)/\(resourceName)"

        guard let url = URL(string: urlString) else {
            throw MapsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        // Optimize field mask based on use case
        // COST OPTIMIZATION:
        // - photos: Only fetched when user opens detail view (on-demand, not during search)
        // - reviews: Only fetched by LLM when specifically asked (on-demand, cost-efficient)
        let fieldMask = minimizeFields ?
            "displayName,location,regularOpeningHours,currentOpeningHours" :
            "displayName,formattedAddress,location,internationalPhoneNumber,rating,userRatingCount,websiteUri,regularOpeningHours,currentOpeningHours,priceLevel,types,photos"

        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = errorData["error"] as? [String: Any],
                           let errorMessage = error["message"] as? String {
                            throw MapsError.apiError(errorMessage)
                        }
                    }
                    throw MapsError.apiError("HTTP \(httpResponse.statusCode)")
                }
            }

            // Parse response
            guard let place = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MapsError.decodingError
            }

            // Extract details using new API structure
            let displayName = place["displayName"] as? [String: Any]
            let name = displayName?["text"] as? String ?? ""
            let address = place["formattedAddress"] as? String ?? ""
            let phone = place["internationalPhoneNumber"] as? String
            let rating = place["rating"] as? Double
            let totalRatings = place["userRatingCount"] as? Int ?? 0
            let websiteUri = place["websiteUri"] as? String
            let priceLevel = place["priceLevel"] as? String

            var latitude = 0.0
            var longitude = 0.0
            if let location = place["location"] as? [String: Double] {
                latitude = location["latitude"] ?? 0.0
                longitude = location["longitude"] ?? 0.0
            }

            // Extract first photo only (cost optimization - only fetch on detail view)
            var photoURLs: [String] = []
            if let photos = place["photos"] as? [[String: Any]],
               let firstPhoto = photos.first,
               let photoName = firstPhoto["name"] as? String {
                // Google Places API returns photo resource names
                // Format: https://places.googleapis.com/v1/{resourceName}/media?maxHeightPx=200&maxWidthPx=200&key={apiKey}
                let photoURL = "https://places.googleapis.com/v1/\(photoName)/media?maxHeightPx=200&maxWidthPx=200&key=\(apiKey)"
                photoURLs = [photoURL]
            }

            // Reviews are fetched by LLM on-demand when users ask
            let reviews: [PlaceReview] = []

            // Extract opening hours (new API structure)
            var isOpenNow: Bool? = nil
            var weekdayText: [String] = []

            // First try to get current opening status from currentOpeningHours
            if let currentOpeningHours = place["currentOpeningHours"] as? [String: Any] {
                if let openNow = currentOpeningHours["openNow"] as? Bool {
                    isOpenNow = openNow
                }
            }

            // Get regular opening hours for weekday descriptions
            if let openingHours = place["regularOpeningHours"] as? [String: Any] {
                // Fallback to regularOpeningHours openNow if currentOpeningHours not available
                if isOpenNow == nil, let openNow = openingHours["openNow"] as? Bool {
                    isOpenNow = openNow
                }
                if let weekdayDescriptions = openingHours["weekdayDescriptions"] as? [String] {
                    weekdayText = weekdayDescriptions
                }
            }

            let types = place["types"] as? [String] ?? []

            // Convert price level string to int
            var priceLevelInt: Int? = nil
            if let priceLevelStr = priceLevel {
                switch priceLevelStr {
                case "PRICE_LEVEL_FREE": priceLevelInt = 0
                case "PRICE_LEVEL_INEXPENSIVE": priceLevelInt = 1
                case "PRICE_LEVEL_MODERATE": priceLevelInt = 2
                case "PRICE_LEVEL_EXPENSIVE": priceLevelInt = 3
                case "PRICE_LEVEL_VERY_EXPENSIVE": priceLevelInt = 4
                default: priceLevelInt = nil
                }
            }

            let placeDetails = PlaceDetails(
                name: name,
                address: address,
                phone: phone,
                latitude: latitude,
                longitude: longitude,
                photoURLs: photoURLs,
                rating: rating,
                totalRatings: totalRatings,
                reviews: reviews,
                website: websiteUri,
                isOpenNow: isOpenNow,
                openingHours: weekdayText,
                priceLevel: priceLevelInt,
                types: types
            )

            // Cache the result persistently (but not for minimized field queries)
            if !minimizeFields {
                detailsCache[placeId] = placeDetails
            }

            return placeDetails

        } catch let error as MapsError {
            throw error
        } catch {
            throw MapsError.networkError(error)
        }
    }

    // MARK: - Cache Management

    /// Clear cached location details when user removes a location
    func clearLocationCache(for googlePlaceId: String) {
        detailsCache.removeValue(forKey: googlePlaceId)
    }

    // MARK: - Get Photo URL

    private func getPhotoURL(photoReference: String, maxWidth: Int = 400) -> String {
        // Use legacy API for photos as new API has different structure
        return "https://maps.googleapis.com/maps/api/place/photo?maxwidth=\(maxWidth)&photo_reference=\(photoReference)&key=\(apiKey)"
    }

    // MARK: - Open in Google Maps

    func openInGoogleMaps(place: SavedPlace, preferGoogle: Bool? = nil) {
        // Determine which map to use
        let useGoogle: Bool
        if let preferGoogle = preferGoogle {
            useGoogle = preferGoogle
        } else {
            // Check user preference
            let userDefaults = UserDefaults.standard
            if let preferredMap = userDefaults.string(forKey: "preferredMapApp") {
                useGoogle = preferredMap == "google"
            } else {
                // Default: try Google Maps first, fallback to Apple Maps
                useGoogle = true
            }
        }
        
        if useGoogle {
            // Try Google Maps app first
            if let googleMapsURL = place.googleMapsURL,
               UIApplication.shared.canOpenURL(googleMapsURL) {
                UIApplication.shared.open(googleMapsURL)
                return
            }
        }
        
        // Use Apple Maps (either as preference or fallback)
        if let appleMapsURL = place.appleMapsURL {
            UIApplication.shared.open(appleMapsURL)
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

    // MARK: - Get Recent Searches

    /// Returns most searched places from local search history
    /// Note: Google doesn't provide a public API to access Google Maps search history
    /// This tracks searches made within the app
    func getMostSearchedPlaces() async throws -> [PlaceSearchResult] {
        let locationsManager = LocationsManager.shared
        let recentSearches = locationsManager.getRecentSearches(limit: 10)

        if !recentSearches.isEmpty {
            return recentSearches
        }

        // If no history, show popular suggestions
        return try await getPopularSuggestions()
    }

    /// Get popular place suggestions as fallback
    private func getPopularSuggestions() async throws -> [PlaceSearchResult] {
        let popularSearches = [
            "coffee shops near me",
            "restaurants near me",
            "gas station near me",
            "grocery store near me"
        ]

        var allPlaces: [PlaceSearchResult] = []

        for query in popularSearches {
            do {
                let places = try await searchPlaces(query: query)
                allPlaces.append(contentsOf: places.prefix(2))
            } catch {
                // Silently continue if a query fails
            }
        }

        return Array(allPlaces.prefix(8))
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
    let totalRatings: Int
    let reviews: [PlaceReview]
    let website: String?
    let isOpenNow: Bool?
    let openingHours: [String]
    let priceLevel: Int?
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
            rating: rating,
            openingHours: openingHours,
            isOpenNow: isOpenNow
        )
    }
}

struct PlaceReview: Identifiable, Codable, Hashable {
    var id = UUID()
    let authorName: String
    let rating: Int
    let text: String
    let relativeTime: String?
    let profilePhotoUrl: String?
}
