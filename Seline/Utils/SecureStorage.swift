//
//  SecureStorage.swift
//  Seline
//
//  Created by Claude on 2025-08-25.
//

import Foundation
import Security

/// Secure storage manager for API keys and sensitive data using iOS Keychain
class SecureStorage {
    static let shared = SecureStorage()
    
    private init() {}
    
    // MARK: - API Key Identifiers
    
    private enum KeychainKey {
        static let openAIAPIKey = "seline.openai.api.key"
        static let googleClientID = "seline.google.client.id"
        static let googleClientSecret = "seline.google.client.secret"
        static let googleAccessToken = "seline.google.access.token"
        static let googleRefreshToken = "seline.google.refresh.token"
        static let userEncryptionKey = "seline.user.encryption.key"
    }
    
    // MARK: - API Key Management
    
    /// Store OpenAI API Key securely (scoped to current user if available)
    func storeOpenAIKey(_ key: String) -> Bool {
        let scopedKey = scopedOpenAIKey()
        return storeInKeychain(key: scopedKey, value: key)
    }
    
    /// Retrieve OpenAI API Key (try current user scope, then global fallback)
    func getOpenAIKey() -> String? {
        let scopedKey = scopedOpenAIKey()
        if let value = retrieveFromKeychain(key: scopedKey) { return value }
        // Fallback to legacy global key if present
        return retrieveFromKeychain(key: KeychainKey.openAIAPIKey)
    }
    
    /// Store Google OAuth credentials
    func storeGoogleCredentials(clientID: String, clientSecret: String) -> Bool {
        let clientIDSuccess = storeInKeychain(key: KeychainKey.googleClientID, value: clientID)
        let clientSecretSuccess = storeInKeychain(key: KeychainKey.googleClientSecret, value: clientSecret)
        return clientIDSuccess && clientSecretSuccess
    }
    
    /// Store Google OAuth tokens
    func storeGoogleTokens(accessToken: String, refreshToken: String?) -> Bool {
        let accessSuccess = storeInKeychain(key: KeychainKey.googleAccessToken, value: accessToken)
        var refreshSuccess = true
        
        if let refreshToken = refreshToken {
            refreshSuccess = storeInKeychain(key: KeychainKey.googleRefreshToken, value: refreshToken)
        }
        
        return accessSuccess && refreshSuccess
    }
    
    /// Retrieve Google access token
    func getGoogleAccessToken() -> String? {
        return retrieveFromKeychain(key: KeychainKey.googleAccessToken)
    }
    
    /// Retrieve Google refresh token
    func getGoogleRefreshToken() -> String? {
        return retrieveFromKeychain(key: KeychainKey.googleRefreshToken)
    }
    
    /// Retrieve Google client ID
    func getGoogleClientID() -> String? {
        return retrieveFromKeychain(key: KeychainKey.googleClientID)
    }
    
    /// Retrieve Google client secret
    func getGoogleClientSecret() -> String? {
        return retrieveFromKeychain(key: KeychainKey.googleClientSecret)
    }
    
    /// Clear all stored credentials (for sign out)
    func clearAllCredentials() {
        let keys = [
            KeychainKey.googleClientID,
            KeychainKey.googleClientSecret,
            KeychainKey.googleAccessToken,
            KeychainKey.googleRefreshToken
        ]
        
        keys.forEach { key in
            deleteFromKeychain(key: key)
        }
        // Also clear user-scoped OpenAI key only if you want a full wipe
        deleteFromKeychain(key: scopedOpenAIKey())
    }

    /// Clear only OpenAI API key (do not touch other credentials)
    func clearOpenAIKey() {
        deleteFromKeychain(key: scopedOpenAIKey())
    }

    /// Clear only Google OAuth credentials
    func clearGoogleCredentials() {
        let keys = [
            KeychainKey.googleClientID,
            KeychainKey.googleClientSecret,
            KeychainKey.googleAccessToken,
            KeychainKey.googleRefreshToken
        ]
        keys.forEach { deleteFromKeychain(key: $0) }
    }
    
    // MARK: - User Data Encryption Key
    
    /// Generate and store encryption key for user data
    func generateUserEncryptionKey() -> Bool {
        let key = generateRandomKey()
        return storeInKeychain(key: KeychainKey.userEncryptionKey, value: key)
    }
    
    /// Get user encryption key
    func getUserEncryptionKey() -> String? {
        var key = retrieveFromKeychain(key: KeychainKey.userEncryptionKey)
        
        // Generate key if it doesn't exist
        if key == nil && generateUserEncryptionKey() {
            key = retrieveFromKeychain(key: KeychainKey.userEncryptionKey)
        }
        
        return key
    }
    
    // MARK: - Keychain Operations
    
    @discardableResult
    private func storeInKeychain(key: String, value: String) -> Bool {
        // Delete any existing entry first
        deleteFromKeychain(key: key)
        
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // Don't sync to iCloud for security
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func retrieveFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    @discardableResult
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Utility Methods
    
    private func generateRandomKey() -> String {
        let length = 32
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// Check if API keys are configured
    func hasOpenAIKey() -> Bool {
        return getOpenAIKey() != nil
    }
    
    func hasGoogleCredentials() -> Bool {
        // For iOS OAuth, check if GoogleService-Info.plist exists and has CLIENT_ID
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           plist["CLIENT_ID"] != nil {
            return true
        }
        
        // Fallback: check for stored access token
        return getGoogleAccessToken() != nil
    }
    
    /// Validate API key format (basic validation)
    func validateOpenAIKey(_ key: String) -> Bool {
        // OpenAI keys start with "sk-" and are typically 51 characters
        return key.hasPrefix("sk-") && key.count >= 40
    }

    // MARK: - User Scoping Helper
    private func scopedOpenAIKey() -> String {
        // Use UserDefaults as a sync fallback for email scoping
        if let email = UserDefaults.standard.string(forKey: "current_user_email")?.lowercased(), !email.isEmpty {
            return "\(KeychainKey.openAIAPIKey).user.\(email)"
        }
        return KeychainKey.openAIAPIKey
    }
}

// MARK: - Configuration Manager

/// Manages app configuration and feature flags
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private init() {}
    
    // MARK: - Feature Flags
    
    enum FeatureFlag {
        case useRealOpenAIAPI
        case useRealGoogleAPIs
        case enableAnalytics
        case enableCrashReporting
        case showDebugInfo
    }
    
    func isFeatureEnabled(_ feature: FeatureFlag) -> Bool {
        switch feature {
        case .useRealOpenAIAPI:
            return SecureStorage.shared.hasOpenAIKey() // Enable when API key is available
        case .useRealGoogleAPIs:
            return SecureStorage.shared.hasGoogleCredentials() // Enable in both debug and production when credentials are available
        case .enableAnalytics:
            return !isDebugMode() && isProductionBuild()
        case .enableCrashReporting:
            return isProductionBuild()
        case .showDebugInfo:
            return isDebugMode()
        }
    }
    
    // MARK: - Environment Detection
    
    func isDebugMode() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    func isProductionBuild() -> Bool {
        return !isDebugMode()
    }
    
    func getAppVersion() -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    func getBuildNumber() -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    // MARK: - API Configuration
    
    func getOpenAIConfiguration() -> OpenAIConfiguration {
        return OpenAIConfiguration(
            useRealAPI: isFeatureEnabled(.useRealOpenAIAPI),
            maxTokens: 150,
            temperature: 0.7,
            timeoutInterval: 30.0,
            maxRetries: 3
        )
    }
    
    func getGoogleAPIConfiguration() -> GoogleAPIConfiguration {
        return GoogleAPIConfiguration(
            useRealAPI: isFeatureEnabled(.useRealGoogleAPIs),
            scopes: [
                "https://www.googleapis.com/auth/gmail.readonly",
                "https://www.googleapis.com/auth/calendar"
            ],
            timeoutInterval: 45.0,
            maxRetries: 3
        )
    }
}

// MARK: - Configuration Models

struct OpenAIConfiguration {
    let useRealAPI: Bool
    let maxTokens: Int
    let temperature: Double
    let timeoutInterval: TimeInterval
    let maxRetries: Int
}

struct GoogleAPIConfiguration {
    let useRealAPI: Bool
    let scopes: [String]
    let timeoutInterval: TimeInterval
    let maxRetries: Int
}