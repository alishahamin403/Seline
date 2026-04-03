import SwiftUI
import Combine
import CoreLocation
import WidgetKit
import UIKit
import GoogleSignIn

struct MainAppView: View {
    private struct HomeSearchIndex {
        struct TaskEntry {
            let task: TaskItem
            let titleLower: String
            let taskDate: Date
            let isRecurring: Bool
        }

        struct EmailEntry {
            let email: Email
            let subjectLower: String
            let senderLower: String
            let snippetLower: String
        }

        struct ReceiptEntry {
            let receipt: ReceiptStat
            let note: Note?
            let titleLower: String
            let categoryLower: String
            let noteTextLower: String
        }

        struct NoteEntry {
            let note: Note
            let titleLower: String
            let contentLower: String
            let isSearchable: Bool
        }

        struct LocationEntry {
            let place: SavedPlace
            let nameLower: String
            let addressLower: String
            let customNameLower: String
        }

        struct ExpenseEntry {
            let expense: RecurringExpense
            let titleLower: String
            let categoryLower: String
            let descriptionLower: String
        }

        static let empty = HomeSearchIndex(
            tasks: [],
            emails: [],
            receipts: [],
            notes: [],
            locations: [],
            expenses: []
        )

        let tasks: [TaskEntry]
        let emails: [EmailEntry]
        let receipts: [ReceiptEntry]
        let notes: [NoteEntry]
        let locations: [LocationEntry]
        let expenses: [ExpenseEntry]
    }

    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    private let pageRefreshCoordinator = PageRefreshCoordinator.shared
    @State private var homeState = HomeDashboardState()
    @ObservedObject private var locationsManager = LocationsManager.shared
    private let locationService = LocationService.shared
    @ObservedObject private var geofenceManager = GeofenceManager.shared
    private let searchService = SearchService.shared
    private let searchIndex = SearchIndexState.shared
    private let widgetManager = WidgetManager.shared
    @ObservedObject private var emailService = EmailService.shared
    @ObservedObject private var taskManager = TaskManager.shared
    @ObservedObject private var receiptManager = ReceiptManager.shared
    private let notesManager = NotesManager.shared
    private let tagManager = TagManager.shared
    private let peopleManager = PeopleManager.shared
    private let locationSuggestionService = LocationSuggestionService.shared
    private let visitState = VisitStateManager.shared
    private let floatingActionCoordinator = FloatingActionCoordinator.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTab: PrimaryTab = .home
    @State private var selectedPlanTab: EmailTab = .inbox
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
    @State private var selectedReceiptToOpen: ReceiptStat? = nil
    @State private var showingNewNoteSheet = false
    @State private var showingAddEventPopup = false
    @State private var showingTodoPhotoImportSheet = false
    @State private var todoImportSourceType: UIImagePickerController.SourceType = .camera
    @State private var searchText = ""
    @State private var isDailyOverviewExpanded = false
    @State private var searchResults: [OverlaySearchResult] = []  // Cache search results instead of computing every time
    @State private var searchSelectedNote: Note? = nil
    @State private var searchSelectedEmail: Email? = nil
    @State private var searchSelectedTask: TaskItem? = nil
    @State private var selectedPersonForDetail: Person? = nil
    @State private var searchSelectedLocation: SavedPlace? = nil
    @State private var searchSelectedFolder: String? = nil
    @State private var showingEditTask = false
    @State private var notificationEmailId: String? = nil
    @State private var notificationTaskId: String? = nil
    @FocusState private var isSearchFocused: Bool
    @Namespace private var noteTransitionNamespace
    @State private var showReceiptStats = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil  // Track debounce task
    @State private var homeSearchIndexRefreshTask: Task<Void, Never>? = nil
    @State private var homeSearchIndex: HomeSearchIndex = .empty
    // OPTIMIZATION: Cache flattened tasks to avoid recomputing on every search
    @State private var cachedFlattenedTasks: [TaskItem] = []
    @State private var lastCacheUpdate: Date = .distantPast
    @State private var currentLocationName: String = "Finding location..."
    @State private var nearbyLocation: String? = nil
    @State private var nearbyLocationFolder: String? = nil
    @State private var nearbyLocationPlace: SavedPlace? = nil
    @State private var distanceToNearest: Double? = nil
    @State private var lastLocationCheckCoordinate: CLLocationCoordinate2D?
    @State private var hasLoadedIncompleteVisits = false
    @State private var allLocations: [(id: UUID, displayName: String, visitCount: Int)] = []
    @State private var showAllLocationsSheet = false
    @State private var lastLocationUpdateTime: Date = Date.distantPast
    @State private var selectedLocationPlace: SavedPlace? = nil
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var showingManualReceiptForm = false
    @State private var showingRecurringExpenseForm = false
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var selectedReceiptImages: [UIImage] = []
    @State private var processingQueue: [UIImage] = []
    @State private var currentProcessingIndex = 0
    @State private var profilePictureUrl: String? = nil
    @State private var hasAppeared = false
    @State private var dismissedVisitReasonIds: Set<UUID> = [] // Track visits where user dismissed the reason popup
    @State private var isSidebarOverlayVisible = false
    @State private var isEmailDetailOpen = false
    @State private var activeOverlayRoute: OverlayRoute? = nil
    @State private var showingHomeDrawer = false
    @State private var syncedWidgetVisitId: UUID? = nil
    @State private var loadTodaysVisitsTask: Task<Void, Never>?
    @State private var allLocationsRefreshTask: Task<Void, Never>?
    @State private var receiptProcessingTask: Task<Void, Never>?
    @State private var startupGeofenceTask: Task<Void, Never>?
    @State private var lastAllLocationsRefreshAt: Date = .distantPast
    @State private var isFetchingProfilePicture = false
    @State private var isViewingNoteInNavigation = false
    @State private var isPeopleOverlaySearchActive = false

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

    private func formatTime(_ date: Date) -> String {
        FormatterCache.shortTime.string(from: date)
    }

    private func formatDateAndTime(_ date: Date) -> String {
        FormatterCache.shortDateTime.string(from: date)
    }

    private func formatEventDateAndTime(targetDate: Date?, scheduledTime: Date?) -> String {
        guard let targetDate = targetDate else { return "No date set" }
        guard let scheduledTime = scheduledTime else {
            return FormatterCache.shortDate.string(from: targetDate)
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

    private var trimmedHomeSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedProfilePictureURL: String? {
        if let profilePictureUrl, !profilePictureUrl.isEmpty {
            return profilePictureUrl
        }

        if let googleProfileURL = GIDSignIn.sharedInstance.currentUser?.profile?.imageURL(withDimension: 128)?.absoluteString,
           !googleProfileURL.isEmpty {
            return googleProfileURL
        }

        return authManager.currentUser?.profile?.imageURL(withDimension: 128)?.absoluteString
    }

    private var isHomeSearchPresented: Bool {
        isSearchFocused || !trimmedHomeSearchText.isEmpty
    }

    private var shouldSuppressHomeSearchResults: Bool {
        searchService.pendingEventCreation != nil ||
        searchService.pendingNoteCreation != nil ||
        searchService.pendingNoteUpdate != nil
    }

    private var unreadInboxCount: Int {
        emailService.unreadInboxCount
    }

    private var todayTodoCount: Int {
        taskManager.todayIncompleteTaskCount
    }

    private func clearHomeSearch() {
        searchDebounceTask?.cancel()
        searchText = ""
        searchResults = []
        isSearchFocused = false
    }

    private func homeSearchBadgeLabel(for type: OverlaySearchResultType) -> String {
        type.badgeLabel
    }

    /// Compute search results against a prebuilt search index.
    private func performSearchComputation(query: String, index: HomeSearchIndex) -> [OverlaySearchResult] {
        guard !query.isEmpty else {
            return []
        }

        var results: [OverlaySearchResult] = []
        let lowercasedSearch = query.lowercased()

        let matchingTasks = index.tasks.filter {
            $0.titleLower.contains(lowercasedSearch)
        }

        // Deduplicate: for each unique title, keep only ONE result
        var tasksByTitle: [String: [HomeSearchIndex.TaskEntry]] = [:]

        for task in matchingTasks {
            if tasksByTitle[task.titleLower] == nil {
                tasksByTitle[task.titleLower] = []
            }
            tasksByTitle[task.titleLower]?.append(task)
        }

        var deduplicatedTasks: [HomeSearchIndex.TaskEntry] = []
        let today = Calendar.current.startOfDay(for: Date())

        for (_, tasks) in tasksByTitle {
            var bestTask: HomeSearchIndex.TaskEntry?
            var bestTaskDate: Date?

            for task in tasks {
                let taskDate = task.taskDate

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

        // Limit to 3 most relevant tasks for faster search
        for task in deduplicatedTasks.prefix(3) {
            results.append(OverlaySearchResult(
                type: .event,
                title: task.task.title,
                subtitle: formatEventDateAndTime(targetDate: task.task.targetDate, scheduledTime: task.task.scheduledTime),
                icon: "calendar",
                task: task.task,
                email: nil,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Limit to 3 most relevant emails for faster search
        for email in index.emails.lazy.filter({
            $0.subjectLower.contains(lowercasedSearch) ||
            $0.senderLower.contains(lowercasedSearch) ||
            $0.snippetLower.contains(lowercasedSearch)
        }).prefix(3) {
            results.append(OverlaySearchResult(
                type: .email,
                title: email.email.subject,
                subtitle: "from \(email.email.sender.displayName)",
                icon: "envelope",
                task: nil,
                email: email.email,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Limit to 3 most relevant receipts for faster search
        for receipt in index.receipts.lazy.filter({
            $0.titleLower.contains(lowercasedSearch) ||
            $0.categoryLower.contains(lowercasedSearch) ||
            $0.noteTextLower.contains(lowercasedSearch)
        }).prefix(3) {
            let dateString = FormatterCache.shortDate.string(from: receipt.receipt.date)

            results.append(OverlaySearchResult(
                type: .receipt,
                title: receipt.receipt.title,
                subtitle: "\(CurrencyParser.formatAmount(receipt.receipt.amount)) • \(dateString)",
                icon: "doc.text",
                task: nil,
                email: nil,
                note: receipt.note,
                receipt: receipt.receipt,
                location: nil,
                category: receipt.receipt.category
            ))
        }

        // Limit to 3 most relevant notes for faster search
        for note in index.notes.lazy.filter({
            $0.isSearchable &&
            ($0.titleLower.contains(lowercasedSearch) ||
             $0.contentLower.contains(lowercasedSearch))
        }).prefix(3) {
            results.append(OverlaySearchResult(
                type: .note,
                title: note.note.title,
                subtitle: note.note.formattedDateModified,
                icon: note.note.isJournalWeeklyRecap ? "book.closed.fill" : (note.note.isJournalEntry ? "square.and.pencil" : "note.text"),
                task: nil,
                email: nil,
                note: note.note,
                location: nil,
                category: nil
            ))
        }

        // Limit to 3 most relevant locations for faster search
        for location in index.locations.lazy.filter({
            $0.nameLower.contains(lowercasedSearch) ||
            $0.addressLower.contains(lowercasedSearch) ||
            $0.customNameLower.contains(lowercasedSearch)
        }).prefix(3) {
            results.append(OverlaySearchResult(
                type: .location,
                title: location.place.displayName,
                subtitle: location.place.address,
                icon: "mappin.circle.fill",
                task: nil,
                email: nil,
                note: nil,
                location: location.place,
                category: nil
            ))
        }

        // Limit to 3 most relevant expenses for faster search
        for expense in index.expenses.lazy.filter({
            $0.titleLower.contains(lowercasedSearch) ||
            $0.categoryLower.contains(lowercasedSearch) ||
            $0.descriptionLower.contains(lowercasedSearch)
        }).prefix(3) {
            let nextDateString = FormatterCache.shortDate.string(from: expense.expense.nextOccurrence)

            results.append(OverlaySearchResult(
                type: .recurringExpense,
                title: expense.expense.title,
                subtitle: "\(expense.expense.formattedAmount) • Next: \(nextDateString)",
                icon: "repeat.circle",
                task: nil,
                email: nil,
                note: nil,
                location: nil,
                category: expense.expense.category
            ))
        }

        return results
    }

    private func buildHomeSearchIndex() -> HomeSearchIndex {
        let tasksSnapshot: [TaskItem]
        let cacheAge = Date().timeIntervalSince(lastCacheUpdate)
        if cacheAge > 30 || cachedFlattenedTasks.isEmpty {
            tasksSnapshot = taskManager.getAllFlattenedTasks()
            cachedFlattenedTasks = tasksSnapshot
            lastCacheUpdate = Date()
        } else {
            tasksSnapshot = cachedFlattenedTasks
        }

        let emailsSnapshot = emailService.inboxEmails + emailService.sentEmails
        let notesSnapshot = notesManager.notes
        let foldersSnapshot = notesManager.folders
        let savedPlacesSnapshot = locationsManager.savedPlaces
        let recurringExpensesSnapshot: [RecurringExpense] =
            CacheManager.shared.get(forKey: CacheManager.CacheKey.allRecurringExpenses) ?? []
        let receiptsSnapshot = receiptManager.receipts

        let folderParentById = Dictionary(uniqueKeysWithValues: foldersSnapshot.map { ($0.id, $0.parentFolderId) })
        let receiptFolderIds = Set(
            foldersSnapshot
                .filter { $0.name.caseInsensitiveCompare("Receipts") == .orderedSame }
                .map(\.id)
        )
        let notesById = Dictionary(uniqueKeysWithValues: notesSnapshot.map { ($0.id, $0) })
        let receiptNoteIds = Set(receiptsSnapshot.compactMap(\.legacyNoteId))

        func isDescendantOfReceiptsFolder(note: Note) -> Bool {
            guard let folderId = note.folderId else { return false }
            var currentFolderId: UUID? = folderId

            while let currentId = currentFolderId {
                if receiptFolderIds.contains(currentId) {
                    return true
                }
                currentFolderId = folderParentById[currentId] ?? nil
            }
            return false
        }

        return HomeSearchIndex(
            tasks: tasksSnapshot.map { task in
                HomeSearchIndex.TaskEntry(
                    task: task,
                    titleLower: task.title.lowercased(),
                    taskDate: task.targetDate ?? task.createdAt,
                    isRecurring: task.isRecurring
                )
            },
            emails: emailsSnapshot.map { email in
                HomeSearchIndex.EmailEntry(
                    email: email,
                    subjectLower: email.subject.lowercased(),
                    senderLower: email.sender.displayName.lowercased(),
                    snippetLower: email.snippet.lowercased()
                )
            },
            receipts: receiptsSnapshot.map { receipt in
                let note = receipt.legacyNoteId.flatMap { notesById[$0] }
                return HomeSearchIndex.ReceiptEntry(
                    receipt: receipt,
                    note: note,
                    titleLower: receipt.title.lowercased(),
                    categoryLower: receipt.category.lowercased(),
                    noteTextLower: receipt.searchableText.lowercased()
                )
            },
            notes: notesSnapshot.map { note in
                let isSearchable = !receiptNoteIds.contains(note.id) && !isDescendantOfReceiptsFolder(note: note)
                return HomeSearchIndex.NoteEntry(
                    note: note,
                    titleLower: note.title.lowercased(),
                    contentLower: note.displayContent.lowercased(),
                    isSearchable: isSearchable
                )
            },
            locations: savedPlacesSnapshot.map { place in
                HomeSearchIndex.LocationEntry(
                    place: place,
                    nameLower: place.name.lowercased(),
                    addressLower: place.address.lowercased(),
                    customNameLower: place.customName?.lowercased() ?? ""
                )
            },
            expenses: recurringExpensesSnapshot.map { expense in
                HomeSearchIndex.ExpenseEntry(
                    expense: expense,
                    titleLower: expense.title.lowercased(),
                    categoryLower: expense.category?.lowercased() ?? "",
                    descriptionLower: expense.description?.lowercased() ?? ""
                )
            }
        )
    }

    private func scheduleHomeSearchIndexRefresh() {
        searchDebounceTask?.cancel()

        let query = trimmedHomeSearchText
        guard !query.isEmpty, !shouldSuppressHomeSearchResults else {
            searchResults = []
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            searchResults = searchIndex.results(
                for: query,
                scopes: .homeSearchScopes,
                limit: 18
            )
        }
    }

    // MARK: - Helper Methods for onChange Consolidation

    private func activateConversationModalIfNeeded() {
        if searchService.pendingEventCreation != nil {
            showingAddEventPopup = true
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
            dismissOverlay()
            selectedTab = .search
        case "journal":
            openJournalInNotes(openToday: false)
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
            case "maps":
                deepLinkHandler.shouldOpenMaps = false
            case "journal":
                deepLinkHandler.shouldOpenJournal = false
            default:
                break
            }
        }
    }

    private func openJournalInNotes(openToday: Bool) {
        selectedTab = .notes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(
                name: .openJournalFromMainApp,
                object: nil,
                userInfo: ["openToday": openToday]
            )
        }
    }

    private func openReceiptsInNotes() {
        presentOverlay(.receipts)
    }

    private func openRecurringInNotes() {
        presentOverlay(.recurring)
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

                        // Save to Supabase immediately
                        Task {
                            print("🔄 Starting Supabase save task for \(place.displayName)")
                            await geofenceManager.saveVisitToSupabase(visit)
                            print("✅ Completed Supabase save task")
                        }
                    }

                    distanceToNearest = nil
                    refreshActiveVisitContext(preferredPlace: place)
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

                clearCurrentLocationWidgetIfNeeded()

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
            clearCurrentLocationWidgetIfNeeded()
        }
    }

    private func loadTodaysVisits() {
        loadTodaysVisitsTask?.cancel()
        loadTodaysVisitsTask = Task {
            await visitState.fetchTodaysVisits()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if selectedTab == .home {
                    pageRefreshCoordinator.markValidated(.home)
                }
            }
        }
    }

    private func refreshAllLocationRankingsIfNeeded(force: Bool = false) {
        let shouldRefresh = force ||
            allLocations.isEmpty ||
            Date().timeIntervalSince(lastAllLocationsRefreshAt) >= 300

        guard shouldRefresh else { return }
        let places = locationsManager.savedPlaces

        allLocationsRefreshTask?.cancel()
        allLocationsRefreshTask = Task {
            guard !places.isEmpty else {
                await MainActor.run {
                    allLocations = []
                    lastAllLocationsRefreshAt = Date()
                }
                return
            }

            await LocationVisitAnalytics.shared.fetchAllStats(for: places)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let visitStats = LocationVisitAnalytics.shared.visitStats
                allLocations = places
                    .map { place in
                        (
                            id: place.id,
                            displayName: place.displayName,
                            visitCount: visitStats[place.id]?.totalVisits ?? 0
                        )
                    }
                    .sorted { $0.visitCount > $1.visitCount }
                lastAllLocationsRefreshAt = Date()
            }
        }
    }

    @MainActor
    private func revalidateHomeIfNeeded(reason: RefreshReason) {
        pageRefreshCoordinator.pageBecameVisible(.home)

        guard pageRefreshCoordinator.shouldRevalidate(
            .home,
            maxAge: pageRefreshCoordinator.defaultMaxAge(for: .home)
        ) else {
            return
        }

        pageRefreshCoordinator.markDirty(.home, reason: reason)
        homeState.refreshAll()
        loadTodaysVisits()
    }

    private func refreshActiveVisitContext(preferredPlace: SavedPlace? = nil) {
        // Get the active visit entry time for the current location from GeofenceManager
        // This uses REAL geofence entry time, not artificial tracking
        // CRITICAL: Check geofenceManager.activeVisits FIRST (most accurate, real-time)
        // This ensures widget updates match calendar view accuracy

        // Find any active visit from geofence manager
        var activePlace: SavedPlace? = nil
        var activeVisit: LocationVisitRecord? = nil

        // First try to find from nearbyLocation if set
        if let place = preferredPlace ?? nearbyLocationPlace ?? nearbyLocation.flatMap({ nearbyLoc in
            locationsManager.savedPlaces.first(where: { $0.displayName == nearbyLoc })
        }),
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
            syncCurrentLocationWidgetIfNeeded(place: place, visit: visit)
        } else {
            clearCurrentLocationWidgetIfNeeded()
        }
    }

    private func syncCurrentLocationWidgetIfNeeded(place: SavedPlace, visit: LocationVisitRecord) {
        guard syncedWidgetVisitId != visit.id else { return }

        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(place.displayName, forKey: "widgetVisitedLocation")
            userDefaults.set(visit.entryTime, forKey: "widgetVisitEntryTime")
            userDefaults.removeObject(forKey: "widgetElapsedTime")
            userDefaults.synchronize()
        }

        syncedWidgetVisitId = visit.id
        WidgetInvalidationCoordinator.shared.requestReload(reason: "current_location_sync")
    }

    private func clearCurrentLocationWidgetIfNeeded() {
        guard syncedWidgetVisitId != nil else { return }

        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.removeObject(forKey: "widgetVisitedLocation")
            userDefaults.removeObject(forKey: "widgetVisitEntryTime")
            userDefaults.removeObject(forKey: "widgetElapsedTime")
            userDefaults.synchronize()
        }

        syncedWidgetVisitId = nil
        WidgetInvalidationCoordinator.shared.requestReload(reason: "current_location_clear")
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
            if let receipt = result.receipt {
                selectedReceiptToOpen = receipt
            } else if let note = result.note {
                selectedNoteToOpen = note
            }
        case .recurringExpense:
            // Navigate to receipt stats view which shows recurring expenses
            showReceiptStats = true
        case .person:
            if let person = result.person {
                selectedPersonForDetail = person
            }
        }

        // Dismiss search after setting the state
        isSearchFocused = false
        searchText = ""
    }

    private func handleSpendingReceiptSelection(_ receipt: ReceiptStat) {
        HapticManager.shared.cardTap()
        selectedReceiptToOpen = receipt
    }

    // MARK: - Tab Navigation Helpers

    private func previousTab() {
        let allTabs = PrimaryTab.allCases
        guard let currentIndex = allTabs.firstIndex(of: selectedTab) else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if currentIndex == 0 {
                selectedTab = allTabs[allTabs.count - 1] // Wrap to last tab
            } else {
                selectedTab = allTabs[currentIndex - 1]
            }
        }
        HapticManager.shared.selection()
    }

    private func nextTab() {
        let allTabs = PrimaryTab.allCases
        guard let currentIndex = allTabs.firstIndex(of: selectedTab) else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if currentIndex == allTabs.count - 1 {
                selectedTab = allTabs[0] // Wrap to first tab
            } else {
                selectedTab = allTabs[currentIndex + 1]
            }
        }
        HapticManager.shared.selection()
    }

    private func presentOverlay(_ route: OverlayRoute) {
        dismissActiveKeyboard()

        guard activeOverlayRoute != route else { return }

        if showingHomeDrawer {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showingHomeDrawer = false
                isSidebarOverlayVisible = false
            }
        }

        withAnimation(.navigationOverlayTransition) {
            activeOverlayRoute = route
        }
    }

    private func dismissOverlay() {
        HapticManager.shared.soft()
        withAnimation(.navigationOverlayTransition) {
            activeOverlayRoute = nil
        }
    }

    private func dismissActiveKeyboard() {
        isSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openPlanInbox() {
        selectedPlanTab = .inbox
        presentOverlay(.plan)
    }

    private func openPlanCalendar() {
        selectedPlanTab = .calendar
        presentOverlay(.plan)
    }

    private func openPlanSent() {
        selectedPlanTab = .sent
        presentOverlay(.plan)
    }

    private func openSettingsOverlay() {
        presentOverlay(.settings)
    }

    private func openPeopleOverlay() {
        isPeopleOverlaySearchActive = false
        presentOverlay(.people)
    }

    var body: some View {
        mainContent
            .edgeSwipeBackEnabled(
                action: activeOverlayRoute != nil ? dismissOverlay : nil
            )
            .onReceive(searchService.$pendingEventCreation.dropFirst()) { _ in
                activateConversationModalIfNeeded()
            }
            .onReceive(searchService.$pendingNoteCreation.dropFirst()) { draft in
                activateConversationModalIfNeeded()
                if draft != nil {
                    showingNewNoteSheet = true
                }
            }
            .onReceive(searchService.$pendingNoteUpdate.dropFirst()) { _ in
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
            .onChange(of: deepLinkHandler.shouldOpenMaps) { newValue in
                if newValue {
                    if let lat = deepLinkHandler.mapsLatitude, let lon = deepLinkHandler.mapsLongitude {
                        let mapsURL = URL(string: "https://maps.google.com/?q=\(lat),\(lon)")!
                        UIApplication.shared.open(mapsURL)
                    }
                    resetDeepLinkFlags("maps")
                }
            }
            .onChange(of: deepLinkHandler.shouldOpenJournal) { newValue in
                if newValue { handleDeepLinkAction(type: "journal") }
            }
            .onChange(of: colorScheme) { _ in
                // FIX: Force view refresh when system theme changes
                // This ensures the app immediately updates from light to dark mode
                // The onChange itself triggers a view update cycle
            }
    }

    private var mainContent: some View {
        mainContentPresented
    }

    @ViewBuilder
    private var mainContentObserved: some View {
            mainContentBase
                .onAppear {
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    isViewingNoteInNavigation = notesManager.isViewingNoteInNavigation
                    pageRefreshCoordinator.markDirty(PageRoute.allCases, reason: .initialLoad)
                    pageRefreshCoordinator.pageBecameVisible(selectedTab.pageRoute)

                    taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                    deepLinkHandler.processPendingAction()
                    Task {
                        await fetchUserProfilePicture()
                    }

                    Task {
                        let (mergedCount, deletedCount) = await LocationVisitAnalytics.shared.mergeAndCleanupVisits()
                        if mergedCount > 0 || deletedCount > 0 {
                            print("🧹 On app startup - Merged \(mergedCount) visit(s), deleted \(deletedCount) short visit(s)")
                        }
                    }

                    locationService.requestLocationPermission()
                    geofenceManager.requestLocationPermission()

                    startupGeofenceTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        await geofenceManager.loadIncompleteVisitsFromSupabase()
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            hasLoadedIncompleteVisits = true
                            updateCurrentLocation()
                        }
                    }

                    loadTodaysVisits()
                }
                .onReceive(locationService.$currentLocation) { _ in
                    let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime)
                    if timeSinceLastUpdate >= 2.0 {
                        lastLocationUpdateTime = Date()
                        updateCurrentLocation()
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        updateCurrentLocation()

                        if selectedTab == .home {
                            revalidateHomeIfNeeded(reason: .appBecameActive)
                        }

                        locationSuggestionService.startMonitoring()

                        if let currentLoc = locationService.currentLocation {
                            Task {
                                await geofenceManager.autoCompleteVisitsIfOutOfRange(
                                    currentLocation: currentLoc,
                                    savedPlaces: locationsManager.savedPlaces
                                )
                            }
                        }
                    } else {
                        locationSuggestionService.stopMonitoring()
                    }
                }
                .onChange(of: locationsManager.savedPlaces) { _ in
                    pageRefreshCoordinator.markDirty([.home, .maps], reason: .locationDataChanged)
                    loadTodaysVisits()
                }
                .onReceive(notesManager.$isViewingNoteInNavigation.removeDuplicates()) { isViewing in
                    isViewingNoteInNavigation = isViewing
                }
                .onChange(of: showAllLocationsSheet) { isPresented in
                    guard isPresented else { return }
                    refreshAllLocationRankingsIfNeeded(force: allLocations.isEmpty)
                }
                .onReceive(taskManager.$tasks) { _ in
                    pageRefreshCoordinator.markDirty([.home, .plan], reason: .taskDataChanged)
                    taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                }
                .onReceive(emailService.$inboxEmails) { _ in
                }
                .onReceive(emailService.$sentEmails) { _ in
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
                    pageRefreshCoordinator.markDirty([.home, .maps], reason: .visitHistoryChanged)
                    loadTodaysVisits()
                    updateCurrentLocation()
                    WidgetInvalidationCoordinator.shared.requestReload(reason: "geofence_visit_created")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VisitHistoryUpdated"))) { _ in
                    pageRefreshCoordinator.markDirty([.home, .maps], reason: .visitHistoryChanged)
                    loadTodaysVisits()
                    updateCurrentLocation()
                    WidgetInvalidationCoordinator.shared.requestReload(reason: "visit_history_updated")
                }
                .onReceive(locationService.$locationName.dropFirst()) { locationName in
                    if locationName != "Unknown Location" {
                        updateCurrentLocation()
                    }
                }
                .onChange(of: selectedTab) { newTab in
                    dismissActiveKeyboard()
                    pageRefreshCoordinator.pageBecameVisible(newTab.pageRoute)

                    if newTab == .home {
                        revalidateHomeIfNeeded(reason: .initialLoad)
                    } else if showingHomeDrawer {
                        showingHomeDrawer = false
                    }
                }
                .onChange(of: nearbyLocationPlace) { newPlace in
                    if newPlace == nil && !dismissedVisitReasonIds.isEmpty {
                        dismissedVisitReasonIds.removeAll()
                    }
                }
                .onDisappear {
                    loadTodaysVisitsTask?.cancel()
                    allLocationsRefreshTask?.cancel()
                    searchDebounceTask?.cancel()
                    homeSearchIndexRefreshTask?.cancel()
                    receiptProcessingTask?.cancel()
                    startupGeofenceTask?.cancel()
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
                .onReceive(NotificationCenter.default.publisher(for: .navigateToJournal)) { _ in
                    openJournalInNotes(openToday: true)
                }
    }

    private func handleHomeSidebarVisibilityChange(_ isVisible: Bool) {
        guard isSidebarOverlayVisible != isVisible else { return }
        isSidebarOverlayVisible = isVisible
    }

    @ViewBuilder
    private var mainContentPresented: some View {
            mainContentObserved
                .sheet(item: $selectedReceiptToOpen) { receipt in
                    ReceiptDetailSheet(receipt: receipt)
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
                    NoteEditView(
                        note: nil,
                        isPresented: Binding<Bool>(
                            get: { showingNewNoteSheet },
                            set: { newValue in
                                showingNewNoteSheet = newValue
                                if !newValue {
                                    searchService.pendingNoteCreation = nil
                                }
                            }
                        ),
                        initialFolderId: searchService.pendingNoteCreation?.folderId,
                        initialTitle: searchService.pendingNoteCreation?.title,
                        initialContent: searchService.pendingNoteCreation?.content ?? ""
                    )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .modifier(PresentationModifiers())
                        .presentationBg()
                }
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
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
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
                                onSaveRecurring: { updatedTask, scope, occurrenceDate in
                                    taskManager.editTask(
                                        updatedTask,
                                        recurringEditScope: scope,
                                        recurringOccurrenceDate: occurrenceDate
                                    )
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
                .sheet(item: $selectedPersonForDetail) { person in
                    PersonDetailSheet(
                        person: person,
                        peopleManager: peopleManager,
                        locationsManager: locationsManager,
                        colorScheme: colorScheme,
                        onDismiss: {
                            selectedPersonForDetail = nil
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBg()
                }
                .onChange(of: searchSelectedTask) { _ in
                    showingEditTask = false
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
                .sheet(isPresented: $showingTodoPhotoImportSheet) {
                    PhotoCalendarImportView(initialSourceType: todoImportSourceType)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationBg()
                }
                .sheet(isPresented: $showReceiptStats) {
                    ReceiptStatsView(
                        onAddReceiptManually: {
                            HapticManager.shared.selection()
                            showingManualReceiptForm = true
                        },
                        onAddReceiptFromCamera: {
                            HapticManager.shared.selection()
                            showingReceiptCameraPicker = true
                        },
                        onAddReceiptFromGallery: {
                            HapticManager.shared.selection()
                            showingReceiptImagePicker = true
                        },
                        isPopup: true
                    )
                    .presentationDetents([.fraction(0.6), .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
                    .presentationBg()
                }
                .sheet(isPresented: $showingManualReceiptForm) {
                    ManualReceiptEntrySheet { draft in
                        do {
                            let receipt = try await receiptManager.createReceipt(from: draft)
                            await MainActor.run {
                                HapticManager.shared.success()
                                selectedReceiptToOpen = receipt
                            }
                        } catch {
                            await MainActor.run {
                                HapticManager.shared.error()
                                receiptProcessingState = .error(error.localizedDescription)
                            }
                        }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBg()
                }
                .sheet(isPresented: $showAllLocationsSheet) {
                    AllVisitsSheet(
                        allLocations: $allLocations,
                        isPresented: $showAllLocationsSheet,
                        onLocationTap: { locationId in
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
                    ImagePicker(selectedImages: $selectedReceiptImages)
                }
                .onChange(of: selectedReceiptImages) { newImages in
                    if !newImages.isEmpty {
                        processingQueue = newImages
                        currentProcessingIndex = 0
                        selectedReceiptImages = []
                        processNextReceiptInQueue()
                    }
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
                .sheet(isPresented: $showingRecurringExpenseForm) {
                    RecurringExpenseForm { expense in
                        HapticManager.shared.buttonTap()
                        print("Created recurring expense: \(expense.title)")
                    }
                    .presentationBg()
                }
                .overlay(alignment: .top) {
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
            ZStack(alignment: .topLeading) {
                mainContentVStack(geometry: geometry)

                overlayRouteView(in: geometry)

                if shouldShowPrimaryFloatingComposeButton {
                    primaryFloatingComposeOverlay(in: geometry)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.appBackground(colorScheme))
        }
    }

    private var canShowBottomTabBar: Bool {
        keyboardHeight == 0 &&
        selectedNoteToOpen == nil &&
        !showingNewNoteSheet &&
        searchSelectedNote == nil &&
        searchSelectedEmail == nil &&
        searchSelectedTask == nil &&
        !authManager.showLocationSetup &&
        activeOverlayRoute == nil &&
        !isViewingNoteInNavigation &&
        !isEmailDetailOpen
    }

    private var shouldShowHomeSidebarAttachedTabBar: Bool {
        canShowBottomTabBar && selectedTab == .home
    }

    private var shouldShowNotesSidebarAttachedTabBar: Bool {
        canShowBottomTabBar && selectedTab == .notes
    }

    private var shouldShowMapsSidebarAttachedTabBar: Bool {
        canShowBottomTabBar && selectedTab == .maps
    }

    private var shouldShowChatSidebarAttachedTabBar: Bool {
        canShowBottomTabBar && selectedTab == .chat
    }

    private var shouldShowShellBottomTabBar: Bool {
        canShowBottomTabBar &&
        selectedTab != .home &&
        selectedTab != .chat &&
        selectedTab != .notes &&
        selectedTab != .maps &&
        !showingHomeDrawer &&
        !isSidebarOverlayVisible
    }

    private var shouldShowPrimaryFloatingComposeButton: Bool {
        activeOverlayRoute == nil &&
        !showingHomeDrawer &&
        !isSidebarOverlayVisible &&
        keyboardHeight == 0 &&
        (selectedTab == .home || selectedTab == .notes || selectedTab == .maps)
    }

    @ViewBuilder
    private func primaryFloatingComposeOverlay(in geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()

            HStack {
                Spacer()
                ShellFloatingComposeButton(
                    selectedTab: selectedTab,
                    coordinator: floatingActionCoordinator,
                    homeButton: AnyView(homeFloatingComposeButton),
                    notesButton: { page in
                        AnyView(notesShellFloatingComposeButton(for: page))
                    },
                    mapsButton: AnyView(mapsShellFloatingComposeButton)
                )
            }
            .padding(.trailing, primaryFloatingComposeTrailingPadding)
            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 56 : 40)
        }
        .transition(.opacity)
        .zIndex(15)
    }

    private var primaryFloatingComposeTrailingPadding: CGFloat {
        selectedTab == .home ? homeCardHorizontalPadding + 8 : 16
    }

    private func bottomTabBarVerticalOffset(for geometry: GeometryProxy) -> CGFloat {
        geometry.safeAreaInsets.bottom > 0 ? 10 : 4
    }

    private func overlayUnderlayOffset(for geometry: GeometryProxy) -> CGFloat {
        guard activeOverlayRoute != nil else { return 0 }
        return -min(32, geometry.size.width * 0.08)
    }

    private func mainContentVStack(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            activeTabContent
                .frame(maxHeight: .infinity)

            if shouldShowShellBottomTabBar {
                BottomTabBar(selectedTab: $selectedTab)
                    .allowsHitTesting(!(showingHomeDrawer || isSidebarOverlayVisible))
                    .padding(.top, -bottomTabBarVerticalOffset(for: geometry))
                    .offset(y: bottomTabBarVerticalOffset(for: geometry))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(Color.appBackground(colorScheme))
        .offset(x: overlayUnderlayOffset(for: geometry))
        .animation(.navigationOverlayTransition, value: activeOverlayRoute)
        // Swipe gestures disabled - user requested removal of left/right swipe navigation
    }

    @ViewBuilder
    private var activeTabContent: some View {
        // Pre-warm .maps alongside .home so MapsViewNew is already initialized
        // when the user first taps it — eliminates the cold-start lag.
        RetainedTabContainer(
            selection: $selectedTab,
            allTabs: PrimaryTab.allCases,
            initialTabs: [.home, .maps]
        ) { tab, isVisible in
            tabContent(for: tab, isVisible: isVisible)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: PrimaryTab, isVisible: Bool) -> some View {
        switch tab {
        case .home:
            homeTabContent(isVisible: isVisible)
        case .search:
            SearchView(
                isVisible: isVisible,
                selectedTab: $selectedTab,
                selectedFolder: $searchSelectedFolder,
                onOpenEmail: { email in
                    selectedPlanTab = emailService.sentEmails.contains(where: { $0.id == email.id }) ? .sent : .inbox
                    presentOverlay(.plan)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        searchSelectedEmail = email
                    }
                },
                onOpenTask: { task in
                    openPlanCalendar()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        searchSelectedTask = task
                        showingEditTask = false
                    }
                },
                onOpenNote: { note in
                    searchSelectedNote = note
                },
                onOpenReceipt: { receipt in
                    selectedReceiptToOpen = receipt
                },
                onOpenPlace: { place in
                    selectedLocationPlace = place
                },
                onOpenPerson: { person in
                    selectedPersonForDetail = person
                }
            )
        case .chat:
            ChatView(
                isVisible: isVisible,
                bottomTabSelection: $selectedTab,
                showsAttachedBottomTabBar: shouldShowChatSidebarAttachedTabBar,
                onOpenEmail: { email in
                    selectedPlanTab = emailService.sentEmails.contains(where: { $0.id == email.id }) ? .sent : .inbox
                    presentOverlay(.plan)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        searchSelectedEmail = email
                    }
                },
                onOpenTask: { task in
                    openPlanCalendar()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        searchSelectedTask = task
                        showingEditTask = false
                    }
                },
                onOpenNote: { note in
                    searchSelectedNote = note
                },
                onOpenPlace: { place in
                    selectedLocationPlace = place
                },
                onOpenPerson: { person in
                    selectedPersonForDetail = person
                }
            )
        case .notes:
            NotesView(
                isVisible: isVisible,
                bottomTabSelection: $selectedTab,
                showsAttachedBottomTabBar: shouldShowNotesSidebarAttachedTabBar
            )
        case .maps:
            MapsViewNew(
                isVisible: isVisible,
                externalSelectedFolder: $searchSelectedFolder,
                bottomTabSelection: $selectedTab,
                showsAttachedBottomTabBar: shouldShowMapsSidebarAttachedTabBar
            )
        }
    }

    @ViewBuilder
    private func homeTabContent(isVisible: Bool) -> some View {
        GeometryReader { geometry in
            InteractiveSidebarOverlay(
                isPresented: $showingHomeDrawer,
                canOpen: isVisible && activeOverlayRoute == nil,
                sidebarWidth: min(318, geometry.size.width * 0.84),
                colorScheme: colorScheme,
                onOverlayVisibilityChanged: handleHomeSidebarVisibilityChange
            ) {
                VStack(spacing: 0) {
                    HomeTabView(isVisible: isVisible) {
                        homeContentWithoutHeader
                    }
                    .frame(width: geometry.size.width)
                    .frame(maxHeight: .infinity)

                    if shouldShowHomeSidebarAttachedTabBar {
                        SidebarAttachedBottomTabBar(
                            selectedTab: $selectedTab,
                            bottomSafeAreaInset: geometry.safeAreaInsets.bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } sidebarContent: {
                homeDrawerContent
            }
        }
    }

    @ViewBuilder
    private func overlayRouteView(in geometry: GeometryProxy) -> some View {
        let planActive = activeOverlayRoute == .plan

        // PlanView is always in the hierarchy so it's pre-warmed — no cold-start cost on tap.
        // When hidden it sits off-screen (offset = screen width), so the GPU skips compositing it.
        // isVisible=false prevents email loading / avatar prefetch while hidden.
        ZStack {
            Color.appBackground(colorScheme)
                .ignoresSafeArea()
            PlanView(
                isVisible: planActive,
                selectedTab: $selectedPlanTab,
                onDetailNavigationChanged: { isShowingDetail in
                    isEmailDetailOpen = isShowingDetail
                },
                onClose: dismissOverlay
            )
        }
        .offset(x: planActive ? 0 : geometry.size.width)
        .allowsHitTesting(planActive)
        .animation(.navigationOverlayTransition, value: planActive)
        .zIndex(planActive ? 20 : 0)

        // All other overlays remain conditional — they are accessed infrequently
        // and don't benefit from pre-warming.
        if let route = activeOverlayRoute, route != .plan {
            ZStack {
                Color.appBackground(colorScheme)
                    .ignoresSafeArea()
                switch route {
                case .receipts:
                    receiptsOverlayContent(in: geometry)
                case .recurring:
                    recurringOverlayContent(in: geometry)
                case .people:
                    peopleOverlayContent(in: geometry)
                case .settings:
                    settingsOverlayContent
                case .plan:
                    EmptyView()
                }
            }
            .transition(.move(edge: .trailing))
            .zIndex(20)
        }
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
            // Use the pre-computed count from emailService (O(1)), then slice for display.
            let totalUnread = emailService.unreadInboxCount
            let unreadEmails = emailService.inboxEmails.lazy.filter { !$0.isRead }.prefix(5)

            if totalUnread == 0 {
                Text("No unread emails")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(Array(unreadEmails), id: \.id) { email in
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

                if totalUnread > 5 {
                    Button(action: {
                        openPlanInbox()
                    }) {
                        Text("... and \(totalUnread - 5) more")
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
                        openPlanCalendar()
                    }) {
                        HStack(spacing: 6) {
                            Group {
                                if task.isCompleted {
                                    ZStack {
                                        Circle()
                                            .fill(colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                } else {
                                    Image(systemName: "circle")
                                        .font(FontManager.geist(size: 12, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                }
                            }
                            .frame(width: 12, height: 12)

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
                        openPlanCalendar()
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
            // No specific email ID, just navigate to the inbox section of Plan
            openPlanInbox()
            return
        }

        // Find the email and show it
        if let email = emailService.inboxEmails.first(where: { $0.id == emailId }) {
            openPlanInbox()
            // Delay slightly to ensure tab is switched before showing email detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedEmail = email
            }
        } else {
            // Email not found, just navigate to the inbox section of Plan
            openPlanInbox()
        }
    }

    private func handleTaskNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo["taskId"] as? String else {
            // No specific task ID, just navigate to the calendar section of Plan
            openPlanCalendar()
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
            openPlanCalendar()
            // Delay slightly to ensure tab is switched before showing task detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedTask = task
                showingEditTask = false // Show in read mode
            }
        } else {
            // Task not found, just navigate to the calendar section of Plan
            openPlanCalendar()
        }
    }

    // MARK: - Search Bar Components

    // Search Bar Button
    private var searchBarView: some View {
        Button(action: {
            HapticManager.shared.selection()
            selectedTab = .search
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                Text("Search across your app...")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            openSettingsOverlay()
        }) {
            Group {
                if let resolvedProfilePictureURL,
                   let url = URL(string: resolvedProfilePictureURL) {
                    CachedAsyncImage(url: url.absoluteString) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(FontManager.geist(size: 36, weight: .medium))
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

    private func toggleHomeDrawer() {
        HapticManager.shared.selection()
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            showingHomeDrawer.toggle()
        }
    }

    // NEW: App-wide search bar for searching emails, events, notes, receipts, etc.
    private var appSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56))

            ZStack(alignment: .leading) {
                if searchText.isEmpty && !isSearchFocused {
                    Text("Search")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.28))
                        .allowsHitTesting(false)
                }

                TextField("", text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .opacity((searchText.isEmpty && !isSearchFocused) ? 0.02 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !searchText.isEmpty {
                Button(action: {
                    clearHomeSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.35))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 21)
        .contentShape(RoundedRectangle(cornerRadius: 21))
        .onChange(of: searchText) { _ in
            scheduleHomeSearchIndexRefresh()
        }
        .onReceive(searchIndex.$snapshotVersion) { _ in
            scheduleHomeSearchIndexRefresh()
        }
        .onTapGesture {
            isSearchFocused = true
        }
    }

    private var searchResultsDropdown: some View {
        let screenHeight = UIScreen.main.bounds.height
        let availableHeight = screenHeight - keyboardHeight - 180
        let dropdownHeight = max(220, min(screenHeight * 0.58, availableHeight))

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
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: dropdownHeight)
        .padding(6)
        .searchResultsCardStyle(colorScheme: colorScheme, cornerRadius: 22)
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
                Text(homeSearchBadgeLabel(for: result.type))
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
            .searchResultsRowStyle(colorScheme: colorScheme, cornerRadius: 14)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var searchBarContainer: some View {
        HStack(spacing: 10) {
            appSearchBar
            homeQuickAddButton
            homeProfileButton(size: 42)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }

    private var homeQuickAddButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                showingAddEventPopup = true
            }) {
                Label("Todo", systemImage: "checklist")
            }

            Button(action: {
                HapticManager.shared.selection()
                todoImportSourceType = .camera
                showingTodoPhotoImportSheet = true
            }) {
                Label("Todo Camera", systemImage: "camera.fill")
            }

            Button(action: {
                HapticManager.shared.selection()
                showingNewNoteSheet = true
            }) {
                Label("New Note", systemImage: "note.text.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func homeProfileButton(size: CGFloat) -> some View {
        Button(action: {
            toggleHomeDrawer()
        }) {
            Group {
                if let resolvedProfilePictureURL,
                   let url = URL(string: resolvedProfilePictureURL) {
                    CachedAsyncImage(url: url.absoluteString) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        homeProfileFallbackAvatar
                    }
                } else {
                    homeProfileFallbackAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.homeGlassInnerBorder(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await fetchUserProfilePicture()
        }
    }

    private var homeHeaderBar: some View {
        let hasGreeting = !homeGreetingText.isEmpty
        let avatarSize: CGFloat = hasGreeting ? 42 : 30
        let topPadding: CGFloat = hasGreeting ? 6 : 4
        let bottomPadding: CGFloat = hasGreeting ? 12 : 10

        return VStack(spacing: 0) {
            HStack(spacing: hasGreeting ? 12 : 0) {
                homeProfileButton(size: avatarSize)

                if hasGreeting {
                    Text(homeGreetingText)
                        .font(FontManager.geist(size: 20, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, homeCardHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)

            Rectangle()
                .fill(Color.homeGlassInnerBorder(colorScheme))
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var homeGreetingText: String {
        ""
    }

    @ViewBuilder
    private var homeComposeMenuContent: some View {
        Button(action: {
            HapticManager.shared.selection()
            showingAddEventPopup = true
        }) {
            Label("Todo", systemImage: "checklist")
        }

        Button(action: {
            HapticManager.shared.selection()
            todoImportSourceType = .camera
            showingTodoPhotoImportSheet = true
        }) {
            Label("Todo Camera", systemImage: "camera.fill")
        }

        Button(action: {
            HapticManager.shared.selection()
            showingNewNoteSheet = true
        }) {
            Label("New Note", systemImage: "note.text.badge.plus")
        }
    }

    private var homeFloatingComposeButton: some View {
        Menu {
            homeComposeMenuContent
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.black)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func notesShellFloatingComposeButton(for page: NotesFloatingActionPage) -> some View {
        switch page {
        case .notes:
            Menu {
                Button(action: {
                    HapticManager.shared.selection()
                    NotificationCenter.default.post(name: .notesShellNewNoteRequested, object: nil)
                }) {
                    Label("New Note", systemImage: "note.text.badge.plus")
                }

                Button(action: {
                    HapticManager.shared.selection()
                    NotificationCenter.default.post(name: .notesShellNewJournalRequested, object: nil)
                }) {
                    Label("New Journal", systemImage: "book.closed")
                }
            } label: {
                floatingComposeButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New note or journal")
        case .receipts:
            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .notesShellAddRequested, object: nil)
            }) {
                floatingComposeButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add receipt")
        case .recurring:
            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .notesShellAddRequested, object: nil)
            }) {
                floatingComposeButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add recurring expense")
        }
    }

    private var mapsShellFloatingComposeButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .mapsShellAddRequested, object: nil)
            }) {
                Label("Add Location", systemImage: "mappin.and.ellipse")
            }

            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .mapsShellNewFolderRequested, object: nil)
            }) {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        } label: {
            floatingComposeButtonLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add location or folder")
    }

    private var floatingComposeButtonLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .regular))
            .foregroundColor(.black)
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(Color.homeGlassAccent)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 10)
    }

    private var receiptsOverlayFloatingComposeButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                showingManualReceiptForm = true
            }) {
                Label("Add Manually", systemImage: "square.and.pencil")
            }

            Button(action: {
                HapticManager.shared.selection()
                showingReceiptCameraPicker = true
            }) {
                Label("Take Picture", systemImage: "camera.fill")
            }

            Button(action: {
                HapticManager.shared.selection()
                showingReceiptImagePicker = true
            }) {
                Label("Select Picture", systemImage: "photo.on.rectangle")
            }
        } label: {
            floatingComposeButtonLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add receipt")
    }

    private var recurringOverlayFloatingComposeButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            showingRecurringExpenseForm = true
        }) {
            floatingComposeButtonLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add recurring expense")
    }

    private var peopleOverlayFloatingComposeButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .peopleHubAddRequested, object: nil)
            }) {
                Label("Add Person", systemImage: "plus.circle")
            }

            Button(action: {
                HapticManager.shared.selection()
                NotificationCenter.default.post(name: .peopleHubImportRequested, object: nil)
            }) {
                Label("Import Contacts", systemImage: "square.and.arrow.down")
            }
        } label: {
            floatingComposeButtonLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add or import person")
    }

    private func overlayFloatingComposeInset<Content: View>(
        in geometry: GeometryProxy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.trailing, 16)
            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 22 : 16)
    }

    private var homeDrawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if let resolvedProfilePictureURL,
                       let url = URL(string: resolvedProfilePictureURL) {
                        CachedAsyncImage(url: url.absoluteString) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            homeProfileFallbackAvatar
                        }
                    } else {
                        homeProfileFallbackAvatar
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(authManager.currentUser?.profile?.name ?? "Seline")
                        .font(FontManager.geist(size: 24, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    if let email = authManager.currentUser?.profile?.email, !email.isEmpty {
                        Text(email)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                homeDrawerButton(title: "Home", systemImage: "house.fill") {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                        showingHomeDrawer = false
                    }
                }

                homeDrawerButton(
                    title: "Inbox",
                    systemImage: "tray.fill",
                    badgeCount: unreadInboxCount
                ) {
                    openPlanInbox()
                }

                homeDrawerButton(
                    title: "Calendar",
                    systemImage: "calendar",
                    badgeCount: todayTodoCount
                ) {
                    openPlanCalendar()
                }

                homeDrawerButton(title: "Sent", systemImage: "paperplane.fill") {
                    openPlanSent()
                }

                homeDrawerButton(title: "Receipts", systemImage: "receipt") {
                    openReceiptsInNotes()
                }

                homeDrawerButton(title: "Recurring", systemImage: "repeat") {
                    openRecurringInNotes()
                }

                homeDrawerButton(title: "People", systemImage: "person.2.fill") {
                    openPeopleOverlay()
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            homeDrawerButton(title: "Settings", systemImage: "gearshape.fill") {
                openSettingsOverlay()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .task {
            await fetchUserProfilePicture()
        }
    }

    private func formattedDrawerBadgeCount(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private func homeDrawerButton(
        title: String,
        systemImage: String,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.soft()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text(title)
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                if badgeCount > 0 {
                    Text(formattedDrawerBadgeCount(badgeCount))
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overlayCircleDismissButton: some View {
        Button(action: dismissOverlay) {
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
    }

    private var chromeDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    private func titledOverlayHeader(_ title: String) -> some View {
        HStack {
            overlayCircleDismissButton
                .frame(width: 44, height: 44)

            Spacer(minLength: 0)

            Text(title)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color.appBackground(colorScheme).opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(chromeDividerColor)
                .frame(height: 0.5)
        }
    }

    private func receiptsOverlayContent(in geometry: GeometryProxy) -> some View {
        NavigationStack {
            ReceiptStatsView()
            .background(Color.appBackground(colorScheme))
            .safeAreaInset(edge: .top) {
                titledOverlayHeader("Receipts")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            overlayFloatingComposeInset(in: geometry) {
                receiptsOverlayFloatingComposeButton
            }
        }
    }

    private func recurringOverlayContent(in geometry: GeometryProxy) -> some View {
        NavigationStack {
            RecurringExpenseStatsContent()
                .background(Color.appBackground(colorScheme))
                .safeAreaInset(edge: .top) {
                    titledOverlayHeader("Recurring")
                }
        }
        .overlay(alignment: .bottomTrailing) {
            overlayFloatingComposeInset(in: geometry) {
                recurringOverlayFloatingComposeButton
            }
        }
    }

    private func peopleOverlayContent(in geometry: GeometryProxy) -> some View {
        NavigationStack {
            PeopleListView(
                peopleManager: peopleManager,
                locationsManager: locationsManager,
                colorScheme: colorScheme,
                searchText: "",
                isSearchActive: $isPeopleOverlaySearchActive
            )
            .background(Color.appBackground(colorScheme))
            .safeAreaInset(edge: .top) {
                titledOverlayHeader("People")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            overlayFloatingComposeInset(in: geometry) {
                peopleOverlayFloatingComposeButton
            }
        }
    }

    private var settingsOverlayContent: some View {
        SettingsView()
            .safeAreaInset(edge: .top) {
                titledOverlayHeader("Settings")
            }
    }

    private var homeProfileFallbackAvatar: some View {
        Group {
            if let name = authManager.currentUser?.profile?.name,
               let firstChar = name.first {
                Circle()
                    .fill(Color.appChip(colorScheme))
                    .overlay(
                        Text(String(firstChar).uppercased())
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    )
            } else {
                Circle()
                    .fill(Color.appChip(colorScheme))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    )
            }
        }
    }

    private var homeSearchBackdrop: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 58)

            LinearGradient(
                colors: [
                    Color.appBackground(colorScheme).opacity(colorScheme == .dark ? 0.76 : 0.62),
                    Color.appBackground(colorScheme).opacity(colorScheme == .dark ? 0.92 : 0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .contentShape(Rectangle())
            .onTapGesture {
                clearHomeSearch()
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity)
    }

    private var homeSearchResultsOverlay: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 54)

            searchResultsDropdown
                .padding(.horizontal, homeCardHorizontalPadding)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity)
    }

    private func mainContentWidgets() -> some View {
        HomeWidgetStackView(
            homeState: homeState,
            isVisible: selectedTab == .home,
            isDailyOverviewExpanded: $isDailyOverviewExpanded,
            currentLocationName: currentLocationName,
            nearbyLocation: nearbyLocation,
            nearbyLocationFolder: nearbyLocationFolder,
            nearbyLocationPlace: nearbyLocationPlace,
            distanceToNearest: distanceToNearest,
            selectedPlace: $selectedLocationPlace,
            showAllLocationsSheet: $showAllLocationsSheet,
            onNoteSelected: { note in
                selectedNoteToOpen = note
            },
            onEmailSelected: { email in
                searchSelectedEmail = email
            },
            onTaskSelected: { task in
                searchSelectedTask = task
            },
            onPersonSelected: { person in
                selectedPersonForDetail = person
            },
            onAddTask: {
                showingAddEventPopup = true
            },
            onAddTaskFromPhoto: {
                todoImportSourceType = .camera
                showingTodoPhotoImportSheet = true
            },
            onAddNote: {
                showingNewNoteSheet = true
            },
            onAddReceiptManually: {
                HapticManager.shared.selection()
                showingManualReceiptForm = true
            },
            onAddReceiptFromCamera: {
                HapticManager.shared.selection()
                showingReceiptCameraPicker = true
            },
            onAddReceiptFromGallery: {
                HapticManager.shared.selection()
                showingReceiptImagePicker = true
            },
            onReceiptSelected: { receipt in
                handleSpendingReceiptSelection(receipt)
            },
            onRefresh: {
                Task {
                    pageRefreshCoordinator.markDirty(.home, reason: .manualRefresh)
                    await refreshAllData()
                    await MainActor.run {
                        homeState.refreshAll()
                    }
                }
            }
        )
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
    
    // MARK: - Widget Views
    
    @ViewBuilder
    private func widgetView(for type: HomeWidgetType) -> some View {
        switch type {
        case .dailyOverview:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .dailyOverview) {
                DailyOverviewWidget(
                    homeState: homeState,
                    isExpanded: $isDailyOverviewExpanded,
                    isVisible: selectedTab == .home,
                    currentLocationName: currentLocationName,
                    nearbyLocation: nearbyLocation,
                    nearbyLocationPlace: nearbyLocationPlace,
                    distanceToNearest: distanceToNearest,
                    onNoteSelected: { note in
                        selectedNoteToOpen = note
                    },
                    onEmailSelected: { email in
                        searchSelectedEmail = email
                    },
                    onTaskSelected: { task in
                        searchSelectedTask = task
                    },
                    onPersonSelected: { person in
                        selectedPersonForDetail = person
                    },
                    onLocationSelected: { place in
                        selectedLocationPlace = place
                    },
                    onAddTask: {
                        showingAddEventPopup = true
                    },
                    onAddTaskFromPhoto: {
                        todoImportSourceType = .camera
                        showingTodoPhotoImportSheet = true
                    },
                    onAddNote: {
                        showingNewNoteSheet = true
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .zIndex(isDailyOverviewExpanded ? 10 : 1)
            
        case .spending:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .spending) {
                SpendingAndETAWidget(
                    isVisible: selectedTab == .home,
                    onAddReceiptManually: {
                        HapticManager.shared.selection()
                        showingManualReceiptForm = true
                    },
                    onAddReceipt: {
                        HapticManager.shared.selection()
                        showingReceiptCameraPicker = true
                    },
                    onAddReceiptFromGallery: {
                        HapticManager.shared.selection()
                        showingReceiptImagePicker = true
                    },
                    onReceiptSelected: { receipt in
                        handleSpendingReceiptSelection(receipt)
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .padding(.top, 4)
            .padding(.bottom, 6)
            
        case .currentLocation:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .currentLocation) {
                CurrentLocationCardWidget(
                    currentLocationName: currentLocationName,
                    nearbyLocation: nearbyLocation,
                    nearbyLocationFolder: nearbyLocationFolder,
                    nearbyLocationPlace: nearbyLocationPlace,
                    distanceToNearest: distanceToNearest,
                    todaysVisits: homeState.todaysVisits,
                    isVisible: selectedTab == .home,
                    selectedPlace: $selectedLocationPlace,
                    showAllLocationsSheet: $showAllLocationsSheet
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .events:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .events) {
                EventsCardWidget(
                    showingAddEventPopup: $showingAddEventPopup,
                    onTaskSelected: { task in
                        searchSelectedTask = task
                    },
                    onOpenEvents: {
                        openPlanCalendar()
                    }
                )
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
                    },
                    onOpenInbox: {
                        openPlanInbox()
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .allowsHitTesting(!isDailyOverviewExpanded)
            
        case .pinnedNotes:
            EmptyView()
            
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
        _ = await MainActor.run {
            dismissedVisitReasonIds.insert(visit.id)
        }

        print("✅ Visit reason saved: '\(reason)' for \(place.displayName)")
    }

    // MARK: - Home Content
    private var homeCardHorizontalPadding: CGFloat {
        ShadcnSpacing.screenEdgeHorizontal
    }

    private var homeContentWithoutHeader: some View {
        VStack(spacing: 0) {
            homeHeaderBar

            VStack(spacing: 0) {
                visitReasonPopupSection
                mainContentWidgets()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            HomeGlassBackgroundLayer(colorScheme: colorScheme)
        )
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
            .padding(.horizontal, homeCardHorizontalPadding)
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
    
    private func getTabEdge(for tab: PrimaryTab, isRemoval: Bool = false) -> Edge {
        let tabs = PrimaryTab.allCases
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
        Task {
            await MainActor.run {
                receiptProcessingState = .processing
            }
            
            do {
                let draft = try await GeminiService.shared.analyzeReceiptImageDraft(image)
                let receipt = try await receiptManager.createReceipt(from: draft, images: [image])

                await MainActor.run {
                    HapticManager.shared.success()
                    selectedReceiptToOpen = receipt
                    receiptProcessingState = .success

                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            receiptProcessingState = .idle
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

    private func processNextReceiptInQueue() {
        guard currentProcessingIndex < processingQueue.count else {
            // All receipts processed, clear the queue
            processingQueue = []
            currentProcessingIndex = 0

            // Hide the success message after 1 second
            receiptProcessingTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    receiptProcessingState = .idle
                }
            }
            return
        }

        let image = processingQueue[currentProcessingIndex]
        let totalCount = processingQueue.count
        let currentNumber = currentProcessingIndex + 1

        print("📸 Processing receipt \(currentNumber) of \(totalCount)")

        receiptProcessingTask = Task {
            // Show processing indicator with count
            await MainActor.run {
                if totalCount > 1 {
                    receiptProcessingState = .processingMultiple(current: currentNumber, total: totalCount)
                } else {
                    receiptProcessingState = .processing
                }
            }

            guard !Task.isCancelled else { return }

            do {
                let draft = try await GeminiService.shared.analyzeReceiptImageDraft(image)
                _ = try await receiptManager.createReceipt(from: draft, images: [image])

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    HapticManager.shared.success()
                    print("✅ Receipt \(currentNumber) of \(totalCount) saved")
                    currentProcessingIndex += 1
                    receiptProcessingState = .success
                }

                // Advance to next receipt after a short pause
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    processNextReceiptInQueue()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    print("❌ Error processing receipt \(currentNumber): \(error.localizedDescription)")
                    HapticManager.shared.error()
                    receiptProcessingState = .error(error.localizedDescription)
                }

                // Skip this receipt and move to next after showing error
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    currentProcessingIndex += 1
                    processNextReceiptInQueue()
                }
            }
        }
    }

    // MARK: - User Profile

    private func fetchUserProfilePicture() async {
        let shouldFetch = await MainActor.run { () -> Bool in
            if profilePictureUrl != nil || isFetchingProfilePicture {
                return false
            }

            isFetchingProfilePicture = true
            return true
        }

        guard shouldFetch else { return }
        defer {
            Task { @MainActor in
                isFetchingProfilePicture = false
            }
        }

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

private struct ShellFloatingComposeButton: View {
    let selectedTab: PrimaryTab
    @ObservedObject var coordinator: FloatingActionCoordinator
    let homeButton: AnyView
    let notesButton: (NotesFloatingActionPage) -> AnyView
    let mapsButton: AnyView

    @ViewBuilder
    var body: some View {
        switch selectedTab {
        case .home:
            homeButton
        case .notes:
            if coordinator.isNotesFloatingActionVisible {
                notesButton(coordinator.notesFloatingActionPage)
            }
        case .maps:
            if coordinator.isMapsFloatingActionVisible {
                mapsButton
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}
