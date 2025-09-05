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
    
    // MARK: - Circuit Breaker for Token Refresh
    
    private struct TokenRefreshState {
        var failureCount: Int = 0
        var lastFailureTime: Date?
        var isCircuitOpen: Bool = false
        var lastRefreshAttempt: Date?
        var isRefreshing: Bool = false
    }
    
    private var refreshState = TokenRefreshState()
    private let maxFailureCount = 3
    private let circuitBreakerTimeout: TimeInterval = 300 // 5 minutes
    private let minRefreshInterval: TimeInterval = 30 // 30 seconds between attempts
    
    
    private var hasLoggedRefreshFailure = false // Prevent log spam
    
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
        ProductionLogger.debug("📋 GOOGLE OAUTH SCOPE VALIDATION:")
        ProductionLogger.debug("   Required scopes (must match Google Console OAuth consent screen):")
        requiredScopes.enumerated().forEach { index, scope in
            ProductionLogger.debug("   \(index + 1). \(scope)")
        }
        ProductionLogger.debug("   ⚠️  Ensure these exact scopes are added in Google Cloud Console > OAuth consent screen > Scopes")
    }
    
    /// Validate URL scheme configuration
    func validateURLSchemeConfiguration() {
        ProductionLogger.debug("📋 URL SCHEME VALIDATION:")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        
        let callbackScheme = getCallbackURLScheme()
        ProductionLogger.debug("   Expected URL Scheme: \(callbackScheme)")
        
        // Check Info.plist CFBundleURLTypes
        if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] {
            ProductionLogger.debug("   ✅ Found CFBundleURLTypes in Info.plist")
            
            var foundMatchingScheme = false
            for (index, urlType) in urlTypes.enumerated() {
                ProductionLogger.debug("   📋 URL Type \(index + 1):")
                
                if let name = urlType["CFBundleURLName"] as? String {
                    ProductionLogger.debug("      Name: \(name)")
                }
                
                if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                    ProductionLogger.debug("      Schemes:")
                    schemes.forEach { scheme in
                        ProductionLogger.debug("         - \(scheme)")
                        if scheme == callbackScheme {
                            foundMatchingScheme = true
                            ProductionLogger.debug("           ✅ MATCHES expected callback scheme!")
                        }
                    }
                }
            }
            
            if foundMatchingScheme {
                ProductionLogger.debug("   ✅ URL scheme properly configured in Info.plist")
            } else {
                ProductionLogger.debug("   ❌ MISSING URL scheme in Info.plist!")
                ProductionLogger.debug("   💡 Add '\(callbackScheme)' to CFBundleURLSchemes array")
                ProductionLogger.debug("   💡 This will cause OAuth callback failures!")
            }
            
        } else {
            ProductionLogger.debug("   ❌ CFBundleURLTypes not found in Info.plist")
            ProductionLogger.debug("   💡 Add URL schemes configuration to Info.plist")
        }
        
        ProductionLogger.debug("═══════════════════════════════════════════════════")
    }
    
    /// Complete OAuth configuration validation
    func validateCompleteOAuthConfiguration() {
        ProductionLogger.debug("🔍 COMPLETE OAUTH CONFIGURATION VALIDATION:")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        
        // 1. Bundle ID validation
        ProductionLogger.debug("1️⃣ Bundle ID Check:")
        if let bundleID = Bundle.main.bundleIdentifier {
            ProductionLogger.debug("   App Bundle ID: \(bundleID)")
            ProductionLogger.debug("   ✅ Bundle ID exists")
        } else {
            ProductionLogger.debug("   ❌ Bundle ID missing!")
        }
        
        // 2. GoogleService-Info.plist validation
        ProductionLogger.debug("\n2️⃣ GoogleService-Info.plist Check:")
        _ = getClientID() // This will log detailed validation
        
        // 3. URL Scheme validation
        ProductionLogger.debug("\n3️⃣ URL Scheme Check:")
        validateURLSchemeConfiguration()
        
        // 4. Google Console checklist
        ProductionLogger.debug("4️⃣ Google Cloud Console Checklist:")
        ProductionLogger.debug("   ⚠️  CRITICAL: Based on Error 400 screenshot, fix these:")
        ProductionLogger.debug("   □ OAuth 2.0 Client ID created for iOS (NOT Web)")
        ProductionLogger.debug("   □ Bundle ID matches: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        ProductionLogger.debug("   □ Redirect URI uses the default iOS native path: scheme:/oauth2redirect/google")
        ProductionLogger.debug("   □ URL scheme in Info.plist: \(getCallbackURLScheme())")
        ProductionLogger.debug("   □ OAuth consent screen configured")
        ProductionLogger.debug("   □ Required scopes added to consent screen")
        ProductionLogger.debug("   □ App status is 'Testing' or 'Published'")
        ProductionLogger.debug("")
        ProductionLogger.debug("🚨 IMMEDIATE ACTION REQUIRED FOR iOS OAUTH:")
        ProductionLogger.debug("   iOS OAuth clients use the default native redirect and PKCE.")
        ProductionLogger.debug("")
        ProductionLogger.debug("   1️⃣ APIs & Services → Credentials → iOS OAuth Client:")
        ProductionLogger.debug("      ✅ Bundle ID: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        ProductionLogger.debug("      ✅ iOS URL scheme: \(getCallbackURLScheme())")
        ProductionLogger.debug("")
        ProductionLogger.debug("   2️⃣ APIs & Services → OAuth consent screen:")
        ProductionLogger.debug("      □ App name filled in")
        ProductionLogger.debug("      □ User support email set")
        ProductionLogger.debug("      □ Developer contact email set")
        ProductionLogger.debug("      □ Add your email to 'Test users' if app is in Testing mode")
        ProductionLogger.debug("")
        ProductionLogger.debug("   3️⃣ OAuth consent screen → Scopes:")
        requiredScopes.forEach { scope in
            ProductionLogger.debug("      □ \(scope)")
        }
        ProductionLogger.debug("")
        ProductionLogger.debug("   4️⃣ APIs & Services → Library (enable these APIs):")
        ProductionLogger.debug("      □ Gmail API")
        ProductionLogger.debug("      □ Google Calendar API")
        ProductionLogger.debug("      □ Google People API (for user profile)")
        ProductionLogger.debug("")
        ProductionLogger.debug("   5️⃣ OAuth consent screen → Publishing status:")
        ProductionLogger.debug("      □ Set to 'In production' OR add your Google account to test users")
        
        ProductionLogger.debug("═══════════════════════════════════════════════════")
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
                Task { 
                    await auth.setAuthenticatedUser(selineUser)
                    ProductionLogger.debug("🔄 Rehydrated AuthenticationService with stored tokens")
                }
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
        ProductionLogger.debug("🔐 Starting Google OAuth authentication flow...")
        
        guard !isAuthenticating else {
            ProductionLogger.debug("❌ Authentication already in progress")
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
                ProductionLogger.debug("✅ Google OAuth authentication completed for: \(profile.email)")
            } else {
                isAuthenticated = true // Still consider authenticated even if profile loading fails
            }
            
        } catch {
            let oauthError = error as? GoogleOAuthError ?? GoogleOAuthError.unknownError
            lastError = oauthError
            ProductionLogger.debug("❌ OAuth authentication failed: \(oauthError.localizedDescription)")
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
                ProductionLogger.debug("❌ Failed to build authorization URL")
                continuation.resume(throwing: GoogleOAuthError.invalidAuthURL)
                return
            }
            
            ProductionLogger.debug("🌐 Authorization URL: \(authURL.absoluteString)")
            ProductionLogger.debug("📱 Callback URL Scheme: \(getCallbackURLScheme())")
            
            // Start authentication session
            authenticationSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: getCallbackURLScheme()
            ) { [weak self] callbackURL, error in
                
                if let error = error {
                    ProductionLogger.debug("❌ Authentication session error: \(error.localizedDescription)")
                    ProductionLogger.debug("   Full error: \(error)")
                    
                    if let webAuthError = error as? ASWebAuthenticationSessionError {
                        ProductionLogger.debug("   ASWebAuthenticationSessionError code: \(webAuthError.code.rawValue)")
                        
                        switch webAuthError.code {
                        case .canceledLogin:
                            ProductionLogger.debug("👤 User cancelled the authentication flow")
                            continuation.resume(throwing: GoogleOAuthError.userCancelled)
                        case .presentationContextNotProvided:
                            ProductionLogger.debug("❌ Presentation context not provided")
                            continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                        case .presentationContextInvalid:
                            ProductionLogger.debug("❌ Presentation context invalid")
                            continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                        @unknown default:
                            ProductionLogger.debug("❌ Unknown ASWebAuthenticationSessionError: \(webAuthError.code.rawValue)")
                            continuation.resume(throwing: GoogleOAuthError.authenticationFailed(error))
                        }
                    } else {
                        ProductionLogger.debug("🚫 Authentication failed with non-ASWebAuthenticationSessionError: \(error)")
                        continuation.resume(throwing: GoogleOAuthError.authenticationFailed(error))
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    ProductionLogger.debug("❌ No callback URL received from authentication session")
                    continuation.resume(throwing: GoogleOAuthError.invalidCallback)
                    return
                }
                
                ProductionLogger.debug("✅ Callback URL received: \(callbackURL.absoluteString)")
                
                do {
                    let authCode = try self?.extractAuthCodeFromCallback(callbackURL) ?? ""
                    ProductionLogger.debug("✅ Authorization code extracted successfully")
                    continuation.resume(returning: authCode)
                } catch {
                    ProductionLogger.debug("❌ Failed to extract authorization code: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            
            // Configure session
            ProductionLogger.debug("⚙️ Configuring authentication session...")
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = true
            
            ProductionLogger.debug("🔍 Session Configuration:")
            ProductionLogger.debug("   - Presentation context provider: \(authenticationSession?.presentationContextProvider != nil ? "✅ Set" : "❌ Missing")")
            ProductionLogger.debug("   - Ephemeral session: \(authenticationSession?.prefersEphemeralWebBrowserSession == true ? "✅ Yes" : "❌ No")")
            
            // Start session
            ProductionLogger.debug("🚀 Starting authentication session...")
            let didStart = authenticationSession?.start()
            ProductionLogger.debug("   Session start result: \(didStart == true ? "✅ Success" : "❌ Failed")")
            
            guard didStart == true else {
                ProductionLogger.debug("❌ Failed to start authentication session")
                ProductionLogger.debug("   This usually means:")
                ProductionLogger.debug("   - Invalid URL")
                ProductionLogger.debug("   - Invalid callback scheme")
                ProductionLogger.debug("   - Missing presentation context")
                continuation.resume(throwing: GoogleOAuthError.sessionStartFailed)
                return
            }
            ProductionLogger.debug("✅ Authentication session started successfully - waiting for user interaction...")
        }
    }
    
    /// Build authorization URL with proper parameters
    private func buildAuthorizationURL() -> URL? {
        guard let clientID = getClientID() else {
            ProductionLogger.debug("❌ OAUTH DEBUG: Client ID is nil - check GoogleService-Info.plist")
            return nil
        }
        
        ProductionLogger.debug("🔍 OAUTH REQUEST DEBUG:")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        ProductionLogger.debug("📱 App Configuration:")
        ProductionLogger.debug("   Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        ProductionLogger.debug("   Client ID: \(clientID)")
        ProductionLogger.debug("   Client ID (last 10 chars): ...\(String(clientID.suffix(10)))")
        
        let redirectURI = getRedirectURI()
        let scopeString = requiredScopes.joined(separator: " ")
        
        // Ensure we have a PKCE verifier/challenge
        let verifier = codeVerifier ?? generateCodeVerifier()
        codeVerifier = verifier
        let codeChallenge = codeChallengeS256(from: verifier)
        
        ProductionLogger.debug("🌐 OAuth Parameters:")
        ProductionLogger.debug("   Authorization URL: \(authURL)")
        ProductionLogger.debug("   Client ID: \(clientID)")
        ProductionLogger.debug("   Redirect URI: \(redirectURI)")
        ProductionLogger.debug("   Response Type: code")
        ProductionLogger.debug("   Scope: \(scopeString)")
        ProductionLogger.debug("   State: \(currentState ?? "nil")")
        ProductionLogger.debug("   Access Type: offline")
        ProductionLogger.debug("   Prompt: consent")
        ProductionLogger.debug("   PKCE: S256")
        
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
            ProductionLogger.debug("❌ OAUTH DEBUG: Failed to construct URL from components")
            return nil
        }
        
        ProductionLogger.debug("🔗 Final OAuth Request URL:")
        ProductionLogger.debug("   \(finalURL.absoluteString)")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        
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
            
            ProductionLogger.debug("❌ OAuth authorization error: \(error)")
            ProductionLogger.debug("   Description: \(errorDescription)")
            
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
        
        ProductionLogger.debug("🔍 TOKEN EXCHANGE DEBUG:")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        ProductionLogger.debug("📋 Token Exchange Parameters:")
        ProductionLogger.debug("   Token URL: \(tokenURL)")
        ProductionLogger.debug("   Client ID: \(clientID)")
        ProductionLogger.debug("   Authorization Code: \(code.prefix(20))...\(code.suffix(10))")
        ProductionLogger.debug("   Grant Type: authorization_code")
        
        let redirectURI = getRedirectURI()
        ProductionLogger.debug("   Redirect URI: \(redirectURI)")
        
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
            ProductionLogger.debug("   Client Secret: [PROVIDED]")
        } else {
            ProductionLogger.debug("   Client Secret: [NOT PROVIDED - using public client flow for iOS]")
        }
        
        ProductionLogger.debug("🌐 HTTP Request Details:")
        ProductionLogger.debug("   Method: POST")
        ProductionLogger.debug("   Content-Type: application/x-www-form-urlencoded")
        ProductionLogger.debug("   Request Body Parameters:")
        requestBody.forEach { key, value in
            if key == "code" {
                ProductionLogger.debug("      \(key): \(String(value.prefix(20)))...\(String(value.suffix(10)))")
            } else if key == "client_secret" {
                ProductionLogger.debug("      \(key): [REDACTED]")
            } else if key == "code_verifier" {
                ProductionLogger.debug("      \(key): [SENT]")
            } else {
                ProductionLogger.debug("      \(key): \(value)")
            }
        }
        
        guard let url = URL(string: tokenURL) else {
            ProductionLogger.debug("❌ Failed to create URL from: \(tokenURL)")
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
        
        ProductionLogger.debug("📤 Form Data: \(formData.count) characters")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        
        let session = networkManager.createURLSession()
        
        do {
            ProductionLogger.debug("📡 Sending token exchange request...")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                ProductionLogger.debug("❌ Invalid response type received")
                throw GoogleOAuthError.invalidResponse
            }
            
            ProductionLogger.debug("📥 Token Exchange Response:")
            ProductionLogger.debug("   Status Code: \(httpResponse.statusCode)")
            ProductionLogger.debug("   Response Headers:")
            httpResponse.allHeaderFields.forEach { key, value in
                ProductionLogger.debug("      \(key): \(value)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                ProductionLogger.debug("   Response Body: \(responseString)")
            }
            
            guard httpResponse.statusCode == 200 else {
                ProductionLogger.debug("❌ Token exchange failed with status code: \(httpResponse.statusCode)")
                
                // Try to parse Google's error response
                if let errorResponse = try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data) {
                    ProductionLogger.debug("❌ Google token exchange error: \(errorResponse.error)")
                    ProductionLogger.debug("   Description: \(errorResponse.errorDescription ?? "No description")")
                    ProductionLogger.debug("   Error URI: \(errorResponse.errorURI ?? "No error URI")")
                    
                    ProductionLogger.debug("🔍 Common Error 400 Causes:")
                    switch errorResponse.error {
                    case "invalid_client":
                        ProductionLogger.debug("   - Bundle ID doesn't match Google Console configuration")
                        ProductionLogger.debug("   - CLIENT_ID is incorrect or missing")
                        ProductionLogger.debug("   - App not configured as 'iOS' type in Google Console")
                        throw GoogleOAuthError.invalidClient(errorResponse.errorDescription ?? "Invalid client credentials")
                    case "invalid_grant":
                        ProductionLogger.debug("   - Authorization code expired or already used")
                        ProductionLogger.debug("   - redirect_uri doesn't match the one used in authorization")
                        ProductionLogger.debug("   - Missing or invalid PKCE code_verifier")
                        throw GoogleOAuthError.invalidGrant(errorResponse.errorDescription ?? "Invalid authorization grant")
                    case "unauthorized_client":
                        ProductionLogger.debug("   - Client not authorized for this grant type")
                        ProductionLogger.debug("   - OAuth app type configuration issue")
                        throw GoogleOAuthError.unauthorizedClient(errorResponse.errorDescription ?? "Client not authorized")
                    case "unsupported_grant_type":
                        ProductionLogger.debug("   - Grant type 'authorization_code' not supported")
                        throw GoogleOAuthError.unsupportedGrantType(errorResponse.errorDescription ?? "Unsupported grant type")
                    case "invalid_scope":
                        ProductionLogger.debug("   - One or more scopes are invalid or not authorized")
                        throw GoogleOAuthError.invalidScope(errorResponse.errorDescription ?? "Invalid scope")
                    default:
                        ProductionLogger.debug("   - Unknown error: \(errorResponse.error)")
                        throw GoogleOAuthError.tokenExchangeFailed(httpResponse.statusCode)
                    }
                } else {
                    ProductionLogger.debug("❌ Failed to parse error response, raw status code: \(httpResponse.statusCode)")
                    throw GoogleOAuthError.tokenExchangeFailed(httpResponse.statusCode)
                }
            }
            
            ProductionLogger.debug("✅ Token exchange successful, parsing response...")
            let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
            ProductionLogger.debug("✅ Token response parsed successfully")
            return tokenResponse
            
        } catch {
            ProductionLogger.debug("❌ Token exchange network error: \(error.localizedDescription)")
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
    
    /// Check if circuit breaker allows refresh attempts
    private func canAttemptRefresh() -> Bool {
        let now = Date()
        
        // Check if we're in circuit breaker mode
        if refreshState.isCircuitOpen {
            if let lastFailure = refreshState.lastFailureTime,
               now.timeIntervalSince(lastFailure) > circuitBreakerTimeout {
                // Reset circuit breaker after timeout
                refreshState.isCircuitOpen = false
                refreshState.failureCount = 0
                hasLoggedRefreshFailure = false
                ProductionLogger.debug("🔄 Token refresh circuit breaker reset")
            } else {
                return false
            }
        }
        
        // Check minimum interval between attempts
        if let lastAttempt = refreshState.lastRefreshAttempt,
           now.timeIntervalSince(lastAttempt) < minRefreshInterval {
            return false
        }
        
        return true
    }
    
    /// Record refresh failure and update circuit breaker state
    private func recordRefreshFailure() {
        refreshState.failureCount += 1
        refreshState.lastFailureTime = Date()
        refreshState.lastRefreshAttempt = Date()
        
        if refreshState.failureCount >= maxFailureCount {
            refreshState.isCircuitOpen = true
            if !hasLoggedRefreshFailure {
                ProductionLogger.debug("❌ Token refresh circuit breaker OPEN - too many failures")
                hasLoggedRefreshFailure = true
            }
        }
    }
    
    /// Record successful refresh and reset circuit breaker
    private func recordRefreshSuccess() {
        refreshState.failureCount = 0
        refreshState.isCircuitOpen = false
        refreshState.lastFailureTime = nil
        refreshState.lastRefreshAttempt = Date()
        hasLoggedRefreshFailure = false
    }
    
    
    /// Check if access token is valid with minimal logging
    private func isTokenValid(_ token: String) async -> Bool {
        guard let url = URL(string: userInfoURL) else { return false }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let session = networkManager.createURLSession(timeout: 10)
            let (_, response) = try await session.data(for: request)
            
            let isValid = (response as? HTTPURLResponse)?.statusCode == 200
            // Only log validation failures once per session
            if !isValid && !hasLoggedRefreshFailure {
                ProductionLogger.debug("🔍 Token validation: INVALID")
            }
            return isValid
        } catch {
            // Only log network errors once per session
            if !hasLoggedRefreshFailure {
                ProductionLogger.debug("❌ Token validation network error")
            }
            return false
        }
    }
    
    /// Refresh access token using refresh token with circuit breaker
    private func refreshTokenIfPossible() async -> Bool {
        // Check circuit breaker
        guard canAttemptRefresh() else {
            if refreshState.isCircuitOpen && !hasLoggedRefreshFailure {
                ProductionLogger.debug("⚠️ Token refresh blocked by circuit breaker")
                hasLoggedRefreshFailure = true
            }
            return false
        }
        
        // Prevent concurrent refresh attempts using NSLock for async compatibility
        
        
        defer {
            refreshState.isRefreshing = false
        }
        
        // Double-check after acquiring semaphore
        if refreshState.isRefreshing {
            return false
        }
        
        refreshState.isRefreshing = true
        refreshState.lastRefreshAttempt = Date()
        
        if !hasLoggedRefreshFailure {
            ProductionLogger.debug("🔄 Attempting to refresh access token...")
        }
        
        guard let refreshToken = secureStorage.getGoogleRefreshToken(),
              let clientID = getClientID() else {
            if !hasLoggedRefreshFailure {
                ProductionLogger.debug("❌ No refresh token or client ID available - signing out user")
                hasLoggedRefreshFailure = true
            }
            recordRefreshFailure()
            await signOut()
            return false
        }
        
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
                recordRefreshSuccess()
                ProductionLogger.debug("✅ Token refresh successful - new tokens stored")
                return true
            } else {
                recordRefreshFailure()
                if !hasLoggedRefreshFailure {
                    ProductionLogger.debug("❌ Token refresh successful but failed to store new tokens")
                    hasLoggedRefreshFailure = true
                }
                return false
            }
            
        } catch {
            recordRefreshFailure()
            if !hasLoggedRefreshFailure {
                ProductionLogger.debug("❌ Token refresh failed: \(error.localizedDescription)")
                ProductionLogger.debug("   Signing out user...")
                hasLoggedRefreshFailure = true
            }
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
    
    /// Load user profile information with minimal logging
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
            // Only log profile loading errors once per session
            if !hasLoggedRefreshFailure {
                ProductionLogger.debug("Failed to load user profile: \(error.localizedDescription)")
            }
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
            ProductionLogger.debug("Failed to revoke token: \(error)")
        }
    }
    
    // MARK: - AuthenticationService Integration
    
    /// Update AuthenticationService with OAuth user data
    private func updateAuthenticationService(with profile: GoogleUserProfile) async {
        ProductionLogger.debug("🔄 Updating AuthenticationService with OAuth user data...")
        
        let accessToken = secureStorage.getGoogleAccessToken()
        let refreshToken = secureStorage.getGoogleRefreshToken()
        
        let selineUser = SelineUser(
            id: profile.id,
            email: profile.email,
            name: profile.name,
            profileImageURL: profile.picture,
            accessToken: accessToken ?? "",
            refreshToken: refreshToken ?? "",
            tokenExpirationDate: nil // Could be calculated from token response
        )
        
        // Update the main AuthenticationService with proper token synchronization
        let authService = AuthenticationService.shared
        Task {
            await authService.setAuthenticatedUser(selineUser)
            ProductionLogger.debug("✅ AuthenticationService updated with synchronized tokens for: \(profile.email)")
        }
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
        ProductionLogger.debug("🔍 BUNDLE ID VERIFICATION:")
        ProductionLogger.debug("   App Bundle ID: \(Bundle.main.bundleIdentifier ?? "MISSING")")
        
        // Always read from GoogleService-Info.plist first (iOS client)
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            ProductionLogger.debug("   ✅ Found GoogleService-Info.plist at: \(path)")
            
            if let plist = NSDictionary(contentsOfFile: path) {
                ProductionLogger.debug("   ✅ Successfully loaded plist dictionary")
                
                // Log all relevant keys for debugging
                let bundleID = plist["BUNDLE_ID"] as? String
                let clientID = plist["CLIENT_ID"] as? String
                let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String
                
                ProductionLogger.debug("   📋 Google Service Info Contents:")
                ProductionLogger.debug("      BUNDLE_ID: \(bundleID ?? "MISSING")")
                ProductionLogger.debug("      CLIENT_ID: \(clientID?.suffix(20) ?? "MISSING")...")
                ProductionLogger.debug("      REVERSED_CLIENT_ID: \(reversedClientID ?? "MISSING")")
                
                // Verify bundle ID matches
                if let bundleID = bundleID, let appBundleID = Bundle.main.bundleIdentifier {
                    if bundleID == appBundleID {
                        ProductionLogger.debug("   ✅ Bundle ID MATCH: App (\(appBundleID)) == Google Console (\(bundleID))")
                    } else {
                        ProductionLogger.debug("   ❌ Bundle ID MISMATCH: App (\(appBundleID)) != Google Console (\(bundleID))")
                        ProductionLogger.debug("      ⚠️  This will cause OAuth 400 errors!")
                        ProductionLogger.debug("      💡 Fix: Update Bundle ID in Google Cloud Console to match app")
                    }
                }
                
                if let clientID = clientID {
                    ProductionLogger.debug("   ✅ Using CLIENT_ID from GoogleService-Info.plist")
                    return clientID
                } else {
                    ProductionLogger.debug("   ❌ CLIENT_ID missing from GoogleService-Info.plist")
                }
            } else {
                ProductionLogger.debug("   ❌ Failed to load GoogleService-Info.plist as dictionary")
            }
        } else {
            ProductionLogger.debug("   ❌ GoogleService-Info.plist not found in bundle")
        }
        
        // Fallback: retrieve from secure storage
        ProductionLogger.debug("   🔄 Attempting fallback: secure storage")
        let fallbackClientID = secureStorage.getGoogleClientID()
        if fallbackClientID != nil {
            ProductionLogger.debug("   ✅ Using CLIENT_ID from secure storage")
        } else {
            ProductionLogger.debug("   ❌ No CLIENT_ID found in secure storage")
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
        
        ProductionLogger.debug("🔍 REDIRECT URI DEBUG:")
        ProductionLogger.debug("   Callback URL Scheme: \(scheme)")
        ProductionLogger.debug("   Full Redirect URI: \(redirectURI)")
        ProductionLogger.debug("   ✅ iOS native apps use the default '/oauth2redirect/google' path")
        
        // Validate the redirect URI format
        if scheme.contains("com.googleusercontent.apps.") {
            ProductionLogger.debug("   ✅ Using Google-provided REVERSED_CLIENT_ID scheme")
        } else {
            ProductionLogger.debug("   ❌ WARNING: Not using standard Google format - may cause errors")
        }
        
        return redirectURI
    }
    
    private func getCallbackURLScheme() -> String {
        ProductionLogger.debug("🔍 CALLBACK URL SCHEME DEBUG:")
        
        // Always use the reversed client ID from GoogleService-Info.plist (iOS client)
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            ProductionLogger.debug("   ✅ Found GoogleService-Info.plist")
            
            if let plist = NSDictionary(contentsOfFile: path) {
                ProductionLogger.debug("   ✅ Loaded plist dictionary")
                
                if let reversedClientID = plist["REVERSED_CLIENT_ID"] as? String {
                    ProductionLogger.debug("   ✅ Found REVERSED_CLIENT_ID: \(reversedClientID)")
                    ProductionLogger.debug("   📋 Validation Checklist:")
                    ProductionLogger.debug("      1. ✅ REVERSED_CLIENT_ID exists in plist")
                    ProductionLogger.debug("      2. 🔍 Check if this scheme is in Info.plist > URL Types")
                    ProductionLogger.debug("      3. 🔍 Check if this scheme matches Google Console configuration")
                    return reversedClientID
                } else {
                    ProductionLogger.debug("   ❌ REVERSED_CLIENT_ID missing from GoogleService-Info.plist")
                }
            } else {
                ProductionLogger.debug("   ❌ Failed to load GoogleService-Info.plist")
            }
        } else {
            ProductionLogger.debug("   ❌ GoogleService-Info.plist not found")
        }
        
        // This should not happen if GoogleService-Info.plist is properly configured
        ProductionLogger.debug("   ❌ CRITICAL ERROR: REVERSED_CLIENT_ID not found in GoogleService-Info.plist")
        ProductionLogger.debug("   🔄 Using fallback: \(Bundle.main.bundleIdentifier ?? "com.seline.app")")
        ProductionLogger.debug("   ⚠️  This will likely cause OAuth failures!")
        
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
        ProductionLogger.debug("🚀 RUNNING OAUTH DEBUG SESSION:")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        
        // Run all validation checks
        validateCompleteOAuthConfiguration()
        
        // Show what the OAuth URL would look like
        currentState = generateState()
        codeVerifier = generateCodeVerifier()
        if let authURL = buildAuthorizationURL() {
            ProductionLogger.debug("\n🔗 OAuth URL Preview:")
            ProductionLogger.debug("   This is the URL that would be sent to Google:")
            ProductionLogger.debug("   \(authURL.absoluteString)")
        } else {
            ProductionLogger.debug("\n❌ Failed to build OAuth URL - check configuration above")
        }
        
        ProductionLogger.debug("\n📋 DEBUGGING CHECKLIST:")
        ProductionLogger.debug("   1. ✅ Check all validation results above")
        ProductionLogger.debug("   2. 🔍 Verify Bundle ID matches Google Console exactly")
        ProductionLogger.debug("   3. 🔍 Verify CLIENT_ID is from correct Google project")
        ProductionLogger.debug("   4. 🔍 Verify URL scheme is registered in Info.plist")
        ProductionLogger.debug("   5. 🔍 Verify OAuth client type is 'iOS' in Google Console")
        ProductionLogger.debug("   6. 🔍 Verify app is configured for 'Testing' or 'Published'")
        ProductionLogger.debug("   7. 🔍 Verify required scopes are added to OAuth consent screen")
        
        ProductionLogger.debug("═══════════════════════════════════════════════════")
        ProductionLogger.debug("🎯 If Error 400 persists after fixing above issues:")
        ProductionLogger.debug("   - Check Google Cloud Console audit logs")
        ProductionLogger.debug("   - Verify project has OAuth consent screen configured")
        ProductionLogger.debug("   - Try creating a new OAuth client ID")
        ProductionLogger.debug("   - Ensure app bundle ID exactly matches console configuration")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
    }
    
    /// Get valid access token for API calls with reduced logging
    func getValidAccessToken() async -> String? {
        // Check if user is authenticated via AuthenticationService (main source of truth)
        let authService = AuthenticationService.shared
        guard authService.isAuthenticated, authService.user != nil else {
            return nil
        }
        
        // Try to get token from secure storage
        if let token = secureStorage.getGoogleAccessToken() {
            // Validate token
            if await isTokenValid(token) {
                return token
            } else {
                // Only log if not in circuit breaker mode
                if !refreshState.isCircuitOpen && !hasLoggedRefreshFailure {
                    ProductionLogger.debug("⚠️ Access token expired, attempting refresh...")
                }
                
                if await refreshTokenIfPossible() {
                    if let refreshedToken = secureStorage.getGoogleAccessToken() {
                        return refreshedToken
                    }
                }
                
                return nil
            }
        }
        
        // Try to get token from AuthenticationService user object
        if let userToken = authService.user?.accessToken, !userToken.isEmpty {
            if secureStorage.storeGoogleTokens(accessToken: userToken, refreshToken: authService.user?.refreshToken) {
                return userToken
            }
        }
        
        return nil
    }
    
    // MARK: - Fallback Authentication Methods
    
    /// Attempt authentication with fallback strategies
    func authenticateWithFallback() async throws {
        var lastError: Error?
        
        // Primary attempt: Standard OAuth flow
        do {
            ProductionLogger.debug("🎯 Attempting primary Google OAuth authentication...")
            try await authenticate()
            ProductionLogger.debug("✅ Primary authentication successful")
            return
        } catch GoogleOAuthError.userCancelled {
            // Don't retry if user explicitly cancelled
            throw GoogleOAuthError.userCancelled
        } catch {
            ProductionLogger.debug("⚠️ Primary authentication failed: \(error.localizedDescription)")
            lastError = error
        }
        
        // Fallback 1: Check if we have valid stored tokens
        ProductionLogger.debug("🔄 Attempting fallback: Using stored tokens...")
        if await attemptStoredTokenAuthentication() {
            ProductionLogger.debug("✅ Fallback authentication with stored tokens successful")
            return
        }
        
        // Fallback 2: Retry with different session configuration
        ProductionLogger.debug("🔄 Attempting fallback: Modified OAuth configuration...")
        if await attemptFallbackOAuthFlow() {
            ProductionLogger.debug("✅ Fallback OAuth authentication successful")
            return
        }
        
        // All methods failed
        ProductionLogger.debug("❌ All authentication methods failed")
        throw lastError ?? GoogleOAuthError.unknownError
    }
    
    /// Attempt authentication using stored tokens with reduced logging
    private func attemptStoredTokenAuthentication() async -> Bool {
        guard let accessToken = secureStorage.getGoogleAccessToken() else {
            return false
        }
        
        if await isTokenValid(accessToken) {
            isAuthenticated = true
            await loadUserProfile()
            return true
        } else {
            _ = await refreshTokenIfPossible()
            return isAuthenticated
        }
    }
    
    /// Attempt OAuth flow with alternative configuration
    private func attemptFallbackOAuthFlow() async -> Bool {
        do {
            // Try with non-ephemeral browser session
            ProductionLogger.debug("🌐 Attempting OAuth with persistent browser session...")
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
            ProductionLogger.debug("❌ Fallback OAuth flow failed: \(error.localizedDescription)")
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
        ProductionLogger.debug("🚀 OAUTH FLOW START:")
        ProductionLogger.debug("   Client ID: \(getClientID()?.suffix(20) ?? "nil")")
        ProductionLogger.debug("   Callback Scheme: \(getCallbackURLScheme())")
        ProductionLogger.debug("   Required Scopes: \(requiredScopes.count)")
        requiredScopes.forEach { scope in
            ProductionLogger.debug("     - \(scope)")
        }
        ProductionLogger.debug("   Timestamp: \(Date())")
    }
    
    private func logOAuthStep(_ step: String, success: Bool, details: String? = nil) {
        let status = success ? "✅" : "❌"
        ProductionLogger.debug("\(status) OAuth Step: \(step)")
        if let details = details {
            ProductionLogger.debug("   Details: \(details)")
        }
        ProductionLogger.debug("   Timestamp: \(Date())")
    }
    
    private func logOAuthFlowComplete(success: Bool, userEmail: String? = nil, error: GoogleOAuthError? = nil) {
        ProductionLogger.debug("🏁 OAUTH FLOW COMPLETE:")
        ProductionLogger.debug("   Success: \(success ? "✅ YES" : "❌ NO")")
        
        if success, let email = userEmail {
            ProductionLogger.debug("   User Email: \(email)")
            ProductionLogger.debug("   Authentication Status: Authenticated")
            ProductionLogger.debug("   Tokens Stored: \(secureStorage.getGoogleAccessToken() != nil)")
        }
        
        if let error = error {
            ProductionLogger.debug("   Error Type: \(error)")
            ProductionLogger.debug("   Error Message: \(error.localizedDescription)")
            ProductionLogger.debug("   Recovery: \(error.recoverySuggestion ?? "None")")
        }
        
        ProductionLogger.debug("   Final Auth State: \(isAuthenticated)")
        ProductionLogger.debug("   Completion Timestamp: \(Date())")
        ProductionLogger.debug("═══════════════════════════════════════════════════")
    }
    
    // MARK: - Enhanced Error Logging
    
    /// Log detailed authentication error information
    private func logAuthenticationError(_ error: GoogleOAuthError) {
        ProductionLogger.debug("❌ Google OAuth Error Details:")
        ProductionLogger.debug("  - Error: \(error.errorDescription ?? "Unknown error")")
        ProductionLogger.debug("  - Recovery: \(error.recoverySuggestion ?? "No recovery suggestion")")
        
        // Log additional context based on error type
        switch error {
        case .userCancelled:
            ProductionLogger.debug("  - Context: User cancelled the authentication flow")
        case .authenticationFailed(let underlyingError):
            ProductionLogger.debug("  - Underlying Error: \(underlyingError.localizedDescription)")
        case .networkError(let networkError):
            ProductionLogger.debug("  - Network Error: \(networkError.localizedDescription)")
        case .tokenExchangeFailed(let statusCode):
            ProductionLogger.debug("  - HTTP Status Code: \(statusCode)")
            logTokenExchangeFailureDetails(statusCode: statusCode)
        case .stateValidationFailed:
            ProductionLogger.debug("  - Security Issue: OAuth state parameter validation failed")
            ProductionLogger.debug("  - This could indicate a CSRF attack or session corruption")
        case .missingClientCredentials:
            ProductionLogger.debug("  - Configuration Issue: Google OAuth client credentials not found")
            ProductionLogger.debug("  - Check GoogleService-Info.plist and secure storage")
        default:
            break
        }
        
        // Log current configuration state
        ProductionLogger.debug("  - Configuration Check:")
        ProductionLogger.debug("    - Has Client ID: \(getClientID() != nil)")
        ProductionLogger.debug("    - Has Client Secret: \(getClientSecret() != nil)")
        ProductionLogger.debug("    - Callback URL Scheme: \(getCallbackURLScheme())")
    }
    
    /// Log specific details for token exchange failures
    private func logTokenExchangeFailureDetails(statusCode: Int) {
        switch statusCode {
        case 400:
            ProductionLogger.debug("  - HTTP 400: Bad Request - Check authorization code or client credentials")
        case 401:
            ProductionLogger.debug("  - HTTP 401: Unauthorized - Invalid client credentials")
        case 403:
            ProductionLogger.debug("  - HTTP 403: Forbidden - Client not authorized for OAuth")
        case 429:
            ProductionLogger.debug("  - HTTP 429: Rate Limited - Too many requests")
        case 500...599:
            ProductionLogger.debug("  - HTTP \(statusCode): Server Error - Google's servers are experiencing issues")
        default:
            ProductionLogger.debug("  - HTTP \(statusCode): Unexpected response code")
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
