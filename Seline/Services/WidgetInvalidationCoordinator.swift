import Foundation
import WidgetKit

final class WidgetInvalidationCoordinator {
    static let shared = WidgetInvalidationCoordinator()

    private static let appGroupIdentifier = "group.seline"
    // File-based storage for location data — bypasses cfprefsd which rejects cross-process
    // UserDefaults reads for App Groups with the error:
    // "Using kCFPreferencesAnyUser with a container is only allowed for System Containers"
    static let locationFileName = "widget_location.json"

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

    // MARK: - Widget Location Data

    /// Shared payload written to the App Group container as a JSON file.
    /// Defined here and mirrored in SelineWidget.swift (separate target, can't share types).
    struct LocationPayload: Codable {
        let placeName: String
        let entryTime: Date
    }

    private static func locationFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(locationFileName)
    }

    /// Write current location to the App Group shared container as a JSON file.
    /// Uses file I/O instead of UserDefaults to avoid the cfprefsd cross-process rejection.
    static func writeLocationData(placeName: String, entryTime: Date) {
        guard let url = locationFileURL() else { return }
        let payload = LocationPayload(placeName: placeName, entryTime: entryTime)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Delete the location JSON file — widget will show "Not at saved location".
    static func clearLocationData() {
        guard let url = locationFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
