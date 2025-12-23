import SwiftUI
import Auth
import GoogleSignIn
import UserNotifications
import EventKit
import BackgroundTasks

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
                        // Perform background refresh check
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
        // Register Background App Refresh task for email notifications
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.seline.emailRefresh", using: nil) { task in
            Task {
                print("📧 Background refresh task started")
                await EmailService.shared.handleBackgroundRefresh()

                // Schedule the next background refresh
                scheduleBackgroundRefresh()

                // Mark task as completed
                task.setTaskCompleted(success: true)
            }
        }

        // Schedule the first background refresh
        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.seline.emailRefresh")
        // Schedule refresh in 15 minutes (minimum is 15 minutes for app refresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            // DEBUG: Commented out to reduce console spam
            // print("📅 Background refresh scheduled for 15 minutes from now")
        } catch {
            print("⚠️ Failed to schedule background refresh: \(error)")
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

            // Load incomplete visits from Supabase to resume tracking
            // This is important for cases where the app was killed mid-visit
            await geofenceManager.loadIncompleteVisitsFromSupabase()

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
}