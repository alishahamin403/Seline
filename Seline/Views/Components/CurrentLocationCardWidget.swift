import SwiftUI

struct CurrentLocationCardWidget: View {
    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let elapsedTimeString: String
    let todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)]

    @Binding var selectedPlace: SavedPlace?
    @Binding var showingPlaceDetail: Bool
    @Binding var showAllLocationsSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current Location Section
            Button(action: {
                if let place = nearbyLocationPlace {
                    selectedPlace = place
                    showingPlaceDetail = true
                }
            }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentLocationName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)

                        // Status text - simplified
                        if let nearby = nearbyLocation {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text(elapsedTimeString.isEmpty ? "Just arrived" : elapsedTimeString)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            }
                        } else if let distance = distanceToNearest {
                            Text(String(format: "%.1f km away", distance / 1000))
                                .font(.system(size: 13))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        } else {
                            Text("No saved locations nearby")
                                .font(.system(size: 13))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Today's Visits Section - minimalist
            if !todaysVisits.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Spacer()

                        Button(action: {
                            showAllLocationsSheet = true
                        }) {
                            Text("See All")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        }
                    }

                    ForEach(todaysVisits, id: \.id) { visit in
                        HStack(spacing: 8) {
                            // Active indicator dot
                            Circle()
                                .fill(visit.isActive ? Color.green : (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)))
                                .frame(width: 6, height: 6)

                            Text(visit.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)

                            Spacer()

                            Text(formatDuration(visit.totalDurationMinutes))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(visit.isActive ? .green : (colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
        )
        .cornerRadius(16)
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
            radius: 12,
            x: 0,
            y: 2
        )
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}
