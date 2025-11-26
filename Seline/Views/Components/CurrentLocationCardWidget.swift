import SwiftUI

struct CurrentLocationCardWidget: View {
    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let elapsedTimeString: String
    let topLocations: [(id: UUID, displayName: String, visitCount: Int)]

    @Binding var selectedPlace: SavedPlace?
    @Binding var showingPlaceDetail: Bool
    @Binding var showAllLocationsSheet: Bool

    var body: some View {
        Button(action: {
            if let place = nearbyLocationPlace {
                selectedPlace = place
                showingPlaceDetail = true
            }
        }) {
            HStack(spacing: 16) {
                // LEFT HALF - Current Location Info
                VStack(alignment: .leading, spacing: 8) {
                    // Location name
                    Text(currentLocationName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)

                    // Folder name as pill
                    if let folder = nearbyLocationFolder {
                        Text(folder)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                            )
                    }

                    // Status section
                    if let nearby = nearbyLocation {
                        Text("\(nearby) | \(elapsedTimeString)")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                            .lineLimit(2)
                    } else if let distance = distanceToNearest {
                        HStack(spacing: 4) {
                            Image(systemName: "location.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)

                            Text(String(format: "%.1f km away", distance / 1000))
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)

                            Text("No nearby locations")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // DIVIDER
                Divider()
                    .frame(height: 70)

                // RIGHT HALF - Top 3 Locations
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Top 3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Spacer()

                        if !topLocations.isEmpty {
                            Button(action: {
                                showAllLocationsSheet = true
                            }) {
                                Text("See All")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if topLocations.isEmpty {
                            Text("No visits yet")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        } else {
                            ForEach(topLocations.prefix(3), id: \.id) { location in
                                HStack(spacing: 8) {
                                    Text(location.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(location.visitCount)")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
