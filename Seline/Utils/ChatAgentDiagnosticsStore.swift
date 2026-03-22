import Foundation

struct ChatAgentDiagnosticEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let userMessage: String
    let model: String
    let responseText: String
    let toolTrace: [AgentToolTrace]
    let evidenceBundle: EvidenceBundle
    let usedLiveWeb: Bool
    let shadowResponseText: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        userMessage: String,
        model: String,
        responseText: String,
        toolTrace: [AgentToolTrace],
        evidenceBundle: EvidenceBundle,
        usedLiveWeb: Bool,
        shadowResponseText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.userMessage = userMessage
        self.model = model
        self.responseText = responseText
        self.toolTrace = toolTrace
        self.evidenceBundle = evidenceBundle
        self.usedLiveWeb = usedLiveWeb
        self.shadowResponseText = shadowResponseText
    }
}

@MainActor
final class ChatAgentDiagnosticsStore: ObservableObject {
    static let shared = ChatAgentDiagnosticsStore()

    @Published private(set) var recentEntries: [ChatAgentDiagnosticEntry] = []

    private let defaultsKey = "chat_agent_diagnostics_store"
    private let isEnabledKey = "chat_agent_diagnostics_enabled"
    private let maxEntries = 40

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isEnabledKey) }
    }

    private init() {
        load()
    }

    func append(_ entry: ChatAgentDiagnosticEntry) {
        guard isEnabled else { return }
        recentEntries.insert(entry, at: 0)
        if recentEntries.count > maxEntries {
            recentEntries = Array(recentEntries.prefix(maxEntries))
        }
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([ChatAgentDiagnosticEntry].self, from: data)
        else {
            return
        }
        recentEntries = decoded
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(recentEntries) else { return }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }
}
