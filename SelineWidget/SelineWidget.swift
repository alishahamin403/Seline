//
//  SelineWidget.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import WidgetKit
import SwiftUI

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
    let todaysTasks: [TaskForWidget]
    let monthlySpending: Double
    let monthOverMonthPercentage: Double
    let isSpendingIncreasing: Bool
    let dailySpending: Double
    let visitedLocation: String?
    let elapsedTime: String?
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        return SelineWidgetEntry(
            date: Date(),
            todaysTasks: [
                TaskForWidget(id: "1", title: "Sample Event", scheduledTime: Date(), isCompleted: false, tagId: nil, tagName: nil)
            ],
            monthlySpending: 2450.80,
            monthOverMonthPercentage: 12.0,
            isSpendingIncreasing: true,
            dailySpending: 125.50,
            visitedLocation: "Home",
            elapsedTime: "1h 23m"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let entry = SelineWidgetEntry(
            date: Date(),
            todaysTasks: [],
            monthlySpending: 2450.80,
            monthOverMonthPercentage: 12.0,
            isSpendingIncreasing: true,
            dailySpending: 125.50,
            visitedLocation: "Home",
            elapsedTime: "1h 23m"
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        var entries: [SelineWidgetEntry] = []
        let currentDate = Date()

        // Load spending data from shared UserDefaults
        let userDefaults = UserDefaults(suiteName: "group.seline")
        let monthlySpending = userDefaults?.double(forKey: "widgetMonthlySpending") ?? 0.0
        let monthOverMonthPercentage = userDefaults?.double(forKey: "widgetMonthOverMonthPercentage") ?? 0.0
        let isSpendingIncreasing = userDefaults?.bool(forKey: "widgetIsSpendingIncreasing") ?? false
        let dailySpending = userDefaults?.double(forKey: "widgetDailySpending") ?? 0.0
        let visitedLocation = userDefaults?.string(forKey: "widgetVisitedLocation")
        let elapsedTime = userDefaults?.string(forKey: "widgetElapsedTime")

        // Load today's tasks
        let todaysTasks = loadTodaysTasks()

        // Create entry with spending data
        let entry = SelineWidgetEntry(
            date: currentDate,
            todaysTasks: todaysTasks,
            monthlySpending: monthlySpending,
            monthOverMonthPercentage: monthOverMonthPercentage,
            isSpendingIncreasing: isSpendingIncreasing,
            dailySpending: dailySpending,
            visitedLocation: visitedLocation,
            elapsedTime: elapsedTime
        )

        entries.append(entry)

        // Update timeline more frequently (every minute) to keep time display current
        let timeline = Timeline(entries: entries, policy: .after(Date(timeIntervalSinceNow: 60)))
        completion(timeline)
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

    var widgetBackgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.16) : Color(red: 0.98, green: 0.97, blue: 0.95)
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

    @ViewBuilder
    var body: some View {
        if widgetFamily == .systemSmall {
            smallWidgetView
                .containerBackground(for: .widget) {
                    widgetBackgroundColor
                }
        } else if widgetFamily == .systemMedium {
            mediumWidgetView
                .containerBackground(for: .widget) {
                    widgetBackgroundColor
                }
        } else if widgetFamily == .systemLarge {
            largeWidgetView
                .containerBackground(for: .widget) {
                    widgetBackgroundColor
                }
        }
    }

    var smallWidgetView: some View {
        VStack(spacing: 10) {
            Spacer()

            // Location card with pill background
            Link(destination: URL(string: "seline://action/timeline")!) {
                if let location = entry.visitedLocation, let elapsed = entry.elapsedTime {
                    VStack(alignment: .center, spacing: 6) {
                        Text(location)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(badgeContentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(elapsed)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(badgeContentColor.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(badgeBackgroundColor))
                } else {
                    VStack(alignment: .center, spacing: 4) {
                        Text("Not at saved location")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(badgeContentColor.opacity(0.6))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(10)
                    .background(Capsule().fill(badgeBackgroundColor))
                }
            }
            .buttonStyle(.plain)

            // Spending card with pill background
            Link(destination: URL(string: "seline://action/receipts")!) {
                VStack(alignment: .center, spacing: 4) {
                    Text(String(format: "$%.2f", entry.dailySpending))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(badgeContentColor)

                    Text("TODAY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(badgeContentColor.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(Capsule().fill(badgeBackgroundColor))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "seline://action/home"))
    }


    var mediumWidgetView: some View {
        HStack(alignment: .center, spacing: 12) {
                // LEFT HALF - Location and Spending
                VStack(spacing: 10) {
                    // Location card (keeping existing colors)
                    Link(destination: URL(string: "seline://action/timeline")!) {
                        if let location = entry.visitedLocation, let elapsed = entry.elapsedTime {
                            VStack(alignment: .center, spacing: 6) {
                                Text(location)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(badgeContentColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(elapsed)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(badgeContentColor.opacity(0.7))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(badgeBackgroundColor))
                        } else {
                            VStack(alignment: .center, spacing: 4) {
                                Text("Not at saved location")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(badgeContentColor.opacity(0.6))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(10)
                            .background(Capsule().fill(badgeBackgroundColor))
                        }
                    }
                    .buttonStyle(.plain)

                    // Spending card
                    Link(destination: URL(string: "seline://action/receipts")!) {
                        VStack(alignment: .center, spacing: 4) {
                            Text(String(format: "$%.2f", entry.dailySpending))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(badgeContentColor)

                            Text("TODAY")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(badgeContentColor.opacity(0.6))
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(badgeBackgroundColor))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)

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
        .widgetURL(URL(string: "seline://action/home"))
    }

    var largeWidgetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // TOP SECTION - Location and Spending side by side
            HStack(alignment: .center, spacing: 12) {
                // Location card (keeping existing colors)
                Link(destination: URL(string: "seline://action/timeline")!) {
                    if let location = entry.visitedLocation, let elapsed = entry.elapsedTime {
                        VStack(alignment: .center, spacing: 6) {
                            Text(location)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(badgeContentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text(elapsed)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(badgeContentColor.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(badgeBackgroundColor))
                    } else {
                        VStack(alignment: .center, spacing: 4) {
                            Text("Not at saved location")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(badgeContentColor.opacity(0.6))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(10)
                        .background(Capsule().fill(badgeBackgroundColor))
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                // Spending card with value context
                Link(destination: URL(string: "seline://action/receipts")!) {
                    VStack(alignment: .center, spacing: 6) {
                        Text(String(format: "$%.2f", entry.dailySpending))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(badgeContentColor)

                        Text("TODAY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(badgeContentColor.opacity(0.6))
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Divider()
                            .opacity(0.3)
                            .padding(.vertical, 2)

                        VStack(alignment: .center, spacing: 3) {
                            Text(String(format: "$%.0f", entry.monthlySpending))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(badgeContentColor.opacity(0.8))

                            HStack(spacing: 4) {
                                Image(systemName: entry.isSpendingIncreasing ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(String(format: "%.0f%%", entry.monthOverMonthPercentage))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(entry.isSpendingIncreasing ? Color.red.opacity(0.85) : Color.green.opacity(0.85))

                            Text("vs last month")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(badgeContentColor.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            // Action buttons row
            HStack(spacing: 10) {
                Link(destination: URL(string: "seline://action/createNote")!) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(badgeContentColor)
                        .frame(width: 55, height: 55)
                        .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "seline://action/createEvent")!) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(badgeContentColor)
                        .frame(width: 55, height: 55)
                        .background(Circle().fill(badgeBackgroundColor))
                }
                .buttonStyle(.plain)

                Spacer()

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
            }

            Divider()
                .opacity(0.3)

            // BOTTOM SECTION - Today's Events sorted by time
            VStack(alignment: .leading, spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(uncompletedAndSorted, id: \.id) { task in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(getEventColor(for: task))
                                        .lineLimit(2)

                                    if let time = task.scheduledTime {
                                        Text(formatTime(time))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(badgeContentColor.opacity(0.6))
                                    }
                                }

                                if let tagName = task.tagName, !tagName.isEmpty {
                                    Spacer()
                                    Text(tagName)
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(textColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(badgeBackgroundColor)
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
        .widgetURL(URL(string: "seline://action/home"))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatCurrentTime(_ date: Date) -> String {
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
        }
        .configurationDisplayName("Seline")
        .description("Quick access to your Seline information")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
