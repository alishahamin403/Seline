import SwiftUI
import CoreLocation
import MapKit

struct MapsViewNew: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Namespace private var tabAnimation

    @State private var selectedTab: String = "folders" // "folders", "ranking", or "timeline"
    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false
    @State private var showingPlaceDetail = false
    @State private var selectedPlace: SavedPlace? = nil
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
    @State private var cachedSortedCategories: [String] = []
    @State private var hasLoadedIncompleteVisits = false  // Prevents race condition on app launch
    @StateObject private var geofenceManager = GeofenceManager.shared
    @Binding var externalSelectedFolder: String?
    @State private var topLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var showAllLocationsSheet = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast  // Time debounce for location updates
    @State private var isFavoritesExpanded = true  // Controls expand/collapse of favourites section
    @State private var recentlyVisitedPlaces: [SavedPlace] = []
    @State private var expandedCategories: Set<String> = []  // Track which categories are expanded
    @State private var showFullMapView = false  // Controls full map view sheet

    init(externalSelectedFolder: Binding<String?> = .constant(nil)) {
        self._externalSelectedFolder = externalSelectedFolder
    }

    var body: some View {
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                // Header section with search
                VStack(spacing: 0) {
                    // Tab bar with search button - Modern pill-based segmented control
                    HStack(spacing: 12) {
                        // Search button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isLocationSearchActive {
                                    isLocationSearchActive = false
                                    locationSearchText = ""
                                } else {
                                    isLocationSearchActive = true
                                }
                            }
                        }) {
                            Image(systemName: isLocationSearchActive ? "xmark.circle.fill" : "magnifyingglass")
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

                        Spacer()

                        // Tab bar - Modern pill-based segmented control
                        HStack(spacing: 4) {
                            ForEach(["folders", "ranking", "timeline"], id: \.self) { tab in
                                let isSelected = selectedTab == tab
                                let tabIcon = tab == "folders" ? "folder.fill" : (tab == "ranking" ? "chart.bar.fill" : "clock.fill")

                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedTab = tab
                                    }
                                }) {
                                    Image(systemName: tabIcon)
                                        .font(.system(size: 14, weight: .medium))
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
                        }
                        .padding(4)
                        .background(
                            Capsule()
                                .fill(tabContainerColor())
                        )

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .background(
                        colorScheme == .dark ? Color.black : Color.white
                    )

                    // Search bar - show when search is active
                    if isLocationSearchActive {
                        EmailSearchBar(searchText: $locationSearchText) { query in
                            // Search is handled by filtering in locationsTabContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if selectedTab == "folders" {
                            locationsTabContent
                        } else if selectedTab == "ranking" {
                            rankingTabContent
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
                .presentationBg()
        }
        .sheet(isPresented: $showingPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(place: place, onDismiss: { showingPlaceDetail = false }, isFromRanking: selectedTab == "ranking")
                    .presentationBg()
            }
        }
        .sheet(isPresented: $showAllLocationsSheet) {
            AllVisitsSheet(
                allLocations: $allLocations,
                isPresented: $showAllLocationsSheet,
                onLocationTap: { locationId in
                    // Find the SavedPlace with this UUID
                    if let place = locationsManager.savedPlaces.first(where: { $0.id == locationId }) {
                        selectedPlace = place
                        showingPlaceDetail = true
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
                    showingPlaceDetail = true
                }
            )
            .presentationBg()
        }
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .maps)

            // Initialize cached categories
            updateCachedCategories()

            // CLEANUP: Auto-close any incomplete visits older than 3 hours in Supabase
            // This fixes visits that got stuck before the auto-cleanup code was added
            Task {
                await geofenceManager.cleanupIncompleteVisitsInSupabase(olderThanMinutes: 180)
            }

            // Load incomplete visits from Supabase to resume tracking BEFORE checking location
            // This prevents race condition where updateCurrentLocation() creates a new visit
            // before the async load completes
            Task {
                await geofenceManager.loadIncompleteVisitsFromSupabase()
                // Now that previous sessions are restored, check current location
                await MainActor.run {
                    updateCurrentLocation()
                    // Signal that we've loaded incomplete visits and can now respond to location changes
                    hasLoadedIncompleteVisits = true
                }
            }

            // Load top 3 locations by visit count
            loadTopLocations()

            // Load recently visited places
            loadRecentlyVisited()

            locationService.requestLocationPermission()
        }
        .onReceive(locationService.$currentLocation) { _ in
            // Only update location if we've finished loading incomplete visits
            // This prevents creating duplicate sessions on app startup
            if hasLoadedIncompleteVisits {
                // TIME DEBOUNCE: Skip updates that occur within 2 seconds of last update
                // This prevents excessive location processing and improves performance
                let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime)
                if timeSinceLastUpdate >= 2.0 {
                    lastLocationUpdateTime = Date()
                    updateCurrentLocation()
                }
            }
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
        // Update cached categories when location search text changes
        .onChange(of: locationSearchText) { _ in updateCachedCategories() }
        // OPTIMIZATION: Stop timer when app goes to background, restart when it comes to foreground
        // The timer only runs when user is actively looking at the screen
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // FIX: Immediately check current location to update nearby location state
                // This ensures UI updates right away when app comes to foreground
                updateCurrentLocation()

                // App came to foreground - restart timer if tracking a location
                if nearbyLocation != nil {
                    startLocationTimer()
                }

                // FALLBACK: Check if any visits have gone stale while app was backgrounded
                // This handles case where geofence exit events didn't fire
                if let currentLoc = locationService.currentLocation {
                    Task {
                        await geofenceManager.autoCompleteVisitsIfOutOfRange(
                            currentLocation: currentLoc,
                            savedPlaces: locationsManager.savedPlaces
                        )
                    }
                }
            } else {
                // App went to background/inactive - pause timer
                stopLocationTimer()
            }
        }
        .onChange(of: locationsManager.savedPlaces) { _ in
            // Reload top 3 locations when places are added/removed/updated
            loadTopLocations()
        }
        .onChange(of: colorScheme) { _ in
            // FIX: Force view refresh when system theme changes
            // This ensures the app immediately updates from light to dark mode
            // The onChange itself triggers a view update cycle
        }
        .id(colorScheme) // Force complete view recreation on theme change
        .onDisappear {
            stopLocationTimer()
        }

        // iPhone-style folder overlay
        if selectedCategory != nil {
            let filteredPlaces = getFilteredPlaces()
                .filter { $0.category == selectedCategory }
            FolderOverlayView(
                category: selectedCategory!,
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

    @ViewBuilder
    private var locationsTabContent: some View {
        if locationsManager.categories.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "map").font(.system(size: 48, weight: .light)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                Text("No saved places yet").font(.system(size: 18, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                Text("Search for places and save them to categories").font(.system(size: 14, weight: .regular)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)).multilineTextAlignment(.center)
            }.padding(.top, 60)
        } else if selectedCategory == nil {
            miniMapSection
            recentlyVisitedSection
            favoritesSection
            expandableCategoriesSection
        }

        Spacer().frame(height: 100)
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let allFavourites = locationsManager.getFavourites()
        let favourites = allFavourites.filter { place in
            if locationSearchText.isEmpty {
                return true
            }
            let searchLower = locationSearchText.lowercased()
            return (place.country?.lowercased().contains(searchLower) ?? false) ||
                   (place.province?.lowercased().contains(searchLower) ?? false) ||
                   (place.city?.lowercased().contains(searchLower) ?? false) ||
                   place.address.lowercased().contains(searchLower) ||
                   place.displayName.lowercased().contains(searchLower)
        }
        if !favourites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header with expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFavoritesExpanded.toggle()
                    }
                    HapticManager.shared.light()
                }) {
                    HStack(spacing: 8) {
                        Text("Favorites").font(.system(size: 17, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black)
                        Spacer()
                        Image(systemName: isFavoritesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, isFavoritesExpanded ? 0 : 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Collapsible content
                if isFavoritesExpanded {
                    VStack(spacing: 8) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(favourites, id: \.id) { place in
                                Button(action: { selectedPlace = place; showingPlaceDetail = true }) {
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            PlaceImageView(place: place, size: 60, cornerRadius: 12)
                                            Button(action: { locationsManager.toggleFavourite(for: place.id); HapticManager.shared.selection() }) {
                                                Image(systemName: place.isFavourite ? "star.fill" : "star")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                                    .padding(4)
                                                    .background(Circle().fill(colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.9)))
                                            }
                                            .offset(x: 4, y: -4)
                                        }

                                        Text(place.displayName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .minimumScaleFactor(0.8)
                                            .frame(height: 24)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(role: .destructive, action: { locationsManager.deletePlace(place) }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                        radius: 12,
                        x: 0,
                        y: 2
                    )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
                    showingPlaceDetail = true
                },
                onExpandTap: {
                    showFullMapView = true
                }
            )
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var recentlyVisitedSection: some View {
        if !recentlyVisitedPlaces.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Recently Visited")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentlyVisitedPlaces, id: \.id) { place in
                            Button(action: {
                                selectedPlace = place
                                showingPlaceDetail = true
                            }) {
                                VStack(spacing: 6) {
                                    PlaceImageView(place: place, size: 70, cornerRadius: 14)

                                    Text(place.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 70, height: 28)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                        radius: 12,
                        x: 0,
                        y: 2
                    )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var expandableCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("All Locations")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 8) {
                ForEach(cachedSortedCategories, id: \.self) { category in
                    ExpandableCategoryRow(
                        category: category,
                        places: getFilteredPlaces().filter { $0.category == category },
                        isExpanded: expandedCategories.contains(category),
                        currentLocation: locationService.currentLocation,
                        colorScheme: colorScheme,
                        onToggle: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if expandedCategories.contains(category) {
                                    expandedCategories.remove(category)
                                } else {
                                    expandedCategories.insert(category)
                                }
                            }
                            HapticManager.shared.light()
                        },
                        onPlaceTap: { place in
                            selectedPlace = place
                            showingPlaceDetail = true
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                    radius: 12,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var rankingTabContent: some View {
        RankingView(locationsManager: locationsManager, colorScheme: colorScheme, locationSearchText: locationSearchText)
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
            // Get all places with their visit counts sorted by most visited
            var placesWithCounts: [(id: UUID, displayName: String, visitCount: Int)] = []

            for place in locationsManager.savedPlaces {
                // Fetch stats for this place
                await LocationVisitAnalytics.shared.fetchStats(for: place.id)

                if let stats = LocationVisitAnalytics.shared.visitStats[place.id] {
                    placesWithCounts.append((
                        id: place.id,
                        displayName: place.displayName,
                        visitCount: stats.totalVisits
                    ))
                }
            }

            // Sort by visit count (descending)
            let allSorted = placesWithCounts.sorted { $0.visitCount > $1.visitCount }

            // Top 3 for the card
            let top3 = allSorted.prefix(3).map { $0 }

            await MainActor.run {
                topLocations = top3
                allLocations = allSorted  // Store all locations for "See All" feature
            }
        }
    }

    private func loadRecentlyVisited() {
        Task {
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
            (place.country?.lowercased().contains(searchLower) ?? false) ||
            (place.province?.lowercased().contains(searchLower) ?? false) ||
            (place.city?.lowercased().contains(searchLower) ?? false) ||
            place.address.lowercased().contains(searchLower) ||
            place.displayName.lowercased().contains(searchLower)
        }
    }

    // OPTIMIZATION: Cache sorted categories to avoid re-sorting on every render
    private func updateCachedCategories() {
        let filteredPlaces = getFilteredPlaces()
        var categorySet = Set<String>()
        for place in filteredPlaces {
            categorySet.insert(place.category)
        }
        cachedSortedCategories = Array(categorySet).sorted()
    }

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
                            .font(.system(size: 40, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
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
                                                        .font(.system(size: 12, weight: .semibold))
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
                                                .font(.system(size: 12, weight: .regular))
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: { showingIconPicker = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
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
                            .font(.system(size: 16, weight: .semibold))
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
                            .font(.system(size: 16, weight: .semibold))
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
                    Button(action: {
                        onPlaceTap(place)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        }
                    }
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
                            .font(.system(size: 12, weight: .medium))
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

    @StateObject private var locationsManager = LocationsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .frame(width: 20)

                    Text(category)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("(\(places.count))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Places list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(places) { place in
                        Button(action: {
                            onPlaceTap(place)
                        }) {
                            HStack(spacing: 12) {
                                PlaceImageView(place: place, size: 50, cornerRadius: 10)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(place.displayName)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        if place.isFavourite {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.yellow)
                                        }
                                    }

                                    if let distance = calculateDistance(to: place) {
                                        Text(formatDistance(distance))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                            )
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

                            Button(role: .destructive, action: {
                                locationsManager.deletePlace(place)
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
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
                    Button(action: {
                        onPlaceTap(place)
                    }) {
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
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.black.opacity(0.75))
                                )
                        }
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
                            .font(.system(size: 30))
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
                            .font(.system(size: 18, weight: .semibold))
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
        }
    }

    private func initializeRegion() {
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

    private func centerOnCurrentLocation() {
        guard let currentLoc = currentLocation else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            region = MKCoordinateRegion(
                center: currentLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
}

#Preview {
    MapsViewNew()
}
