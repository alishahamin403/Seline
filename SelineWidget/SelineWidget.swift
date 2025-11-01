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
        // Fetch upcoming events from Supabase
        Task {
            let upcomingEvent = await fetchUpcomingEvent()

            var entries: [SelineWidgetEntry] = []
            let currentDate = Date()

            // Generate timeline for 5 hours
            for hourOffset in 0 ..< 5 {
                let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
                let entry = SelineWidgetEntry(date: entryDate, upcomingEvent: upcomingEvent)
                entries.append(entry)
            }

            let timeline = Timeline(entries: entries, policy: .atEnd)
            completion(timeline)
        }
    }

    private func fetchUpcomingEvent() async -> UpcomingEvent? {
        do {
            // Get the publishable key from keychain or use default
            let supabaseURL = "https://xkqmqeyftdqswlczilhk.supabase.co"
            let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrcW1xZXlmdGRxc3dsY3ppbGhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mjk3Nzc3NTUsImV4cCI6MjA0NTM1Mzc1NX0.d9bCwpqPQdJpxQa8-1AObQPSJ2pKNKN3UPF0BzJXHlc"

            var urlComponents = URLComponents(string: "\(supabaseURL)/rest/v1/tasks")!
            let now = ISO8601DateFormatter().string(from: Date())

            // Query: Select upcoming tasks (not completed, with scheduled_time in future)
            urlComponents.queryItems = [
                URLQueryItem(name: "select", value: "id,title,scheduled_time"),
                URLQueryItem(name: "is_completed", value: "eq.false"),
                URLQueryItem(name: "scheduled_time", value: "gte.\(now)"),
                URLQueryItem(name: "order", value: "scheduled_time.asc"),
                URLQueryItem(name: "limit", value: "1")
            ]

            var request = URLRequest(url: urlComponents.url!)
            request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            // Parse response
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstEvent = json.first,
               let title = firstEvent["title"] as? String,
               let scheduledTimeString = firstEvent["scheduled_time"] as? String,
               let scheduledTime = ISO8601DateFormatter().date(from: scheduledTimeString) {

                let timeUntil = getTimeUntilString(from: scheduledTime)
                return UpcomingEvent(
                    title: title,
                    startTime: scheduledTime,
                    timeUntilStart: timeUntil
                )
            }

            return nil
        } catch {
            print("Widget: Error fetching upcoming event: \(error)")
            return nil
        }
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
