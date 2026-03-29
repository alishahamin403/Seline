import Foundation

@MainActor
final class SelineChatEvidenceSynthesizer {
    func synthesize(_ context: SelineChatRetrievedContext) async -> SelineChatEvidencePacket {
        var items: [SelineChatEvidenceItem] = []
        var facts: [SelineChatGroundedFact] = []
        var relations: [SelineChatEvidenceRelation] = []

        let emailItems = context.emails.map(emailItem)
        let noteItems = context.notes.map(noteItem)
        let visitItems = context.visits.map { visitItem($0, linkedPeople: context.peopleByVisit[$0.id] ?? []) }
        let receiptItems = context.receipts.map { receiptItem($0, linkedPeople: context.peopleByReceipt[$0.noteId] ?? []) }
        let personItems = context.people.map(personItem)
        let placeResults = SelineChatPlacesService().placeResults(from: context.places)

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
        }

        if let firstVisit = context.visits.first {
            let placeName = context.places.first(where: { $0.id == firstVisit.savedPlaceId })?.displayName ?? "that place"
            let when = FormatterCache.shortDate.string(from: firstVisit.entryTime)
            facts.append(
                SelineChatGroundedFact(
                    text: "A relevant visit was at \(placeName) on \(when).",
                    sourceItemIDs: ["visit-\(firstVisit.id.uuidString)"]
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
            let receiptItemID = "receipt-\(receipt.noteId.uuidString)"
            for person in context.peopleByReceipt[receipt.noteId] ?? [] {
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
            places: placeResults
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
        var artifacts = context.frame.artifactIntent

        if context.frame.requestedDomains == [.emails], !context.emails.isEmpty {
            artifacts.insert(.emailCards)
        }
        if context.frame.requestedDomains == [.receipts], !context.receipts.isEmpty {
            artifacts.insert(.receiptCards)
        }
        if context.frame.requestedDomains == [.places], !context.places.isEmpty, (context.frame.wantsList || context.frame.wantsMap) {
            artifacts.insert(.placeCards)
        }
        if context.frame.wantsMap, !context.places.isEmpty {
            artifacts.insert(.placeCards)
            artifacts.insert(.placeMap)
        }

        return artifacts
    }

    private func emailItem(_ email: Email) -> SelineChatEvidenceItem {
        SelineChatEvidenceItem(
            id: "email-\(email.id)",
            kind: .email,
            title: email.subject.isEmpty ? "(No subject)" : email.subject,
            subtitle: email.sender.displayName,
            detail: email.previewText,
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

        return SelineChatEvidenceItem(
            id: "visit-\(visit.id.uuidString)",
            kind: .visit,
            title: place?.displayName ?? "Visit",
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
            id: "receipt-\(receipt.noteId.uuidString)",
            kind: .receipt,
            title: receipt.title,
            subtitle: CurrencyParser.formatAmount(receipt.amount),
            detail: detail.isEmpty ? nil : detail,
            footnote: FormatterCache.shortDate.string(from: receipt.date),
            date: receipt.date,
            emailID: nil,
            noteID: receipt.noteId,
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
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        let systemPrompt = """
        You are Seline, a grounded personal assistant.

        Rules:
        - Answer only from the evidence packet.
        - Never invent facts, dates, places, people, receipts, or emails.
        - If evidence is partial, say that clearly.
        - If the packet says something is unresolved, ask only one short clarification question.
        - Start with a direct answer in one sentence.
        - If the packet contains multiple useful details, add 2 to 4 concrete supporting details after the direct answer.
        - Prefer explaining the connection between sources when that helps answer the question.
        - Do not stop at a one-line summary if the packet clearly supports a richer answer.
        - Do not mention prompts, retrieval, tools, embeddings, or internal systems.
        """

        let messages = [[
            "role": "user",
            "content": userPrompt(frame: frame, packet: packet)
        ]]

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
        packet: SelineChatEvidencePacket
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
            case .placeMap:
                continue
            }
        }

        return SelineChatAssistantPayload(
            sourceChips: renderedSourceChips(from: blocks),
            responseBlocks: blocks,
            activeContext: draft.followUpAnchor
        )
    }

    func directClarificationOrFailure(for packet: SelineChatEvidencePacket) -> String? {
        if let question = packet.openQuestions.first, !question.isEmpty {
            return question
        }
        if packet.facts.isEmpty && packet.items.isEmpty && packet.places.isEmpty {
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
        \(unresolved)

        Answer the question using only this packet.
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
            let label = packet.places.first?.name ?? visitItems.first?.title ?? "Visit"
            context.episodeAnchor = SelineChatEpisodeAnchor(
                visitIDs: visitIDs,
                placeIDs: placeIDs,
                personIDs: personIDs,
                label: label
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
