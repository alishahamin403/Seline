import Foundation

struct SelineChatAgentRunResult {
    let answerMarkdown: String
    let providerState: SelineChatProviderState
    let evidenceBundle: SelineChatEvidenceBundle
    let noAnswerReason: String?
}

@MainActor
final class SelineChatOpenAIResponsesService {
    typealias StatusHandler = @MainActor (_ title: String, _ sourceChips: [String]) -> Void

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-4o-mini"
    private let maxToolRounds = 8

    func run(
        question: String,
        frame: SelineChatQuestionFrame,
        providerState: SelineChatProviderState?,
        recentEvidence: SelineChatEvidenceBundle?,
        toolExecutor: any SelineChatToolExecuting,
        onStatus: StatusHandler? = nil
    ) async throws -> SelineChatAgentRunResult {
        var state = providerState ?? SelineChatProviderState(previousResponseID: nil)
        var evidenceBundle = SelineChatEvidenceBundle(query: question)
        var nextInput: Any = initialInput(
            question: question,
            frame: frame,
            recentEvidence: recentEvidence
        )
        var usedFallbackThreadReset = false

        for _ in 0..<maxToolRounds {
            let response: OpenAIResponseEnvelope
            do {
                response = try await createResponse(
                    input: nextInput,
                    previousResponseID: state.previousResponseID,
                    toolDefinitions: toolExecutor.toolDefinitions(),
                    instructions: instructions(for: frame)
                )
            } catch {
                let description = error.localizedDescription.lowercased()
                if state.previousResponseID != nil,
                   !usedFallbackThreadReset,
                   (description.contains("previous_response_id") || description.contains("not found")) {
                    usedFallbackThreadReset = true
                    state.previousResponseID = nil
                    nextInput = initialInput(
                        question: question,
                        frame: frame,
                        recentEvidence: recentEvidence
                    )
                    continue
                }
                throw error
            }

            state.previousResponseID = response.id

            let functionCalls = response.functionCalls
            if !functionCalls.isEmpty {
                var toolOutputs: [[String: Any]] = []

                for functionCall in functionCalls {
                    if let onStatus {
                        await onStatus(statusTitle(for: functionCall.name), sourceChips(for: functionCall.name))
                    }

                    let startedAt = Date()
                    do {
                        let result = try await toolExecutor.execute(
                            toolName: functionCall.name,
                            argumentsJSON: functionCall.arguments
                        )

                        evidenceBundle = merge(result: result, into: evidenceBundle)
                        toolOutputs.append([
                            "type": "function_call_output",
                            "call_id": functionCall.callID,
                            "output": result.outputJSON
                        ])

                        evidenceBundle.trace.append(
                            SelineChatToolTraceEntry(
                                toolName: functionCall.name,
                                argumentsSummary: summarizeArguments(functionCall.arguments),
                                latencyMS: Int(Date().timeIntervalSince(startedAt) * 1000),
                                resultCount: result.resultCount,
                                evidenceIDs: traceEvidenceIDs(from: result),
                                note: result.note
                            )
                        )
                    } catch {
                        let fallbackOutput = jsonString(["error": error.localizedDescription])
                        toolOutputs.append([
                            "type": "function_call_output",
                            "call_id": functionCall.callID,
                            "output": fallbackOutput
                        ])

                        evidenceBundle.trace.append(
                            SelineChatToolTraceEntry(
                                toolName: functionCall.name,
                                argumentsSummary: summarizeArguments(functionCall.arguments),
                                latencyMS: Int(Date().timeIntervalSince(startedAt) * 1000),
                                resultCount: 0,
                                evidenceIDs: [],
                                note: error.localizedDescription
                            )
                        )
                    }
                }

                nextInput = toolOutputs
                continue
            }

            let answerMarkdown = response.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answerMarkdown.isEmpty {
                return SelineChatAgentRunResult(
                    answerMarkdown: answerMarkdown,
                    providerState: state,
                    evidenceBundle: evidenceBundle,
                    noAnswerReason: evidenceBundle.records.isEmpty && evidenceBundle.citations.isEmpty ? "No grounded records were retrieved." : nil
                )
            }
        }

        return SelineChatAgentRunResult(
            answerMarkdown: "I couldn't finish the reasoning loop cleanly, so I don't have a grounded answer yet.",
            providerState: state,
            evidenceBundle: evidenceBundle,
            noAnswerReason: "The tool loop exceeded its iteration limit."
        )
    }

    private func createResponse(
        input: Any,
        previousResponseID: String?,
        toolDefinitions: [[String: Any]],
        instructions: String
    ) async throws -> OpenAIResponseEnvelope {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.openAIAPIKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "tools": toolDefinitions,
            "tool_choice": "auto",
            "store": true
        ]

        if let previousResponseID, !previousResponseID.isEmpty {
            body["previous_response_id"] = previousResponseID
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SelineChatToolExecutorError.unavailable("Invalid response from OpenAI.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw SelineChatToolExecutorError.unavailable("OpenAI Responses API error \(httpResponse.statusCode): \(payload)")
        }

        do {
            return try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw SelineChatToolExecutorError.unavailable("Failed to decode OpenAI response: \(payload)")
        }
    }

    private func instructions(for frame: SelineChatQuestionFrame) -> String {
        """
        You are Seline, a ChatGPT-like personal assistant for Celine's data.

        Behavior:
        - Answer naturally in concise prose first.
        - Use tools whenever the answer depends on personal data, maps, or live public web data.
        - Prefer personal data before web data.
        - Prefer exact structured records for dates, times, totals, schedules, reservations, and amounts.
        - Use embeddings-backed personal search only as recall support, then hydrate exact records before making specific claims.
        - For broad day or schedule questions, use get_day_overview first.
        - For weekend, trip, or "what did we do / what happened" recap questions tied to a date, person, or location, use get_day_overview for the resolved range first, then use search_personal_data and get_records for exact trip-specific notes, visits, emails, and reservations.
        - For flight, hotel, booking, or itinerary questions, use search_emails and then extract_email_facts if needed.
        - For place, hours, parking, distance, or ETA questions, use search_places, get_place_details, and get_travel_eta.
        - Use web_search only when the answer needs current public information or personal data is insufficient.
        - Never invent facts. If evidence is missing or conflicting, say so plainly.
        - If the user says "last" or "most recent", find the most recent matching evidence, not merely the most recently created generic records for one person.
        - If a follow-up likely refers to prior evidence, reuse the recent record refs provided in the user message.

        Rendering:
        - Keep the main answer clean and human.
        - Mention exact dates and times when grounded.
        - Do not mention tool names in the final answer unless the user asks.

        Current date: \(formattedNow())
        Query time hint: \(frame.timeScope?.description ?? "none")
        """
    }

    private func initialInput(
        question: String,
        frame: SelineChatQuestionFrame,
        recentEvidence: SelineChatEvidenceBundle?
    ) -> [[String: Any]] {
        var sections: [String] = []
        sections.append("User question: \(question)")
        if !frame.entityMentions.isEmpty {
            sections.append("Named entities: \(frame.entityMentions.map(\.value).joined(separator: ", "))")
        }
        if !frame.requestedDomains.isEmpty {
            sections.append("Likely relevant domains: \(frame.requestedDomains.map(\.rawValue).sorted().joined(separator: ", "))")
        }
        if let timeScope = frame.timeScope?.description {
            sections.append("Resolved time hint: \(timeScope)")
        }
        if let interval = frame.timeScope?.interval {
            sections.append("Resolved interval: \(interval.start.ISO8601Format()) to \(interval.end.ISO8601Format())")
        }
        if frame.prefersMostRecent {
            sections.append("The user is asking for the most recent matching occurrence.")
        }
        if frame.isFollowUpLike {
            sections.append("This looks like a follow-up to prior evidence.")
        }
        if !frame.recentContextRefs.isEmpty {
            sections.append("Recent evidence refs you can pass to get_records: \(frame.recentContextRefs.joined(separator: ", "))")
        }
        if !frame.recentContextSummary.isEmpty {
            sections.append("Recent evidence summary:\n\(frame.recentContextSummary.joined(separator: "\n"))")
        } else if let recentEvidence, !recentEvidence.topContextLines.isEmpty {
            sections.append("Recent evidence summary:\n\(recentEvidence.topContextLines.joined(separator: "\n"))")
        }

        let prompt = sections.joined(separator: "\n\n")
        return [[
            "role": "user",
            "content": [[
                "type": "input_text",
                "text": prompt
            ]]
        ]]
    }

    private func merge(
        result: SelineChatToolExecutionResult,
        into bundle: SelineChatEvidenceBundle
    ) -> SelineChatEvidenceBundle {
        var updated = bundle
        updated.records = dedupe(bundle.records + result.records, id: \.id)
        updated.items = dedupe(bundle.items + result.items, id: \.id)
        updated.places = dedupe(bundle.places + result.places, id: \.id)
        updated.citations = dedupe(bundle.citations + result.citations, id: \.url)
        return updated
    }

    private func traceEvidenceIDs(from result: SelineChatToolExecutionResult) -> [String] {
        if !result.records.isEmpty {
            return Array(result.records.prefix(8).map(\.id))
        }
        if !result.places.isEmpty {
            return Array(result.places.prefix(8).map(\.id))
        }
        if !result.citations.isEmpty {
            return Array(result.citations.prefix(8).map(\.url))
        }
        return []
    }

    private func summarizeArguments(_ argumentsJSON: String) -> String {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 220 {
            return trimmed
        }
        return String(trimmed.prefix(220)) + "..."
    }

    private func statusTitle(for toolName: String) -> String {
        switch toolName {
        case "get_day_overview":
            return "Reviewing your day…"
        case "search_personal_data":
            return "Searching your personal data…"
        case "get_records":
            return "Reading exact records…"
        case "search_emails":
            return "Checking your email…"
        case "extract_email_facts":
            return "Extracting travel details…"
        case "search_places":
            return "Looking up places…"
        case "get_place_details":
            return "Checking place details…"
        case "get_travel_eta":
            return "Calculating travel time…"
        case "web_search":
            return "Checking live web data…"
        default:
            return "Reasoning with your data…"
        }
    }

    private func sourceChips(for toolName: String) -> [String] {
        switch toolName {
        case "get_day_overview":
            return ["Events", "Emails", "Visits"]
        case "search_personal_data":
            return ["Personal Data"]
        case "get_records":
            return ["Grounded"]
        case "search_emails", "extract_email_facts":
            return ["Emails"]
        case "search_places", "get_place_details", "get_travel_eta":
            return ["Maps"]
        case "web_search":
            return ["Web"]
        default:
            return []
        }
    }

    private func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func dedupe<T, ID: Hashable>(_ values: [T], id: (T) -> ID) -> [T] {
        var seen = Set<ID>()
        return values.filter { seen.insert(id($0)).inserted }
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    let id: String
    let output: [OpenAIResponseOutputItem]?
    let outputTextRaw: String?

    enum CodingKeys: String, CodingKey {
        case id
        case output
        case outputTextRaw = "output_text"
    }

    var functionCalls: [OpenAIFunctionCall] {
        output?.compactMap { item in
            guard item.type == "function_call",
                  let callID = item.callID,
                  let name = item.name else {
                return nil
            }
            return OpenAIFunctionCall(
                callID: callID,
                name: name,
                arguments: item.arguments ?? "{}"
            )
        } ?? []
    }

    var outputText: String {
        if let outputTextRaw, !outputTextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputTextRaw
        }

        let fragments: [String] = output?
            .filter { $0.type == "message" }
            .flatMap { item in
                item.content?.compactMap { contentItem in
                    switch contentItem.type {
                    case "output_text", "text":
                        return contentItem.text
                    default:
                        return nil
                    }
                } ?? []
            } ?? []

        return fragments.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct OpenAIResponseOutputItem: Decodable {
    let type: String
    let callID: String?
    let name: String?
    let arguments: String?
    let content: [OpenAIResponseContentItem]?

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case name
        case arguments
        case content
    }
}

private struct OpenAIResponseContentItem: Decodable {
    let type: String
    let text: String?
}

private struct OpenAIFunctionCall {
    let callID: String
    let name: String
    let arguments: String
}
