import SwiftUI

struct PlaceDetailSheet: View {
    let place: SavedPlace
    let onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var mapsService = GoogleMapsService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.5))
                }
                .padding(20)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Photos carousel
                    if !place.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(place.photos.indices, id: \.self) { index in
                                    AsyncImage(url: URL(string: place.photos[index])) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(width: 280, height: 200)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 280, height: 200)
                                                .clipped()
                                                .cornerRadius(12)
                                        case .failure:
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 280, height: 200)
                                                .overlay(
                                                    Image(systemName: "photo")
                                                        .font(.system(size: 40))
                                                        .foregroundColor(.gray)
                                                )
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Place name and category
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            HStack(spacing: 8) {
                                // Category badge
                                Text(place.category)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                colorScheme == .dark ?
                                                    Color.white.opacity(0.2) :
                                                    Color.black.opacity(0.1)
                                            )
                                    )

                                // Rating
                                if let rating = place.rating {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.yellow)

                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                    }
                                }
                            }
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                            .frame(height: 1)

                        // Address
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color.white :
                                        Color.black
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Address")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                Text(place.address)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }

                        // Phone number
                        if let phone = place.phone {
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                                .frame(height: 1)

                            Button(action: {
                                callPhone(phone)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(
                                            colorScheme == .dark ?
                                                Color.white :
                                                Color.black
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Phone")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                        Text(phone)
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                            .frame(height: 1)

                        // Visit Stats and History
                        VisitStatsCard(place: place)

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                            .frame(height: 1)

                        VisitHistoryCard(place: place)

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                            .frame(height: 1)

                        // Open in Maps button
                        Button(action: {
                            mapsService.openInGoogleMaps(place: place)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 18, weight: .semibold))

                                Text("Open in Maps")
                                    .font(.system(size: 16, weight: .semibold))

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 40)
                }
                .padding(.top, 20)
            }
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
        }
        .background(
            (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .ignoresSafeArea()
        )
    }

    private func callPhone(_ phone: String) {
        // Remove formatting from phone number
        let cleanedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        if let phoneURL = URL(string: "tel://\(cleanedPhone)"),
           UIApplication.shared.canOpenURL(phoneURL) {
            UIApplication.shared.open(phoneURL)
        }
    }
}

#Preview {
    PlaceDetailSheet(
        place: SavedPlace(
            googlePlaceId: "test1",
            name: "Blue Bottle Coffee",
            address: "1355 Market St, San Francisco, CA 94103",
            latitude: 37.7749,
            longitude: -122.4194,
            phone: "(415) 555-1234",
            photos: [
                "https://via.placeholder.com/280x200",
                "https://via.placeholder.com/280x200"
            ],
            rating: 4.5
        ),
        onDismiss: {}
    )
}
