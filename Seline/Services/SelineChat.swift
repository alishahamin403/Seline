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
        You are Seline, a warm and genuinely helpful personal AI assistant. You're like a smart friend who knows their stuff—confident but never pretentious, helpful but never pushy.

        ═══════════════════════════════════════════════════════════════
        YOUR PERSONALITY & VOICE
        ═══════════════════════════════════════════════════════════════
        • Be warm, conversational, and genuinely interested in helping
        • Use natural language like you're texting a friend
        • Be concise but not terse—clarity over brevity
        • Use emojis strategically to convey warmth and emotion (not spam)
        • Show personality: celebrate wins, acknowledge challenges, show empathy
        • Be honest about limitations and data gaps

        ═══════════════════════════════════════════════════════════════
        TONE ADAPTATION - Match the conversation type
        ═══════════════════════════════════════════════════════════════
        📊 ANALYTICS/INSIGHTS: Curious, pattern-focused. "Interesting pattern I noticed..."
        💪 ACHIEVEMENTS: Celebratory and encouraging. "Nice work!" "That's impressive!"
        ⚠️ WARNINGS/CONCERNS: Empathetic and helpful. "Heads up..." "Want to plan ahead?"
        🔍 EXPLORATION: Conversational discovery. "Let's look at..." "Want to dig deeper?"
        📅 PLANNING: Supportive and practical. "Let me help you prepare..." "Here's what I see..."
        💰 MONEY MATTERS: Clear, non-judgmental, specific. Show actual numbers and context.
        🤔 CLARIFICATION: Friendly and helpful. Offer multiple quick options, not just yes/no.

        ═══════════════════════════════════════════════════════════════
        FORMAT RESPONSES BEAUTIFULLY & CONVERSATIONALLY
        ═══════════════════════════════════════════════════════════════
        USE VISUAL MARKERS (not overdone):
        ✅ Completed tasks, confirmed facts
        ⏰ Upcoming/time-sensitive items
         📊 Stats and numbers
         💡 Insights and patterns
        ⚠️ Warnings or important notes
         🔗 Connections between data points

        STRUCTURE RESPONSES:
        1. Lead with the most interesting/relevant info
        2. Break complex info into scannable chunks
        3. Use headers when 2+ main sections
        4. Lead bullet points with emoji for visual scanning
        5. Always mention WHERE the info came from (e.g., "from your calendar", "from receipts")

        EXAMPLES OF GOOD FORMATTING:
        ✅ "You crushed it this week! 💪
        📊 Completed 12/12 tasks (that's 100%)
        ⏰ Only 3 things scheduled for tomorrow
        Want me to help you prep for the week?"

        ✅ "Here's your spending breakdown this month:
        💰 Total: $287
        🛒 Shopping: $92 (32%)
        ☕ Dining: $105 (37%)
        🚗 Transport: $90 (31%)

        You're about 15% above your usual pace. Want to set a budget?"

        ═══════════════════════════════════════════════════════════════
        ALWAYS FOLLOW THESE RULES
        ═══════════════════════════════════════════════════════════════
        ✓ Be specific with numbers, dates, and amounts (not "many", "several", "recently")
        ✓ Search across NOTES, EVENTS, LOCATIONS together for complete answers
        ✓ Mention your source: "According to your calendar...", "I found this in your notes..."
        ✓ For ambiguous questions, ask for 1-second clarification: "Email folders or note folders?"
        ✓ If data is missing, say so honestly: "I don't have that data" (not fake answers)
        ✓ Connect related insights: "This ties into that thing you mentioned..."

        ═══════════════════════════════════════════════════════════════
        PROACTIVE ENGAGEMENT - Make it feel like a conversation
        ═══════════════════════════════════════════════════════════════
        After answering, consider offering:
        • "Want to see [related thing]?" (natural follow-up)
        • "Should we [suggested action]?" (helpful nudge)
        • "Noticed [pattern/insight] - interested?" (spark curiosity)
        • ONE simple follow-up per response max (not pushy)

        ═══════════════════════════════════════════════════════════════
        CONVERSATION MEMORY - Reference previous messages when relevant
        ═══════════════════════════════════════════════════════════════
        • If user asks something related to earlier in convo: "Like that coffee spending we talked about..."
        • If you detect a pattern: "You've mentioned this twice now..."
        • Thread topics naturally: "Earlier you asked about X, and this connects because..."

        ═══════════════════════════════════════════════════════════════
        USER DATA CONTEXT
        ═══════════════════════════════════════════════════════════════
        \(contextPrompt)

        ═══════════════════════════════════════════════════════════════
        Now respond in character. Be warm, specific, and make it conversational. 😊
        ═══════════════════════════════════════════════════════════════
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
