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
    
    private let userDefaults = UserDefaults.standard
    private let authStateKey = "seline_auth_state"
    private let userKey = "seline_user"
    
    // Gmail and Calendar scopes
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]
    
    private init() {
        loadAuthState()
    }
    
    // MARK: - Authentication State Management
    
    private func loadAuthState() {
        isAuthenticated = userDefaults.bool(forKey: authStateKey)
        if let userData = userDefaults.data(forKey: userKey),
           let user = try? JSONDecoder().decode(SelineUser.self, from: userData) {
            self.user = user
        }
    }
    
    private func saveAuthState() {
        userDefaults.set(isAuthenticated, forKey: authStateKey)
        if let user = user,
           let userData = try? JSONEncoder().encode(user) {
            userDefaults.set(userData, forKey: userKey)
        }
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle() async {
        isLoading = true
        authError = nil
        
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
            authError = error.localizedDescription
            print("Google Sign-In failed: \(error)")
        }
        
        isLoading = false
    }
    
    func signOut() async {
        isLoading = true
        
        // TODO: Replace with actual Google Sign-Out
        /*
        do {
            GoogleSignIn.sharedInstance.signOut()
        } catch {
            authError = "Sign out failed: \(error.localizedDescription)"
        }
        */
        
        // Clear local state
        isAuthenticated = false
        user = nil
        userDefaults.removeObject(forKey: authStateKey)
        userDefaults.removeObject(forKey: userKey)
        
        isLoading = false
    }
    
    func refreshTokenIfNeeded() async {
        guard let _ = user, isAuthenticated else { return }
        
        // TODO: Implement token refresh logic
        /*
        do {
            let currentUser = GoogleSignIn.sharedInstance.currentUser
            try await currentUser?.refreshTokensIfNeeded()
        } catch {
            print("Token refresh failed: \(error)")
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
            id: "mock_user_123",
            email: "user@example.com",
            name: "John Doe",
            profileImageURL: nil,
            accessToken: "mock_access_token",
            refreshToken: "mock_refresh_token",
            tokenExpirationDate: Date().addingTimeInterval(3600)
        )
        
        self.user = mockUser
        self.isAuthenticated = true
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