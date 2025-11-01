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
    let upcomingEvent: UpcomingEvent?
}

struct UpcomingEvent {
    let title: String
    let startTime: Date
    let timeUntilStart: String
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        let nextEventDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let event = UpcomingEvent(
            title: "Team Meeting",
            startTime: nextEventDate,
            timeUntilStart: "in 1h"
        )
        return SelineWidgetEntry(date: Date(), upcomingEvent: event)
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let nextEventDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let event = UpcomingEvent(
            title: "Team Meeting",
            startTime: nextEventDate,
            timeUntilStart: "in 1h"
        )
        let entry = SelineWidgetEntry(date: Date(), upcomingEvent: event)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        var entries: [SelineWidgetEntry] = []
        let currentDate = Date()

        // Mock upcoming event - in a real app, this would fetch from Supabase
        let nextEventDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let mockEvent = UpcomingEvent(
            title: "Team Meeting",
            startTime: nextEventDate,
            timeUntilStart: "in 1h"
        )

        // Generate timeline for 5 hours
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SelineWidgetEntry(date: entryDate, upcomingEvent: mockEvent)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SelineWidgetEntryView: View {
    var entry: SelineWidgetProvider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.15, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if widgetFamily == .systemSmall {
                // Small widget - ETA focused
                smallWidgetView
            } else {
                // Medium and larger widgets
                mediumWidgetView
            }
        }
        .cornerRadius(16)
    }

    var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Seline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }

            Spacer()

            // ETA Section
            if let event = entry.upcomingEvent {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(event.timeUntilStart)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.blue)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No upcoming events")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Time display
            Text(entry.date, style: .time)
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.gray)
        }
        .padding(12)
    }

    var mediumWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seline")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("Upcoming Event")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }

            Spacer()

            // ETA Section
            if let event = entry.upcomingEvent {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)

                        Text(event.timeUntilStart)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.blue)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No upcoming events")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text("You're all caught up!")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Footer
            HStack {
                Button(action: {}) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(entry.date, style: .time)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
