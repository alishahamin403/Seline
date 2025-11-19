import SwiftUI
import Auth
import GoogleSignIn
import UserNotifications
import EventKit
import BackgroundTasks

@main
struct SelineApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var searchService = SearchService.shared
    @State private var lastCalendarSyncTime: Date = Date.distantPast
    @State private var isCalendarSyncing: Bool = false

    init() {
        configureSupabase()
        configureGoogleSignIn()
        configureNotifications()
        configureBackgroundRefresh()
        // Defer calendar sync to avoid initialization issues - will be called from didBecomeActiveNotification
        // syncCalendarEventsOnFirstLaunch()
        migrateReceiptCategoriesIfNeeded()

        // TEMPORARY: Clear corrupted local tasks (22k duplicates)
        // This will clear all local task cache on next launch
        // After clearing, you can remove this line and rebuild
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                print("🧹 Clearing corrupted local task cache (22k+ duplicated calendar events)...")
                await TaskManager.shared.nuclearReset()
                print("✅ Done! Your actual tasks are still in Supabase and will sync on next screen load")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(notificationService)
                .environmentObject(deepLinkHandler)
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

                        // Sync calendar events only if last sync was > 5 minutes ago (prevents over-syncing during development)
                        let timeSinceLastSync = Date().timeIntervalSince(lastCalendarSyncTime)
                        if timeSinceLastSync > 300 && !isCalendarSyncing { // 300 seconds = 5 minutes
                            isCalendarSyncing = true
                            lastCalendarSyncTime = Date()

                            await taskManager.syncCalendarEvents()

                            isCalendarSyncing = false
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
                print("✅ Notification permissions granted")
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
            print("📅 Background refresh scheduled for 15 minutes from now")
        } catch {
            print("⚠️ Failed to schedule background refresh: \(error)")
        }
    }

    private func syncCalendarEventsOnFirstLaunch() {
        // Sync calendar events on app launch
        // This runs asynchronously without blocking app initialization
        Task {
            print("📅 [SelineApp] Starting calendar sync check on launch...")

            // Check current permission status first
            let status = EventKit.EKEventStore.authorizationStatus(for: .event)
            print("📅 [SelineApp] Current calendar permission status: \(status.rawValue)")

            let hasAccess = await taskManager.requestCalendarAccess()
            print("📅 [SelineApp] requestCalendarAccess returned: \(hasAccess)")

            if hasAccess {
                print("✅ [SelineApp] Calendar access granted - syncing events now")
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
}