import SwiftUI

struct MapsView: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var openAIService = OpenAIService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedPlace: SavedPlace? = nil
    @State private var showingPlaceDetail = false
    @State private var isSearchExpanded = false
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var recentSearches: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var isLoadingPopular = false
    @State private var isLoadingRecent = false
    @FocusState private var isSearchFieldFocused: Bool

    var filteredPlaces: [SavedPlace] {
        let places = locationsManager.getPlaces(for: selectedCategory)

        if searchText.isEmpty {
            return places
        }

        return locationsManager.searchPlaces(query: searchText)
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
                            .frame(height: isSearchExpanded ? (searchText.isEmpty ? 60 : 280) : 120)

                        // Saved places list
                        if filteredPlaces.isEmpty && !isLoadingPopular {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "map")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                Text(searchText.isEmpty ? "No saved places yet" : "No places found")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                                if searchText.isEmpty {
                                    Text("Search for places and save them")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                }
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
                    if !isSearchExpanded {
                        // Search icon button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSearchExpanded = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isSearchFieldFocused = true
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.leading, 20)
                    } else {
                        // Expanded search bar
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            TextField("Search saved places or new locations...", text: $searchText)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .focused($isSearchFieldFocused)
                                .onChange(of: searchText) { newValue in
                                    if !newValue.isEmpty {
                                        performSearch(query: newValue)
                                    } else {
                                        // Show recent searches when field is empty
                                        searchResults = recentSearches
                                    }
                                }
                                .onChange(of: isSearchFieldFocused) { isFocused in
                                    if isFocused && searchText.isEmpty {
                                        loadRecentSearches()
                                    }
                                }

                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                    searchResults = []
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                }
                            }

                            Button(action: {
                                searchText = ""
                                searchResults = []
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSearchExpanded = false
                                }
                                isSearchFieldFocused = false
                            }) {
                                Text("Cancel")
                                    .font(.shadcnTextBase)
                                    .foregroundColor(Color.shadcnPrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                .fill(
                                    colorScheme == .dark ?
                                        Color.black.opacity(0.3) : Color.gray.opacity(0.1)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                        .stroke(
                                            colorScheme == .dark ?
                                                Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground : Color.white
                )

                // Category filters (only show when not searching)
                if !isSearchExpanded && !locationsManager.categories.isEmpty {
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

                // Search results or recent searches
                if isSearchExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // Show header for recent searches
                            if searchText.isEmpty && !recentSearches.isEmpty {
                                Text("Most Searched Places")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                            }

                            if isSearching || isLoadingRecent {
                                ProgressView()
                                    .padding(.vertical, 20)
                            } else if searchResults.isEmpty && !isLoadingRecent {
                                Text(searchText.isEmpty ? "No recent searches" : "No results found")
                                    .font(.shadcnTextSm)
                                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                    .padding(.vertical, 20)
                                    .frame(maxWidth: .infinity)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(searchResults) { result in
                                        PlaceSearchResultRow(
                                            result: result,
                                            isSaved: locationsManager.isPlaceSaved(googlePlaceId: result.id),
                                            onSave: {
                                                savePlace(result)
                                            },
                                            onTap: {
                                                mapsService.openInGoogleMaps(searchResult: result)
                                            }
                                        )

                                        if result.id != searchResults.last?.id {
                                            Rectangle()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                                .frame(height: 1)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(
                        colorScheme == .dark ?
                            Color.gmailDarkBackground : Color.white
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(
            // Floating action button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        loadPopularPlaces()
                    }) {
                        if isLoadingPopular {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(
                                            colorScheme == .dark ?
                                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                Color(red: 0.20, green: 0.34, blue: 0.40)
                                        )
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(
                                            colorScheme == .dark ?
                                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                Color(red: 0.20, green: 0.34, blue: 0.40)
                                        )
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 60)
                    .disabled(isLoadingPopular)
                }
            }
        )
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

    // MARK: - Actions

    private func performSearch(query: String) {
        isSearching = true

        Task {
            do {
                let results = try await mapsService.searchPlaces(query: query)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Search failed: \(error)")
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func savePlace(_ searchResult: PlaceSearchResult) {
        Task {
            do {
                // Get full place details
                let details = try await mapsService.getPlaceDetails(placeId: searchResult.id)

                // Create SavedPlace
                var place = details.toSavedPlace(googlePlaceId: searchResult.id)

                // Categorize with AI
                let category = try await openAIService.categorizeLocation(
                    name: place.name,
                    address: place.address,
                    types: details.types
                )

                place.category = category

                // Save to manager
                await MainActor.run {
                    locationsManager.addPlace(place)
                }

                print("✅ Place saved: \(place.name) - Category: \(category)")
            } catch {
                print("❌ Failed to save place: \(error)")
            }
        }
    }

    private func loadPopularPlaces() {
        isLoadingPopular = true

        Task {
            do {
                let popularPlaces = try await mapsService.getPopularPlaces()
                await MainActor.run {
                    searchResults = popularPlaces
                    isLoadingPopular = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to load popular places: \(error)")
                    isLoadingPopular = false
                }
            }
        }
    }

    private func loadRecentSearches() {
        // Only load if we don't have recent searches already
        guard recentSearches.isEmpty else {
            searchResults = recentSearches
            return
        }

        isLoadingRecent = true

        Task {
            do {
                let recent = try await mapsService.getMostSearchedPlaces()
                await MainActor.run {
                    recentSearches = recent
                    searchResults = recent
                    isLoadingRecent = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to load recent searches: \(error)")
                    recentSearches = []
                    searchResults = []
                    isLoadingRecent = false
                }
            }
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
