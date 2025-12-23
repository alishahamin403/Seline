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
    @Published var shouldOpenReceipts = false
    @Published var shouldOpenTimeline = false
    @Published var shouldOpenHome = false
    @Published var mapsLatitude: Double? = nil
    @Published var mapsLongitude: Double? = nil
    @Published var pendingAction: String? = nil

    private override init() {
        super.init()
    }

    /// Handle URL deep links from the app (e.g., from widget buttons)
    func handleURL(_ url: URL) {
        guard url.scheme == "seline" else {
            print("⚠️ Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }

        // Handle maps deep link: seline://maps?lat=43.2417461&lon=-79.861607
        if let host = url.host, host == "maps" {
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

        switch pathWithoutSlash {
        case "createNote":
            DispatchQueue.main.async {
                self.shouldShowNoteCreation = true
                self.pendingAction = "createNote"
            }

        case "createEvent":
            DispatchQueue.main.async {
                self.shouldShowEventCreation = true
                self.pendingAction = "createEvent"
            }

        case "viewReceiptStats":
            DispatchQueue.main.async {
                self.shouldShowReceiptStats = true
                self.pendingAction = "viewReceiptStats"
            }

        case "search":
            DispatchQueue.main.async {
                self.shouldShowSearch = true
                self.pendingAction = "search"
            }

        case "chat":
            DispatchQueue.main.async {
                self.shouldShowChat = true
                self.pendingAction = "chat"
            }

        case "receipts":
            DispatchQueue.main.async {
                self.shouldOpenReceipts = true
                self.pendingAction = "receipts"
            }

        case "timeline":
            DispatchQueue.main.async {
                self.shouldOpenTimeline = true
                self.pendingAction = "timeline"
            }

        case "home":
            DispatchQueue.main.async {
                self.shouldOpenHome = true
                self.pendingAction = "home"
            }

        default:
            print("⚠️ Unknown action: \(pathWithoutSlash)")
        }
    }

    /// Check if there's a pending action and trigger it
    func processPendingAction() {
        guard let action = pendingAction else { return }

        switch action {
        case "createNote":
            DispatchQueue.main.async {
                self.shouldShowNoteCreation = true
            }
        case "createEvent":
            DispatchQueue.main.async {
                self.shouldShowEventCreation = true
            }
        case "viewReceiptStats":
            DispatchQueue.main.async {
                self.shouldShowReceiptStats = true
            }
        case "search":
            DispatchQueue.main.async {
                self.shouldShowSearch = true
            }
        case "chat":
            DispatchQueue.main.async {
                self.shouldShowChat = true
            }
        case "maps":
            DispatchQueue.main.async {
                self.shouldOpenMaps = true
            }
        case "receipts":
            DispatchQueue.main.async {
                self.shouldOpenReceipts = true
            }
        case "timeline":
            DispatchQueue.main.async {
                self.shouldOpenTimeline = true
            }
        case "home":
            DispatchQueue.main.async {
                self.shouldOpenHome = true
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
        shouldOpenReceipts = false
        shouldOpenTimeline = false
        shouldOpenHome = false
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
