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
    @Published var showLocationSetup = false

    private let supabaseManager = SupabaseManager.shared

    private init() {
        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }

    func checkExistingSession() async {
        do {
            // Try to get current session from Supabase
            let session = try await supabaseManager.authClient.session

            // If we have a valid session, restore authentication state
            self.supabaseUser = session.user
            self.isAuthenticated = true

            // Initialize encryption with restored user ID
            EncryptionManager.shared.setupEncryption(with: session.user.id)

            // Set user for receipt cache isolation
            ReceiptCategorizationService.shared.setCurrentUser(session.user.id.uuidString)

            // Try to restore Google Sign-In state
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                Task { @MainActor in
                    if let user = user {
                        self?.currentUser = user
                    }
                }
            }

            // Sync tasks and notes from Supabase
            await TaskManager.shared.syncTasksOnLogin()
            await NotesManager.shared.syncNotesOnLogin()
            await TagManager.shared.loadTagsFromSupabase()

        } catch {
            // No valid session found, user needs to sign in
            self.isAuthenticated = false
        }
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

            // Request additional Gmail and People API scopes
            let gmailScopes = [
                "https://www.googleapis.com/auth/gmail.readonly",
                "https://www.googleapis.com/auth/contacts.readonly" // For fetching profile pictures
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

            // Initialize encryption with user's UUID
            EncryptionManager.shared.setupEncryption(with: supabaseUser.id)

            // Set user for receipt cache isolation
            ReceiptCategorizationService.shared.setCurrentUser(supabaseUser.id.uuidString)

            // Sync tasks and notes from Supabase
            Task {
                await TaskManager.shared.syncTasksOnLogin()
                await NotesManager.shared.syncNotesOnLogin()
                await LocationsManager.shared.syncPlacesOnLogin()
                await TagManager.shared.loadTagsFromSupabase()
            }

            // Check if first-time setup is needed
            Task {
                await checkFirstTimeSetup()
            }

        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            print("❌ Google Sign-In error: \(error)")
        }

        isLoading = false
    }

    private func checkFirstTimeSetup() async {
        do {
            let preferences = try await supabaseManager.loadLocationPreferences()
            if preferences.isFirstTimeSetup {
                self.showLocationSetup = true
            }
        } catch {
            print("❌ Failed to check first-time setup: \(error)")
            // If we can't load preferences, assume first-time and show setup
            self.showLocationSetup = true
        }
    }

    func signOut() async {
        isLoading = true
        errorMessage = nil

        do {
            // Capture user ID before clearing for cache cleanup
            let userIdToClean = supabaseUser?.id

            // Sign out from Supabase
            try await supabaseManager.signOut()

            // Sign out from Google
            GIDSignIn.sharedInstance.signOut()

            // Clear encryption key
            EncryptionManager.shared.clearEncryption()

            // Clear receipt categorization cache for this user
            if let userId = userIdToClean {
                ReceiptCategorizationService.shared.clearCacheForUser(userId.uuidString)
            }

            // Clear tasks and set authentication state
            TaskManager.shared.clearTasksOnLogout()
            self.isAuthenticated = false
            self.currentUser = nil
            self.supabaseUser = nil

        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
            print("❌ Sign out error: \(error)")
        }

        isLoading = false
    }

    func refreshSession() async {
        do {
            // Refresh the session with Supabase
            let session = try await supabaseManager.authClient.session
            self.supabaseUser = session.user
            self.isAuthenticated = true
        } catch {
            print("❌ Failed to refresh session: \(error.localizedDescription)")
            self.isAuthenticated = false
        }
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