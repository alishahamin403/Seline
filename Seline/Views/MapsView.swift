import SwiftUI

struct MapsView: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var openAIService = OpenAIService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedCategory: String? = nil
    @State private var selectedPlace: SavedPlace? = nil
    @State private var showingPlaceDetail = false
    @State private var showSearchModal = false

    var filteredPlaces: [SavedPlace] {
        return locationsManager.getPlaces(for: selectedCategory)
    }

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

                        // Saved places list
                        if filteredPlaces.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "map")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                Text("No saved places yet")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                                Text("Tap + to search and save places")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 60)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(filteredPlaces.enumerated()), id: \.element.id) { index, place in
                                    SavedPlaceRow(
                                        place: place,
                                        onTap: { place in
                                            selectedPlace = place
                                            showingPlaceDetail = true
                                        },
                                        onDelete: { place in
                                            locationsManager.deletePlace(place)
                                        }
                                    )

                                    if index < filteredPlaces.count - 1 {
                                        Rectangle()
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                            .frame(height: 1)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
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

                // Category filters
                if selectedCategory == nil && !locationsManager.categories.isEmpty {
                    CategoryFilterView(
                        selectedCategory: $selectedCategory,
                        categories: Array(locationsManager.categories)
                    )
                    .padding(.vertical, 8)
                    .background(
                        colorScheme == .dark ?
                            Color.gmailDarkBackground : Color.white
                    )
                }
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
        .sheet(isPresented: $showingPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(place: place) {
                    showingPlaceDetail = false
                }
            }
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
            content: "Search and save your favorite locations with AI-powered categorization.",
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

// MARK: - Place Search Result Row

struct PlaceSearchResultRow: View {
    let result: PlaceSearchResult
    let isSaved: Bool
    let onSave: () -> Void
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.518, green: 0.792, blue: 0.914) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Text(result.address)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                if !isSaved {
                    Button(action: {
                        onSave()
                    }) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(
                                colorScheme == .dark ?
                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40)
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(
                                        colorScheme == .dark ?
                                            Color(red: 0.518, green: 0.792, blue: 0.914).opacity(0.2) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.1)
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MapsView()
}
