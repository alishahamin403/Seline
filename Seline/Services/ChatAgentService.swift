import Foundation

@MainActor
final class ChatAgentService {
    static let shared = ChatAgentService()

    private struct PlanningContextSnapshot: Encodable {
        let anchorState: ConversationAnchorState?
        let previousEvidenceBundle: EvidenceBundle?
    }

    private struct SynthesisContextSnapshot: Encodable {
        let conversationTail: [String]
        let evidenceBundle: EvidenceBundle
    }

    private let responsesService = GeminiResponsesService.shared
    private let toolRegistry = SelineToolRegistry.shared
    private let diagnosticsStore = ChatAgentDiagnosticsStore.shared

    private let maxToolRounds = 5

    private init() {}

    func respond(turn: AgentTurnInput) async -> AgentTurnResult {
        let userMessage = turn.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveSearchEnabled = turn.allowLiveSearch && shouldAllowLiveSearch(for: userMessage)
        let model = selectedModel(for: turn)

        do {
            let toolOutcome = try await planningOutcomeWithRetry(
                userMessage: userMessage,
                conversationHistory: turn.conversationHistory,
                anchorState: turn.anchorState,
                model: model,
                includeLiveSearch: liveSearchEnabled
            )

            let mergedAnchorState = mergedAnchorState(
                base: turn.anchorState,
                from: toolOutcome.toolResults,
                userMessage: userMessage
            )
            let actionDraft = toolOutcome.toolResults.compactMap(\.actionDraft).last
            let presentation = mergedPresentation(from: toolOutcome.toolResults)
            let evidenceBundle = buildEvidenceBundle(
                from: toolOutcome.toolResults,
                anchorState: mergedAnchorState
            )

            let finalResponse: String
            if let draftResponse = draftAssistantText(
                userMessage: userMessage,
                evidenceBundle: evidenceBundle,
                actionDraft: actionDraft,
                presentation: presentation
            ) {
                finalResponse = draftResponse
            } else if toolOutcome.toolResults.isEmpty,
               let plannerText = sanitizedPlannerText(toolOutcome.plannerText) {
                finalResponse = plannerText
            } else {
                finalResponse = try await synthesizeAnswer(
                    userMessage: userMessage,
                    conversationHistory: turn.conversationHistory,
                    evidenceBundle: evidenceBundle,
                    model: model
                )
            }

            let result = AgentTurnResult(
                assistantText: finalResponse,
                evidenceBundle: evidenceBundle,
                toolTrace: toolOutcome.toolTrace,
                locationInfo: toolOutcome.locationInfo,
                actionDraft: actionDraft,
                presentation: presentation,
                usedLiveWeb: toolOutcome.usedLiveWeb,
                model: model
            )

            diagnosticsStore.append(
                ChatAgentDiagnosticEntry(
                    userMessage: userMessage,
                    model: model,
                    responseText: finalResponse,
                    toolTrace: toolOutcome.toolTrace,
                    evidenceBundle: evidenceBundle,
                    usedLiveWeb: toolOutcome.usedLiveWeb
                )
            )

            return result
        } catch {
            return fallbackResult(for: userMessage, model: model, error: error)
        }
    }

    // MARK: - Planning loop

    private struct ToolPlanningOutcome {
        let toolResults: [ToolResult]
        let toolTrace: [AgentToolTrace]
        let locationInfo: ETALocationInfo?
        let usedLiveWeb: Bool
        let plannerText: String?
    }

    private func runToolPlanningLoop(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState?,
        model: String,
        includeLiveSearch: Bool
    ) async throws -> ToolPlanningOutcome {
        let toolDefinitions = toolRegistry.toolDefinitions(includeLiveSearch: includeLiveSearch)
        let plannerInput = plannerMessages(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            anchorState: anchorState,
            liveSearchEnabled: includeLiveSearch
        )

        var previousResponseId: String?
        var nextInput = plannerInput
        var collectedToolResults: [ToolResult] = []
        var collectedTrace: [AgentToolTrace] = []
        var collectedLocationInfo: ETALocationInfo?
        var usedLiveWeb = false
        var plannerText: String?
        var attemptedForcedFunctionCall = false
        let hasCallableFunctions = toolDefinitions.contains { ($0["type"] as? String) == "function" }

        for _ in 0..<maxToolRounds {
            let response = try await responsesService.createResponse(
                model: model,
                input: nextInput,
                tools: toolDefinitions,
                previousResponseId: previousResponseId
            )
            previousResponseId = response.responseId
            usedLiveWeb = usedLiveWeb || response.usedWebSearch

            guard !response.functionCalls.isEmpty else {
                if !response.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    plannerText = response.outputText
                }

                if collectedToolResults.isEmpty
                    && hasCallableFunctions
                    && !attemptedForcedFunctionCall
                    && sanitizedPlannerText(response.outputText) == nil {
                    attemptedForcedFunctionCall = true
                    let forcedPlannerInput = plannerInput + [
                        inputMessage(
                            role: "developer",
                            text: """
                            Use the available tools now. Do not ask the user to provide evidence that Seline can retrieve itself.
                            If the request is about the user's data, call the best tool instead of replying with missing-evidence text.
                            """
                        )
                    ]
                    let forcedResponse = try await responsesService.createResponse(
                        model: model,
                        input: forcedPlannerInput,
                        tools: toolDefinitions,
                        functionCallingMode: .any
                    )
                    previousResponseId = forcedResponse.responseId
                    usedLiveWeb = usedLiveWeb || forcedResponse.usedWebSearch

                    if !forcedResponse.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        plannerText = forcedResponse.outputText
                    }

                    guard !forcedResponse.functionCalls.isEmpty else {
                        break
                    }

                    nextInput = []
                    for functionCall in forcedResponse.functionCalls {
                        let start = Date()
                        let execution = try await toolRegistry.execute(
                            name: functionCall.name,
                            argumentsJSON: functionCall.argumentsJSON
                        )
                        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000.0)
                        collectedToolResults.append(execution.result)
                        if let locationInfo = execution.locationInfo {
                            collectedLocationInfo = locationInfo
                        }
                        collectedTrace.append(
                            AgentToolTrace(
                                toolName: functionCall.name,
                                argumentsJSON: functionCall.argumentsJSON,
                                resultPreview: toolPreview(for: execution.result),
                                latencyMs: elapsedMs
                            )
                        )

                        nextInput.append([
                            "type": "function_call_output",
                            "call_id": functionCall.callId,
                            "output": try encodedJSONString(execution.result)
                        ])
                    }
                    continue
                }
                break
            }

            nextInput = []
            for functionCall in response.functionCalls {
                let start = Date()
                let execution = try await toolRegistry.execute(
                    name: functionCall.name,
                    argumentsJSON: functionCall.argumentsJSON
                )
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000.0)
                collectedToolResults.append(execution.result)
                if let locationInfo = execution.locationInfo {
                    collectedLocationInfo = locationInfo
                }
                collectedTrace.append(
                    AgentToolTrace(
                        toolName: functionCall.name,
                        argumentsJSON: functionCall.argumentsJSON,
                        resultPreview: toolPreview(for: execution.result),
                        latencyMs: elapsedMs
                    )
                )

                nextInput.append([
                    "type": "function_call_output",
                    "call_id": functionCall.callId,
                    "output": try encodedJSONString(execution.result)
                ])
            }
        }

        return ToolPlanningOutcome(
            toolResults: collectedToolResults,
            toolTrace: collectedTrace,
            locationInfo: collectedLocationInfo,
            usedLiveWeb: usedLiveWeb,
            plannerText: plannerText
        )
    }

    private func plannerMessages(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState?,
        liveSearchEnabled: Bool
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's data agent. Your job is to gather the minimum evidence needed before answering.

                Rules:
                - Think holistically across Seline data. Do not assume the answer domain up front.
                - Interpret natural-language phrasing semantically. Do not require exact wording, exact grammar, or perfect spelling before using the right tool.
                - Use search_seline_records first when you need broad context.
                - Use resolve_episode_context first for questions about a weekend, trip, outing, or stay that combine a person and place, such as 'describe the weekend when I went to Niagara with Suju'.
                - Use aggregate_seline for counts, totals, trends, and time series.
                - Use traverse_relations when the answer may depend on linked people, places, visits, or receipts.
                - When search_seline_records returns visits that look relevant, call get_record_details before answering so you can use visit notes, linked people, and linked receipts instead of only shallow visit summaries.
                - When the user asks you to create an event, call prepare_event_draft.
                - When the user asks you to create a note, call prepare_note_draft.
                - When the user asks for the latest or newest email, call refresh_inbox_and_get_latest_email before answering.
                - Treat natural references to inbox recency, like asking for the latest, newest, most recent, or last email/message, as the same underlying inbox request even if the wording is casual or misspelled.
                - When the user asks for full email details after an email is identified, call get_email_details.
                - When the user asks where they are right now, what their current address is, or what location they are currently at, call get_current_context.
                - For follow-up drill-down questions, prefer reusing entity_refs from the structured context instead of starting with a fresh broad search.
                - If the user asks for a breakdown, itemization, or which days/items make up a total, keep the same entity focus and ask tools for grouped rows or detailed records.
                - For named nearby place requests like "wendys near me", use resolve_live_place first.
                - For broader nearby category requests like clinics, pharmacies, sushi, food, restaurants, gas, or stores near the user, use search_nearby_places so you can show multiple nearby matches.
                - For requests about the user's saved places within a drive time or minute radius from the current location, use find_saved_places_within_eta instead of saying the saved places are inaccessible.
                - If the user refers to a nearby place you already showed with wording like "save that" or "save this one", read anchorState.lastLivePlaceResults and call prepare_saved_place_draft with that exact place_id.
                - When the user wants to save a live place, use prepare_saved_place_draft and never claim it is already saved before the user confirms.
                - Use web search only when live external information is actually needed and local tools are insufficient.
                - When continuing a previous answer, reuse explicit refs from the structured context instead of re-inferring entities from loose wording.
                - If the user's wording is ambiguous and the tools surface multiple plausible entities, ask for clarification instead of silently picking one.
                - Do not answer from memory. First gather evidence, then answer.
                """
            ),
            inputMessage(
                role: "developer",
                text: """
                Conversation state JSON:
                \(planningContextJSON(
                    anchorState: anchorState,
                    previousEvidenceBundle: conversationHistory.reversed().first(where: { !$0.isUser })?.evidenceBundle
                ))

                Live search policy: \(liveSearchEnabled ? "enabled for this turn if needed" : "disabled for this turn")
                """
            )
        ]

        let priorTurns = conversationHistory.suffix(10).map { message in
            inputMessage(role: message.isUser ? "user" : "assistant", text: message.text)
        }
        messages.append(contentsOf: priorTurns)

        if conversationHistory.last?.isUser != true || conversationHistory.last?.text != userMessage {
            messages.append(inputMessage(role: "user", text: userMessage))
        }

        return messages
    }

    // MARK: - Final synthesis

    private func synthesizeAnswer(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        evidenceBundle: EvidenceBundle,
        model: String
    ) async throws -> String {
        let priorTurns = conversationHistory.suffix(8).map { message in
            "\(message.isUser ? "User" : "Assistant"): \(message.text)"
        }

        let synthesisInput: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's answer synthesizer.

                Rules:
                - Answer only from the evidence bundle. If evidence is missing, say so plainly.
                - Cite concrete evidence inline as [0], [1], [2] using the zero-based index in evidenceBundle.records.
                - Use citations only for actual evidence records, not aggregate rows.
                - Keep clarifying questions short when ambiguity remains.
                - If aggregates are present, use them directly instead of narrating from loose snippets.
                - If the bundle contains ambiguities, prefer asking the ambiguity question plainly instead of guessing.
                - If the user asks for a breakdown and grouped aggregate rows exist, present the grouped rows before any overall total.
                - If the user asks for itemized or day-level detail and the bundle includes matching records, list those dated records instead of repeating only the total.
                - When the user asks about "near me" results, prioritize nearby place evidence first.
                - If the evidence is partial, weak, or does not clearly satisfy every part of the user's request, ask one short follow-up clarification question instead of giving a confident no-answer.
                - Do not cite loose candidate records in a no-answer or clarification response.
                - For place or proximity results with multiple matches, present them as a short bullet list with the place name first, then ETA or address.
                - For visit records, treat entry_local_date, entry_local_weekday, entry_local_time, exit_local_date, exit_local_weekday, and exit_local_time as authoritative local-time fields. Do not recompute weekdays from ISO timestamps if those local fields are present.
                - Do not invent corrected dates. If the user questions a day/date, explain the recorded local timestamp/day from the evidence instead of fabricating a new date.
                - If a visit happens just after midnight, you may describe it as early the next morning, but keep the actual recorded local date/weekday unchanged unless the evidence itself says otherwise.
                """
            ),
            inputMessage(
                role: "developer",
                text: """
                Structured context JSON:
                \(synthesisContextJSON(conversationTail: priorTurns, evidenceBundle: evidenceBundle))
                """
            ),
            inputMessage(role: "user", text: userMessage)
        ]

        let response = try await responsesService.createResponse(
            model: model,
            input: synthesisInput,
            tools: []
        )

        if !response.outputText.isEmpty {
            return normalizedAssistantText(
                response.outputText,
                userMessage: userMessage,
                evidenceBundle: evidenceBundle
            )
        }

        if evidenceBundle.records.isEmpty && evidenceBundle.aggregates.isEmpty {
            return "I don’t have enough evidence to answer that confidently."
        }

        return fallbackAnswer(from: evidenceBundle)
    }

    // MARK: - Evidence and anchors

    private func buildEvidenceBundle(
        from toolResults: [ToolResult],
        anchorState: ConversationAnchorState
    ) -> EvidenceBundle {
        var records: [EvidenceRecord] = []
        var aggregates: [ToolAggregate] = []
        var citations: [ToolCitation] = []
        var ambiguities: [ToolAmbiguity] = []
        var seenRecordIds = Set<String>()
        var seenCitationKeys = Set<String>()
        var seenAmbiguityIds = Set<UUID>()

        for result in toolResults {
            for record in result.records where seenRecordIds.insert(record.id).inserted {
                records.append(record)
            }
            aggregates.append(contentsOf: result.aggregates)
            for ambiguity in result.ambiguities where seenAmbiguityIds.insert(ambiguity.id).inserted {
                ambiguities.append(ambiguity)
            }
            for citation in result.citations {
                let key = citation.ref.identifier
                if seenCitationKeys.insert(key).inserted {
                    citations.append(citation)
                }
            }
        }

        return EvidenceBundle(
            records: records,
            aggregates: aggregates,
            citations: citations,
            ambiguities: ambiguities.isEmpty ? nil : ambiguities,
            anchorState: anchorState
        )
    }

    private func mergedAnchorState(
        base: ConversationAnchorState?,
        from toolResults: [ToolResult],
        userMessage: String
    ) -> ConversationAnchorState {
        let temporalDescription = TemporalUnderstandingService.shared
            .extractTemporalRange(from: userMessage)?
            .description ?? base?.resolvedTimeRange

        var orderedRefs: [EntityRef] = base?.resolvedEntities ?? []
        var seen = Set(orderedRefs.map(\.identifier))

        for result in toolResults {
            for record in result.records where shouldCarryForwardAnchor(record.ref) {
                if seen.insert(record.ref.identifier).inserted {
                    orderedRefs.append(record.ref)
                }
            }
        }

        let latestLivePlaces = toolResults.compactMap { $0.presentation?.livePlaceCard }.last?.results

        return ConversationAnchorState(
            resolvedEntities: Array(orderedRefs.prefix(4)),
            resolvedTimeRange: temporalDescription,
            comparisonWindow: base?.comparisonWindow,
            lastLivePlaceResults: latestLivePlaces ?? base?.lastLivePlaceResults,
            lastActionDraft: toolResults.compactMap(\.actionDraft).last ?? base?.lastActionDraft
        )
    }

    private func shouldCarryForwardAnchor(_ ref: EntityRef) -> Bool {
        switch ref.type {
        case .currentContext, .aggregate, .webResult:
            return false
        case .email, .note, .event, .location, .visit, .person, .receipt, .nearbyPlace:
            return true
        }
    }

    // MARK: - Helpers

    private func shouldAllowLiveSearch(for userMessage: String) -> Bool {
        let query = userMessage.lowercased()
        let localDataTerms = [
            "email", "emails", "inbox", "message", "messages",
            "note", "notes", "receipt", "receipts",
            "event", "events", "calendar",
            "visit", "visits", "gym",
            "person", "people",
            "saved place", "saved places", "location", "locations"
        ]
        let explicitWebTerms = [
            "search the web", "look it up", "on the web", "online", "internet",
            "website", "site", "menu", "menus", "reviews", "review", "news"
        ]
        let nearbyTerms = ["near me", "nearby", "open now"]
        let mentionsSavedLocalScope = [
            "saved location", "saved locations", "saved place", "saved places", "my saved"
        ].contains { query.contains($0) }

        let mentionsLocalData = localDataTerms.contains { query.contains($0) }
        let mentionsExplicitWeb = explicitWebTerms.contains { query.contains($0) }
        let mentionsNearby = nearbyTerms.contains { query.contains($0) }

        if mentionsSavedLocalScope && !mentionsExplicitWeb {
            return false
        }

        if mentionsLocalData && !mentionsExplicitWeb && !mentionsNearby {
            return false
        }

        return mentionsNearby || mentionsExplicitWeb
    }

    private func planningOutcomeWithRetry(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState?,
        model: String,
        includeLiveSearch: Bool
    ) async throws -> ToolPlanningOutcome {
        do {
            return try await runToolPlanningLoop(
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                anchorState: anchorState,
                model: model,
                includeLiveSearch: includeLiveSearch
            )
        } catch {
            guard includeLiveSearch else {
                throw error
            }

            return try await runToolPlanningLoop(
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                anchorState: anchorState,
                model: model,
                includeLiveSearch: false
            )
        }
    }

    private func selectedModel(for turn: AgentTurnInput) -> String {
        let shouldEscalate = turn.conversationHistory.count >= 12
            || turn.userMessage.count > 220

        return shouldEscalate ? GeminiResponsesService.escalatedChatModel : GeminiResponsesService.defaultChatModel
    }

    private func inputMessage(role: String, text: String) -> [String: Any] {
        [
            "role": role,
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ]
            ]
        ]
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func planningContextJSON(
        anchorState: ConversationAnchorState?,
        previousEvidenceBundle: EvidenceBundle?
    ) -> String {
        let snapshot = PlanningContextSnapshot(
            anchorState: anchorState,
            previousEvidenceBundle: previousEvidenceBundle
        )
        return (try? encodedJSONString(snapshot)) ?? "{}"
    }

    private func synthesisContextJSON(
        conversationTail: [String],
        evidenceBundle: EvidenceBundle
    ) -> String {
        let snapshot = SynthesisContextSnapshot(
            conversationTail: conversationTail,
            evidenceBundle: evidenceBundle
        )
        return (try? encodedJSONString(snapshot)) ?? "{}"
    }

    private func toolPreview(for result: ToolResult) -> String {
        if let actionDraft = result.actionDraft {
            return "Draft: \(actionDraft.type.rawValue)"
        }
        if let firstAggregate = result.aggregates.first {
            return "\(firstAggregate.title) (\(firstAggregate.rows.count) rows)"
        }
        if let firstRecord = result.records.first {
            return "\(firstRecord.title)"
        }
        if let ambiguity = result.ambiguities.first {
            return ambiguity.question
        }
        return "No output"
    }

    private func fallbackResult(for userMessage: String, model: String, error: Error) -> AgentTurnResult {
        _ = error
        let message = genericClarificationPrompt(
            for: userMessage,
            evidenceBundle: EvidenceBundle(
                records: [],
                aggregates: [],
                citations: [],
                ambiguities: nil,
                anchorState: nil
            )
        )
        let evidenceBundle = EvidenceBundle(
            records: [],
            aggregates: [],
            citations: [],
            ambiguities: nil,
            anchorState: ConversationAnchorState(
                resolvedEntities: [],
                resolvedTimeRange: TemporalUnderstandingService.shared.extractTemporalRange(from: userMessage)?.description,
                comparisonWindow: nil
            )
        )
        diagnosticsStore.append(
            ChatAgentDiagnosticEntry(
                userMessage: userMessage,
                model: model,
                responseText: message,
                toolTrace: [],
                evidenceBundle: evidenceBundle,
                usedLiveWeb: false
            )
        )
        return AgentTurnResult(
            assistantText: message,
            evidenceBundle: evidenceBundle,
            toolTrace: [],
            locationInfo: nil,
            actionDraft: nil,
            presentation: nil,
            usedLiveWeb: false,
            model: model
        )
    }

    private func fallbackAnswer(from evidenceBundle: EvidenceBundle) -> String {
        if let ambiguity = evidenceBundle.ambiguities?.first {
            return formattedAmbiguityText(ambiguity)
        }

        if let ambiguity = evidenceBundle.aggregates.first?.summary, evidenceBundle.records.isEmpty {
            return ambiguity
        }

        if evidenceBundle.records.isEmpty && evidenceBundle.aggregates.isEmpty {
            return "I don’t have enough matching evidence to answer that confidently."
        }

        if let aggregate = evidenceBundle.aggregates.first {
            let rows = aggregate.rows.prefix(6).map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            return "\(aggregate.title)\n\(rows)"
        }

        let lines = evidenceBundle.records.prefix(5).enumerated().map { index, record in
            "[\(index)] \(record.title): \(record.summary)"
        }
        return lines.joined(separator: "\n")
    }

    private func sanitizedPlannerText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let lowSignalPhrases = [
            "please provide me with the evidence",
            "i need the evidence",
            "because the evidence is missing",
            "based on the evidence provided",
            "i couldn’t complete that request cleanly",
            "i couldn't complete that request cleanly",
            "try asking again",
            "more specificity",
            "narrow the time",
            "narrow the place",
            "narrow the person",
            "be more specific",
            "cannot directly retrieve",
            "cannot directly access",
            "tools do not allow",
            "provided evidence",
            "comprehensive list of all your saved locations"
        ]

        if lowSignalPhrases.contains(where: { lowered.contains($0) }) {
            return nil
        }

        return trimmed
    }

    private func normalizedAssistantText(
        _ text: String,
        userMessage: String,
        evidenceBundle: EvidenceBundle
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        if shouldConvertToClarification(trimmed) {
            return genericClarificationPrompt(for: userMessage, evidenceBundle: evidenceBundle)
        }

        return trimmed
    }

    private func shouldConvertToClarification(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = [
            "i cannot answer",
            "i can't answer",
            "i cannot find any evidence",
            "i couldn't find any evidence",
            "i could not find any evidence",
            "there is no information",
            "there's no information",
            "provided evidence",
            "cannot directly retrieve",
            "cannot directly access",
            "tools do not allow",
            "do not have information",
            "don't have information",
            "i apologize, but i cannot",
            "i apologize, but i can not",
            "no information about",
            "no evidence of"
        ]

        return phrases.contains(where: { lowered.contains($0) })
    }

    private func genericClarificationPrompt(
        for userMessage: String,
        evidenceBundle: EvidenceBundle
    ) -> String {
        if let ambiguity = evidenceBundle.ambiguities?.first {
            return formattedAmbiguityText(ambiguity)
        }

        let loweredMessage = userMessage.lowercased()
        let recordTypes = Set(evidenceBundle.records.map(\.ref.type))

        if loweredMessage.contains("saved location") || loweredMessage.contains("saved place") || loweredMessage.contains("proximity") {
            return "I need one more constraint to narrow that down cleanly. Do you want me to filter by a saved folder, a type of place, or a wider drive-time range?"
        }

        if loweredMessage.contains("near me") || loweredMessage.contains("nearby") {
            return "I found related nearby results, but I’m not confident which one you mean yet. Do you want the closest one, a specific address, or a tighter category?"
        }

        if recordTypes.contains(.visit) || recordTypes.contains(.person) || loweredMessage.contains("with ") {
            return "I found some related matches, but not enough to answer confidently. Can you narrow it by the exact place, person, or rough date range?"
        }

        if recordTypes.contains(.location) {
            return "I found some related places, but not enough to be sure which one you want. Can you narrow it by exact place, folder, or travel time?"
        }

        return "I’m not confident I have the exact match yet. Can you narrow it by place, person, folder, or date range?"
    }

    private func mergedPresentation(from toolResults: [ToolResult]) -> AgentPresentation? {
        var eventDraftCard: [EventCreationInfo]?
        var noteDraftCard: NoteDraftInfo?
        var emailPreviewCard: EmailPreviewInfo?
        var livePlaceCard: LivePlacePreviewInfo?

        for result in toolResults {
            if let eventDraft = result.presentation?.eventDraftCard {
                eventDraftCard = eventDraft
            }
            if let noteDraft = result.presentation?.noteDraftCard {
                noteDraftCard = noteDraft
            }
            if let emailPreview = result.presentation?.emailPreviewCard {
                emailPreviewCard = emailPreview
            }
            if let livePlace = result.presentation?.livePlaceCard {
                livePlaceCard = livePlace
            }
        }

        guard eventDraftCard != nil || noteDraftCard != nil || emailPreviewCard != nil || livePlaceCard != nil else {
            return nil
        }

        return AgentPresentation(
            eventDraftCard: eventDraftCard,
            noteDraftCard: noteDraftCard,
            emailPreviewCard: emailPreviewCard,
            livePlaceCard: livePlaceCard
        )
    }

    private func draftAssistantText(
        userMessage: String,
        evidenceBundle: EvidenceBundle,
        actionDraft: AgentActionDraft?,
        presentation: AgentPresentation?
    ) -> String? {
        if let ambiguity = evidenceBundle.ambiguities?.first {
            return formattedAmbiguityText(ambiguity)
        }

        if let actionDraft {
            switch actionDraft.type {
            case .createEvent:
                let count = actionDraft.eventDrafts?.count ?? 0
                return count == 1
                    ? "I drafted the event details. Confirm if this looks right."
                    : "I drafted \(count) events. Confirm the ones you want to create."
            case .createNote:
                return "I drafted the note. Confirm and I’ll open it ready for final edits."
            case .latestEmail:
                return "Here’s your latest email."
            case .saveLocation:
                if let folder = actionDraft.placeDraft?.folderName, !folder.isEmpty {
                    return "I found the exact address. Confirm if you want me to save it to \(folder)."
                }
                return "I found the exact address. Confirm if you want me to save it, then pick a folder."
            }
        }

        if let livePlace = presentation?.livePlaceCard,
           let selected = livePlace.results.first(where: { $0.id == livePlace.selectedPlaceId }) ?? livePlace.results.first {
            if selected.types.contains("current_location") {
                return "You’re currently at \(selected.address). Tap the card or map to view location details."
            }

            if livePlace.results.count > 1 {
                return "I found nearby matches for \(selected.name). Tap a place or map pin to view details, or tell me which address you want."
            }

            return "I found \(selected.name) at \(selected.address). Tap the card or map to view details."
        }

        if presentation?.emailPreviewCard != nil {
            return "Here’s the email I found."
        }

        if presentation?.noteDraftCard != nil {
            return "I drafted a note for you."
        }

        if presentation?.eventDraftCard != nil {
            return "I drafted the event details."
        }

        _ = userMessage
        return nil
    }

    private func formattedAmbiguityText(_ ambiguity: ToolAmbiguity) -> String {
        let options = ambiguity.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)

        guard !options.isEmpty else {
            return ambiguity.question
        }

        let loweredQuestion = ambiguity.question.lowercased()
        let intro: String
        if loweredQuestion.contains("different nearby address") || loweredQuestion.contains("which one") {
            intro = "I found a few nearby matches. Tell me which one you want, or tap one below:"
        } else {
            intro = ambiguity.question
        }

        let bulletList = options.map { "- \($0)" }.joined(separator: "\n")
        return "\(intro)\n\n\(bulletList)"
    }
}
