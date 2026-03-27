import Foundation

@MainActor
final class ChatAgentService {
    static let shared = ChatAgentService()

    private struct SynthesisContextSnapshot: Encodable {
        let conversationTail: [String]
        let sessionSnapshot: ConversationSessionSnapshot?
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

    // MARK: - Intent Router types

    private struct IntentRouterPlan {
        struct ToolCall {
            let name: String
            let argsJSON: String
        }
        let synthesisModel: String
        let primaryToolCalls: [ToolCall]
        let needsEnrichment: Bool
    }

    private init() {}

    func respond(
        turn: AgentTurnInput,
        onToolDispatch: (([String]) -> Void)? = nil,
        onSynthesisStart: (() -> Void)? = nil,
        onSynthesisChunk: ((String) -> Void)? = nil
    ) async -> AgentTurnResult {
        let userMessage = turn.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveSearchEnabled = turn.allowLiveSearch && shouldAllowLiveSearch(for: userMessage)
        // Default synthesis model used only if the router flow throws before returning one
        var synthesisModel = selectedModel(for: turn)

        do {
            try Task.checkCancellation()
            let routerResult = try await runIntentRouterFlow(
                userMessage: userMessage,
                conversationHistory: turn.conversationHistory,
                anchorState: turn.anchorState,
                sessionSnapshot: turn.sessionSnapshot,
                includeLiveSearch: liveSearchEnabled,
                onToolDispatch: onToolDispatch
            )
            try Task.checkCancellation()
            let toolOutcome = routerResult.outcome
            synthesisModel = routerResult.synthesisModel

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
                onSynthesisStart?()
                finalResponse = draftResponse
            } else {
                onSynthesisStart?()
                finalResponse = try await synthesizeAnswer(
                    userMessage: userMessage,
                    conversationHistory: turn.conversationHistory,
                    sessionSnapshot: turn.sessionSnapshot,
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
        } catch is CancellationError {
            return AgentTurnResult(
                assistantText: "",
                evidenceBundle: EvidenceBundle(
                    records: [],
                    aggregates: [],
                    citations: [],
                    ambiguities: nil,
                    anchorState: turn.anchorState
                ),
                toolTrace: [],
                locationInfo: nil,
                actionDraft: nil,
                presentation: nil,
                usedLiveWeb: false,
                model: synthesisModel
            )
        } catch {
            return fallbackResult(for: userMessage, model: synthesisModel, error: error)
        }
    }

    // MARK: - Intent Router

    /// Single fast LLM call that classifies intent, selects pillars, and lists all primary tools to
    /// call in parallel. Returns nil on parse failure so the caller can fall back to the planner loop.
    private func makeIntentPlan(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState?,
        sessionSnapshot: ConversationSessionSnapshot?,
        liveSearchEnabled: Bool
    ) async -> IntentRouterPlan? {
        let cal = Calendar.current
        let now = Date()
        let df: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let today = df.string(from: now)

        // Pre-calculate this week's dates (Mon–today) so the LLM never has to do date math
        let weekdayIndex = cal.component(.weekday, from: now)   // 1=Sun … 7=Sat
        let daysFromMonday = (weekdayIndex + 5) % 7             // 0=Mon … 6=Sun
        let weekDates: [String] = (0...daysFromMonday).compactMap { offset in
            cal.date(byAdding: .day, value: -(daysFromMonday - offset), to: now).map { df.string(from: $0) }
        }
        let weekDatesListed = weekDates.map { "  - \($0)" }.joined(separator: "\n")

        let anchorJSON = (try? encodedJSONString(anchorState)) ?? "null"
        let historyTail = conversationHistory.suffix(4)
            .map { "\($0.isUser ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")

        let routerInput: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's intent router. Analyze the user message and output a JSON dispatch plan describing exactly which data tools to call in parallel.

                Today: \(today)
                This week's dates (Monday → today, use these exact strings in date_query args):
                \(weekDatesListed)
                Recent conversation:
                \(historyTail.isEmpty ? "(none)" : historyTail)
                Prior anchor state: \(anchorJSON)
                \(sessionMemoryBlock(snapshot: sessionSnapshot, currentQuery: userMessage, conversationHistory: conversationHistory))
                Live search allowed: \(liveSearchEnabled)

                === TOOL SCHEMAS ===
                Seline (personal data):
                  get_day_context          {"date_query": "YYYY-MM-DD"}
                  search_seline_records    {"query": "...", "scopes": ["visit"|"email"|"note"|"receipt"|"event"|"person"|"location"], "time_range": "YYYY-MM-DD"}
                  aggregate_seline         {"metric": "total_spend"|"visit_count"|"event_count", "filters": {"scopes": [...], "time_range": "YYYY-MM-DD"}, "group_by": "day"|"category"|"place"}
                  resolve_episode_context  {"query": "..."}  — person+place+time episodes only
                  get_current_context      {}
                  refresh_inbox_and_get_latest_email {}
                Maps (location):
                  search_nearby_places     {"query": "category or name near me"}
                  resolve_live_place       {"query": "specific named place"}
                  find_saved_places_within_eta {"eta_minutes": N}
                Actions (never in primaryTools):
                  prepare_event_draft, prepare_note_draft, get_record_details, traverse_relations

                === DISPATCH RULES ===
                Pillars:
                  • "seline" — questions about the user's personal data (day, events, receipts, emails, visits, notes, people)
                  • "maps"   — questions about places nearby, navigation, or finding specific locations
                  • "web"    — general knowledge not in Seline (news, business info, etc.)

                synthesisModel:
                  "gemini-2.5-flash"      — day overviews, week/month recaps, spending analysis, anything multi-source or complex
                  "gemini-2.5-flash-lite" — simple single-record lookups, yes/no questions, short factual answers

                RELATIVE DATE RESOLUTION — resolve before dispatching any tools:
                  "today" → \(today)
                  "yesterday" → subtract 1 day from today
                  "1 year ago" / "this time last year" → subtract 365 days from today
                  "last [month name]" → first day of that month in the most recent occurrence
                  "on my birthday" / named occasions → use anchor state if available, otherwise ask
                  Always emit the resolved YYYY-MM-DD in tool args, never vague strings.

                SINGLE DAY rule — apply for "how's my day", "what happened today", "recap today", "how was my day", "how am I doing today",
                  AND for any specific past date question ("what happened on March 3", "tell me about last Tuesday", "1 year ago today"):
                  Resolve the date first (see RELATIVE DATE RESOLUTION above), then include ALL SIX tools:
                    get_day_context(date_query: "YYYY-MM-DD")
                    search_seline_records(query: "visits YYYY-MM-DD", scopes: ["visit"], time_range: "YYYY-MM-DD")
                    aggregate_seline(metric: "total_spend", filters: {scopes: ["receipt"], time_range: "YYYY-MM-DD"})
                    search_seline_records(query: "emails YYYY-MM-DD", scopes: ["email"], time_range: "YYYY-MM-DD")
                    search_seline_records(query: "notes YYYY-MM-DD", scopes: ["note"], time_range: "YYYY-MM-DD")
                    search_seline_records(query: "journal entry YYYY-MM-DD", scopes: ["note"], time_range: "YYYY-MM-DD")
                  Set needsEnrichment: true for ALL single-day queries — this pulls visit notes and linked people automatically.
                  Set synthesisModel: "gemini-2.5-flash" for all single-day queries.

                MULTI-DAY rule — apply for "this week", "last week", "past N days", "how's my week", "week so far", "last few days":
                  Emit ONE get_day_context call PER DAY using the exact dates from "This week's dates" above.
                  Do NOT use vague strings like "this week" or "week so far" as date_query — use the exact YYYY-MM-DD strings listed above.
                  ALSO include ONE aggregate_seline call for spending and ONE search_seline_records for emails.
                  Example using the week dates listed above:
                    { "name": "get_day_context", "args": { "date_query": "<first date from list>" } },
                    ... (one per date in the list) ...,
                    { "name": "aggregate_seline", "args": { "metric": "total_spend", "filters": { "scopes": ["receipt"] }, "group_by": "day" } },
                    { "name": "search_seline_records", "args": { "query": "emails this week", "scopes": ["email"] } }
                  Set needsEnrichment: true and synthesisModel: "gemini-2.5-flash" for all multi-day queries.

                CROSS-PILLAR rule — when a question mixes personal history + location:
                  e.g. "coffee shops near me I've been to before", "dentist near me I've visited", "restaurants nearby I liked":
                  Include BOTH the relevant Seline tools (search_seline_records scope=["visit","location"]) AND the maps tool (search_nearby_places).
                  The synthesizer will weave both together — personal history + current nearby options.

                FOLLOW-UP MEMORY rule — if session memory shows an active time scope or entity focus and the user asks a short follow-up, inherit that same scope unless the user explicitly changes it.
                  Examples inside an active day/week thread:
                    "what about emails?" -> search_seline_records with scopes ["email"] and the same time_range
                    "and spending?" -> aggregate_seline plus receipt lookup with the same time_range
                    "who was there?" -> search_seline_records with scopes ["visit","person"] and needsEnrichment true
                  Do NOT reset to an all-time search for short follow-up prompts.

                needsEnrichment: true for — single-day queries, multi-day queries, episode queries (resolve_episode_context),
                  or any question where visit details (who was there, visit notes) would enrich the answer.
                  Set needsEnrichment: false only for simple lookups, spending totals, or email/note searches with no visit angle.

                DO NOT include get_record_details or traverse_relations in primaryTools — those are enrichment-only.
                If the query is a follow-up (anchor state has resolvedTimeRange or resolvedEntities), reuse that scope in tool args.
                If uncertain, prefer search_seline_records as the safe default.

                === OUTPUT (strict JSON, no markdown, no commentary) ===
                {
                  "synthesisModel": "gemini-2.5-flash" | "gemini-2.5-flash-lite",
                  "needsEnrichment": true | false,
                  "primaryTools": [
                    { "name": "<tool_name>", "args": { <args matching schema> } }
                  ]
                }
                """
            ),
            inputMessage(role: "user", text: userMessage)
        ]

        guard let response = try? await responsesService.createResponse(
            model: GeminiResponsesService.defaultChatModel,
            input: routerInput,
            tools: []
        ) else { return nil }

        let raw = response.outputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let toolsRaw = json["primaryTools"] as? [[String: Any]],
            !toolsRaw.isEmpty
        else { return nil }

        let synthesisModel = (json["synthesisModel"] as? String) ?? GeminiResponsesService.escalatedChatModel
        let needsEnrichment = (json["needsEnrichment"] as? Bool) ?? false

        let toolCalls: [IntentRouterPlan.ToolCall] = toolsRaw.compactMap { tool in
            guard let name = tool["name"] as? String, !name.isEmpty else { return nil }
            let args = tool["args"] ?? [String: Any]()
            let argsJSON: String
            if JSONSerialization.isValidJSONObject(args),
               let d = try? JSONSerialization.data(withJSONObject: args),
               let s = String(data: d, encoding: .utf8) {
                argsJSON = s
            } else {
                argsJSON = "{}"
            }
            return IntentRouterPlan.ToolCall(name: name, argsJSON: argsJSON)
        }

        guard !toolCalls.isEmpty else { return nil }
        return IntentRouterPlan(synthesisModel: synthesisModel, primaryToolCalls: toolCalls, needsEnrichment: needsEnrichment)
    }

    /// Zero-latency Swift-side routing for the most common query patterns.
    /// Returns nil for anything that needs the full LLM router.
    private func fastPathPlan(
        userMessage: String,
        anchorState: ConversationAnchorState?
    ) -> IntentRouterPlan? {
        let lower = userMessage.lowercased()
        let cal = Calendar.current
        let now = Date()
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        let todayStr = df.string(from: now)

        // ── Single-day query ("how's my day", "how was my day", "what happened today") ──
        let singleDayTriggers = ["how's my day", "how is my day", "how was my day",
                                 "what happened today", "recap my day", "recap today",
                                 "tell me about my day", "how am i doing today",
                                 "what did i do today", "catch me up on today",
                                 "describe my day", "describe today", "summarize my day",
                                 "summarize today", "what's on my plate today"]
        if singleDayTriggers.contains(where: { lower.contains($0) }) {
            return singleDayPlan(for: todayStr)
        }

        // ── Yesterday query ──
        let yesterdayTriggers = ["how was yesterday", "describe yesterday", "recap yesterday",
                                 "what happened yesterday", "tell me about yesterday",
                                 "yesterday's recap", "summarize yesterday",
                                 "describe how yesterday went", "how did yesterday go",
                                 "how yesterday went"]
        if yesterdayTriggers.contains(where: { lower.contains($0) }) {
            if let yesterday = cal.date(byAdding: .day, value: -1, to: now) {
                return singleDayPlan(for: df.string(from: yesterday))
            }
        }

        // ── "today" as a standalone day reference ──
        if lower == "today" || lower.hasSuffix(" today") && lower.count < 40 {
            let broadDay = ["how", "what", "recap", "tell", "describe", "show", "summarize"]
            if broadDay.contains(where: { lower.hasPrefix($0) }) || lower.count < 20 {
                return singleDayPlan(for: todayStr)
            }
        }

        // ── Week-so-far query ──
        let weekTriggers = ["how's my week", "how is my week", "how was my week",
                            "week so far", "this week so far", "how's the week",
                            "recap my week", "recap this week"]
        if weekTriggers.contains(where: { lower.contains($0) }) {
            return weekPlan(cal: cal, now: now, df: df)
        }

        if let followUpPlan = anchoredFollowUpPlan(userMessage: userMessage, anchorState: anchorState) {
            return followUpPlan
        }

        return nil
    }

    private func singleDayPlan(for dateStr: String) -> IntentRouterPlan {
        let tools: [IntentRouterPlan.ToolCall] = [
            .init(name: "get_day_context",         argsJSON: "{\"date_query\":\"\(dateStr)\"}"),
            .init(name: "search_seline_records",   argsJSON: "{\"query\":\"visits \(dateStr)\",\"scopes\":[\"visit\"],\"time_range\":\"\(dateStr)\"}"),
            .init(name: "aggregate_seline",        argsJSON: "{\"metric\":\"total_spend\",\"filters\":{\"scopes\":[\"receipt\"],\"time_range\":\"\(dateStr)\"},\"group_by\":\"category\"}"),
            .init(name: "search_seline_records",   argsJSON: "{\"query\":\"emails \(dateStr)\",\"scopes\":[\"email\"],\"time_range\":\"\(dateStr)\"}"),
            .init(name: "search_seline_records",   argsJSON: "{\"query\":\"notes \(dateStr)\",\"scopes\":[\"note\"],\"time_range\":\"\(dateStr)\"}"),
            .init(name: "search_seline_records",   argsJSON: "{\"query\":\"journal entry \(dateStr)\",\"scopes\":[\"note\"],\"time_range\":\"\(dateStr)\"}"),
        ]
        return IntentRouterPlan(
            synthesisModel: GeminiResponsesService.escalatedChatModel,
            primaryToolCalls: tools,
            needsEnrichment: true
        )
    }

    private func weekPlan(cal: Calendar, now: Date, df: ISO8601DateFormatter) -> IntentRouterPlan {
        let weekday = cal.component(.weekday, from: now)
        let daysFromMonday = (weekday + 5) % 7
        var tools: [IntentRouterPlan.ToolCall] = (0...daysFromMonday).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -(daysFromMonday - offset), to: now) else { return nil }
            let d = df.string(from: day)
            return .init(name: "get_day_context", argsJSON: "{\"date_query\":\"\(d)\"}")
        }
        tools.append(.init(name: "aggregate_seline",
                           argsJSON: "{\"metric\":\"total_spend\",\"filters\":{\"scopes\":[\"receipt\"]},\"group_by\":\"day\"}"))
        tools.append(.init(name: "search_seline_records",
                           argsJSON: "{\"query\":\"emails this week\",\"scopes\":[\"email\"]}"))
        tools.append(.init(name: "search_seline_records",
                           argsJSON: "{\"query\":\"notes this week\",\"scopes\":[\"note\"]}"))
        return IntentRouterPlan(
            synthesisModel: GeminiResponsesService.escalatedChatModel,
            primaryToolCalls: tools,
            needsEnrichment: true
        )
    }

    private func anchoredFollowUpPlan(
        userMessage: String,
        anchorState: ConversationAnchorState?
    ) -> IntentRouterPlan? {
        guard let anchorState, let bounds = anchorState.resolvedDateBounds else { return nil }
        guard TemporalUnderstandingService.shared.extractTemporalRange(from: userMessage) == nil else { return nil }

        let lower = userMessage.lowercased()
        let followUpMarkers = [
            "what about", "how about", "and ", "also", "besides",
            "anything on", "more on", "tell me more", "who was there",
            "what else", "and what", "what were", "what did"
        ]
        let tokenCount = lower.split(whereSeparator: \.isWhitespace).count
        let isLikelyFollowUp = tokenCount <= 10 || followUpMarkers.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0)") })
        guard isLikelyFollowUp else { return nil }

        let timeRange = explicitTimeRangeString(for: bounds)
        let isSingleDay = isSingleDayBounds(bounds)

        if containsAny(lower, terms: ["email", "emails", "inbox", "message", "messages"]) {
            return IntentRouterPlan(
                synthesisModel: isSingleDay ? GeminiResponsesService.defaultChatModel : GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"email\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: false
            )
        }

        if containsAny(lower, terms: ["note", "notes", "journal", "write down", "wrote down"]) {
            return IntentRouterPlan(
                synthesisModel: isSingleDay ? GeminiResponsesService.defaultChatModel : GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"note\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: false
            )
        }

        if containsAny(lower, terms: ["spend", "spent", "spending", "receipt", "receipts", "purchase", "purchases", "buy", "bought", "cost"]) {
            return IntentRouterPlan(
                synthesisModel: GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "aggregate_seline",
                        argsJSON: "{\"metric\":\"total_spend\",\"filters\":{\"scopes\":[\"receipt\"],\"time_range\":\(jsonStringLiteral(timeRange))},\"group_by\":\"category\"}"
                    ),
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"receipt\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: false
            )
        }

        if containsAny(lower, terms: ["who", "with me", "with who", "with whom", "person", "people"]) {
            return IntentRouterPlan(
                synthesisModel: GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"person\",\"visit\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: true
            )
        }

        if containsAny(lower, terms: ["visit", "visits", "place", "places", "location", "locations", "went", "stopped", "there"]) {
            return IntentRouterPlan(
                synthesisModel: GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"visit\",\"location\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: true
            )
        }

        if containsAny(lower, terms: ["event", "events", "meeting", "meetings", "calendar", "schedule", "appointment"]) {
            return IntentRouterPlan(
                synthesisModel: isSingleDay ? GeminiResponsesService.defaultChatModel : GeminiResponsesService.escalatedChatModel,
                primaryToolCalls: [
                    .init(
                        name: "search_seline_records",
                        argsJSON: "{\"query\":\(jsonStringLiteral(userMessage)),\"scopes\":[\"event\"],\"time_range\":\(jsonStringLiteral(timeRange))}"
                    )
                ],
                needsEnrichment: false
            )
        }

        return nil
    }

    /// Safe default plan used when the router LLM call fails or returns unparseable JSON.
    /// A broad search is always better than falling back to an LLM that asks clarifying questions.
    private func defaultSearchPlan(for userMessage: String) -> IntentRouterPlan {
        let call = IntentRouterPlan.ToolCall(
            name: "search_seline_records",
            argsJSON: "{\"query\": \(jsonStringLiteral(userMessage))}"
        )
        return IntentRouterPlan(
            synthesisModel: GeminiResponsesService.escalatedChatModel,
            primaryToolCalls: [call],
            needsEnrichment: true
        )
    }

    private func jsonStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Parallel tool execution

    /// Executes all tool calls concurrently. Each tool's async I/O suspends on the main actor
    /// independently, so network calls overlap even though all code runs on @MainActor.
    private func executeToolsParallel(
        _ calls: [IntentRouterPlan.ToolCall]
    ) async -> (results: [ToolResult], trace: [AgentToolTrace], locationInfo: ETALocationInfo?) {
        guard !calls.isEmpty else { return ([], [], nil) }

        // Each element: (original index, result, locationInfo, elapsed ms)
        typealias RawOut = (idx: Int, result: ToolResult, loc: ETALocationInfo?, ms: Int)
        var rawOutputs: [RawOut] = []
        rawOutputs.reserveCapacity(calls.count)

        await withTaskGroup(of: RawOut.self) { group in
            for (index, call) in calls.enumerated() {
                let name = call.name
                let argsJSON = call.argsJSON
                group.addTask {
                    let start = Date()
                    do {
                        let execution = try await SelineToolRegistry.shared.execute(
                            name: name,
                            argumentsJSON: argsJSON
                        )
                        return (index, execution.result, execution.locationInfo,
                                Int(Date().timeIntervalSince(start) * 1000))
                    } catch {
                        return (index, ToolResult(toolName: name), nil,
                                Int(Date().timeIntervalSince(start) * 1000))
                    }
                }
            }
            for await out in group {
                rawOutputs.append(out)
            }
        }

        let sorted = rawOutputs.sorted { $0.idx < $1.idx }
        let results = sorted.map(\.result)
        let traces: [AgentToolTrace] = sorted.map { out in
            AgentToolTrace(
                toolName: calls[out.idx].name,
                argumentsJSON: calls[out.idx].argsJSON,
                resultPreview: toolPreview(for: out.result),
                latencyMs: out.ms
            )
        }
        return (results, traces, sorted.compactMap(\.loc).last)
    }

    // MARK: - Deterministic enrichment resolver

    /// Decides which enrichment tools to run based on primary results — no extra LLM call needed.
    /// Only enriches visit/daySummary records that came back without full notes.
    private func enrichmentCalls(from results: [ToolResult]) -> [IntentRouterPlan.ToolCall] {
        // Enrich visits and day summaries — this pulls visitNotes, linked_people, and linked_receipt.
        // Limit to 8 (up from 3) so a busy day with multiple visits all get full context.
        let refsToEnrich = results
            .flatMap(\.records)
            .filter { $0.ref.type == .visit || $0.ref.type == .daySummary }
            .prefix(8)
            .map { ["type": $0.ref.type.rawValue, "id": $0.ref.id] }

        guard !refsToEnrich.isEmpty else { return [] }
        let refsArray = Array(refsToEnrich)
        guard
            JSONSerialization.isValidJSONObject(refsArray),
            let data = try? JSONSerialization.data(withJSONObject: refsArray),
            let refsJSON = String(data: data, encoding: .utf8)
        else { return [] }

        return [IntentRouterPlan.ToolCall(
            name: "get_record_details",
            argsJSON: "{\"refs\": \(refsJSON)}"
        )]
    }

    // MARK: - Intent router flow

    /// New primary execution path. Returns immediately after:
    ///   1. One fast router LLM call (picks tools + synthesis model + pillars)
    ///   2. All primary tools run in parallel
    ///   3. Optional deterministic enrichment pass (also parallel, no extra LLM call)
    /// Falls back to the legacy planner loop on any router failure.
    private func runIntentRouterFlow(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState?,
        sessionSnapshot: ConversationSessionSnapshot?,
        includeLiveSearch: Bool,
        onToolDispatch: (([String]) -> Void)? = nil
    ) async throws -> (outcome: ToolPlanningOutcome, synthesisModel: String) {

        // --- Step 1: Route intent ---
        // Try a zero-latency Swift-side fast path first (no LLM call needed for common patterns).
        // Only call the router LLM when the fast path can't handle the query.
        let plan: IntentRouterPlan
        if let fast = fastPathPlan(userMessage: userMessage, anchorState: anchorState) {
            plan = fast
        } else if let routed = await makeIntentPlan(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            anchorState: anchorState,
            sessionSnapshot: sessionSnapshot,
            liveSearchEnabled: includeLiveSearch
        ) {
            plan = routed
        } else {
            plan = defaultSearchPlan(for: userMessage)
        }

        onToolDispatch?(plan.primaryToolCalls.map(\.name))
        try Task.checkCancellation()

        // --- Step 2: Execute primary tools in parallel ---
        // Synthesis will begin streaming immediately after this returns (item 4).
        let (primaryResults, primaryTrace, locationInfo) = await executeToolsParallel(plan.primaryToolCalls)
        try Task.checkCancellation()

        // --- Step 3: Deterministic enrichment (no extra LLM call, also parallel) ---
        var allResults = primaryResults
        var allTrace = primaryTrace

        if plan.needsEnrichment {
            let enrichCalls = enrichmentCalls(from: primaryResults)
            if !enrichCalls.isEmpty {
                let (enrichResults, enrichTrace, _) = await executeToolsParallel(enrichCalls)
                allResults.append(contentsOf: enrichResults)
                allTrace.append(contentsOf: enrichTrace)
            }
        }

        try Task.checkCancellation()

        let outcome = ToolPlanningOutcome(
            toolResults: allResults,
            toolTrace: allTrace,
            locationInfo: locationInfo,
            usedLiveWeb: false,
            plannerText: nil
        )
        return (outcome, plan.synthesisModel)
    }

    // MARK: - Tool outcome

    private struct ToolPlanningOutcome {
        let toolResults: [ToolResult]
        let toolTrace: [AgentToolTrace]
        let locationInfo: ETALocationInfo?
        let usedLiveWeb: Bool
        let plannerText: String?
    }

    // MARK: - Final synthesis

    private func synthesizeAnswer(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        sessionSnapshot: ConversationSessionSnapshot?,
        evidenceBundle: EvidenceBundle,
        model: String,
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        // Skip the LLM call entirely when there is nothing to synthesize from.
        // Without this guard the LLM generates a speculative clarifying question
        // (e.g. "Which specific day should I focus on?") that leaks to the user.
        if evidenceBundle.records.isEmpty && evidenceBundle.aggregates.isEmpty {
            return fallbackAnswer(from: evidenceBundle)
        }

        let priorTurns = conversationHistory.suffix(8).map { message in
            "\(message.isUser ? "User" : "Assistant"): \(message.text)"
        }

        let synthesisInput: [[String: Any]] = [
            inputMessage(
                role: "developer",
                text: """
                You are Seline's answer synthesizer.

                \(userContextBlock())

                \(dailyBriefingBlock())

                \(sessionMemoryBlock(snapshot: sessionSnapshot, currentQuery: userMessage, conversationHistory: conversationHistory))

                Rules:
                - Write like a warm, capable personal assistant who genuinely knows the user. Sound friendly and natural, not robotic or clinical. Use plain everyday language. Be concise but complete.
                - Vary sentence structure. Not every line should start with "You had" or "You visited". Use natural transitions and short warm openers when they fit.
                - Always address the user in second person: "you", "your", "you visited", "you had". Never say "Seline", "the user", or refer to the user in third person.
                - Answer only from the evidence bundle. If evidence is missing, say so plainly.
                - Never use stiff phrases like "based on the evidence bundle", "the data suggests", or "I found" unless they are genuinely necessary for clarity.
                - CRITICAL citation format: cite evidence inline as [0], [1], [2] — the ZERO-BASED INTEGER POSITIONS of records in evidenceBundle.records. NEVER write [visit:UUID], [receipt:UUID], or any other format. Only plain integer indices.
                - CRITICAL citation deduplication: each record index may appear AT MOST ONCE in the entire response. Place it at the very first sentence where you use content from that record and never use that same index again — not in later bullets, not in later sections, not at the end of a paragraph. If ten bullets all come from record [0], you cite [0] exactly once after the first bullet and omit it from all remaining bullets. Count your citations: the total number of unique citation indices must equal the total number of citation tags in your response.
                - Use citations only for actual evidence records, not aggregate rows.
                - Keep clarifying questions short when ambiguity remains.
                - If aggregates are present, use them directly instead of narrating from loose snippets.
                - If the bundle contains ambiguities, prefer asking the ambiguity question plainly instead of guessing.
                - If session memory indicates this is a follow-up, keep the same time or entity scope unless the user clearly changed it. Answer the slice they asked for instead of repeating the whole recap.
                - If the user asks for a breakdown and grouped aggregate rows exist, present the grouped rows before any overall total.
                - If the user asks for itemized or day-level detail and the bundle includes matching records, list those dated records instead of repeating only the total.
                - When the user asks about "near me" results, prioritize nearby place evidence first.
                - If the evidence is partial, weak, or does not clearly satisfy every part of the user's request, ask one short follow-up clarification question instead of giving a confident no-answer.
                - Do not cite loose candidate records in a no-answer or clarification response.
                - PROACTIVE CONTEXT: When answering ANY focused question (a specific event, appointment, purchase, or visit), scan the evidence bundle for other records from the same day or within 1 day. If found, surface 1–2 of them naturally at the end. Examples: "That same afternoon you also stopped by [place]" or "You picked up $X at [merchant] earlier that day". This is what makes the response feel like a real assistant — not just answering the narrow question but painting the full picture.
                - For broad day or week recaps, connect the story across meetings, visits, receipts, notes, and email. Help the user understand how the day unfolded, not just what records exist.
                - For place or proximity results with multiple matches, present them as a short bullet list with the place name first, then ETA or address.
                - For broad day questions ("how was my day", "how's my day looking", "what happened today", "recap my day", any specific past date):
                  Use this EXACT markdown structure — it must look clean like ChatGPT responses:

                  [One or two warm opener sentences that capture the shape of the day.]

                  **Meetings & Events**
                  - [time] [name] (recurring if applicable)
                  - ...

                  **Places & Visits**
                  - [place], [time]–[time] · [duration] — [who was there if known] — [visit note if any]
                  - ...

                  **Spending**
                  - Total: $X across N purchases
                  - [key items]

                  **Emails**
                  - [sender]: [subject or one-line summary]
                  - ...

                  **Notes & Journal**
                  - [what you wrote down, reflected on, or captured]
                  - ...

                  **Highlights**
                  - [each highlight as its own bullet]

                  **To follow up**
                  - [each open item as its own bullet]

                  FORMATTING RULES (critical):
                  - Each section header is **bold** on its own line — NOT a bullet point, NOT inline text
                  - Items within each section are bullet points (-)
                  - Leave one blank line between sections
                  - Skip any section that has zero evidence — do NOT write "None" or "I don't see any..."
                  - Do NOT add a trailing paragraph summarising what's missing — just end after the last populated section
                  - Order sections by how populated they are — richest first after the opener
                  - Emails: only surface ones that are important, have attachments, or are from someone the user knows; skip newsletters/automated alerts unless notable
                - If note or journal records exist, surface them in **Notes & Journal** or fold their strongest insight into **Highlights**. Do not ignore them.
                - For day summary evidence records, the highlights, open_loops, and anomalies attributes contain pipe-separated lists of the actual items. Present EACH ITEM as a separate bullet point. NEVER count them ("3 highlights") — always expand them into individual bullets with the actual text.
                - For visit records, treat entry_local_date, entry_local_weekday, entry_local_time, exit_local_date, exit_local_weekday, and exit_local_time as authoritative local-time fields. Do not recompute weekdays from ISO timestamps if those local fields are present.
                - For event records, always use the local_time and local_date attributes for display. Never convert the UTC ISO timestamp yourself — the local_time attribute already reflects the user's device timezone.
                - Do not invent corrected dates. If the user questions a day/date, explain the recorded local timestamp/day from the evidence instead of fabricating a new date.
                - If a visit happens just after midnight, you may describe it as early the next morning, but keep the actual recorded local date/weekday unchanged unless the evidence itself says otherwise.
                - Never use the phrase "open loops" in your response. Say "things to follow up on", "pending items", or "items still open" instead.
                - CRITICAL — The user's question already contains the temporal scope ("today", "this week", a specific date, etc). NEVER ask the user "which specific day", "which day should I focus on", "which date", "what time period", or any similar date/scope clarification. The date is resolved — answer from what the evidence shows. If the evidence is thin, say "I don't see much data for [date]" and summarize what you do have.
                """
            ),
            inputMessage(
                role: "developer",
                text: """
                Structured context JSON:
                \(citationIndexMap(for: evidenceBundle))

                \(synthesisContextJSON(conversationTail: priorTurns, sessionSnapshot: sessionSnapshot, evidenceBundle: evidenceBundle))
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
        let messageRange = TemporalUnderstandingService.shared
            .extractTemporalRange(from: userMessage)?
            .description
        let temporalDescription = messageRange
            ?? resolvedDateFromToolResults(toolResults)
            ?? base?.resolvedTimeRange
        let resolvedDateBounds = toolResults.compactMap(\.resolvedDateBounds).last ?? base?.resolvedDateBounds

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
            resolvedDateBounds: resolvedDateBounds,
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

    private func selectedModel(for turn: AgentTurnInput) -> String {
        let analyticalKeywords = [
            "week", "month", "year", "quarter",
            "summary", "summarize", "overview", "recap",
            "spending", "spent", "expenses", "budget", "financial",
            "compare", "comparison", "trend", "trends", "pattern", "patterns",
            "how much", "how many", "how often",
            "most", "least", "average", "total",
            "analyze", "analysis", "breakdown",
            // Day-overview and broad life-context queries
            "how was", "how's my", "how is my", "my day", "describe my",
            "tell me about my", "what happened", "what did i do",
            "looking", "catch me up", "fill me in"
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

    private func synthesisContextJSON(
        conversationTail: [String],
        sessionSnapshot: ConversationSessionSnapshot?,
        evidenceBundle: EvidenceBundle
    ) -> String {
        let snapshot = SynthesisContextSnapshot(
            conversationTail: conversationTail,
            sessionSnapshot: sessionSnapshot,
            evidenceBundle: evidenceBundle
        )
        return (try? encodedJSONString(snapshot)) ?? "{}"
    }

    private func sessionMemoryBlock(
        snapshot: ConversationSessionSnapshot?,
        currentQuery: String,
        conversationHistory: [ConversationMessage]
    ) -> String {
        let trimmedQuery = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorHistory: [ConversationMessage]
        if let last = conversationHistory.last,
           last.isUser,
           last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedQuery) == .orderedSame {
            priorHistory = Array(conversationHistory.dropLast())
        } else {
            priorHistory = conversationHistory
        }

        let conversationContext = ConversationStateAnalyzerService.analyzeConversationState(
            currentQuery: currentQuery,
            conversationHistory: priorHistory
        )

        var lines = ["Session memory:"]
        if let summary = snapshot?.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            lines.append("• Thread summary: \(summary)")
        }

        if let scope = snapshot?.resolvedTimeRange ?? snapshot?.anchorState?.resolvedTimeRange,
           !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("• Active time scope: \(scope)")
        }

        let activeEntities = (snapshot?.resolvedEntities ?? snapshot?.anchorState?.resolvedEntities ?? [])
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !activeEntities.isEmpty {
            lines.append("• Active entities: \(Array(activeEntities.prefix(4)).joined(separator: ", "))")
        }

        let recentTurns = snapshot?.recentTurns.suffix(4) ?? []
        if !recentTurns.isEmpty {
            lines.append("• Recent turns:")
            for turn in recentTurns {
                lines.append("  - \(turn.role.capitalized): \(compactPromptText(turn.text, limit: 110))")
            }
        }

        if conversationContext.isProbablyFollowUp {
            lines.append("• Follow-up detected: keep the current scope unless the user clearly changes it.")
        }

        if let lastQuestionType = conversationContext.lastQuestionType {
            lines.append("• Recent topic: \(lastQuestionType)")
        }

        if lines.count == 1 {
            lines.append("• No active thread memory yet.")
        }

        return lines.joined(separator: "\n")
    }

    private func compactPromptText(_ text: String, limit: Int) -> String {
        let compact = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit - 1)) + "…"
    }

    private func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func explicitTimeRangeString(for bounds: ResolvedDateBounds) -> String {
        if isSingleDayBounds(bounds) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: bounds.start)
        }

        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: bounds.start))/\(formatter.string(from: bounds.end))"
    }

    private func isSingleDayBounds(_ bounds: ResolvedDateBounds) -> Bool {
        let inclusiveEnd = bounds.end.addingTimeInterval(-1)
        return Calendar.current.isDate(bounds.start, inSameDayAs: inclusiveEnd)
    }

    private func citationIndexMap(for evidenceBundle: EvidenceBundle) -> String {
        guard !evidenceBundle.records.isEmpty else { return "No evidence records." }
        let lines = evidenceBundle.records.enumerated().map { index, record in
            "[\(index)] \(record.ref.type.rawValue): \(record.title)"
        }
        return "Citation index (use ONLY these integers):\n" + lines.joined(separator: "\n")
    }

    private func resolvedDateFromToolResults(_ toolResults: [ToolResult]) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        dateFormatter.timeZone = TimeZone.current
        let isoParser = ISO8601DateFormatter()
        for result in toolResults {
            for record in result.records {
                guard record.ref.type == .event || record.ref.type == .visit else { continue }
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

        // Post-process: enforce section headers are **bold** on own line, not bulleted
        let formatted = enforceSectionHeaderFormatting(trimmed)
        return formatted
    }

    /// Fixes LLM output where section headers appear as bullet items instead of bold headers.
    /// Converts lines like `- Spending` or `• **Spending**` into `**Spending**` on their own line.
    private func enforceSectionHeaderFormatting(_ text: String) -> String {
        let knownHeaders: Set<String> = [
            "meetings & events", "meetings", "events", "calendar",
            "places & visits", "places", "visits", "locations",
            "spending", "purchases", "expenses",
            "emails", "email", "inbox",
            "highlights", "key highlights",
            "to follow up", "follow up", "follow-up", "pending items", "open items",
            "notes", "journal", "journal entry",
            "summary", "overview"
        ]

        var lines = text.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let line = lines[i]
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip bullet prefix if present: `- `, `• `, `* `
            var content = stripped
            if let range = content.range(of: #"^[-•*]\s+"#, options: .regularExpression) {
                content = String(content[range.upperBound...])
            }

            // Strip existing bold markers
            var plain = content
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove trailing colon for matching
            if plain.hasSuffix(":") {
                plain = String(plain.dropLast()).trimmingCharacters(in: .whitespaces)
            }

            if knownHeaders.contains(plain.lowercased()) {
                lines[i] = "**\(plain)**"
            }
        }

        return lines.joined(separator: "\n")
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
            "no evidence of",
            "cannot determine the exact date",
            "can't determine the exact date",
            "i cannot determine",
            "i can't determine",
            "unable to determine the exact",
            "i cannot fulfill this request",
            "i can't fulfill this request",
            "does not contain information about",
            // Clarifying questions about date/day scope that should never surface
            "which specific day",
            "which day should i focus",
            "what specific day",
            "which date should i",
            "could you specify the date",
            "could you specify which day",
            "please specify the date",
            "please clarify the date",
            "what time period",
            "which time period",
            "could you clarify which week",
            "which week are you referring"
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
