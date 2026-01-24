import Foundation
import CoreLocation
import UserNotifications

// MARK: - LocationSuggestionService
//
// Detects when user stays at an unsaved location for 5+ minutes
// and prompts them to save it via notification and home page indicator
// Only suggests locations with named POIs (restaurants, shops, etc.) - not street addresses

@MainActor
class LocationSuggestionService: ObservableObject {
    static let shared = LocationSuggestionService()
    
    // MARK: - Published Properties
    
    /// Current suggested location (shown on home page indicator)
    @Published var suggestedLocation: SuggestedLocation? = nil
    
    /// Whether a suggestion is currently active
    @Published var hasPendingSuggestion: Bool = false
    
    // MARK: - Private Properties
    
    /// Minimum time at unsaved location before suggesting (5 minutes)
    private let suggestionThreshold: TimeInterval = 5 * 60 // 5 minutes
    
    /// Timer to check dwell time
    private var dwellTimer: Timer?
    
    /// Currently tracked location (unsaved location user is at)
    private var trackedLocation: CLLocation?
    private var trackedLocationName: String?
    private var trackedLocationAddress: String?
    private var trackedLocationStartTime: Date?
    private var trackedLocationIsPOI: Bool = false // Whether the location has a real POI name
    
    /// Cooldown to prevent spamming suggestions (1 hour between suggestions for same area)
    private var recentlySuggestedLocations: [String: Date] = [:]
    private let suggestionCooldown: TimeInterval = 60 * 60 // 1 hour
    
    /// Track dismissed suggestions for this session
    private var dismissedLocationsThisSession: Set<String> = []
    
    private let locationManager = SharedLocationManager.shared
    private let notificationService = NotificationService.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring for location suggestions (call when app becomes active)
    func startMonitoring() {
        print("📍 LocationSuggestionService: Starting monitoring")
        checkCurrentLocation()
        
        // Check every 30 seconds
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkCurrentLocation()
            }
        }
    }
    
    /// Stop monitoring (call when app goes to background)
    func stopMonitoring() {
        print("📍 LocationSuggestionService: Stopping monitoring")
        dwellTimer?.invalidate()
        dwellTimer = nil
    }
    
    /// Dismiss the current suggestion
    func dismissSuggestion() {
        if let key = suggestedLocation?.coordinateKey {
            dismissedLocationsThisSession.insert(key)
        }
        suggestedLocation = nil
        hasPendingSuggestion = false
        trackedLocation = nil
        trackedLocationName = nil
        trackedLocationAddress = nil
        trackedLocationStartTime = nil
        trackedLocationIsPOI = false
    }
    
    /// Save the suggested location
    func saveSuggestedLocation(withCategory category: String = "Other") async -> SavedPlace? {
        guard let suggested = suggestedLocation else { return nil }
        
        // Create a SavedPlace from the suggestion
        let place = SavedPlace(
            googlePlaceId: "suggested_\(UUID().uuidString)", // Temporary ID
            name: suggested.name,
            address: suggested.address,
            latitude: suggested.latitude,
            longitude: suggested.longitude
        )
        
        // Add to LocationsManager
        LocationsManager.shared.addPlace(place)
        
        // Clear suggestion
        dismissSuggestion()
        
        print("✅ Saved suggested location: \(suggested.name)")
        
        return place
    }
    
    // MARK: - Private Methods
    
    private func checkCurrentLocation() {
        guard let currentLocation = locationManager.currentLocation else {
            return
        }
        
        // Check if user is at an unsaved location
        let savedPlaces = LocationsManager.shared.savedPlaces
        let isAtSavedLocation = savedPlaces.contains { place in
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)
            return distance <= radius
        }
        
        if isAtSavedLocation {
            // User is at a saved location, stop tracking
            if trackedLocation != nil {
                print("📍 User entered saved location, stopping suggestion tracking")
            }
            trackedLocation = nil
            trackedLocationName = nil
            trackedLocationAddress = nil
            trackedLocationStartTime = nil
            trackedLocationIsPOI = false
            return
        }
        
        // User is at an unsaved location
        let coordinateKey = "\(String(format: "%.4f", currentLocation.coordinate.latitude)),\(String(format: "%.4f", currentLocation.coordinate.longitude))"
        
        // Check if we recently suggested this location
        if let lastSuggested = recentlySuggestedLocations[coordinateKey],
           Date().timeIntervalSince(lastSuggested) < suggestionCooldown {
            return
        }
        
        // Check if dismissed this session
        if dismissedLocationsThisSession.contains(coordinateKey) {
            return
        }
        
        // Check if this is a new location or same as tracked
        if let tracked = trackedLocation {
            let distance = currentLocation.distance(from: tracked)
            
            if distance > 100 {
                // User moved to different location, reset tracking
                trackedLocation = currentLocation
                trackedLocationStartTime = Date()
                trackedLocationName = nil
                trackedLocationAddress = nil
                trackedLocationIsPOI = false
                
                // Start reverse geocoding
                reverseGeocode(location: currentLocation)
            } else if let startTime = trackedLocationStartTime {
                // Same location, check if threshold reached
                let dwellTime = Date().timeIntervalSince(startTime)
                
                // Only suggest if we have a POI name (not just a street address)
                if dwellTime >= suggestionThreshold && !hasPendingSuggestion && trackedLocationIsPOI {
                    // Time to suggest!
                    createSuggestion(from: currentLocation)
                }
            }
        } else {
            // First time tracking this location
            trackedLocation = currentLocation
            trackedLocationStartTime = Date()
            
            // Start reverse geocoding
            reverseGeocode(location: currentLocation)
        }
    }
    
    private func reverseGeocode(location: CLLocation) {
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Reverse geocode error: \(error.localizedDescription)")
                    return
                }
                
                if let placemark = placemarks?.first {
                    // Check if this is a POI (Point of Interest) with a real name
                    // POIs have names that are different from the street address
                    var isPOI = false
                    var name = ""
                    
                    if let poi = placemark.name,
                       !poi.isEmpty,
                       poi != placemark.thoroughfare,
                       poi != placemark.subThoroughfare,
                       !self.isStreetAddress(poi) {
                        // This is a named POI (restaurant, shop, etc.)
                        name = poi
                        isPOI = true
                        print("📍 Detected POI: \(poi)")
                    } else {
                        // This is just a street address, not a POI
                        // Build address-based name but mark as non-POI
                        if let street = placemark.thoroughfare {
                            if let number = placemark.subThoroughfare {
                                name = "\(number) \(street)"
                            } else {
                                name = street
                            }
                        } else if let neighborhood = placemark.subLocality {
                            name = neighborhood
                        } else if let city = placemark.locality {
                            name = city
                        } else {
                            name = "Unknown Location"
                        }
                        isPOI = false
                        print("📍 Detected address (not POI): \(name)")
                    }
                    
                    // Build address
                    var addressComponents: [String] = []
                    if let street = placemark.thoroughfare {
                        if let number = placemark.subThoroughfare {
                            addressComponents.append("\(number) \(street)")
                        } else {
                            addressComponents.append(street)
                        }
                    }
                    if let city = placemark.locality {
                        addressComponents.append(city)
                    }
                    if let state = placemark.administrativeArea {
                        addressComponents.append(state)
                    }
                    if let country = placemark.country {
                        addressComponents.append(country)
                    }
                    
                    let address = addressComponents.joined(separator: ", ")
                    
                    self.trackedLocationName = name
                    self.trackedLocationAddress = address.isEmpty ? "Address unavailable" : address
                    self.trackedLocationIsPOI = isPOI
                }
            }
        }
    }
    
    /// Check if a string looks like a street address rather than a POI name
    private func isStreetAddress(_ name: String) -> Bool {
        // Check if the name starts with a number (typical of street addresses)
        let firstChar = name.first
        if let first = firstChar, first.isNumber {
            return true
        }
        
        // Check for common address patterns
        let addressPatterns = [
            "Street", "St.", "Avenue", "Ave.", "Road", "Rd.",
            "Boulevard", "Blvd.", "Drive", "Dr.", "Lane", "Ln.",
            "Court", "Ct.", "Place", "Pl.", "Highway", "Hwy."
        ]
        
        // If the name contains only address-like words, it's probably an address
        for pattern in addressPatterns {
            if name.contains(pattern) && name.components(separatedBy: " ").count <= 3 {
                // Short names with street suffixes are likely addresses
                return true
            }
        }
        
        return false
    }
    
    private func createSuggestion(from location: CLLocation) {
        let name = trackedLocationName ?? "New Location"
        let address = trackedLocationAddress ?? "Address unavailable"
        let coordinateKey = "\(String(format: "%.4f", location.coordinate.latitude)),\(String(format: "%.4f", location.coordinate.longitude))"
        
        let suggestion = SuggestedLocation(
            id: UUID(),
            name: name,
            address: address,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            suggestedAt: Date(),
            coordinateKey: coordinateKey
        )
        
        suggestedLocation = suggestion
        hasPendingSuggestion = true
        recentlySuggestedLocations[coordinateKey] = Date()
        
        print("✨ Created location suggestion: \(name)")
        
        // Send notification to alert user
        Task {
            await sendSuggestionNotification(name: name, address: address)
        }
    }
    
    private func sendSuggestionNotification(name: String, address: String) async {
        guard notificationService.isAuthorized else {
            print("⚠️ Notifications not authorized, skipping suggestion notification")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "📍 \(name)"
        content.body = "Tap to save this location to your favorites"
        content.sound = .default
        content.categoryIdentifier = "LOCATION_SUGGESTION"
        content.userInfo = [
            "type": "location_suggestion",
            "name": name,
            "address": address,
            "latitude": suggestedLocation?.latitude ?? 0,
            "longitude": suggestedLocation?.longitude ?? 0
        ]
        
        // Add action buttons
        let saveAction = UNNotificationAction(
            identifier: "SAVE_LOCATION",
            title: "Save Location",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_SUGGESTION",
            title: "Not Now",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "LOCATION_SUGGESTION",
            actions: [saveAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "location-suggestion-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Show immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📍 Sent location suggestion notification for: \(name)")
        } catch {
            print("❌ Failed to send location suggestion notification: \(error)")
        }
    }
}

// MARK: - SuggestedLocation Model

struct SuggestedLocation: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let suggestedAt: Date
    let coordinateKey: String
    
    // No longer showing dwell time in UI, but keeping for internal use
    var dwellTimeMinutes: Int {
        let elapsed = Date().timeIntervalSince(suggestedAt)
        return Int(elapsed / 60) + 5 // Add the 5 min threshold
    }
}
