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
    var rating: Double? // Google's rating
    var openingHours: [String]? // Opening hours weekday descriptions
    var isOpenNow: Bool?
    var country: String? // Country extracted from address
    var province: String? // Province/State extracted from address
    var city: String? // City extracted from address
    var userRating: Int? // User's personal rating (1-10)
    var userNotes: String? // User's personal notes
    var userCuisine: String? // User's manual cuisine assignment
    var isFavourite: Bool // Whether this location is marked as favourite
    var userIcon: String? // User's selected SF Symbol icon name
    var customGeofenceRadius: Double? // User's custom geofence radius in meters (optional override) - NEW
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
        self.province = nil
        self.city = nil
        self.userRating = nil
        self.userNotes = nil
        self.userCuisine = nil
        self.isFavourite = false
        self.userIcon = nil
        self.customGeofenceRadius = nil // NEW: User can override geofence radius
        self.dateCreated = Date()
        self.dateModified = Date()

        // Extract country, province, and city from address
        (self.city, self.province, self.country) = Self.parseLocationFromAddress(address)
    }

    // Get the icon to display - either user's selected icon or auto-detected based on location name
    func getDisplayIcon() -> String {
        // If user has selected a custom icon, use that
        if let userIcon = userIcon {
            return userIcon
        }

        // Otherwise, auto-detect based on location name
        let lowerName = displayName.lowercased()

        if lowerName.contains("home") {
            return "house.fill"
        } else if lowerName.contains("work") || lowerName.contains("office") || lowerName.contains("briefcase") {
            return "briefcase.fill"
        } else if lowerName.contains("gym") || lowerName.contains("fitness") {
            return "dumbbell.fill"
        } else if lowerName.contains("pizza") {
            return "square.fill"
        } else if lowerName.contains("burger") || lowerName.contains("hamburger") {
            return "circle.fill"
        } else if lowerName.contains("pasta") {
            return "triangle.fill"
        } else if lowerName.contains("shawarma") || lowerName.contains("kebab") {
            return "diamond.fill"
        } else if lowerName.contains("jamaican") || lowerName.contains("reggae") {
            return "pentagon.fill"
        } else if lowerName.contains("steak") || lowerName.contains("barbecue") || lowerName.contains("bbq") {
            return "hexagon.fill"
        } else if lowerName.contains("mexican") || lowerName.contains("taco") {
            return "sun.max.fill"
        } else if lowerName.contains("chinese") {
            return "cloud.fill"
        } else if lowerName.contains("haircut") || lowerName.contains("barber") || lowerName.contains("salon") {
            return "scissors"
        } else if lowerName.contains("hotel") || lowerName.contains("motel") {
            return "building.fill"
        } else if lowerName.contains("mosque") {
            return "building.2.fill"
        } else if lowerName.contains("smoke") || lowerName.contains("hookah") || lowerName.contains("shisha") {
            return "flame.fill"
        } else if lowerName.contains("restaurant") || lowerName.contains("diner") || lowerName.contains("cafe") || lowerName.contains("food") {
            return "fork.knife"
        } else if lowerName.contains("park") || lowerName.contains("outdoor") {
            return "tree.fill"
        } else if lowerName.contains("hospital") || lowerName.contains("clinic") || lowerName.contains("medical") {
            return "heart.fill"
        } else if lowerName.contains("shop") || lowerName.contains("store") || lowerName.contains("mall") {
            return "bag.fill"
        } else if lowerName.contains("school") || lowerName.contains("university") {
            return "book.fill"
        } else {
            return "mappin.circle.fill"
        }
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
        // Create Google Maps deep link using address and coordinates only
        // Only the address ensures proper search results in Google Maps
        let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "comgooglemaps://?q=\(query)&center=\(latitude),\(longitude)")
    }

    var appleMapsURL: URL? {
        // Fallback to Apple Maps
        let query = displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "maps://?q=\(query)&ll=\(latitude),\(longitude)")
    }

    // MARK: - Location Parsing

    /// Parse city, province/state, and country from formatted address
    /// Google Places format: "Street Address, City, State/Province PostalCode, Country"
    /// Example: "123 Main St, Mississauga, ON M5H 2R2, Canada"
    /// - Parameter address: The formatted address string
    /// - Returns: Tuple of (city, province, country)
    static func parseLocationFromAddress(_ address: String) -> (city: String?, province: String?, country: String?) {
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else {
            return (nil, nil, nil)
        }

        // Last component is always country
        let country = components.last

        // State/Province with postal code is typically the 3rd-to-last component
        // Format: "State/Province PostalCode" or just "State/Province"
        let stateWithPostal = components[components.count - 2]

        // Extract province/state by removing postal code
        var province: String? = nil

        // Remove postal code patterns at the end
        // Matches: US format (12345 or 12345-1234), Canadian format (M5H 2R2)
        let postalCodePattern = " (?:\\d{5}(?:-\\d{4})?|[A-Z]\\d[A-Z]\\s\\d[A-Z]\\d)$"
        if let postalRange = stateWithPostal.range(of: postalCodePattern, options: .regularExpression) {
            province = String(stateWithPostal[..<postalRange.lowerBound])
        } else {
            province = stateWithPostal
        }

        // City is typically the 2nd-to-last component (before state/province)
        var city: String? = nil
        if components.count >= 3 {
            city = components[components.count - 3]
        }

        return (city, province, country)
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
    @Published var categories: [String] = []
    @Published var countries: Set<String> = []
    @Published var provinces: Set<String> = []
    @Published var cities: Set<String> = []

    private let placesKey = "SavedPlaces"
    private let searchHistoryKey = "MapsSearchHistory"
    private let authManager = AuthenticationManager.shared

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

        // Update categories, countries, provinces, and cities
        // Keep categories as sorted array for consistent ordering
        // IMPORTANT: Only include categories that have at least one place (auto-delete empty folders)
        let categoriesWithPlaces = Set(savedPlaces.map { $0.category })
        categories = Array(categoriesWithPlaces).sorted()
        countries = Set(savedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
        provinces = Set(savedPlaces.compactMap { $0.province }.filter { !$0.isEmpty })
        cities = Set(savedPlaces.compactMap { $0.city }.filter { !$0.isEmpty })
    }

    private func loadSavedPlaces() {
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let decodedPlaces = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            // Always re-parse location data to ensure correct formatting (no postal codes)
            var migratedPlaces = decodedPlaces
            var needsSave = false

            for i in 0..<migratedPlaces.count {
                let (city, province, country) = SavedPlace.parseLocationFromAddress(migratedPlaces[i].address)

                // Update if location data changed or was missing
                if migratedPlaces[i].city != city || migratedPlaces[i].province != province || migratedPlaces[i].country != country {
                    migratedPlaces[i].city = city
                    migratedPlaces[i].province = province
                    migratedPlaces[i].country = country
                    needsSave = true
                }
            }

            self.savedPlaces = migratedPlaces
            self.categories = Array(Set(migratedPlaces.map { $0.category })).sorted()
            self.countries = Set(migratedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
            self.provinces = Set(migratedPlaces.compactMap { $0.province }.filter { !$0.isEmpty })
            self.cities = Set(migratedPlaces.compactMap { $0.city }.filter { !$0.isEmpty })

            // Save migrated data
            if needsSave {
                savePlacesToStorage()
            }
        }
    }

    // MARK: - Place Operations

    func addPlace(_ place: SavedPlace) {
        // Update on main thread for immediate UI refresh
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.savedPlaces.append(place)
            self.savePlacesToStorage()
            
            // OPTIMIZATION: Invalidate affected caches
            self.invalidateLocationCaches(for: place.id)
        }

        // Sync with Supabase
        Task {
            await savePlaceToSupabase(place)
        }
    }

    func updatePlace(_ place: SavedPlace) {
        // Update on main thread for immediate UI refresh
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.savedPlaces.firstIndex(where: { $0.id == place.id }) {
                var updatedPlace = place
                updatedPlace.dateModified = Date()
                self.savedPlaces[index] = updatedPlace
                self.savePlacesToStorage()
                
                // OPTIMIZATION: Invalidate affected caches
                self.invalidateLocationCaches(for: place.id)
            }
        }

        // Sync with Supabase
        Task {
            await updatePlaceInSupabase(place)
        }
    }

    func deletePlace(_ place: SavedPlace) {
        // Update on main thread for immediate UI refresh
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.savedPlaces.removeAll { $0.id == place.id }
            self.savePlacesToStorage()
            
            // OPTIMIZATION: Invalidate affected caches
            self.invalidateLocationCaches(for: place.id)
            
            // Clear from Google Maps cache
            GoogleMapsService.shared.clearLocationCache(for: place.googlePlaceId)
        }

        // Sync with Supabase
        Task {
            await deletePlaceFromSupabase(place.id)
        }
    }

    func updateRestaurantRating(_ placeId: UUID, rating: Int?, notes: String?, cuisine: String? = nil) {
        if let index = savedPlaces.firstIndex(where: { $0.id == placeId }) {
            savedPlaces[index].userRating = rating
            savedPlaces[index].userNotes = notes
            savedPlaces[index].userCuisine = cuisine
            savedPlaces[index].dateModified = Date()
            savePlacesToStorage()

            // OPTIMIZATION: Invalidate affected caches
            invalidateLocationCaches(for: placeId)

            // Sync with Supabase
            Task {
                await updatePlaceInSupabase(savedPlaces[index])
            }
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

    /// Filter places by country, province, and/or city
    /// - Parameters:
    ///   - country: Optional country filter
    ///   - province: Optional province/state filter
    ///   - city: Optional city filter
    /// - Returns: Array of filtered SavedPlace objects
    func getPlaces(country: String? = nil, province: String? = nil, city: String? = nil) -> [SavedPlace] {
        var filtered = savedPlaces

        if let country = country, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        if let province = province, !province.isEmpty {
            filtered = filtered.filter { $0.province == province }
        }

        if let city = city, !city.isEmpty {
            filtered = filtered.filter { $0.city == city }
        }

        return filtered.sorted { $0.dateModified > $1.dateModified }
    }

    /// Get folders (categories) with optional country, province, and city filters
    /// - Parameters:
    ///   - country: Optional country filter
    ///   - province: Optional province/state filter
    ///   - city: Optional city filter
    /// - Returns: Set of category names
    func getCategories(country: String? = nil, province: String? = nil, city: String? = nil) -> Set<String> {
        let filtered = getPlaces(country: country, province: province, city: city)
        return Set(filtered.map { $0.category })
    }

    /// Get all provinces in a specific country
    /// - Parameter country: The country to filter by
    /// - Returns: Set of province/state names in that country
    func getProvinces(in country: String? = nil) -> Set<String> {
        var filtered = savedPlaces

        if let country = country, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        return Set(filtered.compactMap { $0.province }.filter { !$0.isEmpty })
    }

    /// Get all cities in a specific country and province
    /// - Parameters:
    ///   - country: The country to filter by
    ///   - province: Optional province/state to further filter by
    /// - Returns: Set of city names in that location
    func getCities(in country: String? = nil, andProvince province: String? = nil) -> Set<String> {
        var filtered = savedPlaces

        if let country = country, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        if let province = province, !province.isEmpty {
            filtered = filtered.filter { $0.province == province }
        }

        return Set(filtered.compactMap { $0.city }.filter { !$0.isEmpty })
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

    // MARK: - Favourite Management

    func toggleFavourite(for placeId: UUID) {
        if let index = savedPlaces.firstIndex(where: { $0.id == placeId }) {
            savedPlaces[index].isFavourite.toggle()
            savedPlaces[index].dateModified = Date()
            savePlacesToStorage()

            // Sync with Supabase
            Task {
                await updatePlaceInSupabase(savedPlaces[index])
            }
        }
    }

    func getFavourites() -> [SavedPlace] {
        return savedPlaces.filter { $0.isFavourite }
            .sorted { $0.dateModified > $1.dateModified }
    }

    func getFavourites(for category: String) -> [SavedPlace] {
        return savedPlaces.filter { $0.isFavourite && $0.category == category }
            .sorted { $0.dateModified > $1.dateModified }
    }

    // MARK: - Clear Data on Logout

    func clearPlacesOnLogout() {
        savedPlaces = []
        searchHistory = []
        categories = []
        countries = []
        provinces = []
        cities = []

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: placesKey)
        UserDefaults.standard.removeObject(forKey: searchHistoryKey)

        print("🗑️ Cleared all places and search history on logout")
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
            "is_favourite": .bool(place.isFavourite),
            "date_created": .string(formatter.string(from: place.dateCreated)),
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        // Add opening_hours and is_open_now (migration completed)
        placeData["opening_hours"] = place.openingHours != nil ? .string(try! JSONEncoder().encode(place.openingHours!).base64EncodedString()) : .null
        placeData["is_open_now"] = place.isOpenNow != nil ? .bool(place.isOpenNow!) : .null

        // Add user rating and notes
        placeData["user_rating"] = place.userRating != nil ? .double(Double(place.userRating!)) : .null
        placeData["user_notes"] = place.userNotes != nil ? .string(place.userNotes!) : .null

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
            "is_favourite": .bool(place.isFavourite),
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        // Add opening_hours and is_open_now (migration completed)
        placeData["opening_hours"] = place.openingHours != nil ? .string(try! JSONEncoder().encode(place.openingHours!).base64EncodedString()) : .null
        placeData["is_open_now"] = place.isOpenNow != nil ? .bool(place.isOpenNow!) : .null

        // Add user rating and notes
        placeData["user_rating"] = place.userRating != nil ? .double(Double(place.userRating!)) : .null
        placeData["user_notes"] = place.userNotes != nil ? .string(place.userNotes!) : .null

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .update(placeData)
                .eq("id", value: place.id.uuidString)
                .select("id")  // Only return id to reduce egress
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

    // MARK: - Cache Invalidation

    /// Invalidate location-related caches when locations are modified
    private func invalidateLocationCaches(for placeId: UUID? = nil) {
        // Invalidate search cache since locations are searchable
        CacheManager.shared.invalidate(keysWithPrefix: "cache.search")

        // Invalidate today's visits cache
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysVisits)

        // If specific place ID provided, invalidate its stats
        if let placeId = placeId {
            CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.locationStats(placeId.uuidString))
        } else {
            // Otherwise invalidate all location stats
            CacheManager.shared.invalidate(keysWithPrefix: "cache.location")
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
                let (city, province, country) = SavedPlace.parseLocationFromAddress(migratedPlaces[i].address)
                migratedPlaces[i].city = city
                migratedPlaces[i].province = province
                migratedPlaces[i].country = country
            }

            await MainActor.run {
                if !migratedPlaces.isEmpty {
                    self.savedPlaces = migratedPlaces
                    self.categories = Array(Set(migratedPlaces.map { $0.category })).sorted()
                    self.countries = Set(migratedPlaces.compactMap { $0.country }.filter { !$0.isEmpty })
                    self.provinces = Set(migratedPlaces.compactMap { $0.province }.filter { !$0.isEmpty })
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
        place.isFavourite = data.is_favourite
        place.userRating = data.user_rating
        place.userNotes = data.user_notes
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

}

// MARK: - User Location Preferences

struct UserLocationPreferences: Codable, Equatable {
    var location1Name: String?
    var location1Address: String?
    var location1Latitude: Double?
    var location1Longitude: Double?
    var location1Icon: String?
    var location2Name: String?
    var location2Address: String?
    var location2Latitude: Double?
    var location2Longitude: Double?
    var location2Icon: String?
    var location3Name: String?
    var location3Address: String?
    var location3Latitude: Double?
    var location3Longitude: Double?
    var location3Icon: String?
    var location4Name: String?
    var location4Address: String?
    var location4Latitude: Double?
    var location4Longitude: Double?
    var location4Icon: String?
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

    var location4Coordinate: CLLocationCoordinate2D? {
        guard let lat = location4Latitude, let lon = location4Longitude else { return nil }
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
    let is_favourite: Bool
    let user_rating: Int?
    let user_notes: String?
    let date_created: String
    let date_modified: String
}

struct UserProfileSupabaseData: Codable {
    let id: String
    let email: String?
    let full_name: String?
    let location1_name: String?
    let location1_address: String?
    let location1_latitude: Double?
    let location1_longitude: Double?
    let location1_icon: String?
    let location2_name: String?
    let location2_address: String?
    let location2_latitude: Double?
    let location2_longitude: Double?
    let location2_icon: String?
    let location3_name: String?
    let location3_address: String?
    let location3_latitude: Double?
    let location3_longitude: Double?
    let location3_icon: String?
    let location4_name: String?
    let location4_address: String?
    let location4_latitude: Double?
    let location4_longitude: Double?
    let location4_icon: String?
    let is_first_time_setup: Bool?

    func toLocationPreferences() -> UserLocationPreferences {
        var prefs = UserLocationPreferences()
        prefs.location1Name = location1_name
        prefs.location1Address = location1_address
        prefs.location1Latitude = location1_latitude
        prefs.location1Longitude = location1_longitude
        prefs.location1Icon = location1_icon ?? "house.fill"
        prefs.location2Name = location2_name
        prefs.location2Address = location2_address
        prefs.location2Latitude = location2_latitude
        prefs.location2Longitude = location2_longitude
        prefs.location2Icon = location2_icon ?? "briefcase.fill"
        prefs.location3Name = location3_name
        prefs.location3Address = location3_address
        prefs.location3Latitude = location3_latitude
        prefs.location3Longitude = location3_longitude
        prefs.location3Icon = location3_icon ?? "fork.knife"
        prefs.location4Name = location4_name
        prefs.location4Address = location4_address
        prefs.location4Latitude = location4_latitude
        prefs.location4Longitude = location4_longitude
        prefs.location4Icon = location4_icon
        prefs.isFirstTimeSetup = is_first_time_setup ?? true
        return prefs
    }
}

// MARK: - Database Row Models for Advanced Tracking

/// Database row model for location_visits table
struct LocationVisitRow: Codable {
    let id: UUID
    let userId: UUID
    let placeId: UUID
    let entryTime: Date
    let exitTime: Date?
    let durationMinutes: Int?
    let sessionId: UUID?
    let dayOfWeek: String
    let timeOfDay: String
    let month: Int
    let year: Int
    let confidenceScore: Double?
    let mergeReason: String?

    // Advanced tracking fields
    let signalDrops: Int?
    let motionValidated: Bool?
    let stationaryPercentage: Double?
    let wifiMatched: Bool?
    let isOutlier: Bool?
    let isCommuteStop: Bool?
    let semanticValid: Bool?

    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case placeId = "place_id"
        case entryTime = "entry_time"
        case exitTime = "exit_time"
        case durationMinutes = "duration_minutes"
        case sessionId = "session_id"
        case dayOfWeek = "day_of_week"
        case timeOfDay = "time_of_day"
        case month, year
        case confidenceScore = "confidence_score"
        case mergeReason = "merge_reason"

        case signalDrops = "signal_drops"
        case motionValidated = "motion_validated"
        case stationaryPercentage = "stationary_percentage"
        case wifiMatched = "wifi_matched"
        case isOutlier = "is_outlier"
        case isCommuteStop = "is_commute_stop"
        case semanticValid = "semantic_valid"

        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Database row model for places table
struct PlaceRow: Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let category: String?
    let customGeofenceRadius: Double?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case address
        case latitude
        case longitude
        case category
        case customGeofenceRadius = "custom_geofence_radius"
        case createdAt = "created_at"
    }
}
