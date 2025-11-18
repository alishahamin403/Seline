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
        case id, userId, savedPlaceId, entryTime, exitTime, durationMinutes
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
        if dayIndex >= 0 && dayIndex < days.count {
            return days[dayIndex]
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
class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    private let locationManager = CLLocationManager()
    private var monitoredRegions: [String: CLCircularRegion] = [:] // [placeId: region]
    private var activeVisits: [UUID: LocationVisitRecord] = [:] // [placeId: visit]

    @Published var isMonitoring = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let geofenceRadius: CLLocationDistance = 100 // 100 meters

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.pausesLocationUpdatesAutomatically = false
        // NOTE: allowsBackgroundLocationUpdates will be set after authorization is granted
    }

    // MARK: - Permission Handling

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // Request background location permission (Always)
            locationManager.requestAlwaysAuthorization()
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
        print("🔍 Setting up geofences for \(places.count) saved locations")

        // Only proceed if we have background location authorization
        guard authorizationStatus == .authorizedAlways else {
            print("⚠️ Background location authorization not yet granted. Waiting for permission...")
            return
        }

        // Remove existing geofences
        monitoredRegions.forEach { locationManager.stopMonitoring(for: $0.value) }
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

            locationManager.startMonitoring(for: region)
            monitoredRegions[place.id.uuidString] = region

            print("📍 Monitoring geofence for: \(place.displayName) (ID: \(place.id.uuidString))")
        }

        if !locationsToTrack.isEmpty {
            isMonitoring = true
            print("✅ Geofences setup complete. Monitoring \(locationsToTrack.count) locations")
        }
    }

    /// Stop monitoring all geofences
    func stopMonitoring() {
        print("🛑 Stopping all geofence monitoring")
        monitoredRegions.forEach { locationManager.stopMonitoring(for: $0.value) }
        monitoredRegions.removeAll()
        activeVisits.removeAll()
        isMonitoring = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            print("✅ Entered geofence: \(region.identifier)")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
                print("⚠️ No user ID for visit tracking")
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
            print("❌ Exited geofence: \(region.identifier)")

            guard let placeId = UUID(uuidString: region.identifier) else {
                print("❌ Invalid place ID in geofence")
                return
            }

            if var visit = self.activeVisits.removeValue(forKey: placeId) {
                visit.recordExit(exitTime: Date())

                print("📝 Finished tracking visit for place: \(placeId), duration: \(visit.durationMinutes ?? 0) min")

                // Update visit in Supabase with exit time
                await self.updateVisitInSupabase(visit)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedAlways:
                print("✅ Background location authorization granted")

                // Now safe to enable background location updates
                manager.allowsBackgroundLocationUpdates = true
                manager.showsBackgroundLocationIndicator = true

                self.setupGeofences(for: LocationsManager.shared.getFavourites())
            case .authorizedWhenInUse:
                print("⚠️ Only 'When In Use' authorization granted. Geofencing requires 'Always' permission.")
                self.errorMessage = "Geofencing requires 'Always' location permission"
            case .denied, .restricted:
                print("❌ Location authorization denied")
                self.errorMessage = "Location access denied"
                self.stopMonitoring()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("⚠️ Location manager error: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Supabase Integration

    private func saveVisitToSupabase(_ visit: LocationVisitRecord) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase visit save")
            return
        }

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
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .execute()

            print("✅ Visit updated in Supabase: \(visit.id.uuidString)")
        } catch {
            print("❌ Error updating visit in Supabase: \(error)")
        }
    }
}
