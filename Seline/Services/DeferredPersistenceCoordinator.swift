import Foundation

final class DeferredPersistenceCoordinator {
    static let shared = DeferredPersistenceCoordinator()

    private let workQueue = DispatchQueue(label: "com.seline.deferred-persistence.work", qos: .utility)
    private let stateQueue = DispatchQueue(label: "com.seline.deferred-persistence.state")
    private var pendingWorkItems: [String: DispatchWorkItem] = [:]

    private init() {}

    func schedule(
        id: String,
        delay: TimeInterval = 0.15,
        operation: @escaping () -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }

            self.pendingWorkItems[id]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                operation()
                self?.stateQueue.async {
                    self?.pendingWorkItems[id] = nil
                }
            }

            self.pendingWorkItems[id] = workItem
            self.workQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
}
