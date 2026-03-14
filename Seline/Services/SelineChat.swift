import Foundation

/// Main conversation manager for Seline - simpler, more direct approach
/// Uses LLM intelligence instead of pre-processing
///
/// Architecture:
/// - VectorContextBuilder: Uses semantic search for relevant context (NEW - faster!)
/// - SelineAppContext: Legacy context building (fallback)
/// - SelineChat: Manages conversation history and LLM communication
/// - Streaming support: Real-time response chunks with UI callbacks
///
/// Key design principle: Let the LLM be smart. Send ONLY relevant context
/// using vector embeddings for faster, more accurate responses.
@MainActor
class SelineChat: ObservableObject {
    // MARK: - State

    @Published var conversationHistory: [ChatMessage] = []
    let appContext: SelineAppContext
    private let vectorContextBuilder = VectorContextBuilder.shared
    private let vectorSearchService = VectorSearchService.shared
    private let compositeEpisodeResolver = CompositeEpisodeResolver.shared
    private let geminiService: GeminiService
    private let userProfileService: UserProfileService
    private let userMemoryService = UserMemoryService.shared
    @Published var isStreaming = false
    private var shouldCancelStreaming = false
    private var cachedHistorySummary = ""
    private var cachedHistorySummaryTurnCount = 0
    private let summaryRefreshTurnDelta = 4
    private var lastResolvedVisitPlaceId: UUID?
    private var lastResolvedVisitPlaceName: String?
    /// Toggle for using vector search (set to false to use legacy context building)
    /// Default: true for faster, more relevant responses
    var useVectorSearch = true

    // MARK: - Callbacks

    var onMessageAdded: ((ChatMessage) -> Void)?
    var onStreamingChunk: ((String) -> Void)?
    var onStreamingComplete: (() -> Void)?
    var onStreamingStateChanged: ((Bool) -> Void)? // Notify when streaming starts/stops

    // MARK: - Public Properties

    /// True when LLM is actively streaming a response
    var isCurrentlyStreaming: Bool {
        isStreaming
    }

    // MARK: - Init

    init(
        appContext: SelineAppContext? = nil,
        geminiService: GeminiService? = nil,
        userProfileService: UserProfileService? = nil
    ) {
        self.appContext = appContext ?? SelineAppContext()
        self.geminiService = geminiService ?? GeminiService.shared
        self.userProfileService = userProfileService ?? .shared
    }

    // MARK: - Main Chat Interface

    /// Send a message and get a response
    func sendMessage(_ userMessage: String, streaming: Bool = true) async -> String {
        // Avoid duplicate user turns when callers already appended this message.
        let shouldAppendUserMessage = !(conversationHistory.last?.role == .user && conversationHistory.last?.content == userMessage)
        if shouldAppendUserMessage {
            let userMsg = ChatMessage(role: .user, content: userMessage, timestamp: Date())
            conversationHistory.append(userMsg)
            onMessageAdded?(userMsg)
        }

        print("💬 User: \(userMessage)")

        // Build the system prompt with app context
        let systemPrompt = await buildSystemPrompt()

        // Build messages for API (with summarized older turns when history is long)
        let messages = await buildMessagesForAPIAsync()

        // Get response
        let response: String
        if streaming {
            response = await getStreamingResponse(systemPrompt: systemPrompt, messages: messages)
        } else {
            response = await getNonStreamingResponse(systemPrompt: systemPrompt, messages: messages)
        }

        // Add assistant response to history
        let assistantMsg = ChatMessage(role: .assistant, content: response, timestamp: Date())
        conversationHistory.append(assistantMsg)
        onMessageAdded?(assistantMsg)

        print("🤖 Assistant: \(response)")
        
        // Extract and store any learnable memories from the conversation
        Task {
            await extractAndStoreMemories(userMessage: userMessage, assistantResponse: response)
        }

        return response
    }

    /// Returns the effective query to use for retrieval/context for the latest user turn.
    /// If the user wrote only "try again"/"again"/"retry", reuse the previous substantive user query.
    func contextQueryForLatestUserTurn() -> String {
        effectiveContextQueryForCurrentTurn()
    }

    func updateResolvedVisitPlace(from relevantContent: [RelevantContentInfo]?) {
        guard let relevantContent, !relevantContent.isEmpty else { return }

        if let visit = relevantContent.first(where: {
            $0.contentType == .visit && ($0.visitPlaceId != nil || $0.visitPlaceName?.isEmpty == false)
        }) {
            lastResolvedVisitPlaceId = visit.visitPlaceId ?? visit.locationId
            lastResolvedVisitPlaceName = visit.visitPlaceName ?? visit.locationName
            return
        }

        if let location = relevantContent.first(where: {
            $0.contentType == .location && ($0.locationId != nil || $0.locationName?.isEmpty == false)
        }) {
            lastResolvedVisitPlaceId = location.locationId
            lastResolvedVisitPlaceName = location.locationName
        }
    }
    
    // MARK: - Memory Extraction
    
    /// Extract learnable information from conversation and store as memories
    private func extractAndStoreMemories(userMessage: String, assistantResponse: String) async {
        // Pattern-based extraction for common memory types
        let patterns: [(pattern: String, type: UserMemoryService.MemoryType, keyGroup: Int, valueGroup: Int)] = [
            // "X is for Y" / "X is my Y"
            (#"(?i)(\w+(?:\s+\w+)?)\s+is\s+(?:for\s+)?(?:my\s+)?(\w+(?:\s+\w+)?(?:\s+place)?)"#, .entityRelationship, 1, 2),
            // "I go to X for Y"
            (#"(?i)I\s+go\s+to\s+(\w+(?:\s+\w+)?)\s+for\s+(\w+(?:\s+\w+)?)"#, .entityRelationship, 1, 2),
            // "X means Y" / "X = Y"
            (#"(?i)(\w+(?:\s+\w+)?)\s+(?:means|=)\s+(\w+(?:\s+\w+)?)"#, .entityRelationship, 1, 2),
        ]
        
        for (pattern, memoryType, keyGroup, valueGroup) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: userMessage, options: [], range: NSRange(userMessage.startIndex..., in: userMessage)) {
                
                if let keyRange = Range(match.range(at: keyGroup), in: userMessage),
                   let valueRange = Range(match.range(at: valueGroup), in: userMessage) {
                    
                    let key = String(userMessage[keyRange]).trimmingCharacters(in: .whitespaces)
                    let value = String(userMessage[valueRange]).trimmingCharacters(in: .whitespaces)
                    
                    // Skip generic/short values
                    guard key.count > 1, value.count > 1,
                          !["the", "a", "an", "my", "is", "for"].contains(key.lowercased()),
                          !["the", "a", "an", "my", "is", "for"].contains(value.lowercased()) else {
                        continue
                    }
                    
                    do {
                        try await userMemoryService.storeMemory(
                            type: memoryType,
                            key: key,
                            value: value,
                            context: "Extracted from conversation",
                            confidence: 0.7,
                            source: .conversation
                        )
                        print("🧠 Learned: \(key) → \(value)")
                    } catch {
                        print("⚠️ Failed to store memory: \(error)")
                    }
                }
            }
        }
    }

    /// Clear conversation history and refresh data
    func clearHistory() async {
        conversationHistory = []
        resetHistorySummaryCache()
        lastResolvedVisitPlaceId = nil
        lastResolvedVisitPlaceName = nil
        vectorContextBuilder.clearConversationAnchors()
        await appContext.refresh()
        
        // Sync embeddings in background for next conversation
        Task {
            await vectorSearchService.syncEmbeddingsIfNeeded()
        }
    }

    /// Cancel the currently streaming response
    func cancelStreaming() {
        print("🛑 Cancelling streaming response...")
        shouldCancelStreaming = true
    }

    /// Get context size estimate (for display)
    /// Always uses vector search now - legacy path removed
    func getContextSizeEstimate() async -> String {
        // Always use vector context for estimates
        let result = await vectorContextBuilder.buildContext(forQuery: "example query")
        return "~\(result.metadata.estimatedTokens) tokens (vector)"
    }

    // MARK: - Greeting
    
    /// Get greeting for a specific date
    private func getTimeBasedGreeting(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Hello"
        }
    }
    


    /// Generate a proactive morning/daily briefing without user input
    /// Cost-efficient version: Uses simple greeting instead of LLM summary
    func generateMorningBriefing() async {
        guard conversationHistory.isEmpty else { return }
        
        // Simple token-free greeting
        let greeting = getTimeBasedGreeting()
        let name = userProfileService.profile.name ?? "there"

        let content = "\(greeting), \(name)! How can I help you today?"
        
        let assistantMsg = ChatMessage(role: .assistant, content: content, timestamp: Date())
        conversationHistory.append(assistantMsg)
        onMessageAdded?(assistantMsg)
    }

    // MARK: - Private: System Prompt

    private func buildSystemPrompt() async -> String {
        // Get the effective context query for the current turn.
        let userMessage = effectiveContextQueryForCurrentTurn()

        if shouldWarmJournalEmbeddings(for: userMessage) {
            await vectorSearchService.ensureJournalNoteEmbeddingsCurrent()
        }

        // OPTIMIZATION: Always use vector-based context builder for better performance
        let contextPrompt: String

        if !userMessage.isEmpty {
            // Main path: vector-based semantic search (the critical path for response)
            // Convert conversation history to format expected by VectorContextBuilder
            let historyForContext = conversationHistory.map { msg in
                (role: msg.role == .user ? "user" : "assistant", content: msg.content)
            }
            let result = await vectorContextBuilder.buildContext(forQuery: userMessage, conversationHistory: historyForContext)
            contextPrompt = result.context
            appContext.setLastRelevantContent(result.evidence.isEmpty ? nil : result.evidence)

            print("🔍 Vector search: \(result.metadata.estimatedTokens) tokens (optimized from legacy ~10K+)")

            // DEBUG: Log context preview for diagnostics
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEBUG_CONTEXT"] != nil {
                print("🔍 FULL CONTEXT BEING SENT TO LLM:")
                print(String(repeating: "=", count: 80))
                print(contextPrompt)
                print(String(repeating: "=", count: 80))
            } else {
                // Production: Log first 500 chars for quick diagnostics
                let preview = String(contextPrompt.prefix(500))
                print("🔍 Context preview (first 500 chars):\n\(preview)...")
            }
            #else
            // In release builds, just log a preview
            let preview = String(contextPrompt.prefix(300))
            print("🔍 Context preview: \(preview)...")
            #endif
        } else {
            // For empty queries, use minimal essential context
            // Vector search needs a query to work with
            let historyForContext = conversationHistory.map { msg in
                (role: msg.role == .user ? "user" : "assistant", content: msg.content)
            }
            let result = await vectorContextBuilder.buildContext(forQuery: "general status update", conversationHistory: historyForContext)
            contextPrompt = result.context
            appContext.setLastRelevantContent(result.evidence.isEmpty ? nil : result.evidence)
            print("📊 Empty query: Using minimal essential context (\(result.metadata.estimatedTokens) tokens)")
        }
            
        // Get User Profile Context
        let userProfile = userProfileService.getProfileContext()
        let sourceReferencePrompt = buildSourceReferencePrompt()
        return buildChatModePrompt(
            userProfile: userProfile,
            contextPrompt: contextPrompt,
            sourceReferencePrompt: sourceReferencePrompt
        )
    }

    private func effectiveContextQueryForCurrentTurn() -> String {
        guard let lastUserMessage = conversationHistory.last(where: { $0.role == .user })?.content else {
            return ""
        }
        let trimmed = lastUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRetryFollowUpMessage(trimmed) {
            for message in conversationHistory.dropLast().reversed() where message.role == .user {
                let candidate = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && !isRetryFollowUpMessage(candidate) {
                    print("🔁 Retry follow-up detected; reusing previous user query for context: '\(candidate.prefix(80))'")
                    return candidate
                }
            }
            return trimmed
        }

        if let contextualQuery = contextualFollowUpQuery(for: trimmed) {
            return contextualQuery
        }

        return trimmed
    }

    private func contextualFollowUpQuery(for text: String) -> String? {
        let normalized = normalizedFollowUpText(text)
        guard isContextDependentFollowUpMessage(normalized) else { return nil }
        guard let previousQuery = previousSubstantiveUserQuery() else { return nil }

        let scopePhrase = followUpScopePhrase(currentFollowUp: normalized, previousQuery: previousQuery)
        let explicitCurrentScope = explicitScopePhrase(in: normalized)
        let shouldCarryPreviousTopic = shouldCarryPreviousTopic(for: normalized)
        let resolvedQuery: String

        if isShowAllFollowUp(normalized) {
            if let scopePhrase {
                resolvedQuery = "Show all \(scopePhrase) for \(previousQuery)"
            } else {
                resolvedQuery = "Show all results for \(previousQuery)"
            }
        } else if isShowMoreFollowUp(normalized) {
            if let scopePhrase {
                resolvedQuery = "Show more \(scopePhrase) for \(previousQuery)"
            } else {
                resolvedQuery = "Show more for \(previousQuery)"
            }
        } else if shouldCarryPreviousTopic, let scopePhrase {
            resolvedQuery = "For \(previousQuery), \(text). Focus on \(scopePhrase)."
        } else if shouldCarryPreviousTopic {
            resolvedQuery = "For \(previousQuery), \(text)"
        } else if explicitCurrentScope != nil {
            resolvedQuery = text
        } else if let scopePhrase {
            resolvedQuery = "\(text). Focus on \(scopePhrase)."
        } else {
            resolvedQuery = text
        }

        print("🔁 Contextual follow-up detected; resolved '\(text.prefix(60))' → '\(resolvedQuery.prefix(120))'")
        return resolvedQuery
    }

    private func followUpScopePhrase(currentFollowUp normalizedFollowUp: String, previousQuery: String) -> String? {
        if let explicitScope = explicitScopePhrase(in: normalizedFollowUp) {
            return explicitScope
        }

        if let priorScope = dominantRelevantContentScopePhrase() {
            return priorScope
        }

        return inferredScopePhrase(from: normalizedFollowUpText(previousQuery))
    }

    private func previousSubstantiveUserQuery() -> String? {
        for message in conversationHistory.dropLast().reversed() where message.role == .user {
            let candidate = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }

            let normalized = normalizedFollowUpText(candidate)
            if isRetryFollowUpMessage(candidate) || isContextDependentFollowUpMessage(normalized) {
                continue
            }

            return candidate
        }
        return nil
    }

    private func explicitScopePhrase(in normalized: String) -> String? {
        let scopeSignals: [(phrase: String, signals: [String])] = [
            ("receipts", ["receipt", "receipts", "purchase", "purchases", "spent", "spend", "amount", "amounts", "pay", "paid", "cost", "costs", "total"]),
            ("visits", ["visit", "visits", "visited", "went", "go", "place", "places", "location", "locations", "where"]),
            ("emails", ["email", "emails", "inbox", "message", "messages"]),
            ("notes", ["note", "notes", "journal", "journals"]),
            ("events", ["event", "events", "calendar", "meeting", "meetings", "appointment", "appointments"]),
            ("people", ["person", "people", "contact", "contacts"])
        ]

        for (phrase, signals) in scopeSignals where signals.contains(where: { containsNormalizedSignal(normalized, signal: $0) }) {
            return phrase
        }

        return nil
    }

    private func inferredScopePhrase(from normalizedQuery: String) -> String? {
        explicitScopePhrase(in: normalizedQuery)
    }

    private func shouldCarryPreviousTopic(for normalized: String) -> Bool {
        if isShowAllFollowUp(normalized) || isShowMoreFollowUp(normalized) {
            return true
        }

        let topicalTokens = followUpTopicalTokens(in: normalized)
        if normalized.hasPrefix("how about ") || normalized.hasPrefix("what about ") {
            return topicalTokens.count <= 2
        }

        return topicalTokens.count <= 1
    }

    private func followUpTopicalTokens(in normalized: String) -> [String] {
        let ignoredTokens: Set<String> = [
            "show", "tell", "me", "for", "about", "all", "more", "everything",
            "what", "how", "only", "just", "the", "a", "an", "please",
            "that", "those", "them", "it", "same", "instead", "any"
        ]

        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                !token.isEmpty && !ignoredTokens.contains(token)
            }
    }

    private func containsNormalizedSignal(_ normalized: String, signal: String) -> Bool {
        let padded = " \(normalized) "
        return padded.contains(" \(signal) ")
    }

    private func dominantRelevantContentScopePhrase() -> String? {
        guard let sources = appContext.lastRelevantContent, !sources.isEmpty else { return nil }

        let counts = Dictionary(grouping: sources, by: \.contentType).mapValues(\.count)
        guard let dominantType = counts.max(by: { $0.value < $1.value }) else { return nil }
        let uniqueTypeCount = counts.keys.count

        if uniqueTypeCount > 1 && dominantType.value < max(2, sources.count / 2) {
            return nil
        }

        switch dominantType.key {
        case .receipt:
            return "receipts"
        case .visit:
            return "visits"
        case .location:
            return "locations"
        case .email:
            return "emails"
        case .note:
            return "notes"
        case .event:
            return "events"
        case .person:
            return "people"
        }
    }

    private func normalizedFollowUpText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isContextDependentFollowUpMessage(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return false }

        let exactFollowUps: Set<String> = [
            "show all",
            "show more",
            "more",
            "everything",
            "all of them",
            "all",
            "what else",
            "anything else",
            "only receipts",
            "just receipts",
            "only visits",
            "just visits",
            "only emails",
            "just emails",
            "only notes",
            "just notes",
            "only events",
            "just events",
            "how much",
            "how much total"
        ]

        if exactFollowUps.contains(normalized) {
            return true
        }

        let referentialTerms = [
            "that",
            "those",
            "them",
            "it",
            "same",
            "instead",
            "only",
            "just",
            "what about",
            "how about"
        ]

        if referentialTerms.contains(where: { normalized.contains($0) }) {
            return true
        }

        let fillerWords: Set<String> = [
            "show", "tell", "me", "for", "about", "all", "more", "everything",
            "what", "how", "only", "just", "the", "a", "an", "please"
        ]
        let meaningfulTokens = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !fillerWords.contains($0) }

        return meaningfulTokens.count <= 1
    }

    private func isShowAllFollowUp(_ normalized: String) -> Bool {
        let showAllSignals = [
            "show all",
            "all",
            "everything",
            "all of them",
            "what else",
            "anything else"
        ]
        return showAllSignals.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") })
    }

    private func isShowMoreFollowUp(_ normalized: String) -> Bool {
        let showMoreSignals = [
            "show more",
            "more",
            "more of them"
        ]
        return showMoreSignals.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") })
    }

    private func shouldWarmJournalEmbeddings(for query: String) -> Bool {
        let lowercased = query.lowercased()
        let journalSignals = [
            "journal",
            "diary",
            "weekly recap",
            "weekly summary",
            "journal recap",
            "journal summary"
        ]
        return journalSignals.contains(where: { lowercased.contains($0) })
    }

    private func isRetryFollowUpMessage(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let exactRetryPhrases: Set<String> = [
            "again",
            "try again",
            "retry",
            "one more time",
            "try that again",
            "answer again",
            "do it again"
        ]
        if exactRetryPhrases.contains(normalized) {
            return true
        }

        let words = normalized.split(separator: " ")
        if words.count <= 4 {
            if normalized.contains("again") || normalized.contains("retry") {
                return true
            }
        }
        return false
    }

    private struct DeterministicVisitResponse {
        let response: String
        let evidence: [RelevantContentInfo]
    }

    private struct LinkedReceiptEvidence {
        let note: Note
        let amount: Double
        let date: Date
        let category: String
        let explicit: Bool
        let linkedPeople: [Person]
    }

    private func deterministicEpisodeFactResponseIfNeeded(for userMessage: String) async -> DeterministicVisitResponse? {
        guard isDeterministicHistoricalEpisodeQuery(userMessage) else { return nil }

        let history = conversationHistory.map { message in
            (role: message.role == .user ? "user" : "assistant", content: message.content)
        }

        guard let result = await compositeEpisodeResolver.resolve(
            query: userMessage,
            conversationHistory: history
        ) else {
            return nil
        }

        guard case .resolved(let resolution) = result else {
            return nil
        }

        guard shouldAutoAnswerEpisodeResolution(resolution) else { return nil }

        return DeterministicVisitResponse(
            response: renderEpisodeResolution(resolution, query: userMessage),
            evidence: resolution.evidence
        )
    }

    private func shouldAutoAnswerEpisodeResolution(
        _ resolution: CompositeEpisodeResolver.EpisodeResolution
    ) -> Bool {
        if resolution.matchQuality == .exact {
            return true
        }

        if resolution.semanticSupportScore >= 3.5 {
            return true
        }

        if resolution.jointMatchCount > 0 || resolution.proximityMatchCount > 0 {
            return resolution.confidence >= 0.34
        }

        return resolution.confidence >= 0.44
    }

    private func isDeterministicHistoricalEpisodeQuery(_ query: String) -> Bool {
        let lower = " " + query.lowercased() + " "
        let temporalSignals = [
            " when ",
            " last time ",
            " most recent ",
            " latest ",
            " last visit ",
            " last went ",
            " which weekend ",
            " what weekend ",
            " which trip ",
            " what trip ",
            " did i ever ",
            " have i ever "
        ]
        let visitSignals = [
            " go ",
            " went ",
            " visit ",
            " visited ",
            " trip ",
            " stay ",
            " weekend ",
            " spent ",
            " travel ",
            " vacation "
        ]
        let hasTemporalSignal = temporalSignals.contains { lower.contains($0) }
        let hasVisitSignal = visitSignals.contains { lower.contains($0) }
        let hasPersonLikeCue = PeopleManager.shared.people.contains { person in
            let aliases = [person.name, person.nickname]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return aliases.contains { alias in
                !alias.isEmpty && lower.contains(" \(alias) ")
            }
        }
        let hasLocationCue = lower.contains(" to ")
            || lower.contains(" at ")
            || lower.contains(" in ")
            || lower.range(of: #"\b[a-z]{3,}\b\s+with\b"#, options: .regularExpression) != nil

        let hasCompositeFacetCue = hasPersonLikeCue && hasLocationCue
        return hasTemporalSignal && (hasVisitSignal || hasCompositeFacetCue) && (hasPersonLikeCue || hasLocationCue)
    }

    private func renderEpisodeResolution(
        _ resolution: CompositeEpisodeResolver.EpisodeResolution,
        query: String
    ) -> String {
        let lower = query.lowercased()
        let dateLabel = formattedEpisodeRange(start: resolution.start, end: resolution.end)
        let visitCitation = resolution.evidence.firstIndex(where: { $0.contentType == .visit }).map { "[[\($0)]]" } ?? ""
        let personCitation = resolution.evidence.firstIndex(where: { $0.contentType == .person }).map { "[[\($0)]]" }
        let locationCitation = resolution.evidence.firstIndex(where: { $0.contentType == .location }).map { "[[\($0)]]" }
        let supportCitation = resolution.evidence.firstIndex(where: {
            $0.contentType == .note || $0.contentType == .email || $0.contentType == .receipt || $0.contentType == .event
        }).map { "[[\($0)]]" }
        let peopleLabel = resolution.matchedPeople.map(\.name).joined(separator: ", ")
        let geoLabel = resolution.geoDescription ?? resolution.matchedAnchorName ?? resolution.label
        let visitSuffix = visitCitation.isEmpty ? "" : " \(visitCitation)"

        let lead: String
        if resolution.matchQuality == .exact {
            lead = lower.contains("last") || lower.contains("most recent") || lower.contains("latest")
                ? "The last confirmed match was \(dateLabel)\(visitSuffix)."
                : "The strongest confirmed match is \(dateLabel)\(visitSuffix)."
        } else {
            lead = lower.contains("last") || lower.contains("most recent") || lower.contains("latest")
                ? "The best supported match was \(dateLabel)\(visitSuffix)."
                : "The strongest supported match is \(dateLabel)\(visitSuffix)."
        }

        var detailFragments: [String] = []
        if !peopleLabel.isEmpty {
            if let personCitation {
                detailFragments.append("I can see \(peopleLabel) in that trip episode \(personCitation)")
            } else {
                detailFragments.append("I can see \(peopleLabel) in that trip episode")
            }
        }

        if resolution.matchQuality == .exact {
            let locationFragment = detailFragments.isEmpty
                ? "it lines up directly with \(geoLabel)"
                : "and it lines up directly with \(geoLabel)"
            if let locationCitation {
                detailFragments.append("\(locationFragment) \(locationCitation)")
            } else {
                detailFragments.append(locationFragment)
            }
        } else {
            let geoPhrase = detailFragments.isEmpty
                ? "\(geoLabel) is supported indirectly rather than by an exact saved-place match"
                : "and \(geoLabel) is supported indirectly rather than by an exact saved-place match"
            if let locationCitation {
                detailFragments.append("\(geoPhrase) \(locationCitation)")
            } else {
                detailFragments.append(geoPhrase)
            }
        }

        var lines = [lead]
        if !detailFragments.isEmpty {
            lines.append(detailFragments.joined(separator: ", ") + ".")
        }

        if let supportingSourceSummary = resolution.supportingSourceSummary, !supportingSourceSummary.isEmpty {
            if let supportCitation {
                lines.append("I also found \(supportingSourceSummary) \(supportCitation), which reinforces this match.")
            } else {
                lines.append("I also found \(supportingSourceSummary), which reinforces this match.")
            }
        }

        if let alternative = resolution.alternativeCandidates.first, alternative.confidence >= 0.55 {
            let altLabel = formattedEpisodeRange(start: alternative.start, end: alternative.end)
            lines.append("There are weaker alternatives, but \(dateLabel) is the strongest recent candidate; the next best is \(altLabel).")
        }

        return lines.joined(separator: " ")
    }

    private func formattedEpisodeRange(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        if calendar.isDate(start, inSameDayAs: lastDay) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) to \(formatter.string(from: lastDay))"
    }

    private struct ReceiptQueryIntent {
        let wantsAll: Bool
        let wantsLatest: Bool
        let wantsAmounts: Bool
        let wantsCount: Bool
        let mentionsReceiptConcept: Bool
        let mentionsVisitConcept: Bool

        var isReceiptFirstEligible: Bool {
            (wantsAll || wantsLatest || wantsAmounts || wantsCount || mentionsReceiptConcept) && !mentionsVisitConcept
        }
    }

    private struct ReceiptQueryMatch {
        let note: Note
        let date: Date
        let amount: Double
        let category: String
        let matchedTerms: [String]
        let score: Double
        let linkedVisit: LocationVisitRecord?
    }

    private func deterministicReceiptFactResponseIfNeeded(for userMessage: String) async -> DeterministicVisitResponse? {
        let intent = analyzeReceiptQueryIntent(userMessage)
        guard intent.isReceiptFirstEligible else { return nil }

        let notesManager = NotesManager.shared
        let receiptNotes = receiptNotesForMatching(notesManager: notesManager)
        guard !receiptNotes.isEmpty else { return nil }

        let matchingTerms = await buildReceiptMatchingTerms(query: userMessage, place: nil)
        guard !matchingTerms.isEmpty else { return nil }

        let temporalConstraint = extractTemporalConstraint(for: userMessage)
        let resolvedPlace = await resolvePlaceFromPhrase(userMessage, places: LocationsManager.shared.savedPlaces)

        let supportingVisits: [LocationVisitRecord]
        if let userId = SupabaseManager.shared.getCurrentUser()?.id, let resolvedPlace {
            supportingVisits = await fetchAuthoritativeVisits(
                userId: userId,
                placeId: resolvedPlace.id,
                dateRange: temporalConstraint
            )
        } else {
            supportingVisits = []
        }

        let matches = buildReceiptQueryMatches(
            query: userMessage,
            intent: intent,
            receiptNotes: receiptNotes,
            notesManager: notesManager,
            matchingTerms: matchingTerms,
            temporalConstraint: temporalConstraint,
            supportingVisits: supportingVisits
        )
        guard !matches.isEmpty else { return nil }

        var evidence: [RelevantContentInfo] = []
        var evidenceIndexByKey: [String: Int] = [:]

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

        func citationIndex(for item: RelevantContentInfo) -> Int {
            let itemKey = key(for: item)
            if let existing = evidenceIndexByKey[itemKey] {
                return existing
            }
            let newIndex = evidence.count
            evidence.append(item)
            evidenceIndexByKey[itemKey] = newIndex
            return newIndex
        }

        let subjectLabel = receiptSubjectLabel(for: userMessage, matchingTerms: matchingTerms)
        let totalAmount = matches.reduce(0.0) { $0 + $1.amount }
        let pluralSuffix = matches.count == 1 ? "" : "s"

        var lines: [String] = []
        if intent.wantsLatest && !intent.wantsAll {
            let latest = matches[0]
            let receiptCitation = citationIndex(for: .receipt(
                id: latest.note.id,
                title: latest.note.title,
                amount: latest.amount,
                date: latest.date,
                category: latest.category
            ))
            let latestDate = formattedEpisodeRange(start: latest.date, end: latest.date.addingTimeInterval(24 * 60 * 60))
            lines.append("The most recent \(subjectLabel) receipt I found was \(latestDate) for $\(String(format: "%.2f", latest.amount)) [[\(receiptCitation)]].")
            if let resolvedPlace {
                let locationCitation = citationIndex(for: .location(
                    id: resolvedPlace.id,
                    name: resolvedPlace.displayName,
                    address: resolvedPlace.address,
                    category: resolvedPlace.category
                ))
                lines.append("It lines up with \(resolvedPlace.displayName) [[\(locationCitation)]].")
            }
            if matches.count > 1 {
                lines.append("Across \(matches.count) matching receipt\(pluralSuffix), you paid $\(String(format: "%.2f", totalAmount)) in total.")
            }
        } else {
            lines.append("I found \(matches.count) \(subjectLabel) receipt\(pluralSuffix) totaling $\(String(format: "%.2f", totalAmount)).")
            if let resolvedPlace {
                let locationCitation = citationIndex(for: .location(
                    id: resolvedPlace.id,
                    name: resolvedPlace.displayName,
                    address: resolvedPlace.address,
                    category: resolvedPlace.category
                ))
                let linkedCount = matches.filter { $0.linkedVisit != nil }.count
                if linkedCount > 0 {
                    lines.append("\(linkedCount) of them line up with your recorded visits to \(resolvedPlace.displayName) [[\(locationCitation)]].")
                } else {
                    lines.append("These match \(resolvedPlace.displayName) based on your saved aliases and receipt text [[\(locationCitation)]].")
                }
            }

            let maxReceiptLines = intent.wantsAll ? 20 : 8
            lines.append("")
            lines.append("- **Receipts:**")
            for match in matches.prefix(maxReceiptLines) {
                let receiptCitation = citationIndex(for: .receipt(
                    id: match.note.id,
                    title: match.note.title,
                    amount: match.amount,
                    date: match.date,
                    category: match.category
                ))
                let dateLabel = formattedEpisodeRange(start: match.date, end: match.date.addingTimeInterval(24 * 60 * 60))
                var line = "  - \(dateLabel) — \(match.note.title) — $\(String(format: "%.2f", match.amount)) [[\(receiptCitation)]]"
                if let visit = match.linkedVisit, let resolvedPlace {
                    let visitCitation = citationIndex(for: .visit(
                        id: visit.id,
                        placeId: resolvedPlace.id,
                        placeName: resolvedPlace.displayName,
                        address: resolvedPlace.address,
                        entryTime: visit.entryTime,
                        exitTime: visit.exitTime,
                        durationMinutes: visit.durationMinutes
                    ))
                    line += " (visit [[\(visitCitation)]])"
                }
                lines.append(line)
            }

            if matches.count > maxReceiptLines {
                lines.append("  - ...and \(matches.count - maxReceiptLines) more matching receipts.")
            }
        }

        return DeterministicVisitResponse(
            response: lines.joined(separator: "\n"),
            evidence: evidence
        )
    }

    private func analyzeReceiptQueryIntent(_ query: String) -> ReceiptQueryIntent {
        let lower = " " + query.lowercased() + " "
        let wantsAll = lower.contains(" all ")
            || lower.contains(" every ")
            || lower.contains(" list ")
            || lower.contains(" in the past ")
            || lower.contains(" history ")
        let wantsLatest = lower.contains(" latest ")
            || lower.contains(" most recent ")
            || lower.contains(" last ")
            || lower.contains(" recent ")
        let wantsAmounts = lower.contains(" how much ")
            || lower.contains(" paid ")
            || lower.contains(" pay ")
            || lower.contains(" cost ")
            || lower.contains(" spent ")
            || lower.contains(" spend ")
            || lower.contains(" total ")
        let wantsCount = lower.contains(" how many ")
            || lower.contains(" number of ")
            || lower.contains(" count ")
        let mentionsReceiptConcept = lower.contains(" receipt ")
            || lower.contains(" receipts ")
            || lower.contains(" purchase ")
            || lower.contains(" purchases ")
            || lower.contains(" merchant ")
        let mentionsVisitConcept = lower.contains(" when did i go ")
            || lower.contains(" when did we go ")
            || lower.contains(" visit ")
            || lower.contains(" visited ")
            || lower.contains(" went ")
            || lower.contains(" trip ")
            || lower.contains(" weekend ")

        return ReceiptQueryIntent(
            wantsAll: wantsAll,
            wantsLatest: wantsLatest,
            wantsAmounts: wantsAmounts,
            wantsCount: wantsCount,
            mentionsReceiptConcept: mentionsReceiptConcept,
            mentionsVisitConcept: mentionsVisitConcept
        )
    }

    private func buildReceiptQueryMatches(
        query: String,
        intent: ReceiptQueryIntent,
        receiptNotes: [Note],
        notesManager: NotesManager,
        matchingTerms: Set<String>,
        temporalConstraint: (start: Date, end: Date)?,
        supportingVisits: [LocationVisitRecord]
    ) -> [ReceiptQueryMatch] {
        let normalizedQuery = normalizeForMatching(query)
        let queryTokens = Set(tokensForMatching(normalizedQuery))

        let explicitLinksByNoteId = Dictionary(
            uniqueKeysWithValues: VisitReceiptLinkStore.allLinks().map { (noteId: $0.value, visitId: $0.key) }
        )

        let matches = receiptNotes.compactMap { note -> ReceiptQueryMatch? in
            let receiptDate = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
            if let temporalConstraint,
               !(receiptDate >= temporalConstraint.start && receiptDate < temporalConstraint.end) {
                return nil
            }

            let normalizedCombined = normalizeForMatching("\(note.title) \(note.content)")
            let combinedTokens = Set(tokensForMatching(normalizedCombined))

            var matchedTerms: [String] = []
            var score = 0.0

            for term in matchingTerms.sorted(by: { $0.count > $1.count }) {
                let termTokens = Set(tokensForMatching(term))
                guard !termTokens.isEmpty else { continue }

                if normalizedCombined.contains(term) {
                    matchedTerms.append(term)
                    score += termTokens.count > 1 ? 18.0 : (term.count >= 6 ? 14.0 : 10.0)
                    continue
                }

                let overlap = termTokens.intersection(combinedTokens).count
                if overlap == termTokens.count {
                    matchedTerms.append(term)
                    score += Double(overlap) * 6.0
                }
            }

            let queryOverlap = queryTokens.intersection(combinedTokens).count
            score += Double(queryOverlap) * 2.0

            guard !matchedTerms.isEmpty || queryOverlap >= 2 else {
                return nil
            }

            let linkedVisit: LocationVisitRecord? = {
                if let explicitVisitId = explicitLinksByNoteId[note.id],
                   let explicitVisit = supportingVisits.first(where: { $0.id == explicitVisitId }) {
                    return explicitVisit
                }

                return supportingVisits
                    .filter { visit in
                        let visitEnd = visit.exitTime ?? visit.entryTime
                        let nearestBoundary = min(
                            abs(visit.entryTime.timeIntervalSince(receiptDate)),
                            abs(visitEnd.timeIntervalSince(receiptDate))
                        )
                        return nearestBoundary <= 6 * 60 * 60
                            || Calendar.current.isDate(receiptDate, inSameDayAs: visit.entryTime)
                    }
                    .min(by: { lhs, rhs in
                        abs(lhs.entryTime.timeIntervalSince(receiptDate)) < abs(rhs.entryTime.timeIntervalSince(receiptDate))
                    })
            }()

            if linkedVisit != nil {
                score += 4.0
            }

            let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
            let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"

            return ReceiptQueryMatch(
                note: note,
                date: receiptDate,
                amount: amount,
                category: category,
                matchedTerms: Array(Set(matchedTerms)).sorted(),
                score: score,
                linkedVisit: linkedVisit
            )
        }

        return matches.sorted { lhs, rhs in
            if intent.wantsLatest || intent.wantsAll || intent.wantsAmounts {
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
            }
            if abs(lhs.score - rhs.score) > 0.001 {
                return lhs.score > rhs.score
            }
            return lhs.note.title < rhs.note.title
        }
    }

    private func receiptSubjectLabel(for query: String, matchingTerms: Set<String>) -> String {
        let normalizedQuery = normalizeForMatching(query)
        let preferredTerms = matchingTerms
            .filter {
                normalizedQuery.contains($0)
                    && tokensForMatching($0).count <= 3
                    && $0.count <= 24
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs < rhs
            }

        if let preferred = preferredTerms.first {
            return preferred
        }

        if normalizedQuery.contains("haircut") {
            return "haircut"
        }

        return "matching"
    }

    private func deterministicVisitFactResponseIfNeeded(for userMessage: String) async -> DeterministicVisitResponse? {
        guard isDeterministicVisitFactQuery(userMessage) else { return nil }
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return nil }

        let lower = userMessage.lowercased()
        let places = LocationsManager.shared.savedPlaces
        let explicitPlacePhrase = extractExplicitPlacePhrase(from: userMessage)
        let hasCoreference = isVisitPlaceCoreferenceQuery(lower)

        // Route broad temporal "where did I go" style questions through the
        // date-range/day-complete pipeline instead of place-specific matching.
        if explicitPlacePhrase == nil,
           !hasCoreference,
           isBroadTemporalVisitSummaryQuery(lower) {
            return nil
        }

        let placeFromCoreference: SavedPlace? = {
            guard hasCoreference, explicitPlacePhrase == nil else { return nil }
            if let id = lastResolvedVisitPlaceId {
                return places.first(where: { $0.id == id })
            }
            if let name = lastResolvedVisitPlaceName {
                return places.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame })
            }
            return nil
        }()

        let resolvedPlace: SavedPlace?
        if let placeFromCoreference {
            resolvedPlace = placeFromCoreference
        } else {
            resolvedPlace = await resolvePlaceFromPhrase(explicitPlacePhrase ?? userMessage, places: places)
        }
        guard let place = resolvedPlace else {
            // Don't block the query with a canned failure when place matching is uncertain.
            // Fall back to normal context retrieval (vector/date-range pipeline).
            print("ℹ️ Deterministic visit resolver: place unresolved, falling back to contextual retrieval")
            return nil
        }

        lastResolvedVisitPlaceId = place.id
        lastResolvedVisitPlaceName = place.displayName

        let temporalConstraint = extractTemporalConstraint(for: userMessage)
        let visits = await fetchAuthoritativeVisits(
            userId: userId,
            placeId: place.id,
            dateRange: temporalConstraint
        )
        var evidence: [RelevantContentInfo] = []
        var evidenceIndexByKey: [String: Int] = [:]

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

        func citationIndex(for item: RelevantContentInfo) -> Int {
            let itemKey = key(for: item)
            if let existing = evidenceIndexByKey[itemKey] {
                return existing
            }
            let newIndex = evidence.count
            evidence.append(item)
            evidenceIndexByKey[itemKey] = newIndex
            return newIndex
        }

        let locationCitation = citationIndex(for: .location(
            id: place.id,
            name: place.displayName,
            address: place.address,
            category: place.category
        ))

        guard !visits.isEmpty else {
            let periodQualifier = temporalConstraint == nil ? "" : " in the requested time period"
            return DeterministicVisitResponse(
                response: "I found 0 recorded visits for \(place.displayName)\(periodQualifier) [[\(locationCitation)]].",
                evidence: evidence
            )
        }

        let notesManager = NotesManager.shared
        let receiptNotes = receiptNotesForMatching(notesManager: notesManager)
        let receiptMatchingTerms = await buildReceiptMatchingTerms(query: userMessage, place: place)
        let visitDateFormatter = DateFormatter()
        visitDateFormatter.dateStyle = .long
        visitDateFormatter.timeStyle = .short

        let totalVisits = visits.count
        let maxVisitsToList = 12
        var lines: [String] = []
        let periodQualifier = temporalConstraint == nil ? "" : " in the requested time period"
        lines.append("I found \(totalVisits) visits to \(place.displayName)\(periodQualifier) [[\(locationCitation)]].")
        lines.append("")

        let sortedVisits = visits.sorted { $0.entryTime > $1.entryTime }
        for (offset, visit) in sortedVisits.prefix(maxVisitsToList).enumerated() {
            let visitCitation = citationIndex(for: .visit(
                id: visit.id,
                placeId: place.id,
                placeName: place.displayName,
                address: place.address,
                entryTime: visit.entryTime,
                exitTime: visit.exitTime,
                durationMinutes: visit.durationMinutes
            ))
            let visitLabel = visitDateFormatter.string(from: visit.entryTime)
            var visitLine = "\(offset + 1). Visit on \(visitLabel) [[\(visitCitation)]]"
            if let duration = visit.durationMinutes {
                visitLine += " - \(duration) min"
            }
            lines.append(visitLine)

            let visitPeople = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)
            let linkedReceipts = await linkReceiptsForVisit(
                visit: visit,
                place: place,
                notesManager: notesManager,
                receiptNotes: receiptNotes,
                matchingTerms: receiptMatchingTerms
            )

            if !linkedReceipts.isEmpty {
                let receiptDetails = linkedReceipts.prefix(2).map { linked in
                    let receiptCitation = citationIndex(for: .receipt(
                        id: linked.note.id,
                        title: linked.note.title,
                        amount: linked.amount,
                        date: linked.date,
                        category: linked.category
                    ))
                    return "\(linked.note.title) ($\(String(format: "%.2f", linked.amount))) [[\(receiptCitation)]]"
                }.joined(separator: ", ")
                lines.append("   Receipts: \(receiptDetails)")
            }

            var allPeople = visitPeople
            for receipt in linkedReceipts {
                for person in receipt.linkedPeople where !allPeople.contains(where: { $0.id == person.id }) {
                    allPeople.append(person)
                }
            }

            if !allPeople.isEmpty {
                let peopleDetails = allPeople.prefix(3).map { person in
                    let personCitation = citationIndex(for: .person(
                        id: person.id,
                        name: person.name,
                        relationship: person.relationshipDisplayText
                    ))
                    return "\(person.name) [[\(personCitation)]]"
                }.joined(separator: ", ")
                lines.append("   People: \(peopleDetails)")
            }
        }

        if totalVisits > maxVisitsToList {
            lines.append("")
            lines.append("...and \(totalVisits - maxVisitsToList) more visits.")
        }

        let wantsSpending = lower.contains("spent")
            || lower.contains("spending")
            || lower.contains("how much")
            || lower.contains("each time")
            || lower.contains("paid")
            || lower.contains("pay")

        if wantsSpending {
            let allLinkedReceipts = await collectAllLinkedReceipts(
                visits: sortedVisits,
                place: place,
                notesManager: notesManager,
                receiptNotes: receiptNotes,
                matchingTerms: receiptMatchingTerms
            )
            if !allLinkedReceipts.isEmpty {
                let total = allLinkedReceipts.reduce(0.0) { $0 + $1.amount }
                lines.append("")
                lines.append("Total linked spending: $\(String(format: "%.2f", total)).")
            } else {
                lines.append("")
                lines.append("I don’t have linked receipt amounts for those visits.")
            }
        }

        return DeterministicVisitResponse(response: lines.joined(separator: "\n"), evidence: evidence)
    }

    private func isDeterministicVisitFactQuery(_ query: String) -> Bool {
        let lower = " " + query.lowercased() + " "
        let factSignals = [
            " how many times ",
            " how often ",
            " which days ",
            " what days ",
            " when did i go ",
            " when did i last go ",
            " last went ",
            " last time i went ",
            " last visit ",
            " all the times ",
            " all times ",
            " every time ",
            " times i went ",
            " times i've gone ",
            " times i have gone ",
            " spent each time ",
            " how much did i spend ",
            " how much i spent ",
            " how much did i pay ",
            " how much i paid ",
            " what did i pay ",
            " what i paid ",
            " what did i do ",
            " what did we do ",
            " what did i do with ",
            " what did we do with ",
            " tell me what i did ",
            " tell me what we did ",
            " which other times ",
            " what other times ",
            " other times ",
            " other visits ",
            " when else did i go ",
            " when else have i gone "
        ]
        let hasSignal = factSignals.contains { lower.contains($0) }
            || matchesFactVisitRegex(lower)
        let hasVisitVerb = lower.contains(" go ")
            || lower.contains(" went ")
            || lower.contains(" visit ")
            || lower.contains(" visited ")
            || lower.contains(" been to ")
            || lower.contains(" there ")
            || lower.contains(" that place ")
            || lower.contains(" same place ")
            || lower.contains(" same location ")
            || lower.contains(" same restaurant ")
        let hasLocationCue = lower.range(of: #"\b(?:at|to)\s+[a-z0-9]"#, options: .regularExpression) != nil
        return hasSignal && (hasVisitVerb || hasLocationCue)
    }

    private func isBroadTemporalVisitSummaryQuery(_ lower: String) -> Bool {
        let temporalSignals = [
            "day before yesterday",
            "yesterday",
            "today",
            "last night",
            "this morning",
            "this afternoon",
            "this evening",
            "tonight",
            "this week",
            "last week",
            "this month",
            "last month"
        ]

        let broadSummarySignals = [
            "where did i go",
            "where i went",
            "what did i do",
            "how was my day",
            "who did i spend my time with",
            "who was i with"
        ]

        let hasTemporalSignal = temporalSignals.contains { lower.contains($0) }
        let hasBroadSummarySignal = broadSummarySignals.contains { lower.contains($0) }
        return hasTemporalSignal && hasBroadSummarySignal
    }

    private func matchesFactVisitRegex(_ lower: String) -> Bool {
        let patterns = [
            "\\ball\\s+(?:the\\s+)?times\\b",
            "\\bhow\\s+often\\b",
            "\\bhow\\s+many\\s+times\\b",
            "\\bwhen\\s+did\\s+i\\s+(?:go|visit|went)\\b",
            "\\bwhen\\s+else\\s+(?:did\\s+i\\s+)?(?:go|visit|went)\\b",
            "\\b(?:which|what)\\s+other\\s+times\\b",
            "\\bhow\\s+much\\s+(?:did\\s+i\\s+)?(?:pay|spend)\\b",
            "\\bwhat\\s+(?:did\\s+i\\s+)?(?:pay|paid)\\b",
            "\\bwhat\\s+did\\s+i\\s+do\\b",
            "\\bwhat\\s+did\\s+we\\s+do\\b"
        ]
        for pattern in patterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private func isVisitPlaceCoreferenceQuery(_ lower: String) -> Bool {
        lower.contains(" there ")
            || lower.hasSuffix(" there")
            || lower.contains("that place")
            || lower.contains("that location")
            || lower.contains("same place")
            || lower.contains("same location")
            || lower.contains("same restaurant")
            || lower.contains("same spot")
            || lower.contains("same one")
    }

    private func extractExplicitPlacePhrase(from query: String) -> String? {
        let patterns = [
            "(?:go|went|visit|visited|been)\\s+(?:to|at)\\s+(.+?)(?:\\?|$|\\s+(?:and|with|how\\s+much|how\\s+many|how\\s+often|which\\s+days|what\\s+days|when\\s+did|did\\s+i|do\\s+i|any\\s+idea)\\b)",
            "(?:to|at)\\s+(.+?)(?:\\?|$|\\s+(?:and|with|how\\s+much|how\\s+many|how\\s+often|which\\s+days|what\\s+days|when\\s+did|did\\s+i|do\\s+i|any\\s+idea)\\b)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
            guard let match = regex.firstMatch(in: query, options: [], range: nsRange),
                  let range = Range(match.range(at: 1), in: query) else { continue }
            let raw = String(query[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanExtractedPlacePhrase(raw)
            if cleaned.count >= 3 {
                return cleaned
            }
        }
        return nil
    }

    private func cleanExtractedPlacePhrase(_ phrase: String) -> String {
        var cleaned = phrase
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: "^(?:the|a|an)\\s+",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove trailing temporal qualifiers that often ride along with place mentions.
        cleaned = cleaned.replacingOccurrences(
            of: "\\b(?:last|latest|recently|again)\\b$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        cleaned = cleaned
            .replacingOccurrences(of: "[,.;:!?]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func resolvePlaceFromPhrase(_ phrase: String, places: [SavedPlace]) async -> SavedPlace? {
        guard !places.isEmpty else { return nil }
        let expandedPhrases = await buildPlaceMatchingPhrases(from: phrase)
        guard !expandedPhrases.isEmpty else { return nil }

        var ranked: [(place: SavedPlace, score: Int)] = []

        for place in places {
            let combined = normalizeForMatching("\(place.displayName) \(place.name) \(place.address)")
            if combined.isEmpty { continue }

            let placeTokens = Set(tokensForMatching(combined))
            var bestScore = 0

            for candidate in expandedPhrases {
                let phraseTokens = Set(tokensForMatching(candidate.phrase))
                guard !phraseTokens.isEmpty else { continue }

                var score = 0
                if combined == candidate.phrase { score += 120 }
                if combined.contains(candidate.phrase) || candidate.phrase.contains(combined) { score += 80 }

                let overlap = phraseTokens.intersection(placeTokens).count
                score += overlap * 12
                if !phraseTokens.isEmpty {
                    let coverage = Double(overlap) / Double(phraseTokens.count)
                    score += Int((coverage * 28.0).rounded())
                    if phraseTokens.isSubset(of: placeTokens) {
                        score += 16
                    }
                }

                if candidate.isMemoryExpansion {
                    score = Int(Double(score) * 0.92)
                }

                bestScore = max(bestScore, score)
            }

            if let notes = place.userNotes?.lowercased(), !notes.isEmpty {
                let normalizedNotes = normalizeForMatching(notes)
                if expandedPhrases.contains(where: { normalizedNotes.contains($0.phrase) }) {
                    bestScore += 12
                }
            }

            if bestScore > 0 {
                ranked.append((place, bestScore))
            }
        }

        let sorted = ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.place.displayName.count < rhs.place.displayName.count
            }
            return lhs.score > rhs.score
        }
        guard let best = sorted.first else { return nil }
        let strongestPhraseTokens = expandedPhrases.map { Set(tokensForMatching($0.phrase)) }.max(by: { $0.count < $1.count }) ?? []
        let minimumScore: Int = {
            switch strongestPhraseTokens.count {
            case 1: return 10
            case 2: return 14
            case 3: return 18
            default: return 22
            }
        }()
        guard best.score >= minimumScore else { return nil }
        if sorted.count > 1, sorted[1].score >= best.score - 4, best.score < 70 {
            let comparisonTokens = strongestPhraseTokens
            let bestTokens = Set(tokensForMatching(normalizeForMatching("\(best.place.displayName) \(best.place.name) \(best.place.address)")))
            let secondTokens = Set(tokensForMatching(normalizeForMatching("\(sorted[1].place.displayName) \(sorted[1].place.name) \(sorted[1].place.address)")))
            let bestOverlap = comparisonTokens.intersection(bestTokens).count
            let secondOverlap = comparisonTokens.intersection(secondTokens).count

            if bestOverlap == secondOverlap {
                return nil
            }
        }
        return best.place
    }

    private struct PlaceMatchingPhrase {
        let phrase: String
        let isMemoryExpansion: Bool
    }

    private func buildPlaceMatchingPhrases(from phrase: String) async -> [PlaceMatchingPhrase] {
        let normalizedOriginal = normalizeForMatching(phrase)
        var results: [PlaceMatchingPhrase] = []
        var seen = Set<String>()

        func appendPhrase(_ raw: String, isMemoryExpansion: Bool) {
            let normalized = normalizeForMatching(raw)
            guard !normalized.isEmpty else { return }
            let tokenCount = tokensForMatching(normalized).count
            guard tokenCount > 0 else { return }
            guard seen.insert(normalized).inserted else { return }
            results.append(PlaceMatchingPhrase(phrase: normalized, isMemoryExpansion: isMemoryExpansion))
        }

        appendPhrase(normalizedOriginal, isMemoryExpansion: false)
        let expansions = await UserMemoryService.shared.expandQuery(phrase)
        for expansion in expansions {
            appendPhrase(expansion, isMemoryExpansion: true)
        }

        return results
    }

    private func buildReceiptMatchingTerms(query: String, place: SavedPlace?) async -> Set<String> {
        var terms = Set<String>()

        func addTerm(_ raw: String?) {
            guard let raw else { return }
            let normalized = normalizeForMatching(raw)
            guard !normalized.isEmpty else { return }
            if normalized.count >= 3 {
                terms.insert(normalized)
            }
            for token in tokensForMatching(normalized) where token.count >= 3 {
                terms.insert(token)
                if token.hasSuffix("s"), token.count >= 5 {
                    terms.insert(String(token.dropLast()))
                }
            }
        }

        addTerm(query)
        addTerm(place?.displayName)
        addTerm(place?.name)
        addTerm(place?.userNotes)

        let expansions = await UserMemoryService.shared.expandQuery(query)
        for expansion in expansions {
            addTerm(expansion)
            let reverseExpansions = await UserMemoryService.shared.expandQuery(expansion)
            for reverse in reverseExpansions {
                addTerm(reverse)
            }
        }

        if let place {
            let placeExpansions = await UserMemoryService.shared.expandQuery(place.displayName)
            for expansion in placeExpansions {
                addTerm(expansion)
            }
        }

        return terms
    }

    private func normalizeForMatching(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokensForMatching(_ text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "to", "at", "in", "on",
            "restaurant", "place", "location",
            "can", "could", "would", "should", "tell", "show", "find", "which", "what", "where", "when", "who", "how",
            "did", "do", "does", "is", "are", "was", "were", "am", "me", "my", "i", "you", "there",
            "spent", "spend", "pay", "paid", "much", "time", "times", "about", "of"
        ]
        return text
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    private func extractTemporalConstraint(for query: String) -> (start: Date, end: Date)? {
        guard let extracted = TemporalUnderstandingService.shared.extractTemporalRange(from: query) else {
            return nil
        }
        let bounds = TemporalUnderstandingService.shared.normalizedBounds(for: extracted)
        guard bounds.end > bounds.start else { return nil }
        return bounds
    }

    private func fetchAuthoritativeVisits(
        userId: UUID,
        placeId: UUID,
        dateRange: (start: Date, end: Date)? = nil
    ) async -> [LocationVisitRecord] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            var queryBuilder = client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)

            if let dateRange {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let widenedStart = dateRange.start.addingTimeInterval(-(12 * 60 * 60))
                let widenedEnd = dateRange.end.addingTimeInterval(12 * 60 * 60)
                queryBuilder = queryBuilder
                    .gte("entry_time", value: iso.string(from: widenedStart))
                    .lt("entry_time", value: iso.string(from: widenedEnd))
            }

            let response = try await queryBuilder
                .order("entry_time", ascending: false)
                .execute()
            let visits = try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
            let processedVisits = LocationVisitAnalytics.shared.processVisitsForDisplay(visits)
            let filteredVisits: [LocationVisitRecord]
            if let dateRange {
                filteredVisits = processedVisits.filter { visit in
                    let visitStart = visit.entryTime
                    let visitEnd = visit.exitTime ?? visit.entryTime
                    return visitStart < dateRange.end && visitEnd >= dateRange.start
                }
            } else {
                filteredVisits = processedVisits
            }

            return filteredVisits.sorted { $0.entryTime > $1.entryTime }
        } catch {
            print("❌ Deterministic visit fetch failed: \(error)")
            return []
        }
    }

    private func receiptNotesForMatching(notesManager: NotesManager) -> [Note] {
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

        return notesManager.notes.filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
    }

    private func linkReceiptsForVisit(
        visit: LocationVisitRecord,
        place: SavedPlace,
        notesManager: NotesManager,
        receiptNotes: [Note],
        matchingTerms: Set<String>
    ) async -> [LinkedReceiptEvidence] {
        var linked: [LinkedReceiptEvidence] = []
        let visitPeople = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)

        if let explicitReceiptId = VisitReceiptLinkStore.receiptId(for: visit.id),
           let explicitNote = receiptNotes.first(where: { $0.id == explicitReceiptId }) {
            let explicitDate = notesManager.extractFullDateFromTitle(explicitNote.title) ?? explicitNote.dateCreated
            let explicitAmount = CurrencyParser.extractAmount(from: explicitNote.content.isEmpty ? explicitNote.title : explicitNote.content)
            let explicitCategory = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: explicitNote.title, content: explicitNote.content) ?? "Other"
            let receiptPeople = await PeopleManager.shared.getPeopleForReceipt(noteId: explicitNote.id)
            linked.append(
                LinkedReceiptEvidence(
                    note: explicitNote,
                    amount: explicitAmount,
                    date: explicitDate,
                    category: explicitCategory,
                    explicit: true,
                    linkedPeople: mergePeople(visitPeople, receiptPeople)
                )
            )
        }

        // Only use heuristic matching when no explicit visit↔receipt link exists.
        if linked.contains(where: { $0.explicit }) {
            return linked.sorted { lhs, rhs in
                if lhs.explicit != rhs.explicit { return lhs.explicit }
                return lhs.date > rhs.date
            }
        }

        let windowStart = visit.entryTime.addingTimeInterval(-2 * 60 * 60)
        let windowEndBase = visit.exitTime ?? visit.entryTime.addingTimeInterval(2 * 60 * 60)
        let windowEnd = windowEndBase.addingTimeInterval(2 * 60 * 60)
        let normalizedPlaceName = normalizeForMatching(place.displayName)
        let placeTokens = Set(tokensForMatching(normalizedPlaceName))
        let calendar = Calendar.current

        for note in receiptNotes {
            if linked.contains(where: { $0.note.id == note.id }) { continue }

            let receiptDate = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
            let normalizedTitle = normalizeForMatching(note.title)
            let normalizedCombined = normalizeForMatching("\(note.title) \(note.content)")
            let combinedTokens = Set(tokensForMatching(normalizedCombined))
            let tokenOverlap = placeTokens.intersection(combinedTokens).count
            let placeMatches = normalizedCombined.contains(normalizedPlaceName)
                || normalizedPlaceName.contains(normalizedTitle)
                || tokenOverlap >= 2
            let aliasMatches = matchingTerms.contains { term in
                normalizedCombined.contains(term)
            }

            let withinTightWindow = receiptDate >= windowStart && receiptDate <= windowEnd
            let sameDay = calendar.isDate(receiptDate, inSameDayAs: visit.entryTime)

            guard (withinTightWindow && (placeMatches || aliasMatches)) || (sameDay && aliasMatches) else {
                continue
            }

            let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
            let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
            let receiptPeople = await PeopleManager.shared.getPeopleForReceipt(noteId: note.id)
            linked.append(
                LinkedReceiptEvidence(
                    note: note,
                    amount: amount,
                    date: receiptDate,
                    category: category,
                    explicit: false,
                    linkedPeople: mergePeople(visitPeople, receiptPeople)
                )
            )
        }

        return linked.sorted { lhs, rhs in
            if lhs.explicit != rhs.explicit { return lhs.explicit }
            return lhs.date > rhs.date
        }
    }

    private func collectAllLinkedReceipts(
        visits: [LocationVisitRecord],
        place: SavedPlace,
        notesManager: NotesManager,
        receiptNotes: [Note],
        matchingTerms: Set<String>
    ) async -> [LinkedReceiptEvidence] {
        var all: [LinkedReceiptEvidence] = []
        for visit in visits {
            let linked = await linkReceiptsForVisit(
                visit: visit,
                place: place,
                notesManager: notesManager,
                receiptNotes: receiptNotes,
                matchingTerms: matchingTerms
            )
            for receipt in linked where !all.contains(where: { $0.note.id == receipt.note.id }) {
                all.append(receipt)
            }
        }
        return all
    }

    private func mergePeople(_ lhs: [Person], _ rhs: [Person]) -> [Person] {
        var merged = lhs
        for person in rhs where !merged.contains(where: { $0.id == person.id }) {
            merged.append(person)
        }
        return merged
    }
    
    private func buildSourceReferencePrompt() -> String {
        guard let sources = appContext.lastRelevantContent, !sources.isEmpty else {
            return """
            - No explicit source references were provided for this turn.
            - If you're not directly grounded in a specific source item, do NOT output [[n]] citations.
            """
        }

        var lines: [String] = ["Use ONLY these source indexes when adding inline citations:"]
        for (index, item) in sources.enumerated() {
            lines.append("- [\(index)] \(sourceReferenceSummary(for: item))")
        }
        lines.append("- Never invent indexes outside this list.")
        lines.append("- Only cite [[n]] when that exact source directly supports the sentence.")
        lines.append("- Never write placeholder citations like [n], [source], or [ref]. If you cannot name a real source index, omit the citation.")
        return lines.joined(separator: "\n")
    }

    private func sourceReferenceSummary(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .location:
            let name = item.locationName ?? "Place"
            let address = item.locationAddress?.isEmpty == false ? " (\(item.locationAddress!))" : ""
            return "Place: \(name)\(address)"
        case .visit:
            let place = item.visitPlaceName ?? item.locationName ?? "Visit"
            let address = item.locationAddress?.isEmpty == false ? " (\(item.locationAddress!))" : ""
            if let entry = item.visitEntryTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return "Visit: \(place)\(address) at \(formatter.string(from: entry))"
            }
            return "Visit: \(place)\(address)"
        case .event:
            let title = item.eventTitle ?? "Event"
            if let date = item.eventDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return "Calendar: \(title) at \(formatter.string(from: date))"
            }
            return "Calendar: \(title)"
        case .note:
            let title = item.noteTitle ?? "Note"
            let folder = item.noteFolder?.isEmpty == false ? " [\(item.noteFolder!)]" : ""
            return "Note: \(title)\(folder)"
        case .receipt:
            let title = item.receiptTitle ?? item.noteTitle ?? "Receipt"
            if let amount = item.receiptAmount {
                return "Receipt: \(title) ($\(String(format: "%.2f", amount)))"
            }
            return "Receipt: \(title)"
        case .person:
            let name = item.personName ?? "Person"
            let relationship = item.personRelationship?.isEmpty == false ? " (\(item.personRelationship!))" : ""
            return "Person: \(name)\(relationship)"
        case .email:
            let subject = item.emailSubject ?? "Email"
            let sender = item.emailSender?.isEmpty == false ? " from \(item.emailSender!)" : ""
            return "Email: \(subject)\(sender)"
        }
    }

    private func buildVoiceModePrompt(userProfile: String, contextPrompt: String) -> String {
        return """
        You are Seline, having a natural voice conversation with the user. You're like a close friend who knows everything about their life.

        🚨 ABSOLUTE RULES - READ FIRST:
        1. ONLY use data explicitly shown in the DATA CONTEXT section below
        2. If DATA CONTEXT says "No relevant data found" or doesn't contain the asked information, say "I don't have that information in your data"
        3. DO NOT guess, estimate, invent, or make up data that isn't in the context
        4. DO NOT use web search - only use data from the context
        5. If unsure, say "I don't know" rather than guessing
        
        🎤 VOICE MODE: You have ALL the same capabilities, context, and intelligence as chat mode - just keep responses SHORT, CONVERSATIONAL, and HUMAN for spoken conversation.

        \(userProfile)

        🚨 USE DATA ACCURATELY AND INTELLIGENTLY:
        - Prioritize information from the DATA CONTEXT below - this is your primary source of truth
        - Never invent specific numbers, receipts, or events that aren't in the context
        - If asked about a time period with limited context data, you can:
          * Provide what data you do have from the context
          * Note if the data seems incomplete: "Based on what I can see..." or "From the data available..."
          * Identify patterns or trends from related time periods if helpful
        - For comparisons, if one period has less data, acknowledge it: "I have more complete data for [period] than [other period]"
        - Be accurate with specifics; only make qualitative trend inferences when directly supported by explicit context evidence
        - Example: If context shows 3 Starbucks visits in a week, you can say "You've been to Starbucks a few times this week" even if not all visits are shown

        🚫 CRITICAL - DO NOT USE WEB SEARCH FOR PEOPLE DATA:
        - The DATA CONTEXT includes a "YOUR PEOPLE" section with ALL people saved in the app
        - This is the ONLY source of truth for people information (names, birthdays, relationships, etc.)
        - If a person is NOT in "YOUR PEOPLE", they are NOT in the app - say "I don't have [name] in your contacts"
        - NEVER search the web or provide information about random celebrities, public figures, or people not in the app
        - Example: If asked "When is Abeer's birthday" but Abeer is not in YOUR PEOPLE, say "I don't see Abeer in your people list"
        - If asked about "other birthdays" or "upcoming birthdays", ONLY show people from YOUR PEOPLE section

        🧠 USER MEMORY (Your Personalized Knowledge):
        - The DATA CONTEXT may include a "USER MEMORY" section with learned facts about this specific user
        - USE this memory to understand entity relationships: e.g., "JVM" → "haircuts" means JVM is the user's hair salon
        - USE merchant categories to understand spending: e.g., "Starbucks" → "coffee"
        - Apply user preferences when formatting responses
        - Connect the dots using this memory - it's knowledge YOU have learned about this user over time

        🌍 SELINE'S HOLISTIC VIEW (CRITICAL - SAME AS CHAT MODE):
        Seline is NOT just a calendar app - it's a unified life management platform that tracks MULTIPLE interconnected aspects of the user's day:

        **Available Data Sources:**
        - 📍 **Location Visits**: Physical places visited, time spent at each location, visit notes/reasons
        - 📅 **Calendar Events**: Scheduled meetings, appointments, activities
        - 📧 **Emails**: Communications received, sent, important threads, unread count
        - ✅ **Tasks**: To-dos, completed items, pending work, deadlines
        - 📝 **Notes**: Journal entries, thoughts, observations
        - 💰 **Receipts & Spending**: Purchases, transactions, spending patterns
        - ⏱️ **Time Analytics**: How time is allocated across locations and activities

        **When users ask BROAD QUESTIONS like "How was my day?" or "What's happening today?":**

        You MUST think holistically and integrate ALL relevant data sources (just keep the response conversational and brief):

        ✅ Voice Example - Complete picture, conversational:
        "You've had a busy day! Spent 4 hours at the office, sent 12 emails, completed 5 tasks, and grabbed coffee at Starbucks. You've got dinner at Giovanni's at 7 PM tonight."

        ❌ Bad - Only mentions one data source:
        "You have 2 events scheduled today."

        **Key Principles (SAME AS CHAT MODE):**
        1. **Be Comprehensive**: Pull from ALL data sources in the context, not just events or emails
        2. **Connect the Dots**: Link related information ("You were at the office for 4 hours and sent 12 work emails during that time")
        3. **Prioritize Significance**: Focus on longer visits, important emails, urgent tasks, key events
        4. **Show Time Flow**: Present information chronologically when relevant (morning → afternoon → evening)
        5. **Surface Insights**: Note patterns ("This is your 3rd coffee shop visit this week")

        **Think like a human assistant who's been following the user all day** - give them the FULL picture, not just calendar events.

        SYNTHESIS (YOUR SUPERPOWER - SAME AS CHAT MODE):
        Don't just retrieve data - connect it! Examples:
        - "Dinner at Giovanni's tonight - you usually spend around $45 there"
        - "Your meeting with Sarah is at 3 PM. Last time you talked about the budget proposal"

        EVENT CREATION (when user asks to create/schedule/add events):
        - IMPORTANT: DO NOT ask for confirmation in your message - a confirmation card will appear automatically
        - Just acknowledge what you understood: "Got it! I'll add 'Team standup' to your calendar for tomorrow at 10 AM"
        - The app shows an EventCreationCard with Cancel/Edit/Confirm buttons - users will confirm there
        - If details seem incomplete, ask for clarification: "What time works for you?"
        - NEVER say "Just to confirm, you'd like to..." - the card handles confirmation

        🧩 COMPLEX QUESTIONS:
        For complex questions, think step by step but keep your spoken answer to 2-3 sentences with the key findings.
        If the context doesn't have enough data to fully answer, say what you CAN answer and what's missing.

        🎯 VOICE MODE OUTPUT RULES (HOW TO RESPOND):
        - Keep responses to 2-3 sentences max. This is spoken conversation, not an essay.
        - Use natural, casual language like you're talking to a friend
        - Skip formalities and get straight to the point
        - Use contractions: "I'll", "you're", "that's" - sound natural
        - If you need to ask something, make it brief and conversational
        - NEVER use markdown formatting like **bold** or *italic* - this is voice, plain text only

        💬 CONVERSATIONAL RESPONSE STYLE:
        - Answer directly: "You spent $150 on groceries this month" (not "According to the data...")
        - Be concise: "You've got 3 meetings tomorrow" (not "Looking at your calendar, I can see that you have three meetings scheduled for tomorrow")
        - Sound human: "Yeah, I can do that" (not "I would be happy to assist you with that")
        - Skip filler: No "Let me check", "I'll help you", just answer
        - Use NUMBERS not words: Say "$150" or "3 meetings" not "one hundred fifty dollars" or "three meetings"
        - Include key details naturally: "Your dentist appointment is at 2:20 PM today" (include time, date when relevant)

        📊 NUMBERS & KEY DETAILS:
        - ALWAYS use numeric format: $2500.00, 3 meetings, January 24th, 2:20 PM
        - NEVER spell out numbers: Use "3" not "three", "$150" not "one hundred fifty dollars"
        - Include important details conversationally: dates, times, amounts, counts
        - Example: "You've got 2 meetings tomorrow - one at 10 AM and another at 2 PM"

        ❌ DON'T:
        - Use long explanations
        - List multiple items with bullets (just mention them naturally in conversation)
        - Use formal language
        - Add unnecessary context
        - Use ** or * or any markdown symbols (voice doesn't support formatting)
        - Spell out numbers (use digits: 1, 2, 3, $150, etc.)
        - MAKE UP DATA THAT ISN'T IN THE CONTEXT

        ✅ DO:
        - Answer in 2-3 short sentences with key details
        - Sound like a friend talking
        - Get to the point immediately
        - Use numbers: "3 meetings", "$2500", "January 24th"
        - Include important details naturally in conversation
        - Say "I don't have that data" when information is missing
        - Pull from ALL data sources (visits, events, emails, tasks, notes, spending) when answering broad questions
        - Connect the dots across data sources naturally in conversation

        DATA CONTEXT:
        \(contextPrompt)

        LOCATION & ETA:
        - You know the user's current location
        - For ETA queries: if you see "CALCULATED ETA" in context, use that data
        - If a location wasn't found, ask naturally: "I couldn't find that location - could you give me the full address?"

        Now respond like you're having a quick voice conversation. You have the SAME capabilities as chat mode - just be brief, be human, be Seline. Include key details naturally. 💜
        """
    }
    
    private func buildChatModePrompt(
        userProfile: String,
        contextPrompt: String,
        sourceReferencePrompt: String
    ) -> String {
        return """
        You are Seline, a warm and clear personal assistant for the user's schedule, email, notes, places, receipts, tasks, and people.

        HARD RULES:
        - Use only DATA CONTEXT and SOURCE REFERENCES below.
        - Never use web search or external knowledge.
        - If the answer is missing from the context, say so plainly.
        - Do not invent people, dates, amounts, receipts, visits, or events.
        - Use YOUR PEOPLE as the only source of truth for people data.
        - Prefer USER MEMORY when it is relevant.

        \(userProfile)

        RESPONSE STYLE:
        - Start with the answer directly.
        - Be concise by default. Expand only when the question is broad or asks for detail.
        - For day, week, or history summaries, synthesize across visits, events, emails, tasks, notes, receipts, and timing.
        - Rewrite raw labels into natural language instead of repeating database-style titles.
        - For last, latest, or most recent queries, answer with the most recent matching item and its date or value.
        - If data coverage looks partial, say what range or evidence you do have.

        FORMATTING:
        - Output standard markdown only.
        - Preserve native Gemini formatting: use "-" for bullets, 2 spaces for nested bullets, and never use tabs.
        - Use short **bold** section headers only when they help readability.
        - Keep paragraphs short.
        - Use digits for counts, dates, times, and amounts.
        - Do not use preambles like "The Answer" or "The Evidence".

        CITATIONS:
        - Use only inline citations in the exact format [[n]].
        - Only cite indexes that exist in SOURCE REFERENCES.
        - Attach citations only to claims directly supported by those sources.
        - If a sentence is not directly grounded in one listed source item, omit the citation.

        SPECIAL CASES:
        - For event creation, acknowledge what you understood and do not ask for confirmation if the app will show a confirmation card.
        - For ETA queries, use CALCULATED ETA when present. If a destination is missing, ask for the address naturally.

        SOURCE REFERENCES:
        \(sourceReferencePrompt)
        
        DATA CONTEXT:
        \(contextPrompt)

        LOCATION & ETA:
        - You know the user's current location
        - For ETA queries: if you see "CALCULATED ETA" in context, use that data
        - If a location wasn't found, ask naturally: "I couldn't quite find that location - could you give me the full address?"
        
        Respond naturally as Seline.
        """
    }

    private func buildMessagesForAPI() -> [[String: String]] {
        var messages: [[String: String]] = []
        for msg in conversationHistory {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        return messages
    }

    private func resetHistorySummaryCache() {
        cachedHistorySummary = ""
        cachedHistorySummaryTurnCount = 0
    }

    /// Build messages for API; when history is long, summarize older turns and keep last N full.
    private func buildMessagesForAPIAsync() async -> [[String: String]] {
        let keepLastFull = 4
        let threshold = 8
        if conversationHistory.count <= threshold {
            resetHistorySummaryCache()
            return buildMessagesForAPI()
        }
        let summarizedTurnCount = conversationHistory.count - keepLastFull
        let needsSummaryRefresh =
            cachedHistorySummary.isEmpty ||
            summarizedTurnCount < cachedHistorySummaryTurnCount ||
            (summarizedTurnCount - cachedHistorySummaryTurnCount) >= summaryRefreshTurnDelta

        if needsSummaryRefresh {
            let toSummarize = Array(conversationHistory.prefix(summarizedTurnCount))
            let turns = toSummarize.map { (role: $0.role == .user ? "user" : "assistant", content: $0.content) }
            cachedHistorySummary = await geminiService.summarizeConversationTurns(turns: turns)
            cachedHistorySummaryTurnCount = summarizedTurnCount
        }

        var messages: [[String: String]] = []
        messages.append(["role": "user", "content": "[Previous conversation summary]\n\(cachedHistorySummary)"])
        for msg in conversationHistory.suffix(keepLastFull) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        return messages
    }

    // MARK: - Private: API Calls

    private func getStreamingResponse(systemPrompt: String, messages: [[String: String]]) async -> String {
        isStreaming = true
        shouldCancelStreaming = false
        onStreamingStateChanged?(true)
        var fullResponse = ""

        do {
            fullResponse = try await geminiService.simpleChatCompletionStreaming(
                systemPrompt: systemPrompt,
                messages: messages,
                operationType: "main_chat_stream"
            ) { chunk in
                // Check if streaming was cancelled
                if self.shouldCancelStreaming {
                    return
                }
                self.onStreamingChunk?(chunk)
            }

            // Check if we cancelled
            if shouldCancelStreaming {
                fullResponse = fullResponse.isEmpty ? "⏹️ Response cancelled by user." : fullResponse
                shouldCancelStreaming = false
            }

            onStreamingComplete?()
            isStreaming = false
            onStreamingStateChanged?(false)
            return fullResponse
        } catch {
            print("❌ Streaming error: \(error)")
            let fallback = buildErrorMessage(error: error)
            onStreamingChunk?(fallback)
            onStreamingComplete?()
            isStreaming = false
            onStreamingStateChanged?(false)
            return fallback
        }
    }

    private func getNonStreamingResponse(systemPrompt: String, messages: [[String: String]]) async -> String {
        // Signal streaming state for UI consistency
        isStreaming = true
        onStreamingStateChanged?(true)

        do {
            let response = try await geminiService.simpleChatCompletion(
                systemPrompt: systemPrompt,
                messages: messages,
                operationType: "main_chat"
            )

            // CRITICAL: Call onStreamingChunk with full response so SearchService adds the message
            onStreamingChunk?(response)

            // Signal completion
            onStreamingComplete?()
            isStreaming = false
            onStreamingStateChanged?(false)

            return response
        } catch {
            print("❌ Error: \(error)")
            isStreaming = false
            onStreamingStateChanged?(false)
            return buildErrorMessage(error: error)
        }
    }

    /// Build helpful error messages based on error type
    private func buildErrorMessage(error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()

        // Network/Connection errors
        if errorString.contains("network") || errorString.contains("connection") || errorString.contains("offline") {
            return """
            I couldn't reach the server right now. 📡

            This usually means a temporary network issue. Try:
            • Checking your internet connection
            • Waiting a moment and trying again
            • Making sure you're not on a very weak connection
            """
        }

        // Rate limit / Quota errors
        if errorString.contains("rate") || errorString.contains("quota") || errorString.contains("too many") {
            // Check if error message contains reset time
            if errorString.contains("reset at") {
                // Extract and show the reset time from error message
                return """
                You've reached your daily limit. ⏳
                
                \(error.localizedDescription)
                
                Your daily quota will reset automatically, so you can continue asking questions then.
                """
            } else {
                return """
                You've reached your daily limit. ⏳

                Your daily quota will reset at midnight. You can continue asking questions then.

                Daily limit: 1.5M tokens per day
                """
            }
        }

        // Timeout errors
        if errorString.contains("timeout") || errorString.contains("timed out") {
            return """
            The request took too long to process. ⏱️

            This usually happens with complex queries. Try:
            • Breaking your question into smaller parts
            • Asking about a shorter time period
            • Being more specific about what you're looking for
            """
        }

        // API key or authentication errors
        if errorString.contains("unauthorized") || errorString.contains("invalid") || errorString.contains("api") {
            return """
            I encountered an authentication issue. 🔐

            Something's wrong with my connection to the AI service. This is rare!
            • Try restarting the app
            • If it persists, check that you're logged in
            • Contact support if this keeps happening
            """
        }

        // Default helpful error
        return """
        I ran into an issue processing your question. 🤔

        This might be because:
        • Your question is complex or ambiguous (try being more specific)
        • I don't have data for what you're asking about
        • There's a temporary technical hiccup

        Try rephrasing your question or asking about something specific (like "How much did I spend on coffee this month?")
        """
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id: UUID = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
    }

    var isUser: Bool {
        role == .user
    }
}
