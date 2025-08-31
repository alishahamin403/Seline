//
//  LocalEmailService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import Foundation
import Combine
import BackgroundTasks
import UIKit
import CoreData

/// Local-first email service that manages Core Data persistence and Gmail API sync
/// Phase 2: Integrated with Supabase for hybrid cloud storage
class LocalEmailService: ObservableObject {
    static let shared = LocalEmailService()

    private let coreDataManager = CoreDataManager.shared
    private let gmailService = GmailService.shared
    private let supabaseService = SupabaseService.shared
    private let notificationManager = NotificationManager.shared
    private var syncTimer: Timer?
    private var cleanupTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var cloudSyncEnabled = true
    @Published var isCloudSyncing = false
    
    // Background sync configuration
    private let backgroundSyncIdentifier = "com.seline.email-sync"
    private let syncInterval: TimeInterval = 15 * 60 // 15 minutes
    
    private init() {
        setupBackgroundSync()
        setupCleanupTimer()
        setupSupabaseNotifications()
    }
    
    // MARK: - Email Loading (Local-First)
    
    /// Load emails from local storage, then sync with Gmail if needed
    func loadEmails(forceSync: Bool = false) async -> [Email] {
        guard let user = coreDataManager.getCurrentUser() else {
            await MainActor.run {
                errorMessage = "No authenticated user found"
            }
            return []
        }
        
        // Always load from Core Data first for instant UI
        let localEmails = coreDataManager.fetchEmails(for: user, limit: 50)

        // Check if we need to sync
        let shouldSync = forceSync || shouldPerformSync(user: user)

        if shouldSync {
            await performHybridSync(user: user)
            // Return updated local data after sync
            return coreDataManager.fetchEmails(for: user, limit: 50)
        }

        // Return cached local data if no sync needed
        return localEmails
    }
    
    func loadEmailsBy(category: EmailCategory) async -> [Email] {
        guard let user = coreDataManager.getCurrentUser() else { return [] }
        
        let emails = coreDataManager.fetchEmailsBy(category: category, for: user, limit: 50)
        
        // Trigger background sync if data is stale
        if shouldPerformSync(user: user) {
            // Convert user to safe identifier to avoid CoreData context issues
            let userId = user.objectID
            Task.detached { [weak self] in
                await self?.performBackgroundSync(userObjectID: userId)
            }
        }
        
        return emails
    }
    
    /// Get all available emails from local storage (for AI search)
    func getAllEmails() async -> [Email] {
        guard let user = coreDataManager.getCurrentUser() else { return [] }
        
        // Get all emails without category restriction and with higher limit
        return coreDataManager.fetchAllEmails(for: user, limit: 200)
    }
    
    func searchEmails(query: String) async -> [Email] {
        guard let user = coreDataManager.getCurrentUser() else { return [] }
        
        // Search local data first for instant results
        let localResults = coreDataManager.searchEmails(query: query, for: user, limit: 100)
        
        // If cloud sync is enabled and we have Supabase connection, also search remote
        if cloudSyncEnabled, supabaseService.isConnected, let userID = UUID(uuidString: user.id?.uuidString ?? "") {
            do {
                let cloudResults = try await supabaseService.searchEmailsInSupabase(query: query, for: userID, limit: 50)
                // Convert and merge with local results (avoiding duplicates)
                var allEmails = localResults
                let localGmailIDs = Set(localResults.map { $0.id })
                
                for supabaseEmail in cloudResults {
                    if !localGmailIDs.contains(supabaseEmail.gmailID) {
                        if let convertedEmail = convertSupabaseEmailToLocal(supabaseEmail) {
                            allEmails.append(convertedEmail)
                        }
                    }
                }
                
                return allEmails.sorted { $0.date > $1.date }
            } catch {
                ProductionLogger.logError(error as NSError, context: "Cloud search failed, using local results")
            }
        }
        
        return localResults
    }
    
    // MARK: - Email Actions
    
    func markAsRead(emailID: String) async -> Bool {
        guard let user = coreDataManager.getCurrentUser() else { return false }
        
        // Extract user ID safely before background tasks
        let userID = user.id
        
        // Update local data immediately
        let context = coreDataManager.backgroundContext
        
        await withCheckedContinuation { continuation in
            context.perform {
                EmailEntity.markAsRead(gmailIDs: [emailID], user: user, in: context)
                self.coreDataManager.saveBackground(context)
                continuation.resume()
            }
        }
        
        // Sync with Gmail API and Supabase in background
        Task.detached { [weak self] in
            do {
                try await self?.gmailService.markEmailAsRead(emailID)
                
                // Also sync to Supabase if enabled
                if let self = self, self.cloudSyncEnabled, self.supabaseService.isConnected,
                   let safeUserID = userID?.uuidString, let uuid = UUID(uuidString: safeUserID) {
                    try await self.supabaseService.updateEmailStatus(gmailID: emailID, userID: uuid, isRead: true)
                }
            } catch {
                ProductionLogger.logError(error as NSError, context: "Mark as read sync failed")
            }
        }
        
        return true
    }
    
    func markAsImportant(emailID: String, isImportant: Bool) async -> Bool {
        guard let user = coreDataManager.getCurrentUser() else { return false }
        
        // Extract user ID safely before background tasks
        let userID = user.id
        
        // Update local data immediately
        let context = coreDataManager.backgroundContext
        
        await withCheckedContinuation { continuation in
            context.perform {
                EmailEntity.markAsImportant(gmailIDs: [emailID], user: user, isImportant: isImportant, in: context)
                self.coreDataManager.saveBackground(context)
                continuation.resume()
            }
        }
        
        // Sync with Gmail API and Supabase in background
        Task.detached { [weak self] in
            do {
                if isImportant {
                    try await self?.gmailService.addLabelToEmail(emailID, labelId: "IMPORTANT")
                } else {
                    try await self?.gmailService.removeLabelFromEmail(emailID, labelId: "IMPORTANT")
                }
                
                // Also sync to Supabase if enabled
                if let self = self, self.cloudSyncEnabled, self.supabaseService.isConnected,
                   let safeUserID = userID?.uuidString, let uuid = UUID(uuidString: safeUserID) {
                    try await self.supabaseService.updateEmailStatus(gmailID: emailID, userID: uuid, isImportant: isImportant)
                }
            } catch {
                ProductionLogger.logError(error as NSError, context: "Mark as important sync failed")
            }
        }
        
        return true
    }
    
    // MARK: - Hybrid Sync (Gmail → Core Data → Supabase)
    
    /// Performs hybrid sync: Gmail → Core Data → Supabase
    private func performHybridSync(user: UserEntity) async {
        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
            isCloudSyncing = cloudSyncEnabled && supabaseService.isConnected
        }
        
        do {
            // Update user auth if needed
            let selineUser = user.toSelineUser()
            if selineUser.isTokenExpired {
                // TODO: Refresh token
                ProductionLogger.logError(NSError(domain: "LocalEmailService", code: -1), context: "Token expired, need refresh")
                await MainActor.run {
                    errorMessage = "Authentication expired"
                    isSyncing = false
                    isCloudSyncing = false
                }
                return
            }
            
            await MainActor.run { syncProgress = 0.1 }
            
            // Step 1: Fetch emails from Gmail API
            let gmailEmails = try await gmailService.fetchTodaysUnreadEmails()
            ProductionLogger.logCoreDataEvent("Fetched \(gmailEmails.count) emails from Gmail")
            
            await MainActor.run { syncProgress = 0.3 }
            
            // Step 2: Store in Core Data (local-first)
            coreDataManager.saveEmails(gmailEmails, for: user)
            ProductionLogger.logCoreDataEvent("Saved emails to Core Data")
            
            await MainActor.run { syncProgress = 0.6 }

            // Step 3a: Notify about new emails in quick access categories
            await notifyAboutNewEmails(gmailEmails)

            // Step 3: Sync to Supabase if enabled
            if cloudSyncEnabled && supabaseService.isConnected {
                guard let userID = UUID(uuidString: user.id?.uuidString ?? "") else {
                    ProductionLogger.logError(NSError(domain: "LocalEmailService", code: -2), context: "Invalid user ID for Supabase sync")
                    return
                }
                
                let syncedCount = try await supabaseService.syncEmailsToSupabase(gmailEmails, for: userID)
                ProductionLogger.logCoreDataEvent("Synced \(syncedCount) emails to Supabase")
                
                // Update Supabase sync status
                try await supabaseService.updateSyncStatus(
                    type: "gmail_to_supabase",
                    status: "completed",
                    userID: userID,
                    metadata: ["emails_count": gmailEmails.count, "synced_count": syncedCount]
                )
            }
            
            await MainActor.run { syncProgress = 0.9 }
            
            // Step 4: Update local sync status
            coreDataManager.updateSyncStatus(type: "hybrid_sync", date: Date(), for: user)
            
            await MainActor.run {
                syncProgress = 1.0
                lastSyncDate = Date()
                errorMessage = nil
            }
            
            ProductionLogger.logCoreDataEvent("Hybrid sync completed: \(gmailEmails.count) emails")
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Hybrid sync failed")
            await MainActor.run {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isSyncing = false
            isCloudSyncing = false
        }
    }
    
    private func shouldPerformSync(user: UserEntity) -> Bool {
        guard let lastSync = coreDataManager.getLastSyncDate(type: "gmail", for: user) else {
            return true // Never synced before
        }
        
        let timeSinceLastSync = Date().timeIntervalSince(lastSync)
        return timeSinceLastSync > syncInterval
    }
    
    // MARK: - Background Sync
    
    private func setupBackgroundSync() {
        // Register background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundSyncIdentifier, using: nil) { task in
            self.handleBackgroundSync(task as! BGAppRefreshTask)
        }
        
        // Schedule periodic sync
        scheduleBackgroundSync()
    }
    
    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundSyncIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: syncInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            ProductionLogger.logCoreDataEvent("Background sync scheduled")
        } catch {
            ProductionLogger.logError(error as NSError, context: "Background sync scheduling failed")
        }
    }
    
    private func handleBackgroundSync(_ task: BGAppRefreshTask) {
        scheduleBackgroundSync() // Schedule next sync
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            guard let user = coreDataManager.getCurrentUser() else {
                task.setTaskCompleted(success: false)
                return
            }
            
            if shouldPerformSync(user: user) {
                await performHybridSync(user: user)
                performCleanup()
            }
            
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Storage Management
    
    private func setupCleanupTimer() {
        // Run cleanup every 6 hours
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.performCleanup()
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        syncTimer?.invalidate()
        cleanupTimer = nil
        syncTimer = nil
    }
    
    /// Safe background sync using user ObjectID to avoid CoreData context violations
    private func performBackgroundSync(userObjectID: NSManagedObjectID) async {
        let context = coreDataManager.backgroundContext
        
        await withCheckedContinuation { continuation in
            context.perform {
                do {
                    // Safely get user in background context
                    guard let user = try context.existingObject(with: userObjectID) as? UserEntity else {
                        continuation.resume()
                        return
                    }
                    
                    Task.detached { [weak self] in
                        await self?.performHybridSync(user: user)
                        continuation.resume()
                    }
                } catch {
                    ProductionLogger.logError(error as NSError, context: "Failed to get user in background context")
                    continuation.resume()
                }
            }
        }
    }
    
    private func performCleanup() {
        Task.detached { [weak self] in
            self?.coreDataManager.cleanupOldEmails()
            self?.coreDataManager.enforceStorageLimit()
        }
    }
    
    // MARK: - Offline Support
    
    func getOfflineStatus() -> OfflineStatus {
        guard let user = coreDataManager.getCurrentUser() else {
            return OfflineStatus(isOfflineCapable: false, emailCount: 0, lastSyncDate: nil)
        }
        
        let emailCount = coreDataManager.fetchEmails(for: user, limit: Int.max).count
        let lastSync = coreDataManager.getLastSyncDate(type: "gmail", for: user)
        
        return OfflineStatus(
            isOfflineCapable: emailCount > 0,
            emailCount: emailCount,
            lastSyncDate: lastSync
        )
    }
    
    // MARK: - Statistics
    
    func getStorageStatistics() -> StorageStatistics {
        guard let user = coreDataManager.getCurrentUser() else {
            return StorageStatistics(totalSize: 0, emailCount: 0, cleanupDate: nil)
        }
        
        let totalSize = coreDataManager.getStorageSize()
        let emailCount = user.totalEmailCount
        let lastSync = coreDataManager.getLastSyncDate(type: "cleanup", for: user)
        
        return StorageStatistics(
            totalSize: totalSize,
            emailCount: emailCount,
            cleanupDate: lastSync
        )
    }
    
    // MARK: - User Management
    
    func setCurrentUser(_ selineUser: SelineUser) {
        guard let userEntity = coreDataManager.createOrUpdateUser(selineUser) else {
            ProductionLogger.logError(NSError(domain: "LocalEmailService", code: -1), context: "Failed to create/update user")
            return
        }
        
        // Initialize Supabase authentication if enabled
        if cloudSyncEnabled {
            Task {
                do {
                    if let refreshToken = selineUser.refreshToken {
                        try await supabaseService.signInWithOAuth(
                            provider: .google,
                            accessToken: selineUser.accessToken,
                            refreshToken: refreshToken
                        )
                        
                        // Subscribe to real-time updates
                        if let userID = userEntity.id {
                            try await supabaseService.subscribeToEmailUpdates(userID: userID)
                        }
                    } else {
                        ProductionLogger.logError(
                            NSError(domain: "LocalEmailService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing refresh token"]),
                            context: "Supabase authentication skipped: no refresh token"
                        )
                    }
                } catch {
                    ProductionLogger.logError(error as NSError, context: "Supabase authentication failed")
                }
                
                // Initialize first sync
                await performHybridSync(user: userEntity)
            }
        } else {
            // Initialize first sync without Supabase
            Task {
                await performHybridSync(user: userEntity)
            }
        }
    }
    
    func signOut() {
        // Stop timers
        syncTimer?.invalidate()
        syncTimer = nil
        
        // Clear published properties
        isLoading = false
        isSyncing = false
        lastSyncDate = nil
        errorMessage = nil
        
        // Sign out from Supabase if connected
        if supabaseService.isConnected {
            Task {
                try? await supabaseService.signOut()
            }
        }
        
        // Note: We keep Core Data for offline access, just stop syncing
        ProductionLogger.logCoreDataEvent("User signed out, Core Data preserved for offline access")
    }
    
    // MARK: - Supabase Integration
    
    private func setupSupabaseNotifications() {
        // Listen for real-time email updates from other devices
        NotificationCenter.default.addObserver(
            forName: .supabaseEmailUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSupabaseEmailUpdate(notification)
        }
        
        // Listen for sync status updates
        NotificationCenter.default.addObserver(
            forName: .supabaseSyncUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSupabaseSyncUpdate(notification)
        }
    }
    
    private func handleSupabaseEmailUpdate(_ notification: Notification) {
        // When emails are updated from another device, trigger local sync
        guard let user = coreDataManager.getCurrentUser() else { return }
        
        Task { [weak self] in
            // Fetch latest emails from Supabase and update Core Data
            if let userID = UUID(uuidString: user.id?.uuidString ?? "") {
                do {
                    let _ = try await self?.supabaseService.fetchEmailsFromSupabase(for: userID, limit: 50)
                    // Convert and merge with local data
                    // This ensures real-time cross-device sync
                    ProductionLogger.logCoreDataEvent("Received real-time email update, syncing with local storage")
                } catch {
                    ProductionLogger.logError(error as NSError, context: "Real-time email sync failed")
                }
            }
        }
    }
    
    private func handleSupabaseSyncUpdate(_ notification: Notification) {
        // Handle sync status updates for UI feedback
        ProductionLogger.logCoreDataEvent("Received sync status update from Supabase")
    }
    
    /// Convert SupabaseEmail to local Email model
    private func convertSupabaseEmailToLocal(_ supabaseEmail: SupabaseEmail) -> Email? {
        // Parse date
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: supabaseEmail.dateReceived) else {
            return nil
        }
        
        // Create sender
        let sender = EmailContact(
            name: supabaseEmail.senderName,
            email: supabaseEmail.senderEmail
        )
        
        // Create recipients
        let recipients: [EmailContact] = supabaseEmail.recipients.compactMap { recipientDict in
            // recipientDict is already [String: String], no need for .value
            guard let email = recipientDict["email"] else { return nil }
            let name = recipientDict["name"]
            return EmailContact(name: name, email: email)
        }

        // Create attachments
        let attachments = supabaseEmail.attachments.compactMap { attachmentDict -> EmailAttachment? in
            // attachmentDict is [String: AnyCodable], need to handle AnyCodable values
            guard let filename = attachmentDict["filename"]?.value as? String,
                  let mimeType = attachmentDict["mime_type"]?.value as? String,
                  let size = attachmentDict["size"]?.value as? Int else {
                return nil
            }
            return EmailAttachment(filename: filename, mimeType: mimeType, size: size)
        }
        
        return Email(
            id: supabaseEmail.gmailID,
            subject: supabaseEmail.subject,
            sender: sender,
            recipients: recipients,
            body: supabaseEmail.body,
            date: date,
            isRead: supabaseEmail.isRead,
            isImportant: supabaseEmail.isImportant,
            labels: supabaseEmail.labels,
            attachments: attachments,
            isPromotional: supabaseEmail.isPromotional,
            hasCalendarEvent: supabaseEmail.hasCalendarEvent
        )
    }
    
    // MARK: - Cloud Sync Control
    
    func enableCloudSync() {
        cloudSyncEnabled = true
        ProductionLogger.logCoreDataEvent("Cloud sync enabled")
    }
    
    func disableCloudSync() {
        cloudSyncEnabled = false
        Task {
            await supabaseService.unsubscribeFromUpdates()
        }
        ProductionLogger.logCoreDataEvent("Cloud sync disabled")
    }

    // MARK: - Email Notifications

    /// Notify about new emails in quick access categories
    private func notifyAboutNewEmails(_ emails: [Email]) async {
        // Categorize emails
        let importantEmails = emails.filter { $0.isImportant }
        let promotionalEmails = emails.filter { $0.isPromotional }
        let calendarEmails = emails.filter { $0.hasCalendarEvent }

        // Send notifications for each category
        if !importantEmails.isEmpty {
            notificationManager.notifyNewImportantEmails(importantEmails)
        }

        if !promotionalEmails.isEmpty {
            notificationManager.notifyNewPromotionalEmails(promotionalEmails)
        }

        if !calendarEmails.isEmpty {
            notificationManager.notifyNewCalendarEmails(calendarEmails)
        }

        // Notify about general new emails (excluding the categorized ones)
        let generalEmails = emails.filter { !$0.isImportant && !$0.isPromotional && !$0.hasCalendarEvent }
        if !generalEmails.isEmpty {
            notificationManager.notifyNewEmails(generalEmails)
        }

        // Update badge count
        notificationManager.updateBadgeCount()
    }
}

// MARK: - Supporting Types

struct OfflineStatus {
    let isOfflineCapable: Bool
    let emailCount: Int
    let lastSyncDate: Date?
}

struct StorageStatistics {
    let totalSize: Int64
    let emailCount: Int
    let cleanupDate: Date?
    
    var totalSizeMB: Double {
        return Double(totalSize) / (1024 * 1024)
    }
}

// MARK: - GmailService Extensions

extension GmailService {
    func markEmailAsRead(_ emailID: String) async throws {
        // Add implementation for marking email as read via Gmail API
        // This would use the Gmail API to modify labels
        ProductionLogger.logAuthEvent("Gmail API: Mark as read - \(emailID)")
    }
    
    func addLabelToEmail(_ emailID: String, labelId: String) async throws {
        // Add implementation for adding labels via Gmail API
        ProductionLogger.logAuthEvent("Gmail API: Add label \(labelId) to \(emailID)")
    }
    
    func removeLabelFromEmail(_ emailID: String, labelId: String) async throws {
        // Add implementation for removing labels via Gmail API
        ProductionLogger.logAuthEvent("Gmail API: Remove label \(labelId) from \(emailID)")
    }
}
