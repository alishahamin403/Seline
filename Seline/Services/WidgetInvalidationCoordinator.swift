import Foundation
import WidgetKit

final class WidgetInvalidationCoordinator {
    static let shared = WidgetInvalidationCoordinator()

    @MainActor private var reloadTask: Task<Void, Never>?

    private init() {}

    func requestReload(reason: String, debounceNanoseconds: UInt64 = 300_000_000) {
        Task { @MainActor in
            reloadTask?.cancel()
            reloadTask = Task {
                if debounceNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: debounceNanoseconds)
                }
                guard !Task.isCancelled else { return }

#if DEBUG
                print("🧩 WidgetInvalidationCoordinator reload: \(reason)")
#endif
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
