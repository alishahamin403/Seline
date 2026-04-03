import Foundation
import WidgetKit

final class WidgetInvalidationCoordinator {
    static let shared = WidgetInvalidationCoordinator()

    private static let appGroupIdentifier = "group.seline"

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

    // MARK: - Widget Location Data (written from service layer for background support)

    /// Write current location to the shared App Group UserDefaults so the widget can read
    /// it immediately after a timeline reload — even when the app is in the background.
    static func writeLocationData(placeName: String, entryTime: Date) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        userDefaults.set(placeName, forKey: "widgetVisitedLocation")
        userDefaults.set(entryTime, forKey: "widgetVisitEntryTime")
        userDefaults.removeObject(forKey: "widgetElapsedTime")
    }

    /// Remove location data from the shared App Group UserDefaults after a visit ends.
    static func clearLocationData() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "widgetVisitedLocation")
        userDefaults.removeObject(forKey: "widgetVisitEntryTime")
        userDefaults.removeObject(forKey: "widgetElapsedTime")
    }
}
