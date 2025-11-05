import SwiftUI
import Foundation

class DeepLinkHandler: NSObject, ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var shouldShowNoteCreation = false
    @Published var shouldShowEventCreation = false
    @Published var shouldShowReceiptStats = false
    @Published var shouldShowSearch = false
    @Published var shouldShowChat = false
    @Published var shouldOpenMaps = false
    @Published var mapsLatitude: Double? = nil
    @Published var mapsLongitude: Double? = nil
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

        // Handle maps deep link: seline://maps?lat=43.2417461&lon=-79.861607
        if let host = url.host, host == "maps" {
            print("🗺️ Opening maps with coordinates")
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            var lat: Double? = nil
            var lon: Double? = nil

            for item in queryItems {
                if item.name == "lat", let value = item.value {
                    lat = Double(value)
                }
                if item.name == "lon", let value = item.value {
                    lon = Double(value)
                }
            }

            print("🗺️ Maps coordinates: lat=\(lat ?? 0), lon=\(lon ?? 0)")

            DispatchQueue.main.async {
                self.mapsLatitude = lat
                self.mapsLongitude = lon
                self.shouldOpenMaps = true
                self.pendingAction = "maps"
            }
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

        case "viewReceiptStats":
            print("💰 Opening receipt stats")
            DispatchQueue.main.async {
                print("💰 Setting shouldShowReceiptStats = true")
                self.shouldShowReceiptStats = true
                self.pendingAction = "viewReceiptStats"
            }

        case "search":
            print("🔍 Opening search")
            DispatchQueue.main.async {
                print("🔍 Setting shouldShowSearch = true")
                self.shouldShowSearch = true
                self.pendingAction = "search"
            }

        case "chat":
            print("💬 Opening chat")
            DispatchQueue.main.async {
                print("💬 Setting shouldShowChat = true")
                self.shouldShowChat = true
                self.pendingAction = "chat"
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
        case "viewReceiptStats":
            DispatchQueue.main.async {
                print("💰 Triggering receipt stats from pending action")
                self.shouldShowReceiptStats = true
            }
        case "search":
            DispatchQueue.main.async {
                print("🔍 Triggering search from pending action")
                self.shouldShowSearch = true
            }
        case "chat":
            DispatchQueue.main.async {
                print("💬 Triggering chat from pending action")
                self.shouldShowChat = true
            }
        case "maps":
            DispatchQueue.main.async {
                print("🗺️ Triggering maps from pending action")
                self.shouldOpenMaps = true
            }
        default:
            break
        }
    }

    /// Reset navigation state after handling
    func resetNavigationState() {
        shouldShowNoteCreation = false
        shouldShowEventCreation = false
        shouldShowReceiptStats = false
        shouldShowSearch = false
        shouldShowChat = false
        shouldOpenMaps = false
        mapsLatitude = nil
        mapsLongitude = nil
        pendingAction = nil
    }
}

// MARK: - Array Extension for Safe Indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
