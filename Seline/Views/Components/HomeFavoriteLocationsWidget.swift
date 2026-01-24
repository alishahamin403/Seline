import SwiftUI

/// A widget displaying favorite saved locations on the home screen
struct HomeFavoriteLocationsWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var locationsManager = LocationsManager.shared
    
    var onLocationSelected: ((SavedPlace) -> Void)?
    
    private var favorites: [SavedPlace] {
        locationsManager.getFavourites()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Text("Favorites")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
            }
            
            // Locations slider
            if favorites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(FontManager.geist(size: 24, weight: .light))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    
                    Text("No favorites yet")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    
                    Text("Star locations to see them here")
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favorites) { place in
                            locationButton(place: place)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func locationButton(place: SavedPlace) -> some View {
        VStack(spacing: 6) {
            PlaceImageView(
                place: place,
                size: 54,
                cornerRadius: 12
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)

            Text(place.displayName)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(width: 54, height: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.cardTap()
            onLocationSelected?(place)
        }
        .contextMenu {
            Button(action: {
                locationsManager.toggleFavourite(for: place.id)
                HapticManager.shared.selection()
            }) {
                Label(
                    "Remove from Favorites",
                    systemImage: "star.slash"
                )
            }
        }
    }
}

#Preview {
    VStack {
        HomeFavoriteLocationsWidget()
        .padding(.horizontal, 12)
        Spacer()
    }
    .background(Color.shadcnBackground(.dark))
}

