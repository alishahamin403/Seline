import SwiftUI
import CoreLocation
import MapKit

struct MapsViewNew: View, Searchable {
    private enum HubPeriod: String, CaseIterable {
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    private enum HubDetailSection: String, CaseIterable {
        case places
        case people
        case timeline

        var title: String {
            switch self {
            case .places:
                return "Places"
            case .people:
                return "People"
            case .timeline:
                return "Timeline"
            }
        }

        var tabTitle: String {
            switch self {
            case .places:
                return "Locations"
            case .people:
                return "People"
            case .timeline:
                return "Timeline"
            }
        }
    }

    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var peopleManager = PeopleManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    @State private var selectedHubDetail: HubDetailSection = .places
    @State private var hubPeriod: HubPeriod = .thisMonth
    @State private var hubPeriodVisits: [LocationVisitRecord] = []
    @State private var isLoadingHubPeriodVisits = false
    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var selectedPlaceForRating: SavedPlace? = nil
    @State private var showRatingEditor = false
    @State private var locationSearchText: String = ""
    @State private var isLocationSearchActive: Bool = false
    @State private var isPeopleSearchActive: Bool = false
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
    @State private var showNewFolderAlert = false  // Controls new folder alert
    @State private var newFolderName = ""  // Name for the new folder
    @State private var showingRenameAlert = false  // Controls rename alert
    @State private var placeToRename: SavedPlace? = nil  // Place being renamed
    @State private var newPlaceName = ""  // New name for the place
    @FocusState private var isSearchFocused: Bool  // For search bar focus
    @Namespace private var mapsTabAnimation

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
            .onChange(of: hubPeriod) { _ in
                Task {
                    await loadHubPeriodVisits()
                }
            }
            .onChange(of: colorScheme) { _ in
                // Force view refresh when system theme changes
            }
            .id(colorScheme)
            .onDisappear {
                stopLocationTimer()
            }
            .swipeDownToRevealSearch(
                enabled: !isLocationSearchActive && !isPeopleSearchActive,
                topRegion: UIScreen.main.bounds.height * 0.22,
                minimumDistance: 70
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedHubDetail == .places {
                        isLocationSearchActive = true
                        isSearchFocused = true
                    } else if selectedHubDetail == .people {
                        isPeopleSearchActive = true
                    }
                }
            }
            .swipeUpToDismissSearch(
                enabled: (selectedHubDetail == .places
                    && isLocationSearchActive
                    && locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    || (selectedHubDetail == .people && isPeopleSearchActive),
                topRegion: UIScreen.main.bounds.height * 0.28,
                minimumDistance: 54
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedHubDetail == .places {
                        locationSearchText = ""
                        isLocationSearchActive = false
                        isSearchFocused = false
                    } else if selectedHubDetail == .people {
                        isPeopleSearchActive = false
                    }
                }
            }
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
            // Keep People search overlay full-screen when active.
            if !isPeopleSearchActive {
                if !isLocationSearchActive {
                    hubHeader
                }

                // Search bar (appears when active)
                if isLocationSearchActive && selectedHubDetail == .places {
                    locationSearchBar
                        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(hubBackgroundColor)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(hubBackgroundColor)
    }
    
    private var hubHeader: some View {
        HStack(spacing: 0) {
            hubMainPagePicker
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, -4)
        .padding(.bottom, 10)
    }

    private var hubMainPagePicker: some View {
        HStack(spacing: 6) {
            ForEach(HubDetailSection.allCases, id: \.rawValue) { section in
                let isSelected = selectedHubDetail == section

                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedHubDetail = section

                        // Keep each page focused and avoid cross-page search overlays.
                        if section != .places {
                            isLocationSearchActive = false
                            isSearchFocused = false
                            locationSearchText = ""
                            selectedCategory = nil
                        }
                        if section != .people {
                            isPeopleSearchActive = false
                        }
                    }
                }) {
                    Text(section.tabTitle)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(
                            isSelected
                                ? (colorScheme == .dark ? .black : .white)
                                : Color.appTextSecondary(colorScheme)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(hubAccentColor)
                                    .matchedGeometryEffect(id: "mapsMainPageTab", in: mapsTabAnimation)
                            }
                        }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.appChip(colorScheme))
        )
        .frame(maxWidth: .infinity)
    }

    private func detailHeader(for detail: HubDetailSection) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                HapticManager.shared.buttonTap()
                closeHubDetail()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 40, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.appChip(colorScheme))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Text(detail.title)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            if detail == .places || detail == .people {
                Color.clear
                    .frame(width: 40, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, -4)
        .padding(.bottom, 10)
    }

    private var hubPeriodPicker: some View {
        HStack(spacing: 4) {
            ForEach(HubPeriod.allCases, id: \.rawValue) { period in
                let isSelected = period == hubPeriod
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        hubPeriod = period
                    }
                }) {
                    Text(period.rawValue)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : Color.appTextSecondary(colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? hubAccentColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.appChip(colorScheme))
        )
        .frame(maxWidth: .infinity)
    }
    
    private var locationSearchBar: some View {
        UnifiedSearchBar(
            searchText: $locationSearchText,
            isFocused: $isSearchFocused,
            placeholder: "Search locations",
            onCancel: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    locationSearchText = ""
                    isLocationSearchActive = false
                    isSearchFocused = false
                }
            },
            colorScheme: colorScheme
        )
    }
    
    // MARK: - Main Scroll Content

    @ViewBuilder
    private var mainScrollContent: some View {
        detailContent(for: selectedHubDetail)
    }

    private var hubScrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                unifiedHubContent

                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .background(
            hubBackgroundColor
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func detailContent(for detail: HubDetailSection) -> some View {
        if detail == .places {
            ScrollView(.vertical, showsIndicators: false) {
                locationsTabContent
            }
            .background(
                hubBackgroundColor
                    .ignoresSafeArea()
            )
        } else if detail == .people {
            peopleTabContent
                .background(
                    hubBackgroundColor
                        .ignoresSafeArea()
                )
        } else {
            timelineTabContent
                .background(
                    hubBackgroundColor
                        .ignoresSafeArea()
                )
        }
    }

    // MARK: - Unified Hub

    private var unifiedHubContent: some View {
        Group {
            hubOverviewSection
            hubPlacesSection
            hubPeopleSection
            hubTimelineSection
        }
    }

    private var hubOverviewSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(title: "OVERVIEW · \(hubPeriodDisplayText.uppercased())", count: hubPeriodVisits.count)

            HStack(spacing: 8) {
                hubStatPill(label: "Visits", value: "\(hubPeriodVisits.count)")
                hubStatPill(label: "Places", value: "\(hubUniqueVisitedPlacesCount)")
                hubStatPill(label: "Time", value: formatDuration(minutes: hubTotalVisitMinutes))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: nearbyLocation != nil ? "mappin.and.ellipse" : "location")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(hubSecondaryTextColor)

                Text(hubCurrentLocationSummary)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(hubCardBackground)
    }

    private var hubPlacesSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(
                title: "PLACES · \(hubPeriodDisplayText.uppercased())",
                count: hubSavedPlaces.count,
                addAction: {
                    HapticManager.shared.buttonTap()
                    showSearchModal = true
                }
            )

            if hubSavedPlaces.isEmpty {
                hubEmptyState(
                    icon: "mappin.slash",
                    title: "No saved places",
                    subtitle: "Add a location to get started"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(label: "Saved", value: "\(hubSavedPlaces.count)")
                    hubStatPill(label: "Favorites", value: "\(hubSavedPlaces.filter { $0.isFavourite }.count)")
                    hubStatPill(label: "Top", value: hubPlaceCategoryBreakdown.first?.name ?? "-")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                if !hubPlaceCategoryBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top categories")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(hubSecondaryTextColor)

                        ForEach(Array(hubPlaceCategoryBreakdown.prefix(3)), id: \.name) { row in
                            hubCategoryRow(
                                title: row.name,
                                value: row.count,
                                maxValue: hubPlaceCategoryBreakdown.first?.count ?? 1
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                if !hubVisitedPlacesByCount.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(hubVisitedPlacesByCount.prefix(3)), id: \.place.id) { item in
                            hubPlaceVisitRow(item.place, visitCount: item.count)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }

            hubPrimaryButton("Open detailed places") {
                openHubDetail(.places)
            }
            .padding(.bottom, 14)
        }
        .background(hubCardBackground)
    }

    private var hubPeopleSection: some View {
        let people = peopleManager.people

        return VStack(spacing: 0) {
            hubCardHeader(title: "PEOPLE", count: people.count)

            if people.isEmpty {
                hubEmptyState(
                    icon: "person.2.slash",
                    title: "No people saved",
                    subtitle: "Add people to connect them with your places"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(label: "Total", value: "\(people.count)")
                    hubStatPill(label: "Favorites", value: "\(people.filter { $0.isFavourite }.count)")
                    hubStatPill(label: hubPeriodDisplayText, value: "\(hubPeopleUpdatedInPeriodCount) updated")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                if !hubPeopleRelationshipBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Relationship groups")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(hubSecondaryTextColor)

                        ForEach(Array(hubPeopleRelationshipBreakdown.prefix(3)), id: \.name) { row in
                            hubCategoryRow(
                                title: row.name,
                                value: row.count,
                                maxValue: hubPeopleRelationshipBreakdown.first?.count ?? 1
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                VStack(spacing: 8) {
                    ForEach(Array(hubRecentPeople.prefix(3)), id: \.id) { person in
                        hubPersonRow(person)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            hubPrimaryButton("Open people details") {
                openHubDetail(.people)
            }
            .padding(.bottom, 14)
        }
        .background(hubCardBackground)
    }

    private var hubTimelineSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(title: "TIMELINE · \(hubPeriodDisplayText.uppercased())", count: hubPeriodVisits.count)

            if isLoadingHubPeriodVisits {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if hubPeriodVisits.isEmpty {
                hubEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No visits in this period",
                    subtitle: "Your visits will show here once tracking records them"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(label: "Visits", value: "\(hubPeriodVisits.count)")
                    hubStatPill(label: "Unique", value: "\(hubUniqueVisitedPlacesCount)")
                    hubStatPill(label: "Time", value: formatDuration(minutes: hubTotalVisitMinutes))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                VStack(spacing: 8) {
                    ForEach(Array(hubPeriodVisits.prefix(4)), id: \.id) { visit in
                        hubVisitRow(visit)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            hubPrimaryButton("Open day timeline") {
                openHubDetail(.timeline)
            }
            .padding(.bottom, 14)
        }
        .background(hubCardBackground)
    }

    private func hubCardHeader(title: String, count: Int, addAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(hubSecondaryTextColor)
                .textCase(.uppercase)
                .tracking(0.6)

            if count > 0 {
                Text("· \(count)")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(hubSecondaryTextColor)
            }

            Spacer()

            if let addAction {
                Button(action: addAction) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.appChip(colorScheme))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func hubStatPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(hubSecondaryTextColor)
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hubInnerSurfaceColor)
        )
    }

    private func hubCategoryRow(title: String, value: Int, maxValue: Int) -> some View {
        let ratio = maxValue > 0 ? min(max(Double(value) / Double(maxValue), 0.0), 1.0) : 0.0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)

                Spacer()

                Text("\(value)")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appBorder(colorScheme).opacity(0.75))

                    Capsule()
                        .fill(hubAccentColor)
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
    }

    private func hubPlaceVisitRow(_ place: SavedPlace, visitCount: Int) -> some View {
        HStack(spacing: 10) {
            PlaceImageView(place: place, size: 34, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.displayName)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)
                Text("\(visitCount) visit\(visitCount == 1 ? "" : "s")")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(hubSecondaryTextColor)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hubInnerSurfaceColor)
        )
    }

    private func hubPersonRow(_ person: Person) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.appChip(colorScheme))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(person.initials)
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(hubPrimaryTextColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)
                Text(person.relationshipDisplayText)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(hubSecondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hubInnerSurfaceColor)
        )
    }

    private func hubVisitRow(_ visit: LocationVisitRecord) -> some View {
        let placeName = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName ?? "Saved Place"
        let visitMinutes = max(visit.durationMinutes ?? Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)

        return HStack(spacing: 10) {
            Image(systemName: "mappin.circle")
                .font(FontManager.geist(size: 16, weight: .regular))
                .foregroundColor(hubSecondaryTextColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(placeName)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)
                Text(visit.entryTime.formatted(date: .abbreviated, time: .shortened))
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(hubSecondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(minutes: visitMinutes))
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hubInnerSurfaceColor)
        )
    }

    private func hubEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(hubSecondaryTextColor)

            Text(title)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)

            Text(subtitle)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(hubSecondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func hubPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            action()
        }) {
            Text(title)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(hubAccentColor)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Unified Hub Data

    private var hubPeriodDisplayText: String {
        hubPeriod.rawValue
    }

    private var hubDateRange: DateInterval {
        let calendar = Calendar.current
        let now = Date()

        switch hubPeriod {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        }
    }

    private var hubVisitFetchLimit: Int {
        switch hubPeriod {
        case .today:
            return 200
        case .thisWeek:
            return 600
        case .thisMonth:
            return 1500
        }
    }

    private var hubSavedPlaces: [SavedPlace] {
        getFilteredPlaces()
    }

    private var hubVisitedPlacesByCount: [(place: SavedPlace, count: Int)] {
        var counts: [UUID: Int] = [:]
        for visit in hubPeriodVisits {
            counts[visit.savedPlaceId, default: 0] += 1
        }

        return counts
            .compactMap { entry in
                let place = locationsManager.savedPlaces.first(where: { $0.id == entry.key })
                return place.map { (place: $0, count: entry.value) }
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.place.displayName < rhs.place.displayName
                }
                return lhs.count > rhs.count
            }
    }

    private var hubPlaceCategoryBreakdown: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]

        for visit in hubPeriodVisits {
            if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                counts[place.category, default: 0] += 1
            }
        }

        if counts.isEmpty {
            for place in hubSavedPlaces {
                counts[place.category, default: 0] += 1
            }
        }

        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name < rhs.name
                }
                return lhs.count > rhs.count
            }
    }

    private var hubPeopleRelationshipBreakdown: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for person in peopleManager.people {
            counts[person.relationshipDisplayText, default: 0] += 1
        }

        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name < rhs.name
                }
                return lhs.count > rhs.count
            }
    }

    private var hubPeopleUpdatedInPeriodCount: Int {
        let range = hubDateRange
        return peopleManager.people.filter { $0.dateModified >= range.start && $0.dateModified <= range.end }.count
    }

    private var hubRecentPeople: [Person] {
        peopleManager.people.sorted { $0.dateModified > $1.dateModified }
    }

    private var hubUniqueVisitedPlacesCount: Int {
        Set(hubPeriodVisits.map { $0.savedPlaceId }).count
    }

    private var hubTotalVisitMinutes: Int {
        hubPeriodVisits.reduce(0) { partialResult, visit in
            let computedMinutes = max(visit.durationMinutes ?? Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)
            return partialResult + computedMinutes
        }
    }

    private var hubCurrentLocationSummary: String {
        if let nearbyLocation {
            if !elapsedTimeString.isEmpty {
                return "At \(nearbyLocation) · \(elapsedTimeString)"
            }
            return "At \(nearbyLocation)"
        }

        if let distanceToNearest {
            return "Nearest saved place is \(formatDistanceForSummary(distanceToNearest)) away"
        }

        return currentLocationName
    }

    private var hubBackgroundColor: Color {
        Color.appBackground(colorScheme)
    }

    private var hubCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.appSectionCard(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 2
            )
    }

    private var hubInnerSurfaceColor: Color {
        Color.appInnerSurface(colorScheme)
    }

    private var hubPrimaryTextColor: Color {
        Color.appTextPrimary(colorScheme)
    }

    private var hubSecondaryTextColor: Color {
        Color.appTextSecondary(colorScheme)
    }

    private var hubAccentColor: Color {
        colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent
    }

    private var filteredSavedPlacesForQuery: [SavedPlace] {
        let base = getFilteredPlaces()
        let query = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { place in
            place.displayName.lowercased().contains(query)
                || place.address.lowercased().contains(query)
                || place.category.lowercased().contains(query)
                || (place.city?.lowercased().contains(query) ?? false)
                || (place.province?.lowercased().contains(query) ?? false)
                || (place.country?.lowercased().contains(query) ?? false)
        }
    }

    private var savedFolderRows: [(name: String, count: Int)] {
        Dictionary(grouping: filteredSavedPlacesForQuery, by: { $0.category })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name < rhs.name
                }
                return lhs.count > rhs.count
            }
    }

    private var todayVisitCount: Int {
        let calendar = Calendar.current
        return hubPeriodVisits.filter { calendar.isDateInToday($0.entryTime) }.count
    }

    private var todayVisitMinutes: Int {
        let calendar = Calendar.current
        return hubPeriodVisits.reduce(0) { total, visit in
            guard calendar.isDateInToday(visit.entryTime) else { return total }
            let duration = max(visit.durationMinutes ?? Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)
            return total + duration
        }
    }

    private var peopleAddedThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return peopleManager.people.filter {
            calendar.isDate($0.dateModified, equalTo: now, toGranularity: .month)
        }.count
    }

    private func mapsSectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.appSurface(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 1 : 0.75),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 14,
                x: 0,
                y: 4
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private func mapsMiniMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(hubSecondaryTextColor)
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hubInnerSurfaceColor)
        )
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatDistanceForSummary(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int(distance.rounded()))m"
        }
        return String(format: "%.1fkm", distance / 1000)
    }

    private func openHubDetail(_ detail: HubDetailSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedHubDetail = detail
            isLocationSearchActive = false
            isPeopleSearchActive = false
            isSearchFocused = false
            selectedCategory = nil
        }
    }

    private func closeHubDetail() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedHubDetail = .places
            selectedCategory = nil
            isLocationSearchActive = false
            isPeopleSearchActive = false
            isSearchFocused = false
            locationSearchText = ""
        }
    }

    @MainActor
    private func refreshHubData() async {
        loadTopLocations()
        loadRecentlyVisited()
        await loadHubPeriodVisits()
    }

    @MainActor
    private func loadHubPeriodVisits() async {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            hubPeriodVisits = []
            isLoadingHubPeriodVisits = false
            return
        }

        isLoadingHubPeriodVisits = true

        let range = hubDateRange
        let fetched = await geofenceManager.fetchRecentVisits(
            userId: userId,
            since: range.start,
            limit: hubVisitFetchLimit
        )

        let filtered = fetched
            .filter { $0.entryTime >= range.start && $0.entryTime <= range.end }
            .sorted { $0.entryTime > $1.entryTime }

        hubPeriodVisits = filtered
        isLoadingHubPeriodVisits = false
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
                                .foregroundColor(Color.black.opacity(0.9))
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 0.8)
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
        return locationsManager.categories
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
        await loadHubPeriodVisits()
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
                selectedHubDetail = .places
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
            Task {
                await loadHubPeriodVisits()
            }
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
        VStack(spacing: 14) {
            savedOverviewCard

            if filteredSavedPlacesForQuery.isEmpty {
                mapsSectionCard {
                    VStack(spacing: 14) {
                        Image(systemName: "map")
                            .font(FontManager.geist(size: 34, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.5))

                        Text("No saved places yet")
                            .font(FontManager.geist(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))

                        Text("Add locations to build your map and timeline.")
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                favoritesSection
                miniMapSection
                savedFoldersSection
            }

            Spacer().frame(height: 100)
        }
        .padding(.top, 12)
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                locationsManager.addFolder(newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("Enter a name for the new folder")
        }
    }

    private var savedOverviewCard: some View {
        mapsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current location")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(hubSecondaryTextColor)
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Text(hubCurrentLocationSummary)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(hubPrimaryTextColor)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: {
                            newFolderName = ""
                            showNewFolderAlert = true
                        }) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            showSearchModal = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                HStack(spacing: 10) {
                    mapsMiniMetric(title: "Saved", value: "\(filteredSavedPlacesForQuery.count)")
                    mapsMiniMetric(title: "Favorites", value: "\(filteredSavedPlacesForQuery.filter(\.isFavourite).count)")
                    mapsMiniMetric(title: "Active today", value: "\(todayVisitCount)")
                }
            }
        }
    }

    private var savedFoldersSection: some View {
        mapsSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Folders")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }

                if savedFolderRows.isEmpty {
                    Text("No folders match this search.")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(hubSecondaryTextColor)
                        .padding(.vertical, 6)
                } else {
                    ForEach(savedFolderRows, id: \.name) { folder in
                        let isExpanded = selectedCategory == folder.name
                        let folderPlaces = filteredSavedPlacesForQuery
                            .filter { $0.category == folder.name }
                            .sorted { $0.displayName < $1.displayName }

                        Button(action: {
                            HapticManager.shared.selection()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = isExpanded ? nil : folder.name
                            }
                        }) {
                            HStack(spacing: 10) {
                                Text(folder.name)
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(hubPrimaryTextColor)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(folder.count)")
                                    .font(FontManager.geist(size: 13, weight: .semibold))
                                    .foregroundColor(hubSecondaryTextColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(hubInnerSurfaceColor)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        if isExpanded {
                            VStack(spacing: 8) {
                                if folderPlaces.isEmpty {
                                    Text("No locations in this folder")
                                        .font(FontManager.geist(size: 12, weight: .regular))
                                        .foregroundColor(hubSecondaryTextColor)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                } else {
                                    ForEach(folderPlaces, id: \.id) { place in
                                        Button(action: {
                                            selectedPlace = place
                                        }) {
                                            HStack(spacing: 10) {
                                                PlaceImageView(place: place, size: 28, cornerRadius: 8)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(place.displayName)
                                                        .font(FontManager.geist(size: 13, weight: .medium))
                                                        .foregroundColor(hubPrimaryTextColor)
                                                        .lineLimit(1)
                                                    Text(place.address)
                                                        .font(FontManager.geist(size: 11, weight: .regular))
                                                        .foregroundColor(hubSecondaryTextColor)
                                                        .lineLimit(1)
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(hubInnerSurfaceColor.opacity(colorScheme == .dark ? 0.8 : 1))
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                        }
                    }
                }
            }
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
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
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
                    .fill(Color.appSurface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 1 : 0),
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
        MiniMapView(
            places: filteredSavedPlacesForQuery,
            currentLocation: locationService.currentLocation,
            colorScheme: colorScheme,
            onPlaceTap: { place in
                selectedPlace = place
            },
            onExpandTap: {
                showFullMapView = true
            }
        )
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    @ViewBuilder
    private var recentlyVisitedSection: some View {
        if !recentlyVisitedPlaces.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Recently Visited")
                        .font(FontManager.geist(size: 17, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
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
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
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
                    .fill(Color.appSurface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 1 : 0),
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
            searchText: locationSearchText,
            isSearchActive: $isPeopleSearchActive
        )
    }

    @ViewBuilder
    private var timelineTabContent: some View {
        LocationTimelineView(colorScheme: colorScheme)
    }

    private var peopleOverviewCard: some View {
        mapsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("People")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)

                HStack(spacing: 10) {
                    mapsMiniMetric(title: "People", value: "\(peopleManager.people.count)")
                    mapsMiniMetric(title: "Favorites", value: "\(peopleManager.people.filter(\.isFavourite).count)")
                    mapsMiniMetric(title: "New month", value: "\(peopleAddedThisMonth)")
                }
            }
        }
    }

    private var timelineOverviewCard: some View {
        mapsSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timeline")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)

                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)

                HStack(spacing: 10) {
                    mapsMiniMetric(title: "Visits today", value: "\(todayVisitCount)")
                    mapsMiniMetric(title: "Saved places", value: "\(filteredSavedPlacesForQuery.count)")
                    mapsMiniMetric(title: "Time", value: formatDuration(minutes: todayVisitMinutes))
                }
            }
        }
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
                // Always include user-created folders (even if empty); skip others when empty
                if !categoryPlaces.isEmpty || locationsManager.userFolders.contains(category) {
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
                            Color.appInnerSurface(colorScheme)
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
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.appBorder(colorScheme),
                            lineWidth: 1
                        )
                )

                // Folder name below
                Text(category)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
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
            // Stable dim backdrop (avoids screenshot-capture related crashes on some devices).
            Color.black.opacity(0.45)
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
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    Spacer()

                    Button(action: { showingIconPicker = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 18, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface(colorScheme))

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
                .background(Color.appSurface(colorScheme))
            }
            .background(Color.appBackground(colorScheme))
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
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: places) { place in
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
                    Button(action: {
                        centerOnCurrentLocation()
                    }) {
                        Image(systemName: "location.fill")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(currentLocation == nil)
                    .opacity(currentLocation == nil ? 0.55 : 1.0)
                    .padding(8)

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
        } else if let firstPlace = places.first {
            // Calculate region to fit all places
            var minLat = firstPlace.latitude
            var maxLat = firstPlace.latitude
            var minLon = firstPlace.longitude
            var maxLon = firstPlace.longitude

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
        withAnimation(.easeInOut(duration: 0.25)) {
            region.center = currentLoc.coordinate
            region.span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
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
        } else if let firstPlace = places.first {
            // Calculate region to fit all places
            var minLat = firstPlace.latitude
            var maxLat = firstPlace.latitude
            var minLon = firstPlace.longitude
            var maxLon = firstPlace.longitude

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
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 22, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface(colorScheme))

                // Place info
                HStack(spacing: 12) {
                    PlaceImageView(place: place, size: 50, cornerRadius: 10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.displayName)
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text("Currently in: \(currentCategory)")
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appInnerSurface(colorScheme))
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
                                        .foregroundColor(category == currentCategory ? .blue : Color.appTextSecondary(colorScheme))

                                    Text(category)
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))

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
                                            Color.appInnerSurface(colorScheme)
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
                                    .fill(Color.appInnerSurface(colorScheme))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .background(Color.appBackground(colorScheme))
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

    var body: some View {
        VStack(spacing: 4) {
            Button(action: {
                HapticManager.shared.selection()
                onTap()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)

            Text(place.displayName)
                .font(FontManager.geist(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.75))
                )
                .allowsHitTesting(false)
        }
    }
}

struct MiniMapAnnotationView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onTap()
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
        .buttonStyle(.plain)
    }
}

#Preview {
    MapsViewNew()
}
