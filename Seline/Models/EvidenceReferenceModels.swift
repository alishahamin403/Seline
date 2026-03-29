import Foundation

enum AgentEntityType: String, Codable, Hashable, CaseIterable {
    case email
    case note
    case event
    case location
    case visit
    case person
    case receipt
    case daySummary
}

struct EntityRef: Codable, Hashable, Identifiable {
    let type: AgentEntityType
    let id: String
    let title: String?

    var identifier: String {
        "\(type.rawValue):\(id)"
    }
}
