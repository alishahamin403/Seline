//
//  SupabaseConfig.swift
//  Seline
//
//  Enhanced Supabase configuration for real SDK implementation
//

import Foundation

struct SupabaseConfig {
    // Production Supabase Configuration
    static let supabaseURL = URL(string: "https://wnydlexwqtlhfbqdvwfj.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueWRsZXh3cXRsaGZicWR2d2ZqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NjQyMDYyNSwiZXhwIjoyMDcxOTk2NjI1fQ.OPqvoN8o9ccA1TaWe4KZZbZzRm2QN3_thF4Mq4jbaA8"
    
    // Authentication configuration
    static let enabledAuthProviders = ["google"]
    static let redirectURL = URL(string: "https://wnydlexwqtlhfbqdvwfj.supabase.co/auth/v1/callback")!
    
    // Privacy settings for email data
    static let storeOnlyMetadata = true
    static let maxSnippetLength = 150
    static let enableEncryption = true
    
    // Storage limits
    static let defaultStorageQuotaBytes: Int64 = 104_857_600 // 100MB
    static let maxEmailsPerUser = 50_000
    
    // Sync configuration
    static let syncBatchSize = 100
    static let maxRetryAttempts = 3
    static let syncTimeoutSeconds: TimeInterval = 30
    
    // Table Names
    struct Tables {
        static let users = "users"
        static let emails = "emails"
        static let syncStatus = "sync_status"
        static let emailAttachments = "email_attachments"
        static let emailCategories = "email_categories"
    }
    
    // RLS Policies
    struct Policies {
        static let userDataAccess = "Users can only access their own data"
        static let emailAccess = "Users can only access their own emails"
        static let syncStatusAccess = "Users can only access their own sync status"
    }
    
    // Realtime Channels
    struct Channels {
        static let emailUpdates = "email_updates"
        static let syncUpdates = "sync_updates"
    }
    
    // MARK: - Security Settings
    
    /// Get user-specific encryption key material
    static func getUserKeyMaterial(googleId: String, email: String) -> String {
        return "\(googleId):\(email):seline_metadata_key"
    }
    
    /// Validate Supabase configuration
    static func validateConfiguration() -> Bool {
        guard !supabaseAnonKey.isEmpty,
              supabaseURL.absoluteString.contains("supabase.co"),
              !enabledAuthProviders.isEmpty else {
            ProductionLogger.logAuthEvent("❌ Invalid Supabase configuration")
            return false
        }
        
        ProductionLogger.logAuthEvent("✅ Supabase configuration validated")
        return true
    }
    
    // MARK: - Environment Configuration
    
    /// Get configuration for current environment
    static func getEnvironmentConfig() -> [String: Any] {
        return [
            "supabase_url": supabaseURL.absoluteString,
            "auth_providers": enabledAuthProviders,
            "metadata_only": storeOnlyMetadata,
            "storage_quota_mb": defaultStorageQuotaBytes / (1024 * 1024)
        ]
    }
    
    /// Log current configuration (safe for production)
    static func logConfiguration() {
        let config = getEnvironmentConfig()
        ProductionLogger.logAuthEvent("🔧 Supabase Config: \(config)")
    }
}
