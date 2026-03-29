import Foundation

@MainActor
final class SelineChatOrchestrator {
    weak var threadProvider: SelineChatThreadProviding?

    private let interpreter = SelineChatQuestionInterpreter()
    private let retriever = SelineChatEvidenceRetriever()
    private let synthesizer = SelineChatEvidenceSynthesizer()
    private let answerGenerator = SelineChatAnswerGenerator()

    func send(_ text: String, in threadID: UUID?) -> AsyncThrowingStream<SelineChatStreamEvent, Error> {
        let thread = threadProvider?.thread(id: threadID)
        let activeContext = thread?.activeContext

        return AsyncThrowingStream { continuation in
            let task = Task {
                let frame = interpreter.interpret(text, activeContext: activeContext)

                continuation.yield(
                    .status(
                        title: "Understanding your question…",
                        sourceChips: []
                    )
                )

                let retrieved = await retriever.retrieve(for: frame, activeContext: activeContext)

                continuation.yield(
                    .status(
                        title: "Gathering evidence…",
                        sourceChips: evidenceChips(for: retrieved)
                    )
                )

                let packet = await synthesizer.synthesize(retrieved)

                if let directResponse = answerGenerator.directClarificationOrFailure(for: packet) {
                    let draft = answerGenerator.buildDraft(markdown: directResponse, frame: frame, packet: packet)
                    let payload = answerGenerator.buildPayload(from: draft, packet: packet)
                    continuation.yield(.completed(payload))
                    continuation.finish()
                    return
                }

                continuation.yield(
                    .status(
                        title: "Writing response…",
                        sourceChips: writingChips(for: packet)
                    )
                )

                do {
                    let markdown = try await answerGenerator.streamAnswer(
                        frame: frame,
                        packet: packet,
                        onDelta: { delta in
                            continuation.yield(.textDelta(delta))
                        }
                    )

                    let draft = answerGenerator.buildDraft(markdown: markdown, frame: frame, packet: packet)
                    let payload = answerGenerator.buildPayload(from: draft, packet: packet)
                    continuation.yield(.completed(payload))
                } catch {
                    let fallback = answerGenerator.fallbackMarkdown(for: packet)
                    let draft = answerGenerator.buildDraft(markdown: fallback, frame: frame, packet: packet)
                    let payload = answerGenerator.buildPayload(from: draft, packet: packet)
                    continuation.yield(.completed(payload))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func evidenceChips(for context: SelineChatRetrievedContext) -> [String] {
        var chips: [String] = []
        if !context.emails.isEmpty { chips.append("Emails") }
        if !context.notes.isEmpty { chips.append("Notes") }
        if !context.visits.isEmpty { chips.append("Visits") }
        if !context.receipts.isEmpty { chips.append("Receipts") }
        if !context.people.isEmpty { chips.append("People") }
        if !context.places.isEmpty { chips.append("Places") }
        return Array(chips.prefix(3))
    }

    private func writingChips(for packet: SelineChatEvidencePacket) -> [String] {
        if packet.allowedArtifacts.contains(.emailCards) {
            return ["Emails"]
        }
        if packet.allowedArtifacts.contains(.receiptCards) {
            return ["Receipts"]
        }
        if packet.allowedArtifacts.contains(.placeCards) {
            return ["Places"]
        }
        return ["Grounded"]
    }
}
