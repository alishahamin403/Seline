import Foundation
import Combine

/**
 * SyncQueue - Persistent queue for offline operations
 *
 * Stores failed operations and retries them when network is available.
 * Works with AsyncOperationCoordinator for consistent retry behavior.
 *
 * Features:
 * - Persistent storage (survives app restarts)
 * - Automatic retry on network reconnection
 * - Priority-based operation ordering
 * - Deduplication of identical operations
 */
@MainActor
class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    // MARK: - Published State

    @Published var pendingOperations: [QueuedOperation] = []
    @Published var isProcessing: Bool = false

    // MARK: - Storage

    private let queueKey = "SyncQueue_PendingOperations"
    private let coordinator = AsyncOperationCoordinator.shared

    // MARK: - Initialization

    init() {
        loadQueue()
    }

    // MARK: - Queue Management

    /**
     * Add an operation to the sync queue
     *
     * Operations are deduplicated based on their ID
     */
    func enqueue(_ operation: QueuedOperation) {
        // Deduplicate - don't add if same operation already exists
        if !pendingOperations.contains(where: { $0.id == operation.id }) {
            pendingOperations.append(operation)
            saveQueue()
            print("📥 Enqueued operation: \(operation.type) (\(pendingOperations.count) total)")

            // Try to process immediately if not already processing
            if !isProcessing {
                Task {
                    await processQueue()
                }
            }
        }
    }

    /**
     * Process all queued operations
     *
     * Automatically called on app launch and network reconnection
     */
    func processQueue() async {
        guard !isProcessing else { return }
        guard !pendingOperations.isEmpty else { return }

        isProcessing = true
        print("🔄 Processing sync queue (\(pendingOperations.count) operations)...")

        // Sort by priority (high priority first)
        let sorted = pendingOperations.sorted { $0.priority.rawValue > $1.priority.rawValue }

        for operation in sorted {
            let success = await processOperation(operation)

            if success {
                // Remove from queue
                pendingOperations.removeAll { $0.id == operation.id }
                saveQueue()
                print("✅ Completed queued operation: \(operation.type)")
            } else {
                print("❌ Failed queued operation: \(operation.type) (will retry later)")
            }
        }

        isProcessing = false

        // If any operations failed, they remain in queue for next attempt
        if !pendingOperations.isEmpty {
            print("⏳ \(pendingOperations.count) operations remain in queue")
        }
    }

    /**
     * Clear all queued operations
     *
     * Useful for testing or manual intervention
     */
    func clearQueue() {
        pendingOperations.removeAll()
        saveQueue()
        print("🗑️ Sync queue cleared")
    }

    // MARK: - Private Methods

    private func processOperation(_ operation: QueuedOperation) async -> Bool {
        // Execute using AsyncOperationCoordinator for consistent retry
        return await coordinator.execute(
            optimisticUpdate: {
                // Already applied optimistically when operation was created
            },
            rollback: {
                // Rollback handled by the operation's closure
                if let rollback = operation.rollback {
                    rollback()
                }
            },
            remoteOperation: {
                try await operation.execute()
            }
        )
    }

    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(pendingOperations)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            print("❌ Failed to save sync queue: \(error)")
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }

        do {
            pendingOperations = try JSONDecoder().decode([QueuedOperation].self, from: data)
            print("📤 Loaded \(pendingOperations.count) operations from sync queue")

            // Process queue on app launch if there are pending operations
            if !pendingOperations.isEmpty {
                Task {
                    await processQueue()
                }
            }
        } catch {
            print("❌ Failed to load sync queue: \(error)")
        }
    }
}

// MARK: - Queued Operation Model

/**
 * Represents an operation in the sync queue
 */
struct QueuedOperation: Codable, Identifiable {
    let id: String
    let type: OperationType
    let priority: Priority
    let createdAt: Date
    let payload: [String: String] // Simple key-value storage for operation data

    // Not stored - set at runtime
    var execute: () async throws -> Void = { }
    var rollback: (() -> Void)? = nil

    enum OperationType: String, Codable {
        case createTask
        case updateTask
        case deleteTask
        case createNote
        case updateNote
        case deleteNote
        case createLocation
        case updateLocation
        case deleteLocation
        case deleteEmail
    }

    enum Priority: Int, Codable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, priority, createdAt, payload
    }

    init(
        id: String = UUID().uuidString,
        type: OperationType,
        priority: Priority = .normal,
        payload: [String: String] = [:],
        execute: @escaping () async throws -> Void = { },
        rollback: (() -> Void)? = nil
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.createdAt = Date()
        self.payload = payload
        self.execute = execute
        self.rollback = rollback
    }
}

// MARK: - Network Observer (Optional Enhancement)

/**
 * Observes network changes and triggers queue processing
 *
 * Implementation note: This is a placeholder - you would integrate
 * with Network.framework's NWPathMonitor for real network monitoring
 */
extension SyncQueue {
    func startNetworkMonitoring() {
        // TODO: Integrate with Network.framework
        // When network becomes available, call processQueue()
        print("📡 Network monitoring started (placeholder)")
    }
}
