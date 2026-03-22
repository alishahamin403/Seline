import SwiftUI
import Auth
import GoogleSignIn
import UserNotifications
import EventKit
import BackgroundTasks
import WidgetKit

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}

func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {}

@main
struct SelineApp: App {
    private enum BackgroundTaskIdentifier {
        static let emailRefresh = "com.seline.app.emailRefresh"
    }

    // OPTIMIZATION: Centralize all shared managers at app level
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var searchService = SearchService.shared
    @StateObject private var geofenceManager = GeofenceManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var emailService = EmailService.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var tagManager = TagManager.shared
    @State private var lastCalendarSyncTime: Date = Date.distantPast
    @State private var isCalendarSyncing: Bool = false
    @State private var foregroundMaintenanceTask: Task<Void, Never>? = nil
    @State private var foregroundWarmupTask: Task<Void, Never>? = nil

    init() {
        ScrollExperienceConfigurator.installGlobalAppearance()
        NavigationSwipeBack.installGlobalSupport()
        configureSupabase()
        configureGoogleSignIn()
        configureNotifications()
        configureBackgroundRefresh()
        configureLocationServices()
        // Sync calendar events on launch to ensure calendar permission is granted and events are fetched
        syncCalendarEventsOnFirstLaunch()
        migrateReceiptCategoriesIfNeeded()

        // FIX: Update haircut memory (run once to fix database)
        Task {
            try? await UserMemoryService.shared.fixHaircutMemory()
        }

        // Refresh widget spending data on app launch
        // This ensures the widget shows current data even if the app was killed
        refreshWidgetDataOnLaunch()

        // One-time embedding reindex on next launch (improves LLM recall)
        Task.detached(priority: .utility) {
            let flagKey = "didRunEmbeddingReindex_v1"
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: flagKey) { return }
            guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return }

            print("🔁 One-time embedding reindex starting...")
            await VectorSearchService.shared.syncAllEmbeddings()
            defaults.set(true, forKey: flagKey)
            print("✅ One-time embedding reindex complete")
        }

        // DISABLED: Nuclear reset was causing app to hang on startup
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        //     Task {
        //         print("🧹 Clearing corrupted local task cache...")
        //         await TaskManager.shared.nuclearReset()
        //     }
        // }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(notificationService)
                .environmentObject(taskManager)
                .environmentObject(deepLinkHandler)
                .environmentObject(searchService)
                .environmentObject(geofenceManager)
                .environmentObject(locationsManager)
                .environmentObject(emailService)
                .environmentObject(notesManager)
                .environmentObject(locationService)
                .environmentObject(weatherService)
                .environmentObject(navigationService)
                .environmentObject(tagManager)
                .onOpenURL { url in
                    print("🚀 SelineApp: .onOpenURL triggered with URL: \(url.absoluteString)")
                    print("🚀 SelineApp: Passing to deepLinkHandler")
                    deepLinkHandler.handleURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    handleAppDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    foregroundMaintenanceTask?.cancel()
                    foregroundWarmupTask?.cancel()
                    EmailService.shared.suspendForegroundRefresh()
                    // App entered background - save current state
                    // Save current conversation to history before app closes
                    if !searchService.conversationHistory.isEmpty {
                        searchService.saveConversationToHistory()
                        print("💾 Current conversation saved to history before background")
                        Task {
                            await searchService.saveConversationToSupabase()
                        }
                    }
                    // Ask iOS for a fresh background sync window as the app backgrounds.
                    scheduleBackgroundRefresh()
                    LocationBackgroundTaskService.shared.scheduleLocationRefresh()
                    print("App entered background - scheduled background sync")
                }
        }
    }

    private func configureSupabase() {
        // TODO: Configure Supabase when we integrate it
    }

    @MainActor
    private func handleAppDidBecomeActive() {
        foregroundMaintenanceTask?.cancel()
        foregroundWarmupTask?.cancel()

        ScrollExperienceConfigurator.applyToVisibleScrollViews()
        WidgetInvalidationCoordinator.shared.requestReload(reason: "app_active")
        updateUnreadBadge()

        foregroundMaintenanceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            GeofenceManager.shared.setupGeofences(for: LocationsManager.shared.savedPlaces)
            await EmailService.shared.activateForegroundRefresh()
            guard !Task.isCancelled else { return }

            await searchService.loadConversationsFromSupabase()
            guard !Task.isCancelled else { return }

            await searchService.refreshTrackerThreadsFromSupabase()
            guard !Task.isCancelled else { return }

            updateUnreadBadge()
            await syncCalendarEventsIfNeeded()

            scheduleForegroundWarmups()
        }
    }

    @MainActor
    private func updateUnreadBadge() {
        let unreadCount = EmailService.shared.inboxEmails.filter { !$0.isRead }.count
        notificationService.updateAppBadge(count: unreadCount)
    }

    @MainActor
    private func syncCalendarEventsIfNeeded() async {
        let timeSinceLastSync = Date().timeIntervalSince(lastCalendarSyncTime)
        guard timeSinceLastSync > 60, !isCalendarSyncing else { return }

        isCalendarSyncing = true
        lastCalendarSyncTime = Date()
        defer { isCalendarSyncing = false }

        await taskManager.syncCalendarEvents()
    }

    @MainActor
    private func scheduleForegroundWarmups() {
        foregroundWarmupTask?.cancel()
        foregroundWarmupTask = Task.detached(priority: .utility) {
            await MainActor.run {
                _ = TaskManager.shared.getAllFlattenedTasks()
            }
            _ = await LocationVisitAnalytics.shared.getTodaysVisitsWithDuration()

            await MainActor.run {
                SpendingAndETAWidget.refreshWidgetSpendingData()
            }

            let midnightResult = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
            if midnightResult.fixed > 0 {
                print("🌙 Startup cleanup: Fixed \(midnightResult.fixed) midnight-spanning visits")
            }

            await VectorSearchService.shared.syncEmbeddingsIfNeeded()

            print("🔥 Cache warming complete")
        }
    }

    private func configureGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("Warning: GoogleService-Info.plist not found or CLIENT_ID missing")
            return
        }

        // Configure with both iOS client ID and web client ID for Supabase
        let webClientId = "729504866074-ko97g0j9o0o495cl634okidkim5hfsd3.apps.googleusercontent.com"
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientId,
            serverClientID: webClientId
        )
    }

    private func configureNotifications() {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Request notification permissions on app launch
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                // DEBUG: Commented out to reduce console spam
                // print("✅ Notification permissions granted")
            } else {
                print("❌ Notification permissions denied")
            }
        }
    }

    private func configureBackgroundRefresh() {
        // CONSOLIDATED: Single unified background task for all syncing operations
        // Combines email refresh, location checks, and data sync into one efficient task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskIdentifier.emailRefresh, using: nil) { task in
            Task {
                // Check if device is in low power mode
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    print("⚠️ Skipping background sync - device in low power mode")
                    task.setTaskCompleted(success: true)
                    return
                }

                print("🔄 Consolidated background sync started")

                // Perform email and data sync operations in parallel
                // Note: Location checks run separately via LocationBackgroundTaskService
                await withTaskGroup(of: Void.self) { group in
                    // Email refresh (most important for user notifications)
                    group.addTask {
                        await EmailService.shared.handleBackgroundRefresh()
                    }

                    // Vector embedding sync (keeps semantic search up-to-date)
                    group.addTask {
                        await VectorSearchService.shared.syncEmbeddingsIfNeeded()
                    }
                }

                print("✅ Consolidated background sync completed")

                // Schedule next sync (15 minutes - iOS minimum)
                self.scheduleBackgroundRefresh()

                // Mark task as completed
                task.setTaskCompleted(success: true)
            }
        }

        // CRITICAL: Still register location background tasks separately for reliable geofence detection
        // iOS geofencing can be delayed - location service needs its own checks
        LocationBackgroundTaskService.shared.registerBackgroundTasks()

        // Schedule initial sync
        scheduleBackgroundRefresh()

        // Schedule location-specific tasks (these are lightweight and time-critical)
        LocationBackgroundTaskService.shared.scheduleLocationRefresh()
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.emailRefresh)
        // Schedule refresh in 15 minutes (iOS minimum for app refresh)
        // This consolidated task handles all background sync operations
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Consolidated background sync scheduled for 15 minutes from now")
        } catch {
            print("⚠️ Failed to schedule background sync: \(error)")
        }
    }

    private func syncCalendarEventsOnFirstLaunch() {
        // Defer and gate launch sync to avoid blocking cold start.
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)

            guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return }

            let persistedLastSync = CalendarSyncService.shared.getLastSyncDate() ?? Date.distantPast
            guard Date().timeIntervalSince(persistedLastSync) > (4 * 60 * 60) else { return }

            let hasAccess = await taskManager.requestCalendarAccess()
            guard hasAccess else { return }

            await taskManager.syncCalendarEvents()
        }
    }

    private func migrateReceiptCategoriesIfNeeded() {
        // Only run if migration hasn't been completed yet
        if ReceiptCategorizationService.shared.hasCompletedMigration() {
            return
        }

        // Run migration asynchronously in background
        Task {
            print("📋 [SelineApp] Checking for receipt categories that need migration...")
            await ReceiptCategorizationService.shared.migrateOldServices()
        }
    }

    private func configureLocationServices() {
        // CRITICAL: Initialize location services at app launch for background geofencing
        // This ensures GeofenceManager is ready to handle background location events
        // even when the app is killed and iOS wakes it up for a geofence trigger

        Task {
            print("📍 [SelineApp] Configuring location services...")

            // Request location permission and set up geofences
            // If permission is already granted, this immediately sets up geofences
            // If not granted yet, geofences will be set up when permission is granted
            GeofenceManager.shared.requestLocationPermission()
            
            // CRITICAL FIX: Force enable background location immediately
            // This ensures location updates continue even when app is backgrounded
            SharedLocationManager.shared.enableBackgroundLocationTracking(true)
            
            // Start significant location change monitoring immediately
            // This provides faster detection than geofences alone (triggers on 500m+ movement)
            SharedLocationManager.shared.startSignificantLocationChangeMonitoring()
            
            // Start CLVisit monitoring for accurate arrival/departure detection
            SharedLocationManager.shared.startVisitMonitoring()

            // CRITICAL: Start background validation timer immediately
            // This checks every 30 seconds if user entered/exited locations
            // even if iOS geofence events are delayed
            let savedPlaces = LocationsManager.shared.savedPlaces
            if !savedPlaces.isEmpty {
                // Start the continuous location monitoring
                LocationBackgroundValidationService.shared.startContinuousMonitoring(
                    geofenceManager: GeofenceManager.shared,
                    locationManager: SharedLocationManager.shared,
                    savedPlaces: savedPlaces
                )
            }

            print("✅ [SelineApp] Location services configured")
        }
    }
    
    private func refreshWidgetDataOnLaunch() {
        // Refresh widget data asynchronously after a small delay
        // This allows notes to load first from local storage/Supabase
        Task {
            // Wait for notes to load (give time for local storage + potential Supabase sync)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                // Refresh spending data for widget
                SpendingAndETAWidget.refreshWidgetSpendingData()
                
                // Also sync today's tasks to widget  
                TaskManager.shared.syncTodaysTasksToWidget(tags: TagManager.shared.tags)
                
                print("📱 [SelineApp] Widget data refreshed on launch")
            }
        }
    }
}
