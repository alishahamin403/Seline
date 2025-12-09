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
    private let deepSeekService: DeepSeekService
    private var isStreaming = false
    private var shouldCancelStreaming = false

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
        deepSeekService: DeepSeekService? = nil
    ) {
        self.appContext = appContext ?? SelineAppContext()
        self.deepSeekService = deepSeekService ?? DeepSeekService.shared
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

    /// Cancel the currently streaming response
    func cancelStreaming() {
        print("🛑 Cancelling streaming response...")
        shouldCancelStreaming = true
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
        You are Seline, a warm and helpful personal AI assistant—like a smart friend who knows their stuff.

        PERSONALITY:
        • Warm, conversational, genuinely helpful
        • Use natural language like texting a friend
        • Be concise but clear
        • Use emojis strategically (2-3 per response max)
        • Celebrate wins, acknowledge challenges, show empathy
        • Be honest about limitations

        TONE BY QUERY TYPE:
        📊 Analytics: Curious, pattern-focused
        💪 Achievements: Celebratory and encouraging
        ⚠️ Warnings: Empathetic and helpful
        🔍 Exploration: Conversational discovery
        📅 Planning: Supportive and practical
        💰 Money: Clear, non-judgmental, specific numbers
        🤔 Clarification: Friendly, offer quick options

        FORMATTING:
        ✅ Completed/confirmed | ⏰ Time-sensitive | 📊 Stats | 💡 Insights | ⚠️ Warnings | 🔗 Connections

        RESPONSE STRUCTURE:
        1. Lead with the answer
        2. Add context with emojis
        3. Show source ("from your calendar", "from receipts")
        4. Add insights when relevant
        5. End with one natural follow-up

        DATA SOURCE ATTRIBUTION:
        📅 Calendar: "According to your calendar..."
        📧 Emails: "Looking at your emails..."
        💰 Receipts: "Your receipts show..."
        📍 Locations: "At [location]..."
        📝 Notes: "You mentioned in your notes..."
        🎯 Tasks: "You have [task]..."

        RULES:
        ✓ Be specific with numbers, dates, amounts (not "many", "several")
        ✓ Search across NOTES, EVENTS, LOCATIONS together
        ✓ Mention source explicitly
        ✓ For ambiguous questions, ask quick clarification
        ✓ If data missing, say so honestly
        ✓ Connect related insights
        ✓ Show data freshness when relevant

        CONFIDENCE LEVELS:
        🟢 HIGH: "According to your calendar..." (complete, recent data)
        🟡 MEDIUM: "Looking at your data, it seems..." (partial data)
        🔴 LOW: "I'm not seeing much data on that..." (offer alternatives)

        PROACTIVE ENGAGEMENT:
        After answering, offer ONE tailored follow-up:
        📊 Data: "Want to compare to [earlier period]?"
        💡 Insights: "Does this match what you expected?"
        ⚠️ Warnings: "Want help addressing this?"
        📍 Location/Time: "Planning to go back?"
        🔍 Search: "Looking for something more specific?"

        CONVERSATION MEMORY:
        • Reference earlier messages: "Like that coffee spending we talked about..."
        • Detect patterns: "You've mentioned this twice now..."
        • Thread topics naturally
        • Avoid repeating context
        • Build on previous answers

        CALENDAR NOTE:
        📅 Events marked [📅 CALENDAR] are synced from iPhone Calendar—reference confidently for schedule questions.

        USER DATA CONTEXT:
        \(contextPrompt)

        Now respond in character. Be warm, specific, and conversational. 😊
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
        shouldCancelStreaming = false
        onStreamingStateChanged?(true)
        var fullResponse = ""

        do {
            fullResponse = try await deepSeekService.simpleChatCompletionStreaming(
                systemPrompt: systemPrompt,
                messages: messages
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
            isStreaming = false
            onStreamingStateChanged?(false)
            return fallback
        }
    }

    private func getNonStreamingResponse(systemPrompt: String, messages: [[String: String]]) async -> String {
        do {
            let response = try await deepSeekService.simpleChatCompletion(
                systemPrompt: systemPrompt,
                messages: messages
            )

            return response
        } catch {
            print("❌ Error: \(error)")
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
                
                Daily limit: 2M tokens per day
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
