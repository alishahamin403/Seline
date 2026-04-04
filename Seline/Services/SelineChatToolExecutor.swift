import Foundation
import CoreLocation

struct SelineChatToolExecutionResult {
    let outputJSON: String
    let records: [SelineChatEvidenceRecord]
    let items: [SelineChatEvidenceItem]
    let places: [SelineChatPlaceResult]
    let citations: [SelineChatWebCitation]
    let note: String?

    init(
        outputJSON: String,
        records: [SelineChatEvidenceRecord] = [],
        items: [SelineChatEvidenceItem] = [],
        places: [SelineChatPlaceResult] = [],
        citations: [SelineChatWebCitation] = [],
        note: String? = nil
    ) {
        self.outputJSON = outputJSON
        self.records = records
        self.items = items
        self.places = places
        self.citations = citations
        self.note = note
    }

    var resultCount: Int {
        max(records.count, max(items.count, max(places.count, citations.count)))
    }
}

@MainActor
protocol SelineChatToolExecuting: AnyObject {
    func toolDefinitions() -> [[String: Any]]
    func execute(toolName: String, argumentsJSON: String) async throws -> SelineChatToolExecutionResult
}

enum SelineChatToolExecutorError: LocalizedError {
    case invalidArguments(String)
    case unsupportedTool(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .unsupportedTool(let name):
            return "Unsupported tool: \(name)"
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class SelineChatToolExecutor: SelineChatToolExecuting {
    private enum PersonalSource: String, CaseIterable {
        case emails
        case events
        case notes
        case visits
        case people
        case receipts
        case journals
        case trackers
        case daySummaries
    }

    private enum RecordDetailLevel {
        case compact
        case full
    }

    private struct PlaceResolution {
        let ref: String
        let result: SelineChatPlaceResult
    }

    private let temporalService = TemporalUnderstandingService.shared
    private let placesService = SelineChatPlacesService()
    private let webSearchService = SelineChatWebSearchService.shared
    private let notesManager = NotesManager.shared
    private let taskManager = TaskManager.shared
    private let emailService = EmailService.shared
    private let peopleManager = PeopleManager.shared
    private let receiptManager = ReceiptManager.shared
    private let trackerStore = TrackerStore.shared
    private let locationService = LocationService.shared
    private let googleMapsService = GoogleMapsService.shared
    private let navigationService = NavigationService.shared
    private let daySummaryService = DaySummaryService.shared
    private let genericPlaceQueryTokens: Set<String> = [
        "a", "an", "any", "around", "best", "closest", "find", "for", "good", "looking",
        "me", "near", "nearby", "place", "places", "show", "spot", "spots", "the",
        "where"
    ]
    private let placeIntentAliases: [String: [String]] = [
        "dessert": ["dessert", "desserts", "bakery", "patisserie", "pastry", "cake", "cakes", "ice cream", "gelato", "donut", "donuts", "cookie", "cookies", "sweet", "sweets"],
        "coffee": ["coffee", "cafe", "café", "espresso", "latte"],
        "parking": ["parking", "garage", "lot"],
        "pizza": ["pizza", "pizzeria"],
        "gym": ["gym", "fitness", "workout"]
    ]

    private let isoFormatter = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func toolDefinitions() -> [[String: Any]] {
        [
            functionDefinition(
                name: "get_day_overview",
                description: "Get a grounded day or short date-range overview across calendar events, tasks, emails, visits, notes, receipts, and day summaries.",
                properties: [
                    "date_or_range": stringProperty(description: "Natural language date or range like tomorrow, last weekend, April 1 2026, or this week."),
                    "focus": stringProperty(description: "Optional focus such as schedule, travel, spending, or person."),
                    "max_days": integerProperty(description: "Optional cap for range expansion. Defaults to 3, max 7.")
                ],
                required: ["date_or_range"]
            ),
            functionDefinition(
                name: "search_personal_data",
                description: "Search across Seline personal data using exact matching first and embeddings-backed recall when needed. Use for cross-domain questions about people, visits, notes, events, emails, receipts, journals, and trackers.",
                properties: [
                    "query": stringProperty(description: "The user's question or focused search query."),
                    "sources": arrayProperty(
                        description: "Optional list of personal sources to search.",
                        itemSchema: [
                            "type": "string",
                            "enum": PersonalSource.allCases.map(\.rawValue)
                        ]
                    ),
                    "start_date": stringProperty(description: "Optional ISO date or timestamp lower bound."),
                    "end_date": stringProperty(description: "Optional ISO date or timestamp upper bound."),
                    "prefer_exact": boolProperty(description: "Set true for timestamp, amount, booking, or other exact-fact questions."),
                    "limit": integerProperty(description: "Maximum number of top records to return. Defaults to 10.")
                ],
                required: ["query"]
            ),
            functionDefinition(
                name: "get_records",
                description: "Hydrate exact records by reference after an initial search pass. Use this to read fuller note bodies, email bodies, event details, people context, visit notes, or receipt details.",
                properties: [
                    "record_refs": arrayProperty(
                        description: "List of record references like email:abc, note:<uuid>, visit:<uuid>, receipt:<uuid>, event:<id>, person:<uuid>, day_summary:<uuid>, place:<uuid>, or google_place:<id>.",
                        itemSchema: ["type": "string"]
                    )
                ],
                required: ["record_refs"]
            ),
            functionDefinition(
                name: "search_emails",
                description: "Search personal emails for confirmations, schedules, travel details, and exact timestamps. Prefer this for flights, bookings, reservations, and inbox-specific questions.",
                properties: [
                    "query": stringProperty(description: "Email search query."),
                    "time_scope": stringProperty(description: "Optional natural language time scope like tomorrow, last week, or two days ago."),
                    "limit": integerProperty(description: "Maximum emails to return. Defaults to 8.")
                ],
                required: ["query"]
            ),
            functionDefinition(
                name: "extract_email_facts",
                description: "Extract structured itinerary or booking facts from the most relevant hydrated emails. Use this after search_emails when the answer depends on exact reservation details.",
                properties: [
                    "email_refs": arrayProperty(
                        description: "Email record refs returned from search_emails or search_personal_data.",
                        itemSchema: ["type": "string"]
                    ),
                    "query": stringProperty(description: "Original user question to guide extraction.")
                ],
                required: ["email_refs", "query"]
            ),
            functionDefinition(
                name: "search_places",
                description: "Search Google Maps and saved places for locations, nearby places, parking, airports, restaurants, and other destination queries.",
                properties: [
                    "query": stringProperty(description: "Place search query."),
                    "near_current_location": boolProperty(description: "Bias the search around the current location when true.")
                ],
                required: ["query"]
            ),
            functionDefinition(
                name: "get_place_details",
                description: "Get exact place details like open status, hours, phone, website, reviews summary, and address for a selected place result.",
                properties: [
                    "place_ref": stringProperty(description: "A place reference like place:<uuid> or google_place:<id>.")
                ],
                required: ["place_ref"]
            ),
            functionDefinition(
                name: "get_travel_eta",
                description: "Estimate current driving ETA and distance from the user's current location to a destination place.",
                properties: [
                    "destination": stringProperty(description: "Optional destination query if no place_ref is provided."),
                    "place_ref": stringProperty(description: "Optional place reference from search_places or get_place_details.")
                ],
                required: []
            ),
            functionDefinition(
                name: "web_search",
                description: "Search live public web data when personal data is insufficient or the question requires current public information.",
                properties: [
                    "query": stringProperty(description: "Web search query.")
                ],
                required: ["query"]
            )
        ]
    }

    func execute(toolName: String, argumentsJSON: String) async throws -> SelineChatToolExecutionResult {
        let args = try parseArguments(argumentsJSON)

        switch toolName {
        case "get_day_overview":
            return try await getDayOverview(arguments: args)
        case "search_personal_data":
            return try await searchPersonalData(arguments: args)
        case "get_records":
            return try await getRecords(arguments: args)
        case "search_emails":
            return try await searchEmails(arguments: args)
        case "extract_email_facts":
            return try await extractEmailFacts(arguments: args)
        case "search_places":
            return try await searchPlaces(arguments: args)
        case "get_place_details":
            return try await getPlaceDetails(arguments: args)
        case "get_travel_eta":
            return try await getTravelETA(arguments: args)
        case "web_search":
            return await webSearch(arguments: args)
        default:
            throw SelineChatToolExecutorError.unsupportedTool(toolName)
        }
    }

    private func getDayOverview(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let dateOrRange = requiredString("date_or_range", in: arguments)
        let focus = optionalString("focus", in: arguments)
        let maxDays = min(max(optionalInt("max_days", in: arguments) ?? 3, 1), 7)
        let interval = resolveInterval(
            naturalLanguage: dateOrRange,
            startDate: nil,
            endDate: nil
        ) ?? DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date())

        let dates = enumerateDates(in: interval, maxDays: maxDays)
        await receiptManager.ensureLoaded()

        var records: [SelineChatEvidenceRecord] = []
        var items: [SelineChatEvidenceItem] = []
        var overviewDays: [[String: Any]] = []

        for date in dates {
            let dayStart = Calendar.current.startOfDay(for: date)
            let events = taskManager.getAllTasks(for: dayStart)
            let daySummary = await daySummaryService.summary(for: dayStart)
            let visits = await fetchVisits(in: dayInterval(for: dayStart), limit: 20)
            let notes = notesOnSameDay(dayStart)
            let receipts = receiptsOnSameDay(dayStart)
            let inboxEmails = emailsOnSameDay(dayStart)
            let sentEmails = sentEmailsOnSameDay(dayStart)
            let peopleByVisit = await peopleManager.getPeopleForVisits(visitIds: visits.map(\.id))

            if let daySummary {
                records.append(daySummaryRecord(daySummary))
                items.append(daySummaryItem(daySummary))
            }

            let dayEvents = events.sorted { eventSearchDate($0) < eventSearchDate($1) }
            records.append(contentsOf: dayEvents.prefix(8).map { eventRecord($0, detailLevel: .compact) })
            items.append(contentsOf: dayEvents.prefix(8).map(eventItem))

            let dayVisitPayloads = visits.prefix(8).map { visit -> (SelineChatEvidenceRecord, SelineChatEvidenceItem) in
                let people = peopleByVisit[visit.id] ?? []
                return visitPayload(visit, people: people, detailLevel: .compact)
            }
            records.append(contentsOf: dayVisitPayloads.map(\.0))
            items.append(contentsOf: dayVisitPayloads.map(\.1))

            records.append(contentsOf: notes.prefix(6).map { noteRecord($0, detailLevel: .compact) })
            items.append(contentsOf: notes.prefix(6).map(noteItem))

            records.append(contentsOf: receipts.prefix(6).map { receiptRecord($0, detailLevel: .compact) })
            items.append(contentsOf: receipts.prefix(6).map(receiptItem))

            let combinedEmails = Array((inboxEmails + sentEmails).sorted { $0.timestamp > $1.timestamp }.prefix(6))
            records.append(contentsOf: combinedEmails.map { liveEmailRecord($0, detailLevel: .compact) })
            items.append(contentsOf: combinedEmails.map(liveEmailItem))

            let summaryText = daySummary?.summaryText ?? buildFallbackDayOverview(
                date: dayStart,
                events: dayEvents,
                visits: visits,
                notes: notes,
                receipts: receipts,
                inboxEmails: inboxEmails,
                sentEmails: sentEmails
            )

            overviewDays.append(compactJSON([
                "date": dayFormatter.string(from: dayStart),
                "title": daySummary?.title ?? "Day overview",
                "summary": summaryText,
                "focus": focus,
                "event_count": dayEvents.count,
                "visit_count": visits.count,
                "note_count": notes.count,
                "receipt_count": receipts.count,
                "email_count": inboxEmails.count + sentEmails.count,
                "open_tasks": dayEvents.filter { !$0.isCompletedOn(date: dayStart) }.map(\.title),
                "events": dayEvents.prefix(6).map { task in
                    compactJSON([
                        "ref": "event:\(task.id)",
                        "title": task.title,
                        "time": task.formattedTimeRange.isEmpty ? nil : task.formattedTimeRange,
                        "location": task.location,
                        "completed": task.isCompletedOn(date: dayStart)
                    ])
                },
                "emails": combinedEmails.map { email in
                    compactJSON([
                        "ref": "email:\(email.id)",
                        "subject": email.subject,
                        "sender": email.sender.displayName,
                        "timestamp": isoString(email.timestamp)
                    ])
                }
            ]))
        }

        let dedupedRecords = dedupeRecords(records)
        let dedupedItems = dedupeItems(items)
        let output = compactJSON([
            "range_label": dateOrRange,
            "start": isoString(interval.start),
            "end": isoString(interval.end),
            "day_count": dates.count,
            "days": overviewDays,
            "record_refs": dedupedRecords.map(\.id)
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: dedupedRecords,
            items: dedupedItems,
            note: "Loaded \(dates.count) day overview(s)"
        )
    }

    private func searchPersonalData(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let query = requiredString("query", in: arguments)
        let limit = min(max(optionalInt("limit", in: arguments) ?? 10, 1), 20)
        let preferExact = optionalBool("prefer_exact", in: arguments) ?? false
        let sources = requestedSources(from: arguments)
        let interval = resolveInterval(
            naturalLanguage: query,
            startDate: optionalString("start_date", in: arguments),
            endDate: optionalString("end_date", in: arguments)
        )

        await receiptManager.ensureLoaded()

        let terms = searchTerms(from: query)
        let normalizedQuery = normalize(query)
        let emails = allLiveEmails()
        let notes = filteredNotes(sources: sources, interval: nil)
        let events = filteredEvents(sources: sources, interval: interval)
        let receipts = filteredReceipts(sources: sources, interval: interval)
        let people = filteredPeople(sources: sources)
        let trackers = filteredTrackers(sources: sources)

        var candidateScores: [String: Double] = [:]

        if sources.contains(.emails) {
            for email in emails where matchesInterval(email.timestamp, interval: interval) {
                let score = exactScore(
                    text: normalize(email.subject + " " + email.sender.displayName + " " + email.previewText),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                if score > 0 || (preferExact && interval != nil) {
                    candidateScores["email:\(email.id)"] = max(candidateScores["email:\(email.id)"] ?? 0, score + intervalBoost(for: email.timestamp, interval: interval))
                }
            }
        }

        if sources.contains(.events) {
            for event in events {
                let score = exactScore(
                    text: normalize(eventSearchableText(event)),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "event:\(event.id)"
                if score > 0 || (preferExact && interval != nil) {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score + intervalBoost(for: eventSearchDate(event), interval: interval))
                }
            }
        }

        if sources.contains(.notes) || sources.contains(.journals) {
            for note in notes {
                let score = exactScore(
                    text: normalize(note.title + " " + note.displayContent),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "note:\(note.id.uuidString)"
                let boostedScore = score + intervalBoost(for: note.embeddingDate, interval: interval)
                if score > 0 || (preferExact && interval != nil && matchesInterval(note.embeddingDate, interval: interval)) {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, boostedScore)
                }
            }
        }

        if sources.contains(.receipts) {
            for receipt in receipts {
                let score = exactScore(
                    text: normalize(receipt.searchableText),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "receipt:\(receipt.id.uuidString)"
                if score > 0 || (preferExact && interval != nil) {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score + intervalBoost(for: receipt.date, interval: interval))
                }
            }
        }

        var matchedPersonIDs: [UUID] = []
        if sources.contains(.people) {
            for person in people {
                let score = exactScore(
                    text: normalize(personSearchableText(person)),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "person:\(person.id.uuidString)"
                if score > 0 {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score)
                    matchedPersonIDs.append(person.id)
                }
            }
        }

        if sources.contains(.trackers) {
            for tracker in trackers {
                let score = exactScore(
                    text: normalize(tracker.title + " " + (tracker.subtitle ?? "") + " " + trackerSummary(tracker)),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "tracker:\(tracker.id.uuidString)"
                if score > 0 {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score)
                }
            }
        }

        if sources.contains(.daySummaries), let interval {
            let summaries = await daySummaries(in: interval, maxDays: 4)
            for summary in summaries {
                let score = exactScore(
                    text: normalize(summary.title + " " + summary.summaryText + " " + summary.highlights.joined(separator: " ")),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                let ref = "day_summary:\(summary.id.uuidString)"
                if score > 0 || interval != nil {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score + intervalBoost(for: summary.summaryDate, interval: interval))
                }
            }
        }

        var fetchedVisits: [LocationVisitRecord] = []
        if sources.contains(.visits) || !matchedPersonIDs.isEmpty {
            let relatedVisitIDs = !matchedPersonIDs.isEmpty ? await matchedVisitIDs(for: matchedPersonIDs) : []
            let relatedVisitSet = Set(relatedVisitIDs)
            var relatedVisits = relatedVisitIDs.isEmpty ? [] : await fetchVisits(withIDs: relatedVisitIDs)
            if let interval {
                relatedVisits = relatedVisits.filter { matchesInterval($0.entryTime, interval: interval) }
            }

            fetchedVisits = interval != nil
                ? await fetchVisits(in: interval!, limit: 60)
                : await fetchRecentVisits(limit: 80)

            if !relatedVisits.isEmpty {
                var seenVisitIDs = Set(fetchedVisits.map(\.id))
                for visit in relatedVisits where seenVisitIDs.insert(visit.id).inserted {
                    fetchedVisits.append(visit)
                }
                fetchedVisits.sort { $0.entryTime > $1.entryTime }
            }

            if !matchedPersonIDs.isEmpty {
                let personReceiptIDs = await matchedReceiptIDs(for: matchedPersonIDs)
                let receiptIDSet = Set(personReceiptIDs)
                for receipt in receipts where receiptIDSet.contains(receipt.id) {
                    let ref = "receipt:\(receipt.id.uuidString)"
                    let contentScore = exactScore(
                        text: normalize(receipt.searchableText),
                        normalizedQuery: normalizedQuery,
                        terms: terms
                    )
                    candidateScores[ref] = max(
                        candidateScores[ref] ?? 0,
                        contentScore + 2.0 + intervalBoost(for: receipt.date, interval: interval)
                    )
                }
            }

            let peopleByVisit = await peopleManager.getPeopleForVisits(visitIds: fetchedVisits.map(\.id))
            for visit in fetchedVisits {
                let peopleNames = (peopleByVisit[visit.id] ?? []).map(\.displayName).joined(separator: " ")
                var score = exactScore(
                    text: normalize(visitSearchableText(visit) + " " + peopleNames),
                    normalizedQuery: normalizedQuery,
                    terms: terms
                )
                if relatedVisitSet.contains(visit.id) {
                    score += 2.5
                }
                let ref = "visit:\(visit.id.uuidString)"
                if score > 0 || candidateScores[ref] != nil {
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, score + intervalBoost(for: visit.entryTime, interval: interval))
                }
            }

            let visitDates = Set(fetchedVisits.map { Calendar.current.startOfDay(for: $0.entryTime) })
            if !visitDates.isEmpty && (sources.contains(.notes) || sources.contains(.journals)) {
                for note in notes where visitDates.contains(Calendar.current.startOfDay(for: note.embeddingDate)) {
                    let ref = "note:\(note.id.uuidString)"
                    candidateScores[ref] = max(candidateScores[ref] ?? 0, 2.5)
                }
            }
        }

        let vectorRecords = try? await vectorAugmentedRefs(
            query: query,
            interval: interval,
            sources: sources,
            limit: max(limit * 3, 12),
            liveEmails: emails
        )

        for (ref, score) in vectorRecords ?? [:] {
            candidateScores[ref] = max(candidateScores[ref] ?? 0, Double(score) * 10.0)
        }

        let topRefs = candidateScores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)

        let hydration = await hydrateRecords(topRefs, detailLevel: .compact)

        let matchedReceipts = receipts.filter { receipt in
            let score = exactScore(
                text: normalize(receipt.searchableText),
                normalizedQuery: normalizedQuery,
                terms: terms
            )
            return score > 0 && matchesInterval(receipt.date, interval: interval)
        }

        let output = compactJSON([
            "query": query,
            "start": interval.map { isoString($0.start) },
            "end": interval.map { isoString($0.end) },
            "result_count": hydration.records.count,
            "record_refs": hydration.records.map(\.id),
            "receipt_total": matchedReceipts.isEmpty ? nil : matchedReceipts.reduce(0) { $0 + $1.amount },
            "receipt_count": matchedReceipts.isEmpty ? nil : matchedReceipts.count,
            "results": hydration.records.map { record in
                compactJSON([
                    "ref": record.id,
                    "source": record.sourceKind.rawValue,
                    "title": record.title,
                    "snippet": record.snippet,
                    "timestamp": record.timestamp.map(isoString)
                ])
            }
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: hydration.records,
            items: hydration.items,
            note: hydration.records.isEmpty ? "No personal matches found" : "Found \(hydration.records.count) grounded record(s)"
        )
    }

    private func getRecords(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let refs = requiredStringArray("record_refs", in: arguments)
        let hydration = await hydrateRecords(Array(refs.prefix(12)), detailLevel: .full)

        let output = compactJSON([
            "record_count": hydration.records.count,
            "records": hydration.records.map { record in
                compactJSON([
                    "ref": record.id,
                    "source": record.sourceKind.rawValue,
                    "title": record.title,
                    "snippet": record.snippet,
                    "timestamp": record.timestamp.map(isoString),
                    "relation_ids": record.relationIDs
                ])
            }
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: hydration.records,
            items: hydration.items,
            places: hydration.places,
            citations: hydration.citations,
            note: hydration.records.isEmpty ? "No records hydrated" : "Hydrated \(hydration.records.count) record(s)"
        )
    }

    private func searchEmails(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let query = requiredString("query", in: arguments)
        let timeScope = optionalString("time_scope", in: arguments)
        let limit = min(max(optionalInt("limit", in: arguments) ?? 8, 1), 15)
        let interval = resolveInterval(naturalLanguage: timeScope ?? query, startDate: nil, endDate: nil)
        let emails = allLiveEmails()
        let normalizedQuery = normalize(query)
        let terms = searchTerms(from: query)

        var scored: [(Email, Double)] = []
        for email in emails where matchesInterval(email.timestamp, interval: interval) {
            let score = exactScore(
                text: normalize(email.subject + " " + email.sender.displayName + " " + email.previewText),
                normalizedQuery: normalizedQuery,
                terms: terms
            ) + travelKeywordBoost(for: email)
            if score > 0 || interval != nil {
                scored.append((email, score + intervalBoost(for: email.timestamp, interval: interval)))
            }
        }

        if let vectorRefs = try? await vectorAugmentedRefs(
            query: query,
            interval: interval,
            sources: [.emails],
            limit: limit * 3,
            liveEmails: emails
        ) {
            let liveEmailIDs = Set(emails.map(\.id))
            for (ref, score) in vectorRefs where ref.hasPrefix("email:") {
                let id = String(ref.dropFirst("email:".count))
                guard liveEmailIDs.contains(id),
                      let email = emails.first(where: { $0.id == id }) else { continue }
                scored.append((email, Double(score) * 10.0))
            }
        }

        let topEmails = dedupeEmails(
            scored
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0.timestamp > rhs.0.timestamp
                    }
                    return lhs.1 > rhs.1
                }
                .prefix(limit)
                .map(\.0)
        )

        let records = topEmails.map { liveEmailRecord($0, detailLevel: .compact) }
        let items = topEmails.map(liveEmailItem)
        let output = compactJSON([
            "query": query,
            "time_scope": timeScope,
            "start": interval.map { isoString($0.start) },
            "end": interval.map { isoString($0.end) },
            "email_count": topEmails.count,
            "emails": topEmails.map { email in
                compactJSON([
                    "ref": "email:\(email.id)",
                    "subject": email.subject,
                    "sender": email.sender.displayName,
                    "timestamp": isoString(email.timestamp),
                    "snippet": email.previewText
                ])
            }
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: records,
            items: items,
            note: topEmails.isEmpty ? "No email matches found" : "Found \(topEmails.count) email(s)"
        )
    }

    private func extractEmailFacts(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let refs = requiredStringArray("email_refs", in: arguments)
        let query = requiredString("query", in: arguments)
        let limitedRefs = Array(refs.prefix(5))
        let hydrated = await hydrateRecords(limitedRefs, detailLevel: .full)

        let emailContexts = hydrated.records
            .filter { $0.sourceKind == .email }
            .prefix(5)
            .map { record in
                """
                REF: \(record.id)
                TITLE: \(record.title)
                TIMESTAMP: \(record.timestamp.map(isoString) ?? "")
                CONTENT:
                \(record.snippet)
                """
            }
            .joined(separator: "\n\n")

        guard !emailContexts.isEmpty else {
            return SelineChatToolExecutionResult(
                outputJSON: jsonString(["facts": [], "summary": "No email content available for extraction."]),
                records: hydrated.records,
                items: hydrated.items,
                note: "No email content available"
            )
        }

        let systemPrompt = """
        You extract exact travel and booking facts from email content.
        Return strict JSON only.
        """

        let userPrompt = """
        User question: \(query)

        Extract only grounded facts from these emails.
        Return JSON with this shape:
        {
          "high_confidence_answer": "short answer",
          "facts": [
            {
              "type": "flight|hotel|reservation|ticket|schedule|other",
              "summary": "short fact",
              "date_time": "ISO string or empty",
              "origin": "string or empty",
              "destination": "string or empty",
              "provider": "string or empty",
              "confirmation_code": "string or empty",
              "source_ref": "record ref"
            }
          ],
          "uncertainties": ["string"]
        }

        Emails:
        \(emailContexts)
        """

        let raw = try await OpenAIService.shared.simpleChatCompletion(
            systemPrompt: systemPrompt,
            messages: [["role": "user", "content": userPrompt]]
        )

        let extractedJSON = normalizedJSONObjectString(from: raw)
        return SelineChatToolExecutionResult(
            outputJSON: extractedJSON,
            records: hydrated.records,
            items: hydrated.items,
            note: "Extracted facts from \(hydrated.records.count) email(s)"
        )
    }

    private func searchPlaces(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let query = requiredString("query", in: arguments)
        let nearCurrentLocation = optionalBool("near_current_location", in: arguments) ?? false
        let currentLocation = nearCurrentLocation ? locationService.currentLocation : nil
        let normalizedQuery = sanitizedPlaceQuery(query)
        let placeTerms = placeSearchTerms(from: query)
        let queryForSearch = normalizedQuery.isEmpty ? query : normalizedQuery

        let savedMatches: [SavedPlace]
        if normalizedQuery.isEmpty && placeTerms.isEmpty {
            savedMatches = []
        } else {
            savedMatches = placesService
                .rankedMatches(query: queryForSearch, searchTerms: placeTerms, limit: 12)
                .compactMap { match -> (place: SavedPlace, score: Double)? in
                    let score = placeRelevanceScore(
                        name: match.place.displayName,
                        address: match.place.address,
                        category: match.place.category ?? match.place.userCuisine,
                        types: [match.place.category, match.place.userCuisine].compactMap { $0 },
                        normalizedQuery: normalizedQuery,
                        searchTerms: placeTerms
                    )
                    guard placeTerms.isEmpty || score > 0 else { return nil }
                    return (match.place, score)
                }
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.place.displayName.localizedCaseInsensitiveCompare(rhs.place.displayName) == .orderedAscending
                    }
                    return lhs.score > rhs.score
                }
                .map(\.place)
        }

        let mapResults = try await googleMapsService.searchPlaces(query: queryForSearch, currentLocation: currentLocation)
        let rankedMapResults = mapResults
            .map { result -> (place: SelineChatPlaceResult, score: Double) in
                let place = SelineChatPlaceResult(
                    id: "google_place:\(result.id)",
                    savedPlaceID: LocationsManager.shared.savedPlaces.first(where: { $0.googlePlaceId == result.id })?.id,
                    googlePlaceID: result.id,
                    name: result.name,
                    subtitle: result.address,
                    latitude: result.latitude,
                    longitude: result.longitude,
                    category: preferredPlaceCategory(from: result.types),
                    rating: nil,
                    isSaved: result.isSaved
                )
                let score = placeRelevanceScore(
                    name: result.name,
                    address: result.address,
                    category: preferredPlaceCategory(from: result.types),
                    types: result.types,
                    normalizedQuery: normalizedQuery,
                    searchTerms: placeTerms
                )
                return (place, score)
            }
            .filter { entry in
                placeTerms.isEmpty || entry.score > 0
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }

        var places: [SelineChatPlaceResult] = []
        places.append(contentsOf: placesService.placeResults(from: Array(savedMatches.prefix(4))))
        places.append(contentsOf: rankedMapResults.prefix(8).map { $0.place })

        let dedupedPlaces = Array(dedupePlaceResults(places).prefix(8))
        let records = dedupedPlaces.map(placeRecord)
        let output = compactJSON([
            "query": query,
            "near_current_location": nearCurrentLocation,
            "place_count": dedupedPlaces.count,
            "places": dedupedPlaces.map { place in
                compactJSON([
                    "ref": placeRef(for: place),
                    "name": place.name,
                    "address": place.subtitle,
                    "rating": place.rating,
                    "category": place.category,
                    "is_saved": place.isSaved
                ])
            }
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: records,
            places: dedupedPlaces,
            note: dedupedPlaces.isEmpty ? "No place matches found" : "Found \(dedupedPlaces.count) place result(s)"
        )
    }

    private func getPlaceDetails(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let placeRef = requiredString("place_ref", in: arguments)
        let resolution = try await resolvePlace(from: placeRef)
        let details = try await googleMapsService.getPlaceDetails(
            placeId: resolution.result.googlePlaceID,
            minimizeFields: false
        )

        let snippetParts = [
            details.isOpenNow.map { $0 ? "Open now." : "Closed right now." },
            !details.openingHours.isEmpty ? "Hours: \(details.openingHours.prefix(3).joined(separator: "; "))" : nil,
            details.phone,
            details.website
        ].compactMap { $0 }

        let record = SelineChatEvidenceRecord(
            id: placeRef,
            sourceKind: .place,
            title: details.name,
            snippet: snippetParts.joined(separator: " "),
            timestamp: nil,
            relationIDs: [resolution.result.googlePlaceID],
            externalURL: details.website
        )

        let output = compactJSON([
            "ref": placeRef,
            "name": details.name,
            "address": details.address,
            "phone": details.phone,
            "website": details.website,
            "rating": details.rating,
            "total_ratings": details.totalRatings,
            "is_open_now": details.isOpenNow,
            "opening_hours": details.openingHours,
            "types": details.types,
            "price_level": details.priceLevel
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: [record],
            places: [resolution.result],
            note: "Loaded details for \(details.name)"
        )
    }

    private func getTravelETA(arguments: [String: Any]) async throws -> SelineChatToolExecutionResult {
        let placeRef = optionalString("place_ref", in: arguments)
        let destination = optionalString("destination", in: arguments)

        guard let currentLocation = locationService.currentLocation else {
            throw SelineChatToolExecutorError.unavailable("Current location is unavailable, so I can't calculate an ETA yet.")
        }

        let resolution: PlaceResolution
        if let placeRef, !placeRef.isEmpty {
            resolution = try await resolvePlace(from: placeRef)
        } else if let destination, !destination.isEmpty {
            let results = try await googleMapsService.searchPlaces(query: destination, currentLocation: currentLocation)
            guard let first = results.first else {
                throw SelineChatToolExecutorError.unavailable("I couldn't resolve that destination for ETA.")
            }
            let placeResult = SelineChatPlaceResult(
                id: "google_place:\(first.id)",
                savedPlaceID: LocationsManager.shared.savedPlaces.first(where: { $0.googlePlaceId == first.id })?.id,
                googlePlaceID: first.id,
                name: first.name,
                subtitle: first.address,
                latitude: first.latitude,
                longitude: first.longitude,
                category: preferredPlaceCategory(from: first.types),
                rating: nil,
                isSaved: first.isSaved
            )
            resolution = PlaceResolution(ref: "google_place:\(first.id)", result: placeResult)
        } else {
            throw SelineChatToolExecutorError.invalidArguments("get_travel_eta requires either place_ref or destination.")
        }

        let eta = try await navigationService.calculateETA(
            from: currentLocation,
            to: CLLocationCoordinate2D(latitude: resolution.result.latitude, longitude: resolution.result.longitude)
        )

        let record = placeRecord(resolution.result)
        let output = compactJSON([
            "place_ref": resolution.ref,
            "destination_name": resolution.result.name,
            "destination_address": resolution.result.subtitle,
            "duration_text": eta.durationText,
            "duration_seconds": eta.durationSeconds,
            "distance_text": eta.distanceText,
            "distance_meters": eta.distanceMeters
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: [record],
            places: [resolution.result],
            note: "Calculated ETA to \(resolution.result.name)"
        )
    }

    private func webSearch(arguments: [String: Any]) async -> SelineChatToolExecutionResult {
        let query = (arguments["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return SelineChatToolExecutionResult(
                outputJSON: jsonString(["summary": ""]),
                note: "No web query provided"
            )
        }

        let response = await webSearchService.searchStructured(query: query)
        let summary = response?.summary ?? ""
        let citations = response?.citations ?? []
        let record: [SelineChatEvidenceRecord] = summary.isEmpty ? [] : [
            SelineChatEvidenceRecord(
                id: "web:\(UUID().uuidString)",
                sourceKind: .web,
                title: "Web search",
                snippet: summary,
                timestamp: nil,
                relationIDs: [],
                externalURL: citations.first?.url
            )
        ]
        let output = compactJSON([
            "query": query,
            "summary": summary,
            "citations": citations.map { citation in
                compactJSON([
                    "title": citation.title,
                    "url": citation.url,
                    "source": citation.source
                ])
            }
        ])

        return SelineChatToolExecutionResult(
            outputJSON: jsonString(output),
            records: record,
            citations: citations,
            note: citations.isEmpty ? "No web citations found" : "Loaded \(citations.count) web citation(s)"
        )
    }

    private func filteredNotes(sources: Set<PersonalSource>, interval: DateInterval?) -> [Note] {
        let wantsJournalsOnly = sources == [.journals]
        return notesManager.notes.filter { note in
            if wantsJournalsOnly, !note.isJournalEntry && !note.isJournalWeeklyRecap {
                return false
            }
            if !sources.contains(.notes) && !sources.contains(.journals) {
                return false
            }
            return matchesInterval(note.embeddingDate, interval: interval)
        }
    }

    private func filteredEvents(sources: Set<PersonalSource>, interval: DateInterval?) -> [TaskItem] {
        guard sources.contains(.events) else { return [] }
        return taskManager.getAllTasksIncludingArchived()
            .filter { !$0.isDeleted }
            .filter { matchesInterval(eventSearchDate($0), interval: interval) }
    }

    private func filteredReceipts(sources: Set<PersonalSource>, interval: DateInterval?) -> [ReceiptStat] {
        guard sources.contains(.receipts) else { return [] }
        return receiptManager.receipts.filter { matchesInterval($0.date, interval: interval) }
    }

    private func filteredPeople(sources: Set<PersonalSource>) -> [Person] {
        guard sources.contains(.people) else { return [] }
        return peopleManager.people
    }

    private func filteredTrackers(sources: Set<PersonalSource>) -> [TrackerThread] {
        guard sources.contains(.trackers) else { return [] }
        return trackerStore.threads
    }

    private func daySummaries(in interval: DateInterval, maxDays: Int) async -> [DaySummaryService.DaySummary] {
        var summaries: [DaySummaryService.DaySummary] = []
        for date in enumerateDates(in: interval, maxDays: maxDays) {
            if let summary = await daySummaryService.summary(for: date) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    private func matchedVisitIDs(for personIDs: [UUID]) async -> [UUID] {
        var ids: [UUID] = []
        for personID in personIDs.prefix(4) {
            ids.append(contentsOf: await peopleManager.getVisitIdsForPerson(personId: personID))
        }
        return Array(Set(ids))
    }

    private func matchedReceiptIDs(for personIDs: [UUID]) async -> [UUID] {
        var ids: [UUID] = []
        for personID in personIDs.prefix(4) {
            ids.append(contentsOf: await peopleManager.getReceiptIdsForPerson(personId: personID))
        }
        return Array(Set(ids))
    }

    private func vectorAugmentedRefs(
        query: String,
        interval: DateInterval?,
        sources: Set<PersonalSource>,
        limit: Int,
        liveEmails: [Email]
    ) async throws -> [String: Float] {
        let documentTypes = vectorDocumentTypes(for: sources)
        guard !documentTypes.isEmpty else { return [:] }

        let dateRange = interval.map { (start: $0.start, end: $0.end) }
        let results = try await VectorSearchService.shared.search(
            query: query,
            documentTypes: documentTypes,
            limit: limit,
            dateRange: dateRange,
            preferHistorical: interval == nil
        )

        let liveEmailIDs = Set(liveEmails.map(\.id))
        var scoredRefs: [String: Float] = [:]

        for result in results {
            guard let ref = vectorRef(for: result, liveEmailIDs: liveEmailIDs) else { continue }
            scoredRefs[ref] = max(scoredRefs[ref] ?? 0, result.similarity)
        }

        return scoredRefs
    }

    private func vectorDocumentTypes(for sources: Set<PersonalSource>) -> [VectorSearchService.DocumentType] {
        var documentTypes: [VectorSearchService.DocumentType] = []
        if sources.contains(.emails) { documentTypes.append(.email) }
        if sources.contains(.events) { documentTypes.append(.task) }
        if sources.contains(.notes) || sources.contains(.journals) { documentTypes.append(.note) }
        if sources.contains(.receipts) { documentTypes.append(.receipt) }
        if sources.contains(.visits) { documentTypes.append(.visit) }
        if sources.contains(.people) { documentTypes.append(.person) }
        if sources.contains(.trackers) { documentTypes.append(.tracker) }
        if sources.contains(.daySummaries) { documentTypes.append(.note) }
        return documentTypes
    }

    private func vectorRef(
        for result: VectorSearchService.SearchResult,
        liveEmailIDs: Set<String>
    ) -> String? {
        switch result.documentType {
        case .email:
            return liveEmailIDs.contains(result.documentId)
                ? "email:\(result.documentId)"
                : "saved_email:\(result.documentId)"
        case .task:
            return "event:\(result.documentId)"
        case .note:
            return "note:\(result.documentId)"
        case .location:
            return "place:\(result.documentId)"
        case .receipt:
            return "receipt:\(result.documentId)"
        case .visit:
            return "visit:\(result.documentId)"
        case .person:
            return "person:\(result.documentId)"
        case .tracker:
            return "tracker:\(result.documentId)"
        case .recurringExpense, .attachment, .budget:
            return nil
        }
    }

    private func hydrateRecords(
        _ refs: [String],
        detailLevel: RecordDetailLevel
    ) async -> (
        records: [SelineChatEvidenceRecord],
        items: [SelineChatEvidenceItem],
        places: [SelineChatPlaceResult],
        citations: [SelineChatWebCitation]
    ) {
        var records: [SelineChatEvidenceRecord] = []
        var items: [SelineChatEvidenceItem] = []
        var places: [SelineChatPlaceResult] = []
        var citations: [SelineChatWebCitation] = []

        await receiptManager.ensureLoaded()
        let liveEmails = allLiveEmails()

        for ref in refs {
            if ref.hasPrefix("email:") {
                let id = String(ref.dropFirst("email:".count))
                if let email = liveEmails.first(where: { $0.id == id }) {
                    let bodyOverride = detailLevel == .full ? await fullEmailBody(for: email) : nil
                    records.append(liveEmailRecord(email, detailLevel: detailLevel, bodyOverride: bodyOverride))
                    items.append(liveEmailItem(email))
                }
                continue
            }

            if ref.hasPrefix("saved_email:") {
                let id = String(ref.dropFirst("saved_email:".count))
                if let savedID = UUID(uuidString: id),
                   let savedEmail = try? await EmailFolderService.shared.fetchSavedEmail(id: savedID) {
                    records.append(savedEmailRecord(savedEmail, detailLevel: detailLevel))
                }
                continue
            }

            if ref.hasPrefix("event:") {
                let id = String(ref.dropFirst("event:".count))
                if let event = taskManager.getAllTasksIncludingArchived().first(where: { $0.id == id }) {
                    records.append(eventRecord(event, detailLevel: detailLevel))
                    items.append(eventItem(event))
                }
                continue
            }

            if ref.hasPrefix("note:") {
                let id = String(ref.dropFirst("note:".count))
                if let uuid = UUID(uuidString: id),
                   let note = notesManager.notes.first(where: { $0.id == uuid }) {
                    records.append(noteRecord(note, detailLevel: detailLevel))
                    items.append(noteItem(note))
                }
                continue
            }

            if ref.hasPrefix("receipt:") {
                let id = String(ref.dropFirst("receipt:".count))
                if let uuid = UUID(uuidString: id),
                   let receipt = receiptManager.receipt(by: uuid) {
                    records.append(receiptRecord(receipt, detailLevel: detailLevel))
                    items.append(receiptItem(receipt))
                }
                continue
            }

            if ref.hasPrefix("visit:") {
                let id = String(ref.dropFirst("visit:".count))
                if let uuid = UUID(uuidString: id),
                   let visit = await fetchVisits(withIDs: [uuid]).first {
                    let people = await peopleManager.getPeopleForVisit(visitId: visit.id)
                    let payload = visitPayload(visit, people: people, detailLevel: detailLevel)
                    records.append(payload.0)
                    items.append(payload.1)
                }
                continue
            }

            if ref.hasPrefix("person:") {
                let id = String(ref.dropFirst("person:".count))
                if let uuid = UUID(uuidString: id),
                   let person = peopleManager.getPerson(by: uuid) {
                    records.append(personRecord(person, detailLevel: detailLevel))
                    items.append(personItem(person))
                }
                continue
            }

            if ref.hasPrefix("tracker:") {
                let id = String(ref.dropFirst("tracker:".count))
                if let uuid = UUID(uuidString: id),
                   let tracker = trackerStore.threads.first(where: { $0.id == uuid }) {
                    records.append(trackerRecord(tracker))
                    items.append(trackerItem(tracker))
                }
                continue
            }

            if ref.hasPrefix("day_summary:") {
                let id = String(ref.dropFirst("day_summary:".count))
                if let uuid = UUID(uuidString: id),
                   let summary = await daySummaryService.summary(id: uuid) {
                    records.append(daySummaryRecord(summary))
                    items.append(daySummaryItem(summary))
                }
                continue
            }

            if ref.hasPrefix("place:") || ref.hasPrefix("google_place:") {
                if let resolution = try? await resolvePlace(from: ref) {
                    places.append(resolution.result)
                    records.append(placeRecord(resolution.result))
                }
                continue
            }

            if ref.hasPrefix("web:") {
                citations.append(SelineChatWebCitation(title: "Web result", url: ""))
            }
        }

        return (
            dedupeRecords(records),
            dedupeItems(items),
            dedupePlaceResults(places),
            citations.filter { !$0.url.isEmpty }
        )
    }

    private func resolvePlace(from ref: String) async throws -> PlaceResolution {
        if ref.hasPrefix("place:") {
            let id = String(ref.dropFirst("place:".count))
            guard let uuid = UUID(uuidString: id),
                  let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == uuid }) else {
                throw SelineChatToolExecutorError.unavailable("I couldn't resolve that saved place.")
            }
            return PlaceResolution(ref: ref, result: placesService.placeResults(from: [place]).first!)
        }

        if ref.hasPrefix("google_place:") {
            let googlePlaceID = String(ref.dropFirst("google_place:".count))
            if let savedPlace = LocationsManager.shared.savedPlaces.first(where: { $0.googlePlaceId == googlePlaceID }) {
                return PlaceResolution(
                    ref: ref,
                    result: placesService.placeResults(from: [savedPlace]).first!
                )
            }

            let details = try await googleMapsService.getPlaceDetails(placeId: googlePlaceID, minimizeFields: true)
            let transientPlace = SelineChatPlaceResult(
                id: ref,
                savedPlaceID: nil,
                googlePlaceID: googlePlaceID,
                name: details.name,
                subtitle: details.address,
                latitude: details.latitude,
                longitude: details.longitude,
                category: details.types.first,
                rating: details.rating,
                isSaved: false
            )
            return PlaceResolution(ref: ref, result: transientPlace)
        }

        throw SelineChatToolExecutorError.invalidArguments("Unsupported place ref: \(ref)")
    }

    private func allLiveEmails() -> [Email] {
        dedupeEmails((emailService.inboxEmails + emailService.sentEmails).sorted { $0.timestamp > $1.timestamp })
    }

    private func emailsOnSameDay(_ date: Date) -> [Email] {
        emailService.inboxEmails.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
    }

    private func sentEmailsOnSameDay(_ date: Date) -> [Email] {
        emailService.sentEmails.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
    }

    private func receiptsOnSameDay(_ date: Date) -> [ReceiptStat] {
        receiptManager.receipts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    private func notesOnSameDay(_ date: Date) -> [Note] {
        notesManager.notes
            .filter { Calendar.current.isDate($0.embeddingDate, inSameDayAs: date) }
            .sorted { $0.embeddingDate > $1.embeddingDate }
    }

    private func fetchVisits(in interval: DateInterval, limit: Int) async -> [LocationVisitRecord] {
        guard let userID = SupabaseManager.shared.getCurrentUser()?.id else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userID.uuidString)
                .gte("entry_time", value: interval.start.ISO8601Format())
                .lt("entry_time", value: interval.end.ISO8601Format())
                .order("entry_time", ascending: false)
                .execute()

            let visits = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
            return Array(visits.prefix(limit))
        } catch {
            return []
        }
    }

    private func fetchVisits(withIDs visitIDs: [UUID]) async -> [LocationVisitRecord] {
        guard let userID = SupabaseManager.shared.getCurrentUser()?.id,
              !visitIDs.isEmpty else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userID.uuidString)
                .in("id", values: visitIDs.map(\.uuidString))
                .order("entry_time", ascending: false)
                .execute()

            return try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
        } catch {
            return []
        }
    }

    private func fetchRecentVisits(limit: Int) async -> [LocationVisitRecord] {
        guard let userID = SupabaseManager.shared.getCurrentUser()?.id else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let visits = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
            return Array(visits.prefix(limit))
        } catch {
            return []
        }
    }

    private func dayInterval(for date: Date) -> DateInterval {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    private func enumerateDates(in interval: DateInterval, maxDays: Int) -> [Date] {
        var dates: [Date] = []
        var cursor = Calendar.current.startOfDay(for: interval.start)
        let limit = max(maxDays, 1)

        while cursor < interval.end && dates.count < limit {
            dates.append(cursor)
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }

        if dates.isEmpty {
            dates = [Calendar.current.startOfDay(for: interval.start)]
        }

        return dates
    }

    private func requestedSources(from arguments: [String: Any]) -> Set<PersonalSource> {
        let requested = optionalStringArray("sources", in: arguments)
            .compactMap(PersonalSource.init(rawValue:))
        return requested.isEmpty ? Set(PersonalSource.allCases) : Set(requested)
    }

    private func resolveInterval(
        naturalLanguage: String?,
        startDate: String?,
        endDate: String?
    ) -> DateInterval? {
        if let startDate, let endDate,
           let start = parseDate(startDate),
           let end = parseDate(endDate) {
            let resolvedEnd = end >= start ? end : start
            return DateInterval(start: start, end: resolvedEnd)
        }

        if let naturalLanguage,
           let range = temporalService.extractTemporalRange(from: naturalLanguage) {
            let bounds = temporalService.normalizedBounds(for: range)
            return DateInterval(start: bounds.start, end: bounds.end)
        }

        if let startDate, let parsed = parseDate(startDate) {
            let start = Calendar.current.startOfDay(for: parsed)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? parsed
            return DateInterval(start: start, end: end)
        }

        return nil
    }

    private func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter().date(from: trimmed) {
            return iso
        }
        if let day = FormatterCache.shortDate.date(from: trimmed) {
            return day
        }
        return dayFormatter.date(from: trimmed)
    }

    private func exactScore(
        text: String,
        normalizedQuery: String,
        terms: [String]
    ) -> Double {
        guard !text.isEmpty else { return 0 }
        var score = 0.0
        if !normalizedQuery.isEmpty && text.contains(normalizedQuery) {
            score += 8
        }
        for term in terms {
            if text.contains(term) {
                score += term.count >= 5 ? 2.2 : 1.0
            }
        }
        return score
    }

    private func travelKeywordBoost(for email: Email) -> Double {
        let searchable = normalize(email.subject + " " + email.previewText)
        let keywords = ["flight", "boarding", "reservation", "itinerary", "hotel", "airline", "ticket", "booking", "gate", "terminal"]
        return keywords.reduce(into: 0.0) { result, keyword in
            if searchable.contains(keyword) {
                result += 2.5
            }
        }
    }

    private func eventSearchDate(_ task: TaskItem) -> Date {
        task.scheduledTime ?? task.targetDate ?? task.createdAt
    }

    private func intervalBoost(for date: Date, interval: DateInterval?) -> Double {
        guard let interval, interval.contains(date) else { return 0 }
        return 1.5
    }

    private func matchesInterval(_ date: Date, interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        return interval.contains(date)
    }

    private func eventSearchableText(_ task: TaskItem) -> String {
        [
            task.title,
            task.description,
            task.location,
            task.emailSubject,
            task.emailSenderName,
            task.emailSnippet
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func personSearchableText(_ person: Person) -> String {
        [
            person.name,
            person.nickname,
            person.relationshipDisplayText,
            person.notes,
            person.howWeMet,
            person.favouriteFood,
            person.favouriteGift,
            person.favouriteColor,
            person.interests?.joined(separator: " ")
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func visitSearchableText(_ visit: LocationVisitRecord) -> String {
        let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        return [
            place?.displayName,
            place?.address,
            visit.visitNotes,
            visit.dayOfWeek,
            visit.timeOfDay
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func buildFallbackDayOverview(
        date: Date,
        events: [TaskItem],
        visits: [LocationVisitRecord],
        notes: [Note],
        receipts: [ReceiptStat],
        inboxEmails: [Email],
        sentEmails: [Email]
    ) -> String {
        let dateLabel = formattedLongDate(date)
        var parts: [String] = []

        if !events.isEmpty {
            let eventTitles = events.prefix(3).map(\.title).joined(separator: ", ")
            parts.append("You have \(events.count) scheduled item(s), including \(eventTitles).")
        }
        if !visits.isEmpty {
            let places = Array(
                Set(
                    visits.compactMap { visit in
                        LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName
                    }
                )
            ).prefix(3)
            if !places.isEmpty {
                parts.append("Visits include \(places.joined(separator: ", ")).")
            }
        }
        if !receipts.isEmpty {
            let total = receipts.reduce(0) { $0 + $1.amount }
            parts.append("Spending totals \(CurrencyParser.formatAmount(total)).")
        }
        if !notes.isEmpty {
            parts.append("There are \(notes.count) note(s) tied to the day.")
        }
        let emailCount = inboxEmails.count + sentEmails.count
        if emailCount > 0 {
            parts.append("There are \(emailCount) email(s) from that day.")
        }

        if parts.isEmpty {
            return "I found very little Seline activity for \(dateLabel)."
        }

        return parts.joined(separator: " ")
    }

    private func liveEmailRecord(
        _ email: Email,
        detailLevel: RecordDetailLevel,
        bodyOverride: String? = nil
    ) -> SelineChatEvidenceRecord {
        let body = detailLevel == .full ? (bodyOverride ?? email.body ?? email.previewText) : email.previewText
        return SelineChatEvidenceRecord(
            id: "email:\(email.id)",
            sourceKind: .email,
            title: email.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No subject)" : email.subject,
            snippet: clipped(body, limit: detailLevel == .full ? 2000 : 260),
            timestamp: email.timestamp,
            relationIDs: [],
            externalURL: nil
        )
    }

    private func savedEmailRecord(_ email: SavedEmail, detailLevel: RecordDetailLevel) -> SelineChatEvidenceRecord {
        SelineChatEvidenceRecord(
            id: "saved_email:\(email.id.uuidString)",
            sourceKind: .email,
            title: email.subject,
            snippet: clipped(detailLevel == .full ? (email.body ?? email.previewText) : email.previewText, limit: detailLevel == .full ? 2000 : 260),
            timestamp: email.timestamp,
            relationIDs: [],
            externalURL: nil
        )
    }

    private func liveEmailItem(_ email: Email) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "email-item-\(email.id)",
            kind: .email,
            title: email.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No subject)" : email.subject,
            subtitle: email.sender.displayName,
            detail: clipped(email.previewText, limit: 200),
            footnote: FormatterCache.formattedEmailTimestamp(email.timestamp),
            date: email.timestamp,
            emailID: email.id,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func eventRecord(_ task: TaskItem, detailLevel: RecordDetailLevel) -> SelineChatEvidenceRecord {
        let details = [
            task.formattedTimeRange.isEmpty ? nil : task.formattedTimeRange,
            task.location,
            detailLevel == .full ? task.description : nil
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

        return SelineChatEvidenceRecord(
            id: "event:\(task.id)",
            sourceKind: .event,
            title: task.title,
            snippet: details.isEmpty ? "Scheduled item" : clipped(details, limit: 600),
            timestamp: eventSearchDate(task),
            relationIDs: [],
            externalURL: nil
        )
    }

    private func eventItem(_ task: TaskItem) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "event-item-\(task.id)",
            kind: .event,
            title: task.title,
            subtitle: task.formattedTimeRange.isEmpty ? "Event" : task.formattedTimeRange,
            detail: task.location,
            footnote: nil,
            date: eventSearchDate(task),
            emailID: nil,
            noteID: nil,
            taskID: task.id,
            placeID: nil,
            personID: nil
        )
    }

    private func noteRecord(_ note: Note, detailLevel: RecordDetailLevel) -> SelineChatEvidenceRecord {
        SelineChatEvidenceRecord(
            id: "note:\(note.id.uuidString)",
            sourceKind: .note,
            title: note.title,
            snippet: clipped(detailLevel == .full ? note.displayContent : note.preview, limit: detailLevel == .full ? 1800 : 260),
            timestamp: note.embeddingDate,
            relationIDs: [],
            externalURL: nil
        )
    }

    private func noteItem(_ note: Note) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "note-item-\(note.id.uuidString)",
            kind: .note,
            title: note.title,
            subtitle: note.isJournalEntry ? "Journal" : "Note",
            detail: clipped(note.preview, limit: 160),
            footnote: FormatterCache.shortDate.string(from: note.embeddingDate),
            date: note.embeddingDate,
            emailID: nil,
            noteID: note.id,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func receiptRecord(_ receipt: ReceiptStat, detailLevel: RecordDetailLevel) -> SelineChatEvidenceRecord {
        let extra: [String]
        if detailLevel == .full {
            extra = [
                receipt.category,
                receipt.paymentMethod,
                receipt.lineItems.prefix(5).map(\.title).joined(separator: ", ")
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        } else {
            extra = [receipt.category].filter { !$0.isEmpty }
        }
        let summary = "\(CurrencyParser.formatAmount(receipt.amount)) • \(extra.filter { !$0.isEmpty }.joined(separator: " • "))"
        return SelineChatEvidenceRecord(
            id: "receipt:\(receipt.id.uuidString)",
            sourceKind: .receipt,
            title: receipt.title,
            snippet: clipped(summary, limit: 900),
            timestamp: receipt.date,
            relationIDs: [receipt.noteId.uuidString],
            externalURL: nil
        )
    }

    private func receiptItem(_ receipt: ReceiptStat) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "receipt-item-\(receipt.id.uuidString)",
            kind: .receipt,
            title: receipt.title,
            subtitle: CurrencyParser.formatAmount(receipt.amount),
            detail: receipt.category,
            footnote: FormatterCache.shortDate.string(from: receipt.date),
            date: receipt.date,
            emailID: nil,
            noteID: receipt.legacyNoteId ?? receipt.noteId,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func visitPayload(
        _ visit: LocationVisitRecord,
        people: [Person],
        detailLevel: RecordDetailLevel
    ) -> (SelineChatEvidenceRecord, SelineChatEvidenceItem) {
        let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        let placeName = place?.displayName ?? "Visit"
        let peopleList = people.map(\.displayName).joined(separator: ", ")
        let parts = [
            formattedVisitRange(start: visit.entryTime, end: visit.exitTime),
            visit.durationMinutes.map { "\($0)m" },
            peopleList.isEmpty ? nil : "With \(peopleList)",
            detailLevel == .full ? visit.visitNotes : nil
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        let record = SelineChatEvidenceRecord(
            id: "visit:\(visit.id.uuidString)",
            sourceKind: .visit,
            title: placeName,
            snippet: clipped(parts.joined(separator: " • "), limit: 900),
            timestamp: visit.entryTime,
            relationIDs: [visit.savedPlaceId.uuidString] + people.map { $0.id.uuidString },
            externalURL: nil
        )

        let item = SelineChatEvidenceItem(
            id: "visit-item-\(visit.id.uuidString)",
            kind: .visit,
            title: placeName,
            subtitle: visit.durationMinutes.map { "\($0) min" } ?? "Visit",
            detail: peopleList.isEmpty ? nil : peopleList,
            footnote: formattedVisitRange(start: visit.entryTime, end: visit.exitTime),
            date: visit.entryTime,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: visit.savedPlaceId,
            personID: nil
        )

        return (record, item)
    }

    private func personRecord(_ person: Person, detailLevel: RecordDetailLevel) -> SelineChatEvidenceRecord {
        let details = [
            person.relationshipDisplayText,
            person.notes,
            detailLevel == .full ? person.howWeMet : nil,
            detailLevel == .full ? person.interests?.joined(separator: ", ") : nil
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

        return SelineChatEvidenceRecord(
            id: "person:\(person.id.uuidString)",
            sourceKind: .person,
            title: person.displayName,
            snippet: clipped(details.isEmpty ? person.relationshipDisplayText : details, limit: 1200),
            timestamp: person.dateModified,
            relationIDs: [],
            externalURL: nil
        )
    }

    private func personItem(_ person: Person) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "person-item-\(person.id.uuidString)",
            kind: .person,
            title: person.displayName,
            subtitle: person.relationshipDisplayText,
            detail: clipped(person.notes ?? "", limit: 160),
            footnote: nil,
            date: person.dateModified,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: person.id
        )
    }

    private func trackerRecord(_ tracker: TrackerThread) -> SelineChatEvidenceRecord {
        SelineChatEvidenceRecord(
            id: "tracker:\(tracker.id.uuidString)",
            sourceKind: .tracker,
            title: tracker.title,
            snippet: clipped(trackerSummary(tracker), limit: 500),
            timestamp: tracker.updatedAt,
            relationIDs: [],
            externalURL: nil
        )
    }

    private func trackerItem(_ tracker: TrackerThread) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "tracker-item-\(tracker.id.uuidString)",
            kind: .tracker,
            title: tracker.title,
            subtitle: tracker.status.rawValue.capitalized,
            detail: clipped(trackerSummary(tracker), limit: 140),
            footnote: nil,
            date: tracker.updatedAt,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func daySummaryRecord(_ summary: DaySummaryService.DaySummary) -> SelineChatEvidenceRecord {
        SelineChatEvidenceRecord(
            id: "day_summary:\(summary.id.uuidString)",
            sourceKind: .daySummary,
            title: summary.title,
            snippet: clipped(summary.summaryText, limit: 1200),
            timestamp: summary.summaryDate,
            relationIDs: summary.sourceRefs.map(\.id),
            externalURL: nil
        )
    }

    private func daySummaryItem(_ summary: DaySummaryService.DaySummary) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "day-summary-item-\(summary.id.uuidString)",
            kind: .daySummary,
            title: summary.title,
            subtitle: FormatterCache.shortDate.string(from: summary.summaryDate),
            detail: clipped(summary.summaryText, limit: 160),
            footnote: summary.mood,
            date: summary.summaryDate,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func placeRecord(_ place: SelineChatPlaceResult) -> SelineChatEvidenceRecord {
        let snippetParts: [String] = [
            place.subtitle,
            place.category,
            place.rating.map { "Rating \($0)" }
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return SelineChatEvidenceRecord(
            id: placeRef(for: place),
            sourceKind: .place,
            title: place.name,
            snippet: clipped(snippetParts.joined(separator: " • "), limit: 400),
            timestamp: nil,
            relationIDs: [place.googlePlaceID] + (place.savedPlaceID.map { [$0.uuidString] } ?? []),
            externalURL: nil
        )
    }

    private func placeRef(for place: SelineChatPlaceResult) -> String {
        if let savedPlaceID = place.savedPlaceID {
            return "place:\(savedPlaceID.uuidString)"
        }
        return "google_place:\(place.googlePlaceID)"
    }

    private func fullEmailBody(for email: Email) async -> String? {
        if let body = email.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }

        let messageID = email.gmailMessageId ?? email.id
        if let body = try? await GmailAPIClient.shared.fetchBodyForAI(messageId: messageID),
           !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }

        return nil
    }

    private func trackerSummary(_ tracker: TrackerThread) -> String {
        tracker.cachedState?.summaryLine
            ?? tracker.subtitle
            ?? tracker.memorySnapshot.normalizedSummaryText
    }

    private func dedupeRecords(_ records: [SelineChatEvidenceRecord]) -> [SelineChatEvidenceRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }
    }

    private func dedupeItems(_ items: [SelineChatEvidenceItem]) -> [SelineChatEvidenceItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func dedupePlaceResults(_ results: [SelineChatPlaceResult]) -> [SelineChatPlaceResult] {
        var seen = Set<String>()
        return results.filter { place in
            let key = place.savedPlaceID?.uuidString ?? place.googlePlaceID
            return seen.insert(key).inserted
        }
    }

    private func dedupeEmails(_ emails: [Email]) -> [Email] {
        var seen = Set<String>()
        return emails.filter { seen.insert($0.id).inserted }
    }

    private func parseArguments(_ json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SelineChatToolExecutorError.invalidArguments("Tool arguments must be valid JSON.")
        }
        return object
    }

    private func requiredString(_ key: String, in arguments: [String: Any]) -> String {
        optionalString(key, in: arguments) ?? ""
    }

    private func optionalString(_ key: String, in arguments: [String: Any]) -> String? {
        (arguments[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private func optionalInt(_ key: String, in arguments: [String: Any]) -> Int? {
        if let value = arguments[key] as? Int { return value }
        if let value = arguments[key] as? Double { return Int(value) }
        if let value = arguments[key] as? String { return Int(value) }
        return nil
    }

    private func optionalBool(_ key: String, in arguments: [String: Any]) -> Bool? {
        if let value = arguments[key] as? Bool { return value }
        if let value = arguments[key] as? String { return Bool(value) }
        return nil
    }

    private func requiredStringArray(_ key: String, in arguments: [String: Any]) -> [String] {
        optionalStringArray(key, in: arguments)
    }

    private func optionalStringArray(_ key: String, in arguments: [String: Any]) -> [String] {
        (arguments[key] as? [Any])?
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func functionDefinition(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ]
        ]
    }

    private func stringProperty(description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private func integerProperty(description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private func boolProperty(description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private func arrayProperty(description: String, itemSchema: [String: Any]) -> [String: Any] {
        [
            "type": "array",
            "description": description,
            "items": itemSchema
        ]
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchTerms(from query: String) -> [String] {
        let tokens = normalize(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count > 1 }
        var terms = tokens
        if tokens.count >= 2 {
            for index in 0..<(tokens.count - 1) {
                terms.append(tokens[index] + " " + tokens[index + 1])
            }
        }
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    private func sanitizedPlaceQuery(_ query: String) -> String {
        let tokens = normalize(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && !genericPlaceQueryTokens.contains($0) }
        return tokens.joined(separator: " ")
    }

    private func placeSearchTerms(from query: String) -> [String] {
        let sanitized = sanitizedPlaceQuery(query)
        guard !sanitized.isEmpty else { return [] }
        let base = searchTerms(from: sanitized)
        var expanded = base

        for token in sanitized.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let aliases = placeIntentAliases[token] {
                expanded.append(contentsOf: aliases)
            }
        }

        var seen = Set<String>()
        return expanded
            .map(normalize)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func placeRelevanceScore(
        name: String,
        address: String,
        category: String?,
        types: [String],
        normalizedQuery: String,
        searchTerms: [String]
    ) -> Double {
        let normalizedName = normalize(name)
        let normalizedAddress = normalize(address)
        let normalizedCategory = normalize(category ?? "")
        let normalizedTypes = types.map {
            normalize($0.replacingOccurrences(of: "_", with: " "))
        }
        let searchable = ([normalizedName, normalizedAddress, normalizedCategory] + normalizedTypes)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !searchable.isEmpty else { return 0 }

        var score = 0.0

        if !normalizedQuery.isEmpty {
            if normalizedName == normalizedQuery {
                score += 12
            } else if normalizedName.contains(normalizedQuery) {
                score += 8
            } else if searchable.contains(normalizedQuery) {
                score += 4
            }
        }

        for term in searchTerms where !term.isEmpty {
            if normalizedName.contains(term) {
                score += term.contains(" ") ? 6 : 4
            } else if normalizedCategory.contains(term) {
                score += term.contains(" ") ? 5 : 3
            } else if normalizedTypes.contains(where: { $0.contains(term) }) {
                score += term.contains(" ") ? 5 : 3
            } else if searchable.contains(term) {
                score += term.contains(" ") ? 2.5 : 1.5
            }
        }

        return score
    }

    private func preferredPlaceCategory(from types: [String]) -> String? {
        let normalizedGeneric = Set(["establishment", "point_of_interest", "point of interest", "food", "store"])
        if let specific = types.first(where: { !normalizedGeneric.contains($0.lowercased()) }) {
            return specific.replacingOccurrences(of: "_", with: " ")
        }
        return types.first?.replacingOccurrences(of: "_", with: " ")
    }

    private func clipped(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func formattedLongDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func formattedVisitRange(start: Date, end: Date?) -> String {
        let startText = FormatterCache.shortDateTime.string(from: start)
        guard let end else { return startText }
        return "\(startText) to \(FormatterCache.shortDateTime.string(from: end))"
    }

    private func compactJSON(_ dictionary: [String: Any?]) -> [String: Any] {
        dictionary.reduce(into: [String: Any]()) { result, entry in
            if let value = entry.value {
                result[entry.key] = value
            }
        }
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func normalizedJSONObjectString(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return jsonString(["summary": trimmed])
        }
        return String(trimmed[start...end])
    }

    private func isoString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
