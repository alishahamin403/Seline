import SwiftUI

/// A view that displays either a location's photo or its initials
struct PlaceImageView: View {
    let place: SavedPlace
    let size: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme

    // Extract initials from place name (first letter of first two words)
    var initials: String {
        let words = place.displayName.split(separator: " ")
        if words.count >= 2 {
            let first = String(words[0].prefix(1))
            let second = String(words[1].prefix(1))
            return (first + second).uppercased()
        } else if let firstWord = words.first {
            return String(firstWord.prefix(2)).uppercased()
        }
        return "?"
    }

    // Get first photo URL if available
    var photoURL: String? {
        return place.photos.first
    }

    var body: some View {
        ZStack {
            // Prefer showing icon if user has selected one
            if let userIcon = place.userIcon {
                IconDisplayView(
                    icon: userIcon,
                    size: size,
                    cornerRadius: cornerRadius,
                    colorScheme: colorScheme
                )
            } else if let photoURLString = photoURL {
                // Show cached or downloaded photo using existing CachedAsyncImage
                CachedAsyncImage(url: photoURLString) { image in
                    // Successfully loaded image
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } placeholder: {
                    // Loading state - show initials as placeholder
                    InitialsView(
                        initials: initials,
                        size: size,
                        cornerRadius: cornerRadius,
                        colorScheme: colorScheme
                    )
                }
                .frame(width: size, height: size)
            } else {
                // No photo available - show initials
                InitialsView(
                    initials: initials,
                    size: size,
                    cornerRadius: cornerRadius,
                    colorScheme: colorScheme
                )
            }
        }
        .frame(width: size, height: size)
    }
}

/// A view that displays an icon with a subtle background
struct IconDisplayView: View {
    let icon: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme

    var iconSize: CGFloat {
        size * 0.5 // Icon size is 50% of the container size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    colorScheme == .dark ? Color.clear : Color.gray.opacity(0.15),
                    lineWidth: 1
                )
        )
    }
}

/// A view that displays initials with a solid black/white background
struct InitialsView: View {
    let initials: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme

    var fontSize: CGFloat {
        size * 0.4 // Font size is 40% of the container size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.25)
                )

            Text(initials)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Preview with photo
        PlaceImageView(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Pizza Pizza",
                address: "123 Main St",
                latitude: 43.6532,
                longitude: -79.3832,
                photos: ["https://picsum.photos/400"]
            ),
            size: 80,
            cornerRadius: 16
        )

        // Preview with initials (no photo)
        PlaceImageView(
            place: SavedPlace(
                googlePlaceId: "test2",
                name: "Tim Hortons",
                address: "456 Oak Ave",
                latitude: 43.6532,
                longitude: -79.3832,
                photos: []
            ),
            size: 80,
            cornerRadius: 16
        )

        // Preview with single word
        PlaceImageView(
            place: SavedPlace(
                googlePlaceId: "test3",
                name: "Starbucks",
                address: "789 Pine Rd",
                latitude: 43.6532,
                longitude: -79.3832,
                photos: []
            ),
            size: 80,
            cornerRadius: 16
        )
    }
    .padding()
    .background(Color.gmailDarkBackground)
}
