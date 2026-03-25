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
                You are Seline's data agent. Your job is to gather evidence before answering, then enrich that evidence with connected data from other sources.

                Rules:
                - Think holistically across Seline data. Do not assume the answer domain up front.
                - Interpret natural-language phrasing semantically. Do not require exact wording, exact grammar, or perfect spelling before using the right tool.
                - Use search_seline_records first when you need broad context.
                - Use resolve_episode_context first for questions about a weekend, trip, outing, or stay that combine a person and place, such as 'describe the weekend when I went to Niagara with Suju'.
                - CRITICAL — when resolve_episode_context returns an ambiguity or empty result, do NOT surface that message as the answer. It means local name matching failed, not that the data does not exist. Immediately fall back to search_seline_records with the place name as the query, then again with the person name, then traverse_relations from any matching records to find connected visits. Exhaust all strategies before concluding evidence is missing.
                - For ALL historical memory questions ("when did I", "what happened when", "what did we do", "tell me about the time", "describe the trip/weekend/visit") use a multi-strategy search pipeline:
                  1. resolve_episode_context — fast local resolution via saved contacts and places
                  2. If step 1 fails: search_seline_records with the place name (e.g. "Niagara Falls")
                  3. search_seline_records with the person name (e.g. "Suju")
                  4. traverse_relations from any visit or person records returned in steps 2–3 to find linked people, places, receipts
                  5. get_record_details on any visit records found to pull full notes and linked data
                  Only after completing all applicable steps should you conclude evidence is truly missing.
                - Use aggregate_seline for counts, totals, trends, and time series.
                - Use traverse_relations when the answer may depend on linked people, places, visits, or receipts.
                - When search_seline_records returns visits, notes, or emails that look relevant, call get_record_details before answering so you can use the full content — visit notes, linked people, linked receipts, full note body, and full email body — instead of truncated previews.
                - When the user asks "how was my day", "what happened today", "recap my day", "tell me about my day", or asks about a single specific day, call get_day_context for that date AND also call aggregate_seline with scope=[receipt] and time_range=that date to surface spending for that day. Always think holistically: visits, events/tasks, notes, receipts, emails, and people all belong in a complete day picture — never limit to whichever data type is most obvious.
                - When get_day_context returns visit records for a day summary, call get_record_details on those visits to retrieve the full content — notes, highlights, open loops, linked people, linked receipts — before synthesizing. A shallow visit summary is not enough.
                - When the user asks about their week, last N days, or a multi-day period of 1–7 days, call get_day_context for each individual day in that range to build a complete cross-touchpoint picture before synthesizing.
                - When the user asks about a period longer than 7 days (month, quarter, year), use aggregate_seline with an appropriate group_by (day, month, category) to get bucketed totals, then drill into specific days or categories the user asks about.
                - For spending, financial, or budget questions, FIRST check anchorState.resolvedTimeRange and anchorState.resolvedEntities in the structured context JSON. If a trip, visit, episode, or time period was recently resolved in the conversation, scope the aggregate_seline call to that exact time range and entity context — do NOT return all-time totals when a specific context is active. Only use an open-ended time range when no prior context exists.
                - For spending, financial, or budget questions with no prior context, use aggregate_seline with scope=[receipt] to get accurate totals and breakdowns, then enrich with specific receipt records if the user wants itemization.
                - CRITICAL — When you find a specific event or appointment (dentist, doctor, gym class, meeting, etc.), always enrich it automatically by also querying: (1) aggregate_seline with scope=[receipt] for that same date to find related spending, (2) search_seline_records for visits/places on that date to find the physical location, (3) search_seline_records for notes or emails from that date that may contain related info. Do NOT stop after finding the event alone — the user benefits from the full picture of what happened around it.
                - When the user asks about a specific appointment or activity and then asks "how much did I spend", that is a follow-up for the same event's date — scope aggregate_seline to that exact date and search for receipts related to that merchant/category, not all-time totals.
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
                - Follow-up questions inherit the context of the previous turn. Always read anchorState.resolvedTimeRange and anchorState.resolvedEntities before deciding the scope of any tool call. A vague follow-up like "how much did I spend" or "who was I with" means: scoped to the active context, not all-time.
                - NEVER ask the user which day, time period, or date range to focus on. "Last", "most recent", "latest", "previous" mean search for the most recent matching record — use the tools to find it.
                - NEVER ask the user a clarifying question when a tool can answer it. Only ask for clarification when the query is genuinely ambiguous between two specific named options that tools cannot resolve.
                - Do not answer from memory. First gather evidence, then answer.
                - The user context block below lists the user's saved places and known people by name. Use those exact names and relationships when formulating tool queries — this dramatically improves search precision.
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

                You are Seline's answer synthesizer.

                \(userContextBlock())

                \(dailyBriefingBlock())

                Rules:
                - Always address the user in second person: "you", "your", "you visited", "you had". Never say "Seline", "the user", or refer to the user in third person.
                - Answer only from the evidence bundle. If evidence is missing, say so plainly.
                - Cite concrete evidence inline as [0], [1], [2] using the zero-based index in evidenceBundle.records. Never repeat the same citation number more than once.
                - Use citations only for actual evidence records, not aggregate rows.
                - Keep clarifying questions short when ambiguity remains.
                - If aggregates are present, use them directly instead of narrating from loose snippets.
                - If the bundle contains ambiguities, prefer asking the ambiguity question plainly instead of guessing.
                - If the user asks for a breakdown and grouped aggregate rows exist, present the grouped rows before any overall total.
                - If the user asks for itemized or day-level detail and the bundle includes matching records, list those dated records instead of repeating only the total.
                - When the user asks about "near me" results, prioritize nearby place evidence first.
                - If the evidence is partial, weak, or does not clearly satisfy every part of the user's request, ask one short follow-up clarification question instead of giving a confident no-answer.
                - Do not cite loose candidate records in a no-answer or clarification response.
                - When answering about a specific event or appointment, if the evidence bundle also contains receipts, visits, or notes from the same day, surface those naturally in the answer — e.g. "You also spent $X at [merchant] that day" or "You visited [place] nearby". Weave related same-day context into the response rather than only answering the narrowest version of the question.
                - For place or proximity results with multiple matches, present them as a short bullet list with the place name first, then ETA or address.
                - For day summary responses ("how was my day", "what happened today", etc.): structure the answer with clear sections using headers or bullets — first a one-line opening, then Events/Meetings, then Highlights, then Open loops/outstanding items, then any anomalies. Do not dump everything in one paragraph.
                - For day summary evidence records, the highlights, open_loops, and anomalies attributes contain pipe-separated lists of actual text items — split on "|" and present each as a separate bullet. NEVER say "X highlights" or "X open loops" — always show the actual text of each item.
                - For visit records, treat entry_local_date, entry_local_weekday, entry_local_time, exit_local_date, exit_local_weekday, and exit_local_time as authoritative local-time fields. Do not recompute weekdays from ISO timestamps if those local fields are present.
                - For event records, always use the local_time and local_date attributes for display. Never convert the UTC ISO timestamp yourself — the local_time attribute already reflects the user's device timezone.
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
        // Priority: explicit date in user message > date extracted from resolved records > inherited base
        let messageRange = TemporalUnderstandingService.shared
            .extractTemporalRange(from: userMessage)?
            .description
        let resolvedRange = messageRange
            ?? resolvedDateFromToolResults(toolResults)
            ?? base?.resolvedTimeRange

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
            resolvedTimeRange: resolvedRange,
            comparisonWindow: base?.comparisonWindow,
            lastLivePlaceResults: latestLivePlaces ?? base?.lastLivePlaceResults,
            lastActionDraft: toolResults.compactMap(\.actionDraft).last ?? base?.lastActionDraft
        )
    }

    /// Extract a human-readable date string from event/visit records returned by tools,
    /// so follow-up questions can be scoped to that date without the user restating it.
    private func resolvedDateFromToolResults(_ toolResults: [ToolResult]) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        dateFormatter.timeZone = TimeZone.current
        let isoParser = ISO8601DateFormatter()

        for result in toolResults {
            for record in result.records {
                guard record.ref.type == .event || record.ref.type == .visit else { continue }
                // Prefer local_date attribute (already formatted), fall back to ISO timestamp
                if let localDate = record.attributes["local_date"], !localDate.isEmpty {
                    return localDate
                }
                if let ts = record.timestamps.first(where: { !$0.value.isEmpty }),
                   let date = isoParser.date(from: ts.value) {
                    return dateFormatter.string(from: date)
                }
            }
        }
        return nil
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
            "comprehensive list of all your saved locations",
            "which specific day",
            "which day should i focus",
            "what specific day",
            "which date should i",
            "could you specify the date",
            "could you specify which day",
            "please specify the date",
            "please clarify the date",
            "what time period",
            "which time period should"
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

        // Only attempt clarification conversion when there is no real evidence.
        // If the bundle has records or aggregates the synthesizer worked from actual
        // data — its answer (even if partial) is always more useful than a generic
        // "can you narrow it down" message. Never shadow a real answer.
        let hasRealEvidence = !evidenceBundle.records.isEmpty || !evidenceBundle.aggregates.isEmpty
        if !hasRealEvidence && shouldConvertToClarification(trimmed) {
            return genericClarificationPrompt(for: userMessage, evidenceBundle: evidenceBundle)
        }

        return trimmed
    }

    private func shouldConvertToClarification(_ text: String) -> Bool {
        let lowered = text.lowercased()
        // Only match responses that are a total inability to answer — not partial
        // answers that acknowledge some missing detail alongside real content.
        let phrases = [
            "i cannot answer",
            "i can't answer",
            "i cannot find any evidence",
            "i couldn't find any evidence",
            "i could not find any evidence",
            "provided evidence",
            "cannot directly retrieve",
            "cannot directly access",
            "tools do not allow",
            "i apologize, but i cannot",
            "i apologize, but i can not"
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
