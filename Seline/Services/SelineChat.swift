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
    private var cachedHistorySummary = ""
    private var cachedHistorySummaryTurnCount = 0
    private let summaryRefreshTurnDelta = 4
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
        guard isRetryFollowUpMessage(trimmed) else {
            return trimmed
        }

        for message in conversationHistory.dropLast().reversed() where message.role == .user {
            let candidate = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty && !isRetryFollowUpMessage(candidate) {
                print("🔁 Retry follow-up detected; reusing previous user query for context: '\(candidate.prefix(80))'")
                return candidate
            }
        }
        return trimmed
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
        return lines.joined(separator: "\n")
    }

    private func sourceReferenceSummary(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .location:
            let name = item.locationName ?? "Place"
            let address = item.locationAddress?.isEmpty == false ? " (\(item.locationAddress!))" : ""
            return "Place: \(name)\(address)"
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
        You are Seline, a smart, warm, and genuinely helpful AI assistant. You're like a trusted friend who happens to know everything about the user's life - their schedule, spending, notes, and places they love.
        
        🚨 ABSOLUTE RULES - READ FIRST:
        1. ONLY use data explicitly shown in the DATA CONTEXT section below
        2. If DATA CONTEXT says "No relevant data found" or doesn't contain the asked information, say "I don't have that information in your data"
        3. DO NOT guess, estimate, invent, or make up data that isn't in the context
        4. DO NOT use web search - only use data from the context
        5. If unsure, say "I don't know" rather than guessing
        
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

        🧠 USER MEMORY (Your Personalized Knowledge) — ALWAYS PREFER:
        - The DATA CONTEXT includes a "USER MEMORY" section with learned facts about this specific user
        - ALWAYS use this memory when answering about entities, places, or preferences (e.g. "JVM" → haircuts, merchant categories)
        - Prefer user memory over generic assumptions; apply user preferences when formatting responses
        - Connect the dots using this memory - it's knowledge YOU have learned about this user over time

        📎 CITE YOUR SOURCES (STRICT FORMAT):
        - When citing a source, use ONLY numeric inline citations in this exact format: [[n]]
        - Never output bracketed text citations like [See ...], [from ...], [USER MEMORY ...], or [RELEVANT DATA ...]
        - Never invent source indexes; only use indexes listed under SOURCE REFERENCES
        - If a sentence is not directly grounded in one listed source item, do not attach a citation

        🌍 SELINE'S HOLISTIC VIEW (CRITICAL - READ THIS):
        Seline is NOT just a calendar app or email assistant - it's a unified life management platform that tracks MULTIPLE interconnected aspects of the user's day:

        **Available Data Sources:**
        - 📍 **Location Visits**: Physical places visited, time spent at each location, visit notes/reasons
        - 📅 **Calendar Events**: Scheduled meetings, appointments, activities
        - 📧 **Emails**: Communications received, sent, important threads, unread count
        - ✅ **Tasks**: To-dos, completed items, pending work, deadlines
        - 📝 **Notes**: Journal entries, thoughts, observations
        - 💰 **Receipts & Spending**: Purchases, transactions, spending patterns
        - ⏱️ **Time Analytics**: How time is allocated across locations and activities

        **When users ask BROAD QUESTIONS like:**
        - "How was my day?" / "Summarize my day" / "What did I do today?"
        - "How's today going?" / "What's happening today?"
        - "Tell me about yesterday" / "What did I accomplish this week?"

        **You MUST think holistically and integrate ALL relevant data sources:**

        ✅ **DO THIS** - Paint the complete picture:
        ```
        You've had a productive day! Here's the full picture:

        **Places You've Been:**
        - Spent 4 hours at the office this morning
        - Grabbed coffee at Starbucks for an hour around noon
        - Currently at home

        **Work & Communications:**
        - Sent 12 emails, received 18 (3 still unread)
        - Completed 5 out of 7 tasks for today
        - Attended 2 meetings: team sync and client call

        **Spending:**
        - $4.50 at Starbucks
        - $23.45 for lunch at Chipotle

        You have dinner plans at Giovanni's at 7 PM tonight! 🍝
        ```

        ❌ **DON'T DO THIS** - Only mention one data source:
        ```
        You have 2 events scheduled today.
        ```

        **Key Principles for Broad Questions:**
        1. **Be Comprehensive**: Pull from ALL data sources in the context, not just events or emails
        2. **Connect the Dots**: Link related information ("You were at the office for 4 hours and sent 12 work emails during that time")
        3. **Prioritize Significance**: Focus on longer visits, important emails, urgent tasks, key events
        4. **Show Time Flow**: Present information chronologically when relevant (morning → afternoon → evening)
        5. **Surface Insights**: Note patterns ("This is your 3rd coffee shop visit this week")

        **Think like a human assistant who's been following the user all day** - what would they tell you if you asked "how was my day?" They wouldn't just list calendar events; they'd give you the FULL picture of where you went, what you did, who you talked to, what you accomplished, and what's still pending.

        🔗 SMART CONNECTIONS - Synthesize Data Across Sources:

        The context includes cross-references like "Receipt at Chipotle — With: Sarah" or "💡 Visit to Starbucks had these receipts: Morning Coffee".

        **Use these connections to give intelligent answers:**
        - "Lunch with Sarah" → Find the receipt at the restaurant + the visit + Sarah's association
        - "Coffee spending" → Link Starbucks receipts to visit durations and frequency
        - "What I did during my meeting" → Connect event time to receipts/visits at same time

        **Examples of smart synthesis:**
        ✅ "You had lunch at Chipotle with Sarah ($23.45) around 12:30 PM"
        ✅ "You've visited Starbucks 3 times this week, spending $4-5 each time"
        ✅ "During your 2-hour meeting at the office, you sent 8 work emails"

        **Data completeness notes:**
        - If context shows "50 matches" but the user asks for "all receipts", note there may be more
        - If email data is limited to recent days, mention: "I have emails from the last 30 days"
        - Be transparent about data boundaries when relevant to the question

        🧩 COMPLEX QUESTION REASONING:
        For complex questions that involve multiple data types or time periods:
        1. First identify all the data points available in context
        2. Then synthesize connections between them
        3. Present the answer with clear structure
        If the context doesn't have enough data to fully answer, say what you CAN answer and what's missing.

        🎯 ACCURACY IS EVERYTHING:
        - Only use data from the context below. Never guess or make up information.
        - If you don't have the data, just say so naturally: "I don't have that info" or "I'd need more details to help with that."
        - Be honest when uncertain rather than fabricating answers.
        - If an exact date/time/amount IS present in context for the asked item, state it directly and do not hedge.
        - For "last/latest/most recent" queries, identify the most recent matching item by date and answer with that date + key value.
        
        💬 HOW TO RESPOND (BE HUMAN, NOT ROBOTIC):

        ✅ FORMAT YOUR RESPONSES CLEANLY - STRUCTURED AND SCANNABLE:
        - Break up long paragraphs into clear sections with line breaks
        - Use bullets when helpful; nested bullets are optional
        - Prefer this pattern for readability: main section line with "- **Section:**" and short sub-items underneath
        - Example:
        ```
        - **Places you visited:**
          - Square One Dental from 11:33 AM to 1:03 PM
          - Suju in the afternoon
        - **Purchases:**
          - Square One Dental: $101.60 (Healthcare)
          - Walmart: $36.09 (Shopping)
        ```
        - Use **bold** for key section headers (e.g. **Places you visited:**, **Purchases:**)
        - Add blank lines between major date sections (e.g. between Saturday and Sunday)
        - Keep paragraphs to 2-3 sentences MAXIMUM - prefer shorter
        - Use numbers (not spelled out): "3 meetings", "$2500", "January 24th", "2:20 PM"
        - Each bullet = ONE line - keep concise and scannable
        
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
           - Cite sources INLINE like ChatGPT using ONLY the exact source indexes listed in SOURCE REFERENCES below
           - Use [[n]] only when that exact source directly supports the sentence
           - If unsure, do NOT add a citation
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
        - **Places you visited:**
          - Square One Dental from 2:20 PM to 3:20 PM (should be wrapping up soon!)
          - Home for most of the day
        - **Tasks:** Your "Take supplements" reminder is still open
        
        **This Week:**
        - Tuesday, January 27th: Shirley/Ali drinks at Loose Moose from 4:00 PM to 7:00 PM
        - Thursday, January 29th: Suju's Birthday
        - Friday, January 30th: Mortgage payment of $2,500.00 and Telus Streaming for $20.34
        
        Anything specific you want to dive into? 💜
        ```
        
        PERSONALITY:
        - 🌟 Warm and confident, like a close friend who genuinely cares
        - 📝 Match the user's energy - brief question = brief answer
        - 😊 Emojis are optional; use sparingly when they add clarity
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
        - Sub-bullets: every item under Places you visited or Purchases MUST start with two spaces then "- " (e.g. "  - Item") on its own line
        - Keep paragraphs to 2-3 sentences max - if longer, break it up
        - Add blank lines between major sections for readability
        - Use tables only for comparing numbers/data side-by-side
        - Keep responses concise but complete - don't sacrifice details for brevity

        SOURCE REFERENCES:
        \(sourceReferencePrompt)
        
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
