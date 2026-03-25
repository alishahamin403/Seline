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
    private let userProfileService = UserProfileService.shared
    private let locationsManager = LocationsManager.shared
    private let peopleManager = PeopleManager.shared
    private let emailService = EmailService.shared
    private let taskManager = TaskManager.shared

    private let maxToolRounds = 5

    private init() {}

    func respond(
        turn: AgentTurnInput,
        onSynthesisChunk: ((String) -> Void)? = nil
    ) async -> AgentTurnResult {
        let userMessage = turn.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveSearchEnabled = turn.allowLiveSearch && shouldAllowLiveSearch(for: userMessage)
        let synthesisModel = selectedModel(for: turn)
        // Planning always uses the smarter model — it must follow complex multi-step
        // enrichment instructions reliably regardless of question length or keywords.
        let planningModel = GeminiResponsesService.escalatedChatModel

        do {
            let toolOutcome = try await planningOutcomeWithRetry(
                userMessage: userMessage,
                conversationHistory: turn.conversationHistory,
                anchorState: turn.anchorState,
                model: planningModel,
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
                    model: synthesisModel,
                    onChunk: onSynthesisChunk
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
                model: synthesisModel
            )

            diagnosticsStore.append(
                ChatAgentDiagnosticEntry(
                    userMessage: userMessage,
                    model: synthesisModel,
                    responseText: finalResponse,
                    toolTrace: toolOutcome.toolTrace,
                    evidenceBundle: evidenceBundle,
                    usedLiveWeb: toolOutcome.usedLiveWeb
                )
            )

            return result
        } catch {
            return fallbackResult(for: userMessage, model: synthesisModel, error: error)
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
        let plannerInput = await plannerMessages(
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
    ) async -> [[String: Any]] {
        let memoryContext = await UserMemoryService.shared.getMemoryContext()
        var messages: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's personal intelligence agent. Your job is to build the most complete, connected picture of the user's life before answering — not just find the narrowest fact that technically satisfies the question.

                ## Core philosophy
                Every piece of data in Seline is connected to other data by time, place, person, and category. When you find one thing, you have found a thread — pull it. A receipt connects to a visit connects to a person connects to an event. Never answer from a single data type when cross-referencing multiple types would give the user a richer, more useful answer.

                ## Two-phase approach: Discover → Enrich
                Phase 1 — Discovery: Find the primary answer using the best initial tool(s).
                Phase 2 — Enrichment: Once you have the date, place, person, or event from Phase 1, automatically query the other relevant data types for that same context. Ask yourself: "What else in Seline connects to what I just found?" Then go get it.

                The enrichment phase is NOT optional. It applies to every non-trivial question. Stop only when you have checked all data types that could plausibly be relevant to the resolved context.

                ## Universal enrichment rules (apply automatically, without the user asking)
                - Found an event or appointment → also check: visits/places (where did they go), receipts (what did they spend), notes or emails from that date
                - Found a receipt or spending → also check: what event or activity was happening that day, where were they (visits), who they were with
                - Found a visit to a place → also check: what events were scheduled that day, any receipts from or near that location, who was with them (traverse_relations)
                - Found a person → also check: shared visits, shared events, recent communications, linked receipts
                - Found a note or email → also check: what else happened on that date (events, visits, receipts)
                - Resolved a time range or episode → query ALL data types (events, visits, receipts, notes, emails) for that full range before synthesizing

                ## Temporal context rules
                - For a single specific day: call get_day_context AND aggregate_seline(receipt) AND search_seline_records(visits) for that date
                - For the user's week or last N days (≤7): call get_day_context for each day to build a cross-touchpoint picture
                - For longer periods (month/quarter/year): use aggregate_seline with group_by, then drill into notable days
                - For spending follow-ups: ALWAYS check anchorState.resolvedTimeRange first — if an episode or event date is active, scope to that, never return all-time totals

                ## Episode and memory resolution
                - Use resolve_episode_context first for trip/outing/stay questions combining a person and place
                - If resolve_episode_context fails or returns ambiguity: it means local name matching failed, not that data is missing — immediately try search_seline_records(place name), then search_seline_records(person name), then traverse_relations, then get_record_details
                - For all historical memory questions, exhaust all five strategies before concluding evidence is missing

                ## Record depth
                - When search_seline_records returns visits, notes, or emails, call get_record_details on relevant ones to get full content — truncated previews are not enough
                - When get_day_context returns visits, call get_record_details on those visits before synthesizing

                ## Tool selection
                - aggregate_seline for counts, totals, trends, time series, and cross-type summaries
                - traverse_relations when the answer may depend on linked people, places, visits, or receipts
                - resolve_live_place for named nearby place requests ("Wendys near me")
                - search_nearby_places for category-based nearby requests (clinics, restaurants, gas)
                - find_saved_places_within_eta for saved places within a drive time or minute radius
                - prepare_event_draft / prepare_note_draft / prepare_saved_place_draft for creation requests
                - refresh_inbox_and_get_latest_email + get_email_details for email requests
                - get_current_context when the user asks where they are right now
                - Web search only when live external information is genuinely needed and local tools are insufficient

                ## Context and follow-ups
                - Follow-up questions always inherit the active context — read anchorState.resolvedTimeRange and anchorState.resolvedEntities before deciding scope
                - A vague follow-up ("how much did I spend", "who was I with", "what did I do") means: scoped to the active context, not all-time or all people
                - When continuing a previous answer, reuse entity_refs from structured context instead of re-inferring from loose wording
                - If the user's wording is ambiguous and tools surface multiple plausible entities, ask for clarification instead of silently picking one

                ## Hard constraints
                - Never answer from memory — always gather evidence first
                - Interpret phrasing semantically — do not require exact grammar or spelling to trigger the right tool
                - The user context block below lists saved places and known people by name — use those exact names in tool queries for better search precision
                """
            ),
            inputMessage(
                role: "developer",
                text: userContextBlock()
            ),
            inputMessage(
                role: "developer",
                text: dailyBriefingBlock()
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

        if !memoryContext.isEmpty {
            messages.append(inputMessage(role: "developer", text: memoryContext))
        }

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
        model: String,
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        let priorTurns = conversationHistory.suffix(8).map { message in
            "\(message.isUser ? "User" : "Assistant"): \(message.text)"
        }

        let synthesisInput: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's personal intelligence synthesizer. Your job is to give the user the richest, most connected answer possible from the evidence — not just the narrowest fact they asked for.

                \(userContextBlock())

                \(dailyBriefingBlock())

                ## Synthesis philosophy
                The evidence bundle may contain multiple data types: events, visits, receipts, notes, emails. These are all part of the same life. When synthesizing, look at ALL of them and weave connections naturally into the answer. If the user asked about a dentist appointment and the bundle also has a receipt and a visit from that day, include those — they make the answer more useful and personal. Do not give a one-dimensional answer when multi-dimensional evidence exists.

                ## Voice and style
                - Always address the user in second person: "you", "your", "you visited", "you had". Never say "Seline", "the user", or refer to the user in third person.
                - Be conversational but precise. Lead with the direct answer, then enrich with connected context.
                - Keep clarifying questions short when ambiguity remains.

                ## Citations and evidence
                - Cite concrete evidence inline as [0], [1], [2] using the zero-based index in evidenceBundle.records. Never repeat the same citation number more than once.
                - Use citations only for actual evidence records, not aggregate rows.
                - Answer only from the evidence bundle. If evidence is missing, say so plainly.
                - If the evidence is partial, ask one short follow-up clarification question instead of a confident no-answer.
                - Do not cite loose candidate records in a no-answer or clarification response.

                ## Connected context
                - When the bundle contains receipts, visits, notes, or emails alongside the primary answer, surface them naturally: "You also spent $X at [merchant] that day", "You visited [place] around the same time", "There's a note from that day that mentions..."
                - If aggregates are present, use them directly instead of narrating from loose snippets.
                - If the user asks for a breakdown and grouped aggregate rows exist, present grouped rows before any overall total.
                - If the user asks for itemized detail and matching records exist, list those instead of repeating only the total.

                ## Formatting
                - For day summary responses: structure with clear sections — one-line opening, then Events/Meetings, then Highlights, then Open loops/outstanding items, then Anomalies/Spending. Do not dump everything in one paragraph.
                - For day summary evidence records, highlights/open_loops/anomalies are pipe-separated lists — present each as a separate bullet, not a count.
                - For proximity/nearby results with multiple matches: short bullet list, place name first, then ETA or address.

                ## Dates and times
                - For visit records, use entry_local_date, entry_local_weekday, entry_local_time, exit_local_date, exit_local_weekday, exit_local_time as authoritative. Do not recompute from ISO timestamps.
                - For event records, always use local_time and local_date attributes. Never convert UTC timestamps yourself.
                - Do not invent corrected dates. If the user questions a date, explain the recorded local timestamp from the evidence.
                - If a visit happens just after midnight, you may describe it as early the next morning, but keep the recorded local date unchanged.
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

        let outputText: String
        if let onChunk {
            outputText = try await responsesService.streamSynthesisText(
                model: model,
                input: synthesisInput,
                onChunk: onChunk
            )
        } else {
            let response = try await responsesService.createResponse(
                model: model,
                input: synthesisInput,
                tools: []
            )
            outputText = response.outputText
        }

        if !outputText.isEmpty {
            return normalizedAssistantText(
                outputText,
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
            resolvedEntities: Array(orderedRefs.prefix(8)),
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
        case .email, .note, .event, .location, .visit, .person, .receipt, .nearbyPlace, .daySummary:
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
        let analyticalKeywords = [
            "week", "month", "year", "quarter",
            "summary", "summarize", "overview", "recap",
            "spending", "spent", "expenses", "budget", "financial",
            "compare", "comparison", "trend", "trends", "pattern", "patterns",
            "how much", "how many", "how often",
            "most", "least", "average", "total",
            "analyze", "analysis", "breakdown"
        ]
        let loweredMessage = turn.userMessage.lowercased()
        let isAnalytical = analyticalKeywords.contains { loweredMessage.contains($0) }

        let shouldEscalate = turn.conversationHistory.count >= 8
            || turn.userMessage.count > 160
            || isAnalytical

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

    // MARK: - User context helpers

    private func userContextBlock() -> String {
        var lines: [String] = ["User context:"]

        let profile = userProfileService.profile
        if let name = profile.name, !name.isEmpty {
            lines.append("• Name: \(name)")
        }
        lines.append("• Timezone: \(TimeZone.current.identifier)")
        if !profile.knownFacts.isEmpty {
            lines.append("• Known facts: \(profile.knownFacts.prefix(4).joined(separator: "; "))")
        }
        if !profile.interests.isEmpty {
            lines.append("• Interests: \(profile.interests.prefix(3).joined(separator: ", "))")
        }
        if !profile.preferences.isEmpty {
            lines.append("• Preferences: \(profile.preferences.prefix(3).joined(separator: "; "))")
        }

        let places = locationsManager.savedPlaces.prefix(8)
        if !places.isEmpty {
            lines.append("Saved places (top \(places.count)):")
            for place in places {
                let catLabel = place.category.isEmpty ? "" : " [\(place.category)]"
                lines.append("  - \(place.displayName)\(catLabel): \(place.address)")
            }
        }

        let people = peopleManager.people.prefix(8)
        if !people.isEmpty {
            lines.append("Known people (top \(people.count)):")
            for person in people {
                let rel = person.relationship.rawValue
                lines.append("  - \(person.displayName) (\(rel))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func dailyBriefingBlock() -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d yyyy"
        dateFormatter.timeZone = TimeZone.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.timeZone = TimeZone.current

        var lines: [String] = [
            "Current moment:",
            "• Date: \(dateFormatter.string(from: now))",
            "• Time: \(timeFormatter.string(from: now))",
            "• Timezone: \(TimeZone.current.identifier)"
        ]

        let unread = emailService.inboxEmails.filter { !$0.isRead }.count
        if unread > 0 {
            lines.append("• Unread inbox emails: \(unread)")
        }

        let next24h = now.addingTimeInterval(86_400)
        let upcoming = taskManager.getAllTasksIncludingArchived().filter { task in
            guard !task.isCompleted else { return false }
            let date = task.scheduledTime ?? task.targetDate
            guard let date else { return false }
            return date >= now && date <= next24h
        }.sorted { ($0.scheduledTime ?? $0.targetDate ?? now) < ($1.scheduledTime ?? $1.targetDate ?? now) }

        if !upcoming.isEmpty {
            lines.append("• Upcoming events (next 24h):")
            for task in upcoming.prefix(5) {
                let t = task.scheduledTime ?? task.targetDate
                let timeStr = t.map { timeFormatter.string(from: $0) } ?? ""
                let label = timeStr.isEmpty ? task.title : "\(task.title) at \(timeStr)"
                lines.append("  - \(label)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
