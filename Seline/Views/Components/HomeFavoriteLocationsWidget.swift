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
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
            }
            
            // Locations slider
            if favorites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    
                    Text("No favorites yet")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    
                    Text("Star locations to see them here")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(favorites) { place in
                            locationButton(place: place)
                        }
                    }
                    .padding(.horizontal, 4) // Subtle padding inside the slider
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func locationButton(place: SavedPlace) -> some View {
        VStack(spacing: 8) {
            PlaceImageView(
                place: place,
                size: 70,
                cornerRadius: 16
            )
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            Text(place.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(width: 70, height: 32)
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

