import Foundation
import CoreLocation
import MapKit
import EventKit

/// SmartReminderService: Intelligent event reminders with travel time calculation
/// Sends notifications that factor in current location and travel time to event location
@MainActor
class SmartReminderService: ObservableObject {
    static let shared = SmartReminderService()

    private let notificationService = NotificationService.shared
    private let calendarService = CalendarSyncService.shared
    private let locationManager = SharedLocationManager.shared

    // Preferences
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "smartRemindersEnabled")
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "smartRemindersEnabled")

        // Default: enabled
        if !UserDefaults.standard.bool(forKey: "smartRemindersEnabledSet") {
            self.isEnabled = true
            UserDefaults.standard.set(true, forKey: "smartRemindersEnabledSet")
        }
    }

    // MARK: - Schedule Smart Reminders

    /// Process calendar events and schedule smart reminders
    func processUpcomingEvents() async {
        guard isEnabled else { return }

        // Get all upcoming events (filtered by user email)
        let userEmail = AuthenticationManager.shared.currentUser?.profile?.email
        let events = await calendarService.fetchCalendarEventsFromCurrentMonthOnwards(userEmail: userEmail)
        let calendar = Calendar.current
        let now = Date()

        // Filter events for today and tomorrow
        let upcomingEvents = events.filter { event in
            let daysUntilEvent = calendar.dateComponents([.day], from: now, to: event.startDate).day ?? 100
            return daysUntilEvent >= 0 && daysUntilEvent <= 1
        }

        print("🗓️ Processing \(upcomingEvents.count) upcoming events for smart reminders")

        for event in upcomingEvents {
            await scheduleSmartReminder(for: event)
        }
    }

    /// Schedule a smart reminder for a specific event
    private func scheduleSmartReminder(for event: EKEvent) async {
        // Skip if event is in the past
        guard event.startDate > Date() else { return }

        // Get current location
        guard let currentLocation = locationManager.currentLocation else {
            print("⚠️ No current location available for smart reminder")
            // Fall back to standard reminder
            await scheduleStandardReminder(for: event)
            return
        }

        // Try to extract location from event
        if let eventLocation = event.location, !eventLocation.isEmpty {
            // Geocode event location
            if let eventCoordinate = await geocodeLocation(eventLocation) {
                // Calculate travel time
                let travelMinutes = await calculateTravelTime(
                    from: currentLocation.coordinate,
                    to: eventCoordinate
                )

                // Add buffer time (5-10 minutes depending on distance)
                let bufferMinutes = travelMinutes > 20 ? 10 : 5
                let totalMinutes = travelMinutes + bufferMinutes

                // Get current location name (if we're at a saved place)
                let currentLocationName = await getCurrentLocationName()

                // Schedule notification
                await notificationService.scheduleSmartEventReminder(
                    eventTitle: event.title,
                    eventTime: event.startDate,
                    travelMinutes: totalMinutes,
                    currentLocation: currentLocationName
                )

                print("⏰ Scheduled smart reminder for '\(event.title)' with \(totalMinutes) min travel time")
                return
            }
        }

        // If we couldn't get event location, use standard reminder
        await scheduleStandardReminder(for: event)
    }

    /// Schedule standard reminder (fallback when location is unavailable)
    private func scheduleStandardReminder(for event: EKEvent) async {
        // Use default 15-minute reminder
        let reminderTime = event.startDate.addingTimeInterval(-15 * 60)

        // Only schedule if reminder time is in the future
        guard reminderTime > Date() else { return }

        await notificationService.scheduleSmartEventReminder(
            eventTitle: event.title,
            eventTime: event.startDate,
            travelMinutes: 15,
            currentLocation: nil
        )
    }

    // MARK: - Travel Time Calculation

    /// Calculate travel time between two coordinates
    private func calculateTravelTime(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> Int {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile // Could be made configurable

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                let travelTimeMinutes = Int(route.expectedTravelTime / 60)
                return max(travelTimeMinutes, 5) // Minimum 5 minutes
            }
        } catch {
            print("⚠️ Error calculating travel time: \(error)")
        }

        // Fallback: rough estimate based on distance
        let distance = CLLocation(latitude: source.latitude, longitude: source.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))

        // Rough estimate: 40 km/h average speed
        let estimatedMinutes = Int((distance / 1000) / 40 * 60)
        return max(estimatedMinutes, 10) // Minimum 10 minutes
    }

    // MARK: - Location Services

    /// Geocode a location string to coordinates
    private func geocodeLocation(_ locationString: String) async -> CLLocationCoordinate2D? {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.geocodeAddressString(locationString)
            if let location = placemarks.first?.location {
                return location.coordinate
            }
        } catch {
            print("⚠️ Error geocoding location '\(locationString)': \(error)")
        }

        return nil
    }

    /// Get current location name if at a saved place
    private func getCurrentLocationName() async -> String? {
        guard let currentLocation = locationManager.currentLocation else { return nil }

        let locationsManager = LocationsManager.shared
        let savedPlaces = locationsManager.savedPlaces

        // Check if we're at any saved location
        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)

            // If within 300m, consider we're at this location
            if distance < 300 {
                return place.displayName
            }
        }

        return nil
    }

    // MARK: - Background Update

    /// Called by app when location changes significantly or calendar updates
    func refreshSmartReminders() async {
        await processUpcomingEvents()
    }
}
