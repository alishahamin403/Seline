//
//  SelineWidget.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import WidgetKit
import SwiftUI

struct SelineWidgetEntry: TimelineEntry {
    let date: Date
    let location1ETA: String?
    let location2ETA: String?
    let location3ETA: String?
    let location1Icon: String
    let location2Icon: String
    let location3Icon: String
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
            location3Icon: "fork.knife"
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
            location3Icon: "fork.knife"
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        var entries: [SelineWidgetEntry] = []
        let currentDate = Date()

        // Create entry with location ETAs (defaults shown, can be updated with real data)
        let entry = SelineWidgetEntry(
            date: currentDate,
            location1ETA: "12 min",
            location2ETA: "25 min",
            location3ETA: "8 min",
            location1Icon: "house.fill",
            location2Icon: "briefcase.fill",
            location3Icon: "fork.knife"
        )

        // Generate one entry that updates every hour
        entries.append(entry)

        let timeline = Timeline(entries: entries, policy: .after(Date(timeIntervalSinceNow: 3600)))
        completion(timeline)
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
                HStack(spacing: 8) {
                    Image(systemName: entry.location1Icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)

                    Text(entry.location1ETA ?? "---")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()
                }

                // Location 2
                HStack(spacing: 8) {
                    Image(systemName: entry.location2Icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)

                    Text(entry.location2ETA ?? "---")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()
                }

                // Location 3
                HStack(spacing: 8) {
                    Image(systemName: entry.location3Icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)

                    Text(entry.location3ETA ?? "---")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()
                }
            }

            Divider()
                .opacity(0.3)

            // Action buttons
            HStack(spacing: 12) {
                // Note button
                Button(action: {}) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                // Event button
                Button(action: {}) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
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
