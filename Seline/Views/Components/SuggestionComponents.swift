import SwiftUI
import CoreLocation

// MARK: - Category Filter Slider

struct CategoryFilterSlider: View {
    @Binding var selectedCategory: String?
    let categories: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" option
                FilterPillButton(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    colorScheme: colorScheme
                ) {
                    selectedCategory = nil
                }

                // Individual categories
                ForEach(categories, id: \.self) { category in
                    FilterPillButton(
                        title: category,
                        isSelected: selectedCategory == category,
                        colorScheme: colorScheme
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Pill Button

struct FilterPillButton: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    isSelected ?
                        (colorScheme == .dark ? .white : .black) :
                        (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSelected ?
                                (colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                    Color.black.opacity(0.15)) :
                                Color.clear
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear :
                                (colorScheme == .dark ?
                                    Color.white.opacity(0.2) :
                                    Color.black.opacity(0.1)),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Nearby Place Mini Tile

struct NearbyPlaceMiniTile: View {
    let place: SavedPlace
    let currentLocation: CLLocation
    let colorScheme: ColorScheme
    let onTap: () -> Void

    // Get icon specific to the business/place name
    var placeIcon: String {
        let name = place.displayName.lowercased()

        // Specific business/brand icons
        // Pizza chains
        if name.contains("pizza pizza") { return "p.circle.fill" }
        if name.contains("domino") { return "d.circle.fill" }
        if name.contains("pizza hut") { return "h.circle.fill" }
        if name.contains("pizza") { return "pizzaslice.fill" }

        // Coffee shops
        if name.contains("starbucks") { return "s.circle.fill" }
        if name.contains("tim hortons") || name.contains("tim horton") { return "t.circle.fill" }
        if name.contains("second cup") { return "c.circle.fill" }
        if name.contains("coffee") || name.contains("cafe") || name.contains("café") { return "cup.and.saucer.fill" }

        // Fast food
        if name.contains("mcdonald") { return "m.circle.fill" }
        if name.contains("burger king") { return "b.circle.fill" }
        if name.contains("wendy") { return "w.circle.fill" }
        if name.contains("subway") { return "s.circle.fill" }
        if name.contains("kfc") { return "k.circle.fill" }
        if name.contains("burger") { return "takeoutbag.and.cup.and.straw.fill" }

        // Grocery/Retail
        if name.contains("walmart") { return "w.circle.fill" }
        if name.contains("costco") { return "c.circle.fill" }
        if name.contains("loblaws") { return "l.circle.fill" }
        if name.contains("whole foods") { return "leaf.circle.fill" }
        if name.contains("metro") { return "m.circle.fill" }
        if name.contains("shoppers") || name.contains("drug mart") { return "cross.circle.fill" }

        // Other food types
        if name.contains("sushi") { return "fish.fill" }
        if name.contains("chinese") || name.contains("asian") { return "takeoutbag.and.cup.and.straw.fill" }
        if name.contains("indian") { return "flame.fill" }
        if name.contains("mexican") || name.contains("taco") { return "taco.fill" }
        if name.contains("bakery") || name.contains("pastry") { return "birthday.cake.fill" }
        if name.contains("ice cream") || name.contains("gelato") { return "snowflake" }
        if name.contains("bar") || name.contains("pub") { return "wineglass.fill" }

        // Entertainment
        if name.contains("cinema") || name.contains("theater") || name.contains("movie") { return "film.fill" }
        if name.contains("museum") || name.contains("gallery") { return "building.columns.fill" }
        if name.contains("park") { return "leaf.fill" }
        if name.contains("beach") { return "beach.umbrella.fill" }

        // Health & Fitness
        if name.contains("gym") || name.contains("fitness") { return "figure.run" }
        if name.contains("hospital") || name.contains("clinic") { return "cross.case.fill" }
        if name.contains("pharmacy") { return "pills.fill" }

        // Transportation
        if name.contains("airport") { return "airplane" }
        if name.contains("hotel") || name.contains("inn") { return "bed.double.fill" }
        if name.contains("gas") || name.contains("fuel") || name.contains("petro") || name.contains("shell") || name.contains("esso") { return "fuelpump.fill" }
        if name.contains("parking") { return "parkingsign.circle.fill" }

        // Services
        if name.contains("bank") || name.contains("atm") { return "dollarsign.circle.fill" }
        if name.contains("library") { return "book.fill" }
        if name.contains("school") || name.contains("university") { return "graduationcap.fill" }

        // Fall back to category-based icon
        switch place.category.lowercased() {
        case "restaurants", "food":
            return "fork.knife"
        case "coffee shops", "cafe":
            return "cup.and.saucer.fill"
        case "shopping", "retail":
            return "bag.fill"
        case "entertainment":
            return "film.fill"
        case "health & fitness", "gym":
            return "figure.run"
        case "travel", "hotels":
            return "airplane"
        case "services":
            return "wrench.and.screwdriver.fill"
        default:
            return "mappin.circle.fill"
        }
    }

    var distanceText: String {
        let distance = LocationsManager.distance(from: place, to: currentLocation)
        return LocationsManager.formatDistance(distance)
    }

    // Get open/closed status - relies on Google Places API isOpenNow data
    var openStatusInfo: (isOpen: Bool?, timeInfo: String?) {
        // Only return isOpenNow if we have reliable data
        return (place.isOpenNow, nil)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Location photo or initials
                PlaceImageView(
                    place: place,
                    size: 56,
                    cornerRadius: 12
                )

                // Place name
                Text(place.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                // Distance
                Text(distanceText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                // Open/Closed status - only shown if we have reliable data
                if let isOpen = openStatusInfo.isOpen {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isOpen ? Color.green : Color.red)
                            .frame(width: 6, height: 6)

                        Text(isOpen ? "Open" : "Closed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isOpen ? Color.green.opacity(0.9) : .red.opacity(0.8))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 72, height: 110)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        colorScheme == .dark ?
                            Color.white.opacity(0.05) : Color.white
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ?
                            Color.white.opacity(0.1) : Color.black.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Suggestions Section Header

struct SuggestionsSectionHeader: View {
    @Binding var selectedTimeMinutes: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var showCustomTimes = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Nearby")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()
            }

            // Time selector
            VStack(spacing: 8) {
                // First row: Quick times + Custom button
                HStack(spacing: 8) {
                    ForEach([10, 20, 30], id: \.self) { time in
                        Button(action: {
                            selectedTimeMinutes = time
                        }) {
                            Text("\(time) min")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(
                                    selectedTimeMinutes == time ?
                                        (colorScheme == .dark ? .white : .black) :
                                        (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedTimeMinutes == time ?
                                                (colorScheme == .dark ?
                                                    Color.white.opacity(0.15) :
                                                    Color.black.opacity(0.15)) :
                                                Color.clear
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            selectedTimeMinutes == time ? Color.clear :
                                                (colorScheme == .dark ?
                                                    Color.white.opacity(0.2) :
                                                    Color.black.opacity(0.1)),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Custom time button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showCustomTimes.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Custom")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: showCustomTimes ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(
                            [40, 50, 60, 120].contains(selectedTimeMinutes) ?
                                (colorScheme == .dark ? .white : .black) :
                                (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    [40, 50, 60, 120].contains(selectedTimeMinutes) ?
                                        (colorScheme == .dark ?
                                            Color.white.opacity(0.15) :
                                            Color.black.opacity(0.15)) :
                                        Color.clear
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    [40, 50, 60, 120].contains(selectedTimeMinutes) ? Color.clear :
                                        (colorScheme == .dark ?
                                            Color.white.opacity(0.2) :
                                            Color.black.opacity(0.1)),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }

                // Second row: Custom time options (only shown when expanded)
                if showCustomTimes {
                    HStack(spacing: 8) {
                        ForEach([40, 50, 60, 120], id: \.self) { time in
                            Button(action: {
                                selectedTimeMinutes = time
                            }) {
                                Text(time == 120 ? "2 hrs" : "\(time) min")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(
                                        selectedTimeMinutes == time ?
                                            (colorScheme == .dark ? .white : .black) :
                                            (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(
                                                selectedTimeMinutes == time ?
                                                    (colorScheme == .dark ?
                                                        Color.white.opacity(0.15) :
                                                        Color.black.opacity(0.15)) :
                                                    Color.clear
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                selectedTimeMinutes == time ? Color.clear :
                                                    (colorScheme == .dark ?
                                                        Color.white.opacity(0.2) :
                                                        Color.black.opacity(0.1)),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Spacer()
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Filter Slider Preview
        CategoryFilterSlider(
            selectedCategory: .constant(nil),
            categories: ["Restaurants", "Coffee Shops", "Shopping"]
        )

        // Mini Tile Preview
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                NearbyPlaceMiniTile(
                    place: SavedPlace(
                        googlePlaceId: "test1",
                        name: "Blue Bottle Coffee",
                        address: "123 Main St",
                        latitude: 37.7749,
                        longitude: -122.4194
                    ),
                    currentLocation: CLLocation(latitude: 37.7749, longitude: -122.4194),
                    colorScheme: .dark,
                    onTap: {}
                )

                NearbyPlaceMiniTile(
                    place: SavedPlace(
                        googlePlaceId: "test2",
                        name: "Whole Foods Market",
                        address: "456 Oak Ave",
                        latitude: 37.7849,
                        longitude: -122.4294
                    ),
                    currentLocation: CLLocation(latitude: 37.7749, longitude: -122.4194),
                    colorScheme: .dark,
                    onTap: {}
                )
            }
            .padding(.horizontal, 20)
        }
    }
    .background(Color.gmailDarkBackground)
}
