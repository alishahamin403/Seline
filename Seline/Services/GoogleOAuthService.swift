//
//  GoogleOAuthService.swift
//  Seline
//
//  Created by Claude on 2025-08-25.
//

import Foundation
import AuthenticationServices
import Combine
import CryptoKit
import UIKit

// TODO: Consider switching to GoogleSignIn SDK if custom OAuth continues to fail:
// 1. Add GoogleSignIn to Package.swift
// 2. Replace custom OAuth with: GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
// 3. This handles all OAuth complexity automatically

/// Production-ready Google OAuth 2.0 service for Gmail and Calendar access
@MainActor
class GoogleOAuthService: NSObject, ObservableObject {
    static let shared = GoogleOAuthService()
    
    // MARK: - Configuration
    
    private let secureStorage = SecureStorage.shared
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - OAuth URLs (Production Ready)
    
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let revokeURL = "https://oauth2.googleapis.com/revoke"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"
    
    // MARK: - Scopes (Must match Google Cloud Console OAuth consent screen)
    
    private let requiredScopes = [
        // Use gmail.modify to allow moving messages to Trash and label changes
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]
    
    /// Get the configured scopes for validation
    func getConfiguredScopes() -> [String] {
        return requiredScopes
    }
    
    /// Verify scopes match Google Console configuration
    func validateScopeConfiguration() {
        print("📋 GOOGLE OAUTH SCOPE VALIDATION:")
        print("   Required scopes (must match Google Console OAuth consent screen):")
        requiredScopes.enumerated().forEach { index, scope in
            print("   \(index + 1). \(scope)")
        }
        print("   ⚠️  Ensure these exact scopes are added in Google Cloud Console > OAuth consent screen > Scopes")
    }
    
    /// Validate URL scheme configuration
    func validateURLSchemeConfiguration() {
        print("📋 URL SCHEME VALIDATION:")
        print("═══════════════════════════════════════════════════")
        
        let callbackScheme = getCallbackURLScheme()
        print("   Expected URL Scheme: \(callbackScheme)")
        
        // Check Info.plist CFBundleURLTypes
        if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] {
            print("   ✅ Found CFBundleURLTypes in Info.plist")
            
            var foundMatchingScheme = false
            for (index, urlType) in urlTypes.enumerated() {
                print("   📋 URL Type \(index + 1):")
                
                if let name = urlType["CFBundleURLName"] as? String {
                    print("      Name: \(name)")
                }
                
                if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                    print("      Schemes:")
                    schemes.forEach { scheme in
                        print("         - \(scheme)")
                        if scheme == callbackScheme {
                            foundMatchingScheme = true
                            print("           ✅ MATCHES expected callback scheme!")
                        }
                    }
                }
            }
            
            if foundMatchingScheme {
                print("   ✅ URL scheme properly configured in Info.plist")
            } else {
                print("   ❌ MISSING URL scheme in Info.plist!")
                print("   💡 Add '\(callbackScheme)' to CFBundleURLSchemes array")
                print("   💡 This will cause OAuth callback failures!")
            }
            
        } else {
            print("   ❌ CFBundleURLTypes not found in Info.plist")
            print("   💡 Add URL schemes configuration to Info.plist")
        }
        
        print("═══════════════════════════════════════════════════")
    }
    
    /// Complete OAuth configuration validation
    func validateCompleteOAuthConfiguration() {
        print("🔍 COMPLETE OAUTH CONFIGURATION VALIDATION:")
        print("═══════════════════════════════════════════════════")
        
        // 1. Bundle ID validation
        print("1️⃣ Bundle ID Check:")
        if let bundleID = Bundle.main.bundleIdentifier {
            print("   App Bundle ID: \(bundleID)")
            print("   ✅ Bundle ID exists")
        } else {
            print("   ❌ Bundle ID missing!")
        }
        
        // 2. GoogleService-Info.plist validation
        print("\n2️⃣ GoogleService-Info.plist Check:")
        _ = getClientID() // This will log detailed validation
        
        // 3. URL Scheme validation
        print("\n3️⃣ URL Scheme Check:")
        validateURLSchemeConfiguration()
        
        // 4. Google Console checklist
        print("4️⃣ Google Cloud Console Checklist:")
        print("   ⚠️  CRITICAL: Based on Error 400 screenshot, fix these:")
        print("   □ OAuth 2.0 Client ID created for iOS (NOT Web)")
        print("   □ Bundle ID matches: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        print("   □ Redirect URI uses the default iOS native path: scheme:/oauth2redirect/google")
        print("   □ URL scheme in Info.plist: \(getCallbackURLScheme())")
        print("   □ OAuth consent screen configured")
        print("   □ Required scopes added to consent screen")
        print("   □ App status is 'Testing' or 'Published'")
        print("")
        print("🚨 IMMEDIATE ACTION REQUIRED FOR iOS OAUTH:")
        print("   iOS OAuth clients use the default native redirect and PKCE.")
        print("")
        print("   1️⃣ APIs & Services → Credentials → iOS OAuth Client:")
        print("      ✅ Bundle ID: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        print("      ✅ iOS URL scheme: \(getCallbackURLScheme())")
        print("")
        print("   2️⃣ APIs & Services → OAuth consent screen:")
        print("      □ App name filled in")
        print("      □ User support email set")
        print("      □ Developer contact email set")
        print("      □ Add your email to 'Test users' if app is in Testing mode")
        print("")
        print("   3️⃣ OAuth consent screen → Scopes:")
        requiredScopes.forEach { scope in
            print("      □ \(scope)")
        }
        print("")
        print("   4️⃣ APIs & Services → Library (enable these APIs):")
        print("      □ Gmail API")
        print("      □ Google Calendar API")
        print("      □ Google People API (for user profile)")
        print("")
        print("   5️⃣ OAuth consent screen → Publishing status:")
        print("      □ Set to 'In production' OR add your Google account to test users")
        
        print("═══════════════════════════════════════════════════")
    }
    
    // MARK: - Published Properties
    
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var userProfile: GoogleUserProfile?
    @Published var lastError: GoogleOAuthError?
    
    // MARK: - Private Properties
    
    private var authenticationSession: ASWebAuthenticationSession?
    private var currentState: String?
    private var codeVerifier: String?
    
    private override init() {
        super.init()
        checkAuthenticationStatus()
    }
    
    // MARK: - Authentication Status
    
    private func checkAuthenticationStatus() {
        // Rehydrate AuthenticationService with Keychain tokens if present
        if let access = secureStorage.getGoogleAccessToken() {
            let storedRefresh = secureStorage.getGoogleRefreshToken()
            // If AuthenticationService lacks a user, create a minimal shell so services can use the token
            let auth = AuthenticationService.shared
            if auth.user == nil {
                let selineUser = SelineUser(
                    id: UUID().uuidString,
                    email: userProfile?.email ?? "",
                    name: userProfile?.name ?? "",
                    profileImageURL: userProfile?.picture,
                    accessToken: access,
                    refreshToken: storedRefresh,
                    tokenExpirationDate: Date().addingTimeInterval(3600)
                )
                Task { await auth.setAuthenticatedUser(selineUser) }
            }
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
        
        if isAuthenticated {
            Task {
                await loadUserProfile()
                await validateAndRefreshTokenIfNeeded()
            }
        }
    }
    
    // MARK: - OAuth Flow
    
    /// Start OAuth authentication flow
    func authenticate() async throws {
        print("🔐 Starting Google OAuth authentication flow...")
        
        guard !isAuthenticating else {
            print("❌ Authentication already in progress")
            throw GoogleOAuthError.authenticationInProgress
        }
        
        isAuthenticating = true
        lastError = nil
        
        do {
            let authCode = try await performOAuthFlow()
            let tokens = try await exchangeCodeForTokens(authCode)
            
            // Store tokens securely
            guard secureStorage.storeGoogleTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            ) else {
                throw GoogleOAuthError.tokenStorageError
            }
            
            // Load user profile
            await loadUserProfile()
            
            if let profile = userProfile {
                isAuthenticated = true
                // Update AuthenticationService with user data
                await updateAuthenticationService(with: profile)
                print("✅ Google OAuth authentication completed for: \(profile.email)")
            } else {
                isAuthenticated = true // Still consider authenticated even if profile loading fails
            }
            
        } catch {
            let oauthError = error as? GoogleOAuthError ?? GoogleOAuthError.unknownError
            lastError = oauthError
            print("❌ OAuth authentication failed: \(oauthError.localizedDescription)")
            throw error
        }
        
        isAuthenticating = false
    }
    
    /// Perform OAuth flow using ASWebAuthenticationSession
    private func performOAuthFlow() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Generate state parameter for security
            currentState = generateState()
            // Generate PKCE code verifier
            codeVerifier = generateCodeVerifier()
            
            // Build authorization URL
            guard let authURL = buildAuthorizationURL() else {
                print("❌ Failed to build authorization URL")
                continuation.resume(throwing: GoogleOAuthError.invalidAuthURL)
                return
            }
            
            print("🌐 Authorization URL: \(authURL.absoluteString)")
            print("📱 Callback URL Scheme: \(getCallbackURLScheme())")
            
            // Start authentication session
            authenticationSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: getCallbackURLScheme()
            ) { [weak self] callbackURL, error in
                
                if let error = error {
                    print("❌ Authentication session error: \(error.localizedDescription)")
                    print("   Full error: \(error)")
                    
                    if let webAuthError = error as? ASWebAuthenticationSessionError {
                        print("   ASWebAuthenticationSessionError code: \(webAuthError.code.rawValue)")
                        
                        switch webAuthError.code {
                        case .canceledLogin:
                            print("👤 User cancelled the authentication flow")
                            continuation.resume(throwing: GoogleOAuthError.userCancelled)
                        case .presentationContextNotProvided:
                            print("❌ Presentation context not provided")
                            continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                        case .presentationContextInvalid:
                            print("❌ Presentation context invalid")
                            continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                        @unknown default:
                            print("❌ Unknown ASWebAuthenticationSessionError: \(webAuthError.code.rawValue)")
                            continuation.resume(throwing: GoogleOAuthError.authenticationFailed(error))
                        }
                    } else {
                        print("🚫 Authentication failed with non-ASWebAuthenticationSessionError: \(error)")
                        continuation.resume(throwing: GoogleOAuthError.authenticationFailed(error))
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    print("❌ No callback URL received from authentication session")
                    continuation.resume(throwing: GoogleOAuthError.invalidCallback)
                    return
                }
                
                print("✅ Callback URL received: \(callbackURL.absoluteString)")
                
                do {
                    let authCode = try self?.extractAuthCodeFromCallback(callbackURL) ?? ""
                    print("✅ Authorization code extracted successfully")
                    continuation.resume(returning: authCode)
                } catch {
                    print("❌ Failed to extract authorization code: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            
            // Configure session
            print("⚙️ Configuring authentication session...")
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = true
            
            print("🔍 Session Configuration:")
            print("   - Presentation context provider: \(authenticationSession?.presentationContextProvider != nil ? "✅ Set" : "❌ Missing")")
            print("   - Ephemeral session: \(authenticationSession?.prefersEphemeralWebBrowserSession == true ? "✅ Yes" : "❌ No")")
            
            // Start session
            print("🚀 Starting authentication session...")
            let didStart = authenticationSession?.start()
            print("   Session start result: \(didStart == true ? "✅ Success" : "❌ Failed")")
            
            guard didStart == true else {
                print("❌ Failed to start authentication session")
                print("   This usually means:")
                print("   - Invalid URL")
                print("   - Invalid callback scheme")
                print("   - Missing presentation context")
                continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                return
            }
            print("✅ Authentication session started successfully - waiting for user interaction...")
        }
    }
    
    /// Build authorization URL with proper parameters
    private func buildAuthorizationURL() -> URL? {
        guard let clientID = getClientID() else {
            print("❌ OAUTH DEBUG: Client ID is nil - check GoogleService-Info.plist")
            return nil
        }
        
        print("🔍 OAUTH REQUEST DEBUG:")
        print("═══════════════════════════════════════════════════")
        print("📱 App Configuration:")
        print("   Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("   Client ID: \(clientID)")
        print("   Client ID (last 10 chars): ...\(String(clientID.suffix(10)))")
        
        let redirectURI = getRedirectURI()
        let scopeString = requiredScopes.joined(separator: " ")
        
        // Ensure we have a PKCE verifier/challenge
        let verifier = codeVerifier ?? generateCodeVerifier()
        codeVerifier = verifier
        let codeChallenge = codeChallengeS256(from: verifier)
        
        print("🌐 OAuth Parameters:")
        print("   Authorization URL: \(authURL)")
        print("   Client ID: \(clientID)")
        print("   Redirect URI: \(redirectURI)")
        print("   Response Type: code")
        print("   Scope: \(scopeString)")
        print("   State: \(currentState ?? "nil")")
        print("   Access Type: offline")
        print("   Prompt: consent")
        print("   PKCE: S256")
        
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopeString),
            URLQueryItem(name: "state", value: currentState),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let finalURL = components?.url else {
            print("❌ OAUTH DEBUG: Failed to construct URL from components")
            return nil
        }
        
        print("🔗 Final OAuth Request URL:")
        print("   \(finalURL.absoluteString)")
        print("═══════════════════════════════════════════════════")
        
        return finalURL
    }
    
    /// Extract authorization code from callback URL
    private func extractAuthCodeFromCallback(_ url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw GoogleOAuthError.invalidCallback
        }
        
        // Check for errors first and parse specific Google errors
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            
            print("❌ OAuth authorization error: \(error)")
            print("   Description: \(errorDescription)")
            
            switch error {
            case "access_denied":
                throw GoogleOAuthError.accessDenied(errorDescription)
            case "invalid_client":
                throw GoogleOAuthError.invalidClient(errorDescription)
            case "invalid_grant":
                throw GoogleOAuthError.invalidGrant(errorDescription)
            case "unauthorized_client":
                throw GoogleOAuthError.unauthorizedClient(errorDescription)
            case "unsupported_grant_type":
                throw GoogleOAuthError.unsupportedGrantType(errorDescription)
            case "invalid_scope":
                throw GoogleOAuthError.invalidScope(errorDescription)
            case "server_error":
                throw GoogleOAuthError.serverError(errorDescription)
            case "temporarily_unavailable":
                throw GoogleOAuthError.temporarilyUnavailable(errorDescription)
            default:
                throw GoogleOAuthError.authorizationError(errorDescription)
            }
        }
        
        // Validate state parameter
        let receivedState = queryItems.first(where: { $0.name == "state" })?.value
        guard receivedState == currentState else {
            throw GoogleOAuthError.stateValidationFailed
        }
        
        // Extract authorization code
        guard let authCode = queryItems.first(where: { $0.name == "code" })?.value else {
            throw GoogleOAuthError.missingAuthCode
        }
        
        return authCode
    }
    
    /// Exchange authorization code for tokens
    private func exchangeCodeForTokens(_ code: String) async throws -> GoogleTokenResponse {
        guard let clientID = getClientID() else {
            throw GoogleOAuthError.missingClientCredentials
        }
        
        print("🔍 TOKEN EXCHANGE DEBUG:")
        print("═══════════════════════════════════════════════════")
        print("📋 Token Exchange Parameters:")
        print("   Token URL: \(tokenURL)")
        print("   Client ID: \(clientID)")
        print("   Authorization Code: \(code.prefix(20))...\(code.suffix(10))")
        print("   Grant Type: authorization_code")
        
        let redirectURI = getRedirectURI()
        print("   Redirect URI: \(redirectURI)")
        
        // iOS OAuth flow - client secret is optional for native apps
        var requestBody = [
            "client_id": clientID,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier ?? ""
        ]
        
        // Add client secret if available (but not required for iOS)
        let clientSecret = getClientSecret()
        if let clientSecret = clientSecret, !clientSecret.isEmpty {
            requestBody["client_secret"] = clientSecret
            print("   Client Secret: [PROVIDED]")
        } else {
            print("   Client Secret: [NOT PROVIDED - using public client flow for iOS]")
        }
        
        print("🌐 HTTP Request Details:")
        print("   Method: POST")
        print("   Content-Type: application/x-www-form-urlencoded")
        print("   Request Body Parameters:")
        requestBody.forEach { key, value in
            if key == "code" {
                print("      \(key): \(String(value.prefix(20)))...\(String(value.suffix(10)))")
            } else if key == "client_secret" {
                print("      \(key): [REDACTED]")
            } else if key == "code_verifier" {
                print("      \(key): [SENT]")
            } else {
                print("      \(key): \(value)")
            }
        }
        
        guard let url = URL(string: tokenURL) else {
            print("❌ Failed to create URL from: \(tokenURL)")
            throw GoogleOAuthError.invalidTokenURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Convert parameters to form data
        let formData = requestBody
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        print("📤 Form Data: \(formData.count) characters")
        print("═══════════════════════════════════════════════════")
        
        let session = networkManager.createURLSession()
        
        do {
            print("📡 Sending token exchange request...")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type received")
                throw GoogleOAuthError.invalidResponse
            }
            
            print("📥 Token Exchange Response:")
            print("   Status Code: \(httpResponse.statusCode)")
            print("   Response Headers:")
            httpResponse.allHeaderFields.forEach { key, value in
                print("      \(key): \(value)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Response Body: \(responseString)")
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ Token exchange failed with status code: \(httpResponse.statusCode)")
                
                // Try to parse Google's error response
                if let errorResponse = try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data) {
                    print("❌ Google token exchange error: \(errorResponse.error)")
                    print("   Description: \(errorResponse.errorDescription ?? "No description")")
                    print("   Error URI: \(errorResponse.errorURI ?? "No error URI")")
                    
                    print("🔍 Common Error 400 Causes:")
                    switch errorResponse.error {
                    case "invalid_client":
                        print("   - Bundle ID doesn't match Google Console configuration")
                        print("   - CLIENT_ID is incorrect or missing")
                        print("   - App not configured as 'iOS' type in Google Console")
                        throw GoogleOAuthError.invalidClient(errorResponse.errorDescription ?? "Invalid client credentials")
                    case "invalid_grant":
                        print("   - Authorization code expired or already used")
                        print("   - redirect_uri doesn't match the one used in authorization")
                        print("   - Missing or invalid PKCE code_verifier")
                        throw GoogleOAuthError.invalidGrant(errorResponse.errorDescription ?? "Invalid authorization grant")
                    case "unauthorized_client":
                        print("   - Client not authorized for this grant type")
                        print("   - OAuth app type configuration issue")
                        throw GoogleOAuthError.unauthorizedClient(errorResponse.errorDescription ?? "Client not authorized")
                    case "unsupported_grant_type":
                        print("   - Grant type 'authorization_code' not supported")
                        throw GoogleOAuthError.unsupportedGrantType(errorResponse.errorDescription ?? "Unsupported grant type")
                    case "invalid_scope":
                        print("   - One or more scopes are invalid or not authorized")
                        throw GoogleOAuthError.invalidScope(errorResponse.errorDescription ?? "Invalid scope")
                    default:
                        print("   - Unknown error: \(errorResponse.error)")
                        throw GoogleOAuthError.tokenExchangeFailed(httpResponse.statusCode)
                    }
                } else {
                    print("❌ Failed to parse error response, raw status code: \(httpResponse.statusCode)")
                    throw GoogleOAuthError.tokenExchangeFailed(httpResponse.statusCode)
                }
            }
            
            print("✅ Token exchange successful, parsing response...")
            let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
            print("✅ Token response parsed successfully")
            return tokenResponse
            
        } catch {
            print("❌ Token exchange network error: \(error.localizedDescription)")
            throw GoogleOAuthError.networkError(error)
        }
    }
    
    // MARK: - Token Management
    
    /// Validate current token and refresh if needed
    private func validateAndRefreshTokenIfNeeded() async {
        guard let accessToken = secureStorage.getGoogleAccessToken() else {
            isAuthenticated = false
            return
        }
        
        // Test token validity with a simple API call
        if await !isTokenValid(accessToken) {
            _ = await refreshTokenIfPossible()
        }
    }
    
    
    /// Check if access token is valid
    private func isTokenValid(_ token: String) async -> Bool {
        guard let url = URL(string: userInfoURL) else { return false }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let session = networkManager.createURLSession(timeout: 10)
            let (_, response) = try await session.data(for: request)
            
            let isValid = (response as? HTTPURLResponse)?.statusCode == 200
            print("🔍 Token validation result: \(isValid ? "VALID" : "INVALID")")
            return isValid
        } catch {
            print("❌ Token validation failed: \(error)")
            return false
        }
    }
    
    /// Refresh access token using refresh token
    private func refreshTokenIfPossible() async -> Bool {
        print("🔄 Attempting to refresh access token...")
        
        guard let refreshToken = secureStorage.getGoogleRefreshToken(),
              let clientID = getClientID() else {
            print("❌ No refresh token or client ID available - signing out user")
            await signOut()
            return false
        }
        
        print("✅ Found refresh token and client ID, making refresh request...")
        
        do {
            let newTokens = try await refreshAccessToken(
                refreshToken: refreshToken,
                clientID: clientID
            )
            
            // Store new tokens
            let success = secureStorage.storeGoogleTokens(
                accessToken: newTokens.accessToken,
                refreshToken: newTokens.refreshToken ?? refreshToken
            )
            
            if success {
                print("✅ Token refresh successful - new tokens stored")
                return true
            } else {
                print("❌ Token refresh successful but failed to store new tokens")
                return false
            }
            
        } catch {
            print("❌ Token refresh failed: \(error.localizedDescription)")
            print("   Signing out user...")
            await signOut()
            return false
        }
    }
    
    /// Refresh access token
    private func refreshAccessToken(refreshToken: String, clientID: String) async throws -> GoogleTokenResponse {
        var requestBody = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        // Add client secret if available (but not required for iOS)
        if let clientSecret = getClientSecret(), !clientSecret.isEmpty {
            requestBody["client_secret"] = clientSecret
        }
        
        guard let url = URL(string: tokenURL) else {
            throw GoogleOAuthError.invalidTokenURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let formData = requestBody
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        let session = networkManager.createURLSession()
        let (data, _) = try await session.data(for: request)
        
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }
    
    // MARK: - User Profile
    
    /// Load user profile information
    private func loadUserProfile() async {
        guard let accessToken = secureStorage.getGoogleAccessToken(),
              let url = URL(string: userInfoURL) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let session = networkManager.createURLSession()
            let (data, _) = try await session.data(for: request)
            userProfile = try JSONDecoder().decode(GoogleUserProfile.self, from: data)
        } catch {
            print("Failed to load user profile: \(error)")
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() async {
        // Revoke tokens if possible
        if let accessToken = secureStorage.getGoogleAccessToken() {
            await revokeToken(accessToken)
        }
        
        // Clear only Google credentials; keep user-scoped OpenAI key
        secureStorage.clearGoogleCredentials()
        
        // Update state
        isAuthenticated = false
        userProfile = nil
        lastError = nil
    }
    
    /// Revoke access token
    private func revokeToken(_ token: String) async {
        guard let url = URL(string: "\(revokeURL)?token=\(token)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let session = networkManager.createURLSession()
            _ = try await session.data(for: request)
        } catch {
            print("Failed to revoke token: \(error)")
        }
    }
    
    // MARK: - AuthenticationService Integration
    
    /// Update AuthenticationService with OAuth user data
    private func updateAuthenticationService(with profile: GoogleUserProfile) async {
        print("🔄 Updating AuthenticationService with OAuth user data...")
        
        let accessToken = secureStorage.getGoogleAccessToken()
        let refreshToken = secureStorage.getGoogleRefreshToken()
        
        let selineUser = SelineUser(
            id: profile.id,
            email: profile.email,
            name: profile.name,
            profileImageURL: profile.picture,
            accessToken: accessToken ?? "",
            refreshToken: refreshToken,
            tokenExpirationDate: nil // Could be calculated from token response
        )
        
        // Update the main AuthenticationService
        let authService = AuthenticationService.shared
        authService.user = selineUser
        authService.isAuthenticated = true
        print("✅ AuthenticationService updated with user: \(profile.email)")
    }
    
    // MARK: - Helper Methods
    
    private func generateState() -> String {
        return UUID().uuidString
    }
    
    private func generateCodeVerifier() -> String {
        let allowed = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let length = 64
        return String((0..<length).compactMap { _ in allowed.randomElement() })
    }
    
    private func codeChallengeS256(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func getClientID() -> String? {
        print("🔍 BUNDLE ID VERIFICATION:")
        print("   App Bundle ID: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        
        // Always read from GoogleService-Info.plist first (iOS client)
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("   ✅ Found GoogleService-Info.plist at: \(path)")
            
            if let plist = NSDictionary(contentsOfFile: path) {
                print("   ✅ Successfully loaded plist dictionary")
                
                // Log all relevant keys for debugging
                let bundleID = plist["BUNDLE_ID"] as? String
                let clientID = plist["CLIENT_ID"] as? String
                let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String
                
                print("   📋 Google Service Info Contents:")
                print("      BUNDLE_ID: \(bundleID ?? "MISSING")")
                print("      CLIENT_ID: \(clientID?.suffix(20) ?? "MISSING")...")
                print("      REVERSED_CLIENT_ID: \(reversedClientID ?? "MISSING")")
                
                // Verify bundle ID matches
                if let bundleID = bundleID, let appBundleID = Bundle.main.bundleIdentifier {
                    if bundleID == appBundleID {
                        print("   ✅ Bundle ID MATCH: App (\(appBundleID)) == Google Console (\(bundleID))")
                    } else {
                        print("   ❌ Bundle ID MISMATCH: App (\(appBundleID)) != Google Console (\(bundleID))")
                        print("      ⚠️  This will cause OAuth 400 errors!")
                        print("      💡 Fix: Update Bundle ID in Google Cloud Console to match app")
                    }
                }
                
                if let clientID = clientID {
                    print("   ✅ Using CLIENT_ID from GoogleService-Info.plist")
                    return clientID
                } else {
                    print("   ❌ CLIENT_ID missing from GoogleService-Info.plist")
                }
            } else {
                print("   ❌ Failed to load GoogleService-Info.plist as dictionary")
            }
        } else {
            print("   ❌ GoogleService-Info.plist not found in bundle")
        }
        
        // Fallback: retrieve from secure storage
        print("   🔄 Attempting fallback: secure storage")
        let fallbackClientID = secureStorage.getGoogleClientID()
        if fallbackClientID != nil {
            print("   ✅ Using CLIENT_ID from secure storage")
        } else {
            print("   ❌ No CLIENT_ID found in secure storage")
        }
        
        return fallbackClientID
    }
    
    private func getClientSecret() -> String? {
        // iOS OAuth flow doesn't require client secret for native apps
        // Google uses bundle ID verification instead
        // Return nil to use public client flow
        return nil
    }
    
    private func getRedirectURI() -> String {
        // Use app's custom URL scheme with standard Google iOS redirect path
        let scheme = getCallbackURLScheme()
        let redirectURI = "\(scheme):/oauth2redirect/google"
        
        print("🔍 REDIRECT URI DEBUG:")
        print("   Callback URL Scheme: \(scheme)")
        print("   Full Redirect URI: \(redirectURI)")
        print("   ✅ iOS native apps use the default '/oauth2redirect/google' path")
        
        // Validate the redirect URI format
        if scheme.contains("com.googleusercontent.apps.") {
            print("   ✅ Using Google-provided REVERSED_CLIENT_ID scheme")
        } else {
            print("   ❌ WARNING: Not using standard Google format - may cause errors")
        }
        
        return redirectURI
    }
    
    private func getCallbackURLScheme() -> String {
        print("🔍 CALLBACK URL SCHEME DEBUG:")
        
        // Always use the reversed client ID from GoogleService-Info.plist (iOS client)
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("   ✅ Found GoogleService-Info.plist")
            
            if let plist = NSDictionary(contentsOfFile: path) {
                print("   ✅ Loaded plist dictionary")
                
                if let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String {
                    print("   ✅ Found REVERSED_CLIENT_ID: \(reversedClientID)")
                    print("   📋 Validation Checklist:")
                    print("      1. ✅ REVERSED_CLIENT_ID exists in plist")
                    print("      2. 🔍 Check if this scheme is in Info.plist > URL Types")
                    print("      3. 🔍 Check if this scheme matches Google Console configuration")
                    return reversedClientID
                } else {
                    print("   ❌ REVERSED_CLIENT_ID missing from GoogleService-Info.plist")
                }
            } else {
                print("   ❌ Failed to load GoogleService-Info.plist")
            }
        } else {
            print("   ❌ GoogleService-Info.plist not found")
        }
        
        // This should not happen if GoogleService-Info.plist is properly configured
        print("   ❌ CRITICAL ERROR: REVERSED_CLIENT_ID not found in GoogleService-Info.plist")
        print("   🔄 Using fallback: \(Bundle.main.bundleIdentifier ?? "com.seline.app")")
        print("   ⚠️  This will likely cause OAuth failures!")
        
        return Bundle.main.bundleIdentifier ?? "com.seline.app" // Fallback to bundle ID
    }
    
    /// Get client ID for testing (expose private method for debug)
    func getCurrentClientID() -> String? {
        return getClientID()
    }
    
    /// Get callback URL scheme for testing (expose private method for debug)
    func getCurrentCallbackURLScheme() -> String {
        return getCallbackURLScheme()
    }
    
    /// Debug method: Run comprehensive OAuth debugging without authentication
    func runOAuthDebug() {
        print("🚀 RUNNING OAUTH DEBUG SESSION:")
        print("═══════════════════════════════════════════════════")
        
        // Run all validation checks
        validateCompleteOAuthConfiguration()
        
        // Show what the OAuth URL would look like
        currentState = generateState()
        codeVerifier = generateCodeVerifier()
        if let authURL = buildAuthorizationURL() {
            print("\n🔗 OAuth URL Preview:")
            print("   This is the URL that would be sent to Google:")
            print("   \(authURL.absoluteString)")
        } else {
            print("\n❌ Failed to build OAuth URL - check configuration above")
        }
        
        print("\n📋 DEBUGGING CHECKLIST:")
        print("   1. ✅ Check all validation results above")
        print("   2. 🔍 Verify Bundle ID matches Google Console exactly")
        print("   3. 🔍 Verify CLIENT_ID is from correct Google project")
        print("   4. 🔍 Verify URL scheme is registered in Info.plist")
        print("   5. 🔍 Verify OAuth client type is 'iOS' in Google Console")
        print("   6. 🔍 Verify app is configured for 'Testing' or 'Published'")
        print("   7. 🔍 Verify required scopes are added to OAuth consent screen")
        
        print("═══════════════════════════════════════════════════")
        print("🎯 If Error 400 persists after fixing above issues:")
        print("   - Check Google Cloud Console audit logs")
        print("   - Verify project has OAuth consent screen configured")
        print("   - Try creating a new OAuth client ID")
        print("   - Ensure app bundle ID exactly matches console configuration")
        print("═══════════════════════════════════════════════════")
    }
    
    /// Get valid access token for API calls
    func getValidAccessToken() async -> String? {
        print("🔍 TOKEN RETRIEVAL DEBUG:")
        print("   GoogleOAuthService.isAuthenticated: \(isAuthenticated)")
        print("   AuthenticationService.isAuthenticated: \(AuthenticationService.shared.isAuthenticated)")
        print("   AuthenticationService.user: \(AuthenticationService.shared.user?.email ?? "nil")")
        
        // Check if user is authenticated via AuthenticationService (main source of truth)
        let authService = AuthenticationService.shared
        guard authService.isAuthenticated, authService.user != nil else {
            print("❌ User not authenticated in AuthenticationService - cannot provide access token")
            return nil
        }
        
        // Try to get token from secure storage
        if let token = secureStorage.getGoogleAccessToken() {
            print("✅ Found access token in secure storage")
            print("   Token (first 20 chars): \(String(token.prefix(20)))...")
            
            // Validate token
            if await isTokenValid(token) {
                print("✅ Access token is valid and ready for API calls")
                return token
            } else {
                print("⚠️ Access token expired, attempting refresh...")
                
                if await refreshTokenIfPossible() {
                    if let refreshedToken = secureStorage.getGoogleAccessToken() {
                        print("✅ Access token refreshed successfully")
                        print("   New token (first 20 chars): \(String(refreshedToken.prefix(20)))...")
                        return refreshedToken
                    }
                }
                
                print("❌ Failed to refresh access token - user needs to re-authenticate")
                return nil
            }
        }
        
        // Try to get token from AuthenticationService user object
        if let userToken = authService.user?.accessToken, !userToken.isEmpty {
            print("⚠️ No token in secure storage, but found token in user object")
            print("   Storing token from user object to secure storage...")
            
            if secureStorage.storeGoogleTokens(accessToken: userToken, refreshToken: authService.user?.refreshToken) {
                print("✅ Token stored successfully from user object")
                return userToken
            } else {
                print("❌ Failed to store token from user object")
            }
        }
        
        print("❌ No access token found anywhere")
        print("   - Secure storage: empty")
        print("   - User object: \(authService.user?.accessToken.isEmpty == false ? "has token" : "empty")")
        return nil
    }
    
    // MARK: - Fallback Authentication Methods
    
    /// Attempt authentication with fallback strategies
    func authenticateWithFallback() async throws {
        var lastError: Error?
        
        // Primary attempt: Standard OAuth flow
        do {
            print("🎯 Attempting primary Google OAuth authentication...")
            try await authenticate()
            print("✅ Primary authentication successful")
            return
        } catch GoogleOAuthError.userCancelled {
            // Don't retry if user explicitly cancelled
            throw GoogleOAuthError.userCancelled
        } catch {
            print("⚠️ Primary authentication failed: \(error.localizedDescription)")
            lastError = error
        }
        
        // Fallback 1: Check if we have valid stored tokens
        print("🔄 Attempting fallback: Using stored tokens...")
        if await attemptStoredTokenAuthentication() {
            print("✅ Fallback authentication with stored tokens successful")
            return
        }
        
        // Fallback 2: Retry with different session configuration
        print("🔄 Attempting fallback: Modified OAuth configuration...")
        if await attemptFallbackOAuthFlow() {
            print("✅ Fallback OAuth authentication successful")
            return
        }
        
        // All methods failed
        print("❌ All authentication methods failed")
        throw lastError ?? GoogleOAuthError.unknownError
    }
    
    /// Attempt authentication using stored tokens
    private func attemptStoredTokenAuthentication() async -> Bool {
        guard let accessToken = secureStorage.getGoogleAccessToken() else {
            print("❌ No stored access token found")
            return false
        }
        
        print("🔍 Validating stored access token...")
        if await isTokenValid(accessToken) {
            print("✅ Stored access token is valid")
            isAuthenticated = true
            await loadUserProfile()
            return true
        } else {
            print("⚠️ Stored access token expired, attempting refresh...")
            _ = await refreshTokenIfPossible()
            
            if isAuthenticated {
                print("✅ Token refresh successful")
                return true
            }
        }
        
        return false
    }
    
    /// Attempt OAuth flow with alternative configuration
    private func attemptFallbackOAuthFlow() async -> Bool {
        do {
            // Try with non-ephemeral browser session
            print("🌐 Attempting OAuth with persistent browser session...")
            let authCode = try await performFallbackOAuthFlow()
            let tokens = try await exchangeCodeForTokens(authCode)
            
            // Store tokens securely
            guard secureStorage.storeGoogleTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            ) else {
                return false
            }
            
            // Load user profile
            await loadUserProfile()
            isAuthenticated = true
            return true
            
        } catch {
            print("❌ Fallback OAuth flow failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Perform OAuth flow with fallback configuration
    private func performFallbackOAuthFlow() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            currentState = generateState()
            codeVerifier = generateCodeVerifier()
            
            guard let authURL = buildAuthorizationURL() else {
                continuation.resume(throwing: GoogleOAuthError.invalidAuthURL)
                return
            }
            
            // Use non-ephemeral session as fallback
            authenticationSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: getCallbackURLScheme()
            ) { [weak self] callbackURL, error in
                
                if let error = error {
                    continuation.resume(throwing: GoogleOAuthError.authenticationFailed(error))
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.invalidCallback)
                    return
                }
                
                do {
                    let authCode = try self?.extractAuthCodeFromCallback(callbackURL) ?? ""
                    continuation.resume(returning: authCode)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            // Configure fallback session (persistent browser)
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = false
            
            guard authenticationSession?.start() == true else {
                continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                return
            }
        }
    }
    
    /// Check authentication status and provide user-friendly guidance
    func getAuthenticationStatus() -> (isAuthenticated: Bool, statusMessage: String, suggestionMessage: String?) {
        if isAuthenticated {
            return (true, "Successfully authenticated with Google", nil)
        }
        
        if secureStorage.hasGoogleCredentials() {
            return (false, "Google credentials configured but not authenticated", "Tap 'Sign in with Google' to authenticate")
        } else {
            return (false, "Google OAuth not configured", "App needs to be configured with Google OAuth credentials")
        }
    }
    
    // MARK: - OAuth Flow Logging
    
    private func logOAuthFlowStart() {
        print("🚀 OAUTH FLOW START:")
        print("   Client ID: \(getClientID()?.suffix(20) ?? "nil")")
        print("   Callback Scheme: \(getCallbackURLScheme())")
        print("   Required Scopes: \(requiredScopes.count)")
        requiredScopes.forEach { scope in
            print("     - \(scope)")
        }
        print("   Timestamp: \(Date())")
    }
    
    private func logOAuthStep(_ step: String, success: Bool, details: String? = nil) {
        let status = success ? "✅" : "❌"
        print("\(status) OAuth Step: \(step)")
        if let details = details {
            print("   Details: \(details)")
        }
        print("   Timestamp: \(Date())")
    }
    
    private func logOAuthFlowComplete(success: Bool, userEmail: String? = nil, error: GoogleOAuthError? = nil) {
        print("🏁 OAUTH FLOW COMPLETE:")
        print("   Success: \(success ? "✅ YES" : "❌ NO")")
        
        if success, let email = userEmail {
            print("   User Email: \(email)")
            print("   Authentication Status: Authenticated")
            print("   Tokens Stored: \(secureStorage.getGoogleAccessToken() != nil)")
        }
        
        if let error = error {
            print("   Error Type: \(error)")
            print("   Error Message: \(error.localizedDescription)")
            print("   Recovery: \(error.recoverySuggestion ?? "None")")
        }
        
        print("   Final Auth State: \(isAuthenticated)")
        print("   Completion Timestamp: \(Date())")
        print("═══════════════════════════════════════════════════")
    }
    
    // MARK: - Enhanced Error Logging
    
    /// Log detailed authentication error information
    private func logAuthenticationError(_ error: GoogleOAuthError) {
        print("❌ Google OAuth Error Details:")
        print("  - Error: \(error.errorDescription ?? "Unknown error")")
        print("  - Recovery: \(error.recoverySuggestion ?? "No recovery suggestion")")
        
        // Log additional context based on error type
        switch error {
        case .userCancelled:
            print("  - Context: User cancelled the authentication flow")
        case .authenticationFailed(let underlyingError):
            print("  - Underlying Error: \(underlyingError.localizedDescription)")
        case .networkError(let networkError):
            print("  - Network Error: \(networkError.localizedDescription)")
        case .tokenExchangeFailed(let statusCode):
            print("  - HTTP Status Code: \(statusCode)")
            logTokenExchangeFailureDetails(statusCode: statusCode)
        case .stateValidationFailed:
            print("  - Security Issue: OAuth state parameter validation failed")
            print("  - This could indicate a CSRF attack or session corruption")
        case .missingClientCredentials:
            print("  - Configuration Issue: Google OAuth client credentials not found")
            print("  - Check GoogleService-Info.plist and secure storage")
        default:
            break
        }
        
        // Log current configuration state
        print("  - Configuration Check:")
        print("    - Has Client ID: \(getClientID() != nil)")
        print("    - Has Client Secret: \(getClientSecret() != nil)")
        print("    - Callback URL Scheme: \(getCallbackURLScheme())")
    }
    
    /// Log specific details for token exchange failures
    private func logTokenExchangeFailureDetails(statusCode: Int) {
        switch statusCode {
        case 400:
            print("  - HTTP 400: Bad Request - Check authorization code or client credentials")
        case 401:
            print("  - HTTP 401: Unauthorized - Invalid client credentials")
        case 403:
            print("  - HTTP 403: Forbidden - Client not authorized for OAuth")
        case 429:
            print("  - HTTP 429: Rate Limited - Too many requests")
        case 500...599:
            print("  - HTTP \(statusCode): Server Error - Google's servers are experiencing issues")
        default:
            print("  - HTTP \(statusCode): Unexpected response code")
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}

// MARK: - Data Models

struct GoogleTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct GoogleTokenErrorResponse: Codable {
    let error: String
    let errorDescription: String?
    let errorURI: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorURI = "error_uri"
    }
}

struct GoogleUserProfile: Codable {
    let id: String
    let email: String
    let name: String
    let picture: String?
    let verifiedEmail: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, email, name, picture
        case verifiedEmail = "verified_email"
    }
}

// MARK: - Error Types

enum GoogleOAuthError: LocalizedError {
    case authenticationInProgress
    case invalidAuthURL
    case userCancelled
    case authenticationFailed(Error)
    case invalidCallback
    case authorizationError(String)
    case stateValidationFailed
    case missingAuthCode
    case missingClientCredentials
    case invalidTokenURL
    case tokenExchangeFailed(Int)
    case tokenStorageError
    case networkError(Error)
    case invalidResponse
    case unknownError
    case sessionStartFailed
    
    // Google Console specific errors
    case accessDenied(String)
    case invalidClient(String)
    case invalidGrant(String)
    case unauthorizedClient(String)
    case unsupportedGrantType(String)
    case invalidScope(String)
    case serverError(String)
    case temporarilyUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationInProgress:
            return "Authentication is already in progress."
        case .invalidAuthURL:
            return "Failed to create authorization URL."
        case .userCancelled:
            return "Authentication was cancelled by user."
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .invalidCallback:
            return "Invalid callback URL received."
        case .authorizationError(let error):
            return "Authorization error: \(error)"
        case .stateValidationFailed:
            return "Security validation failed."
        case .missingAuthCode:
            return "Authorization code not received."
        case .missingClientCredentials:
            return "Google OAuth credentials not configured."
        case .invalidTokenURL:
            return "Invalid token exchange URL."
        case .tokenExchangeFailed(let code):
            return "Token exchange failed with code: \(code)"
        case .tokenStorageError:
            return "Failed to store authentication tokens securely."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Google."
        case .unknownError:
            return "An unknown error occurred."
        case .sessionStartFailed:
            return "Failed to start authentication session."
        case .accessDenied(let details):
            return "Access denied by user or Google: \(details)"
        case .invalidClient(let details):
            return "Invalid client configuration: \(details)"
        case .invalidGrant(let details):
            return "Invalid authorization grant: \(details)"
        case .unauthorizedClient(let details):
            return "Client not authorized for this operation: \(details)"
        case .unsupportedGrantType(let details):
            return "Unsupported grant type: \(details)"
        case .invalidScope(let details):
            return "Invalid or unauthorized scope requested: \(details)"
        case .serverError(let details):
            return "Google server error: \(details)"
        case .temporarilyUnavailable(let details):
            return "Google service temporarily unavailable: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .userCancelled:
            return "Please try signing in again."
        case .networkError:
            return "Check your internet connection and try again."
        case .missingClientCredentials:
            return "Please contact support to configure Google OAuth."
        case .tokenStorageError:
            return "Check device security settings and try again."
        case .accessDenied:
            return "Please grant the required permissions and try again."
        case .invalidClient:
            return "App configuration issue. Please contact support."
        case .invalidGrant:
            return "Please try signing in again."
        case .unauthorizedClient:
            return "App not properly configured in Google Console. Contact support."
        case .unsupportedGrantType:
            return "OAuth configuration error. Contact support."
        case .invalidScope:
            return "Required permissions not properly configured. Contact support."
        case .serverError, .temporarilyUnavailable:
            return "Google services temporarily unavailable. Please try again later."
        default:
            return "Please try again. If the problem persists, contact support."
        }
    }
}
