import Foundation

/// Main conversation manager for Seline - simpler, more direct approach
/// Uses LLM intelligence instead of pre-processing
///
/// Architecture:
/// - SelineAppContext: Collects all app data without pre-filtering
/// - SelineChat: Manages conversation history and LLM communication
/// - Streaming support: Real-time response chunks with UI callbacks
/// - Future enhancement: Web search integration for external information
///
/// Key design principle: Let the LLM be smart. Send comprehensive context,
/// let it understand intent and provide accurate responses directly.
@MainActor
class SelineChat {
    // MARK: - State

    var conversationHistory: [ChatMessage] = []
    private let appContext: SelineAppContext
    private let openAIService: OpenAIService
    private var isStreaming = false

    // MARK: - Callbacks

    var onMessageAdded: ((ChatMessage) -> Void)?
    var onStreamingChunk: ((String) -> Void)?
    var onStreamingComplete: (() -> Void)?

    // MARK: - Init

    init(
        appContext: SelineAppContext? = nil,
        openAIService: OpenAIService? = nil
    ) {
        self.appContext = appContext ?? SelineAppContext()
        self.openAIService = openAIService ?? OpenAIService.shared
    }

    // MARK: - Main Chat Interface

    /// Send a message and get a response
    func sendMessage(_ userMessage: String, streaming: Bool = true) async -> String {
        // Add user message to history
        let userMsg = ChatMessage(role: .user, content: userMessage, timestamp: Date())
        conversationHistory.append(userMsg)
        onMessageAdded?(userMsg)

        print("💬 User: \(userMessage)")

        // Build the system prompt with app context
        let systemPrompt = await buildSystemPrompt()

        // Build messages for API
        let messages = buildMessagesForAPI()

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

        return response
    }

    /// Clear conversation history
    func clearHistory() async {
        conversationHistory = []
        await appContext.refresh()
    }

    /// Get context size estimate (for display)
    func getContextSizeEstimate() async -> String {
        let contextPrompt = await appContext.buildContextPrompt()
        let estimatedTokens = contextPrompt.count / 4  // Rough estimate
        return "\(estimatedTokens) tokens"
    }

    // MARK: - Private: System Prompt

    private func buildSystemPrompt() async -> String {
        // Get the current user message (last in conversation)
        let userMessage = conversationHistory.last?.content ?? ""

        // Use query-aware context building if we have a user message
        let contextPrompt = !userMessage.isEmpty ?
            await appContext.buildContextPrompt(forQuery: userMessage) :
            await appContext.buildContextPrompt()

        return """
        You are Seline, a friendly personal AI assistant. Be warm, conversational, and concise. Use markdown formatting (bold, headers) and emojis sparingly.

        YOUR ROLE:
        • Answer questions about user data naturally and accurately
        • Ask clarifying questions when intent is ambiguous
        • Mention which data sources you used

        KEY RULES:
        • Always refer to actual data below, never guess
        • Be specific with numbers, dates, amounts
        • Search across NOTES, EVENTS, LOCATIONS together
        • For "folders" queries, ask: email or note folders?
        • For expense queries use RECEIPTS; for bank statements check NOTES
        • If no data matches, say so directly

        USER DATA CONTEXT:
        \(contextPrompt)

        Respond naturally and clearly.
        """
    }

    private func buildMessagesForAPI() -> [[String: String]] {
        var messages: [[String: String]] = []

        // System prompt handled separately in API call

        // Add conversation history
        for msg in conversationHistory {
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
        var fullResponse = ""

        do {
            fullResponse = try await openAIService.simpleChatCompletionStreaming(
                systemPrompt: systemPrompt,
                messages: messages
            ) { chunk in
                self.onStreamingChunk?(chunk)
            }

            onStreamingComplete?()
            isStreaming = false
            return fullResponse
        } catch {
            print("❌ Streaming error: \(error)")
            let fallback = "Sorry, I encountered an error. Please try again."
            onStreamingChunk?(fallback)
            return fallback
        }
    }

    private func getNonStreamingResponse(systemPrompt: String, messages: [[String: String]]) async -> String {
        do {
            let response = try await openAIService.simpleChatCompletion(
                systemPrompt: systemPrompt,
                messages: messages
            )

            return response
        } catch {
            print("❌ Error: \(error)")
            return "Sorry, I encountered an error. Please try again."
        }
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
