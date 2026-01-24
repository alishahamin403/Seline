import SwiftUI
import CoreLocation
import WidgetKit

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
    @StateObject private var widgetManager = WidgetManager.shared
    @StateObject private var locationSuggestionService = LocationSuggestionService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
    @State private var showingNewNoteSheet = false
    @State private var showingAddEventPopup = false
    @State private var searchText = ""
    @State private var isDailyOverviewExpanded = false
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
    @Namespace private var noteTransitionNamespace
    @State private var showReceiptStats = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil  // Track debounce task
    // OPTIMIZATION: Cache flattened tasks to avoid recomputing on every search
    @State private var cachedFlattenedTasks: [TaskItem] = []
    @State private var lastCacheUpdate: Date = .distantPast
    @State private var currentLocationName: String = "Finding location..."
    @State private var nearbyLocation: String? = nil
    @State private var nearbyLocationFolder: String? = nil
    @State private var nearbyLocationPlace: SavedPlace? = nil
    @State private var distanceToNearest: Double? = nil
    @State private var elapsedTimeString: String = ""
    @State private var updateTimer: Timer?
    @State private var lastLocationCheckCoordinate: CLLocationCoordinate2D?
    @State private var hasLoadedIncompleteVisits = false
    @State private var todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] = []
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var showAllLocationsSheet = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast
    @State private var selectedLocationPlace: SavedPlace? = nil
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var showingSettings = false
    @State private var profilePictureUrl: String? = nil
    @State private var hasAppeared = false
    @State private var dismissedVisitReasonIds: Set<UUID> = [] // Track visits where user dismissed the reason popup

    private var unreadEmailCount: Int {
        emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private var todayTaskCount: Int {
        return taskManager.getTasksForToday().count
    }

    private var pinnedNotesCount: Int {
        return notesManager.pinnedNotes.count
    }

    /// Returns the current active visit and place if user is at a saved location and should see the visit reason popup
    private var currentActiveVisitForReasonPopup: (visit: LocationVisitRecord, place: SavedPlace)? {
        guard let place = nearbyLocationPlace,
              let visit = geofenceManager.getActiveVisit(for: place.id),
              // Only show if visit doesn't already have notes
              (visit.visitNotes ?? "").isEmpty,
              // Only show if user hasn't dismissed this visit's popup
              !dismissedVisitReasonIds.contains(visit.id) else {
            return nil
        }
        return (visit, place)
    }

    private var isAnySheetPresented: Bool {
        showingNewNoteSheet || searchSelectedNote != nil || authManager.showLocationSetup ||
        authManager.showLabelSelection || searchSelectedEmail != nil || searchSelectedTask != nil ||
        showingAddEventPopup || showReceiptStats || showAllLocationsSheet || selectedLocationPlace != nil
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

        // OPTIMIZATION: Use cached flattened tasks, refresh every 30 seconds
        let cacheAge = Date().timeIntervalSince(lastCacheUpdate)
        let allTasks: [TaskItem]
        if cacheAge > 30 || cachedFlattenedTasks.isEmpty {
            allTasks = taskManager.getAllFlattenedTasks()
            cachedFlattenedTasks = allTasks
            lastCacheUpdate = Date()
        } else {
            allTasks = cachedFlattenedTasks
        }
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

        // Search receipts (from Receipts folder notes)
        let receiptStatistics = notesManager.getReceiptStatistics()
        let allReceipts = receiptStatistics.flatMap { yearSummary in
            yearSummary.monthlySummaries.flatMap { $0.receipts }
        }
        
        let matchingReceipts = allReceipts.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.category.lowercased().contains(lowercasedSearch)
        }
        
        for receipt in matchingReceipts.prefix(5) {
            // Find the note for this receipt
            if let note = notesManager.notes.first(where: { $0.id == receipt.noteId }) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let dateString = dateFormatter.string(from: receipt.date)
                
                results.append(OverlaySearchResult(
                    type: .receipt,
                    title: receipt.title,
                    subtitle: "\(CurrencyParser.formatAmount(receipt.amount)) • \(dateString)",
                    icon: "doc.text",
                    task: nil,
                    email: nil,
                    note: note,
                    location: nil,
                    category: receipt.category
                ))
            }
        }
        
        // Search recurring expenses (from cache - will be empty if not loaded yet)
        if let cachedExpenses: [RecurringExpense] = CacheManager.shared.get(forKey: CacheManager.CacheKey.allRecurringExpenses) {
            let matchingExpenses = cachedExpenses.filter {
                $0.title.lowercased().contains(lowercasedSearch) ||
                ($0.category?.lowercased().contains(lowercasedSearch) ?? false) ||
                ($0.description?.lowercased().contains(lowercasedSearch) ?? false)
            }
            
            for expense in matchingExpenses.prefix(5) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let nextDateString = dateFormatter.string(from: expense.nextOccurrence)
                
                results.append(OverlaySearchResult(
                    type: .recurringExpense,
                    title: expense.title,
                    subtitle: "\(expense.formattedAmount) • Next: \(nextDateString)",
                    icon: "repeat.circle",
                    task: nil,
                    email: nil,
                    note: nil,
                    location: nil,
                    category: expense.category
                ))
            }
        }

        return results
    }

    // MARK: - Helper Methods for onChange Consolidation

    private func activateConversationModalIfNeeded() {
        // Navigate to chat tab if there's a pending action
        if (searchService.pendingEventCreation != nil ||
            searchService.pendingNoteCreation != nil ||
            searchService.pendingNoteUpdate != nil) &&
           !searchService.isInConversationMode {
            searchService.isInConversationMode = true
            selectedTab = .email
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
            selectedTab = .email // Navigate to email tab which now has chat
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
            // Always update the location name first
            currentLocationName = locationService.locationName

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
                        updateElapsedTime() // Immediately update widget data
                        print("✅ Entered geofence: \(place.displayName) (Folder: \(place.category))")
                    }

                    // If already in geofence but no active visit record, create one
                    // (handles case where user was already at location when app launched)
                    // IMPORTANT: Only create if we've already loaded incomplete visits to avoid duplicate visits on app restart
                    if geofenceManager.activeVisits[place.id] == nil && hasLoadedIncompleteVisits {
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

                        // Immediately update widget data
                        updateElapsedTime()

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

    private func loadTodaysVisits() {
        Task {
            // CRITICAL: Force cache invalidation to ensure fresh active visit data
            // This is especially important when called from GeofenceVisitCreated notification
            CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysVisits)

            // Get today's visits with duration for each location
            let visits = await LocationVisitAnalytics.shared.getTodaysVisitsWithDuration()

            // Also load all locations with visit counts for "See All" feature
            var placesWithCounts: [(id: UUID, displayName: String, visitCount: Int)] = []

            for place in locationsManager.savedPlaces {
                await LocationVisitAnalytics.shared.fetchStats(for: place.id)

                if let stats = LocationVisitAnalytics.shared.visitStats[place.id] {
                    placesWithCounts.append((
                        id: place.id,
                        displayName: place.displayName,
                        visitCount: stats.totalVisits
                    ))
                }
            }

            let allSorted = placesWithCounts.sorted { $0.visitCount > $1.visitCount }

            await MainActor.run {
                todaysVisits = visits
                allLocations = allSorted  // Store all locations for "See All" feature
            }
        }
    }

    private func updateElapsedTime() {
        // Get the active visit entry time for the current location from GeofenceManager
        // This uses REAL geofence entry time, not artificial tracking
        // CRITICAL: Check geofenceManager.activeVisits FIRST (most accurate, real-time)
        // This ensures widget updates match calendar view accuracy
        
        // Find any active visit from geofence manager
        var activePlace: SavedPlace? = nil
        var activeVisit: LocationVisitRecord? = nil
        
        // First try to find from nearbyLocation if set
        if let nearbyLoc = nearbyLocation,
           let place = locationsManager.savedPlaces.first(where: { $0.displayName == nearbyLoc }),
           let visit = geofenceManager.activeVisits[place.id] {
            activePlace = place
            activeVisit = visit
        } else {
            // If nearbyLocation not set yet, check all active visits from geofence manager
            // This handles case where GeofenceVisitCreated fired before updateCurrentLocation()
            for (placeId, visit) in geofenceManager.activeVisits {
                if let place = locationsManager.savedPlaces.first(where: { $0.id == placeId }) {
                    activePlace = place
                    activeVisit = visit
                    
                    // Update nearbyLocation to match active visit
                    if nearbyLocation != place.displayName {
                        nearbyLocation = place.displayName
                        nearbyLocationFolder = place.category
                        nearbyLocationPlace = place
                    }
                    break
                }
            }
        }
        
        if let place = activePlace, let visit = activeVisit {
            let elapsed = Date().timeIntervalSince(visit.entryTime)
            elapsedTimeString = formatElapsedTime(elapsed)

            // Save to UserDefaults for widget
            if let userDefaults = UserDefaults(suiteName: "group.seline") {
                userDefaults.set(place.displayName, forKey: "widgetVisitedLocation")
                userDefaults.set(elapsedTimeString, forKey: "widgetElapsedTime")
            }

            // Reload widget
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            // No active visit - clear elapsed time
            elapsedTimeString = ""

            // Clear widget data
            if let userDefaults = UserDefaults(suiteName: "group.seline") {
                userDefaults.removeObject(forKey: "widgetVisitedLocation")
                userDefaults.removeObject(forKey: "widgetElapsedTime")
            }

            // Reload widget
            WidgetCenter.shared.reloadAllTimelines()
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
                selectedLocationPlace = location
            }
        case .folder:
            if let category = result.category {
                selectedTab = .maps
                searchSelectedFolder = category
            }
        case .receipt:
            // Receipts are notes - open the note
            if let note = result.note {
                searchSelectedNote = note
            }
        case .recurringExpense:
            // Navigate to receipt stats view which shows recurring expenses
            showReceiptStats = true
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
            .onChange(of: colorScheme) { _ in
                // FIX: Force view refresh when system theme changes
                // This ensures the app immediately updates from light to dark mode
                // The onChange itself triggers a view update cycle
            }
            .id(colorScheme) // Force complete view recreation on theme change
    }

    private var mainContent: some View {
        mainContentBase
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                
                taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                // Check if there's a pending deep link action (e.g., from widget)
                deepLinkHandler.processPendingAction()

                // CLEANUP: Auto-close any incomplete visits older than 3 hours in Supabase
                // This fixes visits that got stuck before the auto-cleanup code was added
                Task {
                    await geofenceManager.cleanupIncompleteVisitsInSupabase(olderThanMinutes: 180)
                }

                // CLEANUP: Merge consecutive visits and delete short visits
                Task {
                    let (mergedCount, deletedCount) = await LocationVisitAnalytics.shared.mergeAndCleanupVisits()
                    if mergedCount > 0 || deletedCount > 0 {
                        print("🧹 On app startup - Merged \(mergedCount) visit(s), deleted \(deletedCount) short visit(s)")
                    }
                }

                // Request location permissions immediately
                do {
                    locationService.requestLocationPermission()

                    // Request background location permission for visit tracking
                    // setupGeofences will be called after authorization is granted in GeofenceManager.locationManagerDidChangeAuthorization
                    geofenceManager.requestLocationPermission()
                } catch {
                    print("⚠️ Error requesting location permissions: \(error)")
                }

                // Load incomplete visits from Supabase to resume tracking BEFORE checking location
                // This prevents race condition where updateCurrentLocation() creates a new visit
                // before the async load completes
                Task {
                    // Give location service a moment to resolve the location name
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                    await geofenceManager.loadIncompleteVisitsFromSupabase()
                    // Now that previous sessions are restored, signal we're ready for location updates
                    await MainActor.run {
                        // Signal that we've loaded incomplete visits and can now respond to location changes
                        hasLoadedIncompleteVisits = true
                        // Try updating location after location service has had time to resolve
                        updateCurrentLocation()
                    }
                }

                // Load top 3 locations by visit count
                loadTodaysVisits()
                // Calendar sync is handled in SelineApp.swift via didBecomeActiveNotification
            }
            .onReceive(locationService.$currentLocation) { _ in
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
                    // FIX: Immediately check current location to update nearby location state
                    // This ensures UI updates right away when app comes to foreground
                    updateCurrentLocation()

                    // App came to foreground - restart timer if tracking a location
                    if nearbyLocation != nil {
                        startLocationTimer()
                    }
                    
                    // Start location suggestion monitoring (detects unsaved locations)
                    locationSuggestionService.startMonitoring()

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
                    
                    // Stop location suggestion monitoring
                    locationSuggestionService.stopMonitoring()
                }
            }
            .onChange(of: locationsManager.savedPlaces) { _ in
                // Reload top 3 locations when places are added/removed/updated
                loadTodaysVisits()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
                // Reload visits when a new visit is created (e.g., when app detects user is already inside)
                loadTodaysVisits()
                
                // CRITICAL: Immediately update location widget data to match calendar view accuracy
                // This ensures home screen widget and widget extension update in real-time
                updateCurrentLocation()
                updateElapsedTime()
                
                // Reload widget timelines immediately to match calendar view speed
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: locationService.locationName) { _ in
                // Update location card when location service resolves the location name
                if locationService.locationName != "Unknown Location" {
                    updateCurrentLocation()
                }
            }
            .onChange(of: nearbyLocationPlace) { newPlace in
                // Clear dismissed visit reason IDs when user leaves a location
                // This prevents the Set from growing unbounded and ensures popup shows for new visits
                if newPlace == nil && !dismissedVisitReasonIds.isEmpty {
                    dismissedVisitReasonIds.removeAll()
                }
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
                    set: { if !$0 { 
                        selectedNoteToOpen = nil
                    } }
                ))
            }
            .sheet(isPresented: $showingNewNoteSheet) {
                NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .modifier(PresentationModifiers())
                    .presentationBg()
            }
            // Removed sheet animation for faster presentation
            .sheet(item: $searchSelectedNote) { note in
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { searchSelectedNote != nil },
                    set: { if !$0 { searchSelectedNote = nil } }
                ))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .modifier(PresentationModifiers())
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
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .presentationBg()
            }
            .fullScreenCover(item: $searchSelectedEmail) { email in
                NavigationView {
                    EmailDetailView(email: email)
                }
                .presentationBg()
            }
            .sheet(item: $searchSelectedTask) { task in
                if showingEditTask {
                    NavigationStack {
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
                    NavigationStack {
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
                    onSave: { (title: String, description: String?, date: Date, time: Date?, endTime: Date?, reminder: ReminderTime?, recurring: Bool, frequency: RecurrenceFrequency?, customDays: [WeekDay]?, tagId: String?, location: String?) in
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
                            location: location,
                            isRecurring: recurring,
                            recurrenceFrequency: frequency,
                            customRecurrenceDays: customDays,
                            tagId: tagId
                        )
                    }
                )
                .presentationBg()
            }
            // Removed sheet animation for faster presentation
            .sheet(isPresented: $showReceiptStats) {
                ReceiptStatsView(isPopup: true)
                    .presentationDetents([.fraction(0.6), .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
                    .presentationBg()
            }
            // Removed sheet animation for faster presentation
            .sheet(isPresented: $showAllLocationsSheet) {
                AllVisitsSheet(
                    allLocations: $allLocations,
                    isPresented: $showAllLocationsSheet,
                    onLocationTap: { locationId in
                        // Find the SavedPlace with this UUID
                        if let place = locationsManager.savedPlaces.first(where: { $0.id == locationId }) {
                            selectedLocationPlace = place
                        }
                    },
                    savedPlaces: locationsManager.savedPlaces
                )
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
                .presentationBg()
            }
            // Removed sheet animation for faster presentation
            .sheet(item: $selectedLocationPlace) { place in
                PlaceDetailSheet(place: place, onDismiss: { 
                    selectedLocationPlace = nil
                }, isFromRanking: false)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .modifier(PresentationModifiers())
                .presentationBg()
            }
            .sheet(isPresented: $showingReceiptImagePicker) {
                ImagePicker(selectedImage: Binding(
                    get: { nil },
                    set: { newImage in
                        if let image = newImage {
                            processReceiptImage(image)
                        }
                    }
                ))
            }
            .sheet(isPresented: $showingReceiptCameraPicker) {
                CameraPicker(selectedImage: Binding(
                    get: { nil },
                    set: { newImage in
                        if let image = newImage {
                            processReceiptImage(image)
                        }
                    }
                ))
            }
            .overlay(alignment: .top) {
                // Receipt processing toast indicator
                if receiptProcessingState != .idle {
                    VStack {
                        ReceiptProcessingToast(state: receiptProcessingState)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(1000)
                }
            }
    }

    private var mainContentBase: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                mainContentVStack(geometry: geometry)

                // The fixed header is removed from here and replaced with a floating bar at the bottom
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .blur(radius: isAnySheetPresented ? 5 : 0)
            .animation(.gentleFade, value: isAnySheetPresented)
        }
    }

    private func mainContentVStack(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Negative spacing to eliminate separator line
            // Padding removed - header is now a floating bar at bottom

            // Content based on selected tab - preserve views to avoid recreation
            ZStack {
                // Home tab - no transition for instant switching
                if selectedTab == .home {
                    homeContentWithoutHeader
                        .task {
                            // Only load if not already loaded (defer heavy operations)
                            if emailService.inboxEmails.isEmpty {
                                await emailService.loadEmailsForFolder(.inbox)
                            }
                        }
                        .task(id: selectedTab) {
                            // Background prefetching for adjacent tabs when on home
                            let isEmpty = await MainActor.run { emailService.inboxEmails.isEmpty }
                            Task.detached(priority: .utility) {
                                // Prefetch emails if not loaded
                                if isEmpty {
                                    await emailService.loadEmailsForFolder(.inbox)
                                }
                                
                                // OPTIMIZATION: Pre-load maps data to reduce lag when switching to maps tab
                                let places = await MainActor.run { locationsManager.savedPlaces }
                                await withTaskGroup(of: Void.self) { group in
                                    // Pre-fetch location stats for top locations (parallel)
                                    for place in places.prefix(20) {
                                        group.addTask {
                                            await LocationVisitAnalytics.shared.fetchStats(for: place.id)
                                        }
                                    }
                                }
                            }
                        }
                }
                
                // Email tab - no transition for instant switching
                if selectedTab == .email {
                    EmailView()
                }
                
                // Events tab - no transition for instant switching
                if selectedTab == .events {
                    EventsView()
                }
                
                // Notes tab - no transition for instant switching
                if selectedTab == .notes {
                    NotesView()
                }
                
                // Maps tab - no transition for instant switching
                if selectedTab == .maps {
                    MapsViewNew(externalSelectedFolder: $searchSelectedFolder)
                        .task(id: selectedTab) {
                            // Pre-load maps data when user is on adjacent tabs to reduce lag
                            // This runs in background and doesn't block UI
                            Task.detached(priority: .utility) {
                                // Pre-fetch location stats for top locations (parallel)
                                let places = await MainActor.run { locationsManager.savedPlaces }
                                await withTaskGroup(of: Void.self) { group in
                                    // Only pre-fetch top 20 most likely to be shown
                                    for place in places.prefix(20) {
                                        group.addTask {
                                            await LocationVisitAnalytics.shared.fetchStats(for: place.id)
                                        }
                                    }
                                }
                            }
                        }
                }
            }
            // Removed animation on tab change for instant, lag-free switching
            .frame(maxHeight: .infinity)

            // Fixed Footer - hide when keyboard appears or any sheet is open or viewing note in navigation
            if keyboardHeight == 0 && selectedNoteToOpen == nil && !showingNewNoteSheet && searchSelectedNote == nil && searchSelectedEmail == nil && searchSelectedTask == nil && !authManager.showLocationSetup && !notesManager.isViewingNoteInNavigation {
                
                // Floating AI Bar (only on home tab) - conditionally render to avoid taking space on other pages
                // Floating AI Bar moved to homeContentWithoutHeader ZStack above

                
                BottomTabBar(selectedTab: $selectedTab)
                    .padding(.top, -0.5) // Eliminate separator line by overlapping slightly
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(colorScheme == .dark ? Color.black : Color.white)
        // Swipe gestures disabled - user requested removal of left/right swipe navigation
    }

    // Detail Content Removal - mainContentHeader is no longer used
    
    // Generate an icon based on sender email or name (same logic as EmailRow)

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
                    .font(FontManager.geist(size: 13, weight: .regular))
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
                                        .font(FontManager.geist(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(email.subject)
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text("from \(email.sender.displayName)")
                                    .font(FontManager.geist(size: 12, weight: .regular))
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
                            .font(FontManager.geist(size: 13, weight: .regular))
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
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(todayTasks.prefix(5)) { task in
                    Button(action: {
                        HapticManager.shared.calendar()
                        selectedTab = .events
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(task.isCompleted ?
                                    (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color.black) :
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                )

                            Text(task.title)
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .strikethrough(task.isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            if let scheduledTime = task.scheduledTime {
                                Text(formatTime(scheduledTime))
                                    .font(FontManager.geist(size: 12, weight: .regular))
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
                            .font(FontManager.geist(size: 13, weight: .regular))
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
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(pinnedNotes.prefix(5)) { note in
                    Button(action: {
                        HapticManager.shared.cardTap()
                        selectedNoteToOpen = note
                    }) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Text(note.formattedDateModified)
                                .font(FontManager.geist(size: 11, weight: .regular))
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
                            .font(FontManager.geist(size: 13, weight: .regular))
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

    // LLM Search Bar Button (navigates to chat tab)
    private var searchBarView: some View {
        Button(action: {
            // Navigate to chat tab
            HapticManager.shared.selection()
            selectedTab = .email
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                Text("Search or ask for actions...")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "sparkles")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.cyan.opacity(0.7) : Color.blue.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Profile avatar button (opens settings)
    private var profileAvatarButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            showingSettings = true
        }) {
            Group {
                if let profilePictureUrl = profilePictureUrl, let url = URL(string: profilePictureUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_), .empty:
                            // Fallback to initials or default icon
                            Image(systemName: "person.circle.fill")
                                .font(FontManager.geist(size: 36, weight: .medium))
                        @unknown default:
                            Image(systemName: "person.circle.fill")
                                .font(FontManager.geist(size: 36, weight: .medium))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    // Show initials or default icon
                    if let user = authManager.currentUser,
                       let name = user.profile?.name,
                       let firstChar = name.first {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(firstChar).uppercased())
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                            )
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(FontManager.geist(size: 36, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await fetchUserProfilePicture()
        }
    }

    // NEW: App-wide search bar for searching emails, events, notes, receipts, etc.
    private var appSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(.gray)

            TextField("Search", text: $searchText)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .focused($isSearchFocused)
                .submitLabel(.search)

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
        )
    }

    // Search results dropdown (used when not in overlay mode - kept for compatibility)
    private var searchResultsDropdown: some View {
        let screenHeight = UIScreen.main.bounds.height
        // Calculate available height: screen height minus keyboard minus search bar area (top safe area + search bar height ~160px) minus small gap
        let availableHeight = screenHeight - keyboardHeight - 160 - 16

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 4) {
                if searchResults.isEmpty {
                    Text("No results found")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(searchResults) { result in
                        searchResultRow(for: result)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(height: max(400, availableHeight))
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ?
                      Color(red: 0.11, green: 0.11, blue: 0.12) :
                      Color(red: 0.98, green: 0.98, blue: 0.99))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 20, x: 0, y: 8)
        )
    }

    private func searchResultRow(for result: OverlaySearchResult) -> some View {
        Button(action: {
            handleSearchResultTap(result)
        }) {
            HStack(spacing: 10) {
                // Modern icon container with gradient background - smaller size
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            colorScheme == .dark ?
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.06),
                                        Color.black.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: result.icon)
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(
                            colorScheme == .dark ?
                                Color.white.opacity(0.9) :
                                Color.black.opacity(0.8)
                        )
                }

                // Content - smaller fonts
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                // Modern type badge with better styling - smaller
                Text(result.type.rawValue.capitalized)
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color.white.opacity(0.85) :
                            Color.black.opacity(0.7)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                    Color.black.opacity(0.08)
                            )
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        colorScheme == .dark ?
                            Color.white.opacity(0.05) :
                            Color.black.opacity(0.02)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        colorScheme == .dark ?
                            Color.white.opacity(0.08) :
                            Color.black.opacity(0.05),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Container for app-wide search bar and results
    private var searchBarContainer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Profile avatar button
                profileAvatarButton

                // Search bar
                appSearchBar
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)

            if !searchText.isEmpty {
                searchResultsDropdown
                    .padding(.top, 8)
                    .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            }
        }
    }

    private var mainContentWidgets: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    // NEW: Location suggestion card (shows when at unsaved location for 5+ min)
                    if locationSuggestionService.hasPendingSuggestion {
                        NewLocationSuggestionCard()
                            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                    
                    // Render widgets based on user configuration
                    // Note: Edit button is now inside Quick Access widget
                    ForEach(widgetManager.visibleWidgets) { config in
                        widgetView(for: config.type)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .refreshable {
                // Refresh all data sources
                await refreshAllData()
            }
            // Apply delaysContentTouches via UIScrollView introspection
            .onAppear {
                // Find and configure UIScrollView to delay content touches
                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        configureScrollViewsForSmoothScrolling(in: window)
                    }
                }
            }

            // Edit mode overlay (only when in edit mode)
            if widgetManager.isEditMode {
                WidgetEditModeOverlay(widgetManager: widgetManager)
                    .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Refresh Helper
    
    private func refreshAllData() async {
        // Invalidate caches
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysReceipts)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysSpending)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.birthdaysThisWeek)
        
        // Refresh core data
        await taskManager.syncCalendarEvents()
        await emailService.handleBackgroundRefresh()
        
        // Update location data
        loadTodaysVisits()
        
        // Success haptic
        HapticManager.shared.success()
    }
    
    // Configure all UIScrollViews to delay content touches for smoother scrolling
    private func configureScrollViewsForSmoothScrolling(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.delaysContentTouches = true
            scrollView.canCancelContentTouches = true
        }
        for subview in view.subviews {
            configureScrollViewsForSmoothScrolling(in: subview)
        }
    }
    
    // MARK: - Widget Views
    
    @ViewBuilder
    private func widgetView(for type: HomeWidgetType) -> some View {
        switch type {
        case .dailyOverview:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .dailyOverview) {
                DailyOverviewWidget(
                    isExpanded: $isDailyOverviewExpanded,
                    onNoteSelected: { note in
                        selectedNoteToOpen = note
                    },
                    onEmailSelected: { email in
                        searchSelectedEmail = email
                    },
                    onTaskSelected: { task in
                        searchSelectedTask = task
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .zIndex(isDailyOverviewExpanded ? 10 : 1)
            
        case .spending:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .spending) {
                SpendingAndETAWidget(
                    isVisible: selectedTab == .home,
                    onAddReceipt: {
                        showingReceiptCameraPicker = true
                    },
                    onAddReceiptFromGallery: {
                        showingReceiptImagePicker = true
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .currentLocation:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .currentLocation) {
                CurrentLocationCardWidget(
                    currentLocationName: currentLocationName,
                    nearbyLocation: nearbyLocation,
                    nearbyLocationFolder: nearbyLocationFolder,
                    nearbyLocationPlace: nearbyLocationPlace,
                    distanceToNearest: distanceToNearest,
                    elapsedTimeString: elapsedTimeString,
                    todaysVisits: todaysVisits,
                    selectedPlace: $selectedLocationPlace,
                    showAllLocationsSheet: $showAllLocationsSheet
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .events:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .events) {
                EventsCardWidget(showingAddEventPopup: $showingAddEventPopup)
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .weather:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .weather) {
                HomeWeatherWidget(isVisible: selectedTab == .home)
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .unreadEmails:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .unreadEmails) {
                HomeUnreadEmailsWidget(
                    selectedTab: $selectedTab,
                    onEmailSelected: { email in
                        searchSelectedEmail = email
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .pinnedNotes:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .pinnedNotes) {
                HomePinnedNotesWidget(
                    selectedTab: $selectedTab,
                    showingNewNoteSheet: $showingNewNoteSheet,
                    onNoteSelected: { note in
                        selectedNoteToOpen = note
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .favoriteLocations:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .favoriteLocations) {
                HomeFavoriteLocationsWidget(
                    onLocationSelected: { place in
                        selectedLocationPlace = place
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
        }
    }

    // MARK: - Visit Reason Helpers

    /// Save the visit reason to the active visit and sync to Supabase
    private func saveVisitReason(_ reason: String, for visit: LocationVisitRecord, place: SavedPlace) async {
        // Update the visit with the reason
        var updatedVisit = visit
        updatedVisit.visitNotes = reason
        updatedVisit.updatedAt = Date()

        // Update local active visit
        geofenceManager.updateActiveVisit(updatedVisit, for: place.id)

        // Sync visit notes to Supabase (uses update, not insert)
        await geofenceManager.updateVisitNotesInSupabase(updatedVisit)

        // Dismiss the popup by adding to dismissed set (the visit now has notes so it won't show anyway)
        await MainActor.run {
            dismissedVisitReasonIds.insert(visit.id)
        }

        print("✅ Visit reason saved: '\(reason)' for \(place.displayName)")
    }

    // MARK: - Home Content
    private var homeContentWithoutHeader: some View {
        ZStack(alignment: .top) {
            // Blurred background when in search mode (overlay)
            if isSearchFocused || !searchText.isEmpty {
                ZStack {
                    Color.black.opacity(0.4)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
                .ignoresSafeArea()
                .onTapGesture {
                    isSearchFocused = false
                    searchText = ""
                }
                .zIndex(99)
            }
            
            // Main content with search bar fixed at top
            VStack(spacing: 0) {
                // Search bar fixed at top
                searchBarContainer
                    .padding(.top, 8)
                
                // Main content widgets below search bar
                visitReasonPopupSection
                mainContentWidgets
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .zIndex(100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var visitReasonPopupSection: some View {
        if let place = nearbyLocationPlace,
           let visit = geofenceManager.getActiveVisit(for: place.id),
           (visit.visitNotes ?? "").isEmpty,
           !dismissedVisitReasonIds.contains(visit.id) {
            VisitReasonPopupCard(
                place: place,
                visit: visit,
                colorScheme: colorScheme,
                onSave: { reason in
                    await saveVisitReason(reason, for: visit, place: place)
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        _ = dismissedVisitReasonIds.insert(visit.id)
                    }
                }
            )
            .padding(.top, 12)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }
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
                    .font(FontManager.geist(size: 13, weight: .regular))
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
    
    // MARK: - Tab Transition Helpers
    
    private func getTabEdge(for tab: TabSelection, isRemoval: Bool = false) -> Edge {
        let tabs = TabSelection.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab),
              let tabIndex = tabs.firstIndex(of: tab) else {
            return .trailing
        }
        
        if isRemoval {
            // When removing, determine direction based on where we're going
            return tabIndex < currentIndex ? .leading : .trailing
        } else {
            // When inserting, determine direction based on where we're coming from
            return tabIndex > currentIndex ? .trailing : .leading
        }
    }
    
    // MARK: - Receipt Processing
    
    private func processReceiptImage(_ image: UIImage) {
        // Process receipt image using the same logic as receipts page
        // Navigate to Notes tab and open note editor with receipt
        Task {
            // Show processing indicator
            await MainActor.run {
                receiptProcessingState = .processing
            }
            
            do {
                // Use DeepSeekService (which delegates to OpenAI for vision) - same as receipts page
                let deepSeekService = DeepSeekService.shared
                let (receiptTitle, receiptContent) = try await deepSeekService.analyzeReceiptImage(image)
                
                // Clean up the extracted content - same as receipts page
                let cleanedContent = receiptContent
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                
                // Extract month and year from receipt title for automatic folder organization - same as receipts page
                var folderIdForReceipt: UUID?
                if let (month, year) = notesManager.extractMonthYearFromTitle(receiptTitle) {
                    // Use async folder creation to ensure folders sync before using IDs
                    folderIdForReceipt = await notesManager.getOrCreateReceiptMonthFolderAsync(month: month, year: year)
                    print("✅ Receipt assigned to \(notesManager.getMonthName(month)) \(year)")
                } else {
                    // Fallback to main Receipts folder if no date found
                    let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
                    folderIdForReceipt = receiptsFolderId
                    print("⚠️ No date found in receipt title, using main Receipts folder")
                }
                
                // Create note with receipt content
                var newNote = Note(title: receiptTitle, content: cleanedContent, folderId: folderIdForReceipt)
                
                // Save note first, then upload image
                let syncSuccess = await notesManager.addNoteAndWaitForSync(newNote)
                
                if syncSuccess {
                    // Upload image
                    let imageUrls = await notesManager.uploadNoteImages([image], noteId: newNote.id)
                    
                    // Update note with image URL
                    var updatedNote = newNote
                    updatedNote.imageUrls = imageUrls
                    updatedNote.dateModified = Date()
                    let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
                    
                    await MainActor.run {
                        HapticManager.shared.success()
                        receiptProcessingState = .success
                        print("✅ Receipt saved automatically in background")
                        
                        // Hide success message after 2 seconds
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run {
                                receiptProcessingState = .idle
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Error processing receipt: \(error.localizedDescription)")
                    HapticManager.shared.error()
                    receiptProcessingState = .error(error.localizedDescription)
                    
                    // Hide error message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            receiptProcessingState = .idle
                        }
                    }
                }
            }
        }
    }

    // MARK: - User Profile

    private func fetchUserProfilePicture() async {
        do {
            if let picUrl = try await GmailAPIClient.shared.fetchCurrentUserProfilePicture() {
                await MainActor.run {
                    self.profilePictureUrl = picUrl
                }
            }
        } catch {
            // Silently fail - will show initials fallback
            print("Failed to fetch current user profile picture: \(error)")
        }
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}