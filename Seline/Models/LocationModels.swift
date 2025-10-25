import Foundation
import SwiftUI
import PostgREST
import CoreLocation
import MapKit

// MARK: - Location Models

struct SavedPlace: Identifiable, Codable, Hashable {
    var id: UUID
    var googlePlaceId: String
    var name: String // Original Google Maps name
    var customName: String? // User's custom name/title
    var address: String
    var phone: String?
    var latitude: Double
    var longitude: Double
    var category: String // AI-generated category
    var photos: [String] // URLs to photos
    var rating: Double?
    var openingHours: [String]? // Opening hours weekday descriptions
    var isOpenNow: Bool?
    var country: String? // Country extracted from address
    var city: String? // City extracted from address
    var dateCreated: Date
    var dateModified: Date

    init(googlePlaceId: String, name: String, address: String, latitude: Double, longitude: Double, phone: String? = nil, photos: [String] = [], rating: Double? = nil, openingHours: [String]? = nil, isOpenNow: Bool? = nil) {
        self.id = UUID()
        self.googlePlaceId = googlePlaceId
        self.name = name
        self.customName = nil
        self.address = address
        self.phone = phone
        self.latitude = latitude
        self.longitude = longitude
        self.category = "Uncategorized" // Will be set by AI
        self.photos = photos
        self.rating = rating
        self.openingHours = openingHours
        self.isOpenNow = isOpenNow
        self.country = nil
        self.city = nil
        self.dateCreated = Date()
        self.dateModified = Date()

        // Extract country and city from address
        (self.city, self.country) = Self.parseLocationFromAddress(address)
    }

    // Display name - shows custom name if set, otherwise original name
    var displayName: String {
        return customName ?? name
    }

    var formattedAddress: String {
        // Shorten address if too long
        if address.count > 50 {
            return String(address.prefix(50)) + "..."
        }
        return address
    }

    var formattedPhone: String? {
        guard let phone = phone else { return nil }
        // Format phone number for display
        return phone
    }

    var googleMapsURL: URL? {
        // Create Google Maps deep link using name, address, and coordinates
        // This ensures the exact location opens with full details
        let query = "\(displayName) \(address)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "comgooglemaps://?q=\(query)&center=\(latitude),\(longitude)")
    }

    var appleMapsURL: URL? {
        // Fallback to Apple Maps
        let query = displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "maps://?q=\(query)&ll=\(latitude),\(longitude)")
    }

    // MARK: - Location Parsing

    /// Parse city and country from formatted address
    /// Google Places format: "Street Address, City, State/Province PostalCode, Country"
    /// We extract the State/Province as the main filter (e.g., "Ontario", "California")
    /// - Parameter address: The formatted address string
    /// - Returns: Tuple of (stateOrProvince, country)
    static func parseLocationFromAddress(_ address: String) -> (city: String?, country: String?) {
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else {
            return (nil, nil)
        }

        // Last component is always country
        let country = components.last

        // State/Province with postal code is typically the 3rd-to-last component
        // Format: "State/Province PostalCode" or just "State/Province"
        // We need to extract just the state/province, not the postal code
        let stateWithPostal = components[components.count - 2]

        // Split by space and filter out postal codes (all digits or postal code patterns)
        let stateComponents = stateWithPostal.split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }

        var city: String? = nil

        // Find the first component that's not a postal code (not all digits, not postal code format)
        for component in stateComponents {
            // Skip if it looks like a postal code (all digits, or contains digits/letters like M5V)
            let isPostalCode = component.range(of: "^[A-Z0-9]{3,}$", options: .regularExpression) != nil ||
                              component.range(of: "^\\d{5}(-\\d{4})?$", options: .regularExpression) != nil

            if !isPostalCode && component.count > 1 {
                city = component
                break
            }
        }

        // If we couldn't find state/province, fall back to the full component (without postal)
        if city == nil && !stateWithPostal.isEmpty {
            // Try to take everything before the postal code
            if let postalRange = stateWithPostal.range(of: " [A-Z0-9]{3,}$", options: .regularExpression) {
                city = String(stateWithPostal[..<postalRange.lowerBound])
            } else {
                city = stateWithPostal
            }
        }

        return (city, country)
    }
}

struct PlaceSearchResult: Identifiable, Codable {
    let id: String // Google Place ID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let types: [String]
    var isSaved: Bool = false
}

// MARK: - Locations Manager

class LocationsManager: ObservableObject {
    static let shared = LocationsManager()

    @Published var savedPlaces: [SavedPlace] = []
    @Published var searchHistory: [PlaceSearchResult] = []
    @Published var isLoading = false
    @Published var categories: Set<String> = []
    @Published var countries: Set<String> = []
    @Published var cities: Set<String> = []

    private let placesKey = "SavedPlaces"
    private let searchHistoryKey = "MapsSearchHistory"
    private let authManager = AuthenticationManager.shared

    // Cache to prevent repeated opening hours refreshes during the same session
    private var hasRefreshedOpeningHoursThisSession = false

    private init() {
        loadSavedPlaces()
        loadSearchHistory()

        // Don't load from Supabase here - wait for authentication!
        // The app will call loadPlacesFromSupabase() after user authenticates
        // This ensures EncryptionManager.setupEncryption() is called FIRST
    }

    // MARK: - Search History Management

    func addToSearchHistory(_ result: PlaceSearchResult) {
        // Remove if already exists to avoid duplicates
        searchHistory.removeAll { $0.id == result.id }

        // Add to beginning (most recent first)
        searchHistory.insert(result, at: 0)

        // Keep only last 50 searches
        if searchHistory.count > 50 {
            searchHistory = Array(searchHistory.prefix(50))
        }

        saveSearchHistory()
    }

    func getRecentSearches(limit: Int = 10) -> [PlaceSearchResult] {
        return Array(searchHistory.prefix(limit))
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }

    private func saveSearchHistory() {
        if let encoded = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(encoded, forKey: searchHistoryKey)
        }
    }

    private func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: searchHistoryKey),
           let decoded = try? JSONDecoder().decode([PlaceSearchResult].self, from: data) {
            searchHistory = decoded
        }
    }

    // MARK: - Data Persistence

    private func savePlacesToStorage() {
        if let encoded = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(encoded, forKey: placesKey)
        }

        // Update categories, countries, and cities sets
        categories = Set(savedPlaces.map { $0.category })
        countries = Set(savedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
        cities = Set(savedPlaces.compactMap { $0.city }.filter { !$0.isEmpty })
    }

    private func loadSavedPlaces() {
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let decodedPlaces = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            // Always re-parse location data to ensure correct formatting (no postal codes)
            var migratedPlaces = decodedPlaces
            var needsSave = false

            for i in 0..<migratedPlaces.count {
                let (city, country) = SavedPlace.parseLocationFromAddress(migratedPlaces[i].address)

                // Update if location data changed or was missing
                if migratedPlaces[i].city != city || migratedPlaces[i].country != country {
                    migratedPlaces[i].city = city
                    migratedPlaces[i].country = country
                    needsSave = true
                }
            }

            self.savedPlaces = migratedPlaces
            self.categories = Set(migratedPlaces.map { $0.category })
            self.countries = Set(migratedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
            self.cities = Set(migratedPlaces.compactMap { $0.city }.filter { !$0.isEmpty })

            // Save migrated data
            if needsSave {
                savePlacesToStorage()
            }
        }
    }

    // MARK: - Place Operations

    func addPlace(_ place: SavedPlace) {
        savedPlaces.append(place)
        savePlacesToStorage()

        // Sync with Supabase
        Task {
            await savePlaceToSupabase(place)
        }
    }

    func updatePlace(_ place: SavedPlace) {
        if let index = savedPlaces.firstIndex(where: { $0.id == place.id }) {
            var updatedPlace = place
            updatedPlace.dateModified = Date()
            savedPlaces[index] = updatedPlace
            savePlacesToStorage()

            // Sync with Supabase
            Task {
                await updatePlaceInSupabase(updatedPlace)
            }
        }
    }

    func deletePlace(_ place: SavedPlace) {
        savedPlaces.removeAll { $0.id == place.id }
        savePlacesToStorage()

        // Sync with Supabase
        Task {
            await deletePlaceFromSupabase(place.id)
        }
    }

    func isPlaceSaved(googlePlaceId: String) -> Bool {
        return savedPlaces.contains { $0.googlePlaceId == googlePlaceId }
    }

    // MARK: - Filtering and Search

    func getPlaces(for category: String?) -> [SavedPlace] {
        if let category = category {
            return savedPlaces.filter { $0.category == category }
                .sorted { $0.dateModified > $1.dateModified }
        }
        return savedPlaces.sorted { $0.dateModified > $1.dateModified }
    }

    func searchPlaces(query: String) -> [SavedPlace] {
        if query.isEmpty {
            return savedPlaces.sorted { $0.dateModified > $1.dateModified }
        }

        return savedPlaces.filter { place in
            place.name.localizedCaseInsensitiveContains(query) ||
            place.address.localizedCaseInsensitiveContains(query) ||
            place.category.localizedCaseInsensitiveContains(query)
        }.sorted { $0.dateModified > $1.dateModified }
    }

    // MARK: - Location Filtering

    /// Filter places by country and/or city
    /// - Parameters:
    ///   - country: Optional country filter
    ///   - city: Optional city filter
    /// - Returns: Array of filtered SavedPlace objects
    func getPlaces(country: String? = nil, city: String? = nil) -> [SavedPlace] {
        var filtered = savedPlaces

        if let country = country, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        if let city = city, !city.isEmpty {
            filtered = filtered.filter { $0.city == city }
        }

        return filtered.sorted { $0.dateModified > $1.dateModified }
    }

    /// Get folders (categories) with optional country and city filters
    /// - Parameters:
    ///   - country: Optional country filter
    ///   - city: Optional city filter
    /// - Returns: Set of category names
    func getCategories(country: String? = nil, city: String? = nil) -> Set<String> {
        let filtered = getPlaces(country: country, city: city)
        return Set(filtered.map { $0.category })
    }

    /// Get all cities in a specific country
    /// - Parameter country: The country to filter by
    /// - Returns: Set of city names in that country
    func getCities(in country: String? = nil) -> Set<String> {
        var filtered = savedPlaces

        if let country = country, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        return Set(filtered.compactMap { $0.city }.filter { !$0.isEmpty })
    }

    // MARK: - Nearby Places

    /// Get places within a certain radius of the current location (OLD METHOD - uses distance)
    /// - Parameters:
    ///   - currentLocation: The user's current location
    ///   - radiusInKm: The search radius in kilometers (default: 20km)
    ///   - category: Optional category filter
    /// - Returns: Array of SavedPlace objects sorted by distance (closest first)
    func getNearbyPlaces(from currentLocation: CLLocation, radiusInKm: Double = 20.0, category: String? = nil) -> [SavedPlace] {
        let radiusInMeters = radiusInKm * 1000.0

        var places = savedPlaces

        // Filter by category if specified
        if let category = category {
            places = places.filter { $0.category == category }
        }

        // Filter places within radius and calculate distances
        let nearbyPlaces = places.compactMap { place -> (place: SavedPlace, distance: Double)? in
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)

            // Return place if within radius
            if distance <= radiusInMeters {
                return (place, distance)
            }
            return nil
        }

        // Sort by distance (closest first) and return just the places
        return nearbyPlaces.sorted { $0.distance < $1.distance }
            .map { $0.place }
    }

    /// Get places within a certain driving time from current location
    /// - Parameters:
    ///   - currentLocation: The user's current location
    ///   - maxTravelTimeMinutes: Maximum travel time in minutes (e.g., 10, 20, 30)
    ///   - category: Optional category filter
    /// - Returns: Array of SavedPlace objects sorted by ETA (fastest first)
    func getNearbyPlacesByETA(from currentLocation: CLLocation, maxTravelTimeMinutes: Int, category: String? = nil) async -> [SavedPlace] {
        var places = savedPlaces

        // Filter by category if specified
        if let category = category {
            places = places.filter { $0.category == category }
        }

        // First, filter by distance to reduce number of ETA requests
        // Use a rough estimate: assume average speed of 40 km/h
        let estimatedMaxDistance = Double(maxTravelTimeMinutes) * (40.0 / 60.0) * 1000.0 // in meters
        let distanceFiltered = places.filter { place in
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            return distance <= estimatedMaxDistance * 1.5 // 1.5x buffer for non-straight routes
        }

        // Calculate ETA for filtered places with rate limiting
        var placesWithETA: [(place: SavedPlace, eta: TimeInterval)] = []

        // Process in batches of 5 to avoid rate limiting
        let batchSize = 5
        let batches = stride(from: 0, to: distanceFiltered.count, by: batchSize).map {
            Array(distanceFiltered[$0..<min($0 + batchSize, distanceFiltered.count)])
        }

        for batch in batches {
            // Process batch concurrently
            await withTaskGroup(of: (SavedPlace, TimeInterval).self) { group in
                for place in batch {
                    group.addTask {
                        if let eta = await self.calculateETA(from: currentLocation, to: place) {
                            return (place, eta)
                        }
                        // Fallback to distance-based estimation if ETA fails
                        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                        let distance = currentLocation.distance(from: placeLocation)
                        // Assume average speed of 30 km/h in city
                        let estimatedETA = (distance / 1000.0) / 30.0 * 3600.0 // seconds
                        return (place, estimatedETA)
                    }
                }

                for await result in group {
                    let (place, eta) = result
                    let etaMinutes = eta / 60.0
                    // Only include places within the time limit
                    if etaMinutes <= Double(maxTravelTimeMinutes) {
                        placesWithETA.append((place, eta))
                    }
                }
            }

            // Add delay between batches to avoid rate limiting
            if batch != batches.last {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
            }
        }

        // Sort by ETA (fastest first) and return just the places
        return placesWithETA.sorted { $0.eta < $1.eta }
            .map { $0.place }
    }

    /// Calculate actual driving ETA to a place using MapKit
    /// - Parameters:
    ///   - currentLocation: User's current location
    ///   - place: The destination place
    /// - Returns: ETA in seconds, or nil if calculation fails
    private func calculateETA(from currentLocation: CLLocation, to place: SavedPlace) async -> TimeInterval? {
        let sourcePlacemark = MKPlacemark(coordinate: currentLocation.coordinate)
        let destinationPlacemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        )

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        request.transportType = .automobile

        let directions = MKDirections(request: request)

        // Add timeout to avoid hanging requests
        return await withTaskGroup(of: TimeInterval?.self) { group in
            group.addTask {
                do {
                    let response = try await directions.calculate()
                    if let route = response.routes.first {
                        return route.expectedTravelTime
                    }
                } catch {
                    // Silently fail - we'll use distance-based estimation as fallback
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second timeout
                return nil
            }

            // Return first result (either ETA or timeout)
            if let result = await group.next() {
                group.cancelAll()
                return result
            }

            return nil
        }
    }

    /// Format distance in a human-readable way
    /// - Parameter meters: Distance in meters
    /// - Returns: Formatted string like "1.2 km" or "500 m"
    static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }

    /// Calculate distance between current location and a saved place
    /// - Parameters:
    ///   - place: The saved place
    ///   - currentLocation: The user's current location
    /// - Returns: Distance in meters
    static func distance(from place: SavedPlace, to currentLocation: CLLocation) -> Double {
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return currentLocation.distance(from: placeLocation)
    }

    // MARK: - Category Management

    func categorizePlace(_ place: SavedPlace, with category: String) async {
        if let index = savedPlaces.firstIndex(where: { $0.id == place.id }) {
            savedPlaces[index].category = category
            savePlacesToStorage()

            // Sync with Supabase
            await updatePlaceInSupabase(savedPlaces[index])
        }
    }

    // MARK: - Supabase Sync

    private func savePlaceToSupabase(_ place: SavedPlace) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        print("💾 Saving place to Supabase - User ID: \(userId.uuidString), Place ID: \(place.id.uuidString)")

        let formatter = ISO8601DateFormatter()
        var placeData: [String: PostgREST.AnyJSON] = [
            "id": .string(place.id.uuidString),
            "user_id": .string(userId.uuidString),
            "google_place_id": .string(place.googlePlaceId),
            "name": .string(place.name),
            "custom_name": place.customName != nil ? .string(place.customName!) : .null,
            "address": .string(place.address),
            "phone": place.phone != nil ? .string(place.phone!) : .null,
            "latitude": .double(place.latitude),
            "longitude": .double(place.longitude),
            "category": .string(place.category),
            "country": place.country != nil ? .string(place.country!) : .null,
            "city": place.city != nil ? .string(place.city!) : .null,
            "photos": .string(try! JSONEncoder().encode(place.photos).base64EncodedString()),
            "rating": place.rating != nil ? .double(place.rating!) : .null,
            "date_created": .string(formatter.string(from: place.dateCreated)),
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        // Add opening_hours and is_open_now (migration completed)
        placeData["opening_hours"] = place.openingHours != nil ? .string(try! JSONEncoder().encode(place.openingHours!).base64EncodedString()) : .null
        placeData["is_open_now"] = place.isOpenNow != nil ? .bool(place.isOpenNow!) : .null

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .insert(placeData)
                .execute()
        } catch {
            print("❌ Error saving place to Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func updatePlaceInSupabase(_ place: SavedPlace) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        let formatter = ISO8601DateFormatter()
        var placeData: [String: PostgREST.AnyJSON] = [
            "name": .string(place.name),
            "custom_name": place.customName != nil ? .string(place.customName!) : .null,
            "address": .string(place.address),
            "phone": place.phone != nil ? .string(place.phone!) : .null,
            "latitude": .double(place.latitude),
            "longitude": .double(place.longitude),
            "category": .string(place.category),
            "country": place.country != nil ? .string(place.country!) : .null,
            "city": place.city != nil ? .string(place.city!) : .null,
            "photos": .string(try! JSONEncoder().encode(place.photos).base64EncodedString()),
            "rating": place.rating != nil ? .double(place.rating!) : .null,
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        // Add opening_hours and is_open_now (migration completed)
        placeData["opening_hours"] = place.openingHours != nil ? .string(try! JSONEncoder().encode(place.openingHours!).base64EncodedString()) : .null
        placeData["is_open_now"] = place.isOpenNow != nil ? .bool(place.isOpenNow!) : .null

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .update(placeData)
                .eq("id", value: place.id.uuidString)
                .execute()
        } catch {
            print("❌ Error updating place in Supabase: \(error)")
        }
    }

    private func deletePlaceFromSupabase(_ placeId: UUID) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .delete()
                .eq("id", value: placeId.uuidString)
                .execute()
        } catch {
            print("❌ Error deleting place from Supabase: \(error)")
        }
    }

    func loadPlacesFromSupabase() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }

        guard isAuthenticated, let userId = userId else {
            print("User not authenticated, loading local places only")
            return
        }

        // CRITICAL: Ensure encryption key is initialized before loading
        // Wait for EncryptionManager to be ready (max 2 seconds)
        var attempts = 0
        while await EncryptionManager.shared.isKeyInitialized == false && attempts < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }

        if await !EncryptionManager.shared.isKeyInitialized {
            print("⚠️ Encryption key not initialized after 2 seconds, loading places anyway")
        }

        print("📥 Loading places from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [PlaceSupabaseData] = try await client
                .from("saved_places")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Received \(response.count) places from Supabase")

            // Parse and decrypt places before updating MainActor
            var parsedPlaces: [SavedPlace] = []
            for supabasePlace in response {
                if let place = await parsePlaceFromSupabase(supabasePlace) {
                    parsedPlaces.append(place)
                }
            }

            // Always re-parse location data to ensure correct formatting (no postal codes)
            var migratedPlaces = parsedPlaces
            for i in 0..<migratedPlaces.count {
                let (city, country) = SavedPlace.parseLocationFromAddress(migratedPlaces[i].address)
                migratedPlaces[i].city = city
                migratedPlaces[i].country = country
            }

            await MainActor.run {
                if !migratedPlaces.isEmpty {
                    self.savedPlaces = migratedPlaces
                    self.categories = Set(migratedPlaces.map { $0.category })
                    self.countries = Set(migratedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
                    self.cities = Set(migratedPlaces.compactMap { $0.city }.filter { !$0.isEmpty })
                    savePlacesToStorage()
                } else if response.isEmpty {
                    print("ℹ️ No places in Supabase, keeping \(self.savedPlaces.count) local places")
                } else {
                    print("⚠️ Failed to parse any places from Supabase, keeping \(self.savedPlaces.count) local places")
                }
            }
        } catch {
            print("❌ Error loading places from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func parsePlaceFromSupabase(_ data: PlaceSupabaseData) async -> SavedPlace? {
        guard let id = UUID(uuidString: data.id) else {
            print("❌ Failed to parse place ID: \(data.id)")
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var dateCreated = formatter.date(from: data.date_created)
        var dateModified = formatter.date(from: data.date_modified)

        if dateCreated == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateCreated = formatter.date(from: data.date_created)
        }

        if dateModified == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateModified = formatter.date(from: data.date_modified)
        }

        guard let dateCreated = dateCreated, let dateModified = dateModified else {
            print("❌ Failed to parse dates for place: \(data.name)")
            return nil
        }

        // Decode photos array
        var photos: [String] = []
        if let photosData = Data(base64Encoded: data.photos),
           let decodedPhotos = try? JSONDecoder().decode([String].self, from: photosData) {
            photos = decodedPhotos
        }

        // Decode opening hours array
        var openingHours: [String]? = nil
        if let hoursString = data.opening_hours,
           let hoursData = Data(base64Encoded: hoursString),
           let decodedHours = try? JSONDecoder().decode([String].self, from: hoursData) {
            openingHours = decodedHours
        }

        var place = SavedPlace(
            googlePlaceId: data.google_place_id,
            name: data.name,
            address: data.address,
            latitude: data.latitude,
            longitude: data.longitude,
            phone: data.phone,
            photos: photos,
            rating: data.rating,
            openingHours: openingHours,
            isOpenNow: data.is_open_now
        )
        place.id = id
        place.customName = data.custom_name
        place.category = data.category
        place.country = data.country
        place.city = data.city
        place.dateCreated = dateCreated
        place.dateModified = dateModified

        // DECRYPT place name, address, and custom name after loading from Supabase
        do {
            place = try await decryptSavedPlaceAfterLoading(place)
        } catch {
            print("⚠️ Could not decrypt place \(id): \(error.localizedDescription)")
            print("   Place will be returned unencrypted (legacy data)")
        }

        return place
    }

    func syncPlacesOnLogin() async {
        await loadPlacesFromSupabase()
    }

    // MARK: - Refresh Opening Hours

    /// Refresh opening hours for all saved places that are missing this data
    func refreshOpeningHoursForAllPlaces() async {
        // Skip if already refreshed in this session to avoid expensive API calls on view reappear
        if hasRefreshedOpeningHoursThisSession {
            print("⏭️ Opening hours already refreshed this session, skipping...")
            return
        }

        // Mark as refreshed to prevent repeated calls
        hasRefreshedOpeningHoursThisSession = true

        // Refresh all places to get the most current open/closed status
        print("🔄 Refreshing opening hours for \(savedPlaces.count) places...")

        for place in savedPlaces {
            do {
                // Fetch updated details from Google Places API
                let placeDetails = try await GoogleMapsService.shared.getPlaceDetails(placeId: place.googlePlaceId)

                // Update the saved place with new data
                if let index = savedPlaces.firstIndex(where: { $0.id == place.id }) {
                    savedPlaces[index].isOpenNow = placeDetails.isOpenNow
                    savedPlaces[index].openingHours = placeDetails.openingHours
                }

                print("✅ Updated opening hours for: \(place.name)")

                // Small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            } catch {
                print("⚠️ Failed to refresh opening hours for \(place.name): \(error)")
            }
        }

        // Save updated data
        await MainActor.run {
            savePlacesToStorage()
            print("✅ Opening hours refresh complete")
        }

        // Sync to Supabase
        for place in savedPlaces {
            await updatePlaceInSupabase(place)
        }
    }
}

// MARK: - User Location Preferences

struct UserLocationPreferences: Codable {
    var location1Address: String?
    var location1Latitude: Double?
    var location1Longitude: Double?
    var location1Icon: String?
    var location2Address: String?
    var location2Latitude: Double?
    var location2Longitude: Double?
    var location2Icon: String?
    var location3Address: String?
    var location3Latitude: Double?
    var location3Longitude: Double?
    var location3Icon: String?
    var isFirstTimeSetup: Bool

    // Computed properties for coordinates
    var location1Coordinate: CLLocationCoordinate2D? {
        guard let lat = location1Latitude, let lon = location1Longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var location2Coordinate: CLLocationCoordinate2D? {
        guard let lat = location2Latitude, let lon = location2Longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var location3Coordinate: CLLocationCoordinate2D? {
        guard let lat = location3Latitude, let lon = location3Longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init() {
        self.isFirstTimeSetup = true
        self.location1Icon = "house.fill"
        self.location2Icon = "briefcase.fill"
        self.location3Icon = "fork.knife"
    }
}

// MARK: - Supabase Data Structures

struct PlaceSupabaseData: Codable {
    let id: String
    let user_id: String
    let google_place_id: String
    let name: String
    let custom_name: String?
    let address: String
    let phone: String?
    let latitude: Double
    let longitude: Double
    let category: String
    let country: String?
    let city: String?
    let photos: String // Base64 encoded JSON array
    let rating: Double?
    let opening_hours: String? // Base64 encoded JSON array
    let is_open_now: Bool?
    let date_created: String
    let date_modified: String
}

struct UserProfileSupabaseData: Codable {
    let id: String
    let email: String?
    let full_name: String?
    let location1_address: String?
    let location1_latitude: Double?
    let location1_longitude: Double?
    let location1_icon: String?
    let location2_address: String?
    let location2_latitude: Double?
    let location2_longitude: Double?
    let location2_icon: String?
    let location3_address: String?
    let location3_latitude: Double?
    let location3_longitude: Double?
    let location3_icon: String?
    let is_first_time_setup: Bool?

    func toLocationPreferences() -> UserLocationPreferences {
        var prefs = UserLocationPreferences()
        prefs.location1Address = location1_address
        prefs.location1Latitude = location1_latitude
        prefs.location1Longitude = location1_longitude
        prefs.location1Icon = location1_icon ?? "house.fill"
        prefs.location2Address = location2_address
        prefs.location2Latitude = location2_latitude
        prefs.location2Longitude = location2_longitude
        prefs.location2Icon = location2_icon ?? "briefcase.fill"
        prefs.location3Address = location3_address
        prefs.location3Latitude = location3_latitude
        prefs.location3Longitude = location3_longitude
        prefs.location3Icon = location3_icon ?? "fork.knife"
        prefs.isFirstTimeSetup = is_first_time_setup ?? true
        return prefs
    }
}
