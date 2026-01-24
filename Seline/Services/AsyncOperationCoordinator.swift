import Foundation
import Combine

/**
 * AsyncOperationCoordinator - Unified async operation handling
 *
 * Provides consistent retry logic, rollback support, and optimistic updates
 * for all CRUD operations across the app.
 *
 * Features:
 * - 3x retry with exponential backoff (inspired by NotesManager)
 * - Automatic rollback on failure
 * - Optimistic updates with sync status tracking
 * - Consistent error handling
 */
@MainActor
class AsyncOperationCoordinator: ObservableObject {
    static let shared = AsyncOperationCoordinator()

    // MARK: - Published State

    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    @Published var lastSyncTime: Date?

    // Track in-flight operations
    private var activeOperations: Set<UUID> = []

    // MARK: - Configuration

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0 // seconds

    // MARK: - Core Operation Methods

    /**
     * Execute an async operation with retry logic and rollback support
     *
     * - Parameters:
     *   - optimisticUpdate: Closure to apply optimistic changes locally
     *   - rollback: Closure to revert optimistic changes on failure
     *   - remoteOperation: Closure that performs the remote operation
     * - Returns: Success status
     */
    func execute<T>(
        optimisticUpdate: () -> Void,
        rollback: () -> Void,
        remoteOperation: @escaping () async throws -> T
    ) async -> Bool {
        let operationId = UUID()
        activeOperations.insert(operationId)
        isSyncing = true
        syncError = nil

        // Apply optimistic update immediately
        optimisticUpdate()

        // Try remote operation with retry
        let result = await executeWithRetry(
            operation: remoteOperation,
            currentAttempt: 1
        )

        activeOperations.remove(operationId)
        isSyncing = activeOperations.isEmpty

        if result.success {
            lastSyncTime = Date()
            return true
        } else {
            // Rollback on failure
            rollback()
            syncError = result.error
            print("❌ Operation failed after \(maxRetries) attempts: \(result.error ?? "Unknown error")")
            return false
        }
    }

    /**
     * Execute an async operation without optimistic updates (traditional approach)
     *
     * Use this for operations where optimistic updates don't make sense
     * (e.g., fetching data, complex operations)
     */
    func executeSync<T>(
        operation: @escaping () async throws -> T
    ) async -> Result<T, Error> {
        let operationId = UUID()
        activeOperations.insert(operationId)
        isSyncing = true
        syncError = nil

        let result = await executeWithRetry(
            operation: operation,
            currentAttempt: 1
        )

        activeOperations.remove(operationId)
        isSyncing = activeOperations.isEmpty

        if result.success, let value = result.value {
            lastSyncTime = Date()
            return .success(value)
        } else {
            syncError = result.error
            return .failure(NSError(
                domain: "AsyncOperationCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: result.error ?? "Unknown error"]
            ))
        }
    }

    // MARK: - Retry Logic

    private func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        currentAttempt: Int
    ) async -> OperationResult<T> {
        do {
            let result = try await operation()
            return OperationResult(success: true, value: result, error: nil)
        } catch {
            if currentAttempt < maxRetries {
                // Exponential backoff: 1s, 2s, 4s
                let delay = baseDelay * pow(2.0, Double(currentAttempt - 1))
                print("⏳ Retrying operation in \(delay)s (attempt \(currentAttempt + 1)/\(maxRetries))")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                return await executeWithRetry(
                    operation: operation,
                    currentAttempt: currentAttempt + 1
                )
            } else {
                return OperationResult(
                    success: false,
                    value: nil,
                    error: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Utility Methods

    /**
     * Clear sync error (useful for dismissing error UI)
     */
    func clearError() {
        syncError = nil
    }

    /**
     * Check if coordinator is currently syncing
     */
    var hasPendingOperations: Bool {
        !activeOperations.isEmpty
    }

    /**
     * Get count of pending operations
     */
    var pendingOperationCount: Int {
        activeOperations.count
    }
}

// MARK: - Result Type

private struct OperationResult<T> {
    let success: Bool
    let value: T?
    let error: String?
}

// MARK: - Sync Status Enum (for Phase 4)

/**
 * Sync status for individual models
 * Used in Phase 4 for optimistic updates
 */
enum SyncStatus: Codable, Equatable {
    case synced         // Successfully synced with server
    case pending        // Waiting to sync
    case syncing        // Currently syncing
    case failed         // Sync failed (will retry)

    var isPending: Bool {
        self == .pending || self == .syncing
    }
}
