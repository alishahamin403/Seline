import SwiftUI
import Foundation

class DeepLinkHandler: NSObject, ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var shouldShowNoteCreation = false
    @Published var shouldShowEventCreation = false
    @Published var pendingAction: String? = nil

    private override init() {
        super.init()
    }

    /// Handle URL deep links from the app (e.g., from widget buttons)
    func handleURL(_ url: URL) {
        print("🔗 Deep link received: \(url.absoluteString)")
        print("🔗 URL scheme: \(url.scheme ?? "nil")")
        print("🔗 URL host: \(url.host ?? "nil")")
        print("🔗 URL path: \(url.path)")
        print("🔗 URL pathComponents: \(url.pathComponents)")

        guard url.scheme == "seline" else {
            print("⚠️ Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }

        // Parse the URL: seline://action/createNote or seline://action/createEvent
        // The URL format seline://action/createNote parses as:
        // - host: "action"
        // - path: "/createNote"

        guard let host = url.host, host == "action" else {
            print("⚠️ Invalid URL host. Expected 'action', got: \(url.host ?? "nil")")
            return
        }

        // Extract the action from the path (remove leading /)
        let pathWithoutSlash = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        print("🔗 Detected action: \(pathWithoutSlash)")

        switch pathWithoutSlash {
        case "createNote":
            print("📝 Opening note creation sheet")
            DispatchQueue.main.async {
                print("📝 Setting shouldShowNoteCreation = true")
                self.shouldShowNoteCreation = true
                self.pendingAction = "createNote"
            }

        case "createEvent":
            print("📅 Opening event creation popup")
            DispatchQueue.main.async {
                print("📅 Setting shouldShowEventCreation = true")
                self.shouldShowEventCreation = true
                self.pendingAction = "createEvent"
            }

        default:
            print("⚠️ Unknown action: \(pathWithoutSlash)")
        }
    }

    /// Check if there's a pending action and trigger it
    func processPendingAction() {
        guard let action = pendingAction else { return }

        print("🔗 Processing pending action: \(action)")

        switch action {
        case "createNote":
            DispatchQueue.main.async {
                print("📝 Triggering note creation from pending action")
                self.shouldShowNoteCreation = true
            }
        case "createEvent":
            DispatchQueue.main.async {
                print("📅 Triggering event creation from pending action")
                self.shouldShowEventCreation = true
            }
        default:
            break
        }
    }

    /// Reset navigation state after handling
    func resetNavigationState() {
        shouldShowNoteCreation = false
        shouldShowEventCreation = false
        pendingAction = nil
    }
}

// MARK: - Array Extension for Safe Indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
