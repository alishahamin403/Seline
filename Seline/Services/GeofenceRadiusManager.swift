import CoreLocation
import PostgREST

// MARK: - GeofenceRadiusManager
//
// Intelligently determines geofence radius based on location type and user preferences
// Smart auto-detection reduces false positives/negatives while allowing user overrides

@MainActor
class GeofenceRadiusManager {
    static let shared = GeofenceRadiusManager()

    // Default radius for all location types (fallback)
    private let defaultRadius: CLLocationDistance = 200

    // Smart auto-detected radiuses by category
    private let radiusByCategory: [String: CLLocationDistance] = [
        // Residential
        "Home": 500,
        "Residence": 500,
        "Apartment": 500,

        // Work
        "Work": 300,
        "Office": 300,
        "Workplace": 300,
        "Corporate Office": 300,

        // Food & Dining
        "Restaurant": 150,
        "Cafe": 150,
        "Coffee": 150,
        "Bakery": 150,
        "Diner": 150,
        "Fast Food": 150,
        "Pub": 150,
        "Bar": 150,
        "Bistro": 150,

        // Shopping
        "Shop": 150,
        "Store": 150,
        "Retail": 150,
        "Mall": 200,
        "Shopping Center": 200,
        "Market": 150,
        "Grocery": 150,
        "Supermarket": 150,

        // Entertainment & Leisure
        "Park": 800,
        "Recreation": 800,
        "Gym": 150,
        "Fitness": 150,
        "Sports": 200,
        "Movie": 150,
        "Theater": 150,
        "Library": 150,
        "Museum": 200,

        // Healthcare
        "Hospital": 200,
        "Clinic": 150,
        "Medical": 150,
        "Pharmacy": 150,
        "Doctor": 150,

        // Education
        "School": 300,
        "University": 500,
        "College": 500,

        // Accommodation
        "Hotel": 150,
        "Motel": 150,
        "Resort": 200,
        "Lodging": 150,

        // Transportation
        "Airport": 300,
        "Train Station": 200,
        "Bus Station": 200,
        "Parking": 150,

        // Religious
        "Mosque": 200,
        "Church": 200,
        "Temple": 200,
        "Synagogue": 200,

        // Other
        "Uncategorized": 200
    ]

    private init() {}

    // MARK: - Auto-Detection

    /// Get geofence radius for a saved place
    /// Priority: User custom radius > Smart auto-detect > Default (200m)
    func getRadius(for place: SavedPlace) -> CLLocationDistance {
        // 1. User override (highest priority)
        if let customRadius = place.customGeofenceRadius,
           customRadius > 50 && customRadius < 2000 { // Sanity check: 50m - 2km
            print("📍 Using custom radius for \(place.displayName): \(customRadius)m")
            return customRadius
        }

        // 2. Smart auto-detect from category
        let autoRadius = autoDetectRadius(from: place.category)
        print("📍 Using smart radius for \(place.displayName): \(autoRadius)m (category: \(place.category))")
        return autoRadius
    }

    /// Auto-detect radius based on location category
    private func autoDetectRadius(from category: String) -> CLLocationDistance {
        // Try exact match first
        if let radius = radiusByCategory[category] {
            return radius
        }

        // Try partial matching (case-insensitive)
        let lowerCategory = category.lowercased()

        for (key, radius) in radiusByCategory {
            if lowerCategory.contains(key.lowercased()) ||
               key.lowercased().contains(lowerCategory.prefix(3)) { // First 3 chars
                return radius
            }
        }

        // Fallback to default
        return defaultRadius
    }

    // MARK: - Radius Configuration

    /// Set a custom radius for a place (user override)
    func setCustomRadius(_ radius: CLLocationDistance, for placeId: UUID, in places: inout [SavedPlace]) {
        guard let index = places.firstIndex(where: { $0.id == placeId }) else {
            print("⚠️ Place not found: \(placeId.uuidString)")
            return
        }

        let validated = max(50, min(2000, radius)) // Clamp to 50m - 2km range
        places[index].customGeofenceRadius = validated

        print("✅ Set custom radius for \(places[index].displayName): \(validated)m")

        // Sync to Supabase
        Task {
            await updateRadiusInSupabase(placeId, radius: validated)
        }
    }

    /// Clear custom radius (revert to auto-detect)
    func clearCustomRadius(for placeId: UUID, in places: inout [SavedPlace]) {
        guard let index = places.firstIndex(where: { $0.id == placeId }) else {
            print("⚠️ Place not found")
            return
        }

        let defaultForCategory = autoDetectRadius(from: places[index].category)
        places[index].customGeofenceRadius = nil

        print("✅ Cleared custom radius for \(places[index].displayName)")
        print("   Now using auto-detected: \(defaultForCategory)m")

        // Sync to Supabase
        Task {
            await updateRadiusInSupabase(placeId, radius: nil)
        }
    }

    // MARK: - Radius Change Handling

    /// Handle category change - update geofence radius accordingly
    func handleCategoryChange(
        for place: SavedPlace,
        oldCategory: String,
        newCategory: String,
        in geofenceManager: GeofenceManager
    ) {
        let oldRadius = autoDetectRadius(from: oldCategory)
        let newRadius = autoDetectRadius(from: newCategory)

        if oldRadius != newRadius {
            print("🔄 Category changed: \(oldCategory) → \(newCategory)")
            print("   Radius updated: \(oldRadius)m → \(newRadius)m")

            // Update geofence in Core Location
            geofenceManager.updateGeofenceRadius(for: place)
        }
    }

    // MARK: - Supabase Sync

    /// Update radius in Supabase
    private func updateRadiusInSupabase(_ placeId: UUID, radius: CLLocationDistance?) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ Not authenticated")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            let updateData: [String: PostgREST.AnyJSON] = [
                "custom_geofence_radius": radius != nil ? .double(radius!) : .null,
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]

            try await client
                .from("saved_places")
                .update(updateData)
                .eq("id", value: placeId.uuidString)
                .execute()

            print("💾 Radius synced to Supabase for: \(placeId.uuidString)")
        } catch {
            print("❌ Error updating radius in Supabase: \(error)")
        }
    }

    // MARK: - Diagnostics

    /// Get radius summary for all places
    func getRadiusSummary(for places: [SavedPlace]) -> [(name: String, category: String, radius: CLLocationDistance)] {
        return places.map { place in
            (
                name: place.displayName,
                category: place.category,
                radius: getRadius(for: place)
            )
        }
    }

    /// Print radius diagnostics
    func printRadiusDiagnostics(for places: [SavedPlace]) {
        print("\n📊 ===== GEOFENCE RADIUS DIAGNOSTICS =====")
        for place in places {
            let radius = getRadius(for: place)
            let source = place.customGeofenceRadius != nil ? "CUSTOM" : "AUTO"
            print("📍 \(place.displayName)")
            print("   Category: \(place.category)")
            print("   Radius: \(Int(radius))m [\(source)]")
            if let customRadius = place.customGeofenceRadius {
                let autoRadius = autoDetectRadius(from: place.category)
                print("   (Auto would be: \(Int(autoRadius))m)")
            }
        }
        print("📊 ====================================\n")
    }

    /// Validate all radiuses are in acceptable range
    func validateRadiuses(for places: [SavedPlace]) -> [(placeId: UUID, issue: String)] {
        var issues: [(UUID, String)] = []

        for place in places {
            let radius = getRadius(for: place)

            if radius < 50 {
                issues.append((place.id, "Radius too small: \(Int(radius))m < 50m"))
            } else if radius > 2000 {
                issues.append((place.id, "Radius too large: \(Int(radius))m > 2000m"))
            }
        }

        return issues
    }

    // MARK: - Category Recommendations

    /// Get recommended radius for a category (for UI)
    func getRecommendedRadius(for category: String) -> CLLocationDistance {
        return autoDetectRadius(from: category)
    }

    /// Get all categories with their recommended radiuses
    func getCategoryRecommendations() -> [(category: String, radius: CLLocationDistance)] {
        return Array(radiusByCategory)
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, radius: $0.value) }
    }
}
