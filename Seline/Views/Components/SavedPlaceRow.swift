import SwiftUI

struct SavedPlaceRow: View {
    let place: SavedPlace
    let onTap: (SavedPlace) -> Void
    let onDelete: (SavedPlace) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            onTap(place)
        }) {
            HStack(spacing: 12) {
                // Location icon
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.518, green: 0.792, blue: 0.914) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
                    )

                // Place info
                VStack(alignment: .leading, spacing: 4) {
                    // Name and category
                    HStack(spacing: 6) {
                        Text(place.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)

                        Spacer()

                        // Category badge
                        Text(place.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(
                                colorScheme == .dark ?
                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40)
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color(red: 0.518, green: 0.792, blue: 0.914).opacity(0.2) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.1)
                                    )
                            )
                    }

                    // Address
                    Text(place.formattedAddress)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Rating if available
                    if let rating = place.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)

                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive, action: {
                onDelete(place)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        SavedPlaceRow(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Blue Bottle Coffee",
                address: "1355 Market St, San Francisco, CA 94103",
                latitude: 37.7749,
                longitude: -122.4194,
                phone: "(415) 555-1234",
                photos: [],
                rating: 4.5
            ),
            onTap: { _ in },
            onDelete: { _ in }
        )

        SavedPlaceRow(
            place: SavedPlace(
                googlePlaceId: "test2",
                name: "Whole Foods Market",
                address: "2001 Market St, San Francisco, CA 94114",
                latitude: 37.7749,
                longitude: -122.4194,
                photos: [],
                rating: 4.2
            ),
            onTap: { _ in },
            onDelete: { _ in }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}
