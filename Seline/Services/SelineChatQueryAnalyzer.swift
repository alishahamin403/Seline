import Foundation

struct SelineChatQuestionInterpreter {
    private let temporalService = TemporalUnderstandingService.shared

    private let followUpSignals: [(target: SelineChatFollowUpTargetType, phrases: [String])] = [
        (.place, ["this place", "that place", "this location", "that location", "this restaurant", "that restaurant", "this spot", "that spot"]),
        (.email, ["this email", "that email", "this message", "that message"]),
        (.episode, ["that trip", "this trip", "that visit", "this visit", "that day", "this day",
                    "that whole day", "that entire day", "that weekend", "that same day",
                    "what else happened", "what else did i do", "more about that day",
                    "show me that day", "what happened that day", "that time we"]),
        (.person, ["that person", "this person", "them again"]),
        (.receiptCluster, ["that receipt", "those receipts", "that purchase", "those purchases"])
    ]

    private let detailFollowUpPhrases = [
        "show details", "more details", "details", "show me more", "tell me more", "more context", "elaborate"
    ]

    private let stopWords: Set<String> = [
        "a", "about", "all", "am", "an", "and", "any", "are", "at", "be", "did", "do", "for", "from",
        "go", "had", "how", "i", "in", "is", "it", "its", "me", "my", "near", "of", "on", "or",
        "show", "tell", "the", "their", "there", "these", "this", "those", "time", "to", "today",
        "was", "what", "when", "where", "which", "who", "with", "last", "latest", "recently",
        "detail", "details", "more"
    ]

    func interpret(
        _ question: String,
        activeContext: SelineChatActiveContext?,
        recentEvidence: SelineChatEvidenceBundle? = nil
    ) -> SelineChatQuestionFrame {
        let normalizedQuestion = normalizeWhitespace(question)
        let lowercased = normalizedQuestion.lowercased()
        let timeScope = interpretTimeScope(from: lowercased)
        let followUpTarget = detectFollowUpTarget(in: lowercased, activeContext: activeContext)
        let isExplicitFollowUp = followUpTarget != nil
        let isFollowUpLike = isExplicitFollowUp || detectGenericFollowUp(in: lowercased)
        let searchTerms = extractSearchTerms(from: normalizedQuestion)
        let entityMentions = extractEntityMentions(from: normalizedQuestion)
        let requestedDomains = detectRequestedDomains(in: lowercased, searchTerms: searchTerms)
        let artifactIntent = detectArtifactIntent(in: lowercased, requestedDomains: requestedDomains)
        let wantsList = containsAny(lowercased, phrases: ["show", "list", "which", "what are", "from saved locations", "saved locations"])
        let wantsMap = containsAny(lowercased, phrases: ["nearby", "near me", "around me", "map"])
        let wantsSpecificObject = !wantsList && (
            containsAny(lowercased, phrases: ["this place", "that place", "what time is", "open today", "known for", "reviews", "rating"])
            || entityMentions.count == 1
        )
        let prefersMostRecent = containsAny(lowercased, phrases: ["last", "latest", "most recent", "recently"])
        let recentContextRefs = recentContextRefs(for: lowercased, bundle: recentEvidence)
        let recentContextSummary = recentContextSummary(for: recentContextRefs, bundle: recentEvidence)

        return SelineChatQuestionFrame(
            originalQuestion: question,
            normalizedQuestion: normalizedQuestion,
            timeScope: timeScope,
            entityMentions: entityMentions,
            artifactIntent: artifactIntent,
            requestedDomains: requestedDomains,
            isExplicitFollowUp: isExplicitFollowUp,
            followUpTargetType: followUpTarget,
            searchTerms: searchTerms,
            wantsList: wantsList,
            wantsMap: wantsMap,
            wantsSpecificObject: wantsSpecificObject,
            prefersMostRecent: prefersMostRecent,
            isFollowUpLike: isFollowUpLike,
            recentContextRefs: recentContextRefs,
            recentContextSummary: recentContextSummary
        )
    }

    private func detectGenericFollowUp(in query: String) -> Bool {
        containsAny(query, phrases: [
            "what else happened",
            "what else did i do",
            "that day",
            "that flight",
            "that email",
            "that place",
            "that trip",
            "more on that",
            "tell me more",
            "more details",
            "show details",
            "what about that",
            "how about that",
            "and what about",
            "there",
            "it"
        ])
    }

    private func recentContextRefs(for query: String, bundle: SelineChatEvidenceBundle?) -> [String] {
        guard let bundle else { return [] }
        guard detectGenericFollowUp(in: query) else { return [] }

        let preferredKinds: Set<SelineChatSourceKind> = {
            if containsAny(query, phrases: ["day", "happened", "else"]) {
                return [.daySummary, .event, .visit, .email, .note, .receipt]
            }
            if containsAny(query, phrases: ["flight", "email", "message"]) {
                return [.email]
            }
            if containsAny(query, phrases: ["place", "there", "restaurant", "location"]) {
                return [.place, .visit]
            }
            return []
        }()

        let filtered = bundle.records.filter { record in
            preferredKinds.isEmpty || preferredKinds.contains(record.sourceKind)
        }
        let refs = filtered.isEmpty ? bundle.records : filtered
        return Array(refs.prefix(8).map(\.id))
    }

    private func recentContextSummary(for refs: [String], bundle: SelineChatEvidenceBundle?) -> [String] {
        guard let bundle, !refs.isEmpty else { return [] }
        let allowed = Set(refs)
        return bundle.records
            .filter { allowed.contains($0.id) }
            .prefix(8)
            .map { record in
                if let timestamp = record.timestamp {
                    return "\(record.id) | \(record.title) | \(FormatterCache.shortDate.string(from: timestamp))"
                }
                return "\(record.id) | \(record.title)"
            }
    }

    private func interpretTimeScope(from query: String) -> SelineChatTimeScope? {
        guard let range = temporalService.extractTemporalRange(from: query) else {
            return nil
        }

        let bounds = temporalService.normalizedBounds(for: range)
        return SelineChatTimeScope(
            interval: DateInterval(start: bounds.start, end: bounds.end),
            description: range.description
        )
    }

    private func detectFollowUpTarget(
        in query: String,
        activeContext: SelineChatActiveContext?
    ) -> SelineChatFollowUpTargetType? {
        if containsAny(query, phrases: detailFollowUpPhrases) {
            if activeContext?.episodeAnchor != nil { return .episode }
            if activeContext?.placeAnchor != nil { return .place }
            if activeContext?.emailAnchor != nil { return .email }
            if activeContext?.personAnchor != nil { return .person }
            if activeContext?.receiptClusterAnchor != nil { return .receiptCluster }
        }

        for signal in followUpSignals where containsAny(query, phrases: signal.phrases) {
            switch signal.target {
            case .place where activeContext?.placeAnchor != nil:
                return .place
            case .email where activeContext?.emailAnchor != nil:
                return .email
            case .episode where activeContext?.episodeAnchor != nil:
                return .episode
            case .person where activeContext?.personAnchor != nil:
                return .person
            case .receiptCluster where activeContext?.receiptClusterAnchor != nil:
                return .receiptCluster
            default:
                break
            }
        }

        return nil
    }

    private func detectRequestedDomains(in query: String, searchTerms: [String]) -> Set<SelineChatDomain> {
        var domains = Set<SelineChatDomain>()

        if containsAny(query, phrases: ["email", "emails", "inbox", "reply", "replies", "message", "messages", "sent"]) {
            domains.insert(.emails)
        }
        // Travel/booking queries → search emails for confirmations, itineraries, etc.
        if containsAny(query, phrases: ["flight", "flights", "booking", "reservation", "itinerary",
                                        "hotel", "hostel", "airbnb", "ticket", "tickets",
                                        "boarding pass", "check-in", "check in", "arrive", "arriving",
                                        "departure", "departing", "depart", "layover", "gate",
                                        "terminal", "baggage", "luggage"]) {
            domains.formUnion([.emails, .notes])
        }
        if containsAny(query, phrases: ["note", "notes", "journal", "journals", "wrote", "write down", "recap"]) {
            domains.insert(.notes)
        }
        if containsAny(query, phrases: ["visit", "visited", "go to", "went to", "trip", "trips", "where was i", "where did i go"]) {
            domains.insert(.visits)
        }
        if containsAny(query, phrases: ["place", "places", "location", "locations", "restaurant", "gym", "open", "hours", "nearby", "near me", "saved locations"]) {
            domains.insert(.places)
        }
        if containsAny(query, phrases: ["who", "with", "person", "people", "friend", "friends", "family", "contact"]) {
            domains.insert(.people)
        }
        if containsAny(query, phrases: ["receipt", "receipts", "spend", "spent", "spending", "purchase", "purchases", "expense", "expenses", "paid"]) {
            domains.insert(.receipts)
        }

        if containsAny(query, phrases: ["tracker", "trackers", "tracking", "track my", "how is my", "update on my", "status of my", "progress on"]) {
            domains.insert(.trackers)
        }
        if containsAny(query, phrases: [
            "how was my day", "how's my day", "what happened today", "what did i do today",
            "what happened this week", "how was my week", "week recap", "weekly recap",
            "recap", "summary of my day", "summary of my week", "summarize my day", "summarize my week",
            "what did i do this week", "what happened last week"
        ]) {
            domains.insert(.daySummaries)
            domains.formUnion([.notes, .visits, .receipts, .people])
        }
        // Temporal "what's happening" queries → pull day summaries + events across all domains
        if containsAny(query, phrases: [
            "what is happening", "what's happening", "what's going on", "what is going on",
            "any plans", "do i have anything", "what do i have", "what's on my schedule",
            "what's on for", "what's planned", "anything happening", "anything planned",
            "anything coming up", "coming up", "upcoming", "schedule for"
        ]) {
            domains.insert(.daySummaries)
            domains.formUnion([.notes, .visits, .emails, .people])
        }

        if containsAny(query, phrases: [
            "recent notes", "what did i write", "latest note", "notes from", "what have i written",
            "what did i write about", "my notes"
        ]) {
            domains.insert(.notes)
        }

        if containsAny(query, phrases: [
            "what did i do with", "when did i last see", "last time i saw", "have i seen",
            "activities with", "went with", "been with", "spent time with"
        ]) {
            domains.formUnion([.people, .visits, .receipts, .emails])
        }

        if containsAny(query, phrases: [
            "how much did i spend", "spending this", "budget", "how much have i spent",
            "total spending", "expenses this", "cost me", "total cost"
        ]) {
            domains.insert(.receipts)
        }

        // Base domains for generic fallback — deliberately excludes daySummaries and trackers
        // to avoid slow fetches on ambiguous queries. Those only activate via explicit phrases above.
        let baseDomains: Set<SelineChatDomain> = [.emails, .notes, .visits, .places, .people, .receipts]

        if domains.isEmpty {
            if searchTerms.isEmpty {
                domains = baseDomains
            } else if containsAny(query, phrases: ["known for", "reviews", "rating", "open", "hours"]) {
                domains = [.places, .visits]
            } else {
                domains = baseDomains
            }
        }

        return domains
    }

    private func detectArtifactIntent(
        in query: String,
        requestedDomains: Set<SelineChatDomain>
    ) -> Set<SelineChatArtifactKind> {
        var intent = Set<SelineChatArtifactKind>()

        if containsAny(query, phrases: ["show", "list", "open", "from saved locations", "saved locations"]) {
            if requestedDomains.contains(.places) {
                intent.insert(.placeCards)
            }
            if requestedDomains.contains(.emails) {
                intent.insert(.emailCards)
            }
            if requestedDomains.contains(.receipts) {
                intent.insert(.receiptCards)
            }
        }

        if containsAny(query, phrases: ["nearby", "near me", "around me", "map"]) {
            intent.insert(.placeCards)
            intent.insert(.placeMap)
        }

        if containsAny(query, phrases: ["any emails", "emails from", "show emails", "list emails", "inbox"]) {
            intent.insert(.emailCards)
        }

        if containsAny(query, phrases: ["spend", "spent", "spending", "receipts", "purchases", "expenses"]) {
            intent.insert(.receiptCards)
        }

        return intent
    }

    private func extractEntityMentions(from question: String) -> [SelineChatEntityMention] {
        let ranges = quotedPhrases(in: question) + titleCasedPhrases(in: question)
        var seen = Set<String>()
        var mentions: [SelineChatEntityMention] = []

        for phrase in ranges {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 1 else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            mentions.append(SelineChatEntityMention(value: trimmed))
        }

        return mentions
    }

    private func quotedPhrases(in question: String) -> [String] {
        let pattern = "\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: question, range: NSRange(location: 0, length: question.utf16.count))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: question) else {
                return nil
            }
            return String(question[range])
        }
    }

    private func titleCasedPhrases(in question: String) -> [String] {
        let tokens = question.split(separator: " ")
        var phrases: [String] = []
        var current: [Substring] = []

        for token in tokens {
            let clean = token.trimmingCharacters(in: .punctuationCharacters)
            if clean.first?.isUppercase == true {
                current.append(clean[...])
            } else if !current.isEmpty {
                phrases.append(current.joined(separator: " "))
                current.removeAll()
            }
        }

        if !current.isEmpty {
            phrases.append(current.joined(separator: " "))
        }

        let multiWordPhrases = phrases.filter { $0.split(separator: " ").count >= 2 }
        let singleWordNames = tokens.enumerated().compactMap { index, token -> String? in
            let clean = token.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 3,
                  clean.first?.isUppercase == true else {
                return nil
            }

            let lowered = clean.lowercased()
            guard !stopWords.contains(lowered),
                  lowered != "i" else {
                return nil
            }

            // Ignore the first token when it's just sentence casing.
            if index == 0 && multiWordPhrases.isEmpty {
                return nil
            }

            return clean
        }

        return multiWordPhrases + singleWordNames
    }

    private func extractSearchTerms(from question: String) -> [String] {
        let lowercased = question.lowercased()
        let rawTokens = lowercased
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }

        var terms = rawTokens
        if rawTokens.count >= 2 {
            for index in 0..<(rawTokens.count - 1) {
                terms.append(rawTokens[index] + " " + rawTokens[index + 1])
            }
        }
        if rawTokens.count >= 3 {
            for index in 0..<(rawTokens.count - 2) {
                terms.append(rawTokens[index] + " " + rawTokens[index + 1] + " " + rawTokens[index + 2])
            }
        }

        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    private func containsAny(_ value: String, phrases: [String]) -> Bool {
        phrases.contains { value.contains($0) }
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
