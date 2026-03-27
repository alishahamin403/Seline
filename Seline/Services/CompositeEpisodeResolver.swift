import CoreLocation
import Foundation
import MapKit
import PostgREST

@MainActor
final class CompositeEpisodeResolver {
    static let shared = CompositeEpisodeResolver()

    private var lastResolvedEpisode: EpisodeResolution?
    private var geoAnchorCache: [String: GeoAnchor?] = [:]
    private let vectorSearch = VectorSearchService.shared

    enum ResolveResult {
        case resolved(EpisodeResolution)
        case ambiguous(question: String)
    }

    enum MatchQuality: String {
        case exact
        case approximate
        case inferred
    }

    struct EpisodeCandidateSummary {
        let start: Date
        let end: Date
        let label: String
        let confidence: Double
        let matchQuality: MatchQuality
        let visitCount: Int
        let matchedPeople: [String]
        let matchedPlaces: [String]
        let rationale: String
    }

    struct EpisodeResolution {
        let start: Date
        let end: Date
        let label: String
        let confidence: Double
        let matchQuality: MatchQuality
        let weekendOnly: Bool
        let matchedPeople: [Person]
        let matchedPlaces: [SavedPlace]
        let matchedVisits: [LocationVisitRecord]
        let geoDescription: String?
        let matchedAnchorName: String?
        let jointMatchCount: Int
        let proximityMatchCount: Int
        let semanticSupportScore: Double
        let supportingSourceSummary: String?
        let supportingEvidence: [RelevantContentInfo]
        let alternativeCandidates: [EpisodeCandidateSummary]

        var summaryContext: String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .short
            let inclusiveEnd = end.addingTimeInterval(-1)

            let peopleLabel = matchedPeople.isEmpty
                ? "none"
                : matchedPeople.map(\.name).joined(separator: ", ")
            let placeNames = Array(Set(matchedPlaces.map(\.displayName))).sorted()
            let placePreview = placeNames.prefix(6).joined(separator: ", ")

            var lines: [String] = []
            lines.append("=== RESOLVED EPISODE ===")
            lines.append("Resolved candidate: \(label)")
            lines.append("Confidence: \(Int((confidence * 100).rounded()))%")
            lines.append("Match quality: \(matchQuality.rawValue)")
            lines.append("Date range: \(dateFormatter.string(from: start)) to \(dateFormatter.string(from: inclusiveEnd))")
            lines.append("People: \(peopleLabel)")
            if let geoDescription, !geoDescription.isEmpty {
                lines.append("Geography: \(geoDescription)")
            }
            if let matchedAnchorName, !matchedAnchorName.isEmpty {
                lines.append("Matched geo anchor: \(matchedAnchorName)")
            }
            if !placePreview.isEmpty {
                lines.append("Places in this episode: \(placePreview)")
            }
            if jointMatchCount > 0 || proximityMatchCount > 0 {
                lines.append("Facet overlap: \(jointMatchCount) direct person+place matches, \(proximityMatchCount) nearby person/place matches")
            }
            if let supportingSourceSummary, !supportingSourceSummary.isEmpty {
                lines.append("Cross-source support: \(supportingSourceSummary)")
            }
            lines.append("Matching visits in candidate episode: \(matchedVisits.count)")
            if !alternativeCandidates.isEmpty {
                lines.append("Other plausible candidates:")
                for candidate in alternativeCandidates.prefix(2) {
                    let lastDay = candidate.end.addingTimeInterval(-1)
                    lines.append("- \(candidate.label) • \(Int((candidate.confidence * 100).rounded()))% • \(dateFormatter.string(from: candidate.start)) to \(dateFormatter.string(from: lastDay)) • \(candidate.matchQuality.rawValue)")
                }
            }
            lines.append("Use this as the leading candidate, and prefer query-focused intersection matches if they conflict.")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        var evidence: [RelevantContentInfo] {
            var items: [RelevantContentInfo] = []
            var seen = Set<String>()

            func supportKey(for item: RelevantContentInfo) -> String {
                switch item.contentType {
                case .email:
                    return "email:\(item.emailId ?? item.id.uuidString.lowercased())"
                case .note:
                    return "note:\(item.noteId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                case .receipt:
                    return "receipt:\(item.receiptId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                case .event:
                    return "event:\(item.eventId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                case .location:
                    return "location:\(item.locationId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                case .visit:
                    return "visit:\(item.visitId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                case .person:
                    return "person:\(item.personId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
                }
            }

            for person in matchedPeople {
                let item = RelevantContentInfo.person(
                    id: person.id,
                    name: person.name,
                    relationship: person.relationshipDisplayText
                )
                let key = "person:\(person.id.uuidString.lowercased())"
                if seen.insert(key).inserted {
                    items.append(item)
                }
            }

            for place in matchedPlaces.prefix(8) {
                let item = RelevantContentInfo.location(
                    id: place.id,
                    name: place.displayName,
                    address: place.address,
                    category: place.category
                )
                let key = "location:\(place.id.uuidString.lowercased())"
                if seen.insert(key).inserted {
                    items.append(item)
                }
            }

            for visit in matchedVisits.sorted(by: { $0.entryTime < $1.entryTime }).prefix(12) {
                let place = matchedPlaces.first(where: { $0.id == visit.savedPlaceId })
                let item = RelevantContentInfo.visit(
                    id: visit.id,
                    placeId: visit.savedPlaceId,
                    placeName: place?.displayName,
                    address: place?.address,
                    entryTime: visit.entryTime,
                    exitTime: visit.exitTime,
                    durationMinutes: visit.durationMinutes
                )
                let key = "visit:\(visit.id.uuidString.lowercased())"
                if seen.insert(key).inserted {
                    items.append(item)
                }
            }

            for item in supportingEvidence {
                let key = supportKey(for: item)
                if seen.insert(key).inserted {
                    items.append(item)
                }
            }

            return items
        }
    }

    private struct EpisodeConstraints {
        let anchoredText: String
        let queryFacets: QueryFacets
        let requiredPeople: [Person]
        let matchedPlaces: [SavedPlace]
        let geoAnchors: [GeoAnchor]
        let geoDescription: String?
        let explicitDateRange: (start: Date, end: Date)?
        let weekendOnly: Bool
        let tripLike: Bool
        let referential: Bool

        var dimensionCount: Int {
            var count = 0
            if !requiredPeople.isEmpty { count += 1 }
            if !matchedPlaces.isEmpty || !geoAnchors.isEmpty { count += 1 }
            if weekendOnly || tripLike || explicitDateRange != nil { count += 1 }
            return count
        }

        var hasGeoSignal: Bool {
            !matchedPlaces.isEmpty || !geoAnchors.isEmpty
        }
    }

    private struct QueryFacets {
        let asksWhen: Bool
        let asksPurpose: Bool
        let asksComparison: Bool
        let asksEnumeration: Bool
        let explicitRecency: Bool
        let singularEpisodeLookup: Bool
        let weekendOnly: Bool
        let tripLike: Bool
        let preferMostRecent: Bool
        let allowsAmbiguityPrompt: Bool
    }

    private struct EpisodeCandidate {
        let start: Date
        let end: Date
        let visits: [LocationVisitRecord]
        let matchedPeople: [Person]
        let matchedPlaces: [SavedPlace]
        let score: Double
        let geoDescription: String?
        let matchedAnchorName: String?
        let weekendOnly: Bool
        let matchQuality: MatchQuality
        let jointMatchCount: Int
        let proximityMatchCount: Int
        var semanticSupportScore: Double
        var supportingSourceSummary: String?
        var supportingEvidence: [RelevantContentInfo]
    }

    private struct GeoAnchor {
        let query: String
        let resolvedName: String
        let address: String
        let coordinate: CLLocationCoordinate2D
    }

    private struct GeoMatch {
        let isExactSavedPlace: Bool
        let anchorName: String?
        let anchorDistanceMeters: CLLocationDistance?

        var isMatch: Bool {
            isExactSavedPlace || anchorDistanceMeters != nil
        }

        var matchQuality: MatchQuality {
            if isExactSavedPlace {
                return .exact
            }
            if anchorDistanceMeters != nil {
                return .approximate
            }
            return .inferred
        }
    }

    private struct SemanticSupport {
        let score: Double
        let summary: String?
        let evidence: [RelevantContentInfo]
    }

    private init() {}

    func rememberResolvedEpisode(_ resolution: EpisodeResolution) {
        lastResolvedEpisode = resolution
    }

    func clearRememberedEpisode() {
        lastResolvedEpisode = nil
    }

    func resolve(
        query: String,
        conversationHistory: [(role: String, content: String)]
    ) async -> ResolveResult? {
        let constraints = await resolveConstraints(query: query, conversationHistory: conversationHistory)
        guard constraints.dimensionCount >= 2 else { return nil }
        guard !constraints.requiredPeople.isEmpty || constraints.hasGeoSignal else { return nil }

        let candidateVisits = await fetchCandidateVisits(for: constraints)
        guard !candidateVisits.isEmpty else { return nil }

        let placesById = Dictionary(uniqueKeysWithValues: LocationsManager.shared.savedPlaces.map { ($0.id, $0) })
        let visitPeopleMap = await PeopleManager.shared.getPeopleForVisits(visitIds: candidateVisits.map(\.id))

        let candidates = buildEpisodeCandidates(
            visits: candidateVisits,
            visitPeopleMap: visitPeopleMap,
            placesById: placesById,
            constraints: constraints
        )

        guard !candidates.isEmpty else { return nil }

        let enrichedCandidates = await enrichCandidatesWithSemanticSupport(
            candidates,
            query: query,
            constraints: constraints
        )
        let sorted = orderedCandidates(enrichedCandidates, constraints: constraints)

        if constraints.queryFacets.allowsAmbiguityPrompt, sorted.count > 1 {
            let top = sorted[0]
            let second = sorted[1]
            let ambiguousMargin = max(2.4, effectiveCandidateScore(for: top) * 0.16)
            let sameQuality = top.matchQuality == second.matchQuality
            if sameQuality, (effectiveCandidateScore(for: top) - effectiveCandidateScore(for: second)) < ambiguousMargin {
                return .ambiguous(question: clarificationQuestion(for: Array(sorted.prefix(2)), constraints: constraints))
            }
        }

        guard let best = sorted.first else { return nil }
        let finalVisits = await fetchVisitsForRange(start: best.start, end: best.end)
        let finalPlaceIds = Set(finalVisits.map(\.savedPlaceId))
        let finalPlaces = placesById.values.filter { finalPlaceIds.contains($0.id) }.sorted { $0.displayName < $1.displayName }

        let label = buildEpisodeLabel(for: best, constraints: constraints)
        let structuralEvidence = Double((best.jointMatchCount * 2) + best.proximityMatchCount)
        let qualityBonus: Double = {
            switch best.matchQuality {
            case .exact:
                return 0.22
            case .approximate:
                return 0.14
            case .inferred:
                return 0.05
            }
        }()
        let confidence = min(
            0.96,
            0.30
                + min(best.score / 70.0, 0.24)
                + min(best.semanticSupportScore / 14.0, 0.16)
                + min(structuralEvidence / 10.0, 0.18)
                + qualityBonus
        )

        let alternatives = Array(sorted.dropFirst().prefix(2)).map { candidate in
            EpisodeCandidateSummary(
                start: candidate.start,
                end: candidate.end,
                label: buildEpisodeLabel(for: candidate, constraints: constraints),
                confidence: candidateConfidence(for: candidate),
                matchQuality: candidate.matchQuality,
                visitCount: candidate.visits.count,
                matchedPeople: candidate.matchedPeople.map(\.name),
                matchedPlaces: Array(Set(candidate.matchedPlaces.map(\.displayName))).sorted(),
                rationale: candidateRationale(for: candidate, constraints: constraints)
            )
        }

        return .resolved(
            EpisodeResolution(
                start: best.start,
                end: best.end,
                label: label,
                confidence: confidence,
                matchQuality: best.matchQuality,
                weekendOnly: best.weekendOnly,
                matchedPeople: best.matchedPeople,
                matchedPlaces: finalPlaces.isEmpty ? best.matchedPlaces : finalPlaces,
                matchedVisits: finalVisits.isEmpty ? best.visits : finalVisits,
                geoDescription: best.geoDescription,
                matchedAnchorName: best.matchedAnchorName,
                jointMatchCount: best.jointMatchCount,
                proximityMatchCount: best.proximityMatchCount,
                semanticSupportScore: best.semanticSupportScore,
                supportingSourceSummary: best.supportingSourceSummary,
                supportingEvidence: best.supportingEvidence,
                alternativeCandidates: alternatives
            )
        )
    }

    private func orderedCandidates(
        _ candidates: [EpisodeCandidate],
        constraints: EpisodeConstraints
    ) -> [EpisodeCandidate] {
        let scoreSorted = candidates.sorted { lhs, rhs in
            let lhsScore = effectiveCandidateScore(for: lhs)
            let rhsScore = effectiveCandidateScore(for: rhs)
            if abs(lhsScore - rhsScore) > 0.001 {
                return lhsScore > rhsScore
            }
            if lhs.start != rhs.start {
                return lhs.start > rhs.start
            }
            return lhs.visits.count > rhs.visits.count
        }

        guard constraints.queryFacets.preferMostRecent, let topScore = scoreSorted.first.map({ effectiveCandidateScore(for: $0) }) else {
            return scoreSorted
        }

        let credibleWindow = scoreSorted.filter { candidate in
            effectiveCandidateScore(for: candidate) >= max(topScore - 8.0, topScore * 0.72)
        }
        let recentPreferred = credibleWindow.sorted { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start > rhs.start
            }
            return effectiveCandidateScore(for: lhs) > effectiveCandidateScore(for: rhs)
        }

        var ordered = recentPreferred
        for candidate in scoreSorted where !ordered.contains(where: { $0.start == candidate.start && $0.end == candidate.end && $0.score == candidate.score }) {
            ordered.append(candidate)
        }
        return ordered
    }

    private func candidateConfidence(for candidate: EpisodeCandidate) -> Double {
        let structuralEvidence = Double((candidate.jointMatchCount * 2) + candidate.proximityMatchCount)
        let qualityBonus: Double = {
            switch candidate.matchQuality {
            case .exact:
                return 0.20
            case .approximate:
                return 0.12
            case .inferred:
                return 0.04
            }
        }()
        return min(
            0.94,
            0.28
                + min(candidate.score / 72.0, 0.22)
                + min(candidate.semanticSupportScore / 14.0, 0.16)
                + min(structuralEvidence / 10.0, 0.18)
                + qualityBonus
        )
    }

    private func resolveConstraints(
        query: String,
        conversationHistory: [(role: String, content: String)]
    ) async -> EpisodeConstraints {
        let currentText = normalizedText(query)
        let referential = isReferentialQuery(currentText)
        let rememberedEpisode = referential ? lastResolvedEpisode : nil
        let historyUserTurns = conversationHistory
            .filter { $0.role == "user" }
            .suffix(6)
            .map(\.content)
            .joined(separator: " ")
        let anchoredText = referential ? normalizedText(query + " " + historyUserTurns) : currentText

        let currentPeople = resolvePeople(in: currentText)
        let anchoredPeople = resolvePeople(in: anchoredText)
        let requiredPeople: [Person]
        if !currentPeople.isEmpty {
            requiredPeople = currentPeople
        } else if !anchoredPeople.isEmpty {
            requiredPeople = anchoredPeople
        } else {
            requiredPeople = rememberedEpisode?.matchedPeople ?? []
        }

        let currentPlaces = resolvePlaces(in: currentText)
        let anchoredPlaces = resolvePlaces(in: anchoredText)
        let matchedPlaces: [SavedPlace]
        if !currentPlaces.isEmpty {
            matchedPlaces = currentPlaces
        } else if !anchoredPlaces.isEmpty {
            matchedPlaces = anchoredPlaces
        } else {
            matchedPlaces = rememberedEpisode?.matchedPlaces ?? []
        }

        let geoAnchors = await resolveGeoAnchors(
            query: query,
            anchoredText: anchoredText,
            requiredPeople: requiredPeople,
            matchedPlaces: matchedPlaces,
            rememberedEpisode: rememberedEpisode
        )
        let explicitRange = extractExplicitDateRange(from: query)
            ?? (referential ? rememberedEpisode.map { (start: $0.start, end: $0.end) } : nil)
        let geoDescription = deriveGeoDescription(from: matchedPlaces, geoAnchors: geoAnchors) ?? rememberedEpisode?.geoDescription

        let lower = query.lowercased()
        let queryFacets = parseQueryFacets(
            lowerQuery: lower,
            referential: referential,
            hasPeopleSignal: !requiredPeople.isEmpty,
            hasGeoSignal: !matchedPlaces.isEmpty || !geoAnchors.isEmpty,
            explicitDateRangePresent: explicitRange != nil,
            rememberedEpisodeExists: rememberedEpisode != nil,
            rememberedWeekendOnly: rememberedEpisode?.weekendOnly == true
        )

        return EpisodeConstraints(
            anchoredText: anchoredText,
            queryFacets: queryFacets,
            requiredPeople: requiredPeople,
            matchedPlaces: matchedPlaces,
            geoAnchors: geoAnchors,
            geoDescription: geoDescription,
            explicitDateRange: explicitRange,
            weekendOnly: queryFacets.weekendOnly,
            tripLike: queryFacets.tripLike,
            referential: referential
        )
    }

    private func parseQueryFacets(
        lowerQuery: String,
        referential: Bool,
        hasPeopleSignal: Bool,
        hasGeoSignal: Bool,
        explicitDateRangePresent: Bool,
        rememberedEpisodeExists: Bool,
        rememberedWeekendOnly: Bool
    ) -> QueryFacets {
        let asksWhen = lowerQuery.contains("when ")
        let asksPurpose = [
            "what did we go for",
            "what did i go for",
            "why did we go",
            "why did i go",
            "what were we doing",
            "what was the trip for"
        ].contains { lowerQuery.contains($0) }
        let asksComparison = lowerQuery.contains(" compare ")
            || lowerQuery.contains(" versus ")
            || lowerQuery.contains(" vs ")
        let asksEnumeration = [
            "times",
            "history",
            "list",
            "all the times",
            "every time",
            "whenever",
            "usually",
            "often"
        ].contains { lowerQuery.contains($0) }
        let explicitRecency = lowerQuery.contains("last time")
            || lowerQuery.contains("when was the last time")
            || lowerQuery.contains("most recent")
            || lowerQuery.contains("latest")
            || lowerQuery.contains("last went")
            || lowerQuery.contains("last visit")
        let singularEpisodeLookup = isSingularEpisodeLookup(lowerQuery)
            && !asksEnumeration
            && !asksComparison
            && !explicitDateRangePresent
            && hasPeopleSignal
            && hasGeoSignal
        let weekendOnly = lowerQuery.contains("weekend")
            || (referential && lowerQuery.contains("that") && rememberedWeekendOnly)
        let tripLike = lowerQuery.contains("trip")
            || lowerQuery.contains("stay")
            || lowerQuery.contains("travel")
            || lowerQuery.contains("vacation")
            || lowerQuery.contains("summarize")
            || asksPurpose
            || (referential && rememberedEpisodeExists)
        let preferMostRecent = explicitRecency
            || (singularEpisodeLookup && !explicitDateRangePresent)
        let allowsAmbiguityPrompt = asksComparison
            || asksEnumeration
            || (!preferMostRecent && !referential)

        return QueryFacets(
            asksWhen: asksWhen,
            asksPurpose: asksPurpose,
            asksComparison: asksComparison,
            asksEnumeration: asksEnumeration,
            explicitRecency: explicitRecency,
            singularEpisodeLookup: singularEpisodeLookup,
            weekendOnly: weekendOnly,
            tripLike: tripLike,
            preferMostRecent: preferMostRecent,
            allowsAmbiguityPrompt: allowsAmbiguityPrompt
        )
    }

    private func isSingularEpisodeLookup(_ lowerQuery: String) -> Bool {
        let singularQuestionSignals = [
            "when did i go",
            "when did we go",
            "when did i visit",
            "when did we visit",
            "when was i in",
            "when were we in",
            "when did i go to",
            "when did we go to",
            "what did we go for",
            "what did i go for",
            "why did we go",
            "why did i go"
        ]
        guard singularQuestionSignals.contains(where: { lowerQuery.contains($0) }) else {
            return false
        }

        let nonSingularSignals = [
            "times",
            "history",
            "usually",
            "often",
            "every time",
            "whenever",
            "all the times",
            "list",
            "compare"
        ]

        return !nonSingularSignals.contains(where: { lowerQuery.contains($0) })
    }

    private func resolvePeople(in normalizedQuery: String) -> [Person] {
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = tokenSet(from: normalizedQuery)
        var scored: [(person: Person, score: Double)] = []

        for person in PeopleManager.shared.people {
            var score = 0.0
            let aliases = [person.name, person.nickname].compactMap { alias -> String? in
                guard let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return normalizedText(alias)
            }

            for alias in aliases {
                if normalizedQuery.contains(alias) {
                    score = max(score, alias.split(separator: " ").count > 1 ? 100 : 88)
                }

                let aliasTokens = tokenSet(from: alias)
                guard !aliasTokens.isEmpty else { continue }
                let overlap = queryTokens.intersection(aliasTokens).count
                if overlap == aliasTokens.count {
                    score = max(score, 70 + Double(aliasTokens.count * 8))
                } else if overlap > 0 {
                    score = max(score, 35 + Double(overlap * 10))
                }
            }

            if score >= 55 {
                scored.append((person, score))
            }
        }

        let sorted = scored.sorted {
            if abs($0.score - $1.score) > 0.001 {
                return $0.score > $1.score
            }
            return $0.person.name < $1.person.name
        }

        return dedupePeople(sorted.map(\.person))
    }

    private func resolvePlaces(in normalizedQuery: String) -> [SavedPlace] {
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = tokenSet(from: normalizedQuery)
        var scored: [(place: SavedPlace, score: Double)] = []

        for place in LocationsManager.shared.savedPlaces {
            let displayName = normalizedText(place.displayName)
            let address = normalizedText(place.address)
            let city = normalizedText(place.city ?? "")
            let province = normalizedText(place.province ?? "")
            let country = normalizedText(place.country ?? "")

            var score = 0.0

            score = max(score, geoFieldScore(field: displayName, query: normalizedQuery, queryTokens: queryTokens, exactWeight: 95, tokenWeight: 14))
            score = max(score, geoFieldScore(field: city, query: normalizedQuery, queryTokens: queryTokens, exactWeight: 88, tokenWeight: 16))
            score = max(score, geoFieldScore(field: address, query: normalizedQuery, queryTokens: queryTokens, exactWeight: 78, tokenWeight: 10))
            score = max(score, geoFieldScore(field: province, query: normalizedQuery, queryTokens: queryTokens, exactWeight: 54, tokenWeight: 8))
            score = max(score, geoFieldScore(field: country, query: normalizedQuery, queryTokens: queryTokens, exactWeight: 44, tokenWeight: 6))

            if score >= 48 {
                scored.append((place, score))
            }
        }

        guard let topScore = scored.map(\.score).max() else { return [] }
        return scored
            .filter { $0.score >= max(48, topScore - 14) }
            .sorted {
                if abs($0.score - $1.score) > 0.001 {
                    return $0.score > $1.score
                }
                return $0.place.displayName < $1.place.displayName
            }
            .map(\.place)
    }

    private func fetchCandidateVisits(for constraints: EpisodeConstraints) async -> [LocationVisitRecord] {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return [] }

        var merged: [UUID: LocationVisitRecord] = [:]

        if !constraints.geoAnchors.isEmpty && constraints.matchedPlaces.isEmpty {
            let visits = await fetchAllVisits()
            for visit in visits {
                merged[visit.id] = visit
            }
        }

        if !constraints.requiredPeople.isEmpty {
            var peopleVisitIds = Set<UUID>()
            for person in constraints.requiredPeople {
                let visitIds = await PeopleManager.shared.getVisitIdsForPerson(personId: person.id)
                peopleVisitIds.formUnion(visitIds)
            }

            let visits = await fetchVisits(visitIds: Array(peopleVisitIds))
            for visit in visits {
                merged[visit.id] = visit
            }
        }

        if !constraints.matchedPlaces.isEmpty {
            let visits = await fetchVisits(savedPlaceIds: constraints.matchedPlaces.map(\.id))
            for visit in visits {
                merged[visit.id] = visit
            }
        }

        let semanticVisitIds = await fetchSemanticVisitIds(for: constraints)
        if !semanticVisitIds.isEmpty {
            let visits = await fetchVisits(visitIds: Array(semanticVisitIds))
            for visit in visits {
                merged[visit.id] = visit
            }
        }

        var results = Array(merged.values)
        if let explicitDateRange = constraints.explicitDateRange {
            results = results.filter { visit in
                let end = visit.exitTime ?? visit.entryTime
                return visit.entryTime < explicitDateRange.end && end >= explicitDateRange.start
            }
        }

        return results.sorted { $0.entryTime < $1.entryTime }
    }

    private func buildEpisodeCandidates(
        visits: [LocationVisitRecord],
        visitPeopleMap: [UUID: [Person]],
        placesById: [UUID: SavedPlace],
        constraints: EpisodeConstraints
    ) -> [EpisodeCandidate] {
        let grouped: [[LocationVisitRecord]]
        if constraints.weekendOnly {
            grouped = Dictionary(grouping: visits) { visit in
                weekendStart(for: visit.entryTime) ?? Calendar.current.startOfDay(for: visit.entryTime)
            }
            .values
            .map { $0.sorted { $0.entryTime < $1.entryTime } }
        } else {
            grouped = buildContiguousGroups(
                from: visits,
                placesById: placesById,
                geoPlaces: constraints.matchedPlaces,
                geoAnchors: constraints.geoAnchors,
                geoRadiusMeters: geoAnchorMatchRadius(for: constraints)
            )
        }

        var candidates: [EpisodeCandidate] = []
        let requiredPersonIds = Set(constraints.requiredPeople.map(\.id))
        let requiredPersonAliases = personAliasesById(for: constraints.requiredPeople)

        for group in grouped where !group.isEmpty {
            let groupPlaceIds = Set(group.map(\.savedPlaceId))
            let groupPlaces = groupPlaceIds.compactMap { placesById[$0] }.sorted { $0.displayName < $1.displayName }
            let noteMatchedPersonIdsByVisit = Dictionary(uniqueKeysWithValues: group.map { visit in
                (visit.id, matchedRequiredPersonIds(in: visit, aliasesByPersonId: requiredPersonAliases))
            })
            let noteMatchedPersonIdsInGroup = Set<UUID>(group.flatMap { Array(noteMatchedPersonIdsByVisit[$0.id] ?? Set<UUID>()) })

            let peopleInGroup = dedupePeople(
                group.flatMap { visitPeopleMap[$0.id] ?? [] }
                    + constraints.requiredPeople.filter { noteMatchedPersonIdsInGroup.contains($0.id) }
            )
            let peopleIdsInGroup = Set(peopleInGroup.map(\.id))
            let matchingPeopleSatisfied = requiredPersonIds.isEmpty || requiredPersonIds.isSubset(of: peopleIdsInGroup)
            let personMatchedVisits = group.filter { visit in
                let ids = Set((visitPeopleMap[visit.id] ?? []).map(\.id))
                    .union(noteMatchedPersonIdsByVisit[visit.id] ?? Set<UUID>())
                return !requiredPersonIds.isEmpty && !requiredPersonIds.intersection(ids).isEmpty
            }
            let geoMatches: [(visit: LocationVisitRecord, match: GeoMatch)] = group.compactMap { visit in
                guard let place = placesById[visit.savedPlaceId] else { return nil }
                let match = geoMatch(for: visit, place: place, constraints: constraints)
                return match.isMatch ? (visit, match) : nil
            }
            let geoMatchedVisits = geoMatches.map(\.visit)
            let exactGeoMatchCount = geoMatches.filter { $0.match.isExactSavedPlace }.count
            let approximateGeoMatchCount = geoMatches.filter { !$0.match.isExactSavedPlace && $0.match.anchorDistanceMeters != nil }.count
            let geoSatisfied = !constraints.hasGeoSignal || !geoMatchedVisits.isEmpty

            guard matchingPeopleSatisfied, geoSatisfied else { continue }

            let distinctDays = Set(group.map { Calendar.current.startOfDay(for: $0.entryTime) }).count
            let distinctPlaces = groupPlaceIds.count
            let personHitCount = personMatchedVisits.count
            let jointMatchCount = group.reduce(into: 0) { count, visit in
                let ids = Set((visitPeopleMap[visit.id] ?? []).map(\.id))
                    .union(noteMatchedPersonIdsByVisit[visit.id] ?? Set<UUID>())
                let hasPerson = !requiredPersonIds.isEmpty && !requiredPersonIds.intersection(ids).isEmpty
                let hasGeo = geoMatches.contains(where: { $0.visit.id == visit.id })
                if hasPerson && hasGeo {
                    count += 1
                }
            }
            let proximityMatchCount = countFacetProximityMatches(
                personMatchedVisits: personMatchedVisits,
                geoMatchedVisits: geoMatchedVisits
            )
            let requiresConjunctionEvidence = !requiredPersonIds.isEmpty && constraints.hasGeoSignal
            guard !requiresConjunctionEvidence || jointMatchCount > 0 || proximityMatchCount > 0 else {
                continue
            }

            let matchQuality: MatchQuality = {
                if exactGeoMatchCount > 0 {
                    return .exact
                }
                if approximateGeoMatchCount > 0 {
                    return .approximate
                }
                return .inferred
            }()
            let matchedAnchorName = geoMatches.compactMap { $0.match.anchorName }.first

            let score =
                (matchingPeopleSatisfied ? 10.0 : 0.0) +
                (geoSatisfied ? 10.0 : 0.0) +
                (Double(personHitCount) * 2.4) +
                (Double(geoMatchedVisits.count) * 2.2) +
                (Double(exactGeoMatchCount) * 4.8) +
                (Double(approximateGeoMatchCount) * 3.1) +
                (Double(jointMatchCount) * 6.8) +
                (Double(proximityMatchCount) * 4.6) +
                (Double(distinctDays) * 1.6) +
                (Double(group.count) * 0.9) +
                (Double(distinctPlaces) * 0.7)

            let start: Date
            let end: Date
            if constraints.weekendOnly, let weekendStart = weekendStart(for: group[0].entryTime) {
                start = weekendStart
                end = Calendar.current.date(byAdding: .day, value: 2, to: weekendStart) ?? group.last!.entryTime
            } else {
                start = Calendar.current.startOfDay(for: group.first!.entryTime)
                let lastEnd = group.compactMap(\.exitTime).max() ?? group.last!.entryTime
                end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: lastEnd)) ?? lastEnd
            }

            candidates.append(
                EpisodeCandidate(
                    start: start,
                    end: end,
                    visits: group,
                    matchedPeople: peopleInGroup,
                    matchedPlaces: groupPlaces,
                    score: score,
                    geoDescription: constraints.geoDescription,
                    matchedAnchorName: matchedAnchorName,
                    weekendOnly: constraints.weekendOnly,
                    matchQuality: matchQuality,
                    jointMatchCount: jointMatchCount,
                    proximityMatchCount: proximityMatchCount,
                    semanticSupportScore: 0,
                    supportingSourceSummary: nil,
                    supportingEvidence: []
                )
            )
        }

        return candidates
    }

    private func fetchSemanticVisitIds(for constraints: EpisodeConstraints) async -> Set<UUID> {
        let query = constraints.anchoredText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        do {
            let results = try await vectorSearch.search(
                query: query,
                documentTypes: [.visit],
                limit: constraints.hasGeoSignal ? 36 : 24,
                dateRange: constraints.explicitDateRange,
                preferHistorical: true,
                retrievalMode: .exhaustive
            )

            return Set(
                results.compactMap { result in
                    guard result.documentType == .visit else { return nil }
                    return UUID(uuidString: result.documentId)
                }
            )
        } catch {
            return []
        }
    }

    private func enrichCandidatesWithSemanticSupport(
        _ candidates: [EpisodeCandidate],
        query: String,
        constraints: EpisodeConstraints
    ) async -> [EpisodeCandidate] {
        guard !candidates.isEmpty else { return [] }

        let initialRanking = candidates.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.001 {
                return lhs.score > rhs.score
            }
            if lhs.start != rhs.start {
                return lhs.start > rhs.start
            }
            return lhs.visits.count > rhs.visits.count
        }

        var enriched = initialRanking
        let enrichmentCount = min(enriched.count, constraints.queryFacets.preferMostRecent ? 6 : 4)

        for index in 0..<enrichmentCount {
            let support = await fetchSemanticSupport(
                for: enriched[index],
                query: query,
                constraints: constraints
            )
            enriched[index].semanticSupportScore = support.score
            enriched[index].supportingSourceSummary = support.summary
            enriched[index].supportingEvidence = support.evidence
        }

        return enriched
    }

    private func fetchSemanticSupport(
        for candidate: EpisodeCandidate,
        query: String,
        constraints: EpisodeConstraints
    ) async -> SemanticSupport {
        let searchQuery = buildSemanticSupportQuery(
            query: query,
            candidate: candidate,
            constraints: constraints
        )

        do {
            let results = try await vectorSearch.search(
                query: searchQuery,
                limit: 18,
                dateRange: (start: candidate.start, end: candidate.end),
                preferHistorical: true
            )

            guard !results.isEmpty else {
                return SemanticSupport(score: 0, summary: nil, evidence: [])
            }

            let personTerms = supportTerms(
                for: constraints.requiredPeople.isEmpty ? candidate.matchedPeople : constraints.requiredPeople,
                fallbackPeople: candidate.matchedPeople
            )
            let geoTerms = geoSupportTerms(for: candidate, constraints: constraints)
            let queryTerms = tokenSet(from: query).filter { !temporalStopWords.contains($0) && !episodeStopWords.contains($0) }

            let matches = results.compactMap { result -> (score: Double, evidence: RelevantContentInfo)? in
                let searchable = searchableSupportText(for: result)
                let matchedPeople = personTerms.filter { searchable.contains($0) }
                let matchedGeo = geoTerms.filter { searchable.contains($0) }
                let matchedQuery = queryTerms.filter { searchable.contains($0) }

                let hasPersonSupport = personTerms.isEmpty || !matchedPeople.isEmpty
                let hasGeoSupport = geoTerms.isEmpty || !matchedGeo.isEmpty
                let totalAnchorHits = Set(matchedPeople + matchedGeo + matchedQuery).count

                guard hasPersonSupport else { return nil }
                guard hasGeoSupport || totalAnchorHits >= 3 else { return nil }
                guard totalAnchorHits >= max(2, min(queryTerms.count, 3)) else { return nil }
                guard let evidence = vectorSearch.evidenceItem(from: result) else { return nil }

                var score = Double(result.similarity) * 7.0
                score += Double(matchedPeople.count) * 1.9
                score += Double(matchedGeo.count) * 2.2
                score += Double(min(matchedQuery.count, 3)) * 0.7
                score += crossSourceBonus(for: result.documentType)
                return (score, evidence)
            }
            .sorted { $0.score > $1.score }

            guard !matches.isEmpty else {
                return SemanticSupport(score: 0, summary: nil, evidence: [])
            }

            var evidence: [RelevantContentInfo] = []
            var seen = Set<String>()
            for match in matches {
                let key = evidenceKey(for: match.evidence)
                if seen.insert(key).inserted {
                    evidence.append(match.evidence)
                }
                if evidence.count >= 4 {
                    break
                }
            }

            let totalScore = matches.prefix(4).reduce(0.0) { $0 + $1.score }
            let summary = buildSupportSummary(from: evidence)
            return SemanticSupport(score: totalScore, summary: summary, evidence: evidence)
        } catch {
            print("⚠️ Episode resolver semantic support lookup failed: \(error)")
            return SemanticSupport(score: 0, summary: nil, evidence: [])
        }
    }

    private func buildSemanticSupportQuery(
        query: String,
        candidate: EpisodeCandidate,
        constraints: EpisodeConstraints
    ) -> String {
        var parts: [String] = [query]

        let people = (constraints.requiredPeople.isEmpty ? candidate.matchedPeople : constraints.requiredPeople)
            .map(\.name)
        parts.append(contentsOf: people)

        if let geoDescription = constraints.geoDescription, !geoDescription.isEmpty {
            parts.append(geoDescription)
        }
        if let matchedAnchorName = candidate.matchedAnchorName, !matchedAnchorName.isEmpty {
            parts.append(matchedAnchorName)
        }
        parts.append(contentsOf: candidate.matchedPlaces.prefix(3).flatMap { place in
            [place.displayName, place.city, place.province].compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        })

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func supportTerms(
        for people: [Person],
        fallbackPeople: [Person]
    ) -> [String] {
        let source = people.isEmpty ? fallbackPeople : people
        var terms: [String] = []
        for person in source {
            for alias in [person.name, person.nickname].compactMap({ $0 }) {
                let normalizedAlias = normalizedText(alias)
                if normalizedAlias.count >= 3 {
                    terms.append(normalizedAlias)
                }
            }
        }
        return Array(Set(terms)).sorted()
    }

    private func geoSupportTerms(
        for candidate: EpisodeCandidate,
        constraints: EpisodeConstraints
    ) -> [String] {
        var rawTerms: [String] = []
        rawTerms.append(contentsOf: [constraints.geoDescription, candidate.matchedAnchorName].compactMap { $0 })
        rawTerms.append(contentsOf: candidate.matchedPlaces.prefix(4).flatMap { place in
            [place.displayName, place.city, place.province, place.country].compactMap { $0 }
        })

        var normalizedTerms: [String] = []
        for rawTerm in rawTerms {
            let normalized = normalizedText(rawTerm)
            guard !normalized.isEmpty else { continue }
            normalizedTerms.append(normalized)
            normalizedTerms.append(contentsOf: normalized.split(separator: " ").map(String.init))
        }

        let filtered = normalizedTerms.filter { term in
            term.count >= 3 &&
            !episodeStopWords.contains(term) &&
            !temporalStopWords.contains(term)
        }
        return Array(Set(filtered)).sorted()
    }

    private func searchableSupportText(for result: VectorSearchService.SearchResult) -> String {
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
        return normalizedText(fragments.joined(separator: " "))
    }

    private func crossSourceBonus(for documentType: VectorSearchService.DocumentType) -> Double {
        switch documentType {
        case .note:
            return 2.2
        case .email:
            return 2.0
        case .receipt:
            return 1.8
        case .task:
            return 1.5
        case .visit:
            return 0.8
        case .location:
            return 0.6
        case .person:
            return 0.5
        case .tracker:
            return 0.6
        case .budget:
            return 0.5
        case .recurringExpense:
            return 0.5
        case .attachment:
            return 0.4
        }
    }

    private func evidenceKey(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email:
            return "email:\(item.emailId ?? item.id.uuidString.lowercased())"
        case .note:
            return "note:\(item.noteId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        case .receipt:
            return "receipt:\(item.receiptId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        case .event:
            return "event:\(item.eventId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        case .location:
            return "location:\(item.locationId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        case .visit:
            return "visit:\(item.visitId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        case .person:
            return "person:\(item.personId?.uuidString.lowercased() ?? item.id.uuidString.lowercased())"
        }
    }

    private func buildSupportSummary(from evidence: [RelevantContentInfo]) -> String? {
        guard !evidence.isEmpty else { return nil }

        let prioritized = evidence.filter {
            $0.contentType != .visit && $0.contentType != .location && $0.contentType != .person
        }
        let source = prioritized.isEmpty ? evidence : prioritized
        let grouped = Dictionary(grouping: source, by: \.contentType)
        let orderedTypes: [RelevantContentInfo.ContentType] = [.note, .email, .receipt, .event, .visit, .location, .person]

        let fragments = orderedTypes.compactMap { type -> String? in
            guard let count = grouped[type]?.count, count > 0 else { return nil }
            return "\(count) \(supportLabel(for: type, count: count))"
        }

        guard !fragments.isEmpty else { return nil }
        if fragments.count == 1 {
            return "\(fragments[0]) in the same date range"
        }
        if fragments.count == 2 {
            return "\(fragments[0]) and \(fragments[1]) in the same date range"
        }
        let prefix = fragments.dropLast().joined(separator: ", ")
        return "\(prefix), and \(fragments.last!) in the same date range"
    }

    private func supportLabel(
        for type: RelevantContentInfo.ContentType,
        count: Int
    ) -> String {
        switch type {
        case .note:
            return count == 1 ? "note" : "notes"
        case .email:
            return count == 1 ? "email" : "emails"
        case .receipt:
            return count == 1 ? "receipt" : "receipts"
        case .event:
            return count == 1 ? "event" : "events"
        case .location:
            return count == 1 ? "location" : "locations"
        case .visit:
            return count == 1 ? "visit" : "visits"
        case .person:
            return count == 1 ? "person record" : "person records"
        }
    }

    private func effectiveCandidateScore(for candidate: EpisodeCandidate) -> Double {
        candidate.score + candidate.semanticSupportScore
    }

    private func buildContiguousGroups(
        from visits: [LocationVisitRecord],
        placesById: [UUID: SavedPlace],
        geoPlaces: [SavedPlace],
        geoAnchors: [GeoAnchor],
        geoRadiusMeters: CLLocationDistance
    ) -> [[LocationVisitRecord]] {
        guard !visits.isEmpty else { return [] }

        let geoPlaceIds = Set(geoPlaces.map(\.id))
        let maxGap: TimeInterval = 30 * 60 * 60
        var groups: [[LocationVisitRecord]] = []
        var currentGroup: [LocationVisitRecord] = []

        func sameGeoArea(_ lhs: LocationVisitRecord, _ rhs: LocationVisitRecord) -> Bool {
            if lhs.savedPlaceId == rhs.savedPlaceId {
                return true
            }

            if geoPlaceIds.contains(lhs.savedPlaceId) || geoPlaceIds.contains(rhs.savedPlaceId) {
                return arePlacesGeographicallyRelated(
                    placesById[lhs.savedPlaceId],
                    placesById[rhs.savedPlaceId],
                    geoAnchors: geoAnchors,
                    geoRadiusMeters: geoRadiusMeters
                )
            }
            let lhsPlace = placesById[lhs.savedPlaceId]
            let rhsPlace = placesById[rhs.savedPlaceId]
            if let lhsCity = lhsPlace?.city?.lowercased(), let rhsCity = rhsPlace?.city?.lowercased(), !lhsCity.isEmpty {
                return lhsCity == rhsCity
            }
            if !geoAnchors.isEmpty {
                return arePlacesGeographicallyRelated(lhsPlace, rhsPlace, geoAnchors: geoAnchors, geoRadiusMeters: geoRadiusMeters)
            }
            return false
        }

        for visit in visits.sorted(by: { $0.entryTime < $1.entryTime }) {
            guard let last = currentGroup.last else {
                currentGroup = [visit]
                continue
            }

            let lastEnd = last.exitTime ?? last.entryTime
            let gap = visit.entryTime.timeIntervalSince(lastEnd)
            if gap <= maxGap && sameGeoArea(last, visit) {
                currentGroup.append(visit)
            } else {
                groups.append(currentGroup)
                currentGroup = [visit]
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func clarificationQuestion(
        for candidates: [EpisodeCandidate],
        constraints: EpisodeConstraints
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let peopleLabel = constraints.requiredPeople.map(\.name).joined(separator: ", ")
        let geoLabel = constraints.geoDescription ?? candidates.first?.matchedAnchorName ?? "that place"

        let options = candidates.prefix(2).map { candidate -> String in
            let places = Array(Set(candidate.matchedPlaces.map(\.displayName))).prefix(2).joined(separator: ", ")
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: candidate.end) ?? candidate.end
            let rangeLabel = "\(formatter.string(from: candidate.start)) to \(formatter.string(from: lastDay))"
            if places.isEmpty {
                return rangeLabel
            }
            return "\(rangeLabel) (\(places))"
        }

        let intro: String
        if !peopleLabel.isEmpty {
            intro = "I found multiple possible trips with \(peopleLabel) in \(geoLabel)."
        } else {
            intro = "I found multiple possible trips matching \(geoLabel)."
        }

        return "\(intro) Did you mean \(options.joined(separator: " or "))?"
    }

    private func buildEpisodeLabel(for candidate: EpisodeCandidate, constraints: EpisodeConstraints) -> String {
        let people = constraints.requiredPeople.map(\.name)
        let geoLabel = constraints.geoDescription
            ?? candidate.matchedAnchorName
            ?? candidate.matchedPlaces.first?.city
            ?? candidate.matchedPlaces.first?.displayName
            ?? "that location"

        if constraints.weekendOnly {
            if !people.isEmpty {
                return "Weekend with \(people.joined(separator: ", ")) in \(geoLabel)"
            }
            return "Weekend in \(geoLabel)"
        }

        if constraints.tripLike {
            if !people.isEmpty {
                return "Trip with \(people.joined(separator: ", ")) in \(geoLabel)"
            }
            return "Trip in \(geoLabel)"
        }

        if !people.isEmpty {
            return "Visit episode with \(people.joined(separator: ", ")) in \(geoLabel)"
        }
        return "Visit episode in \(geoLabel)"
    }

    private func fetchVisits(visitIds: [UUID]) async -> [LocationVisitRecord] {
        guard !visitIds.isEmpty else { return [] }
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .in("id", values: visitIds.map { $0.uuidString })
                .order("entry_time", ascending: true)
                .execute()
            return try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
        } catch {
            print("⚠️ Episode resolver failed to fetch visits by id: \(error)")
            return []
        }
    }

    private func fetchVisits(savedPlaceIds: [UUID]) async -> [LocationVisitRecord] {
        guard !savedPlaceIds.isEmpty else { return [] }
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .in("saved_place_id", values: savedPlaceIds.map { $0.uuidString })
                .order("entry_time", ascending: true)
                .execute()
            return try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
        } catch {
            print("⚠️ Episode resolver failed to fetch visits by place: \(error)")
            return []
        }
    }

    private func fetchAllVisits() async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: true)
                .execute()
            return try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
        } catch {
            print("⚠️ Episode resolver failed to fetch all visits: \(error)")
            return []
        }
    }

    private func fetchVisitsForRange(start: Date, end: Date) async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let widenHours: TimeInterval = 12 * 60 * 60
        let fetchStart = start.addingTimeInterval(-widenHours)
        let fetchEnd = end.addingTimeInterval(widenHours)

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: iso.string(from: fetchStart))
                .lt("entry_time", value: iso.string(from: fetchEnd))
                .order("entry_time", ascending: true)
                .execute()
            let decoded = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
            return decoded.filter { visit in
                let visitEnd = visit.exitTime ?? visit.entryTime
                return visit.entryTime < end && visitEnd >= start
            }
        } catch {
            print("⚠️ Episode resolver failed to fetch visits for resolved range: \(error)")
            return []
        }
    }

    private func extractExplicitDateRange(from query: String) -> (start: Date, end: Date)? {
        guard let temporalRange = TemporalUnderstandingService.shared.extractTemporalRange(from: query) else {
            return nil
        }
        let bounds = TemporalUnderstandingService.shared.normalizedBounds(for: temporalRange)
        guard bounds.end > bounds.start else { return nil }
        return bounds
    }

    private func deriveGeoDescription(from places: [SavedPlace], geoAnchors: [GeoAnchor]) -> String? {
        if let firstAnchor = geoAnchors.first {
            return firstAnchor.query
        }

        guard !places.isEmpty else { return nil }

        let cityCounts = Dictionary(grouping: places.compactMap { $0.city?.trimmingCharacters(in: .whitespacesAndNewlines) }) { $0 }
            .mapValues(\.count)
        if let topCity = cityCounts.max(by: { $0.value < $1.value })?.key, !topCity.isEmpty {
            return topCity
        }

        let countryCounts = Dictionary(grouping: places.compactMap { $0.country?.trimmingCharacters(in: .whitespacesAndNewlines) }) { $0 }
            .mapValues(\.count)
        if let topCountry = countryCounts.max(by: { $0.value < $1.value })?.key, !topCountry.isEmpty {
            return topCountry
        }

        return places.first?.displayName
    }

    private func candidateRationale(
        for candidate: EpisodeCandidate,
        constraints: EpisodeConstraints
    ) -> String {
        var fragments: [String] = []
        if !constraints.requiredPeople.isEmpty {
            fragments.append("person match")
        }
        if constraints.hasGeoSignal {
            fragments.append(candidate.matchQuality == .exact ? "exact location match" : "regional location match")
        }
        if candidate.jointMatchCount > 0 {
            fragments.append("\(candidate.jointMatchCount) direct overlaps")
        } else if candidate.proximityMatchCount > 0 {
            fragments.append("\(candidate.proximityMatchCount) nearby overlaps")
        }
        if let supportingSourceSummary = candidate.supportingSourceSummary, !supportingSourceSummary.isEmpty {
            fragments.append(supportingSourceSummary)
        }
        return fragments.joined(separator: ", ")
    }

    private func geoAnchorMatchRadius(for constraints: EpisodeConstraints) -> CLLocationDistance {
        if constraints.tripLike || constraints.weekendOnly || constraints.queryFacets.preferMostRecent {
            return 75_000
        }
        return 40_000
    }

    private func geoMatch(
        for visit: LocationVisitRecord,
        place: SavedPlace,
        constraints: EpisodeConstraints
    ) -> GeoMatch {
        let matchedPlaceIds = Set(constraints.matchedPlaces.map(\.id))
        if matchedPlaceIds.contains(visit.savedPlaceId) {
            return GeoMatch(isExactSavedPlace: true, anchorName: nil, anchorDistanceMeters: nil)
        }

        guard !constraints.geoAnchors.isEmpty else {
            return GeoMatch(isExactSavedPlace: false, anchorName: nil, anchorDistanceMeters: nil)
        }

        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let maxDistance = geoAnchorMatchRadius(for: constraints)
        let bestAnchor = constraints.geoAnchors
            .map { anchor in
                let anchorLocation = CLLocation(latitude: anchor.coordinate.latitude, longitude: anchor.coordinate.longitude)
                return (anchor: anchor, distance: placeLocation.distance(from: anchorLocation))
            }
            .filter { $0.distance <= maxDistance }
            .min(by: { $0.distance < $1.distance })

        guard let bestAnchor else {
            return GeoMatch(isExactSavedPlace: false, anchorName: nil, anchorDistanceMeters: nil)
        }

        return GeoMatch(
            isExactSavedPlace: false,
            anchorName: bestAnchor.anchor.query,
            anchorDistanceMeters: bestAnchor.distance
        )
    }

    private func resolveGeoAnchors(
        query: String,
        anchoredText: String,
        requiredPeople: [Person],
        matchedPlaces: [SavedPlace],
        rememberedEpisode: EpisodeResolution?
    ) async -> [GeoAnchor] {
        guard matchedPlaces.isEmpty else { return [] }

        let normalizedQuery = normalizedText(query)
        if let rememberedEpisode,
           isReferentialQuery(normalizedQuery),
           let rememberedGeo = rememberedEpisode.geoDescription,
           let cachedAnchor = await lookupGeoAnchor(for: rememberedGeo) {
            return [cachedAnchor]
        }

        guard shouldAttemptGeoAnchorLookup(for: normalizedQuery) else { return [] }

        let candidatePhrases = extractCandidateGeoPhrases(
            from: query,
            anchoredText: anchoredText,
            requiredPeople: requiredPeople
        )

        var anchors: [GeoAnchor] = []
        for phrase in candidatePhrases.prefix(2) {
            if let anchor = await lookupGeoAnchor(for: phrase),
               !anchors.contains(where: { $0.query == anchor.query || $0.resolvedName == anchor.resolvedName }) {
                anchors.append(anchor)
            }
        }
        return anchors
    }

    private func shouldAttemptGeoAnchorLookup(for normalizedQuery: String) -> Bool {
        let padded = " \(normalizedQuery) "
        let visitSignals = [" go ", " went ", " visit ", " visited ", " trip ", " stay ", " travel ", " vacation ", " weekend "]
        let hasVisitSignal = visitSignals.contains { padded.contains($0) }
        let hasLocationPrep = padded.contains(" to ") || padded.contains(" at ") || padded.contains(" in ")
        return hasVisitSignal || hasLocationPrep
    }

    private func extractCandidateGeoPhrases(
        from query: String,
        anchoredText: String,
        requiredPeople: [Person]
    ) -> [String] {
        var phrases: [String] = []

        let patterns = [
            #"(?:go|went|visit|visited|travel|stayed|stay|trip)(?:\s+(?:to|at|in))?\s+(.+?)(?:\s+with\b|\s+for\b|\s+during\b|\s+last\b|\?|$)"#,
            #"(?:in|at|to)\s+(.+?)(?:\s+with\b|\s+for\b|\s+during\b|\?|$)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
            guard let match = regex.firstMatch(in: query, options: [], range: nsRange),
                  let range = Range(match.range(at: 1), in: query) else {
                continue
            }
            let phrase = cleanCandidateGeoPhrase(String(query[range]), requiredPeople: requiredPeople)
            if phrase.count >= 3 {
                phrases.append(phrase)
            }
        }

        if phrases.isEmpty {
            let personTokens = Set(requiredPeople.flatMap { person in
                [person.name, person.nickname]
                    .compactMap { $0 }
                    .flatMap { tokenSet(from: $0) }
            })
            let anchorTokens = anchoredText
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count >= 3 &&
                    !episodeStopWords.contains(token) &&
                    !personTokens.contains(token) &&
                    !temporalStopWords.contains(token)
                }
            if !anchorTokens.isEmpty {
                phrases.append(anchorTokens.prefix(3).joined(separator: " "))
            }
        }

        var seen = Set<String>()
        return phrases.filter { seen.insert($0).inserted }
    }

    private func cleanCandidateGeoPhrase(_ phrase: String, requiredPeople: [Person]) -> String {
        let personTokens = Set(requiredPeople.flatMap { person in
            [person.name, person.nickname]
                .compactMap { $0 }
                .flatMap { tokenSet(from: $0) }
        })
        let cleanedTokens = normalizedText(phrase)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count >= 3 &&
                !episodeStopWords.contains(token) &&
                !temporalStopWords.contains(token) &&
                !personTokens.contains(token)
            }
        return cleanedTokens.joined(separator: " ")
    }

    private func lookupGeoAnchor(for phrase: String) async -> GeoAnchor? {
        let normalizedPhrase = normalizedText(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }

        if let cached = geoAnchorCache[normalizedPhrase] {
            return cached
        }

        let anchor = await searchGeoAnchor(for: phrase)
        geoAnchorCache[normalizedPhrase] = anchor
        return anchor
    }

    private func searchGeoAnchor(for phrase: String) async -> GeoAnchor? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = phrase

        if let currentLocation = LocationService.shared.currentLocation {
            request.region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 300_000,
                longitudinalMeters: 300_000
            )
        } else {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
                latitudinalMeters: 300_000,
                longitudinalMeters: 300_000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                let placemark = item.placemark
                let name = item.name ?? placemark.name ?? phrase
                let address = [placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                return GeoAnchor(
                    query: phrase,
                    resolvedName: name,
                    address: address,
                    coordinate: placemark.coordinate
                )
            }
        } catch {
            print("⚠️ Episode resolver MapKit geo anchor search failed for '\(phrase)': \(error)")
        }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(phrase)
            if let first = placemarks.first, let location = first.location {
                let address = [first.locality, first.administrativeArea, first.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                return GeoAnchor(
                    query: phrase,
                    resolvedName: first.name ?? phrase,
                    address: address,
                    coordinate: location.coordinate
                )
            }
        } catch {
            print("⚠️ Episode resolver geocoder failed for '\(phrase)': \(error)")
        }

        return nil
    }

    private func countFacetProximityMatches(
        personMatchedVisits: [LocationVisitRecord],
        geoMatchedVisits: [LocationVisitRecord]
    ) -> Int {
        guard !personMatchedVisits.isEmpty, !geoMatchedVisits.isEmpty else { return 0 }

        var matchedGeoVisitIds = Set<UUID>()
        for geoVisit in geoMatchedVisits {
            if personMatchedVisits.contains(where: { visitsAreTemporallyRelated($0, geoVisit) }) {
                matchedGeoVisitIds.insert(geoVisit.id)
            }
        }
        return matchedGeoVisitIds.count
    }

    private func visitsAreTemporallyRelated(
        _ lhs: LocationVisitRecord,
        _ rhs: LocationVisitRecord,
        maxGap: TimeInterval = 24 * 60 * 60
    ) -> Bool {
        let lhsStart = lhs.entryTime
        let lhsEnd = lhs.exitTime ?? lhs.entryTime
        let rhsStart = rhs.entryTime
        let rhsEnd = rhs.exitTime ?? rhs.entryTime

        if lhsStart <= rhsEnd && rhsStart <= lhsEnd {
            return true
        }

        let gapAfterLhs = abs(rhsStart.timeIntervalSince(lhsEnd))
        let gapAfterRhs = abs(lhsStart.timeIntervalSince(rhsEnd))
        return min(gapAfterLhs, gapAfterRhs) <= maxGap
    }

    private func arePlacesGeographicallyRelated(
        _ lhs: SavedPlace?,
        _ rhs: SavedPlace?,
        geoAnchors: [GeoAnchor] = [],
        geoRadiusMeters: CLLocationDistance = 45_000
    ) -> Bool {
        guard let lhs, let rhs else { return false }

        if lhs.id == rhs.id {
            return true
        }

        let lhsCity = lhs.city?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let rhsCity = rhs.city?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !lhsCity.isEmpty && lhsCity == rhsCity {
            return true
        }

        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        if lhsLocation.distance(from: rhsLocation) <= 45_000 {
            return true
        }

        guard !geoAnchors.isEmpty else { return false }
        for anchor in geoAnchors {
            let anchorLocation = CLLocation(latitude: anchor.coordinate.latitude, longitude: anchor.coordinate.longitude)
            let lhsDistance = lhsLocation.distance(from: anchorLocation)
            let rhsDistance = rhsLocation.distance(from: anchorLocation)
            if lhsDistance <= geoRadiusMeters && rhsDistance <= geoRadiusMeters {
                return true
            }
        }
        return false
    }

    private func geoFieldScore(
        field: String,
        query: String,
        queryTokens: Set<String>,
        exactWeight: Double,
        tokenWeight: Double
    ) -> Double {
        guard !field.isEmpty else { return 0 }
        if query.contains(field) {
            return exactWeight
        }

        let fieldTokens = tokenSet(from: field)
        guard !fieldTokens.isEmpty else { return 0 }

        let overlap = queryTokens.intersection(fieldTokens)
        if overlap.count == fieldTokens.count && overlap.count >= 2 {
            return exactWeight - 8
        }
        if overlap.count >= 2 {
            return Double(overlap.count) * tokenWeight
        }
        if overlap.count == 1 {
            return tokenWeight * 0.6
        }
        return 0
    }

    private func tokenSet(from text: String) -> Set<String> {
        Set(
            normalizedText(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 3 && !episodeStopWords.contains($0) }
        )
    }

    private func dedupePeople(_ people: [Person]) -> [Person] {
        var seen = Set<UUID>()
        var deduped: [Person] = []
        for person in people where seen.insert(person.id).inserted {
            deduped.append(person)
        }
        return deduped
    }

    private func personAliasesById(for people: [Person]) -> [UUID: [String]] {
        var aliasesById: [UUID: [String]] = [:]
        for person in people {
            let aliases = [person.name, person.nickname]
                .compactMap { $0 }
                .map(normalizedText)
                .filter { !$0.isEmpty }
            aliasesById[person.id] = Array(Set(aliases)).sorted()
        }
        return aliasesById
    }

    private func matchedRequiredPersonIds(
        in visit: LocationVisitRecord,
        aliasesByPersonId: [UUID: [String]]
    ) -> Set<UUID> {
        guard let notes = visit.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return []
        }

        let normalizedNotes = normalizedText(notes)
        guard !normalizedNotes.isEmpty else { return [] }

        let noteTokens = Set(normalizedNotes.split(separator: " ").map(String.init))
        var matched = Set<UUID>()

        for (personId, aliases) in aliasesByPersonId {
            let found = aliases.contains { alias in
                if alias.contains(" ") {
                    return normalizedNotes.contains(alias)
                }
                return noteTokens.contains(alias)
            }
            if found {
                matched.insert(personId)
            }
        }

        return matched
    }

    private func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isReferentialQuery(_ normalizedQuery: String) -> Bool {
        let markers = [
            "that",
            "same",
            "there",
            "those",
            "it",
            "her",
            "his",
            "for her",
            "for him",
            "birthday",
            "one weekend",
            "that one",
            "summarize that",
            "what did i do that"
        ]
        return markers.contains { normalizedQuery.contains($0) }
    }

    private func weekendStart(for date: Date) -> Date? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysBackToSaturday = weekday == 7 ? 0 : (weekday == 1 ? 1 : weekday)
        guard let weekendStart = calendar.date(byAdding: .day, value: -daysBackToSaturday, to: day) else {
            return nil
        }
        return calendar.startOfDay(for: weekendStart)
    }

    private let episodeStopWords: Set<String> = [
        "what", "when", "where", "who", "how", "tell", "summarize", "summary",
        "weekend", "trip", "stay", "went", "with", "and", "the", "that", "one",
        "did", "can", "you", "about", "there", "same", "into", "from"
    ]

    private let temporalStopWords: Set<String> = [
        "last", "latest", "recent", "recently", "time", "times", "week", "month",
        "year", "today", "yesterday", "tomorrow", "before", "after", "during"
    ]
}
