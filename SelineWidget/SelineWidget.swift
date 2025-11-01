//
//  SelineWidget.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - User Location Preferences (mirrored from main app)
struct UserLocationPreferences: Codable, Equatable {
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
    var isFirstTimeSetup: Bool = true
}

struct SelineWidgetEntry: TimelineEntry {
    let date: Date
    let location1ETA: String?
    let location2ETA: String?
    let location3ETA: String?
    let location1Icon: String
    let location2Icon: String
    let location3Icon: String
    let location1Latitude: Double?
    let location1Longitude: Double?
    let location2Latitude: Double?
    let location2Longitude: Double?
    let location3Latitude: Double?
    let location3Longitude: Double?
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        return SelineWidgetEntry(
            date: Date(),
            location1ETA: "12 min",
            location2ETA: "25 min",
            location3ETA: "8 min",
            location1Icon: "house.fill",
            location2Icon: "briefcase.fill",
            location3Icon: "fork.knife",
            location1Latitude: nil,
            location1Longitude: nil,
            location2Latitude: nil,
            location2Longitude: nil,
            location3Latitude: nil,
            location3Longitude: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let entry = SelineWidgetEntry(
            date: Date(),
            location1ETA: "12 min",
            location2ETA: "25 min",
            location3ETA: "8 min",
            location1Icon: "house.fill",
            location2Icon: "briefcase.fill",
            location3Icon: "fork.knife",
            location1Latitude: nil,
            location1Longitude: nil,
            location2Latitude: nil,
            location2Longitude: nil,
            location3Latitude: nil,
            location3Longitude: nil
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        var entries: [SelineWidgetEntry] = []
        let currentDate = Date()

        // Load location preferences from UserDefaults
        var location1Icon = "house.fill"
        var location2Icon = "briefcase.fill"
        var location3Icon = "fork.knife"
        var location1Lat: Double? = nil
        var location1Lon: Double? = nil
        var location2Lat: Double? = nil
        var location2Lon: Double? = nil
        var location3Lat: Double? = nil
        var location3Lon: Double? = nil
        var location1ETA: String? = nil
        var location2ETA: String? = nil
        var location3ETA: String? = nil

        // Try to decode UserLocationPreferences from UserDefaults
        if let prefs = loadUserLocationPreferences() {
            location1Icon = prefs.location1Icon ?? "house.fill"
            location2Icon = prefs.location2Icon ?? "briefcase.fill"
            location3Icon = prefs.location3Icon ?? "fork.knife"
            location1Lat = prefs.location1Latitude
            location1Lon = prefs.location1Longitude
            location2Lat = prefs.location2Latitude
            location2Lon = prefs.location2Longitude
            location3Lat = prefs.location3Latitude
            location3Lon = prefs.location3Longitude
        }

        // Get current location and calculate ETAs
        if let lastLocation = loadLastUserLocation() {
            print("🟢 Widget: Loaded user location: \(lastLocation.latitude), \(lastLocation.longitude)")

            // Calculate ETAs using the saved location
            if let lat1 = location1Lat, let lon1 = location1Lon {
                print("🟢 Widget: Calculating ETA for location1: \(lat1), \(lon1)")
                location1ETA = calculateETADistance(from: lastLocation, toLat: lat1, toLon: lon1)
            }
            if let lat2 = location2Lat, let lon2 = location2Lon {
                print("🟢 Widget: Calculating ETA for location2: \(lat2), \(lon2)")
                location2ETA = calculateETADistance(from: lastLocation, toLat: lat2, toLon: lon2)
            }
            if let lat3 = location3Lat, let lon3 = location3Lon {
                print("🟢 Widget: Calculating ETA for location3: \(lat3), \(lon3)")
                location3ETA = calculateETADistance(from: lastLocation, toLat: lat3, toLon: lon3)
            }
        } else {
            print("🔴 Widget: Could not load user location from UserDefaults")
        }

        // Create entry with location data and calculated ETAs
        let entry = SelineWidgetEntry(
            date: currentDate,
            location1ETA: location1ETA ?? "---",
            location2ETA: location2ETA ?? "---",
            location3ETA: location3ETA ?? "---",
            location1Icon: location1Icon,
            location2Icon: location2Icon,
            location3Icon: location3Icon,
            location1Latitude: location1Lat,
            location1Longitude: location1Lon,
            location2Latitude: location2Lat,
            location2Longitude: location2Lon,
            location3Latitude: location3Lat,
            location3Longitude: location3Lon
        )

        // Generate one entry that updates every 10 minutes for more frequent ETA updates
        entries.append(entry)

        let timeline = Timeline(entries: entries, policy: .after(Date(timeIntervalSinceNow: 600)))
        completion(timeline)
    }

    // Helper to load UserLocationPreferences from UserDefaults
    private func loadUserLocationPreferences() -> UserLocationPreferences? {
        let userDefaults = UserDefaults(suiteName: "group.seline")
        guard let data = userDefaults?.data(forKey: "UserLocationPreferences") else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(UserLocationPreferences.self, from: data)
    }

    // Helper to load last known user location from UserDefaults
    private func loadLastUserLocation() -> CLLocationCoordinate2D? {
        let userDefaults = UserDefaults(suiteName: "group.seline")
        guard let lat = userDefaults?.double(forKey: "lastUserLocationLatitude"),
              let lon = userDefaults?.double(forKey: "lastUserLocationLongitude"),
              lat != 0 && lon != 0 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // Calculate ETA using distance-based estimation
    // Assumes average driving speed of 35 km/h (conservative for urban areas with traffic)
    private func calculateETADistance(from origin: CLLocationCoordinate2D, toLat: Double, toLon: Double) -> String? {
        let destinationCoordinate = CLLocationCoordinate2D(latitude: toLat, longitude: toLon)

        // Calculate distance using Haversine formula (approximate)
        let distance = calculateDistance(from: origin, to: destinationCoordinate)

        // Estimate time assuming average speed of 35 km/h
        let speedKmPerHour = 35.0
        let timeInHours = distance / speedKmPerHour
        let timeInSeconds = Int(timeInHours * 3600)

        return formatETA(timeInSeconds)
    }

    // Calculate distance between two coordinates (in kilometers)
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let to = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distanceMeters = from.distance(from: to)
        return distanceMeters / 1000.0 // Convert to km
    }

    // Format duration in seconds to a short string
    private func formatETA(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours)h"
        }

        return "\(minutes) min"
    }

}

struct SelineWidgetEntryView: View {
    var entry: SelineWidgetProvider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        if widgetFamily == .systemSmall {
            smallWidgetView
        } else {
            mediumWidgetView
        }
    }

    var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 3 Location ETAs
            VStack(alignment: .leading, spacing: 8) {
                // Location 1
                Link(destination: googleMapsURL(lat: entry.location1Latitude, lon: entry.location1Longitude)) {
                    HStack(spacing: 8) {
                        Image(systemName: entry.location1Icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 24)
                            .foregroundColor(.gray)

                        Text(entry.location1ETA ?? "---")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.gray)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                // Location 2
                Link(destination: googleMapsURL(lat: entry.location2Latitude, lon: entry.location2Longitude)) {
                    HStack(spacing: 8) {
                        Image(systemName: entry.location2Icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 24)
                            .foregroundColor(.gray)

                        Text(entry.location2ETA ?? "---")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.gray)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                // Location 3
                Link(destination: googleMapsURL(lat: entry.location3Latitude, lon: entry.location3Longitude)) {
                    HStack(spacing: 8) {
                        Image(systemName: entry.location3Icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 24)
                            .foregroundColor(.gray)

                        Text(entry.location3ETA ?? "---")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.gray)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()
                .opacity(0.3)

            // Action buttons
            HStack(spacing: 12) {
                // Note button
                Link(destination: URL(string: "seline://action/createNote") ?? URL(fileURLWithPath: "")) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                // Event button
                Link(destination: URL(string: "seline://action/createEvent") ?? URL(fileURLWithPath: "")) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func googleMapsURL(lat: Double?, lon: Double?) -> URL {
        guard let lat = lat, let lon = lon else {
            return URL(string: "https://maps.google.com")!
        }
        return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=driving")!
    }

    var mediumWidgetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Navigation")
                .font(.system(size: 16, weight: .bold))

            // 3 Location ETAs
            VStack(alignment: .leading, spacing: 10) {
                // Location 1
                HStack(spacing: 12) {
                    Image(systemName: entry.location1Icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location 1")
                            .font(.system(size: 11, weight: .regular))
                            .opacity(0.7)

                        Text(entry.location1ETA ?? "---")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Spacer()
                }

                Divider().opacity(0.2)

                // Location 2
                HStack(spacing: 12) {
                    Image(systemName: entry.location2Icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location 2")
                            .font(.system(size: 11, weight: .regular))
                            .opacity(0.7)

                        Text(entry.location2ETA ?? "---")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Spacer()
                }

                Divider().opacity(0.2)

                // Location 3
                HStack(spacing: 12) {
                    Image(systemName: entry.location3Icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location 3")
                            .font(.system(size: 11, weight: .regular))
                            .opacity(0.7)

                        Text(entry.location3ETA ?? "---")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Spacer()
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 12))
                        Text("New Note")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 12))
                        Text("New Event")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

struct SelineWidget: Widget {
    let kind: String = "com.seline.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SelineWidgetProvider()) { entry in
            SelineWidgetEntryView(entry: entry)
                .widgetBackground(Color.clear)
        }
        .configurationDisplayName("Seline")
        .description("Quick access to your Seline information")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Extension to support both iOS 16 and 17+
extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                color
            }
        } else {
            self.background(color)
        }
    }
}
