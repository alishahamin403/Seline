import Foundation

struct ChatTurnTelemetry: Identifiable, Codable {
    let id: UUID
    let requestID: UUID
    let conversationID: UUID?
    let userMessage: String
    let model: String?
    let startedAt: Date
    let firstTokenLatencyMs: Int?
    let totalLatencyMs: Int?
    let toolLatencyMs: Int
    let toolCount: Int
    let didCancel: Bool
    let staleChunkCount: Int
}

@MainActor
final class ChatTurnTelemetryStore: ObservableObject {
    static let shared = ChatTurnTelemetryStore()

    @Published private(set) var entries: [ChatTurnTelemetry] = []

    private struct ActiveTurn {
        let conversationID: UUID?
        let userMessage: String
        let startedAt: Date
        var firstTokenAt: Date?
    }

    private var activeTurns: [UUID: ActiveTurn] = [:]

    private init() {}

    func begin(requestID: UUID, conversationID: UUID?, userMessage: String) {
        activeTurns[requestID] = ActiveTurn(
            conversationID: conversationID,
            userMessage: userMessage,
            startedAt: Date(),
            firstTokenAt: nil
        )
    }

    func markFirstToken(requestID: UUID, at date: Date?) {
        guard var active = activeTurns[requestID], active.firstTokenAt == nil else { return }
        active.firstTokenAt = date ?? Date()
        activeTurns[requestID] = active
    }

    func finishCompleted(
        requestID: UUID,
        conversationID: UUID?,
        model: String?,
        toolTrace: [AgentToolTrace],
        staleChunkCount: Int
    ) {
        guard let active = activeTurns.removeValue(forKey: requestID) else { return }
        let completedAt = Date()
        let firstTokenLatency = active.firstTokenAt.map { Int($0.timeIntervalSince(active.startedAt) * 1000) }
        let totalLatency = Int(completedAt.timeIntervalSince(active.startedAt) * 1000)
        let toolLatency = toolTrace.reduce(0) { $0 + $1.latencyMs }

        entries.append(
            ChatTurnTelemetry(
                id: UUID(),
                requestID: requestID,
                conversationID: conversationID ?? active.conversationID,
                userMessage: active.userMessage,
                model: model,
                startedAt: active.startedAt,
                firstTokenLatencyMs: firstTokenLatency,
                totalLatencyMs: totalLatency,
                toolLatencyMs: toolLatency,
                toolCount: toolTrace.count,
                didCancel: false,
                staleChunkCount: staleChunkCount
            )
        )
        trimIfNeeded()
    }

    func finishCancelled(
        requestID: UUID,
        conversationID: UUID?,
        staleChunkCount: Int
    ) {
        guard let active = activeTurns.removeValue(forKey: requestID) else { return }
        let cancelledAt = Date()
        let firstTokenLatency = active.firstTokenAt.map { Int($0.timeIntervalSince(active.startedAt) * 1000) }
        let totalLatency = Int(cancelledAt.timeIntervalSince(active.startedAt) * 1000)

        entries.append(
            ChatTurnTelemetry(
                id: UUID(),
                requestID: requestID,
                conversationID: conversationID ?? active.conversationID,
                userMessage: active.userMessage,
                model: nil,
                startedAt: active.startedAt,
                firstTokenLatencyMs: firstTokenLatency,
                totalLatencyMs: totalLatency,
                toolLatencyMs: 0,
                toolCount: 0,
                didCancel: true,
                staleChunkCount: staleChunkCount
            )
        )
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
    }
}
