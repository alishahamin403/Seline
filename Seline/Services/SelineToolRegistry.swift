import Foundation
import CoreLocation
import MapKit

@MainActor
final class SelineToolRegistry {
    static let shared = SelineToolRegistry()

    struct ToolExecution {
        let result: ToolResult
        let locationInfo: ETALocationInfo?
    }

    private let vectorSearch = VectorSearchService.shared
    private let mapsService = GoogleMapsService.shared
    private let locationsManager = LocationsManager.shared
    private let notesManager = NotesManager.shared
    private let taskManager = TaskManager.shared
    private let emailService = EmailService.shared
    private let peopleManager = PeopleManager.shared
    private let weatherService = WeatherService.shared
    private let navigationService = NavigationService.shared
    private let sharedLocationManager = SharedLocationManager.shared
    private let temporalService = TemporalUnderstandingService.shared
    private let spendingInsightsService = SpendingInsightsService.shared
    private let conversationActionHandler = ConversationActionHandler.shared
    private let episodeResolver = CompositeEpisodeResolver.shared
    private let gmailAPIClient = GmailAPIClient.shared
    private let geminiService = GeminiService.shared
    private let daySummaryService = DaySummaryService.shared

    private init() {}

    func toolDefinitions(includeLiveSearch: Bool) -> [[String: Any]] {
        var tools: [[String: Any]] = [
            functionTool(
                name: "resolve_episode_context",
                description: "Resolve an episode-style query that combines people, places, and time windows such as weekends, trips, or outings. Use this for requests like 'describe the weekend when I went to Niagara with Suju'.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "conversation_history": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "role": ["type": "string"],
                                    "content": ["type": "string"]
                                ],
                                "required": ["role", "content"]
                            ]
                        ]
                    ],
                    "required": ["query"]
                ]
            ),
            functionTool(
                name: "get_day_context",
                description: "Get a daily cross-touchpoint summary for one day, combining journal, tasks, visits, receipts, linked people, and inbox activity. Use this for questions like 'how was I doing yesterday' or 'what happened that day'.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "date_query": ["type": "string"]
                    ]
                ]
            ),
            functionTool(
                name: "search_seline_records",
                description: "Search Seline records holistically across visits, locations, people, receipts, notes, emails, and events. Use this when you need broad evidence before answering.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "scopes": [
                            "type": "array",
                            "items": ["type": "string", "enum": ["visit", "location", "person", "receipt", "note", "email", "event"]]
                        ],
                        "time_range": ["type": "string"],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 30]
                    ],
                    "required": ["query"]
                ]
            ),
            functionTool(
                name: "get_record_details",
                description: "Load richer details for specific records when search results are promising and you need exact fields before answering.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "refs": [
                            "type": "array",
                            "items": entityRefSchema()
                        ]
                    ],
                    "required": ["refs"]
                ]
            ),
            functionTool(
                name: "aggregate_seline",
                description: "Aggregate Seline data like counts, totals, and breakdowns. Reuse filters.entity_refs from prior evidence whenever the user is asking a follow-up about the same place, person, visit, or receipt set. Use group_by=day for daily breakdowns, month for month-by-month trends, category for spend by category, weekday for visit patterns, place for location rollups, calendar for event source rollups, or sender for email rollups.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "metric": ["type": "string"],
                        "group_by": [
                            "type": "string",
                            "enum": ["day", "month", "category", "weekday", "place", "calendar", "sender"]
                        ],
                        "filters": [
                            "type": "object",
                            "properties": [
                                "query": ["type": "string"],
                                "scopes": [
                                    "type": "array",
                                    "items": ["type": "string", "enum": ["visit", "location", "person", "receipt", "note", "email", "event"]]
                                ],
                                "time_range": ["type": "string"],
                                "entity_refs": [
                                    "type": "array",
                                    "items": entityRefSchema()
                                ]
                            ]
                        ]
                    ],
                    "required": ["metric"]
                ]
            ),
            functionTool(
                name: "traverse_relations",
                description: "Follow relationships between records, such as place to visits, visit to people, person to receipts, or place to linked spending.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "seed_refs": [
                            "type": "array",
                            "items": entityRefSchema()
                        ],
                        "relation_types": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "depth": ["type": "integer", "minimum": 1, "maximum": 2]
                    ],
                    "required": ["seed_refs"]
                ]
            ),
            functionTool(
                name: "get_current_context",
                description: "Get the current date, timezone, current location, current address when available, and current weather. Use this for questions like 'where am I right now' or 'what is my current address'.",
                parameters: [
                    "type": "object",
                    "properties": [:]
                ]
            ),
            functionTool(
                name: "prepare_event_draft",
                description: "Draft an event from the user's natural-language request. Extract title, date, time, end time, recurrence, reminder, notes, location, and category. If category is not specified, default to Personal. Return ambiguities instead of failing when critical fields are missing.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "user_request": ["type": "string"]
                    ],
                    "required": ["user_request"]
                ]
            ),
            functionTool(
                name: "prepare_note_draft",
                description: "Draft a note from the user's natural-language request. Suggest a concise title when needed and preserve the body content.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "user_request": ["type": "string"]
                    ],
                    "required": ["user_request"]
                ]
            ),
            functionTool(
                name: "refresh_inbox_and_get_latest_email",
                description: "Refresh the inbox first, then return the latest matching email. Use this for latest or newest email requests instead of replying from cached memory.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "scope": ["type": "string"]
                    ]
                ]
            ),
            functionTool(
                name: "get_email_details",
                description: "Load full email details, including body and attachments, for an already identified email.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "email_id": ["type": "string"],
                        "email_ref": entityRefSchema()
                    ]
                ]
            ),
            functionTool(
                name: "resolve_live_place",
                description: "Resolve a plain-English nearby request for one named place like 'wendys near me'. Return the closest exact address, coordinates, and a live place preview, but do not save anything yet.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "radius_meters": ["type": "integer", "minimum": 100, "maximum": 50000],
                        "open_now": ["type": "boolean"],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 12]
                    ],
                    "required": ["query"]
                ]
            ),
            functionTool(
                name: "prepare_saved_place_draft",
                description: "Prepare a confirmed-save draft for a live place result. If the folder is missing, surface the existing saved-place folders so the user can choose one before saving.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "place_id": ["type": "string"],
                        "folder_name": ["type": "string"]
                    ],
                    "required": ["place_id"]
                ]
            ),
            functionTool(
                name: "list_saved_place_folders",
                description: "List existing saved-place folders and categories for a follow-up location save.",
                parameters: [
                    "type": "object",
                    "properties": [:]
                ]
            ),
            functionTool(
                name: "find_saved_places_within_eta",
                description: "Search the user's saved places by current drive time. Use this for requests like restaurants in 20 minutes from my saved places, saved sushi within 15 min, or clinics in my saved locations within 30 minutes.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "max_minutes": ["type": "integer", "minimum": 1, "maximum": 240],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 20],
                        "folder_name": ["type": "string"]
                    ]
                ]
            ),
            functionTool(
                name: "search_nearby_places",
                description: "Search live nearby places using the user's current location. Use this for broader nearby searches that may have multiple matches, like clinics near me, pharmacies near me, sushi near me, food nearby, or open now.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "radius_meters": ["type": "integer", "minimum": 100, "maximum": 50000],
                        "open_now": ["type": "boolean"],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 12]
                    ],
                    "required": ["query"]
                ]
            ),
            functionTool(
                name: "get_place_details",
                description: "Get richer live details for a nearby place result, like phone, site, rating, hours, and address.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "place_id": ["type": "string"]
                    ],
                    "required": ["place_id"]
                ]
            ),
            functionTool(
                name: "get_eta",
                description: "Calculate drive ETA from the user's current location to a saved or live place.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "destination": [
                            "type": "object",
                            "properties": [
                                "saved_place_id": ["type": "string"],
                                "place_id": ["type": "string"],
                                "name": ["type": "string"],
                                "address": ["type": "string"],
                                "latitude": ["type": "number"],
                                "longitude": ["type": "number"]
                            ]
                        ]
                    ],
                    "required": ["destination"]
                ]
            )
        ]

        if includeLiveSearch {
            tools.append(["type": "web_search"])
        }

        return tools
    }

    func execute(
        name: String,
        argumentsJSON: String
    ) async throws -> ToolExecution {
        let arguments = try decodeArgumentsJSON(argumentsJSON)

        switch name {
        case "resolve_episode_context":
            return try await ToolExecution(result: resolveEpisodeContext(arguments: arguments), locationInfo: nil)
        case "get_day_context":
            return try await ToolExecution(result: getDayContext(arguments: arguments), locationInfo: nil)
        case "search_seline_records":
            return try await ToolExecution(result: searchSelineRecords(arguments: arguments), locationInfo: nil)
        case "get_record_details":
            return try await ToolExecution(result: getRecordDetails(arguments: arguments), locationInfo: nil)
        case "aggregate_seline":
            return try await ToolExecution(result: aggregateSeline(arguments: arguments), locationInfo: nil)
        case "traverse_relations":
            return try await ToolExecution(result: traverseRelations(arguments: arguments), locationInfo: nil)
        case "get_current_context":
            return try await ToolExecution(result: getCurrentContext(), locationInfo: nil)
        case "prepare_event_draft":
            return try await ToolExecution(result: prepareEventDraft(arguments: arguments), locationInfo: nil)
        case "prepare_note_draft":
            return try await ToolExecution(result: prepareNoteDraft(arguments: arguments), locationInfo: nil)
        case "refresh_inbox_and_get_latest_email":
            return try await ToolExecution(result: refreshInboxAndGetLatestEmail(arguments: arguments), locationInfo: nil)
        case "get_email_details":
            return try await ToolExecution(result: getEmailDetails(arguments: arguments), locationInfo: nil)
        case "resolve_live_place":
            return try await ToolExecution(result: resolveLivePlace(arguments: arguments), locationInfo: nil)
        case "prepare_saved_place_draft":
            return try await ToolExecution(result: prepareSavedPlaceDraft(arguments: arguments), locationInfo: nil)
        case "list_saved_place_folders":
            return try await ToolExecution(result: listSavedPlaceFolders(), locationInfo: nil)
        case "find_saved_places_within_eta":
            return try await ToolExecution(result: findSavedPlacesWithinETA(arguments: arguments), locationInfo: nil)
        case "search_nearby_places":
            return try await ToolExecution(result: searchNearbyPlaces(arguments: arguments), locationInfo: nil)
        case "get_place_details":
            return try await ToolExecution(result: getPlaceDetails(arguments: arguments), locationInfo: nil)
        case "get_eta":
            return try await getETA(arguments: arguments)
        default:
            return ToolExecution(
                result: ToolResult(
                    toolName: name,
                    records: [],
                    aggregates: [],
                    ambiguities: [],
                    citations: []
                ),
                locationInfo: nil
            )
        }
    }

    // MARK: - Tool implementations

    private func resolveEpisodeContext(arguments: [String: Any]) async throws -> ToolResult {
        let query = stringValue(arguments["query"]) ?? ""
        let conversationHistory = conversationHistoryPairs(from: arguments["conversation_history"])

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                toolName: "resolve_episode_context",
                ambiguities: [ToolAmbiguity(question: "Which trip or weekend should I look at?", options: [])]
            )
        }

        guard let resolution = await episodeResolver.resolve(query: query, conversationHistory: conversationHistory) else {
            return ToolResult(
                toolName: "resolve_episode_context",
                ambiguities: [ToolAmbiguity(question: "I couldn’t resolve a specific weekend or trip from that yet. Try naming the person, place, or rough date range.", options: [])]
            )
        }

        switch resolution {
        case .ambiguous(let question):
            return ToolResult(
                toolName: "resolve_episode_context",
                ambiguities: [ToolAmbiguity(question: question, options: [])]
            )
        case .resolved(let episode):
            episodeResolver.rememberResolvedEpisode(episode)

            var records: [EvidenceRecord] = []
            for person in episode.matchedPeople {
                records.append(personEvidenceRecord(person))
            }
            for place in episode.matchedPlaces.prefix(6) {
                records.append(placeEvidenceRecord(place))
            }
            for visit in episode.matchedVisits.prefix(12) {
                if let record = await visitEvidenceRecord(visit) {
                    records.append(record)
                }
            }
            for evidence in episode.supportingEvidence {
                if let record = evidenceRecord(from: evidence) {
                    records.append(record)
                }
            }

            let dedupedRecords = dedupeRecords(records)
            let aggregate = ToolAggregate(
                title: "Resolved episode",
                metric: "episode",
                groupBy: nil,
                rows: [
                    ToolAggregateRow(key: "Date range", value: episodeDateRangeLabel(episode)),
                    ToolAggregateRow(key: "People", value: episode.matchedPeople.map(\.name).joined(separator: ", ").nilIfEmpty ?? "None"),
                    ToolAggregateRow(key: "Places", value: Array(Set(episode.matchedPlaces.map(\.displayName))).sorted().joined(separator: ", ").nilIfEmpty ?? "None"),
                    ToolAggregateRow(key: "Visits", value: "\(episode.matchedVisits.count)", numericValue: Double(episode.matchedVisits.count)),
                    ToolAggregateRow(key: "Confidence", value: "\(Int((episode.confidence * 100).rounded()))%")
                ],
                summary: episode.supportingSourceSummary ?? episode.label
            )

            return ToolResult(
                toolName: "resolve_episode_context",
                records: dedupedRecords,
                aggregates: [aggregate],
                ambiguities: [],
                citations: dedupedRecords.map { ToolCitation(ref: $0.ref, label: $0.title) },
                resolvedTimeRange: episodeDateRangeLabel(episode),
                resolvedDateBounds: ResolvedDateBounds(start: episode.start, end: episode.end)
            )
        }
    }

    private func searchSelineRecords(arguments: [String: Any]) async throws -> ToolResult {
        let query = stringValue(arguments["query"]) ?? ""
        let scopes = stringArray(arguments["scopes"])
        let documentTypes = vectorDocumentTypes(for: scopes)
        let timeRange = stringValue(arguments["time_range"]) ?? query
        let limit = intValue(arguments["limit"]) ?? 10
        let resolvedBounds = resolvedDateRange(from: timeRange)

        let results = try await vectorSearch.search(
            query: query,
            documentTypes: documentTypes,
            limit: limit,
            dateRange: resolvedBounds,
            preferHistorical: true,
            retrievalMode: .exhaustive
        )

        var records: [EvidenceRecord] = []
        for result in results.prefix(limit) {
            if result.documentType == .visit,
               let visitId = UUID(uuidString: result.documentId),
               let visit = try? await fetchVisit(id: visitId),
               let detailedVisitRecord = await visitEvidenceRecord(visit) {
                records.append(detailedVisitRecord)
                continue
            }

            if let record = evidenceRecord(from: result) {
                records.append(record)
            }
        }

        let dedupedRecords = dedupeRecords(records)
        let cappedRecords = Array(dedupedRecords.prefix(limit))
        let result = ToolResult(
            toolName: "search_seline_records",
            records: cappedRecords,
            aggregates: [],
            ambiguities: [],
            citations: cappedRecords.map { ToolCitation(ref: $0.ref, label: $0.title) },
            isTruncated: results.count >= limit
        )
        return applyingResolvedDateContext(to: result, bounds: resolvedBounds)
    }

    private func getDayContext(arguments: [String: Any]) async throws -> ToolResult {
        let rawDateQuery = stringValue(arguments["date_query"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current

        let targetDate: Date
        if let rawDateQuery, !rawDateQuery.isEmpty {
            if let bounds = resolvedDateRange(from: rawDateQuery) {
                let start = calendar.startOfDay(for: bounds.start)
                let inclusiveEnd = bounds.end.addingTimeInterval(-1)
                if !calendar.isDate(start, inSameDayAs: inclusiveEnd) {
                    return ToolResult(
                        toolName: "get_day_context",
                        ambiguities: [ToolAmbiguity(question: "Which specific day should I focus on?", options: [])]
                    )
                }
                targetDate = start
            } else if let parsed = parseFlexibleDate(rawDateQuery) {
                targetDate = calendar.startOfDay(for: parsed)
            } else {
                return ToolResult(
                    toolName: "get_day_context",
                    ambiguities: [ToolAmbiguity(question: "Which day should I look at?", options: [])]
                )
            }
        } else {
            targetDate = calendar.startOfDay(for: Date())
        }

        guard let summary = await daySummaryService.summary(for: targetDate) else {
            return ToolResult(
                toolName: "get_day_context",
                ambiguities: [ToolAmbiguity(question: "I couldn’t assemble day context for that yet.", options: [])]
            )
        }

        let record = daySummaryEvidenceRecord(summary)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate.addingTimeInterval(86_400)
        let aggregate = ToolAggregate(
            title: "Day context",
            metric: "day_context",
            rows: [
                ToolAggregateRow(key: "Date", value: isoDate(targetDate)),
                ToolAggregateRow(key: "Mood", value: summary.mood ?? "Unknown"),
                ToolAggregateRow(key: "Highlights", value: "\(summary.highlights.count)", numericValue: Double(summary.highlights.count)),
                ToolAggregateRow(key: "Open loops", value: "\(summary.openLoops.count)", numericValue: Double(summary.openLoops.count)),
                ToolAggregateRow(key: "Anomalies", value: "\(summary.anomalies.count)", numericValue: Double(summary.anomalies.count))
            ],
            summary: summary.summaryText
        )

        return ToolResult(
            toolName: "get_day_context",
            records: [record],
            aggregates: [aggregate],
            ambiguities: [],
            citations: [ToolCitation(ref: record.ref, label: record.title)],
            resolvedTimeRange: dayAnchorLabel(for: targetDate),
            resolvedDateBounds: ResolvedDateBounds(start: targetDate, end: dayEnd)
        )
    }

    private func getRecordDetails(arguments: [String: Any]) async throws -> ToolResult {
        let refs = entityRefs(from: arguments["refs"])
        let records = try await detailedRecords(for: refs)
        return ToolResult(
            toolName: "get_record_details",
            records: records,
            aggregates: [],
            ambiguities: [],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func aggregateSeline(
        arguments: [String: Any]
    ) async throws -> ToolResult {
        let metric = stringValue(arguments["metric"])?.lowercased() ?? "count"
        let groupBy = stringValue(arguments["group_by"])?.lowercased()
        let filters = arguments["filters"] as? [String: Any] ?? [:]
        let scopes = stringArray(filters["scopes"])
        let query = stringValue(filters["query"])
        let timeRange = stringValue(filters["time_range"]) ?? query
        let resolvedBounds = resolvedDateRange(from: timeRange)
        let explicitRefs = entityRefs(from: filters["entity_refs"])
        let resolvedRefs = explicitRefs

        if scopes.contains("receipt") || metric.contains("spend") || metric.contains("amount") {
            let result = try await aggregateReceipts(metric: metric, groupBy: groupBy, query: query, timeRange: timeRange, refs: resolvedRefs)
            return applyingResolvedDateContext(to: result, bounds: resolvedBounds)
        }

        if scopes.contains("event") || metric.contains("event") || metric.contains("calendar") {
            let result = aggregateEvents(metric: metric, groupBy: groupBy, query: query, timeRange: timeRange)
            return applyingResolvedDateContext(to: result, bounds: resolvedBounds)
        }

        if scopes.contains("email") || metric.contains("email") {
            let result = aggregateEmails(metric: metric, groupBy: groupBy, query: query, timeRange: timeRange)
            return applyingResolvedDateContext(to: result, bounds: resolvedBounds)
        }

        let result = try await aggregateVisits(
            metric: metric,
            groupBy: groupBy,
            query: query,
            timeRange: timeRange,
            refs: resolvedRefs
        )
        return applyingResolvedDateContext(to: result, bounds: resolvedBounds)
    }

    private func traverseRelations(arguments: [String: Any]) async throws -> ToolResult {
        let seedRefs = entityRefs(from: arguments["seed_refs"])
        let depth = max(1, intValue(arguments["depth"]) ?? 1)
        let relationTypes = Set(stringArray(arguments["relation_types"]).map { $0.lowercased() })

        var queue = seedRefs
        var visited = Set(seedRefs.map(\.identifier))
        var collected: [EvidenceRecord] = []

        for _ in 0..<depth {
            var nextQueue: [EntityRef] = []
            for ref in queue {
                let relatedRefs = try await relatedEntityRefs(for: ref, relationTypes: relationTypes)
                let newRefs = relatedRefs.filter { visited.insert($0.identifier).inserted }
                let newRecords = try await detailedRecords(for: newRefs)
                collected.append(contentsOf: newRecords)
                nextQueue.append(contentsOf: newRefs)
            }
            queue = nextQueue
            if queue.isEmpty { break }
        }

        let deduped = dedupeRecords(collected)
        return ToolResult(
            toolName: "traverse_relations",
            records: deduped,
            aggregates: [],
            ambiguities: [],
            citations: deduped.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func getCurrentContext() async throws -> ToolResult {
        let now = Date()
        var attributes: [String: String] = [
            "date": ISO8601DateFormatter().string(from: now),
            "timezone": TimeZone.current.identifier
        ]
        var livePlaceCard: LivePlacePreviewInfo?

        if let currentLocation = sharedLocationManager.currentLocation {
            attributes["latitude"] = String(format: "%.5f", currentLocation.coordinate.latitude)
            attributes["longitude"] = String(format: "%.5f", currentLocation.coordinate.longitude)
            attributes["accuracy_meters"] = String(format: "%.0f", currentLocation.horizontalAccuracy)

            if weatherService.weatherData == nil {
                await weatherService.fetchWeather(for: currentLocation)
            }

            if let weather = weatherService.weatherData {
                attributes["weather"] = "\(weather.temperature)C, \(weather.description)"
                attributes["location_name"] = weather.locationName
            }

            if let currentPlace = await currentLocationResult(for: currentLocation, fallbackName: attributes["location_name"]) {
                attributes["location_name"] = currentPlace.name
                attributes["address"] = currentPlace.address
                livePlaceCard = LivePlacePreviewInfo(
                    results: [currentPlace],
                    selectedPlaceId: currentPlace.id,
                    prompt: "Tap the card or map to view details for your current location."
                )
            }
        }

        let record = EvidenceRecord(
            ref: EntityRef(type: .currentContext, id: "now", title: "Current context"),
            title: "Current context",
            summary: attributes["address"] ?? attributes["location_name"] ?? "Current time, timezone, location, and weather when available.",
            attributes: attributes
        )

        return ToolResult(
            toolName: "get_current_context",
            records: [record],
            aggregates: [],
            ambiguities: [],
            citations: [ToolCitation(ref: record.ref, label: record.title)],
            presentation: livePlaceCard.map { AgentPresentation(livePlaceCard: $0) }
        )
    }

    private func prepareEventDraft(arguments: [String: Any]) async throws -> ToolResult {
        let userRequest = stringValue(arguments["user_request"]) ?? ""
        let context = ConversationActionContext(
            conversationHistory: [],
            recentTopics: [],
            lastNoteCreated: nil,
            lastEventCreated: nil
        )
        let action = await conversationActionHandler.startAction(
            from: userRequest,
            actionType: .createEvent,
            conversationContext: context
        )

        guard let eventDraft = eventDraftInfo(from: action.extractedInfo) else {
            return ToolResult(
                toolName: "prepare_event_draft",
                ambiguities: eventDraftAmbiguities(from: action.extractedInfo),
                actionDraft: AgentActionDraft(type: .createEvent, eventDrafts: nil),
                presentation: nil
            )
        }

        let record = EvidenceRecord(
            ref: EntityRef(type: .event, id: eventDraft.id.uuidString, title: eventDraft.title),
            title: eventDraft.title,
            summary: eventDraft.notes ?? eventDraft.location ?? eventDraft.formattedDateTime,
            timestamps: [EvidenceTimestamp(label: "date", value: isoDate(eventDraft.date))],
            attributes: [
                "category": eventDraft.category,
                "location": eventDraft.location ?? "",
                "recurrence": eventDraft.recurrenceFrequency?.rawValue ?? "",
                "reminder": eventDraft.reminderText
            ].filter { !$0.value.isEmpty }
        )

        return ToolResult(
            toolName: "prepare_event_draft",
            records: [record],
            citations: [ToolCitation(ref: record.ref, label: record.title)],
            actionDraft: AgentActionDraft(type: .createEvent, eventDrafts: [eventDraft]),
            presentation: AgentPresentation(eventDraftCard: [eventDraft])
        )
    }

    private func prepareNoteDraft(arguments: [String: Any]) async throws -> ToolResult {
        let userRequest = stringValue(arguments["user_request"]) ?? ""
        let context = ConversationActionContext(
            conversationHistory: [],
            recentTopics: [],
            lastNoteCreated: nil,
            lastEventCreated: nil
        )
        let action = await conversationActionHandler.startAction(
            from: userRequest,
            actionType: .createNote,
            conversationContext: context
        )

        let fallbackTitle = inferredNoteTitle(from: userRequest)
        guard let title = action.extractedInfo.noteTitle ?? fallbackTitle,
              let content = normalizedNoteContent(action.extractedInfo.noteContent) else {
            return ToolResult(
                toolName: "prepare_note_draft",
                ambiguities: noteDraftAmbiguities(from: action.extractedInfo, userRequest: userRequest)
            )
        }

        let noteDraft = NoteDraftInfo(title: title, content: content)
        let record = EvidenceRecord(
            ref: EntityRef(type: .note, id: noteDraft.id.uuidString, title: title),
            title: title,
            summary: String(content.prefix(220))
        )

        return ToolResult(
            toolName: "prepare_note_draft",
            records: [record],
            citations: [ToolCitation(ref: record.ref, label: record.title)],
            actionDraft: AgentActionDraft(type: .createNote, noteDraft: noteDraft),
            presentation: AgentPresentation(noteDraftCard: noteDraft)
        )
    }

    private func refreshInboxAndGetLatestEmail(arguments: [String: Any]) async throws -> ToolResult {
        let scope = stringValue(arguments["scope"])
        return try await latestEmailToolResult(scope: scope, forceRefresh: true)
    }

    private func getEmailDetails(arguments: [String: Any]) async throws -> ToolResult {
        let emailId =
            stringValue(arguments["email_id"]) ??
            entityRef(from: arguments["email_ref"])?.id

        guard let emailId else {
            return ToolResult(
                toolName: "get_email_details",
                ambiguities: [ToolAmbiguity(question: "Which email do you want me to open?", options: [])]
            )
        }

        let allEmails = emailService.inboxEmails + emailService.sentEmails
        guard let email = allEmails.first(where: { $0.id == emailId }) else {
            return ToolResult(
                toolName: "get_email_details",
                ambiguities: [ToolAmbiguity(question: "I couldn't find that email in your current mailbox.", options: [])]
            )
        }

        let enrichedEmail = try await enrichedEmailForPreview(email)
        let preview = emailPreviewInfo(from: enrichedEmail)
        let record = emailEvidenceRecord(enrichedEmail).map { [$0] } ?? []

        return ToolResult(
            toolName: "get_email_details",
            records: record,
            citations: record.map { ToolCitation(ref: $0.ref, label: $0.title) },
            actionDraft: AgentActionDraft(type: .latestEmail, requiresConfirmation: false, emailPreview: preview),
            presentation: AgentPresentation(emailPreviewCard: preview)
        )
    }

    private func resolveLivePlace(arguments: [String: Any]) async throws -> ToolResult {
        let query = stringValue(arguments["query"]) ?? ""
        let limit = intValue(arguments["limit"]) ?? 5
        let radiusMeters = intValue(arguments["radius_meters"]) ?? 30000
        let openNow = boolValue(arguments["open_now"]) ?? false
        let results = await resolvedNearbyPlaceResults(
            query: query,
            limit: limit,
            radiusMeters: radiusMeters,
            openNow: openNow
        )

        guard let primary = results.first else {
            return ToolResult(
                toolName: "resolve_live_place",
                ambiguities: [ToolAmbiguity(question: "I couldn't find a nearby match for that place. If location access is off, enable it and try again.", options: [])]
            )
        }

        let records = results.map(placeEvidenceRecord(from:))

        let options = results.dropFirst().prefix(3).map { "\($0.name) — \($0.address)" }
        let prompt = options.isEmpty
            ? "I found the closest nearby match. Tap the card or map pin to open details."
            : "I picked the closest nearby match. Tap a place or map pin to open details, or choose one of the alternatives."

        return ToolResult(
            toolName: "resolve_live_place",
            records: records,
            ambiguities: options.isEmpty ? [] : [ToolAmbiguity(question: "If you meant a different nearby address, tell me which one.", options: Array(options))],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) },
            presentation: AgentPresentation(
                livePlaceCard: LivePlacePreviewInfo(
                    results: results,
                    selectedPlaceId: primary.id,
                    prompt: prompt
                )
            )
        )
    }

    private func prepareSavedPlaceDraft(arguments: [String: Any]) async throws -> ToolResult {
        guard let placeId = stringValue(arguments["place_id"]) else {
            return ToolResult(
                toolName: "prepare_saved_place_draft",
                ambiguities: [ToolAmbiguity(question: "Which live place should I save?", options: [])]
            )
        }

        let folderName = stringValue(arguments["folder_name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveResult = await livePlaceResult(for: placeId)

        guard let liveResult else {
            return ToolResult(
                toolName: "prepare_saved_place_draft",
                ambiguities: [ToolAmbiguity(question: "I couldn't resolve that place to save.", options: [])]
            )
        }

        let folders = savedPlaceFolderNames()
        let ambiguities: [ToolAmbiguity]
        if let folderName, !folderName.isEmpty {
            ambiguities = []
        } else {
            ambiguities = [
                ToolAmbiguity(
                    question: "Which folder should I save \(liveResult.name) into?",
                    options: Array(folders.prefix(8))
                )
            ]
        }

        let records = [
            EvidenceRecord(
                ref: EntityRef(type: .nearbyPlace, id: liveResult.id, title: liveResult.name),
                title: liveResult.name,
                summary: liveResult.address,
                attributes: ["folder": folderName ?? ""].filter { !$0.value.isEmpty }
            )
        ]

        return ToolResult(
            toolName: "prepare_saved_place_draft",
            records: records,
            ambiguities: ambiguities,
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) },
            actionDraft: AgentActionDraft(
                type: .saveLocation,
                placeDraft: SavedPlaceDraftInfo(place: liveResult, folderName: folderName)
            ),
            presentation: AgentPresentation(
                livePlaceCard: LivePlacePreviewInfo(
                    results: [liveResult],
                    selectedPlaceId: liveResult.id,
                    prompt: folderName == nil ? "Pick a folder after you confirm the address." : "Confirm if you want me to save this exact address."
                )
            )
        )
    }

    private func listSavedPlaceFolders() async throws -> ToolResult {
        let folders = savedPlaceFolderNames()
        let rows = folders.map { folder in
            ToolAggregateRow(key: folder, value: "folder")
        }

        return ToolResult(
            toolName: "list_saved_place_folders",
            aggregates: [
                ToolAggregate(
                    title: "Saved place folders",
                    metric: "folders",
                    groupBy: nil,
                    rows: rows,
                    summary: folders.isEmpty ? "No saved place folders yet." : "Existing saved place folders."
                )
            ]
        )
    }

    private func findSavedPlacesWithinETA(arguments: [String: Any]) async throws -> ToolResult {
        guard let origin = sharedLocationManager.currentLocation else {
            return ToolResult(
                toolName: "find_saved_places_within_eta",
                ambiguities: [
                    ToolAmbiguity(
                        question: "I need your current location to calculate drive-time proximity. Turn on location access and try again.",
                        options: []
                    )
                ]
            )
        }

        let rawQuery = stringValue(arguments["query"]) ?? ""
        let maxMinutes = max(1, intValue(arguments["max_minutes"]) ?? inferredTravelLimitMinutes(from: rawQuery) ?? 20)
        let limit = min(max(intValue(arguments["limit"]) ?? 8, 1), 20)
        let folderName = stringValue(arguments["folder_name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let matchingPlaces = filteredSavedPlacesForTravelQuery(
            query: rawQuery,
            folderName: folderName
        )

        guard !matchingPlaces.isEmpty else {
            return ToolResult(
                toolName: "find_saved_places_within_eta",
                ambiguities: [
                    ToolAmbiguity(
                        question: "I couldn’t find any saved places matching that filter yet. Do you want a different folder or a broader place type?",
                        options: Array(savedPlaceFolderNames().prefix(4))
                    )
                ]
            )
        }

        let sortedCandidates = matchingPlaces.sorted { lhs, rhs in
            directDistance(from: origin, to: lhs) < directDistance(from: origin, to: rhs)
        }

        let maxCandidates = min(max(limit * 3, 12), 24)
        let shortlisted = Array(sortedCandidates.prefix(maxCandidates))
        var matches: [(place: SavedPlace, eta: ETAResult)] = []

        for place in shortlisted {
            let destination = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            guard let etaResult = try? await navigationService.calculateETA(from: origin, to: destination) else {
                continue
            }

            if etaResult.durationSeconds <= maxMinutes * 60 {
                matches.append((place: place, eta: etaResult))
            }
        }

        matches.sort { lhs, rhs in
            if lhs.eta.durationSeconds == rhs.eta.durationSeconds {
                return lhs.place.displayName.localizedCaseInsensitiveCompare(rhs.place.displayName) == .orderedAscending
            }
            return lhs.eta.durationSeconds < rhs.eta.durationSeconds
        }

        guard !matches.isEmpty else {
            return ToolResult(
                toolName: "find_saved_places_within_eta",
                ambiguities: [
                    ToolAmbiguity(
                        question: "I didn’t find any matching saved places within \(maxMinutes) minutes of your current location. Do you want me to widen it to 30 minutes or look in a different folder?",
                        options: ["30 minutes", "45 minutes"] + Array(savedPlaceFolderNames().prefix(2))
                    )
                ]
            )
        }

        let limitedMatches = Array(matches.prefix(limit))
        let records = limitedMatches.map { savedPlaceETAEvidenceRecord(place: $0.place, eta: $0.eta) }
        let rows = limitedMatches.map {
            ToolAggregateRow(
                key: $0.place.displayName,
                value: "\($0.eta.durationText) • \($0.place.address)",
                numericValue: Double($0.eta.durationSeconds) / 60.0,
                ref: EntityRef(type: .location, id: $0.place.id.uuidString, title: $0.place.displayName)
            )
        }

        return ToolResult(
            toolName: "find_saved_places_within_eta",
            records: records,
            aggregates: [
                ToolAggregate(
                    title: "Saved places within \(maxMinutes) minutes",
                    metric: "drive_eta",
                    groupBy: nil,
                    rows: rows,
                    summary: "\(limitedMatches.count) saved place\(limitedMatches.count == 1 ? "" : "s") within \(maxMinutes) minutes."
                )
            ],
            ambiguities: [],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func searchNearbyPlaces(arguments: [String: Any]) async throws -> ToolResult {
        let query = stringValue(arguments["query"]) ?? ""
        let limit = intValue(arguments["limit"]) ?? 6
        let radiusMeters = intValue(arguments["radius_meters"]) ?? 30000
        let openNow = boolValue(arguments["open_now"]) ?? false
        let filtered = await resolvedNearbyPlaceResults(
            query: query,
            limit: limit,
            radiusMeters: radiusMeters,
            openNow: openNow
        )

        guard !filtered.isEmpty else {
            return ToolResult(
                toolName: "search_nearby_places",
                ambiguities: [ToolAmbiguity(question: "I couldn't find any nearby matches for that search. If location access is off, enable it and try again.", options: [])]
            )
        }

        let records = filtered.map(placeEvidenceRecord(from:))
        let primary = filtered.first
        let alternativeOptions = filtered.dropFirst().prefix(3).map { "\($0.name) — \($0.address)" }

        return ToolResult(
            toolName: "search_nearby_places",
            records: records,
            aggregates: [],
            ambiguities: alternativeOptions.isEmpty
                ? []
                : [ToolAmbiguity(question: "If you meant a different nearby address, tell me which one.", options: Array(alternativeOptions))],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) },
            presentation: primary.map {
                AgentPresentation(
                    livePlaceCard: LivePlacePreviewInfo(
                        results: filtered,
                        selectedPlaceId: $0.id,
                        prompt: "Tap a place or map pin to open details."
                    )
                )
            }
        )
    }

    private func getPlaceDetails(arguments: [String: Any]) async throws -> ToolResult {
        guard let placeId = stringValue(arguments["place_id"]) else {
            return ToolResult(
                toolName: "get_place_details",
                ambiguities: [ToolAmbiguity(question: "Which place do you want details for?", options: [])]
            )
        }

        if !placeId.hasPrefix("mapkit:"),
           let details = try? await mapsService.getPlaceDetails(placeId: placeId) {
            let attributes: [String: String] = [
                "address": details.address,
                "phone": details.phone ?? "",
                "website": details.website ?? "",
                "rating": details.rating.map { String($0) } ?? "",
                "user_ratings_total": String(details.totalRatings),
                "price_level": details.priceLevel.map { String($0) } ?? "",
                "is_open_now": details.isOpenNow.map { $0 ? "true" : "false" } ?? ""
            ].filter { !$0.value.isEmpty }

            let record = EvidenceRecord(
                ref: EntityRef(type: .nearbyPlace, id: placeId, title: details.name),
                title: details.name,
                summary: details.address,
                attributes: attributes
            )
            return ToolResult(
                toolName: "get_place_details",
                records: [record],
                aggregates: [],
                ambiguities: [],
                citations: [ToolCitation(ref: record.ref, label: record.title)]
            )
        }

        if let liveResult = await livePlaceResult(for: placeId) {
            let record = placeEvidenceRecord(from: liveResult)
            return ToolResult(
                toolName: "get_place_details",
                records: [record],
                aggregates: [],
                ambiguities: [],
                citations: [ToolCitation(ref: record.ref, label: record.title)]
            )
        }

        return ToolResult(
            toolName: "get_place_details",
            ambiguities: [ToolAmbiguity(question: "I couldn't load more details for that place right now.", options: [])]
        )
    }

    private func getETA(arguments: [String: Any]) async throws -> ToolExecution {
        guard
            let destination = arguments["destination"] as? [String: Any],
            let origin = sharedLocationManager.currentLocation
        else {
            let result = ToolResult(toolName: "get_eta", records: [], aggregates: [], ambiguities: [], citations: [])
            return ToolExecution(result: result, locationInfo: nil)
        }

        let resolvedDestination = try await resolveDestination(from: destination)
        let etaResult = try await navigationService.calculateETA(from: origin, to: resolvedDestination.coordinate)

        let record = EvidenceRecord(
            ref: EntityRef(type: .location, id: resolvedDestination.entityId, title: resolvedDestination.name),
            title: resolvedDestination.name,
            summary: "Drive ETA \(etaResult.durationText), distance \(etaResult.distanceText).",
            attributes: [
                "eta": etaResult.durationText,
                "distance": etaResult.distanceText,
                "address": resolvedDestination.address
            ]
        )

        let locationInfo = ETALocationInfo(
            originName: weatherService.weatherData?.locationName,
            originAddress: nil,
            originLatitude: origin.coordinate.latitude,
            originLongitude: origin.coordinate.longitude,
            destinationName: resolvedDestination.name,
            destinationAddress: resolvedDestination.address,
            destinationLatitude: resolvedDestination.coordinate.latitude,
            destinationLongitude: resolvedDestination.coordinate.longitude,
            driveTime: etaResult.durationText,
            distance: etaResult.distanceText
        )

        let result = ToolResult(
            toolName: "get_eta",
            records: [record],
            aggregates: [],
            ambiguities: [],
            citations: [ToolCitation(ref: record.ref, label: record.title)]
        )
        return ToolExecution(result: result, locationInfo: locationInfo)
    }

    // MARK: - Aggregation

    private func aggregateVisits(
        metric: String,
        groupBy: String?,
        query: String?,
        timeRange: String?,
        refs: [EntityRef]
    ) async throws -> ToolResult {
        let dateBounds = resolvedDateRange(from: timeRange)
        let allVisits = try await fetchVisits(dateBounds: dateBounds)
        let visitPeopleMap = await peopleManager.getPeopleForVisits(visitIds: allVisits.map(\.id))

        let explicitPlaceIds = refs.compactMap(placeId(from:))
        let explicitPersonIds = refs.compactMap(personId(from:))
        let candidatePlaceIds = Set(explicitPlaceIds)
        let candidatePersonIds = Set(explicitPersonIds)

        let linkedReceipts = VisitReceiptLinkStore.allLinks()
        let notesById = Dictionary(uniqueKeysWithValues: notesManager.notes.map { ($0.id, $0) })

        let filtered = allVisits.filter { visit in
            let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
            let people = visitPeopleMap[visit.id] ?? []
            let linkedReceipt = linkedReceipts[visit.id].flatMap { notesById[$0] }

            if !candidatePlaceIds.isEmpty && !candidatePlaceIds.contains(visit.savedPlaceId) {
                return false
            }
            if !candidatePersonIds.isEmpty {
                let visitPersonIds = Set(people.map(\.id))
                guard !visitPersonIds.isDisjoint(with: candidatePersonIds) else { return false }
            }
            return visitMatchesQuery(visit: visit, place: place, people: people, linkedReceipt: linkedReceipt, query: query)
        }

        let rows = aggregateVisitRows(visits: filtered, groupBy: groupBy)
        let matchingPlaces = filtered.compactMap { visit in
            locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        }
        let uniquePlaces = Array(Dictionary(grouping: matchingPlaces, by: \.id).values.compactMap(\.first))
        let placeRecords = uniquePlaces.map(placeEvidenceRecord(_:))

        let aggregate = ToolAggregate(
            title: aggregateTitle(metric: metric, scope: "visits", groupBy: groupBy),
            metric: metric,
            groupBy: groupBy,
            rows: rows,
            summary: "Matched \(filtered.count) visits."
        )

        return ToolResult(
            toolName: "aggregate_seline",
            records: placeRecords,
            aggregates: [aggregate],
            ambiguities: [],
            citations: placeRecords.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func aggregateReceipts(
        metric: String,
        groupBy: String?,
        query: String?,
        timeRange: String?,
        refs: [EntityRef]
    ) async throws -> ToolResult {
        await notesManager.ensureReceiptDataAvailable()
        let allYearlyStats = notesManager.getReceiptStatistics()
        let allReceipts = allYearlyStats.flatMap { $0.monthlySummaries }.flatMap(\.receipts)
        let dateBounds = resolvedDateRange(from: timeRange)
        let shouldApplyEntityScope = shouldApplyReceiptEntityScope(query: query, refs: refs, dateBounds: dateBounds)
        let personIds = shouldApplyEntityScope ? Set(refs.compactMap(personId(from:))) : []
        let placeIds = shouldApplyEntityScope ? Set(refs.compactMap(placeId(from:))) : []
        let visitIds = shouldApplyEntityScope ? Set(refs.compactMap(visitId(from:))) : []
        let receiptIds = Set(refs.compactMap(receiptId(from:)))
        var receiptPeopleMap: [UUID: Set<UUID>] = [:]
        var linkedReceiptIds = receiptIds

        if !placeIds.isEmpty {
            let relatedVisits = try await fetchVisits(dateBounds: dateBounds, placeIds: Array(placeIds))
            for visit in relatedVisits {
                if let linkedReceiptId = VisitReceiptLinkStore.receiptId(for: visit.id) {
                    linkedReceiptIds.insert(linkedReceiptId)
                }
            }
        }

        if !visitIds.isEmpty {
            for visitId in visitIds {
                if let linkedReceiptId = VisitReceiptLinkStore.receiptId(for: visitId) {
                    linkedReceiptIds.insert(linkedReceiptId)
                }
            }
        }

        if !personIds.isEmpty {
            for receipt in allReceipts {
                let people = await peopleForReceipt(receipt.noteId)
                receiptPeopleMap[receipt.noteId] = Set(people.map(\.id))
            }
        }

        let baseFiltered = allReceipts.filter { receipt in
            if let dateBounds, !(receipt.date >= dateBounds.start && receipt.date < dateBounds.end) {
                return false
            }
            if !personIds.isEmpty {
                let people = receiptPeopleMap[receipt.noteId] ?? []
                guard !people.isDisjoint(with: personIds) else { return false }
            }
            if !linkedReceiptIds.isEmpty && !linkedReceiptIds.contains(receipt.noteId) {
                return false
            }
            return true
        }
        let queryFiltered = baseFiltered.filter { receiptMatchesQuery($0, query: query) }
        let hasGroundedScope = dateBounds != nil
            || !personIds.isEmpty
            || !placeIds.isEmpty
            || !visitIds.isEmpty
            || !receiptIds.isEmpty
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filtered = hasGroundedScope && !trimmedQuery.isEmpty && queryFiltered.isEmpty
            ? baseFiltered
            : queryFiltered

        let rows = aggregateReceiptRows(receipts: filtered, groupBy: groupBy)
        let records = filtered.prefix(8).compactMap(receiptEvidenceRecord(_:))
        let total = filtered.reduce(0) { $0 + $1.amount }
        let aggregate = ToolAggregate(
            title: aggregateTitle(metric: metric, scope: "receipts", groupBy: groupBy),
            metric: metric,
            groupBy: groupBy,
            rows: rows,
            summary: "Matched \(filtered.count) receipts totaling \(CurrencyParser.formatAmount(total))."
        )
        return ToolResult(
            toolName: "aggregate_seline",
            records: records,
            aggregates: [aggregate],
            ambiguities: [],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func shouldApplyReceiptEntityScope(
        query: String?,
        refs: [EntityRef],
        dateBounds: (start: Date, end: Date)?
    ) -> Bool {
        guard dateBounds != nil else {
            return true
        }

        let scopedRefs = refs.filter { ref in
            switch ref.type {
            case .person, .location, .visit:
                return true
            default:
                return false
            }
        }
        guard !scopedRefs.isEmpty else {
            return true
        }

        guard let query = query?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return true
        }

        return scopedRefs.contains { ref in
            guard let title = ref.title?.lowercased(), !title.isEmpty else {
                return false
            }
            if query.contains(title) {
                return true
            }
            let titleTerms = searchableTerms(from: title)
            return !titleTerms.isEmpty && titleTerms.allSatisfy { query.contains($0) }
        }
    }

    private func aggregateEvents(
        metric: String,
        groupBy: String?,
        query: String?,
        timeRange: String?
    ) -> ToolResult {
        let tasks = taskManager.getAllTasksIncludingArchived()
        let dateBounds = resolvedDateRange(from: timeRange)
        let filtered = tasks.filter { task in
            let taskDate = task.targetDate ?? task.scheduledTime ?? task.createdAt
            if let dateBounds, !(taskDate >= dateBounds.start && taskDate < dateBounds.end) {
                return false
            }
            return taskMatchesQuery(task, query: query)
        }
        let rows = aggregateEventRows(tasks: filtered, groupBy: groupBy)
        let records = filtered.prefix(8).compactMap(eventEvidenceRecord(_:))
        let aggregate = ToolAggregate(
            title: aggregateTitle(metric: metric, scope: "events", groupBy: groupBy),
            metric: metric,
            groupBy: groupBy,
            rows: rows,
            summary: "Matched \(filtered.count) events."
        )
        return ToolResult(
            toolName: "aggregate_seline",
            records: records,
            aggregates: [aggregate],
            ambiguities: [],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    private func aggregateEmails(
        metric: String,
        groupBy: String?,
        query: String?,
        timeRange: String?
    ) -> ToolResult {
        let emails = emailService.inboxEmails + emailService.sentEmails
        let dateBounds = resolvedDateRange(from: timeRange)
        let filtered = emails.filter { email in
            if let dateBounds, !(email.timestamp >= dateBounds.start && email.timestamp < dateBounds.end) {
                return false
            }
            return emailMatchesQuery(email, query: query)
        }
        let rows = aggregateEmailRows(emails: filtered, groupBy: groupBy)
        let records = filtered.prefix(8).compactMap(emailEvidenceRecord(_:))
        let aggregate = ToolAggregate(
            title: aggregateTitle(metric: metric, scope: "emails", groupBy: groupBy),
            metric: metric,
            groupBy: groupBy,
            rows: rows,
            summary: "Matched \(filtered.count) emails."
        )
        return ToolResult(
            toolName: "aggregate_seline",
            records: records,
            aggregates: [aggregate],
            ambiguities: [],
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) }
        )
    }

    // MARK: - Detail loading

    private func detailedRecords(for refs: [EntityRef]) async throws -> [EvidenceRecord] {
        var records: [EvidenceRecord] = []
        for ref in refs {
            switch ref.type {
            case .daySummary:
                if let summaryId = UUID(uuidString: ref.id),
                   let summary = await daySummaryService.summary(id: summaryId) {
                    records.append(daySummaryEvidenceRecord(summary))
                }
            case .email:
                if let email = (emailService.inboxEmails + emailService.sentEmails).first(where: { $0.id == ref.id }),
                   let record = emailEvidenceRecord(email) {
                    records.append(record)
                }
            case .note:
                if let noteId = UUID(uuidString: ref.id),
                   let note = notesManager.notes.first(where: { $0.id == noteId }),
                   let record = noteEvidenceRecord(note) {
                    records.append(record)
                }
            case .receipt:
                if let noteId = UUID(uuidString: ref.id),
                   let receipt = await receiptStat(for: noteId),
                   let record = receiptEvidenceRecord(receipt) {
                    records.append(record)
                }
            case .event:
                if let task = taskManager.getAllTasksIncludingArchived().first(where: { $0.id == ref.id }),
                   let record = eventEvidenceRecord(task) {
                    records.append(record)
                }
            case .location:
                if let placeId = UUID(uuidString: ref.id),
                   let place = locationsManager.savedPlaces.first(where: { $0.id == placeId }) {
                    records.append(placeEvidenceRecord(place))
                }
            case .visit:
                if let visitId = UUID(uuidString: ref.id),
                   let visit = try await fetchVisit(id: visitId),
                   let record = await visitEvidenceRecord(visit) {
                    records.append(record)
                }
            case .person:
                if let personId = UUID(uuidString: ref.id),
                   let person = peopleManager.getPerson(by: personId) {
                    records.append(personEvidenceRecord(person))
                }
            case .nearbyPlace:
                if let details = try? await mapsService.getPlaceDetails(placeId: ref.id) {
                    let record = EvidenceRecord(
                        ref: ref,
                        title: details.name,
                        summary: details.address,
                        attributes: [
                            "address": details.address,
                            "rating": details.rating.map { String($0) } ?? "",
                            "website": details.website ?? ""
                        ].filter { !$0.value.isEmpty }
                    )
                    records.append(record)
                }
            case .currentContext, .aggregate, .webResult:
                continue
            }
        }
        return dedupeRecords(records)
    }

    private func relatedEntityRefs(for ref: EntityRef, relationTypes: Set<String>) async throws -> [EntityRef] {
        switch ref.type {
        case .daySummary:
            guard let summaryId = UUID(uuidString: ref.id) else { return [] }
            return await daySummaryService.relatedEntityRefs(for: summaryId, relationTypes: relationTypes)
        case .location:
            guard let placeId = UUID(uuidString: ref.id) else { return [] }
            let visits = try await fetchVisits(dateBounds: nil, placeIds: [placeId])
            var refs = visits.prefix(6).map { visit in
                EntityRef(type: .visit, id: visit.id.uuidString, title: locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName)
            }
            if relationTypes.isEmpty || relationTypes.contains("people") {
                let peopleMap = await peopleManager.getPeopleForVisits(visitIds: visits.map(\.id))
                let people = dedupePeople(peopleMap.values.flatMap { $0 })
                refs.append(contentsOf: people.prefix(5).map { EntityRef(type: .person, id: $0.id.uuidString, title: $0.name) })
            }
            return refs
        case .visit:
            guard let visitId = UUID(uuidString: ref.id),
                  let visit = try await fetchVisit(id: visitId)
            else { return [] }
            var refs: [EntityRef] = []
            if relationTypes.isEmpty || relationTypes.contains("place") || relationTypes.contains("location") {
                refs.append(EntityRef(type: .location, id: visit.savedPlaceId.uuidString, title: locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName))
            }
            if relationTypes.isEmpty || relationTypes.contains("people") {
                let people = await peopleManager.getPeopleForVisit(visitId: visit.id)
                refs.append(contentsOf: people.map { EntityRef(type: .person, id: $0.id.uuidString, title: $0.name) })
            }
            if relationTypes.isEmpty || relationTypes.contains("receipt") {
                if let receiptId = VisitReceiptLinkStore.receiptId(for: visit.id) {
                    refs.append(EntityRef(type: .receipt, id: receiptId.uuidString, title: notesManager.notes.first(where: { $0.id == receiptId })?.title))
                }
            }
            return refs
        case .person:
            guard let personId = UUID(uuidString: ref.id) else { return [] }
            let visitIds = await peopleManager.getVisitIdsForPerson(personId: personId)
            let receiptIds = await peopleManager.getReceiptIdsForPerson(personId: personId)
            let favouritePlaceIds = await peopleManager.getFavouritePlacesForPerson(personId: personId)
            var refs = visitIds.prefix(6).map { EntityRef(type: .visit, id: $0.uuidString, title: nil) }
            refs.append(contentsOf: receiptIds.prefix(6).map { EntityRef(type: .receipt, id: $0.uuidString, title: nil) })
            refs.append(contentsOf: favouritePlaceIds.prefix(6).map { placeId in
                EntityRef(type: .location, id: placeId.uuidString, title: locationsManager.savedPlaces.first(where: { $0.id == placeId })?.displayName)
            })
            return refs
        case .receipt:
            guard let receiptId = UUID(uuidString: ref.id) else { return [] }
            let people = await peopleManager.getPeopleForReceipt(noteId: receiptId)
            var refs = people.map { EntityRef(type: .person, id: $0.id.uuidString, title: $0.name) }
            let linkedVisitIds = VisitReceiptLinkStore.allLinks()
                .filter { $0.value == receiptId }
                .map(\.key)
            refs.append(contentsOf: linkedVisitIds.map { EntityRef(type: .visit, id: $0.uuidString, title: nil) })
            return refs
        case .event:
            // Semantically search for emails related to this event by its title.
            // There is no explicit event↔email link table, so we use vector similarity
            // with the event title as the query to surface confirmation emails, invitations,
            // and any other communications about this event.
            guard let title = ref.title, !title.isEmpty else { return [] }
            let emailResults = (try? await vectorSearch.search(
                query: title,
                documentTypes: [.email],
                limit: 5,
                dateRange: nil,
                preferHistorical: true,
                retrievalMode: .exhaustive
            )) ?? []
            return emailResults.map { EntityRef(type: .email, id: $0.documentId, title: $0.title) }
        case .email:
            // Search for calendar events semantically related to this email's title/subject.
            guard let title = ref.title, !title.isEmpty else { return [] }
            let eventResults = (try? await vectorSearch.search(
                query: title,
                documentTypes: [.task],
                limit: 5,
                dateRange: nil,
                preferHistorical: true,
                retrievalMode: .exhaustive
            )) ?? []
            return eventResults.map { EntityRef(type: .event, id: $0.documentId, title: $0.title) }
        default:
            return []
        }
    }

    // MARK: - Evidence builders

    private func evidenceRecord(from result: VectorSearchService.SearchResult) -> EvidenceRecord? {
        if result.documentType == .visit {
            return visitSearchEvidenceRecord(from: result)
        }

        guard let item = vectorSearch.evidenceItem(from: result) else { return nil }
        return evidenceRecord(from: item)
    }

    private func evidenceRecord(from item: RelevantContentInfo) -> EvidenceRecord? {
        switch item.contentType {
        case .email:
            guard let id = item.emailId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .email, id: id, title: item.emailSubject),
                title: item.emailSubject ?? item.emailSender ?? "Email",
                summary: item.emailSnippet ?? "",
                timestamps: item.emailDate.map { [EvidenceTimestamp(label: "date", value: isoDate($0))] } ?? [],
                attributes: [
                    "sender": item.emailSender ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .note:
            guard let id = item.noteId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .note, id: id.uuidString, title: item.noteTitle),
                title: item.noteTitle ?? "Note",
                summary: item.noteSnippet ?? "",
                attributes: [
                    "folder": item.noteFolder ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .receipt:
            guard let id = item.receiptId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .receipt, id: id.uuidString, title: item.receiptTitle),
                title: item.receiptTitle ?? "Receipt",
                summary: item.receiptCategory ?? "",
                timestamps: item.receiptDate.map { [EvidenceTimestamp(label: "date", value: isoDate($0))] } ?? [],
                attributes: [
                    "amount": item.receiptAmount.map { CurrencyParser.formatAmount($0) } ?? "",
                    "category": item.receiptCategory ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .event:
            guard let id = item.eventId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .event, id: id.uuidString, title: item.eventTitle),
                title: item.eventTitle ?? "Event",
                summary: item.eventCategory ?? "",
                timestamps: item.eventDate.map { [EvidenceTimestamp(label: "date", value: isoDate($0))] } ?? [],
                attributes: [
                    "category": item.eventCategory ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .location:
            guard let id = item.locationId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .location, id: id.uuidString, title: item.locationName),
                title: item.locationName ?? "Place",
                summary: item.locationAddress ?? "",
                attributes: [
                    "category": item.locationCategory ?? "",
                    "address": item.locationAddress ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .visit:
            guard let id = item.visitId else { return nil }
            var timestamps: [EvidenceTimestamp] = []
            if let entry = item.visitEntryTime {
                timestamps.append(EvidenceTimestamp(label: "entry", value: isoDate(entry)))
            }
            if let exit = item.visitExitTime {
                timestamps.append(EvidenceTimestamp(label: "exit", value: isoDate(exit)))
            }
            return EvidenceRecord(
                ref: EntityRef(type: .visit, id: id.uuidString, title: item.visitPlaceName),
                title: item.visitPlaceName ?? "Visit",
                summary: item.locationAddress ?? "",
                timestamps: timestamps,
                attributes: [
                    "duration_minutes": item.visitDurationMinutes.map(String.init) ?? ""
                ].filter { !$0.value.isEmpty }
            )
        case .person:
            guard let id = item.personId else { return nil }
            return EvidenceRecord(
                ref: EntityRef(type: .person, id: id.uuidString, title: item.personName),
                title: item.personName ?? "Person",
                summary: item.personRelationship ?? "",
                attributes: [
                    "relationship": item.personRelationship ?? ""
                ].filter { !$0.value.isEmpty }
            )
        }
    }

    private func daySummaryEvidenceRecord(_ summary: DaySummaryService.DaySummary) -> EvidenceRecord {
        var attributes: [String: String] = [
            "mood": summary.mood ?? ""
        ]
        // Expose actual content strings, not just counts — the LLM needs the text to synthesize a real answer
        if !summary.highlights.isEmpty {
            attributes["highlights"] = summary.highlights.joined(separator: " | ")
        }
        if !summary.openLoops.isEmpty {
            attributes["open_loops"] = summary.openLoops.joined(separator: " | ")
        }
        if !summary.anomalies.isEmpty {
            attributes["anomalies"] = summary.anomalies.joined(separator: " | ")
        }

        return EvidenceRecord(
            ref: EntityRef(
                type: .daySummary,
                id: summary.id.uuidString,
                title: summary.title
            ),
            title: summary.title,
            summary: summary.summaryText,
            timestamps: [
                EvidenceTimestamp(label: "date", value: isoDate(summary.summaryDate))
            ],
            attributes: attributes.filter { !$0.value.isEmpty },
            relations: summary.sourceRefs.map { source in
                EvidenceRelation(
                    type: source.relationType,
                    label: source.label,
                    target: source.entityRef
                )
            }
        )
    }

    private func noteEvidenceRecord(_ note: Note) -> EvidenceRecord? {
        EvidenceRecord(
            ref: EntityRef(type: .note, id: note.id.uuidString, title: note.title),
            title: note.title,
            summary: note.preview,
            timestamps: [
                EvidenceTimestamp(label: "created", value: isoDate(note.dateCreated)),
                EvidenceTimestamp(label: "modified", value: isoDate(note.dateModified))
            ],
            attributes: [
                "folder": notesManager.getFolderName(for: note.folderId),
                "kind": note.resolvedKind.rawValue
            ]
        )
    }

    private func receiptEvidenceRecord(_ receipt: ReceiptStat) -> EvidenceRecord? {
        let note = notesManager.notes.first(where: { $0.id == receipt.noteId })
        let merchant = spendingInsightsService.extractMerchantName(from: receipt.title)
        let preview = note?.displayContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return EvidenceRecord(
            ref: EntityRef(type: .receipt, id: receipt.noteId.uuidString, title: receipt.title),
            title: receipt.title,
            summary: merchant == receipt.title ? receipt.category : merchant,
            timestamps: [EvidenceTimestamp(label: "date", value: isoDate(receipt.date))],
            attributes: [
                "amount": CurrencyParser.formatAmount(receipt.amount),
                "category": receipt.category,
                "merchant": merchant,
                "content_preview": String(preview.prefix(220))
            ]
            .filter { !$0.value.isEmpty }
        )
    }

    private func eventEvidenceRecord(_ task: TaskItem) -> EvidenceRecord? {
        let date = task.targetDate ?? task.scheduledTime ?? task.createdAt

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.timeZone = TimeZone.current

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d yyyy"
        dateFormatter.timeZone = TimeZone.current

        var attributes: [String: String] = [
            "location": task.location ?? "",
            "calendar": task.calendarTitle ?? "",
            "completed": task.isCompleted ? "true" : "false",
            "local_date": dateFormatter.string(from: date),
            "timezone": TimeZone.current.identifier
        ]
        if let scheduledTime = task.scheduledTime {
            attributes["local_time"] = timeFormatter.string(from: scheduledTime)
        }

        return EvidenceRecord(
            ref: EntityRef(type: .event, id: task.id, title: task.title),
            title: task.title,
            summary: task.description ?? "",
            timestamps: [EvidenceTimestamp(label: "date", value: isoDate(date))],
            attributes: attributes.filter { !$0.value.isEmpty }
        )
    }

    private func emailEvidenceRecord(_ email: Email) -> EvidenceRecord? {
        EvidenceRecord(
            ref: EntityRef(type: .email, id: email.id, title: email.subject),
            title: email.subject.isEmpty ? "No Subject" : email.subject,
            summary: email.previewText,
            timestamps: [EvidenceTimestamp(label: "date", value: isoDate(email.timestamp))],
            attributes: [
                "sender": email.sender.displayName,
                "ai_summary": email.aiSummary ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    private func personEvidenceRecord(_ person: Person) -> EvidenceRecord {
        EvidenceRecord(
            ref: EntityRef(type: .person, id: person.id.uuidString, title: person.name),
            title: person.name,
            summary: person.relationshipDisplayText,
            timestamps: [EvidenceTimestamp(label: "modified", value: isoDate(person.dateModified))],
            attributes: [
                "relationship": person.relationshipDisplayText,
                "nickname": person.nickname ?? "",
                "birthday": person.formattedBirthday ?? "",
                "email": person.email ?? "",
                "phone": person.phone ?? "",
                "address": person.address ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    private func placeEvidenceRecord(_ place: SavedPlace) -> EvidenceRecord {
        EvidenceRecord(
            ref: EntityRef(type: .location, id: place.id.uuidString, title: place.displayName),
            title: place.displayName,
            summary: place.address,
            timestamps: [
                EvidenceTimestamp(label: "created", value: isoDate(place.dateCreated)),
                EvidenceTimestamp(label: "modified", value: isoDate(place.dateModified))
            ],
            attributes: [
                "category": place.category,
                "address": place.address,
                "city": place.city ?? "",
                "province": place.province ?? "",
                "country": place.country ?? "",
                "cuisine": place.userCuisine ?? "",
                "favourite": place.isFavourite ? "true" : "false"
            ].filter { !$0.value.isEmpty }
        )
    }

    private func savedPlaceETAEvidenceRecord(place: SavedPlace, eta: ETAResult) -> EvidenceRecord {
        EvidenceRecord(
            ref: EntityRef(type: .location, id: place.id.uuidString, title: place.displayName),
            title: place.displayName,
            summary: "\(eta.durationText) away • \(place.address)",
            timestamps: [
                EvidenceTimestamp(label: "created", value: isoDate(place.dateCreated)),
                EvidenceTimestamp(label: "modified", value: isoDate(place.dateModified))
            ],
            attributes: [
                "category": place.category,
                "address": place.address,
                "city": place.city ?? "",
                "province": place.province ?? "",
                "country": place.country ?? "",
                "cuisine": place.userCuisine ?? "",
                "eta": eta.durationText,
                "distance": eta.distanceText,
                "favourite": place.isFavourite ? "true" : "false"
            ].filter { !$0.value.isEmpty }
        )
    }

    private func visitEvidenceRecord(_ visit: LocationVisitRecord) async -> EvidenceRecord? {
        let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        let people = await peopleManager.getPeopleForVisit(visitId: visit.id)
        let linkedReceiptId = VisitReceiptLinkStore.receiptId(for: visit.id)
        let linkedReceipt = linkedReceiptId.flatMap { noteId in
            notesManager.notes.first(where: { $0.id == noteId })
        }

        var relations: [EvidenceRelation] = []
        if let place {
            relations.append(
                EvidenceRelation(
                    type: "place",
                    label: "Visited place",
                    target: EntityRef(type: .location, id: place.id.uuidString, title: place.displayName)
                )
            )
        }
        relations.append(contentsOf: people.map {
            EvidenceRelation(
                type: "person",
                label: "With",
                target: EntityRef(type: .person, id: $0.id.uuidString, title: $0.name)
            )
        })
        if let linkedReceiptId, let linkedReceipt {
            relations.append(
                EvidenceRelation(
                    type: "receipt",
                    label: "Linked receipt",
                    target: EntityRef(type: .receipt, id: linkedReceiptId.uuidString, title: linkedReceipt.title)
                )
            )
        }

        return EvidenceRecord(
            ref: EntityRef(type: .visit, id: visit.id.uuidString, title: place?.displayName),
            title: place?.displayName ?? "Visit",
            summary: visit.visitNotes ?? place?.address ?? "",
            timestamps: [
                EvidenceTimestamp(label: "entry", value: isoDate(visit.entryTime)),
                EvidenceTimestamp(label: "exit", value: visit.exitTime.map(isoDate) ?? "")
            ].filter { !$0.value.isEmpty },
            attributes: [
                "duration_minutes": visit.durationMinutes.map(String.init) ?? "",
                "day_of_week": visit.dayOfWeek,
                "time_of_day": visit.timeOfDay,
                "entry_local_date": localCalendarDate(visit.entryTime),
                "entry_local_weekday": visit.dayOfWeek,
                "entry_local_time": localClockTime(visit.entryTime),
                "exit_local_date": visit.exitTime.map(localCalendarDate) ?? "",
                "exit_local_weekday": visit.exitTime.map(localWeekday) ?? "",
                "exit_local_time": visit.exitTime.map(localClockTime) ?? "",
                "spans_midnight": visit.spansMidnight() ? "true" : "false",
                "merge_reason": visit.mergeReason ?? ""
            ].filter { !$0.value.isEmpty },
            relations: relations
        )
    }

    private func visitSearchEvidenceRecord(from result: VectorSearchService.SearchResult) -> EvidenceRecord? {
        guard let visitId = UUID(uuidString: result.documentId) else { return nil }

        let metadata = result.metadata
        let placeId = metadataString(metadata?["place_id"]).flatMap(UUID.init(uuidString:))
        let placeName = metadataString(metadata?["place_name"]) ?? result.title?.replacingOccurrences(of: "Visit: ", with: "") ?? "Visit"
        let address = metadataString(metadata?["address"]) ?? ""
        let visitNotes = metadataString(metadata?["visit_notes"]) ?? ""
        let peopleNames = metadataStringArray(metadata?["people"])
        let peopleIds = metadataStringArray(metadata?["people_ids"])
        let linkedReceiptId = metadataString(metadata?["linked_receipt_id"])
        let linkedReceiptTitle = metadataString(metadata?["linked_receipt_title"])

        var relations: [EvidenceRelation] = []
        if let placeId {
            relations.append(
                EvidenceRelation(
                    type: "place",
                    label: "Visited place",
                    target: EntityRef(type: .location, id: placeId.uuidString, title: placeName)
                )
            )
        }

        for (index, name) in peopleNames.enumerated() {
            let identifier = peopleIds.indices.contains(index) ? peopleIds[index] : "search-person-\(index)-\(name)"
            relations.append(
                EvidenceRelation(
                    type: "person",
                    label: "With",
                    target: EntityRef(type: .person, id: identifier, title: name)
                )
            )
        }

        if let linkedReceiptId, let linkedReceiptTitle {
            relations.append(
                EvidenceRelation(
                    type: "receipt",
                    label: "Linked receipt",
                    target: EntityRef(type: .receipt, id: linkedReceiptId, title: linkedReceiptTitle)
                )
            )
        }

        var timestamps: [EvidenceTimestamp] = []
        if let entry = metadataDate(metadata?["entry_time"]) {
            timestamps.append(EvidenceTimestamp(label: "entry", value: isoDate(entry)))
        }
        if let exit = metadataDate(metadata?["exit_time"]) {
            timestamps.append(EvidenceTimestamp(label: "exit", value: isoDate(exit)))
        }

        let summary = visitNotes.nilIfEmpty ?? address.nilIfEmpty ?? String(result.content.prefix(180))

        return EvidenceRecord(
            ref: EntityRef(type: .visit, id: visitId.uuidString, title: placeName),
            title: placeName,
            summary: summary,
            timestamps: timestamps,
            attributes: [
                "address": address,
                "duration_minutes": metadataInt(metadata?["duration_minutes"]).map(String.init) ?? "",
                "day_of_week": metadataString(metadata?["day_of_week"]) ?? "",
                "time_of_day": metadataString(metadata?["time_of_day"]) ?? "",
                "entry_local_date": metadataString(metadata?["entry_time"]).flatMap(parseMetadataDate).map(localCalendarDate) ?? "",
                "entry_local_time": metadataString(metadata?["entry_time"]).flatMap(parseMetadataDate).map(localClockTime) ?? "",
                "visit_notes": visitNotes,
                "people": peopleNames.joined(separator: ", ")
            ].filter { !$0.value.isEmpty },
            relations: relations
        )
    }

    // MARK: - Helpers

    private func functionTool(name: String, description: String, parameters: [String: Any]) -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": parameters
        ]
    }

    private func entityRefSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "type": ["type": "string"],
                "id": ["type": "string"],
                "title": ["type": "string"]
            ],
            "required": ["type", "id"]
        ]
    }

    private func decodeArgumentsJSON(_ argumentsJSON: String) throws -> [String: Any] {
        guard
            let data = argumentsJSON.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func vectorDocumentTypes(for scopes: [String]) -> [VectorSearchService.DocumentType]? {
        guard !scopes.isEmpty else { return nil }
        let mapped = scopes.compactMap { scope -> VectorSearchService.DocumentType? in
            switch scope.lowercased() {
            case "visit": return .visit
            case "location": return .location
            case "person": return .person
            case "receipt": return .receipt
            case "note": return .note
            case "email": return .email
            case "event": return .task
            default: return nil
            }
        }
        return mapped.isEmpty ? nil : mapped
    }

    private func resolvedDateRange(from raw: String?) -> (start: Date, end: Date)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let normalizedRaw = normalizedDateText(raw)

        if let explicitRange = parsedExplicitDateRange(normalizedRaw) {
            return explicitRange
        }

        if let extracted = temporalService.extractTemporalRange(from: normalizedRaw) {
            return temporalService.normalizedBounds(for: extracted)
        }

        return nil
    }

    private func parseFlexibleDate(_ raw: String) -> Date? {
        let value = normalizedDateText(raw)
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d, yyyy 'at' h:mm a",
            "MMMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm a",
            "MMMM d, yyyy, h:mm a"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func parsedExplicitDateRange(_ raw: String) -> (start: Date, end: Date)? {
        let separators = ["/", " to "]

        for separator in separators {
            let parts: [String]
            if separator == "/" {
                parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
            } else {
                parts = raw.components(separatedBy: separator)
            }

            guard parts.count == 2 else { continue }
            guard
                let start = parseFlexibleDate(parts[0]),
                let end = parseFlexibleDate(parts[1])
            else {
                continue
            }
            return (start, end)
        }

        return nil
    }

    private func normalizedDateText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2007}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func entityRefs(from raw: Any?) -> [EntityRef] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard
                let rawType = item["type"] as? String,
                let type = AgentEntityType(rawValue: rawType),
                let id = item["id"] as? String
            else {
                return nil
            }
            return EntityRef(type: type, id: id, title: item["title"] as? String)
        }
    }

    private func entityRef(from raw: Any?) -> EntityRef? {
        if let item = raw as? [String: Any] {
            return entityRefs(from: [item]).first
        }
        return nil
    }

    private func eventDraftInfo(from info: ExtractedActionInfo) -> EventCreationInfo? {
        guard
            let rawTitle = info.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawTitle.isEmpty,
            let rawDate = info.eventDate
        else {
            return nil
        }

        let hasExplicitTime = !(info.eventStartTime?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasTime = !info.isAllDay && hasExplicitTime
        let startDate = hasTime
            ? (combine(date: rawDate, withTime: info.eventStartTime) ?? rawDate)
            : Calendar.current.startOfDay(for: rawDate)
        let endDate = combine(date: startDate, withTime: info.eventEndTime)
        let category = info.eventCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Personal"

        return EventCreationInfo(
            title: rawTitle,
            date: startDate,
            endDate: endDate,
            hasTime: hasTime,
            reminderMinutes: info.eventReminders.first?.minutesBefore,
            category: category,
            tagId: existingTagId(forCategory: category),
            recurrenceFrequency: recurrenceFrequency(from: info.eventRecurrence),
            location: info.eventLocation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: info.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func eventDraftAmbiguities(from info: ExtractedActionInfo) -> [ToolAmbiguity] {
        var ambiguities: [ToolAmbiguity] = []

        if info.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            ambiguities.append(ToolAmbiguity(question: "What should I call this event?", options: []))
        }

        if info.eventDate == nil {
            ambiguities.append(
                ToolAmbiguity(
                    question: "When should I schedule it?",
                    options: ["Today", "Tomorrow", "Next week"]
                )
            )
        }

        return ambiguities
    }

    private func inferredNoteTitle(from userRequest: String) -> String? {
        let cleaned = userRequest
            .replacingOccurrences(of: #"(?i)\b(create|make|add|start)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(a|new)?\s*note\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\babout\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.prefix(6).joined(separator: " ").capitalized
    }

    private func normalizedNoteContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func noteDraftAmbiguities(from info: ExtractedActionInfo, userRequest: String) -> [ToolAmbiguity] {
        var ambiguities: [ToolAmbiguity] = []

        if normalizedNoteContent(info.noteContent) == nil {
            ambiguities.append(ToolAmbiguity(question: "What should I put in the note?", options: []))
        }

        if (info.noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
            inferredNoteTitle(from: userRequest) == nil {
            ambiguities.append(ToolAmbiguity(question: "What should I title this note?", options: []))
        }

        return ambiguities
    }

    private func combine(date: Date, withTime rawTime: String?) -> Date? {
        guard let rawTime = rawTime?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTime.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        for format in ["HH:mm", "H:mm", "h:mm a", "h a", "ha"] {
            formatter.dateFormat = format
            guard let parsedTime = formatter.date(from: rawTime) else { continue }

            let calendar = Calendar.current
            let dateParts = calendar.dateComponents([.year, .month, .day], from: date)
            let timeParts = calendar.dateComponents([.hour, .minute], from: parsedTime)
            var components = DateComponents()
            components.year = dateParts.year
            components.month = dateParts.month
            components.day = dateParts.day
            components.hour = timeParts.hour
            components.minute = timeParts.minute
            return calendar.date(from: components)
        }

        return nil
    }

    private func recurrenceFrequency(from raw: String?) -> RecurrenceFrequency? {
        guard let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !normalized.isEmpty else {
            return nil
        }
        return RecurrenceFrequency(rawValue: normalized)
    }

    private func existingTagId(forCategory category: String) -> String? {
        guard category.lowercased() != "personal" else { return nil }
        return TagManager.shared.tags.first(where: { $0.name.caseInsensitiveCompare(category) == .orderedSame })?.id
    }

    private func latestEmailToolResult(scope: String?, forceRefresh: Bool) async throws -> ToolResult {
        if forceRefresh {
            await emailService.loadEmailsForFolder(.inbox, forceRefresh: true)
        }

        let normalizedScope = scope?.lowercased() ?? ""
        let unreadOnly = normalizedScope.contains("unread")
        let candidates = emailService.inboxEmails
            .sorted { $0.timestamp > $1.timestamp }
            .filter { email in
                !unreadOnly || !email.isRead
            }

        guard let latest = candidates.first else {
            return ToolResult(
                toolName: "refresh_inbox_and_get_latest_email",
                ambiguities: [ToolAmbiguity(question: "I couldn't find a matching email in your inbox.", options: [])]
            )
        }

        let enrichedEmail = try await enrichedEmailForPreview(latest)
        let preview = emailPreviewInfo(from: enrichedEmail)
        let records = emailEvidenceRecord(enrichedEmail).map { [$0] } ?? []

        return ToolResult(
            toolName: "refresh_inbox_and_get_latest_email",
            records: records,
            citations: records.map { ToolCitation(ref: $0.ref, label: $0.title) },
            actionDraft: AgentActionDraft(type: .latestEmail, requiresConfirmation: false, emailPreview: preview),
            presentation: AgentPresentation(emailPreviewCard: preview)
        )
    }

    private func enrichedEmailForPreview(_ email: Email) async throws -> Email {
        var enriched = email

        if (enriched.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let messageId = enriched.gmailMessageId,
           let fullEmail = try await gmailAPIClient.fetchFullEmailBody(messageId: messageId) {
            enriched = mergeEmail(primary: enriched, withFullBody: fullEmail)
        }

        let currentSummary = enriched.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if currentSummary.isEmpty {
            let summarySource = enriched.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? enriched.snippet
            if !summarySource.isEmpty {
                let generatedSummary = try await geminiService.summarizeEmail(
                    subject: enriched.subject,
                    body: summarySource
                )
                await emailService.updateEmailWithAISummary(enriched, summary: generatedSummary)
                enriched = emailByReplacingSummary(enriched, summary: generatedSummary)
            }
        }

        return enriched
    }

    private func mergeEmail(primary: Email, withFullBody full: Email) -> Email {
        Email(
            id: primary.id,
            threadId: full.threadId ?? primary.threadId,
            sender: full.sender,
            recipients: full.recipients.isEmpty ? primary.recipients : full.recipients,
            ccRecipients: full.ccRecipients.isEmpty ? primary.ccRecipients : full.ccRecipients,
            subject: full.subject.isEmpty ? primary.subject : full.subject,
            snippet: full.snippet.isEmpty ? primary.snippet : full.snippet,
            body: full.body ?? primary.body,
            timestamp: full.timestamp,
            isRead: full.isRead,
            isImportant: full.isImportant,
            hasAttachments: full.hasAttachments || primary.hasAttachments,
            attachments: full.attachments.isEmpty ? primary.attachments : full.attachments,
            labels: full.labels.isEmpty ? primary.labels : full.labels,
            aiSummary: primary.aiSummary ?? full.aiSummary,
            gmailMessageId: full.gmailMessageId ?? primary.gmailMessageId,
            gmailThreadId: full.gmailThreadId ?? primary.gmailThreadId,
            unsubscribeInfo: full.unsubscribeInfo ?? primary.unsubscribeInfo
        )
    }

    private func emailByReplacingSummary(_ email: Email, summary: String) -> Email {
        Email(
            id: email.id,
            threadId: email.threadId,
            sender: email.sender,
            recipients: email.recipients,
            ccRecipients: email.ccRecipients,
            subject: email.subject,
            snippet: email.snippet,
            body: email.body,
            timestamp: email.timestamp,
            isRead: email.isRead,
            isImportant: email.isImportant,
            hasAttachments: email.hasAttachments,
            attachments: email.attachments,
            labels: email.labels,
            aiSummary: summary,
            gmailMessageId: email.gmailMessageId,
            gmailThreadId: email.gmailThreadId,
            unsubscribeInfo: email.unsubscribeInfo
        )
    }

    private func emailPreviewInfo(from email: Email) -> EmailPreviewInfo {
        let body = email.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let bodyPreview = body.map { String($0.prefix(420)) } ?? email.previewText

        return EmailPreviewInfo(
            emailId: email.id,
            senderName: email.sender.displayName,
            senderEmail: email.sender.email,
            subject: email.subject.isEmpty ? "No Subject" : email.subject,
            timestamp: email.timestamp,
            summary: email.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? email.previewText,
            bodyPreview: bodyPreview,
            body: body,
            gmailMessageId: email.gmailMessageId,
            attachments: email.attachments
        )
    }

    private func savedPlaceFolderNames() -> [String] {
        Array(Set(locationsManager.categories).union(locationsManager.userFolders)).sorted()
    }

    private func resolvedNearbyPlaceResults(
        query: String,
        limit: Int,
        radiusMeters: Int,
        openNow: Bool
    ) async -> [PlaceSearchResult] {
        let currentLocation = sharedLocationManager.currentLocation

        if let liveResults = try? await mapsService.searchPlaces(query: query, currentLocation: currentLocation),
           !liveResults.isEmpty {
            let annotated = annotatedPlaceSearchResults(Array(liveResults.prefix(limit)))
            cacheLivePlaceResults(annotated)
            return annotated
        }

        let fallbackResults = await mapKitSearchPlaces(
            query: query,
            currentLocation: currentLocation,
            radiusMeters: radiusMeters,
            openNow: openNow,
            limit: limit
        )
        let annotated = annotatedPlaceSearchResults(fallbackResults)
        cacheLivePlaceResults(annotated)
        return annotated
    }

    private func annotatedPlaceSearchResults(_ results: [PlaceSearchResult]) -> [PlaceSearchResult] {
        results.map { result in
            var annotated = result
            annotated.isSaved = locationsManager.isPlaceSaved(googlePlaceId: result.id)
            return annotated
        }
    }

    private func cacheLivePlaceResults(_ results: [PlaceSearchResult]) {
        for result in results.prefix(6) {
            locationsManager.addToSearchHistory(result)
        }
    }

    private func mapKitSearchPlaces(
        query: String,
        currentLocation: CLLocation?,
        radiusMeters: Int,
        openNow: Bool,
        limit: Int
    ) async -> [PlaceSearchResult] {
        let cleanedQuery = sanitizedNearbyQuery(query, removeOpenNow: true)
        guard !cleanedQuery.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cleanedQuery

        if let currentLocation {
            let searchRadius = CLLocationDistance(max(radiusMeters, 5_000))
            request.region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: searchRadius,
                longitudinalMeters: searchRadius
            )
        } else {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }

        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }

        let rawResults = response.mapItems.compactMap { mapItem -> PlaceSearchResult? in
            let name = (mapItem.name ?? mapItem.placemark.name ?? cleanedQuery)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            let coordinate = mapItem.placemark.coordinate
            let address = formattedAddress(from: mapItem.placemark)

            return PlaceSearchResult(
                id: mapKitResultIdentifier(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude),
                name: name,
                address: address.isEmpty ? name : address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                types: inferredNearbyTypes(query: cleanedQuery, openNow: openNow),
                photoURL: nil
            )
        }

        let deduped = dedupeNearbySearchResults(rawResults)
        let sorted: [PlaceSearchResult]
        if let currentLocation {
            sorted = deduped.sorted {
                let lhsDistance = CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: currentLocation)
                let rhsDistance = CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: currentLocation)
                return lhsDistance < rhsDistance
            }
        } else {
            sorted = deduped
        }

        return Array(sorted.prefix(limit))
    }

    private func sanitizedNearbyQuery(_ query: String, removeOpenNow: Bool) -> String {
        var cleaned = query
        let phrases = removeOpenNow
            ? ["near me", "nearby", "open now"]
            : ["near me", "nearby"]

        for phrase in phrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }

        let normalized = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized.isEmpty ? query.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
    }

    private func dedupeNearbySearchResults(_ results: [PlaceSearchResult]) -> [PlaceSearchResult] {
        var seen = Set<String>()
        var deduped: [PlaceSearchResult] = []

        for result in results {
            let key = "\(result.name.lowercased())|\(result.address.lowercased())"
            if seen.insert(key).inserted {
                deduped.append(result)
            }
        }

        return deduped
    }

    private func formattedAddress(from placemark: MKPlacemark) -> String {
        var parts: [String] = []

        if let thoroughfare = placemark.thoroughfare {
            if let subThoroughfare = placemark.subThoroughfare {
                parts.append("\(subThoroughfare) \(thoroughfare)")
            } else {
                parts.append(thoroughfare)
            }
        }
        if let locality = placemark.locality {
            parts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            parts.append(postalCode)
        }
        if let country = placemark.country {
            parts.append(country)
        }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }

        return placemark.title?
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func formattedAddress(from placemark: CLPlacemark) -> String {
        var parts: [String] = []

        if let thoroughfare = placemark.thoroughfare {
            if let subThoroughfare = placemark.subThoroughfare {
                parts.append("\(subThoroughfare) \(thoroughfare)")
            } else {
                parts.append(thoroughfare)
            }
        }
        if let locality = placemark.locality {
            parts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            parts.append(postalCode)
        }
        if let country = placemark.country {
            parts.append(country)
        }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }

        return placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func mapKitResultIdentifier(name: String, latitude: Double, longitude: Double) -> String {
        let normalizedName = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "mapkit:\(normalizedName):\(String(format: "%.5f", latitude)),\(String(format: "%.5f", longitude))"
    }

    private func inferredNearbyTypes(query: String, openNow: Bool) -> [String] {
        var types: [String] = []
        let loweredQuery = query.lowercased()

        if loweredQuery.contains("sushi") || loweredQuery.contains("restaurant") || loweredQuery.contains("food") || loweredQuery.contains("wendy") {
            types.append("restaurant")
        }
        if openNow {
            types.append("open_now_requested")
        }

        return types
    }

    private func placeEvidenceRecord(from place: PlaceSearchResult) -> EvidenceRecord {
        EvidenceRecord(
            ref: EntityRef(type: .nearbyPlace, id: place.id, title: place.name),
            title: place.name,
            summary: place.address,
            attributes: [
                "address": place.address,
                "latitude": String(place.latitude),
                "longitude": String(place.longitude),
                "types": place.types.joined(separator: ", ")
            ].filter { !$0.value.isEmpty }
        )
    }

    private func currentLocationResult(for location: CLLocation, fallbackName: String?) async -> PlaceSearchResult? {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        let placemark = placemarks?.first

        let name = placemark?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? placemark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Current Location"
        let address = placemark.map(formattedAddress(from:))?.nilIfEmpty
            ?? fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Current Location"

        return PlaceSearchResult(
            id: "mapkit:current-location:\(String(format: "%.5f", location.coordinate.latitude)),\(String(format: "%.5f", location.coordinate.longitude))",
            name: name,
            address: address,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            types: ["current_location"],
            photoURL: nil
        )
    }

    private func livePlaceResult(for placeId: String) async -> PlaceSearchResult? {
        if let existing = locationsManager.searchHistory.first(where: { $0.id == placeId }) {
            return existing
        }

        guard !placeId.hasPrefix("mapkit:"),
              let details = try? await mapsService.getPlaceDetails(placeId: placeId, minimizeFields: true) else {
            return nil
        }

        return PlaceSearchResult(
            id: placeId,
            name: details.name,
            address: details.address,
            latitude: details.latitude,
            longitude: details.longitude,
            types: details.types,
            photoURL: details.photoURLs.first
        )
    }

    private func fetchVisit(id: UUID) async throws -> LocationVisitRecord? {
        let visits = try await fetchVisits(dateBounds: nil, visitIds: [id])
        return visits.first
    }

    private func fetchVisits(
        dateBounds: (start: Date, end: Date)?,
        visitIds: [UUID]? = nil,
        placeIds: [UUID]? = nil
    ) async throws -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        let client = await SupabaseManager.shared.getPostgrestClient()
        var query = client
            .from("location_visits")
            .select()
            .eq("user_id", value: userId.uuidString)

        if let visitIds, !visitIds.isEmpty {
            query = query.in("id", values: visitIds.map(\.uuidString))
        }
        if let placeIds, !placeIds.isEmpty {
            query = query.in("saved_place_id", values: placeIds.map(\.uuidString))
        }
        if let dateBounds {
            let iso = ISO8601DateFormatter()
            query = query
                .gte("entry_time", value: iso.string(from: dateBounds.start))
                .lt("entry_time", value: iso.string(from: dateBounds.end))
        }

        let response = try await query.order("entry_time", ascending: false).execute()
        let decoder = JSONDecoder.supabaseDecoder()
        return try decoder.decode([LocationVisitRecord].self, from: response.data)
    }

    private func resolveDestination(from destination: [String: Any]) async throws -> (entityId: String, name: String, address: String, coordinate: CLLocationCoordinate2D) {
        if let savedPlaceId = stringValue(destination["saved_place_id"]),
           let placeUUID = UUID(uuidString: savedPlaceId),
           let place = locationsManager.savedPlaces.first(where: { $0.id == placeUUID }) {
            return (
                entityId: place.id.uuidString,
                name: place.displayName,
                address: place.address,
                coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            )
        }

        if let placeId = stringValue(destination["place_id"]) {
            let details = try await mapsService.getPlaceDetails(placeId: placeId, minimizeFields: true)
            return (
                entityId: placeId,
                name: details.name,
                address: details.address,
                coordinate: CLLocationCoordinate2D(latitude: details.latitude, longitude: details.longitude)
            )
        }

        guard
            let latitude = doubleValue(destination["latitude"]),
            let longitude = doubleValue(destination["longitude"])
        else {
            throw GeminiResponsesService.ResponsesError.invalidResponse
        }

        return (
            entityId: UUID().uuidString,
            name: stringValue(destination["name"]) ?? "Destination",
            address: stringValue(destination["address"]) ?? "",
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    private func aggregateVisitRows(visits: [LocationVisitRecord], groupBy: String?) -> [ToolAggregateRow] {
        let placesById = Dictionary(uniqueKeysWithValues: locationsManager.savedPlaces.map { ($0.id, $0) })
        switch groupBy {
        case "day":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let grouped = Dictionary(grouping: visits) { visit in
                formatter.string(from: visit.entryTime)
            }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "month":
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let grouped = Dictionary(grouping: visits) { visit in
                formatter.string(from: visit.entryTime)
            }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "weekday":
            let grouped = Dictionary(grouping: visits, by: \.dayOfWeek)
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "place":
            let grouped = Dictionary(grouping: visits, by: \.savedPlaceId)
            return grouped.compactMap { placeId, items in
                let place = placesById[placeId]
                return ToolAggregateRow(
                    key: place?.displayName ?? "Unknown",
                    value: "\(items.count)",
                    numericValue: Double(items.count),
                    ref: EntityRef(type: .location, id: placeId.uuidString, title: place?.displayName)
                )
            }.sorted { ($0.numericValue ?? 0) > ($1.numericValue ?? 0) }
        default:
            return [
                ToolAggregateRow(
                    key: "total",
                    value: "\(visits.count)",
                    numericValue: Double(visits.count)
                )
            ]
        }
    }

    private func aggregateReceiptRows(receipts: [ReceiptStat], groupBy: String?) -> [ToolAggregateRow] {
        switch groupBy {
        case "day":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let grouped = Dictionary(grouping: receipts) { formatter.string(from: $0.date) }
            return grouped.keys.sorted().map { key in
                let total = grouped[key]?.reduce(0) { $0 + $1.amount } ?? 0
                return ToolAggregateRow(key: key, value: CurrencyParser.formatAmount(total), numericValue: total)
            }
        case "month":
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let grouped = Dictionary(grouping: receipts) { receipt -> Date in
                let components = Calendar.current.dateComponents([.year, .month], from: receipt.date)
                return Calendar.current.date(from: components) ?? receipt.date
            }
            return grouped.keys.sorted().map { monthDate in
                let total = grouped[monthDate]?.reduce(0) { $0 + $1.amount } ?? 0
                return ToolAggregateRow(
                    key: formatter.string(from: monthDate),
                    value: CurrencyParser.formatAmount(total),
                    numericValue: total
                )
            }
        case "category":
            let grouped = Dictionary(grouping: receipts, by: \.category)
            return grouped.keys.sorted().map { key in
                let total = grouped[key]?.reduce(0) { $0 + $1.amount } ?? 0
                return ToolAggregateRow(key: key, value: CurrencyParser.formatAmount(total), numericValue: total)
            }
        default:
            let total = receipts.reduce(0) { $0 + $1.amount }
            return [ToolAggregateRow(key: "total", value: CurrencyParser.formatAmount(total), numericValue: total)]
        }
    }

    private func aggregateEventRows(tasks: [TaskItem], groupBy: String?) -> [ToolAggregateRow] {
        switch groupBy {
        case "day":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let grouped = Dictionary(grouping: tasks) {
                formatter.string(from: $0.targetDate ?? $0.scheduledTime ?? $0.createdAt)
            }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "month":
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let grouped = Dictionary(grouping: tasks) { formatter.string(from: $0.targetDate ?? $0.scheduledTime ?? $0.createdAt) }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "calendar":
            let grouped = Dictionary(grouping: tasks) { $0.calendarTitle ?? "Personal" }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        default:
            return [ToolAggregateRow(key: "total", value: "\(tasks.count)", numericValue: Double(tasks.count))]
        }
    }

    private func aggregateEmailRows(emails: [Email], groupBy: String?) -> [ToolAggregateRow] {
        switch groupBy {
        case "day":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let grouped = Dictionary(grouping: emails) { formatter.string(from: $0.timestamp) }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "month":
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let grouped = Dictionary(grouping: emails) { formatter.string(from: $0.timestamp) }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        case "sender":
            let grouped = Dictionary(grouping: emails) { $0.sender.displayName }
            return grouped.keys.sorted().map { key in
                ToolAggregateRow(key: key, value: "\(grouped[key]?.count ?? 0)", numericValue: Double(grouped[key]?.count ?? 0))
            }
        default:
            return [ToolAggregateRow(key: "total", value: "\(emails.count)", numericValue: Double(emails.count))]
        }
    }

    private func aggregateTitle(metric: String, scope: String, groupBy: String?) -> String {
        if let groupBy, !groupBy.isEmpty {
            return "\(scope.capitalized) \(metric) by \(groupBy)"
        }
        return "\(scope.capitalized) \(metric)"
    }

    private func visitMatchesQuery(
        visit: LocationVisitRecord,
        place: SavedPlace?,
        people: [Person],
        linkedReceipt: Note?,
        query: String?
    ) -> Bool {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return true
        }
        let terms = searchableTerms(from: query)
        guard !terms.isEmpty else { return true }

        let personNames = people.map(\.name).joined(separator: " ")
        let personRelationships = people.map(\.relationshipDisplayText).joined(separator: " ")
        let placeDisplayName = place?.displayName ?? ""
        let placeName = place?.name ?? ""
        let placeCategory = place?.category ?? ""
        let placeAddress = place?.address ?? ""
        let placeCuisine = place?.userCuisine ?? ""
        let placeNotes = place?.userNotes ?? ""
        let visitNotes = visit.visitNotes ?? ""
        let receiptTitle = linkedReceipt?.title ?? ""
        let receiptContent = linkedReceipt?.content ?? ""

        var haystack = [
            placeDisplayName,
            placeName,
            placeCategory,
            placeAddress,
            placeCuisine,
            placeNotes,
            visitNotes,
            receiptTitle,
            receiptContent,
            personNames,
            personRelationships
        ]

        if let place, (place.displayName.lowercased().contains("fitness") || place.category.lowercased().contains("fitness")) {
            haystack.append("gym workout")
        }

        let searchable = haystack.joined(separator: " ").lowercased()
        if searchable.contains(query.lowercased()) {
            return true
        }
        return terms.allSatisfy { searchable.contains($0) }
    }

    private func receiptMatchesQuery(_ receipt: ReceiptStat, query: String?) -> Bool {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return true
        }
        let queryVariants = normalizedReceiptQueryVariants(for: query)
        let content = receiptSearchContent(for: receipt)

        if queryVariants.contains(where: { content.contains($0) }) {
            return true
        }

        let searchTerms = Set(queryVariants.flatMap { receiptSearchTerms(from: $0) })
        if searchTerms.isEmpty {
            return true
        }
        if !searchTerms.isEmpty && searchTerms.allSatisfy({ content.contains($0) }) {
            return true
        }

        return false
    }

    private func taskMatchesQuery(_ task: TaskItem, query: String?) -> Bool {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return true
        }
        let content = "\(task.title) \(task.description ?? "") \(task.location ?? "") \(task.calendarTitle ?? "")".lowercased()
        if content.contains(query.lowercased()) {
            return true
        }
        return searchableTerms(from: query).allSatisfy { content.contains($0) }
    }

    private func emailMatchesQuery(_ email: Email, query: String?) -> Bool {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return true
        }
        let content = "\(email.subject) \(email.previewText) \(email.sender.displayName)".lowercased()
        if content.contains(query.lowercased()) {
            return true
        }
        return searchableTerms(from: query).allSatisfy { content.contains($0) }
    }

    private func searchableTerms(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func receiptSearchTerms(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "again", "amount", "amounts", "average", "breakdown", "cost", "costs",
            "day", "days", "did", "during", "for", "from", "had", "her", "his", "how",
            "much", "many", "month", "months", "paid", "pay", "receipt", "receipts",
            "same", "spend", "spent", "spending", "that", "the", "their", "them", "there",
            "this", "those", "through", "time", "total", "totals", "trip", "visit",
            "visits", "was", "week", "weekend", "weekends", "what", "with", "year", "years"
        ]

        return searchableTerms(from: query).filter { !stopWords.contains($0) }
    }

    private func filteredSavedPlacesForTravelQuery(
        query: String,
        folderName: String?
    ) -> [SavedPlace] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return locationsManager.savedPlaces.filter { place in
            if let folderName,
               place.category.caseInsensitiveCompare(folderName) != .orderedSame {
                return false
            }

            return savedPlaceMatchesTravelQuery(place, query: trimmedQuery)
        }
    }

    private func savedPlaceMatchesTravelQuery(_ place: SavedPlace, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let loweredQuery = trimmedQuery.lowercased()
        let content = [
            place.displayName,
            place.name,
            place.address,
            place.category,
            place.userCuisine ?? "",
            place.userNotes ?? "",
            place.city ?? "",
            place.province ?? "",
            place.country ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        if content.contains(loweredQuery) {
            return true
        }

        let terms = filteredTravelSearchTerms(from: trimmedQuery)
        if terms.isEmpty {
            return true
        }

        return terms.allSatisfy { term in
            if content.contains(term) {
                return true
            }

            switch term {
            case "restaurant", "restaurants", "food", "dining", "eat", "eats":
                return isRestaurantLikePlace(place)
            case "coffee", "cafe", "cafes":
                return isCafeLikePlace(place)
            case "clinic", "clinics", "medical", "doctor", "walkin", "health":
                return isClinicLikePlace(place)
            default:
                return false
            }
        }
    }

    private func filteredTravelSearchTerms(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "within", "minute", "minutes", "mins", "min", "hour", "hours", "hr", "hrs",
            "drive", "driving", "travel", "time", "distance", "proximity", "radius",
            "saved", "save", "location", "locations", "place", "places", "current",
            "from", "my", "me", "the", "that", "this", "around", "under", "less", "than",
            "and", "all", "show", "tell", "what", "which", "are", "is", "in", "of", "to"
        ]

        return searchableTerms(from: query)
            .filter { !stopWords.contains($0) && Int($0) == nil }
    }

    private func isRestaurantLikePlace(_ place: SavedPlace) -> Bool {
        let content = [
            place.displayName,
            place.name,
            place.category,
            place.userCuisine ?? "",
            place.userNotes ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        let keywords = [
            "restaurant", "food", "eat", "dining", "sushi", "pizza", "burger", "bbq",
            "grill", "shawarma", "kebab", "cafe", "coffee", "tea", "bakery"
        ]

        return keywords.contains(where: { content.contains($0) })
    }

    private func isCafeLikePlace(_ place: SavedPlace) -> Bool {
        let content = [
            place.displayName,
            place.name,
            place.category,
            place.userCuisine ?? "",
            place.userNotes ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return ["coffee", "cafe", "tea", "espresso", "latte", "bakery"].contains(where: { content.contains($0) })
    }

    private func isClinicLikePlace(_ place: SavedPlace) -> Bool {
        let content = [
            place.displayName,
            place.name,
            place.category,
            place.userNotes ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return ["clinic", "medical", "doctor", "walk", "pharmacy", "health"].contains(where: { content.contains($0) })
    }

    private func directDistance(from origin: CLLocation, to place: SavedPlace) -> CLLocationDistance {
        let destination = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return origin.distance(from: destination)
    }

    private func inferredTravelLimitMinutes(from query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = firstRegexMatch(
            pattern: #"(\d+)\s*(?:min|mins|minute|minutes)\b"#,
            in: trimmed
        ), let minutes = Int(match) {
            return minutes
        }

        if let match = firstRegexMatch(
            pattern: #"(\d+)\s*(?:hr|hrs|hour|hours)\b"#,
            in: trimmed
        ), let hours = Int(match) {
            return hours * 60
        }

        return nil
    }

    private func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: nsRange),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[range])
    }

    private func receiptSearchContent(for receipt: ReceiptStat) -> String {
        let note = notesManager.notes.first(where: { $0.id == receipt.noteId })
        let merchant = spendingInsightsService.extractMerchantName(from: receipt.title)
        let normalizedMerchant = spendingInsightsService.normalizeMerchantName(merchant)
        let noteText = note.map { "\($0.title) \($0.displayContent)" } ?? ""

        return [
            receipt.title,
            receipt.category,
            merchant,
            normalizedMerchant,
            noteText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func normalizedReceiptQueryVariants(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalizedMerchant = spendingInsightsService.normalizeMerchantName(trimmed)
        let aliasMap: [String: String] = [
            "tims": "tim hortons",
            "tims coffee": "tim hortons",
            "tim horton": "tim hortons"
        ]

        var variants = Set([trimmed.lowercased(), normalizedMerchant.lowercased()])
        if let alias = aliasMap[trimmed.lowercased()] {
            variants.insert(alias)
        }
        if let alias = aliasMap[normalizedMerchant.lowercased()] {
            variants.insert(alias)
        }
        return Array(variants)
    }

    private func receiptStat(for noteId: UUID) async -> ReceiptStat? {
        await notesManager.ensureReceiptDataAvailable()
        return notesManager
            .getReceiptStatistics()
            .flatMap(\.monthlySummaries)
            .flatMap(\.receipts)
            .first(where: { $0.noteId == noteId })
    }

    private func peopleForReceipt(_ noteId: UUID) async -> [Person] {
        await peopleManager.getPeopleForReceipt(noteId: noteId)
    }

    private func conversationHistoryPairs(from raw: Any?) -> [(role: String, content: String)] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard
                let role = item["role"] as? String,
                let content = item["content"] as? String
            else {
                return nil
            }
            return (role: role, content: content)
        }
    }

    private func stringValue(_ raw: Any?) -> String? {
        raw as? String
    }

    private func metadataString(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? String {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private func metadataInt(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        if let number = raw as? NSNumber { return number.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private func stringArray(_ raw: Any?) -> [String] {
        raw as? [String] ?? []
    }

    private func metadataStringArray(_ raw: Any?) -> [String] {
        if let values = raw as? [String] {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let values = raw as? [Any] {
            return values.compactMap { metadataString($0) }
        }
        return []
    }

    private func metadataDate(_ raw: Any?) -> Date? {
        metadataString(raw).flatMap(parseMetadataDate)
    }

    private func parseMetadataDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func localCalendarDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func localClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func localWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func applyingResolvedDateContext(
        to result: ToolResult,
        bounds: (start: Date, end: Date)?
    ) -> ToolResult {
        guard let bounds else {
            return result
        }

        return ToolResult(
            toolName: result.toolName,
            records: result.records,
            aggregates: result.aggregates,
            ambiguities: result.ambiguities,
            citations: result.citations,
            resolvedTimeRange: result.resolvedTimeRange ?? anchorDateRangeLabel(start: bounds.start, end: bounds.end),
            resolvedDateBounds: result.resolvedDateBounds ?? ResolvedDateBounds(start: bounds.start, end: bounds.end),
            actionDraft: result.actionDraft,
            presentation: result.presentation,
            isTruncated: result.isTruncated
        )
    }

    private func dayAnchorLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func anchorDateRangeLabel(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let inclusiveEnd = end.addingTimeInterval(-1)
        if calendar.isDate(start, inSameDayAs: inclusiveEnd) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start)
        }

        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) to \(formatter.string(from: inclusiveEnd))"
    }

    private func episodeDateRangeLabel(_ episode: CompositeEpisodeResolver.EpisodeResolution) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let inclusiveEnd = episode.end.addingTimeInterval(-1)
        return "\(formatter.string(from: episode.start)) to \(formatter.string(from: inclusiveEnd))"
    }

    private func placeId(from ref: EntityRef) -> UUID? {
        guard ref.type == .location else { return nil }
        return UUID(uuidString: ref.id)
    }

    private func personId(from ref: EntityRef) -> UUID? {
        guard ref.type == .person else { return nil }
        return UUID(uuidString: ref.id)
    }

    private func visitId(from ref: EntityRef) -> UUID? {
        guard ref.type == .visit else { return nil }
        return UUID(uuidString: ref.id)
    }

    private func receiptId(from ref: EntityRef) -> UUID? {
        guard ref.type == .receipt else { return nil }
        return UUID(uuidString: ref.id)
    }

    private func dedupeRecords(_ records: [EvidenceRecord]) -> [EvidenceRecord] {
        var seen = Set<String>()
        var deduped: [EvidenceRecord] = []
        for record in records {
            if seen.insert(record.id).inserted {
                deduped.append(record)
            }
        }
        return deduped
    }

    private func dedupePeople(_ people: [Person]) -> [Person] {
        var seen = Set<UUID>()
        var deduped: [Person] = []
        for person in people where seen.insert(person.id).inserted {
            deduped.append(person)
        }
        return deduped
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
