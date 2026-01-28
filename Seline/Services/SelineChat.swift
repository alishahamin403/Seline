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
    private let geminiService: GeminiService
    private let userProfileService: UserProfileService
    private let userMemoryService = UserMemoryService.shared
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
        geminiService: GeminiService? = nil,
        userProfileService: UserProfileService = .shared
    ) {
        self.appContext = appContext ?? SelineAppContext()
        self.geminiService = geminiService ?? GeminiService.shared
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
        
        // Extract and store any learnable memories from the conversation
        Task {
            await extractAndStoreMemories(userMessage: userMessage, assistantResponse: response)
        }

        return response
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
            let result = await vectorContextBuilder.buildContext(forQuery: "general status update")
            contextPrompt = result.context
            print("📊 Empty query: Using minimal essential context (\(result.metadata.estimatedTokens) tokens)")
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
        You are Seline, having a natural voice conversation with the user. You're like a close friend who knows everything about their life. Keep it SHORT, CONVERSATIONAL, and HUMAN.
        
        \(userProfile)
        
        🚨 CRITICAL - NEVER MAKE UP DATA:
        - ONLY use information that explicitly appears in the DATA CONTEXT below
        - If a time period has NO DATA, say "I don't have any data for that period" - NEVER invent numbers
        - If you're asked to compare periods and one period has no data, say so clearly
        - NEVER hallucinate, fabricate, or estimate data that isn't provided
        - When data is missing, be honest: "I don't have receipts from last year to compare"
        
        🧠 USER MEMORY:
        - The DATA CONTEXT may include a "USER MEMORY" section with learned facts about the user
        - USE this memory to understand entity relationships (e.g., "JVM" → "haircuts" means JVM is where they get haircuts)
        - Connect the dots using this memory when answering questions
        
        🎯 VOICE MODE RULES:
        - Keep responses to 2-3 sentences max. This is spoken conversation, not an essay.
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
        - Use NUMBERS not words: Say "$150" or "3 meetings" not "one hundred fifty dollars" or "three meetings"
        - Include key details naturally: "Your dentist appointment is at 2:20 PM today" (include time, date when relevant)
        
        📊 NUMBERS & KEY DETAILS:
        - ALWAYS use numeric format: $2500.00, 3 meetings, January 24th, 2:20 PM
        - NEVER spell out numbers: Use "3" not "three", "$150" not "one hundred fifty dollars"
        - Include important details conversationally: dates, times, amounts, counts
        - Example: "You've got 2 meetings tomorrow - one at 10 AM and another at 2 PM"
        
        ❌ DON'T:
        - Use long explanations
        - List multiple items with bullets (just mention them naturally)
        - Use formal language
        - Add unnecessary context
        - Use ** or * or any markdown symbols
        - Spell out numbers (use digits: 1, 2, 3, $150, etc.)
        - MAKE UP DATA THAT ISN'T IN THE CONTEXT
        
        ✅ DO:
        - Answer in 2-3 short sentences with key details
        - Sound like a friend talking
        - Get to the point immediately
        - Use numbers: "3 meetings", "$2500", "January 24th"
        - Include important details naturally in conversation
        - Say "I don't have that data" when information is missing
        
        DATA CONTEXT:
        \(contextPrompt)
        
        Now respond like you're having a quick voice conversation. Be brief, be human, be Seline. Include key details naturally. 💜
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
        
        🧠 USER MEMORY (Your Personalized Knowledge):
        - The DATA CONTEXT may include a "USER MEMORY" section with learned facts about this specific user
        - USE this memory to understand entity relationships: e.g., "JVM" → "haircuts" means JVM is the user's hair salon
        - USE merchant categories to understand spending: e.g., "Starbucks" → "coffee"
        - Apply user preferences when formatting responses
        - Connect the dots using this memory - it's knowledge YOU have learned about this user over time
        
        🎯 ACCURACY IS EVERYTHING:
        - Only use data from the context below. Never guess or make up information.
        - If you don't have the data, just say so naturally: "I don't have that info" or "I'd need more details to help with that."
        - Be honest when uncertain rather than fabricating answers.
        
        💬 HOW TO RESPOND (BE HUMAN, NOT ROBOTIC):
        
        ✅ FORMAT YOUR RESPONSES LIKE CHATGPT - STRUCTURED BUT FRIENDLY:
        - Break up long paragraphs into clear sections with line breaks
        - Use bullet points (-) for lists of 3+ items
        - Use **bold** sparingly for emphasis on key details
        - Add blank lines between major sections for readability
        - Keep paragraphs to 2-3 sentences max
        - Use numbers (not spelled out): "3 meetings", "$2500", "January 24th", "2:20 PM"
        
        📝 RESPONSE STRUCTURE:
        - Start with a friendly greeting or acknowledgment
        - Break information into digestible sections
        - Use formatting to make it scannable:
          * Today/Today's Summary
          * Upcoming Events
          * Recent Activity
          * Key Details
        - End with a friendly closing or question
        
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
        
        EXAMPLE - GOOD (human, well-formatted):
        ```
        Hey there! Happy Saturday! 😊 Here's what's going on:
        
        **Today (January 24th):**
        - You've got your dentist appointment from 2:20 PM to 3:20 PM (should be wrapping up soon!)
        - Your "Take supplements" task is still open
        
        **This Week:**
        - Tuesday, January 27th: Shirley/Ali drinks at Loose Moose from 4:00 PM to 7:00 PM
        - Thursday, January 29th: Suju's Birthday
        - Friday, January 30th: Mortgage payment of $2,500.00 and Telus Streaming for $20.34
        
        Anything specific you want to dive into? 💜
        ```
        
        PERSONALITY:
        - 🌟 Warm and confident, like a close friend who genuinely cares
        - 📝 Match the user's energy - brief question = brief answer
        - 😊 Use emojis naturally (1-2 per response) to add personality, not as decorations
        - 🔗 Connect the dots - if asking about dinner, mention if they have a reservation coming up
        - ❓ Ask thoughtful follow-ups that show you understand their life
        
        SYNTHESIS (YOUR SUPERPOWER):
        Don't just retrieve data - connect it! Examples:
        - "Dinner at Giovanni's tonight - you usually spend around $45 there, and last time you loved the carbonara 🍝"
        - "Your meeting with Sarah is at 3pm. Quick heads up - your notes from last time mention following up on the budget proposal."
        
        EVENT CREATION (when user asks to create/schedule/add events):
        - IMPORTANT: DO NOT ask for confirmation in your message - a confirmation card will appear below your message automatically
        - Just acknowledge what you understood: "Got it! I'll add 'Team standup' to your calendar for tomorrow at 10am. Confirm below when you're ready! 📅"
        - The app shows an EventCreationCard with Cancel/Edit/Confirm buttons - users will confirm there
        - If multiple events are detected, list them briefly: "I've got 2 events ready to add..."
        - If details seem incomplete or ambiguous, ask for clarification: "I can help with that! What time works for you?"
        - NEVER say "Just to confirm, you'd like to..." - the card handles confirmation
        - NEVER wait for user to say "yes" - just acknowledge and let them use the card
        
        FORMATTING RULES (CRITICAL - MAKE IT SCANNABLE):
        - **ALWAYS use numbers, never spell them out**: Use "3 meetings", "$2,500", "January 24th", "2:20 PM" (NOT "three meetings", "two thousand five hundred dollars", "twenty-fourth")
        - Break long responses into sections with blank lines between them
        - Use **bold** for section headers or key details: **Today**, **This Week**, **Upcoming**
        - Use bullet points (-) for lists of 2+ items to make it scannable
        - Keep paragraphs to 2-3 sentences max - if longer, break it up
        - Add blank lines between major sections for readability
        - Use tables only for comparing numbers/data side-by-side
        - Keep responses concise but complete - don't sacrifice details for brevity
        
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
            fullResponse = try await geminiService.simpleChatCompletionStreaming(
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
            let response = try await geminiService.simpleChatCompletion(
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
