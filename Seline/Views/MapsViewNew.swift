import SwiftUI
import CoreLocation

struct MapsViewNew: View, Searchable {
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    @State private var selectedTab: String = "folders" // "folders" or "ranking"
    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false
    @State private var showingPlaceDetail = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var locationPreferences: UserLocationPreferences?
    @State private var showETAEditModal = false
    @State private var selectedCountry: String? = nil
    @State private var selectedProvince: String? = nil
    @State private var selectedCity: String? = nil
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

    init(externalSelectedFolder: Binding<String?> = .constant(nil)) {
        self._externalSelectedFolder = externalSelectedFolder
    }

    var body: some View {
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(["folders", "ranking"], id: \.self) { tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }) {
                            Text(tab == "folders" ? "Locations" : "Ranking")
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundColor(selectedTab == tab ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedTab == tab ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color.clear)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.gray.opacity(0.08))
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .background(
                    colorScheme == .dark ? Color.black : Color.white
                )

                // Main content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if selectedTab == "folders" {
                            quickLocationsSection
                            locationsTabContent
                        } else {
                            rankingTabContent
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

            // Load location preferences for quick locations section
            locationService.requestLocationPermission()
            Task {
                do {
                    locationPreferences = try await supabaseManager.loadLocationPreferences()

                    // Initial refresh or check if 5km moved since last refresh
                    if let currentLocation = locationService.currentLocation, let preferences = locationPreferences {
                        await navigationService.checkAndRefreshIfNeeded(
                            currentLocation: currentLocation,
                            location1: preferences.location1Coordinate,
                            location2: preferences.location2Coordinate,
                            location3: preferences.location3Coordinate,
                            location4: preferences.location4Coordinate
                        )
                    } else {
                        // Fallback to direct update if no location yet
                        updateETAs()
                    }
                } catch {
                    print("Failed to load location preferences: \(error)")
                }
            }
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
        // OPTIMIZATION: Update cached categories only once when any filter changes
        // Combined onChange instead of three separate ones to avoid redundant calculations
        .onChange(of: selectedCountry) { _ in updateCachedCategories() }
        .onChange(of: selectedProvince) { _ in updateCachedCategories() }
        .onChange(of: selectedCity) { _ in updateCachedCategories() }
        // OPTIMIZATION: Stop timer when app goes to background, restart when it comes to foreground
        // The timer only runs when user is actively looking at the screen
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
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
        .onChange(of: locationService.currentLocation) { location in
            // Auto-refresh ETAs when user moves 5km+
            guard let currentLocation = location, let preferences = locationPreferences else { return }

            Task {
                await navigationService.checkAndRefreshIfNeeded(
                    currentLocation: currentLocation,
                    location1: preferences.location1Coordinate,
                    location2: preferences.location2Coordinate,
                    location3: preferences.location3Coordinate,
                    location4: preferences.location4Coordinate
                )
            }
        }
        .onChange(of: showETAEditModal) { isShowing in
            if !isShowing {
                // Reload location preferences when edit sheet closes
                Task {
                    do {
                        locationPreferences = try await supabaseManager.loadLocationPreferences()
                        updateETAs()
                    } catch {
                        print("Failed to reload location preferences: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showETAEditModal) {
            AllLocationsEditView(currentPreferences: locationPreferences)
        }
        .onDisappear {
            stopLocationTimer()
        }

        // iPhone-style folder overlay
        if selectedCategory != nil {
            let filteredPlaces = locationsManager.getPlaces(country: selectedCountry, province: selectedProvince, city: selectedCity)
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
            favoritesSection
            savedLocationsSection
        }

        Spacer().frame(height: 100)
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let favourites = locationsManager.getFavourites()
        if !favourites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(.yellow)
                    Text("Favorites").font(.system(size: 16, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(favourites, id: \.id) { place in
                            Button(action: { selectedPlace = place; showingPlaceDetail = true }) {
                                VStack(spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        PlaceImageView(place: place, size: 60, cornerRadius: 12).shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                        Button(action: { locationsManager.toggleFavourite(for: place.id); HapticManager.shared.selection() }) {
                                            Image(systemName: place.isFavourite ? "star.fill" : "star").font(.system(size: 12, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black).padding(6).background(Circle().fill(colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.9)))
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                    Text(place.displayName).font(.system(size: 10, weight: .regular)).foregroundColor(colorScheme == .dark ? .white : .black).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8).frame(height: 20)
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
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var savedLocationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
                Text("Saved Locations").font(.system(size: 16, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            LocationFiltersView(locationsManager: locationsManager, selectedCountry: $selectedCountry, selectedProvince: $selectedProvince, selectedCity: $selectedCity, colorScheme: colorScheme)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(cachedSortedCategories, id: \.self) { category in
                    CategoryCard(category: category, count: locationsManager.getPlaces(country: selectedCountry, province: selectedProvince, city: selectedCity).filter { $0.category == category }.count, colorScheme: colorScheme) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var rankingTabContent: some View {
        RankingView(locationsManager: locationsManager, colorScheme: colorScheme)
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

    // OPTIMIZATION: Cache sorted categories to avoid re-sorting on every render
    private func updateCachedCategories() {
        let categories = Array(locationsManager.getCategories(
            country: selectedCountry,
            province: selectedProvince,
            city: selectedCity
        )).sorted()
        cachedSortedCategories = categories
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

    @ViewBuilder
    private var quickLocationsSection: some View {
        if locationPreferences != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                    Text("Quick Locations")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(spacing: 12) {
                    quickLocationCard(icon: locationPreferences?.location1Icon ?? "house.fill", name: "Home", eta: navigationService.location1ETA, isLocationSet: locationPreferences?.location1Coordinate != nil, onTap: { if locationPreferences?.location1Coordinate != nil { openNavigation(to: locationPreferences?.location1Coordinate, address: locationPreferences?.location1Address) } }, onLongPress: { showETAEditModal = true })

                    quickLocationCard(icon: locationPreferences?.location2Icon ?? "briefcase.fill", name: "Work", eta: navigationService.location2ETA, isLocationSet: locationPreferences?.location2Coordinate != nil, onTap: { if locationPreferences?.location2Coordinate != nil { openNavigation(to: locationPreferences?.location2Coordinate, address: locationPreferences?.location2Address) } }, onLongPress: { showETAEditModal = true })

                    quickLocationCard(icon: locationPreferences?.location3Icon ?? "fork.knife", name: "Lunch", eta: navigationService.location3ETA, isLocationSet: locationPreferences?.location3Coordinate != nil, onTap: { if locationPreferences?.location3Coordinate != nil { openNavigation(to: locationPreferences?.location3Coordinate, address: locationPreferences?.location3Address) } }, onLongPress: { showETAEditModal = true })

                    quickLocationCard(icon: locationPreferences?.location4Icon ?? "dumbbell.fill", name: "Gym", eta: navigationService.location4ETA, isLocationSet: locationPreferences?.location4Coordinate != nil, onTap: { if locationPreferences?.location4Coordinate != nil { openNavigation(to: locationPreferences?.location4Coordinate, address: locationPreferences?.location4Address) } }, onLongPress: { showETAEditModal = true })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
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

    private func openNavigation(to coordinate: CLLocationCoordinate2D?, address: String?) {
        guard let coordinate = coordinate, let address = address else { return }
        let url = "comgooglemaps://?q=\(address)&center=\(coordinate.latitude),\(coordinate.longitude)"
        if let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encodedUrl) {
            UIApplication.shared.open(url)
        }
    }

    private func quickLocationCard(
        icon: String,
        name: String,
        eta: String?,
        isLocationSet: Bool,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))

                VStack(spacing: 2) {
                    if navigationService.isLoading && isLocationSet {
                        ProgressView()
                            .scaleEffect(0.7, anchor: .center)
                    } else if let eta = eta, isLocationSet {
                        Text(eta)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text("--")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }

                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
            }
            .frame(width: 70)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                HapticManager.shared.selection()
                onLongPress()
            }) {
                Label("Edit Locations", systemImage: "pencil")
            }
        }
    }

    private func updateETAs() {
        guard let preferences = locationPreferences else { return }

        if locationService.currentLocation == nil {
            locationService.requestLocationPermission()
            return
        }

        guard let currentLocation = locationService.currentLocation else { return }

        Task {
            await navigationService.updateETAs(
                currentLocation: currentLocation,
                location1: preferences.location1Coordinate,
                location2: preferences.location2Coordinate,
                location3: preferences.location3Coordinate,
                location4: preferences.location4Coordinate
            )
        }
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

#Preview {
    MapsViewNew()
}
