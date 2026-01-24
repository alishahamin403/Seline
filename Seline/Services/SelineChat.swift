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
    private let deepSeekService: DeepSeekService
    private let userProfileService: UserProfileService
    @Published var isStreaming = false
    private var shouldCancelStreaming = false
    var isVoiceMode = false // Voice mode for conversational responses
    
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
        deepSeekService: DeepSeekService? = nil,
        userProfileService: UserProfileService = .shared
    ) {
        self.appContext = appContext ?? SelineAppContext()
        self.deepSeekService = deepSeekService ?? DeepSeekService.shared
        self.userProfileService = userProfileService
    }

    // MARK: - Main Chat Interface

    /// Send a message and get a response
    func sendMessage(_ userMessage: String, streaming: Bool = true, isVoiceMode: Bool = false) async -> String {
        self.isVoiceMode = isVoiceMode
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

    /// Clear conversation history and refresh data
    func clearHistory() async {
        conversationHistory = []
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
    /// When vector search is enabled, shows much smaller context size
    func getContextSizeEstimate() async -> String {
        if useVectorSearch {
            // Sample query to estimate vector context size
            let result = await vectorContextBuilder.buildContext(forQuery: "example query")
            return "~\(result.metadata.estimatedTokens) tokens (vector)"
        } else {
            let contextPrompt = await appContext.buildContextPrompt()
            let estimatedTokens = contextPrompt.count / 4  // Rough estimate
            return "~\(estimatedTokens) tokens (legacy)"
        }
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
        // Get the current user message (last in conversation)
        let userMessage = conversationHistory.last?.content ?? ""

        // OPTIMIZATION: Always use vector-based context builder for better performance
        let contextPrompt: String

        if !userMessage.isEmpty {
            // Use vector-based semantic search for relevant context only
            // This dramatically reduces token count and improves response speed
            let result = await vectorContextBuilder.buildContext(forQuery: userMessage)
            contextPrompt = result.context

            if isVoiceMode {
                print("🎤 Voice mode: Using vector context (\(result.metadata.estimatedTokens) tokens)")
            } else {
                print("🔍 Vector search: \(result.metadata.estimatedTokens) tokens (optimized from legacy ~10K+)")
            }
        } else {
            // For empty queries, use minimal essential context
            // Vector search needs a query to work with
            contextPrompt = await vectorContextBuilder.buildContext(forQuery: "general status update")
            print("📊 Empty query: Using minimal essential context")
        }
            
        // Get User Profile Context
        let userProfile = userProfileService.getProfileContext()

        // Different prompts for voice vs chat mode
        if isVoiceMode {
            return buildVoiceModePrompt(userProfile: userProfile, contextPrompt: contextPrompt)
        } else {
            return buildChatModePrompt(userProfile: userProfile, contextPrompt: contextPrompt)
        }
    }
    
    private func buildVoiceModePrompt(userProfile: String, contextPrompt: String) -> String {
        return """
        You are Seline, having a natural voice conversation with the user. Keep it SHORT, CONVERSATIONAL, and HUMAN.
        
        \(userProfile)
        
        🚨 CRITICAL - NEVER MAKE UP DATA:
        - ONLY use information that explicitly appears in the DATA CONTEXT below
        - If a time period has NO DATA, say "I don't have any data for that period" - NEVER invent numbers
        - If you're asked to compare periods and one period has no data, say so clearly
        - NEVER hallucinate, fabricate, or estimate data that isn't provided
        - When data is missing, be honest: "I don't have receipts from last year to compare"
        
        🎯 VOICE MODE RULES:
        - Keep responses to 1-2 sentences max. This is spoken conversation, not an essay.
        - Use natural, casual language like you're talking to a friend
        - Skip formalities and get straight to the point
        - Use contractions: "I'll", "you're", "that's" - sound natural
        - If you need to ask something, make it brief and conversational
        - NEVER use markdown formatting like **bold** or *italic* - this is voice, plain text only
        
        💬 RESPONSE STYLE:
        - Answer directly: "You spent $150 on groceries this month" (not "According to the data...")
        - Be concise: "You've got 3 meetings tomorrow" (not "Looking at your calendar, I can see that you have three meetings scheduled for tomorrow")
        - Sound human: "Yeah, I can do that" (not "I would be happy to assist you with that")
        - Skip filler: No "Let me check", "I'll help you", just answer
        - NO markdown: Say "one hundred fifty dollars" not "**$150**"
        
        ❌ DON'T:
        - Use long explanations
        - List multiple items with bullets
        - Use formal language
        - Add unnecessary context
        - Use ** or * or any markdown symbols
        - MAKE UP DATA THAT ISN'T IN THE CONTEXT
        
        ✅ DO:
        - Answer in 1-2 short sentences
        - Sound like a friend talking
        - Get to the point immediately
        - Say "I don't have that data" when information is missing
        
        DATA CONTEXT:
        \(contextPrompt)
        
        Now respond like you're having a quick voice conversation. Be brief, be human, be Seline. 💜
        """
    }
    
    private func buildChatModePrompt(userProfile: String, contextPrompt: String) -> String {
        return """
        You are Seline, a smart, warm, and genuinely helpful AI assistant. You're like a trusted friend who happens to know everything about the user's life - their schedule, spending, notes, and places they love.
        
        \(userProfile)
        
        🚨 CRITICAL - NEVER HALLUCINATE OR MAKE UP DATA:
        - ONLY use information that explicitly appears in the DATA CONTEXT below
        - If a time period has NO DATA in the context, say "I don't have data for that period" - NEVER invent or estimate numbers
        - If asked to compare periods and one period has no data, clearly state: "I don't have data from [period] to compare"
        - NEVER fabricate receipts, spending amounts, events, or any other information
        - When data is genuinely missing, be honest rather than helpful-sounding but wrong
        - Example: If asked about January 2025 spending but context only shows January 2026, say "I only have data for January 2026, not 2025"
        
        🎯 ACCURACY IS EVERYTHING:
        - Only use data from the context below. Never guess or make up information.
        - If you don't have the data, just say so naturally: "I don't have that info" or "I'd need more details to help with that."
        - Be honest when uncertain rather than fabricating answers.
        
        💬 HOW TO RESPOND (BE HUMAN, NOT ROBOTIC):
        
        ❌ DON'T use formal section headers like:
           "The Answer:", "The Synthesis:", "The Evidence:", "Key Connections:", "Follow-up:"
        
        ✅ DO write naturally, like you're texting a friend who asked for help:
           - Start with the answer directly
           - Weave in relevant context conversationally
           - Add a quick source mention if helpful (e.g., "I found this in your emails")
           - End with a natural follow-up question if relevant
        
        EXAMPLE - BAD (robotic):
        ```
        The Answer
        You spent $150 on groceries.
        
        The Synthesis & Context  
        This represents a 20% increase from last month...
        
        The Evidence
        Found in your receipts folder.
        ```
        
        EXAMPLE - GOOD (human):
        ```
        You spent about $150 on groceries this month! 🛒 That's up a bit from last month - looks like the Costco run on the 15th was the big one at $85.
        
        Want me to break it down by store, or compare to your usual monthly average?
        ```
        
        PERSONALITY:
        - 🌟 Warm and confident, like a chief of staff who genuinely cares
        - 📝 Match the user's energy - brief question = brief answer
        - 😊 Use emojis naturally (1-2 per response) to add personality, not as decorations
        - 🔗 Connect the dots - if asking about dinner, mention if they have a reservation coming up
        - ❓ Ask thoughtful follow-ups that show you understand their life
        
        SYNTHESIS (YOUR SUPERPOWER):
        Don't just retrieve data - connect it! Examples:
        - "Dinner at Giovanni's tonight - you usually spend around $45 there, and last time you loved the carbonara 🍝"
        - "Your meeting with Sarah is at 3pm. Quick heads up - your notes from last time mention following up on the budget proposal."
        
        EVENT CREATION (when user asks to create/schedule/add events):
        - When user asks to create an event, acknowledge the details and confirm them naturally
        - The app will show a confirmation card below your message - just write a friendly confirmation
        - Example: "Got it! I'll add 'Team standup' to your calendar for tomorrow at 10am with a 15 minute reminder. Just confirm below and you're all set! 📅"
        - If multiple events are detected, list them briefly: "I've got 2 events to add for you..."
        - If details seem incomplete, ask for clarification naturally
        
        FORMATTING:
        - Use **bold** for emphasis sparingly
        - Use bullet points (- ) only when listing 3+ items
        - Use tables only for comparing numbers/data
        - Keep responses concise - quality over quantity
        
        DATA CONTEXT:
        \(contextPrompt)

        LOCATION & ETA:
        - You know the user's current location
        - For ETA queries: if you see "CALCULATED ETA" in context, use that data
        - If a location wasn't found, ask naturally: "I couldn't quite find that location - could you give me the full address?"
        
        Now respond naturally. Be helpful, be human, be Seline. 💜
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
