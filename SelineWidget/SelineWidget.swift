//
//  SelineWidget.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import WidgetKit
import SwiftUI

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
    var location4Address: String?
    var location4Latitude: Double?
    var location4Longitude: Double?
    var location4Icon: String?
    var isFirstTimeSetup: Bool = true
}

struct TaskForWidget: Codable {
    let id: String
    let title: String
    let scheduledTime: Date?
    let isCompleted: Bool
    let tagId: String?
    let tagName: String?
}

struct SelineWidgetEntry: TimelineEntry {
    let date: Date
    let location1ETA: String?
    let location2ETA: String?
    let location3ETA: String?
    let location4ETA: String?
    let location1Icon: String
    let location2Icon: String
    let location3Icon: String
    let location4Icon: String
    let location1Latitude: Double?
    let location1Longitude: Double?
    let location2Latitude: Double?
    let location2Longitude: Double?
    let location3Latitude: Double?
    let location3Longitude: Double?
    let location4Latitude: Double?
    let location4Longitude: Double?
    let todaysTasks: [TaskForWidget]
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        return SelineWidgetEntry(
            date: Date(),
            location1ETA: "12 min",
            location2ETA: "25 min",
            location3ETA: "8 min",
            location4ETA: "15 min",
            location1Icon: "house.fill",
            location2Icon: "briefcase.fill",
            location3Icon: "fork.knife",
            location4Icon: "gym.bag.fill",
            location1Latitude: nil,
            location1Longitude: nil,
            location2Latitude: nil,
            location2Longitude: nil,
            location3Latitude: nil,
            location3Longitude: nil,
            location4Latitude: nil,
            location4Longitude: nil,
            todaysTasks: [
                TaskForWidget(id: "1", title: "Sample Event", scheduledTime: Date(), isCompleted: false, tagId: nil, tagName: nil)
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let entry = SelineWidgetEntry(
            date: Date(),
            location1ETA: "12 min",
            location2ETA: "25 min",
            location3ETA: "8 min",
            location4ETA: "15 min",
            location1Icon: "house.fill",
            location2Icon: "briefcase.fill",
            location3Icon: "fork.knife",
            location4Icon: "gym.bag.fill",
            location1Latitude: nil,
            location1Longitude: nil,
            location2Latitude: nil,
            location2Longitude: nil,
            location3Latitude: nil,
            location3Longitude: nil,
            location4Latitude: nil,
            location4Longitude: nil,
            todaysTasks: []
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
        var location4Icon = "gym.bag.fill"
        var location1Lat: Double? = nil
        var location1Lon: Double? = nil
        var location2Lat: Double? = nil
        var location2Lon: Double? = nil
        var location3Lat: Double? = nil
        var location3Lon: Double? = nil
        var location4Lat: Double? = nil
        var location4Lon: Double? = nil
        var location1ETA: String? = nil
        var location2ETA: String? = nil
        var location3ETA: String? = nil
        var location4ETA: String? = nil

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

        // Load pre-calculated ETAs from the app's NavigationService
        let userDefaults = UserDefaults(suiteName: "group.seline")

        location1ETA = userDefaults?.string(forKey: "widgetLocation1ETA")
        location2ETA = userDefaults?.string(forKey: "widgetLocation2ETA")
        location3ETA = userDefaults?.string(forKey: "widgetLocation3ETA")
        location4ETA = userDefaults?.string(forKey: "widgetLocation4ETA")

        print("🟢 Widget: Loaded ETAs from shared UserDefaults - L1: \(location1ETA ?? "---"), L2: \(location2ETA ?? "---"), L3: \(location3ETA ?? "---"), L4: \(location4ETA ?? "---")")

        // Load today's tasks
        let todaysTasks = loadTodaysTasks()

        // Create entry with location data
        // Note: ETAs are loaded from shared UserDefaults but will show as nil if not available
        let entry = SelineWidgetEntry(
            date: currentDate,
            location1ETA: location1ETA,
            location2ETA: location2ETA,
            location3ETA: location3ETA,
            location4ETA: location4ETA,
            location1Icon: location1Icon,
            location2Icon: location2Icon,
            location3Icon: location3Icon,
            location4Icon: location4Icon,
            location1Latitude: location1Lat,
            location1Longitude: location1Lon,
            location2Latitude: location2Lat,
            location2Longitude: location2Lon,
            location3Latitude: location3Lat,
            location3Longitude: location3Lon,
            location4Latitude: location4Lat,
            location4Longitude: location4Lon,
            todaysTasks: todaysTasks
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

    // Helper to load today's tasks from UserDefaults
    private func loadTodaysTasks() -> [TaskForWidget] {
        let userDefaults = UserDefaults(suiteName: "group.seline")
        guard let data = userDefaults?.data(forKey: "widgetTodaysTasks") else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let tasks = try? decoder.decode([TaskForWidget].self, from: data) {
            return tasks
        }
        return []
    }

}

struct SelineWidgetEntryView: View {
    var entry: SelineWidgetProvider.Entry
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.colorScheme) var colorScheme

    var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }

    private func getEventColor(for task: TaskForWidget) -> Color {
        // Determine color based on task type (synced, tagged, or personal)
        if task.id.hasPrefix("cal_") {
            // Synced events - blue color
            return colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color.blue
        } else if let tagId = task.tagId, !tagId.isEmpty {
            // Tagged events - use a purple/accent color
            return colorScheme == .dark ? Color(red: 0.8, green: 0.6, blue: 1.0) : Color.purple
        } else {
            // Personal events - light gray
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
        }
    }

    var body: some View {
        if widgetFamily == .systemSmall {
            smallWidgetView
        } else {
            mediumWidgetView
        }
    }

    var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
                // 4 Location ETAs
                VStack(alignment: .leading, spacing: 6) {
                    // Location 1
                    Link(destination: googleMapsURL(lat: entry.location1Latitude, lon: entry.location1Longitude)) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.location1Icon)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 24)
                                .foregroundColor(textColor)

                            if let eta = entry.location1ETA {
                                Text(eta)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                                    .opacity(0.5)
                            }

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
                                .foregroundColor(textColor)

                            if let eta = entry.location2ETA {
                                Text(eta)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                                    .opacity(0.5)
                            }

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
                                .foregroundColor(textColor)

                            if let eta = entry.location3ETA {
                                Text(eta)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                                    .opacity(0.5)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    // Location 4
                    Link(destination: googleMapsURL(lat: entry.location4Latitude, lon: entry.location4Longitude)) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.location4Icon)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 24)
                                .foregroundColor(textColor)

                            if let eta = entry.location4ETA {
                                Text(eta)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(textColor)
                                    .opacity(0.5)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Note button
                    VStack {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundColor(textColor)
                    }
                    .contentShape(Rectangle())
                    .widgetURL(URL(string: "seline://action/createNote"))

                    // Event button
                    VStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundColor(textColor)
                    }
                    .contentShape(Rectangle())
                    .widgetURL(URL(string: "seline://action/createEvent"))
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
        HStack(spacing: 12) {
            // Left side - 40% (ETAs + buttons)
            VStack(alignment: .center, spacing: 10) {
                Spacer()

                // 4 Location ETAs (2x2 grid - icon on top, time below)
                VStack(spacing: 12) {
                    // Row 1 - Locations 1 & 2
                    HStack(spacing: 12) {
                        // Location 1
                        Link(destination: googleMapsURL(lat: entry.location1Latitude, lon: entry.location1Longitude)) {
                            VStack(spacing: 4) {
                                Image(systemName: entry.location1Icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(height: 20)
                                    .foregroundColor(textColor)

                                if let eta = entry.location1ETA {
                                    Text(eta)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                } else {
                                    Text("--")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                        .opacity(0.5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)

                        // Location 2
                        Link(destination: googleMapsURL(lat: entry.location2Latitude, lon: entry.location2Longitude)) {
                            VStack(spacing: 4) {
                                Image(systemName: entry.location2Icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(height: 20)
                                    .foregroundColor(textColor)

                                if let eta = entry.location2ETA {
                                    Text(eta)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                } else {
                                    Text("--")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                        .opacity(0.5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }

                    // Row 2 - Locations 3 & 4
                    HStack(spacing: 12) {
                        // Location 3
                        Link(destination: googleMapsURL(lat: entry.location3Latitude, lon: entry.location3Longitude)) {
                            VStack(spacing: 4) {
                                Image(systemName: entry.location3Icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(height: 20)
                                    .foregroundColor(textColor)

                                if let eta = entry.location3ETA {
                                    Text(eta)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                } else {
                                    Text("--")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                        .opacity(0.5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)

                        // Location 4
                        Link(destination: googleMapsURL(lat: entry.location4Latitude, lon: entry.location4Longitude)) {
                            VStack(spacing: 4) {
                                Image(systemName: entry.location4Icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(height: 20)
                                    .foregroundColor(textColor)

                                if let eta = entry.location4ETA {
                                    Text(eta)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                } else {
                                    Text("--")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                        .opacity(0.5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Spacer between ETAs and buttons
                Spacer()
                    .frame(height: 12)

                // Buttons
                HStack(spacing: 12) {
                    // Note button
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .widgetURL(URL(string: "seline://action/createNote"))

                    // Event button
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .widgetURL(URL(string: "seline://action/createEvent"))
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .layoutPriority(0)

            Divider()
                .opacity(0.3)

            // Right side - 50% (Today's uncompleted events, sorted by time, vertically centered)
            VStack(alignment: .leading, spacing: 4) {
                let uncompletedAndSorted = entry.todaysTasks
                    .filter { !$0.isCompleted }
                    .sorted {
                        let time1 = $0.scheduledTime ?? Date.distantFuture
                        let time2 = $1.scheduledTime ?? Date.distantFuture
                        return time1 < time2
                    }

                Spacer()
                    .frame(height: 8)

                if uncompletedAndSorted.isEmpty {
                    VStack(alignment: .center, spacing: 4) {
                        Text("No pending events")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(textColor.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(uncompletedAndSorted.prefix(6), id: \.id) { task in
                        HStack(spacing: 4) {
                            // Colored circle for event status
                            Image(systemName: "circle")
                                .font(.system(size: 9))
                                .foregroundColor(getEventColor(for: task))

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(task.title)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textColor)
                                        .lineLimit(1)

                                    if let tagName = task.tagName, !tagName.isEmpty {
                                        Text(tagName)
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(textColor)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(3)
                                    }

                                    Spacer()
                                }

                                if let time = task.scheduledTime {
                                    Text(formatTime(time))
                                        .font(.system(size: 8, weight: .regular))
                                        .foregroundColor(textColor.opacity(0.6))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
            .layoutPriority(0)
        }
        .padding(14)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SelineWidget: Widget {
    let kind: String = "com.seline.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SelineWidgetProvider()) { entry in
            SelineWidgetEntryView(entry: entry)
                // Widget handles its own background color in dark mode via ZStack
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
