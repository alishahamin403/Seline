//
//  AuthenticationService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import Combine
import GoogleSignIn

enum AuthError: Error {
    case tokenRefreshFailed
    case authenticationFailed
    case userCancelled
}

@MainActor
class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var isAuthenticated = false
    @Published var user: SelineUser?
    @Published var authError: String?
    @Published var isLoading = false
    @Published var hasCompletedOnboarding = false
    
    private let userDefaults = UserDefaults.standard
    private let authStateKey = "seline_auth_state"
    private let userKey = "seline_user"
    private let onboardingKey = "seline_onboarding_completed"
    private let supabaseService = SupabaseService.shared
    
    // Gmail and Calendar scopes
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]
    
    private init() {
        loadAuthState()
        debugInitialState()
    }
    
    // MARK: - Authentication State Management
    
    private func loadAuthState() {
        let storedAuthState = userDefaults.bool(forKey: authStateKey)
        let completedOnboarding = userDefaults.bool(forKey: onboardingKey)
        
        if let userData = userDefaults.data(forKey: userKey) {
            if let decodedUser = try? JSONDecoder().decode(SelineUser.self, from: userData) {
                Task { @MainActor in
                    self.user = decodedUser
                    self.hasCompletedOnboarding = completedOnboarding
                }
                
                // Check if token is expired (but be more lenient in development)
                #if DEBUG
                if decodedUser.isTokenExpired {
                    print("⚠️ Token expired in dev mode, extending expiration")
                    // In development, extend the token expiration instead of clearing auth
                    let extendedUser = SelineUser(
                        id: decodedUser.id,
                        email: decodedUser.email,
                        name: decodedUser.name,
                        profileImageURL: decodedUser.profileImageURL,
                        accessToken: decodedUser.accessToken,
                        refreshToken: decodedUser.refreshToken,
                        tokenExpirationDate: Date().addingTimeInterval(365 * 24 * 3600) // Extend for 1 year
                    )
                    Task { @MainActor in
                        self.user = extendedUser
                    }
                    saveAuthState() // Save the updated user with extended token
                }
                #else
                if decodedUser.isTokenExpired {
                    clearAuthState()
                    return
                }
                #endif
                
                // Update last sign in if authenticated
                if storedAuthState {
                    Task {
                        do {
                            try await supabaseService.updateLastSignIn(userID: UUID())
                        } catch {
                            ProductionLogger.logError(error, context: "Updating last sign in")
                        }
                    }
                }
            } else {
                ProductionLogger.logError(NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode user data"]), context: "User data decoding")
                clearAuthState()
                return
            }
        }
        
        // Set authentication state
        Task { @MainActor in
            self.isAuthenticated = storedAuthState && self.user != nil
            self.hasCompletedOnboarding = completedOnboarding || self.user != nil
            
            #if DEBUG
            print("🔐 Auth state loaded: authenticated=\(self.isAuthenticated), onboarding=\(self.hasCompletedOnboarding)")
            #endif
        }
    }
    
    private func clearAuthState() {
        Task { @MainActor in
            self.isAuthenticated = false
            self.user = nil
            // Keep onboarding state so user doesn't see intro screens again
        }
        userDefaults.removeObject(forKey: authStateKey)
        userDefaults.removeObject(forKey: userKey)
        // Don't clear onboarding state - user has already seen the flow
    }
    
    private func saveAuthState() {
        userDefaults.set(isAuthenticated, forKey: authStateKey)
        userDefaults.set(hasCompletedOnboarding, forKey: onboardingKey)
        if let user = user,
           let userData = try? JSONEncoder().encode(user) {
            userDefaults.set(userData, forKey: userKey)
            
            #if DEBUG
            print("💾 User data saved for: \(user.email)")
            #endif
            
            // CRITICAL FIX: Synchronize tokens to secure storage when saving auth state
            // This ensures GoogleOAuthService can find the tokens for API calls
            if !user.accessToken.isEmpty {
                let secureStorage = SecureStorage.shared
                if secureStorage.storeGoogleTokens(accessToken: user.accessToken, refreshToken: user.refreshToken) {
                    #if DEBUG
                    print("✅ Tokens synchronized to secure storage")
                    #endif
                } else {
                    ProductionLogger.logError(NSError(domain: "AuthenticationService", code: -2), context: "Failed to synchronize tokens to secure storage")
                }
            }
        }
        
        // Force synchronize to ensure data is written immediately
        userDefaults.synchronize()
    }
    
    private func debugInitialState() {
        #if DEBUG
        print("🔐 AuthenticationService initialized - authenticated: \(isAuthenticated), user: \(user?.email ?? "nil")")
        #endif
    }
    
    // MARK: - Public Authentication Methods
    
    
    /// Refresh token if needed and sync to storage
    func refreshTokenIfNeeded() async throws {
        guard let user = user else { return }
        
        // Check if token is expiring within next 5 minutes
        let fiveMinutesFromNow = Date().addingTimeInterval(300)
        if let expiration = user.tokenExpirationDate, expiration > fiveMinutesFromNow {
            return
        }
        
        print("🔄 Token expired, refreshing...")
        
        // In development with mock data, we don't have a real refresh token.
        // So we will just extend the expiration date of the current mock token.
        #if DEBUG
        print("⚠️ In DEBUG mode, skipping real token refresh and extending mock token's expiration.")
        let refreshedUser = SelineUser(
            id: user.id,
            email: user.email,
            name: user.name,
            profileImageURL: user.profileImageURL,
            accessToken: user.accessToken,
            refreshToken: user.refreshToken,
            tokenExpirationDate: Date().addingTimeInterval(3600) // Extend for 1 hour
        )
        
        await MainActor.run {
            self.user = refreshedUser
        }
        
        saveAuthState()
        return
        #endif

        do {
            // Use GoogleOAuthService for token refresh
            if let newAccessToken = await GoogleOAuthService.shared.getValidAccessToken() {
                let refreshedUser = SelineUser(
                    id: user.id,
                    email: user.email,
                    name: user.name,
                    profileImageURL: user.profileImageURL,
                    accessToken: newAccessToken,
                    refreshToken: user.refreshToken,
                    tokenExpirationDate: Date().addingTimeInterval(3600) // Google tokens typically last 1 hour
                )
                
                await MainActor.run {
                    self.user = refreshedUser
                }
                
                saveAuthState()
                print("✅ Token refreshed successfully")
            } else {
                // If refresh fails, user needs to re-authenticate
                print("❌ Token refresh failed, user needs to re-authenticate")
                await signOut()
                throw AuthError.tokenRefreshFailed
            }
        } catch {
            print("❌ Token refresh error: \(error)")
            await signOut()
            throw error
        }
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle() async {
        /*
        await MainActor.run {
            isLoading = true
            authError = nil
        }
        
        // Check if user is already authenticated and token is valid
        if isAuthenticated, let user = user, !user.isTokenExpired {
            #if DEBUG
            print("✅ User already authenticated, skipping sign-in")
            #endif
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            // TODO: Replace with actual Google Sign-In implementation
            // For now, simulate successful authentication
            try await simulateGoogleSignIn()
            
            /*
            // Real implementation would look like this:
            guard let presentingViewController = await getRootViewController() else {
                throw AuthenticationError.noViewController
            }
            
            let result = try await GoogleSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            let user = result.user
            
            // Check if we have the required scopes
            guard let grantedScopes = user.grantedScopes,
                  scopes.allSatisfy({ grantedScopes.contains($0) }) else {
                try await requestAdditionalScopes()
                return
            }
            
            await handleSuccessfulSignIn(user: user)
            */
            
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
            ProductionLogger.logAuthError(error, context: "Google Sign-In")
        }
        
        await MainActor.run {
            isLoading = false
        }
        */
    }
    
    func signOut() async {
        isLoading = true
        
        // Clean up Supabase session and real-time subscriptions
        try? await SupabaseService.shared.signOut()
        
        /*
        do {
            GoogleSignIn.shared.signOut()
        } catch {
            authError = "Sign out failed: \(error.localizedDescription)"
        }
        */
        
        // Clear local email service
        LocalEmailService.shared.signOut()
        
        // Clear local state
        clearAuthState()
        
        #if DEBUG
        print("✅ Sign out completed")
        #endif
        
        isLoading = false
    }
    
    // MARK: - Debug Methods
    
    func forceSignOut() {
        #if DEBUG
        print("🔐 Force sign out executed")
        #endif
        clearAuthState()
    }

    /// Clears user authentication data from UserDefaults.
    /// This is useful for debugging or forcing a fresh sign-in.
    public func clearUserDataFromUserDefaults() {
        userDefaults.removeObject(forKey: authStateKey)
        userDefaults.removeObject(forKey: userKey)
        userDefaults.removeObject(forKey: onboardingKey) // Also clear onboarding for a clean slate
        userDefaults.removeObject(forKey: "current_user_email") // Clear the email used for API key scoping
        userDefaults.synchronize() // Ensure changes are written immediately
        
        // Also clear any related secure storage data if necessary for a full reset
        SecureStorage.shared.clearAllCredentials()
        SecureStorage.shared.clearOpenAIKey() // Ensure OpenAI key is also cleared
        
        // Reset in-memory state
        Task { @MainActor in
            self.isAuthenticated = false
            self.user = nil
            self.hasCompletedOnboarding = false
            self.authError = nil
            self.isLoading = false
        }
        
        #if DEBUG
        print("🗑️ User data cleared from UserDefaults and SecureStorage.")
        #endif
    }
    
    /// Check if user has valid persistent authentication
    func checkPersistentAuthentication() -> Bool {
        let hasValidUser = user != nil
        let isCurrentlyAuthenticated = isAuthenticated
        let tokenNotExpired = user?.isTokenExpired == false
        
        let isPersistent = hasValidUser && isCurrentlyAuthenticated && tokenNotExpired
        
        #if DEBUG
        print("🔍 Persistent auth check: \(isPersistent)")
        #endif
        
        return isPersistent
    }
    
    func debugCurrentState() {
        #if DEBUG
        print("🔐 Auth Debug - authenticated: \(isAuthenticated), user: \(user?.email ?? "nil"), loading: \(isLoading)")
        if let user = user {
            print("🔐 User: \(user.name) (ID: \(user.id)), Token expired: \(user.isTokenExpired)")
        }
        #endif
    }
    
    
    // MARK: - Helper Methods
    
    private func simulateGoogleSignIn() async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Create mock user for development
        let mockUser = SelineUser(
            id: "mock_google_id_alishah",
            email: "alishah.amin96@gmail.com",
            name: "Alishah Amin",
            profileImageURL: nil,
            accessToken: "mock_access_token_persistent",
            refreshToken: "mock_refresh_token_persistent",
            tokenExpirationDate: Date().addingTimeInterval(365 * 24 * 3600) // 1 year - long expiration for dev
        )
        
        await MainActor.run {
            self.user = mockUser
            self.isAuthenticated = true
        }
        // Set the current user's email in UserDefaults for API key scoping
        userDefaults.set(mockUser.email, forKey: "current_user_email")
        // Store tokens in Keychain so Gmail/Calendar services can retrieve them
        _ = SecureStorage.shared.storeGoogleTokens(
            accessToken: mockUser.accessToken,
            refreshToken: mockUser.refreshToken
        )
        saveAuthState()
    }
    
    /*
    private func handleSuccessfulSignIn(user: GIDGoogleUser) async {
        let selineUser = SelineUser(
            id: user.userID ?? "",
            email: user.profile?.email ?? "",
            name: user.profile?.name ?? "",
            profileImageURL: user.profile?.imageURL(withDimension: 100)?.absoluteString,
            accessToken: user.accessToken.tokenString,
            refreshToken: user.refreshToken?.tokenString,
            tokenExpirationDate: user.accessToken.expirationDate
        )
        
        self.user = selineUser
        self.isAuthenticated = true
        saveAuthState()
    }
    
    private func requestAdditionalScopes() async throws {
        guard let presentingViewController = await getRootViewController() else {
            throw AuthenticationError.noViewController
        }
        
        try await GoogleSignIn.shared.addScopes(scopes, presenting: presentingViewController)
    }
    
    private func getRootViewController() async -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        return window.rootViewController
    }
    */
    
    /// Set authenticated user data (for custom OAuth integration)
    public func setAuthenticatedUser(_ user: SelineUser) async {
        await MainActor.run {
            self.user = user
            self.isAuthenticated = true
            self.hasCompletedOnboarding = true
            self.authError = nil
        }
        
        // Set the current user's email in UserDefaults for API key scoping
        userDefaults.set(user.email, forKey: "current_user_email")
        
        // CRITICAL: Store tokens in SecureStorage for Gmail operations
        if !user.accessToken.isEmpty || user.refreshToken != nil {
            let tokenStored = SecureStorage.shared.storeGoogleTokens(
                accessToken: user.accessToken,
                refreshToken: user.refreshToken
            )
            
            #if DEBUG
            print("🔐 Tokens stored in SecureStorage: \(tokenStored)")
            #endif
            
            if !tokenStored {
                ProductionLogger.logError(NSError(domain: "AuthenticationService", code: -3), context: "Failed to store tokens")
            }
        }
        
        // User successfully authenticated - proceed with sync
        
        // Integrate with Supabase for metadata storage (with consent)
        do {
            let supabaseUser = try await SupabaseService.shared.upsertUser(selineUser: user)
            
            await MainActor.run {
                self.user?.supabaseId = supabaseUser.id
            }

            #if DEBUG
            print("✅ User synchronized to Supabase: \(supabaseUser.id)")
            #endif
            
            // User successfully synced to Supabase
            
        } catch {
            ProductionLogger.logError(error, context: "Supabase user sync")
            // Don't fail authentication if Supabase sync fails
        }
        
        saveAuthState()
        
        // Initialize local email service with authenticated user
        LocalEmailService.shared.setCurrentUser(user)
        
        #if DEBUG
        print("✅ User authentication completed successfully")
        #endif
    }
    
    /// Check if user exists in Supabase and is returning user
    public func isReturningUser(_ googleID: String) async -> Bool {
        do {
            let existingUser = try await supabaseService.getUserByGoogleID(googleID)
            return existingUser != nil
        } catch {
            ProductionLogger.logError(error, context: "Checking returning user")
            return false
        }
    }
    
    /// Mark onboarding as completed
    public func completeOnboarding() {
        Task { @MainActor in
            self.hasCompletedOnboarding = true
        }
        userDefaults.set(true, forKey: onboardingKey)
        
        #if DEBUG
        print("🎯 Onboarding marked as completed")
        #endif
    }
}

// MARK: - Models

struct SelineUser: Codable {
    let id: String // Google ID
    var supabaseId: UUID?
    let email: String
    let name: String
    let profileImageURL: String?
    let accessToken: String
    let refreshToken: String?
    let tokenExpirationDate: Date?
    
    var isTokenExpired: Bool {
        guard let expirationDate = tokenExpirationDate else { return true }
        return Date() >= expirationDate
    }
}

// MARK: - Errors

enum AuthenticationError: LocalizedError {
    case noViewController
    case missingScopes
    case tokenExpired
    case networkError
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .noViewController:
            return "Could not find view controller for authentication"
        case .missingScopes:
            return "Required permissions not granted"
        case .tokenExpired:
            return "Authentication token has expired"
        case .networkError:
            return "Network error during authentication"
        case .userCancelled:
            return "Authentication cancelled by user"
        }
    }
}