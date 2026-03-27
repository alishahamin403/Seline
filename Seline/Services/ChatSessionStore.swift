import Foundation
import Combine

private struct ChatSessionSafeDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct ChatStatusPresentation: Equatable {
    let primaryText: String
    let secondaryText: String?
    let showsDots: Bool

    static let idle = ChatStatusPresentation(primaryText: "", secondaryText: nil, showsDots: false)
}

enum ChatTurnPhase: String, Equatable {
    case idle
    case routing
    case retrieving
    case synthesizing
    case cancelled
    case failed

    var isActive: Bool {
        switch self {
        case .routing, .retrieving, .synthesizing:
            return true
        case .idle, .cancelled, .failed:
            return false
        }
    }
}

struct ConversationSessionTurn: Codable, Hashable {
    let role: String
    let text: String
}

struct ConversationSessionSnapshot: Codable, Hashable {
    let summary: String?
    let anchorState: ConversationAnchorState?
    let recentTurns: [ConversationSessionTurn]
    let resolvedEntities: [EntityRef]
    let resolvedTimeRange: String?
}

@MainActor
final class ChatSessionStore: ObservableObject {
    private static let conversationHistoryStorageKey = "conversationHistory"
    private static let lastConversationStorageKey = "lastConversation"
    private static let lastActiveConversationIdStorageKey = "lastActiveConversationId"

    static let shared = ChatSessionStore()

    @Published private(set) var conversationHistory: [ConversationMessage] = []
    @Published private(set) var lastMessageContentVersion: Int = 0
    @Published private(set) var isInConversationMode: Bool = false
    @Published private(set) var conversationTitle: String = "New Conversation"
    @Published private(set) var conversationKind: ConversationKind = .standard
    @Published private(set) var savedConversations: [SavedConversation] = []
    @Published private(set) var isNewConversation: Bool = false
    @Published private(set) var currentTrackerThread: TrackerThread? = nil
    @Published private(set) var pendingTrackerDraft: TrackerOperationDraft? = nil
    @Published private(set) var phase: ChatTurnPhase = .idle
    @Published private(set) var statusPresentation: ChatStatusPresentation = .idle
    @Published private(set) var turnStartedAt: Date? = nil

    private var currentConversationAnchorState: ConversationAnchorState?
    private var currentlyLoadedConversationId: UUID? = nil
    private var lastGeneratedTitleMessageCount: Int = 0
    private var lastContentVersionUpdate: Date = .distantPast

    private var activeTurnTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeToolNames: [String] = []
    private var activeFirstTokenAt: Date?
    private var activeStaleChunkCount: Int = 0

    private let chatAgent = ChatAgentService.shared
    private let telemetryStore = ChatTurnTelemetryStore.shared
    private let trackerStore = TrackerStore.shared
    private let trackerParserService = TrackerParserService.shared
    private let locationsManager = LocationsManager.shared
    private let mapsService = GoogleMapsService.shared

    var currentConversationId: UUID? {
        currentlyLoadedConversationId
    }

    var isTrackerConversation: Bool {
        conversationKind == .tracker
    }

    var isTurnActive: Bool {
        phase.isActive
    }

    private init() {
        loadConversationHistoryLocally()
        trackerStore.loadLocalThreads()
    }

    func isStreaming(_ message: ConversationMessage) -> Bool {
        guard !message.isUser, phase == .synthesizing else { return false }
        return conversationHistory.last?.id == message.id
    }

    func isPendingTrackerDraft(_ message: ConversationMessage) -> Bool {
        pendingTrackerDraft?.id == message.trackerOperationDraft?.id
    }

    func startNewConversation(kind: ConversationKind = .standard) {
        stop()
        persistCurrentConversationIfNeeded()

        conversationHistory = []
        lastMessageContentVersion = 0
        isInConversationMode = true
        isNewConversation = true
        conversationKind = kind
        conversationTitle = kind == .tracker ? "New Tracker" : ""
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        currentlyLoadedConversationId = nil
        lastGeneratedTitleMessageCount = 0
        currentConversationAnchorState = nil
        phase = .idle
        statusPresentation = .idle
        turnStartedAt = nil
        persistLastActiveConversationId(nil)
        UserDefaults.standard.removeObject(forKey: Self.lastConversationStorageKey)
    }

    func startNewTrackerConversation() {
        startNewConversation(kind: .tracker)
    }

    func startConversation(with initialQuestion: String) async {
        guard !ChatUsageTracker.shared.isLimitReached else { return }
        startNewConversation(kind: .standard)
        await send(initialQuestion)
    }

    func send(_ userMessage: String) async {
        await send(userMessage, appendUserMessage: true)
    }

    func stop() {
        guard activeTurnTask != nil || phase.isActive else { return }

        if activeTurnTask != nil || phase.isActive {
            stop()
        }

        if let requestID = activeRequestID {
            telemetryStore.finishCancelled(
                requestID: requestID,
                conversationID: currentlyLoadedConversationId,
                staleChunkCount: activeStaleChunkCount
            )
        }

        activeRequestID = nil
        activeToolNames = []
        activeFirstTokenAt = nil
        activeStaleChunkCount = 0
        phase = .cancelled
        statusPresentation = .idle
        turnStartedAt = nil

        if let lastMessage = conversationHistory.last,
           !lastMessage.isUser,
           lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversationHistory.removeLast()
        }

        if !conversationHistory.isEmpty {
            saveConversationLocally()
            _ = upsertCurrentConversationInHistory()
        }
    }

    func regenerate(messageID: UUID) async {
        guard !ChatUsageTracker.shared.isLimitReached else { return }
        guard conversationKind != .tracker else { return }
        guard let assistantIndex = conversationHistory.firstIndex(where: { $0.id == messageID && !$0.isUser }) else { return }
        guard assistantIndex > 0, conversationHistory[assistantIndex - 1].isUser else { return }

        let userMessage = conversationHistory[assistantIndex - 1].text
        conversationHistory.remove(at: assistantIndex)
        saveConversationLocally()

        await send(userMessage, appendUserMessage: false)
    }

    func confirmActionDraft(
        for messageId: UUID,
        confirmedEvents: [EventCreationInfo]? = nil,
        folderName: String? = nil
    ) async {
        guard let index = conversationHistory.firstIndex(where: { $0.id == messageId }),
              let draft = conversationHistory[index].actionDraft else {
            return
        }

        switch draft.type {
        case .createEvent:
            let eventsToCreate = confirmedEvents ?? draft.eventDrafts ?? []
            guard !eventsToCreate.isEmpty else { return }
            await createEventsFromDraft(eventsToCreate)
            updateActionDraftStatus(for: messageId, status: .confirmed)
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: eventsToCreate.count == 1 ? "I created the event." : "I created \(eventsToCreate.count) events.",
                    intent: .calendar
                )
            )
        case .createNote:
            guard let noteDraft = draft.noteDraft else { return }
            SearchService.shared.pendingNoteCreation = NoteCreationData(
                title: noteDraft.title,
                content: noteDraft.content,
                formattedContent: noteDraft.content,
                folderId: noteDraft.folderId,
                folderName: noteDraft.folderName
            )
            updateActionDraftStatus(for: messageId, status: .confirmed)
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: "I opened the note draft so you can make final edits before saving.",
                    intent: .notes
                )
            )
        case .latestEmail:
            return
        case .saveLocation:
            guard let placeDraft = draft.placeDraft else { return }
            let trimmedRequestedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDraftFolder = placeDraft.folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedFolder: String? = {
                if let trimmedRequestedFolder, !trimmedRequestedFolder.isEmpty { return trimmedRequestedFolder }
                if let trimmedDraftFolder, !trimmedDraftFolder.isEmpty { return trimmedDraftFolder }
                return nil
            }()
            guard let resolvedFolder else { return }

            if locationsManager.isPlaceSaved(googlePlaceId: placeDraft.place.id) {
                updateActionDraftStatus(for: messageId, status: .confirmed)
                conversationHistory.append(
                    ConversationMessage(
                        isUser: false,
                        text: "\(placeDraft.place.name) is already saved.",
                        intent: .locations
                    )
                )
                break
            }

            if !locationsManager.categories.contains(resolvedFolder) && !locationsManager.userFolders.contains(resolvedFolder) {
                locationsManager.addFolder(resolvedFolder)
            }

            let savedPlace: SavedPlace
            if !placeDraft.place.id.hasPrefix("mapkit:"),
               let details = try? await mapsService.getPlaceDetails(placeId: placeDraft.place.id) {
                savedPlace = {
                    var place = details.toSavedPlace(googlePlaceId: placeDraft.place.id)
                    place.category = resolvedFolder
                    return place
                }()
            } else {
                savedPlace = {
                    var place = SavedPlace(
                        googlePlaceId: placeDraft.place.id,
                        name: placeDraft.place.name,
                        address: placeDraft.place.address,
                        latitude: placeDraft.place.latitude,
                        longitude: placeDraft.place.longitude,
                        photos: placeDraft.place.photoURL.map { [$0] } ?? []
                    )
                    place.category = resolvedFolder
                    return place
                }()
            }

            locationsManager.addPlace(savedPlace)
            updateActionDraftStatus(for: messageId, status: .confirmed, folderName: resolvedFolder)
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: "Saved \(savedPlace.displayName) at \(savedPlace.address) to \(resolvedFolder).",
                    intent: .locations
                )
            )
        }

        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func cancelActionDraft(for messageId: UUID) {
        updateActionDraftStatus(for: messageId, status: .cancelled)
        conversationHistory.append(
            ConversationMessage(
                isUser: false,
                text: "Okay, I cancelled that draft.",
                intent: .general
            )
        )
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func draftUndoLastTrackerChange() async {
        guard conversationKind == .tracker, let currentTrackerThread else { return }

        if pendingTrackerDraft != nil {
            appendTrackerAssistantMessage("Confirm or cancel the current tracker draft before undoing another change.")
            saveConversationLocally()
            _ = upsertCurrentConversationInHistory()
            return
        }

        let userMessage = ConversationMessage(
            isUser: true,
            text: "Undo the last change.",
            intent: .general,
            trackerThreadId: currentTrackerThread.id
        )
        conversationHistory.append(userMessage)
        beginTurn(phase: .retrieving, status: ChatStatusPresentation(primaryText: "Updating your tracker", secondaryText: nil, showsDots: true))

        let outcome = await trackerParserService.draftUndoLastChange(
            in: currentTrackerThread,
            conversationHistory: conversationHistory
        )

        pendingTrackerDraft = outcome.draft

        if outcome.shouldPersistAssistantMessage {
            appendTrackerAssistantMessage(
                outcome.responseText,
                draft: outcome.draft,
                stateSnapshot: outcome.derivedState
            )
        }

        if outcome.commitsProjectedStateToThread,
           let projectedState = outcome.derivedState {
            updateTrackerSubtitle(from: projectedState)
        }

        finishTurn()
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func applyPendingTrackerDraft() {
        guard let pendingTrackerDraft else { return }

        let applyResult = trackerParserService.applyDraft(pendingTrackerDraft, to: currentTrackerThread)
        self.pendingTrackerDraft = nil

        if let thread = applyResult.thread {
            conversationKind = .tracker
            conversationTitle = thread.title
            currentTrackerThread = thread
            trackerStore.upsertThread(thread)
            conversationHistory = conversationHistory.map { message in
                ConversationMessage(
                    id: message.id,
                    isUser: message.isUser,
                    text: message.text,
                    timestamp: message.timestamp,
                    intent: message.intent,
                    relatedData: message.relatedData,
                    timeStarted: message.timeStarted,
                    timeFinished: message.timeFinished,
                    followUpSuggestions: message.followUpSuggestions,
                    locationInfo: message.locationInfo,
                    eventCreationInfo: message.eventCreationInfo,
                    relevantContent: message.relevantContent,
                    proactiveQuestion: message.proactiveQuestion,
                    trackerThreadId: thread.id,
                    trackerOperationDraft: message.trackerOperationDraft,
                    trackerStateSnapshot: message.trackerStateSnapshot,
                    evidenceBundle: message.evidenceBundle,
                    toolTrace: message.toolTrace,
                    actionDraft: message.actionDraft,
                    presentation: message.presentation
                )
            }
        }

        conversationHistory.append(
            ConversationMessage(
                isUser: false,
                text: applyResult.message,
                intent: .general,
                trackerThreadId: currentTrackerThread?.id,
                trackerStateSnapshot: currentTrackerThread?.cachedState
            )
        )
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()

        if let currentTrackerThread {
            Task {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
        }
    }

    func cancelPendingTrackerDraft() {
        guard pendingTrackerDraft != nil else { return }
        pendingTrackerDraft = nil
        conversationHistory.append(
            ConversationMessage(
                isUser: false,
                text: "Tracker draft cancelled.",
                intent: .general,
                trackerThreadId: currentTrackerThread?.id,
                trackerStateSnapshot: currentTrackerThread?.cachedState
            )
        )
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    func generateFinalConversationTitle() async {
        guard !conversationHistory.isEmpty else { return }

        if conversationKind == .tracker {
            conversationTitle = currentTrackerThread?.title ?? conversationTitle
            _ = upsertCurrentConversationInHistory()
            if let currentTrackerThread {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
            return
        }

        let currentMessageCount = conversationHistory.count
        let shouldRegenerateTitle =
            isWeakConversationTitle(conversationTitle) ||
            currentMessageCount >= (lastGeneratedTitleMessageCount + 6)

        if shouldRegenerateTitle {
            if let generatedTitle = await generateConversationTitleWithGemini(from: conversationHistory) {
                conversationTitle = generatedTitle
            } else {
                conversationTitle = provisionalConversationTitle(from: conversationHistory)
            }
            lastGeneratedTitleMessageCount = currentMessageCount
        }

        _ = upsertCurrentConversationInHistory()
    }

    func saveConversationToHistory() {
        guard !conversationHistory.isEmpty else { return }
        _ = upsertCurrentConversationInHistory()
    }

    func loadConversationHistoryLocally() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.conversationHistoryStorageKey) else { return }

        do {
            savedConversations = try JSONDecoder().decode([SavedConversation].self, from: data)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("❌ Error loading conversation history: \(error)")
        }
    }

    func restoreMostRecentConversationIfNeeded() {
        if !conversationHistory.isEmpty {
            isInConversationMode = true
            return
        }

        loadConversationHistoryLocally()

        if let loadedId = currentlyLoadedConversationId,
           savedConversations.contains(where: { $0.id == loadedId }) {
            loadConversation(withId: loadedId)
            return
        }

        if let lastActiveId = persistedLastActiveConversationId(),
           savedConversations.contains(where: { $0.id == lastActiveId }) {
            loadConversation(withId: lastActiveId)
            return
        }

        if let mostRecentConversation = savedConversations.first {
            loadConversation(withId: mostRecentConversation.id)
            return
        }

        loadLastConversation()
    }

    func loadConversation(withId id: UUID) {
        stop()

        guard let saved = savedConversations.first(where: { $0.id == id }) else { return }
        conversationHistory = saved.messages
        conversationTitle = saved.title
        conversationKind = saved.kind
        isInConversationMode = true
        isNewConversation = false
        currentlyLoadedConversationId = id
        lastGeneratedTitleMessageCount = conversationHistory.count
        pendingTrackerDraft = saved.messages.last(where: { !$0.isUser })?.trackerOperationDraft
        currentTrackerThread = trackerStore.thread(id: saved.trackerThreadId)
        currentConversationAnchorState = saved.sessionSnapshot?.anchorState ?? saved.messages.last(where: { !$0.isUser })?.evidenceBundle?.anchorState
        phase = .idle
        statusPresentation = .idle
        turnStartedAt = nil
        persistLastActiveConversationId(id)
        saveConversationLocally()
    }

    @discardableResult
    func loadConversationsFromSupabase() async -> [SavedConversation] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("conversations")
                .select("id,title,messages,created_at")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()

            let records = try JSONDecoder.supabaseDecoder().decode([RemoteConversationRecord].self, from: response.data)
            let remoteConversations = deduplicatedRemoteStandardConversations(from: records)
            mergeRemoteStandardConversations(remoteConversations)
            return remoteConversations
        } catch {
            print("❌ Error loading conversations from Supabase: \(error)")
            return []
        }
    }

    func saveConversationToSupabase() async {
        guard !conversationHistory.isEmpty else { return }

        if conversationKind == .tracker, let currentTrackerThread {
            await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            return
        }

        let conversationID = upsertCurrentConversationInHistory()
        guard let localConversation = savedConversations.first(where: { $0.id == conversationID }) else { return }

        let titleToSave = isWeakConversationTitle(conversationTitle)
            ? provisionalConversationTitle(from: conversationHistory)
            : conversationTitle

        do {
            let supabaseManager = SupabaseManager.shared
            let client = await supabaseManager.getPostgrestClient()

            guard let session = try? await supabaseManager.authClient.session else {
                print("❌ No authenticated user to save conversation")
                return
            }
            let userId = session.user.id

            var historyJson = "[]"
            if let encoded = try? JSONEncoder().encode(conversationHistory),
               let jsonString = String(data: encoded, encoding: .utf8) {
                historyJson = jsonString
            }

            struct ConversationData: Encodable {
                let id: UUID
                let user_id: UUID
                let title: String
                let messages: String
                let message_count: Int
                let first_message: String
                let created_at: String
            }

            let data = ConversationData(
                id: conversationID,
                user_id: userId,
                title: titleToSave,
                messages: historyJson,
                message_count: conversationHistory.count,
                first_message: conversationHistory.first?.text ?? "",
                created_at: ISO8601DateFormatter().string(from: localConversation.updatedAt)
            )

            try await client
                .from("conversations")
                .upsert(data, onConflict: "id")
                .execute()
        } catch {
            print("❌ Error saving conversation to Supabase: \(error)")
        }
    }

    func refreshTrackerThreadsFromSupabase() async {
        let bundles = await trackerStore.refreshFromSupabase()
        guard !bundles.isEmpty else { return }

        for bundle in bundles {
            let existingIndex = savedConversations.firstIndex(where: { $0.trackerThreadId == bundle.thread.id })
            let resolvedMessages: [ConversationMessage]
            if !bundle.messages.isEmpty {
                resolvedMessages = bundle.messages
            } else {
                resolvedMessages = existingIndex.flatMap { savedConversations[$0].messages } ?? []
            }

            let saved = SavedConversation(
                id: existingIndex.map { savedConversations[$0].id } ?? UUID(),
                title: bundle.thread.title,
                kind: .tracker,
                trackerThreadId: bundle.thread.id,
                subtitle: bundle.thread.cachedState?.summaryLine ?? bundle.thread.subtitle,
                messages: resolvedMessages,
                createdAt: existingIndex.map { savedConversations[$0].createdAt } ?? bundle.thread.createdAt,
                updatedAt: bundle.thread.updatedAt,
                sessionSnapshot: existingIndex.flatMap { savedConversations[$0].sessionSnapshot }
            )

            let shouldApplyRemote: Bool
            if let existingIndex {
                if saved.updatedAt >= savedConversations[existingIndex].updatedAt {
                    savedConversations[existingIndex] = saved
                    shouldApplyRemote = true
                } else {
                    shouldApplyRemote = false
                }
            } else {
                savedConversations.append(saved)
                shouldApplyRemote = true
            }

            if shouldApplyRemote, currentTrackerThread?.id == bundle.thread.id {
                currentTrackerThread = bundle.thread
                if conversationKind == .tracker, currentlyLoadedConversationId == saved.id {
                    conversationHistory = resolvedMessages
                    pendingTrackerDraft = resolvedMessages.last(where: { !$0.isUser })?.trackerOperationDraft
                    conversationTitle = bundle.thread.title
                }
            }
        }

        savedConversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversationHistoryLocally()
    }

    func deleteConversation(withId id: UUID) {
        let isCurrentlyLoaded = currentlyLoadedConversationId == id

        if let conversation = savedConversations.first(where: { $0.id == id }),
           conversation.kind == .tracker,
           let trackerThreadId = conversation.trackerThreadId {
            trackerStore.deleteThread(id: trackerThreadId)
        } else {
            Task {
                await deleteStandardConversationsFromSupabase(ids: [id])
            }
        }

        savedConversations.removeAll { $0.id == id }

        if isCurrentlyLoaded {
            resetDeletedConversationState()
        }

        saveConversationHistoryLocally()
    }

    func deleteAllConversations() {
        let trackerIds = savedConversations.compactMap(\.trackerThreadId)
        trackerIds.forEach { trackerStore.deleteThread(id: $0) }
        let standardConversationIDs = savedConversations
            .filter { $0.kind == .standard }
            .map(\.id)
        savedConversations.removeAll()

        if !standardConversationIDs.isEmpty {
            Task {
                await deleteStandardConversationsFromSupabase(ids: standardConversationIDs)
            }
        }

        if currentlyLoadedConversationId != nil {
            resetDeletedConversationState()
        }

        saveConversationHistoryLocally()
    }

    func clearConversationDataOnLogout() {
        stop()
        conversationHistory = []
        savedConversations = []
        isInConversationMode = false
        conversationTitle = "New Conversation"
        conversationKind = .standard
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        isNewConversation = false
        currentlyLoadedConversationId = nil
        currentConversationAnchorState = nil
        trackerStore.clearLocalData()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.conversationHistoryStorageKey)
        defaults.removeObject(forKey: Self.lastConversationStorageKey)
        defaults.removeObject(forKey: Self.lastActiveConversationIdStorageKey)
    }

    private func send(_ userMessage: String, appendUserMessage: Bool) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !ChatUsageTracker.shared.isLimitReached else { return }

        if !isInConversationMode {
            isInConversationMode = true
        }

        activeTurnTask?.cancel()
        activeTurnTask = nil

        let requestID = UUID()
        activeRequestID = requestID
        activeToolNames = []
        activeFirstTokenAt = nil
        activeStaleChunkCount = 0
        telemetryStore.begin(
            requestID: requestID,
            conversationID: currentlyLoadedConversationId,
            userMessage: trimmed
        )

        if conversationKind == .tracker {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runTrackerTurn(userMessage: trimmed, requestID: requestID, appendUserMessage: appendUserMessage)
            }
            activeTurnTask = task
            await task.value
            return
        }

        let priorSessionSnapshot = sessionSnapshotForNextTurn()

        let shouldAddUserMessage: Bool
        if !appendUserMessage {
            shouldAddUserMessage = false
        } else if let lastMessage = conversationHistory.last, lastMessage.isUser, lastMessage.text == trimmed {
            shouldAddUserMessage = false
        } else {
            shouldAddUserMessage = true
        }

        if shouldAddUserMessage {
            conversationHistory.append(ConversationMessage(isUser: true, text: trimmed, intent: .general))
        }

        if !isNewConversation {
            updateConversationTitle()
        }

        beginTurn(phase: .routing, status: ChatStatusPresentation(primaryText: "Thinking through your request", secondaryText: nil, showsDots: true))

        let thinkStartTime = Date()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runStandardTurn(
                userMessage: trimmed,
                requestID: requestID,
                thinkStartTime: thinkStartTime,
                sessionSnapshot: priorSessionSnapshot
            )
        }
        activeTurnTask = task
        await task.value
    }

    private func runStandardTurn(
        userMessage: String,
        requestID: UUID,
        thinkStartTime: Date,
        sessionSnapshot: ConversationSessionSnapshot?
    ) async {
        VectorSearchService.shared.beginInteractiveRequest(reason: "chat")
        defer {
            VectorSearchService.shared.endInteractiveRequest(reason: "chat")
        }

        let assistantId = UUID()
        var streamStarted = false
        var accumulatedStreamText = ""

        let turnInput = AgentTurnInput(
            userMessage: userMessage,
            conversationHistory: conversationHistory,
            anchorState: currentConversationAnchorState,
            sessionSnapshot: sessionSnapshot,
            allowLiveSearch: true
        )

        let turnResult = await chatAgent.respond(
            turn: turnInput,
            onToolDispatch: { [weak self] toolNames in
                guard let self else { return }
                guard self.activeRequestID == requestID else {
                    self.activeStaleChunkCount += 1
                    return
                }
                self.activeToolNames = toolNames
                self.phase = .retrieving
                self.statusPresentation = self.makeStatusPresentation(for: .retrieving, toolNames: toolNames)
            },
            onSynthesisStart: { [weak self] in
                guard let self else { return }
                guard self.activeRequestID == requestID else {
                    self.activeStaleChunkCount += 1
                    return
                }
                self.phase = .synthesizing
                self.statusPresentation = self.makeStatusPresentation(for: .synthesizing, toolNames: self.activeToolNames)
            },
            onSynthesisChunk: { [weak self] chunk in
                guard let self else { return }
                guard self.activeRequestID == requestID else {
                    self.activeStaleChunkCount += 1
                    return
                }

                if self.activeFirstTokenAt == nil {
                    self.activeFirstTokenAt = Date()
                    self.telemetryStore.markFirstToken(requestID: requestID, at: self.activeFirstTokenAt)
                }

                accumulatedStreamText += chunk
                let lowered = accumulatedStreamText.lowercased()
                let clarifyingPhrases = [
                    "which specific day",
                    "which day should i focus",
                    "what specific day",
                    "which date should i"
                ]
                if clarifyingPhrases.contains(where: { lowered.contains($0) }) {
                    return
                }

                self.phase = .synthesizing
                self.statusPresentation = self.makeStatusPresentation(for: .synthesizing, toolNames: self.activeToolNames)

                if !streamStarted {
                    streamStarted = true
                    let placeholder = ConversationMessage(
                        id: assistantId,
                        isUser: false,
                        text: accumulatedStreamText,
                        timestamp: Date(),
                        intent: .general,
                        timeStarted: thinkStartTime
                    )
                    self.conversationHistory.append(placeholder)
                } else if let index = self.conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                    self.conversationHistory[index] = ConversationMessage(
                        id: assistantId,
                        isUser: false,
                        text: accumulatedStreamText,
                        timestamp: self.conversationHistory[index].timestamp,
                        intent: .general,
                        timeStarted: thinkStartTime
                    )
                    self.bumpLastMessageContentVersionIfNeeded()
                }
            }
        )

        guard activeRequestID == requestID else { return }

        if activeFirstTokenAt == nil {
            activeFirstTokenAt = Date()
            telemetryStore.markFirstToken(requestID: requestID, at: activeFirstTokenAt)
        }

        currentConversationAnchorState = turnResult.evidenceBundle.anchorState

        if turnResult.assistantText.isEmpty,
           turnResult.actionDraft == nil,
           turnResult.presentation == nil {
            finishTurn(requestID: requestID, result: turnResult)
            return
        }

        if !streamStarted {
            phase = .synthesizing
            statusPresentation = makeStatusPresentation(for: .synthesizing, toolNames: activeToolNames)
        }

        await applyAgentTurnResult(
            turnResult,
            requestID: requestID,
            thinkStartTime: thinkStartTime,
            existingMessageId: streamStarted ? assistantId : nil
        )
    }

    private func runTrackerTurn(
        userMessage: String,
        requestID: UUID,
        appendUserMessage: Bool
    ) async {
        let lower = userMessage.lowercased()

        if pendingTrackerDraft != nil {
            if isTrackerConfirmationMessage(lower) {
                applyPendingTrackerDraft()
                finishTurn(requestID: requestID, result: nil)
                return
            }
            if isTrackerCancellationMessage(lower) {
                cancelPendingTrackerDraft()
                finishTurn(requestID: requestID, result: nil)
                return
            }
        }

        let shouldAddUserMessage = appendUserMessage && !(conversationHistory.last?.isUser == true && conversationHistory.last?.text == userMessage)
        if shouldAddUserMessage {
            conversationHistory.append(
                ConversationMessage(
                    isUser: true,
                    text: userMessage,
                    intent: .general,
                    trackerThreadId: currentTrackerThread?.id
                )
            )
        }

        phase = .retrieving
        statusPresentation = ChatStatusPresentation(primaryText: "Updating your tracker", secondaryText: nil, showsDots: true)

        let outcome = await trackerParserService.handleMessage(
            userMessage,
            in: currentTrackerThread,
            conversationHistory: conversationHistory
        )

        guard activeRequestID == requestID else { return }

        pendingTrackerDraft = outcome.draft

        if outcome.shouldPersistAssistantMessage {
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: outcome.responseText,
                    intent: .general,
                    trackerThreadId: currentTrackerThread?.id,
                    trackerOperationDraft: outcome.draft,
                    trackerStateSnapshot: outcome.derivedState
                )
            )
        }

        if outcome.commitsProjectedStateToThread,
           let projectedState = outcome.derivedState {
            updateTrackerSubtitle(from: projectedState)
        }

        finishTurn(requestID: requestID, result: nil)
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    private func applyAgentTurnResult(
        _ turnResult: AgentTurnResult,
        requestID: UUID,
        thinkStartTime: Date,
        existingMessageId: UUID? = nil
    ) async {
        guard activeRequestID == requestID else {
            activeStaleChunkCount += 1
            return
        }

        let citationProjection = projectedCitations(in: turnResult.responseText, from: turnResult.evidenceBundle)
        let relevantContent = citationProjection.relevantContent
        let relatedData = citationProjection.relatedData
        let displayResponseText = citationProjection.responseText
        let presentedEventDrafts = turnResult.presentation?.eventDraftCard ?? turnResult.actionDraft?.eventDrafts

        if let assistantId = existingMessageId {
            if let index = conversationHistory.lastIndex(where: { $0.id == assistantId }) {
                conversationHistory[index] = ConversationMessage(
                    id: assistantId,
                    isUser: false,
                    text: displayResponseText,
                    timestamp: conversationHistory[index].timestamp,
                    intent: .general,
                    relatedData: relatedData.isEmpty ? nil : relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date(),
                    locationInfo: turnResult.locationInfo,
                    eventCreationInfo: presentedEventDrafts,
                    relevantContent: relevantContent,
                    evidenceBundle: turnResult.evidenceBundle,
                    toolTrace: turnResult.toolTrace,
                    actionDraft: turnResult.actionDraft,
                    presentation: turnResult.presentation
                )
                lastMessageContentVersion += 1
            }
        } else {
            conversationHistory.append(
                ConversationMessage(
                    isUser: false,
                    text: displayResponseText,
                    timestamp: Date(),
                    intent: .general,
                    relatedData: relatedData.isEmpty ? nil : relatedData,
                    timeStarted: thinkStartTime,
                    timeFinished: Date(),
                    locationInfo: turnResult.locationInfo,
                    eventCreationInfo: presentedEventDrafts,
                    relevantContent: relevantContent,
                    evidenceBundle: turnResult.evidenceBundle,
                    toolTrace: turnResult.toolTrace,
                    actionDraft: turnResult.actionDraft,
                    presentation: turnResult.presentation
                )
            )
        }

        finishTurn(requestID: requestID, result: turnResult)
        saveConversationLocally()
        _ = upsertCurrentConversationInHistory()
    }

    private func beginTurn(phase: ChatTurnPhase, status: ChatStatusPresentation) {
        self.phase = phase
        statusPresentation = status
        turnStartedAt = turnStartedAt ?? Date()
    }

    private func finishTurn(requestID: UUID? = nil, result: AgentTurnResult? = nil) {
        let resolvedRequestID = requestID ?? activeRequestID
        if let resolvedRequestID {
            telemetryStore.finishCompleted(
                requestID: resolvedRequestID,
                conversationID: currentlyLoadedConversationId,
                model: result?.model,
                toolTrace: result?.toolTrace ?? [],
                staleChunkCount: activeStaleChunkCount
            )
        }

        activeTurnTask = nil
        activeRequestID = nil
        activeToolNames = []
        activeFirstTokenAt = nil
        activeStaleChunkCount = 0
        phase = .idle
        statusPresentation = .idle
        turnStartedAt = nil
    }

    private func bumpLastMessageContentVersionIfNeeded() {
        if Date().timeIntervalSince(lastContentVersionUpdate) > 0.1 {
            lastMessageContentVersion += 1
            lastContentVersionUpdate = Date()
        }
    }

    private func makeStatusPresentation(for phase: ChatTurnPhase, toolNames: [String]) -> ChatStatusPresentation {
        switch phase {
        case .routing:
            return ChatStatusPresentation(primaryText: "Thinking through your request", secondaryText: nil, showsDots: true)
        case .retrieving:
            let names = Set(toolNames)
            if names.contains("get_day_context") {
                return ChatStatusPresentation(
                    primaryText: "Looking through your day",
                    secondaryText: "Checking visits, receipts, notes, and inbox activity",
                    showsDots: true
                )
            }
            if names.contains("search_nearby_places") || names.contains("resolve_live_place") {
                return ChatStatusPresentation(primaryText: "Checking what's nearby", secondaryText: nil, showsDots: true)
            }
            if names.contains("aggregate_seline") {
                return ChatStatusPresentation(primaryText: "Checking visits and receipts", secondaryText: nil, showsDots: true)
            }
            if names.contains("search_seline_records") {
                return ChatStatusPresentation(primaryText: "Scanning your data", secondaryText: nil, showsDots: true)
            }
            return ChatStatusPresentation(primaryText: "Looking through your data", secondaryText: nil, showsDots: true)
        case .synthesizing:
            return ChatStatusPresentation(primaryText: "Writing your answer", secondaryText: nil, showsDots: true)
        case .idle, .cancelled, .failed:
            return .idle
        }
    }

    private func persistCurrentConversationIfNeeded() {
        guard !conversationHistory.isEmpty else { return }
        _ = upsertCurrentConversationInHistory()

        if conversationKind == .tracker, let currentTrackerThread {
            Task {
                await trackerStore.syncThread(currentTrackerThread, messages: conversationHistory)
            }
        }
    }

    @discardableResult
    private func upsertCurrentConversationInHistory() -> UUID {
        let finalTitle = isWeakConversationTitle(conversationTitle)
            ? provisionalConversationTitle(from: conversationHistory)
            : conversationTitle
        let subtitle = currentConversationSubtitle()
        let updatedAt = Date()
        let sessionSnapshot = currentSessionSnapshot(summary: finalTitle)

        if let loadedId = currentlyLoadedConversationId,
           let index = savedConversations.firstIndex(where: { $0.id == loadedId }) {
            savedConversations[index] = SavedConversation(
                id: loadedId,
                title: finalTitle,
                kind: conversationKind,
                trackerThreadId: currentTrackerThread?.id,
                subtitle: subtitle,
                messages: conversationHistory,
                createdAt: savedConversations[index].createdAt,
                updatedAt: updatedAt,
                sessionSnapshot: sessionSnapshot
            )
            persistLastActiveConversationId(loadedId)
            saveConversationHistoryLocally()
            return loadedId
        }

        if let firstMessageId = conversationHistory.first?.id,
           let existingIndex = savedConversations.firstIndex(where: { $0.messages.first?.id == firstMessageId }) {
            let existingId = savedConversations[existingIndex].id
            savedConversations[existingIndex] = SavedConversation(
                id: existingId,
                title: finalTitle,
                kind: conversationKind,
                trackerThreadId: currentTrackerThread?.id,
                subtitle: subtitle,
                messages: conversationHistory,
                createdAt: savedConversations[existingIndex].createdAt,
                updatedAt: updatedAt,
                sessionSnapshot: sessionSnapshot
            )
            currentlyLoadedConversationId = existingId
            persistLastActiveConversationId(existingId)
            saveConversationHistoryLocally()
            return existingId
        }

        let newId = UUID()
        let saved = SavedConversation(
            id: newId,
            title: finalTitle,
            kind: conversationKind,
            trackerThreadId: currentTrackerThread?.id,
            subtitle: subtitle,
            messages: conversationHistory,
            createdAt: Date(),
            updatedAt: updatedAt,
            sessionSnapshot: sessionSnapshot
        )
        savedConversations.insert(saved, at: 0)
        currentlyLoadedConversationId = newId
        persistLastActiveConversationId(newId)
        saveConversationHistoryLocally()
        return newId
    }

    private func currentSessionSnapshot(summary: String) -> ConversationSessionSnapshot {
        let recentTurns = conversationHistory.suffix(6).map { message in
            ConversationSessionTurn(
                role: message.isUser ? "user" : "assistant",
                text: message.text
            )
        }

        return ConversationSessionSnapshot(
            summary: conversationSessionSummary(fallbackSummary: summary),
            anchorState: currentConversationAnchorState,
            recentTurns: recentTurns,
            resolvedEntities: currentConversationAnchorState?.resolvedEntities ?? [],
            resolvedTimeRange: currentConversationAnchorState?.resolvedTimeRange
        )
    }

    private func sessionSnapshotForNextTurn() -> ConversationSessionSnapshot? {
        guard !conversationHistory.isEmpty || currentConversationAnchorState != nil else { return nil }
        let fallbackSummary = isWeakConversationTitle(conversationTitle)
            ? provisionalConversationTitle(from: conversationHistory)
            : conversationTitle
        return currentSessionSnapshot(summary: fallbackSummary)
    }

    private func conversationSessionSummary(fallbackSummary: String) -> String? {
        var parts: [String] = []
        let trimmedFallback = fallbackSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedFallback.isEmpty, !isWeakConversationTitle(trimmedFallback) {
            parts.append(trimmedFallback)
        }

        if let scope = currentConversationAnchorState?.resolvedTimeRange,
           !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Scope: \(scope)")
        }

        let focusedEntities = (currentConversationAnchorState?.resolvedEntities ?? [])
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !focusedEntities.isEmpty {
            parts.append("Focus: \(Array(focusedEntities.prefix(3)).joined(separator: ", "))")
        }

        if let latestAssistant = conversationHistory.reversed().first(where: { !$0.isUser })?.text,
           let excerpt = condensedSessionExcerpt(from: latestAssistant) {
            parts.append("Latest answer: \(excerpt)")
        }

        if parts.isEmpty {
            return trimmedFallback.isEmpty ? nil : trimmedFallback
        }

        return parts.joined(separator: " • ")
    }

    private func condensedSessionExcerpt(from text: String) -> String? {
        let candidateLine = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "`", with: "")
                    .replacingOccurrences(of: #"^[-•*]\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { line in
                !line.isEmpty && !line.hasSuffix(":")
            }

        guard var excerpt = candidateLine, !excerpt.isEmpty else { return nil }
        excerpt = excerpt.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if excerpt.count > 140 {
            excerpt = String(excerpt.prefix(139)) + "…"
        }
        return excerpt
    }

    private func saveConversationLocally() {
        let defaults = UserDefaults.standard

        do {
            var snapshot = Array(conversationHistory.suffix(120))
            var encoded = try JSONEncoder().encode(snapshot)

            if encoded.count > 1_000_000 {
                snapshot = Array(conversationHistory.suffix(40))
                encoded = try JSONEncoder().encode(snapshot)
            }

            defaults.set(encoded, forKey: Self.lastConversationStorageKey)
        } catch {
            print("❌ Error saving conversation locally: \(error)")
        }
    }

    private func loadLastConversation() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.lastConversationStorageKey) else { return }

        do {
            conversationHistory = try JSONDecoder().decode([ConversationMessage].self, from: data)
            guard !conversationHistory.isEmpty else { return }
            conversationTitle = provisionalConversationTitle(from: conversationHistory)
            conversationKind = .standard
            currentTrackerThread = nil
            pendingTrackerDraft = nil
            isInConversationMode = true
            isNewConversation = false
            currentlyLoadedConversationId = nil
            lastGeneratedTitleMessageCount = conversationHistory.count
            currentConversationAnchorState = conversationHistory.last(where: { !$0.isUser })?.evidenceBundle?.anchorState
        } catch {
            print("❌ Error loading conversation: \(error)")
        }
    }

    private func saveConversationHistoryLocally() {
        let defaults = UserDefaults.standard

        do {
            let compact = Array(savedConversations.prefix(30)).map { conversation in
                SavedConversation(
                    id: conversation.id,
                    title: conversation.title,
                    kind: conversation.kind,
                    trackerThreadId: conversation.trackerThreadId,
                    subtitle: conversation.subtitle,
                    messages: Array(conversation.messages.suffix(80)),
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    sessionSnapshot: conversation.sessionSnapshot
                )
            }

            let encoded = try JSONEncoder().encode(compact)
            defaults.set(encoded, forKey: Self.conversationHistoryStorageKey)
        } catch {
            print("❌ Error saving conversation history: \(error)")
        }
    }

    private func persistedLastActiveConversationId() -> UUID? {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.lastActiveConversationIdStorageKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func persistLastActiveConversationId(_ id: UUID?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id.uuidString, forKey: Self.lastActiveConversationIdStorageKey)
        } else {
            defaults.removeObject(forKey: Self.lastActiveConversationIdStorageKey)
        }
    }

    private func currentConversationSubtitle() -> String? {
        if conversationKind == .tracker {
            return currentTrackerThread?.subtitle ?? currentTrackerThread?.cachedState?.summaryLine
        }
        return nil
    }

    private func generateConversationTitleWithGemini(from messages: [ConversationMessage]) async -> String? {
        guard !messages.isEmpty else { return nil }

        let compactTranscript = messages
            .prefix(10)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                let compact = message.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(role): \(compact)"
            }
            .joined(separator: "\n")

        let prompt = """
        Create ONE specific chat title from this transcript.

        Rules:
        - 4 to 8 words
        - Concrete and descriptive
        - Include key topic/timeframe when relevant
        - DO NOT start with generic phrasing like "Tell me", "What did I do", "Can you"
        - No quotes, no markdown, no trailing punctuation

        Transcript:
        \(compactTranscript)

        Title:
        """

        do {
            let rawTitle = try await GeminiService.shared.generateText(
                systemPrompt: "You create concise, specific conversation titles.",
                userPrompt: prompt,
                maxTokens: 24,
                temperature: 0.25,
                operationType: "conversation_title"
            )
            let cleaned = sanitizeConversationTitle(rawTitle)
            guard !cleaned.isEmpty, cleaned.count <= 80, !isWeakConversationTitle(cleaned) else { return nil }
            return cleaned
        } catch {
            return nil
        }
    }

    private func provisionalConversationTitle(from messages: [ConversationMessage]) -> String {
        if conversationKind == .tracker {
            return currentTrackerThread?.title ?? "Tracker"
        }
        if let firstUserMessage = messages.first(where: { $0.isUser }) {
            let compact = firstUserMessage.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if compact.isEmpty { return "New chat" }
            return compact.count > 80 ? String(compact.prefix(79)) + "…" : compact
        }
        return "New chat"
    }

    private func sanitizeConversationTitle(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "Title:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".!?-–— "))
        return cleaned
    }

    private func isWeakConversationTitle(_ title: String) -> Bool {
        if conversationKind == .tracker {
            return title.isEmpty || title == "New Tracker" || title == "Tracker"
        }
        let lower = title.lowercased()
        if title.isEmpty || title == "New Conversation" || title == "New chat" { return true }
        if lower.hasPrefix("tell me") || lower.hasPrefix("what did i do") || lower.hasPrefix("can you") { return true }
        if lower.hasPrefix("chat on ") { return true }
        return false
    }

    private func deduplicatedRemoteStandardConversations(from records: [RemoteConversationRecord]) -> [SavedConversation] {
        var bestConversationsByKey: [String: SavedConversation] = [:]

        for record in records {
            guard let conversation = remoteStandardConversation(from: record) else { continue }
            let dedupeKey = conversation.messages.first?.id.uuidString ?? record.id.uuidString

            if let existing = bestConversationsByKey[dedupeKey] {
                let shouldReplace =
                    conversation.messages.count > existing.messages.count ||
                    (conversation.messages.count == existing.messages.count && conversation.updatedAt > existing.updatedAt)
                if shouldReplace {
                    bestConversationsByKey[dedupeKey] = conversation
                }
            } else {
                bestConversationsByKey[dedupeKey] = conversation
            }
        }

        return bestConversationsByKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func remoteStandardConversation(from record: RemoteConversationRecord) -> SavedConversation? {
        let messagesData = record.messages.data(using: .utf8) ?? Data("[]".utf8)
        let decoder = JSONDecoder()
        let messages: [ConversationMessage]
        if let all = try? decoder.decode([ConversationMessage].self, from: messagesData) {
            messages = all
        } else if let raws = try? decoder.decode([ChatSessionSafeDecodable<ConversationMessage>].self, from: messagesData) {
            messages = raws.compactMap(\.value)
        } else {
            messages = []
        }

        let title = sanitizedStandardConversationTitle(record.title, messages: messages)
        return SavedConversation(
            id: record.id,
            title: title,
            kind: .standard,
            messages: messages,
            createdAt: record.created_at,
            updatedAt: record.created_at
        )
    }

    private func mergeRemoteStandardConversations(_ remoteConversations: [SavedConversation]) {
        guard !remoteConversations.isEmpty else { return }

        for remoteConversation in remoteConversations {
            if let index = savedConversations.firstIndex(where: { $0.kind == .standard && $0.id == remoteConversation.id }) {
                savedConversations[index] = mergedStandardConversation(local: savedConversations[index], remote: remoteConversation)
                continue
            }

            if let firstMessageID = remoteConversation.messages.first?.id,
               let index = savedConversations.firstIndex(where: {
                   $0.kind == .standard && $0.messages.first?.id == firstMessageID
               }) {
                savedConversations[index] = mergedStandardConversation(local: savedConversations[index], remote: remoteConversation)
                continue
            }

            savedConversations.append(remoteConversation)
        }

        savedConversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversationHistoryLocally()
    }

    private func mergedStandardConversation(local: SavedConversation, remote: SavedConversation) -> SavedConversation {
        let remoteIsNewer = remote.updatedAt > local.updatedAt
        let preferredMessages: [ConversationMessage]

        if remote.messages.count > local.messages.count {
            preferredMessages = remote.messages
        } else if remote.messages.count < local.messages.count {
            preferredMessages = local.messages
        } else {
            preferredMessages = remoteIsNewer ? remote.messages : local.messages
        }

        let title = remoteIsNewer
            ? preferredStandardConversationTitle(local: local.title, remote: remote.title, messages: preferredMessages)
            : preferredStandardConversationTitle(local: remote.title, remote: local.title, messages: preferredMessages)

        return SavedConversation(
            id: local.id,
            title: title,
            kind: .standard,
            trackerThreadId: local.trackerThreadId ?? remote.trackerThreadId,
            subtitle: local.subtitle ?? remote.subtitle,
            messages: preferredMessages,
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt),
            sessionSnapshot: remote.sessionSnapshot ?? local.sessionSnapshot
        )
    }

    private func preferredStandardConversationTitle(local: String, remote: String, messages: [ConversationMessage]) -> String {
        let localTitle = sanitizedStandardConversationTitle(local, messages: messages)
        let remoteTitle = sanitizedStandardConversationTitle(remote, messages: messages)
        let localIsWeak = isWeakStandardConversationTitle(localTitle)
        let remoteIsWeak = isWeakStandardConversationTitle(remoteTitle)

        switch (localIsWeak, remoteIsWeak) {
        case (true, false):
            return remoteTitle
        case (false, true):
            return localTitle
        default:
            return localTitle
        }
    }

    private func sanitizedStandardConversationTitle(_ rawTitle: String, messages: [ConversationMessage]) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !isWeakStandardConversationTitle(trimmed) {
            return trimmed
        }

        if let firstUserMessage = messages.first(where: { $0.isUser })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUserMessage.isEmpty {
            return firstUserMessage.count > 80 ? String(firstUserMessage.prefix(79)) + "…" : firstUserMessage
        }

        return trimmed.isEmpty ? "New chat" : trimmed
    }

    private func isWeakStandardConversationTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        if title.isEmpty || title == "New Conversation" || title == "New chat" { return true }
        if lower.hasPrefix("tell me") || lower.hasPrefix("what did i do") || lower.hasPrefix("can you") { return true }
        if lower.hasPrefix("chat on ") { return true }
        return false
    }

    private func updateConversationTitle() {
        if conversationKind == .tracker {
            conversationTitle = currentTrackerThread?.title ?? "New Tracker"
            return
        }
        conversationTitle = ""
    }

    private func updateTrackerSubtitle(from state: TrackerDerivedState) {
        guard conversationKind == .tracker else { return }
        if var thread = currentTrackerThread {
            thread.cachedState = state
            thread.subtitle = state.summaryLine
            currentTrackerThread = thread
            trackerStore.upsertThread(thread)
        }
    }

    private func isTrackerConfirmationMessage(_ lower: String) -> Bool {
        ["confirm", "yes", "looks good", "save it", "apply it"].contains(lower)
    }

    private func isTrackerCancellationMessage(_ lower: String) -> Bool {
        ["cancel", "never mind", "stop", "discard"].contains(lower)
    }

    private func appendTrackerAssistantMessage(
        _ text: String,
        draft: TrackerOperationDraft? = nil,
        stateSnapshot: TrackerDerivedState? = nil
    ) {
        conversationHistory.append(
            ConversationMessage(
                isUser: false,
                text: text,
                intent: .general,
                trackerThreadId: currentTrackerThread?.id,
                trackerOperationDraft: draft,
                trackerStateSnapshot: stateSnapshot ?? currentTrackerThread?.cachedState
            )
        )
    }

    private func updateActionDraftStatus(
        for messageId: UUID,
        status: AgentActionDraftStatus,
        folderName: String? = nil
    ) {
        guard let index = conversationHistory.firstIndex(where: { $0.id == messageId }),
              let draft = conversationHistory[index].actionDraft else {
            return
        }

        let updatedPlaceDraft: SavedPlaceDraftInfo?
        if let placeDraft = draft.placeDraft {
            updatedPlaceDraft = SavedPlaceDraftInfo(place: placeDraft.place, folderName: folderName ?? placeDraft.folderName)
        } else {
            updatedPlaceDraft = nil
        }

        conversationHistory[index].actionDraft = AgentActionDraft(
            id: draft.id,
            type: draft.type,
            status: status,
            requiresConfirmation: draft.requiresConfirmation,
            eventDrafts: draft.eventDrafts,
            noteDraft: draft.noteDraft,
            emailPreview: draft.emailPreview,
            placeDraft: updatedPlaceDraft
        )

        if let presentation = conversationHistory[index].presentation,
           let livePlaceCard = presentation.livePlaceCard,
           let updatedPlaceDraft {
            conversationHistory[index].presentation = AgentPresentation(
                eventDraftCard: presentation.eventDraftCard,
                noteDraftCard: presentation.noteDraftCard,
                emailPreviewCard: presentation.emailPreviewCard,
                livePlaceCard: LivePlacePreviewInfo(
                    results: livePlaceCard.results,
                    selectedPlaceId: updatedPlaceDraft.place.id,
                    prompt: livePlaceCard.prompt
                )
            )
        }

        lastMessageContentVersion += 1
    }

    private func createEventsFromDraft(_ events: [EventCreationInfo]) async {
        let taskManager = TaskManager.shared
        let calendar = Calendar.current

        for event in events {
            let weekday = weekdayFromNumber(calendar.component(.weekday, from: event.date))
            taskManager.addTask(
                title: event.title,
                to: weekday,
                description: event.notes,
                scheduledTime: event.hasTime ? event.date : nil,
                endTime: event.endDate,
                targetDate: event.date,
                reminderTime: reminderTime(for: event.reminderMinutes),
                location: event.location,
                isRecurring: event.recurrenceFrequency != nil,
                recurrenceFrequency: event.recurrenceFrequency,
                customRecurrenceDays: nil,
                tagId: tagId(forCategory: event.category) ?? event.tagId
            )
        }
    }

    private func reminderTime(for minutes: Int?) -> ReminderTime? {
        guard let minutes else { return nil }
        switch minutes {
        case ..<15:
            return .fifteenMinutes
        case ..<60:
            return .oneHour
        case ..<180:
            return .threeHours
        default:
            return .oneDay
        }
    }

    private func weekdayFromNumber(_ number: Int) -> WeekDay {
        switch number {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    private func tagId(forCategory category: String) -> String? {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.lowercased() != "personal" else { return nil }

        let tagManager = TagManager.shared
        if let existing = tagManager.tags.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return existing.id
        }

        return tagManager.createTag(name: normalized)?.id
    }

    private struct CitationProjection {
        let responseText: String
        let relevantContent: [RelevantContentInfo]?
        let relatedData: [RelatedDataItem]
    }

    private func projectedCitations(
        in responseText: String,
        from evidenceBundle: EvidenceBundle
    ) -> CitationProjection {
        let indices = citationIndices(
            in: responseText,
            maxIndex: evidenceBundle.records.count - 1
        )

        guard !indices.isEmpty else {
            return CitationProjection(
                responseText: normalizedEvidenceCitationText(responseText),
                relevantContent: nil,
                relatedData: []
            )
        }

        var flattenedRelevantContent: [RelevantContentInfo] = []
        var seenContentKeys = Set<String>()
        var relatedDataItems: [RelatedDataItem] = []
        var localCitationIndexByEvidenceIndex: [Int: Int] = [:]

        for index in indices {
            guard evidenceBundle.records.indices.contains(index) else { continue }
            let record = evidenceBundle.records[index]

            if let related = relatedData(from: record) {
                relatedDataItems.append(related)
            }

            let items = relevantContentItems(from: record)
            let dedupedItems = items.filter { seenContentKeys.insert(relevantContentDedupKey(for: $0)).inserted }
            guard !dedupedItems.isEmpty else { continue }
            localCitationIndexByEvidenceIndex[index] = flattenedRelevantContent.count
            flattenedRelevantContent.append(contentsOf: dedupedItems)
        }

        return CitationProjection(
            responseText: remappedCitationText(
                responseText,
                localCitationIndexByEvidenceIndex: localCitationIndexByEvidenceIndex,
                maxEvidenceIndex: evidenceBundle.records.count - 1
            ),
            relevantContent: flattenedRelevantContent.isEmpty ? nil : flattenedRelevantContent,
            relatedData: relatedDataItems
        )
    }

    private func citationIndices(in responseText: String, maxIndex: Int) -> [Int] {
        guard maxIndex >= 0 else { return [] }

        let normalized = normalizedEvidenceCitationText(responseText)
        let pattern = #"\[(\d+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, options: [], range: nsRange)
        var orderedIndices: [Int] = []
        var seen = Set<Int>()

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0,
                value <= maxIndex,
                seen.insert(value).inserted
            else {
                continue
            }
            orderedIndices.append(value)
        }

        return orderedIndices
    }

    private func remappedCitationText(
        _ responseText: String,
        localCitationIndexByEvidenceIndex: [Int: Int],
        maxEvidenceIndex: Int
    ) -> String {
        let normalized = normalizedEvidenceCitationText(responseText)
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else {
            return normalized
        }

        let mutable = NSMutableString(string: normalized)
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized))

        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0
            else {
                mutable.replaceCharacters(in: match.range, with: "")
                continue
            }

            if value <= maxEvidenceIndex, let localIndex = localCitationIndexByEvidenceIndex[value] {
                mutable.replaceCharacters(in: match.range, with: "[\(localIndex)]")
            } else {
                mutable.replaceCharacters(in: match.range, with: "")
            }
        }

        return (mutable as String)
            .components(separatedBy: "\n")
            .map { line in
                let leading = String(line.prefix { $0 == " " || $0 == "\t" })
                let remainder = String(line.dropFirst(leading.count))
                    .replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
                return leading + remainder
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedEvidenceCitationText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")

        let replacements: [(pattern: String, template: String)] = [
            (#"\[\s*(?:evidenceBundle\.)?records\.(\d+)\s*\]"#, "[$1]"),
            (#"\[\s*(?:evidenceBundle\.)?citations\.(\d+)\s*\]"#, "[$1]")
        ]
        for replacement in replacements {
            normalized = normalized.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }

        let stripPatterns = [
            #"\[\s*(?:evidenceBundle\.)?aggregates\.\d+\s*\]"#,
            #"\[\s*(?:evidenceBundle\.)?aggregate_rows\.\d+\s*\]"#
        ]
        for pattern in stripPatterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return normalized
    }

    private func relevantContentItems(from record: EvidenceRecord) -> [RelevantContentInfo] {
        if record.ref.type == .daySummary {
            return daySummaryRelevantContent(from: record)
        }

        if let item = relevantContent(from: record) {
            return [item]
        }

        return []
    }

    private func relevantContent(from record: EvidenceRecord) -> RelevantContentInfo? {
        switch record.ref.type {
        case .email:
            return RelevantContentInfo.email(
                id: record.ref.id,
                subject: record.title,
                sender: record.attributes["sender"] ?? "Email",
                snippet: record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value) ?? Date()
            )
        case .note:
            guard let noteId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.note(
                id: noteId,
                title: record.title,
                snippet: record.summary,
                folder: record.attributes["folder"] ?? "Notes"
            )
        case .receipt:
            guard let receiptId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.receipt(
                id: receiptId,
                title: record.title,
                amount: record.attributes["amount"].flatMap { CurrencyParser.extractAmount(from: $0) },
                date: parseEvidenceDate(record.timestamps.first?.value),
                category: record.attributes["category"]
            )
        case .event:
            guard let eventId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.event(
                id: eventId,
                title: record.title,
                date: parseEvidenceDate(record.timestamps.first?.value) ?? Date(),
                category: record.attributes["calendar"] ?? "Personal"
            )
        case .location, .nearbyPlace:
            guard let locationId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.location(
                id: locationId,
                name: record.title,
                address: record.attributes["address"] ?? record.summary,
                category: record.attributes["category"] ?? "Place"
            )
        case .visit:
            guard let visitId = UUID(uuidString: record.ref.id) else { return nil }
            let placeRelation = record.relations.first(where: { $0.type == "place" })
            let placeId = placeRelation.flatMap { UUID(uuidString: $0.target.id) }
            return RelevantContentInfo.visit(
                id: visitId,
                placeId: placeId,
                placeName: placeRelation?.target.title ?? record.title,
                address: record.attributes["address"] ?? record.summary,
                entryTime: parseEvidenceDate(record.timestamps.first(where: { $0.label == "entry" })?.value),
                exitTime: parseEvidenceDate(record.timestamps.first(where: { $0.label == "exit" })?.value),
                durationMinutes: Int(record.attributes["duration_minutes"] ?? "")
            )
        case .person:
            guard let personId = UUID(uuidString: record.ref.id) else { return nil }
            return RelevantContentInfo.person(
                id: personId,
                name: record.title,
                relationship: record.attributes["relationship"]
            )
        case .daySummary, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func daySummaryRelevantContent(from record: EvidenceRecord) -> [RelevantContentInfo] {
        var items: [RelevantContentInfo] = []
        var seen = Set<String>()

        for relation in record.relations {
            guard let item = relevantContent(from: relation) else { continue }
            let key = relevantContentDedupKey(for: item)
            guard seen.insert(key).inserted else { continue }
            items.append(item)
        }

        return Array(items.prefix(8))
    }

    private func relevantContent(from relation: EvidenceRelation) -> RelevantContentInfo? {
        switch relation.target.type {
        case .email:
            return RelevantContentInfo.email(
                id: relation.target.id,
                subject: relation.target.title ?? relation.label ?? "Email",
                sender: relation.label ?? "Email",
                snippet: relation.label ?? "",
                date: Date()
            )
        case .note:
            guard let noteId = UUID(uuidString: relation.target.id) else { return nil }
            let folderName: String
            switch relation.type {
            case "journal":
                folderName = "Journal"
            case "weekly_recap":
                folderName = "Journal Weekly Summary"
            default:
                folderName = relation.label ?? "Notes"
            }
            return RelevantContentInfo.note(
                id: noteId,
                title: relation.target.title ?? relation.label ?? "Note",
                snippet: relation.label ?? "",
                folder: folderName
            )
        case .receipt:
            guard let receiptId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.receipt(
                id: receiptId,
                title: relation.target.title ?? relation.label ?? "Receipt",
                amount: nil,
                date: nil,
                category: relation.label
            )
        case .event:
            guard let eventId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.event(
                id: eventId,
                title: relation.target.title ?? relation.label ?? "Event",
                date: Date(),
                category: relation.label ?? "Calendar"
            )
        case .location:
            guard let locationId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.location(
                id: locationId,
                name: relation.target.title ?? relation.label ?? "Place",
                address: relation.label ?? "",
                category: "Place"
            )
        case .visit:
            guard let visitId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.visit(
                id: visitId,
                placeId: nil,
                placeName: relation.target.title ?? relation.label ?? "Visit",
                address: nil,
                entryTime: nil,
                exitTime: nil,
                durationMinutes: nil
            )
        case .person:
            guard let personId = UUID(uuidString: relation.target.id) else { return nil }
            return RelevantContentInfo.person(
                id: personId,
                name: relation.target.title ?? relation.label ?? "Person",
                relationship: relation.label
            )
        case .daySummary, .nearbyPlace, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func relevantContentDedupKey(for item: RelevantContentInfo) -> String {
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

    private func relatedData(from record: EvidenceRecord) -> RelatedDataItem? {
        switch record.ref.type {
        case .email:
            return RelatedDataItem(
                type: .email,
                title: record.title,
                subtitle: record.attributes["sender"] ?? record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value)
            )
        case .note:
            return RelatedDataItem(
                type: .note,
                title: record.title,
                subtitle: record.summary.isEmpty ? record.attributes["folder"] : record.summary
            )
        case .receipt:
            return RelatedDataItem(
                type: .receipt,
                title: record.title,
                subtitle: record.attributes["category"],
                date: parseEvidenceDate(record.timestamps.first?.value),
                amount: record.attributes["amount"].flatMap { CurrencyParser.extractAmount(from: $0) },
                merchant: record.title
            )
        case .event:
            return RelatedDataItem(
                type: .event,
                title: record.title,
                subtitle: record.summary,
                date: parseEvidenceDate(record.timestamps.first?.value)
            )
        case .location:
            return RelatedDataItem(
                type: .location,
                title: record.title,
                subtitle: record.attributes["address"] ?? record.summary
            )
        case .visit, .person, .daySummary, .nearbyPlace, .currentContext, .aggregate, .webResult:
            return nil
        }
    }

    private func parseEvidenceDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        return iso.date(from: raw)
    }

    private func resetDeletedConversationState() {
        stop()
        conversationHistory = []
        isInConversationMode = false
        conversationTitle = "New Conversation"
        conversationKind = .standard
        currentTrackerThread = nil
        pendingTrackerDraft = nil
        isNewConversation = false
        currentlyLoadedConversationId = nil
        lastGeneratedTitleMessageCount = 0
        currentConversationAnchorState = nil
        UserDefaults.standard.removeObject(forKey: Self.lastConversationStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.lastActiveConversationIdStorageKey)
    }

    private func deleteStandardConversationsFromSupabase(ids: [UUID]) async {
        guard !ids.isEmpty, let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("conversations")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .in("id", values: ids.map(\.uuidString))
                .execute()
        } catch {
            print("❌ Failed deleting conversations from Supabase: \(error)")
        }
    }
}

private struct RemoteConversationRecord: Decodable {
    let id: UUID
    let title: String
    let messages: String
    let created_at: Date
}
