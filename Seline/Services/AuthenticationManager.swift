import Foundation
import SwiftUI
import GoogleSignIn
import Auth

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: GIDGoogleUser?
    @Published var supabaseUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabaseManager = SupabaseManager.shared

    private init() {
        // For now, just initialize without auth state listener
        // We'll add Supabase integration once Google Sign-In works
    }

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            // First, sign in with Google
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let presentingViewController = windowScene.windows.first?.rootViewController else {
                throw AuthError.noPresentingViewController
            }

            // Request additional Gmail scopes
            let gmailScopes = [
                "https://www.googleapis.com/auth/gmail.readonly"
            ]

            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: gmailScopes
            )

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.noIdToken
            }

            let accessToken = result.user.accessToken.tokenString

            // Sign in with Supabase using Google tokens (no nonce since "Skip nonce checks" is enabled)
            let supabaseUser = try await supabaseManager.signInWithGoogleIdToken(idToken, accessToken: accessToken, nonce: nil)

            // Create/update user profile in Supabase
            try await supabaseManager.createOrUpdateUserProfile(
                user: supabaseUser,
                email: result.user.profile?.email,
                name: result.user.profile?.name
            )

            // Set authentication state
            self.isAuthenticated = true
            self.currentUser = result.user
            self.supabaseUser = supabaseUser

            print("✅ Google Sign-In Success: \(result.user.profile?.email ?? "No email")")
            print("✅ Supabase User Created: \(supabaseUser.id)")

        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            print("Google Sign-In error: \(error)")
        }

        isLoading = false
    }

    func signOut() async {
        isLoading = true
        errorMessage = nil

        do {
            // Sign out from Supabase
            try await supabaseManager.signOut()

            // Sign out from Google
            GIDSignIn.sharedInstance.signOut()

            // Set authentication state
            self.isAuthenticated = false
            self.currentUser = nil
            self.supabaseUser = nil

        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
            print("Sign out error: \(error)")
        }

        isLoading = false
    }

    func refreshSession() async {
        // TODO: Implement session refresh with Supabase
        print("Session refresh not yet implemented")
    }
}

enum AuthError: LocalizedError {
    case noPresentingViewController
    case noIdToken

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "No presenting view controller available"
        case .noIdToken:
            return "Failed to get ID token from Google"
        }
    }
}