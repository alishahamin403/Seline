import Foundation
import UIKit

/**
 * DeepSeekService - Simplified LLM Service
 *
 * Drop-in replacement for OpenAIService with these benefits:
 * - 90% cheaper than OpenAI
 * - NO rate limits (no 429 errors!)
 * - Better at structured tasks (email parsing, data extraction)
 * - Powerful caching (10x cheaper for repeated prompts)
 */
@MainActor
class DeepSeekService: ObservableObject {
    static let shared = DeepSeekService()

    // Published properties for UI
    @Published var quotaUsed: Int = 0
    @Published var quotaLimit: Int = 100_000
    @Published var quotaPercentage: Double = 0.0
    @Published var cacheSavings: Double = 0.0
    @Published var lastSearchAnswer: SearchAnswer?

    // Daily usage tracking
    @Published var dailyTokensUsed: Int = 0
    @Published var dailyQueryCount: Int = 0
    private var lastResetDate: Date = Date()
    private let dailyTokenLimit: Int = 2_000_000 // 2M tokens per day

    // Average tokens per query (updated dynamically)
    private var averageTokensPerQuery: Int = 15_000 // Conservative estimate

    private init() {
        Task {
            await loadQuotaStatus()
            await loadDailyUsage()
        }
    }

    // MARK: - Main API Methods

    /// Send a chat request (replaces OpenAI's answerQuestion)
    func answerQuestion(
        query: String,
        conversationHistory: [Message] = [],
        operationType: String? = nil
    ) async throws -> String {
        // Convert conversation history to messages
        var messages: [Message] = conversationHistory

        // Add current query
        messages.append(Message(role: "user", content: query))

        // Make request
        let response = try await chat(
            messages: messages,
            operationType: operationType ?? "search"
        )

        return response.choices.first?.message.content ?? ""
    }

    /// Low-level chat method
    func chat(
        messages: [Message],
        model: String = "deepseek-chat",
        temperature: Double = 0.6,  // Reduced from 0.7 for more focused responses
        maxTokens: Int = 1024,  // Reduced from 2048 to save ~50% on output costs
        operationType: String? = nil
    ) async throws -> Response {
        let request = Request(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            operation_type: operationType,
            stream: false
        )

        let response = try await makeProxyRequest(request)

        // Update quota after successful request
        await loadQuotaStatus()

        return response
    }

    /// Summarize email (drop-in replacement for OpenAI method)
    func summarizeEmail(subject: String, body: String) async throws -> String {
        // Debug: Log first 1000 chars of email body to verify content
        let bodyPreview = String(body.prefix(1000))
        print("📧 ===========================================")
        print("📧 Summarizing email - Subject: \(subject)")
        print("📧 Body preview (first 1000 chars):")
        print(bodyPreview)
        print("📧 ===========================================")

        let prompt = """
        You must analyze the email below and create exactly 4 bullet points summarizing ONLY the information found in this specific email.

        Subject: \(subject)

        Body:
        \(body.prefix(8000))

        CRITICAL RULES - NEVER HALLUCINATE:
        1. Extract information ONLY from the email content above - NEVER make up or assume any details
        2. If you cannot find specific information (stock symbols, amounts, account types) in the email, DO NOT mention them
        3. Create exactly 4 bullet points using the • symbol
        4. Each bullet point must be 15 words or less
        5. Include ONLY the specific numbers, dates, amounts, stock symbols, account names that are explicitly stated in the email
        6. Be direct - no prefixes like "Main purpose:" or "Action:"
        7. For financial emails: Include ONLY the exact account type, stock symbol, and dollar amount FROM THE EMAIL TEXT
        8. If the email is too short or lacks detail, summarize what IS there - don't add details

        EXAMPLE - If the email says "You earned $1.44 from MSFT in your TFSA account":
        • You earned a dividend from your investment in MSFT (Microsoft).
        • The dividend amount is $1.44.
        • The dividend will be deposited into your TFSA account.
        • The email is from Wealthsimple regarding your investment activity.

        Return only the 4 bullet points, nothing else.
        """

        let messages = [Message(role: "user", content: prompt)]
        let response = try await chat(
            messages: messages,
            temperature: 0.0,  // Zero temperature for maximum consistency
            maxTokens: 400,    // Increased from 200 to avoid cutoffs
            operationType: "email_summary"
        )

        let summary = response.choices.first?.message.content ?? ""
        print("✅ Generated summary:")
        print(summary)
        print("📧 ===========================================")

        return summary
    }

    // MARK: - Quota Management

    /// Load current quota status from database
    func loadQuotaStatus() async {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [QuotaStatus] = try await client
                .from("deepseek_quota_status")
                .select()
                .execute()
                .value

            if let status = response.first {
                // Use daily quota if available, fallback to monthly for backward compatibility
                self.quotaUsed = status.quota_used ?? status.quota_used_this_month ?? 0
                self.quotaLimit = status.quota_tokens ?? status.monthly_quota_tokens ?? 1000000
                self.quotaPercentage = (Double(quotaUsed) / Double(quotaLimit)) * 100
            }
        } catch {
            print("Error loading quota status: \(error)")
        }
    }

    /// Check if user has enough quota
    func hasQuota(estimatedTokens: Int = 2000) async -> Bool {
        await loadQuotaStatus()
        return (quotaUsed + estimatedTokens) <= quotaLimit
    }

    /// Get formatted quota status string for UI
    var quotaStatusString: String {
        let remaining = quotaLimit - quotaUsed
        return "\(remaining.formatted()) / \(quotaLimit.formatted()) tokens remaining"
    }

    /// Get cache savings string for UI
    var cacheSavingsString: String {
        return "Saved $\(String(format: "%.4f", cacheSavings)) from caching"
    }

    // MARK: - Daily Usage Tracking

    /// Get user-specific keys for UserDefaults
    private func getUserKey(_ key: String) -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id.uuidString else {
            return key // Fallback to global key if no user
        }
        return "\(key)_\(userId)"
    }

    /// Load daily usage from UserDefaults
    func loadDailyUsage() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get user-specific keys
        let tokensKey = getUserKey("dailyTokensUsed")
        let queryCountKey = getUserKey("dailyQueryCount")
        let dateKey = getUserKey("lastResetDate")

        // Load saved date
        if let savedDate = UserDefaults.standard.object(forKey: dateKey) as? Date {
            lastResetDate = savedDate
        }

        // Check if we need to reset (new day)
        if !calendar.isDate(lastResetDate, inSameDayAs: today) {
            // New day - reset counters
            dailyTokensUsed = 0
            dailyQueryCount = 0
            lastResetDate = today
            saveDailyUsage()
        } else {
            // Load from storage
            dailyTokensUsed = UserDefaults.standard.integer(forKey: tokensKey)
            dailyQueryCount = UserDefaults.standard.integer(forKey: queryCountKey)
        }

        print("📊 Daily Usage Loaded: \(dailyTokensUsed) tokens, \(dailyQueryCount) queries")
    }

    /// Save daily usage to UserDefaults
    private func saveDailyUsage() {
        let tokensKey = getUserKey("dailyTokensUsed")
        let queryCountKey = getUserKey("dailyQueryCount")
        let dateKey = getUserKey("lastResetDate")

        UserDefaults.standard.set(dailyTokensUsed, forKey: tokensKey)
        UserDefaults.standard.set(dailyQueryCount, forKey: queryCountKey)
        UserDefaults.standard.set(lastResetDate, forKey: dateKey)

        print("💾 Daily Usage Saved: \(dailyTokensUsed) tokens, \(dailyQueryCount) queries")
    }

    /// Track tokens used in a request
    func trackTokenUsage(tokens: Int) async {
        await loadDailyUsage() // Ensure we have current data
        dailyTokensUsed += tokens
        dailyQueryCount += 1

        // Update average tokens per query
        averageTokensPerQuery = dailyTokensUsed / max(dailyQueryCount, 1)

        saveDailyUsage()
    }

    /// Get remaining tokens for today
    var dailyTokensRemaining: Int {
        max(0, dailyTokenLimit - dailyTokensUsed)
    }

    /// Get estimated queries remaining
    var estimatedQueriesRemaining: Int {
        let remaining = dailyTokensRemaining
        return max(0, remaining / averageTokensPerQuery)
    }

    /// Get formatted daily usage string for UI
    var dailyUsageString: String {
        let usedFormatted = formatTokenCount(dailyTokensUsed)
        let limitFormatted = formatTokenCount(dailyTokenLimit)
        return "\(usedFormatted) / \(limitFormatted) tokens"
    }

    /// Format token count for display (e.g., "1.2M", "500K")
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Private Methods

    private func makeProxyRequest(_ request: Request) async throws -> Response {
        // Get Supabase Edge Function URL
        let functionURL = "\(SupabaseManager.shared.url)/functions/v1/deepseek-proxy"

        guard let url = URL(string: functionURL) else {
            throw DeepSeekError.invalidURL
        }

        // Get auth token
        guard let session = try? await SupabaseManager.shared.authClient.session else {
            throw DeepSeekError.notAuthenticated
        }
        let accessToken = session.accessToken

        // Create request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseManager.shared.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.timeoutInterval = 90  // Increased from 30 to 90 seconds for complex queries

        // Encode body
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        // Handle errors
        if httpResponse.statusCode == 429 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw DeepSeekError.quotaExceeded(errorResponse.error)
            }
            throw DeepSeekError.quotaExceeded("Quota exceeded")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw DeepSeekError.apiError(errorResponse.error)
            }
            throw DeepSeekError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        let decoder = JSONDecoder()
        let deepseekResponse = try decoder.decode(Response.self, from: data)

        // Track token usage
        let totalTokens = deepseekResponse.usage.total_tokens
        await trackTokenUsage(tokens: totalTokens)

        // Log metrics (from headers)
        if let tokensUsed = httpResponse.value(forHTTPHeaderField: "X-Tokens-Used"),
           let cacheHits = httpResponse.value(forHTTPHeaderField: "X-Cache-Hit-Tokens"),
           let latency = httpResponse.value(forHTTPHeaderField: "X-Latency-Ms"),
           let cost = httpResponse.value(forHTTPHeaderField: "X-Cost-Usd") {
            print("✅ DeepSeek: \(tokensUsed) tokens, \(cacheHits) cached, \(latency)ms, $\(cost)")
        }

        return deepseekResponse
    }

    private func makeStreamingProxyRequest(_ request: Request, onChunk: @escaping (String) -> Void) async throws {
        // Get Supabase Edge Function URL
        let functionURL = "\(SupabaseManager.shared.url)/functions/v1/deepseek-proxy"

        guard let url = URL(string: functionURL) else {
            throw DeepSeekError.invalidURL
        }

        // Get auth token
        guard let session = try? await SupabaseManager.shared.authClient.session else {
            throw DeepSeekError.notAuthenticated
        }
        let accessToken = session.accessToken

        // Create request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(SupabaseManager.shared.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.timeoutInterval = 90

        // Encode body
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        // Make streaming request
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw DeepSeekError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Track token usage from headers (estimate for streaming)
        var totalTokens = 0
        if let tokensUsed = httpResponse.value(forHTTPHeaderField: "X-Tokens-Used"),
           let tokens = Int(tokensUsed) {
            totalTokens = tokens
        }

        // Parse SSE stream
        var buffer = ""
        var usageTracked = false
        for try await line in asyncBytes.lines {
            // SSE format: "data: {...}"
            if line.hasPrefix("data: ") {
                let jsonStr = String(line.dropFirst(6))

                // Skip [DONE] marker
                if jsonStr == "[DONE]" {
                    continue
                }

                // Parse chunk
                if let data = jsonStr.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {

                    // Get content if available
                    if let content = chunk.choices.first?.delta.content {
                        onChunk(content)
                    }

                    // Check for usage data in the final chunk
                    if let usage = chunk.usage, !usageTracked {
                        totalTokens = usage.total_tokens
                        await trackTokenUsage(tokens: totalTokens)
                        usageTracked = true
                        print("📊 Streaming tokens tracked: \(totalTokens)")
                    }
                }
            }
        }

        // If usage wasn't tracked from chunks and we have header data, track it now
        if !usageTracked && totalTokens > 0 {
            await trackTokenUsage(tokens: totalTokens)
            print("📊 Streaming tokens tracked from headers: \(totalTokens)")
        } else if !usageTracked {
            // Fallback: estimate based on average
            let estimatedTokens = averageTokensPerQuery
            await trackTokenUsage(tokens: estimatedTokens)
            print("⚠️ Streaming tokens estimated: \(estimatedTokens)")
        }
    }

    // MARK: - Streaming Models

    struct StreamChunk: Codable {
        struct Choice: Codable {
            struct Delta: Codable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
        let usage: Usage? // Optional usage data in final chunk

        struct Usage: Codable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
            let prompt_cache_hit_tokens: Int?
            let prompt_cache_miss_tokens: Int?
        }
    }

    // MARK: - Additional Methods (for compatibility with OpenAIService)

    /// Generate text with a simple prompt
    func generateText(
        systemPrompt: String? = nil,
        userPrompt: String,
        maxTokens: Int = 500,
        temperature: Double = 0.7
    ) async throws -> String {
        let fullPrompt = if let systemPrompt = systemPrompt {
            "\(systemPrompt)\n\n\(userPrompt)"
        } else {
            userPrompt
        }

        return try await answerQuestion(
            query: fullPrompt,
            conversationHistory: [],
            operationType: "text_generation"
        )
    }

    /// Answer question with streaming (now with real streaming!)
    func answerQuestionWithStreaming(
        query: String,
        conversationHistory: [Message] = [],
        onChunk: @escaping (String) -> Void
    ) async throws {
        // Convert conversation history to messages
        var messages: [Message] = conversationHistory
        messages.append(Message(role: "user", content: query))

        // Make streaming request
        try await chatStreaming(
            messages: messages,
            operationType: "streaming_chat",
            onChunk: onChunk
        )
    }

    /// Low-level streaming chat method
    private func chatStreaming(
        messages: [Message],
        model: String = "deepseek-chat",
        temperature: Double = 0.6,
        maxTokens: Int = 1024,
        operationType: String? = nil,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let request = Request(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            operation_type: operationType,
            stream: true  // Enable streaming
        )

        try await makeStreamingProxyRequest(request, onChunk: onChunk)

        // Update quota after successful request
        await loadQuotaStatus()
    }

    /// Get semantic similarity scores (stub - returns empty for now)
    func getSemanticSimilarityScores(
        query: String,
        contents: [(String, String)]
    ) async throws -> [String: Double] {
        // Stub implementation - semantic search not yet implemented for DeepSeek
        // Return zero scores for all items
        var scores: [String: Double] = [:]
        for (id, _) in contents {
            scores[id] = 0.0
        }
        return scores
    }

    /// Generate semantic query (stub - returns nil for now)
    func generateSemanticQuery(from userQuery: String) async -> SemanticQuery? {
        // Stub - semantic queries disabled in SearchService anyway
        return nil
    }

    /// Simple chat completion (for SelineChat)
    func simpleChatCompletion(
        systemPrompt: String,
        messages: [[String: String]]
    ) async throws -> String {
        var allMessages: [Message] = [Message(role: "system", content: systemPrompt)]
        for msg in messages {
            if let role = msg["role"], let content = msg["content"] {
                allMessages.append(Message(role: role, content: content))
            }
        }

        let response = try await chat(messages: allMessages, operationType: "simple_chat")
        return response.choices.first?.message.content ?? ""
    }

    /// Simple chat completion with streaming (for SelineChat)
    func simpleChatCompletionStreaming(
        systemPrompt: String,
        messages: [[String: String]],
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        var allMessages: [Message] = [Message(role: "system", content: systemPrompt)]
        for msg in messages {
            if let role = msg["role"], let content = msg["content"] {
                allMessages.append(Message(role: role, content: content))
            }
        }

        var fullResponse = ""
        let chunkHandler: (String) -> Void = { chunk in
            fullResponse += chunk
            onChunk(chunk)
        }

        // Use real streaming
        try await chatStreaming(
            messages: allMessages,
            operationType: "simple_chat",
            onChunk: chunkHandler
        )

        return fullResponse
    }

    /// Extract detailed document content
    func extractDetailedDocumentContent(
        _ fileContent: String,
        withPrompt prompt: String,
        fileName: String = ""
    ) async throws -> String {
        let maxContentLength = 10000
        let truncatedContent = fileContent.count > maxContentLength
            ? String(fileContent.prefix(maxContentLength)) + "\n[... document exceeds 3-page limit, rest truncated ...]"
            : fileContent

        let systemPrompt = """
        You are a document text extraction system. Your task is to extract and preserve the raw text content from documents.

        RULES:
        - Extract the raw text content as-is from the document
        - Preserve the original structure and formatting
        - Do NOT summarize or condense content
        - Do NOT add interpretations or modifications
        - Remove only obvious boilerplate (page headers/footers, form fields, account numbers)
        - Keep all substantive content intact
        """

        let userMessage = """
        \(prompt)

        Document Content:
        \(truncatedContent)
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userMessage,
            maxTokens: 2000,
            temperature: 0.0
        )
    }

    /// Generate monthly summary
    func generateMonthlySummary(summary: MonthlySummary) async throws -> String {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthName = monthFormatter.string(from: summary.monthDate)

        let statsDescription = """
        Month: \(monthName)
        Total Events: \(summary.totalEvents)
        Completed: \(summary.completedEvents) (\(summary.completionPercentage)%)
        Incomplete: \(summary.incompleteEvents)

        Breakdown:
        - Recurring events completed: \(summary.recurringCompletedCount)
        - Recurring events missed: \(summary.recurringMissedCount)
        - One-time events completed: \(summary.oneTimeCompletedCount)

        Top completed events:
        \(summary.topCompletedEvents.isEmpty ? "None" : summary.topCompletedEvents.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """

        let systemPrompt = """
        You are a helpful productivity coach that provides brief, actionable insights about monthly productivity patterns.
        - Analyze the monthly statistics and identify key trends
        - Provide 2-3 sentences: one observation about performance and one encouraging suggestion
        - Be conversational, supportive, and personalized based on the data
        - Celebrate wins and gently encourage improvement where needed
        - Focus on the most significant patterns
        """

        let userPrompt = """
        Monthly productivity summary:

        \(statsDescription)

        Provide a brief 2-3 sentence insight:
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 150,
            temperature: 0.7
        )
    }

    /// Generate recurring events summary
    func generateRecurringEventsSummary(missedEvents: [WeeklyMissedEventSummary.MissedEventDetail]) async throws -> String {
        let eventsDescription = missedEvents.map { event in
            let missRate = event.missRatePercentage
            return "- \(event.eventName) (\(event.frequency.displayName)): Missed \(event.missedCount) out of \(event.expectedCount) times (\(missRate)%)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a helpful productivity coach that provides brief, actionable insights about recurring event patterns.
        - Analyze the missed recurring events and identify the main pattern
        - Provide 2 sentences maximum: one observation and one encouraging suggestion
        - Be conversational and supportive, not judgmental
        - Focus on the most significant trend
        """

        let userPrompt = """
        Last week's missed recurring events:

        \(eventsDescription)

        Provide a brief 2-sentence insight:
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 100,
            temperature: 0.7
        )
    }

    /// Generate note title
    func generateNoteTitle(from content: String) async throws -> String {
        let maxContentLength = 2000
        let truncatedContent = content.count > maxContentLength ? String(content.prefix(maxContentLength)) + "..." : content

        let systemPrompt = """
        Generate a concise, descriptive title (3-6 words) for this note content.
        - Capture the main topic or theme
        - Use title case
        - Be specific but brief
        - No quotes or special formatting
        - Return ONLY the title, nothing else
        """

        let userPrompt = """
        Generate a title for this note:

        \(truncatedContent)

        Title:
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 30,
            temperature: 0.3
        )
    }

    /// Generate follow-up questions based on conversation context
    func generateFollowUpQuestions(prompt: String) async throws -> String {
        return try await generateText(
            systemPrompt: nil,
            userPrompt: prompt,
            maxTokens: 100,
            temperature: 0.7
        )
    }

    /// Clean up note text
    func cleanUpNoteText(_ text: String) async throws -> String {
        let maxContentLength = 48000
        let processedText: String

        if text.count > maxContentLength {
            let truncated = String(text.prefix(maxContentLength))
            processedText = truncated + "\n\n[... text truncated due to length, remaining content not shown ...]"
        } else {
            processedText = text
        }

        let systemPrompt = """
        You are an expert text cleanup and formatting assistant. Your ONLY job is to clean up and professionally format messy text while preserving ALL information.

        CRITICAL CLEANUP TASKS - YOU MUST DO ALL OF THESE:
        ✓ Fix grammar, spelling, and punctuation errors
        ✓ Remove extra whitespace, blank lines, and formatting clutter
        ✓ Remove duplicate content or repeated text
        ✓ Clean up inconsistent spacing and formatting
        ✓ Fix malformed tables and convert to clean pipe-delimited format if needed
        ✓ Remove unwanted characters, emojis, or symbols
        ✓ Use markdown formatting for structure and emphasis

        MARKDOWN FORMATTING REQUIREMENTS:
        ✓ Use # Heading for main sections (H1)
        ✓ Use ## Subheading for subsections (H2)
        ✓ Use **bold** for emphasis on important terms
        ✓ Use *italic* for subtle emphasis
        ✓ Use - item for bullet lists
        ✓ Use 1. item for numbered lists
        ✓ Use | column1 | column2 | for tables (pipe-delimited)
        ✓ Add blank lines between major sections for readability

        DO NOT:
        ✗ Summarize, condense, or omit any information
        ✗ Add new information not in the original
        ✗ Change the meaning or structure of content
        ✗ Add explanations or commentary

        Return the cleaned text with proper markdown formatting, nothing else.
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: processedText,
            maxTokens: 4000,
            temperature: 0.1
        )
    }

    /// Summarize note text
    func summarizeNoteText(_ text: String) async throws -> String {
        let maxContentLength = 48000
        let processedText: String

        if text.count > maxContentLength {
            let truncated = String(text.prefix(maxContentLength))
            processedText = truncated + "\n\n[... text truncated due to length, remaining content not shown ...]"
        } else {
            processedText = text
        }

        let systemPrompt = """
        You are an expert summarization assistant. Your job is to create a concise, well-structured summary of the provided text.

        SUMMARY REQUIREMENTS:
        ✓ Capture the main points and key information
        ✓ Maintain important details like dates, numbers, names, and facts
        ✓ Organize information logically with clear structure
        ✓ Use clear, professional language
        ✓ Keep the summary comprehensive but concise
        ✓ Preserve the tone and context of the original

        MARKDOWN FORMATTING REQUIREMENTS:
        ✓ Use # Summary or # Main Points for main heading (H1)
        ✓ Use ## Section Name for subsections (H2)
        ✓ Use **bold** for emphasis on key terms or important facts
        ✓ Use *italic* for subtle emphasis
        ✓ Use - item for bullet lists of key points
        ✓ Use 1. item for numbered lists when order matters
        ✓ Add blank lines between major sections for readability

        DO NOT:
        ✗ Add information not present in the original text
        ✗ Change facts or numbers
        ✗ Use HTML or other formatting (only markdown)

        Return the summary text with proper markdown formatting for structure, nothing else.
        """

        let userPrompt = """
        Summarize the following text, capturing all key information and main points:

        \(processedText)
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 4000,
            temperature: 0.3
        )
    }

    /// Add more content to note based on user request
    func addMoreToNoteText(_ text: String, userRequest: String) async throws -> String {
        let maxContentLength = 48000
        let processedText: String

        if text.count > maxContentLength {
            let truncated = String(text.prefix(maxContentLength))
            processedText = truncated + "\n\n[... text truncated due to length, remaining content not shown ...]"
        } else {
            processedText = text
        }

        let systemPrompt = """
        You are a helpful writing assistant. Your job is to expand and enhance the provided text based on the user's specific request.

        TASKS:
        ✓ Add the requested information to the existing text
        ✓ Maintain the original content and structure
        ✓ Preserve existing markdown formatting in the original text
        ✓ Integrate new content naturally and coherently
        ✓ Use clear, professional language
        ✓ Only add text-based content (no images)
        ✓ Ensure the new content flows well with the existing text

        MARKDOWN FORMATTING REQUIREMENTS:
        ✓ Preserve any existing markdown formatting in the original text
        ✓ Use # Heading for new main sections (H1)
        ✓ Use ## Subheading for new subsections (H2)
        ✓ Use **bold** for emphasis on important terms
        ✓ Use *italic* for subtle emphasis
        ✓ Use - item for bullet lists
        ✓ Use 1. item for numbered lists
        ✓ Add blank lines between major sections for readability

        IMPORTANT CONSTRAINTS:
        ✗ Do NOT mention images, photos, or visual content
        ✗ Do NOT add placeholders for images
        ✗ Only add text-based information
        ✗ Preserve all original content and formatting

        Return the complete text (original + additions) with proper markdown formatting, nothing else.
        """

        let userPrompt = """
        Current text:
        \(processedText)

        User request: \(userRequest)

        Add the requested information to the text above. Only add text-based content, no images or visual elements.
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 4000,
            temperature: 0.5
        )
    }

    /// Analyze receipt image (uses OpenAI vision - DeepSeek doesn't support vision yet)
    func analyzeReceiptImage(_ image: UIImage) async throws -> (title: String, content: String) {
        // DeepSeek v3 doesn't support vision, so delegate to OpenAI for this specific task
        print("📸 Using OpenAI for image analysis (DeepSeek doesn't support vision)")
        return try await OpenAIService.shared.analyzeReceiptImage(image)
    }

    /// Categorize receipt
    func categorizeReceipt(title: String) async throws -> String {
        let systemPrompt = """
        You are a helpful assistant that categorizes receipts and invoices.
        Categorize the receipt into ONE of these 13 categories only:
        - Food & Dining
        - Transportation
        - Healthcare
        - Entertainment
        - Shopping
        - Software & Subscriptions
        - Accommodation & Travel
        - Utilities & Internet
        - Professional Services
        - Auto & Vehicle
        - Home & Maintenance
        - Education
        - Other

        Return ONLY the category name, nothing else.
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: "Categorize this receipt: \(title)",
            maxTokens: 50,
            temperature: 0.0
        )
    }
}

// MARK: - Data Models

extension DeepSeekService {
    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let max_tokens: Int?
        let operation_type: String?
        let stream: Bool?
    }

    struct Response: Codable {
        let id: String
        let choices: [Choice]
        let usage: Usage

        struct Choice: Codable {
            let message: Message
            let finish_reason: String?
        }

        struct Usage: Codable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
            let prompt_cache_hit_tokens: Int?
            let prompt_cache_miss_tokens: Int?
        }
    }

    struct QuotaStatus: Codable {
        let user_id: String
        let subscription_tier: String
        let monthly_quota_tokens: Int?  // Optional for backward compatibility
        let quota_used_this_month: Int?  // Optional for backward compatibility
        let quota_tokens: Int?  // Daily quota (from view)
        let quota_used: Int?  // Daily usage (from view)
        let quota_remaining: Int
        let quota_used_percent: Double
        let quota_reset_at: String?  // Reset time
    }
}

struct ErrorResponse: Codable {
    let error: String
}

enum DeepSeekError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case quotaExceeded(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid proxy URL"
        case .notAuthenticated:
            return "Not authenticated. Please log in."
        case .invalidResponse:
            return "Invalid response from server"
        case .quotaExceeded(let message):
            // Message from server already contains reset time, use it directly
            if message.contains("reset at") {
                return message  // Use the message with reset time from server
            }
            return "Daily quota exceeded. Your quota will reset at midnight. You've used your daily limit of 2M tokens."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
