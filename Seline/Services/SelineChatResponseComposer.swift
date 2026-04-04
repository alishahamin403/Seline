import Foundation

@MainActor
final class SelineChatEvidenceSynthesizer {
    func synthesize(_ context: SelineChatRetrievedContext) async -> SelineChatEvidencePacket {
        var items: [SelineChatEvidenceItem] = []
        var facts: [SelineChatGroundedFact] = []
        var relations: [SelineChatEvidenceRelation] = []

        let emailItems = context.emails.map { emailItem($0, body: context.emailBodies[$0.id]) }
        let noteItems = context.notes.map(noteItem)
        let visitItems = context.visits.map { visitItem($0, linkedPeople: context.peopleByVisit[$0.id] ?? []) }
        let receiptItems = context.receipts.map { receiptItem($0, linkedPeople: context.peopleByReceipt[$0.id] ?? []) }
        let personItems = context.people.map(personItem)
        let placeResults = SelineChatPlacesService().placeResults(from: context.places)

        // Day summary facts
        for summary in context.daySummaries {
            let dateStr = FormatterCache.shortDate.string(from: summary.summaryDate)
            var summaryParts = ["\(dateStr): \(summary.summaryText)"]
            if !summary.highlights.isEmpty {
                summaryParts.append("Highlights: \(summary.highlights.prefix(3).joined(separator: "; "))")
            }
            if !summary.openLoops.isEmpty {
                summaryParts.append("Open loops: \(summary.openLoops.prefix(2).joined(separator: "; "))")
            }
            if let mood = summary.mood, !mood.isEmpty {
                summaryParts.append("Mood: \(mood)")
            }
            facts.append(SelineChatGroundedFact(text: summaryParts.joined(separator: " • "), sourceItemIDs: []))
        }

        // Tracker facts + evidence items
        let trackerItems = context.trackers.map(trackerItem)
        items.append(contentsOf: trackerItems)
        for (tracker, item) in zip(context.trackers, trackerItems) {
            if let state = tracker.cachedState {
                var trackerParts = ["Tracker '\(tracker.title)': \(state.currentSummary)"]
                if !state.quickFacts.isEmpty {
                    trackerParts.append(state.quickFacts.prefix(3).joined(separator: "; "))
                }
                if !state.warnings.isEmpty {
                    trackerParts.append("Warnings: \(state.warnings.prefix(2).joined(separator: "; "))")
                }
                facts.append(SelineChatGroundedFact(text: trackerParts.joined(separator: " • "), sourceItemIDs: [item.id]))
            } else {
                facts.append(SelineChatGroundedFact(text: "Tracker '\(tracker.title)': No state recorded yet.", sourceItemIDs: [item.id]))
            }
        }

        items.append(contentsOf: emailItems)
        items.append(contentsOf: noteItems)
        items.append(contentsOf: visitItems)
        items.append(contentsOf: receiptItems)
        items.append(contentsOf: personItems)

        if !context.emails.isEmpty {
            let emailFactText = context.frame.timeScope != nil
                ? "I found \(context.emails.count) matching emails for \(context.frame.timeScope?.description.lowercased() ?? "that time")."
                : "I found \(context.emails.count) matching emails."
            facts.append(SelineChatGroundedFact(text: emailFactText, sourceItemIDs: emailItems.map(\.id)))
        }

        if !context.receipts.isEmpty {
            let total = context.receipts.reduce(0) { $0 + $1.amount }
            facts.append(
                SelineChatGroundedFact(
                    text: "Matched receipts total \(CurrencyParser.formatAmount(total)).",
                    sourceItemIDs: receiptItems.map(\.id)
                )
            )

            // Spending category breakdown
            let byCategory = Dictionary(grouping: context.receipts) { $0.category ?? "Uncategorized" }
            if byCategory.count > 1 {
                let breakdown = byCategory
                    .sorted { $0.value.reduce(0) { $0 + $1.amount } > $1.value.reduce(0) { $0 + $1.amount } }
                    .prefix(5)
                    .map { cat, items in
                        let catTotal = items.reduce(0) { $0 + $1.amount }
                        return "\(cat): \(CurrencyParser.formatAmount(catTotal))"
                    }
                    .joined(separator: " • ")
                facts.append(
                    SelineChatGroundedFact(
                        text: "Spending by category — \(breakdown).",
                        sourceItemIDs: receiptItems.map(\.id)
                    )
                )
            }
        }

        for visit in context.visits.prefix(3) {
            let savedPlace = context.places.first(where: { $0.id == visit.savedPlaceId })
                ?? LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
            let placeName = savedPlace?.displayName ?? "a location"
            // Include city so LLM can match area references (e.g. "Niagara" → "Niku Japanese BBQ · Niagara Falls")
            let placeLabel = [placeName, savedPlace?.city].compactMap { $0 }.joined(separator: ", ")
            let when = FormatterCache.shortDate.string(from: visit.entryTime)
            let linkedPeople = context.peopleByVisit[visit.id] ?? []
            var factParts = ["Visit to \(placeLabel) on \(when)"]
            if !linkedPeople.isEmpty {
                factParts.append("with \(linkedPeople.map(\.displayName).joined(separator: ", "))")
            }
            if let notes = visit.visitNotes, !notes.isEmpty {
                factParts.append("notes: \(notes)")
            }
            facts.append(
                SelineChatGroundedFact(
                    text: factParts.joined(separator: " — "),
                    sourceItemIDs: ["visit-\(visit.id.uuidString)"]
                )
            )
        }

        if !context.notes.isEmpty {
            facts.append(
                SelineChatGroundedFact(
                    text: "I found \(context.notes.count) notes or journal entries tied to this question.",
                    sourceItemIDs: noteItems.map(\.id)
                )
            )
        }

        if !context.people.isEmpty {
            let names = context.people.prefix(3).map(\.displayName).joined(separator: ", ")
            facts.append(
                SelineChatGroundedFact(
                    text: "Relevant people include \(names).",
                    sourceItemIDs: personItems.map(\.id)
                )
            )
        }

        if let firstPlace = context.places.first {
            var parts: [String] = [firstPlace.displayName]
            if !firstPlace.category.isEmpty {
                parts.append(firstPlace.category)
            }
            if let rating = firstPlace.rating {
                parts.append(String(format: "%.1f rating", rating))
            }
            if let isOpenNow = firstPlace.isOpenNow {
                parts.append(isOpenNow ? "currently open" : "currently closed")
            }
            if let openingHours = firstPlace.openingHours, !openingHours.isEmpty {
                parts.append(openingHours.prefix(2).joined(separator: " • "))
            }
            if let userNotes = firstPlace.userNotes, !userNotes.isEmpty {
                parts.append(userNotes)
            }
            facts.append(
                SelineChatGroundedFact(
                    text: parts.joined(separator: " • "),
                    sourceItemIDs: []
                )
            )
        }

        for visit in context.visits {
            let visitItemID = "visit-\(visit.id.uuidString)"
            if let place = context.places.first(where: { $0.id == visit.savedPlaceId }) {
                relations.append(
                    SelineChatEvidenceRelation(
                        fromItemID: visitItemID,
                        toItemID: "place-\(place.id.uuidString)",
                        label: "visit at"
                    )
                )
            }

            for person in context.peopleByVisit[visit.id] ?? [] {
                relations.append(
                    SelineChatEvidenceRelation(
                        fromItemID: visitItemID,
                        toItemID: "person-\(person.id.uuidString)",
                        label: "with"
                    )
                )
            }
        }

        for receipt in context.receipts {
            let receiptItemID = "receipt-\(receipt.id.uuidString)"
            for person in context.peopleByReceipt[receipt.id] ?? [] {
                relations.append(
                    SelineChatEvidenceRelation(
                        fromItemID: receiptItemID,
                        toItemID: "person-\(person.id.uuidString)",
                        label: "linked to"
                    )
                )
            }
        }

        relations.append(contentsOf: context.graphRelations)
        relations = dedupeRelations(relations)

        return SelineChatEvidencePacket(
            frame: context.frame,
            facts: facts,
            items: items,
            relations: relations,
            openQuestions: context.openQuestions,
            allowedArtifacts: allowedArtifacts(for: context),
            places: placeResults,
            webSearchResult: context.webSearchResult
        )
    }

    private func dedupeRelations(_ relations: [SelineChatEvidenceRelation]) -> [SelineChatEvidenceRelation] {
        var seen = Set<String>()
        return relations.filter { relation in
            let key = "\(relation.fromItemID)|\(relation.toItemID)|\(relation.label)"
            return seen.insert(key).inserted
        }
    }

    private func allowedArtifacts(for context: SelineChatRetrievedContext) -> Set<SelineChatArtifactKind> {
        // Cards are disabled for now — responses are text-only.
        // Tracker cards are kept since they display structured data that text can't easily convey.
        var artifacts = Set<SelineChatArtifactKind>()
        if context.frame.requestedDomains.contains(.trackers), !context.trackers.isEmpty {
            artifacts.insert(.trackerCards)
        }
        return artifacts
    }

    private func emailItem(_ email: Email, body: String? = nil) -> SelineChatEvidenceItem {
        // Use full body when available, fall back to snippet.
        // Truncate to 2000 chars to avoid bloating the prompt.
        let content: String?
        if let fullBody = body, !fullBody.isEmpty {
            content = String(fullBody.prefix(2000))
        } else {
            content = email.previewText
        }

        // Include attachment filenames so the LLM knows what's attached
        let attachmentNote: String? = email.attachments.isEmpty
            ? nil
            : "Attachments: " + email.attachments.map(\.name).joined(separator: ", ")

        let detail = [content, attachmentNote]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SelineChatEvidenceItem(
            id: "email-\(email.id)",
            kind: .email,
            title: email.subject.isEmpty ? "(No subject)" : email.subject,
            subtitle: email.sender.displayName,
            detail: detail.isEmpty ? nil : detail,
            footnote: FormatterCache.shortDate.string(from: email.timestamp),
            date: email.timestamp,
            emailID: email.id,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func noteItem(_ note: Note) -> SelineChatEvidenceItem {
        let noteDate = note.journalDate ?? note.dateModified
        return SelineChatEvidenceItem(
            id: "note-\(note.id.uuidString)",
            kind: .note,
            title: note.title,
            subtitle: note.preview,
            detail: note.isJournalEntry ? "Journal entry" : nil,
            footnote: FormatterCache.shortDate.string(from: noteDate),
            date: noteDate,
            emailID: nil,
            noteID: note.id,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func visitItem(_ visit: LocationVisitRecord, linkedPeople: [Person]) -> SelineChatEvidenceItem {
        let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
        let linkedPeopleText = linkedPeople.isEmpty ? nil : linkedPeople.map(\.displayName).joined(separator: ", ")
        let detailParts = [
            visit.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
            linkedPeopleText
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        // Build title as "Place Name · City" so the LLM knows the location even
        // when the user references it by area (e.g. "Niagara" → "Niku BBQ · Niagara Falls")
        let placeName = place?.displayName ?? "Visit"
        let cityLabel = place?.city.map { " · \($0)" } ?? ""
        let fullTitle = placeName + cityLabel

        return SelineChatEvidenceItem(
            id: "visit-\(visit.id.uuidString)",
            kind: .visit,
            title: fullTitle,
            subtitle: visitDurationLabel(for: visit),
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " • "),
            footnote: FormatterCache.shortDate.string(from: visit.entryTime),
            date: visit.entryTime,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: place?.id,
            personID: nil
        )
    }

    private func receiptItem(_ receipt: ReceiptStat, linkedPeople: [Person]) -> SelineChatEvidenceItem {
        let peopleText = linkedPeople.isEmpty ? nil : linkedPeople.map(\.displayName).joined(separator: ", ")
        let detail = [receipt.category, peopleText]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")

        return SelineChatEvidenceItem(
            id: "receipt-\(receipt.id.uuidString)",
            kind: .receipt,
            title: receipt.title,
            subtitle: CurrencyParser.formatAmount(receipt.amount),
            detail: detail.isEmpty ? nil : detail,
            footnote: FormatterCache.shortDate.string(from: receipt.date),
            date: receipt.date,
            emailID: nil,
            noteID: receipt.id,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func personItem(_ person: Person) -> SelineChatEvidenceItem {
        let detail = [person.relationshipDisplayText, person.notes]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")

        return SelineChatEvidenceItem(
            id: "person-\(person.id.uuidString)",
            kind: .person,
            title: person.displayName,
            subtitle: person.relationshipDisplayText,
            detail: detail.isEmpty ? nil : detail,
            footnote: nil,
            date: person.dateModified,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: person.id
        )
    }

    private func trackerItem(_ tracker: TrackerThread) -> SelineChatEvidenceItem {
        let subtitle: String
        let detail: String?
        if let state = tracker.cachedState {
            subtitle = state.headline
            detail = state.quickFacts.first
        } else {
            subtitle = tracker.subtitle ?? "No data yet"
            detail = nil
        }
        let lastUpdated = tracker.cachedState?.lastUpdatedAt ?? tracker.updatedAt
        return SelineChatEvidenceItem(
            id: "tracker-\(tracker.id.uuidString)",
            kind: .tracker,
            title: tracker.title,
            subtitle: subtitle,
            detail: detail,
            footnote: FormatterCache.shortDate.string(from: lastUpdated),
            date: lastUpdated,
            emailID: nil,
            noteID: nil,
            taskID: nil,
            placeID: nil,
            personID: nil
        )
    }

    private func visitDurationLabel(for visit: LocationVisitRecord) -> String {
        if let durationMinutes = visit.durationMinutes, durationMinutes > 0 {
            if durationMinutes >= 60 {
                let hours = Double(durationMinutes) / 60.0
                return String(format: "%.1f hours", hours)
            }
            return "\(durationMinutes) min"
        }

        if visit.exitTime == nil {
            return "Ongoing"
        }

        return FormatterCache.shortTime.string(from: visit.entryTime)
    }
}

final class SelineChatAnswerGenerator {
    private let geminiService = GeminiService.shared

    func streamAnswer(
        frame: SelineChatQuestionFrame,
        packet: SelineChatEvidencePacket,
        conversationHistory: [(role: String, text: String)] = [],
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        let memoryContext = await UserMemoryService.shared.getMemoryContext()
        let today = FormatterCache.shortDate.string(from: Date())

        var systemPrompt = """
        You are Seline, a grounded personal assistant embedded in an iOS life-tracking app.
        Today's date is \(today).

        The user's app tracks: notes, journal entries, emails, calendar events, location visits, saved places, receipts/expenses, people/contacts, and custom trackers.

        IMPORTANT: Notes and receipts are completely separate. Notes are text written by the user. Receipts are purchase records with merchant, amount, and date. Never return receipts when the user asks about notes, and never return notes when the user asks about receipts.

        DATA READING RULES:
        - Emails often contain booking confirmations, flight itineraries, hotel reservations, and event details. When the user asks about flights, travel plans, or upcoming bookings — READ the full email body carefully. The answer is usually inside the email.
        - Visit titles are formatted as "Place Name · City" — use the city to match area references (e.g. "Niagara" matches "Niku BBQ · Niagara Falls").
        - Web search results (when present) provide live external data like parking info, airport details, hours, and current conditions. Combine them with personal data for the best answer.
        - If web search results answer the question and personal data doesn't, answer from the web results — that's correct behaviour.

        Your job:
        - Answer questions directly using the evidence packet provided.
        - Never invent facts, dates, places, people, receipts, emails, or tracker data.
        - If evidence is partial or missing, say so honestly in one sentence — do not pad.
        - If something is unresolved, ask exactly one short clarification question and stop.
        - Start with a direct answer. Then add 2–4 concrete supporting details if the evidence supports it.
        - When multiple data types connect (e.g. a visit + a receipt + a person), explain the connection — that's the most valuable thing you can do.
        - Be conversational and warm, not robotic or listy. Avoid bullet points unless listing genuinely parallel items.
        - Never mention prompts, retrieval, tools, embeddings, vector search, or any internal system.
        - Keep responses concise. Don't summarize what you just said at the end.
        """

        if !memoryContext.isEmpty {
            systemPrompt += "\n\n" + memoryContext
        }

        var messages: [[String: String]] = []

        // Include recent conversation history for multi-turn context (last 8 turns)
        let recentHistory = conversationHistory.suffix(8)
        for turn in recentHistory {
            messages.append(["role": turn.role, "content": turn.text])
        }

        messages.append(["role": "user", "content": userPrompt(frame: frame, packet: packet)])

        return try await geminiService.simpleChatCompletionStreaming(
            systemPrompt: systemPrompt,
            messages: messages,
            operationType: "seline_evidence_chat",
            onChunk: onDelta
        )
    }

    func buildDraft(
        markdown: String,
        frame: SelineChatQuestionFrame,
        packet: SelineChatEvidencePacket
    ) -> SelineChatAnswerDraft {
        SelineChatAnswerDraft(
            markdown: markdown.trimmingCharacters(in: .whitespacesAndNewlines),
            referencedItemIDs: packet.referencedItemIDs,
            artifactRequests: artifactRequests(for: packet),
            followUpAnchor: followUpAnchor(for: frame, packet: packet)
        )
    }

    func buildPayload(
        from draft: SelineChatAnswerDraft,
        packet: SelineChatEvidencePacket,
        followUpSuggestions: [String] = []
    ) -> SelineChatAssistantPayload {
        var blocks: [SelineChatResponseBlock] = [.markdown(draft.markdown)]

        for request in draft.artifactRequests {
            switch request.kind {
            case .emailCards:
                let items = packet.items.filter { $0.kind == .email }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "Emails", items: items))
                }
            case .noteCards:
                let items = packet.items.filter { $0.kind == .note }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "Notes", items: items))
                }
            case .visitCards:
                let items = packet.items.filter { $0.kind == .visit }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "Visits", items: items))
                }
            case .placeCards:
                if !packet.places.isEmpty {
                    blocks.append(
                        .places(
                            title: request.title ?? "Saved Places",
                            results: packet.places,
                            showMap: draft.artifactRequests.contains(where: { $0.kind == .placeMap })
                        )
                    )
                }
            case .receiptCards:
                let items = packet.items.filter { $0.kind == .receipt }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "Receipts", items: items))
                }
            case .personCards:
                let items = packet.items.filter { $0.kind == .person }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "People", items: items))
                }
            case .trackerCards:
                let items = packet.items.filter { $0.kind == .tracker }
                if !items.isEmpty {
                    blocks.append(.evidence(title: request.title ?? "Trackers", items: items))
                }
            case .placeMap:
                continue
            }
        }

        return SelineChatAssistantPayload(
            sourceChips: renderedSourceChips(from: blocks),
            responseBlocks: blocks,
            activeContext: draft.followUpAnchor,
            followUpSuggestions: followUpSuggestions
        )
    }

    /// Generates 2-3 follow-up question suggestions based on the question and evidence packet.
    func generateFollowUps(
        frame: SelineChatQuestionFrame,
        packet: SelineChatEvidencePacket
    ) async -> [String] {
        guard !packet.facts.isEmpty || !packet.items.isEmpty else { return [] }

        let factsPreview = packet.facts.prefix(4).map(\.text).joined(separator: "; ")
        var seen = Set<String>()
        let domainsFound = packet.items.map(\.kind.label).filter { seen.insert($0).inserted }.joined(separator: ", ")

        let prompt = """
        The user asked: "\(frame.originalQuestion)"
        The response was grounded in: \(domainsFound.isEmpty ? "general context" : domainsFound)
        Key facts found: \(factsPreview.isEmpty ? "none" : factsPreview)

        Suggest 2-3 short follow-up questions the user might naturally ask next.
        Rules:
        - Each question should be answerable from the same data (notes, emails, visits, receipts, people, trackers)
        - Make them specific and useful, not generic
        - Keep each under 8 words
        - Return ONLY a JSON array of strings, e.g. ["Question 1?", "Question 2?"]
        """

        guard let raw = try? await geminiService.simpleChatCompletion(
            systemPrompt: "You generate short follow-up question suggestions. Return only valid JSON.",
            messages: [["role": "user", "content": prompt]],
            operationType: "follow_up_suggestions"
        ) else { return [] }

        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let suggestions = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }

        return Array(suggestions.prefix(3))
    }

    func directClarificationOrFailure(for packet: SelineChatEvidencePacket) -> String? {
        if let question = packet.openQuestions.first, !question.isEmpty {
            return question
        }
        if packet.facts.isEmpty && packet.items.isEmpty && packet.places.isEmpty {
            // If web search returned data, let the LLM answer from that — don't bail early
            if packet.webSearchResult != nil {
                return nil
            }
            return "I can't confirm that from your Seline data yet."
        }
        return nil
    }

    func fallbackMarkdown(for packet: SelineChatEvidencePacket) -> String {
        if let question = packet.openQuestions.first, !question.isEmpty {
            return question
        }

        if !packet.facts.isEmpty {
            let leadingFacts = packet.facts.prefix(4).map(\.text)
            if !packet.items.isEmpty {
                let supportingItems = packet.items.prefix(3).map { item in
                    var parts = [item.title, item.subtitle]
                    if let detail = item.detail, !detail.isEmpty {
                        parts.append(detail)
                    }
                    return "- " + parts.joined(separator: " • ")
                }
                return ([leadingFacts.joined(separator: "\n")] + supportingItems).joined(separator: "\n")
            }
            return leadingFacts.joined(separator: "\n")
        }

        if !packet.items.isEmpty {
            let bullets = packet.items.prefix(3).map { "- \($0.title): \($0.subtitle)" }.joined(separator: "\n")
            return "Here’s the grounded context I found:\n\(bullets)"
        }

        return "I can't confirm that from your Seline data yet."
    }

    private func userPrompt(frame: SelineChatQuestionFrame, packet: SelineChatEvidencePacket) -> String {
        let facts = packet.facts.map { "- \($0.text)" }.joined(separator: "\n")
        let items = packet.items.prefix(12).map { item in
            var parts = [item.kind.label, item.title, item.subtitle]
            if let footnote = item.footnote, !footnote.isEmpty {
                parts.append(footnote)  // includes date for visits, receipts, etc.
            }
            if let detail = item.detail, !detail.isEmpty {
                parts.append(detail)
            }
            return "- " + parts.joined(separator: " | ")
        }.joined(separator: "\n")
        let relations = packet.relations.prefix(12).map { "- \($0.fromItemID) \($0.label) \($0.toItemID)" }.joined(separator: "\n")
        let places = packet.places.prefix(6).map { place in
            var parts = [place.name, place.subtitle]
            if let category = place.category, !category.isEmpty {
                parts.append(category)
            }
            if let rating = place.rating {
                parts.append(String(format: "%.1f rating", rating))
            }
            if let savedPlaceID = place.savedPlaceID,
               let savedPlace = LocationsManager.shared.savedPlaces.first(where: { $0.id == savedPlaceID }) {
                if let isOpenNow = savedPlace.isOpenNow {
                    parts.append(isOpenNow ? "currently open" : "currently closed")
                }
                if let openingHours = savedPlace.openingHours, !openingHours.isEmpty {
                    parts.append(openingHours.prefix(2).joined(separator: " • "))
                }
                if let userNotes = savedPlace.userNotes, !userNotes.isEmpty {
                    parts.append(userNotes)
                }
            }
            return "- " + parts.joined(separator: " | ")
        }.joined(separator: "\n")
        let unresolved = packet.openQuestions.isEmpty ? "none" : packet.openQuestions.joined(separator: "\n")
        let entityMentions = frame.entityMentions.map(\.value).joined(separator: ", ")

        let webSection = packet.webSearchResult.map { result in
            "\n\nWeb search results (for external facts like parking, hours, directions):\n\(result)"
        } ?? ""

        return """
        Question:
        \(frame.originalQuestion)

        Explicit entities:
        \(entityMentions.isEmpty ? "none" : entityMentions)

        Time scope:
        \(frame.timeScope?.description ?? "none")

        Facts:
        \(facts.isEmpty ? "- none" : facts)

        Items:
        \(items.isEmpty ? "- none" : items)

        Relations:
        \(relations.isEmpty ? "- none" : relations)

        Places:
        \(places.isEmpty ? "- none" : places)

        Unresolved:
        \(unresolved)\(webSection)

        Answer the question using the personal data and web results above. Be conversational and warm.
        """
    }

    private func artifactRequests(for packet: SelineChatEvidencePacket) -> [SelineChatArtifactRequest] {
        var requests: [SelineChatArtifactRequest] = []

        if packet.allowedArtifacts.contains(.emailCards) {
            requests.append(SelineChatArtifactRequest(kind: .emailCards, title: "Emails"))
        }
        if packet.allowedArtifacts.contains(.noteCards) {
            requests.append(SelineChatArtifactRequest(kind: .noteCards, title: "Notes"))
        }
        if packet.allowedArtifacts.contains(.visitCards) {
            requests.append(SelineChatArtifactRequest(kind: .visitCards, title: "Visits"))
        }
        if packet.allowedArtifacts.contains(.receiptCards) {
            requests.append(SelineChatArtifactRequest(kind: .receiptCards, title: "Receipts"))
        }
        if packet.allowedArtifacts.contains(.personCards) {
            requests.append(SelineChatArtifactRequest(kind: .personCards, title: "People"))
        }
        if packet.allowedArtifacts.contains(.placeCards) {
            requests.append(SelineChatArtifactRequest(kind: .placeCards, title: "Saved Places"))
        }
        if packet.allowedArtifacts.contains(.trackerCards) {
            requests.append(SelineChatArtifactRequest(kind: .trackerCards, title: "Trackers"))
        }
        if packet.allowedArtifacts.contains(.placeMap) {
            requests.append(SelineChatArtifactRequest(kind: .placeMap))
        }

        return requests
    }

    private func followUpAnchor(
        for frame: SelineChatQuestionFrame,
        packet: SelineChatEvidencePacket
    ) -> SelineChatActiveContext? {
        var context = SelineChatActiveContext()

        if packet.places.count == 1, let place = packet.places.first, let savedPlaceID = place.savedPlaceID {
            context.placeAnchor = SelineChatPlaceAnchor(savedPlaceID: savedPlaceID, name: place.name)
        }

        let emailItems = packet.items.filter { $0.kind == .email }
        if emailItems.count == 1, let item = emailItems.first, let emailID = item.emailID {
            context.emailAnchor = SelineChatEmailAnchor(emailID: emailID, subject: item.title)
        }

        let visitItems = packet.items.filter { $0.kind == .visit }
        if !visitItems.isEmpty && (frame.requestedDomains.contains(.visits) || frame.requestedDomains.contains(.places) || frame.requestedDomains.contains(.people)) {
            let visitIDs = visitItems.compactMap { UUID(uuidString: $0.id.replacingOccurrences(of: "visit-", with: "")) }
            let placeIDs = visitItems.compactMap(\.placeID)
            let personIDs = packet.items.filter { $0.kind == .person }.compactMap(\.personID)
            let visitDates = visitItems.compactMap(\.date)
            let label = packet.places.first?.name ?? visitItems.first?.title ?? "Visit"
            context.episodeAnchor = SelineChatEpisodeAnchor(
                visitIDs: visitIDs,
                placeIDs: placeIDs,
                personIDs: personIDs,
                label: label,
                visitDates: visitDates
            )
        }

        let personItems = packet.items.filter { $0.kind == .person }
        if personItems.count == 1, let item = personItems.first, let personID = item.personID {
            context.personAnchor = SelineChatPersonAnchor(personID: personID, name: item.title)
        }

        let receiptItems = packet.items.filter { $0.kind == .receipt }
        if !receiptItems.isEmpty && frame.requestedDomains.contains(.receipts) {
            context.receiptClusterAnchor = SelineChatReceiptClusterAnchor(
                noteIDs: receiptItems.compactMap(\.noteID),
                title: receiptItems.first?.title ?? "Receipts"
            )
        }

        if context == SelineChatActiveContext() {
            return nil
        }
        return context
    }

    private func renderedSourceChips(from blocks: [SelineChatResponseBlock]) -> [String] {
        var chips: [String] = []
        for block in blocks {
            switch block {
            case .markdown:
                continue
            case .evidence(let title, let items):
                if !items.isEmpty {
                    chips.append(title)
                }
            case .places(let title, let results, _):
                if !results.isEmpty {
                    chips.append(title)
                }
            case .citations:
                chips.append("Sources")
            }
        }

        var seen = Set<String>()
        return chips.filter { seen.insert($0).inserted }
    }
}
