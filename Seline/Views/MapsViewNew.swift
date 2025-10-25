import SwiftUI

struct MapsViewNew: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedCategory: String? = nil
    @State private var selectedSuggestionCategory: String? = nil
    @State private var showSearchModal = false
    @State private var selectedTimeMinutes: Int = 10 // Default to 10 mins
    @State private var nearbyPlaces: [SavedPlace] = []
    @State private var availableNearbyCategories: [String] = []
    @State private var isLoadingNearby = false
    @State private var selectedCountry: String? = nil
    @State private var selectedCity: String? = nil
    @Binding var externalSelectedFolder: String?

    init(externalSelectedFolder: Binding<String?> = .constant(nil)) {
        self._externalSelectedFolder = externalSelectedFolder
    }

    var body: some View {
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer for fixed header
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: selectedCategory == nil ? 20 : 60)

                        if selectedCategory == nil {
                            // Categories Grid
                            Group {
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
                                // Suggestions section - ALWAYS show this section
                                VStack(spacing: 8) {
                                    SuggestionsSectionHeader(selectedTimeMinutes: $selectedTimeMinutes)

                                    // Category filter slider - only show if categories are available
                                    if !availableNearbyCategories.isEmpty {
                                        CategoryFilterSlider(
                                            selectedCategory: $selectedSuggestionCategory,
                                            categories: availableNearbyCategories
                                        )
                                        .padding(.bottom, 4)
                                    }

                                    // Nearby places horizontal scroll or empty state
                                    if nearbyPlaces.isEmpty {
                                        // Empty state when no nearby places
                                        VStack(spacing: 12) {
                                            HStack {
                                                Image(systemName: "location.slash")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))

                                                Text("No places nearby within \(selectedTimeMinutes == 120 ? "2 hours" : "\(selectedTimeMinutes) minutes")")
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                                                Spacer()
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(
                                                        colorScheme == .dark ?
                                                            Color.white.opacity(0.03) : Color.gray.opacity(0.05)
                                                    )
                                            )
                                            .padding(.horizontal, 20)
                                        }
                                    } else {
                                        // Nearby places horizontal scroll
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(nearbyPlaces) { place in
                                                    if let currentLocation = locationService.currentLocation {
                                                        NearbyPlaceMiniTile(
                                                            place: place,
                                                            currentLocation: currentLocation,
                                                            colorScheme: colorScheme
                                                        ) {
                                                            GoogleMapsService.shared.openInGoogleMaps(place: place)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                                .padding(.bottom, 16)

                                // Folders section header
                                HStack {
                                    Text("Folders")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, nearbyPlaces.isEmpty ? 0 : 0)
                                .padding(.bottom, 12)

                                // Location filters section
                                LocationFiltersView(
                                    locationsManager: locationsManager,
                                    selectedCountry: $selectedCountry,
                                    selectedCity: $selectedCity,
                                    colorScheme: colorScheme
                                )

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(Array(locationsManager.getCategories(country: selectedCountry, city: selectedCity)), id: \.self) { category in
                                        CategoryCard(
                                            category: category,
                                            count: locationsManager.getPlaces(country: selectedCountry, city: selectedCity).filter { $0.category == category }.count,
                                            colorScheme: colorScheme
                                        ) {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            }
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }

                        // Bottom spacing
                        Spacer()
                            .frame(height: 100)
                    }
                }
                .background(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .ignoresSafeArea()
                )
            }
        }
        .overlay(
            // Floating + button (hide when folder is open)
            Group {
                if selectedCategory == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showSearchModal = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
        )
        .sheet(isPresented: $showSearchModal) {
            LocationSearchModal()
        }
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .maps)
            // Request location permission for nearby suggestions
            locationService.requestLocationPermission()
            // Load nearby places with ETA
            loadNearbyPlaces()
            // Refresh opening hours for places that don't have this data
            Task {
                await locationsManager.refreshOpeningHoursForAllPlaces()
                // Reload nearby places after refresh to show updated data
                loadNearbyPlaces()
            }
        }
        .onChange(of: selectedTimeMinutes) { _ in
            loadNearbyPlaces()
        }
        .onChange(of: selectedSuggestionCategory) { _ in
            loadNearbyPlaces()
        }
        .onChange(of: locationService.currentLocation) { _ in
            loadNearbyPlaces()
        }
        .onChange(of: externalSelectedFolder) { newFolder in
            if let folder = newFolder {
                withAnimation(.spring(response: 0.3)) {
                    selectedCategory = folder
                }
                // Clear the external binding after handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    externalSelectedFolder = nil
                }
            }
        }

        // iPhone-style folder overlay
        if selectedCategory != nil {
            let filteredPlaces = locationsManager.getPlaces(country: selectedCountry, city: selectedCity)
                .filter { $0.category == selectedCategory }
            FolderOverlayView(
                category: selectedCategory!,
                places: filteredPlaces,
                colorScheme: colorScheme,
                onClose: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedCategory = nil
                    }
                }
            )
            .zIndex(999)
            .transition(.opacity.combined(with: .scale(scale: 1.1)))
        }
    }

    // MARK: - Load Nearby Places with ETA

    private func loadNearbyPlaces() {
        guard let currentLocation = locationService.currentLocation else {
            nearbyPlaces = []
            availableNearbyCategories = []
            return
        }

        Task {
            isLoadingNearby = true

            // Get places filtered by ETA
            let places = await locationsManager.getNearbyPlacesByETA(
                from: currentLocation,
                maxTravelTimeMinutes: selectedTimeMinutes,
                category: selectedSuggestionCategory
            )

            await MainActor.run {
                nearbyPlaces = places

                // Update available categories
                let categories = Set(places.map { $0.category })
                availableNearbyCategories = Array(categories).sorted()

                isLoadingNearby = false
            }
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

    @StateObject private var locationsManager = LocationsManager.shared

    // Get icon for a specific place based on its name
    func iconForPlace(_ place: SavedPlace) -> String {
        let name = place.displayName.lowercased()

        // Food & Dining
        if name.contains("restaurant") || name.contains("dining") { return "fork.knife" }
        if name.contains("coffee") || name.contains("cafe") || name.contains("starbucks") { return "cup.and.saucer.fill" }
        if name.contains("pizza") { return "pizzaslice.fill" }
        if name.contains("burger") { return "takeoutbag.and.cup.and.straw.fill" }
        if name.contains("bar") || name.contains("pub") { return "wineglass.fill" }
        if name.contains("bakery") || name.contains("pastry") { return "birthday.cake.fill" }
        if name.contains("ice cream") || name.contains("gelato") { return "drop.fill" }

        // Shopping
        if name.contains("mall") || name.contains("shopping") { return "bag.fill" }
        if name.contains("store") || name.contains("shop") { return "cart.fill" }
        if name.contains("market") || name.contains("grocery") { return "basket.fill" }

        // Entertainment
        if name.contains("cinema") || name.contains("theater") || name.contains("movie") { return "film.fill" }
        if name.contains("museum") || name.contains("gallery") { return "building.columns.fill" }
        if name.contains("park") { return "leaf.fill" }
        if name.contains("beach") { return "beach.umbrella.fill" }

        // Health & Fitness
        if name.contains("gym") || name.contains("fitness") { return "figure.run" }
        if name.contains("hospital") || name.contains("clinic") { return "cross.case.fill" }
        if name.contains("pharmacy") || name.contains("drug") { return "pills.fill" }

        // Transportation & Travel
        if name.contains("airport") { return "airplane" }
        if name.contains("hotel") || name.contains("inn") { return "bed.double.fill" }
        if name.contains("gas") || name.contains("fuel") { return "fuelpump.fill" }
        if name.contains("parking") { return "parkingsign.circle.fill" }

        // Services
        if name.contains("bank") || name.contains("atm") { return "dollarsign.circle.fill" }
        if name.contains("library") { return "book.fill" }
        if name.contains("school") || name.contains("university") { return "graduationcap.fill" }

        // Default based on category
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

    // Get places for this category
    var places: [SavedPlace] {
        let allPlaces = locationsManager.getPlaces(for: category)
        return Array(allPlaces.prefix(4)) // Show up to 4 icons in a 2x2 grid
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // iPhone-style folder with location icons inside
                ZStack {
                    // Folder background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            colorScheme == .dark ?
                                Color.white.opacity(0.05) : Color.black.opacity(0.05)
                        )

                    // Grid of small location photos/initials (2x2)
                    if !places.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                                PlaceImageView(
                                    place: place,
                                    size: 32,
                                    cornerRadius: 8
                                )
                            }
                        }
                        .padding(16)
                    } else {
                        // Empty folder - show single large icon
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            colorScheme == .dark ?
                                Color.white.opacity(0.1) : Color.black.opacity(0.05),
                            lineWidth: 1
                        )
                )

                // Folder name below
                Text(category)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Folder Overlay View (iPhone-style)

struct FolderOverlayView: View {
    let category: String
    let places: [SavedPlace]
    let colorScheme: ColorScheme
    let onClose: () -> Void

    @StateObject private var locationsManager = LocationsManager.shared
    @State private var backgroundImage: UIImage? = nil
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirm = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var newPlaceName = ""

    // Get icon for a specific place based on its name
    func iconForPlace(_ place: SavedPlace) -> String {
        let name = place.displayName.lowercased()

        // Food & Dining
        if name.contains("restaurant") || name.contains("dining") { return "fork.knife" }
        if name.contains("coffee") || name.contains("cafe") || name.contains("starbucks") { return "cup.and.saucer.fill" }
        if name.contains("pizza") { return "pizzaslice.fill" }
        if name.contains("burger") { return "takeoutbag.and.cup.and.straw.fill" }
        if name.contains("bar") || name.contains("pub") { return "wineglass.fill" }
        if name.contains("bakery") || name.contains("pastry") { return "birthday.cake.fill" }
        if name.contains("ice cream") || name.contains("gelato") { return "drop.fill" }

        // Shopping
        if name.contains("mall") || name.contains("shopping") { return "bag.fill" }
        if name.contains("store") || name.contains("shop") { return "cart.fill" }
        if name.contains("market") || name.contains("grocery") { return "basket.fill" }

        // Entertainment
        if name.contains("cinema") || name.contains("theater") || name.contains("movie") { return "film.fill" }
        if name.contains("museum") || name.contains("gallery") { return "building.columns.fill" }
        if name.contains("park") { return "leaf.fill" }
        if name.contains("beach") { return "beach.umbrella.fill" }

        // Health & Fitness
        if name.contains("gym") || name.contains("fitness") { return "figure.run" }
        if name.contains("hospital") || name.contains("clinic") { return "cross.case.fill" }
        if name.contains("pharmacy") || name.contains("drug") { return "pills.fill" }

        // Transportation & Travel
        if name.contains("airport") { return "airplane" }
        if name.contains("hotel") || name.contains("inn") { return "bed.double.fill" }
        if name.contains("gas") || name.contains("fuel") { return "fuelpump.fill" }
        if name.contains("parking") { return "parkingsign.circle.fill" }

        // Services
        if name.contains("bank") || name.contains("atm") { return "dollarsign.circle.fill" }
        if name.contains("library") { return "book.fill" }
        if name.contains("school") || name.contains("university") { return "graduationcap.fill" }

        // Default based on category
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

    // Capture screenshot of current view
    func captureScreen() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    var body: some View {
        ZStack {
            // Background image (captured screenshot)
            if let bgImage = backgroundImage {
                Image(uiImage: bgImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            // Dimmed overlay
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Centered content - use frame with alignment
            VStack(spacing: 40) {
                // Folder title
                Text(category)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(.white)

                // Large rounded container with apps
                VStack(spacing: 0) {
                    if places.isEmpty {
                        // Empty state
                        VStack(spacing: 20) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.white.opacity(0.5))

                            Text("No places in this folder")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(height: 400)
                    } else {
                        // Grid of location images/initials
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 32) {
                                ForEach(places) { place in
                                    Button(action: {
                                        HapticManager.shared.selection()
                                        GoogleMapsService.shared.openInGoogleMaps(place: place)
                                        onClose()
                                    }) {
                                        VStack(spacing: 6) {
                                            // Location photo or initials
                                            PlaceImageView(
                                                place: place,
                                                size: 80,
                                                cornerRadius: 18
                                            )
                                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                                            // Place name
                                            Text(place.displayName)
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .minimumScaleFactor(0.8)
                                                .frame(height: 28)

                                            // Open/Closed status
                                            FolderPlaceStatusView(place: place)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        Button(action: {
                                            selectedPlace = place
                                            newPlaceName = place.customName ?? place.name
                                            showingRenameAlert = true
                                        }) {
                                            Label("Rename", systemImage: "pencil")
                                        }

                                        Button(role: .destructive, action: {
                                            selectedPlace = place
                                            showingDeleteConfirm = true
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 32)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 500)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color.black.opacity(0.5))
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(.ultraThinMaterial)
                        )
                )
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .onAppear {
            // Capture screenshot when view appears
            backgroundImage = captureScreen()
        }
        .alert("Rename Place", isPresented: $showingRenameAlert) {
            TextField("Place name", text: $newPlaceName)
            Button("Cancel", role: .cancel) {
                selectedPlace = nil
                newPlaceName = ""
            }
            Button("Rename") {
                if let place = selectedPlace {
                    var updatedPlace = place
                    updatedPlace.customName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    locationsManager.updatePlace(updatedPlace)
                    selectedPlace = nil
                    newPlaceName = ""
                }
            }
        } message: {
            Text("Enter a new name for this place")
        }
        .confirmationDialog("Delete Place", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let place = selectedPlace {
                    locationsManager.deletePlace(place)
                    selectedPlace = nil
                }
            }
            Button("Cancel", role: .cancel) {
                selectedPlace = nil
            }
        } message: {
            if let place = selectedPlace {
                Text("Are you sure you want to delete '\(place.displayName)'?")
            }
        }
    }
}

// MARK: - Folder Place Status View

struct FolderPlaceStatusView: View {
    let place: SavedPlace

    // Get open/closed status - relies on Google Places API isOpenNow data
    var openStatusInfo: (isOpen: Bool?, timeInfo: String?) {
        // Only return isOpenNow if we have reliable data
        return (place.isOpenNow, nil)
    }

    var body: some View {
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
}

// MARK: - Location Filters View

struct LocationFiltersView: View {
    @ObservedObject var locationsManager: LocationsManager
    @Binding var selectedCountry: String?
    @Binding var selectedCity: String?
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 12) {
            // Country filter
            if !locationsManager.countries.isEmpty {
                CountryFilterView(
                    locationsManager: locationsManager,
                    selectedCountry: $selectedCountry,
                    selectedCity: $selectedCity,
                    colorScheme: colorScheme
                )
            }

            // City filter
            if let country = selectedCountry, !locationsManager.getCities(in: country).isEmpty {
                CityFilterView(
                    locationsManager: locationsManager,
                    country: country,
                    selectedCity: $selectedCity,
                    colorScheme: colorScheme
                )
            }
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Country Filter View

struct CountryFilterView: View {
    @ObservedObject var locationsManager: LocationsManager
    @Binding var selectedCountry: String?
    @Binding var selectedCity: String?
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterButtonView(
                    title: "All",
                    isSelected: selectedCountry == nil,
                    colorScheme: colorScheme,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCountry = nil
                            selectedCity = nil
                        }
                    }
                )

                ForEach(Array(locationsManager.countries).sorted(), id: \.self) { country in
                    FilterButtonView(
                        title: country,
                        isSelected: selectedCountry == country,
                        colorScheme: colorScheme,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCountry = country
                                selectedCity = nil
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - City Filter View

struct CityFilterView: View {
    @ObservedObject var locationsManager: LocationsManager
    let country: String
    @Binding var selectedCity: String?
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterButtonView(
                    title: "All",
                    isSelected: selectedCity == nil,
                    colorScheme: colorScheme,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCity = nil
                        }
                    }
                )

                ForEach(Array(locationsManager.getCities(in: country)).sorted(), id: \.self) { city in
                    FilterButtonView(
                        title: city,
                        isSelected: selectedCity == city,
                        colorScheme: colorScheme,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCity = city
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Button View

struct FilterButtonView: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ?
                            Color(red: 0.2, green: 0.2, blue: 0.2) :
                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.2))
                        )
                )
        }
    }
}

#Preview {
    MapsViewNew()
}
