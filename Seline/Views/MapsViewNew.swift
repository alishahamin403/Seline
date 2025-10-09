import SwiftUI

struct MapsViewNew: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer for fixed header
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: selectedCategory == nil ? 120 : 60)

                        if selectedCategory == nil {
                            // Categories Grid
                            if locationsManager.categories.isEmpty {
                                // Empty state
                                VStack(spacing: 16) {
                                    Image(systemName: "map")
                                        .font(.system(size: 48, weight: .light))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                    Text("No saved places yet")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                                    Text("Search for places and save them to categories")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 60)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(Array(locationsManager.categories), id: \.self) { category in
                                        CategoryCard(
                                            category: category,
                                            count: locationsManager.getPlaces(for: category).count,
                                            colorScheme: colorScheme
                                        ) {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                            }
                        } else {
                            // Saved places in selected category
                            let places = locationsManager.getPlaces(for: selectedCategory)

                            if places.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "mappin.slash")
                                        .font(.system(size: 48, weight: .light))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                    Text("No places in this category")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                }
                                .padding(.top, 60)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                                        SavedPlaceRow(
                                            place: place,
                                            onTap: { place in
                                                // Show place detail
                                                GoogleMapsService.shared.openInGoogleMaps(place: place)
                                            },
                                            onDelete: { place in
                                                locationsManager.deletePlace(place)
                                            }
                                        )

                                        if index < places.count - 1 {
                                            Rectangle()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                                .frame(height: 1)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        // Bottom spacing
                        Spacer()
                            .frame(height: 100)
                    }
                }
                .background(
                    (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                        .ignoresSafeArea()
                )
            }

            // Fixed header
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if selectedCategory == nil {
                        // Title when showing all categories
                        Text("Maps")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.leading, 20)
                    } else {
                        // Back button when in category
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedCategory = nil
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(selectedCategory!)
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.leading, 20)
                    }

                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground : Color.white
                )
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(
            // Floating + button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showSearchModal = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(
                                        colorScheme == .dark ?
                                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40)
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                }
            }
        )
        .sheet(isPresented: $showSearchModal) {
            LocationSearchModal()
        }
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .maps)
        }
    }

    // MARK: - Searchable Protocol

    func getSearchableContent() -> [SearchableItem] {
        var items: [SearchableItem] = []

        // Add main maps functionality
        items.append(SearchableItem(
            title: "Maps",
            content: "Search and save your favorite locations organized by categories.",
            type: .maps,
            identifier: "maps-main",
            metadata: ["category": "navigation"]
        ))

        // Add saved places as searchable content
        for place in locationsManager.savedPlaces {
            items.append(SearchableItem(
                title: place.name,
                content: "\(place.category): \(place.address)",
                type: .maps,
                identifier: "place-\(place.id)",
                metadata: [
                    "category": place.category,
                    "address": place.address,
                    "rating": place.rating != nil ? String(format: "%.1f", place.rating!) : "N/A"
                ]
            ))
        }

        return items
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: String
    let count: Int
    let colorScheme: ColorScheme
    let action: () -> Void

    var categoryIcon: String {
        switch category.lowercased() {
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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 24))
                        .foregroundColor(
                            colorScheme == .dark ?
                                Color(red: 0.518, green: 0.792, blue: 0.914) :
                                Color(red: 0.20, green: 0.34, blue: 0.40)
                        )

                    Spacer()

                    Text("\(count)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(category)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)

                    Text("\(count) place\(count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(16)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        colorScheme == .dark ?
                            Color.black.opacity(0.3) : Color.gray.opacity(0.1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
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

#Preview {
    MapsViewNew()
}
