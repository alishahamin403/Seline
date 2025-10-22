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
            if let photoURLString = photoURL {
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

/// A view that displays initials with a gradient background
struct InitialsView: View {
    let initials: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme

    // Generate a consistent color based on the initials
    var gradientColors: [Color] {
        let hash = abs(initials.hashValue)
        let hue = Double(hash % 360) / 360.0

        if colorScheme == .dark {
            return [
                Color(hue: hue, saturation: 0.6, brightness: 0.5),
                Color(hue: hue, saturation: 0.4, brightness: 0.3)
            ]
        } else {
            return [
                Color(hue: hue, saturation: 0.5, brightness: 0.9),
                Color(hue: hue, saturation: 0.3, brightness: 0.7)
            ]
        }
    }

    var fontSize: CGFloat {
        size * 0.4 // Font size is 40% of the container size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.white)
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
