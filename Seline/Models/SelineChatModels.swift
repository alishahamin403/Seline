import Foundation

enum SelineChatRole: String, Codable, Hashable {
    case user
    case assistant
}

enum SelineChatDomain: String, Codable, CaseIterable, Hashable {
    case emails
    case events
    case notes
    case visits
    case places
    case people
    case receipts
    case daySummaries
    case trackers
}

enum SelineChatArtifactKind: String, Codable, CaseIterable, Hashable {
    case emailCards
    case noteCards
    case visitCards
    case placeCards
    case receiptCards
    case personCards
    case trackerCards
    case placeMap
}

enum SelineChatFollowUpTargetType: String, Codable, Hashable {
    case place
    case email
    case episode
    case person
    case receiptCluster
}

struct SelineChatEntityMention: Identifiable, Codable, Hashable {
    let id: String
    let value: String
    let normalizedValue: String

    init(value: String) {
        self.id = value.lowercased()
        self.value = value
        self.normalizedValue = value.lowercased()
    }
}

struct SelineChatTimeScope: Codable, Hashable {
    let interval: DateInterval
    let description: String
}

struct SelineChatQuestionFrame: Codable, Hashable {
    let originalQuestion: String
    let normalizedQuestion: String
    let timeScope: SelineChatTimeScope?
    let entityMentions: [SelineChatEntityMention]
    let artifactIntent: Set<SelineChatArtifactKind>
    let requestedDomains: Set<SelineChatDomain>
    let isExplicitFollowUp: Bool
    let followUpTargetType: SelineChatFollowUpTargetType?
    let searchTerms: [String]
    let wantsList: Bool
    let wantsMap: Bool
    let wantsSpecificObject: Bool
    let prefersMostRecent: Bool
    let isFollowUpLike: Bool
    let recentContextRefs: [String]
    let recentContextSummary: [String]
}

enum SelineChatSourceKind: String, Codable, CaseIterable, Hashable {
    case email
    case event
    case note
    case receipt
    case visit
    case person
    case place
    case daySummary
    case tracker
    case web

    var label: String {
        switch self {
        case .email: return "Emails"
        case .event: return "Events"
        case .note: return "Notes"
        case .receipt: return "Receipts"
        case .visit: return "Visits"
        case .person: return "People"
        case .place: return "Places"
        case .daySummary: return "Day Summaries"
        case .tracker: return "Trackers"
        case .web: return "Web"
        }
    }
}

struct SelineChatProviderState: Codable, Hashable {
    var previousResponseID: String?
}

struct SelineChatToolTraceEntry: Identifiable, Codable, Hashable {
    let id: String
    let toolName: String
    let argumentsSummary: String
    let latencyMS: Int
    let resultCount: Int
    let evidenceIDs: [String]
    let note: String?

    init(
        toolName: String,
        argumentsSummary: String,
        latencyMS: Int,
        resultCount: Int,
        evidenceIDs: [String],
        note: String? = nil
    ) {
        self.id = UUID().uuidString
        self.toolName = toolName
        self.argumentsSummary = argumentsSummary
        self.latencyMS = latencyMS
        self.resultCount = resultCount
        self.evidenceIDs = evidenceIDs
        self.note = note
    }
}

struct SelineChatTurnTrace: Codable, Hashable {
    let query: String
    let startedAt: Date
    let completedAt: Date
    let toolCalls: [SelineChatToolTraceEntry]
    let finalEvidenceIDs: [String]
    let noAnswerReason: String?
}

struct SelineChatEvidenceRecord: Identifiable, Codable, Hashable {
    let id: String
    let sourceKind: SelineChatSourceKind
    let title: String
    let snippet: String
    let timestamp: Date?
    let relationIDs: [String]
    let externalURL: String?
}

struct SelineChatEvidenceBundle: Codable, Hashable {
    let id: String
    let query: String
    let generatedAt: Date
    var records: [SelineChatEvidenceRecord]
    var items: [SelineChatEvidenceItem]
    var places: [SelineChatPlaceResult]
    var citations: [SelineChatWebCitation]
    var trace: [SelineChatToolTraceEntry]

    init(
        query: String,
        generatedAt: Date = Date(),
        records: [SelineChatEvidenceRecord] = [],
        items: [SelineChatEvidenceItem] = [],
        places: [SelineChatPlaceResult] = [],
        citations: [SelineChatWebCitation] = [],
        trace: [SelineChatToolTraceEntry] = []
    ) {
        self.id = UUID().uuidString
        self.query = query
        self.generatedAt = generatedAt
        self.records = records
        self.items = items
        self.places = places
        self.citations = citations
        self.trace = trace
    }

    var topContextLines: [String] {
        Array(records.prefix(8).map { record in
            if let timestamp = record.timestamp {
                return "\(record.id) | \(record.sourceKind.rawValue) | \(record.title) | \(FormatterCache.shortDate.string(from: timestamp))"
            }
            return "\(record.id) | \(record.sourceKind.rawValue) | \(record.title)"
        })
    }
}

struct SelineChatGroundedFact: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let sourceItemIDs: [String]

    init(text: String, sourceItemIDs: [String]) {
        self.id = UUID().uuidString
        self.text = text
        self.sourceItemIDs = sourceItemIDs
    }
}

struct SelineChatEvidenceRelation: Identifiable, Codable, Hashable {
    let id: String
    let fromItemID: String
    let toItemID: String
    let label: String

    init(fromItemID: String, toItemID: String, label: String) {
        self.id = UUID().uuidString
        self.fromItemID = fromItemID
        self.toItemID = toItemID
        self.label = label
    }
}

enum SelineChatEvidenceKind: String, Codable, Hashable {
    case email
    case event
    case note
    case receipt
    case visit
    case person
    case daySummary
    case tracker

    var label: String {
        switch self {
        case .email: return "Email"
        case .event: return "Event"
        case .note: return "Note"
        case .receipt: return "Receipt"
        case .visit: return "Visit"
        case .person: return "Person"
        case .daySummary: return "Summary"
        case .tracker: return "Tracker"
        }
    }

    var systemImage: String {
        switch self {
        case .email: return "tray.fill"
        case .event: return "calendar"
        case .note: return "note.text"
        case .receipt: return "creditcard"
        case .visit: return "location"
        case .person: return "person.fill"
        case .daySummary: return "sun.max"
        case .tracker: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct SelineChatEvidenceItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: SelineChatEvidenceKind
    let title: String
    let subtitle: String
    let detail: String?
    let footnote: String?
    let date: Date?
    let emailID: String?
    let noteID: UUID?
    let taskID: String?
    let placeID: UUID?
    let personID: UUID?
}

struct SelineChatPlaceResult: Identifiable, Codable, Hashable {
    let id: String
    let savedPlaceID: UUID?
    let googlePlaceID: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let rating: Double?
    let isSaved: Bool

    var asSearchResult: PlaceSearchResult {
        PlaceSearchResult(
            id: googlePlaceID,
            name: name,
            address: subtitle,
            latitude: latitude,
            longitude: longitude,
            types: category.map { [$0] } ?? [],
            photoURL: nil,
            isSaved: isSaved
        )
    }

    func resolvedSavedPlace() -> SavedPlace {
        if let savedPlaceID,
           let existing = LocationsManager.shared.savedPlaces.first(where: { $0.id == savedPlaceID }) {
            return existing
        }

        var place = SavedPlace(
            googlePlaceId: googlePlaceID,
            name: name,
            address: subtitle,
            latitude: latitude,
            longitude: longitude
        )
        if let category {
            place.category = category
        }
        return place
    }
}

struct SelineChatWebCitation: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let url: String
    let source: String?

    init(title: String, url: String, source: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.url = url
        self.source = source
    }
}

struct SelineChatEvidencePacket: Codable, Hashable {
    let frame: SelineChatQuestionFrame
    let facts: [SelineChatGroundedFact]
    let items: [SelineChatEvidenceItem]
    let relations: [SelineChatEvidenceRelation]
    let openQuestions: [String]
    let allowedArtifacts: Set<SelineChatArtifactKind>
    let places: [SelineChatPlaceResult]
    var webSearchResult: String? = nil

    var referencedItemIDs: [String] {
        Array(Set(facts.flatMap(\.sourceItemIDs)))
    }
}

struct SelineChatArtifactRequest: Identifiable, Codable, Hashable {
    let id: String
    let kind: SelineChatArtifactKind
    let title: String?

    init(kind: SelineChatArtifactKind, title: String? = nil) {
        self.id = "\(kind.rawValue)-\(title ?? "default")"
        self.kind = kind
        self.title = title
    }
}

struct SelineChatInlineSource: Identifiable, Codable, Hashable {
    let id: String
    let displayText: String
    let evidenceItem: SelineChatEvidenceItem?
    let placeResult: SelineChatPlaceResult?
    let citation: SelineChatWebCitation?

    init(evidenceItem: SelineChatEvidenceItem, displayText: String) {
        self.id = "inline-evidence-\(evidenceItem.id)"
        self.displayText = displayText
        self.evidenceItem = evidenceItem
        self.placeResult = nil
        self.citation = nil
    }

    init(placeResult: SelineChatPlaceResult, displayText: String) {
        self.id = "inline-place-\(placeResult.id)"
        self.displayText = displayText
        self.evidenceItem = nil
        self.placeResult = placeResult
        self.citation = nil
    }

    init(citation: SelineChatWebCitation, displayText: String? = nil) {
        self.id = "inline-citation-\(citation.id)"
        self.displayText = displayText ?? citation.source ?? citation.title
        self.evidenceItem = nil
        self.placeResult = nil
        self.citation = citation
    }
}

struct SelineChatPlaceAnchor: Codable, Hashable {
    let savedPlaceID: UUID
    let name: String
}

struct SelineChatEmailAnchor: Codable, Hashable {
    let emailID: String
    let subject: String
}

struct SelineChatEpisodeAnchor: Codable, Hashable {
    let visitIDs: [UUID]
    let placeIDs: [UUID]
    let personIDs: [UUID]
    let label: String
    var visitDates: [Date]  // actual dates of the visits, used for day-scoped follow-up retrieval
}

struct SelineChatPersonAnchor: Codable, Hashable {
    let personID: UUID
    let name: String
}

struct SelineChatReceiptClusterAnchor: Codable, Hashable {
    let noteIDs: [UUID]
    let title: String
}

struct SelineChatActiveContext: Codable, Hashable {
    var placeAnchor: SelineChatPlaceAnchor? = nil
    var emailAnchor: SelineChatEmailAnchor? = nil
    var episodeAnchor: SelineChatEpisodeAnchor? = nil
    var personAnchor: SelineChatPersonAnchor? = nil
    var receiptClusterAnchor: SelineChatReceiptClusterAnchor? = nil
}

struct SelineChatAnswerDraft: Codable, Hashable {
    let markdown: String
    let referencedItemIDs: [String]
    let artifactRequests: [SelineChatArtifactRequest]
    let followUpAnchor: SelineChatActiveContext?
}

enum SelineChatResponseBlock: Hashable, Codable {
    case markdown(String)
    case evidence(title: String, items: [SelineChatEvidenceItem])
    case places(title: String, results: [SelineChatPlaceResult], showMap: Bool)
    case citations([SelineChatWebCitation])

    private enum CodingKeys: String, CodingKey {
        case type
        case markdown
        case title
        case items
        case results
        case showMap
        case citations
    }

    private enum BlockType: String, Codable {
        case markdown
        case evidence
        case places
        case citations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)

        switch type {
        case .markdown:
            self = .markdown(try container.decode(String.self, forKey: .markdown))
        case .evidence:
            self = .evidence(
                title: try container.decode(String.self, forKey: .title),
                items: try container.decode([SelineChatEvidenceItem].self, forKey: .items)
            )
        case .places:
            self = .places(
                title: try container.decode(String.self, forKey: .title),
                results: try container.decode([SelineChatPlaceResult].self, forKey: .results),
                showMap: try container.decode(Bool.self, forKey: .showMap)
            )
        case .citations:
            self = .citations(try container.decode([SelineChatWebCitation].self, forKey: .citations))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .markdown(let markdown):
            try container.encode(BlockType.markdown, forKey: .type)
            try container.encode(markdown, forKey: .markdown)
        case .evidence(let title, let items):
            try container.encode(BlockType.evidence, forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(items, forKey: .items)
        case .places(let title, let results, let showMap):
            try container.encode(BlockType.places, forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(results, forKey: .results)
            try container.encode(showMap, forKey: .showMap)
        case .citations(let citations):
            try container.encode(BlockType.citations, forKey: .type)
            try container.encode(citations, forKey: .citations)
        }
    }
}

struct SelineChatAssistantPayload: Codable, Hashable {
    let sourceChips: [String]
    let responseBlocks: [SelineChatResponseBlock]
    let activeContext: SelineChatActiveContext?
    let inlineSources: [SelineChatInlineSource]
    var followUpSuggestions: [String]

    init(
        sourceChips: [String],
        responseBlocks: [SelineChatResponseBlock],
        activeContext: SelineChatActiveContext?,
        inlineSources: [SelineChatInlineSource] = [],
        followUpSuggestions: [String] = []
    ) {
        self.sourceChips = sourceChips
        self.responseBlocks = responseBlocks
        self.activeContext = activeContext
        self.inlineSources = inlineSources
        self.followUpSuggestions = followUpSuggestions
    }

    private enum CodingKeys: String, CodingKey {
        case sourceChips
        case responseBlocks
        case activeContext
        case inlineSources
        case followUpSuggestions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceChips = try container.decode([String].self, forKey: .sourceChips)
        self.responseBlocks = try container.decode([SelineChatResponseBlock].self, forKey: .responseBlocks)
        self.activeContext = try container.decodeIfPresent(SelineChatActiveContext.self, forKey: .activeContext)
        self.inlineSources = try container.decodeIfPresent([SelineChatInlineSource].self, forKey: .inlineSources) ?? []
        self.followUpSuggestions = try container.decodeIfPresent([String].self, forKey: .followUpSuggestions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceChips, forKey: .sourceChips)
        try container.encode(responseBlocks, forKey: .responseBlocks)
        try container.encodeIfPresent(activeContext, forKey: .activeContext)
        try container.encode(inlineSources, forKey: .inlineSources)
        try container.encode(followUpSuggestions, forKey: .followUpSuggestions)
    }

    var primaryText: String {
        for block in responseBlocks {
            if case .markdown(let markdown) = block {
                return markdown
            }
        }
        return ""
    }
}

struct SelineChatTurn: Identifiable, Codable, Hashable {
    let id: UUID
    let role: SelineChatRole
    var text: String
    var assistantPayload: SelineChatAssistantPayload?
    var debugTrace: SelineChatTurnTrace?
    var isStreaming: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: SelineChatRole,
        text: String,
        assistantPayload: SelineChatAssistantPayload? = nil,
        debugTrace: SelineChatTurnTrace? = nil,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.assistantPayload = assistantPayload
        self.debugTrace = debugTrace
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }

    var transcriptText: String {
        assistantPayload?.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? assistantPayload?.primaryText ?? text
            : text
    }
}

struct SelineChatThread: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var turns: [SelineChatTurn]
    var updatedAt: Date
    var activeContext: SelineChatActiveContext?
    var providerState: SelineChatProviderState?
    var lastEvidenceBundle: SelineChatEvidenceBundle?

    init(
        id: UUID = UUID(),
        title: String,
        turns: [SelineChatTurn] = [],
        updatedAt: Date = Date(),
        activeContext: SelineChatActiveContext? = nil,
        providerState: SelineChatProviderState? = nil,
        lastEvidenceBundle: SelineChatEvidenceBundle? = nil
    ) {
        self.id = id
        self.title = title
        self.turns = turns
        self.updatedAt = updatedAt
        self.activeContext = activeContext
        self.providerState = providerState
        self.lastEvidenceBundle = lastEvidenceBundle
    }

    var previewText: String {
        turns.reversed()
            .map(\.transcriptText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "No messages yet"
    }
}

struct SelineChatThinkingState: Hashable {
    let threadID: UUID
    let title: String
    let sourceChips: [String]
}

struct SelineChatCompletionContext {
    let payload: SelineChatAssistantPayload
    let providerState: SelineChatProviderState?
    let lastEvidenceBundle: SelineChatEvidenceBundle?
    let turnTrace: SelineChatTurnTrace?
}

enum SelineChatStreamEvent {
    case status(title: String, sourceChips: [String])
    case textDelta(String)
    case completed(SelineChatCompletionContext)
    case failed(String)
}
