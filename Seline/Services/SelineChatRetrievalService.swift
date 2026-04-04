import Foundation

struct SelineChatRetrievedContext {
    let frame: SelineChatQuestionFrame
    var emails: [Email] = []
    var notes: [Note] = []
    var visits: [LocationVisitRecord] = []
    var receipts: [ReceiptStat] = []
    var places: [SavedPlace] = []
    var people: [Person] = []
    var peopleByVisit: [UUID: [Person]] = [:]
    var peopleByReceipt: [UUID: [Person]] = [:]
    var graphRelations: [SelineChatEvidenceRelation] = []
    var openQuestions: [String] = []
    var daySummaries: [DaySummaryService.DaySummary] = []
    var trackers: [TrackerThread] = []
    /// Full email bodies keyed by email.id — fetched on demand for top relevant emails
    var emailBodies: [String: String] = [:]
    /// Web search result text — populated when the query needs external/factual information
    var webSearchResult: String? = nil
}

@MainActor
final class SelineChatEvidenceRetriever {
    private let emailService = EmailService.shared
    private let notesManager = NotesManager.shared
    private let receiptManager = ReceiptManager.shared
    private let peopleManager = PeopleManager.shared
    private let locationsManager = LocationsManager.shared
    private let placesService = SelineChatPlacesService()
    private let memoryResolver = SelineChatMemoryClusterResolver()

    private let emailCap = 4
    private let noteCap = 4
    private let visitCap = 6
    private let receiptCap = 4
    private let placeCap = 4
    private let peopleCap = 4
    private let candidateMultiplier = 3

    func retrieve(
        for frame: SelineChatQuestionFrame,
        activeContext: SelineChatActiveContext?
    ) async -> SelineChatRetrievedContext {
        var context = SelineChatRetrievedContext(frame: frame)

        let allEmails = allEmailsSnapshot()
        let allPeople = peopleManager.people
        let allPlaces = locationsManager.savedPlaces
        let allReceipts = await allReceiptsSnapshot()

        // Exclude legacy receipt-backed notes from note retrieval — receipts are their own domain now
        let receiptNoteIDs = Set(allReceipts.compactMap(\.legacyNoteId))
        let allNotes = notesManager.notes.filter { !receiptNoteIDs.contains($0.id) }

        // Fetch semantic search scores in parallel with keyword retrieval
        let semanticScores = await fetchSemanticScores(for: frame)

        if frame.isExplicitFollowUp {
            await seedFromExplicitFollowUp(
                context: &context,
                activeContext: activeContext,
                allEmails: allEmails,
                allNotes: allNotes,
                allPeople: allPeople,
                allPlaces: allPlaces,
                allReceipts: allReceipts
            )

            if !context.openQuestions.isEmpty {
                finalize(&context, frame: frame)
                return context
            }

            // For episode follow-ups that resolved specific visits, expand the context
            // with notes/receipts from those visit dates and return immediately.
            // Skipping the full pipeline prevents the cluster resolver from overwriting
            // the anchor visits with unrelated recent activity.
            if frame.followUpTargetType == .episode, !context.visits.isEmpty {
                let visitDates = context.visits.map { Calendar.current.startOfDay(for: $0.entryTime) }
                let uniqueDates = Array(Set(visitDates))

                // Pull in notes from the same day(s) as the anchor visits
                let anchorNotes = allNotes.filter { note in
                    let noteDate = Calendar.current.startOfDay(for: note.journalDate ?? note.dateModified)
                    return uniqueDates.contains(noteDate)
                }
                context.notes = Array(anchorNotes.prefix(noteCap))

                // Pull in receipts from the same day(s)
                let anchorReceipts = allReceipts.filter { receipt in
                    let receiptDate = Calendar.current.startOfDay(for: receipt.date)
                    return uniqueDates.contains(receiptDate)
                }
                context.receipts = Array(anchorReceipts.prefix(receiptCap))

                finalize(&context, frame: frame)
                return context
            }
        }

        let rankedPlaces = candidatePlaces(for: frame)
        let rankedPeople = rankPeople(
            allPeople,
            using: frame.searchTerms,
            entityMentions: frame.entityMentions,
            timeScope: frame.timeScope
        )
        let rankedEmails = rankEmails(
            allEmails,
            using: frame.searchTerms,
            entityMentions: frame.entityMentions,
            timeScope: frame.timeScope
        )
        let rankedNotes = rankNotes(
            allNotes,
            using: frame.searchTerms,
            entityMentions: frame.entityMentions,
            timeScope: frame.timeScope
        )
        let rankedReceipts = rankReceipts(
            allReceipts,
            using: frame.searchTerms,
            entityMentions: frame.entityMentions,
            timeScope: frame.timeScope
        )

        let candidatePlaces = mergeUniquePlaces(
            context.places,
            rankedPlaces.prefix(placeCap * candidateMultiplier).map { $0.place }
        )
        let candidatePeople = mergeUniquePeople(
            context.people,
            rankedPeople.prefix(peopleCap * candidateMultiplier)
        )
        let candidateEmails = mergeUniqueEmails(
            context.emails,
            rankedEmails.prefix(emailCap * candidateMultiplier)
        )
        let candidateNotes = mergeUniqueNotes(
            context.notes,
            rankedNotes.prefix(noteCap * candidateMultiplier)
        )
        let candidateReceipts = mergeUniqueReceipts(
            context.receipts,
            rankedReceipts.prefix(receiptCap * candidateMultiplier)
        )

        let candidateVisits = mergeUniqueVisits(
            context.visits,
            await retrieveRelevantVisits(
                frame: frame,
                matchedPlaces: candidatePlaces,
                matchedPeople: candidatePeople,
                limit: visitCap * candidateMultiplier * 2
            )
        )

        let candidatePeopleByVisit = await peopleManager.getPeopleForVisits(visitIds: candidateVisits.map(\.id))
        var candidatePeopleByReceipt: [UUID: [Person]] = [:]
        for receipt in candidateReceipts {
            candidatePeopleByReceipt[receipt.id] = await peopleManager.getPeopleForReceipt(
                receiptId: receipt.id,
                legacyNoteId: receipt.legacyNoteId
            )
        }

        // Only disambiguate places when the query is genuinely about a saved place —
        // NOT when it's a general/travel/email query (e.g. "my flight to Atlanta", "flight info").
        // A places-focused query has places as its primary domain, not mixed in via baseDomains fallback.
        // Heuristic: skip disambiguation when emails are also requested (travel/booking queries)
        // or when places is not the only domain alongside visits.
        let isPlacesFocusedQuery = frame.requestedDomains.isSubset(of: [.places, .visits, .people])
        if context.places.isEmpty,
           frame.requestedDomains.contains(.places),
           isPlacesFocusedQuery,
           frame.wantsSpecificObject,
           !frame.isExplicitFollowUp {
            if rankedPlaces.isEmpty {
                context.openQuestions.append("I couldn't match that to one of your saved places yet.")
            } else if rankedPlaces.count > 1 && rankedPlaces[0].score - rankedPlaces[1].score < 1.5 {
                let options = rankedPlaces.prefix(3).map { $0.place.displayName }.joined(separator: ", ")
                context.openQuestions.append("I found a few matching saved places. Which one did you mean: \(options)?")
            } else if let best = rankedPlaces.first?.place {
                context.places = [best]
            }
        }

        // Apply semantic boost: re-rank candidates by promoting semantically matched items
        let semanticallyBoostedEmails = applySemanticBoost(to: candidateEmails, docType: "email", idKeyPath: \.id, semanticScores: semanticScores)
        let semanticallyBoostedNotes = applySemanticBoost(to: candidateNotes, docType: "note", idKeyPath: { $0.id.uuidString }, semanticScores: semanticScores)
        let semanticallyBoostedReceipts = applySemanticBoost(to: candidateReceipts, docType: "receipt", idKeyPath: { $0.id.uuidString }, semanticScores: semanticScores)
        let semanticallyBoostedPeople = applySemanticBoost(to: candidatePeople, docType: "person", idKeyPath: { $0.id.uuidString }, semanticScores: semanticScores)

        // Specific queries (any named entity or time scope) bypass the cluster resolver.
        // The cluster picks ONE best-scoring theme and silently drops everything else —
        // exactly wrong when the user asks about a specific person, place, date, or combo.
        // For specific queries, all retrieval paths have already run and candidates are
        // scored; use them directly so the LLM sees the full relevant picture.
        //
        // The cluster is reserved for truly ambient queries ("what have I been up to?")
        // where there are no anchors and theme-picking is actually useful.
        let isSpecificQuery = !frame.entityMentions.isEmpty || frame.timeScope != nil

        if !isSpecificQuery, let clusteredContext = buildClusteredContext(
            frame: frame,
            baseContext: context,
            allPeople: allPeople,
            allPlaces: allPlaces,
            emails: semanticallyBoostedEmails,
            notes: semanticallyBoostedNotes,
            visits: candidateVisits,
            receipts: semanticallyBoostedReceipts,
            places: mergeUniquePlaces(candidatePlaces, context.places),
            people: semanticallyBoostedPeople,
            peopleByVisit: candidatePeopleByVisit,
            peopleByReceipt: candidatePeopleByReceipt
        ) {
            // Ambient query — cluster resolved a dominant theme.
            context = clusteredContext
        } else {
            // Specific query (or cluster returned nothing) — use scored candidates directly.
            // Every retrieval path has run; this gives the LLM the full relevant context.
            context.emails = Array(semanticallyBoostedEmails.prefix(emailCap))
            context.notes = Array(semanticallyBoostedNotes.prefix(noteCap))
            context.visits = Array(candidateVisits.prefix(visitCap))
            context.receipts = Array(semanticallyBoostedReceipts.prefix(receiptCap))
            context.people = Array(semanticallyBoostedPeople.prefix(peopleCap))
            context.peopleByVisit = candidatePeopleByVisit
            context.peopleByReceipt = candidatePeopleByReceipt
            // Enrich places: matched places + places from the retrieved visits themselves
            let visitPlaces = context.visits.compactMap { visit in
                locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
            }
            context.places = Array(mergeUniquePlaces(
                mergeUniquePlaces(context.places, candidatePlaces),
                visitPlaces
            ).prefix(placeCap))
        }

        // Fetch day summaries when query is temporal/reflective
        if frame.requestedDomains.contains(.daySummaries) || isDaySummaryQuery(frame) {
            context.daySummaries = await retrieveDaySummaries(for: frame)
        }

        // Fetch trackers when query involves tracker domain
        if frame.requestedDomains.contains(.trackers) {
            context.trackers = retrieveTrackers(for: frame)
        }

        finalize(&context, frame: frame)

        // Fetch full email bodies for the top relevant emails so the LLM gets
        // complete content (not just the 150-char snippet from Gmail metadata).
        if !context.emails.isEmpty {
            context.emailBodies = await fetchEmailBodies(for: context.emails)
        }

        return context
    }

    /// Fetches full email body text for the top 3 relevant emails via Gmail API.
    private func fetchEmailBodies(for emails: [Email]) async -> [String: String] {
        var bodies: [String: String] = [:]
        for email in emails.prefix(3) {
            let messageId = email.gmailMessageId ?? email.id
            if let body = (try? await GmailAPIClient.shared.fetchBodyForAI(messageId: messageId)) ?? nil,
               !body.isEmpty {
                bodies[email.id] = body
            } else if !email.snippet.isEmpty {
                bodies[email.id] = email.snippet
            }
        }
        return bodies
    }

    private func isDaySummaryQuery(_ frame: SelineChatQuestionFrame) -> Bool {
        let q = frame.normalizedQuestion.lowercased()
        return q.contains("how was my day") || q.contains("how was my week") ||
               q.contains("what happened today") || q.contains("what did i do today") ||
               q.contains("recap") || q.contains("weekly recap") ||
               q.contains("summary of") || q.contains("summarize my") ||
               q.contains("what is happening") || q.contains("what's happening") ||
               q.contains("what's going on") || q.contains("anything happening") ||
               q.contains("anything planned") || q.contains("anything coming up") ||
               q.contains("what do i have") || q.contains("do i have anything") ||
               q.contains("upcoming") || q.contains("coming up") ||
               q.contains("schedule for") || q.contains("what's on")
    }

    private func retrieveDaySummaries(for frame: SelineChatQuestionFrame) async -> [DaySummaryService.DaySummary] {
        var summaries: [DaySummaryService.DaySummary] = []
        let service = DaySummaryService.shared

        if let scope = frame.timeScope {
            // Fetch summaries for each day in the time scope (capped at 7 days)
            var current = scope.interval.start
            let calendar = Calendar.current
            let maxDays = 7
            var count = 0
            while current <= scope.interval.end && count < maxDays {
                if let summary = await service.summary(for: current) {
                    summaries.append(summary)
                }
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
                count += 1
            }
        } else {
            // Default: today and yesterday
            if let today = await service.summary(for: Date()) {
                summaries.append(today)
            }
            if let yesterday = await service.summary(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) {
                summaries.append(yesterday)
            }
        }

        return summaries.filter(\.hasMeaningfulEvidence)
    }

    private func retrieveTrackers(for frame: SelineChatQuestionFrame) -> [TrackerThread] {
        let allTrackers = TrackerStore.shared.threads
        let q = frame.normalizedQuestion.lowercased()
        let terms = frame.searchTerms.map { $0.lowercased() }

        // If query mentions a specific tracker by name, prioritize those
        let matched = allTrackers.filter { tracker in
            let title = tracker.title.lowercased()
            return terms.contains(where: { title.contains($0) }) ||
                   q.contains(title)
        }

        // Return matched trackers, or all active trackers if no specific match
        if !matched.isEmpty {
            return matched
        }
        return Array(allTrackers.filter { $0.status == .active }.prefix(5))
    }

    private func seedFromExplicitFollowUp(
        context: inout SelineChatRetrievedContext,
        activeContext: SelineChatActiveContext?,
        allEmails: [Email],
        allNotes: [Note],
        allPeople: [Person],
        allPlaces: [SavedPlace],
        allReceipts: [ReceiptStat]
    ) async {
        switch context.frame.followUpTargetType {
        case .place:
            guard let anchor = activeContext?.placeAnchor,
                  let place = placesService.place(for: anchor) else {
                context.openQuestions.append("Tell me which place you're asking about.")
                return
            }
            context.places = [place]
        case .email:
            guard let anchor = activeContext?.emailAnchor,
                  let email = allEmails.first(where: { $0.id == anchor.emailID }) else {
                context.openQuestions.append("Tell me which email you mean.")
                return
            }
            context.emails = [email]
        case .episode:
            guard let anchor = activeContext?.episodeAnchor else {
                context.openQuestions.append("Tell me which trip or visit you mean.")
                return
            }
            // Primary: fetch by stored IDs
            var visits = await fetchVisits(withIDs: anchor.visitIDs)
            // Fallback: if ID lookup returned nothing but we have stored dates,
            // fetch all visits for those days so the early-return path can still fire.
            if visits.isEmpty, !anchor.visitDates.isEmpty {
                let calendar = Calendar.current
                let dayStarts = anchor.visitDates.map { calendar.startOfDay(for: $0) }
                let earliestDay = dayStarts.min() ?? Date()
                let latestDay = dayStarts.max() ?? Date()
                let endOfLatestDay = calendar.date(byAdding: .day, value: 1, to: latestDay) ?? latestDay
                let interval = DateInterval(start: earliestDay, end: endOfLatestDay)
                visits = await fetchVisits(in: interval, limit: visitCap * 2)
            }
            context.visits = visits
            context.people = allPeople.filter { anchor.personIDs.contains($0.id) }
            context.places = allPlaces.filter { anchor.placeIDs.contains($0.id) }
            context.peopleByVisit = await peopleManager.getPeopleForVisits(visitIds: visits.map(\.id))
        case .person:
            guard let anchor = activeContext?.personAnchor,
                  let person = allPeople.first(where: { $0.id == anchor.personID }) else {
                context.openQuestions.append("Tell me which person you mean.")
                return
            }
            context.people = [person]
        case .receiptCluster:
            guard let anchor = activeContext?.receiptClusterAnchor else {
                context.openQuestions.append("Tell me which receipt or purchase you mean.")
                return
            }
            context.receipts = allReceipts.filter { anchor.noteIDs.contains($0.id) }
        case .none:
            break
        }

        if !context.receipts.isEmpty {
            for receipt in context.receipts {
                context.peopleByReceipt[receipt.id] = await peopleManager.getPeopleForReceipt(
                    receiptId: receipt.id,
                    legacyNoteId: receipt.legacyNoteId
                )
            }
        }
    }

    private func finalize(
        _ context: inout SelineChatRetrievedContext,
        frame: SelineChatQuestionFrame
    ) {
        if frame.requestedDomains == [.emails] {
            context.notes = []
            context.visits = []
            context.receipts = []
            context.places = []
            context.people = []
            context.peopleByVisit = [:]
            context.peopleByReceipt = [:]
            context.daySummaries = []
            context.trackers = []
        } else if frame.requestedDomains == [.receipts] {
            context.emails = []
            context.visits = []
            context.notes = []
            context.peopleByVisit = [:]
            context.daySummaries = []
            context.trackers = []
        } else if frame.requestedDomains == [.notes] {
            context.emails = []
            context.visits = []
            context.receipts = []
            context.peopleByVisit = [:]
            context.peopleByReceipt = [:]
            context.daySummaries = []
            context.trackers = []
        } else if frame.requestedDomains == [.trackers] {
            context.emails = []
            context.notes = []
            context.visits = []
            context.receipts = []
            context.places = []
            context.people = []
            context.peopleByVisit = [:]
            context.peopleByReceipt = [:]
            context.daySummaries = []
        } else if frame.requestedDomains == [.daySummaries] {
            context.emails = []
            context.notes = []
            context.visits = []
            context.receipts = []
            context.places = []
            context.people = []
            context.peopleByVisit = [:]
            context.peopleByReceipt = [:]
            context.trackers = []
        }

        context.emails = Array(context.emails.prefix(emailCap))
        context.notes = Array(context.notes.prefix(noteCap))
        context.visits = Array(context.visits.prefix(visitCap))
        context.receipts = Array(context.receipts.prefix(receiptCap))
        context.places = Array(context.places.prefix(placeCap))
        context.people = Array(context.people.prefix(peopleCap))

        let visitIDs = Set(context.visits.map(\.id))
        let receiptIDs = Set(context.receipts.map(\.id))
        context.peopleByVisit = context.peopleByVisit.filter { visitIDs.contains($0.key) }
        context.peopleByReceipt = context.peopleByReceipt.filter { receiptIDs.contains($0.key) }

        let retainedItemIDs = retainedEvidenceItemIDs(from: context)
        context.graphRelations = context.graphRelations.filter {
            retainedItemIDs.contains($0.fromItemID) && retainedItemIDs.contains($0.toItemID)
        }
    }

    private func candidatePlaces(for frame: SelineChatQuestionFrame) -> [(place: SavedPlace, score: Double)] {
        guard !frame.searchTerms.isEmpty || frame.isExplicitFollowUp || frame.timeScope != nil else { return [] }
        return placesService.rankedMatches(
            query: frame.normalizedQuestion,
            searchTerms: frame.searchTerms,
            limit: max(placeCap * candidateMultiplier, 8)
        )
    }

    private func buildClusteredContext(
        frame: SelineChatQuestionFrame,
        baseContext: SelineChatRetrievedContext,
        allPeople: [Person],
        allPlaces: [SavedPlace],
        emails: [Email],
        notes: [Note],
        visits: [LocationVisitRecord],
        receipts: [ReceiptStat],
        places: [SavedPlace],
        people: [Person],
        peopleByVisit: [UUID: [Person]],
        peopleByReceipt: [UUID: [Person]]
    ) -> SelineChatRetrievedContext? {
        let nodeResult = buildMemoryNodes(
            frame: frame,
            allPeople: allPeople,
            allPlaces: allPlaces,
            emails: emails,
            notes: notes,
            visits: visits,
            receipts: receipts,
            places: places,
            people: people,
            peopleByVisit: peopleByVisit,
            peopleByReceipt: peopleByReceipt
        )

        guard let cluster = memoryResolver.resolve(
            frame: frame,
            nodes: nodeResult.nodes,
            edges: nodeResult.edges
        ) else {
            return nil
        }

        let emailByID = Dictionary(uniqueKeysWithValues: emails.map { ("email-\($0.id)", $0) })
        let noteByID = Dictionary(uniqueKeysWithValues: notes.map { ("note-\($0.id.uuidString)", $0) })
        let visitByID = Dictionary(uniqueKeysWithValues: visits.map { ("visit-\($0.id.uuidString)", $0) })
        let receiptByID = Dictionary(uniqueKeysWithValues: receipts.map { ("receipt-\($0.id.uuidString)", $0) })
        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ("place-\($0.id.uuidString)", $0) })
        let personByID = Dictionary(uniqueKeysWithValues: people.map { ("person-\($0.id.uuidString)", $0) })

        var context = baseContext
        context.emails = []
        context.notes = []
        context.visits = []
        context.receipts = []
        context.places = []
        context.people = []
        context.peopleByVisit = [:]
        context.peopleByReceipt = [:]
        context.openQuestions = []
        context.graphRelations = cluster.edges.map {
            SelineChatEvidenceRelation(
                fromItemID: $0.fromID,
                toItemID: $0.toID,
                label: $0.label
            )
        }

        for nodeID in cluster.nodeIDs {
            if let email = emailByID[nodeID] {
                context.emails = mergeUniqueEmails(context.emails, [email])
                continue
            }
            if let note = noteByID[nodeID] {
                context.notes = mergeUniqueNotes(context.notes, [note])
                continue
            }
            if let visit = visitByID[nodeID] {
                context.visits = mergeUniqueVisits(context.visits, [visit])
                context.peopleByVisit[visit.id] = peopleByVisit[visit.id] ?? []
                continue
            }
            if let receipt = receiptByID[nodeID] {
                context.receipts = mergeUniqueReceipts(context.receipts, [receipt])
                context.peopleByReceipt[receipt.id] = peopleByReceipt[receipt.id] ?? []
                continue
            }
            if let place = placeByID[nodeID] {
                context.places = mergeUniquePlaces(context.places, [place])
                continue
            }
            if let person = personByID[nodeID] {
                context.people = mergeUniquePeople(context.people, [person])
            }
        }

        return context
    }

    private func buildMemoryNodes(
        frame: SelineChatQuestionFrame,
        allPeople: [Person],
        allPlaces: [SavedPlace],
        emails: [Email],
        notes: [Note],
        visits: [LocationVisitRecord],
        receipts: [ReceiptStat],
        places: [SavedPlace],
        people: [Person],
        peopleByVisit: [UUID: [Person]],
        peopleByReceipt: [UUID: [Person]]
    ) -> (nodes: [SelineChatMemoryNode], edges: [SelineChatMemoryEdge]) {
        let personAliases = buildPersonAliases(from: allPeople)
        let placeAliases = buildPlaceAliases(from: allPlaces)
        let placesByID = Dictionary(uniqueKeysWithValues: allPlaces.map { ($0.id, $0) })
        let notesByID = Dictionary(uniqueKeysWithValues: notesManager.notes.map { ($0.id, $0) })

        var nodes: [SelineChatMemoryNode] = []

        for email in emails {
            let searchable = normalize([
                email.subject,
                email.snippet,
                email.body ?? "",
                email.sender.displayName,
                email.sender.email,
                email.recipients.map(\.displayName).joined(separator: " "),
                email.recipients.map(\.email).joined(separator: " ")
            ].joined(separator: " "))
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(SelineChatMemoryRef(kind: .dayKey, value: dayKey(for: email.timestamp), weight: 0.8))
            refs.append(SelineChatMemoryRef(kind: .emailAddress, value: normalize(email.sender.email), weight: 1.8))
            for recipient in email.recipients {
                refs.append(SelineChatMemoryRef(kind: .emailAddress, value: normalize(recipient.email), weight: 1.5))
            }
            if let threadID = email.threadId ?? email.gmailThreadId {
                refs.append(SelineChatMemoryRef(kind: .threadID, value: threadID, weight: 1.0))
            }
            refs.append(contentsOf: entityRefs(in: searchable, personAliases: personAliases, placeAliases: placeAliases))

            nodes.append(
                SelineChatMemoryNode(
                    id: "email-\(email.id)",
                    kind: .email,
                    searchableText: searchable,
                    dateInterval: DateInterval(start: email.timestamp, duration: 60),
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .email,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: email.timestamp
                    )
                )
            )
        }

        for note in notes {
            let noteDate = note.journalDate ?? note.dateModified
            let searchable = noteSearchText(note)
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(SelineChatMemoryRef(kind: .noteID, value: note.id.uuidString.lowercased(), weight: 1.8))
            refs.append(SelineChatMemoryRef(kind: .dayKey, value: dayKey(for: noteDate), weight: 0.8))
            refs.append(contentsOf: entityRefs(in: searchable, personAliases: personAliases, placeAliases: placeAliases))

            nodes.append(
                SelineChatMemoryNode(
                    id: "note-\(note.id.uuidString)",
                    kind: .note,
                    searchableText: searchable,
                    dateInterval: DateInterval(start: noteDate, duration: 60),
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .note,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: noteDate
                    )
                )
            )
        }

        for visit in visits {
            let place = placesByID[visit.savedPlaceId]
            let linkedPeople = peopleByVisit[visit.id] ?? []
            let searchable = normalize([
                place?.displayName ?? "",
                place?.address ?? "",
                visit.visitNotes ?? "",
                linkedPeople.map(\.displayName).joined(separator: " ")
            ].joined(separator: " "))
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(SelineChatMemoryRef(kind: .placeID, value: visit.savedPlaceId.uuidString.lowercased(), weight: 2.2))
            refs.append(SelineChatMemoryRef(kind: .dayKey, value: dayKey(for: visit.entryTime), weight: 0.9))
            if let place {
                refs.append(contentsOf: placeRefs(for: place))
            }
            for person in linkedPeople {
                refs.append(contentsOf: personRefs(for: person, includeFavorites: false))
            }
            refs.append(contentsOf: entityRefs(in: searchable, personAliases: personAliases, placeAliases: placeAliases))

            let visitEnd = visit.exitTime ?? visit.entryTime.addingTimeInterval(3_600)
            nodes.append(
                SelineChatMemoryNode(
                    id: "visit-\(visit.id.uuidString)",
                    kind: .visit,
                    searchableText: searchable,
                    dateInterval: DateInterval(start: visit.entryTime, end: visitEnd),
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .visit,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: visit.entryTime
                    )
                )
            )
        }

        for receipt in receipts {
            let linkedPeople = peopleByReceipt[receipt.id] ?? []
            let noteContext = receipt.legacyNoteId.flatMap { notesByID[$0] }.map { noteSearchText($0) } ?? ""
            let searchable = normalize([
                receipt.title,
                receipt.category,
                receipt.searchableText,
                noteContext,
                linkedPeople.map(\.displayName).joined(separator: " ")
            ].joined(separator: " "))
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(SelineChatMemoryRef(kind: .noteID, value: receipt.id.uuidString.lowercased(), weight: 2.0))
            refs.append(SelineChatMemoryRef(kind: .merchant, value: normalize(receipt.merchant), weight: 1.6))
            refs.append(SelineChatMemoryRef(kind: .category, value: normalize(receipt.category), weight: 0.6))
            refs.append(SelineChatMemoryRef(kind: .dayKey, value: dayKey(for: receipt.date), weight: 0.8))
            refs.append(contentsOf: entityRefs(in: searchable, personAliases: personAliases, placeAliases: placeAliases))
            for person in linkedPeople {
                refs.append(contentsOf: personRefs(for: person, includeFavorites: false))
            }

            nodes.append(
                SelineChatMemoryNode(
                    id: "receipt-\(receipt.id.uuidString)",
                    kind: .receipt,
                    searchableText: searchable,
                    dateInterval: DateInterval(start: receipt.date, duration: 60),
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .receipt,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: receipt.date
                    )
                )
            )
        }

        for place in places {
            let searchable = normalize([
                place.displayName,
                place.name,
                place.address,
                place.category,
                place.userNotes ?? "",
                place.userCuisine ?? "",
                place.city ?? "",
                place.province ?? "",
                place.country ?? ""
            ].joined(separator: " "))
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(contentsOf: placeRefs(for: place))
            refs.append(SelineChatMemoryRef(kind: .merchant, value: normalize(place.displayName), weight: 1.3))

            nodes.append(
                SelineChatMemoryNode(
                    id: "place-\(place.id.uuidString)",
                    kind: .place,
                    searchableText: searchable,
                    dateInterval: nil,
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .place,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: nil
                    )
                )
            )
        }

        for person in people {
            let searchable = normalize([
                person.name,
                person.nickname ?? "",
                person.relationshipDisplayText,
                person.notes ?? "",
                person.howWeMet ?? "",
                person.email ?? ""
            ].joined(separator: " "))
            let matchedTerms = matchedQueryTerms(in: searchable, frame: frame)
            var refs = queryTermRefs(for: matchedTerms)
            refs.append(contentsOf: personRefs(for: person, includeFavorites: true))

            nodes.append(
                SelineChatMemoryNode(
                    id: "person-\(person.id.uuidString)",
                    kind: .person,
                    searchableText: searchable,
                    dateInterval: DateInterval(start: person.dateModified, duration: 60),
                    refs: dedupeRefs(refs),
                    matchedTerms: matchedTerms,
                    seedScore: scoreNodeSeed(
                        kind: .person,
                        searchable: searchable,
                        matchedTerms: matchedTerms,
                        frame: frame,
                        date: person.dateModified
                    )
                )
            )
        }

        return (nodes, buildMemoryEdges(from: nodes))
    }

    private func retrieveRelevantVisits(
        frame: SelineChatQuestionFrame,
        matchedPlaces: [SavedPlace],
        matchedPeople: [Person],
        limit: Int
    ) async -> [LocationVisitRecord] {
        var candidates: [LocationVisitRecord] = []

        if let timeScope = frame.timeScope {
            candidates.append(contentsOf: await fetchVisits(in: timeScope.interval, limit: limit))
        }

        if !matchedPlaces.isEmpty {
            candidates.append(contentsOf: await fetchVisits(forPlaceIDs: matchedPlaces.map(\.id), interval: frame.timeScope?.interval, limit: limit))
        }

        if !matchedPeople.isEmpty {
            for person in matchedPeople.prefix(3) {
                let visitIDs = await peopleManager.getVisitIdsForPerson(personId: person.id)
                let visits = await fetchVisits(withIDs: Array(visitIDs.prefix(limit)))
                candidates.append(contentsOf: visits)
            }
        }

        // Always search visit_notes when search terms exist — runs alongside place and
        // people fetches to catch any textual connection: a person mentioned in notes,
        // an area name (e.g. "niagara"), an event description, anything.
        if !frame.searchTerms.isEmpty {
            candidates.append(contentsOf: await fetchVisitsByNotes(searchTerms: frame.searchTerms, limit: limit))
        }

        if candidates.isEmpty, frame.timeScope != nil {
            candidates.append(contentsOf: await fetchVisits(in: frame.timeScope!.interval, limit: limit))
        }

        if candidates.isEmpty {
            candidates.append(contentsOf: await fetchRecentVisits(limit: limit))
        }

        let uniqueVisits = dedupeVisits(candidates)
        guard !uniqueVisits.isEmpty else { return [] }

        let peopleByVisit = await peopleManager.getPeopleForVisits(visitIds: uniqueVisits.map(\.id))

        let scored = uniqueVisits.map { visit -> (LocationVisitRecord, Double) in
            var score = 0.0

            if matchedPlaces.contains(where: { $0.id == visit.savedPlaceId }) {
                score += 4
            }
            if let linkedPeople = peopleByVisit[visit.id], !linkedPeople.isEmpty,
               matchedPeople.contains(where: { person in linkedPeople.contains(where: { $0.id == person.id }) }) {
                score += 3
            }
            if let visitNotes = visit.visitNotes, scoreText(visitNotes, searchTerms: frame.searchTerms) > 0 {
                score += 2
            }
            if frame.timeScope?.interval.contains(visit.entryTime) == true {
                score += 1.5
            }

                if score == 0 {
                    if matchedPlaces.isEmpty && matchedPeople.isEmpty && frame.timeScope != nil {
                        score = 1
                    } else if scoreText(normalize(placeName(for: visit)), searchTerms: frame.searchTerms) > 0 {
                        score = 1
                    }
                }

            return (visit, score)
        }

        return Array(
            scored
                .filter { $0.1 > 0 }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0.entryTime > rhs.0.entryTime
                    }
                    return lhs.1 > rhs.1
                }
                .prefix(limit)
                .map(\.0)
        )
    }

    private func expandPlacesAndPeople(into context: inout SelineChatRetrievedContext) {
        let placesFromVisits = context.visits.compactMap { visit in
            locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        }
        context.places = mergeUniquePlaces(context.places, placesFromVisits)

        let visitLinkedPeople = context.visits.flatMap { context.peopleByVisit[$0.id] ?? [] }
        context.people = mergeUniquePeople(context.people, visitLinkedPeople)

        for receipt in context.receipts where context.peopleByReceipt[receipt.id] == nil {
            context.peopleByReceipt[receipt.id] = []
        }

        let receiptLinkedPeople = context.receipts.flatMap { context.peopleByReceipt[$0.id] ?? [] }
        context.people = mergeUniquePeople(context.people, receiptLinkedPeople)

        for person in context.people {
            let favoritePlaces = (person.favouritePlaceIds ?? []).compactMap { placeID in
                locationsManager.savedPlaces.first(where: { $0.id == placeID })
            }
            context.places = mergeUniquePlaces(context.places, favoritePlaces)
        }
    }

    private func expandNotes(into context: inout SelineChatRetrievedContext, allNotes: [Note]) {
        guard context.notes.count < noteCap else { return }

        let matchedPeople = context.people
        let matchedPlaces = context.places
        let matchedNotes = allNotes.filter { note in
            let searchable = noteSearchText(note)
            let matchesPeople = matchedPeople.contains { searchable.contains(normalizedPersonText($0)) }
            let matchesPlaces = matchedPlaces.contains { searchable.contains(normalizedPlaceText($0)) }
            return matchesPeople || matchesPlaces
        }

        context.notes = mergeUniqueNotes(context.notes, matchedNotes.prefix(noteCap))
    }

    private func expandReceipts(into context: inout SelineChatRetrievedContext, allReceipts: [ReceiptStat]) {
        guard context.receipts.count < receiptCap else { return }

        let matchedPlaceNames = Set(context.places.map { normalize($0.displayName) })
        let matchedPeople = context.people

        let relatedReceipts = allReceipts.filter { receipt in
            let merchantText = normalize(receipt.title)
            let noteLinkedPeople = context.peopleByReceipt[receipt.id] ?? []
            if matchedPlaceNames.contains(where: { merchantText.contains($0) || $0.contains(merchantText) }) {
                return true
            }
            if !matchedPeople.isEmpty,
               noteLinkedPeople.contains(where: { related in matchedPeople.contains(where: { $0.id == related.id }) }) {
                return true
            }
            return false
        }

        context.receipts = mergeUniqueReceipts(context.receipts, relatedReceipts.prefix(receiptCap))
    }

    // MARK: - Semantic Search Boost

    /// Fetches semantic similarity scores from VectorSearchService for the query.
    /// Returns a dict of "docType::docId" → similarity score.
    private func fetchSemanticScores(for frame: SelineChatQuestionFrame) async -> [String: Float] {
        guard !frame.searchTerms.isEmpty || !frame.entityMentions.isEmpty else { return [:] }

        let docTypes = semanticDocumentTypes(for: frame.requestedDomains)
        guard !docTypes.isEmpty else { return [:] }

        let dateRange: (start: Date, end: Date)? = frame.timeScope.map {
            (start: $0.interval.start, end: $0.interval.end)
        }

        do {
            let results = try await VectorSearchService.shared.search(
                query: frame.normalizedQuestion,
                documentTypes: docTypes,
                limit: 20,
                dateRange: dateRange
            )
            var scores: [String: Float] = [:]
            for result in results {
                let key = "\(result.documentType.rawValue)::\(result.documentId)"
                scores[key] = result.similarity
            }
            return scores
        } catch {
            return [:]
        }
    }

    private func semanticDocumentTypes(for domains: Set<SelineChatDomain>) -> [VectorSearchService.DocumentType] {
        var types: [VectorSearchService.DocumentType] = []
        if domains.contains(.emails) { types.append(.email) }
        if domains.contains(.notes) { types.append(.note) }
        if domains.contains(.receipts) { types.append(.receipt) }
        if domains.contains(.people) { types.append(.person) }
        if domains.contains(.visits) { types.append(.visit) }
        if domains.contains(.trackers) { types.append(.tracker) }
        return types
    }

    /// Re-ranks a list by promoting items that appear in semantic results to the top.
    private func applySemanticBoost<T>(
        to items: [T],
        docType: String,
        idKeyPath: (T) -> String,
        semanticScores: [String: Float]
    ) -> [T] {
        guard !semanticScores.isEmpty else { return items }

        return items.sorted { a, b in
            let keyA = "\(docType)::\(idKeyPath(a))"
            let keyB = "\(docType)::\(idKeyPath(b))"
            let scoreA = semanticScores[keyA] ?? 0
            let scoreB = semanticScores[keyB] ?? 0
            return scoreA > scoreB
        }
    }

    private func allEmailsSnapshot() -> [Email] {
        (emailService.inboxEmails + emailService.sentEmails)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func allReceiptsSnapshot() async -> [ReceiptStat] {
        await receiptManager.ensureLoaded()
        await notesManager.ensureReceiptDataAvailable()
        return receiptManager.receipts.sorted { $0.date > $1.date }
    }

    private func rankEmails(
        _ emails: [Email],
        using searchTerms: [String],
        entityMentions: [SelineChatEntityMention],
        timeScope: SelineChatTimeScope?
    ) -> [Email] {
        rank(emails) { email in
            let searchable = normalize([
                email.subject,
                email.snippet,
                email.body ?? "",
                email.sender.displayName,
                email.sender.email
            ].joined(separator: " "))

            var score = scoreText(searchable, searchTerms: searchTerms)
            score += phraseScore(searchable, entityMentions: entityMentions)
            if timeScope?.interval.contains(email.timestamp) == true {
                score += 2
            }
            if searchTerms.isEmpty && timeScope?.interval.contains(email.timestamp) == true {
                score += 1
            }
            return score
        }
    }

    private func rankNotes(
        _ notes: [Note],
        using searchTerms: [String],
        entityMentions: [SelineChatEntityMention],
        timeScope: SelineChatTimeScope?
    ) -> [Note] {
        rank(notes) { note in
            let searchable = noteSearchText(note)
            let noteDate = note.journalDate ?? note.dateModified

            var score = scoreText(searchable, searchTerms: searchTerms)
            score += phraseScore(searchable, entityMentions: entityMentions)
            if timeScope?.interval.contains(noteDate) == true {
                score += 2
            }
            return score
        }
    }

    private func rankPeople(
        _ people: [Person],
        using searchTerms: [String],
        entityMentions: [SelineChatEntityMention],
        timeScope: SelineChatTimeScope?
    ) -> [Person] {
        rank(people) { person in
            let searchable = normalize([
                person.name,
                person.nickname ?? "",
                person.relationshipDisplayText,
                person.notes ?? "",
                person.howWeMet ?? ""
            ].joined(separator: " "))

            var score = scoreText(searchable, searchTerms: searchTerms)
            score += phraseScore(searchable, entityMentions: entityMentions) * 1.5
            if timeScope != nil && score > 0 {
                score += 0.5
            }
            return score
        }
    }

    private func rankReceipts(
        _ receipts: [ReceiptStat],
        using searchTerms: [String],
        entityMentions: [SelineChatEntityMention],
        timeScope: SelineChatTimeScope?
    ) -> [ReceiptStat] {
        rank(receipts) { receipt in
            let searchable = normalize(receipt.searchableText)
            var score = scoreText(searchable, searchTerms: searchTerms)
            score += phraseScore(searchable, entityMentions: entityMentions)
            if timeScope?.interval.contains(receipt.date) == true {
                score += 2
            }
            if searchTerms.isEmpty && timeScope?.interval.contains(receipt.date) == true {
                score += 1
            }
            return score
        }
    }

    private func rank<T>(
        _ values: [T],
        score: (T) -> Double
    ) -> [T] {
        values
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }
            .map(\.0)
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

    private func fetchVisits(forPlaceIDs placeIDs: [UUID], interval: DateInterval?, limit: Int) async -> [LocationVisitRecord] {
        guard let userID = SupabaseManager.shared.getCurrentUser()?.id,
              !placeIDs.isEmpty else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            let response = if let interval {
                try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userID.uuidString)
                    .in("saved_place_id", values: placeIDs.map(\.uuidString))
                    .gte("entry_time", value: interval.start.ISO8601Format())
                    .lt("entry_time", value: interval.end.ISO8601Format())
                    .order("entry_time", ascending: false)
                    .execute()
            } else {
                try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userID.uuidString)
                    .in("saved_place_id", values: placeIDs.map(\.uuidString))
                    .order("entry_time", ascending: false)
                    .execute()
            }

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

    /// Fetches visits whose visit_notes contain any of the given search terms (case-insensitive).
    /// Used when a place isn't in saved places but the user references it by name in the query.
    private func fetchVisitsByNotes(searchTerms: [String], limit: Int) async -> [LocationVisitRecord] {
        guard let userID = SupabaseManager.shared.getCurrentUser()?.id,
              !searchTerms.isEmpty else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            var allVisits: [LocationVisitRecord] = []

            for term in searchTerms.prefix(3) where term.count >= 3 {
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userID.uuidString)
                    .ilike("visit_notes", pattern: "%\(term)%")
                    .order("entry_time", ascending: false)
                    .execute()

                let visits = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
                allVisits.append(contentsOf: visits.prefix(limit))
            }

            return dedupeVisits(allVisits)
        } catch {
            return []
        }
    }

    private func retainedEvidenceItemIDs(from context: SelineChatRetrievedContext) -> Set<String> {
        var ids = Set(context.emails.map { "email-\($0.id)" })
        ids.formUnion(context.notes.map { "note-\($0.id.uuidString)" })
        ids.formUnion(context.visits.map { "visit-\($0.id.uuidString)" })
        ids.formUnion(context.receipts.map { "receipt-\($0.id.uuidString)" })
        ids.formUnion(context.places.map { "place-\($0.id.uuidString)" })
        ids.formUnion(context.people.map { "person-\($0.id.uuidString)" })
        return ids
    }

    private func buildPersonAliases(from people: [Person]) -> [(alias: String, person: Person)] {
        people.flatMap { person -> [(String, Person)] in
            [person.name, person.nickname]
                .compactMap { $0 }
                .map(normalize)
                .filter { $0.count >= 3 }
                .map { ($0, person) }
        }
    }

    private func buildPlaceAliases(from places: [SavedPlace]) -> [(alias: String, place: SavedPlace)] {
        places.flatMap { place -> [(String, SavedPlace)] in
            [place.displayName, place.name, place.customName, place.userCuisine]
                .compactMap { $0 }
                .map(normalize)
                .filter { $0.count >= 3 }
                .map { ($0, place) }
        }
    }

    private func matchedQueryTerms(in searchable: String, frame: SelineChatQuestionFrame) -> [String] {
        var matched: [String] = []
        for term in frame.searchTerms where searchable.contains(term) {
            matched.append(term)
        }
        for mention in frame.entityMentions.map(\.normalizedValue) where searchable.contains(mention) {
            matched.append(mention)
        }

        var seen = Set<String>()
        return matched.filter { seen.insert($0).inserted }
    }

    private func queryTermRefs(for matchedTerms: [String]) -> [SelineChatMemoryRef] {
        matchedTerms.map { term in
            let weight = term.contains(" ") ? 1.6 : 1.0
            return SelineChatMemoryRef(kind: .queryTerm, value: term, weight: weight)
        }
    }

    private func entityRefs(
        in searchable: String,
        personAliases: [(alias: String, person: Person)],
        placeAliases: [(alias: String, place: SavedPlace)]
    ) -> [SelineChatMemoryRef] {
        var refs: [SelineChatMemoryRef] = []

        for entry in personAliases where searchable.contains(entry.alias) {
            refs.append(SelineChatMemoryRef(kind: .personID, value: entry.person.id.uuidString.lowercased(), weight: 2.0))
            refs.append(SelineChatMemoryRef(kind: .personName, value: entry.alias, weight: 1.2))
        }

        for entry in placeAliases where searchable.contains(entry.alias) {
            refs.append(SelineChatMemoryRef(kind: .placeID, value: entry.place.id.uuidString.lowercased(), weight: 2.0))
            refs.append(SelineChatMemoryRef(kind: .placeName, value: entry.alias, weight: 1.2))
        }

        return refs
    }

    private func placeRefs(for place: SavedPlace) -> [SelineChatMemoryRef] {
        var refs: [SelineChatMemoryRef] = [
            SelineChatMemoryRef(kind: .placeID, value: place.id.uuidString.lowercased(), weight: 2.3),
            SelineChatMemoryRef(kind: .placeName, value: normalize(place.displayName), weight: 1.8),
            SelineChatMemoryRef(kind: .placeAlias, value: normalize(place.name), weight: 1.1)
        ]

        if let customName = place.customName {
            refs.append(SelineChatMemoryRef(kind: .placeAlias, value: normalize(customName), weight: 1.2))
        }
        if let city = place.city {
            refs.append(SelineChatMemoryRef(kind: .placeAlias, value: normalize(city), weight: 0.5))
        }

        return refs
    }

    private func personRefs(for person: Person, includeFavorites: Bool) -> [SelineChatMemoryRef] {
        var refs: [SelineChatMemoryRef] = [
            SelineChatMemoryRef(kind: .personID, value: person.id.uuidString.lowercased(), weight: 2.3),
            SelineChatMemoryRef(kind: .personName, value: normalize(person.name), weight: 1.6)
        ]

        if let nickname = person.nickname {
            refs.append(SelineChatMemoryRef(kind: .personName, value: normalize(nickname), weight: 1.5))
        }
        if let email = person.email, !email.isEmpty {
            refs.append(SelineChatMemoryRef(kind: .emailAddress, value: normalize(email), weight: 1.9))
        }
        if includeFavorites {
            for placeID in person.favouritePlaceIds ?? [] {
                refs.append(SelineChatMemoryRef(kind: .placeID, value: placeID.uuidString.lowercased(), weight: 1.1))
            }
        }

        return refs
    }

    private func dedupeRefs(_ refs: [SelineChatMemoryRef]) -> [SelineChatMemoryRef] {
        var bestByKey: [String: SelineChatMemoryRef] = [:]

        for ref in refs where !ref.value.isEmpty {
            let key = "\(ref.kind.rawValue)|\(ref.value)"
            if let existing = bestByKey[key] {
                if ref.weight > existing.weight {
                    bestByKey[key] = ref
                }
            } else {
                bestByKey[key] = ref
            }
        }

        return Array(bestByKey.values)
    }

    private func scoreNodeSeed(
        kind: SelineChatMemoryNodeKind,
        searchable: String,
        matchedTerms: [String],
        frame: SelineChatQuestionFrame,
        date: Date?
    ) -> Double {
        var score = 0.0
        score += Double(matchedTerms.count) * 1.4
        score += phraseScore(searchable, entityMentions: frame.entityMentions) * 0.6

        if let date, frame.timeScope?.interval.contains(date) == true {
            score += 1.8
        }

        if frame.requestedDomains.contains(domain(for: kind)) {
            // Give visits a stronger boost when the query is explicitly about visits,
            // so the cluster resolver doesn't drop them in favour of email/people clusters.
            score += (kind == .visit && frame.requestedDomains.contains(.visits)) ? 1.4 : 0.7
        }

        if frame.isExplicitFollowUp {
            score += 0.4
        }

        if frame.wantsSpecificObject, kind == .place {
            score += 0.4
        }

        return score
    }

    private func domain(for kind: SelineChatMemoryNodeKind) -> SelineChatDomain {
        switch kind {
        case .email:
            return .emails
        case .note:
            return .notes
        case .visit:
            return .visits
        case .receipt:
            return .receipts
        case .place:
            return .places
        case .person:
            return .people
        }
    }

    private func buildMemoryEdges(from nodes: [SelineChatMemoryNode]) -> [SelineChatMemoryEdge] {
        var refBuckets: [String: (kind: SelineChatMemoryRefKind, refs: [(nodeID: String, weight: Double)])] = [:]

        for node in nodes {
            for ref in node.refs {
                let key = "\(ref.kind.rawValue)|\(ref.value)"
                var bucket = refBuckets[key] ?? (ref.kind, [])
                bucket.refs.append((node.id, ref.weight))
                refBuckets[key] = bucket
            }
        }

        var edges: [SelineChatMemoryEdge] = []

        for (_, bucket) in refBuckets {
            let refs = bucket.refs
            if refs.count < 2 { continue }
            if bucket.kind == .category && refs.count > 6 { continue }
            if bucket.kind == .dayKey && refs.count > 10 { continue }

            for lhsIndex in 0..<(refs.count - 1) {
                for rhsIndex in (lhsIndex + 1)..<refs.count {
                    let lhs = refs[lhsIndex]
                    let rhs = refs[rhsIndex]
                    guard lhs.nodeID != rhs.nodeID else { continue }
                    edges.append(
                        SelineChatMemoryEdge(
                            fromID: lhs.nodeID,
                            toID: rhs.nodeID,
                            label: relationLabel(for: bucket.kind),
                            weight: min(lhs.weight, rhs.weight)
                        )
                    )
                }
            }
        }

        for lhsIndex in 0..<nodes.count {
            for rhsIndex in (lhsIndex + 1)..<nodes.count {
                let lhs = nodes[lhsIndex]
                let rhs = nodes[rhsIndex]
                guard lhs.kind != rhs.kind,
                      let lhsDate = lhs.dateInterval?.start,
                      let rhsDate = rhs.dateInterval?.start else {
                    continue
                }

                let distance = abs(lhsDate.timeIntervalSince(rhsDate))
                if distance <= 36 * 60 * 60,
                   !Calendar.current.isDate(lhsDate, inSameDayAs: rhsDate) {
                    edges.append(
                        SelineChatMemoryEdge(
                            fromID: lhs.id,
                            toID: rhs.id,
                            label: "near in time",
                            weight: 0.55
                        )
                    )
                }
            }
        }

        return edges
    }

    private func relationLabel(for kind: SelineChatMemoryRefKind) -> String {
        switch kind {
        case .personID, .personName:
            return "references"
        case .placeID, .placeName, .placeAlias:
            return "relates to place"
        case .emailAddress:
            return "shares contact"
        case .threadID:
            return "same thread"
        case .noteID:
            return "same note"
        case .merchant:
            return "same merchant"
        case .category:
            return "same category"
        case .dayKey:
            return "same day"
        case .queryTerm:
            return "matches query"
        }
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(year)-\(month)-\(day)"
    }

    private func mergeUniqueEmails<S: Sequence>(_ existing: [Email], _ incoming: S) -> [Email] where S.Element == Email {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for email in incoming where seen.insert(email.id).inserted {
            merged.append(email)
        }
        return merged.sorted { $0.timestamp > $1.timestamp }
    }

    private func mergeUniqueVisits<S: Sequence>(_ existing: [LocationVisitRecord], _ incoming: S) -> [LocationVisitRecord] where S.Element == LocationVisitRecord {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for visit in incoming where seen.insert(visit.id).inserted {
            merged.append(visit)
        }
        return merged.sorted { $0.entryTime > $1.entryTime }
    }

    private func mergeUniquePeople<S: Sequence>(_ existing: [Person], _ incoming: S) -> [Person] where S.Element == Person {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for person in incoming where seen.insert(person.id).inserted {
            merged.append(person)
        }
        return merged
    }

    private func mergeUniquePlaces<S: Sequence>(_ existing: [SavedPlace], _ incoming: S) -> [SavedPlace] where S.Element == SavedPlace {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for place in incoming where seen.insert(place.id).inserted {
            merged.append(place)
        }
        return merged
    }

    private func mergeUniqueNotes<S: Sequence>(_ existing: [Note], _ incoming: S) -> [Note] where S.Element == Note {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for note in incoming where seen.insert(note.id).inserted {
            merged.append(note)
        }
        return merged.sorted { lhs, rhs in
            let lhsDate = lhs.journalDate ?? lhs.dateModified
            let rhsDate = rhs.journalDate ?? rhs.dateModified
            return lhsDate > rhsDate
        }
    }

    private func mergeUniqueReceipts<S: Sequence>(_ existing: [ReceiptStat], _ incoming: S) -> [ReceiptStat] where S.Element == ReceiptStat {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for receipt in incoming where seen.insert(receipt.id).inserted {
            merged.append(receipt)
        }
        return merged.sorted { $0.date > $1.date }
    }

    private func dedupeVisits(_ visits: [LocationVisitRecord]) -> [LocationVisitRecord] {
        var seen = Set<UUID>()
        var result: [LocationVisitRecord] = []
        for visit in visits where seen.insert(visit.id).inserted {
            result.append(visit)
        }
        return result
    }

    private func containsWhoSignal(_ question: String) -> Bool {
        question.contains("who") || question.contains("with ")
    }

    private func placeName(for visit: LocationVisitRecord) -> String {
        locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName ?? ""
    }

    private func noteSearchText(_ note: Note) -> String {
        normalize("\(note.title) \(note.displayContent)")
    }

    private func normalizedPersonText(_ person: Person) -> String {
        normalize([person.name, person.nickname ?? ""].joined(separator: " "))
    }

    private func normalizedPlaceText(_ place: SavedPlace) -> String {
        normalize([place.displayName, place.name].joined(separator: " "))
    }

    private func phraseScore(_ searchable: String, entityMentions: [SelineChatEntityMention]) -> Double {
        entityMentions.reduce(0) { partial, mention in
            partial + (searchable.contains(mention.normalizedValue) ? 3 : 0)
        }
    }

    private func scoreText(_ searchable: String, searchTerms: [String]) -> Double {
        guard !searchTerms.isEmpty else { return 0 }
        return searchTerms.reduce(0) { partial, term in
            if searchable == term {
                return partial + 5
            }
            if searchable.contains(term) {
                return partial + (term.contains(" ") ? 2 : 1)
            }
            return partial
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
