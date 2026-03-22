import Foundation

enum TrackerThreadStatus: String, Codable, CaseIterable, Hashable {
    case active
    case archived
}

enum TrackerChatIntent: String, CaseIterable, Hashable, Codable {
    case createTracker = "create_tracker"
    case editRules = "edit_rules"
    case updateState = "update_state"
    case askState = "ask_state"
    case askRules = "ask_rules"
    case whatIf = "what_if"
    case clarification

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "create_tracker":
            self = .createTracker
        case "edit_rules":
            self = .editRules
        case "update_state", "draft_entry":
            self = .updateState
        case "ask_state":
            self = .askState
        case "ask_rules":
            self = .askRules
        case "what_if":
            self = .whatIf
        default:
            self = .clarification
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TrackerOperationType: String, CaseIterable, Hashable, Codable {
    case createTracker
    case updateRules
    case updateState
    case whatIf
    case clarification

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "createTracker":
            self = .createTracker
        case "updateRules":
            self = .updateRules
        case "updateState", "expense", "adjustment", "transfer":
            self = .updateState
        case "whatIf":
            self = .whatIf
        default:
            self = .clarification
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TrackerChangeType: String, CaseIterable, Hashable, Codable {
    case ruleChange = "rule_change"
    case stateUpdate = "state_update"
    case correction
    case note
}

struct TrackerChangeContext: Codable, Hashable {
    var actors: [String]
    var relatedEntities: [String]
    var subject: String?
    var amount: Double?
    var resultingValue: Double?
    var unit: String?
    var periodLabel: String?
    var tags: [String]

    init(
        actors: [String] = [],
        relatedEntities: [String] = [],
        subject: String? = nil,
        amount: Double? = nil,
        resultingValue: Double? = nil,
        unit: String? = nil,
        periodLabel: String? = nil,
        tags: [String] = []
    ) {
        self.actors = actors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.relatedEntities = relatedEntities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = amount
        self.resultingValue = resultingValue
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.periodLabel = periodLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct TrackerChange: Identifiable, Codable, Hashable {
    var id: UUID
    var type: TrackerChangeType
    var title: String?
    var content: String
    var effectiveAt: Date
    var createdAt: Date
    var sourceMessageId: UUID?
    var context: TrackerChangeContext?

    init(
        id: UUID = UUID(),
        type: TrackerChangeType,
        title: String? = nil,
        content: String,
        effectiveAt: Date = Date(),
        createdAt: Date = Date(),
        sourceMessageId: UUID? = nil,
        context: TrackerChangeContext? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.effectiveAt = effectiveAt
        self.createdAt = createdAt
        self.sourceMessageId = sourceMessageId
        self.context = context
    }
}

struct TrackerMemorySnapshot: Codable, Hashable {
    var version: Int
    var title: String
    var rulesText: String
    var currentSummary: String
    var quickFacts: [String]
    var changeLog: [TrackerChange]
    var notes: String?
    var lastUpdatedAt: Date?

    init(
        version: Int = 1,
        title: String,
        rulesText: String,
        currentSummary: String,
        quickFacts: [String] = [],
        changeLog: [TrackerChange] = [],
        notes: String? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.version = version
        self.title = title
        self.rulesText = rulesText
        self.currentSummary = currentSummary
        self.quickFacts = quickFacts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.changeLog = changeLog.sorted { lhs, rhs in
            if lhs.effectiveAt == rhs.effectiveAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.effectiveAt < rhs.effectiveAt
        }
        self.notes = notes
        self.lastUpdatedAt = lastUpdatedAt
    }

    var normalizedRulesText: String {
        rulesText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedSummaryText: String {
        currentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TrackerDerivedState: Hashable, Codable {
    var threadId: UUID
    var asOf: Date
    var ruleSummary: String
    var currentSummary: String
    var quickFacts: [String]
    var recentChanges: [TrackerChange]
    var changeCount: Int
    var headline: String
    var blockers: [String]
    var warnings: [String]
    var lastUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case threadId
        case asOf
        case ruleSummary
        case currentSummary
        case quickFacts
        case recentChanges
        case changeCount
        case headline
        case blockers
        case warnings
        case lastUpdatedAt
    }

    init(
        threadId: UUID,
        asOf: Date = Date(),
        ruleSummary: String,
        currentSummary: String,
        quickFacts: [String] = [],
        recentChanges: [TrackerChange] = [],
        changeCount: Int = 0,
        headline: String,
        blockers: [String] = [],
        warnings: [String] = [],
        lastUpdatedAt: Date? = nil
    ) {
        self.threadId = threadId
        self.asOf = asOf
        self.ruleSummary = ruleSummary
        self.currentSummary = currentSummary
        self.quickFacts = quickFacts
        self.recentChanges = recentChanges
        self.changeCount = changeCount
        self.headline = headline
        self.blockers = blockers
        self.warnings = warnings
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let threadId = try container.decodeIfPresent(UUID.self, forKey: .threadId) ?? UUID()
        let asOf = try container.decodeIfPresent(Date.self, forKey: .asOf) ?? Date()
        let ruleSummary = try container.decodeIfPresent(String.self, forKey: .ruleSummary) ?? "No rules saved yet."
        let decodedCurrentSummary = try container.decodeIfPresent(String.self, forKey: .currentSummary)
        let decodedHeadline = try container.decodeIfPresent(String.self, forKey: .headline)
        let currentSummary = decodedCurrentSummary
            ?? decodedHeadline
            ?? ""
        let quickFacts = try container.decodeIfPresent([String].self, forKey: .quickFacts) ?? []
        let recentChanges = try container.decodeIfPresent([TrackerChange].self, forKey: .recentChanges) ?? []
        let changeCount = try container.decodeIfPresent(Int.self, forKey: .changeCount) ?? recentChanges.count
        let headline = decodedHeadline
            ?? currentSummary.trackerPreviewText
            ?? "Tracker ready."
        let blockers = try container.decodeIfPresent([String].self, forKey: .blockers) ?? []
        let warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        let lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)

        self.init(
            threadId: threadId,
            asOf: asOf,
            ruleSummary: ruleSummary,
            currentSummary: currentSummary,
            quickFacts: quickFacts,
            recentChanges: recentChanges,
            changeCount: changeCount,
            headline: headline,
            blockers: blockers,
            warnings: warnings,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    var summaryLine: String {
        currentSummary.trackerPreviewText
            ?? headline.trackerPreviewText
            ?? "Tracker ready."
    }
}

struct TrackerThread: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var status: TrackerThreadStatus
    var memorySnapshot: TrackerMemorySnapshot
    var cachedState: TrackerDerivedState?
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var subtitle: String?

    init(
        id: UUID = UUID(),
        title: String,
        status: TrackerThreadStatus = .active,
        memorySnapshot: TrackerMemorySnapshot,
        cachedState: TrackerDerivedState? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        subtitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.memorySnapshot = memorySnapshot
        self.cachedState = cachedState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
        self.subtitle = subtitle
    }
}

struct TrackerOperationDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var intent: TrackerChatIntent
    var type: TrackerOperationType
    var requiresConfirmation: Bool
    var summaryText: String
    var assistantResponse: String
    var validationErrors: [String]
    var clarificationPrompt: String?
    var confidence: Double
    var proposedMemorySnapshot: TrackerMemorySnapshot?
    var proposedChange: TrackerChange?
    var projectedState: TrackerDerivedState?

    enum CodingKeys: String, CodingKey {
        case id
        case intent
        case type
        case requiresConfirmation
        case summaryText
        case assistantResponse
        case validationErrors
        case clarificationPrompt
        case confidence
        case proposedMemorySnapshot
        case proposedChange
        case projectedState
    }

    init(
        id: UUID = UUID(),
        intent: TrackerChatIntent,
        type: TrackerOperationType,
        requiresConfirmation: Bool,
        summaryText: String,
        assistantResponse: String,
        validationErrors: [String] = [],
        clarificationPrompt: String? = nil,
        confidence: Double = 1.0,
        proposedMemorySnapshot: TrackerMemorySnapshot? = nil,
        proposedChange: TrackerChange? = nil,
        projectedState: TrackerDerivedState? = nil
    ) {
        self.id = id
        self.intent = intent
        self.type = type
        self.requiresConfirmation = requiresConfirmation
        self.summaryText = summaryText
        self.assistantResponse = assistantResponse
        self.validationErrors = validationErrors
        self.clarificationPrompt = clarificationPrompt
        self.confidence = confidence
        self.proposedMemorySnapshot = proposedMemorySnapshot
        self.proposedChange = proposedChange
        self.projectedState = projectedState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.intent = try container.decodeIfPresent(TrackerChatIntent.self, forKey: .intent) ?? .clarification
        self.type = try container.decodeIfPresent(TrackerOperationType.self, forKey: .type) ?? .clarification
        self.requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? true
        self.summaryText = try container.decodeIfPresent(String.self, forKey: .summaryText) ?? ""
        self.assistantResponse = try container.decodeIfPresent(String.self, forKey: .assistantResponse) ?? ""
        self.validationErrors = try container.decodeIfPresent([String].self, forKey: .validationErrors) ?? []
        self.clarificationPrompt = try container.decodeIfPresent(String.self, forKey: .clarificationPrompt)
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        self.proposedMemorySnapshot = try container.decodeIfPresent(TrackerMemorySnapshot.self, forKey: .proposedMemorySnapshot)
        self.proposedChange = try container.decodeIfPresent(TrackerChange.self, forKey: .proposedChange)
        self.projectedState = try container.decodeIfPresent(TrackerDerivedState.self, forKey: .projectedState)
    }
}

struct TrackerParserResult: Codable, Hashable {
    var intent: TrackerChatIntent
    var draft: TrackerOperationDraft?
    var responseText: String
    var shouldPersistAssistantMessage: Bool
}

enum TrackerSyncState: String, Codable, Hashable {
    case idle
    case syncing
    case failed
}

struct TrackerRemoteThreadRecord: Codable, Hashable {
    var id: UUID
    var title: String
    var status: String
    var rule_json: String
    var summary_text: String?
    var subtitle: String?
    var updated_at: String
    var created_at: String
}

struct TrackerRemoteMessageRecord: Codable, Hashable {
    var id: UUID
    var tracker_thread_id: UUID
    var is_user: Bool
    var text: String
    var draft_json: String?
    var state_json: String?
    var created_at: String
}

enum TrackerRuleSummaryBuilder {
    static func summary(for snapshot: TrackerMemorySnapshot) -> String {
        let rules = snapshot.normalizedRulesText
        return rules.isEmpty ? "No rules saved yet." : rules
    }
}

extension String {
    var trackerNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trackerPreviewText: String? {
        guard let trimmed = trackerNonEmpty else { return nil }

        let collapsedWhitespace = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        guard collapsedWhitespace.count > 96 else {
            return collapsedWhitespace
        }

        let endIndex = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: 93)
        let prefixText = String(collapsedWhitespace[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefixText + "..."
    }
}
