import SwiftUI

struct StatsCard: View {
    let title: String
    let mainValue: Int
    let mainLabel: String
    let secondaryStats: [(value: Int, label: String, color: Color)]
    let showPercentage: Bool
    @Environment(\.colorScheme) var colorScheme

    private var totalForPercentage: Int {
        secondaryStats.reduce(0) { $0 + $1.value }
    }

    private var completionPercentage: Int {
        guard totalForPercentage > 0,
              let completedStat = secondaryStats.first else { return 0 }
        return Int((Double(completedStat.value) / Double(totalForPercentage)) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card title
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

            // Main metric
            VStack(alignment: .leading, spacing: 4) {
                Text("\(mainValue)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color.white :
                            Color.black
                    )

                Text(mainLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }

            // Completion percentage (if enabled)
            if showPercentage && totalForPercentage > 0 {
                HStack(spacing: 12) {
                    // Circular progress indicator
                    ZStack {
                        Circle()
                            .stroke(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.2) :
                                    Color.black.opacity(0.1),
                                lineWidth: 4
                            )
                            .frame(width: 44, height: 44)

                        Circle()
                            .trim(from: 0, to: CGFloat(completionPercentage) / 100.0)
                            .stroke(
                                colorScheme == .dark ?
                                    Color.white :
                                    Color.black,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))

                        Text("\(completionPercentage)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completion Rate")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                        Text("\(completionPercentage)% of events completed")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }

                    Spacer()
                }
            }

            // Secondary stats breakdown
            VStack(spacing: 10) {
                ForEach(Array(secondaryStats.enumerated()), id: \.offset) { index, stat in
                    HStack(spacing: 12) {
                        // Color indicator
                        Circle()
                            .fill(stat.color)
                            .frame(width: 8, height: 8)

                        Text(stat.label)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))

                        Spacer()

                        Text("\(stat.value)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    colorScheme == .dark ?
                        Color.white.opacity(0.1) :
                        Color.black.opacity(0.05),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 0 : 12,
            x: 0,
            y: colorScheme == .dark ? 0 : 4
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        StatsCard(
            title: "November 2024",
            mainValue: 42,
            mainLabel: "Total Events",
            secondaryStats: [
                (value: 35, label: "Completed", color: Color.white),
                (value: 7, label: "Incomplete", color: Color.gray.opacity(0.5))
            ],
            showPercentage: true
        )

        StatsCard(
            title: "Recurring Events",
            mainValue: 156,
            mainLabel: "Total Instances",
            secondaryStats: [
                (value: 142, label: "Completed", color: Color.white),
                (value: 14, label: "Missed", color: Color.red.opacity(0.7))
            ],
            showPercentage: true
        )
    }
    .padding()
    .background(Color.gmailDarkBackground)
}
