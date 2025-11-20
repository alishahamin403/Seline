import Foundation
import CoreLocation
import PostgREST

// MARK: - LocationVisitRecord Model

struct LocationVisitRecord: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let savedPlaceId: UUID
    let entryTime: Date
    var exitTime: Date?
    var durationMinutes: Int?
    let dayOfWeek: String
    let timeOfDay: String
    let month: Int
    let year: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case savedPlaceId = "saved_place_id"
        case entryTime = "entry_time"
        case exitTime = "exit_time"
        case durationMinutes = "duration_minutes"
        case dayOfWeek = "day_of_week"
        case timeOfDay = "time_of_day"
        case month, year
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func create(
        userId: UUID,
        savedPlaceId: UUID,
        entryTime: Date
    ) -> LocationVisitRecord {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .month, .year], from: entryTime)

        let dayOfWeek = Self.dayOfWeekName(for: components.weekday ?? 1)
        let timeOfDay = Self.timeOfDayName(for: entryTime)
        let month = components.month ?? 1
        let year = components.year ?? 2024

        return LocationVisitRecord(
            id: UUID(),
            userId: userId,
            savedPlaceId: savedPlaceId,
            entryTime: entryTime,
            exitTime: Optional<Date>.none,
            durationMinutes: Optional<Int>.none,
            dayOfWeek: dayOfWeek,
            timeOfDay: timeOfDay,
            month: month,
            year: year,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    mutating func recordExit(exitTime: Date) {
        self.exitTime = exitTime
        let minutes = Int(exitTime.timeIntervalSince(entryTime) / 60)
        self.durationMinutes = max(minutes, 1) // At least 1 minute
        self.updatedAt = Date()
    }

    private static func dayOfWeekName(for dayIndex: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        // dayIndex from Calendar.dateComponents is 1-7 (1=Sunday), but array is 0-indexed
        if dayIndex >= 1 && dayIndex <= 7 {
            return days[dayIndex - 1]
        }
        return "Unknown"
    }

    private static func timeOfDayName(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }
}

// MARK: - GeofenceManager

@MainActor
class GeofenceManager: NSObject, ObservableObject {
    static let shared = GeofenceManager()

    // OPTIMIZATION: Use SharedLocationManager instead of creating own instance
    // This consolidates CLLocationManager to reduce battery drain and redundancy
    private let sharedLocationManager = SharedLocationManager.shared

    private var monitoredRegions: [String: CLCircularRegion] = [:] // [placeId: region]
    var activeVisits: [UUID: LocationVisitRecord] = [:] // [placeId: visit]

    @Published var isMonitoring = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let geofenceRadius: CLLocationDistance = 100 // 100 meters

    override init() {
        super.init()
        // Subscribe to shared location manager updates
        authorizationStatus = sharedLocationManager.authorizationStatus
    }

    /// Handle geofence entry from SharedLocationManager
    nonisolated func handleGeofenceEntry(region: CLCircularRegion) async {
        await self.locationManager(CLLocationManager(), didEnterRegion: region)
    }

    /// Handle geofence exit from SharedLocationManager
    nonisolated func handleGeofenceExit(region: CLCircularRegion) async {
        await self.locationManager(CLLocationManager(), didExitRegion: region)
    }

    // MARK: - Permission Handling

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // Request background location permission (Always)
            sharedLocationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            errorMessage = "Background location access required for visit tracking. Please enable in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Geofence Management

    /// Setup geofences for all saved locations
    func setupGeofences(for places: [SavedPlace]) {
        print("\n🔍 ===== SETTING UP GEOFENCES =====")
        print("🔍 Total locations to track: \(places.count)")

        // Only proceed if we have background location authorization
        guard authorizationStatus == .authorizedAlways else {
            print("⚠️ Background location authorization not yet granted. Waiting for permission...")
            print("⚠️ Current status: \(authorizationStatus.rawValue)")
            print("🔍 ===================================\n")
            return
        }

        // Remove existing geofences
        print("🔨 Removing \(monitoredRegions.count) existing geofences...")
        monitoredRegions.forEach { sharedLocationManager.stopMonitoring(region: $0.value) }
        monitoredRegions.removeAll()

        // Add new geofences for all saved locations
        let locationsToTrack = places

        for place in locationsToTrack {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                radius: geofenceRadius,
                identifier: place.id.uuidString
            )

            region.notifyOnEntry = true
            region.notifyOnExit = true

            sharedLocationManager.startMonitoring(region: region)
            monitoredRegions[place.id.uuidString] = region

            print("📍 Monitoring geofence for: \(place.displayName)")
            print("   ID: \(place.id.uuidString)")
            print("   Coords: \(place.latitude), \(place.longitude)")
            print("   Radius: \(geofenceRadius)m")
        }

        if !locationsToTrack.isEmpty {
            isMonitoring = true
            print("✅ GEOFENCES SETUP COMPLETE - Now monitoring \(locationsToTrack.count) locations")
        }
        print("🔍 ===================================\n")
    }

    /// Stop monitoring all geofences
    func stopMonitoring() {
        print("🛑 Stopping all geofence monitoring")
        monitoredRegions.forEach { sharedLocationManager.stopMonitoring(region: $0.value) }
        monitoredRegions.removeAll()
        activeVisits.removeAll()
        isMonitoring = false
    }

    /// Update background location tracking based on user preference
    func updateBackgroundLocationTracking(enabled: Bool) {
        sharedLocationManager.enableBackgroundLocationTracking(enabled)
    }

    // MARK: - Geofence Event Handling (called by SharedLocationManager)

    nonisolated private func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            print("\n✅ ===== GEOFENCE ENTRY EVENT FIRED =====")
            print("✅ Entered geofence: \(region.identifier)")
            print("✅ ========================================\n")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
                print("⚠️ No user ID for visit tracking")
                return
            }

            // Check if we already have an active visit for this location
            // This prevents duplicate sessions if geofence is re-triggered while user is still in location
            if self.activeVisits[placeId] != nil {
                print("ℹ️ Active visit already exists for place: \(placeId), skipping duplicate entry")
                return
            }

            // Create a new visit record
            var visit = LocationVisitRecord.create(
                userId: userId,
                savedPlaceId: placeId,
                entryTime: Date()
            )

            self.activeVisits[placeId] = visit

            print("📝 Started tracking visit for place: \(placeId)")

            // Save to Supabase
            await self.saveVisitToSupabase(visit)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            print("\n⛔️ ===== GEOFENCE EXIT EVENT FIRED =====")
            print("⛔️ Exited geofence: \(region.identifier)")
            print("⛔️ Active visits in memory: \(self.activeVisits.count)")
            print("⛔️ =====================================\n")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            // First, check if we have an active visit in memory
            if var visit = self.activeVisits.removeValue(forKey: placeId) {
                visit.recordExit(exitTime: Date())
                print("✅ Finished tracking visit for place: \(placeId), duration: \(visit.durationMinutes ?? 0) min")
                await self.updateVisitInSupabase(visit)
            } else {
                // If not in memory (app was backgrounded/killed), fetch from Supabase
                print("⚠️ Visit not found in memory, fetching from Supabase...")
                await self.findAndCloseIncompleteVisit(for: placeId)
            }
        }
    }

    /// Fetches the most recent incomplete visit for a location and closes it
    private func findAndCloseIncompleteVisit(for placeId: UUID) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, cannot close incomplete visit")
            return
        }

        do {
            print("🔍 Querying Supabase for incomplete visit - Place: \(placeId), User: \(userId.uuidString)")

            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .order("entry_time", ascending: false)
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            if var visit = visits.first {
                print("📋 Found visit in Supabase - ID: \(visit.id), Entry: \(visit.entryTime), Exit: \(visit.exitTime?.description ?? "nil")")

                // Only close if it doesn't already have an exit time
                if visit.exitTime == nil {
                    visit.recordExit(exitTime: Date())
                    print("✅ CLOSED INCOMPLETE VISIT - Place: \(placeId), Duration: \(visit.durationMinutes ?? 0) min")
                    await self.updateVisitInSupabase(visit)
                } else {
                    print("ℹ️ Most recent visit already has exit time at \(visit.exitTime?.description ?? "unknown"), skipping")
                }
            } else {
                print("⚠️ No visit found in Supabase for place: \(placeId)")
            }
        } catch {
            print("❌ Error finding incomplete visit: \(error)")
        }
    }

    /// Sync authorization status from SharedLocationManager
    func observeAuthorizationChanges() {
        // In the future, this could use Combine to observe changes
        // For now, it's called from requestLocationPermission
    }

    /// Handle authorization changes (internal use, sync with SharedLocationManager)
    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        self.authorizationStatus = status

        switch status {
        case .authorizedAlways:
            print("✅ Background location authorization granted")

            // Enable background location updates based on user preference
            let locationTrackingMode = UserDefaults.standard.string(forKey: "locationTrackingMode") ?? "active"
            sharedLocationManager.enableBackgroundLocationTracking(locationTrackingMode == "background")

            setupGeofences(for: LocationsManager.shared.savedPlaces)
        case .authorizedWhenInUse:
            print("⚠️ Only 'When In Use' authorization granted. Geofencing requires 'Always' permission.")
            self.errorMessage = "Geofencing requires 'Always' location permission"
        case .denied, .restricted:
            print("❌ Location authorization denied")
            self.errorMessage = "Location access denied"
            stopMonitoring()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Supabase Integration

    /// Load incomplete visits from Supabase and restore them to activeVisits
    /// Called on app startup to resume tracking
    func loadIncompleteVisitsFromSupabase() async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping incomplete visits load")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .limit(10)
                .execute()

            // Decode the response data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Find the first incomplete visit (no exit_time)
            if let incompleteVisit = visits.first(where: { $0.exitTime == nil }) {
                // Check if visit has been open for more than 24 hours - if so, auto-complete it
                let hoursSinceEntry = Date().timeIntervalSince(incompleteVisit.entryTime) / 3600
                if hoursSinceEntry > 24 {
                    print("⚠️ Incomplete visit has been open for \(Int(hoursSinceEntry)) hours, auto-completing...")
                    var completedVisit = incompleteVisit
                    completedVisit.recordExit(exitTime: Date())
                    await self.updateVisitInSupabase(completedVisit)
                    print("✅ Auto-completed stale visit: \(incompleteVisit.savedPlaceId)")
                } else {
                    // DEDUPLICATION: Only restore if not already in activeVisits
                    if self.activeVisits[incompleteVisit.savedPlaceId] == nil {
                        self.activeVisits[incompleteVisit.savedPlaceId] = incompleteVisit
                        print("📝 Restored incomplete visit from Supabase: \(incompleteVisit.savedPlaceId)")
                    } else {
                        print("ℹ️ Incomplete visit already in activeVisits, skipping restore: \(incompleteVisit.savedPlaceId)")
                    }
                }
            } else {
                print("✅ No incomplete visits in Supabase")
            }
        } catch {
            print("❌ Error loading incomplete visits: \(error)")
        }
    }

    func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        print("🔍 saveVisitToSupabase called - checking user...")
        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No user ID, skipping Supabase visit save")
            return
        }

        print("👤 Current user found: \(user.id.uuidString)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let visitData: [String: PostgREST.AnyJSON] = [
            "id": .string(visit.id.uuidString),
            "user_id": .string(visit.userId.uuidString),
            "saved_place_id": .string(visit.savedPlaceId.uuidString),
            "entry_time": .string(formatter.string(from: visit.entryTime)),
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "day_of_week": .string(visit.dayOfWeek),
            "time_of_day": .string(visit.timeOfDay),
            "month": .double(Double(visit.month)),
            "year": .double(Double(visit.year)),
            "created_at": .string(formatter.string(from: visit.createdAt)),
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        print("📤 Preparing to insert visit into Supabase: \(visitData)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .insert(visitData)
                .execute()

            print("✅ Visit saved to Supabase: \(visit.id.uuidString)")
        } catch {
            print("❌ Error saving visit to Supabase: \(error)")
        }
    }

    private func updateVisitInSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase visit update")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let updateData: [String: PostgREST.AnyJSON] = [
            "exit_time": visit.exitTime != nil ? .string(formatter.string(from: visit.exitTime!)) : .null,
            "duration_minutes": visit.durationMinutes != nil ? .double(Double(visit.durationMinutes!)) : .null,
            "updated_at": .string(formatter.string(from: visit.updatedAt))
        ]

        do {
            print("💾 Updating visit in Supabase - ID: \(visit.id.uuidString), ExitTime: \(visit.exitTime?.description ?? "nil"), Duration: \(visit.durationMinutes ?? 0)min")

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ VISIT UPDATE SUCCESSFUL - ID: \(visit.id.uuidString)")

            // OPTIMIZATION: Invalidate cached stats for this location
            // so next query fetches fresh data
            LocationVisitAnalytics.shared.invalidateCache(for: visit.savedPlaceId)
        } catch {
            print("❌ Error updating visit in Supabase: \(error)")
        }
    }

    /// Auto-complete any active visits if user has moved too far from the location
    func autoCompleteVisitsIfOutOfRange(currentLocation: CLLocation, savedPlaces: [SavedPlace]) async {
        let geofenceRadius: CLLocationDistance = 100 // 100 meters

        // Check each active visit
        for (placeId, var visit) in activeVisits {
            // Find the location for this visit
            if let place = savedPlaces.first(where: { $0.id == placeId }) {
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLocation.distance(from: placeLocation)

                // If user has moved beyond geofence radius, auto-complete the visit
                if distance > geofenceRadius {
                    print("\n🚀 ===== AUTO-COMPLETING VISIT =====")
                    print("🚀 Location: \(place.displayName)")
                    print("🚀 Distance from location: \(String(format: "%.1f", distance))m (beyond \(geofenceRadius)m geofence)")
                    print("🚀 Active visit duration: \(Int(Date().timeIntervalSince(visit.entryTime) / 60)) minutes")
                    print("🚀 ====================================\n")

                    // Record the exit and remove from active visits
                    visit.recordExit(exitTime: Date())
                    activeVisits.removeValue(forKey: placeId)

                    // Update in Supabase
                    await updateVisitInSupabase(visit)
                }
            }
        }
    }
}
