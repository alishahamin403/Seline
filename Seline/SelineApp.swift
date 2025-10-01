import SwiftUI
import Auth
import GoogleSignIn
import UserNotifications

@main
struct SelineApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationService = NotificationService.shared

    init() {
        configureSupabase()
        configureGoogleSignIn()
        configureNotifications()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(notificationService)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Handle app becoming active
                    Task {
                        // Perform background refresh check
                        await EmailService.shared.handleBackgroundRefresh()

                        // Update app badge with current unread count
                        let unreadCount = EmailService.shared.inboxEmails.filter { !$0.isRead }.count
                        notificationService.updateAppBadge(count: unreadCount)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // App entered background - save current state
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
}