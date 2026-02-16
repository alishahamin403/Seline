import SwiftUI
import Auth
import GoogleSignIn
import UserNotifications
import EventKit
import BackgroundTasks
import WidgetKit

@main
struct SelineApp: App {
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

    init() {
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
                    // Handle app becoming active
                    Task {
                        // LOCATION FIX: Immediately refresh widgets when app becomes active
                        // This ensures widget shows current location state
                        WidgetCenter.shared.reloadAllTimelines()
                        print("🔄 Widget refresh on app active")
                        
                        // LOCATION FIX: Ensure geofences are up to date
                        GeofenceManager.shared.setupGeofences(for: LocationsManager.shared.savedPlaces)
                        
                        // Perform background refresh check for emails
                        await EmailService.shared.handleBackgroundRefresh()

                        // Update app badge with current unread count
                        let unreadCount = EmailService.shared.inboxEmails.filter { !$0.isRead }.count
                        notificationService.updateAppBadge(count: unreadCount)

                        // Sync new calendar events when app resumes (real-time refresh)
                        // Only sync if last sync was > 1 minute ago (prevents over-syncing)
                        let timeSinceLastSync = Date().timeIntervalSince(lastCalendarSyncTime)
                        if timeSinceLastSync > 60 && !isCalendarSyncing { // 60 seconds = 1 minute
                            isCalendarSyncing = true
                            lastCalendarSyncTime = Date()

                            await taskManager.syncCalendarEvents()

                            isCalendarSyncing = false
                        }

                        // OPTIMIZATION: Background cache warming - preload commonly needed data
                        Task.detached(priority: .utility) {
                            // Warm up task caches
                            _ = await taskManager.getAllFlattenedTasks()

                            // Warm up today's visits cache
                            _ = await LocationVisitAnalytics.shared.getTodaysVisitsWithDuration()

                            // Refresh widget spending data to ensure it's up-to-date
                            await MainActor.run {
                                SpendingAndETAWidget.refreshWidgetSpendingData()
                            }

                            // CRITICAL: Run visit cleanup to fix any midnight-spanning issues
                            // This runs in the background and won't block the UI
                            let midnightResult = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
                            if midnightResult.fixed > 0 {
                                print("🌙 Startup cleanup: Fixed \(midnightResult.fixed) midnight-spanning visits")
                            }
                            
                            // NEW: Sync vector embeddings for semantic search
                            // This keeps embeddings up-to-date for fast, relevant LLM context
                            await VectorSearchService.shared.syncEmbeddingsIfNeeded()

                            print("🔥 Cache warming complete")
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // App entered background - save current state
                    // Save current conversation to history before app closes
                    if !searchService.conversationHistory.isEmpty {
                        searchService.saveConversationToHistory()
                        print("💾 Current conversation saved to history before background")
                    }
                    // The email polling timer will continue running
                    print("App entered background - email polling continues")
                }
        }
    }

    private func configureSupabase() {
        // TODO: Configure Supabase when we integrate it
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
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.seline.emailRefresh", using: nil) { task in
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
        let request = BGAppRefreshTaskRequest(identifier: "com.seline.emailRefresh")
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
        // Sync calendar events on app launch
        // This runs asynchronously without blocking app initialization
        Task {
            // DEBUG: Commented out to reduce console spam
            // print("📅 [SelineApp] Starting calendar sync check on launch...")

            // Check current permission status first
            let status = EventKit.EKEventStore.authorizationStatus(for: .event)
            // DEBUG: Commented out to reduce console spam
            // print("📅 [SelineApp] Current calendar permission status: \(status.rawValue)")

            let hasAccess = await taskManager.requestCalendarAccess()
            // DEBUG: Commented out to reduce console spam
            // print("📅 [SelineApp] requestCalendarAccess returned: \(hasAccess)")

            if hasAccess {
                // DEBUG: Commented out to reduce console spam
                // print("✅ [SelineApp] Calendar access granted - syncing events now")
                await taskManager.syncCalendarEvents()
            } else {
                print("⚠️ [SelineApp] Calendar access not granted. Status: \(status.rawValue)")
                print("⚠️ [SelineApp] User can enable it in Settings > Seline > Calendars")
            }
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
            geofenceManager.requestLocationPermission()
            
            // CRITICAL FIX: Force enable background location immediately
            // This ensures location updates continue even when app is backgrounded
            SharedLocationManager.shared.enableBackgroundLocationTracking(true)
            
            // Start significant location change monitoring immediately
            // This provides faster detection than geofences alone (triggers on 500m+ movement)
            SharedLocationManager.shared.startSignificantLocationChangeMonitoring()
            
            // Start CLVisit monitoring for accurate arrival/departure detection
            SharedLocationManager.shared.startVisitMonitoring()

            // Load incomplete visits from Supabase to resume tracking
            // This is important for cases where the app was killed mid-visit
            await geofenceManager.loadIncompleteVisitsFromSupabase()
            
            // CRITICAL: Start background validation timer immediately
            // This checks every 30 seconds if user entered/exited locations
            // even if iOS geofence events are delayed
            let savedPlaces = locationsManager.savedPlaces
            if !savedPlaces.isEmpty {
                // Start the continuous location monitoring
                LocationBackgroundValidationService.shared.startContinuousMonitoring(
                    geofenceManager: geofenceManager,
                    locationManager: SharedLocationManager.shared,
                    savedPlaces: savedPlaces
                )
            }

            // Fix historical visits that span midnight
            // CRITICAL: Run this fix on app launch to process any visits that span midnight
            // This runs directly (not detached) to ensure it completes before user interacts with app
            print("🌙 [SelineApp] Starting midnight-spanning visit fix...")
            let result = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
            if result.fixed > 0 {
                print("✅ [SelineApp] Fixed \(result.fixed) historical midnight-spanning visits!")
            } else if result.errors > 0 {
                print("❌ [SelineApp] \(result.errors) errors while fixing midnight visits")
            } else {
                print("✅ [SelineApp] No midnight-spanning visits to fix")
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
