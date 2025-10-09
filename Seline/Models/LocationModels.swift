import Foundation
import SwiftUI
import PostgREST
import CoreLocation

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
    var dateCreated: Date
    var dateModified: Date

    init(googlePlaceId: String, name: String, address: String, latitude: Double, longitude: Double, phone: String? = nil, photos: [String] = [], rating: Double? = nil) {
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
        self.dateCreated = Date()
        self.dateModified = Date()
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
        // Create Google Maps deep link
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "comgooglemaps://?q=\(query)&center=\(latitude),\(longitude)")
    }

    var appleMapsURL: URL? {
        // Fallback to Apple Maps
        return URL(string: "maps://?q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&ll=\(latitude),\(longitude)")
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

    private let placesKey = "SavedPlaces"
    private let searchHistoryKey = "MapsSearchHistory"
    private let authManager = AuthenticationManager.shared

    private init() {
        loadSavedPlaces()
        loadSearchHistory()

        // Load places from Supabase if user is authenticated
        Task {
            await loadPlacesFromSupabase()
        }
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

        // Update categories set
        categories = Set(savedPlaces.map { $0.category })
    }

    private func loadSavedPlaces() {
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let decodedPlaces = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            self.savedPlaces = decodedPlaces
            self.categories = Set(decodedPlaces.map { $0.category })
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
        let placeData: [String: PostgREST.AnyJSON] = [
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
            "photos": .string(try! JSONEncoder().encode(place.photos).base64EncodedString()),
            "rating": place.rating != nil ? .double(place.rating!) : .null,
            "date_created": .string(formatter.string(from: place.dateCreated)),
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .insert(placeData)
                .execute()
            print("✅ Place saved to Supabase: \(place.name)")
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
        let placeData: [String: PostgREST.AnyJSON] = [
            "name": .string(place.name),
            "custom_name": place.customName != nil ? .string(place.customName!) : .null,
            "address": .string(place.address),
            "phone": place.phone != nil ? .string(place.phone!) : .null,
            "latitude": .double(place.latitude),
            "longitude": .double(place.longitude),
            "category": .string(place.category),
            "photos": .string(try! JSONEncoder().encode(place.photos).base64EncodedString()),
            "rating": place.rating != nil ? .double(place.rating!) : .null,
            "date_modified": .string(formatter.string(from: place.dateModified))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("saved_places")
                .update(placeData)
                .eq("id", value: place.id.uuidString)
                .execute()
            print("✅ Place updated in Supabase: \(place.name)")
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
            print("✅ Place deleted from Supabase")
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

            await MainActor.run {
                if !response.isEmpty {
                    let parsedPlaces = response.compactMap { supabasePlace in
                        parsePlaceFromSupabase(supabasePlace)
                    }

                    if !parsedPlaces.isEmpty {
                        self.savedPlaces = parsedPlaces
                        self.categories = Set(parsedPlaces.map { $0.category })
                        savePlacesToStorage()
                        print("✅ Loaded \(parsedPlaces.count) places from Supabase")
                    } else {
                        print("⚠️ Failed to parse any places from Supabase, keeping \(self.savedPlaces.count) local places")
                    }
                } else {
                    print("ℹ️ No places in Supabase, keeping \(self.savedPlaces.count) local places")
                }
            }
        } catch {
            print("❌ Error loading places from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func parsePlaceFromSupabase(_ data: PlaceSupabaseData) -> SavedPlace? {
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

        var place = SavedPlace(
            googlePlaceId: data.google_place_id,
            name: data.name,
            address: data.address,
            latitude: data.latitude,
            longitude: data.longitude,
            phone: data.phone,
            photos: photos,
            rating: data.rating
        )
        place.id = id
        place.customName = data.custom_name
        place.category = data.category
        place.dateCreated = dateCreated
        place.dateModified = dateModified

        print("✅ Successfully parsed place: \(place.name)")
        return place
    }

    func syncPlacesOnLogin() async {
        await loadPlacesFromSupabase()
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
    let photos: String // Base64 encoded JSON array
    let rating: Double?
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
