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
}

struct SelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelineWidgetEntry {
        SelineWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SelineWidgetEntry) -> Void) {
        let entry = SelineWidgetEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SelineWidgetEntry>) -> Void) {
        var entries: [SelineWidgetEntry] = []
        let currentDate = Date()

        // Generate timeline for 5 hours
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SelineWidgetEntry(date: entryDate)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SelineWidgetEntryView: View {
    var entry: SelineWidgetProvider.Entry

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

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seline")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text("Placeholder Widget")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }

                Spacer()

                // Content Area
                VStack(alignment: .leading, spacing: 6) {
                    Text("Details coming soon")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Tap to customize widget content")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
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
        .cornerRadius(16)
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
