import Combine
import Foundation

@MainActor
final class ConversationPageState: ObservableObject {
    @Published private(set) var conversationHistory: [ConversationMessage] = []
    @Published private(set) var isLoadingQuestionResponse: Bool = false
    @Published private(set) var chatLoadingStatusLabel: String = SearchService.ChatLoadingPhase.idle.statusLabel
    @Published private(set) var isTrackerConversation: Bool = false
    @Published private(set) var currentTrackerThread: TrackerThread?
    @Published private(set) var pendingTrackerDraftId: UUID?
    @Published private(set) var lastMessageContentVersion: Int = 0

    private var cancellables = Set<AnyCancellable>()

    init(searchService: SearchService = .shared) {
        searchService.$conversationHistory
            .sink { [weak self] history in
                self?.conversationHistory = history
            }
            .store(in: &cancellables)

        searchService.$isLoadingQuestionResponse
            .sink { [weak self] isLoading in
                self?.isLoadingQuestionResponse = isLoading
            }
            .store(in: &cancellables)

        searchService.$chatLoadingPhase
            .map(\.statusLabel)
            .sink { [weak self] label in
                self?.chatLoadingStatusLabel = label
            }
            .store(in: &cancellables)

        searchService.$conversationKind
            .map { $0 == .tracker }
            .sink { [weak self] isTracker in
                self?.isTrackerConversation = isTracker
            }
            .store(in: &cancellables)

        searchService.$currentTrackerThread
            .sink { [weak self] thread in
                self?.currentTrackerThread = thread
            }
            .store(in: &cancellables)

        searchService.$pendingTrackerDraft
            .map { $0?.id }
            .sink { [weak self] draftId in
                self?.pendingTrackerDraftId = draftId
            }
            .store(in: &cancellables)

        searchService.$lastMessageContentVersion
            .sink { [weak self] version in
                self?.lastMessageContentVersion = version
            }
            .store(in: &cancellables)
    }

    func isStreaming(_ message: ConversationMessage) -> Bool {
        guard !message.isUser, isLoadingQuestionResponse else { return false }
        return conversationHistory.last?.id == message.id
    }

    func isPendingTrackerDraft(_ message: ConversationMessage) -> Bool {
        pendingTrackerDraftId == message.trackerOperationDraft?.id
    }
}
