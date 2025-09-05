import Foundation

class NotifiedEmailTracker {
    static let shared = NotifiedEmailTracker()
    private let notifiedEmailIDsKey = "notifiedEmailIDs"

    private init() {}

    func addNotifiedEmail(id: String) {
        var notifiedIDs = getNotifiedEmailIDs()
        notifiedIDs.insert(id)
        UserDefaults.standard.set(Array(notifiedIDs), forKey: notifiedEmailIDsKey)
    }

    func hasBeenNotified(id: String) -> Bool {
        return getNotifiedEmailIDs().contains(id)
    }

    private func getNotifiedEmailIDs() -> Set<String> {
        let ids = UserDefaults.standard.array(forKey: notifiedEmailIDsKey) as? [String] ?? []
        return Set(ids)
    }
}