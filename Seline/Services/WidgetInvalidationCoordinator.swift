import Foundation
import WidgetKit

@MainActor
final class WidgetInvalidationCoordinator {
    static let shared = WidgetInvalidationCoordinator()

    private var reloadTask: Task<Void, Never>?

    private init() {}

    func requestReload(reason: String, debounceNanoseconds: UInt64 = 300_000_000) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

#if DEBUG
            print("🧩 WidgetInvalidationCoordinator reload: \(reason)")
#endif
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
