//
//  SupabaseConfig.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import Foundation

struct SupabaseConfig {
    // Production Supabase Configuration
    static let supabaseURL = URL(string: "https://wnydlexwqtlhfbqdvwfj.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndueWRsZXh3cXRsaGZicWR2d2ZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY0MjA2MjUsImV4cCI6MjA3MTk5NjYyNX0.ww5jU6IpG0HPtQfUgugP4czoNVzrD7HJfHZ72G4i-kY"
    
    // OpenAI Configuration (already available)
    static let openAIAPIKey = "sk-proj-wQEAcJC5ok32A..." // Truncated for security
    
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
}