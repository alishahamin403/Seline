import SwiftUI
import CoreLocation

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var geofenceManager = GeofenceManager.shared
    @StateObject private var searchService = SearchService.shared
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
    @State private var showingNewNoteSheet = false
    @State private var showingAddEventPopup = false
    @State private var searchText = ""
    @State private var searchResults: [OverlaySearchResult] = []  // Cache search results instead of computing every time
    @State private var searchSelectedNote: Note? = nil
    @State private var searchSelectedEmail: Email? = nil
    @State private var searchSelectedTask: TaskItem? = nil
    @State private var searchSelectedLocation: SavedPlace? = nil
    @State private var searchSelectedFolder: String? = nil
    @State private var showingEditTask = false
    @State private var notificationEmailId: String? = nil
    @State private var notificationTaskId: String? = nil
    @FocusState private var isSearchFocused: Bool
    @State private var showConversationModal = false
    @State private var showReceiptStats = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil  // Track debounce task
    @State private var currentLocationName: String = "Finding location..."
    @State private var nearbyLocation: String? = nil
    @State private var nearbyLocationFolder: String? = nil
    @State private var nearbyLocationPlace: SavedPlace? = nil
    @State private var distanceToNearest: Double? = nil
    @State private var elapsedTimeString: String = ""
    @State private var updateTimer: Timer?
    @State private var lastLocationCheckCoordinate: CLLocationCoordinate2D?
    @State private var hasLoadedIncompleteVisits = false
    @State private var topLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var showAllLocationsSheet = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast
    @State private var showingLocationPlaceDetail = false
    @State private var selectedLocationPlace: SavedPlace? = nil

    private var unreadEmailCount: Int {
        emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private var todayTaskCount: Int {
        return taskManager.getTasksForToday().count
    }

    private var pinnedNotesCount: Int {
        return notesManager.pinnedNotes.count
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatEventDateAndTime(targetDate: Date?, scheduledTime: Date?) -> String {
        guard let targetDate = targetDate else { return "No date set" }
        guard let scheduledTime = scheduledTime else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: targetDate)
        }

        // Combine targetDate (the actual date) with scheduledTime (the time component)
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
        if let combinedDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                minute: timeComponents.minute ?? 0,
                                                second: timeComponents.second ?? 0,
                                                of: targetDate) {
            return formatDateAndTime(combinedDateTime)
        }
        return formatDateAndTime(targetDate)
    }

    /// Compute search results (called with debounce, not on every render)
    private func performSearchComputation() -> [OverlaySearchResult] {
        guard !searchText.isEmpty else {
            return []
        }

        // If there's a pending action (event or note creation), show action UI instead
        if searchService.pendingEventCreation != nil {
            return []
        }
        if searchService.pendingNoteCreation != nil {
            return []
        }
        if searchService.pendingNoteUpdate != nil {
            return []
        }

        var results: [OverlaySearchResult] = []
        let lowercasedSearch = searchText.lowercased()

        // Search tasks/events - use cached flattened tasks
        let allTasks = taskManager.getAllFlattenedTasks()
        let matchingTasks = allTasks.filter {
            $0.title.lowercased().contains(lowercasedSearch)
        }

        // Deduplicate: for each unique title, keep only ONE result
        var tasksByTitle: [String: [TaskItem]] = [:]

        for task in matchingTasks {
            let titleLower = task.title.lowercased()
            if tasksByTitle[titleLower] == nil {
                tasksByTitle[titleLower] = []
            }
            tasksByTitle[titleLower]?.append(task)
        }

        var deduplicatedTasks: [TaskItem] = []
        let today = Calendar.current.startOfDay(for: Date())

        for (_, tasks) in tasksByTitle {
            var bestTask: TaskItem?
            var bestTaskDate: Date?

            for task in tasks {
                let taskDate = task.targetDate ?? task.createdAt

                if task.isRecurring {
                    let taskStartDate = Calendar.current.startOfDay(for: taskDate)
                    if taskStartDate < today {
                        continue
                    }
                }

                if bestTask == nil {
                    bestTask = task
                    bestTaskDate = taskDate
                } else if let best = bestTaskDate, taskDate < best {
                    bestTask = task
                    bestTaskDate = taskDate
                }
            }

            if let best = bestTask {
                deduplicatedTasks.append(best)
            }
        }

        for task in deduplicatedTasks.prefix(5) {
            results.append(OverlaySearchResult(
                type: .event,
                title: task.title,
                subtitle: formatEventDateAndTime(targetDate: task.targetDate, scheduledTime: task.scheduledTime),
                icon: "calendar",
                task: task,
                email: nil,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Search emails
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        let matchingEmails = allEmails.filter {
            $0.subject.lowercased().contains(lowercasedSearch) ||
            $0.sender.displayName.lowercased().contains(lowercasedSearch) ||
            $0.snippet.lowercased().contains(lowercasedSearch)
        }

        for email in matchingEmails.prefix(5) {
            results.append(OverlaySearchResult(
                type: .email,
                title: email.subject,
                subtitle: "from \(email.sender.displayName)",
                icon: "envelope",
                task: nil,
                email: email,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Search notes
        let matchingNotes = notesManager.notes.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.content.lowercased().contains(lowercasedSearch)
        }

        for note in matchingNotes.prefix(5) {
            results.append(OverlaySearchResult(
                type: .note,
                title: note.title,
                subtitle: note.formattedDateModified,
                icon: "note.text",
                task: nil,
                email: nil,
                note: note,
                location: nil,
                category: nil
            ))
        }

        // Search locations
        let locationsManager = LocationsManager.shared
        let matchingLocations = locationsManager.savedPlaces.filter {
            $0.name.lowercased().contains(lowercasedSearch) ||
            $0.address.lowercased().contains(lowercasedSearch) ||
            ($0.customName?.lowercased().contains(lowercasedSearch) ?? false)
        }

        for location in matchingLocations.prefix(5) {
            results.append(OverlaySearchResult(
                type: .location,
                title: location.displayName,
                subtitle: location.address,
                icon: "mappin.circle.fill",
                task: nil,
                email: nil,
                note: nil,
                location: location,
                category: nil
            ))
        }

        return results
    }

    // MARK: - Helper Methods for onChange Consolidation

    private func activateConversationModalIfNeeded() {
        if (searchService.pendingEventCreation != nil ||
            searchService.pendingNoteCreation != nil ||
            searchService.pendingNoteUpdate != nil) &&
           !searchService.isInConversationMode {
            searchService.isInConversationMode = true
        }
    }

    private func handleDeepLinkAction(type: String) {
        switch type {
        case "noteCreation":
            showingNewNoteSheet = true
        case "eventCreation":
            showingAddEventPopup = true
        case "receiptStats":
            showReceiptStats = true
        case "search":
            isSearchFocused = true
        case "chat":
            showConversationModal = true
        default:
            break
        }
        resetDeepLinkFlags(type)
    }

    private func resetDeepLinkFlags(_ type: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch type {
            case "noteCreation":
                deepLinkHandler.shouldShowNoteCreation = false
            case "eventCreation":
                deepLinkHandler.shouldShowEventCreation = false
            case "receiptStats":
                deepLinkHandler.shouldShowReceiptStats = false
            case "search":
                deepLinkHandler.shouldShowSearch = false
            case "chat":
                deepLinkHandler.shouldShowChat = false
            case "maps":
                deepLinkHandler.shouldOpenMaps = false
            default:
                break
            }
        }
    }

    private func computeSearchResults() {
        searchResults = performSearchComputation()
    }

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
            print("🏠 HOME PAGE updateCurrentLocation - locationName: \(locationService.locationName)")

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
            // Only clear nearby location data if location is nil
            // But don't immediately set "Location not available" - keep "Finding location..."
            if currentLocationName != "Finding location..." {
                currentLocationName = "Location not available"
            }
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

    private func handleSearchResultTap(_ result: OverlaySearchResult) {
        HapticManager.shared.selection()

        switch result.type {
        case .note:
            if let note = result.note {
                searchSelectedNote = note
            }
        case .email:
            if let email = result.email {
                searchSelectedEmail = email
            }
        case .event:
            if let task = result.task {
                searchSelectedTask = task
            }
        case .location:
            if let location = result.location {
                GoogleMapsService.shared.openInGoogleMaps(place: location)
            }
            // Dismiss search for locations
            isSearchFocused = false
            searchText = ""
            return
        case .folder:
            if let category = result.category {
                selectedTab = .maps
                searchSelectedFolder = category
            }
        }

        // Dismiss search after setting the state
        isSearchFocused = false
        searchText = ""
    }

    var body: some View {
        mainContent
            .onChange(of: searchText) { newValue in
                // OPTIMIZATION: Debounce search computation with 300ms delay
                // Cancel previous debounce task if any
                searchDebounceTask?.cancel()

                if newValue.isEmpty {
                    searchService.cancelAction()
                    searchResults = []
                } else {
                    // Create a new debounced task on background thread
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        if !Task.isCancelled {
                            DispatchQueue.global(qos: .userInitiated).async {
                                let results = self.performSearchComputation()
                                DispatchQueue.main.async {
                                    self.searchResults = results
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: searchService.pendingEventCreation) { _ in
                activateConversationModalIfNeeded()
            }
            .onChange(of: searchService.pendingNoteCreation) { _ in
                activateConversationModalIfNeeded()
            }
            .onChange(of: searchService.pendingNoteUpdate) { _ in
                activateConversationModalIfNeeded()
            }
            .onChange(of: searchService.isInConversationMode) { newValue in
                showConversationModal = newValue
            }
            .onChange(of: deepLinkHandler.shouldShowNoteCreation) { newValue in
                if newValue { handleDeepLinkAction(type: "noteCreation") }
            }
            .onChange(of: deepLinkHandler.shouldShowEventCreation) { newValue in
                if newValue { handleDeepLinkAction(type: "eventCreation") }
            }
            .onChange(of: deepLinkHandler.shouldShowReceiptStats) { newValue in
                if newValue { handleDeepLinkAction(type: "receiptStats") }
            }
            .onChange(of: deepLinkHandler.shouldShowSearch) { newValue in
                if newValue { handleDeepLinkAction(type: "search") }
            }
            .onChange(of: deepLinkHandler.shouldShowChat) { newValue in
                if newValue { handleDeepLinkAction(type: "chat") }
            }
            .onChange(of: deepLinkHandler.shouldOpenMaps) { newValue in
                if newValue {
                    if let lat = deepLinkHandler.mapsLatitude, let lon = deepLinkHandler.mapsLongitude {
                        let mapsURL = URL(string: "https://maps.google.com/?q=\(lat),\(lon)")!
                        UIApplication.shared.open(mapsURL)
                    }
                    resetDeepLinkFlags("maps")
                }
            }
            .fullScreenCover(isPresented: $showConversationModal) {
                ConversationSearchView()
            }
    }

    private var mainContent: some View {
        mainContentBase
            .onAppear {
                taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                // Check if there's a pending deep link action (e.g., from widget)
                deepLinkHandler.processPendingAction()

                // CLEANUP: Auto-close any incomplete visits older than 3 hours in Supabase
                // This fixes visits that got stuck before the auto-cleanup code was added
                Task {
                    await geofenceManager.cleanupIncompleteVisitsInSupabase(olderThanMinutes: 180)
                }

                // Request location permissions with a slight delay to ensure system is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        locationService.requestLocationPermission()

                        // Request background location permission for visit tracking
                        // setupGeofences will be called after authorization is granted in GeofenceManager.locationManagerDidChangeAuthorization
                        geofenceManager.requestLocationPermission()
                    } catch {
                        print("⚠️ Error requesting location permissions: \(error)")
                    }
                }

                // Load incomplete visits from Supabase to resume tracking BEFORE checking location
                // This prevents race condition where updateCurrentLocation() creates a new visit
                // before the async load completes
                Task {
                    await geofenceManager.loadIncompleteVisitsFromSupabase()
                    // Now that previous sessions are restored, signal we're ready for location updates
                    await MainActor.run {
                        // Signal that we've loaded incomplete visits and can now respond to location changes
                        hasLoadedIncompleteVisits = true
                    }
                }

                // Load top 3 locations by visit count
                loadTopLocations()
                // Calendar sync is handled in SelineApp.swift via didBecomeActiveNotification
            }
            .onReceive(locationService.$currentLocation) { _ in
                print("🏠 HOME PAGE onReceive fired - hasLoadedIncompleteVisits: \(hasLoadedIncompleteVisits), locationName: \(locationService.locationName)")
                // TIME DEBOUNCE: Skip updates that occur within 2 seconds of last update
                // This prevents excessive location processing and improves performance
                let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime)
                if timeSinceLastUpdate >= 2.0 {
                    lastLocationUpdateTime = Date()
                    updateCurrentLocation()
                }
            }
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
            .onDisappear {
                stopLocationTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    keyboardHeight = keyboardFrame.cgRectValue.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToEmail)) { notification in
                handleEmailNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToTask)) { notification in
                handleTaskNotification(notification)
            }
            .fullScreenCover(item: $selectedNoteToOpen) { note in
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { selectedNoteToOpen != nil },
                    set: { if !$0 { selectedNoteToOpen = nil } }
                ))
            }
            .sheet(isPresented: $showingNewNoteSheet) {
                NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBg()
            }
            .sheet(item: $searchSelectedNote) { note in
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { searchSelectedNote != nil },
                    set: { if !$0 { searchSelectedNote = nil } }
                ))
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBg()
            }
            .sheet(isPresented: $authManager.showLocationSetup) {
                LocationSetupView()
                    .presentationBg()
            }
            .sheet(isPresented: $authManager.showLabelSelection) {
                GmailLabelSelectionView()
                    .presentationBg()
            }
            .sheet(item: $searchSelectedEmail) { email in
                EmailDetailView(email: email)
                    .presentationBg()
            }
            .sheet(item: $searchSelectedTask) { task in
                if showingEditTask {
                    NavigationView {
                        EditTaskView(
                            task: task,
                            onSave: { updatedTask in
                                taskManager.editTask(updatedTask)
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onCancel: {
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                searchSelectedTask = nil
                                showingEditTask = false
                            }
                        )
                    }
                } else {
                    NavigationView {
                        ViewEventView(
                            task: task,
                            onEdit: {
                                showingEditTask = true
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                searchSelectedTask = nil
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                searchSelectedTask = nil
                            }
                        )
                    }
                }
            }
            .onChange(of: searchSelectedTask) { newValue in
                if newValue != nil {
                    showingEditTask = false
                } else {
                    showingEditTask = false
                }
            }
            .sheet(isPresented: $showingAddEventPopup) {
                AddEventPopupView(
                    isPresented: $showingAddEventPopup,
                    onSave: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                        let calendar = Calendar.current
                        let weekdayIndex = calendar.component(.weekday, from: date)

                        let weekday: WeekDay
                        switch weekdayIndex {
                        case 1: weekday = .sunday
                        case 2: weekday = .monday
                        case 3: weekday = .tuesday
                        case 4: weekday = .wednesday
                        case 5: weekday = .thursday
                        case 6: weekday = .friday
                        case 7: weekday = .saturday
                        default: weekday = .monday
                        }

                        taskManager.addTask(
                            title: title,
                            to: weekday,
                            description: description,
                            scheduledTime: time,
                            endTime: endTime,
                            targetDate: date,
                            reminderTime: reminder,
                            isRecurring: recurring,
                            recurrenceFrequency: frequency,
                            tagId: tagId
                        )
                    }
                )
                .presentationBg()
            }
            .sheet(isPresented: $showReceiptStats) {
                ReceiptStatsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBg()
            }
            .sheet(isPresented: $showAllLocationsSheet) {
                AllVisitsSheet(
                    allLocations: $allLocations,
                    isPresented: $showAllLocationsSheet,
                    onLocationTap: { locationId in
                        // Find the SavedPlace with this UUID
                        if let place = locationsManager.savedPlaces.first(where: { $0.id == locationId }) {
                            selectedLocationPlace = place
                            showingLocationPlaceDetail = true
                        }
                    }
                )
                .presentationBg()
            }
            .sheet(isPresented: $showingLocationPlaceDetail) {
                if let place = selectedLocationPlace {
                    PlaceDetailSheet(place: place, onDismiss: { showingLocationPlaceDetail = false }, isFromRanking: false)
                        .presentationBg()
                }
            }
    }

    private var mainContentBase: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                mainContentVStack(geometry: geometry)

                // Fixed Header with search bar at top (only on home tab)
                if selectedTab == .home {
                    mainContentHeader
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }

    private func mainContentVStack(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Padding to account for fixed header (only on home tab)
            if selectedTab == .home {
                Color.clear.frame(height: 48)
            }

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .home:
                    homeContentWithoutHeader
                        .onAppear {
                            Task {
                                await emailService.loadEmailsForFolder(.inbox)
                            }
                        }
                case .email:
                    EmailView()
                case .events:
                    EventsView()
                case .notes:
                    NotesView()
                case .maps:
                    MapsViewNew(externalSelectedFolder: $searchSelectedFolder)
                }
            }
            .frame(maxHeight: .infinity)

            // Fixed Footer - hide when keyboard appears or any sheet is open or viewing note in navigation
            if keyboardHeight == 0 && selectedNoteToOpen == nil && !showingNewNoteSheet && searchSelectedNote == nil && searchSelectedEmail == nil && searchSelectedTask == nil && !authManager.showLocationSetup && !notesManager.isViewingNoteInNavigation {
                BottomTabBar(selectedTab: $selectedTab)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private var mainContentHeader: some View {
        VStack(spacing: 0) {
            HeaderSection(
                selectedTab: $selectedTab,
                searchText: $searchText,
                isSearchFocused: $isSearchFocused,
                onSearchSubmit: {
                    Task {
                        await searchService.performSearch(query: searchText)
                    }
                },
                onNewConversation: {
                    HapticManager.shared.selection()
                    searchService.clearConversation()
                    Task {
                        searchService.conversationHistory = []
                        searchService.conversationTitle = "New Conversation"
                        searchService.isInConversationMode = true
                    }
                }
            )
            .padding(.bottom, 8)
            .background(colorScheme == .dark ? Color.black : Color.white)

            // Search results or question response
            if !searchText.isEmpty && !searchService.isInConversationMode {
                if let response = searchService.questionResponse {
                    questionResponseView(response)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                } else if !searchResults.isEmpty {
                    searchResultsDropdown
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                } else if searchService.isLoadingQuestionResponse {
                    loadingQuestionView
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .zIndex(100)
    }


    // MARK: - Detail Content

    // Generate an icon based on sender email or name (same logic as EmailRow)
    private func emailIcon(for email: Email) -> String? {
        let senderEmail = email.sender.email.lowercased()
        let senderName = (email.sender.name ?? "").lowercased()
        let sender = senderEmail + " " + senderName

        // Financial/Investing
        if sender.contains("wealthsimple") || sender.contains("robinhood") ||
           sender.contains("questrade") || sender.contains("tdameritrade") ||
           sender.contains("etrade") || sender.contains("fidelity") {
            return "chart.line.uptrend.xyaxis"
        }

        // Banking
        if sender.contains("bank") || sender.contains("chase") || sender.contains("cibc") ||
           sender.contains("rbc") || sender.contains("td") || sender.contains("bmo") ||
           sender.contains("scotiabank") || sender.contains("wellsfargo") ||
           sender.contains("amex") || sender.contains("americanexpress") ||
           sender.contains("american express") {
            return "dollarsign.circle.fill"
        }

        // Shopping/Retail
        if sender.contains("amazon") || sender.contains("ebay") || sender.contains("walmart") ||
           sender.contains("target") || sender.contains("bestbuy") || sender.contains("shopify") ||
           sender.contains("etsy") || sender.contains("aliexpress") {
            return "bag.fill"
        }

        // Travel/Airlines
        if sender.contains("airline") || sender.contains("flight") || sender.contains("expedia") ||
           sender.contains("airbnb") || sender.contains("booking") || sender.contains("hotels") ||
           sender.contains("delta") || sender.contains("united") || sender.contains("aircanada") {
            return "airplane"
        }

        // Food Delivery
        if sender.contains("uber") && sender.contains("eats") || sender.contains("doordash") ||
           sender.contains("grubhub") || sender.contains("skipthedishes") ||
           sender.contains("postmates") || sender.contains("deliveroo") {
            return "fork.knife"
        }

        // Ride Share/Transportation
        if sender.contains("uber") || sender.contains("lyft") || sender.contains("taxi") {
            return "car.fill"
        }

        // Tech/Development
        if sender.contains("github") || sender.contains("gitlab") || sender.contains("bitbucket") {
            return "chevron.left.forwardslash.chevron.right"
        }

        // Social Media - Camera apps
        if sender.contains("snapchat") || sender.contains("instagram") {
            return "camera.fill"
        }

        // Facebook
        if sender.contains("facebook") || sender.contains("meta") {
            return "person.2.fill"
        }

        // LinkedIn
        if sender.contains("linkedin") {
            return "briefcase.fill"
        }

        // Twitter/X
        if sender.contains("twitter") || sender.contains("x.com") {
            return "bubble.left.and.bubble.right.fill"
        }

        // TikTok
        if sender.contains("tiktok") {
            return "music.note"
        }

        // YouTube
        if sender.contains("youtube") {
            return "play.rectangle.fill"
        }

        // Discord
        if sender.contains("discord") {
            return "message.fill"
        }

        // Reddit
        if sender.contains("reddit") {
            return "text.bubble.fill"
        }

        // Google
        if sender.contains("google") || sender.contains("gmail") && !sender.contains("@gmail.com") {
            return "magnifyingglass"
        }

        // Apple
        if sender.contains("apple") || sender.contains("icloud") && !sender.contains("@icloud.com") {
            return "apple.logo"
        }

        // Microsoft
        if sender.contains("microsoft") || sender.contains("outlook") && !sender.contains("@outlook.com") ||
           sender.contains("office365") || sender.contains("teams") {
            return "square.grid.2x2.fill"
        }

        // Amazon
        if sender.contains("amazon") && !sender.contains("shopping") {
            return "shippingbox.fill"
        }

        // Netflix
        if sender.contains("netflix") {
            return "play.tv.fill"
        }

        // Spotify
        if sender.contains("spotify") {
            return "music.note.list"
        }

        // Slack
        if sender.contains("slack") {
            return "number"
        }

        // Zoom
        if sender.contains("zoom") {
            return "video.fill"
        }

        // Dropbox
        if sender.contains("dropbox") {
            return "folder.fill"
        }

        // PayPal/Venmo
        if sender.contains("paypal") || sender.contains("venmo") {
            return "dollarsign.square.fill"
        }

        // Security/Notifications
        if sender.contains("noreply") || sender.contains("no-reply") ||
           sender.contains("notification") || sender.contains("alert") {
            return "bell.fill"
        }

        // Healthcare
        if sender.contains("health") || sender.contains("medical") || sender.contains("doctor") ||
           sender.contains("clinic") || sender.contains("hospital") {
            return "heart.fill"
        }

        // Calendar/Events
        if sender.contains("calendar") || sender.contains("eventbrite") || sender.contains("meetup") {
            return "calendar"
        }

        // Check if it's a personal email (common personal email domains)
        let personalDomains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com",
                              "icloud.com", "me.com", "aol.com", "protonmail.com"]
        if personalDomains.contains(where: { senderEmail.contains($0) }) {
            return "person.fill"
        }

        // Default to company/building icon for business emails
        return "building.2.fill"
    }

    // Email avatar color based on sender email (Google brand colors)
    private func emailAvatarColor(for email: Email) -> Color {
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),  // Google Blue #4285F4
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),  // Google Red #EA4335
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),  // Google Yellow #FBBC04
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),  // Google Green #34A853
        ]

        // Generate deterministic color based on sender email using stable hash
        let hash = HashUtils.deterministicHash(email.sender.email)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }

    private var emailDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let unreadEmails = emailService.inboxEmails.filter { !$0.isRead }.prefix(5)

            if unreadEmails.isEmpty {
                Text("No unread emails")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(Array(unreadEmails.enumerated()), id: \.element.id) { index, email in
                    Button(action: {
                        HapticManager.shared.email()
                        searchSelectedEmail = email
                    }) {
                        HStack(spacing: 8) {
                            // Avatar circle with colored background and icon
                            Circle()
                                .fill(emailAvatarColor(for: email))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(email.subject)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text("from \(email.sender.displayName)")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if emailService.inboxEmails.filter({ !$0.isRead }).count > 5 {
                    Button(action: {
                        selectedTab = .email
                    }) {
                        Text("... and \(emailService.inboxEmails.filter { !$0.isRead }.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var eventsDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let todayTasks = taskManager.getTasksForToday()

            if todayTasks.isEmpty {
                Text("No events today")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(todayTasks.prefix(5)) { task in
                    Button(action: {
                        HapticManager.shared.calendar()
                        selectedTab = .events
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(task.isCompleted ?
                                    (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color.black) :
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                )

                            Text(task.title)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .strikethrough(task.isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            if let scheduledTime = task.scheduledTime {
                                Text(formatTime(scheduledTime))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if todayTasks.count > 5 {
                    Button(action: {
                        selectedTab = .events
                    }) {
                        Text("... and \(todayTasks.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var notesDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let pinnedNotes = notesManager.pinnedNotes

            if pinnedNotes.isEmpty {
                Text("No pinned notes")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(pinnedNotes.prefix(5)) { note in
                    Button(action: {
                        HapticManager.shared.cardTap()
                        selectedNoteToOpen = note
                    }) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Text(note.formattedDateModified)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if pinnedNotes.count > 5 {
                    Button(action: {
                        selectedTab = .notes
                    }) {
                        Text("... and \(pinnedNotes.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Notification Handlers

    private func handleEmailNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let emailId = userInfo["emailId"] as? String else {
            // No specific email ID, just navigate to email tab
            selectedTab = .email
            return
        }

        // Find the email and show it
        if let email = emailService.inboxEmails.first(where: { $0.id == emailId }) {
            selectedTab = .email
            // Delay slightly to ensure tab is switched before showing email detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedEmail = email
            }
        } else {
            // Email not found, just navigate to email tab
            selectedTab = .email
        }
    }

    private func handleTaskNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo["taskId"] as? String else {
            // No specific task ID, just navigate to events tab
            selectedTab = .events
            return
        }

        // Find the task by searching through all weekdays
        var foundTask: TaskItem? = nil
        for (_, tasks) in taskManager.tasks {
            if let task = tasks.first(where: { $0.id == taskId }) {
                foundTask = task
                break
            }
        }

        if let task = foundTask {
            selectedTab = .events
            // Delay slightly to ensure tab is switched before showing task detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedTask = task
                showingEditTask = false // Show in read mode
            }
        } else {
            // Task not found, just navigate to events tab
            selectedTab = .events
        }
    }

    // MARK: - Search Bar Components

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            TextField("Search or ask for actions...", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    // Perform search when user taps search button
                    if !searchText.isEmpty {
                        Task {
                            await searchService.performSearch(query: searchText)
                        }
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
    }

    private var searchResultsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if searchResults.isEmpty {
                        Text("No results found")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(searchResults) { result in
                            searchResultRow(for: result)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 300)
        }
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func searchResultRow(for result: OverlaySearchResult) -> some View {
        Button(action: {
            handleSearchResultTap(result)
        }) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: result.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .frame(width: 24)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Type badge
                Text(result.type.rawValue.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.05)
                    )
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark ?
                    Color.white.opacity(0.03) :
                    Color.black.opacity(0.02)
            )
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var searchBarContainer: some View {
        VStack(spacing: 0) {
            searchBarView

            if !searchText.isEmpty {
                searchResultsDropdown
            }
        }
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(!searchText.isEmpty ? 0.15 : 0.05), radius: !searchText.isEmpty ? 12 : 4, x: 0, y: !searchText.isEmpty ? 6 : 2)
        .padding(.horizontal, 12)
        .zIndex(100)
    }

    private var mainContentWidgets: some View {
        VStack(spacing: 6) {
            // Spending + ETA widget - replaces weather widget
            SpendingAndETAWidget(isVisible: selectedTab == .home)
                .padding(.horizontal, 12)

            // Current Location card
            CurrentLocationCardWidget(
                currentLocationName: currentLocationName,
                nearbyLocation: nearbyLocation,
                nearbyLocationFolder: nearbyLocationFolder,
                nearbyLocationPlace: nearbyLocationPlace,
                distanceToNearest: distanceToNearest,
                elapsedTimeString: elapsedTimeString,
                topLocations: topLocations,
                selectedPlace: $selectedLocationPlace,
                showingPlaceDetail: $showingLocationPlaceDetail,
                showAllLocationsSheet: $showAllLocationsSheet
            )
            .padding(.horizontal, 12)

            // Events card - expands to fill available space
            EventsCardWidget(showingAddEventPopup: $showingAddEventPopup)
                .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }


    // MARK: - Home Content
    private var homeContentWithoutHeader: some View {
        ZStack(alignment: .top) {
            mainContentWidgets
                .opacity(searchText.isEmpty ? 1 : 0.3)

            // Overlay to dismiss search when tapping outside
            if !searchText.isEmpty {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = false
                        searchText = ""
                    }
            }
        }
        .background(
            colorScheme == .dark ?
                Color.black : Color.white
        )
    }

    // MARK: - Question Response View

    private func questionResponseView(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render markdown response with proper formatting
            MarkdownText(markdown: response, colorScheme: colorScheme)
        }
        .padding(12)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private var loadingQuestionView: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8, anchor: .center)

                Text("Thinking...")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}