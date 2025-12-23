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
    // Increased from 200m to 300m to better capture large stores like Walmart
    private let defaultRadius: CLLocationDistance = 300

    // Smart auto-detected radiuses by category
    private let radiusByCategory: [String: CLLocationDistance] = [
        // Residential
        "Home": 500,
        "Residence": 500,
        "Apartment": 500,

        // Work (reduced from 300m to 200m to prevent nearby location triggering)
        "Work": 200,
        "Office": 200,
        "Workplace": 200,
        "Corporate Office": 200,

        // Food & Dining
        "Restaurant": 75,
        "Cafe": 75,
        "Coffee": 75,
        "Bakery": 75,
        "Diner": 75,
        "Fast Food": 75,
        "Pub": 75,
        "Bar": 75,
        "Bistro": 75,
        "Grill": 75,
        "Burger": 75,
        "Steak": 75,

        // Personal Services
        "Salon": 75,
        "Haircut": 75,
        "Barber": 75,
        "Spa": 75,
        "Beauty": 75,

        // Shopping
        "Shop": 75,
        "Store": 75,
        "Retail": 75,
        "Mall": 200,
        "Shopping Center": 200,
        "Market": 75,
        "Grocery": 100,
        "Supermarket": 100,
        "Essential": 300,  // Large stores like Walmart with metal roofs

        // Entertainment & Leisure
        "Park": 800,
        "Recreation": 800,
        "Gym": 75,
        "Fitness": 75,
        "Sports": 200,
        "Movie": 75,
        "Theater": 75,
        "Library": 100,
        "Museum": 200,

        // Healthcare
        "Hospital": 200,
        "Clinic": 75,
        "Medical": 75,
        "Pharmacy": 75,
        "Doctor": 75,

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
        "Uncategorized": 300  // Increased default for better coverage
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
        // DEBUG: Commented out to reduce console spam
        // print("📍 Using smart radius for \(place.displayName): \(autoRadius)m (category: \(place.category))")
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

    // MARK: - SOLUTION 4: Proximity Collision Detection

    struct ProximityCollision {
        let place1: SavedPlace
        let place2: SavedPlace
        let distance: CLLocationDistance
        let place1Radius: CLLocationDistance
        let place2Radius: CLLocationDistance
        let overlapPercentage: Double

        var description: String {
            return "\(place1.displayName) (\(Int(place1Radius))m) ↔ \(place2.displayName) (\(Int(place2Radius))m): \(String(format: "%.0f", distance))m apart (\(String(format: "%.0f", overlapPercentage))% overlap)"
        }

        var isCritical: Bool {
            return overlapPercentage > 50 // Critical if overlap > 50%
        }
    }

    /// Detect all proximity collisions between saved places
    /// Returns list of collisions where geofence radii overlap
    func detectProximityCollisions(for places: [SavedPlace]) -> [ProximityCollision] {
        var collisions: [ProximityCollision] = []

        for i in 0..<places.count {
            for j in (i+1)..<places.count {
                let place1 = places[i]
                let place2 = places[j]

                let location1 = CLLocation(latitude: place1.latitude, longitude: place1.longitude)
                let location2 = CLLocation(latitude: place2.latitude, longitude: place2.longitude)
                let distance = location1.distance(from: location2)

                let radius1 = getRadius(for: place1)
                let radius2 = getRadius(for: place2)

                // Calculate if geofences overlap
                let combinedRadius = radius1 + radius2

                if distance < combinedRadius {
                    // Calculate overlap percentage
                    let overlap = combinedRadius - distance
                    let overlapPercentage = (overlap / combinedRadius) * 100

                    let collision = ProximityCollision(
                        place1: place1,
                        place2: place2,
                        distance: distance,
                        place1Radius: radius1,
                        place2Radius: radius2,
                        overlapPercentage: overlapPercentage
                    )

                    collisions.append(collision)
                }
            }
        }

        return collisions.sorted { $0.overlapPercentage > $1.overlapPercentage }
    }

    /// Print proximity collision report
    func printProximityCollisionReport(for places: [SavedPlace]) {
        let collisions = detectProximityCollisions(for: places)

        if collisions.isEmpty {
            print("\n✅ ===== PROXIMITY COLLISION REPORT =====")
            print("✅ No geofence collisions detected!")
            print("✅ All locations have sufficient spacing")
            print("✅ =====================================\n")
            return
        }

        print("\n⚠️ ===== PROXIMITY COLLISION REPORT =====")
        print("⚠️ Found \(collisions.count) geofence collision(s):")
        print()

        for (index, collision) in collisions.enumerated() {
            let severity = collision.isCritical ? "🔴 CRITICAL" : "⚠️ WARNING"
            print("\(index + 1). \(severity)")
            print("   \(collision.description)")

            // Suggest radius reduction
            let suggestedRadius1 = max(50, collision.distance * 0.4)
            let suggestedRadius2 = max(50, collision.distance * 0.4)

            print("   💡 Suggestion: Reduce radii to ~\(Int(suggestedRadius1))m each to prevent overlap")
            print()
        }

        print("⚠️ ====================================\n")
    }

    /// Get suggested radius reduction to eliminate collision
    func getSuggestedRadiusForCollision(_ collision: ProximityCollision) -> (place1: CLLocationDistance, place2: CLLocationDistance) {
        // Suggest radius = 40% of distance between locations (leaves 20% buffer)
        let suggestedRadius = max(50, collision.distance * 0.4)
        return (suggestedRadius, suggestedRadius)
    }

    /// Auto-fix collisions by reducing radii (optional, use with caution)
    func autoFixCollisions(for places: inout [SavedPlace], criticalOnly: Bool = true) async {
        let collisions = detectProximityCollisions(for: places)
        let toFix = criticalOnly ? collisions.filter { $0.isCritical } : collisions

        guard !toFix.isEmpty else {
            print("✅ No collisions to fix")
            return
        }

        print("\n🔧 AUTO-FIXING \(toFix.count) COLLISION(S)...\n")

        for collision in toFix {
            let (suggested1, suggested2) = getSuggestedRadiusForCollision(collision)

            // Only reduce if current radius is larger than suggested
            if collision.place1Radius > suggested1 {
                setCustomRadius(suggested1, for: collision.place1.id, in: &places)
                print("   ✅ Reduced \(collision.place1.displayName): \(Int(collision.place1Radius))m → \(Int(suggested1))m")
            }

            if collision.place2Radius > suggested2 {
                setCustomRadius(suggested2, for: collision.place2.id, in: &places)
                print("   ✅ Reduced \(collision.place2.displayName): \(Int(collision.place2Radius))m → \(Int(suggested2))m")
            }
        }

        print("\n🔧 Auto-fix complete!\n")
    }
}
