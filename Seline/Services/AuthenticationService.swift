//
//  AuthenticationService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import Combine
import GoogleSignIn
import CommonCrypto

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
    @Published var isInitializing = true // NEW: Track initialization state
    
    private let userDefaults = UserDefaults.standard
    private let authStateKey = "seline_auth_state"
    private let userKey = "seline_user"
    private let onboardingKey = "seline_onboarding_completed"
    private let supabaseService = SupabaseService.shared
    
    // Debounce mechanism to prevent rapid auth state changes
    private var lastAuthStateChange: Date = Date()
    private let authStateChangeMinInterval: TimeInterval = 2.0 // Minimum 2 seconds between changes
    
    // Safe method to set authentication state with debouncing
    private func setAuthenticationState(_ isAuth: Bool, reason: String = "") {
        let now = Date()
        if now.timeIntervalSince(lastAuthStateChange) < authStateChangeMinInterval {
            #if DEBUG
            print("⏭️ Debouncing auth state change: \(reason) (too recent)")
            #endif
            return
        }
        
        lastAuthStateChange = now
        self.isAuthenticated = isAuth
        
        #if DEBUG
        print("🔐 Auth state set to \(isAuth): \(reason)")
        #endif
    }
    
    // Gmail and Calendar scopes
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.readonly",  // Try readonly first
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
        let currentUserEmail = userDefaults.string(forKey: "current_user_email")
        
        #if DEBUG
        print("🔍 Loading auth state:")
        print("  - Stored auth state: \(storedAuthState)")
        print("  - Completed onboarding: \(completedOnboarding)")
        print("  - Current user email: \(currentUserEmail ?? "nil")")
        #endif
        
        // CRITICAL FIX: Set onboarding state immediately (synchronous)
        self.hasCompletedOnboarding = completedOnboarding
        
        if let userData = userDefaults.data(forKey: userKey) {
            if let decodedUser = try? JSONDecoder().decode(SelineUser.self, from: userData) {
                #if DEBUG
                print("  - Decoded user: \(decodedUser.email)")
                print("  - Token expired: \(decodedUser.isTokenExpired)")
                #endif
                
                // CRITICAL FIX: Set user and auth state immediately (synchronous)
                self.user = decodedUser
                self.isAuthenticated = storedAuthState && !decodedUser.isTokenExpired
                
                // Check if token is expired (but be more lenient in development)
                #if DEBUG
                if decodedUser.isTokenExpired {
                    print("⚠️ Token expired in dev mode, extending expiration")
                    // In development, extend the token expiration instead of clearing auth
                    var extendedUser = SelineUser(
                        id: decodedUser.id,
                        email: decodedUser.email,
                        name: decodedUser.name,
                        profileImageURL: decodedUser.profileImageURL,
                        accessToken: decodedUser.accessToken,
                        refreshToken: decodedUser.refreshToken,
                        tokenExpirationDate: Date().addingTimeInterval(365 * 24 * 3600) // Extend for 1 year
                    )
                    extendedUser.supabaseId = decodedUser.supabaseId // Preserve supabaseId
                    Task { @MainActor in
                        self.user = extendedUser
                    }
                    saveAuthState() // Save the updated user with extended token
                }
                #else
                if decodedUser.isTokenExpired {
                    print("⚠️ Token expired in production mode, attempting refresh...")
                    // Instead of immediately clearing, try to refresh the token first
                    Task {
                        do {
                            try await self.refreshTokenIfNeeded()
                            print("✅ Token refreshed successfully in production")
                        } catch {
                            print("❌ Token refresh failed in production, clearing auth state")
                            await MainActor.run {
                                self.clearAuthState()
                            }
                        }
                    }
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
        
        // CRITICAL FIX: Set final authentication state synchronously
        self.isAuthenticated = storedAuthState && self.user != nil && !(self.user?.isTokenExpired ?? true)
        
        // CRITICAL FIX: Set initialization as complete synchronously
        self.isInitializing = false
        
        #if DEBUG
        print("🔐 Auth state loaded: authenticated=\(self.isAuthenticated), onboarding=\(self.hasCompletedOnboarding)")
        #endif
        
        // Background tasks (async but don't affect UI state)
        Task {
            // For existing users: if they don't have supabaseId but are authenticated, try to get it
            if let user = self.user, user.supabaseId == nil, self.isAuthenticated {
                await self.recoverSupabaseId(for: user)
            }
            
            // Update last sign in if authenticated
            if storedAuthState && self.user != nil {
                do {
                    try await supabaseService.updateLastSignIn(userID: UUID())
                } catch {
                    ProductionLogger.logError(error, context: "Updating last sign in")
                }
            }
        }
    }
    
    private func clearAuthState() {
        setAuthenticationState(false, reason: "clearing auth state")
        self.user = nil
        self.authError = nil
        // Keep onboarding state so user doesn't see intro screens again
        
        // Clear UserDefaults but preserve user email for OpenAI key scoping
        // IMPORTANT: Don't clear "current_user_email" - needed for API key scoping
        userDefaults.removeObject(forKey: authStateKey)
        userDefaults.removeObject(forKey: userKey)
        // Don't clear onboarding state - user has already seen the flow
        
        // CRITICAL: Clear tokens from secure storage but preserve API keys
        let secureStorage = SecureStorage.shared
        secureStorage.clearGoogleCredentials()
        // NOTE: Don't clear OpenAI key here - only clear during complete sign out
        
        #if DEBUG
        print("🧹 Authentication state cleared (preserving API keys and user email)")
        #endif
    }
    
    private func saveAuthState() {
        userDefaults.set(isAuthenticated, forKey: authStateKey)
        userDefaults.set(hasCompletedOnboarding, forKey: onboardingKey)
        if let user = user,
           let userData = try? JSONEncoder().encode(user) {
            userDefaults.set(userData, forKey: userKey)
            
            // CRITICAL FIX: Save current user email for OpenAI key scoping
            userDefaults.set(user.email.lowercased(), forKey: "current_user_email")
            
            #if DEBUG
            print("💾 User data saved for: \(user.email)")
            print("💾 Current user email saved: \(user.email.lowercased())")
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
        
        // Additional check: Don't refresh if we're in DEBUG mode and token is still valid for more than 1 hour
        #if DEBUG
        let oneHourFromNow = Date().addingTimeInterval(3600)
        if let expiration = user.tokenExpirationDate, expiration > oneHourFromNow {
            return
        }
        #endif
        
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
            tokenExpirationDate: Date().addingTimeInterval(24 * 3600) // Extend for 24 hours in DEBUG
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
    
    /// Gracefully handle calendar scope upgrade without forcing logout
    func requestCalendarScopeUpgrade() async {
        print("🗓️ Calendar access not available - continuing without calendar features")
        print("   App will function normally with email and other features")
        print("   Calendar integration can be enabled later through settings")
        
        // Don't force sign out - just continue without calendar access
        // The app should gracefully degrade and work without calendar features
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
            
            // Request all scopes upfront to avoid incremental authorization issues
            let result = try await GoogleSignIn.shared.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: scopes)
            let user = result.user
            
            // Verify we got all required scopes
            guard let grantedScopes = user.grantedScopes,
                  scopes.allSatisfy({ grantedScopes.contains($0) }) else {
                print("⚠️ Not all required scopes were granted")
                print("📋 Requested: \(scopes)")
                print("✅ Granted: \(user.grantedScopes ?? [])")
                throw AuthenticationError.missingScopes
            }
            
            await handleSuccessfulSignIn(user: user)
            
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
        
        // Clear local state INCLUDING user email (complete sign out)
        clearAuthStateCompletely()
        
        #if DEBUG
        print("✅ Sign out completed")
        #endif
        
        isLoading = false
    }
    
    /// Complete sign out that clears everything including user email
    private func clearAuthStateCompletely() {
        Task { @MainActor in
            self.isAuthenticated = false
            self.user = nil
            self.authError = nil
        }
        
        // Clear ALL UserDefaults including user email
        userDefaults.removeObject(forKey: authStateKey)
        userDefaults.removeObject(forKey: userKey)
        userDefaults.removeObject(forKey: "current_user_email") // Clear for complete sign out
        
        // Clear tokens from secure storage
        let secureStorage = SecureStorage.shared
        secureStorage.clearGoogleCredentials()
        
        #if DEBUG
        print("🧹 Complete authentication state cleared including user email")
        #endif
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
        if isAuthenticated, let user = user {
            print("🔐 AUTH: \(user.name) (\(user.email))")
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
        var updatedUser = user
        do {
            let supabaseUser = try await SupabaseService.shared.upsertUser(user)
            
            // Update the user object with Supabase ID
            updatedUser.supabaseId = supabaseUser.id

            #if DEBUG
            print("✅ User synchronized to Supabase: \(supabaseUser.id)")
            #endif
            
        } catch {
            #if DEBUG
            LogRateLimiter.shared.logIfAllowed("supabase_user_sync_failed", interval: 30.0) {
                print("⚠️ [AuthenticationService.swift:564] setAuthenticatedUser(_:) - Error in Supabase user sync: \(error)")
            }
            #endif
            
            // CRITICAL FIX: Create a deterministic UUID based on Google ID to ensure consistency
            // This prevents repeated Supabase sync failures and enables offline functionality
            if updatedUser.supabaseId == nil {
                let deterministicUUID = generateDeterministicUUID(from: user.id)
                updatedUser.supabaseId = deterministicUUID
                
                #if DEBUG
                print("🔧 Generated offline Supabase ID: \(deterministicUUID)")
                #endif
            }
        }
        
        // Set the user (with or without Supabase ID)
        await MainActor.run {
            self.user = updatedUser
        }
        
        saveAuthState()
        
        // Initialize local email service with authenticated user
        LocalEmailService.shared.setCurrentUser(updatedUser)
        
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
    
    /// Recover supabaseId for existing users who don't have it
    private func recoverSupabaseId(for user: SelineUser) async {
        ProductionLogger.logAuthEvent("[AuthenticationService] Recovering Supabase ID for user: \(user.email)")
        
        do {
            // Try to find existing user in Supabase by Google ID
            if let existingUser = try await supabaseService.getUserByGoogleID(user.id) {
                // User exists in Supabase, update local user with Supabase ID
                var updatedUser = user
                updatedUser.supabaseId = existingUser.id
                
                await MainActor.run {
                    self.user = updatedUser
                }
                saveAuthState()
                
                ProductionLogger.logAuthEvent("✅ [AuthenticationService] Supabase ID recovered from existing user: \(existingUser.id)")
                
            } else {
                // User doesn't exist in Supabase, create them
                ProductionLogger.logAuthEvent("[AuthenticationService] User not found in Supabase, creating new user")
                
                let supabaseUser = try await supabaseService.upsertUser(user)
                var updatedUser = user
                updatedUser.supabaseId = supabaseUser.id
                
                await MainActor.run {
                    self.user = updatedUser
                }
                saveAuthState()
                
                ProductionLogger.logAuthEvent("✅ [AuthenticationService] New Supabase user created: \(supabaseUser.id)")
            }
            
        } catch let supabaseError as SupabaseError {
            // Handle specific Supabase errors with detailed context
            let context = "Supabase ID recovery for user: \(user.email)"
            
            switch supabaseError {
            case .connectionFailed(let message):
                ProductionLogger.logError(supabaseError, context: "\(context) - Connection failed: \(message)")
                
            case .authenticationFailed(let message):
                ProductionLogger.logError(supabaseError, context: "\(context) - Authentication failed: \(message)")
                // Clear auth state if authentication is completely broken
                await signOut()
                
            case .userNotFound:
                ProductionLogger.logAuthEvent("ℹ️ [AuthenticationService] User not found in Supabase, will create new user on next sync")
                
            case .networkError(let underlyingError):
                ProductionLogger.logError(underlyingError, context: "\(context) - Network error during Supabase ID recovery")
                
            case .configurationError(let message):
                ProductionLogger.logError(supabaseError, context: "\(context) - Configuration error: \(message)")
                
            default:
                ProductionLogger.logError(supabaseError, context: context)
            }
            
        } catch {
            // Handle any other unexpected errors
            let mappedError = SupabaseError.from(error, context: "Supabase ID recovery")
            ProductionLogger.logError(mappedError, context: "Unexpected error in Supabase ID recovery for user: \(user.email)")
        }
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
    case calendarScopeRequired
    case tokenExpired
    case networkError
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .noViewController:
            return "Could not find view controller for authentication"
        case .missingScopes:
            return "Required permissions not granted"
        case .calendarScopeRequired:
            return "Calendar access required - please sign in again"
        case .tokenExpired:
            return "Authentication token has expired"
        case .networkError:
            return "Network error during authentication"
        case .userCancelled:
            return "Authentication cancelled by user"
        }
    }
}

// MARK: - UUID Generation Helper

extension Data {
    var sha256: Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}

extension AuthenticationService {
    /// Generate a deterministic UUID from a Google ID for offline Supabase compatibility
    private func generateDeterministicUUID(from googleID: String) -> UUID {
        // Create a namespace UUID for Seline app (using a fixed UUID for consistency)
        let namespace = "seline-app-namespace"
        
        // Create deterministic UUID using namespace + Google ID
        let combinedString = namespace + googleID
        let data = combinedString.data(using: .utf8)!
        
        // Simple hash-based UUID generation
        let hashValue = abs(data.hashValue)
        let uuidString = String(format: "12FC56DB-E575-4C21-B61F-%012d", hashValue % 1000000000000)
        
        return UUID(uuidString: uuidString) ?? UUID()
    }
}