import Foundation
import SwiftUI

@MainActor
protocol SelineChatThreadProviding: AnyObject {
    func thread(id: UUID?) -> SelineChatThread?
}

@MainActor
final class SelineChatStore: ObservableObject, SelineChatThreadProviding {
    @MainActor static let shared = SelineChatStore()

    @Published private(set) var threads: [SelineChatThread] = []
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var thinkingState: SelineChatThinkingState?

    private let threadsStorageKey = "selineChatThreads.v2"
    private let lastActiveThreadKey = "selineChatLastActiveThreadID.v2"
    private let orchestrator: SelineChatOrchestrator
    private var sendTask: Task<Void, Never>?

    private init() {
        self.orchestrator = SelineChatOrchestrator()
        loadThreads()
        self.orchestrator.threadProvider = self
    }

    var selectedThread: SelineChatThread? {
        thread(id: selectedThreadID)
    }

    func thread(id: UUID?) -> SelineChatThread? {
        guard let id else { return nil }
        return threads.first(where: { $0.id == id })
    }

    func selectThread(_ id: UUID) {
        selectedThreadID = id
        setLastActiveThreadID(id)
    }

    func beginNewThread() {
        cancelCurrentSend()
        selectedThreadID = nil
        setLastActiveThreadID(nil)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancelCurrentSend()

        let threadID = ensureThread(for: trimmed)
        append(turn: SelineChatTurn(role: .user, text: trimmed), to: threadID)

        let assistantTurnID = UUID()
        append(
            turn: SelineChatTurn(
                id: assistantTurnID,
                role: .assistant,
                text: "",
                isStreaming: true
            ),
            to: threadID
        )
        saveThreads()

        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in self.orchestrator.send(trimmed, in: threadID) {
                    guard !Task.isCancelled else { return }
                    await self.handle(event, assistantTurnID: assistantTurnID, threadID: threadID)
                }
            } catch {
                await self.failAssistantTurn(
                    assistantTurnID: assistantTurnID,
                    threadID: threadID,
                    message: "I couldn't answer that right now. Try again in a moment."
                )
            }
        }
    }

    func cancelCurrentSend() {
        sendTask?.cancel()
        sendTask = nil
        thinkingState = nil

        var didMutate = false
        for index in threads.indices {
            guard let lastIndex = threads[index].turns.indices.last,
                  threads[index].turns[lastIndex].role == .assistant,
                  threads[index].turns[lastIndex].isStreaming else {
                continue
            }

            threads[index].turns[lastIndex].isStreaming = false
            if threads[index].turns[lastIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                threads[index].turns.removeLast()
            }
            threads[index].updatedAt = Date()
            didMutate = true
        }

        if didMutate {
            sortThreads()
            saveThreads()
        }
    }

    private func ensureThread(for prompt: String) -> UUID {
        if let selectedThreadID,
           let index = threads.firstIndex(where: { $0.id == selectedThreadID }) {
            if threads[index].turns.isEmpty {
                threads[index].title = threadTitle(from: prompt)
                threads[index].updatedAt = Date()
                saveThreads()
            }
            return selectedThreadID
        }

        let thread = SelineChatThread(title: threadTitle(from: prompt))
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
        setLastActiveThreadID(thread.id)
        return thread.id
    }

    private func append(turn: SelineChatTurn, to threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].turns.append(turn)
        threads[index].updatedAt = Date()
        sortThreads()
    }

    private func handle(
        _ event: SelineChatStreamEvent,
        assistantTurnID: UUID,
        threadID: UUID
    ) async {
        switch event {
        case .status(let title, let sourceChips):
            thinkingState = SelineChatThinkingState(
                threadID: threadID,
                title: title,
                sourceChips: sourceChips
            )
        case .textDelta(let delta):
            updateAssistantTurn(id: assistantTurnID, in: threadID) { turn in
                turn.text += delta
                turn.isStreaming = true
            }
        case .completed(let payload):
            thinkingState = nil
            if let threadIndex = threads.firstIndex(where: { $0.id == threadID }) {
                threads[threadIndex].activeContext = mergeActiveContext(
                    existing: threads[threadIndex].activeContext,
                    incoming: payload.activeContext
                )
            }
            updateAssistantTurn(id: assistantTurnID, in: threadID) { turn in
                turn.text = payload.primaryText
                turn.assistantPayload = payload
                turn.isStreaming = false
            }
            sendTask = nil
            saveThreads()
        case .failed(let message):
            await failAssistantTurn(
                assistantTurnID: assistantTurnID,
                threadID: threadID,
                message: message
            )
        }
    }

    private func failAssistantTurn(
        assistantTurnID: UUID,
        threadID: UUID,
        message: String
    ) async {
        thinkingState = nil
        updateAssistantTurn(id: assistantTurnID, in: threadID) { turn in
            turn.text = message
            turn.isStreaming = false
        }
        sendTask = nil
        saveThreads()
    }

    private func updateAssistantTurn(
        id: UUID,
        in threadID: UUID,
        mutate: (inout SelineChatTurn) -> Void
    ) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let turnIndex = threads[threadIndex].turns.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&threads[threadIndex].turns[turnIndex])
        threads[threadIndex].updatedAt = Date()
        sortThreads()
    }

    private func sortThreads() {
        threads.sort { $0.updatedAt > $1.updatedAt }
        if let selectedThreadID {
            setLastActiveThreadID(selectedThreadID)
        }
    }

    private func loadThreads() {
        guard let data = UserDefaults.standard.data(forKey: threadsStorageKey) else {
            threads = []
            selectedThreadID = nil
            return
        }

        do {
            let decoded = try JSONDecoder().decode([SelineChatThread].self, from: data)
            threads = decoded.sorted { $0.updatedAt > $1.updatedAt }

            if let lastActive = lastActiveThreadID(),
               threads.contains(where: { $0.id == lastActive }) {
                selectedThreadID = lastActive
            } else {
                selectedThreadID = threads.first?.id
            }
        } catch {
            threads = []
            selectedThreadID = nil
        }
    }

    private func saveThreads() {
        do {
            let data = try JSONEncoder().encode(threads.sorted { $0.updatedAt > $1.updatedAt })
            UserDefaults.standard.set(data, forKey: threadsStorageKey)
        } catch {
            print("Failed to save chat threads: \(error)")
        }
    }

    private func setLastActiveThreadID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: lastActiveThreadKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastActiveThreadKey)
        }
    }

    private func lastActiveThreadID() -> UUID? {
        guard let value = UserDefaults.standard.string(forKey: lastActiveThreadKey) else { return nil }
        return UUID(uuidString: value)
    }

    private func threadTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 36
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func mergeActiveContext(
        existing: SelineChatActiveContext?,
        incoming: SelineChatActiveContext?
    ) -> SelineChatActiveContext? {
        guard existing != nil || incoming != nil else { return nil }
        return SelineChatActiveContext(
            placeAnchor: incoming?.placeAnchor ?? existing?.placeAnchor,
            emailAnchor: incoming?.emailAnchor ?? existing?.emailAnchor,
            episodeAnchor: incoming?.episodeAnchor ?? existing?.episodeAnchor,
            personAnchor: incoming?.personAnchor ?? existing?.personAnchor,
            receiptClusterAnchor: incoming?.receiptClusterAnchor ?? existing?.receiptClusterAnchor
        )
    }
}
