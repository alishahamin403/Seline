import Foundation
import UIKit

/**
 * GeminiService - Google Gemini LLM Service
 *
 * Primary LLM service for Seline with these capabilities:
 * - Excellent at web search and general knowledge
 * - Strong reasoning capabilities
 * - Good at historical data retrieval
 * - Fast and cost-effective with Gemini 2.5 Flash
 */
@MainActor
class GeminiService: ObservableObject {
    static let shared = GeminiService()

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
    private let dailyTokenLimit: Int = 1_500_000 // 1.5M tokens per day (~$0.30/day at 70/30 input/output ratio)

    // Average tokens per query (updated dynamically)
    private var averageTokensPerQuery: Int = 15_000 // Conservative estimate
    
    // API key
    private let apiKey: String

    private init() {
        self.apiKey = Config.geminiAPIKey
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
        model: String = "gemini-2.5-flash-lite",  // Flash-Lite: 33% cheaper than Flash ($0.10/$0.40 per 1M tokens vs $0.15/$0.60)
        temperature: Double = 0.6,
        maxTokens: Int = 1024,  // Reduced from 2048 for cost optimization (most responses don't need 2K tokens)
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

        let response = try await makeDirectRequest(request)

        // Update quota after successful request
        await loadQuotaStatus()

        return response
    }

    /// Summarize email (drop-in replacement for OpenAI method)
    func summarizeEmail(subject: String, body: String) async throws -> String {
        let bodyPreview = String(body.prefix(1000))
        print("📧 ===========================================")
        print("📧 Summarizing email - Subject: \(subject)")
        print("📧 Body preview (first 1000 chars):")
        print(bodyPreview)
        print("📧 ===========================================")

        let prompt = """
        Read this email and extract what actually matters to the reader. Be their smart assistant.

        EMAIL CONTENT:
        \(body.prefix(8000))

        YOUR TASK: Create 2-4 concise bullet points (MAX 4) that answer "What do I need to know?" and "What should I do?"

        CRITICAL RULES:
        1. Write like a helpful friend, NOT a robot. Never say "this email", "the email states", "the sender"
        2. NEVER repeat the subject line or sender name - the user already sees those
        3. Focus on: amounts, dates, deadlines, action items, important details, links, tracking numbers
        4. If there's something to DO, start with an action verb (Review, Confirm, Pay, Check, Track, etc.)
        5. Include specific numbers: $amounts, dates, percentages, quantities, order numbers, tracking numbers
        6. 🚨 CRITICAL - LINKS FORMATTING:
           - ALWAYS convert URLs to markdown links: [descriptive text](URL)
           - NEVER show raw URLs like https://example.com/long-url
           - Use descriptive link text like [Select your bank], [Learn more], [Track package]
           - Example: "Select your bank: [RBC Royal Bank](https://etransfer.interac.ca/...)" NOT "using this link: (https://etransfer.interac.ca/...)"
        7. Skip fluff - no "Thank you for your business" type content
        8. If it's a receipt/transaction: state the key numbers (amount, what it's for, order number)
        9. If it's a request: state what they're asking and any deadline
        10. If it's informational: state the key takeaway with all relevant details
        11. Keep it concise - combine related info into single bullets when possible

        EXAMPLES OF GOOD SUMMARIES:

        For a money transfer:
        • You received $500.00 CAD - select your bank to claim: [RBC Royal Bank](url) or [Other institution](url)
        • Funds expire March 9, 2026
        • Reference number: CAEvQgGX

        For an order confirmation:
        • Your order (#702-7867393-7724246) arrives tomorrow - [Track package](https://tracking-url.com)
        • Charged $81.34 CAD for 2 items: cleanser ($20.99) and DIY kit ($50.99)

        For a deposit notification:
        • $500 deposited to your TFSA account
        • New balance: $12,450.32 (as of Jan 24, 2026)

        For a bill/invoice:
        • $89.99 due by Jan 25th - [Pay now](https://account.example.com/pay)
        • Invoice #12345

        Return ONLY the bullet points using • symbol. NEVER show raw URLs - always use markdown [text](url) format. Keep it to 4 points maximum.
        """

        let messages = [Message(role: "user", content: prompt)]
        let response = try await chat(
            messages: messages,
            temperature: 0.0,
            maxTokens: 400,
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
                .from("gemini_quota_status")
                .select()
                .execute()
                .value

            if let status = response.first {
                self.quotaUsed = status.quota_used ?? status.quota_used_this_month ?? 0
                self.quotaLimit = status.quota_tokens ?? status.monthly_quota_tokens ?? 1000000
            }
        } catch {
            // If table doesn't exist, use defaults
            print("Note: Gemini quota table not found, using defaults")
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
            return key
        }
        return "\(key)_\(userId)"
    }

    /// Load daily usage from UserDefaults
    func loadDailyUsage() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let tokensKey = getUserKey("gemini_dailyTokensUsed")
        let queryCountKey = getUserKey("gemini_dailyQueryCount")
        let dateKey = getUserKey("gemini_lastResetDate")

        if let savedDate = UserDefaults.standard.object(forKey: dateKey) as? Date {
            lastResetDate = savedDate
        }

        if !calendar.isDate(lastResetDate, inSameDayAs: today) {
            dailyTokensUsed = 0
            dailyQueryCount = 0
            lastResetDate = today
            saveDailyUsage()
        } else {
            dailyTokensUsed = UserDefaults.standard.integer(forKey: tokensKey)
            dailyQueryCount = UserDefaults.standard.integer(forKey: queryCountKey)
        }
        
        quotaPercentage = (Double(dailyTokensUsed) / Double(dailyTokenLimit)) * 100
        print("📊 Gemini Daily Usage Loaded: \(dailyTokensUsed) tokens, \(dailyQueryCount) queries, \(String(format: "%.1f", quotaPercentage))% used")
    }

    /// Save daily usage to UserDefaults
    private func saveDailyUsage() {
        let tokensKey = getUserKey("gemini_dailyTokensUsed")
        let queryCountKey = getUserKey("gemini_dailyQueryCount")
        let dateKey = getUserKey("gemini_lastResetDate")

        UserDefaults.standard.set(dailyTokensUsed, forKey: tokensKey)
        UserDefaults.standard.set(dailyQueryCount, forKey: queryCountKey)
        UserDefaults.standard.set(lastResetDate, forKey: dateKey)
        print("💾 Gemini Daily Usage Saved: \(dailyTokensUsed) tokens, \(dailyQueryCount) queries")
    }

    /// Track tokens used in a request
    func trackTokenUsage(tokens: Int) async {
        await loadDailyUsage()
        dailyTokensUsed += tokens
        dailyQueryCount += 1
        averageTokensPerQuery = dailyTokensUsed / max(dailyQueryCount, 1)
        quotaPercentage = (Double(dailyTokensUsed) / Double(dailyTokenLimit)) * 100
        saveDailyUsage()
    }

    /// Get remaining tokens for today
    var dailyTokensRemaining: Int {
        max(0, dailyTokenLimit - dailyTokensUsed)
    }
    
    /// Get daily usage percentage (0-100) for real-time display
    var dailyUsagePercentage: Double {
        min(100.0, (Double(dailyTokensUsed) / Double(dailyTokenLimit)) * 100)
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

    private func makeDirectRequest(_ request: Request) async throws -> Response {
        // Gemini API endpoint - using v1beta for Google Search grounding support
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        // Convert messages to Gemini format
        let geminiContents = convertMessagesToGeminiFormat(request.messages)

        // Build request body with Google Search grounding enabled
        var requestBody: [String: Any] = [
            "contents": geminiContents,
            "generationConfig": [
                "temperature": request.temperature ?? 0.6,
                "maxOutputTokens": request.max_tokens ?? 2048
            ],
            // Enable Google Search grounding for web queries
            "tools": [
                [
                    "google_search": [:]
                ]
            ]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 90

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.apiError(message)
            }
            throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse Gemini response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse JSON response")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Raw response: \(responseString.prefix(500))")
            }
            throw GeminiError.invalidResponse
        }

        // Check for safety blocking or other issues
        if let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let finishReason = firstCandidate["finishReason"] as? String {
            if finishReason == "SAFETY" {
                print("⚠️ Response blocked by safety filters")
                throw GeminiError.apiError("Response blocked by Gemini safety filters")
            }
            if finishReason != "STOP" && finishReason != "MAX_TOKENS" {
                print("⚠️ Unexpected finish reason: \(finishReason)")
            }
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            print("❌ No candidates in response")
            throw GeminiError.invalidResponse
        }

        guard let content = firstCandidate["content"] as? [String: Any] else {
            print("❌ No content in candidate")
            print("📄 Candidate: \(firstCandidate)")
            throw GeminiError.invalidResponse
        }

        print("📄 Content keys: \(content.keys)")

        guard let parts = content["parts"] as? [[String: Any]] else {
            print("❌ No parts in content or wrong format")
            print("📄 Content: \(content)")
            throw GeminiError.invalidResponse
        }

        guard let firstPart = parts.first else {
            print("❌ Parts array is empty")
            throw GeminiError.invalidResponse
        }

        print("📄 First part keys: \(firstPart.keys)")

        guard let text = firstPart["text"] as? String else {
            print("❌ No text in part or wrong format")
            print("📄 First part: \(firstPart)")
            throw GeminiError.invalidResponse
        }

        // Extract usage info if available
        var promptTokens = 0
        var completionTokens = 0
        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            promptTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
            completionTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
        } else {
            // Estimate tokens (rough: 1 token ≈ 4 characters)
            let totalChars = request.messages.map { $0.content }.joined().count
            promptTokens = totalChars / 4
            completionTokens = text.count / 4
        }

        let totalTokens = promptTokens + completionTokens
        await trackTokenUsage(tokens: totalTokens)

        // Convert to our Response format
        let geminiResponse = Response(
            id: UUID().uuidString,
            choices: [Response.Choice(
                message: Message(role: "assistant", content: text),
                finish_reason: firstCandidate["finishReason"] as? String
            )],
            usage: Response.Usage(
                prompt_tokens: promptTokens,
                completion_tokens: completionTokens,
                total_tokens: totalTokens,
                prompt_cache_hit_tokens: nil,
                prompt_cache_miss_tokens: nil
            )
        )

        print("✅ Gemini: \(totalTokens) tokens used")

        return geminiResponse
    }

    /// Convert our Message format to Gemini's format
    private func convertMessagesToGeminiFormat(_ messages: [Message]) -> [[String: Any]] {
        return messages.map { message in
            var role = "user"
            if message.role == "assistant" {
                role = "model"
            } else if message.role == "system" {
                // Gemini doesn't have system role, prepend to first user message
                role = "user"
            }
            
            return [
                "role": role,
                "parts": [["text": message.content]]
            ]
        }
    }

    // MARK: - Additional Methods

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

    /// Answer question with streaming using Gemini's native SSE streaming
    func answerQuestionWithStreaming(
        query: String,
        conversationHistory: [Message] = [],
        onChunk: @escaping (String) -> Void
    ) async throws {
        var messages: [Message] = conversationHistory
        messages.append(Message(role: "user", content: query))

        // Use streamGenerateContent for real server-side streaming (tokens arrive as generated)
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:streamGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        let geminiContents = convertMessagesToGeminiFormat(messages)

        let requestBody: [String: Any] = [
            "contents": geminiContents,
            "generationConfig": [
                "temperature": 0.6,
                "maxOutputTokens": 1024
            ],
            "tools": [
                ["google_search": [:]]
            ]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 90
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            if let errorResponse = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let error = errorResponse["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.apiError(message)
            }
            throw GeminiError.apiError("HTTP \(httpResponse.statusCode)")
        }

        var fullText = ""
        var promptTokens = 0
        var completionTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else { continue }

            fullText += text
            onChunk(text)

            // Extract usage metadata (typically in final chunk)
            if let usageMetadata = json["usageMetadata"] as? [String: Any] {
                promptTokens = usageMetadata["promptTokenCount"] as? Int ?? promptTokens
                completionTokens = usageMetadata["candidatesTokenCount"] as? Int ?? completionTokens
            }
        }

        // Track token usage
        let totalTokens = promptTokens + completionTokens > 0
            ? promptTokens + completionTokens
            : fullText.count / 4  // Fallback estimate if no usage metadata
        await trackTokenUsage(tokens: totalTokens)
        print("✅ Gemini (streaming): \(totalTokens) tokens used, \(fullText.count) chars")
    }

    /// Get semantic similarity scores (stub)
    func getSemanticSimilarityScores(
        query: String,
        contents: [(String, String)]
    ) async throws -> [String: Double] {
        var scores: [String: Double] = [:]
        for (id, _) in contents {
            scores[id] = 0.0
        }
        return scores
    }

    /// Generate semantic query (stub)
    func generateSemanticQuery(from userQuery: String) async -> SemanticQuery? {
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

        try await answerQuestionWithStreaming(
            query: allMessages.last?.content ?? "",
            conversationHistory: Array(allMessages.dropLast()),
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
        ✓ Remove unwanted characters, emojis, or symbols
        ✓ Use markdown formatting for structure and emphasis

        MARKDOWN FORMATTING REQUIREMENTS:
        ✓ Use # Heading for main sections (H1)
        ✓ Use ## Subheading for subsections (H2)
        ✓ Use **bold** for emphasis on important terms
        ✓ Use *italic* for subtle emphasis
        ✓ Use - item for bullet lists
        ✓ Use 1. item for numbered lists
        ✓ Add blank lines between major sections for readability

        CRITICAL - TABLE CONVERSION:
        If you encounter pipe-delimited tables (| column | column |):
        ✗ Do NOT keep the pipe-delimited table format
        ✓ Convert each table row into a structured section:
          - Use ## for each row header (first column becomes the heading)
          - Use bullet points with **bold labels** for remaining columns

        DO NOT:
        ✗ Summarize, condense, or omit any information
        ✗ Add new information not in the original
        ✗ Change the meaning or structure of content
        ✗ Add explanations or commentary
        ✗ Keep pipe-delimited table syntax

        Return the cleaned text with proper markdown formatting, nothing else.
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: processedText,
            maxTokens: 2000,  // Reduced from 4000 for cost optimization
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
        ✗ Use pipe-delimited markdown table syntax (| column | column |)

        Return the summary text with proper markdown formatting for structure, nothing else.
        """

        let userPrompt = """
        Summarize the following text, capturing all key information and main points:

        \(processedText)
        """

        return try await generateText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 1500,  // Reduced from 4000 - summaries should be concise
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

        CRITICAL - TABLE FORMATTING:
        When the user requests a TABLE, SCHEDULE, TRACKER, or any TABULAR DATA:
        ✗ Do NOT use pipe-delimited markdown table syntax (| column | column |)
        ✗ Do NOT use horizontal lines (|---|---|)
        ✓ Instead, format each row as a structured section with clear labels
        ✓ Use ## for each row header (e.g., ## Monday, ## Week 1)
        ✓ Use bullet points with **bold labels** for columns

        IMPORTANT CONSTRAINTS:
        ✗ Do NOT mention images, photos, or visual content
        ✗ Do NOT add placeholders for images
        ✗ Do NOT use markdown table syntax (pipes and dashes)
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
            maxTokens: 2500,  // Reduced from 4000 for cost optimization
            temperature: 0.5
        )
    }

    /// Analyze receipt image (delegates to OpenAI for vision)
    func analyzeReceiptImage(_ image: UIImage) async throws -> (title: String, content: String) {
        print("📸 Using OpenAI for image analysis (Gemini vision not yet implemented)")
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

extension GeminiService {
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
        let monthly_quota_tokens: Int?
        let quota_used_this_month: Int?
        let quota_tokens: Int?
        let quota_used: Int?
        let quota_remaining: Int
        let quota_used_percent: Double
        let quota_reset_at: String?
    }
}

enum GeminiError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case quotaExceeded(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Gemini API URL"
        case .notAuthenticated:
            return "Not authenticated. Please log in."
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .quotaExceeded(let message):
            return "Quota exceeded: \(message)"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        }
    }
}
