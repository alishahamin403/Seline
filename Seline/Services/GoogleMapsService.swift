import Foundation
import UIKit
import CoreLocation
import MapKit

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

        let isAddressLikeQuery = queryLooksLikeStreetAddress(queryToSearch)

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

            let fallbackResults: [PlaceSearchResult]
            if searchResults.isEmpty || isAddressLikeQuery {
                fallbackResults = await searchAddressResults(query: queryToSearch, currentLocation: currentLocation)
            } else {
                fallbackResults = []
            }

            let mergedResults = mergeSearchResults(
                primary: isAddressLikeQuery ? fallbackResults : searchResults,
                secondary: isAddressLikeQuery ? searchResults : fallbackResults
            )

            // Cache the results
            self.searchCache[cacheKey] = SearchCacheEntry(results: mergedResults, timestamp: Date())

            return mergedResults

        } catch {
            let fallbackResults = await searchAddressResults(query: queryToSearch, currentLocation: currentLocation)
            if !fallbackResults.isEmpty {
                self.searchCache[cacheKey] = SearchCacheEntry(results: fallbackResults, timestamp: Date())
                return fallbackResults
            }

            if let mapsError = error as? MapsError {
                throw mapsError
            }

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
            "displayName,formattedAddress,location,internationalPhoneNumber,rating,userRatingCount,websiteUri,regularOpeningHours,currentOpeningHours,priceLevel,types,photos,reviews"

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

            // Extract a small gallery of photos for the detail view
            var photoURLs: [String] = []
            if let photos = place["photos"] as? [[String: Any]] {
                photoURLs = photos.prefix(8).compactMap { photo in
                    guard let photoName = photo["name"] as? String else { return nil }
                    return "https://places.googleapis.com/v1/\(photoName)/media?maxHeightPx=900&maxWidthPx=900&key=\(apiKey)"
                }
            }

            let reviews: [PlaceReview]
            if let rawReviews = place["reviews"] as? [[String: Any]] {
                reviews = rawReviews.compactMap(parseReview).sorted {
                    if $0.rating == $1.rating {
                        let lhsLength = $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count
                        let rhsLength = $1.text.trimmingCharacters(in: .whitespacesAndNewlines).count
                        return lhsLength > rhsLength
                    }
                    return $0.rating > $1.rating
                }
            } else {
                reviews = []
            }

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

    private func parseReview(_ review: [String: Any]) -> PlaceReview? {
        let authorAttribution = review["authorAttribution"] as? [String: Any]
        let authorName =
            (authorAttribution?["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Google user"

        let ratingValue = review["rating"]
        let rating: Int
        if let intValue = ratingValue as? Int {
            rating = intValue
        } else if let doubleValue = ratingValue as? Double {
            rating = Int(doubleValue.rounded())
        } else {
            rating = 0
        }

        let relativeTime =
            (review["relativePublishTimeDescription"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let text = reviewText(from: review)
        let profilePhotoUrl =
            (authorAttribution?["photoUri"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty || !authorName.isEmpty else { return nil }

        return PlaceReview(
            authorName: authorName.isEmpty ? "Google user" : authorName,
            rating: max(0, min(5, rating)),
            text: text.isEmpty ? "No written review provided." : text,
            relativeTime: relativeTime?.isEmpty == true ? nil : relativeTime,
            profilePhotoUrl: profilePhotoUrl?.isEmpty == true ? nil : profilePhotoUrl
        )
    }

    private func reviewText(from review: [String: Any]) -> String {
        if let text = review["text"] as? [String: Any],
           let value = text["text"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let text = review["originalText"] as? [String: Any],
           let value = text["text"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let text = review["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private func queryLooksLikeStreetAddress(_ query: String) -> Bool {
        let lower = query.lowercased()
        let hasStreetNumber = lower.range(of: #"\b\d+[a-z]?\b"#, options: .regularExpression) != nil
        let streetKeywords = [
            "street", "st", "road", "rd", "avenue", "ave", "boulevard", "blvd",
            "drive", "dr", "lane", "ln", "court", "ct", "circle", "cir",
            "trail", "trl", "way", "parkway", "pkwy", "place", "pl"
        ]
        let hasStreetKeyword = streetKeywords.contains { keyword in
            lower.contains(" \(keyword) ") || lower.hasSuffix(" \(keyword)")
        }

        return hasStreetNumber || hasStreetKeyword || lower.contains(",")
    }

    private func searchAddressResults(query: String, currentLocation: CLLocation?) async -> [PlaceSearchResult] {
        var results: [PlaceSearchResult] = []

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address

        if let currentLocation, !queryLooksLikeStreetAddress(query) {
            request.region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 200000,
                longitudinalMeters: 200000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            results.append(contentsOf: response.mapItems.prefix(8).compactMap(makeAddressSearchResult))
        } catch {
            print("⚠️ MapKit address search failed for '\(query)': \(error.localizedDescription)")
        }

        if !results.isEmpty {
            return dedupeSearchResults(results)
        }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            results.append(contentsOf: placemarks.prefix(3).compactMap(makeAddressSearchResult))
        } catch {
            print("⚠️ Address geocoding failed for '\(query)': \(error.localizedDescription)")
        }

        return dedupeSearchResults(results)
    }

    private func mergeSearchResults(primary: [PlaceSearchResult], secondary: [PlaceSearchResult]) -> [PlaceSearchResult] {
        dedupeSearchResults(primary + secondary)
    }

    private func dedupeSearchResults(_ results: [PlaceSearchResult]) -> [PlaceSearchResult] {
        var seen = Set<String>()
        var deduped: [PlaceSearchResult] = []

        for result in results {
            let key = dedupeKey(for: result)
            guard seen.insert(key).inserted else { continue }
            deduped.append(result)
        }

        return deduped
    }

    private func dedupeKey(for result: PlaceSearchResult) -> String {
        let normalizedAddress = result.address
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let roundedLat = String(format: "%.5f", result.latitude)
        let roundedLon = String(format: "%.5f", result.longitude)
        return "\(normalizedAddress)|\(roundedLat)|\(roundedLon)"
    }

    private func makeAddressSearchResult(from mapItem: MKMapItem) -> PlaceSearchResult? {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        let address = formattedAddress(for: placemark)
        let name = resolvedName(
            explicitName: mapItem.name,
            address: address,
            fallbackName: placemark.name
        )
        let syntheticId = syntheticAddressPlaceId(name: name, address: address, coordinate: coordinate)
        let result = PlaceSearchResult(
            id: syntheticId,
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            types: ["street_address"],
            photoURL: nil
        )

        cacheFallbackDetails(for: result)
        return result
    }

    private func makeAddressSearchResult(from placemark: CLPlacemark) -> PlaceSearchResult? {
        guard let location = placemark.location else { return nil }

        let address = formattedAddress(for: placemark)
        let name = resolvedName(
            explicitName: placemark.name,
            address: address,
            fallbackName: placemark.thoroughfare
        )
        let coordinate = location.coordinate
        let syntheticId = syntheticAddressPlaceId(name: name, address: address, coordinate: coordinate)
        let result = PlaceSearchResult(
            id: syntheticId,
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            types: ["street_address"],
            photoURL: nil
        )

        cacheFallbackDetails(for: result)
        return result
    }

    private func cacheFallbackDetails(for result: PlaceSearchResult) {
        detailsCache[result.id] = PlaceDetails(
            name: result.name,
            address: result.address,
            phone: nil,
            latitude: result.latitude,
            longitude: result.longitude,
            photoURLs: [],
            rating: nil,
            totalRatings: 0,
            reviews: [],
            website: nil,
            isOpenNow: nil,
            openingHours: [],
            priceLevel: nil,
            types: result.types
        )
    }

    private func resolvedName(explicitName: String?, address: String, fallbackName: String?) -> String {
        let trimmedExplicit = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedExplicit.isEmpty {
            return trimmedExplicit
        }

        let trimmedFallback = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }

        return address.isEmpty ? "Address Result" : address
    }

    private func formattedAddress(for placemark: MKPlacemark) -> String {
        var addressParts: [String] = []

        if let subThoroughfare = placemark.subThoroughfare, let thoroughfare = placemark.thoroughfare {
            addressParts.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            addressParts.append(thoroughfare)
        } else if let name = placemark.name {
            addressParts.append(name)
        }

        if let locality = placemark.locality {
            addressParts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            addressParts.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            addressParts.append(postalCode)
        }
        if let country = placemark.country {
            addressParts.append(country)
        }

        return addressParts.isEmpty ? "Address Result" : addressParts.joined(separator: ", ")
    }

    private func formattedAddress(for placemark: CLPlacemark) -> String {
        var addressParts: [String] = []

        if let subThoroughfare = placemark.subThoroughfare, let thoroughfare = placemark.thoroughfare {
            addressParts.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            addressParts.append(thoroughfare)
        } else if let name = placemark.name {
            addressParts.append(name)
        }

        if let locality = placemark.locality {
            addressParts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            addressParts.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            addressParts.append(postalCode)
        }
        if let country = placemark.country {
            addressParts.append(country)
        }

        return addressParts.isEmpty ? "Address Result" : addressParts.joined(separator: ", ")
    }

    private func syntheticAddressPlaceId(
        name: String,
        address: String,
        coordinate: CLLocationCoordinate2D
    ) -> String {
        let signature = [
            name.lowercased(),
            address.lowercased(),
            String(format: "%.5f", coordinate.latitude),
            String(format: "%.5f", coordinate.longitude)
        ]
        .joined(separator: "|")

        return "address-search-\(HashUtils.deterministicHash(signature).magnitude)"
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
