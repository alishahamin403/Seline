import SwiftUI

struct VisitStatsCard: View {
    let place: SavedPlace
    @Environment(\.colorScheme) var colorScheme

    @State private var stats: LocationVisitStats?
    @State private var isLoading = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color.white :
                            Color.black
                    )
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Visits")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading stats...")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    } else if let stats = stats {
                        Text(stats.summaryText)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(2)
                    } else {
                        Text("No visits tracked yet")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                }

                Spacer()
            }

            // Detailed Stats Grid
            if let stats = stats, stats.totalVisits > 0 {
                VStack(spacing: 12) {
                    // Row 1: Total Visits & Average Duration
                    HStack(spacing: 12) {
                        StatTile(
                            label: "Total Visits",
                            value: "\(stats.totalVisits)",
                            icon: "location.circle",
                            colorScheme: colorScheme
                        )

                        StatTile(
                            label: "Avg Duration",
                            value: stats.formattedAverageDuration,
                            icon: "clock",
                            colorScheme: colorScheme
                        )

                        StatTile(
                            label: "This Month",
                            value: "\(stats.thisMonthVisits)",
                            icon: "calendar",
                            colorScheme: colorScheme
                        )
                    }

                    // Row 2: Peak Time Info
                    if let peakTime = stats.mostCommonTimeOfDay,
                       let peakDay = stats.mostCommonDayOfWeek {
                        HStack(spacing: 0) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color.white :
                                        Color.black
                                )
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Peak Time")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                Text("\(peakDay) • \(peakTime)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            .padding(.leading, 8)

                            Spacer()

                            if let lastVisit = stats.lastVisitDate {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Last Visit")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Text(stats.formattedLastVisit)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                    }
                }
            }
        }

        .onAppear {
            loadStats()
            // Refresh stats every 10 seconds if there's an active visit
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
                loadStats()
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func loadStats() {
        Task {
            await LocationVisitAnalytics.shared.fetchStats(for: place.id)

            await MainActor.run {
                stats = LocationVisitAnalytics.shared.visitStats[place.id]
            }
        }
    }
}

// MARK: - Stat Tile Component

struct StatTile: View {
    let label: String
    let value: String
    let icon: String
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(
                    colorScheme == .dark ?
                        Color.white.opacity(0.7) :
                        Color.black.opacity(0.6)
                )

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        VisitStatsCard(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Test Location",
                address: "123 Main St",
                latitude: 37.7749,
                longitude: -122.4194
            )
        )
        .padding()
    }
    .background(Color.black)
}
