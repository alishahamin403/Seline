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
@MainActor
class LocalEmailService: ObservableObject {
    static let shared = LocalEmailService()

    private let coreDataManager = CoreDataManager.shared
    private let gmailService = GmailService.shared
    @MainActor
    private var supabaseService: SupabaseService { SupabaseService.shared }
    private let notificationManager = NotificationManager.shared
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
        if cloudSyncEnabled, supabaseService.isConnected, let _ = UUID(uuidString: user.id?.uuidString ?? "") {
            // TODO: Implement Supabase search with searchEmails method
            // For now, just return local results
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
            guard let self = self else { return }
            let gmailService = self.gmailService
            do {
                try await gmailService.markEmailAsRead(emailID)
                
                // Also sync to Supabase if enabled
                /* TODO: Fix compiler error.
                if self.cloudSyncEnabled, await (await self.supabaseService).isInitialized,
                   let safeUserID = userID?.uuidString, let uuid = UUID(uuidString: safeUserID) {
                    try await (await self.supabaseService).updateEmailStatus(gmailId: emailID, isRead: true, userId: uuid)
                }
                */
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
            guard let self = self else { return }
            let service = self.gmailService
            do {
                if isImportant {
                    try await self.gmailService.addLabelToEmail(emailID, labelId: "IMPORTANT")
                } else {
                    try await self.gmailService.removeLabelFromEmail(emailID, labelId: "IMPORTANT")
                }
                
                // Also sync to Supabase if enabled
                /* TODO: Fix compiler error.
                if self.cloudSyncEnabled, await (await self.supabaseService).isInitialized,
                   let safeUserID = userID?.uuidString, let uuid = UUID(uuidString: safeUserID) {
                    try await (await self.supabaseService).updateEmailStatus(gmailId: emailID, isRead: false, userId: uuid)
                }
                */
            } catch {
                ProductionLogger.logError(error as NSError, context: "Mark as important sync failed")
            }
        }
        
        return true
    }
    
    // MARK: - Hybrid Sync (Gmail → Core Data → Supabase)
    
    /// Performs hybrid sync: Gmail → Core Data → Supabase
    private func performHybridSync(user: UserEntity) async {
        let supabaseInitialized = supabaseService.isConnected
        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
            isCloudSyncing = cloudSyncEnabled && supabaseInitialized
        }
        
        do {
            // Update user auth if needed
            let selineUser = user.toSelineUser()
            if selineUser.isTokenExpired {
                do {
                    try await AuthenticationService.shared.refreshTokenIfNeeded()
                    ProductionLogger.logAuthEvent("Token refreshed successfully during sync")
                } catch {
                    ProductionLogger.logError(error, context: "Token refresh failed during sync")
                    await MainActor.run {
                        errorMessage = "Authentication expired. Please sign in again."
                        isSyncing = false
                        isCloudSyncing = false
                    }
                    return
                }
            }
            
            await MainActor.run { syncProgress = 0.1 }
            
            // Step 1: Fetch emails from Gmail API
            let gmailEmails = try await gmailService.fetchTodaysEmailsOnly()
            ProductionLogger.logCoreDataEvent("Fetched \(gmailEmails.count) emails from Gmail")
            
            await MainActor.run { syncProgress = 0.3 }
            
            // Step 2: Store in Core Data (local-first)
            coreDataManager.saveEmails(gmailEmails, for: user)
            ProductionLogger.logCoreDataEvent("Saved emails to Core Data")
            
            await MainActor.run { syncProgress = 0.6 }

            // Step 3a: Notify about new emails in quick access categories
            await notifyAboutNewEmails(gmailEmails)

            // Step 3: Sync to Supabase if enabled
            let supabaseInitialized = supabaseService.isConnected
            if cloudSyncEnabled && supabaseInitialized {
                guard let userID = UUID(uuidString: user.id?.uuidString ?? "") else {
                    ProductionLogger.logError(NSError(domain: "LocalEmailService", code: -2), context: "Invalid user ID for Supabase sync")
                    return
                }
                
                _ = try await supabaseService.syncEmailsToSupabase(gmailEmails, for: userID)
                ProductionLogger.logCoreDataEvent("Synced \(gmailEmails.count) emails to Supabase")
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
            Task { @MainActor in
                self?.performCleanup()
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
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
                // OAuth authentication is handled via AuthenticationService
                // Subscribe to real-time updates
                if let userID = userEntity.id {
                    // DISABLED: await supabaseService.subscribeToEmailUpdates(userID: userID)
                } else {
                    ProductionLogger.logError(
                        NSError(domain: "LocalEmailService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing refresh token"]),
                        context: "Supabase authentication skipped: no refresh token"
                    )
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
        
        // Clear published properties
        isLoading = false
        isSyncing = false
        lastSyncDate = nil
        errorMessage = nil
        
        // Sign out from Supabase if connected
        Task {
            // DISABLED: Supabase sign out
            // if await supabaseService.isConnected {
            //     await supabaseService.signOut()
            // }
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
                    // DISABLED: let _ = try await self?.supabaseService.fetchEmailsFromSupabase(userID: userID, limit: 100)
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
    // DISABLED: Supabase integration paused
    /*
    private func convertSupabaseEmailToLocal(_ supabaseEmail: SupabaseEmail) -> Email? {
        let date = supabaseEmail.dateReceived
        
        // Create sender
        let sender = EmailContact(
            name: supabaseEmail.senderName,
            email: supabaseEmail.senderEmail
        )
        
        // Recipients and attachments would be empty for now
        let recipients: [EmailContact] = []
        let attachments: [EmailAttachment] = []
        
        return Email(
            id: supabaseEmail.gmailId,
            subject: supabaseEmail.subject,
            sender: sender,
            recipients: recipients,
            body: supabaseEmail.body,
            date: date,
            isRead: supabaseEmail.isRead,
            isImportant: supabaseEmail.isImportant,
            labels: supabaseEmail.labels,
            attachments: attachments,
            isPromotional: supabaseEmail.isPromotional
        )
    }
    */
    
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
        // Notify about all new emails
        notificationManager.notifyNewEmails(emails)

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
