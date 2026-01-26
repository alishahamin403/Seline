import SwiftUI
import CoreLocation
import MapKit

struct MapsViewNew: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var peopleManager = PeopleManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Namespace private var tabAnimation

    @State private var selectedTab: String = "folders" // "folders", "people", or "timeline"
    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var selectedPlaceForRating: SavedPlace? = nil
    @State private var showRatingEditor = false
    @State private var locationSearchText: String = ""
    @State private var isLocationSearchActive: Bool = false
    @State private var currentLocationName: String = "Finding location..."
    @State private var nearbyLocation: String? = nil
    @State private var nearbyLocationFolder: String? = nil
    @State private var nearbyLocationPlace: SavedPlace? = nil
    @State private var distanceToNearest: Double? = nil
    @State private var elapsedTimeString: String = ""
    @State private var updateTimer: Timer?
    @State private var lastLocationCheckCoordinate: CLLocationCoordinate2D?
    @State private var hasLoadedIncompleteVisits = false  // Prevents race condition on app launch
    @StateObject private var geofenceManager = GeofenceManager.shared
    @Binding var externalSelectedFolder: String?
    @State private var topLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var showAllLocationsSheet = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast  // Time debounce for location updates
    @State private var recentlyVisitedPlaces: [SavedPlace] = []
    @State private var expandedCategories: Set<String> = []  // Track which categories are expanded
    @State private var selectedCuisines: Set<String> = []  // Track selected cuisine filters
    @State private var showFullMapView = false  // Controls full map view sheet
    @State private var showChangeFolderSheet = false  // Controls change folder sheet
    @State private var placeToMove: SavedPlace? = nil  // Place being moved to different folder
    @State private var showingRenameAlert = false  // Controls rename alert
    @State private var placeToRename: SavedPlace? = nil  // Place being renamed
    @State private var newPlaceName = ""  // New name for the place
    @FocusState private var isSearchFocused: Bool  // For search bar focus

    init(externalSelectedFolder: Binding<String?> = .constant(nil)) {
        self._externalSelectedFolder = externalSelectedFolder
    }

    var body: some View {
        mainContentView
            .sheet(isPresented: $showSearchModal) {
                LocationSearchModal()
                    .presentationBg()
            }
            .sheet(item: $selectedPlace) { place in
                PlaceDetailSheet(place: place, onDismiss: { 
                    selectedPlace = nil
                }, isFromRanking: false)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBg()
            }
            .sheet(isPresented: $showRatingEditor) {
                if let place = selectedPlaceForRating {
                    RatingEditorSheet(
                        place: place,
                        colorScheme: colorScheme,
                        onSave: { rating, notes, cuisine in
                            locationsManager.updateRestaurantRating(place.id, rating: rating, notes: notes, cuisine: cuisine)
                            showRatingEditor = false
                            selectedPlaceForRating = nil
                        },
                        onDismiss: {
                            showRatingEditor = false
                            selectedPlaceForRating = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBg()
                }
            }
            .sheet(isPresented: $showAllLocationsSheet) {
                AllVisitsSheet(
                    allLocations: $allLocations,
                    isPresented: $showAllLocationsSheet,
                    onLocationTap: { locationId in
                        if let place = locationsManager.savedPlaces.first(where: { $0.id == locationId }) {
                            selectedPlace = place
                        }
                    },
                    savedPlaces: locationsManager.savedPlaces
                )
                .presentationBg()
            }
            .sheet(isPresented: $showFullMapView) {
                FullMapView(
                    places: getFilteredPlaces(),
                    currentLocation: locationService.currentLocation,
                    colorScheme: colorScheme,
                    onPlaceTap: { place in
                        showFullMapView = false
                        selectedPlace = place
                    }
                )
                .presentationBg()
            }
            .sheet(isPresented: $showChangeFolderSheet) {
                if let place = placeToMove {
                    ChangeFolderSheet(
                        place: place,
                        currentCategory: place.category,
                        allCategories: getAllCategories(),
                        colorScheme: colorScheme,
                        onFolderSelected: { newCategory in
                            var updatedPlace = place
                            updatedPlace.category = newCategory
                            locationsManager.updatePlace(updatedPlace)
                            showChangeFolderSheet = false
                            placeToMove = nil
                            HapticManager.shared.success()
                        },
                        onDismiss: {
                            showChangeFolderSheet = false
                            placeToMove = nil
                        }
                    )
                    .presentationBg()
                }
            }
            .alert("Rename Place", isPresented: $showingRenameAlert) {
                TextField("Place name", text: $newPlaceName)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                    newPlaceName = ""
                }
                Button("Rename") {
                    if let place = placeToRename {
                        var updatedPlace = place
                        updatedPlace.customName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        locationsManager.updatePlace(updatedPlace)
                        placeToRename = nil
                        newPlaceName = ""
                    }
                }
            } message: {
                Text("Enter a new name for this place")
            }
            .task {
                // Use .task for async setup - only runs once per view lifecycle
                await setupOnAppear()
            }
            .onReceive(locationService.$currentLocation) { _ in
                handleLocationUpdate()
            }
            .onChange(of: externalSelectedFolder) { newFolder in
                handleExternalFolderSelection(newFolder)
            }
            .onChange(of: scenePhase) { newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: locationsManager.savedPlaces) { _ in
                // Only reload if we have no data yet, or debounce to avoid excessive reloads
                if topLocations.isEmpty {
                    loadTopLocations()
                } else {
                    // Debounce: reload after a short delay to batch multiple changes
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        loadTopLocations()
                    }
                }
            }
            .onChange(of: colorScheme) { _ in
                // Force view refresh when system theme changes
            }
            .id(colorScheme)
            .onDisappear {
                stopLocationTimer()
            }
            .overlay(folderOverlay)
    }
    
    // MARK: - Main Content View
    
    private var mainContentView: some View {
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                headerSection
                mainScrollContent
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Tab bar with search bar
            HStack(spacing: 12) {
                // Empty spacer for balance
                Color.clear.frame(width: 44, height: 44)
                
                Spacer()
                tabBarView
                Spacer()
                
                // Search icon on the right
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLocationSearchActive = true
                        isSearchFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(
                colorScheme == .dark ? Color.black : Color.white
            )
            
            // Search bar (appears when active)
            if isLocationSearchActive {
                locationSearchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .background(
                        colorScheme == .dark ? Color.black : Color.white
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var locationSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(.gray)

            TextField("Search locations", text: $locationSearchText)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .focused($isSearchFocused)
                .submitLabel(.search)

            // Clear button
            if !locationSearchText.isEmpty {
                Button(action: {
                    locationSearchText = ""
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Close button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    locationSearchText = ""
                    isLocationSearchActive = false
                    isSearchFocused = false
                }
            }) {
                Text("Cancel")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
        )
    }
    
    // MARK: - Tab Bar View
    
    private var tabBarView: some View {
        HStack(spacing: 4) {
            ForEach(["folders", "people", "timeline"], id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(tabContainerColor())
        )
    }
    
    // MARK: - Tab Button
    
    private func tabButton(for tab: String) -> some View {
        let isSelected = selectedTab == tab
        let tabIcon = getTabIcon(for: tab)
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            Image(systemName: tabIcon)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(tabForegroundColor(isSelected: isSelected))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(tabBackgroundColor())
                            .matchedGeometryEffect(id: "tab", in: tabAnimation)
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Icon Helper
    
    private func getTabIcon(for tab: String) -> String {
        if tab == "folders" {
            return "folder.fill"
        } else if tab == "people" {
            return "person.2.fill"
        } else {
            return "clock.fill"
        }
    }
    
    // MARK: - Main Scroll Content
    
    private var mainScrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if selectedTab == "folders" {
                    locationsTabContent
                } else if selectedTab == "people" {
                    peopleTabContent
                } else {
                    timelineTabContent
                }
            }
        }
        .background(
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Floating Add Button
    
    private var floatingAddButton: some View {
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
                                .font(FontManager.geist(size: 20, weight: .semibold))
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
    }
    
    // MARK: - Folder Overlay
    
    @ViewBuilder
    private var folderOverlay: some View {
        if let category = selectedCategory {
            let filteredPlaces = getFilteredPlaces().filter { $0.category == category }
            FolderOverlayView(
                category: category,
                places: filteredPlaces,
                colorScheme: colorScheme,
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                }
            )
            .zIndex(999)
            .transition(.opacity)
        }
    }
    
    // MARK: - Helper Functions
    
    private func getAllCategories() -> [String] {
        let categorySet = Set(locationsManager.savedPlaces.map { $0.category })
        return Array(categorySet).sorted()
    }
    
    private func setupOnAppear() async {
        SearchService.shared.registerSearchableProvider(self, for: .maps)

        // CLEANUP: Auto-close any incomplete visits older than 3 hours in Supabase (background)
        Task.detached(priority: .utility) {
            await geofenceManager.cleanupIncompleteVisitsInSupabase(olderThanMinutes: 180)
        }

        // Load incomplete visits from Supabase to resume tracking BEFORE checking location
        await geofenceManager.loadIncompleteVisitsFromSupabase()
        await MainActor.run {
            updateCurrentLocation()
            hasLoadedIncompleteVisits = true
        }

        // OPTIMIZATION: Load data in background (non-blocking) so UI appears immediately
        // Only load if data is empty or stale
        if topLocations.isEmpty {
            loadTopLocations()
        }
        if recentlyVisitedPlaces.isEmpty {
            loadRecentlyVisited()
        }
        
        locationService.requestLocationPermission()
    }
    
    private func handleLocationUpdate() {
        if hasLoadedIncompleteVisits {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime)
            if timeSinceLastUpdate >= 2.0 {
                lastLocationUpdateTime = Date()
                updateCurrentLocation()
            }
        }
    }
    
    private func handleExternalFolderSelection(_ newFolder: String?) {
        if let folder = newFolder {
            withAnimation(.spring(response: 0.3)) {
                selectedCategory = folder
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                externalSelectedFolder = nil
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            updateCurrentLocation()
            if nearbyLocation != nil {
                startLocationTimer()
            }
            if let currentLoc = locationService.currentLocation {
                Task {
                    await geofenceManager.autoCompleteVisitsIfOutOfRange(
                        currentLocation: currentLoc,
                        savedPlaces: locationsManager.savedPlaces
                    )
                }
            }
        } else {
            stopLocationTimer()
        }
    }

    @ViewBuilder
    private var locationsTabContent: some View {
        VStack(spacing: 0) {
            // Header with "Saved Locations" title and Add button
            HStack(spacing: 12) {
                Text("Saved Locations")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()

                // Add button in top right
                Button(action: {
                    showSearchModal = true
                }) {
                    Text("Add")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if locationsManager.categories.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "map").font(FontManager.geist(size: 48, weight: .light)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    Text("No saved places yet").font(FontManager.geist(size: 18, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    Text("Search for places and save them to categories").font(FontManager.geist(size: 14, weight: .regular)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)).multilineTextAlignment(.center)
                }.padding(.top, 60)
            } else if selectedCategory == nil {
                VStack(spacing: 16) {
                    miniMapSection
                    favoritesSection
                    expandableCategoriesSection
                }
            }

            Spacer().frame(height: 100)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let allFavourites = locationsManager.getFavourites()
        let favourites: [SavedPlace] = {
            if locationSearchText.isEmpty {
                return allFavourites
            } else {
                let searchLower = locationSearchText.lowercased()
                return allFavourites.filter { place in
                    let countryMatch = place.country?.lowercased().contains(searchLower) ?? false
                    let provinceMatch = place.province?.lowercased().contains(searchLower) ?? false
                    let cityMatch = place.city?.lowercased().contains(searchLower) ?? false
                    let addressMatch = place.address.lowercased().contains(searchLower)
                    let nameMatch = place.displayName.lowercased().contains(searchLower)
                    return countryMatch || provinceMatch || cityMatch || addressMatch || nameMatch
                }
            }
        }()
        
        if !favourites.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Favorites")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favourites, id: \.id) { place in
                            Button(action: {
                                selectedPlace = place
                            }) {
                                VStack(spacing: 6) {
                                    PlaceImageView(place: place, size: 54, cornerRadius: 12)

                                    Text(place.displayName)
                                        .font(FontManager.geist(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54, height: 28)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button(action: {
                                    placeToRename = place
                                    newPlaceName = place.customName ?? place.name
                                    showingRenameAlert = true
                                }) {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive, action: { locationsManager.deletePlace(place) }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        colorScheme == .dark 
                            ? Color.white.opacity(0.08)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 20,
                x: 0,
                y: 4
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        }
    }

    @ViewBuilder
    private var miniMapSection: some View {
        VStack(spacing: 0) {
            MiniMapView(
                places: getFilteredPlaces(),
                currentLocation: locationService.currentLocation,
                colorScheme: colorScheme,
                onPlaceTap: { place in
                    selectedPlace = place
                },
                onExpandTap: {
                    showFullMapView = true
                }
            )
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var recentlyVisitedSection: some View {
        if !recentlyVisitedPlaces.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Recently Visited")
                        .font(FontManager.geist(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentlyVisitedPlaces, id: \.id) { place in
                            Button(action: {
                                selectedPlace = place
                            }) {
                                VStack(spacing: 6) {
                                    PlaceImageView(place: place, size: 54, cornerRadius: 12)

                                    Text(place.displayName)
                                        .font(FontManager.geist(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54, height: 28)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        colorScheme == .dark 
                            ? Color.white.opacity(0.08)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 20,
                x: 0,
                y: 4
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        }
    }

    @ViewBuilder
    private var expandableCategoriesSection: some View {
        VStack(spacing: 24) {
            ForEach(LocationSuperCategory.allCases, id: \.self) { superCategory in
                let groupedPlaces = getFilteredPlaces(for: superCategory)

                if !groupedPlaces.isEmpty {
                    // Add cuisine filter for Food & Dining
                    if superCategory == .foodAndDining {
                        CuisineFilterView(
                            selectedCuisines: $selectedCuisines,
                            colorScheme: colorScheme
                        )
                    }

                    SuperCategorySection(
                        superCategory: superCategory,
                        groupedPlaces: groupedPlaces,
                        expandedCategories: $expandedCategories,
                        colorScheme: colorScheme,
                        currentLocation: locationService.currentLocation,
                        onPlaceTap: { place in
                            selectedPlace = place
                        },
                        onRatingTap: { place in
                            selectedPlaceForRating = place
                            showRatingEditor = true
                        },
                        onMoveToFolder: { place in
                            placeToMove = place
                            showChangeFolderSheet = true
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var peopleTabContent: some View {
        PeopleListView(
            peopleManager: peopleManager,
            locationsManager: locationsManager,
            colorScheme: colorScheme,
            searchText: locationSearchText
        )
    }

    @ViewBuilder
    private var timelineTabContent: some View {
        LocationTimelineView(colorScheme: colorScheme)
    }

    // MARK: - Current Location Tracking

    private func updateCurrentLocation() {
        // Get current location from LocationService
        if let currentLoc = locationService.currentLocation {
            // OPTIMIZATION: Debounce location updates - only process if moved 50m+
            let debounceThreshold: CLLocationDistance = 50.0 // 50 meters
            if let lastCheck = lastLocationCheckCoordinate {
                let lastLocation = CLLocation(latitude: lastCheck.latitude, longitude: lastCheck.longitude)
                let currentLocObj = CLLocation(latitude: currentLoc.coordinate.latitude, longitude: currentLoc.coordinate.longitude)
                let distanceMoved = currentLocObj.distance(from: lastLocation)

                // If moved less than 50m, skip expensive calculations
                if distanceMoved < debounceThreshold {
                    return
                }
            }

            // Update last check coordinate
            lastLocationCheckCoordinate = currentLoc.coordinate

            // Get current address/location name
            currentLocationName = locationService.locationName

            // Check if user is in any geofence (within 200m to match GeofenceManager)
            let geofenceRadius = 200.0
            var foundNearby = false

            for place in locationsManager.savedPlaces {
                let placeLocation = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLoc.distance(from: CLLocation(latitude: placeLocation.latitude, longitude: placeLocation.longitude))

                if distance <= geofenceRadius {
                    // Check if we just entered a new location
                    if nearbyLocation != place.displayName {
                        nearbyLocation = place.displayName
                        nearbyLocationFolder = place.category
                        nearbyLocationPlace = place
                        startLocationTimer()
                        print("✅ Entered geofence: \(place.displayName) (Folder: \(place.category))")
                    }

                    // If already in geofence but no active visit record, create one
                    // (handles case where user was already at location when app launched)
                    if geofenceManager.activeVisits[place.id] == nil {
                        // IMPORTANT: Only create if we have a valid user ID
                        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
                            print("⚠️ Cannot auto-create visit - user not authenticated")
                            return
                        }

                        var visit = LocationVisitRecord.create(
                            userId: userId,
                            savedPlaceId: place.id,
                            entryTime: Date()
                        )
                        geofenceManager.activeVisits[place.id] = visit
                        print("📝 Auto-created visit for already-present location: \(place.displayName)")
                        print("📍 Visit details - ID: \(visit.id.uuidString), UserID: \(visit.userId.uuidString), PlaceID: \(visit.savedPlaceId.uuidString)")

                        // Save to Supabase immediately
                        Task {
                            print("🔄 Starting Supabase save task for \(place.displayName)")
                            await geofenceManager.saveVisitToSupabase(visit)
                            print("✅ Completed Supabase save task")
                        }
                    }

                    distanceToNearest = nil
                    foundNearby = true
                    break
                }
            }

            // If not in any geofence, find nearest location
            if !foundNearby {
                var nearestDistance: Double = Double.infinity
                for place in locationsManager.savedPlaces {
                    let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                    let distance = currentLoc.distance(from: placeLocation)
                    if distance < nearestDistance {
                        nearestDistance = distance
                    }
                }

                nearbyLocation = nil
                nearbyLocationFolder = nil
                nearbyLocationPlace = nil
                if nearestDistance < Double.infinity {
                    distanceToNearest = nearestDistance
                } else {
                    distanceToNearest = nil
                }

                // Clear elapsed time when not in any geofence
                elapsedTimeString = ""
                stopLocationTimer()

                // Auto-complete any active visits if user has moved outside geofences
                Task {
                    await geofenceManager.autoCompleteVisitsIfOutOfRange(
                        currentLocation: currentLoc,
                        savedPlaces: locationsManager.savedPlaces
                    )
                }
            }
        } else {
            currentLocationName = "Location not available"
            nearbyLocation = nil
            nearbyLocationFolder = nil
            nearbyLocationPlace = nil
            distanceToNearest = nil
            elapsedTimeString = ""
            stopLocationTimer()
        }
    }

    private func loadTopLocations() {
        Task {
            // OPTIMIZATION: Check cache first to avoid expensive Supabase queries
            typealias LocationTuple = (id: UUID, displayName: String, visitCount: Int)
            
            // Try to load from cache (use codable wrapper for caching)
            if let cached: [[String: Any]] = CacheManager.shared.get(forKey: CacheManager.CacheKey.topLocations) {
                // Convert cached data back to tuple array
                var cachedLocations: [LocationTuple] = []
                var cachedAllLocations: [LocationTuple] = []
                
                for item in cached {
                    if let idString = item["id"] as? String, 
                       let id = UUID(uuidString: idString),
                       let displayName = item["displayName"] as? String,
                       let visitCount = item["visitCount"] as? Int {
                        cachedAllLocations.append((id: id, displayName: displayName, visitCount: visitCount))
                    }
                }
                
                if !cachedAllLocations.isEmpty {
                    cachedLocations = Array(cachedAllLocations.prefix(3))
                    await MainActor.run {
                        topLocations = cachedLocations
                        allLocations = cachedAllLocations
                    }
                    return // Use cached data
                }
            }
            
            // OPTIMIZATION: Fetch stats in parallel for all places (much faster!)
            let places = locationsManager.savedPlaces
            var placesWithCounts: [LocationTuple] = []
            
            await withTaskGroup(of: (UUID, String, Int?).self) { group in
                for place in places {
                    group.addTask {
                        // Fetch stats for this place
                        await LocationVisitAnalytics.shared.fetchStats(for: place.id)
                        
                        // Access visitStats on MainActor since it's main actor-isolated
                        let stats = await MainActor.run {
                            LocationVisitAnalytics.shared.visitStats[place.id]
                        }
                        
                        if let stats = stats {
                            return (place.id, place.displayName, stats.totalVisits)
                        } else {
                            return (place.id, place.displayName, nil)
                        }
                    }
                }
                
                for await (id, displayName, visitCount) in group {
                    if let visitCount = visitCount {
                        placesWithCounts.append((id: id, displayName: displayName, visitCount: visitCount))
                    }
                }
            }

            // Sort by visit count (descending)
            let allSorted = placesWithCounts.sorted { $0.visitCount > $1.visitCount }

            // Top 3 for the card
            let top3 = allSorted.prefix(3).map { $0 }

            await MainActor.run {
                topLocations = top3
                allLocations = allSorted  // Store all locations for "See All" feature
                
                // OPTIMIZATION: Cache the results for 5 minutes
                // Convert to dictionary array for caching (tuples aren't Codable)
                let cacheData: [[String: Any]] = allSorted.map { item in
                    return [
                        "id": item.id.uuidString,
                        "displayName": item.displayName,
                        "visitCount": item.visitCount
                    ]
                }
                CacheManager.shared.set(cacheData, forKey: CacheManager.CacheKey.topLocations, ttl: CacheManager.TTL.medium)
            }
        }
    }

    private func loadRecentlyVisited() {
        Task {
            // OPTIMIZATION: Check cache first to avoid expensive Supabase queries
            if let cachedIds: [String] = CacheManager.shared.get(forKey: CacheManager.CacheKey.recentlyVisitedPlaces) {
                // Rebuild places from cached IDs
                var cachedPlaces: [SavedPlace] = []
                for idString in cachedIds {
                    if let id = UUID(uuidString: idString),
                       let place = locationsManager.savedPlaces.first(where: { $0.id == id }) {
                        cachedPlaces.append(place)
                    }
                }
                if !cachedPlaces.isEmpty {
                    await MainActor.run {
                        recentlyVisitedPlaces = cachedPlaces
                    }
                    return // Use cached data
                }
            }
            
            // Get visits from last 7 days
            let calendar = Calendar.current
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

            guard let userId = supabaseManager.getCurrentUser()?.id else { return }

            // Fetch recent visits from Supabase
            let recentVisits = await geofenceManager.fetchRecentVisits(userId: userId, since: sevenDaysAgo, limit: 10)

            // Get unique place IDs from recent visits, maintaining order
            var seenPlaceIds = Set<UUID>()
            var recentPlaces: [SavedPlace] = []

            for visit in recentVisits {
                if !seenPlaceIds.contains(visit.savedPlaceId) {
                    if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                        recentPlaces.append(place)
                        seenPlaceIds.insert(visit.savedPlaceId)
                    }
                }

                // Limit to 8 places for the horizontal scroll
                if recentPlaces.count >= 8 {
                    break
                }
            }

            await MainActor.run {
                recentlyVisitedPlaces = recentPlaces
                
                // OPTIMIZATION: Cache the place IDs for 5 minutes
                let cacheData = recentPlaces.map { $0.id.uuidString }
                CacheManager.shared.set(cacheData, forKey: CacheManager.CacheKey.recentlyVisitedPlaces, ttl: CacheManager.TTL.medium)
            }
        }
    }

    private func updateElapsedTime() {
        // Get the active visit entry time for the current location from GeofenceManager
        // This uses REAL geofence entry time, not artificial tracking
        if let nearbyLoc = nearbyLocation {
            // Find the place by display name
            if let place = locationsManager.savedPlaces.first(where: { $0.displayName == nearbyLoc }) {
                // Only show elapsed time if geofence manager has recorded an entry
                if let activeVisit = geofenceManager.activeVisits[place.id] {
                    let elapsed = Date().timeIntervalSince(activeVisit.entryTime)
                    elapsedTimeString = formatElapsedTime(elapsed)
                    // Debug: Verify we're using real geofence data
                    // print("⏱️ Timer using REAL geofence data: \(place.displayName) - Entry: \(activeVisit.entryTime)")
                } else {
                    // No active visit record from geofence - don't show time
                    // Debug: Track when timer can't show because geofence event hasn't fired
                    // print("⚠️ No geofence entry recorded yet for: \(nearbyLoc) (proximity detected but geofence event pending)")
                    elapsedTimeString = ""
                }
            } else {
                print("⚠️ Location '\(nearbyLoc)' not found in saved places")
                elapsedTimeString = ""
            }
        } else {
            elapsedTimeString = ""
        }
    }

    // Filter places based on location search text
    private func getFilteredPlaces() -> [SavedPlace] {
        if locationSearchText.isEmpty {
            return locationsManager.savedPlaces
        }

        let searchLower = locationSearchText.lowercased()
        return locationsManager.savedPlaces.filter { place in
            let countryMatch = place.country?.lowercased().contains(searchLower) ?? false
            let provinceMatch = place.province?.lowercased().contains(searchLower) ?? false
            let cityMatch = place.city?.lowercased().contains(searchLower) ?? false
            let addressMatch = place.address.lowercased().contains(searchLower)
            let nameMatch = place.displayName.lowercased().contains(searchLower)
            return countryMatch || provinceMatch || cityMatch || addressMatch || nameMatch
        }
    }
    
    private func getPlacesForSuperCategory(_ superCategory: LocationSuperCategory) -> [String: [SavedPlace]] {
        let filtered = getFilteredPlaces()
        var result: [String: [SavedPlace]] = [:]
        
        for category in locationsManager.categories {
            if locationsManager.getSuperCategory(for: category) == superCategory {
                let categoryPlaces = filtered.filter { $0.category == category }
                if !categoryPlaces.isEmpty {
                    result[category] = categoryPlaces
                }
            }
        }
        
        return result
    }

    /// Get filtered places for a super-category with cuisine filtering applied
    private func getFilteredPlaces(for superCategory: LocationSuperCategory) -> [String: [SavedPlace]] {
        var groupedPlaces = getPlacesForSuperCategory(superCategory)

        // Apply cuisine filter for Food & Dining
        if superCategory == .foodAndDining && !selectedCuisines.isEmpty {
            groupedPlaces = groupedPlaces.mapValues { places in
                places.filter { place in
                    selectedCuisines.contains { cuisine in
                        place.userCuisine?.localizedCaseInsensitiveContains(cuisine) ?? false ||
                        place.category.localizedCaseInsensitiveContains(cuisine)
                    }
                }
            }.filter { !$0.value.isEmpty }
        }

        return groupedPlaces
    }

    // OPTIMIZATION: Cache sorted categories to avoid re-sorting on every render

    private func startLocationTimer() {
        stopLocationTimer()
        // Timer only runs when app is in foreground (scenePhase .active)
        // This shows real-time elapsed seconds only when user is looking at the screen
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsedTime()
        }
    }

    private func stopLocationTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func formatElapsedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }


    // MARK: - Helper Functions

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
        }
    }

    private func tabBackgroundColor() -> Color {
        return colorScheme == .dark ? .white : .black
    }

    private func tabContainerColor() -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
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
            // Build metadata with location and ranking data
            var metadata: [String: String] = [
                "category": place.category,
                "address": place.address,
                "rating": place.rating != nil ? String(format: "%.1f", place.rating!) : "N/A",
                "country": place.country ?? "Unknown",
                "province": place.province ?? "Unknown",
                "city": place.city ?? "Unknown"
            ]

            // Add ranking data
            if let userRating = place.userRating {
                metadata["userRating"] = String(userRating)
            }

            if let userNotes = place.userNotes {
                metadata["userNotes"] = userNotes
            }

            if let userCuisine = place.userCuisine {
                metadata["cuisine"] = userCuisine
            }

            // Build content with location and ranking info
            var contentParts: [String] = [
                "\(place.category): \(place.address)",
                "Location: \(place.city ?? "Unknown"), \(place.province ?? "Unknown"), \(place.country ?? "Unknown")"
            ]

            if let cuisine = place.userCuisine {
                contentParts.append("Cuisine: \(cuisine)")
            }

            if let userRating = place.userRating {
                contentParts.append("Rating: \(userRating)/10")
            }

            if let notes = place.userNotes {
                contentParts.append("Notes: \(notes)")
            }

            items.append(SearchableItem(
                title: place.displayName,
                content: contentParts.joined(separator: " | "),
                type: .maps,
                identifier: "place-\(place.id)",
                metadata: metadata
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
            VStack(spacing: 6) {
                // iPhone-style folder with location icons inside
                ZStack {
                    // Folder background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            colorScheme == .dark ?
                                Color.white.opacity(0.05) : Color.black.opacity(0.05)
                        )

                    // Grid of small location photos/initials (2x2)
                    if !places.isEmpty {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ], spacing: 6) {
                            ForEach(Array(places.prefix(4).enumerated()), id: \.element.id) { index, place in
                                PlaceImageView(
                                    place: place,
                                    size: 36,
                                    cornerRadius: 8
                                )
                            }
                        }
                        .padding(16)
                    } else {
                        // Empty folder - show single large icon
                        Image(systemName: "mappin.circle.fill")
                            .font(FontManager.geist(size: 40, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(white: 0.25))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            colorScheme == .dark ?
                                Color.white.opacity(0.1) : Color.black.opacity(0.05),
                            lineWidth: 1
                        )
                )

                // Folder name below
                Text(category)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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
    @State private var showingPlaceDetail = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var newPlaceName = ""
    @State private var showingIconPicker = false
    @State private var selectedIcon: String? = nil
    @State private var showingChangeFolderSheet = false
    @State private var placeToMove: SavedPlace? = nil

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
            // Background image (captured screenshot) - blurred and grayed out
            if let bgImage = backgroundImage {
                Image(uiImage: bgImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 10)  // Blur the background
                    .grayscale(0.5)    // Gray out the background
            }

            // Dimmed overlay
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Centered content - use frame with alignment
            VStack(spacing: 40) {
                // Folder title
                Text(category)
                    .font(FontManager.geist(size: 32, weight: .regular))
                    .foregroundColor(.white)

                // Large rounded container with apps
                VStack(spacing: 0) {
                    if places.isEmpty {
                        // Empty state
                        VStack(spacing: 20) {
                            Image(systemName: "mappin.slash")
                                .font(FontManager.geist(size: 48, weight: .light))
                                .foregroundColor(.white.opacity(0.5))

                            Text("No places in this folder")
                                .font(FontManager.geist(size: 16, weight: .regular))
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
                                    ZStack {
                                        VStack(spacing: 6) {
                                            // Location photo or initials with favourite button
                                            ZStack(alignment: .topTrailing) {
                                                Button(action: {
                                                    HapticManager.shared.selection()
                                                    selectedPlace = place
                                                    showingPlaceDetail = true
                                                }) {
                                                    PlaceImageView(
                                                        place: place,
                                                        size: 80,
                                                        cornerRadius: 18
                                                    )
                                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                                }
                                                .buttonStyle(PlainButtonStyle())

                                                // Favourite star button - always visible and interactive
                                                Button(action: {
                                                    locationsManager.toggleFavourite(for: place.id)
                                                    HapticManager.shared.selection()
                                                }) {
                                                    Image(systemName: place.isFavourite ? "star.fill" : "star")
                                                        .font(FontManager.geist(size: 12, weight: .semibold))
                                                        .foregroundColor(.white)
                                                        .padding(6)
                                                        .background(
                                                            Circle()
                                                                .fill(Color.black.opacity(0.7))
                                                        )
                                                }
                                                .offset(x: 6, y: -6)
                                                .zIndex(1)
                                            }

                                            // Place name
                                            Text(place.displayName)
                                                .font(FontManager.geist(size: 12, weight: .regular))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .minimumScaleFactor(0.8)
                                                .frame(height: 28)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            selectedPlace = place
                                            selectedIcon = place.userIcon
                                            showingIconPicker = true
                                        }) {
                                            Label("Edit Icon", systemImage: "square.and.pencil")
                                        }

                                        Button(action: {
                                            selectedPlace = place
                                            newPlaceName = place.customName ?? place.name
                                            showingRenameAlert = true
                                        }) {
                                            Label("Rename", systemImage: "pencil")
                                        }

                                        Button(action: {
                                            placeToMove = place
                                            showingChangeFolderSheet = true
                                        }) {
                                            Label("Move to Folder", systemImage: "folder")
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
        .sheet(isPresented: $showingPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(place: place, onDismiss: { showingPlaceDetail = false })
                    .presentationBg()
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            VStack(spacing: 0) {
                HStack {
                    Text("Edit Icon")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: { showingIconPicker = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 18, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? Color.black : Color.white)

                ScrollView {
                    IconPickerView(selectedIcon: $selectedIcon)
                        .padding(.bottom, 20)
                }

                HStack(spacing: 12) {
                    Button(action: { showingIconPicker = false }) {
                        Text("Cancel")
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    Button(action: {
                        if let place = selectedPlace {
                            var updatedPlace = place
                            updatedPlace.userIcon = selectedIcon
                            locationsManager.updatePlace(updatedPlace)
                            showingIconPicker = false
                            selectedPlace = nil
                            selectedIcon = nil
                        }
                    }) {
                        Text("Save")
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? Color.black : Color.white)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .sheet(isPresented: $showingChangeFolderSheet) {
            if let place = placeToMove {
                ChangeFolderSheet(
                    place: place,
                    currentCategory: place.category,
                    allCategories: Array(Set(locationsManager.savedPlaces.map { $0.category })).sorted(),
                    colorScheme: colorScheme,
                    onFolderSelected: { newCategory in
                        var updatedPlace = place
                        updatedPlace.category = newCategory
                        locationsManager.updatePlace(updatedPlace)
                        showingChangeFolderSheet = false
                        placeToMove = nil
                        HapticManager.shared.success()
                    },
                    onDismiss: {
                        showingChangeFolderSheet = false
                        placeToMove = nil
                    }
                )
                .presentationBg()
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
                    .font(FontManager.geist(size: 10, weight: .medium))
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
    @Binding var selectedProvince: String?
    @Binding var selectedCity: String?
    let colorScheme: ColorScheme

    var provinces: Set<String> {
        selectedCountry.map { locationsManager.getProvinces(in: $0) } ?? locationsManager.provinces
    }

    var cities: Set<String> {
        if let country = selectedCountry, let province = selectedProvince {
            return locationsManager.getCities(in: country, andProvince: province)
        } else if let country = selectedCountry {
            return locationsManager.getCities(in: country)
        } else {
            return []
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Country filter dropdown
            CompactDropdown(
                label: selectedCountry ?? "Country",
                options: ["All"] + Array(locationsManager.countries).sorted(),
                selectedOption: selectedCountry,
                onSelect: { option in
                    selectedCountry = option == "All" ? nil : option
                },
                colorScheme: colorScheme
            )

            // Province filter dropdown
            CompactDropdown(
                label: selectedProvince ?? "Province",
                options: ["All"] + Array(provinces).sorted(),
                selectedOption: selectedProvince,
                onSelect: { option in
                    selectedProvince = option == "All" ? nil : option
                },
                colorScheme: colorScheme
            )

            // City filter dropdown
            CompactDropdown(
                label: selectedCity ?? "City",
                options: ["All"] + Array(cities).sorted(),
                selectedOption: selectedCity,
                onSelect: { option in
                    selectedCity = option == "All" ? nil : option
                },
                colorScheme: colorScheme
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Mini Map View

struct MiniMapView: View {
    let places: [SavedPlace]
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onPlaceTap: (SavedPlace) -> Void
    let onExpandTap: () -> Void

    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var hasInitialized = false

    var body: some View {
        ZStack {
            Map(coordinateRegion: .constant(region), showsUserLocation: true, annotationItems: places) { place in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                    MiniMapAnnotationView(onTap: {
                        onPlaceTap(place)
                    })
                }
            }
            .disabled(false)

            // Overlay button to open full map
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        onExpandTap()
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            }
        }
        .onAppear {
            if !hasInitialized {
                updateRegion()
                hasInitialized = true
            }
            
            // Configure UIScrollView for smooth scrolling (same as home page)
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    configureScrollViewsForSmoothScrolling(in: window)
                }
            }
        }
    }

    private func updateRegion() {
        if let currentLoc = currentLocation {
            region = MKCoordinateRegion(
                center: currentLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        } else if !places.isEmpty {
            // Calculate region to fit all places
            var minLat = places[0].latitude
            var maxLat = places[0].latitude
            var minLon = places[0].longitude
            var maxLon = places[0].longitude

            for place in places {
                minLat = min(minLat, place.latitude)
                maxLat = max(maxLat, place.latitude)
                minLon = min(minLon, place.longitude)
                maxLon = max(maxLon, place.longitude)
            }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.01) * 1.5,
                longitudeDelta: max(maxLon - minLon, 0.01) * 1.5
            )

            region = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    // Configure all UIScrollViews to delay content touches for smoother scrolling
    // Same implementation as MainAppView for consistent behavior
    private func configureScrollViewsForSmoothScrolling(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.delaysContentTouches = true
            scrollView.canCancelContentTouches = true
        }
        for subview in view.subviews {
            configureScrollViewsForSmoothScrolling(in: subview)
        }
    }
}

// MARK: - Expandable Category Row

struct ExpandableCategoryRow: View {
    let category: String
    let places: [SavedPlace]
    let isExpanded: Bool
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onToggle: () -> Void
    let onPlaceTap: (SavedPlace) -> Void
    let onMoveToFolder: ((SavedPlace) -> Void)?

    @StateObject private var locationsManager = LocationsManager.shared
    @State private var showingRenameAlert = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var newPlaceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Text(category)
                        .font(FontManager.geist(size: 16, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()
                    
                    // Count badge - matching notes section styling
                    Text("\(places.count)")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(minWidth: 24, minHeight: 24)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Places list
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 8)
                        .opacity(0.3)
                    
                    ForEach(places) { place in
                        Button(action: {
                            onPlaceTap(place)
                        }) {
                            HStack(spacing: 12) {
                                PlaceImageView(place: place, size: 52, cornerRadius: 12)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(place.displayName)
                                            .font(FontManager.geist(size: 15, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        if place.isFavourite {
                                            Image(systemName: "star.fill")
                                                .font(FontManager.geist(size: 11, weight: .semibold))
                                                .foregroundColor(.yellow)
                                        }
                                    }

                                    if let distance = calculateDistance(to: place) {
                                        Text(formatDistance(distance))
                                            .font(FontManager.geist(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 0)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button(action: {
                                locationsManager.toggleFavourite(for: place.id)
                                HapticManager.shared.selection()
                            }) {
                                Label(
                                    place.isFavourite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: place.isFavourite ? "star.slash" : "star.fill"
                                )
                            }

                            Button(action: {
                                selectedPlace = place
                                newPlaceName = place.customName ?? place.name
                                showingRenameAlert = true
                            }) {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(action: {
                                onMoveToFolder?(place)
                            }) {
                                Label("Move to Folder", systemImage: "folder")
                            }

                            Button(role: .destructive, action: {
                                locationsManager.deletePlace(place)
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        
                        // Divider between places
                        if place.id != places.last?.id {
                            Divider()
                                .padding(.horizontal, 0)
                                .opacity(0.2)
                        }
                    }
                }
                .padding(.horizontal, 0)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
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
    }

    private func calculateDistance(to place: SavedPlace) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return current.distance(from: placeLocation)
    }

    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

// MARK: - Full Map View

struct FullMapView: View {
    let places: [SavedPlace]
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onPlaceTap: (SavedPlace) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    var body: some View {
        ZStack {
            // Interactive map - user can pan and zoom freely
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: places) { place in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                    MapAnnotationView(place: place, colorScheme: colorScheme) {
                        onPlaceTap(place)
                    }
                }
            }
            .ignoresSafeArea()

            // Top bar with close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 30, weight: .regular))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 32, height: 32)
                            )
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }

            // Target current location button (bottom right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        centerOnCurrentLocation()
                    }) {
                        Image(systemName: "location.fill")
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            initializeRegion()
            
            // Configure UIScrollView for smooth scrolling (same as home page)
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    configureScrollViewsForSmoothScrolling(in: window)
                }
            }
        }
    }

    private func initializeRegion() {
        // Use LocationService directly to get the actual current location
        if let currentLoc = LocationService.shared.currentLocation {
            region = MKCoordinateRegion(
                center: currentLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        } else if !places.isEmpty {
            // Calculate region to fit all places
            var minLat = places[0].latitude
            var maxLat = places[0].latitude
            var minLon = places[0].longitude
            var maxLon = places[0].longitude

            for place in places {
                minLat = min(minLat, place.latitude)
                maxLat = max(maxLat, place.latitude)
                minLon = min(minLon, place.longitude)
                maxLon = max(maxLon, place.longitude)
            }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.01) * 1.5,
                longitudeDelta: max(maxLon - minLon, 0.01) * 1.5
            )

            region = MKCoordinateRegion(center: center, span: span)
        }
    }

    private func centerOnCurrentLocation() {
        // Use LocationService directly to get the actual current location
        guard let currentLoc = LocationService.shared.currentLocation else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            region = MKCoordinateRegion(
                center: currentLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
    
    // Configure all UIScrollViews to delay content touches for smoother scrolling
    // Same implementation as MainAppView for consistent behavior
    private func configureScrollViewsForSmoothScrolling(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.delaysContentTouches = true
            scrollView.canCancelContentTouches = true
        }
        for subview in view.subviews {
            configureScrollViewsForSmoothScrolling(in: subview)
        }
    }
}

// MARK: - Change Folder Sheet

struct ChangeFolderSheet: View {
    let place: SavedPlace
    let currentCategory: String
    let allCategories: [String]
    let colorScheme: ColorScheme
    let onFolderSelected: (String) -> Void
    let onDismiss: () -> Void

    @State private var newFolderName: String = ""
    @State private var showingNewFolderAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Move to Folder")
                        .font(FontManager.geist(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 22, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? Color.black : Color.white)

                // Place info
                HStack(spacing: 12) {
                    PlaceImageView(place: place, size: 50, cornerRadius: 10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.displayName)
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Currently in: \(currentCategory)")
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Folder list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(allCategories, id: \.self) { category in
                            Button(action: {
                                if category != currentCategory {
                                    onFolderSelected(category)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(FontManager.geist(size: 18, weight: .medium))
                                        .foregroundColor(category == currentCategory ? .blue : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)))

                                    Text(category)
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)

                                    Spacer()

                                    if category == currentCategory {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(FontManager.geist(size: 18, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(category == currentCategory ?
                                            Color.blue.opacity(0.1) :
                                            (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(category == currentCategory)
                        }

                        // Create new folder button
                        Button(action: {
                            showingNewFolderAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(FontManager.geist(size: 18, weight: .medium))
                                    .foregroundColor(.green)

                                Text("Create New Folder")
                                    .font(FontManager.geist(size: 15, weight: .medium))
                                    .foregroundColor(.green)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .alert("Create New Folder", isPresented: $showingNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
                Button("Create") {
                    let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty && !allCategories.contains(trimmedName) {
                        onFolderSelected(trimmedName)
                    }
                    newFolderName = ""
                }
            } message: {
                Text("Enter a name for the new folder")
            }
        }
    }
}

// MARK: - Map Annotation View (Gesture-Aware)
// These views use a drag gesture to allow scrolling while preventing accidental taps

struct MapAnnotationView: View {
    let place: SavedPlace
    let colorScheme: ColorScheme
    let onTap: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
            
            Text(place.displayName)
                .font(FontManager.geist(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.75))
                )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Only trigger tap if drag distance is very small (< 10 points)
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    if dragDistance < 10 {
                        HapticManager.shared.selection()
                        onTap()
                    }
                    dragOffset = .zero
                }
        )
    }
}

struct MiniMapAnnotationView: View {
    let onTap: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Only trigger tap if drag distance is very small (< 10 points)
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    if dragDistance < 10 {
                        HapticManager.shared.selection()
                        onTap()
                    }
                    dragOffset = .zero
                }
        )
    }
}

#Preview {
    MapsViewNew()
}
