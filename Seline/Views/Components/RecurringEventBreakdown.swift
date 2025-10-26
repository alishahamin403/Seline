import SwiftUI

struct RecurringEventBreakdown: View {
    let recurringStats: [RecurringEventStat]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            ForEach(recurringStats) { stat in
                ShadcnAccordionItem(stat.eventName, subtitle: "\(stat.completionPercentage)% completed") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Frequency badge
                        HStack {
                            Text("Frequency")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            Spacer()

                            ShadcnBadge(stat.frequencyDisplayName, variant: .secondary)
                        }

                        // Completion stats
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Completion Rate")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                Spacer()

                                Text("\(stat.completedCount)/\(stat.expectedCount)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }

                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                        .frame(height: 8)

                                    // Foreground
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            stat.completionRate >= 0.8 ?
                                                Color.green.opacity(0.8) :
                                                stat.completionRate >= 0.5 ?
                                                    (colorScheme == .dark ?
                                                        Color.white :
                                                        Color.black) :
                                                    Color.red.opacity(0.8)
                                        )
                                        .frame(width: geometry.size.width * stat.completionRate, height: 8)
                                }
                            }
                            .frame(height: 8)
                        }

                        // Missed dates section
                        if !stat.missedDates.isEmpty {
                            Divider()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Missed Dates")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Spacer()

                                    ShadcnBadge("\(stat.missedCount)", variant: .destructive)
                                }

                                // List of missed dates
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(stat.missedDates.sorted(by: >).prefix(5), id: \.self) { date in
                                        HStack(spacing: 8) {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 4))
                                                .foregroundColor(Color.red.opacity(0.6))

                                            Text(formatMissedDate(date))
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
                                        }
                                    }

                                    if stat.missedDates.count > 5 {
                                        Text("+ \(stat.missedDates.count - 5) more")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                            .italic()
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatMissedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
