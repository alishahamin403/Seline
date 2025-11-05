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
    let monthlySpending: Double
    let monthOverMonthPercentage: Double
    let isSpendingIncreasing: Bool
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
            ],
            monthlySpending: 2450.80,
            monthOverMonthPercentage: 12.0,
            isSpendingIncreasing: true
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
            todaysTasks: [],
            monthlySpending: 2450.80,
            monthOverMonthPercentage: 12.0,
            isSpendingIncreasing: true
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
            location4Icon = prefs.location4Icon ?? "gym.bag.fill"
            location1Lat = prefs.location1Latitude
            location1Lon = prefs.location1Longitude
            location2Lat = prefs.location2Latitude
            location2Lon = prefs.location2Longitude
            location3Lat = prefs.location3Latitude
            location3Lon = prefs.location3Longitude
            location4Lat = prefs.location4Latitude
            location4Lon = prefs.location4Longitude
        }

        // Load pre-calculated ETAs from the app's NavigationService
        let userDefaults = UserDefaults(suiteName: "group.seline")

        location1ETA = userDefaults?.string(forKey: "widgetLocation1ETA")
        location2ETA = userDefaults?.string(forKey: "widgetLocation2ETA")
        location3ETA = userDefaults?.string(forKey: "widgetLocation3ETA")
        location4ETA = userDefaults?.string(forKey: "widgetLocation4ETA")

        print("🟢 Widget: Loaded ETAs from shared UserDefaults - L1: \(location1ETA ?? "---"), L2: \(location2ETA ?? "---"), L3: \(location3ETA ?? "---"), L4: \(location4ETA ?? "---")")

        // Load spending data from shared UserDefaults
        let monthlySpending = userDefaults?.double(forKey: "widgetMonthlySpending") ?? 0.0
        let monthOverMonthPercentage = userDefaults?.double(forKey: "widgetMonthOverMonthPercentage") ?? 0.0
        let isSpendingIncreasing = userDefaults?.bool(forKey: "widgetIsSpendingIncreasing") ?? false

        // Load today's tasks
        let todaysTasks = loadTodaysTasks()

        // Create entry with location data and spending data
        // Note: ETAs and spending data are loaded from shared UserDefaults but will show defaults if not available
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
            todaysTasks: todaysTasks,
            monthlySpending: monthlySpending,
            monthOverMonthPercentage: monthOverMonthPercentage,
            isSpendingIncreasing: isSpendingIncreasing
        )

        // Generate one entry that updates every 5 minutes for more frequent ETA updates
        entries.append(entry)

        let timeline = Timeline(entries: entries, policy: .after(Date(timeIntervalSinceNow: 300)))
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
        colorScheme == .dark ? Color(red: 0.94, green: 0.94, blue: 0.95) : .black
    }

    var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }

    // Gunmetal theme - bright text for contrast
    var badgeContentColor: Color {
        colorScheme == .dark ? Color(red: 0.94, green: 0.94, blue: 0.95) : Color.black.opacity(0.7)
    }

    // Gunmetal theme - slightly lighter gunmetal background for badges
    var badgeBackgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.23) : Color.black.opacity(0.08)
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
        } else if widgetFamily == .systemMedium {
            mediumWidgetView
        } else if widgetFamily == .systemLarge {
            largeWidgetView
        }
    }

    var smallWidgetView: some View {
        VStack(spacing: 0) {
            // Chat button at top (pill-shaped)
            Link(destination: URL(string: "seline://action/chat")!) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(badgeContentColor.opacity(0.6))

                    Text("Chat")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(badgeContentColor.opacity(0.6))

                    Spacer()
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .background(badgeBackgroundColor)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .padding(10)

            Spacer()

            // Centered action buttons
            HStack(spacing: 12) {
                Spacer()

                // Note button
                Link(destination: URL(string: "seline://action/createNote")!) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(badgeContentColor)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                // Event button
                Link(destination: URL(string: "seline://action/createEvent")!) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(badgeContentColor)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(0)
    }

    private func googleMapsURL(lat: Double?, lon: Double?) -> URL {
        guard let lat = lat, let lon = lon else {
            return URL(string: "https://maps.google.com")!
        }
        // Try Google Maps app first with comgooglemaps scheme
        // Falls back to web URL if app not installed
        return URL(string: "comgooglemaps://?daddr=\(lat),\(lon)")
            ?? URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)")!
    }

    var mediumWidgetView: some View {
        HStack(alignment: .center, spacing: 12) {
            // LEFT HALF - 4 ETAs in 2x2 grid
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    // Location 1
                    Link(destination: googleMapsURL(lat: entry.location1Latitude, lon: entry.location1Longitude)) {
                        VStack(spacing: 4) {
                            Image(systemName: entry.location1Icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(badgeContentColor)

                            if let eta = entry.location1ETA {
                                Text(eta)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                                    .opacity(0.5)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)

                    // Location 2
                    Link(destination: googleMapsURL(lat: entry.location2Latitude, lon: entry.location2Longitude)) {
                        VStack(spacing: 4) {
                            Image(systemName: entry.location2Icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(badgeContentColor)

                            if let eta = entry.location2ETA {
                                Text(eta)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                                    .opacity(0.5)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    // Location 3
                    Link(destination: googleMapsURL(lat: entry.location3Latitude, lon: entry.location3Longitude)) {
                        VStack(spacing: 4) {
                            Image(systemName: entry.location3Icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(badgeContentColor)

                            if let eta = entry.location3ETA {
                                Text(eta)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                                    .opacity(0.5)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)

                    // Location 4
                    Link(destination: googleMapsURL(lat: entry.location4Latitude, lon: entry.location4Longitude)) {
                        VStack(spacing: 4) {
                            Image(systemName: entry.location4Icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(badgeContentColor)

                            if let eta = entry.location4ETA {
                                Text(eta)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                            } else {
                                Text("--")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(badgeContentColor)
                                    .opacity(0.5)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)
                }
            }

            // RIGHT HALF - Action buttons and chat
            VStack(spacing: 10) {
                // Note and Event buttons side by side
                HStack(spacing: 10) {
                    // Note button
                    Link(destination: URL(string: "seline://action/createNote")!) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(badgeContentColor)
                            .frame(width: 55, height: 55)
                            .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)

                    // Event button
                    Link(destination: URL(string: "seline://action/createEvent")!) {
                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(badgeContentColor)
                            .frame(width: 55, height: 55)
                            .background(Circle().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)
                }

                // Chat bar - pill-shaped
                Link(destination: URL(string: "seline://action/chat")!) {
                    Text("Chat")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(badgeContentColor.opacity(0.7))
                        .frame(height: 44)
                        .frame(maxWidth: 120)
                        .background(badgeBackgroundColor)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
    }

    var largeWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top section - 4 ETAs in a single row
            HStack(spacing: 10) {
                // Location 1
                Link(destination: googleMapsURL(lat: entry.location1Latitude, lon: entry.location1Longitude)) {
                    VStack(spacing: 4) {
                        Image(systemName: entry.location1Icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(badgeContentColor)

                        if let eta = entry.location1ETA {
                            Text(eta)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                        } else {
                            Text("--")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                                .opacity(0.5)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                // Location 2
                Link(destination: googleMapsURL(lat: entry.location2Latitude, lon: entry.location2Longitude)) {
                    VStack(spacing: 4) {
                        Image(systemName: entry.location2Icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(badgeContentColor)

                        if let eta = entry.location2ETA {
                            Text(eta)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                        } else {
                            Text("--")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                                .opacity(0.5)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                // Location 3
                Link(destination: googleMapsURL(lat: entry.location3Latitude, lon: entry.location3Longitude)) {
                    VStack(spacing: 4) {
                        Image(systemName: entry.location3Icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(badgeContentColor)

                        if let eta = entry.location3ETA {
                            Text(eta)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                        } else {
                            Text("--")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                                .opacity(0.5)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                // Location 4
                Link(destination: googleMapsURL(lat: entry.location4Latitude, lon: entry.location4Longitude)) {
                    VStack(spacing: 4) {
                        Image(systemName: entry.location4Icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(badgeContentColor)

                        if let eta = entry.location4ETA {
                            Text(eta)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                        } else {
                            Text("--")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor)
                                .opacity(0.5)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .opacity(0.3)

            // Middle section - Action buttons
            HStack(spacing: 10) {
                Spacer()

                // Note button
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badgeContentColor)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                    .contentShape(Circle())
                    .widgetURL(URL(string: "seline://action/createNote"))

                // Event button
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badgeContentColor)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(badgeBackgroundColor))
                    .contentShape(Circle())
                    .widgetURL(URL(string: "seline://action/createEvent"))

                Spacer()
            }

            Divider()
                .opacity(0.3)

            // Bottom section - All active events
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Events")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textColor.opacity(0.7))
                    .padding(.horizontal, 2)

                let uncompletedAndSorted = entry.todaysTasks
                    .filter { !$0.isCompleted }
                    .sorted {
                        let time1 = $0.scheduledTime ?? Date.distantFuture
                        let time2 = $1.scheduledTime ?? Date.distantFuture
                        return time1 < time2
                    }

                if uncompletedAndSorted.isEmpty {
                    VStack(alignment: .center, spacing: 4) {
                        Text("No pending events")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(textColor.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(uncompletedAndSorted, id: \.id) { task in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(getEventColor(for: task))
                                        .lineLimit(2)

                                    if let time = task.scheduledTime {
                                        Text(formatTime(time))
                                            .font(.system(size: 9, weight: .regular))
                                            .foregroundColor(textColor.opacity(0.6))
                                    }
                                }

                                if let tagName = task.tagName, !tagName.isEmpty {
                                    Spacer()
                                    Text(tagName)
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(textColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                // Gunmetal theme background
                .widgetBackground(Color(red: 0.15, green: 0.15, blue: 0.16))
        }
        .configurationDisplayName("Seline")
        .description("Quick access to your Seline information")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
