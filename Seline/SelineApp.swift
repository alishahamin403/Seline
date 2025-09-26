import SwiftUI
import Auth
import GoogleSignIn

@main
struct SelineApp: App {
    @StateObject private var authManager = AuthenticationManager.shared

    init() {
        configureSupabase()
        configureGoogleSignIn()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
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
}