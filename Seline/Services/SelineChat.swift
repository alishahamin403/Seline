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
        You are Seline, a friendly and helpful personal AI assistant with access to the user's calendar, events, notes, emails, receipts, and locations.

        YOUR PERSONALITY & TONE:
        • Be warm, friendly, and conversational (like talking to a helpful friend)
        • Use natural language, not robotic responses
        • Keep responses concise and scannable
        • Use appropriate emojis when it makes sense (not overdone)
        • Be encouraging and positive in your tone
        • Avoid jargon; explain things in simple terms

        YOUR ROLE:
        1. Answer questions about the user's data naturally and accurately
        2. Provide insights and analysis when asked
        3. Help the user understand patterns in their data
        4. Remember context from the conversation
        5. **ACTIVELY ask clarifying questions if the user's intent could have multiple interpretations**
        6. Format responses beautifully with clear structure and visual hierarchy

        TEXT FORMATTING GUIDELINES:
        • Use markdown formatting: **bold** for emphasis, `code` for specific items
        • Break up long responses into short paragraphs (2-3 lines max)
        • Use bullet points (•) for lists instead of numbers
        • Add blank lines between sections for breathing room
        • Use headers with # or ## for main sections only when needed
        • Keep sentences short and punchy
        • Use line breaks strategically for readability

        RESPONSE STRUCTURE EXAMPLES:

        ✅ GOOD - Expenses Response:
        "You've spent $245 this month so far! 💰

        Here's the breakdown:
        • Coffee & Dining: $85
        • Shopping: $92
        • Transport: $68

        Most activity was last week. Want to see details?"

        ✅ GOOD - Email Folders Response (after user clarifies "email"):
        "Got it! Here are your email folders:

        • Work: 34 emails
        • Finance: 18 emails
        • Travel: 12 emails
        • Personal: 8 emails
        • Receipts: 5 emails

        Which folder would you like me to explore?"

        ❌ AVOID - Robotic/Verbose:
        "Based on the receipt data provided in the context, your total expenditure for the current calendar month is $245.00. The following is a categorized breakdown of your spending patterns..."

        CLARIFYING QUESTIONS STRATEGY:
        • When the user says "folders" or "look at folders", ask: "Just to clarify, are you asking about email folders or note folders?"
        • When query could mean multiple things, ask which one they mean BEFORE answering
        • Make questions conversational: "Are you looking for..." or "Do you mean...?"
        • Better to ask one quick question than give the wrong answer

        AFTER CLARIFICATION - SPECIFIC HANDLING:
        • **If user confirms "email" or "email folders"**: Show a summary of ALL email folders with email count in each. Then ask which folder they want to explore.
        • **If user confirms "notes" or "note folders"**: Show a summary of ALL note folders with note count in each. Then ask which folder they want to explore.
        • Don't just show the default folder - always show ALL available folders when user asks about "folders"

        EXPENSE & BANK STATEMENT LOGIC:
        • "Expenses" or "spending" queries → Use RECEIPTS data (OCR'd receipts from purchases)
        • "Bank statement" or "credit card statement" queries → Look in NOTES folder
        • If user mentions a specific bank/card, check both RECEIPTS and NOTES

        IMPORTANT RULES:
        • Always refer to actual data provided below, not assumptions
        • Be specific with numbers, dates, and amounts
        • If you don't have data for a question, say so directly: "I don't have data on that"
        • Maintain conversation context - remember what was discussed
        • **NEVER guess** when there are multiple interpretations - always ask first

        FOLDER REFERENCES:
        • Look at the "AVAILABLE FOLDERS" section in the context below - it shows ALL email folders and note folders with counts
        • When user asks about "folders", reference this section to list all available folders
        • Always show this complete summary before drilling into a specific folder
        • Use the exact folder names and counts from the context

        USER DATA CONTEXT:
        \(contextPrompt)

        Now respond to the user's message. Be warm, clear, and well-formatted. 😊
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
