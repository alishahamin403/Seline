//
//  AuthenticationService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import Combine
// import GoogleSignIn
// import GoogleAPIClientForREST

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
        ProductionLogger.logAuthEvent("Loading authentication state")
        
        let storedAuthState = userDefaults.bool(forKey: authStateKey)
        let completedOnboarding = userDefaults.bool(forKey: onboardingKey)
        
        if let userData = userDefaults.data(forKey: userKey) {
            if let decodedUser = try? JSONDecoder().decode(SelineUser.self, from: userData) {
                Task { @MainActor in
                    self.user = decodedUser
                    self.hasCompletedOnboarding = completedOnboarding
                }
                ProductionLogger.logAuthEvent("User data loaded for: \(decodedUser.email)")
                
                // Check if token is expired (but be more lenient in development)
                #if DEBUG
                if decodedUser.isTokenExpired {
                    ProductionLogger.logAuthEvent("⚠️ Token expired in dev mode, but keeping user signed in")
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
                    ProductionLogger.logAuthEvent("Token expired, clearing auth state")
                    clearAuthState()
                    return
                }
                #endif
                
                // Update last sign in if authenticated
                if storedAuthState {
                    Task {
                        do {
                            // In a real implementation, get user ID from Supabase
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
            // If we have user data stored (even if not currently authenticated), they've completed onboarding
            self.hasCompletedOnboarding = completedOnboarding || self.user != nil
            ProductionLogger.logAuthEvent("Authentication state set: \(self.isAuthenticated), onboarding: \(self.hasCompletedOnboarding)")
        }
    }
    
    private func clearAuthState() {
        ProductionLogger.logAuthEvent("Clearing authentication state")
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
        ProductionLogger.logAuthEvent("Saving authentication state")
        userDefaults.set(isAuthenticated, forKey: authStateKey)
        userDefaults.set(hasCompletedOnboarding, forKey: onboardingKey)
        if let user = user,
           let userData = try? JSONEncoder().encode(user) {
            userDefaults.set(userData, forKey: userKey)
            ProductionLogger.logAuthEvent("✅ User data saved for: \(user.email) - Token expires: \(user.tokenExpirationDate?.description ?? "never")")
        }
        
        // Force synchronize to ensure data is written immediately
        userDefaults.synchronize()
    }
    
    private func debugInitialState() {
        #if DEBUG
        ProductionLogger.logAuthEvent("AuthenticationService initialized - isAuthenticated: \(isAuthenticated), user: \(user?.email ?? "nil")")
        #endif
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle() async {
        await MainActor.run {
            isLoading = true
            authError = nil
        }
        
        // Check if user is already authenticated and token is valid
        if isAuthenticated, let user = user, !user.isTokenExpired {
            ProductionLogger.logAuthEvent("✅ User already authenticated and token is valid, skipping sign-in")
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
    }
    
    func signOut() async {
        ProductionLogger.logAuthEvent("Sign out initiated")
        isLoading = true
        
        // TODO: Replace with actual Google Sign-Out
        /*
        do {
            GoogleSignIn.sharedInstance.signOut()
        } catch {
            authError = "Sign out failed: \(error.localizedDescription)"
        }
        */
        
        // Clear local email service
        LocalEmailService.shared.signOut()
        
        // Clear local state
        clearAuthState()
        ProductionLogger.logAuthEvent("Sign out completed")
        
        isLoading = false
    }
    
    // MARK: - Debug Methods
    
    func forceSignOut() {
        ProductionLogger.logAuthEvent("Force sign out executed")
        clearAuthState()
    }
    
    /// Check if user has valid persistent authentication
    func checkPersistentAuthentication() -> Bool {
        let hasValidUser = user != nil
        let isCurrentlyAuthenticated = isAuthenticated
        let tokenNotExpired = user?.isTokenExpired == false
        
        let isPersistent = hasValidUser && isCurrentlyAuthenticated && tokenNotExpired
        
        ProductionLogger.logAuthEvent("🔍 Persistent auth check - Valid user: \(hasValidUser), Authenticated: \(isCurrentlyAuthenticated), Token valid: \(tokenNotExpired) = Result: \(isPersistent)")
        
        return isPersistent
    }
    
    func debugCurrentState() {
        #if DEBUG
        ProductionLogger.logAuthEvent("Auth Debug - isAuthenticated: \(isAuthenticated), user: \(user?.email ?? "nil"), loading: \(isLoading)")
        if let user = user {
            ProductionLogger.logAuthEvent("User details - ID: \(user.id), Name: \(user.name), Token expired: \(user.isTokenExpired)")
        }
        #endif
    }
    
    func refreshTokenIfNeeded() async {
        ProductionLogger.logAuthEvent("Checking token refresh needed")
        
        guard let currentUser = user, isAuthenticated else { 
            ProductionLogger.logAuthEvent("Not authenticated or no user, skipping refresh")
            return 
        }
        
        if currentUser.isTokenExpired {
            ProductionLogger.logAuthEvent("Token expired, clearing auth state")
            clearAuthState()
            return
        }
        
        ProductionLogger.logAuthEvent("Token is still valid")
        
        // TODO: Implement token refresh logic
        /*
        do {
            let currentUser = GoogleSignIn.sharedInstance.currentUser
            try await currentUser?.refreshTokensIfNeeded()
        } catch {
            ProductionLogger.logAuthError(error, context: "Token refresh")
            await signOut()
        }
        */
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
        
        try await GoogleSignIn.sharedInstance.addScopes(scopes, presenting: presentingViewController)
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
        ProductionLogger.logAuthEvent("Setting authenticated user: \(user.email)")
        
        await MainActor.run {
            self.user = user
            self.isAuthenticated = true
            self.hasCompletedOnboarding = true
            self.authError = nil
        }
        // Persist Google tokens to secure storage if provided
        if !user.accessToken.isEmpty || user.refreshToken != nil {
            _ = SecureStorage.shared.storeGoogleTokens(
                accessToken: user.accessToken,
                refreshToken: user.refreshToken
            )
        }
        
        // Persist user data to Supabase
        do {
            let supabaseUser = try await supabaseService.upsertUser(selineUser: user)
            ProductionLogger.logAuthEvent("User persisted to Supabase: \(supabaseUser.id)")
        } catch {
            ProductionLogger.logError(error, context: "Persisting user to Supabase")
            // Don't fail authentication if Supabase sync fails
        }
        
        saveAuthState()
        
        // Initialize local email service with authenticated user
        LocalEmailService.shared.setCurrentUser(user)
        
        ProductionLogger.logAuthEvent("User authentication completed successfully")
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
        ProductionLogger.logAuthEvent("Onboarding marked as completed")
    }
}

// MARK: - Models

struct SelineUser: Codable {
    let id: String
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