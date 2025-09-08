//
//  SelineApp.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI
// Note: Add these dependencies via Swift Package Manager in Xcode:
// 1. https://github.com/google/GoogleSignIn-iOS (GoogleSignIn)
// 2. https://github.com/googleapis/google-api-objectivec-client-for-rest (GoogleAPIClientForREST)
import GoogleSignIn
import BackgroundTasks

@main
struct SelineApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        registerAndUpdateIconTask()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .onAppear {
                    setupDevelopmentEnvironment()
                    setupNotifications()
                    trackAppLaunch()
                    DynamicIconService.shared.updateAppIcon()
                }
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .background:
                scheduleAppIconUpdate()
            default:
                break
            }
        }
    }
    
    private func setupDevelopmentEnvironment() {
        // Suppress verbose network warnings
        suppressNetworkWarnings()
        
        // Configure GoogleSignIn
        configureGoogleSignIn()
        
        #if DEBUG
        // ENABLE REAL SUPABASE SYNC IN DEVELOPMENT
        print("🔄 DEBUG MODE: Real Supabase cloud sync ENABLED")
        print("📊 All app activity will be tracked in Supabase cloud storage")
        
        
        // Debug authentication service state
        AuthenticationService.shared.debugCurrentState()
        
        // Initialize Supabase connection
        Task {
            // Test Supabase connection
            let supabaseService = SupabaseService.shared
            print("🌐 Supabase initialization status: \(supabaseService.isConnected ? "✅ Connected" : "❌ Not Connected")")
        }
        #endif
    }
    
    private func suppressNetworkWarnings() {
        // Suppress common iOS network warnings that clutter logs
        setenv("CFNETWORK_DIAGNOSTICS", "0", 1)
        setenv("CFNETWORK_VERBOSE", "0", 1)
        
        // ADDITIONAL: Suppress more network debug logs
        setenv("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES", 1)
        setenv("NW_LOG_LEVEL", "0", 1) // Disable Network framework logging
        
        #if DEBUG
        // In debug mode, further suppress unwanted network logs
        LogRateLimiter.shared.logIfAllowed("network_suppression", interval: 60.0) {
            print("🔇 Network logging suppressed to reduce console spam")
        }
        #endif
    }
    
    private func configureGoogleSignIn() {
        // Configure GoogleSignIn with client ID from GoogleService-Info.plist
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            print("❌ Failed to load Google OAuth configuration from GoogleService-Info.plist")
            return
        }
        
        // Configure with all required scopes upfront to avoid incremental authorization issues
        let configuration = GIDConfiguration(clientID: clientID)
        configuration.scopes = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/calendar.readonly",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/userinfo.profile"
        ]
        
        GIDSignIn.sharedInstance.configuration = configuration
        print("🔧 Google OAuth configured with all scopes: \(configuration.scopes ?? [])")
    }
    
    private func setupNotifications() {
        // Set up notification categories and request permissions
        NotificationManager.shared.setupNotificationCategories()

        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                print("✅ Notification permissions granted")
            } else {
                print("❌ Notification permissions denied")
            }
        }
    }

    private func trackAppLaunch() {
        // Track app launch for analytics
        AnalyticsManager.shared.trackAppLaunch()

        // Start performance monitoring
        PerformanceMonitor.shared.startTiming("app_startup")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PerformanceMonitor.shared.endTiming("app_startup")
        }
    }

    private func registerAndUpdateIconTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.seline.updateIcon", using: nil) { task in
            self.handleAppIconUpdate(task: task as! BGAppRefreshTask)
        }
    }

    private func handleAppIconUpdate(task: BGAppRefreshTask) {
        scheduleAppIconUpdate()

        let operation = BlockOperation {
            DynamicIconService.shared.updateAppIcon()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        task.expirationHandler = {
            operation.cancel()
        }

        OperationQueue.main.addOperation(operation)
    }

    private func scheduleAppIconUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: "com.seline.updateIcon")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // Fetch no more than once an hour

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app icon update: \(error)")
        }
    }
}