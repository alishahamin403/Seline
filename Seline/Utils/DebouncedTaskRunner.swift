import Foundation

@MainActor
final class DebouncedTaskRunner {
    private var task: Task<Void, Never>?

    func schedule(
        delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            operation()
        }
    }

    func scheduleAsync(
        delay: TimeInterval,
        operation: @escaping @MainActor () async -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
