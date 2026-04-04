import SwiftUI
import CoreLocation
import MapKit

struct MapsViewNew: View, Searchable {
    var isVisible: Bool = true
    var bottomTabSelection: Binding<PrimaryTab>? = nil
    var showsAttachedBottomTabBar: Bool = false

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

    private enum LocationsSectionAnchor: String {
        case map
        case visits
        case saved
    }

    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var pageState = MapsPageState()
    private let locationService = LocationService.shared
    private let supabaseManager = SupabaseManager.shared
    private let peopleManager = PeopleManager.shared
    private let pageRefreshCoordinator = PageRefreshCoordinator.shared
    @StateObject private var floatingActionCoordinator = FloatingActionCoordinator.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    @State private var selectedHubDetail: HubDetailSection = .places
    @State private var hubPeriod: HubPeriod = .thisMonth
    @State private var hubPeriodVisits: [LocationVisitRecord] = []
    @State private var isLoadingHubPeriodVisits = false
    @State private var hasResolvedHubPeriodVisits = false
    @State private var selectedCategory: String? = nil
    @State private var showSearchModal = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var selectedPlaceForRating: SavedPlace? = nil
    @State private var locationSearchText: String = ""
    @State private var isLocationSearchActive: Bool = false
    @State private var isPeopleSearchActive: Bool = false
    @State private var currentLocationName: String = "Finding location..."
    @State private var nearbyLocation: String? = nil
    @State private var nearbyLocationFolder: String? = nil
    @State private var nearbyLocationPlace: SavedPlace? = nil
    @State private var distanceToNearest: Double? = nil
    @State private var currentMapLocation: CLLocation? = nil
    @State private var lastLocationCheckCoordinate: CLLocationCoordinate2D?
    @State private var hasLoadedIncompleteVisits = false  // Prevents race condition on app launch
    @StateObject private var geofenceManager = GeofenceManager.shared
    @Binding var externalSelectedFolder: String?
    @State private var topLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var selectedSavedFolder: SavedPlacesFolderSelection? = nil
    @State private var showActivePlacesSheet = false
    @State private var showAllHeroFavourites = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast  // Time debounce for location updates
    @State private var recentlyVisitedPlaces: [SavedPlace] = []
    @State private var expandedCategories: Set<String> = []  // Track which categories are expanded
    @State private var selectedCuisines: Set<String> = []  // Track selected cuisine filters
    @State private var showFullMapView = false  // Controls full map view sheet
    @State private var placeToMove: SavedPlace? = nil  // Place being moved to different folder
    @State private var showNewFolderAlert = false  // Controls new folder alert
    @State private var newFolderName = ""  // Name for the new folder
    @State private var folderToRename: String? = nil
    @State private var folderRenameDraft = ""
    @State private var folderToDelete: String? = nil
    @State private var showingFolderSidebar = false
    @State private var isSidebarOverlayVisible = false
    @State private var folderSidebarSearchText = ""
    @State private var showingRenameAlert = false  // Controls rename alert
    @State private var placeToRename: SavedPlace? = nil  // Place being renamed
    @State private var newPlaceName = ""  // New name for the place
    @FocusState private var isSearchFocused: Bool  // For search bar focus
    @Namespace private var mapsTabAnimation
    @State private var lastVisibilityRefreshAt: Date = .distantPast
    @State private var mapsRefreshTask: Task<Void, Never>?
    @State private var hubPeriodLoadTask: Task<Void, Never>?
    @State private var derivedDataRefreshTask: Task<Void, Never>?
    @State private var topLocationsLoadTask: Task<Void, Never>?
    @State private var embeddedTimelineMountTask: Task<Void, Never>?
    @State private var shouldRenderEmbeddedTimeline = false

    init(
        isVisible: Bool = true,
        externalSelectedFolder: Binding<String?> = .constant(nil),
        bottomTabSelection: Binding<PrimaryTab>? = nil,
        showsAttachedBottomTabBar: Bool = false
    ) {
        self.isVisible = isVisible
        self._externalSelectedFolder = externalSelectedFolder
        self.bottomTabSelection = bottomTabSelection
        self.showsAttachedBottomTabBar = showsAttachedBottomTabBar
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
            .sheet(item: $selectedPlaceForRating) { place in
                RatingEditorSheet(
                    place: place,
                    colorScheme: colorScheme,
                    onSave: { rating, notes, cuisine in
                        locationsManager.updateRestaurantRating(place.id, rating: rating, notes: notes, cuisine: cuisine)
                        selectedPlaceForRating = nil
                    },
                    onDismiss: {
                        selectedPlaceForRating = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBg()
            }
            .sheet(item: $selectedSavedFolder) { folder in
                SavedPlacesFolderSheet(
                    colorScheme: colorScheme,
                    folder: folder,
                    onPlaceTap: { place in
                        selectedPlace = place
                    },
                    onFolderChanged: { folderName in
                        refreshSelectedSavedFolder(named: folderName)
                    },
                    onFolderRenamed: { oldName, newName in
                        renameFolder(oldName, to: newName)
                    },
                    onFolderDeleted: { folderName in
                        deleteFolderNamed(folderName)
                    },
                    onDismiss: {
                        selectedSavedFolder = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBg()
            }
            .sheet(isPresented: $showActivePlacesSheet) {
                ActivePlacesSheet(
                    colorScheme: colorScheme,
                    title: locationsHeroHeadline,
                    subtitle: hubPeriodDisplayText,
                    places: hubActivePlaces,
                    onPlaceTap: { place in
                        showActivePlacesSheet = false
                        selectedPlace = place
                    },
                    onDismiss: {
                        showActivePlacesSheet = false
                    }
                )
                .presentationBg()
            }
            .sheet(isPresented: $showFullMapView) {
                FullMapView(
                    places: getFilteredPlaces(),
                    currentLocation: currentMapLocation,
                    colorScheme: colorScheme,
                    onPlaceTap: { place in
                        showFullMapView = false
                        selectedPlace = place
                    }
                )
                .presentationBg()
            }
            .sheet(item: $placeToMove) { place in
                ChangeFolderSheet(
                    place: place,
                    currentCategory: place.category,
                    allCategories: getAllCategories(),
                    colorScheme: colorScheme,
                    onFolderSelected: { newCategory in
                        var updatedPlace = place
                        updatedPlace.category = newCategory
                        locationsManager.updatePlace(updatedPlace)
                        placeToMove = nil
                        HapticManager.shared.success()
                    },
                    onDismiss: {
                        placeToMove = nil
                    }
                )
                .presentationBg()
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
                        let trimmedName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedPlace.customName = trimmedName.isEmpty ? nil : trimmedName
                        locationsManager.updatePlace(updatedPlace)
                        placeToRename = nil
                        newPlaceName = ""
                    }
                }
            } message: {
                Text("Enter a new name for this place")
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { folderToRename != nil },
                set: { isPresented in
                    if !isPresented {
                        folderToRename = nil
                        folderRenameDraft = ""
                    }
                }
            )) {
                TextField("Folder name", text: $folderRenameDraft)
                Button("Cancel", role: .cancel) {
                    folderToRename = nil
                    folderRenameDraft = ""
                }
                Button("Rename") {
                    if let oldName = folderToRename {
                        renameFolder(oldName, to: folderRenameDraft)
                    }
                    folderToRename = nil
                    folderRenameDraft = ""
                }
            } message: {
                Text("Enter a new name for this folder")
            }
            .confirmationDialog("Delete Folder", isPresented: Binding(
                get: { folderToDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        folderToDelete = nil
                    }
                }
            ), titleVisibility: .visible) {
                Button("Delete Folder", role: .destructive) {
                    if let folderName = folderToDelete {
                        deleteFolderNamed(folderName)
                    }
                    folderToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    folderToDelete = nil
                }
            } message: {
                if let folder = folderPendingDeleteSelection {
                    Text("Delete '\(folder.name)' and all \(folder.places.count) saved place\(folder.places.count == 1 ? "" : "s") inside it?")
                }
            }
            .task {
                // Use .task for async setup - only runs once per view lifecycle
                await setupOnAppear()
                await MainActor.run {
                    syncPageStateInputs()
                    pageRefreshCoordinator.pageBecameVisible(.maps)
                    pageRefreshCoordinator.markValidated(.maps)
                }
            }
            .onChange(of: isVisible) { newValue in
                handleVisibilityChange(newValue, reason: "visibility")
            }
            .onReceive(locationService.$currentLocation) { location in
                guard isVisible else { return }
                guard shouldApplyMapLocationUpdate(location) else { return }
                currentMapLocation = location
                handleLocationUpdate()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
                guard isVisible else {
                    pageRefreshCoordinator.markDirty([.home, .maps], reason: .visitHistoryChanged)
                    return
                }
                scheduleMapsRefresh(forceRefresh: true, refreshCurrentLocation: true, delayNanoseconds: 250_000_000)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VisitHistoryUpdated"))) { _ in
                guard isVisible else {
                    pageRefreshCoordinator.markDirty([.home, .maps], reason: .visitHistoryChanged)
                    return
                }
                scheduleMapsRefresh(forceRefresh: true, refreshCurrentLocation: true, delayNanoseconds: 250_000_000)
            }
            .onChange(of: externalSelectedFolder) { newFolder in
                handleExternalFolderSelection(newFolder)
            }
            .onChange(of: isVisible) { newValue in
                if !newValue {
                    showingFolderSidebar = false
                }
                syncFloatingActionState()
            }
            .onChange(of: scenePhase) { newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: locationsManager.savedPlaces) { _ in
                guard isVisible else {
                    pageRefreshCoordinator.markDirty(.maps, reason: .locationDataChanged)
                    return
                }
                updateCurrentLocation()
                scheduleDerivedLocationRefresh(forceRefresh: true, delayNanoseconds: 500_000_000)
            }
            .onChange(of: hubPeriod) { _ in
                syncPageStateInputs()
                guard isVisible else {
                    pageRefreshCoordinator.markDirty(.maps, reason: .manualRefresh)
                    return
                }
                scheduleHubPeriodVisitsLoad(delayNanoseconds: 120_000_000)
            }
            .onChange(of: locationSearchText) { _ in
                syncPageStateInputs()
            }
            .onChange(of: hubPeriodVisits) { _ in
                syncPageStateInputs()
            }
            .onChange(of: selectedHubDetail) { _ in
                syncFloatingActionState()
            }
            .onChange(of: isLocationSearchActive) { _ in
                syncFloatingActionState()
            }
            .onChange(of: isPeopleSearchActive) { _ in
                syncFloatingActionState()
            }
            .onChange(of: showingFolderSidebar) { _ in
                if !showingFolderSidebar {
                    folderSidebarSearchText = ""
                }
                syncFloatingActionState()
            }
            .onChange(of: isSidebarOverlayVisible) { _ in
                syncFloatingActionState()
            }
            .onChange(of: selectedCategory) { _ in
                syncFloatingActionState()
            }
            .onChange(of: colorScheme) { _ in
                // Force view refresh when system theme changes
            }
            .onAppear {
                syncFloatingActionState()
            }
            .onDisappear {
                cancelMapsTasks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mapsShellAddRequested)) { _ in
                performFloatingMapsAddAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mapsShellNewFolderRequested)) { _ in
                HapticManager.shared.selection()
                newFolderName = ""
                showNewFolderAlert = true
            }
    }
    
    // MARK: - Main Content View

    @ViewBuilder
    private func attachedBottomTabBar(bottomSafeAreaInset: CGFloat) -> some View {
        if showsAttachedBottomTabBar, let bottomTabSelection {
            SidebarAttachedBottomTabBar(
                selectedTab: bottomTabSelection,
                bottomSafeAreaInset: bottomSafeAreaInset
            )
        }
    }
    
    private var mainContentView: some View {
        GeometryReader { geometry in
            InteractiveSidebarOverlay(
                isPresented: $showingFolderSidebar,
                canOpen: isVisible && selectedCategory == nil && !isLocationSearchActive,
                sidebarWidth: min(336, geometry.size.width * 0.86),
                colorScheme: colorScheme,
                onOverlayVisibilityChanged: handleSidebarOverlayVisibilityChange
            ) {
                VStack(spacing: 0) {
                    ZStack {
                        AppAmbientBackgroundLayer(
                            colorScheme: colorScheme,
                            variant: activeAmbientVariant
                        )

                        VStack(spacing: 0) {
                            headerSection
                            mainScrollContent
                        }

                        folderOverlay
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    attachedBottomTabBar(bottomSafeAreaInset: geometry.safeAreaInsets.bottom)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } sidebarContent: {
                placesFolderSidebarContent
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            if !isLocationSearchActive {
                placesHeader
            }

            if isLocationSearchActive {
                locationSearchBar
                    .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(Color.clear)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.clear)
        .zIndex(20)
    }

    private var placesHeader: some View {
        ZStack {
            Text("Places")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            HStack(spacing: 10) {
                overviewIconActionPill(systemImage: "line.3.horizontal", accessibilityLabel: "Open folders") {
                    toggleFolderSidebar()
                }
                .frame(width: 42, height: 42)

                Spacer(minLength: 0)

                overviewIconActionPill(systemImage: "magnifyingglass", accessibilityLabel: "Search locations") {
                    activateLocationSearch()
                }
                .frame(width: 42, height: 42)
            }
        }
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
                        .contentShape(Rectangle())
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
                .overlay(
                    Capsule()
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
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
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: activeAmbientVariant,
            cornerRadius: 18,
            highlightStrength: 0.5
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
            colorScheme: colorScheme,
            variant: activeAmbientVariant
        )
    }

    private func activateLocationSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isLocationSearchActive = true
            isSearchFocused = true
            showingFolderSidebar = false
        }
    }

    // MARK: - Main Scroll Content

    private var mainScrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            locationsTabContent
        }
        .selinePrimaryPageScroll()
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

                hubCurrentLocationSummaryView(lineLimit: 1)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(hubPrimaryTextColor)

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
        let peopleCount = pageState.peopleCount
        let favouritePeopleCount = pageState.favouritePeopleCount

        return VStack(spacing: 0) {
            hubCardHeader(title: "PEOPLE", count: peopleCount)

            if peopleCount == 0 {
                hubEmptyState(
                    icon: "person.2.slash",
                    title: "No people saved",
                    subtitle: "Add people to connect them with your places"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(label: "Total", value: "\(peopleCount)")
                    hubStatPill(label: "Favorites", value: "\(favouritePeopleCount)")
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
        filteredSavedPlacesForQuery
    }

    private var hubVisitedPlacesByCount: [(place: SavedPlace, count: Int)] {
        pageState.hubVisitedPlacesByCount
    }

    private var hubPlaceCategoryBreakdown: [(name: String, count: Int)] {
        pageState.hubPlaceCategoryBreakdown
    }

    private var hubPeopleRelationshipBreakdown: [(name: String, count: Int)] {
        pageState.hubPeopleRelationshipBreakdown
    }

    private var hubPeopleUpdatedInPeriodCount: Int {
        pageState.hubPeopleUpdatedInRangeCount
    }

    private var hubRecentPeople: [Person] {
        pageState.hubRecentPeople
    }

    private var hubUniqueVisitedPlacesCount: Int {
        Set(hubPeriodVisits.map { $0.savedPlaceId }).count
    }

    private var hubRevisitedPlacesCount: Int {
        Dictionary(grouping: hubPeriodVisits, by: \.savedPlaceId)
            .values
            .filter { $0.count > 1 }
            .count
    }

    private var hubActivePlaces: [(place: SavedPlace, count: Int)] {
        hubVisitedPlacesByCount
    }

    private var hubTotalVisitMinutes: Int {
        hubPeriodVisits.reduce(0) { partialResult, visit in
            let computedMinutes = max(visit.durationMinutes ?? Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)
            return partialResult + computedMinutes
        }
    }

    private var activeNearbyVisitEntryTime: Date? {
        guard let place = nearbyLocationPlace ?? nearbyLocation.flatMap({ nearbyName in
            locationsManager.savedPlaces.first(where: { $0.displayName == nearbyName })
        }) else {
            return nil
        }

        return geofenceManager.activeVisits[place.id]?.entryTime
    }

    private func hubCurrentLocationSummary(at referenceDate: Date = Date()) -> String {
        if let nearbyLocation {
            if let entryTime = activeNearbyVisitEntryTime {
                let elapsed = max(referenceDate.timeIntervalSince(entryTime), 0)
                return "At \(nearbyLocation) · \(FormatterCache.formatElapsedTime(elapsed))"
            }
            return "At \(nearbyLocation)"
        }

        if let distanceToNearest {
            return "Nearest saved place is \(formatDistanceForSummary(distanceToNearest)) away"
        }

        return currentLocationName
    }

    @ViewBuilder
    private func hubCurrentLocationSummaryView(lineLimit: Int) -> some View {
        if nearbyLocation != nil, activeNearbyVisitEntryTime != nil {
            SwiftUI.TimelineView(.periodic(from: Date.now, by: 1)) { context in
                Text(hubCurrentLocationSummary(at: context.date))
                    .lineLimit(lineLimit)
            }
        } else {
            Text(hubCurrentLocationSummary())
                .lineLimit(lineLimit)
        }
    }

    private var hubCardBackground: some View {
        AppAmbientCardBackground(
            colorScheme: colorScheme,
            variant: activeAmbientVariant,
            cornerRadius: 16,
            highlightStrength: 0.5
        )
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

    private var activeAmbientVariant: AppAmbientBackgroundVariant {
        .topLeading
    }

    private var locationsAmbientVariant: AppAmbientBackgroundVariant {
        .topLeading
    }

    private var filteredSavedPlacesForQuery: [SavedPlace] {
        pageState.filteredSavedPlaces
    }

    private var filteredFavouritePlacesForQuery: [SavedPlace] {
        pageState.filteredFavouritePlaces
    }

    private var savedFolderBreakdownRows: [(name: String, places: [SavedPlace], favourites: Int)] {
        pageState.savedFolderBreakdownRows
    }

    private var landingMapPlaces: [SavedPlace] {
        let places = filteredSavedPlacesForQuery
        let hasSearchQuery = !locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let maxAnnotations = hasSearchQuery ? 24 : 40

        guard places.count > maxAnnotations else {
            return places
        }

        var prioritized: [SavedPlace] = []
        var seen = Set<UUID>()

        func append(_ candidates: [SavedPlace]) {
            guard prioritized.count < maxAnnotations else { return }
            for place in candidates where seen.insert(place.id).inserted {
                prioritized.append(place)
                if prioritized.count >= maxAnnotations {
                    break
                }
            }
        }

        append(hubVisitedPlacesByCount.map(\.place))
        append(filteredFavouritePlacesForQuery)
        append(places)

        return Array(prioritized.prefix(maxAnnotations))
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
        pageState.peopleAddedThisMonthCount
    }

    private func mapsSectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: locationsAmbientVariant,
                cornerRadius: 22,
                highlightStrength: 0.55
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
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 12)
    }

    private var locationsHeroCardBackground: some View {
        AppAmbientCardBackground(
            colorScheme: colorScheme,
            variant: locationsAmbientVariant,
            cornerRadius: 24,
            highlightStrength: 0.95
        )
    }

    private func mapsHeroMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 23, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private func overviewIconActionPill(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(PlainButtonStyle())
    }

    private func overviewPrimaryIconActionPill(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(.black)
                .background(
                    Circle()
                        .fill(Color(red: 0.98, green: 0.64, blue: 0.41))
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(PlainButtonStyle())
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

    private func invalidateMapsDerivedCaches() {
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.topLocations)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.recentlyVisitedPlaces)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.allLocationsRanking)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.weeklyVisitsSummary)
    }

    @MainActor
    private func refreshDerivedLocationData(forceRefresh: Bool = false) {
        if forceRefresh {
            invalidateMapsDerivedCaches()
        }

        loadTopLocations()
    }

    @MainActor
    private func refreshHubData(forceRefresh: Bool = false) async {
        refreshDerivedLocationData(forceRefresh: forceRefresh)
        await loadHubPeriodVisits()
    }

    @MainActor
    private func loadHubPeriodVisits() async {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            hubPeriodVisits = []
            isLoadingHubPeriodVisits = false
            hasResolvedHubPeriodVisits = true
            return
        }

        isLoadingHubPeriodVisits = true

        let range = hubDateRange
        let fetched = await geofenceManager.fetchRecentVisits(
            userId: userId,
            since: range.start,
            limit: hubVisitFetchLimit
        )

        guard !Task.isCancelled else {
            isLoadingHubPeriodVisits = false
            return
        }

        let filtered = fetched
            .filter { $0.entryTime >= range.start && $0.entryTime <= range.end }
            .sorted { $0.entryTime > $1.entryTime }

        hubPeriodVisits = filtered
        isLoadingHubPeriodVisits = false
        hasResolvedHubPeriodVisits = true
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
        if let category = selectedCategory,
           let folder = savedFolderSelection(for: category) {
            SavedPlacesFolderPage(
                colorScheme: colorScheme,
                folder: folder,
                onPlaceTap: { place in
                    selectedPlace = place
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                },
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                },
                onFolderRenamed: { oldName, newName in
                    renameFolder(oldName, to: newName)
                },
                onFolderDeleted: { folderName in
                    deleteFolderNamed(folderName)
                }
            )
            .zIndex(999)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func savedFolderSelection(for category: String) -> SavedPlacesFolderSelection? {
        let places = locationsManager.savedPlaces
            .filter { $0.category == category }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let isUserFolder = locationsManager.userFolders.contains(category)

        guard isUserFolder || !places.isEmpty else { return nil }

        return SavedPlacesFolderSelection(
            id: category,
            name: category,
            places: places,
            favourites: places.filter(\.isFavourite).count
        )
    }

    private func refreshSelectedSavedFolder(named folderName: String) {
        selectedSavedFolder = savedFolderSelection(for: folderName)
    }

    private func beginRenamingFolder(_ folderName: String) {
        folderToRename = folderName
        folderRenameDraft = folderName
    }

    private func beginDeletingFolder(_ folderName: String) {
        folderToDelete = folderName
    }

    private func renameFolder(_ oldName: String, to newName: String) {
        guard locationsManager.renameCategory(oldName, to: newName) else { return }

        DispatchQueue.main.async {
            if selectedCategory == oldName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = newName
                }
            }

            if selectedSavedFolder?.name == oldName {
                refreshSelectedSavedFolder(named: newName)
            }
        }
    }

    private func deleteFolderNamed(_ folderName: String) {
        locationsManager.deleteFolder(folderName)

        if selectedCategory == folderName {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = nil
            }
        }

        if selectedSavedFolder?.name == folderName {
            selectedSavedFolder = nil
        }
    }

    private var folderPendingDeleteSelection: SavedPlacesFolderSelection? {
        guard let folderToDelete else { return nil }
        return savedFolderSelection(for: folderToDelete)
    }

    @ViewBuilder
    private func folderManagementContextMenu(for folderName: String) -> some View {
        Button(action: {
            beginRenamingFolder(folderName)
        }) {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive, action: {
            beginDeletingFolder(folderName)
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Helper Functions
    
    private func getAllCategories() -> [String] {
        return locationsManager.categories
    }

    private func syncPageStateInputs() {
        pageState.updateInputs(
            searchText: locationSearchText,
            hubPeriodVisits: hubPeriodVisits,
            hubDateRange: hubDateRange
        )
    }

    private func shouldApplyMapLocationUpdate(_ location: CLLocation?) -> Bool {
        switch (currentMapLocation, location) {
        case (.none, .none):
            return false
        case (.some, .none), (.none, .some):
            return true
        case let (.some(existing), .some(next)):
            return next.distance(from: existing) >= 25
        }
    }

    @MainActor
    private func scheduleEmbeddedTimelineMountIfNeeded() {
        guard !shouldRenderEmbeddedTimeline else { return }
        embeddedTimelineMountTask?.cancel()
        embeddedTimelineMountTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            shouldRenderEmbeddedTimeline = true
        }
    }

    @MainActor
    private func scheduleDerivedLocationRefresh(forceRefresh: Bool = false, delayNanoseconds: UInt64 = 0) {
        derivedDataRefreshTask?.cancel()
        derivedDataRefreshTask = Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            refreshDerivedLocationData(forceRefresh: forceRefresh)
        }
    }

    @MainActor
    private func scheduleHubPeriodVisitsLoad(delayNanoseconds: UInt64 = 0) {
        hubPeriodLoadTask?.cancel()
        hubPeriodLoadTask = Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await loadHubPeriodVisits()
            guard !Task.isCancelled else { return }
            pageRefreshCoordinator.markValidated(.maps)
        }
    }

    @MainActor
    private func scheduleMapsRefresh(
        forceRefresh: Bool,
        refreshCurrentLocation: Bool = false,
        delayNanoseconds: UInt64 = 0
    ) {
        mapsRefreshTask?.cancel()
        hubPeriodLoadTask?.cancel()
        derivedDataRefreshTask?.cancel()
        mapsRefreshTask = Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            if refreshCurrentLocation {
                updateCurrentLocation()
            }
            await refreshHubData(forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            pageRefreshCoordinator.markValidated(.maps)
        }
    }

    @MainActor
    private func cancelMapsTasks() {
        mapsRefreshTask?.cancel()
        hubPeriodLoadTask?.cancel()
        derivedDataRefreshTask?.cancel()
        topLocationsLoadTask?.cancel()
        embeddedTimelineMountTask?.cancel()
    }
    
    private func setupOnAppear() async {
        SearchService.shared.registerSearchableProvider(self)

        // CLEANUP: Auto-close any incomplete visits older than 3 hours in Supabase (background)
        Task.detached(priority: .utility) {
            await geofenceManager.cleanupIncompleteVisitsInSupabase(olderThanMinutes: 180)
        }

        // Load incomplete visits from Supabase to resume tracking BEFORE checking location
        await geofenceManager.loadIncompleteVisitsFromSupabase()
        await MainActor.run {
            updateCurrentLocation()
            hasLoadedIncompleteVisits = true
            scheduleEmbeddedTimelineMountIfNeeded()
        }

        // Load only the data used by the current landing page.
        if allLocations.isEmpty {
            await MainActor.run {
                scheduleDerivedLocationRefresh()
            }
        }
        
        locationService.requestLocationPermission()
        await MainActor.run {
            currentMapLocation = locationService.currentLocation
            syncPageStateInputs()
            scheduleHubPeriodVisitsLoad()
        }
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
                showingFolderSidebar = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                externalSelectedFolder = nil
            }
        }
    }

    @MainActor
    private func performLightweightVisibleRefresh() {
        let now = Date()
        if now.timeIntervalSince(lastVisibilityRefreshAt) >= 1.0 {
            lastVisibilityRefreshAt = now
            updateCurrentLocation()
        }
    }

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard isVisible else {
            return
        }

        if newPhase == .active {
            pageRefreshCoordinator.pageBecameVisible(.maps)
            performLightweightVisibleRefresh()
            scheduleEmbeddedTimelineMountIfNeeded()
            if pageRefreshCoordinator.isDirty(.maps) {
                scheduleMapsRefresh(forceRefresh: false, delayNanoseconds: 120_000_000)
            }
            if let currentLoc = locationService.currentLocation {
                Task {
                    await geofenceManager.autoCompleteVisitsIfOutOfRange(
                        currentLocation: currentLoc,
                        savedPlaces: locationsManager.savedPlaces
                    )
                }
            }
        }
    }

    @MainActor
    private func handleVisibilityChange(_ visible: Bool, reason: String) {
        guard visible else {
            cancelMapsTasks()
            return
        }

        syncPageStateInputs()
        pageRefreshCoordinator.pageBecameVisible(.maps)
        performLightweightVisibleRefresh()
        scheduleEmbeddedTimelineMountIfNeeded()

        if pageRefreshCoordinator.isDirty(.maps) {
            scheduleMapsRefresh(forceRefresh: false, delayNanoseconds: 120_000_000)
        }
    }

    @ViewBuilder
    private var locationsTabContent: some View {
        LazyVStack(spacing: 14) {
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
                locationsMapCutoutSection
                    .id(LocationsSectionAnchor.map.rawValue)
            }

            if shouldRenderEmbeddedTimeline {
                LocationTimelineView(
                    colorScheme: colorScheme,
                    displayMode: .embedded,
                    isActive: isVisible
                )
            } else {
                mapsSectionCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.appTextSecondary(colorScheme))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Loading timeline")
                                .font(FontManager.geist(size: 15, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))

                            Text("Visits will appear once the map settles.")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    private var locationVisitCountsByPlaceId: [UUID: Int] {
        if !allLocations.isEmpty {
            return Dictionary(uniqueKeysWithValues: allLocations.map { ($0.id, $0.visitCount) })
        }

        return Dictionary(uniqueKeysWithValues: hubVisitedPlacesByCount.map { ($0.place.id, $0.count) })
    }

    private var locationRankedPlaces: [(place: SavedPlace, count: Int)] {
        if !hubVisitedPlacesByCount.isEmpty {
            return Array(hubVisitedPlacesByCount.prefix(3))
        }

        if !allLocations.isEmpty {
            return Array(allLocations.prefix(3)).compactMap { item in
                locationsManager.savedPlaces.first(where: { $0.id == item.id }).map { place in
                    (place: place, count: item.visitCount)
                }
            }
        }

        return Array(filteredSavedPlacesForQuery.prefix(3)).map { place in
            (place: place, count: locationVisitCountsByPlaceId[place.id] ?? 0)
        }
    }

    private var locationsHeroPeriodPhrase: String {
        hubPeriodDisplayText.lowercased()
    }

    private var locationsHeroPeriodLeadIn: String {
        switch hubPeriod {
        case .today:
            return "Today"
        case .thisWeek:
            return "This week"
        case .thisMonth:
            return "This month"
        }
    }

    private var locationsHeroHeadline: String {
        guard hasResolvedHubPeriodVisits else {
            return "Your movement \(locationsHeroPeriodPhrase)"
        }

        let count = max(hubUniqueVisitedPlacesCount, 0)
        guard count > 0 else {
            return "No saved-place visits \(locationsHeroPeriodPhrase)"
        }

        return "\(count) active place\(count == 1 ? "" : "s") \(locationsHeroPeriodPhrase)"
    }

    private var locationsHeroDominantTimeWindow: String? {
        guard !hubPeriodVisits.isEmpty else { return nil }

        var buckets: [String: Int] = [:]
        let calendar = Calendar.current

        for visit in hubPeriodVisits {
            let hour = calendar.component(.hour, from: visit.entryTime)
            let bucket: String
            switch hour {
            case 5..<12:
                bucket = "morning"
            case 12..<17:
                bucket = "afternoon"
            case 17..<22:
                bucket = "evening"
            default:
                bucket = "late hours"
            }
            buckets[bucket, default: 0] += 1
        }

        guard let dominant = buckets.max(by: { $0.value < $1.value }) else { return nil }
        return dominant.value >= max(2, hubPeriodVisits.count / 3) ? dominant.key : nil
    }

    private var locationsHeroSupportingText: String {
        guard hasResolvedHubPeriodVisits else {
            return "Pulling together your visit patterns for \(locationsHeroPeriodPhrase)."
        }

        guard !filteredSavedPlacesForQuery.isEmpty else {
            return "Add places to build a cleaner map, movement history, and timeline."
        }

        guard !hubPeriodVisits.isEmpty else {
            return "No saved-place visits have landed for \(locationsHeroPeriodPhrase) yet, so your map is ready for the next stop."
        }

        let uniqueText = "\(hubUniqueVisitedPlacesCount) unique stop\(hubUniqueVisitedPlacesCount == 1 ? "" : "s")"
        let commonNames = hubVisitedPlacesByCount.prefix(3).map(\.place.displayName)
        let commonText = commonNames.isEmpty ? nil : "Most common: \(commonNames.joined(separator: ", "))."
        let revisitText = hubRevisitedPlacesCount > 0
            ? "\(hubRevisitedPlacesCount) revisited."
            : nil
        let timeText = locationsHeroDominantTimeWindow.map { "Mostly \($0)." }

        return [uniqueText + ".", commonText, revisitText, timeText]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private var movementHeadlineText: String {
        guard hasResolvedHubPeriodVisits else {
            return "Loading your \(hubPeriodDisplayText.lowercased()) movement"
        }

        if hubPeriodVisits.isEmpty {
            return "No tracked movement \(hubPeriodDisplayText.lowercased())"
        }

        return "\(hubPeriodVisits.count) visit\(hubPeriodVisits.count == 1 ? "" : "s") in \(hubPeriodDisplayText.lowercased())"
    }

    private var movementSupportingText: String {
        guard hasResolvedHubPeriodVisits else {
            return "We are stitching together your saved-place timeline."
        }

        if hubPeriodVisits.isEmpty {
            return "Once saved-place visits land, this section will summarize where your time actually went."
        }

        let topPlace = hubVisitedPlacesByCount.first?.place.displayName
        let lead = topPlace.map { "Most active at \($0)." }
        let revisit = hubRevisitedPlacesCount > 0 ? "\(hubRevisitedPlacesCount) revisited place\(hubRevisitedPlacesCount == 1 ? "" : "s")." : nil
        let duration = hubTotalVisitMinutes > 0 ? "\(formatDuration(minutes: hubTotalVisitMinutes)) tracked in total." : nil

        return [lead, revisit, duration]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private var locationsHeroFavouritePlaces: [SavedPlace] {
        filteredFavouritePlacesForQuery
            .sorted { lhs, rhs in
                let lhsCount = hubVisitedPlacesByCount.first(where: { $0.place.id == lhs.id })?.count ?? locationVisitCountsByPlaceId[lhs.id] ?? 0
                let rhsCount = hubVisitedPlacesByCount.first(where: { $0.place.id == rhs.id })?.count ?? locationVisitCountsByPlaceId[rhs.id] ?? 0

                if lhsCount == rhsCount {
                    return lhs.displayName < rhs.displayName
                }

                return lhsCount > rhsCount
            }
    }

    private var displayedHeroFavouritePlaces: [SavedPlace] {
        if showAllHeroFavourites {
            return locationsHeroFavouritePlaces
        }

        return Array(locationsHeroFavouritePlaces.prefix(2))
    }

    private func locationsHeroFavouriteSubtitle(for place: SavedPlace) -> String {
        let periodCount = hubVisitedPlacesByCount.first(where: { $0.place.id == place.id })?.count ?? 0
        if periodCount > 0 {
            return "\(periodCount) visit\(periodCount == 1 ? "" : "s") \(locationsHeroPeriodPhrase)"
        }
        return place.category
    }

    private func locationsHeroCard() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LOCATIONS")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(1.1)

            Button(action: {
                guard hasResolvedHubPeriodVisits, !hubActivePlaces.isEmpty else { return }
                HapticManager.shared.selection()
                showActivePlacesSheet = true
            }) {
                Text(locationsHeroHeadline)
                    .font(FontManager.geist(size: 29, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Text(locationsHeroSupportingText)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                locationsHeroSummaryMetric(
                    title: hubPeriodDisplayText,
                    value: "\(hubPeriodVisits.count)",
                    detail: "Visits"
                )
                locationsHeroSummaryMetric(
                    title: "Tracked",
                    value: formatDuration(minutes: hubTotalVisitMinutes),
                    detail: "Time"
                )
            }

            if !locationsHeroFavouritePlaces.isEmpty {
                embeddedFavouritesOverview
            }
        }
        .padding(20)
        .background(locationsHeroCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 16,
            x: 0,
            y: 6
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private func locationsHeroSummaryMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 22, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(detail)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appInnerSurface(colorScheme))
        )
    }

    private var locationsMapCutoutSection: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.appSectionCard(colorScheme))

            MiniMapView(
                places: landingMapPlaces,
                currentLocation: currentMapLocation,
                colorScheme: colorScheme,
                showsExpandControl: false,
                onPlaceTap: { place in
                    selectedPlace = place
                },
                onExpandTap: {
                    showFullMapView = true
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(8)

            Button(action: {
                showFullMapView = true
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.appChip(colorScheme))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 10)
            .padding(.trailing, 10)

            VStack {
                Spacer()
                HStack {
                    Text("MAP")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18))
                        )

                    Spacer()
                }
                .padding(.leading, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 208)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 16,
            x: 0,
            y: 6
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    @ViewBuilder
    private var locationsTopPlacesSection: some View {
        if !locationRankedPlaces.isEmpty || !filteredFavouritePlacesForQuery.isEmpty {
            mapsSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top places")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    if !locationRankedPlaces.isEmpty {
                        VStack(spacing: 0) {
                            let maxCount = locationRankedPlaces.first?.count ?? 1

                            ForEach(Array(locationRankedPlaces.enumerated()), id: \.element.place.id) { index, item in
                                locationsTopPlaceRow(item.place, rank: index + 1, count: item.count, maxCount: maxCount)

                                if index < locationRankedPlaces.count - 1 {
                                    Divider()
                                        .overlay(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.65 : 1))
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.appInnerSurface(colorScheme))
                        )
                    }

                }
            }
        }
    }

    private func locationsTopPlaceRow(_ place: SavedPlace, rank: Int, count: Int, maxCount: Int) -> some View {
        Button(action: {
            selectedPlace = place
        }) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", rank))
                    .font(FontManager.geist(size: 20, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.6))
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.displayName)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)

                    Text(place.category)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(count)")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.appChip(colorScheme))

                            Capsule()
                                .fill(Color.appTextPrimary(colorScheme).opacity(colorScheme == .dark ? 0.4 : 0.18))
                                .frame(width: max(10, geometry.size.width * (CGFloat(count) / CGFloat(max(maxCount, 1)))))
                        }
                    }
                    .frame(width: 58, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var locationsSavedPlacesSection: some View {
        mapsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Saved places")
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text("Folders")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(1.0)

                if savedFolderBreakdownRows.isEmpty {
                    Text("Create folders to group the places you save here.")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(savedFolderBreakdownRows.enumerated()), id: \.element.name) { index, folder in
                            locationsSavedFolderRow(folder)

                            if index < savedFolderBreakdownRows.count - 1 {
                                Divider()
                                    .overlay(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.65 : 1))
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.appInnerSurface(colorScheme))
                    )
                }
            }
        }
    }

    private func locationsSavedFolderRow(_ folder: (name: String, places: [SavedPlace], favourites: Int)) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            selectedSavedFolder = savedFolderSelection(for: folder.name)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appChip(colorScheme))
                        .frame(width: 36, height: 36)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)

                    Text(folderMeta(for: folder))
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            folderManagementContextMenu(for: folder.name)
        }
    }

    private func folderMeta(for folder: (name: String, places: [SavedPlace], favourites: Int)) -> String {
        let placeCount = folder.places.count
        let placesText = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        guard folder.favourites > 0 else {
            return placesText
        }
        return "\(placesText) • \(folder.favourites) favourite\(folder.favourites == 1 ? "" : "s")"
    }

    private var savedOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    hubCurrentLocationSummaryView(lineLimit: 2)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    overviewIconActionPill(systemImage: "folder.badge.plus", accessibilityLabel: "Create folder") {
                        newFolderName = ""
                        showNewFolderAlert = true
                    }
                }
            }

            HStack(spacing: 10) {
                mapsHeroMetricTile(title: "Saved", value: "\(filteredSavedPlacesForQuery.count)")
                mapsHeroMetricTile(title: "Favourites", value: "\(filteredFavouritePlacesForQuery.count)")
                mapsHeroMetricTile(title: "Active today", value: "\(todayVisitCount)")
            }

            if !filteredFavouritePlacesForQuery.isEmpty {
                embeddedFavouritesOverview
            }
        }
        .padding(16)
        .background(locationsHeroCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 16,
            x: 0,
            y: 6
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private var placesFolderSidebarContent: some View {
        ZStack {
            placesSidebarBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35))

                        TextField("Search", text: $folderSidebarSearchText)
                            .textFieldStyle(.plain)
                            .font(FontManager.geist(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(placesSidebarSearchFieldFillColor)
                    )

                    Button(action: {
                        HapticManager.shared.buttonTap()
                        newFolderName = ""
                        showNewFolderAlert = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New folder")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(placesSidebarBackgroundColor)
                .frame(maxWidth: .infinity)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if !isFolderSidebarSearching {
                            VStack(alignment: .leading, spacing: 2) {
                                placesSidebarSectionLabel("BROWSE")

                                placesSidebarBrowseRow(
                                    title: "All Places",
                                    countText: "\(filteredSavedPlacesForQuery.count)",
                                    isSelected: true
                                ) {
                                    HapticManager.shared.selection()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingFolderSidebar = false
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            placesSidebarSectionLabel("FOLDERS")

                            if filteredFolderSidebarRows.isEmpty {
                                if isFolderSidebarSearching {
                                    VStack(spacing: 8) {
                                        Text("No folders found")
                                            .font(FontManager.geist(size: 15, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                                        Text("Try another search term")
                                            .font(FontManager.geist(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 12)
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 36, weight: .light))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2))

                                        Text("No folders yet")
                                            .font(FontManager.geist(size: 15, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))

                                        Text("Create a folder to organize your saved places.")
                                            .font(FontManager.geist(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 32)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                                }
                            } else {
                                ForEach(filteredFolderSidebarRows, id: \.name) { folder in
                                    placesSidebarBrowseRow(
                                        title: folder.name,
                                        countText: "\(folder.places.count)",
                                        isSelected: false
                                    ) {
                                        openFolderCategory(folder.name)
                                    }
                                    .contextMenu {
                                        folderManagementContextMenu(for: folder.name)
                                    }
                                }
                            }
                        }

                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(placesSidebarBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placesSidebarBackgroundColor: Color {
        colorScheme == .dark ? Color.black : .white
    }

    private var placesSidebarSearchFieldFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var placesSidebarSectionLabelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.40)
    }

    private var isFolderSidebarSearching: Bool {
        !folderSidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredFolderSidebarRows: [(name: String, places: [SavedPlace], favourites: Int)] {
        let query = folderSidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return savedFolderBreakdownRows }
        return savedFolderBreakdownRows.filter { $0.name.lowercased().contains(query) }
    }

    private func placesSidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(FontManager.geist(size: 11, weight: .medium))
            .foregroundColor(placesSidebarSectionLabelColor)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    private func placesSidebarBrowseRow(
        title: String,
        countText: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: title == "All Places" ? "mappin.and.ellipse" : "folder")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                    .frame(width: 22)

                Text(title)
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))

                Spacer()

                if let countText {
                    Text(countText)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055))
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placesFolderSidebarButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appChip(colorScheme))
                        .frame(width: 36, height: 36)

                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(FontManager.geist(size: 17, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var floatingActionMode: MapsFloatingActionMode {
        .places
    }

    private func syncFloatingActionState() {
        floatingActionCoordinator.updateMaps(
            isVisible: !isSidebarOverlayVisible,
            mode: floatingActionMode
        )
    }

    private func handleSidebarOverlayVisibilityChange(_ isVisible: Bool) {
        guard isSidebarOverlayVisible != isVisible else { return }
        isSidebarOverlayVisible = isVisible
    }

    private func performFloatingMapsAddAction() {
        HapticManager.shared.selection()
        showSearchModal = true
    }

    private func toggleFolderSidebar() {
        HapticManager.shared.selection()
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            showingFolderSidebar.toggle()
        }
    }

    private func openFolderCategory(_ category: String) {
        HapticManager.shared.selection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedCategory = category
            showingFolderSidebar = false
            isLocationSearchActive = false
            isSearchFocused = false
        }
    }

    private var embeddedFavouritesOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label("Favourites", systemImage: "star.fill")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Spacer(minLength: 8)

                Text("\(filteredFavouritePlacesForQuery.count)")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(Color.appChip(colorScheme))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                    )

                if locationsHeroFavouritePlaces.count > 2 {
                    Button(action: {
                        HapticManager.shared.selection()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAllHeroFavourites.toggle()
                        }
                    }) {
                        Image(systemName: showAllHeroFavourites ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.appChip(colorScheme))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            VStack(spacing: 8) {
                ForEach(displayedHeroFavouritePlaces, id: \.id) { place in
                    Button(action: {
                        selectedPlace = place
                    }) {
                        HStack(spacing: 10) {
                            PlaceImageView(place: place, size: 40, cornerRadius: 12)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.displayName)
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                    .lineLimit(1)

                                Text(locationsHeroFavouriteSubtitle(for: place))
                                    .font(FontManager.geist(size: 10, weight: .medium))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.homeGlassAccent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 14)
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
        }
    }

    @ViewBuilder
    private var miniMapSection: some View {
        MiniMapView(
            places: landingMapPlaces,
            currentLocation: currentMapLocation,
            colorScheme: colorScheme,
            showsExpandControl: true,
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
                        currentLocation: currentMapLocation,
                        onPlaceTap: { place in
                            selectedPlace = place
                        },
                        onRatingTap: { place in
                            selectedPlaceForRating = place
                        },
                        onMoveToFolder: { place in
                            placeToMove = place
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
                    mapsMiniMetric(title: "People", value: "\(pageState.peopleCount)")
                    mapsMiniMetric(title: "Favorites", value: "\(pageState.favouritePeopleCount)")
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
        currentMapLocation = locationService.currentLocation
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
        }
    }

    private func loadTopLocations() {
        topLocationsLoadTask?.cancel()
        topLocationsLoadTask = Task {
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
                    guard !Task.isCancelled else { return }
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

            guard !Task.isCancelled else { return }
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

    // Filter places based on location search text
    private func getFilteredPlaces() -> [SavedPlace] {
        pageState.filteredSavedPlaces
    }
    
    private func getPlacesForSuperCategory(_ superCategory: LocationSuperCategory) -> [String: [SavedPlace]] {
        pageState.groupedPlaces(for: superCategory)
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
    @State private var selectedPlaceForDetail: SavedPlace? = nil
    @State private var selectedPlace: SavedPlace? = nil
    @State private var newPlaceName = ""
    @State private var showingIconPicker = false
    @State private var selectedIcon: String? = nil
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
                                                    selectedPlaceForDetail = place
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
        .sheet(item: $selectedPlaceForDetail) { place in
            PlaceDetailSheet(place: place, onDismiss: {
                selectedPlaceForDetail = nil
            })
            .presentationBg()
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
        .sheet(item: $placeToMove) { place in
            ChangeFolderSheet(
                place: place,
                currentCategory: place.category,
                allCategories: Array(Set(locationsManager.savedPlaces.map { $0.category })).sorted(),
                colorScheme: colorScheme,
                onFolderSelected: { newCategory in
                    var updatedPlace = place
                    updatedPlace.category = newCategory
                    locationsManager.updatePlace(updatedPlace)
                    placeToMove = nil
                    HapticManager.shared.success()
                },
                onDismiss: {
                    placeToMove = nil
                }
            )
            .presentationBg()
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
    let showsExpandControl: Bool
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

            VStack {
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

                    if showsExpandControl {
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
                    } else {
                        Spacer()
                            .frame(width: 36)
                            .padding(8)
                    }
                }
                Spacer()
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

private struct SavedPlacesFolderSelection: Identifiable {
    let id: String
    let name: String
    let places: [SavedPlace]
    let favourites: Int
}

private struct SavedPlacesFolderSheet: View {
    let colorScheme: ColorScheme
    let folder: SavedPlacesFolderSelection
    let onPlaceTap: (SavedPlace) -> Void
    let onFolderChanged: (String) -> Void
    let onFolderRenamed: (String, String) -> Void
    let onFolderDeleted: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationsManager = LocationsManager.shared
    @State private var selectedPlace: SavedPlace? = nil
    @State private var showingRenamePlaceAlert = false
    @State private var showingDeletePlaceConfirm = false
    @State private var showingFolderActions = false
    @State private var showingRenameFolderAlert = false
    @State private var showingDeleteFolderConfirm = false
    @State private var newPlaceName = ""
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder.name)
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text(folderMetaText)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }

                    Spacer()

                    Button(action: {
                        showingFolderActions = true
                    }) {
                        Image(systemName: "ellipsis.circle")
                            .font(FontManager.geist(size: 18, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 18, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface(colorScheme))

                if folder.places.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(FontManager.geist(size: 40, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))

                        Text("No saved places in this folder")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(folder.places.enumerated()), id: \.element.id) { index, place in
                                Button(action: {
                                    onPlaceTap(place)
                                    close()
                                }) {
                                    HStack(spacing: 12) {
                                        PlaceImageView(place: place, size: 38, cornerRadius: 12)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(place.displayName)
                                                    .font(FontManager.geist(size: 14, weight: .medium))
                                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                                    .lineLimit(1)

                                                if place.isFavourite {
                                                    Image(systemName: "bookmark.fill")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(Color(red: 0.98, green: 0.64, blue: 0.41))
                                                }
                                            }

                                            Text(place.address)
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.8))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(action: {
                                        selectedPlace = place
                                        newPlaceName = place.customName ?? place.name
                                        showingRenamePlaceAlert = true
                                    }) {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive, action: {
                                        selectedPlace = place
                                        showingDeletePlaceConfirm = true
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                                if index < folder.places.count - 1 {
                                    Divider()
                                        .overlay(Color.appBorder(colorScheme))
                                        .padding(.leading, 66)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.appSectionCard(colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Color.appBackground(colorScheme))
            .navigationBarHidden(true)
        }
        .confirmationDialog("Folder Actions", isPresented: $showingFolderActions, titleVisibility: .visible) {
            Button("Rename Folder") {
                newFolderName = folder.name
                showingRenameFolderAlert = true
            }

            Button("Delete Folder", role: .destructive) {
                showingDeleteFolderConfirm = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Folder", isPresented: $showingRenameFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Rename") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onFolderRenamed(folder.name, trimmed)
                newFolderName = ""
            }
        } message: {
            Text("Enter a new name for this folder")
        }
        .confirmationDialog("Delete Folder", isPresented: $showingDeleteFolderConfirm, titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) {
                onFolderDeleted(folder.name)
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete '\(folder.name)' and all \(folder.places.count) saved place\(folder.places.count == 1 ? "" : "s") inside it?")
        }
        .alert("Rename Place", isPresented: $showingRenamePlaceAlert) {
            TextField("Place name", text: $newPlaceName)
            Button("Cancel", role: .cancel) {
                selectedPlace = nil
                newPlaceName = ""
            }
            Button("Rename") {
                if let place = selectedPlace {
                    var updatedPlace = place
                    let trimmedName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedPlace.customName = trimmedName.isEmpty ? nil : trimmedName
                    locationsManager.updatePlace(updatedPlace)
                    DispatchQueue.main.async {
                        onFolderChanged(folder.name)
                    }
                    selectedPlace = nil
                    newPlaceName = ""
                }
            }
        } message: {
            Text("Enter a new name for this place")
        }
        .confirmationDialog("Delete Place", isPresented: $showingDeletePlaceConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let place = selectedPlace {
                    locationsManager.deletePlace(place)
                    DispatchQueue.main.async {
                        onFolderChanged(folder.name)
                    }
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

    private var folderMetaText: String {
        let placeCount = folder.places.count
        let placesText = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        guard folder.favourites > 0 else { return placesText }
        return "\(placesText) • \(folder.favourites) favourite\(folder.favourites == 1 ? "" : "s")"
    }

    private func close() {
        onDismiss()
        dismiss()
    }
}

private struct SavedPlacesFolderPage: View {
    let colorScheme: ColorScheme
    let folder: SavedPlacesFolderSelection
    let onPlaceTap: (SavedPlace) -> Void
    let onDismiss: () -> Void
    let onFolderRenamed: (String, String) -> Void
    let onFolderDeleted: (String) -> Void

    @StateObject private var locationsManager = LocationsManager.shared
    @State private var selectedPlace: SavedPlace? = nil
    @State private var showingFolderActions = false
    @State private var showingRenameFolderAlert = false
    @State private var showingDeleteFolderConfirm = false
    @State private var showingRenamePlaceAlert = false
    @State private var showingDeletePlaceConfirm = false
    @State private var newFolderName = ""
    @State private var newPlaceName = ""

    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .topLeading)

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        summaryCard

                        if folder.places.isEmpty {
                            emptyStateCard
                        } else {
                            placesCard
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .selinePrimaryPageScroll()
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .confirmationDialog("Folder Actions", isPresented: $showingFolderActions, titleVisibility: .visible) {
            Button("Rename Folder") {
                newFolderName = folder.name
                showingRenameFolderAlert = true
            }

            Button("Delete Folder", role: .destructive) {
                showingDeleteFolderConfirm = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Folder", isPresented: $showingRenameFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Rename") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onFolderRenamed(folder.name, trimmed)
                newFolderName = ""
            }
        } message: {
            Text("Enter a new name for this folder")
        }
        .confirmationDialog("Delete Folder", isPresented: $showingDeleteFolderConfirm, titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) {
                onFolderDeleted(folder.name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete '\(folder.name)' and all \(folder.places.count) saved place\(folder.places.count == 1 ? "" : "s") inside it?")
        }
        .alert("Rename Place", isPresented: $showingRenamePlaceAlert) {
            TextField("Place name", text: $newPlaceName)
            Button("Cancel", role: .cancel) {
                selectedPlace = nil
                newPlaceName = ""
            }
            Button("Rename") {
                if let place = selectedPlace {
                    var updatedPlace = place
                    let trimmedName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedPlace.customName = trimmedName.isEmpty ? nil : trimmedName
                    locationsManager.updatePlace(updatedPlace)
                    selectedPlace = nil
                    newPlaceName = ""
                }
            }
        } message: {
            Text("Enter a new name for this place")
        }
        .confirmationDialog("Delete Place", isPresented: $showingDeletePlaceConfirm, titleVisibility: .visible) {
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

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.appChip(colorScheme))
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text(folder.name)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: {
                showingFolderActions = true
            }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.appBackground(colorScheme).opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOLDER")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(1.1)

            Text(folder.name)
                .font(FontManager.geist(size: 28, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(2)

            Text(folderMetaText)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            HStack(spacing: 10) {
                folderMetric(title: "Places", value: "\(folder.places.count)")
                folderMetric(title: "Favorites", value: "\(folder.favourites)")
            }
        }
        .padding(20)
        .background(
            AppAmbientCardBackground(
                colorScheme: colorScheme,
                variant: .topLeading,
                cornerRadius: 24,
                highlightStrength: 0.84
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(FontManager.geist(size: 40, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            Text("No saved places in this folder")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appSectionCard(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private var placesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(folder.places.enumerated()), id: \.element.id) { index, place in
                Button(action: { onPlaceTap(place) }) {
                    HStack(spacing: 12) {
                        PlaceImageView(place: place, size: 42, cornerRadius: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(place.displayName)
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                    .lineLimit(1)

                                if place.isFavourite {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color.homeGlassAccent)
                                }
                            }

                            Text(place.address)
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(action: {
                        selectedPlace = place
                        newPlaceName = place.customName ?? place.name
                        showingRenamePlaceAlert = true
                    }) {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: {
                        selectedPlace = place
                        showingDeletePlaceConfirm = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if index < folder.places.count - 1 {
                    Divider()
                        .overlay(Color.appBorder(colorScheme))
                        .padding(.leading, 70)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appSectionCard(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private var folderMetaText: String {
        let placeCount = folder.places.count
        let placesText = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        guard folder.favourites > 0 else { return placesText }
        return "\(placesText) • \(folder.favourites) favourite\(folder.favourites == 1 ? "" : "s")"
    }

    private func folderMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            Text(value)
                .font(FontManager.geist(size: 20, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appInnerSurface(colorScheme))
        )
    }
}

struct ActivePlacesSheet: View {
    let colorScheme: ColorScheme
    let title: String
    let subtitle: String
    let places: [(place: SavedPlace, count: Int)]
    let onPlaceTap: (SavedPlace) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text(subtitle)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }

                    Spacer()

                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 18, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.appSurface(colorScheme))

                if places.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(FontManager.geist(size: 40, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))

                        Text("No active places yet")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            let maxCount = places.first?.count ?? 1

                            ForEach(Array(places.enumerated()), id: \.element.place.id) { index, item in
                                Button(action: {
                                    onPlaceTap(item.place)
                                    close()
                                }) {
                                    HStack(spacing: 12) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(FontManager.geist(size: 18, weight: .semibold))
                                            .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.7))
                                            .frame(width: 28, alignment: .leading)

                                        PlaceImageView(place: item.place, size: 38, cornerRadius: 12)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.place.displayName)
                                                .font(FontManager.geist(size: 14, weight: .semibold))
                                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                                .lineLimit(1)

                                            Text(item.place.category)
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 12)

                                        VStack(alignment: .trailing, spacing: 5) {
                                            Text("\(item.count)")
                                                .font(FontManager.geist(size: 18, weight: .semibold))
                                                .foregroundColor(Color.appTextPrimary(colorScheme))

                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.appChip(colorScheme))

                                                    Capsule()
                                                        .fill(Color.appTextPrimary(colorScheme).opacity(colorScheme == .dark ? 0.4 : 0.18))
                                                        .frame(width: max(10, geometry.size.width * (CGFloat(item.count) / CGFloat(max(maxCount, 1)))))
                                                }
                                            }
                                            .frame(width: 58, height: 6)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if index < places.count - 1 {
                                    Divider()
                                        .overlay(Color.appBorder(colorScheme))
                                        .padding(.leading, 70)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.appSectionCard(colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Color.appBackground(colorScheme))
            .navigationBarHidden(true)
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }
}

#Preview {
    MapsViewNew()
}
