import Foundation

@MainActor
final class SelineChatOrchestrator {
    weak var threadProvider: SelineChatThreadProviding?

    private let interpreter = SelineChatQuestionInterpreter()
    private let toolExecutor = SelineChatToolExecutor()
    private let responsesService = SelineChatOpenAIResponsesService()
    private let genericInlineSourceTerms: Set<String> = [
        "all", "appointment", "appointments", "detail", "details", "email", "emails",
        "event", "events", "exact", "last", "latest", "message", "messages", "more",
        "location", "locations", "map", "near", "nearby", "place", "places",
        "note", "notes", "person", "people", "previous", "receipt", "receipts",
        "recent", "recently", "show", "spot", "spots", "tell", "visit", "visits", "when"
    ]

    func send(_ text: String, in threadID: UUID?) -> AsyncThrowingStream<SelineChatStreamEvent, Error> {
        let thread = threadProvider?.thread(id: threadID)
        let recentEvidence = thread?.lastEvidenceBundle
        let activeContext = thread?.activeContext

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let startedAt = Date()
                let frame = interpreter.interpret(
                    text,
                    activeContext: activeContext,
                    recentEvidence: recentEvidence
                )

                continuation.yield(
                    .status(
                        title: "Understanding your question…",
                        sourceChips: []
                    )
                )

                do {
                    let runResult = try await responsesService.run(
                        question: text,
                        frame: frame,
                        providerState: thread?.providerState,
                        recentEvidence: recentEvidence,
                        toolExecutor: toolExecutor,
                        onStatus: { title, chips in
                            continuation.yield(.status(title: title, sourceChips: chips))
                        }
                    )

                    let answer = finalizedAnswer(
                        from: runResult.answerMarkdown,
                        bundle: runResult.evidenceBundle
                    )
                    let payload = buildPayload(
                        markdown: answer,
                        frame: frame,
                        bundle: runResult.evidenceBundle
                    )
                    let trace = SelineChatTurnTrace(
                        query: text,
                        startedAt: startedAt,
                        completedAt: Date(),
                        toolCalls: runResult.evidenceBundle.trace,
                        finalEvidenceIDs: runResult.evidenceBundle.records.map(\.id),
                        noAnswerReason: runResult.noAnswerReason
                    )

                    continuation.yield(
                        .completed(
                            SelineChatCompletionContext(
                                payload: payload,
                                providerState: runResult.providerState,
                                lastEvidenceBundle: runResult.evidenceBundle,
                                turnTrace: trace
                            )
                        )
                    )
                } catch {
                    continuation.yield(
                        .failed(
                            "I couldn't answer that right now. Try again in a moment."
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func finalizedAnswer(
        from markdown: String,
        bundle: SelineChatEvidenceBundle
    ) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if let firstRecord = bundle.records.first {
            return "I found grounded information in \(firstRecord.sourceKind.label.lowercased()), but I couldn't turn it into a final answer cleanly yet."
        }

        if !bundle.citations.isEmpty {
            return "I found live web sources, but I couldn't produce a grounded final answer cleanly yet."
        }

        return "I couldn't find enough grounded data to answer that."
    }

    private func buildPayload(
        markdown: String,
        frame: SelineChatQuestionFrame,
        bundle: SelineChatEvidenceBundle
    ) -> SelineChatAssistantPayload {
        let inlineSources = inlineSources(
            from: bundle,
            frame: frame,
            answerMarkdown: markdown
        )
        var responseBlocks: [SelineChatResponseBlock] = [.markdown(markdown)]

        if frame.wantsMap && !bundle.places.isEmpty {
            responseBlocks.append(
                .places(
                    title: "Places",
                    results: Array(bundle.places.prefix(8)),
                    showMap: frame.wantsMap || bundle.places.count > 1
                )
            )
        }

        return SelineChatAssistantPayload(
            sourceChips: [],
            responseBlocks: responseBlocks,
            activeContext: activeContext(from: bundle, frame: frame),
            inlineSources: inlineSources,
            followUpSuggestions: followUpSuggestions(from: bundle)
        )
    }

    private func activeContext(
        from bundle: SelineChatEvidenceBundle,
        frame: SelineChatQuestionFrame
    ) -> SelineChatActiveContext? {
        var context = SelineChatActiveContext()

        if bundle.places.count == 1,
           let place = bundle.places.first,
           let savedPlaceID = place.savedPlaceID {
            context.placeAnchor = SelineChatPlaceAnchor(savedPlaceID: savedPlaceID, name: place.name)
        }

        let emailItems = bundle.items.filter { $0.kind == .email }
        if emailItems.count == 1,
           let item = emailItems.first,
           let emailID = item.emailID {
            context.emailAnchor = SelineChatEmailAnchor(emailID: emailID, subject: item.title)
        }

        let visitItems = bundle.items.filter { $0.kind == .visit }
        if !visitItems.isEmpty,
           (
                frame.requestedDomains.contains(.visits)
                || frame.requestedDomains.contains(.places)
                || frame.requestedDomains.contains(.people)
                || frame.timeScope != nil
           ) {
            let visitIDs = bundle.records
                .filter { $0.sourceKind == .visit }
                .compactMap { record in
                    parseUUID(from: record.id, prefix: "visit:")
                }
            let placeIDs = visitItems.compactMap(\.placeID)
            let personIDs = bundle.items.filter { $0.kind == .person }.compactMap(\.personID)
            let visitDates = visitItems.compactMap(\.date)
            let label = bundle.places.first?.name ?? visitItems.first?.title ?? "Visit"

            context.episodeAnchor = SelineChatEpisodeAnchor(
                visitIDs: Array(Set(visitIDs)),
                placeIDs: Array(Set(placeIDs)),
                personIDs: Array(Set(personIDs)),
                label: label,
                visitDates: Array(Set(visitDates)).sorted()
            )
        }

        let personItems = bundle.items.filter { $0.kind == .person }
        if personItems.count == 1,
           let item = personItems.first,
           let personID = item.personID {
            context.personAnchor = SelineChatPersonAnchor(personID: personID, name: item.title)
        }

        let receiptItems = bundle.items.filter { $0.kind == .receipt }
        if !receiptItems.isEmpty && frame.requestedDomains.contains(.receipts) {
            context.receiptClusterAnchor = SelineChatReceiptClusterAnchor(
                noteIDs: receiptItems.compactMap(\.noteID),
                title: receiptItems.first?.title ?? "Receipts"
            )
        }

        return context == SelineChatActiveContext() ? nil : context
    }

    private func parseUUID(from value: String, prefix: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }

    private func inlineSources(
        from bundle: SelineChatEvidenceBundle,
        frame: SelineChatQuestionFrame,
        answerMarkdown: String
    ) -> [SelineChatInlineSource] {
        let rankedItems = bundle.items
            .map { item in
                (item: item, score: inlineSourceScore(for: item, frame: frame, answerMarkdown: answerMarkdown))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.item.date ?? .distantPast) > (rhs.item.date ?? .distantPast)
                }
                return lhs.score > rhs.score
            }

        let rankedCitations = bundle.citations
            .map { citation in
                (citation: citation, score: inlineCitationScore(for: citation, frame: frame, answerMarkdown: answerMarkdown))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.citation.title.localizedCaseInsensitiveCompare(rhs.citation.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }

        let rankedPlaces = bundle.places
            .map { place in
                (place: place, score: inlinePlaceScore(for: place, frame: frame, answerMarkdown: answerMarkdown))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }

        var sources: [SelineChatInlineSource] = rankedItems
            .filter { $0.score > 0 }
            .prefix(rankedPlaces.isEmpty && rankedCitations.isEmpty ? 4 : 2)
            .map { SelineChatInlineSource(evidenceItem: $0.item, displayText: inlineSourceLabel(for: $0.item)) }

        let placeLimit = max(0, min(4 - sources.count, rankedCitations.isEmpty ? 3 : 2))
        if placeLimit > 0 {
            let relevantPlaces = rankedPlaces.filter { $0.score > 0 }
            let placesToUse = (relevantPlaces.isEmpty ? rankedPlaces : relevantPlaces).prefix(placeLimit)
            sources.append(contentsOf: placesToUse.map {
                SelineChatInlineSource(placeResult: $0.place, displayText: inlineSourceLabel(for: $0.place))
            })
        }

        let citationLimit = max(0, 4 - sources.count)
        if citationLimit > 0 {
            let relevantCitations = rankedCitations.filter { $0.score > 0 }
            let citationsToUse = (relevantCitations.isEmpty ? rankedCitations : relevantCitations).prefix(citationLimit)
            sources.append(contentsOf: citationsToUse.map {
                SelineChatInlineSource(citation: $0.citation, displayText: inlineSourceLabel(for: $0.citation))
            })
        }

        if sources.isEmpty, frame.timeScope != nil {
            sources = rankedItems
                .filter { $0.item.date != nil }
                .prefix(3)
                .map { SelineChatInlineSource(evidenceItem: $0.item, displayText: inlineSourceLabel(for: $0.item)) }
        } else if sources.isEmpty, !bundle.places.isEmpty {
            sources = rankedPlaces
                .prefix(4)
                .map { SelineChatInlineSource(placeResult: $0.place, displayText: inlineSourceLabel(for: $0.place)) }
        }

        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }
    }

    private func inlineSourceScore(
        for item: SelineChatEvidenceItem,
        frame: SelineChatQuestionFrame,
        answerMarkdown: String
    ) -> Double {
        let title = normalizedSearchText(item.title)
        let subtitle = normalizedSearchText(item.subtitle)
        let detail = normalizedSearchText(item.detail ?? "")
        let footnote = normalizedSearchText(item.footnote ?? "")
        let searchable = [title, subtitle, detail, footnote]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedAnswer = normalizedSearchText(answerMarkdown)

        var score = 0.0

        if !title.isEmpty, normalizedAnswer.contains(title) {
            score += 14
        } else if !searchable.isEmpty, normalizedAnswer.contains(searchable) {
            score += 10
        }

        for term in meaningfulQueryTerms(from: frame) {
            guard !term.isEmpty else { continue }
            if title.contains(term) {
                score += term.contains(" ") ? 8 : 6
            } else if subtitle.contains(term) {
                score += term.contains(" ") ? 6 : 4
            } else if detail.contains(term) {
                score += term.contains(" ") ? 5 : 3
            } else if footnote.contains(term) {
                score += 1
            }
        }

        for mention in frame.entityMentions.map(\.normalizedValue).map(normalizedSearchText) where !mention.isEmpty {
            if searchable.contains(mention) {
                score += 8
            }
        }

        if let interval = frame.timeScope?.interval,
           let date = item.date,
           interval.contains(date) {
            score += 4
        }

        if frame.requestedDomains.contains(domain(for: item.kind)) {
            score += 1.5
        }

        return score
    }

    private func inlineCitationScore(
        for citation: SelineChatWebCitation,
        frame: SelineChatQuestionFrame,
        answerMarkdown: String
    ) -> Double {
        let normalizedAnswer = normalizedSearchText(answerMarkdown)
        let normalizedTitle = normalizedSearchText(citation.title)
        let normalizedSource = normalizedSearchText(citation.source ?? "")
        var score = 0.0

        if !normalizedTitle.isEmpty, normalizedAnswer.contains(normalizedTitle) {
            score += 8
        }
        if !normalizedSource.isEmpty, normalizedAnswer.contains(normalizedSource) {
            score += 5
        }

        for term in meaningfulQueryTerms(from: frame) {
            if normalizedTitle.contains(term) {
                score += term.contains(" ") ? 5 : 3
            } else if normalizedSource.contains(term) {
                score += 2
            }
        }

        return score
    }

    private func inlinePlaceScore(
        for place: SelineChatPlaceResult,
        frame: SelineChatQuestionFrame,
        answerMarkdown: String
    ) -> Double {
        let name = normalizedSearchText(place.name)
        let subtitle = normalizedSearchText(place.subtitle)
        let category = normalizedSearchText(place.category ?? "")
        let searchable = [name, subtitle, category]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedAnswer = normalizedSearchText(answerMarkdown)

        var score = 0.0

        if !name.isEmpty, normalizedAnswer.contains(name) {
            score += 12
        }

        for term in meaningfulQueryTerms(from: frame) {
            if name.contains(term) {
                score += term.contains(" ") ? 8 : 6
            } else if category.contains(term) {
                score += term.contains(" ") ? 6 : 4
            } else if subtitle.contains(term) {
                score += term.contains(" ") ? 4 : 2
            }
        }

        for mention in frame.entityMentions.map(\.normalizedValue).map(normalizedSearchText) where !mention.isEmpty {
            if searchable.contains(mention) {
                score += 8
            }
        }

        if frame.requestedDomains.contains(.places) || frame.wantsMap {
            score += 1.5
        }

        if place.isSaved {
            score += 0.5
        }

        return score
    }

    private func inlineSourceLabel(for item: SelineChatEvidenceItem) -> String {
        let trimmedFootnote = item.footnote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedFootnote.isEmpty, item.title.count + trimmedFootnote.count <= 54 {
            return "\(item.title) · \(trimmedFootnote)"
        }
        return item.title
    }

    private func inlineSourceLabel(for citation: SelineChatWebCitation) -> String {
        let source = citation.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty, source.caseInsensitiveCompare(citation.title) != .orderedSame {
            return "\(source) · \(citation.title)"
        }
        return source.isEmpty ? citation.title : source
    }

    private func inlineSourceLabel(for place: SelineChatPlaceResult) -> String {
        let category = place.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCategory = normalizedSearchText(category)
        let genericCategories = Set(["establishment", "point of interest", "store", "food", "restaurant"])
        if !category.isEmpty,
           !genericCategories.contains(normalizedCategory),
           category.caseInsensitiveCompare(place.name) != .orderedSame,
           place.name.count + category.count <= 42 {
            return "\(place.name) · \(category)"
        }
        return place.name
    }

    private func meaningfulQueryTerms(from frame: SelineChatQuestionFrame) -> [String] {
        var seen = Set<String>()
        return frame.searchTerms
            .map(normalizedSearchText)
            .filter { term in
                guard term.count >= 3 else { return false }
                guard !genericInlineSourceTerms.contains(term) else { return false }
                return seen.insert(term).inserted
            }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func domain(for kind: SelineChatEvidenceKind) -> SelineChatDomain {
        switch kind {
        case .email:
            return .emails
        case .event:
            return .events
        case .note:
            return .notes
        case .receipt:
            return .receipts
        case .visit:
            return .visits
        case .person:
            return .people
        case .daySummary:
            return .daySummaries
        case .tracker:
            return .trackers
        }
    }

    private func followUpSuggestions(from bundle: SelineChatEvidenceBundle) -> [String] {
        let sourceKinds = Set(bundle.records.map(\.sourceKind))
        var suggestions: [String] = []

        if sourceKinds.contains(.daySummary) || sourceKinds.contains(.event) {
            suggestions.append("What else happened that day?")
        }
        if sourceKinds.contains(.email) {
            suggestions.append("Show me the exact email")
        }
        if sourceKinds.contains(.place) {
            suggestions.append("How far is it right now?")
        }
        if sourceKinds.contains(.receipt) {
            suggestions.append("What else did I spend that day?")
        }
        if sourceKinds.contains(.person) {
            suggestions.append("What else have I done with them?")
        }

        return Array(suggestions.prefix(3))
    }
}
