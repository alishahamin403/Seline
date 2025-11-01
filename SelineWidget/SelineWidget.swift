//
//  SelineWidget.swift
//  SelineWidget
//
//  Created by Alishah Amin on 2025-11-01.
//

import WidgetKit
import SwiftUI

// Helper function to format time until event
func getTimeUntilString(from date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    guard date > now else { return "Now" }

    let components = calendar.dateComponents([.hour, .minute, .day], from: now, to: date)

    if let day = components.day, day > 0 {
        return "in \(day)d"
    } else if let hour = components.hour, hour > 0 {
        return "in \(hour)h"
    } else if let minute = components.minute, minute > 0 {
        return "in \(minute)m"
    } else {
        return "Soon"
    }
}

struct SelineWidgetEntry: TimelineEntry {
    let date: Date
    let upcomingEvents: [UpcomingEvent]
}

struct UpcomingEvent {
    let title: String
    let startTime: Date
    let timeUntilStart: String
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        let events = [
            UpcomingEvent(title: "Team Meeting", startTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!, timeUntilStart: "in 1h"),
            UpcomingEvent(title: "Lunch", startTime: Calendar.current.date(byAdding: .hour, value: 3, to: Date())!, timeUntilStart: "in 3h"),
            UpcomingEvent(title: "Project Review", startTime: Calendar.current.date(byAdding: .hour, value: 5, to: Date())!, timeUntilStart: "in 5h")
        ]
        return SelineWidgetEntry(date: Date(), upcomingEvents: events)
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let events = [
            UpcomingEvent(title: "Team Meeting", startTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!, timeUntilStart: "in 1h"),
            UpcomingEvent(title: "Lunch", startTime: Calendar.current.date(byAdding: .hour, value: 3, to: Date())!, timeUntilStart: "in 3h"),
            UpcomingEvent(title: "Project Review", startTime: Calendar.current.date(byAdding: .hour, value: 5, to: Date())!, timeUntilStart: "in 5h")
        ]
        let entry = SelineWidgetEntry(date: Date(), upcomingEvents: events)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        let currentDate = Date()

        // Try to fetch upcoming events from Supabase
        Task {
            let upcomingEvents = await fetchUpcomingEvents()

            var entries: [SelineWidgetEntry] = []

            // Generate timeline for 5 hours
            for hourOffset in 0 ..< 5 {
                let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
                let entry = SelineWidgetEntry(date: entryDate, upcomingEvents: upcomingEvents)
                entries.append(entry)
            }

            let timeline = Timeline(entries: entries, policy: .atEnd)
            DispatchQueue.main.async {
                completion(timeline)
            }
        }
    }

    private func fetchUpcomingEvents() async -> [UpcomingEvent] {
        do {
            let supabaseURL = "https://xkqmqeyftdqswlczilhk.supabase.co"
            let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrcW1xZXlmdGRxc3dsY3ppbGhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mjk3Nzc3NTUsImV4cCI6MjA0NTM1Mzc1NX0.d9bCwpqPQdJpxQa8-1AObQPSJ2pKNKN3UPF0BzJXHlc"

            var urlComponents = URLComponents(string: "\(supabaseURL)/rest/v1/tasks")!
            let now = ISO8601DateFormatter().string(from: Date())

            // Query: Select next 3 upcoming tasks (not completed, with scheduled_time in future)
            urlComponents.queryItems = [
                URLQueryItem(name: "select", value: "id,title,scheduled_time"),
                URLQueryItem(name: "is_completed", value: "eq.false"),
                URLQueryItem(name: "scheduled_time", value: "gte.\(now)"),
                URLQueryItem(name: "order", value: "scheduled_time.asc"),
                URLQueryItem(name: "limit", value: "3")
            ]

            var request = URLRequest(url: urlComponents.url!)
            request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            // Parse response
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var events: [UpcomingEvent] = []
                for eventDict in json {
                    if let title = eventDict["title"] as? String,
                       let scheduledTimeString = eventDict["scheduled_time"] as? String,
                       let scheduledTime = ISO8601DateFormatter().date(from: scheduledTimeString) {
                        let timeUntil = getTimeUntilString(from: scheduledTime)
                        events.append(UpcomingEvent(
                            title: title,
                            startTime: scheduledTime,
                            timeUntilStart: timeUntil
                        ))
                    }
                }
                return events
            }

            return []
        } catch {
            print("Widget: Error fetching upcoming events: \(error)")
            return []
        }
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
        VStack(alignment: .leading, spacing: 10) {
            // ETAs list
            if entry.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No upcoming events")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Add a scheduled task")
                        .font(.system(size: 11, weight: .regular))
                        .opacity(0.7)
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.upcomingEvents.prefix(3)), id: \.title) { event in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)

                                Text(event.timeUntilStart)
                                    .font(.system(size: 10, weight: .regular))
                                    .opacity(0.7)
                            }
                            Spacer()
                        }
                    }
                }
            }

            Divider()
                .opacity(0.3)

            // Action buttons
            HStack(spacing: 12) {
                // Note button
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 11))
                        Text("Note")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Event button
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 11))
                        Text("Event")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    var mediumWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Events")
                    .font(.system(size: 16, weight: .bold))

                Spacer()
            }

            if entry.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No upcoming events")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Create your first event to get started")
                        .font(.system(size: 11, weight: .regular))
                        .opacity(0.7)
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entry.upcomingEvents.prefix(3)), id: \.title) { event in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .semibold))

                                Text(event.timeUntilStart)
                                    .font(.system(size: 11, weight: .regular))
                                    .opacity(0.7)
                            }
                            Spacer()
                        }

                        if entry.upcomingEvents.firstIndex(where: { $0.title == event.title }) ?? -1 < entry.upcomingEvents.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 12))
                        Text("New Note")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 12))
                        Text("New Event")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
