import SwiftUI
import Foundation

class DeepLinkHandler: NSObject, ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var shouldShowNoteCreation = false
    @Published var shouldShowEventCreation = false

    private override init() {
        super.init()
    }

    /// Handle URL deep links from the app (e.g., from widget buttons)
    func handleURL(_ url: URL) {
        print("🔗 Deep link received: \(url.absoluteString)")

        guard url.scheme == "seline" else {
            print("⚠️ Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }

        // Parse the URL: seline://action/createNote or seline://action/createEvent
        let components = url.pathComponents

        if components.count >= 2 && components[1] == "action" {
            let action = components[safe: 2] ?? ""

            switch action {
            case "createNote":
                print("📝 Opening note creation")
                DispatchQueue.main.async {
                    self.shouldShowNoteCreation = true
                }

            case "createEvent":
                print("📅 Opening event creation")
                DispatchQueue.main.async {
                    self.shouldShowEventCreation = true
                }

            default:
                print("⚠️ Unknown action: \(action)")
            }
        } else {
            print("⚠️ Invalid URL format: \(url.absoluteString)")
        }
    }

    /// Reset navigation state after handling
    func resetNavigationState() {
        shouldShowNoteCreation = false
        shouldShowEventCreation = false
    }
}

// MARK: - Array Extension for Safe Indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
