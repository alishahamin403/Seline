import Foundation

enum AgentEntityType: String, Codable, Hashable, CaseIterable {
    case email
    case note
    case event
    case location
    case visit
    case person
    case receipt
    case daySummary
    case nearbyPlace
    case currentContext
    case aggregate
    case webResult
}

struct EntityRef: Codable, Hashable, Identifiable {
    let type: AgentEntityType
    let id: String
    let title: String?

    var identifier: String {
        "\(type.rawValue):\(id)"
    }
}

struct EvidenceTimestamp: Codable, Hashable {
    let label: String
    let value: String
}

struct ResolvedDateBounds: Codable, Hashable {
    let start: Date
    let end: Date
}

struct EvidenceRelation: Codable, Hashable {
    let type: String
    let label: String?
    let target: EntityRef
}

struct EvidenceRecord: Hashable, Identifiable {
    let id: String
    let ref: EntityRef
    let title: String
    let summary: String
    let timestamps: [EvidenceTimestamp]
    let attributes: [String: String]
    let relations: [EvidenceRelation]
    /// Which tool retrieved this record. Empty string for records decoded from old stored data.
    let sourceTool: String

    init(
        ref: EntityRef,
        title: String,
        summary: String,
        timestamps: [EvidenceTimestamp] = [],
        attributes: [String: String] = [:],
        relations: [EvidenceRelation] = [],
        sourceTool: String = ""
    ) {
        self.id = ref.identifier
        self.ref = ref
        self.title = title
        self.summary = summary
        self.timestamps = timestamps
        self.attributes = attributes
        self.relations = relations
        self.sourceTool = sourceTool
    }

    func withSourceTool(_ tool: String) -> EvidenceRecord {
        EvidenceRecord(
            ref: ref,
            title: title,
            summary: summary,
            timestamps: timestamps,
            attributes: attributes,
            relations: relations,
            sourceTool: tool
        )
    }
}

extension EvidenceRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, ref, title, summary, timestamps, attributes, relations, sourceTool
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ref = try c.decode(EntityRef.self, forKey: .ref)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        timestamps = (try? c.decode([EvidenceTimestamp].self, forKey: .timestamps)) ?? []
        attributes = (try? c.decode([String: String].self, forKey: .attributes)) ?? [:]
        relations = (try? c.decode([EvidenceRelation].self, forKey: .relations)) ?? []
        // sourceTool was added in a later version; default to "" for old stored records
        sourceTool = (try? c.decode(String.self, forKey: .sourceTool)) ?? ""
    }
}

struct ToolAggregateRow: Codable, Hashable, Identifiable {
    let id: UUID
    let key: String
    let value: String
    let numericValue: Double?
    let ref: EntityRef?

    init(
        id: UUID = UUID(),
        key: String,
        value: String,
        numericValue: Double? = nil,
        ref: EntityRef? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.numericValue = numericValue
        self.ref = ref
    }
}

struct ToolAggregate: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let metric: String
    let groupBy: String?
    let rows: [ToolAggregateRow]
    let summary: String?

    init(
        id: UUID = UUID(),
        title: String,
        metric: String,
        groupBy: String? = nil,
        rows: [ToolAggregateRow],
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.metric = metric
        self.groupBy = groupBy
        self.rows = rows
        self.summary = summary
    }
}

struct ToolAmbiguity: Codable, Hashable, Identifiable {
    let id: UUID
    let question: String
    let options: [String]

    init(id: UUID = UUID(), question: String, options: [String]) {
        self.id = id
        self.question = question
        self.options = options
    }
}

struct ToolCitation: Codable, Hashable, Identifiable {
    let id: UUID
    let ref: EntityRef
    let label: String

    init(id: UUID = UUID(), ref: EntityRef, label: String) {
        self.id = id
        self.ref = ref
        self.label = label
    }
}

struct ToolResult: Codable, Hashable {
    let toolName: String
    let records: [EvidenceRecord]
    let aggregates: [ToolAggregate]
    let ambiguities: [ToolAmbiguity]
    let citations: [ToolCitation]
    let resolvedTimeRange: String?
    let resolvedDateBounds: ResolvedDateBounds?
    let actionDraft: AgentActionDraft?
    let presentation: AgentPresentation?
    /// True when the tool hit its result cap and may have more matching data.
    let isTruncated: Bool

    init(
        toolName: String,
        records: [EvidenceRecord] = [],
        aggregates: [ToolAggregate] = [],
        ambiguities: [ToolAmbiguity] = [],
        citations: [ToolCitation] = [],
        resolvedTimeRange: String? = nil,
        resolvedDateBounds: ResolvedDateBounds? = nil,
        actionDraft: AgentActionDraft? = nil,
        presentation: AgentPresentation? = nil,
        isTruncated: Bool = false
    ) {
        self.toolName = toolName
        self.records = records
        self.aggregates = aggregates
        self.ambiguities = ambiguities
        self.citations = citations
        self.resolvedTimeRange = resolvedTimeRange
        self.resolvedDateBounds = resolvedDateBounds
        self.actionDraft = actionDraft
        self.presentation = presentation
        self.isTruncated = isTruncated
    }
}

enum AgentActionType: String, Codable, Hashable {
    case createEvent
    case createNote
    case latestEmail
    case saveLocation
}

enum AgentActionDraftStatus: String, Codable, Hashable {
    case pending
    case confirmed
    case cancelled
}

struct NoteDraftInfo: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let folderId: UUID?
    let folderName: String?
    let isUpdate: Bool

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        folderId: UUID? = nil,
        folderName: String? = nil,
        isUpdate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.folderName = folderName
        self.isUpdate = isUpdate
    }
}

struct EmailPreviewInfo: Codable, Hashable, Identifiable {
    let id: String
    let emailId: String
    let senderName: String
    let senderEmail: String?
    let subject: String
    let timestamp: Date
    let summary: String
    let bodyPreview: String
    let body: String?
    let gmailMessageId: String?
    let attachments: [EmailAttachment]

    init(
        emailId: String,
        senderName: String,
        senderEmail: String?,
        subject: String,
        timestamp: Date,
        summary: String,
        bodyPreview: String,
        body: String?,
        gmailMessageId: String?,
        attachments: [EmailAttachment]
    ) {
        self.id = emailId
        self.emailId = emailId
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.subject = subject
        self.timestamp = timestamp
        self.summary = summary
        self.bodyPreview = bodyPreview
        self.body = body
        self.gmailMessageId = gmailMessageId
        self.attachments = attachments
    }
}

struct SavedPlaceDraftInfo: Codable, Hashable, Identifiable {
    let id: String
    let place: PlaceSearchResult
    let folderName: String?

    init(place: PlaceSearchResult, folderName: String? = nil) {
        self.id = place.id
        self.place = place
        self.folderName = folderName
    }
}

struct LivePlacePreviewInfo: Codable, Hashable, Identifiable {
    let id: String
    let results: [PlaceSearchResult]
    let selectedPlaceId: String?
    let prompt: String?

    init(
        results: [PlaceSearchResult],
        selectedPlaceId: String? = nil,
        prompt: String? = nil
    ) {
        self.id = selectedPlaceId ?? results.first?.id ?? UUID().uuidString
        self.results = results
        self.selectedPlaceId = selectedPlaceId
        self.prompt = prompt
    }
}

struct AgentActionDraft: Codable, Hashable, Identifiable {
    let id: UUID
    let type: AgentActionType
    let status: AgentActionDraftStatus
    let requiresConfirmation: Bool
    let eventDrafts: [EventCreationInfo]?
    let noteDraft: NoteDraftInfo?
    let emailPreview: EmailPreviewInfo?
    let placeDraft: SavedPlaceDraftInfo?

    init(
        id: UUID = UUID(),
        type: AgentActionType,
        status: AgentActionDraftStatus = .pending,
        requiresConfirmation: Bool = true,
        eventDrafts: [EventCreationInfo]? = nil,
        noteDraft: NoteDraftInfo? = nil,
        emailPreview: EmailPreviewInfo? = nil,
        placeDraft: SavedPlaceDraftInfo? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.requiresConfirmation = requiresConfirmation
        self.eventDrafts = eventDrafts
        self.noteDraft = noteDraft
        self.emailPreview = emailPreview
        self.placeDraft = placeDraft
    }
}

struct AgentPresentation: Codable, Hashable {
    let eventDraftCard: [EventCreationInfo]?
    let noteDraftCard: NoteDraftInfo?
    let emailPreviewCard: EmailPreviewInfo?
    let livePlaceCard: LivePlacePreviewInfo?

    init(
        eventDraftCard: [EventCreationInfo]? = nil,
        noteDraftCard: NoteDraftInfo? = nil,
        emailPreviewCard: EmailPreviewInfo? = nil,
        livePlaceCard: LivePlacePreviewInfo? = nil
    ) {
        self.eventDraftCard = eventDraftCard
        self.noteDraftCard = noteDraftCard
        self.emailPreviewCard = emailPreviewCard
        self.livePlaceCard = livePlaceCard
    }
}

struct ConversationAnchorState: Codable, Hashable {
    let resolvedEntities: [EntityRef]
    let resolvedTimeRange: String?
    let resolvedDateBounds: ResolvedDateBounds?
    let comparisonWindow: String?
    let lastLivePlaceResults: [PlaceSearchResult]?
    let lastActionDraft: AgentActionDraft?

    init(
        resolvedEntities: [EntityRef] = [],
        resolvedTimeRange: String? = nil,
        resolvedDateBounds: ResolvedDateBounds? = nil,
        comparisonWindow: String? = nil,
        lastLivePlaceResults: [PlaceSearchResult]? = nil,
        lastActionDraft: AgentActionDraft? = nil
    ) {
        self.resolvedEntities = resolvedEntities
        self.resolvedTimeRange = resolvedTimeRange
        self.resolvedDateBounds = resolvedDateBounds
        self.comparisonWindow = comparisonWindow
        self.lastLivePlaceResults = lastLivePlaceResults
        self.lastActionDraft = lastActionDraft
    }
}

struct AgentToolTrace: Codable, Hashable, Identifiable {
    let id: UUID
    let toolName: String
    let argumentsJSON: String
    let resultPreview: String
    let latencyMs: Int

    init(
        id: UUID = UUID(),
        toolName: String,
        argumentsJSON: String,
        resultPreview: String,
        latencyMs: Int
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.resultPreview = resultPreview
        self.latencyMs = latencyMs
    }
}

/// Describes the completeness of evidence retrieved during a planning loop.
struct EvidenceBundleMetadata: Codable, Hashable {
    /// All tools that were successfully called this turn.
    let toolsUsed: [String]
    /// Tools that hit their result cap and may have more matching data.
    let truncatedTools: [String]

    var isComplete: Bool { truncatedTools.isEmpty }
}

struct EvidenceBundle: Codable, Hashable {
    let records: [EvidenceRecord]
    let aggregates: [ToolAggregate]
    let citations: [ToolCitation]
    let ambiguities: [ToolAmbiguity]?
    let anchorState: ConversationAnchorState?
    let metadata: EvidenceBundleMetadata?

    init(
        records: [EvidenceRecord] = [],
        aggregates: [ToolAggregate] = [],
        citations: [ToolCitation] = [],
        ambiguities: [ToolAmbiguity]? = nil,
        anchorState: ConversationAnchorState? = nil,
        metadata: EvidenceBundleMetadata? = nil
    ) {
        self.records = records
        self.aggregates = aggregates
        self.citations = citations
        self.ambiguities = ambiguities
        self.anchorState = anchorState
        self.metadata = metadata
    }
}

struct AgentTurnResult: Codable {
    let assistantText: String
    let evidenceBundle: EvidenceBundle
    let toolTrace: [AgentToolTrace]
    let locationInfo: ETALocationInfo?
    let actionDraft: AgentActionDraft?
    let presentation: AgentPresentation?
    let usedLiveWeb: Bool
    let model: String

    var responseText: String {
        assistantText
    }
}

struct AgentTurnInput: Codable {
    let userMessage: String
    let conversationHistory: [ConversationMessage]
    let anchorState: ConversationAnchorState?
    let sessionSnapshot: ConversationSessionSnapshot?
    let allowLiveSearch: Bool

    init(
        userMessage: String,
        conversationHistory: [ConversationMessage],
        anchorState: ConversationAnchorState? = nil,
        sessionSnapshot: ConversationSessionSnapshot? = nil,
        allowLiveSearch: Bool = true
    ) {
        self.userMessage = userMessage
        self.conversationHistory = conversationHistory
        self.anchorState = anchorState
        self.sessionSnapshot = sessionSnapshot
        self.allowLiveSearch = allowLiveSearch
    }
}
