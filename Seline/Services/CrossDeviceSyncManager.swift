//
//  CrossDeviceSyncManager.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import Foundation
import Combine
import Network
import UIKit
import CoreData

/// Manages cross-device synchronization using Supabase real-time features
class CrossDeviceSyncManager: ObservableObject {
    static let shared = CrossDeviceSyncManager()
    
    private let supabaseService = SupabaseService.shared
    private let localEmailService = LocalEmailService.shared
    private let coreDataManager = CoreDataManager.shared
    
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var syncStatus: CrossDeviceSyncStatus = .disconnected
    @Published var lastCrossDeviceSync: Date?
    @Published var pendingChanges: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Device identification
    private let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    private let deviceName = UIDevice.current.name
    private let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    
    private init() {
        setupNetworkMonitoring()
        setupRealtimeSubscriptions()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    self?.handleNetworkAvailable()
                } else {
                    self?.handleNetworkUnavailable()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func handleNetworkAvailable() {
        ProductionLogger.logCoreDataEvent("Network available - enabling cross-device sync")
        
        if supabaseService.isConnected {
            syncStatus = .connected
            Task {
                await performCrossDeviceSync()
            }
        }
    }
    
    private func handleNetworkUnavailable() {
        ProductionLogger.logCoreDataEvent("Network unavailable - disabling cross-device sync")
        syncStatus = .offline
    }
    
    // MARK: - Real-time Subscriptions
    
    private func setupRealtimeSubscriptions() {
        // Listen for email updates from other devices
        NotificationCenter.default.addObserver(
            forName: .supabaseEmailUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRemoteEmailUpdate(notification)
        }
        
        // Listen for sync status updates
        NotificationCenter.default.addObserver(
            forName: .supabaseSyncUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRemoteSyncUpdate(notification)
        }
    }
    
    // MARK: - Cross-Device Sync
    
    /// Initialize cross-device sync for user
    func initializeCrossDeviceSync(for userID: UUID) async {
        guard supabaseService.isConnected else {
            ProductionLogger.logError(NSError(domain: "CrossDeviceSyncManager", code: -1), context: "Supabase not connected")
            return
        }
        
        do {
            // Register this device
            try await registerDevice(userID: userID)
            
            // Subscribe to real-time updates
            try await supabaseService.subscribeToEmailUpdates(userID: userID)
            
            // Perform initial sync
            await performCrossDeviceSync()
            
            await MainActor.run {
                syncStatus = .connected
            }
            
            ProductionLogger.logCoreDataEvent("Cross-device sync initialized for user: \(userID)")
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Failed to initialize cross-device sync")
            await MainActor.run {
                syncStatus = .error("Failed to initialize: \(error.localizedDescription)")
            }
        }
    }
    
    /// Register this device with Supabase
    private func registerDevice(userID: UUID) async throws {
        let _ = [
            "device_id": deviceID,
            "device_name": deviceName,
            "device_type": deviceType,
            "platform": "iOS",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "last_seen": ISO8601DateFormatter().string(from: Date())
        ]

        // This would be stored in a devices table in Supabase
        // For now, we'll just log it
        ProductionLogger.logCoreDataEvent("Device registered: \(deviceName) (\(deviceID))")
    }
    
    /// Perform bidirectional sync between devices
    func performCrossDeviceSync() async {
        guard supabaseService.isConnected,
              let user = coreDataManager.getCurrentUser(),
              let userID = UUID(uuidString: user.id?.uuidString ?? "") else {
            return
        }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            // 1. Get local changes since last sync
            let localChanges = getLocalChanges(since: lastCrossDeviceSync)
            
            // 2. Push local changes to Supabase
            if !localChanges.isEmpty {
                let pushedCount = try await pushLocalChangesToSupabase(localChanges, userID: userID)
                ProductionLogger.logCoreDataEvent("Pushed \(pushedCount) local changes to Supabase")
            }
            
            // 3. Pull remote changes from Supabase
            let remoteChanges = try await pullRemoteChangesFromSupabase(userID: userID, since: lastCrossDeviceSync)
            
            // 4. Apply remote changes to local Core Data
            if !remoteChanges.isEmpty {
                let appliedCount = await applyRemoteChangesToLocal(remoteChanges, user: user)
                ProductionLogger.logCoreDataEvent("Applied \(appliedCount) remote changes to local storage")
            }
            
            // 5. Update sync timestamp
            await MainActor.run {
                lastCrossDeviceSync = Date()
                syncStatus = .connected
                pendingChanges = 0
            }
            
            ProductionLogger.logCoreDataEvent("Cross-device sync completed successfully")
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Cross-device sync failed")
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Local Changes Management
    
    private func getLocalChanges(since date: Date?) -> [LocalEmailChange] {
        guard let user = coreDataManager.getCurrentUser() else { return [] }
        
        // Get emails that have been modified locally since last sync
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        
        var predicate = NSPredicate(format: "user == %@", user)
        
        if let since = date {
            let updatedPredicate = NSPredicate(format: "updatedAt > %@", since as NSDate)
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, updatedPredicate])
        }
        
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.updatedAt, ascending: true)]
        
        do {
            let changedEntities = try context.fetch(request)
            return changedEntities.compactMap { entity in
                guard let gmailID = entity.gmailID else { return nil }
                return LocalEmailChange(
                    gmailID: gmailID,
                    isRead: entity.isRead,
                    isImportant: entity.isImportant,
                    lastModified: entity.updatedAt ?? Date()
                )
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Failed to get local changes")
            return []
        }
    }
    
    private func pushLocalChangesToSupabase(_ changes: [LocalEmailChange], userID: UUID) async throws -> Int {
        var pushedCount = 0
        
        for change in changes {
            try await supabaseService.updateEmailStatus(
                gmailID: change.gmailID,
                userID: userID,
                isRead: change.isRead,
                isImportant: change.isImportant
            )
            pushedCount += 1
        }
        
        return pushedCount
    }
    
    // MARK: - Remote Changes Management
    
    private func pullRemoteChangesFromSupabase(userID: UUID, since date: Date?) async throws -> [RemoteEmailChange] {
        // This would query Supabase for emails modified on other devices
        // For now, we'll simulate this with the existing fetch method
        let supabaseEmails = try await supabaseService.fetchEmailsFromSupabase(for: userID, limit: 100)
        
        // Convert to remote changes (this is simplified)
        return supabaseEmails.compactMap { email in
            let formatter = ISO8601DateFormatter()
            guard let syncedAt = formatter.date(from: email.syncedAt) else { return nil }
            
            // Only include if modified after our last sync
            if let since = date, syncedAt <= since {
                return nil
            }
            
            return RemoteEmailChange(
                gmailID: email.gmailID,
                isRead: email.isRead,
                isImportant: email.isImportant,
                lastModified: syncedAt,
                sourceDevice: "other"
            )
        }
    }
    
    private func applyRemoteChangesToLocal(_ changes: [RemoteEmailChange], user: UserEntity) async -> Int {
        let backgroundContext = coreDataManager.backgroundContext
        var appliedCount = 0
        
        await withCheckedContinuation { continuation in
            backgroundContext.perform {
                for change in changes {
                    // Find the local email entity
                    let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "gmailID == %@ AND user == %@", change.gmailID, user)
                    request.fetchLimit = 1
                    
                    do {
                        if let emailEntity = try backgroundContext.fetch(request).first {
                            // Apply remote changes
                            emailEntity.isRead = change.isRead
                            emailEntity.isImportant = change.isImportant
                            emailEntity.updatedAt = change.lastModified
                            appliedCount += 1
                        }
                    } catch {
                        ProductionLogger.logError(error as NSError, context: "Failed to apply remote change for email: \(change.gmailID)")
                    }
                }
                
                self.coreDataManager.saveBackground(backgroundContext)
                continuation.resume()
            }
        }
        
        return appliedCount
    }
    
    // MARK: - Real-time Event Handlers
    
    private func handleRemoteEmailUpdate(_ notification: Notification) {
        // Another device updated an email - trigger sync
        Task {
            await performCrossDeviceSync()
        }
        
        ProductionLogger.logCoreDataEvent("Received remote email update notification")
    }
    
    private func handleRemoteSyncUpdate(_ notification: Notification) {
        // Update connected devices list or sync status
        ProductionLogger.logCoreDataEvent("Received remote sync update notification")
    }
    
    // MARK: - Device Management
    
    func getConnectedDevices(for userID: UUID) async -> [ConnectedDevice] {
        // This would query a devices table in Supabase
        // For now, return mock data
        return [
            ConnectedDevice(
                id: deviceID,
                name: deviceName,
                type: deviceType,
                platform: "iOS",
                lastSeen: Date(),
                isCurrentDevice: true
            )
        ]
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflict(local: LocalEmailChange, remote: RemoteEmailChange) -> EmailChange {
        // Simple last-write-wins strategy
        if local.lastModified > remote.lastModified {
            return .local(local)
        } else {
            return .remote(remote)
        }
    }
    
    // MARK: - Public Methods
    
    func enableCrossDeviceSync() {
        guard let user = coreDataManager.getCurrentUser(),
              let userID = UUID(uuidString: user.id?.uuidString ?? "") else {
            return
        }
        
        Task {
            await initializeCrossDeviceSync(for: userID)
        }
    }
    
    func disableCrossDeviceSync() {
        Task {
            await supabaseService.unsubscribeFromUpdates()
        }
        
        syncStatus = .disconnected
        connectedDevices = []
        
        ProductionLogger.logCoreDataEvent("Cross-device sync disabled")
    }
    
    func forceSyncNow() {
        Task {
            await performCrossDeviceSync()
        }
    }
}

// MARK: - Supporting Types

enum CrossDeviceSyncStatus {
    case disconnected
    case connecting
    case connected
    case syncing
    case offline
    case error(String)
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .syncing:
            return "Syncing..."
        case .offline:
            return "Offline"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct ConnectedDevice: Identifiable {
    let id: String
    let name: String
    let type: String
    let platform: String
    let lastSeen: Date
    let isCurrentDevice: Bool
}

struct LocalEmailChange {
    let gmailID: String
    let isRead: Bool
    let isImportant: Bool
    let lastModified: Date
}

struct RemoteEmailChange {
    let gmailID: String
    let isRead: Bool
    let isImportant: Bool
    let lastModified: Date
    let sourceDevice: String
}

enum EmailChange {
    case local(LocalEmailChange)
    case remote(RemoteEmailChange)
}