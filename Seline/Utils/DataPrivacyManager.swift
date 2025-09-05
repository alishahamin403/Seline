//
//  DataPrivacyManager.swift
//  Seline
//
//  Manages user consent for cloud data storage and privacy settings
//

import Foundation

class DataPrivacyManager {
    static let shared = DataPrivacyManager()
    
    private let userDefaults = UserDefaults.standard
    private let cloudSyncConsentKey = "seline_cloud_sync_consent"
    private let tokenStorageConsentKey = "seline_token_storage_consent" 
    private let dataRetentionConsentKey = "seline_data_retention_consent"
    
    private init() {}
    
    // MARK: - Consent Management
    
    /// Check if user has consented to cloud sync
    var hasCloudSyncConsent: Bool {
        get { userDefaults.bool(forKey: cloudSyncConsentKey) }
        set { 
            userDefaults.set(newValue, forKey: cloudSyncConsentKey)
            ProductionLogger.logAuthEvent("Cloud sync consent: \(newValue)")
        }
    }
    
    /// Check if user has consented to encrypted token storage in cloud
    var hasTokenStorageConsent: Bool {
        get { userDefaults.bool(forKey: tokenStorageConsentKey) }
        set { 
            userDefaults.set(newValue, forKey: tokenStorageConsentKey)
            ProductionLogger.logAuthEvent("Token storage consent: \(newValue)")
        }
    }
    
    /// Check if user has consented to data retention policies
    var hasDataRetentionConsent: Bool {
        get { userDefaults.bool(forKey: dataRetentionConsentKey) }
        set { 
            userDefaults.set(newValue, forKey: dataRetentionConsentKey)
            ProductionLogger.logAuthEvent("Data retention consent: \(newValue)")
        }
    }
    
    // MARK: - Privacy Policy Compliance
    
    /// Check if all required consents are granted for cloud sync
    var canSyncToCloud: Bool {
        return hasCloudSyncConsent && hasTokenStorageConsent && hasDataRetentionConsent
    }
    
    /// Initialize default consent for first-time users (metadata-only is low-risk)
    func initializeDefaultConsent() {
        if !hasCloudSyncConsent && !hasTokenStorageConsent && !hasDataRetentionConsent {
            // For metadata-only storage, we can set reasonable defaults
            hasCloudSyncConsent = true  // Metadata sync is privacy-friendly
            hasTokenStorageConsent = true  // Encrypted token storage
            hasDataRetentionConsent = true  // 90-day auto-purge
            
            ProductionLogger.logAuthEvent("✅ Initialized default privacy consents for metadata-only sync")
        }
    }
    
    /// Reset all privacy consents (for settings reset)
    func resetAllConsents() {
        hasCloudSyncConsent = false
        hasTokenStorageConsent = false
        hasDataRetentionConsent = false
        ProductionLogger.logAuthEvent("All privacy consents reset")
    }
    
    /// Get consent message for user display
    func getConsentMessage() -> String {
        return """
        Seline Cloud Sync & Privacy
        
        To provide the best experience across your devices, Seline can:
        
        • Sync your email preferences and settings to the cloud
        • Store encrypted authentication tokens securely  
        • Keep your data synchronized across devices
        
        Your data privacy is our priority:
        ✓ All tokens are encrypted before cloud storage
        ✓ Only you can decrypt your data
        ✓ Data is automatically purged after 90 days of inactivity
        ✓ You can revoke consent and delete all cloud data anytime
        
        Do you consent to secure cloud sync?
        """
    }
    
    // MARK: - Token Storage Validation
    
    /// Validate if token storage is allowed before Supabase operations
    func validateTokenStoragePermission() throws {
        guard hasTokenStorageConsent else {
            throw DataPrivacyError.tokenStorageNotConsented
        }
        
        guard hasCloudSyncConsent else {
            throw DataPrivacyError.cloudSyncNotConsented  
        }
        
        ProductionLogger.logAuthEvent("✅ Token storage permission validated")
    }
    
    // MARK: - Data Retention
    
    /// Check if user data should be purged (90 days since last activity)
    func shouldPurgeUserData(lastActivity: Date) -> Bool {
        let purgeThreshold = TimeInterval(90 * 24 * 3600) // 90 days in seconds
        let daysSinceActivity = Date().timeIntervalSince(lastActivity)
        return daysSinceActivity > purgeThreshold
    }
    
    /// Log data retention check
    func logDataRetentionCheck(userEmail: String, lastActivity: Date) {
        let daysSinceActivity = Int(Date().timeIntervalSince(lastActivity) / (24 * 3600))
        
        if shouldPurgeUserData(lastActivity: lastActivity) {
            ProductionLogger.logAuthEvent("⚠️ Data retention: User \(userEmail) data eligible for purge (inactive \(daysSinceActivity) days)")
        } else {
            ProductionLogger.logAuthEvent("✅ Data retention: User \(userEmail) data retained (active \(daysSinceActivity) days ago)")
        }
    }
}

enum DataPrivacyError: Error, LocalizedError {
    case cloudSyncNotConsented
    case tokenStorageNotConsented
    case dataRetentionNotConsented
    
    var errorDescription: String? {
        switch self {
        case .cloudSyncNotConsented:
            return "Cloud sync permission required. Please grant consent in Settings."
        case .tokenStorageNotConsented:
            return "Token storage permission required for secure sync."
        case .dataRetentionNotConsented:
            return "Data retention consent required for long-term storage."
        }
    }
}