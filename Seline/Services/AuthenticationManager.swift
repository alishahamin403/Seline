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

            // CRITICAL: Verify cached data matches current user before syncing
            // This prevents issues if app was used by multiple accounts
            await verifyAndCleanCacheIfNeeded(for: session.user.id.uuidString)

            // Sync tasks, notes, people from Supabase
            await TaskManager.shared.syncTasksOnLogin()
            await NotesManager.shared.syncNotesOnLogin()
            await PeopleManager.shared.syncPeopleOnLogin()
            await TagManager.shared.loadTagsFromSupabase()

        } catch {
            // No valid session found, user needs to sign in
            self.isAuthenticated = false
        }
    }

    /// Verify that cached data belongs to current user, clear if it doesn't
    private func verifyAndCleanCacheIfNeeded(for userId: String) async {
        let lastCachedUserKey = "LastCachedUserId"
        let lastCachedUserId = UserDefaults.standard.string(forKey: lastCachedUserKey)

        // If we have a different user cached, clear everything
        if let lastCachedUserId = lastCachedUserId, lastCachedUserId != userId {
            print("⚠️ Detected different user in cache (was: \(lastCachedUserId), now: \(userId)) - clearing old data")
            TaskManager.shared.clearTasksOnLogout()
            NotesManager.shared.clearNotesOnLogout()
            LocationsManager.shared.clearPlacesOnLogout()
            PeopleManager.shared.clearPeopleOnLogout()
            TagManager.shared.clearTagsOnLogout()
        }

        // Update the current user ID
        UserDefaults.standard.set(userId, forKey: lastCachedUserKey)
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
                "https://www.googleapis.com/auth/contacts.readonly", // For contact search + profile pictures
                "https://www.googleapis.com/auth/contacts.other.readonly" // For Gmail-style auto-saved recipients
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

            // CRITICAL: Check if this is a different user and clear caches only if needed
            let lastCachedUserId = UserDefaults.standard.string(forKey: "LastCachedUserId")
            let currentUserId = supabaseUser.id.uuidString

            if let lastCachedUserId = lastCachedUserId, lastCachedUserId != currentUserId {
                print("⚠️ Detected different user (was: \(lastCachedUserId), now: \(currentUserId)) - clearing old data")
                TaskManager.shared.clearTasksOnLogout()
                NotesManager.shared.clearNotesOnLogout()
                LocationsManager.shared.clearPlacesOnLogout()
                PeopleManager.shared.clearPeopleOnLogout()
                TagManager.shared.clearTagsOnLogout()
            }

            // Track current user ID to detect account switches
            UserDefaults.standard.set(currentUserId, forKey: "LastCachedUserId")

            // Sync tasks, notes, people, places from Supabase
            Task {
                await TaskManager.shared.syncTasksOnLogin()
                await NotesManager.shared.syncNotesOnLogin()
                await PeopleManager.shared.syncPeopleOnLogin()
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

            // === CLEAR ALL USER DATA ===

            // 1. Clear manager data
            TaskManager.shared.clearTasksOnLogout()
            NotesManager.shared.clearNotesOnLogout()
            LocationsManager.shared.clearPlacesOnLogout()
            PeopleManager.shared.clearPeopleOnLogout()
            TagManager.shared.clearTagsOnLogout()

            // 2. Clear email data
            EmailService.shared.clearEmailsOnLogout()

            // 3. Clear search & conversation data
            SearchService.shared.clearSearchOnLogout()

            // 4. Clear receipt cache (user-specific)
            if let userId = userIdToClean {
                ReceiptCategorizationService.shared.clearCacheForUser(userId.uuidString)
            }

            // 5. Clear user profile
            UserProfilePersistenceService.clearUserProfile()

            // 6. Clear image cache
            ImageCacheManager.shared.clearCache()

            // 7. Clear encryption key
            EncryptionManager.shared.clearEncryption()

            // 8. Clear all UserDefaults that might contain user-specific data
            clearAllUserDefaults()

            // === SIGN OUT FROM SERVICES ===

            // Sign out from Supabase
            try await supabaseManager.signOut()

            // Sign out from Google
            GIDSignIn.sharedInstance.signOut()

            // Clear authentication state
            self.isAuthenticated = false
            self.currentUser = nil
            self.supabaseUser = nil

            print("✅ Successfully signed out and cleared all user data")

        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
            print("❌ Sign out error: \(error)")
        }

        isLoading = false
    }

    /// Clear all UserDefaults that might contain user-specific data
    private func clearAllUserDefaults() {
        let defaults = UserDefaults.standard

        // Clear known keys that might contain user-specific data
        let keysToRemove = [
            "SavedTasks",
            "SavedNotes",
            "SavedNoteFolders",
            "SavedPlaces",
            "SavedPeople",
            "MapsSearchHistory",
            "cached_inbox_emails",
            "cached_sent_emails",
            "cached_inbox_timestamp",
            "cached_sent_timestamp",
            "last_email_ids",
            "SavedConversations",
            "com.vibecode.seline.userprofile",
            "UserLocationPreferences",
            "UserCreatedTags",
            "DeletedNotes",
            "DeletedFolders",
            "LastCachedUserId"  // Clear user ID tracking on logout
        ]

        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        // Also clear shared UserDefaults (for widgets/app groups)
        if let sharedDefaults = UserDefaults(suiteName: "group.seline") {
            for key in keysToRemove {
                sharedDefaults.removeObject(forKey: key)
            }
        }

        defaults.synchronize()
        print("🗑️ Cleared all UserDefaults")
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
