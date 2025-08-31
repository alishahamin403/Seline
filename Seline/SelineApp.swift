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

@main
struct SelineApp: App {
    @StateObject private var authService = AuthenticationService.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .onAppear {
                    setupDevelopmentEnvironment()
                    setupNotifications()
                    trackAppLaunch()
                }
        }
    }
    
    private func setupDevelopmentEnvironment() {
        // Configure GoogleSignIn
        configureGoogleSignIn()
        
        #if DEBUG
        // ENABLE REAL SUPABASE SYNC IN DEVELOPMENT
        print("🔄 DEBUG MODE: Real Supabase cloud sync ENABLED")
        print("📊 All app activity will be tracked in Supabase cloud storage")
        
        // Setup development credentials automatically
        DevelopmentConfiguration.shared.setupDevelopmentCredentials()
        
        // Print credential status for debugging
        DevelopmentConfiguration.shared.printCredentialStatus()
        
        // Debug authentication service state
        AuthenticationService.shared.debugCurrentState()
        
        // Initialize Supabase connection
        Task {
            // Test Supabase connection
            let supabaseService = SupabaseService.shared
            print("🌐 Supabase connection status: \(supabaseService.isConnected ? "✅ Connected" : "❌ Disconnected")")
            
            await DevelopmentConfiguration.shared.validateAPIKeys()
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
        
        // Uncomment when GoogleSignIn dependency is added:
         GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        print("🔧 Google OAuth Client ID configured: \(clientID)")
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
}
