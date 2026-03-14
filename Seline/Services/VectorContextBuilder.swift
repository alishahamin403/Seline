import Foundation
import CoreLocation

/**
 * VectorContextBuilder - LLM Context using Vector Search
 *
 * Simplified approach: Let vector search do the work, add date completeness guarantees,
 * and use a small generic retrieval plan to distinguish top-K relevance from exhaustive list/count queries.
 * Avoid domain-specific routing; rely on generic query semantics instead.
 *
 * Benefits:
 * - Much simpler codebase (~80% less code)
 * - More flexible (adapts to new query types automatically)
 * - Still guarantees completeness for date-specific queries
 * - Better semantic matching with broader recall for exhaustive questions
 */
@MainActor
class VectorContextBuilder {
    static let shared = VectorContextBuilder()

    private enum AnswerOperation: String {
        case answer
        case list
        case count
        case latest
        case summarize
        case compare
    }

    private enum RetrievalStrategy: String {
        case focused
        case multiFacet
    }

    private struct QueryPlan {
        let operation: AnswerOperation
        let retrievalStrategy: RetrievalStrategy
        let retrievalMode: VectorSearchService.RetrievalMode
        let preferHistorical: Bool
        let shouldRunSecondPass: Bool
        let allowWidening: Bool
        let documentTypes: [VectorSearchService.DocumentType]?
        let admission: VectorSearchService.RetrievalAdmission
    }

    private struct RetrievalLane {
        let title: String
        let query: String
        let documentTypes: [VectorSearchService.DocumentType]?
        let presentation: VectorSearchService.ContextPresentation
        let admission: VectorSearchService.RetrievalAdmission
    }

    private let vectorSearch = VectorSearchService.shared
    private let monthNameToNumber: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12
    ]

    func clearConversationAnchors() {
    }

    // MARK: - Configuration

    /// Determine dynamic search limit based on query complexity and temporal intent.
    private func determineSearchLimit(forQuery query: String, plan: QueryPlan) -> Int {
        let lowercased = query.lowercased()
        let baselineLimit: Int

        if plan.retrievalMode == .exhaustive && plan.preferHistorical {
            baselineLimit = 70
        } else if plan.retrievalMode == .exhaustive {
            baselineLimit = 50
        } else if plan.preferHistorical || isHistoricalQuery(query: query) {
            baselineLimit = 90
        } else if lowercased.contains("all ")
            || lowercased.contains("every ")
            || lowercased.contains("total ")
            || lowercased.contains("history ")
            || lowercased.contains("in the past")
            || lowercased.contains("how much")
            || lowercased.contains("paid")
            || lowercased.contains("spent") {
            baselineLimit = 70
        } else if lowercased.contains("yesterday") || lowercased.contains("today") ||
                    lowercased.contains("week") || lowercased.contains("month") {
            baselineLimit = 30
        } else {
            baselineLimit = 18
        }

        let wideningMultiplier = plan.allowWidening ? 3 : 2
        let budgetDrivenLimit = max(
            12,
            max(
                plan.admission.maxMergedResults + 6,
                plan.admission.maxMergedResults * wideningMultiplier
            )
        )

        return min(baselineLimit, budgetDrivenLimit)
    }

    private func shouldRunExpandedSecondPass(forQuery query: String, plan: QueryPlan) -> Bool {
        let lowercased = query.lowercased()

        if plan.shouldRunSecondPass || plan.preferHistorical || isHistoricalQuery(query: query) {
            return true
        }

        return lowercased.contains("all ")
            || lowercased.contains("every ")
            || lowercased.contains("history ")
            || lowercased.contains("summary")
            || lowercased.contains("summarize")
            || lowercased.contains("compare")
    }

    private func buildQueryPlan(
        for query: String,
        dateRange: (start: Date, end: Date)? = nil
    ) -> QueryPlan {
        let padded = " " + query.lowercased() + " "
        let isShortTopicalQuery = looksLikeShortTopicalQuery(query)

        let operation: AnswerOperation
        if containsAnySignal([" how many ", " count ", " number of "], in: padded) {
            operation = .count
        } else if containsAnySignal([" compare ", " versus ", " vs "], in: padded) {
            operation = .compare
        } else if containsAnySignal([" summary ", " summarize ", " recap ", " overview "], in: padded) {
            operation = .summarize
        } else if containsAnySignal([" latest ", " most recent ", " newest "], in: padded) {
            operation = .latest
        } else if containsAnySignal(
            [
                " all ",
                " every ",
                " list ",
                " show me all ",
                " tell me all ",
                " all my ",
                " i've had ",
                " i have had ",
                " ever had ",
                " ever went ",
                " ever visited "
            ],
            in: padded
        ) {
            operation = .list
        } else {
            operation = .answer
        }

        let exhaustiveSignals = containsAnySignal(
            [
                " all ",
                " every ",
                " list ",
                " show me all ",
                " tell me all ",
                " all my ",
                " i've had ",
                " i have had ",
                " ever had ",
                " how many ",
                " number of "
            ],
            in: padded
        )
        let retrievalMode: VectorSearchService.RetrievalMode = (operation == .count || operation == .list || exhaustiveSignals) ? .exhaustive : .topK

        let baseHistorical = isHistoricalQuery(query: query, dateRange: dateRange)
        let historicalBiasSignals = containsAnySignal(
            [
                " had ",
                " ever ",
                " history ",
                " over time ",
                " total ",
                " times ",
                " been "
            ],
            in: padded
        )
        let preferHistorical = baseHistorical || (retrievalMode == .exhaustive && historicalBiasSignals)
        let inferredTypes = inferredDocumentTypes(for: query)
            ?? (isShortTopicalQuery ? [.visit, .location, .receipt, .note, .email] : nil)
        let retrievalStrategy = shouldUseMultiFacetRetrieval(
            for: query,
            operation: operation,
            inferredDocumentTypes: inferredTypes,
            preferHistorical: preferHistorical
        ) ? RetrievalStrategy.multiFacet : .focused
        let documentTypes = retrievalStrategy == .multiFacet ? nil : inferredTypes
        let allowWidening = shouldAllowWidening(
            operation: operation,
            retrievalMode: retrievalMode,
            preferHistorical: preferHistorical,
            documentTypes: documentTypes,
            retrievalStrategy: retrievalStrategy
        )
        let shouldRunSecondPass = allowWidening && (
            preferHistorical
            || retrievalMode == .exhaustive
            || operation == .summarize
            || operation == .compare
        )
        let admission = buildRetrievalAdmission(
            operation: operation,
            retrievalMode: retrievalMode,
            preferHistorical: preferHistorical,
            documentTypes: documentTypes,
            allowWidening: allowWidening,
            minimumAnchorMatches: (documentTypes != nil || isShortTopicalQuery) ? 1 : 0
        )

        return QueryPlan(
            operation: operation,
            retrievalStrategy: retrievalStrategy,
            retrievalMode: retrievalMode,
            preferHistorical: preferHistorical,
            shouldRunSecondPass: shouldRunSecondPass,
            allowWidening: allowWidening,
            documentTypes: documentTypes,
            admission: admission
        )
    }

    private func shouldUseMultiFacetRetrieval(
        for query: String,
        operation: AnswerOperation,
        inferredDocumentTypes: [VectorSearchService.DocumentType]?,
        preferHistorical: Bool
    ) -> Bool {
        if operation == .summarize || operation == .compare {
            return true
        }

        guard operation == .answer else { return false }

        let lower = " " + query.lowercased() + " "
        let broadSignals = [
            " what did i do ",
            " what did we do ",
            " what happened ",
            " tell me about ",
            " walk me through ",
            " how did i ",
            " how did we ",
            " how was ",
            " whole day ",
            " whole weekend ",
            " that whole day ",
            " around ",
            " during ",
            " celebrate ",
            " celebrated ",
            " celebration ",
            " full picture ",
            " everything about "
        ]
        let hasBroadSignal = broadSignals.contains { lower.contains($0) }
        let inferredTypeCount = Set(inferredDocumentTypes ?? []).count

        if hasBroadSignal && (inferredTypeCount >= 2 || preferHistorical) {
            return true
        }

        if inferredTypeCount >= 4 {
            return true
        }

        let relationalSignals = [
            " with ",
            " around ",
            " during ",
            " on ",
            " for "
        ]
        let hasRelationalSignal = relationalSignals.contains { lower.contains($0) }
        return hasBroadSignal && hasRelationalSignal
    }

    private func containsAnySignal(_ signals: [String], in text: String) -> Bool {
        signals.contains { text.contains($0) }
    }

    private func inferredDocumentTypes(for query: String) -> [VectorSearchService.DocumentType]? {
        let padded = " " + query.lowercased() + " "
        var types = Set<VectorSearchService.DocumentType>()

        if containsAnySignal(
            [" spend ", " spent ", " pay ", " paid ", " cost ", " costs ", " amount ", " total ", " receipt ", " receipts ", " purchase ", " purchases ", " price ", "$"],
            in: padded
        ) {
            types.insert(.receipt)
        }

        if containsAnySignal(
            [" where ", " place ", " places ", " location ", " locations ", " visit ", " visited ", " went ", " go to ", " been to ", " near "],
            in: padded
        ) {
            types.insert(.visit)
            types.insert(.location)
        }

        if containsAnySignal(
            [" email ", " emails ", " inbox ", " unread ", " sender ", " subject ", " message ", " messages ", " thread "],
            in: padded
        ) {
            types.insert(.email)
        }

        if containsAnySignal(
            [" task ", " tasks ", " todo ", " to do ", " event ", " events ", " calendar ", " meeting ", " meetings ", " appointment ", " appointments ", " scheduled ", " schedule "],
            in: padded
        ) {
            types.insert(.task)
        }

        if containsAnySignal(
            [" note ", " notes ", " journal ", " diary ", " recap ", " reflection ", " wrote ", " writing "],
            in: padded
        ) {
            types.insert(.note)
        }

        if containsAnySignal(
            [" person ", " people ", " contact ", " contacts ", " friend ", " friends ", " family ", " birthday ", " birthdays ", " relationship ", " relationships ", " who is ", " who s ", " whose "],
            in: padded
        ) {
            types.insert(.person)
        }

        return types.isEmpty ? nil : Array(types)
    }

    private func shouldAllowWidening(
        operation: AnswerOperation,
        retrievalMode: VectorSearchService.RetrievalMode,
        preferHistorical: Bool,
        documentTypes: [VectorSearchService.DocumentType]?,
        retrievalStrategy: RetrievalStrategy
    ) -> Bool {
        if retrievalStrategy == .multiFacet {
            return true
        }

        if operation == .summarize || operation == .compare {
            return true
        }

        if documentTypes == nil {
            return retrievalMode == .exhaustive || preferHistorical
        }

        return false
    }

    private func buildRetrievalAdmission(
        operation: AnswerOperation,
        retrievalMode: VectorSearchService.RetrievalMode,
        preferHistorical: Bool,
        documentTypes: [VectorSearchService.DocumentType]?,
        allowWidening: Bool,
        minimumAnchorMatches: Int
    ) -> VectorSearchService.RetrievalAdmission {
        let focusedTypes = Set(documentTypes ?? [])
        var perTypeCaps = Dictionary(
            uniqueKeysWithValues: VectorSearchService.DocumentType.allCases.map { ($0, 2) }
        )

        let defaults: (searchQueries: Int, mergedResults: Int, previewChars: Int, canonicalRecords: Int, evidenceItems: Int, focusedCap: Int, broadCap: Int) = {
            switch operation {
            case .latest:
                return (1, 8, 120, 1, 4, 3, 2)
            case .list, .count:
                return (3, preferHistorical ? 28 : 20, 120, preferHistorical ? 18 : 12, preferHistorical ? 14 : 10, 6, 3)
            case .answer:
                return (allowWidening ? 2 : 1, preferHistorical ? 18 : 12, 180, 0, preferHistorical ? 10 : 8, 5, 3)
            case .summarize, .compare:
                return (3, preferHistorical ? 26 : 20, 180, 0, preferHistorical ? 12 : 10, 6, 4)
            }
        }()

        if focusedTypes.isEmpty {
            for type in VectorSearchService.DocumentType.allCases {
                perTypeCaps[type] = defaults.broadCap
            }
        } else {
            for type in VectorSearchService.DocumentType.allCases {
                perTypeCaps[type] = focusedTypes.contains(type) ? defaults.focusedCap : 1
            }
        }

        if retrievalMode == .exhaustive {
            for type in focusedTypes {
                perTypeCaps[type] = max(perTypeCaps[type] ?? defaults.focusedCap, defaults.focusedCap + 1)
            }
        }

        return VectorSearchService.RetrievalAdmission(
            maxSearchQueries: defaults.searchQueries,
            maxMergedResults: defaults.mergedResults,
            maxPreviewCharacters: defaults.previewChars,
            maxCanonicalRecords: defaults.canonicalRecords,
            maxEvidenceItems: defaults.evidenceItems,
            minimumAnchorMatches: minimumAnchorMatches,
            perTypeCaps: perTypeCaps
        )
    }

    private func buildRetrievalLanes(
        for query: String,
        plan: QueryPlan
    ) -> [RetrievalLane] {
        guard plan.retrievalStrategy == .multiFacet else { return [] }

        let anchorPresentation = contextPresentation(for: plan)
        let supportingPresentation: VectorSearchService.ContextPresentation = {
            switch anchorPresentation {
            case .detailed:
                return .compactTimeline
            case .compactTimeline, .latestOnly:
                return anchorPresentation
            }
        }()

        var lanes: [RetrievalLane] = [
            RetrievalLane(
                title: "Cross-Domain Anchors",
                query: query,
                documentTypes: nil,
                presentation: anchorPresentation,
                admission: makeLaneAdmission(
                    focusedTypes: nil,
                    base: plan.admission,
                    maxMergedResults: 8,
                    maxEvidenceItems: 5,
                    maxPreviewCharacters: 150,
                    maxCanonicalRecords: 8
                )
            ),
            RetrievalLane(
                title: "Timeline & Movement",
                query: "\(query) visits places locations events tasks timeline",
                documentTypes: [.visit, .location, .task],
                presentation: supportingPresentation,
                admission: makeLaneAdmission(
                    focusedTypes: [.visit, .location, .task],
                    base: plan.admission,
                    maxMergedResults: 8,
                    maxEvidenceItems: 5,
                    maxPreviewCharacters: 140,
                    maxCanonicalRecords: 8
                )
            ),
            RetrievalLane(
                title: "Spending & Purchases",
                query: "\(query) receipts purchases spending paid amounts",
                documentTypes: [.receipt],
                presentation: supportingPresentation,
                admission: makeLaneAdmission(
                    focusedTypes: [.receipt],
                    base: plan.admission,
                    maxMergedResults: 6,
                    maxEvidenceItems: 4,
                    maxPreviewCharacters: 130,
                    maxCanonicalRecords: 6
                )
            ),
            RetrievalLane(
                title: "Notes & Messages",
                query: "\(query) notes journal emails messages",
                documentTypes: [.note, .email],
                presentation: supportingPresentation,
                admission: makeLaneAdmission(
                    focusedTypes: [.note, .email],
                    base: plan.admission,
                    maxMergedResults: 6,
                    maxEvidenceItems: 4,
                    maxPreviewCharacters: 130,
                    maxCanonicalRecords: 6
                )
            )
        ]

        let lower = query.lowercased()
        let peopleSignals = [
            "birthday", "birthdays", "with", "friend", "friends", "family",
            "person", "people", "relationship", "relationships", "celebrate", "celebrated"
        ]
        if peopleSignals.contains(where: { lower.contains($0) }) {
            lanes.append(
                RetrievalLane(
                    title: "People & Relationships",
                    query: "\(query) people relationships contacts with",
                    documentTypes: [.person, .visit, .note, .receipt],
                    presentation: supportingPresentation,
                    admission: makeLaneAdmission(
                        focusedTypes: [.person, .visit, .note, .receipt],
                        base: plan.admission,
                        maxMergedResults: 6,
                        maxEvidenceItems: 4,
                        maxPreviewCharacters: 130,
                        maxCanonicalRecords: 6
                    )
                )
            )
        }

        return lanes
    }

    private func makeLaneAdmission(
        focusedTypes: [VectorSearchService.DocumentType]?,
        base: VectorSearchService.RetrievalAdmission,
        maxMergedResults: Int,
        maxEvidenceItems: Int,
        maxPreviewCharacters: Int,
        maxCanonicalRecords: Int
    ) -> VectorSearchService.RetrievalAdmission {
        let focused = Set(focusedTypes ?? [])
        var perTypeCaps: [VectorSearchService.DocumentType: Int] = [:]

        for type in VectorSearchService.DocumentType.allCases {
            if focused.isEmpty {
                perTypeCaps[type] = 2
            } else {
                perTypeCaps[type] = focused.contains(type) ? 4 : 1
            }
        }

        return VectorSearchService.RetrievalAdmission(
            maxSearchQueries: min(base.maxSearchQueries, focused.isEmpty ? 2 : 1),
            maxMergedResults: max(1, min(base.maxMergedResults, maxMergedResults)),
            maxPreviewCharacters: min(base.maxPreviewCharacters, maxPreviewCharacters),
            maxCanonicalRecords: max(1, min(base.maxCanonicalRecords, maxCanonicalRecords)),
            maxEvidenceItems: max(1, min(base.maxEvidenceItems, maxEvidenceItems)),
            minimumAnchorMatches: focused.isEmpty ? max(1, base.minimumAnchorMatches) : 1,
            perTypeCaps: perTypeCaps
        )
    }

    private func buildMultiFacetRelevantContext(
        for query: String,
        dateRange: (start: Date, end: Date)?,
        plan: QueryPlan
    ) async throws -> VectorSearchService.RelevantContextResult {
        let lanes = buildRetrievalLanes(for: query, plan: plan)
        guard !lanes.isEmpty else {
            return try await vectorSearch.getRelevantContext(
                forQuery: query,
                limit: determineSearchLimit(forQuery: query, plan: plan),
                documentTypes: plan.documentTypes,
                dateRange: dateRange,
                preferHistorical: plan.preferHistorical,
                retrievalMode: plan.retrievalMode,
                presentation: contextPresentation(for: plan),
                admission: plan.admission
            )
        }

        var sections: [String] = []
        var mergedEvidence: [RelevantContentInfo] = []
        var seenEvidenceKeys = Set<String>()

        for lane in lanes {
            let laneLimit = max(lane.admission.maxMergedResults + 2, 8)
            let result = try await vectorSearch.getRelevantContext(
                forQuery: lane.query,
                limit: laneLimit,
                documentTypes: lane.documentTypes,
                dateRange: dateRange,
                preferHistorical: plan.preferHistorical,
                retrievalMode: plan.retrievalMode,
                presentation: lane.presentation,
                admission: lane.admission
            )

            let laneEvidence = result.evidence.filter { item in
                let key = dedupKey(for: item)
                guard !seenEvidenceKeys.contains(key) else { return false }
                seenEvidenceKeys.insert(key)
                return true
            }

            guard !laneEvidence.isEmpty else { continue }

            let trimmedContext = result.context.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContext.isEmpty {
                sections.append("=== \(lane.title.uppercased()) ===\n\(trimmedContext)")
            }
            mergedEvidence.append(contentsOf: laneEvidence)
        }

        if sections.isEmpty {
            return try await vectorSearch.getRelevantContext(
                forQuery: query,
                limit: determineSearchLimit(forQuery: query, plan: plan),
                documentTypes: nil,
                dateRange: dateRange,
                preferHistorical: plan.preferHistorical,
                retrievalMode: plan.retrievalMode,
                presentation: contextPresentation(for: plan),
                admission: plan.admission
            )
        }

        return VectorSearchService.RelevantContextResult(
            context: sections.joined(separator: "\n\n"),
            evidence: mergedEvidence
        )
    }

    private func fetchRelevantContext(
        for query: String,
        dateRange: (start: Date, end: Date)?,
        plan: QueryPlan
    ) async throws -> VectorSearchService.RelevantContextResult {
        if plan.retrievalStrategy == .multiFacet {
            return try await buildMultiFacetRelevantContext(
                for: query,
                dateRange: dateRange,
                plan: plan
            )
        }

        let limit = determineSearchLimit(forQuery: query, plan: plan)
        return try await vectorSearch.getRelevantContext(
            forQuery: query,
            limit: limit,
            documentTypes: plan.documentTypes,
            dateRange: dateRange,
            preferHistorical: plan.preferHistorical,
            retrievalMode: plan.retrievalMode,
            presentation: contextPresentation(for: plan),
            admission: plan.admission
        )
    }

    private func looksLikeShortTopicalQuery(_ query: String) -> Bool {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }

        let excludedSignals = [
            "today", "yesterday", "tomorrow", "week", "weekend", "month", "year",
            "compare", "summary", "summarize", "recap", "overview", "count",
            "how many", "latest", "most recent", "newest", "birthday", "birthdays",
            "weather", "temperature", "eta", "traffic", "schedule", "scheduled"
        ]
        if excludedSignals.contains(where: { normalized.contains($0) }) {
            return false
        }

        let fillerWords: Set<String> = [
            "show", "tell", "me", "for", "about", "find", "look", "up", "the",
            "a", "an", "my", "all", "any", "and", "or", "please"
        ]

        let tokens = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let meaningfulTokens = tokens.filter { !$0.allSatisfy(\.isNumber) && !fillerWords.contains($0) }
        return !meaningfulTokens.isEmpty && meaningfulTokens.count <= 4
    }

    private func contextPresentation(for plan: QueryPlan) -> VectorSearchService.ContextPresentation {
        switch plan.operation {
        case .latest:
            return .latestOnly
        case .list, .count:
            return .compactTimeline
        case .answer, .summarize, .compare:
            return .detailed
        }
    }

    private func shouldIncludeMemoryContext(for plan: QueryPlan) -> Bool {
        switch plan.operation {
        case .list, .count, .latest:
            return false
        case .answer, .summarize, .compare:
            return true
        }
    }

    private func shouldIncludePeopleContext(forQuery query: String) -> Bool {
        let lower = query.lowercased()
        let peopleSignals = [
            "birthday", "birthdays", "person", "people", "contact", "contacts",
            "friend", "friends", "family", "relationship", "relationships",
            "who is", "who's", "whose", "upcoming birthdays"
        ]
        if peopleSignals.contains(where: { lower.contains($0) }) {
            return true
        }

        let padded = " " + lower + " "
        for person in PeopleManager.shared.people {
            let aliases = [person.name, person.nickname]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            if aliases.contains(where: { alias in
                !alias.isEmpty && padded.contains(" \(alias) ")
            }) {
                return true
            }
        }

        return false
    }

    private func shouldIncludeAmbientContext(forQuery query: String) -> Bool {
        let lower = query.lowercased()
        let ambientSignals = [
            "weather", "temperature", "rain", "snow", "outside",
            "eta", "traffic", "drive", "commute", "current location",
            "where am i", "near me", "nearby"
        ]
        return ambientSignals.contains(where: { lower.contains($0) })
    }

    private func shouldIncludeDataAvailabilitySummary(for plan: QueryPlan) -> Bool {
        switch plan.operation {
        case .summarize, .compare, .answer:
            return true
        case .list, .count, .latest:
            return false
        }
    }

    private func isStructuredHistoricalFactQuery(_ query: String) -> Bool {
        let lower = " " + query.lowercased() + " "
        let factSignals = [
            " how many times ",
            " how often ",
            " when did i go ",
            " when did i last go ",
            " last went ",
            " last visit ",
            " all the times ",
            " all times ",
            " which days ",
            " what days ",
            " how much did i spend ",
            " how much did i pay ",
            " what did i pay ",
            " who was i with ",
            " who did i spend my time with ",
            " where did i go ",
            " what other times ",
            " which other times ",
            " other visits "
        ]
        return factSignals.contains { lower.contains($0) }
    }

    private func isHistoricalQuery(query: String, dateRange: (start: Date, end: Date)? = nil) -> Bool {
        let lower = query.lowercased()
        let historicalHints = [
            "oldest", "earliest", "first time", "historical", "history",
            "years ago", "back in", "in the past", "archive"
        ]
        if historicalHints.contains(where: { lower.contains($0) }) {
            return true
        }

        if let year = extractExplicitYear(from: lower),
           year < Calendar.current.component(.year, from: Date()) {
            return true
        }

        if let dateRange {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            if dateRange.end < thirtyDaysAgo {
                return true
            }
        }

        return false
    }

    private func extractExplicitYear(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20\d{2})\b"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            let yearRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[yearRange])
    }

    // MARK: - Query Understanding (single LLM decides: date range vs vector vs clarify)

    /// Result of the query-understanding LLM: use DB for this date range, vector search, or ask for clarification.
    private enum QueryUnderstandingResult {
        case dateRange(start: Date, end: Date)
        case vectorSearch
        case clarify(question: String)
    }

    /// Cost optimization: only run query-understanding LLM when the prompt likely depends on time disambiguation.
    private func shouldUseQueryUnderstandingLLM(
        query: String,
        conversationHistory: [(role: String, content: String)]
    ) -> Bool {
        let lower = query.lowercased()

        // Entity-grounded "when did I go X with Y" is better served by semantic retrieval than date parsing.
        if lower.contains("when did i go") {
            let hasExplicitYear = lower.range(of: #"\b(19\d{2}|20\d{2})\b"#, options: .regularExpression) != nil
            let hasExplicitRelativeDate = lower.contains("today")
                || lower.contains("yesterday")
                || lower.contains("tomorrow")
                || lower.contains("weekend")
                || lower.contains("this week")
                || lower.contains("last week")
                || lower.contains("month")
                || lower.contains("year")
                || hasExplicitYear
            if !hasExplicitRelativeDate {
                return false
            }
        }

        // Explicit date/time language where DB date-range retrieval helps accuracy.
        let dateKeywords = [
            "today", "yesterday", "tomorrow", "week", "weekend", "month", "year",
            "last", "next", "ago", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]
        if dateKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.range(of: #"\bmy day\b|\bday\b"#, options: .regularExpression) != nil {
            return true
        }

        // Absolute date formats.
        if lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b(19\d{2}|20\d{2})\b"#, options: .regularExpression) != nil {
            return true
        }

        // Referential follow-ups ("that", "then", etc.) benefit from disambiguation.
        if !conversationHistory.isEmpty {
            let referenceTerms = ["that", "then", "there", "same day", "before that", "after that", "that weekend"]
            if referenceTerms.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        // General semantic questions can skip this extra LLM hop.
        return false
    }

    private struct DeterministicTemporalRange {
        let start: Date
        let end: Date
        let weekendOnly: Bool
        let reason: String
    }

    private func deterministicTemporalRangeFromTemporalService(
        for query: String,
        calendar: Calendar
    ) -> DeterministicTemporalRange? {
        let lower = query.lowercased()
        guard let extracted = TemporalUnderstandingService.shared.extractTemporalRange(from: query) else {
            return nil
        }

        let bounds = TemporalUnderstandingService.shared.normalizedBounds(for: extracted, calendar: calendar)
        guard bounds.end > bounds.start else { return nil }

        return DeterministicTemporalRange(
            start: bounds.start,
            end: bounds.end,
            weekendOnly: lower.contains("weekend"),
            reason: "temporal parser (\(extracted.description))"
        )
    }

    private func normalizedExclusiveEnd(
        for endDate: Date,
        startDate: Date,
        calendar: Calendar
    ) -> Date {
        if endDate <= startDate {
            return calendar.date(byAdding: .day, value: 1, to: startDate) ?? endDate
        }

        let startOfEndDay = calendar.startOfDay(for: endDate)
        let isMidnightBoundary = abs(endDate.timeIntervalSince(startOfEndDay)) < 1
        if isMidnightBoundary {
            return calendar.date(byAdding: .day, value: 1, to: startOfEndDay) ?? endDate
        }

        return endDate
    }

    /// Deterministic routing for explicit month/year or year-only queries.
    /// Examples handled: "any weekend in January 2026", "what happened in 2023".
    private func deterministicTemporalRange(for query: String) -> DeterministicTemporalRange? {
        let lower = query.lowercased()
        let weekendOnly = lower.contains("weekend")
        let calendar = Calendar.current

        // 0) Match explicit relative-day queries.
        let todayStart = calendar.startOfDay(for: Date())
        if lower.contains("day before yesterday") {
            if let start = calendar.date(byAdding: .day, value: -2, to: todayStart),
               let end = calendar.date(byAdding: .day, value: 1, to: start) {
                return DeterministicTemporalRange(
                    start: start,
                    end: end,
                    weekendOnly: false,
                    reason: "explicit relative-day query (day before yesterday)"
                )
            }
        } else if lower.contains("yesterday") {
            if let start = calendar.date(byAdding: .day, value: -1, to: todayStart),
               let end = calendar.date(byAdding: .day, value: 1, to: start) {
                return DeterministicTemporalRange(
                    start: start,
                    end: end,
                    weekendOnly: false,
                    reason: "explicit relative-day query (yesterday)"
                )
            }
        } else if lower.contains("today") {
            if let end = calendar.date(byAdding: .day, value: 1, to: todayStart) {
                return DeterministicTemporalRange(
                    start: todayStart,
                    end: end,
                    weekendOnly: false,
                    reason: "explicit relative-day query (today)"
                )
            }
        }

        if let parsedRange = deterministicTemporalRangeFromTemporalService(for: query, calendar: calendar) {
            return parsedRange
        }

        // 1) Match single "month year" mention (e.g., January 2026, jan 2026).
        let monthYearPattern = #"\b(?:in|of)?\s*(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\s*,?\s*(\d{4})\b"#
        if let regex = try? NSRegularExpression(pattern: monthYearPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            if matches.count == 1,
               let match = matches.first,
               let monthRange = Range(match.range(at: 1), in: lower),
               let yearRange = Range(match.range(at: 2), in: lower) {
                let monthKey = String(lower[monthRange])
                if let month = monthNameToNumber[monthKey], let year = Int(String(lower[yearRange])) {
                    var startComponents = DateComponents()
                    startComponents.calendar = calendar
                    startComponents.timeZone = TimeZone.current
                    startComponents.year = year
                    startComponents.month = month
                    startComponents.day = 1

                    if let monthStart = calendar.date(from: startComponents),
                       let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) {
                        let reason = weekendOnly
                            ? "explicit weekend-in-month query (\(monthKey) \(year))"
                            : "explicit month-year query (\(monthKey) \(year))"
                        return DeterministicTemporalRange(
                            start: calendar.startOfDay(for: monthStart),
                            end: calendar.startOfDay(for: monthEnd),
                            weekendOnly: weekendOnly,
                            reason: reason
                        )
                    }
                }
            }
        }

        // 2) Match single explicit year mention (e.g., 2023).
        let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let yearRegex = try? NSRegularExpression(pattern: yearPattern, options: []) else {
            return nil
        }
        let yearMatches = yearRegex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
        guard yearMatches.count == 1,
              let yearMatch = yearMatches.first,
              let yearRange = Range(yearMatch.range(at: 1), in: lower),
              let year = Int(String(lower[yearRange])) else {
            return nil
        }

        var startComponents = DateComponents()
        startComponents.calendar = calendar
        startComponents.timeZone = TimeZone.current
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1

        guard let yearStart = calendar.date(from: startComponents),
              let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
            return nil
        }

        return DeterministicTemporalRange(
            start: calendar.startOfDay(for: yearStart),
            end: calendar.startOfDay(for: yearEnd),
            weekendOnly: false,
            reason: "explicit year query (\(year))"
        )
    }

    private func preferredQueryUnderstandingModel(
        query: String,
        conversationHistory: [(role: String, content: String)]
    ) -> String {
        let history = conversationHistory.suffix(6).map { $0.content }.joined(separator: " ")
        let lower = "\(query) \(history)".lowercased()
        let advancedSignals = [
            "which weekend", "what weekend", "that weekend", "weekend before",
            "last last weekend", "breakdown of that", "same weekend",
            "when did i go", "trip", "stay", "versus", "compare"
        ]
        if advancedSignals.contains(where: { lower.contains($0) }) {
            return "gemini-2.5-flash"
        }
        return "gemini-2.0-flash"
    }

    private func shouldFallbackFromClarifyToVectorSearch(query: String) -> Bool {
        let lower = query.lowercased()
        let stopWords: Set<String> = [
            "what", "when", "where", "who", "how", "show", "me", "the", "a", "an", "is", "it", "was",
            "i", "we", "you", "my", "our", "with", "at", "in", "on", "of", "for", "to", "and", "or",
            "weekend", "weekends", "that", "this", "last", "next", "trip", "stay", "breakdown", "spent",
            "which", "did", "her", "his", "their", "birthday"
        ]
        let tokens = uniqueTokens(in: lower, stopWords: stopWords)
        if tokens.count >= 2 {
            return true
        }
        if lower.contains("when did") || lower.contains("where did") || lower.contains("what day") {
            return true
        }
        return false
    }

    private struct WeekendInferenceCandidate {
        let date: Date
        let title: String
        let score: Double
        let matchedTokens: [String]
    }

    /// Resolve weekend queries with stronger confidence checks so we do not pin the wrong weekend.
    /// Uses semantic candidates first, then task fallback.
    private func inferWeekendRangeFromLocalData(
        for query: String,
        conversationHistory: [(role: String, content: String)]
    ) async -> DeterministicTemporalRange? {
        let lower = query.lowercased()
        guard lower.contains("weekend") else { return nil }

        let hasReferentialLanguage = lower.contains("that weekend")
            || lower.contains("that trip")
            || lower.contains("that stay")
            || lower.contains("breakdown of that")
            || lower.contains("same weekend")
        let asksForSpecificWeekend = lower.contains("which weekend")
            || lower.contains("what weekend")
            || lower.contains("when did")

        // Only run this deterministic path for referential weekend follow-ups or explicit "which/what weekend" lookups.
        guard hasReferentialLanguage || asksForSpecificWeekend else { return nil }

        var anchorText = lower
        if hasReferentialLanguage {
            let historyText = conversationHistory.suffix(8).map { $0.content.lowercased() }.joined(separator: " ")
            anchorText += " " + historyText
        }

        let stopWords: Set<String> = [
            "what", "when", "where", "who", "how", "show", "me", "the", "a", "an", "is", "it", "was",
            "i", "we", "you", "my", "our", "with", "at", "in", "on", "of", "for", "to", "and", "or",
            "weekend", "weekends", "that", "this", "last", "next", "trip", "stay", "breakdown", "spent",
            "which", "did", "her", "his", "their", "birthday"
        ]

        let queryTokens = uniqueTokens(in: lower, stopWords: stopWords)
        let anchorTokens = uniqueTokens(in: anchorText, stopWords: stopWords)
        let requiredTokens = queryTokens.isEmpty ? Array(anchorTokens.prefix(8)) : queryTokens
        guard !requiredTokens.isEmpty else { return nil }

        if let semanticCandidate = await bestWeekendCandidateFromSemanticSearch(
            query: anchorText,
            requiredTokens: requiredTokens,
            strictMode: !hasReferentialLanguage
        ) {
            if let weekendRange = weekendRange(for: semanticCandidate.date) {
                return DeterministicTemporalRange(
                    start: weekendRange.start,
                    end: weekendRange.end,
                    weekendOnly: true,
                    reason: "semantic weekend inference via '\(semanticCandidate.title)' (tokens: \(semanticCandidate.matchedTokens.joined(separator: ", ")))"
                )
            }
        }

        // Fallback: task-based anchor lookup with a rare-token gate so person-only matches don't override place anchors.
        let tasks = TaskManager.shared.getAllTasksIncludingArchived().filter { !$0.isDeleted }
        guard !tasks.isEmpty else { return nil }

        var tokenFrequency: [String: Int] = [:]
        for token in requiredTokens {
            tokenFrequency[token] = tasks.reduce(into: 0) { partial, task in
                let searchable = "\(task.title) \(task.description ?? "") \(task.location ?? "")".lowercased()
                if searchable.contains(token) { partial += 1 }
            }
        }
        let rarestRequiredToken = tokenFrequency
            .filter { $0.value > 0 }
            .min(by: { lhs, rhs in lhs.value < rhs.value })?
            .key

        var bestMatch: (task: TaskItem, score: Int, date: Date, matched: [String])?

        for task in tasks {
            let taskDate = task.scheduledTime ?? task.targetDate ?? task.createdAt
            let searchable = "\(task.title) \(task.description ?? "") \(task.location ?? "")".lowercased()
            let matchedTokens = requiredTokens.filter { searchable.contains($0) }
            guard !matchedTokens.isEmpty else { continue }

            if !hasReferentialLanguage, let rarestRequiredToken, !matchedTokens.contains(rarestRequiredToken) {
                continue
            }

            let score = matchedTokens.count
            if let currentBest = bestMatch {
                if score > currentBest.score || (score == currentBest.score && taskDate > currentBest.date) {
                    bestMatch = (task, score, taskDate, matchedTokens)
                }
            } else {
                bestMatch = (task, score, taskDate, matchedTokens)
            }
        }

        guard let best = bestMatch else { return nil }
        guard hasReferentialLanguage || best.score >= max(1, min(2, requiredTokens.count)) else { return nil }

        if let weekendRange = weekendRange(for: best.date) {
            return DeterministicTemporalRange(
                start: weekendRange.start,
                end: weekendRange.end,
                weekendOnly: true,
                reason: "context-anchored weekend via event '\(best.task.title)' (tokens: \(best.matched.joined(separator: ", ")))"
            )
        }
        return nil
    }

    private func uniqueTokens(in text: String, stopWords: Set<String>) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        for token in tokens where !seen.contains(token) {
            seen.insert(token)
            ordered.append(token)
        }
        return ordered
    }

    private func bestWeekendCandidateFromSemanticSearch(
        query: String,
        requiredTokens: [String],
        strictMode: Bool
    ) async -> WeekendInferenceCandidate? {
        do {
            let results = try await vectorSearch.search(query: query, limit: 25)
            guard !results.isEmpty else { return nil }

            struct RawCandidate {
                let date: Date
                let title: String
                let similarity: Float
                let type: VectorSearchService.DocumentType
                let searchableText: String
                let matchedTokens: [String]
            }

            var rawCandidates: [RawCandidate] = []
            for result in results {
                guard let date = weekendInferenceDate(from: result) else { continue }
                let searchableText = buildSearchableText(for: result)
                let matchedTokens = requiredTokens.filter { searchableText.contains($0) }
                guard !matchedTokens.isEmpty else { continue }
                rawCandidates.append(
                    RawCandidate(
                        date: date,
                        title: result.title ?? result.documentType.displayName,
                        similarity: result.similarity,
                        type: result.documentType,
                        searchableText: searchableText,
                        matchedTokens: matchedTokens
                    )
                )
            }

            guard !rawCandidates.isEmpty else { return nil }

            var tokenDocumentFrequency: [String: Int] = [:]
            for token in requiredTokens {
                tokenDocumentFrequency[token] = rawCandidates.reduce(into: 0) { partial, candidate in
                    if candidate.searchableText.contains(token) { partial += 1 }
                }
            }

            let rarestRequiredToken = tokenDocumentFrequency
                .filter { $0.value > 0 }
                .min(by: { lhs, rhs in lhs.value < rhs.value })?
                .key

            var bestCandidate: WeekendInferenceCandidate?
            for candidate in rawCandidates {
                if strictMode, let rarestRequiredToken, !candidate.matchedTokens.contains(rarestRequiredToken) {
                    continue
                }

                let tokenScore = candidate.matchedTokens.reduce(into: 0.0) { partial, token in
                    let frequency = max(1, tokenDocumentFrequency[token] ?? 1)
                    partial += 1.0 / Double(frequency)
                }

                let typeBoost: Double
                switch candidate.type {
                case .task: typeBoost = 0.22
                case .visit: typeBoost = 0.16
                case .email: typeBoost = 0.14
                case .receipt: typeBoost = 0.08
                case .note: typeBoost = 0.06
                case .location: typeBoost = 0.03
                case .person: typeBoost = 0.0
                }

                let combinedScore = (Double(candidate.similarity) * 0.65) + (tokenScore * 0.30) + typeBoost
                let inferred = WeekendInferenceCandidate(
                    date: candidate.date,
                    title: candidate.title,
                    score: combinedScore,
                    matchedTokens: candidate.matchedTokens
                )

                if let currentBest = bestCandidate {
                    if inferred.score > currentBest.score {
                        bestCandidate = inferred
                    }
                } else {
                    bestCandidate = inferred
                }
            }

            guard let bestCandidate else { return nil }
            let minimumScore = strictMode ? 0.45 : 0.35
            guard bestCandidate.score >= minimumScore else { return nil }
            return bestCandidate
        } catch {
            print("⚠️ Semantic weekend inference failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func weekendInferenceDate(from result: VectorSearchService.SearchResult) -> Date? {
        switch result.documentType {
        case .task:
            return parseDate(from: result.metadata, keys: ["start", "scheduled_time", "target_date", "date", "created_at"])
        case .visit:
            return parseDate(from: result.metadata, keys: ["entry_time", "date", "created_at"])
        case .email:
            return parseDate(from: result.metadata, keys: ["date", "created_at"])
        case .receipt, .note:
            return parseDate(from: result.metadata, keys: ["date", "created_at"])
        case .location, .person:
            return parseDate(from: result.metadata, keys: ["date", "created_at"])
        }
    }

    private func parseDate(from metadata: [String: Any]?, keys: [String]) -> Date? {
        guard let metadata else { return nil }
        for key in keys {
            guard let rawValue = metadata[key] as? String, !rawValue.isEmpty else { continue }
            if let parsed = parseDate(rawValue) {
                return parsed
            }
        }
        return nil
    }

    private func parseDate(_ value: String) -> Date? {
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

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.timeZone = TimeZone.current
        return fallback.date(from: value)
    }

    private func weekendRange(for date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1=Sun ... 7=Sat
        let daysBackToSaturday = weekday == 7 ? 0 : (weekday == 1 ? 1 : weekday)
        guard
            let weekendStart = calendar.date(byAdding: .day, value: -daysBackToSaturday, to: day),
            let weekendEnd = calendar.date(byAdding: .day, value: 2, to: weekendStart)
        else {
            return nil
        }
        return (start: calendar.startOfDay(for: weekendStart), end: calendar.startOfDay(for: weekendEnd))
    }

    private func buildSearchableText(for result: VectorSearchService.SearchResult) -> String {
        var fragments: [String] = []
        if let title = result.title {
            fragments.append(title)
        }
        fragments.append(result.content)
        if let metadata = result.metadata {
            for (key, value) in metadata {
                fragments.append("\(key) \(String(describing: value))")
            }
        }
        return fragments.joined(separator: " ").lowercased()
    }

    private func buildEntityConstrainedSemanticContext(
        query: String,
        conversationHistory: [(role: String, content: String)],
        dateRange: (start: Date, end: Date)?,
        documentTypes: [VectorSearchService.DocumentType]? = nil,
        retrievalMode: VectorSearchService.RetrievalMode = .topK,
        admission: VectorSearchService.RetrievalAdmission
    ) async -> (context: String, evidence: [RelevantContentInfo]) {
        let stopWords: Set<String> = [
            "what", "when", "where", "who", "how", "show", "me", "the", "a", "an", "is", "it", "was",
            "i", "we", "you", "my", "our", "with", "at", "in", "on", "of", "for", "to", "and", "or",
            "weekend", "weekends", "that", "this", "last", "next", "trip", "stay", "breakdown", "spent",
            "which", "did", "her", "his", "their", "birthday"
        ]

        let queryTokens = uniqueTokens(in: query.lowercased(), stopWords: stopWords)
        let isReferential = query.lowercased().contains("that weekend")
            || query.lowercased().contains("that trip")
            || query.lowercased().contains("that stay")
            || query.lowercased().contains("same weekend")

        var anchorTokens = queryTokens
        if isReferential || queryTokens.count < 2 {
            let historyText = conversationHistory.suffix(8).map { $0.content }.joined(separator: " ").lowercased()
            let historyTokens = uniqueTokens(in: historyText, stopWords: stopWords)
            for token in historyTokens where !anchorTokens.contains(token) {
                anchorTokens.append(token)
            }
        }

        let anchors = Array(anchorTokens.prefix(6))
        guard anchors.count >= 2 else { return ("", []) }

        do {
            let candidates = try await vectorSearch.search(
                query: query,
                documentTypes: documentTypes,
                limit: min(max(admission.maxMergedResults, 12), 30),
                dateRange: dateRange,
                retrievalMode: retrievalMode,
                admission: admission
            )
            guard !candidates.isEmpty else { return ("", []) }

            var tokenFrequency: [String: Int] = [:]
            for token in anchors {
                tokenFrequency[token] = candidates.reduce(into: 0) { partial, candidate in
                    if buildSearchableText(for: candidate).contains(token) {
                        partial += 1
                    }
                }
            }
            let rarestAnchor = tokenFrequency
                .filter { $0.value > 0 }
                .min(by: { lhs, rhs in lhs.value < rhs.value })?
                .key

            let matched: [(result: VectorSearchService.SearchResult, matchedTokens: [String])] = candidates.compactMap { result in
                let searchable = buildSearchableText(for: result)
                let matchedTokens = anchors.filter { searchable.contains($0) }
                guard matchedTokens.count >= 2 else { return nil }
                if let rarestAnchor, !matchedTokens.contains(rarestAnchor) {
                    return nil
                }
                return (result, matchedTokens)
            }

            guard !matched.isEmpty else { return ("", []) }

            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            let limited = Array(matched.prefix(max(4, admission.maxEvidenceItems)))

            var context = "=== QUERY-FOCUSED MATCHES (ENTITY-CONSTRAINED) ===\n"
            context += "Anchors: \(anchors.joined(separator: ", "))\n"
            context += "Only items matching at least 2 anchors are listed.\n\n"
            var evidence: [RelevantContentInfo] = []
            var seenEvidenceKeys = Set<String>()
            for item in limited {
                let title = item.result.title ?? item.result.documentType.displayName
                let similarity = Int(item.result.similarity * 100)
                let dateLabel: String
                if let date = weekendInferenceDate(from: item.result) {
                    dateLabel = df.string(from: date)
                } else {
                    dateLabel = "Unknown date"
                }
                let snippet = item.result.content
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                context += "- [\(similarity)%] \(item.result.documentType.displayName): \(title) • \(dateLabel) • matched: \(item.matchedTokens.joined(separator: ", "))\n"
                if !snippet.isEmpty {
                    context += "  - \(snippet.prefix(admission.maxPreviewCharacters))\n"
                }

                if let mapped = vectorSearch.evidenceItem(from: item.result) {
                    let key = dedupKey(for: mapped)
                    if !seenEvidenceKeys.contains(key), evidence.count < admission.maxEvidenceItems {
                        seenEvidenceKeys.insert(key)
                        evidence.append(mapped)
                    }
                }
            }
            context += "\n"
            return (context, evidence)
        } catch {
            print("⚠️ Entity-constrained semantic context failed: \(error.localizedDescription)")
            return ("", [])
        }
    }

    private func dedupKey(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email:
            return "email::\(item.emailId ?? item.id.uuidString)"
        case .note:
            return "note::\(item.noteId?.uuidString ?? item.id.uuidString)"
        case .receipt:
            return "receipt::\(item.receiptId?.uuidString ?? item.id.uuidString)"
        case .event:
            return "event::\(item.eventId?.uuidString ?? item.id.uuidString)"
        case .location:
            return "location::\(item.locationId?.uuidString ?? item.id.uuidString)"
        case .visit:
            return "visit::\(item.visitId?.uuidString ?? item.id.uuidString)"
        case .person:
            return "person::\(item.personId?.uuidString ?? item.id.uuidString)"
        }
    }

    private func buildWeekendOnlyCompletenessContext(dateRange: (start: Date, end: Date)) async -> String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .full
        dayFormatter.timeStyle = .none

        var context = "\n=== COMPLETE WEEKEND DATA ===\n"
        let lastDay = calendar.date(byAdding: .day, value: -1, to: dateRange.end) ?? dateRange.end
        context += "Date range: \(dayFormatter.string(from: dateRange.start)) – \(dayFormatter.string(from: lastDay))\n"
        context += "Only Saturday/Sunday data is included for this query.\n\n"

        var cursor = dateRange.start
        var weekendCount = 0

        while cursor < dateRange.end {
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun ... 7=Sat
            if weekday == 1 || weekday == 7 {
                let weekendStart: Date
                let weekendEnd: Date

                if weekday == 7 {
                    weekendStart = cursor
                    weekendEnd = min(
                        dateRange.end,
                        calendar.date(byAdding: .day, value: 2, to: weekendStart) ?? dateRange.end
                    )
                } else {
                    let previousSaturday = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                    if previousSaturday >= dateRange.start {
                        weekendStart = previousSaturday
                        weekendEnd = min(
                            dateRange.end,
                            calendar.date(byAdding: .day, value: 2, to: weekendStart) ?? dateRange.end
                        )
                    } else {
                        // Range starts on Sunday; include just that in-range day.
                        weekendStart = cursor
                        weekendEnd = min(
                            dateRange.end,
                            calendar.date(byAdding: .day, value: 1, to: weekendStart) ?? dateRange.end
                        )
                    }
                }

                weekendCount += 1
                context += "=== WEEKEND \(weekendCount) (\(dayFormatter.string(from: weekendStart))) ===\n"
                context += await buildDayCompletenessContext(dateRange: (start: weekendStart, end: weekendEnd))
                context += "\n"

                cursor = weekendEnd
                continue
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? dateRange.end
        }

        if weekendCount == 0 {
            context += "(No weekend dates in this range)\n"
        }

        return context
    }

    /// Single LLM call: decide if the query is about a specific date/range (→ DB), general (→ vector), or vague (→ clarify).
    /// Uses conversation history to resolve "that", "last weekend", "last last weekend", etc. No pattern list.
    private func understandQuery(query: String, conversationHistory: [(role: String, content: String)]) async -> QueryUnderstandingResult {
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: todayStart)

        // Compute "last weekend" and "weekend before that" so the model has exact reference dates
        var referenceBlock = ""
        let weekday = calendar.component(.weekday, from: todayStart) // 1=Sun ... 7=Sat
        let daysBackToSaturday = weekday == 7 ? 0 : (weekday == 1 ? 1 : weekday)
        let isActiveWeekend = weekday == 1 || weekday == 7
        if let mostRecentSaturday = calendar.date(byAdding: .day, value: -daysBackToSaturday, to: todayStart),
           let lastWeekendStart = calendar.date(byAdding: .day, value: isActiveWeekend ? -7 : 0, to: mostRecentSaturday),
           let lastWeekendEnd = calendar.date(byAdding: .day, value: 2, to: lastWeekendStart),
           let weekendBeforeStart = calendar.date(byAdding: .day, value: -7, to: lastWeekendStart),
           let weekendBeforeEnd = calendar.date(byAdding: .day, value: 2, to: weekendBeforeStart) {
            let lastWeekendStartStr = df.string(from: lastWeekendStart)
            let lastWeekendEndStr = df.string(from: lastWeekendEnd)
            let weekendBeforeStartStr = df.string(from: weekendBeforeStart)
            let weekendBeforeEndStr = df.string(from: weekendBeforeEnd)
            referenceBlock = "\nReference (use these exact dates): \"Last weekend\" = \(lastWeekendStartStr) to \(lastWeekendEndStr) (output START: \(lastWeekendStartStr), END: \(lastWeekendEndStr)). \"Last last weekend\" or \"the weekend before that\" = \(weekendBeforeStartStr) to \(weekendBeforeEndStr) (output START: \(weekendBeforeStartStr), END: \(weekendBeforeEndStr)).\n\n"
        }

        let recentTurns = conversationHistory.suffix(6)
        let historyBlock = recentTurns.isEmpty ? "" : """
            Recent conversation (use this to resolve references like "that", "last weekend", "the weekend before that"):
            \(recentTurns.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))

            """

        let prompt = """
            Today's date is \(todayStr). User's message: "\(query)"

            \(historyBlock)\(referenceBlock)Decide what the user is asking for. Respond with EXACTLY one of these (no other text):

            1) If they are asking about a SPECIFIC day or date range (e.g. "how was my day yesterday", "what did I do last weekend", "last last weekend", "the weekend before that", "two weeks ago"), output the date range:
            START: YYYY-MM-DD
            END: YYYY-MM-DD
            (START = first day inclusive, END = day after last day. For a single day, END = next day. For a weekend Sat–Sun, END = Monday.)

            2) If they are asking something general with NO specific date (e.g. "where do I go most", "summarize my spending", "my top locations"), output:
            NONE

            3) If the request is too vague even with the conversation and you cannot infer what they mean, output:
            CLARIFY: <one short clarifying question>

            Respond with ONLY the chosen option (START/END lines, or NONE, or CLARIFY: ...).
            """

        do {
            let queryUnderstandingModel = preferredQueryUnderstandingModel(
                query: query,
                conversationHistory: conversationHistory
            )
            let response = try await GeminiService.shared.simpleChatCompletion(
                systemPrompt: "You are a query understanding assistant. Output only START/END, NONE, or CLARIFY: as instructed. Use the conversation to resolve time references like 'that' or 'last last weekend'.",
                messages: [["role": "user", "content": prompt]],
                model: queryUnderstandingModel,
                operationType: "query_understanding"
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // CLARIFY
            if trimmed.uppercased().hasPrefix("CLARIFY:") {
                let question = trimmed.dropFirst("CLARIFY:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty {
                    print("📅 Query understanding: CLARIFY - \(question.prefix(60))...")
                    return .clarify(question: question)
                }
            }

            // NONE → vector search
            if trimmed.uppercased().contains("NONE") {
                print("📅 Query understanding: NONE (vector search)")
                return .vectorSearch
            }

            // Parse START/END dates
            let datePattern = #"\d{4}-\d{2}-\d{2}"#
            guard let regex = try? NSRegularExpression(pattern: datePattern) else {
                print("📅 Query understanding: parse failed, falling back to vector search")
                return .vectorSearch
            }
            let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            let dates = matches.compactMap { match -> Date? in
                guard let range = Range(match.range, in: trimmed) else { return nil }
                return df.date(from: String(trimmed[range]))
            }.map { calendar.startOfDay(for: $0) }

            guard let startDate = dates.first else {
                print("📅 Query understanding: no dates in response, falling back to vector search")
                return .vectorSearch
            }
            let endDate: Date = dates.count > 1 ? dates[1] : calendar.date(byAdding: .day, value: 1, to: startDate)!
            print("📅 Query understanding: DATE RANGE \(startDate) to \(endDate)")
            return .dateRange(start: startDate, end: endDate)
        } catch {
            print("⚠️ Query understanding failed: \(error), falling back to vector search")
            return .vectorSearch
        }
    }

    // MARK: - Main Context Building
    // Uses a small generic retrieval plan for query semantics (top-K vs exhaustive) while
    // still relying on semantic search instead of domain-specific routing tables.

    /// Build optimized context for LLM using vector search
    /// This is the main replacement for buildContextPrompt(forQuery:)
    /// CACHING OPTIMIZATION: Context is structured for Gemini 2.5 implicit caching
    /// - Static content (system instructions, schema) goes FIRST
    /// - Variable content (user query, search results) goes LAST
    /// - This enables 75% discount on cached tokens automatically
    func buildContext(forQuery query: String, conversationHistory: [(role: String, content: String)] = []) async -> ContextResult {
        let startTime = Date()

        var context = ""
        var metadata = ContextMetadata()
        var evidence: [RelevantContentInfo] = []
        let initialQueryPlan = buildQueryPlan(for: query)

        // 1. STATIC: Essential context (optimized for caching - date only, no time)
        context += buildEssentialContext(forQuery: query, plan: initialQueryPlan)
        
        // 2. Add user memory context (learned preferences, entity relationships, etc.)
        if shouldIncludeMemoryContext(for: initialQueryPlan) {
            let memoryContext = await UserMemoryService.shared.getMemoryContext()
            if !memoryContext.isEmpty {
                context += memoryContext
            }
        }

        // 3. Query routing: deterministic temporal parsing first, then LLM understanding.
        var understanding: QueryUnderstandingResult
        var useWeekendOnlyCompleteness = false

        if let forcedRange = deterministicTemporalRange(for: query) {
            understanding = .dateRange(start: forcedRange.start, end: forcedRange.end)
            useWeekendOnlyCompleteness = forcedRange.weekendOnly
            print("📅 Deterministic query understanding: \(forcedRange.reason) → DATE RANGE \(forcedRange.start) to \(forcedRange.end)")
        } else if shouldUseQueryUnderstandingLLM(query: query, conversationHistory: conversationHistory) {
            print("🔍 Query understanding...")
            understanding = await understandQuery(query: query, conversationHistory: conversationHistory)
        } else {
            print("🔍 Query understanding skipped (general query) → vector search")
            understanding = .vectorSearch
        }

        // Guardrail: if LLM returned NONE for a clearly explicit month-year query, force deterministic date range.
        if case .vectorSearch = understanding,
           let fallbackRange = deterministicTemporalRange(for: query) {
            understanding = .dateRange(start: fallbackRange.start, end: fallbackRange.end)
            useWeekendOnlyCompleteness = fallbackRange.weekendOnly
            print("📅 Guardrail routing: LLM returned NONE for explicit temporal query; forcing DATE RANGE \(fallbackRange.start) to \(fallbackRange.end)")
        }

        // Guardrail: if the parser asks for clarification on a concrete entity query, continue with vector retrieval.
        if case .clarify = understanding,
           shouldFallbackFromClarifyToVectorSearch(query: query) {
            understanding = .vectorSearch
            print("📅 Guardrail routing: CLARIFY for concrete query → vector search fallback")
        }

        switch understanding {
        case .clarify(let question):
            context += "\n=== CLARIFICATION NEEDED ===\n"
            context += question + "\n"
            metadata.estimatedTokens = estimateTokenCount(context)
            metadata.buildTime = Date().timeIntervalSince(startTime)
            return ContextResult(context: context, metadata: metadata, evidence: [])

        case .dateRange(let start, let end):
            let dateRange = (start: start, end: end)
            let queryLower = query.lowercased()
            let isComparison = queryLower.contains("compare") || queryLower.contains(" vs ") || queryLower.contains(" versus ") || queryLower.contains("compared to")
            let queryPlan = buildQueryPlan(for: query, dateRange: dateRange)
            let presentation = contextPresentation(for: queryPlan)
            let domainLabel = queryPlan.documentTypes?.map(\.rawValue).sorted().joined(separator: ",") ?? "all"
            print("🧭 Query plan: operation=\(queryPlan.operation.rawValue) strategy=\(queryPlan.retrievalStrategy.rawValue) retrieval=\(queryPlan.retrievalMode.rawValue) historical=\(queryPlan.preferHistorical) domains=\(domainLabel) widen=\(queryPlan.allowWidening)")
            let daySpan = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            let shouldUseCompleteDayData = daySpan > 0 && daySpan <= 45

            if !shouldUseCompleteDayData {
                print("📅 Large date range (\(daySpan) days) - using vector retrieval instead of complete day expansion")
            }

            // When user asks to "compare to last week" (or similar), also fetch this week so the model has both periods
            if isComparison && shouldUseCompleteDayData {
                let calendar = Calendar.current
                let today = Date()
                let todayStart = calendar.startOfDay(for: today)
                let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                let requestedRangeIsPast = end <= tomorrowStart
                if requestedRangeIsPast {
                    let weekday = calendar.component(.weekday, from: today)
                    let daysSinceMonday = (weekday == 1) ? 6 : (weekday - 2)
                    if let thisWeekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: todayStart) {
                        let thisWeekEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                        let baselineRange = (start: thisWeekStart, end: thisWeekEnd)
                        let baselineContext = await buildDayCompletenessContext(dateRange: baselineRange)
                        if !baselineContext.isEmpty {
                            context += "\n=== PERIOD TO COMPARE AGAINST (This week) ===\n"
                            context += baselineContext
                            metadata.usedCompleteDayData = true
                            print("✅ Added comparison baseline period (this week)")
                        }
                    }
                }
            }

            do {
                if shouldUseCompleteDayData {
                    let dayContext = useWeekendOnlyCompleteness
                        ? await buildWeekendOnlyCompletenessContext(dateRange: dateRange)
                        : await buildDayCompletenessContext(dateRange: dateRange)
                    if !dayContext.isEmpty {
                        if isComparison {
                            context += "\n=== OTHER PERIOD (Requested range, e.g. last week) ===\n"
                        }
                        context += "\n" + dayContext
                        metadata.usedCompleteDayData = true
                        print("✅ Found complete day data via direct DB query")

                        if queryPlan.retrievalStrategy == .focused
                            && queryPlan.allowWidening
                            && presentation == .detailed
                            && !isStructuredHistoricalFactQuery(query) {
                            let constrainedSemantic = await buildEntityConstrainedSemanticContext(
                                query: query,
                                conversationHistory: conversationHistory,
                                dateRange: dateRange,
                                documentTypes: queryPlan.documentTypes,
                                retrievalMode: queryPlan.retrievalMode,
                                admission: queryPlan.admission
                            )
                            if !constrainedSemantic.context.isEmpty {
                                context += "\n" + constrainedSemantic.context
                                evidence.append(contentsOf: constrainedSemantic.evidence)
                                metadata.usedVectorSearch = true
                                print("✅ Added entity-constrained semantic matches for date-range query")
                            }
                        } else {
                            print("⚡️ Skipping redundant semantic enrichment for structured historical fact query")
                        }
                    } else {
                        print("⚠️ Direct DB query returned nothing, falling back to vector search")
                        let relevantContext = try await fetchRelevantContext(
                            for: query,
                            dateRange: dateRange,
                            plan: queryPlan
                        )
                        context += "\n" + relevantContext.context
                        evidence.append(contentsOf: relevantContext.evidence)
                        metadata.usedVectorSearch = true
                    }
                } else {
                    let relevantContext = try await fetchRelevantContext(
                        for: query,
                        dateRange: dateRange,
                        plan: queryPlan
                    )
                    context += "\n" + relevantContext.context
                    evidence.append(contentsOf: relevantContext.evidence)
                    metadata.usedVectorSearch = true
                }
            } catch {
                print("❌ Day completeness / vector search failed: \(error)")
                context += "\n[Search unavailable for this date range]\n"
            }

        case .vectorSearch:
            do {
                let queryPlan = buildQueryPlan(for: query)
                let presentation = contextPresentation(for: queryPlan)
                let domainLabel = queryPlan.documentTypes?.map(\.rawValue).sorted().joined(separator: ",") ?? "all"
                print("🧭 Query plan: operation=\(queryPlan.operation.rawValue) strategy=\(queryPlan.retrievalStrategy.rawValue) retrieval=\(queryPlan.retrievalMode.rawValue) historical=\(queryPlan.preferHistorical) domains=\(domainLabel) widen=\(queryPlan.allowWidening)")
                let limit = determineSearchLimit(forQuery: query, plan: queryPlan)
                let relevantContext = try await fetchRelevantContext(
                    for: query,
                    dateRange: nil,
                    plan: queryPlan
                )
                if !relevantContext.context.isEmpty {
                    context += "\n" + relevantContext.context
                    evidence.append(contentsOf: relevantContext.evidence)
                    metadata.usedVectorSearch = true
                    // Only broaden retrieval for explicitly broad or historical queries.
                    let shouldRunCompactSecondPass = queryPlan.retrievalStrategy == .focused
                        && queryPlan.allowWidening
                        && presentation != .detailed
                        && relevantContext.evidence.count < min(4, queryPlan.admission.maxEvidenceItems)
                    if queryPlan.retrievalStrategy == .focused
                        && queryPlan.allowWidening
                        && (((presentation == .detailed && shouldRunExpandedSecondPass(forQuery: query, plan: queryPlan))
                            || shouldRunCompactSecondPass))
                        && relevantContext.context.count < 1800 {
                        let secondLimit: Int = {
                            switch (queryPlan.retrievalMode, queryPlan.preferHistorical) {
                            case (.exhaustive, true):
                                return min(limit + 20, 90)
                            case (.exhaustive, false):
                                return min(limit + 15, 70)
                            case (.topK, true):
                                return min(limit + 25, 120)
                            case (.topK, false):
                                return min(limit + 15, 50)
                            }
                        }()
                        let secondContext = try await vectorSearch.getRelevantContext(
                            forQuery: query,
                            limit: secondLimit,
                            documentTypes: queryPlan.documentTypes,
                            dateRange: nil,
                            preferHistorical: queryPlan.preferHistorical,
                            retrievalMode: queryPlan.retrievalMode,
                            presentation: presentation,
                            admission: queryPlan.admission
                        )
                        if !secondContext.context.isEmpty && secondContext.context != relevantContext.context {
                            context += "\n\n=== ADDITIONAL RELEVANT DATA (second pass) ===\n"
                            context += secondContext.context
                            evidence.append(contentsOf: secondContext.evidence)
                        }
                    }

                    if queryPlan.retrievalStrategy == .focused && queryPlan.allowWidening && presentation == .detailed {
                        let constrainedSemantic = await buildEntityConstrainedSemanticContext(
                            query: query,
                            conversationHistory: conversationHistory,
                            dateRange: nil,
                            documentTypes: queryPlan.documentTypes,
                            retrievalMode: queryPlan.retrievalMode,
                            admission: queryPlan.admission
                        )
                        if !constrainedSemantic.context.isEmpty {
                            context += "\n" + constrainedSemantic.context
                            evidence.append(contentsOf: constrainedSemantic.evidence)
                        }
                    }
                } else {
                    context += "\n[No relevant data found for this query]\n"
                }
            } catch {
                print("❌ Vector search failed: \(error)")
                context += "\n[Search unavailable - using minimal context]\n"
            }
        }
        
        // 5. Calculate token estimate
        metadata.estimatedTokens = estimateTokenCount(context)
        metadata.buildTime = Date().timeIntervalSince(startTime)
        let dedupedEvidence = deduplicateEvidence(evidence)

        print("📊 Context built: ~\(metadata.estimatedTokens) tokens in \(String(format: "%.2f", metadata.buildTime))s")

        // DEBUG: Log context structure
        #if DEBUG
        if ProcessInfo.processInfo.environment["DEBUG_CONTEXT_TYPE"] != nil {
            print("📊 CONTEXT STRUCTURE:")
            print("  - Query Planning: \(!metadata.usedVectorSearch && metadata.usedCompleteDayData)")
            print("  - Vector Search Fallback: \(metadata.usedVectorSearch)")
            print("  - Estimated Tokens: \(metadata.estimatedTokens)")
        }
        #endif

        return ContextResult(context: context, metadata: metadata, evidence: dedupedEvidence)
    }

    /// Build compact context for voice mode (even smaller)
    func buildVoiceContext(forQuery query: String, conversationHistory: [(role: String, content: String)] = []) async -> String {
        // Backwards-compatible API: voice mode now uses the SAME context as chat mode.
        // (Response concision is handled by the voice-mode system prompt, not by hiding data.)
        let result = await buildContext(forQuery: query, conversationHistory: conversationHistory)
        return result.context
    }
    
    // MARK: - Essential Context
    
    /// Build essential context that's always included
    /// OPTIMIZATION: This is structured for Gemini 2.5 implicit caching (75% discount on cached tokens)
    /// Keep this stable across requests - avoid including frequently changing data like current time
    private func buildEssentialContext(forQuery query: String, plan: QueryPlan) -> String {
        var context = ""
        let includeAmbientContext = shouldIncludeAmbientContext(forQuery: query)
        let includePeopleContext = shouldIncludePeopleContext(forQuery: query)
        let includeDataSummary = shouldIncludeDataAvailabilitySummary(for: plan)

        // Current date (NO TIME - for cache stability)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none  // Changed from .short to .none for caching
        dateFormatter.timeZone = TimeZone.current

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        dayFormatter.timeZone = TimeZone.current

        context += "=== CURRENT DATE ===\n"
        context += "Today: \(dayFormatter.string(from: Date())), \(dateFormatter.string(from: Date()))\n"
        
        let utcOffset = TimeZone.current.secondsFromGMT() / 3600
        let utcSign = utcOffset >= 0 ? "+" : ""
        context += "Timezone: \(TimeZone.current.identifier) (UTC\(utcSign)\(utcOffset))\n\n"
        
        if includeAmbientContext {
            let locationService = LocationService.shared
            if let currentLocation = locationService.currentLocation {
                context += "=== CURRENT LOCATION ===\n"
                context += "Location: \(locationService.locationName)\n"
                context += "Coordinates: \(String(format: "%.4f", currentLocation.coordinate.latitude)), \(String(format: "%.4f", currentLocation.coordinate.longitude))\n\n"
            }

            let weatherService = WeatherService.shared
            if let weather = weatherService.weatherData {
                context += "=== CURRENT WEATHER ===\n"
                context += "Temperature: \(weather.temperature)°C\n"
                context += "Conditions: \(weather.description)\n"
                context += "Location: \(weather.locationName)\n\n"
            }
        }

        let peopleCount = PeopleManager.shared.people.count
        if includeDataSummary {
            context += "=== DATA AVAILABLE ===\n"
            context += "Events: \(TaskManager.shared.getAllTasksIncludingArchived().count)\n"
            context += "Notes: \(NotesManager.shared.notes.count)\n"
            context += "Emails: \(EmailService.shared.inboxEmails.count + EmailService.shared.sentEmails.count)\n"
            context += "Locations: \(LocationsManager.shared.savedPlaces.count)\n"
            context += "People: \(peopleCount)\n\n"
        }

        // IMPORTANT: Include complete people list with birthdays for easy lookup
        if includePeopleContext && peopleCount > 0 {
            context += "=== YOUR PEOPLE (Complete List) ===\n"
            context += "IMPORTANT: This is the ONLY source of truth for people in the app. Do NOT search the web for random people.\n\n"

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .none

            for person in PeopleManager.shared.people.sorted(by: { $0.name < $1.name }) {
                var personLine = "- \(person.name)"
                if let nickname = person.nickname {
                    personLine += " (aka \(nickname))"
                }
                personLine += " — \(person.relationshipDisplayText)"

                if let birthday = person.birthday {
                    let birthdayStr = dateFormatter.string(from: birthday)
                    personLine += " — Birthday: \(birthdayStr)"
                }

                context += personLine + "\n"
            }
            context += "\n"
        }

        
        // Critical instruction to prevent hallucination
        context += "🚨 CRITICAL INSTRUCTIONS:\n"
        context += "- ONLY use data explicitly provided in this context below.\n"
        context += "- If the context shows \"No relevant data found\", tell the user you don't have that information.\n"
        context += "- NEVER invent, fabricate, estimate, or guess data that isn't in the context.\n"
        context += "- For future-date questions, only use future events explicitly present in the context.\n"
        context += "- When in doubt, say \"I don't have that information\" instead of guessing.\n\n"
        
        return context
    }
    
    // MARK: - Date Completeness Context
    
    /// Fetch ALL items for a date range to guarantee completeness
    /// This ensures "what did I do yesterday" gets ALL visits/events/receipts, not just top-k
    private func buildDayCompletenessContext(dateRange: (start: Date, end: Date)) async -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return ""
        }
        
        let dayStart = dateRange.start
        let dayEnd = dateRange.end
        
        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateStyle = .full
        dayLabelFormatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        let isSingleDay: Bool = {
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return true }
            return nextDay >= dayEnd
        }()

        var context: String
        if isSingleDay {
            context = "\n=== COMPLETE DATA ===\n"
            context += "Date: \(dayLabelFormatter.string(from: dayStart))\n"
        } else {
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: dayEnd) ?? dayEnd
            context = "\n=== COMPLETE DATA ===\n"
            context += "Date range: \(dayLabelFormatter.string(from: dayStart)) – \(dayLabelFormatter.string(from: lastDay))\n"
        }
        context += "This is the authoritative list of ALL items for this period. Each day is labeled with its weekday and date — use the exact weekday (e.g. Monday, Sunday) when answering.\n\n"
        
        print("📊 Building day completeness context for: \(dayLabelFormatter.string(from: dayStart))")
        
        let calendar = Calendar.current
        
        // 1. Visits (source-of-truth from location_visits)
        var visitsForDay: [LocationVisitRecord] = []
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            
            // Fetch wider window to handle timezone issues
            let widenHours: TimeInterval = 12 * 60 * 60
            let fetchStart = dayStart.addingTimeInterval(-widenHours)
            let fetchEnd = dayEnd.addingTimeInterval(widenHours)
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: iso.string(from: fetchStart))
                .lt("entry_time", value: iso.string(from: fetchEnd))
                .order("entry_time", ascending: true)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let fetched: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            
            // Filter to local day window
            visitsForDay = fetched.filter { visit in
                let start = visit.entryTime
                let end = visit.exitTime ?? visit.entryTime
                return start < dayEnd && end >= dayStart
            }
            
            print("📍 Found \(visitsForDay.count) visits for range")
        } catch {
            print("⚠️ Failed to fetch visits for day: \(error)")
        }

        let visitPeopleMap = await PeopleManager.shared.getPeopleForVisits(
            visitIds: visitsForDay.map(\.id)
        )
        
        // 2. Events/Tasks (source-of-truth from TaskManager) — build list for per-day output
        var validTasks: [TaskItem] = []
        do {
            var allTasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            var iterDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            while iterDay < dayEnd {
                let moreTasks = TaskManager.shared.getTasksForDate(iterDay).filter { !$0.isDeleted }
                allTasks.append(contentsOf: moreTasks)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: iterDay) else { break }
                iterDay = nextDay
            }
            var seenIds = Set<String>()
            let tasks = allTasks.filter { task in
                if seenIds.contains(task.id) { return false }
                seenIds.insert(task.id)
                return true
            }
            validTasks = tasks.filter { task in
                if let targetDate = task.targetDate {
                    let isInRange = targetDate >= dayStart && targetDate < dayEnd
                    if !isInRange { print("⚠️ MISMATCH: Task '\(task.title)' targetDate \(targetDate) outside range \(dayStart)–\(dayEnd)") }
                    return isInRange
                }
                if let scheduledTime = task.scheduledTime {
                    let isInRange = scheduledTime >= dayStart && scheduledTime < dayEnd
                    if !isInRange { print("⚠️ MISMATCH: Task '\(task.title)' scheduledTime \(scheduledTime) outside range \(dayStart)–\(dayEnd)") }
                    return isInRange
                }
                return true
            }
            let rangeLabel = isSingleDay ? dayLabelFormatter.string(from: dayStart) : "\(dayLabelFormatter.string(from: dayStart))–\(dayLabelFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: dayEnd) ?? dayEnd))"
            print("📋 Day completeness: Found \(validTasks.count) validated events for \(rangeLabel)")
        }
        
        // 3. Receipts (source-of-truth from receipt notes) — build list for per-day output
        var receiptNotes: [(note: Note, date: Date, amount: Double, category: String)] = []
        do {
            let notesManager = NotesManager.shared
            let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

            func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
                guard let folderId else { return false }
                if folderId == receiptsFolderId { return true }
                if let folder = notesManager.folders.first(where: { $0.id == folderId }),
                   let parentId = folder.parentFolderId {
                    return isUnderReceiptsFolderHierarchy(folderId: parentId)
                }
                return false
            }

            receiptNotes = notesManager.notes
                .filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
                .compactMap { note -> (note: Note, date: Date, amount: Double, category: String)? in
                    let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                    guard date >= dayStart && date < dayEnd else { return nil }
                    let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                    let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                    return (note, date, amount, category)
                }
        }

        // 4. Emails (local cache first, Gmail API fallback) — include communication evidence for date-specific queries
        var emailsForRange = (EmailService.shared.inboxEmails + EmailService.shared.sentEmails)
            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            .sorted { $0.timestamp < $1.timestamp }

        if emailsForRange.isEmpty {
            let spanDays = max(1, Calendar.current.dateComponents([.day], from: dayStart, to: dayEnd).day ?? 1)
            if spanDays <= 14 {
                let queryFormatter = DateFormatter()
                queryFormatter.locale = Locale(identifier: "en_US_POSIX")
                queryFormatter.timeZone = TimeZone.current
                queryFormatter.dateFormat = "yyyy/MM/dd"

                let afterDate = queryFormatter.string(from: dayStart)
                let beforeDate = queryFormatter.string(from: dayEnd)
                let historicalQuery = "in:anywhere after:\(afterDate) before:\(beforeDate)"

                do {
                    let fetched = try await GmailAPIClient.shared.searchEmails(query: historicalQuery, maxResults: 80)
                    if !fetched.isEmpty {
                        emailsForRange = fetched
                            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                            .sorted { $0.timestamp < $1.timestamp }
                        print("📧 Day completeness: Pulled \(emailsForRange.count) emails from Gmail API fallback")
                    }
                } catch {
                    print("⚠️ Day completeness email fallback failed: \(error)")
                }
            }
        }
        
        // 5. Per-day blocks (weekday + date so the model reports e.g. "Monday" not "Saturday")
        var currentDay = dayStart
        while currentDay < dayEnd {
            context += "--- \(dayLabelFormatter.string(from: currentDay)) ---\n"
            let visitsOnDay = visitsForDay.filter { calendar.isDate($0.entryTime, inSameDayAs: currentDay) }
            if !visitsOnDay.isEmpty {
                context += "VISITS (\(visitsOnDay.count)):\n"
                for visit in visitsOnDay {
                    let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                    let placeName = place?.displayName ?? "Unknown Location"
                    let start = visit.entryTime
                    let end = visit.exitTime
                    let range = end != nil ? "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end!))" : "\(timeFormatter.string(from: start))–(ongoing)"
                    let duration = visit.durationMinutes.map { "\($0)m" } ?? "unknown duration"
                    let notes = (visit.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let peopleForVisit = visitPeopleMap[visit.id] ?? []
                    let peopleNames = peopleForVisit.map { $0.name }
                    var visitLine = "- \(range) • \(placeName) • \(duration)"
                    if !peopleNames.isEmpty { visitLine += " • With: \(peopleNames.joined(separator: ", "))" }
                    if !notes.isEmpty { visitLine += " • Reason: \(notes)" }
                    context += visitLine + "\n"
                }
                context += "\n"
            }
            let tagManager = TagManager.shared
            let taskDate: (TaskItem) -> Date? = { t in t.scheduledTime ?? t.targetDate ?? t.createdAt }
            let tasksOnDay = validTasks.filter { guard let d = taskDate($0) else { return false }; return calendar.isDate(d, inSameDayAs: currentDay) }
            if !tasksOnDay.isEmpty {
                context += "EVENTS/TASKS (\(tasksOnDay.count)):\n"
                for t in tasksOnDay.sorted(by: { (taskDate($0) ?? .distantPast) < (taskDate($1) ?? .distantPast) }) {
                    let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                    let timeLabel: String = {
                        if t.scheduledTime == nil, t.targetDate != nil { return "[All-day]" }
                        if let st = t.scheduledTime, let et = t.endTime {
                            let tf = DateFormatter(); tf.timeStyle = .short
                            if calendar.isDate(st, inSameDayAs: et) { return "\(tf.string(from: st)) - \(tf.string(from: et))" }
                            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
                            return "\(df.string(from: st)) → \(df.string(from: et))"
                        }
                        if let st = t.scheduledTime {
                            let tf = DateFormatter(); tf.timeStyle = .short
                            return tf.string(from: st)
                        }
                        return ""
                    }()
                    let loc = (t.location?.isEmpty == false) ? " @ \(t.location!)" : ""
                    context += "- \(timeLabel) \(t.title) — \(tagName)\(loc)\n"
                    if let desc = t.description, !desc.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        context += "  - \(desc.prefix(160))\n"
                    }
                }
                context += "\n"
            }
            let receiptsOnDay = receiptNotes.filter { calendar.isDate($0.date, inSameDayAs: currentDay) }
            if !receiptsOnDay.isEmpty {
                let total = receiptsOnDay.reduce(0.0) { $0 + $1.amount }
                context += "RECEIPTS (\(receiptsOnDay.count)) — Total $\(String(format: "%.2f", total)):\n"
                for r in receiptsOnDay.sorted(by: { $0.amount > $1.amount }) {
                    let linkedPeople = linkReceiptToPeople(
                        receipt: r,
                        visits: visitsForDay,
                        visitPeopleMap: visitPeopleMap
                    )
                    var receiptLine = "- \(r.note.title) — $\(String(format: "%.2f", r.amount)) (\(r.category))"
                    if !linkedPeople.isEmpty { receiptLine += " — With: \(linkedPeople.joined(separator: ", "))" }
                    context += receiptLine + "\n"
                }
                context += "\n"
            }
            let emailsOnDay = emailsForRange.filter { calendar.isDate($0.timestamp, inSameDayAs: currentDay) }
            if !emailsOnDay.isEmpty {
                context += "EMAILS (\(emailsOnDay.count)):\n"
                for email in emailsOnDay.prefix(20) {
                    let sender = email.sender.displayName
                    let time = timeFormatter.string(from: email.timestamp)
                    let importance = email.isImportant ? " [important]" : ""
                    let unread = email.isRead ? "" : " [unread]"
                    context += "- \(time) • \(email.subject) • From: \(sender)\(importance)\(unread)\n"
                    let snippet = email.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !snippet.isEmpty {
                        context += "  - \(snippet.prefix(160))\n"
                    }
                }
                context += "\n"
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        
        // 6. SPENDING SUMMARY - Match receipts to visits with smart connections
        do {
            // Match receipts to visits using time + location name scoring
            let receiptMatches = matchReceiptsToVisits(receipts: receiptNotes, visits: visitsForDay)
            
            // Build spending summary grouped by location
            let spendingSummary = buildSpendingSummary(
                matches: receiptMatches,
                visits: visitsForDay,
                visitPeopleMap: visitPeopleMap,
                timeFormatter: timeFormatter
            )
            if !spendingSummary.isEmpty {
                context += spendingSummary + "\n"
            }
        }

        // 7. RELATED CONTEXT - Synthesize connections across data types
        context += "RELATED CONTEXT (Smart Connections):\n"
        var hasRelatedData = false

        // Link receipts to events at same time
        for r in receiptNotes.sorted(by: { $0.amount > $1.amount }).prefix(5) {
            let receiptTime = r.date
            let allTasks = TaskManager.shared.getAllTasksIncludingArchived()
            let nearbyTasks = allTasks.filter { task in
                guard let taskTime = task.scheduledTime else { return false }
                return abs(taskTime.timeIntervalSince(receiptTime)) < 2 * 60 * 60  // Within 2 hours
            }

            if !nearbyTasks.isEmpty {
                hasRelatedData = true
                let taskNames = nearbyTasks.map { $0.title }.joined(separator: ", ")
                context += "💡 Receipt '\(r.note.title)' ($\(String(format: "%.2f", r.amount))) occurred during: \(taskNames)\n"
            }
        }

        // Link visits to receipts and events
        for visit in visitsForDay.prefix(5) {
            let visitTime = visit.entryTime
            let nearbyReceipts = receiptNotes.filter { receipt in
                abs(receipt.date.timeIntervalSince(visitTime)) < 2 * 60 * 60
            }

            if !nearbyReceipts.isEmpty {
                hasRelatedData = true
                let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                let placeName = place?.displayName ?? "Unknown Location"
                let receiptTitles = nearbyReceipts.map { $0.note.title }.joined(separator: ", ")
                context += "💡 Visit to \(placeName) had these receipts: \(receiptTitles)\n"
            }
        }

        if !hasRelatedData {
            context += "(No notable cross-connections detected for this time period)\n"
        }
        context += "\n"

        return context
    }
    
    // MARK: - Utilities

    /// Link receipts to people by finding visits within ±2 hours at same location
    private func linkReceiptToPeople(
        receipt: (note: Note, date: Date, amount: Double, category: String),
        visits: [LocationVisitRecord],
        visitPeopleMap: [UUID: [Person]]
    ) -> [String] {
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60

        // Find visits within ±2 hours of receipt time
        let nearbyVisits = visits.filter { visit in
            let timeDiff = abs(visit.entryTime.timeIntervalSince(receipt.date))
            return timeDiff <= twoHoursInSeconds
        }

        var allPeople: [String] = []
        for visit in nearbyVisits {
            let people = visitPeopleMap[visit.id] ?? []
            allPeople.append(contentsOf: people.map { $0.name })
        }

        return Array(Set(allPeople))  // Remove duplicates
    }
    
    /// Enhanced receipt-to-visit matching with time + location name scoring
    /// Matches within ±2 hours OR if receipt title contains location name (loose matching)
    private struct ReceiptVisitMatch {
        let receipt: (note: Note, date: Date, amount: Double, category: String)
        let visit: LocationVisitRecord?
        let matchType: String // "time", "location", or nil
    }
    
    private func matchReceiptsToVisits(
        receipts: [(note: Note, date: Date, amount: Double, category: String)],
        visits: [LocationVisitRecord]
    ) -> [ReceiptVisitMatch] {
        var matches: [ReceiptVisitMatch] = []
        let twoHours: TimeInterval = 2 * 60 * 60
        
        for receipt in receipts {
            var bestMatch: LocationVisitRecord?
            var matchType: String?
            var bestScore: Double = 0
            
            for visit in visits {
                var score: Double = 0
                var currentMatchType: String?
                
                // Score 1: Time proximity (within ±2 hours)
                let timeDiff = abs(visit.entryTime.timeIntervalSince(receipt.date))
                if timeDiff <= twoHours {
                    // Closer time = higher score
                    score = 1.0 - (timeDiff / twoHours)  // 1.0 for exact match, 0 for 2 hours away
                    currentMatchType = "time"
                }
                
                // Score 2: Location name match (loose matching)
                if let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                    let receiptTitle = receipt.note.title.lowercased()
                    let locationName = place.displayName.lowercased()
                    
                    // Check various matching strategies
                    let hasLocationMatch = 
                        receiptTitle.contains(locationName) ||
                        locationName.contains(receiptTitle) ||
                        receiptTitle.split(separator: " ").contains(where: { locationName.contains($0) }) ||
                        locationName.split(separator: " ").contains(where: { receiptTitle.contains($0) })
                    
                    if hasLocationMatch {
                        // Location match is very strong signal
                        if score > 0 {
                            score += 0.5  // Bonus for time + location match
                            currentMatchType = "location+time"
                        } else {
                            // Location match without time - still consider it
                            score = 0.3
                            currentMatchType = "location"
                        }
                    }
                }
                
                if score > bestScore {
                    bestScore = score
                    bestMatch = visit
                    matchType = currentMatchType
                }
            }
            
            // Only include matches with meaningful score
            if bestScore >= 0.1 {
                matches.append(ReceiptVisitMatch(
                    receipt: receipt,
                    visit: bestMatch,
                    matchType: matchType ?? "time"
                ))
            } else {
                // Receipt with no matching visit
                matches.append(ReceiptVisitMatch(
                    receipt: receipt,
                    visit: nil,
                    matchType: ""
                ))
            }
        }
        
        return matches
    }
    
    /// Build spending summary grouped by location with visit connections
    private func buildSpendingSummary(
        matches: [ReceiptVisitMatch],
        visits: [LocationVisitRecord],
        visitPeopleMap: [UUID: [Person]],
        timeFormatter: DateFormatter
    ) -> String {
        guard !matches.isEmpty else { return "" }
        
        // Group receipts by visit location
        var locationSpending: [String: (amount: Double, receipts: [(note: Note, amount: Double)], visitTime: Date?)] = [:]
        
        for match in matches {
            let receipt = match.receipt
            let locationName: String
            
            if let visit = match.visit, let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                locationName = place.displayName
            } else {
                locationName = receipt.note.title  // Use receipt title if no visit match
            }
            
            if var existing = locationSpending[locationName] {
                existing.amount += receipt.amount
                existing.receipts.append((note: receipt.note, amount: receipt.amount))
                if let visit = match.visit {
                    existing.visitTime = visit.entryTime
                }
                locationSpending[locationName] = existing
            } else {
                locationSpending[locationName] = (
                    amount: receipt.amount,
                    receipts: [(note: receipt.note, amount: receipt.amount)],
                    visitTime: match.visit?.entryTime
                )
            }
        }
        
        // Build output
        var output = "SPENDING BY LOCATION (Smart Connections):\n"
        let totalSpending = locationSpending.values.reduce(0.0) { $0 + $1.amount }
        output += "Total: $\(String(format: "%.2f", totalSpending)) across \(matches.count) purchases\n\n"
        
        // Sort by amount descending
        for (location, data) in locationSpending.sorted(by: { $0.value.amount > $1.value.amount }) {
            output += "📍 \(location): $\(String(format: "%.2f", data.amount))\n"
            
            // Show individual receipts
            for receipt in data.receipts.sorted(by: { $0.amount > $1.amount }) {
                output += "   • \(receipt.note.title) — $\(String(format: "%.2f", receipt.amount))\n"
            }
            
            // Link to visit if available
            if let visitTime = data.visitTime {
                let timeStr = timeFormatter.string(from: visitTime)
                if let visit = visits.first(where: { $0.entryTime == visitTime }),
                   LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) != nil {
                    let people = visitPeopleMap[visit.id] ?? []
                    if !people.isEmpty {
                        let peopleNames = people.map { $0.name }.joined(separator: ", ")
                        output += "   → Visit at \(timeStr) with \(peopleNames)\n"
                    }
                }
            }
            output += "\n"
        }
        
        return output
    }

    /// Estimate token count (rough: ~4 chars per token)
    private func estimateTokenCount(_ text: String) -> Int {
        return text.count / 4
    }

    private func deduplicateEvidence(_ evidence: [RelevantContentInfo]) -> [RelevantContentInfo] {
        var seen = Set<String>()
        var deduped: [RelevantContentInfo] = []

        func key(for item: RelevantContentInfo) -> String {
            switch item.contentType {
            case .email:
                return "email::\(item.emailId ?? item.id.uuidString)"
            case .note:
                return "note::\(item.noteId?.uuidString ?? item.id.uuidString)"
            case .receipt:
                return "receipt::\(item.receiptId?.uuidString ?? item.id.uuidString)"
            case .event:
                return "event::\(item.eventId?.uuidString ?? item.id.uuidString)"
            case .location:
                return "location::\(item.locationId?.uuidString ?? item.id.uuidString)"
            case .visit:
                return "visit::\(item.visitId?.uuidString ?? item.id.uuidString)"
            case .person:
                return "person::\(item.personId?.uuidString ?? item.id.uuidString)"
            }
        }

        for item in evidence {
            let itemKey = key(for: item)
            if !seen.contains(itemKey) {
                seen.insert(itemKey)
                deduped.append(item)
            }
        }
        return deduped
    }
    
    // MARK: - Types
    
    struct ContextResult {
        let context: String
        let metadata: ContextMetadata
        let evidence: [RelevantContentInfo]
    }
    
    struct ContextMetadata {
        var usedVectorSearch: Bool = false
        var usedCompleteDayData: Bool = false
        var estimatedTokens: Int = 0
        var buildTime: TimeInterval = 0
    }
}
