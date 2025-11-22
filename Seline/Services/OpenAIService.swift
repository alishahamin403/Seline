import Foundation
import UIKit
import CoreLocation

// MARK: - Expense Query Models

/// Represents a parsed expense query with intent and filters
struct ExpenseQuery {
    let type: QueryType
    let keywords: [String]  // e.g., ["pizza"], ["coffee"], ["costco"]
    let dateRange: (start: Date, end: Date)
    let hasFilters: Bool  // Whether query asks for specific product/merchant

    enum QueryType {
        case countByProduct      // "how many times did I buy pizza?"
        case amountByProduct     // "how much did I spend on coffee?"
        case listByProduct       // "show me all pizza purchases"
        case comparison          // "did I spend more on pizza or coffee?"
        case general             // "how much did I spend this month?"
        case unsure              // Query too ambiguous
    }
}

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    // API key loaded from Config.swift (not committed to git)
    private let apiKey = Config.openAIAPIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    // Track the last SearchAnswer for UI to display related items after streaming
    @Published var lastSearchAnswer: SearchAnswer?

    // Rate limiting properties
    private let requestQueue = DispatchQueue(label: "openai-requests", qos: .utility)
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 2.0 // 2 seconds between requests

    // Cache properties for response optimization
    // Embedding cache: store embeddings to avoid repeated API calls
    private var embeddingCache: [String: [Float]] = [:]
    private let embeddingModel = "text-embedding-3-small" // Faster, cheaper model
    private let embeddingsBaseURL = "https://api.openai.com/v1/embeddings"

    private init() {}

    enum SummaryError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case apiError(String)
        case rateLimitExceeded(retryAfter: TimeInterval)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from API"
            case .decodingError:
                return "Failed to decode API response"
            case .apiError(let message):
                return "API Error: \(message)"
            case .rateLimitExceeded(let retryAfter):
                return "Rate limit exceeded. Please wait \(Int(retryAfter)) seconds before trying again."
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }

    /// Summarizes an email into 4 key facts for quick understanding.
    /// This method properly handles HTML email bodies, extracting text while preserving
    /// important structure like tables, lists, and formatting. It intelligently processes
    /// receipts, order confirmations, and formatted emails.
    ///
    /// - Parameters:
    ///   - subject: The email subject line
    ///   - body: The full email body (can be plain text or HTML)
    /// - Returns: A string containing 4 key facts separated by periods
    func summarizeEmail(subject: String, body: String) async throws -> String {
        // Rate limiting - ensure minimum interval between requests
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Extract and clean the main body content
        // This handles HTML emails by extracting meaningful text while preserving structure
        let cleanedBody = extractMainBodyContent(from: body)

        // Check if cleaned body is too short (might indicate over-filtering)
        let isContentTooShort = cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines).count < 50

        // More aggressive truncation to reduce token usage (roughly 4 chars = 1 token)
        let maxBodyLength = 8000 // Reduced to ~2k tokens for faster processing
        let truncatedBody = cleanedBody.count > maxBodyLength ? String(cleanedBody.prefix(maxBodyLength)) + "..." : cleanedBody

        // Create the prompt for GPT
        let emailContent = """
        Subject: \(subject)

        Body: \(truncatedBody)
        """

        let systemPrompt = """
        You are summarizing emails for a busy user who doesn't have time to read the full email. Extract the 4 most important and actionable details from the email content.

        CRITICAL: Focus on the core message in the email. Extract what matters to the user.

        Key rules:
        - Be specific with WHO, WHAT, WHEN, WHERE, and HOW MUCH (include names, dates, amounts, locations)
        - Each fact should be 8-12 words with concrete details
        - If people are mentioned, include their names
        - If there are numbers (amounts, totals), include them
        - If there are dates or deadlines, include them
        - Focus on what the user needs to know or do
        - If the email asks the user to do something (like provide feedback, complete a survey, click a link), mention that

        Common email types:
        - Receipts/Orders: Include total amount, merchant/store, items purchased, order/tracking number
        - Feedback requests: Mention WHO is asking for feedback and WHAT about
        - Notifications: Include WHO sent them and WHAT they're about
        - Meeting invites: Include WHO, WHEN, WHERE, and purpose
        - Action items: Include WHAT needs to be done, by WHEN, and by WHO

        If the email body is very short or seems filtered, use the SUBJECT line to help provide context.

        IMPORTANT: If there's genuinely no substantive content to summarize (empty email, just a signature, only unsubscribe links), return an empty string.
        """

        let userPrompt = """
        Email: \(emailContent)

        4 key facts:
        """

        // Create the request body - using gpt-4o-mini for cost-effective summaries
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // Fast, cost-effective model for email summarization
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "max_tokens": 200, // Slightly increased for more detailed, precise summaries
            "temperature": 0.1 // Very low temperature for consistent, focused output
        ]

        // Create the HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw SummaryError.networkError(error)
        }

        // Make the API call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {

                        // Check for rate limit specifically
                        if httpResponse.statusCode == 429 || message.contains("Rate limit") {
                            // Extract retry time if available
                            let retryAfter = extractRetryAfterFromMessage(message)
                            throw SummaryError.rateLimitExceeded(retryAfter: retryAfter)
                        }

                        throw SummaryError.apiError(message)
                    } else {
                        throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            // Parse the response
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummaryError.decodingError
            }

            // Clean up the response and ensure it's properly formatted
            let cleanedSummary = cleanAndFormatSummary(content)

            // FALLBACK: If content was too short and we got an empty summary, try with raw body
            if cleanedSummary.isEmpty && isContentTooShort && !body.isEmpty {
                print("⚠️ Summary empty with cleaned content, retrying with minimal processing for: '\(subject)'")
                return try await summarizeWithMinimalProcessing(subject: subject, rawBody: body, url: url)
            }

            return cleanedSummary

        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.networkError(error)
        }
    }

    /// Fallback summarization with minimal content processing
    private func summarizeWithMinimalProcessing(subject: String, rawBody: String, url: URL) async throws -> String {
        // Only do basic HTML stripping, no aggressive filtering
        var processedBody = rawBody

        if rawBody.contains("<") {
            // Basic HTML to text conversion
            processedBody = stripHTMLAndExtractText(rawBody)
        }

        // Truncate if needed
        let maxBodyLength = 8000
        let truncatedBody = processedBody.count > maxBodyLength ? String(processedBody.prefix(maxBodyLength)) + "..." : processedBody

        let emailContent = """
        Subject: \(subject)

        Body: \(truncatedBody)
        """

        let systemPrompt = """
        Summarize this email into 4 key facts (8-12 words each). Focus on the main message and what the user needs to know.
        If there's truly nothing substantive to summarize, return an empty string.
        """

        let userPrompt = """
        Email: \(emailContent)

        4 key facts:
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 200,
            "temperature": 0.1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SummaryError.apiError("Fallback summary failed")
        }

        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SummaryError.decodingError
        }

        return cleanAndFormatSummary(content)
    }

    private func cleanAndFormatSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var bulletPoints: [String] = []

        for line in lines {
            var cleanLine = line

            // Remove common bullet point prefixes
            if cleanLine.hasPrefix("• ") || cleanLine.hasPrefix("- ") || cleanLine.hasPrefix("* ") {
                cleanLine = String(cleanLine.dropFirst(2))
            } else if cleanLine.hasPrefix("•") || cleanLine.hasPrefix("-") || cleanLine.hasPrefix("*") {
                cleanLine = String(cleanLine.dropFirst(1))
            }

            // Remove numbered prefixes (1., 2., etc.)
            if let range = cleanLine.range(of: "^\\d+\\.\\s*", options: .regularExpression) {
                cleanLine = String(cleanLine[range.upperBound...])
            }

            cleanLine = cleanLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanLine.isEmpty {
                bulletPoints.append(cleanLine)
            }
        }

        // Return the bullet points we have (up to 4)
        let finalBullets = Array(bulletPoints.prefix(4))

        // If we have no bullet points, the email likely has no meaningful content
        if finalBullets.isEmpty {
            return ""
        }

        return finalBullets.joined(separator: ". ")
    }

    /// Extracts detailed content from a document file with comprehensive detail preservation.
    /// This method is designed for extracting full content from PDFs, documents, etc.
    /// Unlike summarizeEmail which creates a 4-point summary, this extracts complete detailed text.
    ///
    /// - Parameters:
    ///   - fileContent: The text content extracted from the file
    ///   - prompt: The detailed extraction prompt specifying what to extract
    ///   - fileName: The original file name for context
    /// - Returns: A comprehensive detailed extraction of the document content
    func extractDetailedDocumentContent(_ fileContent: String, withPrompt prompt: String, fileName: String = "") async throws -> String {
        // Rate limiting - ensure minimum interval between requests
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // For extraction, limit to approximately 3 pages of content
        // Max 10000 characters = ~2500 tokens (approximately 3-4 pages of text)
        let maxContentLength = 10000
        let truncatedContent = fileContent.count > maxContentLength ? String(fileContent.prefix(maxContentLength)) + "\n[... document exceeds 3-page limit, rest truncated ...]" : fileContent

        // Build the extraction request with a simple raw text extraction prompt
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

        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",  // Cheaper model for simple text extraction
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 4000,  // Standard token limit for 3-page extraction
            "temperature": 0.3   // Lower temperature for consistent extraction
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Increase timeout for large file extractions (default is 60 seconds)
        // Very large PDFs with many transactions can take 5+ minutes to process
        request.timeoutInterval = 300 // 5 minutes for detailed extraction of large files

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.networkError(NSError(domain: "HTTPError", code: 0))
        }

        if httpResponse.statusCode != 200 {
            if let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {

                if httpResponse.statusCode == 429 || message.contains("Rate limit") {
                    let retryAfter = extractRetryAfterFromMessage(message)
                    throw SummaryError.rateLimitExceeded(retryAfter: retryAfter)
                }

                throw SummaryError.apiError(message)
            } else {
                throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
            }
        }

        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SummaryError.decodingError
        }

        // Return the extracted content as-is (no aggressive formatting)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rate Limiting Helpers

    private func enforceRateLimit() async {
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)

        if timeSinceLastRequest < minimumRequestInterval {
            let waitTime = minimumRequestInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        lastRequestTime = Date()
    }

    private func extractRetryAfterFromMessage(_ message: String) -> TimeInterval {
        // Try to extract retry time from error message like "Please try again in 8.916s"
        let pattern = "try again in ([0-9.]+)s"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let range = Range(match.range(at: 1), in: message) {
            if let seconds = Double(String(message[range])) {
                return seconds
            }
        }
        return 30.0 // Default fallback
    }

    // MARK: - Content Processing

    private func extractMainBodyContent(from body: String) -> String {
        var cleanedContent = body

        // For HTML emails, extract meaningful content while preserving structure
        if cleanedContent.contains("<") {
            cleanedContent = extractHTMLContent(cleanedContent)
        }

        // Detect email type for appropriate filtering
        let isReceipt = detectReceipt(cleanedContent)
        let isFeedbackOrSurvey = detectFeedbackOrSurvey(cleanedContent)

        // CRITICAL FIX: Apply filtering based on email type
        // Feedback/survey emails: very minimal filtering (preserve core message)
        // Receipts: moderate filtering (preserve transaction details)
        // Regular emails: standard filtering

        if isFeedbackOrSurvey {
            // For feedback/survey emails, only remove the most basic noise
            cleanedContent = removeMinimalBoilerplate(cleanedContent)
            // Keep social media links and buttons as they might be part of the message
        } else {
            // Remove header/footer sections for non-feedback emails
            cleanedContent = removeHeaderFooterSections(cleanedContent)

            if isReceipt {
                // For receipts, be conservative with content removal
                cleanedContent = removeMinimalBoilerplate(cleanedContent)
            } else {
                // For regular emails, apply standard filtering
                cleanedContent = removeEmailSignatures(cleanedContent)
                cleanedContent = removeEmailThreading(cleanedContent)
                cleanedContent = removeEmailBoilerplate(cleanedContent)
            }
        }

        // Remove URLs and links (but preserve context) - safe for all emails
        cleanedContent = removeURLs(cleanedContent)

        // Remove excessive whitespace and clean up formatting
        cleanedContent = cleanUpWhitespace(cleanedContent)

        return cleanedContent
    }

    private func detectFeedbackOrSurvey(_ content: String) -> Bool {
        let feedbackIndicators = [
            "feedback",
            "survey",
            "questionnaire",
            "rate your experience",
            "tell us what you think",
            "share your thoughts",
            "customer satisfaction",
            "how did we do",
            "review your experience",
            "take a survey",
            "complete our survey",
            "brief survey"
        ]

        let lowercasedContent = content.lowercased()
        var matchCount = 0

        for indicator in feedbackIndicators {
            if lowercasedContent.contains(indicator) {
                matchCount += 1
            }
        }

        // If we find 2 or more feedback indicators, it's likely a feedback/survey email
        return matchCount >= 2
    }

    private func detectReceipt(_ content: String) -> Bool {
        let receiptIndicators = [
            "order confirmation",
            "order number",
            "order total",
            "receipt",
            "invoice",
            "purchase",
            "transaction",
            "payment",
            "subtotal",
            "shipping",
            "tax",
            "items ordered",
            "quantity",
            "tracking number"
        ]

        let lowercasedContent = content.lowercased()
        var matchCount = 0

        for indicator in receiptIndicators {
            if lowercasedContent.contains(indicator) {
                matchCount += 1
            }
        }

        // If we find 3 or more receipt indicators, it's likely a receipt
        return matchCount >= 3
    }

    private func removeMinimalBoilerplate(_ content: String) -> String {
        var cleaned = content

        // Only remove the most basic boilerplate for receipts
        let minimalBoilerplatePatterns = [
            "(?i)please consider the environment.*",
            "(?i)this email and any attachments.*",
            "(?i)if you have received this.*"
        ]

        for pattern in minimalBoilerplatePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func removeHeaderFooterSections(_ content: String) -> String {
        var cleaned = content

        // CRITICAL: This function removes common header/footer patterns that contain
        // promotional content, social media links, and template boilerplate
        // This must run BEFORE other content extraction to avoid noise in AI summaries

        // Remove social media follow sections
        let headerFooterPatterns = [
            // Social media sections (often at top/bottom of emails)
            "(?i)(follow us|connect with us|find us on).*?(facebook|twitter|instagram|linkedin|youtube).*?(\n\n|\n\n\n|$)",

            // View in browser / download app sections
            "(?i)(view.*browser|trouble viewing|view online|download.*app|get.*app).*?(\n\n|\n\n\n|$)",

            // Unsubscribe and preference sections (usually at bottom)
            "(?i)(unsubscribe|manage.*preferences|email preferences|update.*preferences|opt out).*?(\n\n|\n\n\n|$)",

            // Copyright and legal sections
            "(?i)(©|copyright|\\(c\\)|all rights reserved).*?(\n\n|\n\n\n|$)",

            // Physical address sections (common in footers)
            "(?i)^.*?(\\d{1,5}\\s+[\\w\\s]+,\\s*[A-Z]{2}\\s+\\d{5}).*?(\n\n|\n\n\n|$)",

            // Terms and privacy policy sections
            "(?i)(terms.*service|privacy policy|terms.*conditions|terms of use).*?(\n\n|\n\n\n|$)",

            // Promotional taglines and marketing messages
            "(?i)(shop now|learn more|discover|explore|browse|visit.*website|check it out)\\s*(\n|$)",

            // Email header metadata (From:, To:, etc. - usually forwarded content)
            "(?i)^(from|to|sent|date|subject):\\s+.*?(\n|$)",

            // Corporate disclaimers
            "(?i)this email is intended only for.*?(\n\n|\n\n\n|$)",
            "(?i)confidential.*communication.*?(\n\n|\n\n\n|$)",

            // App download badges/sections
            "(?i)(available on|download on)\\s+(app store|google play|play store).*?(\n\n|\n\n\n|$)",

            // Customer service footers
            "(?i)(questions|need help|contact us|customer service|support)\\?.*?(\n\n|\n\n\n|$)"
        ]

        for pattern in headerFooterPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        // Remove button-like text that's common in email templates
        // These are usually calls to action that don't contain useful info
        let buttonTextPatterns = [
            "(?i)view order",
            "(?i)track package",
            "(?i)view details",
            "(?i)click here",
            "(?i)learn more",
            "(?i)shop now",
            "(?i)get started",
            "(?i)sign in",
            "(?i)verify email",
            "(?i)confirm.*account",
            "(?i)update settings",
            "(?i)manage preferences"
        ]

        for pattern in buttonTextPatterns {
            // Only remove if it's on its own line (likely a button, not part of text)
            cleaned = cleaned.replacingOccurrences(
                of: "\n\\s*\(pattern)\\s*\n",
                with: "\n",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func extractHTMLContent(_ html: String) -> String {
        var content = html

        // CRITICAL: First try to extract main content sections before processing
        // Many emails have <main>, <article>, or role="main" for the actual content
        content = extractMainContentSection(content)

        // Remove problematic elements that don't contain useful content
        content = removeHTMLNoise(content)

        // Extract meaningful text from HTML while preserving important structure
        content = extractMeaningfulHTMLText(content)

        // Clean up the extracted content
        content = cleanUpExtractedText(content)

        return content
    }

    private func extractMainContentSection(_ html: String) -> String {
        // Try to find the main content section using common patterns
        // This helps skip headers, navigation, and footers in HTML emails

        // Pattern 1: Look for <main> tag
        if let mainRange = html.range(of: "<main[^>]*>([\\s\\S]*?)</main>", options: .regularExpression) {
            return String(html[mainRange])
        }

        // Pattern 2: Look for role="main" attribute
        if let roleMainRange = html.range(of: "<[^>]*role=\"main\"[^>]*>([\\s\\S]*?)</[^>]+>", options: .regularExpression) {
            return String(html[roleMainRange])
        }

        // Pattern 3: Look for <article> tag (common in transactional emails)
        if let articleRange = html.range(of: "<article[^>]*>([\\s\\S]*?)</article>", options: .regularExpression) {
            return String(html[articleRange])
        }

        // Pattern 4: Look for a div with common content class names
        let contentClassPatterns = [
            "(?i)<div[^>]*class=\"[^\"]*content[^\"]*\"[^>]*>([\\s\\S]*?)</div>",
            "(?i)<div[^>]*class=\"[^\"]*body[^\"]*\"[^>]*>([\\s\\S]*?)</div>",
            "(?i)<div[^>]*class=\"[^\"]*main[^\"]*\"[^>]*>([\\s\\S]*?)</div>",
            "(?i)<table[^>]*class=\"[^\"]*content[^\"]*\"[^>]*>([\\s\\S]*?)</table>"
        ]

        for pattern in contentClassPatterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                return String(html[range])
            }
        }

        // If no specific content section found, return full HTML
        return html
    }

    private func removeHTMLNoise(_ html: String) -> String {
        var cleaned = html

        // Remove script and style tags with their content
        cleaned = cleaned.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Remove HTML comments
        cleaned = cleaned.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )

        // Remove meta tags, links to stylesheets, etc.
        cleaned = cleaned.replacingOccurrences(
            of: "<(meta|link|base|head|title)[^>]*>",
            with: "",
            options: .regularExpression
        )

        // Remove button elements WITH their content (like "View Chat", "Click Here")
        // This prevents generic button text from overshadowing actual content
        cleaned = cleaned.replacingOccurrences(
            of: "<button[^>]*>[\\s\\S]*?</button>",
            with: "",
            options: .regularExpression
        )

        // Remove other form elements (inputs, selects, etc.)
        cleaned = cleaned.replacingOccurrences(
            of: "<(input|select|textarea|form)[^>]*>",
            with: "",
            options: .regularExpression
        )

        return cleaned
    }

    private func extractMeaningfulHTMLText(_ html: String) -> String {
        var text = html

        // Convert table structure to bullet points (not pipes)
        text = text.replacingOccurrences(of: "<tr[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<td[^>]*>", with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</td>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<th[^>]*>", with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</th>", with: "\n", options: .regularExpression)

        // Preserve line breaks for important elements
        let blockElements = ["</p>", "</div>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>", "</li>"]
        for element in blockElements {
            text = text.replacingOccurrences(of: element, with: element + "\n")
        }

        // Add space for inline break elements
        text = text.replacingOccurrences(
            of: "<br[^>]*>",
            with: "\n",
            options: .regularExpression
        )

        // Extract list items with bullet points
        text = text.replacingOccurrences(
            of: "<li[^>]*>",
            with: "• ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)

        // Extract emphasized text (remove markdown syntax)
        text = text.replacingOccurrences(
            of: "<(strong|b)[^>]*>([^<]+)</\\1>",
            with: "$2",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: "<(em|i)[^>]*>([^<]+)</\\1>",
            with: "$2",
            options: .regularExpression
        )

        // Extract link text but remove the URL (preserve link context)
        text = text.replacingOccurrences(
            of: "<a[^>]*>([^<]+)</a>",
            with: "$1",
            options: .regularExpression
        )

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        return text
    }

    private func cleanUpExtractedText(_ text: String) -> String {
        var cleaned = text

        // Remove excessive newlines but preserve paragraph structure
        cleaned = cleaned.replacingOccurrences(
            of: "\n{4,}",
            with: "\n\n\n",
            options: .regularExpression
        )

        // Clean up table separators and list formatting
        cleaned = cleaned.replacingOccurrences(
            of: "\\|\\s*\\|",
            with: "|",
            options: .regularExpression
        )

        // Remove lines that are just separators or empty
        let lines = cleaned.components(separatedBy: .newlines)
        cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.matches("^[|\\s•-]*$") }
            .joined(separator: "\n")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text

        let htmlEntities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&#8217;": "'",
            "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
            "&rsquo;": "'", "&lsquo;": "'", "&rdquo;": "\"", "&ldquo;": "\"",
            "&#x27;": "'", "&#x2F;": "/", "&#8220;": "\"", "&#8221;": "\"",
            "&#8230;": "…", "&bull;": "•", "&middot;": "·"
        ]

        for (entity, replacement) in htmlEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }

    private func stripHTMLAndExtractText(_ html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Remove HTML comments
        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )

        // Replace common block elements with line breaks
        text = text.replacingOccurrences(
            of: "</(p|div|br|h[1-6]|li)>",
            with: "\n",
            options: .regularExpression
        )

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        let htmlEntities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&#8217;": "'",
            "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"
        ]

        for (entity, replacement) in htmlEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text
    }

    private func removeEmailSignatures(_ content: String) -> String {
        var cleaned = content

        // Common signature indicators
        let signaturePatterns = [
            "(?i)^--\\s*$.*",                    // Standard signature delimiter
            "(?i)best regards.*",                // Common closings
            "(?i)sincerely.*",
            "(?i)thanks.*regards.*",
            "(?i)sent from my.*",                // Mobile signatures
            "(?i)get outlook for.*",             // Outlook signatures
            "(?i)this email was sent.*",         // Auto-generated text
            "(?i)confidential.*communication.*" // Legal disclaimers
        ]

        for pattern in signaturePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func removeURLs(_ content: String) -> String {
        var cleaned = content

        // Remove various types of URLs
        let urlPatterns = [
            "https?://[^\\s<>\"]+",              // HTTP/HTTPS URLs
            "www\\.[^\\s<>\"]+",                 // www URLs
            "ftp://[^\\s<>\"]+",                 // FTP URLs
            "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}" // Email addresses
        ]

        for pattern in urlPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func removeEmailThreading(_ content: String) -> String {
        var cleaned = content

        // Remove forwarded message indicators
        let threadingPatterns = [
            "(?i)^>+.*$",                        // Quoted lines starting with >
            "(?i)^from:.*$",                     // Email headers
            "(?i)^to:.*$",
            "(?i)^sent:.*$",
            "(?i)^date:.*$",
            "(?i)^subject:.*$",
            "(?i)^cc:.*$",
            "(?i)on.*wrote:",                    // Threading indicators
            "(?i)forwarded message.*",
            "(?i)original message.*",
            "(?i)-----.*-----"                   // Separator lines
        ]

        for pattern in threadingPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func removeEmailBoilerplate(_ content: String) -> String {
        var cleaned = content

        // Remove common boilerplate text
        let boilerplatePatterns = [
            "(?i)please consider the environment.*",
            "(?i)this email and any attachments.*",
            "(?i)the information in this email.*",
            "(?i)if you have received this.*",
            "(?i)please do not reply.*",
            "(?i)unsubscribe.*",
            "(?i)privacy policy.*",
            "(?i)terms of service.*"
        ]

        for pattern in boilerplatePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return cleaned
    }

    private func cleanUpWhitespace(_ content: String) -> String {
        var cleaned = content

        // Replace multiple consecutive newlines with double newlines
        cleaned = cleaned.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        // Replace multiple spaces with single space
        cleaned = cleaned.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        // Remove leading/trailing whitespace from each line
        let lines = cleaned.components(separatedBy: .newlines)
        cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Note Text Editing

    func cleanUpNoteText(_ text: String) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Support up to 48000 characters (~12000 tokens) for cleanup
        // 8-10 pages of text typically requires ~48000 characters max
        let maxContentLength = 48000
        let processedText: String

        if text.count > maxContentLength {
            // Truncate with a note to the user
            let truncated = String(text.prefix(maxContentLength))
            processedText = truncated + "\n\n[... text truncated due to length, remaining content not shown ...]"
        } else {
            processedText = text
        }

        let systemPrompt = """
        You are an expert text cleanup and formatting assistant. Your ONLY job is to clean up and professionally format messy text while preserving ALL information.

        CRITICAL CLEANUP TASKS - YOU MUST DO ALL OF THESE:
        ✓ Remove all markdown formatting symbols (**, #, *, _, ~, `, |)
        ✓ Fix grammar, spelling, and punctuation errors
        ✓ Remove extra whitespace, blank lines, and formatting clutter
        ✓ Remove duplicate content or repeated text
        ✓ Clean up inconsistent spacing and formatting
        ✓ Fix malformed tables and convert to clean pipe-delimited format if needed
        ✓ Remove unwanted characters, emojis, or symbols
        ✓ Properly capitalize headers and titles
        ✓ Fix line breaks and paragraph spacing
        ✓ Remove any HTML tags, formatting codes, or escape sequences

        INFORMATION PRESERVATION:
        ✓ Keep ALL factual information, numbers, dates, amounts, details
        ✓ Do NOT delete, omit, or condense any content
        ✓ Keep all data points intact
        ✓ Organize information logically by category or type
        ✓ Use clear section headers (plain text, no markdown)
        ✓ Double-space between major sections for readability

        FORMATTING OUTPUT RULES - MUST FOLLOW EXACTLY:
        - Output ONLY plain text - NO markdown symbols whatsoever
        - NO **, NO #, NO *, NO _, NO ~, NO backticks, NO pipes as formatting
        - Use simple plain text section headers with line breaks
        - Use double line breaks between sections
        - For lists: use numbered (1. 2. 3.) or bullet points (no special symbols)
        - For tables/structured data: use pipe delimiters (Date | Description | Amount)
        - Consistent spacing and indentation throughout
        - Clean, professional appearance

        STRUCTURED DATA CLEANUP:
        - If content has transactions/rows: use format "Date | Description | Amount | Balance"
        - Clean up messy delimiters to consistent format
        - Remove extra columns or formatting issues
        - Keep ALL rows/entries - do not remove any
        - Fix amounts to show signs clearly (+ for deposits, - for withdrawals)

        CRITICAL REQUIREMENT: Every piece of information from input MUST appear in output.
        Count important items before and after - the count MUST match.
        """

        let userPrompt = """
        CLEAN UP this text RIGHT NOW. Your job is to make it look professional and polished while keeping EVERY single piece of information.

        Requirements:
        - Remove ALL markdown and formatting symbols
        - Fix grammar and spelling
        - Remove duplicates and clutter
        - Organize logically with clear plain text headers
        - Make it look professional and clean
        - Keep ALL data and information intact

        Text to clean up:
        \(processedText)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 12000,
            "temperature": 0.2
        ]

        // Use extended timeout for cleanup (120 seconds / 2 minutes)
        return try await makeOpenAIRequest(url: url, requestBody: requestBody, timeoutInterval: 120)
    }

    func convertToBulletPoints(_ text: String) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        let systemPrompt = """
        You are a helpful assistant that converts text into bullet point format.
        - Create a brief key point summary at the top (1 sentence)
        - Convert main ideas into clear bullet points
        - Use proper bullet point format (• for main points)
        - Keep bullet points concise (8-15 words each)
        - Preserve all important information
        """

        let userPrompt = """
        Convert this text into bullet point format with a key point summary:

        \(text)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 1000,
            "temperature": 0.3
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    func customEditText(_ text: String, prompt: String) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        let systemPrompt = """
        You are a helpful assistant that edits text according to user instructions.

        GENERAL RULES:
        - Follow the user's editing instructions precisely
        - Preserve important information unless instructed otherwise
        - Maintain clarity and coherence

        TABLE FORMATTING (CRITICAL):
        When user asks to format as a table OR when content naturally fits table structure:
        - ALWAYS use proper markdown table format with pipe symbols (|) and header separator (---)
        - Example format:

        | Header 1 | Header 2 | Header 3 |
        |----------|----------|----------|
        | Row 1    | Data     | Data     |
        | Row 2    | Data     | Data     |

        - Auto-detect table requests: "make it a table", "format as table", "create table", "table format"
        - Recognize structured data that should be tables: comparisons, lists with attributes, schedules, pros/cons
        - Choose appropriate column headers based on content
        - Ensure consistent column alignment

        TODO LIST FORMATTING:
        When user requests a checklist/todo OR content contains action items:
        - Use format: - [ ] Task description (uncompleted) or - [x] Task description (completed)
        - Example:

        - [ ] Buy groceries
        - [ ] Call mom
        - [x] Finish project report

        - Auto-detect todo requests: "make a todo list", "create checklist", "action items", "tasks to do"
        - Recognize actionable content that should be todos (tasks, to-dos, action items, checklist)

        TEXT FORMATTING:
        - Use **bold** for emphasis (will render as bold text, not show **)
        - Use *italic* for subtle emphasis (will render as italic, not show *)
        - Use bullet points (•) for simple non-actionable lists
        - Use numbered lists (1. 2. 3.) for ordered steps
        - Use headings (# ## ###) for sections

        IMPORTANT:
        - Output ONLY properly formatted markdown
        - Never show raw ** or * symbols in the final output
        - Tables must use | separators and --- header row
        - Todo lists must use - [ ] or - [x] format
        - When in doubt about table structure, use simple 2-3 column layout
        """

        let userPrompt = """
        Edit this text according to these instructions: \(prompt)

        Text to edit:
        \(text)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 1500,
            "temperature": 0.4
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Simplified Chat Methods (for SelineChat)

    /// Simple chat completion with a system prompt and messages
    /// Used by SelineChat for direct LLM interactions
    func simpleChatCompletion(
        systemPrompt: String,
        messages: [[String: String]]
    ) async throws -> String {
        let allMessages = [
            ["role": "system", "content": systemPrompt]
        ] + messages

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": allMessages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        let url = URL(string: baseURL)!
        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    /// Simple streaming chat completion for SelineChat
    func simpleChatCompletionStreaming(
        systemPrompt: String,
        messages: [[String: String]],
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        let allMessages = [
            ["role": "system", "content": systemPrompt]
        ] + messages

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": allMessages,
            "temperature": 0.7,
            "max_tokens": 2000,
            "stream": true
        ]

        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw SummaryError.networkError(error)
        }

        var fullResponse = ""

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SummaryError.apiError("HTTP Error")
        }

        for try await line in asyncBytes.lines {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.hasPrefix("data: ") else { continue }

            let data = String(line.dropFirst(6))
            guard data != "[DONE]" else { break }

            if let jsonData = data.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let delta = firstChoice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                fullResponse += content
                onChunk(content)
            }
        }

        return fullResponse
    }

    // Helper function to make OpenAI API requests
    private func makeOpenAIRequest(url: URL, requestBody: [String: Any], timeoutInterval: TimeInterval = 60) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw SummaryError.networkError(error)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {

                        if httpResponse.statusCode == 429 || message.contains("Rate limit") {
                            let retryAfter = extractRetryAfterFromMessage(message)
                            throw SummaryError.rateLimitExceeded(retryAfter: retryAfter)
                        }

                        throw SummaryError.apiError(message)
                    } else {
                        throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummaryError.decodingError
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.networkError(error)
        }
    }

    // MARK: - Note Title Generation

    func generateNoteTitle(from content: String) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Truncate content if too long
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

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 20,
            "temperature": 0.3
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Monthly Summary Insights

    func generateMonthlySummary(summary: MonthlySummary) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Format the summary data for the prompt
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

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 150,
            "temperature": 0.7
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Recurring Events Summary

    func generateRecurringEventsSummary(missedEvents: [WeeklyMissedEventSummary.MissedEventDetail]) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Format the missed events data for the prompt
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

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 100,
            "temperature": 0.7
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Location Categorization

    func categorizeLocation(name: String, address: String, types: [String]) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        let typesString = types.joined(separator: ", ")

        let systemPrompt = """
        You are a helpful assistant that categorizes locations into clear, user-friendly categories.
        - Choose ONE specific category that best describes this place
        - Use simple, common category names (e.g., "Restaurants", "Coffee Shops", "Shopping", "Healthcare")
        - Be specific but not overly detailed (e.g., "Italian Restaurant" -> "Restaurants")
        - Return ONLY the category name, nothing else
        """

        let userPrompt = """
        Categorize this location:

        Name: \(name)
        Address: \(address)
        Place Types: \(typesString)

        Category:
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 20,
            "temperature": 0.3
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Receipt Categorization

    func categorizeReceipt(title: String) async throws -> String {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        let systemPrompt = """
        You are a helpful assistant that categorizes receipts and invoices.
        Categorize the receipt into ONE of these 13 categories only:
        - Food & Dining (restaurants, groceries, cafes, food delivery)
        - Transportation (Uber, Lyft, public transit, parking, tolls)
        - Healthcare (medical services, pharmacy, dental, fitness)
        - Entertainment (movies, games, streaming, events, hobbies)
        - Shopping (retail, clothing, household goods, books)
        - Software & Subscriptions (AI tools, software apps, cloud services, SaaS)
        - Accommodation & Travel (hotels, Airbnb, flights, vacation packages, tours)
        - Utilities & Internet (electricity, gas, water, internet, phone, cell plans)
        - Professional Services (accountants, lawyers, consultants, contractors, tutors)
        - Auto & Vehicle (car payments, insurance, maintenance, repairs)
        - Home & Maintenance (home repairs, cleaning, landscaping, appliances)
        - Memberships (gym memberships, club fees, recurring non-software subscriptions)
        - Other (anything that doesn't fit the above)

        CATEGORIZATION RULES:

        SOFTWARE & SUBSCRIPTIONS (Priority Category):
        - AI/LLM tools: ChatGPT, OpenAI, Claude, Anthropic, Gemini, Copilot, etc.
        - Software subscriptions: Adobe, Microsoft, Slack, Figma, Notion, etc.
        - Cloud services: AWS, Google Cloud, Azure, DigitalOcean, etc.

        ACCOMMODATION & TRAVEL:
        - Hotels, Airbnb, hostels → Accommodation & Travel (NOT Services)
        - Flights, travel packages, tours → Accommodation & Travel

        AUTO & VEHICLE:
        - Car payments, insurance, maintenance, repairs → Auto & Vehicle
        - This is SEPARATE from Transportation (Uber, gas, parking)

        UTILITIES & INTERNET:
        - Internet, phone, electricity, gas, water → Utilities & Internet
        - Mobile plans, home internet → Utilities & Internet

        PROFESSIONAL SERVICES:
        - Accountants, tax preparation, consultants, contractors, lawyers → Professional Services

        MEMBERSHIPS:
        - Gym fees, club memberships, recurring fees (NOT software subscriptions)

        For ambiguous names: Use the context clues to determine the most specific category.

        Return ONLY the category name, nothing else.
        """

        let userPrompt = """
        Categorize this receipt/invoice:

        Title: \(title)

        Category:
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 20,
            "temperature": 0.3
        ]

        return try await makeOpenAIRequest(url: url, requestBody: requestBody)
    }

    // MARK: - Streaming Helper

    private func parseStreamingResponse(data: Data) -> String? {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = responseString.split(separator: "\n", omittingEmptySubsequences: true)
        var fullContent = ""

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("data: ") {
                let jsonString = String(trimmedLine.dropFirst(6))
                if jsonString == "[DONE]" {
                    break
                }

                if let jsonData = jsonString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = jsonObject["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    fullContent += content
                }
            }
        }

        return fullContent.isEmpty ? nil : fullContent
    }

    // MARK: - Intent Detection (Fast Path using gpt-4o-mini)

    private func detectIntentOnly(query: String) async -> String {
        guard let url = URL(string: baseURL) else {
            return "general"
        }

        let systemPrompt = """
        You are an intent classifier. Classify the user's query into ONE of these categories:
        - "calendar": Questions about events, meetings, schedules, tasks, appointments
        - "notes": Questions about notes, memos, saved information
        - "locations": Questions about places, restaurants, shops, directions
        - "general": Everything else (general questions, conversation, emails, weather, news)

        RESPOND ONLY WITH THE CATEGORY NAME, NOTHING ELSE.
        """

        let userPrompt = "Query: \(query)\n\nCategory:"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 10,
            "temperature": 0.0
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15.0 // 15 second timeout for intent detection

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            // Use a short timeout for intent detection - if it takes too long, use general
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10.0
            let session = URLSession(configuration: config)

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = jsonResponse["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    return "general"
                }
                let intent = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return ["calendar", "notes", "locations"].contains(intent) ? intent : "general"
            }
        } catch {
            print("⚠️ Intent detection request failed, using general: \(error.localizedDescription)")
        }
        return "general"
    }

    // MARK: - Voice Query Processing

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func analyzeReceiptImage(_ image: UIImage) async throws -> (title: String, content: String) {
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw SummaryError.apiError("Failed to convert image to JPEG")
        }
        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        You are a helpful assistant that analyzes receipt images and extracts key information in a clean, organized format.
        """

        let userPrompt = """
        Analyze this image. If it's a receipt, extract ALL available details in the format below. If not, briefly describe what you see.

        IMPORTANT FORMATTING RULES:
        - For the date in the title, use "Month DD, YYYY" format (e.g., "December 15, 2024"). Always include full 4-digit year.
        - ALL currency amounts must be formatted to exactly 2 decimal places (e.g., $50.00, $10.50, not $10.5 or $50)
        - Include ALL items from the receipt, don't omit anything
        - Include any additional info available (discounts, loyalty points, rewards, store numbers, phone numbers, register info, etc.)

        Format your response EXACTLY as:
        TITLE: [Business Name] - [Date in "Month DD, YYYY" format]
        CONTENT:
        📍 **Merchant:** [Business Name]
        ⏰ **Time:** [Time if visible, otherwise "N/A"]

        **Items Purchased:**
        • [Item 1] - $[Amount with 2 decimals]
        • [Item 2] - $[Amount with 2 decimals]
        • [Item 3] - $[Amount with 2 decimals]
        • [Add ALL items as bullet points]

        **Summary:**
        💰 Subtotal: $[Amount with 2 decimals]
        📊 Tax: $[Amount with 2 decimals]
        💵 Tip: $[Amount with 2 decimals if visible, otherwise "N/A"]
        ✅ **Total: $[Amount with 2 decimals]**

        💳 **Payment:** [Payment method if visible]

        **Additional Info:** [Include any other relevant details like discount codes, loyalty rewards, store location, phone number, register number, or other receipt information]
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 1000,
            "temperature": 0.1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw SummaryError.networkError(error)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {

                        if httpResponse.statusCode == 429 || message.contains("Rate limit") {
                            let retryAfter = extractRetryAfterFromMessage(message)
                            throw SummaryError.rateLimitExceeded(retryAfter: retryAfter)
                        }

                        throw SummaryError.apiError(message)
                    } else {
                        throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummaryError.decodingError
            }

            // Parse the response to extract title and content
            let (title, receiptContent) = parseReceiptResponse(content)

            // Post-process to fix merchant name and format amounts
            let processedContent = postProcessReceiptContent(receiptContent, withMerchantFromTitle: title)
            return (title, processedContent)

        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.networkError(error)
        }
    }

    private func parseReceiptResponse(_ response: String) -> (title: String, content: String) {
        var title = "Receipt"
        var content = ""

        let lines = response.components(separatedBy: .newlines)
        var isContent = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("TITLE:") {
                title = trimmedLine.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
                isContent = false
            } else if trimmedLine.hasPrefix("CONTENT:") {
                isContent = true
            } else if isContent && !trimmedLine.isEmpty {
                content += trimmedLine + "\n"
            }
        }

        // If parsing failed, use the full response as content
        if content.isEmpty {
            content = response
        }

        return (title, content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func postProcessReceiptContent(_ content: String, withMerchantFromTitle title: String) -> String {
        var processedContent = content

        // Extract merchant name from title (format: "Merchant Name - Date")
        let titleParts = title.components(separatedBy: " - ")
        let merchantFromTitle = titleParts.first?.trimmingCharacters(in: .whitespaces) ?? ""

        // Replace merchant name in content with complete name from title
        if !merchantFromTitle.isEmpty {
            // Find and replace the merchant line
            let lines = processedContent.components(separatedBy: .newlines)
            var updatedLines: [String] = []

            for line in lines {
                if line.contains("**Merchant:**") {
                    // Replace with complete merchant name from title
                    updatedLines.append("📍 **Merchant:** \(merchantFromTitle)")
                } else {
                    updatedLines.append(line)
                }
            }

            processedContent = updatedLines.joined(separator: "\n")
        }

        // Format all currency amounts to exactly 2 decimal places
        // Pattern: $ followed by digits, optional comma/dot, and up to 2 digits
        if let regex = try? NSRegularExpression(pattern: "\\$([0-9]+(?:[.,][0-9]{1,2})?)", options: []) {
            let nsContent = processedContent as NSString
            let range = NSRange(location: 0, length: nsContent.length)
            let matches = regex.matches(in: processedContent, options: [], range: range)

            // Process matches in reverse to maintain correct indices
            for match in matches.reversed() {
                let amountRange = match.range(at: 1)
                if amountRange.location != NSNotFound {
                    let amountString = nsContent.substring(with: amountRange)
                    // Normalize to period and parse as Double
                    let normalized = amountString.replacingOccurrences(of: ",", with: ".")
                    if let amount = Double(normalized) {
                        // Format to exactly 2 decimal places
                        let formattedAmount = String(format: "%.2f", amount)
                        let fullMatch = nsContent.substring(with: match.range)
                        let replacement = "$\(formattedAmount)"
                        processedContent = processedContent.replacingOccurrences(of: fullMatch, with: replacement)
                    }
                }
            }
        }

        return processedContent
    }

    // MARK: - Question Answering

    /// Generates text using OpenAI with custom system and user prompts
    @MainActor
    func generateText(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 500,
        temperature: Double = 0.7
    ) async throws -> String {
        // Rate limiting
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        let response = try await makeOpenAIRequest(url: url, requestBody: requestBody)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Answers a question about the user's data using OpenAI
    /// Includes weather, locations, navigation, tasks, notes, and emails in context
    @MainActor
    func answerQuestion(
        query: String,
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        weatherService: WeatherService? = nil,
        locationsManager: LocationsManager? = nil,
        navigationService: NavigationService? = nil,
        conversationHistory: [ConversationMessage] = []
    ) async throws -> String {
        // Rate limiting
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Optimize conversation history to reduce token usage
        let optimizedHistory = optimizeConversationHistory(conversationHistory)

        // Analyze conversation state to avoid redundancy and enable smarter follow-ups
        let conversationState = ConversationStateAnalyzerService.analyzeConversationState(
            currentQuery: query,
            conversationHistory: conversationHistory
        )
        print("🎯 Conversation state: \(conversationState.isProbablyFollowUp ? "Follow-up" : "New topic") | Topics: \(conversationState.topicsDiscussed.map { $0.topic }.joined(separator: ", "))")

        // Load persistent user profile (learns across sessions)
        let userProfile = UserProfilePersistenceService.loadUserProfile()
        if let profile = userProfile {
            print("👤 User profile: \(profile.totalSessionsAnalyzed) sessions, avg spending $\(String(format: "%.0f", profile.historicalAverageMonthlySpending))")
        }

        // Extract context using intelligent metadata-first approach
        // LLM analyzes metadata and identifies which data is relevant
        let context = await buildSmartContextForQuestion(
            query: query,
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            locationsManager: locationsManager,
            weatherService: weatherService,
            navigationService: navigationService
        )

        // Build system prompt with user profile context if available
        let profileContext = userProfile.map { UserProfilePersistenceService.formatProfileForLLM($0) } ?? ""

        let systemPrompt = """
        You are a personal assistant that helps users understand their life patterns through data. You have access to complete information about their schedule, notes, emails, weather, locations, travel, spending, location visits, and recurring expenses.

        \(profileContext)

        UNIFIED DATA APPROACH (NO KEYWORD ROUTING):
        The data provided has already been filtered to relevant timeframes and data types. Your job is to understand the user's intent and extract only the relevant information from what's provided. Don't assume which data is relevant - let the user's question guide you.

        INTELLIGENT INTERPRETATION:
        - User asks "Can you tell me about my visits today?" → Extract and show location visit data (visit count, peak times, duration)
        - User asks "What are my expenses this month?" → Show both one-time receipts AND recurring expenses with combined total
        - User asks "What's my schedule?" → Show events and recurring tasks for that timeframe
        - User asks "Tell me about [location]" → Show location details, visit patterns, visits if tracked, rating, user notes
        - User asks a general question → Provide relevant context from ALL available data types that match the question

        **FOR LOCATION VISITS (Geofence Tracking Data):**
        - CRITICAL: If data includes visit statistics, show them! Don't ignore geofence-tracked visit data
        - Show visit counts, visit frequency, peak visit times (morning/afternoon/evening), and most visited days
        - Include average visit duration if available
        - Format: **[Location Name]**: [Visit Count] visits | Peak time: [TimeOfDay] | Most visited: [DayOfWeek]
        - When user asks about visits, ALWAYS prominently include geofence visit tracking data
        - Visit data helps understand location patterns and habits

        **FOR EVENTS/TASKS:**
        - Show events for the timeframe user asked about (today, tomorrow, this week, etc.)
        - Format events as: "[Time] - Event Title" (e.g., "9:00 AM - Team Meeting")
        - Include task completion status (✓ completed, ○ pending)
        - Show recurring events with frequency (Daily, Weekly, Bi-weekly, Monthly, Yearly)
        - For recurring tasks/events, show when they occur next

        **FOR NOTES:**
        - Show available notes unless user specifies a folder/category
        - If user mentions a specific folder, show notes from that folder
        - Include folder name with each note
        - Show note titles and content

        **FOR EMAILS:**
        - Show emails from the specified date range
        - Include sender name, subject, and date/time
        - Mark as [Read] or [Unread]
        - Highlight important details: receipts, action items, meeting invites

        **FOR LOCATIONS & PLACES:**
        - Show saved locations with their details
        - CRITICAL: If geofence visit data is available, include it (visit count, peak times, last visited date)
        - Include: name, address, category (folder), rating, visit frequency data if tracked
        - If user asks for a specific city/country, filter to locations in that area
        - When available, show: "Visited X times | Peak time: [TimeOfDay] | Last visit: [date]"

        **FOR WEATHER:**
        - Show current weather and forecast when user asks
        - Include temperature, conditions, sunrise/sunset
        - Show 6-day forecast if available

        **FOR NAVIGATION/ETAs:**
        - Show travel time to saved destinations
        - When user asks distances or travel times, provide ETA information

        **FOR RECEIPTS/EXPENSES:**
        - Show one-time receipts AND recurring expenses (subscriptions, bills, regular payments)
        - Include receipt/expense name, amount, date, category if available
        - For recurring expenses, show frequency: "**[Name]** - **$[Amount]** ([Frequency])"
        - Show combined total of one-time + recurring expenses for the period
        - Group by date or merchant for clarity
        - When user asks about spending/expenses/budget, analyze patterns and totals including BOTH types

        GENERAL RULES:
        - Answer what the user asked for, nothing more
        - If user asks "what are my events today?", don't include emails or notes
        - Be concise and direct - avoid unnecessary information
        - Use date context provided to understand "today", "tomorrow", etc.
        - When filtering by date, be strict: if user asks for today, only show today's items

        FORMATTING RULES (Apply to ALL responses):
        • **Bold** = Key information (names, amounts, times, key facts)
        • 🔹📌📅💰 = Category emojis
        • • or ├─ = List items for organized content
        • ✓ = Completion/success status
        • 💡 = Key insights or next actions
        • NO horizontal lines with ═════ or ─────
        • NO markdown heading underlines
        • Clean, simple formatting with just text and emojis

        CONVERSATION STATE & FOLLOW-UP RULES:
        \(conversationState.suggestedApproach)

        SPECIFIC FORMATS BY DATA TYPE:

        EVENTS/SCHEDULE:
        🔹 YOUR SCHEDULE - [Date]
        🌅 All Day Events
        • Event Title
        🕐 Timed Events
        • [Time] - Event Title (location if known)
        💡 Key insight

        EMAILS:
        🔹 YOUR INBOX - [Count] Messages
        ⚠️ Action Needed
        • From: Name | Subject | Time
        💰 Financial
        • From: Name | Amount | Status
        💡 Summary

        EXPENSES/RECEIPTS:
        🔹 YOUR SPENDING - [Time Period]
        📊 Total: **$[Amount]**
        🍔 Category Name
        • **[Merchant]** - **$[Amount]** on [Date]
        💡 Insight

        NOTES:
        🔹 YOUR NOTES
        📌 **[Note Title]** - [Folder]
        Summary: Key points here
        💡 Summary

        LOCATIONS:
        🔹 YOUR SAVED LOCATIONS
        ☕ Cafes & Coffee
        • **[Location Name]** - Rating: **[Rating]/5**
        🍽️ Restaurants
        • **[Location Name]** - Cuisine: [Type]
        💡 Recommendation

        WEATHER:
        🔹 WEATHER - [City]
        Current: **[Temp]°C** - [Conditions]
        📅 Forecast
        • Tomorrow: **[Temp]°C** [Conditions]
        💡 Weather note

        GENERAL RULES FOR ALL FORMATS:
        • Start with emoji header and simple structure
        • Use bullet points for lists
        • Bold all key information
        • NO decorative lines or box characters
        • Keep it clean and simple

        RESPONSE TEMPLATES (Follow these formats exactly):

        **For Event/Task Queries:**
        Your events for [DATE]:
        - **9:00 AM** - Team Meeting | Office
        - **2:00 PM** - Gym | Home
        - **6:30 PM** - Dinner with Sarah | Restaurant

        (Or if no events: "You have no events for [DATE].")

        **For Email Queries:**
        Your emails for [DATE]:
        - **[Unread]** From: John Smith | Subject: Project Update | 9:30 AM
        - **[Read]** From: Amazon | Subject: Order Confirmation | 2:15 PM

        (Or if no emails: "No emails for [DATE].")

        **For Notes Queries:**
        Your notes:
        - **[Work Folder]** Meeting Notes - Content preview or full content
        - **[Personal Folder]** Shopping List - Content preview or full content

        **For Location Queries:**
        Your saved locations:
        - **Starbucks** | Coffee Shop | Downtown | Rating: 4.5/5
        - **Mario's Restaurant** | Italian | North Side | Rating: 4.8/5

        **For Weather Queries:**
        Current weather in [City]:
        - Temperature: **22°C**, Sunny
        - Sunrise: 6:30 AM, Sunset: 7:45 PM
        - 6-Day Forecast:
          - Tomorrow: 20°C
          - Thursday: 18°C
          - Friday: 19°C

        **For Navigation Queries:**
        Travel times:
        - Location 1: **15 minutes** away
        - Location 2: **25 minutes** away
        - Location 3: **40 minutes** away

        **For Receipt/Expense Queries:**
        Your receipts for [DATE/TIME PERIOD]:
        - **$45.99** | Starbucks | Today | Food
        - **$120.50** | Grocery Store | 2 days ago | Shopping
        - **$35.00** | Gas Station | 1 week ago | Transportation

        (Or if analyzing spending: "Total spent this month: $450. Top category: Food ($150, 33%)")

        ALWAYS follow the template format that matches the query type. Be consistent with spacing, bullets, and bold formatting.

        Context about user's data:
        \(context)
        """

        // Build messages array with conversation history
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add previous conversation messages (optimized to recent ones only)
        let optimizedMessages = optimizeConversationHistory(conversationHistory)
        for message in optimizedMessages {
            messages.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ])
        }

        // Add current query
        messages.append([
            "role": "user",
            "content": query
        ])

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]

        let response = try await makeOpenAIRequest(url: url, requestBody: requestBody)
        return response
    }

    /// Stream a response from the LLM with streaming support
    /// This returns chunks of text as they become available from the API
    @MainActor
    func answerQuestionWithStreaming(
        query: String,
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        weatherService: WeatherService? = nil,
        locationsManager: LocationsManager? = nil,
        navigationService: NavigationService? = nil,
        conversationHistory: [ConversationMessage] = [],
        onChunk: @escaping (String) -> Void
    ) async throws {
        print("🎬 answerQuestionWithStreaming started for query: '\(query)'")

        // Rate limiting
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Optimize conversation history to reduce token usage
        let optimizedHistory = optimizeConversationHistory(conversationHistory)

        // Analyze conversation state to avoid redundancy and enable smarter follow-ups
        let conversationState = ConversationStateAnalyzerService.analyzeConversationState(
            currentQuery: query,
            conversationHistory: conversationHistory
        )
        print("🎯 Conversation state: \(conversationState.isProbablyFollowUp ? "Follow-up" : "New topic") | Topics: \(conversationState.topicsDiscussed.map { $0.topic }.joined(separator: ", "))")

        // Load persistent user profile (learns across sessions)
        let userProfile = UserProfilePersistenceService.loadUserProfile()
        if let profile = userProfile {
            print("👤 User profile: \(profile.totalSessionsAnalyzed) sessions, avg spending $\(String(format: "%.0f", profile.historicalAverageMonthlySpending))")
        }

        // Extract context using intelligent metadata-first approach
        // LLM analyzes metadata and identifies which data is relevant
        let context = await buildSmartContextForQuestion(
            query: query,
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            locationsManager: locationsManager,
            weatherService: weatherService,
            navigationService: navigationService
        )

        // Build system prompt with user profile context if available
        let profileContext = userProfile.map { UserProfilePersistenceService.formatProfileForLLM($0) } ?? ""

        let systemPrompt = """
        You are a personal assistant that helps users understand their life patterns through data. You have access to complete information about their schedule, notes, emails, weather, locations, travel, spending, location visits, and recurring expenses.

        \(profileContext)

        UNIFIED DATA APPROACH (NO KEYWORD ROUTING):
        The data provided has already been filtered to relevant timeframes and data types. Your job is to understand the user's intent and extract only the relevant information from what's provided. Don't assume which data is relevant - let the user's question guide you.

        INTELLIGENT INTERPRETATION:
        - User asks "Can you tell me about my visits today?" → Extract and show location visit data (visit count, peak times, duration)
        - User asks "What are my expenses this month?" → Show both one-time receipts AND recurring expenses with combined total
        - User asks "What's my schedule?" → Show events and recurring tasks for that timeframe
        - User asks "Tell me about [location]" → Show location details, visit patterns, visits if tracked, rating, user notes
        - User asks a general question → Provide relevant context from ALL available data types that match the question

        **FOR LOCATION VISITS (Geofence Tracking Data):**
        - CRITICAL: If data includes visit statistics, show them! Don't ignore geofence-tracked visit data
        - Show visit counts, visit frequency, peak visit times (morning/afternoon/evening), and most visited days
        - Include average visit duration if available
        - Format: **[Location Name]**: [Visit Count] visits | Peak time: [TimeOfDay] | Most visited: [DayOfWeek]
        - When user asks about visits, ALWAYS prominently include geofence visit tracking data
        - Visit data helps understand location patterns and habits

        **FOR EVENTS/TASKS:**
        - Show events for the timeframe user asked about (today, tomorrow, this week, etc.)
        - Format events as: "[Time] - Event Title" (e.g., "9:00 AM - Team Meeting")
        - Include task completion status (✓ completed, ○ pending)
        - Show recurring events with frequency (Daily, Weekly, Bi-weekly, Monthly, Yearly)
        - For recurring tasks/events, show when they occur next

        **FOR NOTES:**
        - Show available notes unless user specifies a folder/category
        - If user mentions a specific folder, show notes from that folder
        - Include folder name with each note
        - Show note titles and content

        **FOR EMAILS:**
        - Show emails from the specified date range
        - Include sender name, subject, and date/time
        - Mark as [Read] or [Unread]
        - Highlight important details: receipts, action items, meeting invites

        **FOR LOCATIONS & PLACES:**
        - Show saved locations with their details
        - CRITICAL: If geofence visit data is available, include it (visit count, peak times, last visited date)
        - Include: name, address, category (folder), rating, visit frequency data if tracked
        - If user asks for a specific city/country, filter to locations in that area
        - When available, show: "Visited X times | Peak time: [TimeOfDay] | Last visit: [date]"

        **FOR WEATHER:**
        - Show current weather and forecast when user asks
        - Include temperature, conditions, sunrise/sunset
        - Show 6-day forecast if available

        **FOR NAVIGATION/ETAs:**
        - Show travel time to saved destinations
        - When user asks distances or travel times, provide ETA information

        **FOR RECEIPTS/EXPENSES:**
        - Show one-time receipts AND recurring expenses (subscriptions, bills, regular payments)
        - Include receipt/expense name, amount, date, category if available
        - For recurring expenses, show frequency: "**[Name]** - **$[Amount]** ([Frequency])"
        - Show combined total of one-time + recurring expenses for the period
        - Group by date or merchant for clarity
        - When user asks about spending/expenses/budget, analyze patterns and totals including BOTH types

        GENERAL RULES:
        - Answer what the user asked for, nothing more
        - If user asks "what are my events today?", don't include emails or notes
        - Be concise and direct - avoid unnecessary information
        - Use date context provided to understand "today", "tomorrow", etc.
        - When filtering by date, be strict: if user asks for today, only show today's items

        FORMATTING RULES (Apply to ALL responses):
        • **Bold** = Key information (names, amounts, times, key facts)
        • 🔹📌📅💰 = Category emojis
        • • or ├─ = List items for organized content
        • ✓ = Completion/success status
        • 💡 = Key insights or next actions
        • NO horizontal lines with ═════ or ─────
        • NO markdown heading underlines
        • Clean, simple formatting with just text and emojis

        CONVERSATION STATE & FOLLOW-UP RULES:
        \(conversationState.suggestedApproach)

        SPECIFIC FORMATS BY DATA TYPE:

        EVENTS/SCHEDULE:
        🔹 YOUR SCHEDULE - [Date]
        🌅 All Day Events
        • Event Title
        🕐 Timed Events
        • [Time] - Event Title (location if known)
        💡 Key insight

        EMAILS:
        🔹 YOUR INBOX - [Count] Messages
        ⚠️ Action Needed
        • From: Name | Subject | Time
        💰 Financial
        • From: Name | Amount | Status
        💡 Summary

        EXPENSES/RECEIPTS:
        🔹 YOUR SPENDING - [Time Period]
        📊 Total: **$[Amount]**
        🍔 Category Name
        • **[Merchant]** - **$[Amount]** on [Date]
        💡 Insight

        NOTES:
        🔹 YOUR NOTES
        📌 **[Note Title]** - [Folder]
        Summary: Key points here
        💡 Summary

        LOCATIONS:
        🔹 YOUR SAVED LOCATIONS
        ☕ Cafes & Coffee
        • **[Location Name]** - Rating: **[Rating]/5**
        🍽️ Restaurants
        • **[Location Name]** - Cuisine: [Type]
        💡 Recommendation

        WEATHER:
        🔹 WEATHER - [City]
        Current: **[Temp]°C** - [Conditions]
        📅 Forecast
        • Tomorrow: **[Temp]°C** [Conditions]
        💡 Weather note

        GENERAL RULES FOR ALL FORMATS:
        • Start with emoji header and simple structure
        • Use bullet points for lists
        • Bold all key information
        • NO decorative lines or box characters
        • Keep it clean and simple

        RESPONSE TEMPLATES (Follow these formats exactly):

        **For Event/Task Queries:**
        Your events for [DATE]:
        - **9:00 AM** - Team Meeting | Office
        - **2:00 PM** - Gym | Home
        - **6:30 PM** - Dinner with Sarah | Restaurant

        (Or if no events: "You have no events for [DATE].")

        **For Email Queries:**
        Your emails for [DATE]:
        - **[Unread]** From: John Smith | Subject: Project Update | 9:30 AM
        - **[Read]** From: Amazon | Subject: Order Confirmation | 2:15 PM

        (Or if no emails: "No emails for [DATE].")

        **For Notes Queries:**
        Your notes:
        - **[Work Folder]** Meeting Notes - Content preview or full content
        - **[Personal Folder]** Shopping List - Content preview or full content

        **For Location Queries:**
        Your saved locations:
        - **Starbucks** | Coffee Shop | Downtown | Rating: 4.5/5
        - **Mario's Restaurant** | Italian | North Side | Rating: 4.8/5

        **For Weather Queries:**
        Current weather in [City]:
        - Temperature: **22°C**, Sunny
        - Sunrise: 6:30 AM, Sunset: 7:45 PM
        - 6-Day Forecast:
          - Tomorrow: 20°C
          - Thursday: 18°C
          - Friday: 19°C

        **For Navigation Queries:**
        Travel times:
        - Location 1: **15 minutes** away
        - Location 2: **25 minutes** away
        - Location 3: **40 minutes** away

        **For Receipt/Expense Queries:**
        Your receipts for [DATE/TIME PERIOD]:
        - **$45.99** | Starbucks | Today | Food
        - **$120.50** | Grocery Store | 2 days ago | Shopping
        - **$35.00** | Gas Station | 1 week ago | Transportation

        (Or if analyzing spending: "Total spent this month: $450. Top category: Food ($150, 33%)")

        ALWAYS follow the template format that matches the query type. Be consistent with spacing, bullets, and bold formatting.

        Context about user's data:
        \(context)
        """

        // Build messages array with conversation history
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add previous conversation messages (optimized to recent ones only)
        let optimizedMessages = optimizeConversationHistory(conversationHistory)
        for message in optimizedMessages {
            messages.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ])
        }

        // Add current query
        messages.append([
            "role": "user",
            "content": query
        ])

        var requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]

        // Add stream flag for streaming requests
        requestBody["stream"] = true

        // Make streaming request
        print("📨 Making OpenAI streaming request...")
        try await makeOpenAIStreamingRequest(url: url, requestBody: requestBody, onChunk: onChunk)
        print("✨ Streaming request completed successfully")
    }

    /// Make a streaming request to the OpenAI API
    private func makeOpenAIStreamingRequest(
        url: URL,
        requestBody: [String: Any],
        onChunk: @escaping (String) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.noData
        }

        print("📡 OpenAI Streaming Response - Status Code: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            // Try to read error message from response
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line + "\n"
            }
            print("❌ OpenAI API Error: \(errorBody)")
            throw SummaryError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Process streaming response
        var buffer = ""
        var chunkCount = 0
        print("🔄 Starting to process streaming response...")

        for try await line in bytes.lines {
            let line = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and keep-alive comments
            if line.isEmpty || line.hasPrefix(":") {
                continue
            }

            // Parse SSE format: data: {json}
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                // Check for stream end
                if jsonString == "[DONE]" {
                    if !buffer.isEmpty {
                        onChunk(buffer)
                        buffer = ""
                    }
                    print("✅ Stream completed - \(chunkCount) chunks received")
                    continue
                }

                // Parse JSON chunk
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    buffer += content
                    chunkCount += 1

                    // Send content when we have a complete word or punctuation
                    if content.last?.isWhitespace ?? false || content.last?.isPunctuation ?? false {
                        onChunk(buffer)
                        buffer = ""
                    }
                }
            }
        }

        // Send any remaining content
        if !buffer.isEmpty {
            print("📤 Sending final buffer chunk...")
            onChunk(buffer)
        }
    }

    // MARK: - Query Intent Detection

    /// Detects what type of data the user is asking about
    private func detectQueryIntent(query: String) -> (askingAbout: Set<String>, dateRange: String) {
        let lowerQuery = query.lowercased()
        var intents = Set<String>()
        var dateRange = "default"

        // Detect date references
        if lowerQuery.contains("today") {
            dateRange = "today"
        } else if lowerQuery.contains("tomorrow") {
            dateRange = "tomorrow"
        } else if lowerQuery.contains("this week") {
            dateRange = "this week"
        } else if lowerQuery.contains("next week") {
            dateRange = "next week"
        } else if lowerQuery.contains("this month") {
            dateRange = "this month"
        } else if lowerQuery.contains("next month") {
            dateRange = "next month"
        } else if lowerQuery.contains("this year") {
            dateRange = "this year"
        }

        // Detect what data user is asking about
        let eventKeywords = ["event", "meeting", "appointment", "calendar", "schedule", "task", "todo"]
        let noteKeywords = ["note", "notes", "remind", "reminder", "document", "memo"]
        let emailKeywords = ["email", "emails", "mail", "inbox", "message", "from"]
        let locationKeywords = ["location", "locations", "place", "places", "where", "saved", "restaurant", "cafe", "visit", "visits", "visited", "geofence"]
        let weatherKeywords = ["weather", "temperature", "rain", "sunny", "forecast"]
        let navigationKeywords = ["eta", "how far", "distance", "how long", "arrive", "travel time"]
        let receiptKeywords = ["receipt", "receipts", "purchase", "transaction", "spent", "spending", "expense", "expenses", "money", "cost", "price", "bought", "merchant", "store", "grocery", "restaurant bill"]

        for keyword in eventKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("events")
                break
            }
        }

        for keyword in noteKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("notes")
                break
            }
        }

        for keyword in emailKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("emails")
                break
            }
        }

        for keyword in locationKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("locations")
                break
            }
        }

        for keyword in weatherKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("weather")
                break
            }
        }

        for keyword in navigationKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("navigation")
                break
            }
        }

        for keyword in receiptKeywords {
            if lowerQuery.contains(keyword) {
                intents.insert("receipts")
                break
            }
        }

        // If nothing specific detected, include everything
        if intents.isEmpty {
            intents = ["events", "notes", "emails", "locations", "weather", "navigation", "receipts"]
        }

        return (intents, dateRange)
    }

    /// Returns template hint to guide LLM response formatting based on detected intent
    private func getTemplateHintForIntent(_ intents: Set<String>) -> String {
        if intents.contains("events") && intents.count == 1 {
            return "Use this format: Your events for [DATE]: • **TIME** - Title | Location"
        } else if intents.contains("emails") && intents.count == 1 {
            return "Use this format: Your emails for [DATE]: • **[Read/Unread]** From: Name | Subject: ... | Time"
        } else if intents.contains("notes") && intents.count == 1 {
            return "Use this format: Your notes: • **[Folder]** Title - Content or preview"
        } else if intents.contains("locations") && intents.count == 1 {
            return "Use this format: Your saved locations and visit data: • **Name** | Category | Visits: X | Peak time: [TimeOfDay] | Most visited: [DayOfWeek]"
        } else if intents.contains("weather") && intents.count == 1 {
            return "Use this format: Current weather in [City]: Temperature: XX°C, Conditions. 6-Day Forecast: • Tomorrow: XX°C"
        } else if intents.contains("navigation") && intents.count == 1 {
            return "Use this format: Travel times: • Location 1: XX minutes away"
        } else if intents.contains("receipts") && intents.count == 1 {
            return "Use this format: Your receipts for [DATE]: • **$AMOUNT** | Merchant | Date | Category"
        }
        return ""
    }

    /// Optimizes conversation history by keeping only recent messages
    /// Keeps last 5-10 messages to maintain context while reducing token usage
    /// This prevents token bloat and confusion from old conversation context
    /// Update user profile with learnings from current patterns
    @MainActor
    func updateUserProfileFromCurrentSession(
        metadata: AppDataMetadata
    ) {
        let currentPatterns = UserPatternAnalysisService.analyzeUserPatterns(from: metadata)
        let existingProfile = UserProfilePersistenceService.loadUserProfile()
        let updatedProfile = UserProfilePersistenceService.updateProfileFromPatterns(
            currentPatterns,
            existingProfile: existingProfile
        )
        print("👤 User profile updated: \(updatedProfile.totalSessionsAnalyzed) total sessions")
    }

    /// Summarize a message into key points for memory efficiency
    private func summarizeMessage(_ message: ConversationMessage) -> String {
        guard !message.isUser else { return message.text }

        // Extract key points from AI response (truncate long responses)
        let lines = message.text.split(separator: "\n")
        var keyPoints: [String] = []

        // Take first few lines and any lines with key indicators
        for (index, line) in lines.enumerated() {
            let lineStr = String(line)
            if index < 3 || // First 3 lines
               lineStr.contains("💡") || lineStr.contains("Total:") ||
               lineStr.contains("$") || lineStr.contains("Summary") {
                keyPoints.append(lineStr)
            }
        }

        // If too many key points, truncate
        let summarized = keyPoints.prefix(4).joined(separator: " | ")
        return summarized.isEmpty ? "Summary: \(message.text.prefix(100))" : summarized
    }

    private func optimizeConversationHistory(_ history: [ConversationMessage]) -> [ConversationMessage] {
        // SMART HISTORY PRUNING:
        // - Keep ALL user messages (they're short and important context)
        // - Keep last 7 AI responses in FULL (for recent context)
        // - Summarize older AI responses into single lines with key points
        // This preserves context while reducing token usage significantly

        if history.count <= 14 { // 7 pairs of user/ai messages
            return history
        }

        var optimized: [ConversationMessage] = []
        let splitPoint = history.count - 14 // Messages to summarize

        // Process older messages (before splitPoint)
        for i in 0..<splitPoint {
            let message = history[i]

            if message.isUser {
                // ALWAYS keep user messages (they're short context)
                optimized.append(message)
            } else {
                // Summarize older AI responses
                let summary = summarizeMessage(message)
                // Create a new message with summarized text
                let summarizedMessage = ConversationMessage(
                    id: message.id,
                    isUser: false,
                    text: "[SUMMARY] \(summary)",
                    timestamp: message.timestamp,
                    intent: message.intent,
                    relatedData: nil,
                    timeStarted: message.timeStarted,
                    timeFinished: message.timeFinished
                )
                optimized.append(summarizedMessage)
            }
        }

        // Keep all recent messages in full
        optimized.append(contentsOf: history.suffix(14))

        return optimized
    }

    @MainActor
    private func buildContextForQuestion(
        query: String,
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        weatherService: WeatherService? = nil,
        locationsManager: LocationsManager? = nil,
        navigationService: NavigationService? = nil,
        conversationHistory: [ConversationMessage] = []
    ) async -> String {
        print("📋 buildContextForQuestion called with query: '\(query)'")
        var context = ""
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        // Detect what the user is asking about (smart filtering)
        let (queryIntents, detectedDateRange) = detectQueryIntent(query: query)

        // Detect the date range the user is asking about
        let dateRange = detectDateRange(in: query, from: currentDate)

        // Add current date/time context first (ALWAYS include this)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        context += "Current date/time: \(dateFormatter.string(from: currentDate)) at \(timeFormatter.string(from: currentDate))\n"
        context += "Date range user asked about: \(detectedDateRange)\n"

        // Add template hint if this is a specific query type
        let templateHint = getTemplateHintForIntent(queryIntents)
        if !templateHint.isEmpty {
            context += "IMPORTANT: \(templateHint)\n"
        }
        context += "\n"

        // Add weather data only if user asked about weather
        if queryIntents.contains("weather"), let weatherService = weatherService, let weatherData = weatherService.weatherData {
            context += "=== WEATHER ===\n"
            context += "Location: \(weatherData.locationName)\n"
            context += "Current: \(weatherData.temperature)°C, \(weatherData.description)\n"
            context += "Sunrise: \(timeFormatter.string(from: weatherData.sunrise))\n"
            context += "Sunset: \(timeFormatter.string(from: weatherData.sunset))\n"

            if !weatherData.dailyForecasts.isEmpty {
                context += "6-Day Forecast:\n"
                for forecast in weatherData.dailyForecasts {
                    context += "- \(forecast.day): \(forecast.temperature)°C\n"
                }
            }
            context += "\n"
        }

        // Add navigation destinations only if user asked about ETAs or travel time
        if queryIntents.contains("navigation"), let navigationService = navigationService {
            context += "=== NAVIGATION DESTINATIONS ===\n"
            if let location1ETA = navigationService.location1ETA {
                context += "Location 1: \(location1ETA) away\n"
            }
            if let location2ETA = navigationService.location2ETA {
                context += "Location 2: \(location2ETA) away\n"
            }
            if let location3ETA = navigationService.location3ETA {
                context += "Location 3: \(location3ETA) away\n"
            }
            context += "\n"
        }

        // Add saved locations only if user asked about locations
        if queryIntents.contains("locations"), let locationsManager = locationsManager, !locationsManager.savedPlaces.isEmpty {
            context += "=== SAVED LOCATIONS ===\n"
            context += "Available filters: country, city, category (folder), distance, rating\n\n"

            for place in locationsManager.savedPlaces.sorted(by: { $0.dateCreated > $1.dateCreated }) {
                let displayName = place.customName ?? place.name
                context += "- \(displayName)\n"
                context += "  Category: \(place.category)\n"
                context += "  Address: \(place.address)\n"
                if let city = place.city {
                    context += "  City: \(city)\n"
                }
                if let country = place.country {
                    context += "  Country: \(country)\n"
                }
                if let rating = place.rating {
                    context += "  Rating: \(String(format: "%.1f", rating))/5\n"
                }
                if let phone = place.phone {
                    context += "  Phone: \(phone)\n"
                }
                context += "\n"
            }

            // Add available cities and countries for filtering
            let cities = locationsManager.getCities()
            let countries = locationsManager.countries
            if !cities.isEmpty || !countries.isEmpty {
                context += "Available Filters:\n"
                if !countries.isEmpty {
                    context += "Countries: \(countries.sorted().joined(separator: ", "))\n"
                }
                if !cities.isEmpty {
                    context += "Cities: \(cities.sorted().joined(separator: ", "))\n"
                }
                context += "\n"
            }
        }

        // Add tasks/events only if user asked about events
        if queryIntents.contains("events") {
            let allTasks = taskManager.tasks.values.flatMap { $0 }
            let filteredTasks = filterTasksByDateRange(allTasks, range: dateRange, currentDate: currentDate)
            if !filteredTasks.isEmpty {
                context += "=== TASKS/EVENTS ===\n"
                for task in filteredTasks.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let status = task.isCompleted ? "✓" : "○"
                    let dateStr = task.targetDate.map { dateFormatter.string(from: $0) } ?? "No date"
                    let timeStr = task.scheduledTime.map { formatTime(date: $0) } ?? "All day"
                    context += "- \(status) \(task.title) | \(dateStr) at \(timeStr) | \(task.description ?? "")\n"
                }
                context += "\n"
            } else if !allTasks.isEmpty {
                context += "=== TASKS/EVENTS ===\n"
                context += "No tasks/events found for the requested timeframe (\(detectedDateRange)).\n\n"
            }
        }

        // Add notes only if user asked about notes
        if queryIntents.contains("notes"), !notesManager.notes.isEmpty {
            context += "=== NOTES ===\n"
            // Include folder information if available
            if !notesManager.folders.isEmpty {
                context += "Available Folders: \(notesManager.folders.map { $0.name }.sorted().joined(separator: ", "))\n\n"
            }
            for note in notesManager.notes.sorted(by: { $0.dateModified > $1.dateModified }) {
                let folderInfo = note.folderId.flatMap { id in notesManager.folders.first(where: { $0.id == id })?.name } ?? "Uncategorized"
                context += "Note: \(note.title) [Folder: \(folderInfo)]\nContent: \(note.content)\n---\n"
            }
            context += "\n"
        }

        // Add emails only if user asked about emails
        if queryIntents.contains("emails"), !emailService.inboxEmails.isEmpty {
            context += "=== EMAILS ===\n"
            // Filter emails by date if user specified a date range
            var emailsToShow = emailService.inboxEmails
            if detectedDateRange != "default" {
                emailsToShow = filterEmailsByDateRange(emailService.inboxEmails, range: dateRange, currentDate: currentDate)
            }

            if !emailsToShow.isEmpty {
                for email in emailsToShow.sorted(by: { $0.timestamp > $1.timestamp }) {
                    let unreadMarker = email.isRead ? "[Read]" : "[Unread]"
                    context += "\(unreadMarker) From: \(email.sender.displayName)\nSubject: \(email.subject)\nDate: \(dateFormatter.string(from: email.timestamp))\nBody: \(email.body ?? "")\n---\n"
                }
            } else {
                context += "No emails found for the requested timeframe (\(detectedDateRange)).\n"
            }
            context += "\n"
        }

        // Add receipts only if user asked about receipts, expenses, spending, or purchases
        if queryIntents.contains("receipts") {
            let allNotes = notesManager.notes

            // Helper function to check if a folder is under the Receipts hierarchy
            func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
                guard let folderId = folderId else { return false }

                // Find the folder
                guard let folder = notesManager.folders.first(where: { $0.id == folderId }) else { return false }

                // Check if it's the Receipts folder itself
                if folder.name == "Receipts" {
                    return true
                }

                // Check if parent is Receipts folder (for year/month folders)
                if let parentId = folder.parentFolderId {
                    if let parentFolder = notesManager.folders.first(where: { $0.id == parentId }) {
                        if parentFolder.name == "Receipts" {
                            return true
                        }
                        // Check grandparent (for month under year)
                        if let grandparentId = parentFolder.parentFolderId {
                            if let grandparentFolder = notesManager.folders.first(where: { $0.id == grandparentId }) {
                                if grandparentFolder.name == "Receipts" {
                                    return true
                                }
                            }
                        }
                    }
                }

                return false
            }

            // Filter to only receipts (notes in Receipts folder hierarchy)
            let receiptNotes = allNotes.filter { note in
                isUnderReceiptsFolderHierarchy(folderId: note.folderId)
            }

            if !receiptNotes.isEmpty {
                context += "=== RECEIPTS/EXPENSES ===\n"
                // Filter receipts by date if user specified a date range
                var receiptsToShow = receiptNotes
                if detectedDateRange != "default" {
                    receiptsToShow = receiptsToShow.filter { note in
                        let noteStartOfDay = dateFormatter.calendar.startOfDay(for: note.dateCreated)
                        return noteStartOfDay >= dateRange.start && noteStartOfDay < dateRange.end
                    }
                }

                if !receiptsToShow.isEmpty {
                    var totalAmount: Double = 0
                    var receiptDetails: [String] = []

                    for receipt in receiptsToShow.sorted(by: { $0.dateCreated > $1.dateCreated }) {
                        let dateStr = dateFormatter.string(from: receipt.dateCreated)
                        // Try to extract amount from receipt title or content
                        let contentPreview = String(receipt.content.prefix(150))

                        // Try to extract dollar amount using regex
                        let amountPattern = "\\$([0-9]+\\.?[0-9]*)"
                        if let regex = try? NSRegularExpression(pattern: amountPattern) {
                            let range = NSRange(receipt.content.startIndex..<receipt.content.endIndex, in: receipt.content)
                            if let match = regex.firstMatch(in: receipt.content, range: range),
                               let amountRange = Range(match.range(at: 1), in: receipt.content) {
                                if let amount = Double(receipt.content[amountRange]) {
                                    totalAmount += amount
                                    receiptDetails.append("• \(receipt.title) - $\(String(format: "%.2f", amount)) on \(dateStr)")
                                } else {
                                    receiptDetails.append("• \(receipt.title) on \(dateStr)")
                                }
                            } else {
                                receiptDetails.append("• \(receipt.title) on \(dateStr)")
                            }
                        } else {
                            receiptDetails.append("• \(receipt.title) on \(dateStr)")
                        }
                    }

                    // Add receipts with total
                    for detail in receiptDetails {
                        context += detail + "\n"
                    }
                    if totalAmount > 0 {
                        context += "\nTotal spent: $\(String(format: "%.2f", totalAmount))\n"
                    }
                } else {
                    context += "No receipts found for the requested timeframe (\(detectedDateRange)).\n"
                }
                context += "\n"
            } else {
                if !allNotes.isEmpty {
                    context += "=== RECEIPTS/EXPENSES ===\n"
                    context += "No receipts found in the app.\n\n"
                }
            }
        }

        // Add semantic enrichment: find related content even without explicit keywords
        // (skipped for simple queries for better performance)
        let allEvents = taskManager.tasks.values.flatMap { $0 }
        let semanticEnrichment = try? await enrichContextWithSemanticMatches(
            query: query,
            notes: notesManager.notes,
            emails: emailService.inboxEmails,
            events: allEvents,
            queryIntents: queryIntents
        )
        if let enrichment = semanticEnrichment, !enrichment.isEmpty {
            context += enrichment
        }

        return context.isEmpty ? "No data available in the app." : context
    }

    // MARK: - New Intelligent Context Building (Metadata-First Approach)

    /// Extract date from receipt text (e.g., "November 08, 2025" or "Nov 08, 2025")
    private func extractDateFromReceiptText(_ text: String) -> Date? {
        let dateFormatter = DateFormatter()

        // Try full month names first (e.g., "November 08, 2025")
        dateFormatter.dateFormat = "MMMM dd, yyyy"
        if let date = dateFormatter.date(from: text) {
            return date
        }

        // Try abbreviated month names (e.g., "Nov 08, 2025")
        dateFormatter.dateFormat = "MMM dd, yyyy"
        if let date = dateFormatter.date(from: text) {
            return date
        }

        // Try with dashes (e.g., "November 08-2025" or "November-08-2025")
        dateFormatter.dateFormat = "MMMM dd-yyyy"
        if let date = dateFormatter.date(from: text) {
            return date
        }

        // Try slash format (e.g., "11/08/2025" or "2025/11/08")
        dateFormatter.dateFormat = "MM/dd/yyyy"
        if let date = dateFormatter.date(from: text) {
            return date
        }

        dateFormatter.dateFormat = "yyyy/MM/dd"
        if let date = dateFormatter.date(from: text) {
            return date
        }

        return nil
    }

    /// Build context for expense queries by directly fetching all receipts
    /// Bypasses LLM ID selection (which corrupts UUIDs) for expense queries
    @MainActor
    private func buildExpenseQueryContext(
        query: String,
        notesManager: NotesManager,
        currentDate: Date,
        dateFormatter: DateFormatter,
        timeFormatter: DateFormatter
    ) async -> String {
        var context = ""
        context += "Current date/time: \(dateFormatter.string(from: currentDate)) at \(timeFormatter.string(from: currentDate))\n\n"

        // Add critical instruction at the top
        context += "⚠️ CRITICAL INSTRUCTION FOR EXPENSE SUMMARY:\n"
        context += "Look at the **Summary:** section at the bottom for the final totals.\n"
        context += "DO NOT add up the individual receipt amounts yourself.\n"
        context += "The summary already has the correct TOTAL SPENDING calculated.\n"
        context += "Simply use and report the **Total Spending** value from the summary.\n\n"

        // Parse date range from query
        let lowerQuery = query.lowercased()
        let calendar = Calendar.current

        var startDate: Date
        var endDate: Date

        // Determine date range
        if lowerQuery.contains("this month") {
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("last month") {
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: currentDate)!
            let components = calendar.dateComponents([.year, .month], from: lastMonth)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("this year") {
            let components = calendar.dateComponents([.year], from: currentDate)
            startDate = calendar.date(from: DateComponents(year: components.year, month: 1, day: 1))!
            endDate = calendar.date(from: DateComponents(year: (components.year ?? 0) + 1, month: 1, day: 1))!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("today") {
            startDate = calendar.startOfDay(for: currentDate)
            endDate = calendar.date(byAdding: DateComponents(day: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else {
            // Default to this month
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        }

        print("💰 Expense query date range: \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))")

        // Get ALL receipts for the date range - no filtering, no ID selection
        let receiptsFolder = notesManager.getOrCreateReceiptsFolder()

        // Helper to check if note is in receipts hierarchy
        func isInReceiptsFolderHierarchy(_ note: Note) -> Bool {
            var currentFolderId = note.folderId
            while let folderId = currentFolderId {
                if folderId == receiptsFolder { return true }
                if let folder = notesManager.folders.first(where: { $0.id == folderId }) {
                    currentFolderId = folder.parentFolderId
                } else {
                    break
                }
            }
            return false
        }

        // Get all receipts in date range
        // IMPORTANT: Filter by actual receipt transaction date, not note.dateModified
        // (Notes might be modified after creation, e.g., when reorganizing folders)
        // Try to extract date from receipt title/content first, fall back to dateCreated

        let dateRangeStart = calendar.startOfDay(for: startDate)
        let dateRangeEnd = calendar.date(byAdding: DateComponents(day: 1), to: calendar.startOfDay(for: endDate))!

        let receiptsInRange = notesManager.notes.filter { note in
            guard isInReceiptsFolderHierarchy(note) else { return false }

            // Extract transaction date from receipt
            var transactionDate = note.dateCreated

            // Try to extract date from title (e.g., "Store Name - November 08, 2025")
            if let extractedDate = extractDateFromReceiptText(note.title) {
                transactionDate = extractedDate
            } else if let extractedDate = extractDateFromReceiptText(note.content) {
                transactionDate = extractedDate
            }

            return transactionDate >= dateRangeStart && transactionDate < dateRangeEnd
        }.sorted { note1, note2 in
            // Extract dates for sorting
            let date1 = extractDateFromReceiptText(note1.title) ?? extractDateFromReceiptText(note1.content) ?? note1.dateCreated
            let date2 = extractDateFromReceiptText(note2.title) ?? extractDateFromReceiptText(note2.content) ?? note2.dateCreated
            return date1 > date2
        }

        print("💰 Found \(receiptsInRange.count) receipts in date range")
        print("💰 Date filter: \(dateFormatter.string(from: startDate)) to \(dateFormatter.string(from: endDate))")

        // Fetch recurring expenses for this period
        var recurringTotal: Double = 0
        var recurringExpenses: [RecurringExpense] = []
        do {
            let activeRecurring = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
            recurringExpenses = activeRecurring.filter { expense in
                // Include if expense occurs during this period
                expense.nextOccurrence >= startDate && expense.startDate <= endDate
            }
            for expense in recurringExpenses {
                recurringTotal += Double(truncating: expense.amount as NSDecimalNumber)
            }
            print("💰 Found \(recurringExpenses.count) recurring expenses in date range")
        } catch {
            print("⚠️ Could not fetch recurring expenses: \(error.localizedDescription)")
        }

        // Format receipts for LLM
        context += "=== EXPENSES FOR REQUESTED PERIOD ===\n\n"

        // Add recurring expenses first
        if !recurringExpenses.isEmpty {
            context += "💳 **RECURRING EXPENSES:**\n"
            for expense in recurringExpenses.sorted(by: { $0.nextOccurrence < $1.nextOccurrence }) {
                context += "   • \(expense.title): \(expense.formattedAmount) (\(expense.frequency.rawValue))\n"
            }
            context += "\n"
        }

        // Then add one-time receipts
        if !receiptsInRange.isEmpty {
            var totalAmount: Double = 0
            var amountDetails: [(title: String, amount: Double)] = []
            var merchantBreakdown: [String: (count: Int, total: Double)] = [:]

            // Calculate totals and build merchant breakdown
            for note in receiptsInRange {
                let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                totalAmount += amount
                amountDetails.append((title: note.title, amount: amount))

                // Extract merchant name
                let merchant = note.title.split(separator: "-").first.map(String.init) ?? note.title
                if merchantBreakdown[merchant] != nil {
                    merchantBreakdown[merchant]?.count += 1
                    merchantBreakdown[merchant]?.total += amount
                } else {
                    merchantBreakdown[merchant] = (count: 1, total: amount)
                }
            }

            // Only list individual receipts if there are 10 or fewer
            // For larger lists, just show summary (avoids LLM picking and choosing which to list)
            if receiptsInRange.count <= 10 {
                context += "**All Receipts:**\n\n"
                for (index, note) in receiptsInRange.enumerated() {
                    let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                    let dateStr = dateFormatter.string(from: note.dateModified)
                    context += "\(index + 1). \(note.title)\n"
                    context += "   Amount: $\(String(format: "%.2f", amount))\n"
                    context += "   Date: \(dateStr)\n"
                    context += "   Details: \(String(note.content.prefix(100)))\n\n"
                }
            } else {
                context += "Found \(receiptsInRange.count) receipts. Showing breakdown by merchant:\n\n"
            }

            // Debug logging for each receipt
            print("💰 Receipt Amounts Extracted:")
            for (title, amount) in amountDetails {
                print("   - \(title): $\(String(format: "%.2f", amount))")
            }
            print("💰 TOTAL CALCULATED: $\(String(format: "%.2f", totalAmount))")

            // Summary - Make it stand out with visual emphasis
            let avgAmount = totalAmount / Double(receiptsInRange.count)
            let combinedTotal = totalAmount + recurringTotal
            context += "\n════════════════════════════════════════════════════════\n"
            context += "🔍 **FINAL SUMMARY** - USE THIS FOR YOUR ANSWER:\n"
            context += "════════════════════════════════════════════════════════\n"
            context += "💰 **ONE-TIME EXPENSES: $\(String(format: "%.2f", totalAmount))**\n"
            if recurringTotal > 0 {
                context += "💳 **RECURRING EXPENSES: $\(String(format: "%.2f", recurringTotal))**\n"
                context += "💵 **TOTAL SPENDING: $\(String(format: "%.2f", combinedTotal))** ← THIS IS THE ANSWER\n"
            } else {
                context += "💰 **TOTAL SPENDING: $\(String(format: "%.2f", totalAmount))** ← THIS IS THE ANSWER\n"
            }
            context += "📊 Number of One-Time Transactions: \(receiptsInRange.count)\n"
            context += "📊 Number of Recurring Expenses: \(recurringExpenses.count)\n"
            context += "📈 Average per One-Time Transaction: $\(String(format: "%.2f", avgAmount))\n"
            context += "📌 Highest Transaction: $\(String(format: "%.2f", receiptsInRange.map { CurrencyParser.extractAmount(from: $0.content.isEmpty ? $0.title : $0.content) }.max() ?? 0))\n"
            context += "📌 Lowest Transaction: $\(String(format: "%.2f", receiptsInRange.map { CurrencyParser.extractAmount(from: $0.content.isEmpty ? $0.title : $0.content) }.min() ?? 0))\n"

            // Show merchant breakdown for large receipt lists
            if receiptsInRange.count > 10 && merchantBreakdown.count > 1 {
                context += "\n📍 **Spending by Merchant:**\n"
                for (merchant, data) in merchantBreakdown.sorted(by: { $0.value.total > $1.value.total }) {
                    context += "   - \(merchant): \(data.count) transaction(s), $\(String(format: "%.2f", data.total))\n"
                }
            }

            context += "════════════════════════════════════════════════════════\n"
        } else {
            // No receipts, but might have recurring expenses
            if !recurringExpenses.isEmpty {
                context += "No one-time receipts found, but you have recurring expenses:\n\n"
                context += "💳 **RECURRING EXPENSES:**\n"
                for expense in recurringExpenses.sorted(by: { $0.nextOccurrence < $1.nextOccurrence }) {
                    context += "   • \(expense.title): \(expense.formattedAmount) (\(expense.frequency.rawValue))\n"
                }
                context += "\n════════════════════════════════════════════════════════\n"
                context += "💳 **TOTAL RECURRING EXPENSES: $\(String(format: "%.2f", recurringTotal))** ← THIS IS THE ANSWER\n"
                context += "════════════════════════════════════════════════════════\n"
            } else {
                context += "No expenses found for the requested period.\n"
            }
        }

        return context
    }

    // MARK: - Smart Expense Query Analysis with Semantic Understanding

    /// Use LLM to intelligently extract product intent from user query
    /// This removes the need for hardcoded keywords
    /// Examples:
    /// - "how many times did I buy pizza?" → "pizza"
    /// - "show me my Starbucks spending" → "Starbucks"
    /// - "did I spend more on coffee or tea?" → ["coffee", "tea"]
    private func extractProductIntentFromQuery(_ query: String) async -> [String] {
        let prompt = """
        The user asked: "\(query)"

        Extract ONLY the products or merchants the user is asking about.
        Return a comma-separated list of product/merchant names.
        Return ONLY the products/merchants, nothing else.

        Examples:
        - "how many times did I buy pizza?" → pizza
        - "show me Starbucks spending" → Starbucks
        - "did I spend more on coffee or burgers?" → coffee, burgers
        - "how much on groceries this month?" → groceries

        If the query doesn't mention a specific product (e.g., "how much did I spend?"), return: GENERAL
        """

        do {
            guard let url = URL(string: baseURL) else { return [] }

            let requestBody = [
                "model": "gpt-4o-mini",
                "messages": [[
                    "role": "user",
                    "content": prompt
                ]],
                "temperature": 0.3,
                "max_tokens": 100
            ] as [String: Any]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)

            if let content = response.choices.first?.message.content {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "GENERAL" {
                    return []
                }
                // Parse comma-separated products
                let products = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                print("🎯 Extracted product intent: \(products)")
                return products
            }
        } catch {
            print("❌ Error extracting product intent: \(error)")
        }

        return []
    }

    /// Calculate semantic similarity between two texts using embeddings
    /// Returns score between 0.0 and 1.0
    private func semanticSimilarity(text1: String, text2: String) async -> Double {
        do {
            let embedding1 = try await getEmbedding(for: text1)
            let embedding2 = try await getEmbedding(for: text2)

            // Cosine similarity
            let dotProduct = zip(embedding1, embedding2).map(*).reduce(0, +)
            let magnitude1 = sqrt(embedding1.map { $0 * $0 }.reduce(0, +))
            let magnitude2 = sqrt(embedding2.map { $0 * $0 }.reduce(0, +))

            guard magnitude1 > 0, magnitude2 > 0 else { return 0.0 }

            return Double(dotProduct / (magnitude1 * magnitude2))
        } catch {
            print("❌ Error calculating semantic similarity: \(error)")
            return 0.0
        }
    }

    /// Analyze expense query to extract intent and determine query type
    /// Uses LLM to extract product intent (no hardcoded keywords!)
    /// Examples:
    /// - "how many times did I buy pizza?" → countByProduct with products ["pizza"]
    /// - "how much did I spend on coffee?" → amountByProduct with products ["coffee"]
    /// - "how much did I spend?" → general with no products
    private func parseExpenseQuery(_ query: String) async -> ExpenseQuery {
        let lowerQuery = query.lowercased()
        var queryType: ExpenseQuery.QueryType = .general

        // Use LLM to extract product intent (no hardcoding!)
        let products = await extractProductIntentFromQuery(query)

        // Determine query type based on question structure
        if !products.isEmpty {
            if lowerQuery.contains("how many") || lowerQuery.contains("times") || lowerQuery.contains("count") {
                queryType = .countByProduct
            } else if lowerQuery.contains("how much") || lowerQuery.contains("spent") || lowerQuery.contains("cost") {
                queryType = .amountByProduct
            } else if lowerQuery.contains("show") || lowerQuery.contains("list") {
                queryType = .listByProduct
            } else {
                queryType = .countByProduct  // Default for product queries
            }
        }

        // Parse date range (same logic as buildExpenseQueryContext)
        let calendar = Calendar.current
        let currentDate = Date()

        var startDate: Date
        var endDate: Date

        if lowerQuery.contains("this month") {
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("last month") {
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: currentDate)!
            let components = calendar.dateComponents([.year, .month], from: lastMonth)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("two months") {
            let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: currentDate)!
            let components = calendar.dateComponents([.year, .month], from: twoMonthsAgo)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 2), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("this year") {
            let components = calendar.dateComponents([.year], from: currentDate)
            startDate = calendar.date(from: DateComponents(year: components.year, month: 1, day: 1))!
            endDate = calendar.date(from: DateComponents(year: (components.year ?? 0) + 1, month: 1, day: 1))!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else if lowerQuery.contains("today") {
            startDate = calendar.startOfDay(for: currentDate)
            endDate = calendar.date(byAdding: DateComponents(day: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        } else {
            // Default to this month
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            startDate = calendar.date(from: components)!
            endDate = calendar.date(byAdding: DateComponents(month: 1), to: startDate)!
            endDate = calendar.date(byAdding: DateComponents(second: -1), to: endDate)!
        }

        print("🔍 Expense Query Analysis:")
        print("   Type: \(queryType)")
        print("   Products: \(products)")
        print("   Has Filters: \(!products.isEmpty)")

        return ExpenseQuery(
            type: queryType,
            keywords: products,
            dateRange: (startDate, endDate),
            hasFilters: !products.isEmpty
        )
    }

    /// Filter receipts by semantic similarity to product keywords
    /// Uses embeddings to find semantically similar receipts (no hardcoded keywords!)
    /// This handles misspellings, variations, and new merchants automatically
    /// Example: "pizza" matches Domino's, JP's Pizzeria, Pizza Hut, etc.
    private func filterReceiptsBySemanticSimilarity(
        _ receipts: [Note],
        products: [String],
        similarityThreshold: Double = 0.45
    ) async -> [Note] {
        guard !products.isEmpty else { return receipts }

        var filteredReceipts: [Note] = []

        for receipt in receipts {
            // Extract merchant name from receipt title
            // Usually format is "Merchant Name - Date" so take everything before first dash
            let merchantName = receipt.title.split(separator: "-").first.map(String.init) ?? receipt.title

            // Also search in receipt content in case merchant isn't in title
            let searchTexts = [merchantName, receipt.content]

            var maxSimilarity: Double = 0.0

            // Find the best similarity score across all products and search texts
            for product in products {
                for searchText in searchTexts {
                    let similarity = await semanticSimilarity(text1: product, text2: searchText.trimmingCharacters(in: .whitespaces))
                    maxSimilarity = max(maxSimilarity, similarity)

                    // Log the best match for this product
                    if similarity > maxSimilarity - 0.01 { // Only log top results
                        print("   Similarity: '\(product)' vs '\(merchantName)' = \(String(format: "%.2f", similarity))")
                    }
                }
            }

            // Include receipt if it exceeds similarity threshold
            if maxSimilarity >= similarityThreshold {
                print("   ✅ MATCH: '\(merchantName)' (score: \(String(format: "%.2f", maxSimilarity)))")
                filteredReceipts.append(receipt)
            }
        }

        print("🔍 Semantic filtering complete: Found \(filteredReceipts.count) semantically similar receipts (threshold: \(similarityThreshold))")
        return filteredReceipts
    }

    /// Build smart expense context with filtered receipts and detailed analysis
    /// Uses LLM to extract product intent + semantic embeddings to find matches
    private func buildSmartExpenseContext(
        query: String,
        notesManager: NotesManager,
        dateFormatter: DateFormatter,
        timeFormatter: DateFormatter
    ) async -> String {
        // LLM extracts what product the user is asking about (no hardcoded keywords!)
        let expenseQuery = await parseExpenseQuery(query)

        // If no filters detected, use the standard context
        if !expenseQuery.hasFilters {
            return await buildExpenseQueryContext(
                query: query,
                notesManager: notesManager,
                currentDate: Date(),
                dateFormatter: dateFormatter,
                timeFormatter: timeFormatter
            )
        }

        var context = ""
        context += "Current date/time: \(dateFormatter.string(from: Date())) at \(timeFormatter.string(from: Date()))\n\n"

        // Explain what filtering is being done
        context += "🔍 SMART SEMANTIC SEARCH:\n"
        context += "LLM extracted product intent: \(expenseQuery.keywords.joined(separator: ", "))\n"
        context += "Using embeddings to find semantically similar receipts (no hardcoded keywords!)\n"
        context += "Date range: \(dateFormatter.string(from: expenseQuery.dateRange.start)) to \(dateFormatter.string(from: expenseQuery.dateRange.end))\n\n"

        // Include recurring expenses in the date range
        do {
            let activeRecurring = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
            let recurringInRange = activeRecurring.filter { expense in
                // Check if recurring expense occurs during the query date range
                expense.nextOccurrence >= expenseQuery.dateRange.start && expense.startDate <= expenseQuery.dateRange.end
            }

            if !recurringInRange.isEmpty {
                context += "💳 RECURRING EXPENSES IN DATE RANGE:\n"
                var recurringTotal: Double = 0
                for expense in recurringInRange.sorted(by: { $0.nextOccurrence < $1.nextOccurrence }) {
                    let amountDouble = Double(truncating: expense.amount as NSDecimalNumber)
                    recurringTotal += amountDouble
                    context += "• \(expense.title) - \(expense.formattedAmount) (\(expense.frequency.rawValue))\n"
                }
                context += "Subtotal (recurring): $\(String(format: "%.2f", recurringTotal))\n\n"
            }
        } catch {
            print("⚠️ Could not fetch recurring expenses: \(error.localizedDescription)")
        }

        // Get all receipts in the date range
        let receiptsFolder = notesManager.getOrCreateReceiptsFolder()

        func isInReceiptsFolderHierarchy(_ note: Note) -> Bool {
            var currentFolderId = note.folderId
            while let folderId = currentFolderId {
                if folderId == receiptsFolder { return true }
                if let folder = notesManager.folders.first(where: { $0.id == folderId }) {
                    currentFolderId = folder.parentFolderId
                } else {
                    break
                }
            }
            return false
        }

        let calendar = Calendar.current
        let dateRangeStart = calendar.startOfDay(for: expenseQuery.dateRange.start)
        let dateRangeEnd = calendar.date(byAdding: DateComponents(day: 1), to: calendar.startOfDay(for: expenseQuery.dateRange.end))!

        // Get all receipts in date range, then filter by semantic similarity
        let allReceiptsInRange = notesManager.notes.filter { note in
            guard isInReceiptsFolderHierarchy(note) else { return false }
            var transactionDate = note.dateCreated
            if let extractedDate = extractDateFromReceiptText(note.title) {
                transactionDate = extractedDate
            } else if let extractedDate = extractDateFromReceiptText(note.content) {
                transactionDate = extractedDate
            }
            return transactionDate >= dateRangeStart && transactionDate < dateRangeEnd
        }

        print("📊 Semantic filtering: comparing \(expenseQuery.keywords) against \(allReceiptsInRange.count) receipts...")
        let filteredReceipts = await filterReceiptsBySemanticSimilarity(allReceiptsInRange, products: expenseQuery.keywords)
            .sorted { note1, note2 in
                let date1 = extractDateFromReceiptText(note1.title) ?? extractDateFromReceiptText(note1.content) ?? note1.dateCreated
                let date2 = extractDateFromReceiptText(note2.title) ?? extractDateFromReceiptText(note2.content) ?? note2.dateCreated
                return date1 > date2
            }

        print("🔍 Filtered Results: Found \(filteredReceipts.count) matching receipts (out of \(allReceiptsInRange.count) total)")

        if !filteredReceipts.isEmpty {
            var totalAmount: Double = 0
            var merchantBreakdown: [String: (count: Int, total: Double)] = [:]

            // Calculate totals and merchant breakdown
            for note in filteredReceipts {
                let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                totalAmount += amount

                // Extract merchant name (usually first part of title)
                let merchant = note.title.split(separator: "-").first.map(String.init) ?? note.title

                if merchantBreakdown[merchant] != nil {
                    merchantBreakdown[merchant]?.count += 1
                    merchantBreakdown[merchant]?.total += amount
                } else {
                    merchantBreakdown[merchant] = (count: 1, total: amount)
                }
            }

            // For product-specific queries, list all matching receipts
            // For general queries, just show summary (avoids LLM picking and choosing which to list)
            if expenseQuery.hasFilters && filteredReceipts.count <= 20 {
                context += "=== MATCHING RECEIPTS ===\n\n"
                for (index, note) in filteredReceipts.enumerated() {
                    let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                    let dateStr = dateFormatter.string(from: note.dateModified)
                    context += "\(index + 1). **\(note.title)** - **$\(String(format: "%.2f", amount))**\n"
                    context += "   Date: \(dateStr)\n"
                    context += "   Details: \(String(note.content.prefix(150)))\n\n"
                }
            } else if expenseQuery.hasFilters && filteredReceipts.count > 20 {
                // Too many receipts, just show summary + breakdown
                context += "Found \(filteredReceipts.count) matching receipts. Showing summary breakdown:\n\n"
            }

            // Summary with breakdown by merchant
            let avgAmount = totalAmount / Double(filteredReceipts.count)
            context += "\n════════════════════════════════════════════════════════\n"
            context += "🔍 **FILTERED SUMMARY** - USE THIS FOR YOUR ANSWER:\n"
            context += "════════════════════════════════════════════════════════\n"
            context += "💰 **TOTAL SPENDING ON \(expenseQuery.keywords.joined(separator: "/").uppercased()): $\(String(format: "%.2f", totalAmount))** ← THIS IS THE ANSWER\n"
            context += "📊 **Total Purchases: \(filteredReceipts.count) times**\n"
            context += "📈 Average per Transaction: $\(String(format: "%.2f", avgAmount))\n"

            if merchantBreakdown.count > 1 {
                context += "\n📍 **Breakdown by Merchant:**\n"
                for (merchant, data) in merchantBreakdown.sorted(by: { $0.value.total > $1.value.total }) {
                    context += "   - \(merchant): \(data.count) time(s), $\(String(format: "%.2f", data.total))\n"
                }
            }

            context += "════════════════════════════════════════════════════════\n"
        } else {
            context += "❌ No receipts found matching '\(expenseQuery.keywords.joined(separator: ", "))'.\n"
            context += "Total receipts in date range: \(allReceiptsInRange.count)\n"
        }

        return context
    }

    /// NEW APPROACH: Build context by letting LLM intelligently filter metadata
    /// Instead of pre-filtering in backend, send all metadata to LLM
    /// LLM identifies which items are relevant and we fetch only those
    @MainActor
    func buildSmartContextForQuestion(
        query: String,
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        locationsManager: LocationsManager? = nil,
        weatherService: WeatherService? = nil,
        navigationService: NavigationService? = nil
    ) async -> String {
        print("🧠 buildSmartContextForQuestion with query: '\(query)'\n⚡ Using unified metadata approach (no keyword routing)")
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        var context = ""

        // Add current context
        context += "Current date/time: \(dateFormatter.string(from: currentDate)) at \(timeFormatter.string(from: currentDate))\n\n"

        // NO MORE KEYWORD ROUTING - Just always build complete metadata
        print("📊 Building complete metadata for all data types...")

        // Step 1: Compile lightweight metadata from all data sources
        let allMetadata = await MetadataBuilderService.buildAppMetadata(
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            locationsManager: locationsManager ?? LocationsManager.shared
        )

        // Step 1.5: CRITICAL - Filter metadata by temporal bounds BEFORE LLM sees it
        // This ensures LLM only receives data from the requested time period
        let temporalFilter = TemporalDataFilterService.shared
        let dateBounds = temporalFilter.extractTemporalBoundsFromQuery(query)

        print("⏰ TEMPORAL FILTER: \(dateBounds.periodDescription)")
        print("   Start: \(ISO8601DateFormatter().string(from: dateBounds.start))")
        print("   End: \(ISO8601DateFormatter().string(from: dateBounds.end))")

        // Filter all metadata to only include relevant dates
        let filteredEvents = temporalFilter.filterEventsByDate(
            allMetadata.events,
            startDate: dateBounds.start,
            endDate: dateBounds.end
        )

        let filteredReceipts = temporalFilter.filterReceiptsByDate(
            allMetadata.receipts,
            startDate: dateBounds.start,
            endDate: dateBounds.end
        )

        let filteredNotes = temporalFilter.filterNotesByDate(
            allMetadata.notes,
            startDate: dateBounds.start,
            endDate: dateBounds.end
        )

        let filteredEmails = temporalFilter.filterEmailsByDate(
            allMetadata.emails,
            startDate: dateBounds.start,
            endDate: dateBounds.end
        )

        // Create temporally-filtered metadata
        let metadata = AppDataMetadata(
            receipts: filteredReceipts,
            events: filteredEvents,
            locations: allMetadata.locations,  // Locations don't have dates, keep all
            notes: filteredNotes,
            emails: filteredEmails,
            recurringExpenses: allMetadata.recurringExpenses  // Recurring expenses don't have dates, keep all
        )

        print("📊 METADATA AFTER TEMPORAL FILTER:")
        print("   Events: \(allMetadata.events.count) → \(filteredEvents.count)")
        print("   Receipts: \(allMetadata.receipts.count) → \(filteredReceipts.count)")
        print("   Notes: \(allMetadata.notes.count) → \(filteredNotes.count)")
        print("   Emails: \(allMetadata.emails.count) → \(filteredEmails.count)")

        // Step 2: Ask LLM which items are relevant based on FILTERED metadata
        let relevantItemIds = await getRelevantDataIds(
            forQuestion: query,
            metadata: metadata,
            currentDate: currentDate
        )

        // Step 3: Fetch full details of relevant items
        let fullData = await fetchFullDataForIds(
            relevantItemIds: relevantItemIds,
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            locationsManager: locationsManager ?? LocationsManager.shared
        )

        print("📥 Fetched full data: \(fullData.receipts.count) receipts, \(fullData.events.count) events, \(fullData.locations.count) locations, \(fullData.notes.count) notes, \(fullData.emails.count) emails")

        // Step 4: Add full data context to be sent to LLM
        context += "=== AVAILABLE DATA ===\n\n"

        // Add receipts
        if !fullData.receipts.isEmpty {
            context += "=== RECEIPTS/EXPENSES ===\n"
            for receipt in fullData.receipts.sorted(by: { $0.dateCreated > $1.dateCreated }) {
                let dateStr = dateFormatter.string(from: receipt.dateCreated)
                context += "• \(receipt.title) - \(dateStr)\n"
                // Include full content for detailed receipts (e.g., American Express statements with multiple transactions)
                context += receipt.content + "\n\n"
            }
            context += "\n"
        }

        // Add events
        if !fullData.events.isEmpty {
            context += "=== EVENTS ===\n"
            for event in fullData.events.sorted(by: { ($0.targetDate ?? Date()) > ($1.targetDate ?? Date()) }) {
                let dateStr = event.targetDate.map { dateFormatter.string(from: $0) } ?? "No date"
                let timeStr = event.scheduledTime.map { timeFormatter.string(from: $0) } ?? "All day"
                let status = event.isCompleted ? "✓ Completed" : "○ Pending"
                context += "• \(event.title) - \(dateStr) at \(timeStr) [\(status)]\n"
                if let description = event.description {
                    context += "  Description: \(description)\n"
                }
            }
            context += "\n"
        }

        // Add locations with visit statistics
        if !fullData.locations.isEmpty {
            context += "=== SAVED LOCATIONS WITH VISIT DATA ===\n"
            for location in fullData.locations {
                // Find corresponding metadata with visit stats
                if let locMeta = allMetadata.locations.first(where: { $0.id == location.id }) {
                    var locStr = "• \(location.displayName) - \(location.category)"
                    if let rating = location.userRating {
                        locStr += " (Rating: \(rating)/10)"
                    }
                    context += locStr + "\n"

                    // Add geofence visit tracking data
                    if let visitCount = locMeta.visitCount {
                        context += "  📊 Visits: \(visitCount) times"
                        if let lastVisited = locMeta.lastVisited {
                            let lastVisitStr = dateFormatter.string(from: lastVisited)
                            context += " | Last visited: \(lastVisitStr)"
                        }
                        context += "\n"

                        if let peakTimes = locMeta.peakVisitTimes, !peakTimes.isEmpty {
                            context += "  🕐 Peak times: \(peakTimes.joined(separator: ", "))\n"
                        }
                        if let visitDays = locMeta.mostVisitedDays, !visitDays.isEmpty {
                            context += "  📅 Most visited: \(visitDays.joined(separator: ", "))\n"
                        }
                        if let avgDuration = locMeta.averageVisitDuration {
                            let minutes = Int(avgDuration / 60)
                            if minutes > 0 {
                                context += "  ⏱️ Average visit: \(minutes) minutes\n"
                            }
                        }
                    } else {
                        context += "  ⓘ No geofence tracking data yet\n"
                    }

                    if let notes = location.userNotes {
                        context += "  📝 Notes: \(notes)\n"
                    }
                    context += "\n"
                } else {
                    // Fallback if metadata not found
                    var locStr = "• \(location.displayName) - \(location.category)"
                    if let rating = location.userRating {
                        locStr += " (Rating: \(rating)/10)"
                    }
                    context += locStr + "\n"
                    if let notes = location.userNotes {
                        context += "  Notes: \(notes)\n"
                    }
                }
            }
            context += "\n"
        }

        // Add notes
        if !fullData.notes.isEmpty {
            context += "=== NOTES ===\n"
            for note in fullData.notes.sorted(by: { $0.dateModified > $1.dateModified }) {
                context += "• \(note.title) - \(dateFormatter.string(from: note.dateModified))\n"
                context += "  \(note.content)\n\n"
            }
            context += "\n"
        }

        // Add emails
        if !fullData.emails.isEmpty {
            context += "=== EMAILS ===\n"
            for email in fullData.emails.sorted(by: { $0.timestamp > $1.timestamp }) {
                context += "• From: \(email.sender.displayName) - \(email.subject)\n"
                context += "  \(email.snippet)\n"
                context += "  \(timeFormatter.string(from: email.timestamp))\n\n"
            }
            context += "\n"
        }

        // Add weather if requested
        if query.lowercased().contains("weather"), let weatherService = weatherService, let weatherData = weatherService.weatherData {
            context += "=== WEATHER ===\n"
            context += "Location: \(weatherData.locationName)\n"
            context += "Current: \(weatherData.temperature)°C, \(weatherData.description)\n"
        }

        return context.isEmpty ? "No relevant data found for your question." : context
    }

    /// Ask LLM which items from metadata are relevant to the user's question
    @MainActor
    private func getRelevantDataIds(
        forQuestion question: String,
        metadata: AppDataMetadata,
        currentDate: Date
    ) async -> DataFilteringResponse {
        // Format metadata as human-readable text for better LLM understanding
        let metadataStr = formatMetadataForLLM(metadata, currentDate: currentDate)

        // Analyze user behavior patterns for predictive intelligence
        let userPatterns = UserPatternAnalysisService.analyzeUserPatterns(from: metadata)
        let patternsStr = formatUserPatterns(userPatterns)

        // Log what metadata is available
        print("📊 Metadata compiled: \(metadata.receipts.count) receipts, \(metadata.events.count) events, \(metadata.locations.count) locations, \(metadata.notes.count) notes, \(metadata.emails.count) emails")
        print("🎯 User patterns: \(userPatterns.topExpenseCategories.map { $0.category }.joined(separator: ", "))")

        let systemPrompt = """
        You are a data analyst. Given the user's question and metadata about available data, determine which specific items are relevant.

        CRITICAL: Use EXACT ID values from the metadata provided. Do NOT generate or modify IDs.

        Return ONLY a JSON object with these fields:
        {
            "receiptIds": ["exact-uuid-from-metadata"] or null,
            "eventIds": ["exact-uuid-from-metadata"] or null,
            "locationIds": ["exact-uuid-from-metadata"] or null,
            "noteIds": ["exact-uuid-from-metadata"] or null,
            "emailIds": ["exact-email-id-from-metadata"] or null,
            "reasoning": "Brief explanation of your selection"
        }

        IMPORTANT: All IDs must be copied EXACTLY as they appear in the metadata. Do not modify, shorten, or reconstruct IDs.

        Selection rules:
        - For date-based questions like "this week" or "this month", select items within that timeframe
        - For FUTURE date questions (tomorrow, next week, upcoming, next month):
          * CRITICAL: For recurring events, PROJECT which events will occur on the target date(s)
          * Check the event's weekday and recurrenceFrequency to determine if it will occur
          * Example: If user asks "How's my day tomorrow?" and tomorrow is Wednesday:
            - Find recurring events where weekday=Wednesday
            - Include those recurring events in your selection (the LLM will explain which ones will occur)
          * For weekly events: Check if the event's weekday matches the target date's weekday
          * For daily events: Include if the target date is before recurrenceEndDate
          * For other frequencies: Use the recurrenceFrequency pattern to calculate occurrences
          * Return the recurring event IDs - the LLM context will indicate which future dates they apply to
        - For location questions:
          * CRITICAL: Check BOTH address City AND Folder City fields to match requested location
          * If user asks for "locations in [city]" or "saved locations in [city]", return ALL locations where:
            - Address City matches [city] OR Folder City matches [city] (all categories)
          * If user asks for "restaurants in [city]" or "restaurants near [place]", return locations where:
            - (Address City matches [city] OR Folder City matches [city]) AND category is restaurant/food
          * If user asks for "cafes in [city]", return locations where:
            - (Address City matches [city] OR Folder City matches [city]) AND category is cafe/coffee
          * EXACT MATCHING: If user asks for "Hamilton", look for BOTH "City" and "Folder City" fields containing "Hamilton"
          * Return ALL matching locations, not just a few - if user asks for "all locations", return EVERY location in that city
          * Folder context is important: "Hamilton Restaurants" folder means user organized those restaurants for Hamilton, so treat as Hamilton locations
          * If query is ambiguous (e.g., "places in Hamilton"), include all location categories but filter by city (address or folder)
        - For expense questions, select receipts matching the category or date range
        - For event/activity questions (gym, workout, exercise, meeting, etc.):
          * CRITICAL: Only select events where isRecurring=true for recurring activity patterns
          * For "gym" queries: Find events with "gym" in the title and isRecurring=true
          * If multiple similar recurring events exist (e.g., "Go gym", "Go gym pussy"), select the SHORTEST/CLEANEST name
          * For FUTURE dates: Use recurrenceFrequency and weekday to project which events will occur
          * For PAST dates: Use completedDates field to count occurrences in the requested timeframe
          * Each date in completedDates represents one completion of that recurring event
        - For month/timeframe analysis:
          * For "this month": Only include completedDates that fall in the CURRENT month
          * For "last month": Only include completedDates that fall in the PREVIOUS month
          * Check each date in completedDates against the month specified in the question
          * Do NOT include events from October when user asks about November
        - Matching strategy:
          * First: Match by keyword (gym → contains "gym")
          * Second: Verify isRecurring=true (ignore one-time events)
          * Third: Filter to shortest name if multiple matches
          * Fourth: Use completedDates (past) or recurrence pattern (future) to verify relevance
        - Return null for categories with no relevant items
        - If query is ambiguous and you need clarification (e.g., user asks for "places" but doesn't specify category or location), include a note in "reasoning" like: "Query is ambiguous - user may want [option 1] or [option 2]. Selecting [most likely option]. Please ask for clarification if needed."
        """

        // Get current date components for better context
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        let currentMonth = components.month ?? 1
        let currentYear = components.year ?? 2025
        let lastMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let lastYear = currentMonth == 1 ? currentYear - 1 : currentYear

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        let currentMonthName = dateFormatter.string(from: currentDate)
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        let lastMonthName = dateFormatter.string(from: lastMonthDate)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        let tomorrowStr = dateFormatter.string(from: tomorrow)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: currentDate) ?? currentDate
        let nextWeekStr = dateFormatter.string(from: nextWeek)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        let nextMonthName = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: nextMonth)
        }()

        let prompt = """
        User's question: "\(question)"

        USER BEHAVIOR PATTERNS (what we know about this user):
        \(patternsStr)

        Available metadata:
        \(metadataStr)

        Current date: \(DateFormatter().string(from: currentDate))
        Current month: \(currentMonthName) (month \(currentMonth) of year \(currentYear))
        Last month: \(lastMonthName) (month \(lastMonth) of year \(lastYear))
        Tomorrow: \(tomorrowStr)
        Next week: \(nextWeekStr)
        Next month: \(nextMonthName)

        IMPORTANT: When user asks about "this month", they mean \(currentMonthName).
        When user asks about "last month", they mean \(lastMonthName).
        When user asks about "tomorrow", they mean \(tomorrowStr).
        When user asks about "next week", they mean around \(nextWeekStr).
        When user asks about "next month" or "upcoming month", they mean \(nextMonthName).

        USE USER PATTERNS TO MAKE SMARTER SELECTIONS:
        - If user asks about spending and their top category is 'food', prioritize food expenses
        - If user asks about activities and they do 'gym' frequently, prefer gym-related events
        - If user asks about restaurants and they like 'Italian', look for Italian restaurants
        - Use spending patterns to understand if amounts are typical or unusual
        - Use activity frequency to determine if "often" means their usual frequency

        Which items should I fetch and analyze?
        """

        guard let url = URL(string: baseURL) else {
            print("❌ Invalid OpenAI URL")
            return DataFilteringResponse(
                receiptIds: nil,
                eventIds: nil,
                locationIds: nil,
                noteIds: nil,
                emailIds: nil,
                reasoning: "Invalid API URL"
            )
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        do {
            let response = try await makeOpenAIRequest(url: url, requestBody: requestBody)

            print("🔍 Raw LLM response: \(response)")

            // Extract JSON from response (handle markdown-wrapped JSON)
            let cleanedResponse = extractJSONFromResponse(response)
            print("🔍 Cleaned response: \(cleanedResponse)")

            guard let jsonData = cleanedResponse.data(using: .utf8) else {
                throw SummaryError.decodingError
            }

            let filteringResponse = try JSONDecoder().decode(DataFilteringResponse.self, from: jsonData)
            print("🎯 LLM selected data: \(filteringResponse.reasoning ?? "No reasoning")")
            print("📋 Filtered IDs - Receipts: \(filteringResponse.receiptIds?.count ?? 0), Events: \(filteringResponse.eventIds?.count ?? 0), Locations: \(filteringResponse.locationIds?.count ?? 0), Notes: \(filteringResponse.noteIds?.count ?? 0), Emails: \(filteringResponse.emailIds?.count ?? 0)")
            if let emailIds = filteringResponse.emailIds {
                print("📧 Email IDs returned: \(emailIds)")
            } else {
                print("📧 Email IDs: nil")
            }
            return filteringResponse
        } catch {
            print("❌ Error getting relevant data IDs: \(error)")
            // Return empty response on error
            return DataFilteringResponse(
                receiptIds: nil,
                eventIds: nil,
                locationIds: nil,
                noteIds: nil,
                emailIds: nil,
                reasoning: "Error filtering data"
            )
        }
    }

    /// Format user behavior patterns into readable text for LLM context
    private func formatUserPatterns(_ patterns: UserPatterns) -> String {
        var formatted = ""

        formatted += "## USER BEHAVIOR PATTERNS\n\n"

        formatted += "SPENDING HABITS:\n"
        formatted += "• Monthly Average: $\(String(format: "%.2f", patterns.averageMonthlySpending))\n"
        formatted += "• Trend: \(patterns.spendingTrend.capitalized)\n"
        formatted += "• Top Categories:\n"
        for category in patterns.topExpenseCategories.prefix(3) {
            formatted += "  - \(category.category.capitalized): $\(String(format: "%.2f", category.totalAmount)) (\(String(format: "%.0f", category.percentage))%)\n"
        }
        formatted += "\n"

        formatted += "ACTIVITY PATTERNS:\n"
        formatted += "• Events per Week: \(String(format: "%.1f", patterns.averageEventsPerWeek))\n"
        formatted += "• Favorite Activities: \(patterns.favoriteEventTypes.joined(separator: ", "))\n"
        if !patterns.mostFrequentEvents.isEmpty {
            formatted += "• Most Frequent Events:\n"
            for event in patterns.mostFrequentEvents.prefix(3) {
                formatted += "  - \(event.title): \(String(format: "%.1f", event.timesPerMonth))x/month\n"
            }
        }
        formatted += "\n"

        formatted += "LOCATION PREFERENCES:\n"
        if !patterns.mostVisitedLocations.isEmpty {
            formatted += "• Most Visited:\n"
            for location in patterns.mostVisitedLocations.prefix(3) {
                formatted += "  - \(location.name) (\(location.visitCount) visits)\n"
            }
        }
        if !patterns.favoriteRestaurantTypes.isEmpty {
            formatted += "• Favorite Cuisines: \(patterns.favoriteRestaurantTypes.joined(separator: ", "))\n"
        }
        formatted += "\n"

        formatted += "TIME PATTERNS:\n"
        formatted += "• Most Active: \(patterns.mostActiveTimeOfDay.capitalized)\n"
        formatted += "• Busiest Days: \(patterns.busyDays.joined(separator: ", "))\n\n"

        return formatted
    }

    /// Format metadata as human-readable text for better LLM comprehension
    private func formatMetadataForLLM(_ metadata: AppDataMetadata, currentDate: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let calendar = Calendar.current

        var formatted = ""

        // Receipts - grouped by month for easier analysis
        if !metadata.receipts.isEmpty {
            formatted += "## RECEIPTS/EXPENSES\n"
            print("📊 FormatMetadata: Processing \(metadata.receipts.count) receipts for LLM context")

            // Group receipts by month
            var receiptsByMonth: [String: [ReceiptMetadata]] = [:]
            for receipt in metadata.receipts {
                let monthKey = receipt.monthYear ?? "Unknown Month"
                if receiptsByMonth[monthKey] == nil {
                    receiptsByMonth[monthKey] = []
                }
                receiptsByMonth[monthKey]?.append(receipt)
            }

            // Display grouped by month (newest first)
            let sortedMonths = receiptsByMonth.keys.sorted().reversed()
            for month in sortedMonths {
                guard let receipts = receiptsByMonth[month] else { continue }
                let monthTotal = receipts.reduce(0) { $0 + $1.amount }
                print("📊 FormatMetadata: \(month) has \(receipts.count) receipts totaling $\(String(format: "%.2f", monthTotal))")
                formatted += "\n### \(month)\n"
                formatted += "Total: $\(String(format: "%.2f", monthTotal)) across \(receipts.count) transactions\n\n"

                for receipt in receipts.sorted(by: { $0.date > $1.date }) {
                    let dateStr = dateFormatter.string(from: receipt.date)
                    let categoryStr = receipt.category ?? "uncategorized"
                    formatted += "- ID: \(receipt.id.uuidString)\n"
                    formatted += "  Merchant: \(receipt.merchant)\n"
                    formatted += "  Amount: $\(String(format: "%.2f", receipt.amount))\n"
                    formatted += "  Date: \(dateStr) (\(receipt.dayOfWeek ?? ""))\n"
                    formatted += "  Category: \(categoryStr)\n"
                    formatted += "\n"
                }
            }
        } else {
            formatted += "## RECEIPTS/EXPENSES\nNo receipts found.\n\n"
        }

        // Events
        if !metadata.events.isEmpty {
            formatted += "## EVENTS/TASKS\n"
            for event in metadata.events.sorted(by: { ($0.date ?? Date.distantFuture) > ($1.date ?? Date.distantFuture) }) {
                let dateStr = event.date.map { dateFormatter.string(from: $0) } ?? "No date"
                formatted += "- ID: \(event.id)\n"
                formatted += "  Title: \(event.title)\n"
                formatted += "  Date: \(dateStr)\n"
                formatted += "  Recurring: \(event.isRecurring)\n"
                if event.isRecurring, let pattern = event.recurrencePattern {
                    formatted += "  Pattern: \(pattern)\n"
                    if let eventDate = event.date {
                        let dayName = calendar.component(.weekday, from: eventDate)
                        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                        formatted += "  Day of Week: \(dayNames[dayName - 1])\n"
                    }
                }
                if let completedDates = event.completedDates, !completedDates.isEmpty {
                    let thisMonthCount = completedDates.filter { date in
                        let month = calendar.component(.month, from: date)
                        let year = calendar.component(.year, from: date)
                        let currentMonth = calendar.component(.month, from: currentDate)
                        let currentYear = calendar.component(.year, from: currentDate)
                        return month == currentMonth && year == currentYear
                    }.count
                    let lastMonthCount = completedDates.filter { date in
                        let month = calendar.component(.month, from: date)
                        let year = calendar.component(.year, from: date)
                        let lastMonth = currentDate.addingTimeInterval(-86400 * 30)
                        let compareMonth = calendar.component(.month, from: lastMonth)
                        let compareYear = calendar.component(.year, from: lastMonth)
                        return month == compareMonth && year == compareYear
                    }.count
                    formatted += "  Total Completions: \(completedDates.count)\n"
                    formatted += "  This Month: \(thisMonthCount) times\n"
                    formatted += "  Last Month: \(lastMonthCount) times\n"
                }
                if event.isRecurring {
                    // Calculate next 3 occurrences for context
                    let nextOccurrences = calculateNextRecurringOccurrences(event: event, from: currentDate, count: 3)
                    if !nextOccurrences.isEmpty {
                        formatted += "  Next Occurrences: \(nextOccurrences.map { dateFormatter.string(from: $0) }.joined(separator: ", "))\n"
                    }
                }
                if let eventType = event.eventType {
                    formatted += "  Type: \(eventType)\n"
                }
                if let description = event.description {
                    formatted += "  Description: \(description)\n"
                }
                formatted += "\n"
            }
        } else {
            formatted += "## EVENTS/TASKS\nNo events found.\n\n"
        }

        // Locations
        if !metadata.locations.isEmpty {
            formatted += "## SAVED LOCATIONS\n"
            for location in metadata.locations {
                formatted += "- ID: \(location.id.uuidString)\n"
                formatted += "  Name: \(location.displayName)\n"
                formatted += "  Folder: \(location.folderName ?? "Uncategorized")\n"

                // Show folder's geographic context
                if let folderCity = location.folderCity {
                    formatted += "  Folder City: \(folderCity)\n"
                }
                if let folderProvince = location.folderProvince {
                    formatted += "  Folder Province: \(folderProvince)\n"
                }
                if let folderCountry = location.folderCountry {
                    formatted += "  Folder Country: \(folderCountry)\n"
                }

                formatted += "  Address: \(location.address)\n"
                if let city = location.city {
                    formatted += "  City: \(city)\n"
                }
                if let province = location.province {
                    formatted += "  Province/State: \(province)\n"
                }
                if let country = location.country {
                    formatted += "  Country: \(country)\n"
                }
                if let rating = location.userRating {
                    formatted += "  Rating: \(rating)/10\n"
                }
                if let cuisine = location.cuisine {
                    formatted += "  Cuisine: \(cuisine)\n"
                }
                if let notes = location.notes {
                    formatted += "  Notes: \(notes)\n"
                }
                formatted += "\n"
            }
        } else {
            formatted += "## SAVED LOCATIONS\nNo locations found.\n\n"
        }

        // Notes
        if !metadata.notes.isEmpty {
            formatted += "## NOTES\n"
            for note in metadata.notes.sorted(by: { $0.dateModified > $1.dateModified }) {
                let dateStr = dateFormatter.string(from: note.dateModified)
                formatted += "- ID: \(note.id.uuidString)\n"
                formatted += "  Title: \(note.title)\n"
                formatted += "  Date: \(dateStr)\n"
                if let folder = note.folder {
                    formatted += "  Folder: \(folder)\n"
                }
                formatted += "  Content: \(note.content)\n"
                formatted += "\n"
            }
        } else {
            formatted += "## NOTES\nNo notes found.\n\n"
        }

        // Emails
        if !metadata.emails.isEmpty {
            formatted += "## EMAILS\n"
            for email in metadata.emails.sorted(by: { $0.date > $1.date }) {
                let dateStr = dateFormatter.string(from: email.date)
                formatted += "- ID: \(email.id)\n"
                formatted += "  From: \(email.from)\n"
                formatted += "  Subject: \(email.subject)\n"
                formatted += "  Date: \(dateStr)\n"
                formatted += "  Preview: \(email.snippet)\n"
                formatted += "\n"
            }
        } else {
            formatted += "## EMAILS\nNo emails found.\n\n"
        }

        return formatted
    }

    /// Fetch full details of items identified as relevant by LLM
    @MainActor
    private func fetchFullDataForIds(
        relevantItemIds: DataFilteringResponse,
        taskManager: TaskManager,
        notesManager: NotesManager,
        emailService: EmailService,
        locationsManager: LocationsManager
    ) async -> (
        receipts: [Note],
        events: [TaskItem],
        locations: [SavedPlace],
        notes: [Note],
        emails: [Email]
    ) {
        var receipts: [Note] = []
        var events: [TaskItem] = []
        var locations: [SavedPlace] = []
        var notes: [Note] = []
        var emails: [Email] = []

        // Fetch receipts (deduplicate IDs first to avoid duplicates)
        if let receiptIds = relevantItemIds.receiptIds, !receiptIds.isEmpty {
            let uniqueIds = Array(Set(receiptIds))  // Remove duplicates
            print("📦 Fetch: LLM selected \(receiptIds.count) receipt IDs (\(uniqueIds.count) unique)")
            receipts = notesManager.notes.filter { uniqueIds.contains($0.id) }
            print("📦 Fetch: Found \(receipts.count) matching notes in notesManager")
        }

        // Fetch events
        if let eventIds = relevantItemIds.eventIds, !eventIds.isEmpty {
            for (_, tasks) in taskManager.tasks {
                let matching = tasks.filter { eventIds.contains($0.id) }
                events.append(contentsOf: matching)
            }
        }

        // Fetch locations
        if let locationIds = relevantItemIds.locationIds, !locationIds.isEmpty {
            locations = locationsManager.savedPlaces.filter { locationIds.contains($0.id) }
        }

        // Fetch notes
        if let noteIds = relevantItemIds.noteIds, !noteIds.isEmpty {
            notes = notesManager.notes.filter { noteIds.contains($0.id) }
        }

        // Fetch emails
        if let emailIds = relevantItemIds.emailIds, !emailIds.isEmpty {
            print("📧 Looking for email IDs: \(emailIds)")
            let allEmails = emailService.inboxEmails + emailService.sentEmails
            print("📧 Total emails available: \(allEmails.count)")
            let allEmailIds = allEmails.map { $0.id }
            print("📧 Available email IDs: \(allEmailIds)")
            emails = allEmails.filter { emailIds.contains($0.id) }
            print("📧 Matched emails: \(emails.count)")
        }

        return (receipts, events, locations, notes, emails)
    }

    /// Filter emails to only those within the requested date range
    private func filterEmailsByDateRange(_ emails: [Email], range: (start: Date, end: Date), currentDate: Date) -> [Email] {
        let calendar = Calendar.current

        return emails.filter { email in
            let emailStartOfDay = calendar.startOfDay(for: email.timestamp)
            return emailStartOfDay >= range.start && emailStartOfDay < range.end
        }
    }

    /// Extract JSON from markdown-wrapped response
    /// Handles cases where LLM returns ```json { ... } ```
    private func extractJSONFromResponse(_ response: String) -> String {
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code block markers
        // Case 1: ```json ... ```
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = String(cleanedResponse.dropFirst(7)) // Remove ```json
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3)) // Remove ```
        }

        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3)) // Remove trailing ```
        }

        // Trim again after removing markdown
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedResponse
    }

    /// Builds comprehensive context for action queries (event/note creation) with weather, locations, and destinations
    @MainActor
    func buildContextForAction(
        weatherService: WeatherService,
        locationsManager: LocationsManager,
        navigationService: NavigationService?
    ) -> String {
        var context = ""

        // Add current date/time
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let currentDate = Date()

        context += "Current date/time: \(dateFormatter.string(from: currentDate)) at \(timeFormatter.string(from: currentDate))\n\n"

        // Add weather data
        if let weatherData = weatherService.weatherData {
            context += "=== WEATHER ===\n"
            context += "Location: \(weatherData.locationName)\n"
            context += "Current: \(weatherData.temperature)°C, \(weatherData.description)\n"
            context += "Sunrise: \(timeFormatter.string(from: weatherData.sunrise))\n"
            context += "Sunset: \(timeFormatter.string(from: weatherData.sunset))\n"

            if !weatherData.dailyForecasts.isEmpty {
                context += "6-Day Forecast:\n"
                for forecast in weatherData.dailyForecasts {
                    context += "- \(forecast.day): \(forecast.temperature)°C\n"
                }
            }
            context += "\n"
        } else if weatherService.isLoading {
            context += "=== WEATHER ===\nWeather data is loading...\n\n"
        }

        // Add saved locations
        if !locationsManager.savedPlaces.isEmpty {
            context += "=== SAVED LOCATIONS ===\n"
            for place in locationsManager.savedPlaces.sorted(by: { $0.dateCreated > $1.dateCreated }) {
                let displayName = place.customName ?? place.name
                context += "- \(displayName) (\(place.category))\n"
                context += "  Address: \(place.address)\n"
                if let rating = place.rating {
                    context += "  Rating: \(String(format: "%.1f", rating))/5\n"
                }
                if let phone = place.phone {
                    context += "  Phone: \(phone)\n"
                }
                context += "\n"
            }
        }

        // Add navigation/destination ETAs if available
        if let navigationService = navigationService {
            context += "=== NAVIGATION DESTINATIONS ===\n"

            // Location 1 ETA (Home)
            if let location1ETA = navigationService.location1ETA {
                context += "Location 1: \(location1ETA) away\n"
            }

            // Location 2 ETA (Work)
            if let location2ETA = navigationService.location2ETA {
                context += "Location 2: \(location2ETA) away\n"
            }

            // Location 3 ETA (Favorite)
            if let location3ETA = navigationService.location3ETA {
                context += "Location 3: \(location3ETA) away\n"
            }

            context += "\n"
        }

        return context.isEmpty ? "No contextual data available." : context
    }

    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Detect the date range the user is asking about
    /// Returns a tuple of (startDate, endDate) to filter tasks
    private func detectDateRange(in query: String, from currentDate: Date) -> (start: Date, end: Date) {
        let lowerQuery = query.lowercased()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: currentDate)

        // Default: only today
        var startDate = todayStart
        var endDate = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Tomorrow
        if lowerQuery.contains("tomorrow") {
            startDate = calendar.date(byAdding: .day, value: 1, to: todayStart)!
            endDate = calendar.date(byAdding: .day, value: 2, to: todayStart)!
        }
        // Today
        else if lowerQuery.contains("today") {
            startDate = todayStart
            endDate = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        }
        // This week - properly calculate Monday to Sunday of current week
        else if lowerQuery.contains("this week") || (lowerQuery.contains("week") && !lowerQuery.contains("next") && !lowerQuery.contains("last")) {
            // Find the Monday of the current week
            let weekday = calendar.component(.weekday, from: todayStart)
            // weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
            let daysToMonday = (weekday == 1) ? -6 : -(weekday - 2)
            let mondayStart = calendar.date(byAdding: .day, value: daysToMonday, to: todayStart)!
            startDate = mondayStart
            endDate = calendar.date(byAdding: .day, value: 7, to: mondayStart)!
        }
        // Last week
        else if lowerQuery.contains("last week") {
            let weekday = calendar.component(.weekday, from: todayStart)
            let daysToMonday = (weekday == 1) ? -6 : -(weekday - 2)
            let thisMonday = calendar.date(byAdding: .day, value: daysToMonday, to: todayStart)!
            startDate = calendar.date(byAdding: .day, value: -7, to: thisMonday)!
            endDate = thisMonday
        }
        // Next week
        else if lowerQuery.contains("next week") {
            let weekday = calendar.component(.weekday, from: todayStart)
            let daysToMonday = (weekday == 1) ? -6 : -(weekday - 2)
            let thisMonday = calendar.date(byAdding: .day, value: daysToMonday, to: todayStart)!
            startDate = calendar.date(byAdding: .day, value: 7, to: thisMonday)!
            endDate = calendar.date(byAdding: .day, value: 14, to: thisMonday)!
        }
        // This month - properly calculate from 1st to last day of month
        else if lowerQuery.contains("this month") || (lowerQuery.contains("month") && !lowerQuery.contains("next") && !lowerQuery.contains("last")) {
            // Get the first day of this month
            if let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: todayStart)) {
                startDate = firstOfMonth
                endDate = calendar.date(byAdding: .month, value: 1, to: firstOfMonth)!
            }
        }
        // Last month
        else if lowerQuery.contains("last month") {
            if let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: todayStart)) {
                startDate = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
                endDate = firstOfMonth
            }
        }
        // Next month
        else if lowerQuery.contains("next month") {
            if let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: todayStart)) {
                startDate = calendar.date(byAdding: .month, value: 1, to: firstOfMonth)!
                endDate = calendar.date(byAdding: .month, value: 2, to: firstOfMonth)!
            }
        }
        // This year
        else if lowerQuery.contains("this year") || (lowerQuery.contains("year") && !lowerQuery.contains("next") && !lowerQuery.contains("last")) {
            // Get Jan 1st of current year
            if let firstOfYear = calendar.date(from: calendar.dateComponents([.year], from: todayStart)) {
                startDate = firstOfYear
                endDate = calendar.date(byAdding: .year, value: 1, to: firstOfYear)!
            }
        }
        // Last year
        else if lowerQuery.contains("last year") {
            if let firstOfYear = calendar.date(from: calendar.dateComponents([.year], from: todayStart)) {
                startDate = calendar.date(byAdding: .year, value: -1, to: firstOfYear)!
                endDate = firstOfYear
            }
        }

        return (startDate, endDate)
    }

    /// Filter tasks to only those within the requested date range
    private func filterTasksByDateRange(_ tasks: [TaskItem], range: (start: Date, end: Date), currentDate: Date) -> [TaskItem] {
        let calendar = Calendar.current

        return tasks.filter { task in
            guard let taskDate = task.targetDate else {
                // Tasks with no date are only included if asking about "all" or general
                return false
            }

            // Check if task is within the requested date range
            let taskStartOfDay = calendar.startOfDay(for: taskDate)
            return taskStartOfDay >= range.start && taskStartOfDay < range.end
        }
    }

    // MARK: - Semantic Similarity & Embeddings

    /// Get embedding vector for text using OpenAI API
    /// Caches results to avoid repeated API calls
    func getEmbedding(for text: String) async throws -> [Float] {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Check cache first
        if let cached = embeddingCache[normalizedText] {
            return cached
        }

        guard let url = URL(string: embeddingsBaseURL) else {
            throw SummaryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "input": normalizedText,
            "model": embeddingModel
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw SummaryError.apiError("Failed to serialize embedding request")
        }

        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.networkError(NSError(domain: "OpenAI", code: -1))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError("Embedding API error: \(httpResponse.statusCode) - \(errorMessage)")
        }

        let decoder = JSONDecoder()
        let embeddingResponse = try decoder.decode(EmbeddingResponse.self, from: data)

        guard let embedding = embeddingResponse.data.first?.embedding else {
            throw SummaryError.decodingError
        }

        // Cache the result
        embeddingCache[normalizedText] = embedding

        return embedding
    }

    /// Calculate cosine similarity between two embedding vectors
    /// Returns a value between 0 and 1, where 1 is identical meaning
    private func cosineSimilarity(_ vector1: [Float], _ vector2: [Float]) -> Float {
        guard vector1.count == vector2.count, !vector1.isEmpty else {
            return 0.0
        }

        var dotProduct: Float = 0.0
        var magnitude1: Float = 0.0
        var magnitude2: Float = 0.0

        for i in 0..<vector1.count {
            dotProduct += vector1[i] * vector2[i]
            magnitude1 += vector1[i] * vector1[i]
            magnitude2 += vector2[i] * vector2[i]
        }

        magnitude1 = sqrt(magnitude1)
        magnitude2 = sqrt(magnitude2)

        guard magnitude1 > 0, magnitude2 > 0 else {
            return 0.0
        }

        return dotProduct / (magnitude1 * magnitude2)
    }

    /// Calculate semantic similarity score between a query and content
    /// Returns a score between 0 and 10 for consistent ranking with other scoring methods
    func getSemanticSimilarityScore(query: String, content: String) async throws -> Double {
        let queryEmbedding = try await getEmbedding(for: query)
        let contentEmbedding = try await getEmbedding(for: content)

        let similarity = cosineSimilarity(queryEmbedding, contentEmbedding)

        // Scale to 0-10 range to match other scoring methods
        // Values above 0.5 cosine similarity are considered meaningful matches
        return Double(similarity) * 10.0
    }

    /// Batch get semantic similarity scores for multiple items
    /// More efficient than calling getSemanticSimilarityScore multiple times
    func getSemanticSimilarityScores(
        query: String,
        contents: [(id: String, text: String)]
    ) async throws -> [String: Double] {
        var results: [String: Double] = [:]

        // Get query embedding once
        let queryEmbedding = try await getEmbedding(for: query)

        // Get all content embeddings in parallel where possible
        for (id, text) in contents {
            let contentEmbedding = try await getEmbedding(for: text)
            let similarity = cosineSimilarity(queryEmbedding, contentEmbedding)
            results[id] = Double(similarity) * 10.0
        }

        return results
    }

    // MARK: - Semantic Search for Smart Context

    /// Finds semantically similar notes based on a query
    /// Returns top N most relevant notes even if keywords don't match exactly
    func findSemanticallySimilarNotes(
        query: String,
        from notes: [Note],
        maxResults: Int = 5,
        similarityThreshold: Double = 4.0
    ) async throws -> [Note] {
        guard !notes.isEmpty else { return [] }

        // Create searchable content from notes (title + content)
        let searchableNotes = notes.map { note in
            (id: note.id.uuidString, text: "\(note.title) \(note.content)", note: note)
        }

        // Get similarity scores
        let scores = try await getSemanticSimilarityScores(
            query: query,
            contents: searchableNotes.map { ($0.id, $0.text) }
        )

        // Filter by threshold and sort
        return searchableNotes
            .filter { scores[$0.id, default: 0] >= similarityThreshold }
            .sorted { scores[$0.id, default: 0] > scores[$1.id, default: 0] }
            .prefix(maxResults)
            .map { $0.note }
    }

    /// Finds semantically similar emails based on a query
    func findSemanticallySimilarEmails(
        query: String,
        from emails: [Email],
        maxResults: Int = 5,
        similarityThreshold: Double = 4.0
    ) async throws -> [Email] {
        guard !emails.isEmpty else { return [] }

        // Create searchable content from emails
        let searchableEmails = emails.map { email in
            (id: email.id, text: "\(email.subject) \(email.body ?? "")", email: email)
        }

        // Get similarity scores
        let emailContents = searchableEmails.map { ($0.id, $0.text) }
        let scores = try await getSemanticSimilarityScores(
            query: query,
            contents: emailContents
        )

        // Filter by threshold and sort
        let filteredEmails = searchableEmails.filter { scores[$0.id, default: 0] >= similarityThreshold }
        let sortedEmails = filteredEmails.sorted { scores[$0.id, default: 0] > scores[$1.id, default: 0] }
        return Array(sortedEmails.prefix(maxResults)).map { $0.email }
    }

    /// Finds semantically similar events/tasks based on a query
    func findSemanticallySimilarEvents(
        query: String,
        from events: [TaskItem],
        maxResults: Int = 5,
        similarityThreshold: Double = 4.0
    ) async throws -> [TaskItem] {
        guard !events.isEmpty else { return [] }

        // Create searchable content from events
        let searchableEvents = events.map { event in
            (id: event.id, text: "\(event.title) \(event.description ?? "")", event: event)
        }

        // Get similarity scores
        let eventContents = searchableEvents.map { ($0.id, $0.text) }
        let scores = try await getSemanticSimilarityScores(
            query: query,
            contents: eventContents
        )

        // Filter by threshold and sort
        let filteredEvents = searchableEvents.filter { scores[$0.id, default: 0] >= similarityThreshold }
        let sortedEvents = filteredEvents.sorted { scores[$0.id, default: 0] > scores[$1.id, default: 0] }
        return Array(sortedEvents.prefix(maxResults)).map { $0.event }
    }

    /// Determines if a query is "simple" and doesn't need semantic enrichment
    /// Simple queries are those asking for specific data types with date filters
    private func isSimpleQuery(_ query: String, intents: Set<String>) -> Bool {
        let lowerQuery = query.lowercased()

        // Single-intent queries with date/time filters are simple (don't need semantic search)
        if intents.count == 1 {
            let intent = intents.first ?? ""

            // Receipts/expenses queries are simple - user knows what they want
            if intent == "receipts" {
                return true
            }

            // Events/tasks with date filter are simple
            if intent == "events" && (lowerQuery.contains("today") || lowerQuery.contains("week") || lowerQuery.contains("month")) {
                return true
            }

            // Emails with date filter are simple
            if intent == "emails" && (lowerQuery.contains("today") || lowerQuery.contains("week") || lowerQuery.contains("month")) {
                return true
            }

            // Notes in specific folder are simple
            if intent == "notes" && lowerQuery.split(separator: " ").count <= 5 {
                return true
            }

            // Navigation queries are simple
            if intent == "navigation" {
                return true
            }

            // Weather queries are simple
            if intent == "weather" {
                return true
            }
        }

        // Multi-intent or complex queries need semantic search
        return false
    }

    /// Enriches context with semantically relevant content
    /// Finds related notes, emails, events even if user didn't explicitly ask for them
    /// Skips semantic search for simple queries to improve performance
    func enrichContextWithSemanticMatches(
        query: String,
        notes: [Note],
        emails: [Email],
        events: [TaskItem],
        queryIntents: Set<String>
    ) async throws -> String {
        var enrichedContext = ""

        // Skip semantic search for simple queries (performance optimization)
        if isSimpleQuery(query, intents: queryIntents) {
            print("⏭️ Skipping semantic search for simple query")
            return enrichedContext
        }

        do {
            // Find semantically similar notes
            let similarNotes = try await findSemanticallySimilarNotes(query: query, from: notes, maxResults: 3)
            if !similarNotes.isEmpty {
                enrichedContext += "=== RELATED NOTES (Semantic Match) ===\n"
                for note in similarNotes {
                    let preview = String(note.content.prefix(80))
                    enrichedContext += "• \(note.title): \(preview)...\n"
                }
                enrichedContext += "\n"
            }

            // Find semantically similar emails
            let similarEmails = try await findSemanticallySimilarEmails(query: query, from: emails, maxResults: 3)
            if !similarEmails.isEmpty {
                enrichedContext += "=== RELATED EMAILS (Semantic Match) ===\n"
                for email in similarEmails {
                    enrichedContext += "• From: \(email.sender.displayName), Subject: \(email.subject)\n"
                }
                enrichedContext += "\n"
            }

            // Find semantically similar events
            let similarEvents = try await findSemanticallySimilarEvents(query: query, from: events, maxResults: 3)
            if !similarEvents.isEmpty {
                enrichedContext += "=== RELATED EVENTS (Semantic Match) ===\n"
                for event in similarEvents {
                    enrichedContext += "• \(event.title): \(event.description ?? "No description")\n"
                }
                enrichedContext += "\n"
            }
        } catch {
            // If semantic search fails, silently continue - it's an enhancement, not critical
            print("⚠️ Semantic enrichment failed: \(error)")
        }

        return enrichedContext
    }

    /// Calculates the next N occurrences of a recurring event
    /// - Parameters:
    ///   - event: The EventMetadata for a recurring event
    ///   - from: The starting date to calculate from
    ///   - count: Number of occurrences to calculate
    /// - Returns: Array of dates when the event will next occur
    private func calculateNextRecurringOccurrences(event: EventMetadata, from startDate: Date, count: Int) -> [Date] {
        guard event.isRecurring, let frequency = event.recurrencePattern else {
            return []
        }

        var occurrences: [Date] = []
        let calendar = Calendar.current
        // Look ahead up to 2 years for recurring events
        let endDate = calendar.date(byAdding: .year, value: 2, to: startDate) ?? startDate

        var currentDate = startDate

        while occurrences.count < count && currentDate < endDate {
            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate

            // Check if this date matches the recurrence pattern
            if shouldRecurOn(date: currentDate, event: event, frequency: frequency, calendar: calendar) {
                occurrences.append(currentDate)
            }

            // Safety check to prevent infinite loops
            if currentDate > calendar.date(byAdding: .year, value: 2, to: startDate) ?? startDate {
                break
            }
        }

        return occurrences
    }

    /// Determines if a recurring event should occur on a specific date
    /// - Parameters:
    ///   - date: The date to check
    ///   - event: The EventMetadata for the recurring event
    ///   - frequency: The recurrence frequency
    ///   - calendar: The calendar to use for calculations
    /// - Returns: True if the event should occur on this date
    private func shouldRecurOn(date: Date, event: EventMetadata, frequency: String, calendar: Calendar) -> Bool {
        guard let eventDate = event.date else { return false }

        let eventWeekday = getWeekdayString(for: eventDate, calendar: calendar)
        let dateWeekday = getWeekdayString(for: date, calendar: calendar)

        switch frequency.lowercased() {
        case "daily":
            return true

        case "weekly":
            // For weekly events, check if the day of week matches
            return dateWeekday == eventWeekday

        case "biweekly":
            // For biweekly, check day of week and week number
            if dateWeekday != eventWeekday {
                return false
            }

            // Check if it's the right week (every 2 weeks)
            let components = calendar.dateComponents([.weekOfYear], from: eventDate, to: date)
            let weekDifference = components.weekOfYear ?? 0
            return weekDifference % 2 == 0

        case "monthly":
            // For monthly events, check if it's the same day of month
            let eventDay = calendar.component(.day, from: eventDate)
            let currentDay = calendar.component(.day, from: date)
            return eventDay == currentDay

        case "yearly":
            // For yearly events, check if it's the same month and day
            let eventMonth = calendar.component(.month, from: eventDate)
            let eventDay = calendar.component(.day, from: eventDate)
            let currentMonth = calendar.component(.month, from: date)
            let currentDay = calendar.component(.day, from: date)
            return eventMonth == currentMonth && eventDay == currentDay

        default:
            return false
        }
    }

    /// Converts a date to a weekday string (e.g., "monday", "tuesday")
    private func getWeekdayString(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        // Calendar uses: 1=Sunday, 2=Monday, ..., 7=Saturday
        let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return weekday > 0 && weekday <= 7 ? weekdayNames[weekday - 1] : ""
    }

    /// Handles future date queries directly without LLM filtering
    /// For "tomorrow", "next week", etc., calculates events that will occur and returns them directly
    /// This bypasses the complex filtering and ensures recurring events are detected
    @MainActor
    private func checkForFutureDateQuery(query: String, currentDate: Date, taskManager: TaskManager) -> String? {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        var targetDates: [Date] = []
        var queryDescription = ""

        // Detect future date keywords
        if query.contains("tomorrow") {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) {
                targetDates = [tomorrow]
                queryDescription = "tomorrow"
            }
        } else if query.contains("next week") || query.contains("upcoming week") {
            if let nextWeekStart = calendar.date(byAdding: .day, value: 1, to: currentDate),
               let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: currentDate) {
                targetDates = (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: nextWeekStart) }
                queryDescription = "next week"
            }
        } else if query.contains("next month") || query.contains("upcoming month") {
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                let range = calendar.range(of: .day, in: .month, for: nextMonth)
                let daysInMonth = range?.count ?? 28
                targetDates = (1...daysInMonth).compactMap { day in
                    calendar.date(from: DateComponents(year: calendar.component(.year, from: nextMonth),
                                                        month: calendar.component(.month, from: nextMonth),
                                                        day: day))
                }
                queryDescription = "next month"
            }
        }

        guard !targetDates.isEmpty else { return nil }

        // Get all tasks and filter for those that occur on target dates
        var allEvents: [TaskItem] = []
        for weekday in WeekDay.allCases {
            if let tasksForDay = taskManager.tasks[weekday] {
                allEvents.append(contentsOf: tasksForDay)
            }
        }
        var matchingEvents: [TaskItem] = []

        for targetDate in targetDates {
            let targetWeekday = calendar.component(.weekday, from: targetDate)
            let targetDay = calendar.component(.day, from: targetDate)
            let targetMonth = calendar.component(.month, from: targetDate)
            let targetYear = calendar.component(.year, from: targetDate)

            for event in allEvents {
                // Check if event occurs on this target date
                let isMatch: Bool

                if event.isRecurring {
                    // For recurring events, check if it recurs on this date based on frequency
                    let eventWeekday = event.weekday.calendarWeekday
                    isMatch = shouldEventOccurOnDate(event: event, targetWeekday: targetWeekday, targetDay: targetDay, calendar: calendar)
                } else {
                    // For one-time events, check if the date matches
                    let eventDate = event.targetDate ?? event.createdAt
                    let eventDay = calendar.component(.day, from: eventDate)
                    let eventMonth = calendar.component(.month, from: eventDate)
                    let eventYear = calendar.component(.year, from: eventDate)
                    isMatch = (eventDay == targetDay && eventMonth == targetMonth && eventYear == targetYear)
                }

                if isMatch && !matchingEvents.contains(where: { $0.id == event.id }) {
                    matchingEvents.append(event)
                }
            }
        }

        // Build response with matching events
        var response = "Events for \(queryDescription):\n\n"

        if matchingEvents.isEmpty {
            response += "You have no events for \(queryDescription)."
        } else {
            response += "Here are your events for \(queryDescription):\n\n"
            for event in matchingEvents.sorted(by: { ($0.scheduledTime ?? Date()) < ($1.scheduledTime ?? Date()) }) {
                response += "• \(event.title)"
                if let time = event.scheduledTime {
                    response += " - \(timeFormatter.string(from: time))"
                }
                if event.isRecurring {
                    response += " (recurring \(event.recurrenceFrequency?.displayName ?? ""))"
                }
                if let description = event.description {
                    response += "\n  \(description)"
                }
                response += "\n"
            }
        }

        return response
    }

    /// Determines if a recurring event should occur on a specific target date
    @MainActor
    private func shouldEventOccurOnDate(event: TaskItem, targetWeekday: Int, targetDay: Int, calendar: Calendar) -> Bool {
        let eventWeekday = event.weekday.calendarWeekday

        switch event.recurrenceFrequency {
        case .daily:
            return true

        case .weekly:
            return eventWeekday == targetWeekday

        case .biweekly:
            if eventWeekday != targetWeekday { return false }
            // Check if it's in the right bi-weekly cycle
            let components = calendar.dateComponents([.weekOfYear], from: event.createdAt, to: Date())
            let weekDiff = components.weekOfYear ?? 0
            return weekDiff % 2 == 0

        case .monthly:
            return targetDay == calendar.component(.day, from: event.createdAt)

        case .yearly:
            let eventMonth = calendar.component(.month, from: event.createdAt)
            let eventDay = calendar.component(.day, from: event.createdAt)
            let targetMonth = calendar.component(.month, from: Date().addingTimeInterval(TimeInterval(targetDay * 86400)))
            return eventMonth == targetMonth && eventDay == targetDay

        case .none:
            return false
        }
    }

    // MARK: - LLM-Based Expense Intent Extraction

    /// Use LLM to intelligently extract expense query intent
    /// Handles natural language variation without hardcoded lists
    func extractExpenseIntent(from query: String) async -> ExpenseIntent? {
        let systemPrompt = """
        You are an expert at understanding purchase/expense queries. Extract the intent from the user's query and respond with ONLY a JSON object (no other text).

        Return this JSON structure:
        {
            "productName": "the main product/item being asked about (e.g., 'pizza', 'coffee', 'zonnic')",
            "alternateSearchTerms": ["list", "of", "related", "terms"],
            "queryType": "one of: lookup, countUnique, listAll, sumAmount, frequency",
            "dateFilter": "optional date constraint like 'this month', 'last week', or null if none",
            "merchantFilter": "optional merchant/location filter or null if none",
            "confidence": 0.0-1.0
        }

        Query types:
        - lookup: "when did I last buy X?", "did I ever buy X?" → most recent purchase
        - countUnique: "how many different pizza places?", "how many unique merchants?" → count unique merchants
        - listAll: "show all pizza purchases", "list all coffee" → all matching receipts
        - sumAmount: "how much did I spend on X?", "total spent on X?" → sum amounts
        - frequency: "how many times did I buy X?", "how often?" → count occurrences

        IMPORTANT: Include semantic variations in alternateSearchTerms!
        - "pizza" → ["pizza", "pizzeria", "pizza hut", "pizza place"]
        - "coffee" → ["coffee", "cafe", "café", "espresso", "starbucks"]
        - "donut" → ["donut", "doughnut", "donuts", "doughnuts"]

        Examples:
        - "How many times did I buy pizza" → {productName: "pizza", alternateSearchTerms: ["pizza", "pizzeria", "pizza place"], queryType: "frequency", ...}
        - "When did I last buy zonnic?" → {productName: "zonnic", alternateSearchTerms: ["zonnic"], queryType: "lookup", ...}
        - "How many different pizza places did I get pizza from?" → {productName: "pizza", alternateSearchTerms: ["pizza", "pizzeria"], queryType: "countUnique", ...}
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": query]
            ],
            "temperature": 0.2,
            "max_tokens": 200
        ]

        do {
            let responseString = try await makeOpenAIRequest(
                url: URL(string: baseURL)!,
                requestBody: requestBody
            )

            // Parse JSON response
            guard let jsonData = responseString.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()

            struct IntentResponse: Codable {
                let productName: String
                let queryType: String
                let dateFilter: String?
                let merchantFilter: String?
                let confidence: Double
                let alternateSearchTerms: [String]?
            }

            let intentResponse = try decoder.decode(IntentResponse.self, from: jsonData)

            // Convert string queryType to enum
            let queryTypeEnum: ExpenseQueryType
            switch intentResponse.queryType.lowercased() {
            case "lookup":
                queryTypeEnum = .lookup
            case "countunique":
                queryTypeEnum = .countUnique
            case "listall":
                queryTypeEnum = .listAll
            case "sumamount":
                queryTypeEnum = .sumAmount
            case "frequency":
                queryTypeEnum = .frequency
            default:
                queryTypeEnum = .lookup
            }

            // Ensure alternateSearchTerms always includes at least the productName
            var alternateTerms = intentResponse.alternateSearchTerms ?? [intentResponse.productName]
            if !alternateTerms.contains(intentResponse.productName) {
                alternateTerms.insert(intentResponse.productName, at: 0)
            }

            let intent = ExpenseIntent(
                productName: intentResponse.productName,
                queryType: queryTypeEnum,
                dateFilter: intentResponse.dateFilter,
                merchantFilter: intentResponse.merchantFilter,
                confidence: intentResponse.confidence,
                alternateSearchTerms: alternateTerms
            )

            print("🧠 LLM Intent Extraction: product='\(intent.productName)', type=\(intent.queryType), terms=\(alternateTerms), confidence=\(String(format: "%.1f%%", intent.confidence * 100))")
            return intent

        } catch {
            print("❌ Intent extraction failed: \(error)")
            return nil
        }
    }

    // MARK: - Universal Semantic Query Generation

    /// Generate a semantic query that works across all app data types
    /// This is the new foundational query system that replaces rigid intent types
    func generateSemanticQuery(from userQuery: String) async -> SemanticQuery? {
        let systemPrompt = """
        You are an expert semantic query parser for a personal data assistant.

        The app contains 6 data types:
        1. **Receipts** - Purchase history with merchant, amount, date, category
        2. **Emails** - Messages organized in folders
        3. **Events** - Calendar events (upcoming/completed)
        4. **Notes** - Text content organized in folders
        5. **Locations** - Saved places (favorited, ranked, in folders)
        6. **Calendar** - Integrated calendar events

        Parse the user's natural language query into a semantic query plan. Return ONLY valid JSON (no other text).

        {
          "intent": "search|compare|analyze|explore|track|summarize|predict",
          "reasoning": "brief explanation of intent interpretation",

          "dataSources": [
            {
              "type": "receipts|emails|events|notes|locations|calendar",
              "filters": { "category": "...", "folder": "...", "status": "..." }
            }
          ],

          "filters": [
            {
              "type": "date_range|category|text_search|status|amount_range|merchant",
              "parameters": { ... }
            }
          ],

          "operations": [
            {
              "type": "aggregate|comparison|search|trend_analysis",
              "parameters": { ... }
            }
          ],

          "presentation": {
            "format": "summary|table|list|timeline|trend|cards|mixed",
            "includeIndividualItems": true|false,
            "maxItemsToShow": 5-20,
            "summaryLevel": "brief|detailed|comprehensive"
          },

          "confidence": 0.0-1.0
        }

        **Intent Types:**
        - search: Find items matching criteria ("show my emails from John", "find notes about project X")
        - compare: Compare time periods or categories ("compare Nov vs Oct", "food vs shopping spending")
        - analyze: Statistics, patterns, insights ("which merchant do I use most", "spending trend")
        - explore: Browse and discover ("show my recent emails", "what locations have I saved")
        - track: Monitor status/progress ("what events are pending", "incomplete tasks")
        - summarize: Overview/digest ("monthly summary", "recap of last week")
        - predict: Forecast/suggest ("when will I hit budget", "likely next purchase")

        **Data Source Examples:**
        - receipts: { "type": "receipts", "filters": {"category": "Food"} }
        - emails: { "type": "emails", "filters": {"folder": "Work"} }
        - events: { "type": "events", "filters": {"status": "upcoming"} }
        - notes: { "type": "notes", "filters": {"folder": "Projects"} }
        - locations: { "type": "locations" }

        **Filter Types:**
        - date_range: { "startDate": "2025-11-01", "endDate": "2025-11-30", "labels": ["November 2025"] }
        - category: { "categories": ["Food", "Shopping"], "excludeCategories": [] }
        - text_search: { "query": "pizza", "fields": ["content", "merchant"], "fuzzyMatch": true }
        - status: { "status": "completed" }
        - amount_range: { "minAmount": 10.0, "maxAmount": 100.0 }
        - merchant: { "merchants": ["Costco", "Trader Joe's"], "fuzzyMatch": true }

        **Operation Types:**
        - aggregate: { "type": "aggregate", "aggregationType": "sum|count|average|min|max", "groupBy": "category|merchant|date|status" }
        - comparison: { "type": "comparison", "dimension": "time|category|merchant", "slices": ["November", "October"], "metric": "total|count|average" }
        - search: { "type": "search", "query": "...", "rankBy": "relevance|date|amount", "limit": 10 }
        - trend_analysis: { "type": "trend_analysis", "metric": "spending|frequency", "timeGranularity": "daily|weekly|monthly|yearly" }

        **CRITICAL RULES:**
        1. For comparison queries (e.g., "Nov vs Oct"), use comparison operation with dimension "time"
        2. For aggregate queries (e.g., "spending by category"), use aggregate operation with groupBy
        3. For month comparisons, detect both date periods and add them as date_range filters
        4. Set includeIndividualItems: false for aggregate/comparison/analyze queries
        5. Set includeIndividualItems: true for search/explore/track queries

        **Examples:**

        Query: "Compare my spending in November and October 2025"
        {
          "intent": "compare",
          "dataSources": [{"type": "receipts"}],
          "filters": [
            {
              "type": "date_range",
              "parameters": {
                "startDate": "2025-10-01",
                "endDate": "2025-11-30",
                "labels": ["October 2025", "November 2025"]
              }
            }
          ],
          "operations": [
            {
              "type": "comparison",
              "parameters": {
                "dimension": "time",
                "slices": ["October 2025", "November 2025"],
                "metric": "total"
              }
            },
            {
              "type": "aggregate",
              "parameters": {
                "aggregationType": "sum",
                "groupBy": "category"
              }
            }
          ],
          "presentation": {
            "format": "table",
            "includeIndividualItems": false,
            "maxItemsToShow": 10,
            "summaryLevel": "detailed"
          },
          "confidence": 0.95
        }

        Query: "Show me unread emails from the past week"
        {
          "intent": "explore",
          "dataSources": [{"type": "emails"}],
          "filters": [
            {"type": "date_range", "parameters": {"days": 7, "labels": ["past week"]}},
            {"type": "status", "parameters": {"status": "unread"}}
          ],
          "operations": [],
          "presentation": {
            "format": "list",
            "includeIndividualItems": true,
            "maxItemsToShow": 20,
            "summaryLevel": "brief"
          },
          "confidence": 0.98
        }

        Query: "What's my top spending category"
        {
          "intent": "analyze",
          "dataSources": [{"type": "receipts"}],
          "filters": [],
          "operations": [
            {
              "type": "aggregate",
              "parameters": {
                "aggregationType": "sum",
                "groupBy": "category"
              }
            }
          ],
          "presentation": {
            "format": "summary",
            "includeIndividualItems": false,
            "maxItemsToShow": 5,
            "summaryLevel": "brief"
          },
          "confidence": 0.92
        }
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userQuery]
            ],
            "temperature": 0.3,
            "max_tokens": 1500
        ]

        do {
            let responseString = try await makeOpenAIRequest(
                url: URL(string: baseURL)!,
                requestBody: requestBody
            )

            guard let jsonData = responseString.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(SemanticQueryResponse.self, from: jsonData)

            // Build the SemanticQuery from the response
            let intent = SemanticQueryIntent(rawValue: response.intent) ?? .search
            let dataSources = parseDataSources(response.dataSources)
            let filters = parseFilters(response.filters)
            let operations = parseOperations(response.operations)
            let presentation = PresentationRules(
                format: PresentationRules.ResponseFormat(rawValue: response.presentation.format) ?? .mixed,
                includeIndividualItems: response.presentation.includeIndividualItems ?? true,
                maxItemsToShow: response.presentation.maxItemsToShow ?? 5,
                visualizations: [],
                summaryLevel: PresentationRules.SummaryLevel(rawValue: response.presentation.summaryLevel ?? "detailed") ?? .detailed
            )

            let query = SemanticQuery(
                userQuery: userQuery,
                intent: intent,
                dataSources: dataSources,
                filters: filters,
                operations: operations,
                presentation: presentation,
                confidence: response.confidence,
                reasoning: response.reasoning
            )

            print("🧠 Semantic Query Generated:")
            print("   Intent: \(intent)")
            print("   Sources: \(dataSources.count)")
            print("   Filters: \(filters.count)")
            print("   Operations: \(operations.count)")
            print("   Format: \(presentation.format)")
            print("   Confidence: \(String(format: "%.0f%%", response.confidence * 100))")

            return query

        } catch {
            print("❌ Semantic query generation failed: \(error)")
            return nil
        }
    }

    // MARK: - Semantic Query Response Parsing

    private struct SemanticQueryResponse: Codable {
        let intent: String
        let reasoning: String?  // Optional - LLM may not include reasoning
        let dataSources: [[String: AnyCodable]]
        let filters: [[String: AnyCodable]]
        let operations: [[String: AnyCodable]]
        let presentation: PresentationResponse
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case intent, reasoning, dataSources, filters, operations, presentation, confidence
        }
    }

    private struct PresentationResponse: Codable {
        let format: String
        let includeIndividualItems: Bool?
        let maxItemsToShow: Int?
        let summaryLevel: String?
    }

    private func parseDataSources(_ raw: [[String: AnyCodable]]) -> [DataSource] {
        return raw.compactMap { dict -> DataSource? in
            guard let typeStr = (dict["type"] as? AnyCodable)?.value as? String else { return nil }

            switch typeStr {
            case "receipts":
                let category = (dict["filters"]?.value as? [String: AnyCodable])
                    .flatMap { $0["category"]?.value as? String }
                return .receipts(category: category)

            case "emails":
                let folder = (dict["filters"]?.value as? [String: AnyCodable])
                    .flatMap { $0["folder"]?.value as? String }
                return .emails(folder: folder)

            case "events":
                let statusStr = (dict["filters"]?.value as? [String: AnyCodable])
                    .flatMap { $0["status"]?.value as? String }
                let status = statusStr.flatMap { EventStatus(rawValue: $0) }
                return .events(status: status)

            case "notes":
                let folder = (dict["filters"]?.value as? [String: AnyCodable])
                    .flatMap { $0["folder"]?.value as? String }
                return .notes(folder: folder)

            case "locations":
                return .locations(type: nil)

            case "calendar":
                return .calendar

            default:
                return nil
            }
        }
    }

    private func parseFilters(_ raw: [[String: AnyCodable]]) -> [AnyFilter] {
        return raw.compactMap { dict -> AnyFilter? in
            guard let typeStr = (dict["type"] as? AnyCodable)?.value as? String else { return nil }
            guard let params = (dict["parameters"] as? AnyCodable)?.value as? [String: Any] else { return nil }

            switch typeStr {
            case "date_range":
                let labels = (params["labels"] as? [String]) ?? []
                let startStr = params["startDate"] as? String
                let endStr = params["endDate"] as? String

                let formatter = ISO8601DateFormatter()
                let start = startStr.flatMap { formatter.date(from: $0) }
                let end = endStr.flatMap { formatter.date(from: $0) }

                return AnyFilter(DateRangeFilter(startDate: start, endDate: end, labels: labels))

            case "category":
                let categories = (params["categories"] as? [String]) ?? []
                let excludeCategories = (params["excludeCategories"] as? [String]) ?? []
                return AnyFilter(CategoryFilter(categories: categories, excludeCategories: excludeCategories))

            case "text_search":
                let query = (params["query"] as? String) ?? ""
                let fields = (params["fields"] as? [String]) ?? []
                let fuzzyMatch = (params["fuzzyMatch"] as? Bool) ?? true
                return AnyFilter(TextSearchFilter(query: query, fields: fields, fuzzyMatch: fuzzyMatch))

            case "status":
                let status = (params["status"] as? String) ?? ""
                return AnyFilter(StatusFilter(status: status))

            case "amount_range":
                let minAmount = params["minAmount"] as? Double
                let maxAmount = params["maxAmount"] as? Double
                return AnyFilter(AmountRangeFilter(minAmount: minAmount, maxAmount: maxAmount))

            case "merchant":
                let merchants = (params["merchants"] as? [String]) ?? []
                let fuzzyMatch = (params["fuzzyMatch"] as? Bool) ?? true
                return AnyFilter(MerchantFilter(merchants: merchants, fuzzyMatch: fuzzyMatch))

            default:
                return nil
            }
        }
    }

    private func parseOperations(_ raw: [[String: AnyCodable]]) -> [AnyOperation] {
        return raw.compactMap { dict in
            guard let typeStr = (dict["type"] as? AnyCodable)?.value as? String else { return nil }
            guard let params = (dict["parameters"] as? AnyCodable)?.value as? [String: Any] else { return nil }

            switch typeStr {
            case "aggregate":
                let aggTypeStr = (params["aggregationType"] as? String) ?? "count"
                let groupBy = params["groupBy"] as? String

                let aggType: AggregateOperation.AggregationType
                switch aggTypeStr {
                case "sum":
                    aggType = .sum(field: "amount")
                case "average":
                    aggType = .average(field: "amount")
                case "min":
                    aggType = .min(field: "amount")
                case "max":
                    aggType = .max(field: "amount")
                default:
                    aggType = .count
                }

                return AnyOperation(AggregateOperation(type: aggType, groupBy: groupBy, sortBy: nil, orderBy: nil))

            case "comparison":
                let dimension = (params["dimension"] as? String) ?? "time"
                let slices = (params["slices"] as? [String]) ?? []
                let metric = (params["metric"] as? String) ?? "total"
                return AnyOperation(ComparisonOperation(dimension: dimension, slices: slices, metric: metric))

            case "search":
                let query = (params["query"] as? String) ?? ""
                let rankBy = params["rankBy"] as? String
                let limit = params["limit"] as? Int
                return AnyOperation(SearchOperation(query: query, rankBy: rankBy, limit: limit))

            case "trend_analysis":
                let metric = (params["metric"] as? String) ?? "spending"
                let granularity = (params["timeGranularity"] as? String) ?? "monthly"
                let direction = params["direction"] as? String
                return AnyOperation(TrendAnalysisOperation(metric: metric, timeGranularity: granularity, direction: direction))

            default:
                return nil
            }
        }
    }

    // MARK: - Response Formatting Helpers

    private func formatLookupResponseWithItems(
        productName: String,
        result: ItemSearchResult,
        dateFormatter: DateFormatter,
        allReceipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> String {
        let answer = ItemSearchService.shared.createSearchAnswer(
            text: formatLookupResponse(productName: productName, result: result, dateFormatter: dateFormatter),
            for: [result],
            receipts: allReceipts,
            notes: Array(notes.values)
        )
        self.lastSearchAnswer = answer
        return answer.text
    }

    private func formatLookupResponse(
        productName: String,
        result: ItemSearchResult,
        dateFormatter: DateFormatter
    ) -> String {
        let dateStr = dateFormatter.string(from: result.receiptDate)
        var response = "You last bought **\(productName)** on **\(dateStr)** at **\(result.merchant)**"

        if result.amount > 0 {
            let formattedAmount = String(format: "$%.2f", result.amount)
            response += " for \(formattedAmount)"
        }

        if result.confidence < 1.0 {
            response += " (confidence: \(String(format: "%.0f%%", result.confidence * 100)))"
        }

        response += "."
        return response
    }

    private func formatCountUniqueResponseWithItems(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter,
        allReceipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> String {
        let answer = ItemSearchService.shared.createSearchAnswer(
            text: formatCountUniqueResponse(productName: productName, matches: matches, dateFormatter: dateFormatter),
            for: matches,
            receipts: allReceipts,
            notes: Array(notes.values)
        )
        self.lastSearchAnswer = answer
        return answer.text
    }

    private func formatCountUniqueResponse(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter
    ) -> String {
        let grouped = ItemSearchService.shared.groupReceiptsByMerchant(for: matches)
        let uniqueCount = grouped.count

        var response = "You bought **\(productName)** from **\(uniqueCount) different \(uniqueCount == 1 ? "place" : "places")**:\n\n"

        // Sort merchants by most recent receipt
        let sortedMerchants = grouped.keys.sorted { merchant1, merchant2 in
            let date1 = grouped[merchant1]?.max(by: { $0.receiptDate < $1.receiptDate })?.receiptDate ?? Date()
            let date2 = grouped[merchant2]?.max(by: { $0.receiptDate < $1.receiptDate })?.receiptDate ?? Date()
            return date1 > date2
        }

        for (index, merchant) in sortedMerchants.enumerated() {
            let receiptsAtMerchant = grouped[merchant] ?? []
            let count = receiptsAtMerchant.count
            let totalAmount = receiptsAtMerchant.reduce(0) { $0 + $1.amount }

            response += "**\(index + 1). \(merchant)**"
            if count > 1 {
                response += " (\(count) times, total: $\(String(format: "%.2f", totalAmount)))"
            } else {
                response += " ($\(String(format: "%.2f", totalAmount)))"
            }
            response += "\n"

            // Show dates of purchases at this merchant
            let dates = receiptsAtMerchant.sorted { $0.receiptDate > $1.receiptDate }
            for date in dates.prefix(3) {
                response += "   • \(dateFormatter.string(from: date.receiptDate))\n"
            }
            if dates.count > 3 {
                response += "   • ...and \(dates.count - 3) more\n"
            }
        }

        return response
    }

    private func formatListAllResponseWithItems(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter,
        allReceipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> String {
        let answer = ItemSearchService.shared.createSearchAnswer(
            text: formatListAllResponse(productName: productName, matches: matches, dateFormatter: dateFormatter),
            for: matches,
            receipts: allReceipts,
            notes: Array(notes.values)
        )
        self.lastSearchAnswer = answer
        return answer.text
    }

    private func formatListAllResponse(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter
    ) -> String {
        var response = "Found \(matches.count) receipt\(matches.count == 1 ? "" : "s") for **\(productName)**:\n\n"

        for (index, match) in matches.enumerated() {
            let dateStr = dateFormatter.string(from: match.receiptDate)
            response += "**\(index + 1). \(dateStr)** - \(match.merchant)"

            if match.amount > 0 {
                response += " ($\(String(format: "%.2f", match.amount)))"
            }

            response += "\n"
        }

        return response
    }

    private func formatSumResponseWithItems(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter,
        allReceipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> String {
        let answer = ItemSearchService.shared.createSearchAnswer(
            text: formatSumResponse(productName: productName, matches: matches, dateFormatter: dateFormatter),
            for: matches,
            receipts: allReceipts,
            notes: Array(notes.values)
        )
        self.lastSearchAnswer = answer
        return answer.text
    }

    private func formatSumResponse(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter
    ) -> String {
        let totalAmount = ItemSearchService.shared.sumAmount(for: matches)
        let count = matches.count

        var response = "You spent **$\(String(format: "%.2f", totalAmount))** on **\(productName)** across \(count) purchase\(count == 1 ? "" : "s"):\n\n"

        for match in matches.sorted(by: { $0.receiptDate > $1.receiptDate }) {
            let dateStr = dateFormatter.string(from: match.receiptDate)
            response += "• \(dateStr): \(match.merchant) - $\(String(format: "%.2f", match.amount))\n"
        }

        return response
    }

    private func formatFrequencyResponseWithItems(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter,
        allReceipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> String {
        let answer = ItemSearchService.shared.createSearchAnswer(
            text: formatFrequencyResponse(productName: productName, matches: matches, dateFormatter: dateFormatter),
            for: matches,
            receipts: allReceipts,
            notes: Array(notes.values)
        )
        self.lastSearchAnswer = answer
        return answer.text
    }

    private func formatFrequencyResponse(
        productName: String,
        matches: [ItemSearchResult],
        dateFormatter: DateFormatter
    ) -> String {
        let count = matches.count

        var response = "You bought **\(productName)** \(count) time\(count == 1 ? "" : "s"):\n\n"

        for (index, match) in matches.enumerated() {
            let dateStr = dateFormatter.string(from: match.receiptDate)
            response += "**\(index + 1). \(dateStr)** at \(match.merchant)"

            if match.amount > 0 {
                response += " ($\(String(format: "%.2f", match.amount)))"
            }

            response += "\n"
        }

        return response
    }
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
}

// MARK: - Response Models (for future use if needed)
struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

// MARK: - Embedding Response Models
struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let model: String
}

struct EmbeddingData: Codable {
    let embedding: [Float]
    let index: Int
}

// MARK: - String Extension for Pattern Matching
extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}