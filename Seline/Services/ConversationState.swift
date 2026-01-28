import Foundation

/**
 * ConversationState - Focused state for conversation management
 *
 * Split from SearchService to reduce over-subscription.
 * Views that only care about conversation state can subscribe to just this.
 */
@MainActor
class ConversationState: ObservableObject {
    // MARK: - Published Properties

    @Published var conversationHistory: [ConversationMessage] = []
    @Published var isInConversationMode: Bool = false
    @Published var conversationTitle: String = "New Conversation"
    @Published var savedConversations: [SavedConversation] = []
    @Published var isNewConversation: Bool = false
    @Published var isLoadingQuestionResponse: Bool = false

    // MARK: - Private State

    private(set) var currentlyLoadedConversationId: UUID?

    // MARK: - Public Methods

    func startNewConversation() {
        conversationHistory = []
        conversationTitle = "New Conversation"
        isNewConversation = true
        isInConversationMode = true
        currentlyLoadedConversationId = nil
    }

    func loadConversation(_ conversation: SavedConversation) {
        conversationHistory = conversation.messages
        conversationTitle = conversation.title
        isNewConversation = false
        isInConversationMode = true
        currentlyLoadedConversationId = conversation.id
    }

    func addMessage(_ message: ConversationMessage) {
        conversationHistory.append(message)
    }

    func updateLastMessage(content: String) {
        guard !conversationHistory.isEmpty else { return }
        let lastIndex = conversationHistory.count - 1
        let lastMessage = conversationHistory[lastIndex]
        
        // Create a new message with updated text, preserving all other properties
        let updatedMessage = ConversationMessage(
            id: lastMessage.id,
            isUser: lastMessage.isUser,
            text: content,
            timestamp: lastMessage.timestamp,
            intent: lastMessage.intent,
            relatedData: lastMessage.relatedData,
            timeStarted: lastMessage.timeStarted,
            timeFinished: lastMessage.timeFinished,
            followUpSuggestions: lastMessage.followUpSuggestions,
            locationInfo: lastMessage.locationInfo,
            eventCreationInfo: lastMessage.eventCreationInfo,
            relevantContent: lastMessage.relevantContent,
            proactiveQuestion: lastMessage.proactiveQuestion
        )
        conversationHistory[lastIndex] = updatedMessage
    }

    func clearHistory() {
        conversationHistory = []
    }

    func saveConversation(_ conversation: SavedConversation) {
        if let index = savedConversations.firstIndex(where: { $0.id == conversation.id }) {
            savedConversations[index] = conversation
        } else {
            savedConversations.append(conversation)
        }
    }

    func deleteConversation(_ id: UUID) {
        savedConversations.removeAll { $0.id == id }
    }
}
