//
//  SyncCoordinator.swift
//  Seline
//
//  Coordinates calendar sync operations to prevent concurrent execution and race conditions
//

import Foundation

@MainActor
class SyncCoordinator {
    static let shared = SyncCoordinator()
    
    private var activeSyncOperations: Set<String> = []
    private var syncQueue: [(id: String, operation: () async throws -> Void)] = []
    private var lastSyncRequestTime: Date = Date.distantPast
    private var isProcessingQueue = false
    
    // Configuration
    private let debounceInterval: TimeInterval = 2.0 // Debounce rapid sync requests
    private let maxConcurrentSyncs = 1 // Only allow one sync at a time
    private let syncTimeoutInterval: TimeInterval = 60.0 // 60 second timeout
    
    private init() {}
    
    // MARK: - Public API
    
    /// Request a sync operation with automatic coordination and debouncing
    func requestSync(
        operationID: String,
        priority: SyncPriority = .normal,
        operation: @escaping () async throws -> Void
    ) async {
        
        let now = Date()
        lastSyncRequestTime = now
        
        // Check if this operation is already running
        if activeSyncOperations.contains(operationID) {
            ProductionLogger.debug("🔄 Sync operation '\(operationID)' already in progress, skipping duplicate")
            return
        }
        
        // Add to queue with priority handling
        let queueItem = (id: operationID, operation: operation)
        
        if priority == .high {
            syncQueue.insert(queueItem, at: 0) // High priority goes to front
        } else {
            syncQueue.append(queueItem)
        }
        
        ProductionLogger.debug("📝 Queued sync operation '\(operationID)' (queue size: \(syncQueue.count))")
        
        // Start processing if not already processing
        if !isProcessingQueue {
            await processSyncQueue()
        }
    }
    
    /// Cancel a specific sync operation
    func cancelSync(operationID: String) {
        syncQueue.removeAll { $0.id == operationID }
        activeSyncOperations.remove(operationID)
        ProductionLogger.debug("❌ Cancelled sync operation '\(operationID)'")
    }
    
    /// Cancel all pending sync operations
    func cancelAllSyncs() {
        let cancelledCount = syncQueue.count
        syncQueue.removeAll()
        activeSyncOperations.removeAll()
        ProductionLogger.debug("🛑 Cancelled all sync operations (\(cancelledCount) operations)")
    }
    
    /// Check if a sync operation is currently active
    func isSyncActive(_ operationID: String) -> Bool {
        return activeSyncOperations.contains(operationID)
    }
    
    /// Get current sync status
    func getSyncStatus() -> CoordinatorSyncStatus {
        return CoordinatorSyncStatus(
            activeOperations: Array(activeSyncOperations),
            queuedOperations: syncQueue.map { $0.id },
            isProcessing: isProcessingQueue,
            lastSyncRequestTime: lastSyncRequestTime
        )
    }
    
    // MARK: - Private Implementation
    
    private func processSyncQueue() async {
        guard !isProcessingQueue else { return }
        
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        while !syncQueue.isEmpty {
            
            // Check if we should debounce (rapid requests within debounce interval)
            let timeSinceLastRequest = Date().timeIntervalSince(lastSyncRequestTime)
            if timeSinceLastRequest < debounceInterval {
                ProductionLogger.debug("⏳ Debouncing sync operations (waiting \(String(format: "%.1f", debounceInterval - timeSinceLastRequest))s)")
                try? await Task.sleep(nanoseconds: UInt64((debounceInterval - timeSinceLastRequest) * 1_000_000_000))
            }
            
            // Get next operation from queue
            guard !syncQueue.isEmpty else { break }
            let queueItem = syncQueue.removeFirst()
            
            // Check if we're at max concurrent syncs
            guard activeSyncOperations.count < maxConcurrentSyncs else {
                // Put item back at front of queue and wait
                syncQueue.insert(queueItem, at: 0)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                continue
            }
            
            // Execute the sync operation
            await executeSyncOperation(queueItem.id, operation: queueItem.operation)
        }
    }
    
    private func executeSyncOperation(_ operationID: String, operation: @escaping () async throws -> Void) async {
        
        activeSyncOperations.insert(operationID)
        let startTime = Date()
        
        ProductionLogger.debug("🚀 Starting sync operation '\(operationID)'")
        
        do {
            // Execute with timeout
            try await withTimeout(syncTimeoutInterval) {
                try await operation()
            }
            
            let duration = Date().timeIntervalSince(startTime)
            ProductionLogger.debug("✅ Completed sync operation '\(operationID)' in \(String(format: "%.2f", duration))s")
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            ProductionLogger.logError(error, context: "Sync operation '\(operationID)' failed after \(String(format: "%.2f", duration))s")
        }
        
        activeSyncOperations.remove(operationID)
    }
    
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            
            // Add the main operation
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SyncCoordinatorError.timeout
            }
            
            // Return first completed result
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Sync Operation Definitions



// MARK: - Data Models

enum SyncPriority {
    case low
    case normal
    case high
}

struct CoordinatorSyncStatus {
    let activeOperations: [String]
    let queuedOperations: [String]
    let isProcessing: Bool
    let lastSyncRequestTime: Date
    
    var totalOperations: Int {
        return activeOperations.count + queuedOperations.count
    }
    
    var isIdle: Bool {
        return totalOperations == 0 && !isProcessing
    }
}

enum SyncCoordinatorError: LocalizedError {
    case timeout
    case syncDisabled
    case operationCancelled
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Sync operation timed out"
        case .syncDisabled:
            return "Calendar sync is currently disabled"
        case .operationCancelled:
            return "Sync operation was cancelled"
        }
    }
}



// MARK: - Debug Extensions

#if DEBUG
extension SyncCoordinator {
    
    /// Print current sync coordination status
    func printSyncStatus() {
        let status = getSyncStatus()
        
        print("\n" + String(repeating: "=", count: 50))
        print("🔄 SYNC COORDINATOR STATUS")
        print(String(repeating: "=", count: 50))
        
        print("\n📊 CURRENT STATE:")
        print("   Is Idle: \(status.isIdle ? "✅" : "❌")")
        print("   Is Processing: \(status.isProcessing ? "✅" : "❌")")
        print("   Total Operations: \(status.totalOperations)")
        
        if !status.activeOperations.isEmpty {
            print("\n🚀 ACTIVE OPERATIONS (\(status.activeOperations.count)):")
            for operation in status.activeOperations {
                print("   • \(operation)")
            }
        }
        
        if !status.queuedOperations.isEmpty {
            print("\n📝 QUEUED OPERATIONS (\(status.queuedOperations.count)):")
            for (index, operation) in status.queuedOperations.enumerated() {
                print("   \(index + 1). \(operation)")
            }
        }
        
        let timeSinceLastRequest = Date().timeIntervalSince(status.lastSyncRequestTime)
        if timeSinceLastRequest < 60 {
            print("\n⏰ Last sync request: \(String(format: "%.1f", timeSinceLastRequest))s ago")
        }
        
        print(String(repeating: "=", count: 50))
    }
    
    /// Test the coordination system
    func testCoordination() async {
        print("\n🧪 Testing Sync Coordination...")
        
        // Request multiple syncs rapidly to test debouncing
        await requestSync(operationID: "test_sync_1") {
            print("   Executing test sync 1")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        await requestSync(operationID: "test_sync_2") {
            print("   Executing test sync 2")
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        await requestSync(operationID: "test_sync_1") { // Duplicate
            print("   This should not execute (duplicate)")
        }
        
        await requestSync(operationID: "test_sync_3", priority: .high) {
            print("   Executing high priority test sync 3")
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        
        // Wait for completion
        while !getSyncStatus().isIdle {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        print("✅ Coordination test completed")
    }
}
#endif