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
    @StateObject private var locationsManager = LocationsManager.shared
    private let locationService = LocationService.shared
    @StateObject private var geofenceManager = GeofenceManager.shared
    private let searchService = SearchService.shared
    private let widgetManager = WidgetManager.shared
    private let emailService = EmailService.shared
    private let taskManager = TaskManager.shared
    private let notesManager = NotesManager.shared
    private let tagManager = TagManager.shared
    private let peopleManager = PeopleManager.shared
    private let locationSuggestionService = LocationSuggestionService.shared
    private let visitState = VisitStateManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
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
    @State private var showingReceiptAddOptions = false
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var selectedReceiptImages: [UIImage] = []
    @State private var processingQueue: [UIImage] = []
    @State private var currentProcessingIndex = 0
    @State private var showingSettings = false
    @State private var profilePictureUrl: String? = nil
    @State private var hasAppeared = false
    @State private var dismissedVisitReasonIds: Set<UUID> = [] // Track visits where user dismissed the reason popup
    @State private var isSidebarOverlayVisible = false
    @State private var isEmailDetailOpen = false
    @State private var syncedWidgetVisitId: UUID? = nil
    @State private var loadTodaysVisitsTask: Task<Void, Never>?
    @State private var allLocationsRefreshTask: Task<Void, Never>?
    @State private var lastAllLocationsRefreshAt: Date = .distantPast
    @State private var isFetchingProfilePicture = false
    @State private var isViewingNoteInNavigation = false

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

    private func clearHomeSearch() {
        searchText = ""
        searchResults = []
        isSearchFocused = false
    }

    private func homeSearchBadgeLabel(for type: OverlaySearchResultType) -> String {
        switch type {
        case .email:
            return "Email"
        case .event:
            return "Event"
        case .note:
            return "Note"
        case .location:
            return "Place"
        case .folder:
            return "Folder"
        case .receipt:
            return "Receipt"
        case .recurringExpense:
            return "Recurring"
        }
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

        let matchingEmails = index.emails.filter {
            $0.subjectLower.contains(lowercasedSearch) ||
            $0.senderLower.contains(lowercasedSearch) ||
            $0.snippetLower.contains(lowercasedSearch)
        }

        // Limit to 3 most relevant emails for faster search
        for email in matchingEmails.prefix(3) {
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

        let matchingReceipts = index.receipts.filter {
            $0.titleLower.contains(lowercasedSearch) ||
                $0.categoryLower.contains(lowercasedSearch) ||
                $0.noteTextLower.contains(lowercasedSearch)
        }

        // Limit to 3 most relevant receipts for faster search
        for receipt in matchingReceipts.prefix(3) {
            if let note = receipt.note {
                let dateString = FormatterCache.shortDate.string(from: receipt.receipt.date)

                results.append(OverlaySearchResult(
                    type: .receipt,
                    title: receipt.receipt.title,
                    subtitle: "\(CurrencyParser.formatAmount(receipt.receipt.amount)) • \(dateString)",
                    icon: "doc.text",
                    task: nil,
                    email: nil,
                    note: note,
                    location: nil,
                    category: receipt.receipt.category
                ))
            }
        }

        let matchingNotes = index.notes.filter {
            $0.isSearchable &&
                ($0.titleLower.contains(lowercasedSearch) ||
                 $0.contentLower.contains(lowercasedSearch))
        }

        // Limit to 3 most relevant notes for faster search
        for note in matchingNotes.prefix(3) {
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

        let matchingLocations = index.locations.filter {
            $0.nameLower.contains(lowercasedSearch) ||
            $0.addressLower.contains(lowercasedSearch) ||
            $0.customNameLower.contains(lowercasedSearch)
        }

        // Limit to 3 most relevant locations for faster search
        for location in matchingLocations.prefix(3) {
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

        let matchingExpenses = index.expenses.filter {
            $0.titleLower.contains(lowercasedSearch) ||
                $0.categoryLower.contains(lowercasedSearch) ||
                $0.descriptionLower.contains(lowercasedSearch)
        }

        // Limit to 3 most relevant expenses for faster search
        for expense in matchingExpenses.prefix(3) {
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
        let receiptSummaries = notesManager.getReceiptStatistics()
        let receiptsSnapshot = receiptSummaries.flatMap { yearSummary in
            yearSummary.monthlySummaries.flatMap { $0.receipts }
        }

        let folderParentById = Dictionary(uniqueKeysWithValues: foldersSnapshot.map { ($0.id, $0.parentFolderId) })
        let receiptFolderIds = Set(
            foldersSnapshot
                .filter { $0.name.caseInsensitiveCompare("Receipts") == .orderedSame }
                .map(\.id)
        )
        let notesById = Dictionary(uniqueKeysWithValues: notesSnapshot.map { ($0.id, $0) })
        let receiptNoteIds = Set(receiptsSnapshot.map(\.noteId))

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
                let note = notesById[receipt.noteId]
                return HomeSearchIndex.ReceiptEntry(
                    receipt: receipt,
                    note: note,
                    titleLower: receipt.title.lowercased(),
                    categoryLower: receipt.category.lowercased(),
                    noteTextLower: note?.displayContent.lowercased() ?? ""
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
        homeSearchIndexRefreshTask?.cancel()
        homeSearchIndexRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let nextIndex = buildHomeSearchIndex()
            guard !Task.isCancelled else { return }

            homeSearchIndex = nextIndex

            let query = trimmedHomeSearchText
            guard !query.isEmpty, !shouldSuppressHomeSearchResults else { return }

            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                let capturedQuery = query
                let capturedIndex = nextIndex
                DispatchQueue.global(qos: .userInitiated).async {
                    let results = performSearchComputation(query: capturedQuery, index: capturedIndex)
                    DispatchQueue.main.async {
                        if trimmedHomeSearchText == capturedQuery {
                            searchResults = results
                        }
                    }
                }
            }
        }
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
            case "chat":
                deepLinkHandler.shouldShowChat = false
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
            if let note = result.note {
                selectedNoteToOpen = note
            }
        case .recurringExpense:
            // Navigate to receipt stats view which shows recurring expenses
            showReceiptStats = true
        }

        // Dismiss search after setting the state
        isSearchFocused = false
        searchText = ""
    }

    private func handleSpendingReceiptSelection(_ receipt: ReceiptStat) {
        guard let note = notesManager.notes.first(where: { $0.id == receipt.noteId }) else {
            print("⚠️ Could not find note for receipt noteId: \(receipt.noteId)")
            return
        }

        HapticManager.shared.cardTap()
        selectedNoteToOpen = note
    }

    // MARK: - Tab Navigation Helpers

    private func previousTab() {
        let allTabs = TabSelection.allCases
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
        let allTabs = TabSelection.allCases
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

    var body: some View {
        mainContent
            .onChange(of: searchText) { newValue in
                searchDebounceTask?.cancel()

                let trimmedQuery = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedQuery.isEmpty {
                    searchService.cancelAction()
                    searchResults = []
                } else if shouldSuppressHomeSearchResults {
                    searchResults = []
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }

                        let query = trimmedQuery
                        let index = homeSearchIndex
                        DispatchQueue.global(qos: .userInitiated).async {
                            let results = performSearchComputation(query: query, index: index)
                            DispatchQueue.main.async {
                                if trimmedHomeSearchText == query {
                                    searchResults = results
                                }
                            }
                        }
                    }
                }
            }
            .onReceive(searchService.$pendingEventCreation.dropFirst()) { _ in
                activateConversationModalIfNeeded()
            }
            .onReceive(searchService.$pendingNoteCreation.dropFirst()) { _ in
                activateConversationModalIfNeeded()
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

    private var mainContentObserved: AnyView {
        AnyView(
            mainContentBase
                .onAppear {
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    isViewingNoteInNavigation = notesManager.isViewingNoteInNavigation
                    pageRefreshCoordinator.markDirty(TabSelection.allCases, reason: .initialLoad)
                    pageRefreshCoordinator.pageBecameVisible(selectedTab)

                    taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                    deepLinkHandler.processPendingAction()
                    Task {
                        await fetchUserProfilePicture()
                    }
                    scheduleHomeSearchIndexRefresh()

                    Task {
                        let (mergedCount, deletedCount) = await LocationVisitAnalytics.shared.mergeAndCleanupVisits()
                        if mergedCount > 0 || deletedCount > 0 {
                            print("🧹 On app startup - Merged \(mergedCount) visit(s), deleted \(deletedCount) short visit(s)")
                        }
                    }

                    locationService.requestLocationPermission()
                    geofenceManager.requestLocationPermission()

                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await geofenceManager.loadIncompleteVisitsFromSupabase()
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
                    scheduleHomeSearchIndexRefresh()
                }
                .onReceive(notesManager.$notes) { _ in
                    scheduleHomeSearchIndexRefresh()
                }
                .onReceive(notesManager.$folders) { _ in
                    scheduleHomeSearchIndexRefresh()
                }
                .onReceive(notesManager.$isViewingNoteInNavigation.removeDuplicates()) { isViewing in
                    isViewingNoteInNavigation = isViewing
                }
                .onChange(of: showAllLocationsSheet) { isPresented in
                    guard isPresented else { return }
                    refreshAllLocationRankingsIfNeeded(force: allLocations.isEmpty)
                }
                .onReceive(taskManager.$tasks) { _ in
                    pageRefreshCoordinator.markDirty([.home, .email], reason: .taskDataChanged)
                    taskManager.syncTodaysTasksToWidget(tags: tagManager.tags)
                    scheduleHomeSearchIndexRefresh()
                }
                .onReceive(emailService.$inboxEmails) { _ in
                    scheduleHomeSearchIndexRefresh()
                }
                .onReceive(emailService.$sentEmails) { _ in
                    scheduleHomeSearchIndexRefresh()
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
                    pageRefreshCoordinator.pageBecameVisible(newTab)

                    if newTab == .home {
                        revalidateHomeIfNeeded(reason: .initialLoad)
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
                .onReceive(NotificationCenter.default.publisher(for: .interactiveSidebarVisibilityChanged)) { notification in
                    let isVisible = (notification.userInfo?["isVisible"] as? Bool) ?? false
                    isSidebarOverlayVisible = isVisible
                }
        )
    }

    private var mainContentPresented: AnyView {
        AnyView(
            mainContentObserved
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
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .presentationDetents([.large])
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
                        onAddReceipt: {
                            HapticManager.shared.buttonTap()
                            showingReceiptAddOptions = true
                        },
                        isPopup: true
                    )
                    .presentationDetents([.fraction(0.6), .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
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
                .confirmationDialog("Add Receipt", isPresented: $showingReceiptAddOptions, titleVisibility: .visible) {
                    Button("Take Picture") {
                        HapticManager.shared.buttonTap()
                        showingReceiptCameraPicker = true
                    }
                    Button("Upload Images") {
                        HapticManager.shared.buttonTap()
                        showingReceiptImagePicker = true
                    }
                    Button("Cancel", role: .cancel) {}
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
        )
    }

    private var mainContentBase: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                mainContentVStack(geometry: geometry)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.appBackground(colorScheme))
        }
    }

    private var shouldShowFloatingTabBar: Bool {
        keyboardHeight == 0 &&
        selectedNoteToOpen == nil &&
        !showingNewNoteSheet &&
        searchSelectedNote == nil &&
        searchSelectedEmail == nil &&
        searchSelectedTask == nil &&
        !authManager.showLocationSetup &&
        !isViewingNoteInNavigation &&
        !isSidebarOverlayVisible &&
        !isEmailDetailOpen
    }

    private func bottomTabBarVerticalOffset(for geometry: GeometryProxy) -> CGFloat {
        geometry.safeAreaInsets.bottom > 0 ? 10 : 4
    }

    private func mainContentVStack(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            activeTabContent
                .frame(maxHeight: .infinity)

            if shouldShowFloatingTabBar {
                BottomTabBar(selectedTab: $selectedTab)
                    .padding(.top, -bottomTabBarVerticalOffset(for: geometry))
                    .offset(y: bottomTabBarVerticalOffset(for: geometry))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(Color.appBackground(colorScheme))
        // Swipe gestures disabled - user requested removal of left/right swipe navigation
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .home:
            HomeTabView(isVisible: true) {
                homeContentWithoutHeader
            }
        case .email:
            EmailView(
                isVisible: true,
                onDetailNavigationChanged: { isShowingDetail in
                    isEmailDetailOpen = isShowingDetail
                }
            )
        case .events:
            EventsView(isVisible: true)
        case .notes:
            NotesView(isVisible: true)
        case .maps:
            MapsViewNew(isVisible: true, externalSelectedFolder: $searchSelectedFolder)
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
                    searchText = ""
                    searchResults = []
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
        .padding(8)
        .homeGlassCardStyle(colorScheme: colorScheme, cornerRadius: 22, highlightStrength: 0.85)
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
            .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 14)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var searchBarContainer: some View {
        HStack(spacing: 10) {
            appSearchBar
            homeQuickAddButton
            homeProfileButton
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

    private var homeProfileButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            showingSettings = true
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
            .frame(width: 42, height: 42)
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
            Color.clear.frame(height: 92)

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
            Color.clear.frame(height: 86)

            searchResultsDropdown
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity)
    }

    private var mainContentWidgets: some View {
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
            onAddReceiptTapped: {
                showingReceiptAddOptions = true
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
                    }
                )
            }
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .zIndex(isDailyOverviewExpanded ? 10 : 1)
            
        case .spending:
            ReorderableWidgetContainer(widgetManager: widgetManager, type: .spending) {
                SpendingAndETAWidget(
                    isVisible: selectedTab == .home,
                    onAddReceiptTapped: {
                        showingReceiptAddOptions = true
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
                        selectedTab = .events
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
    private var homeContentWithoutHeader: some View {
        ZStack(alignment: .top) {
            HomeGlassBackgroundLayer(colorScheme: colorScheme)

            if isHomeSearchPresented {
                homeSearchBackdrop
                    .zIndex(90)
            }
            
            VStack(spacing: 0) {
                searchBarContainer
                    .padding(.top, -8)
                    .zIndex(120)

                VStack(spacing: 0) {
                    visitReasonPopupSection
                    mainContentWidgets
                }
                .allowsHitTesting(!isHomeSearchPresented)
            }
            .background(Color.clear)
            .zIndex(100)

            if !trimmedHomeSearchText.isEmpty {
                homeSearchResultsOverlay
                    .zIndex(110)
            }
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
                // Use GeminiService (which delegates to OpenAI for vision) - same as receipts page
                let deepSeekService = GeminiService.shared
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
                let newNote = Note(title: receiptTitle, content: cleanedContent, folderId: folderIdForReceipt)
                
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

    private func processNextReceiptInQueue() {
        guard currentProcessingIndex < processingQueue.count else {
            // All receipts processed, clear the queue
            processingQueue = []
            currentProcessingIndex = 0

            // Hide the success message after 1 second
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
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

        Task {
            // Show processing indicator with count
            await MainActor.run {
                if totalCount > 1 {
                    receiptProcessingState = .processingMultiple(current: currentNumber, total: totalCount)
                } else {
                    receiptProcessingState = .processing
                }
            }

            do {
                // Use GeminiService (which delegates to OpenAI for vision)
                let deepSeekService = GeminiService.shared
                let (receiptTitle, receiptContent) = try await deepSeekService.analyzeReceiptImage(image)

                // Clean up the extracted content
                let cleanedContent = receiptContent
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                // Extract month and year from receipt title for automatic folder organization
                var folderIdForReceipt: UUID?
                if let (month, year) = notesManager.extractMonthYearFromTitle(receiptTitle) {
                    folderIdForReceipt = await notesManager.getOrCreateReceiptMonthFolderAsync(month: month, year: year)
                    print("✅ Receipt assigned to \(notesManager.getMonthName(month)) \(year)")
                } else {
                    let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
                    folderIdForReceipt = receiptsFolderId
                    print("⚠️ No date found in receipt title, using main Receipts folder")
                }

                // Create note with receipt content
                let newNote = Note(title: receiptTitle, content: cleanedContent, folderId: folderIdForReceipt)

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
                        print("✅ Receipt \(currentNumber) of \(totalCount) saved")

                        // Move to next receipt in queue
                        currentProcessingIndex += 1

                        // Show success briefly before processing next
                        receiptProcessingState = .success
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            await MainActor.run {
                                processNextReceiptInQueue()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Error processing receipt \(currentNumber): \(error.localizedDescription)")
                    HapticManager.shared.error()
                    receiptProcessingState = .error(error.localizedDescription)

                    // Skip this receipt and move to next after showing error
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await MainActor.run {
                            currentProcessingIndex += 1
                            processNextReceiptInQueue()
                        }
                    }
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

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}
