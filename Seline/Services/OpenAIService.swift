import Foundation
import UIKit
import CoreLocation

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    // API key loaded from Config.swift (not committed to git)
    private let apiKey = Config.openAIAPIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"

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

        // Create the request body - using gpt-4o for high-quality, precise summaries
        let requestBody: [String: Any] = [
            "model": "gpt-4o", // Better model: ~$2.50 per 1M input tokens - excellent quality while still affordable at scale
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
            "model": "gpt-4o",
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

        // For detailed extraction, use larger token limit to preserve complete content
        // Max 12000 characters = ~3000 tokens for comprehensive extraction
        let maxContentLength = 12000
        let truncatedContent = fileContent.count > maxContentLength ? String(fileContent.prefix(maxContentLength)) + "\n[... content truncated due to length ...]" : fileContent

        // Build the extraction request with the detailed prompt
        let systemPrompt = """
        You are a detailed document extraction system. Your task is to extract COMPLETE, detailed information from documents.

        CRITICAL RULES:
        - Provide COMPREHENSIVE extraction, not a summary
        - Include ALL details, numbers, dates, amounts, items, and information
        - Preserve the structure and hierarchy of the information
        - Do NOT summarize or condense - extract everything
        - Format the output clearly with proper organization
        """

        let userMessage = """
        \(prompt)

        Document Content:
        \(truncatedContent)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 4000,  // Larger token limit for comprehensive extraction
            "temperature": 0.3   // Lower temperature for more consistent, factual extraction
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Increase timeout for large file extractions (default is 60 seconds)
        // Very large PDFs can take 5+ minutes to process
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
        Categorize the receipt into ONE of these categories only:
        - Food
        - Services
        - Transportation
        - Healthcare
        - Entertainment
        - Shopping
        - Other

        IMPORTANT RULES - Categorize as SERVICES:
        - Any AI/LLM subscriptions or payments (ChatGPT, Claude, Anthropic, OpenAI, Gemini, Copilot, etc.)
        - Any software/app subscriptions (Adobe, Microsoft, Slack, etc.)
        - Any cloud service subscriptions (AWS, Google Cloud, Azure, etc.)
        - Any recurring subscription payments or memberships
        - Any professional service payments (contractors, consultants, accountants, etc.)
        - Any utility, internet, phone, or connectivity services
        - Any maintenance, repair, or installation services
        - Even if company name is abbreviated or vague, if it looks like a service/subscription payment → Services

        IMPORTANT: Err on the side of "Services" for unclear or ambiguous company names - subscriptions and service payments are the most common "Other" misclassifications.

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
            "model": "gpt-4o",
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

        // Extract context from the query with all available data (now includes semantic enrichment)
        let context = await buildContextForQuestion(
            query: query,
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            weatherService: weatherService,
            locationsManager: locationsManager,
            navigationService: navigationService,
            conversationHistory: optimizedHistory
        )

        let systemPrompt = """
        You are a personal assistant that helps users manage their schedule, notes, emails, weather, locations, and travel.

        CRITICAL FILTERING RULES:

        **FOR EVENTS/TASKS:**
        - ONLY show events for the timeframe the user asked about (today, tomorrow, this week, etc.)
        - If user asks "show me events today", ONLY show events where date = today. Do NOT show next week's events.
        - Format events as: "Time - Event Title" (e.g., "9:00 AM - Team Meeting")
        - Include task completion status (✓ for completed, ○ for pending)
        - If no events found for requested timeframe, explicitly state "No events for [timeframe]"

        **FOR NOTES:**
        - Show all available notes unless user specifies a folder/category
        - If user mentions a specific folder, ONLY show notes from that folder
        - Include folder name when listing notes
        - Show note titles and full content

        **FOR EMAILS:**
        - Show only emails from the specified date range (today, this week, etc.)
        - If user asks "emails today", only show emails from today. Do NOT show last week's emails.
        - Include sender name, subject, and date
        - Mark emails as [Read] or [Unread]
        - Highlight important details like receipts, action items, or meeting invites

        **FOR LOCATIONS:**
        - Show all saved locations unless user specifies filters
        - User can filter by: country, city, category (folder), or rating
        - Include location name, address, category, and rating if available
        - If user asks for a specific city or country, ONLY show locations from that area

        **FOR WEATHER:**
        - Show current weather and forecast when user asks
        - Include temperature, conditions, sunrise/sunset times
        - Include 6-day forecast if available

        **FOR NAVIGATION/ETAs:**
        - Show travel time to saved destinations
        - If user asks "how far" or "how long", show ETA information

        **FOR RECEIPTS/EXPENSES:**
        - Show only receipts from the specified date range (today, this month, this year, etc.)
        - If user asks "expenses this month", only show receipts from this month
        - Include receipt name/merchant, amount, date, and category if available
        - Format as: **$AMOUNT** | Merchant Name | Date
        - Group receipts by date or merchant for clarity
        - If user asks about spending/expenses/costs, analyze patterns and totals

        GENERAL RULES:
        - Answer what the user asked for, nothing more
        - If user asks "what are my events today?", don't include emails or notes
        - Be concise and direct - avoid unnecessary information
        - Use date context provided to understand "today", "tomorrow", etc.
        - When filtering by date, be strict: if user asks for today, only show today's items

        UNIVERSAL FORMATTING SYSTEM (Apply to ALL responses):
        ════════════════════════════════════════════════════════════════

        STRUCTURE: Use this pattern for every response
        ────────────────────────────────────────────
        1. HEADLINE (1-2 lines, bold key info)
        2. Divider line (═════)
        3. SECTIONS with emoji headers (🔹 SECTION NAME)
        4. List items with visual hierarchy
        5. KEY INSIGHT or action (💡)

        TYPOGRAPHY & VISUAL ELEMENTS:
        ────────────────────────────────────────────
        • **Bold** = Key information (names, amounts, times, key facts)
        • ═══════ = Major section dividers (use at top/bottom)
        • ─────── = Subsection breaks (between groups)
        • 📌📅💰 = Category emojis (identify what type of info)
        • ├─ or • = List items (indent for hierarchy)
        • ✓ = Completion/success status
        • 💡 = Key insights or next actions
        • Code formatting: Use monospace for amounts and times like $105.42 or 12:30 PM

        SPECIFIC FORMATS BY DATA TYPE:
        ────────────────────────────────────────────

        EVENTS/SCHEDULE:
        📅 YOUR SCHEDULE - [Date]
        ═════════════════════════════════════════════

        🌅 ALL DAY
        ├─ Event Title
        ├─ Event Title

        🕐 [TIME]
        ├─ Event Title (duration if known)
        ├─ Location: [Place]
        ├─ With: [Person]

        💡 [Key insight about day/schedule]

        EMAILS:
        📬 YOUR INBOX - [Count] Messages
        ═════════════════════════════════════════════

        ⚠️  ACTION NEEDED ([count])
        ├─ **[Sender Name]**
          Subject: [Subject line]

        💰 FINANCIAL ([count])
        ├─ **[Sender Name]** - [Amount] [Status]
        ├─ **[Sender Name]** - [Amount] [Status]

        🛒 ORDERS ([count])
        ├─ **[Sender Name]** - [Description]

        💡 [Summary or action needed]

        EXPENSES/RECEIPTS:
        💰 YOUR SPENDING - [Time Period]
        ═════════════════════════════════════════════

        📊 TOTAL: **$[Amount]**

        🍔 CATEGORY ([count])
        ├─ **[Merchant]** - **$[Amount]** on [Date]
        ├─ **[Merchant]** - **$[Amount]** on [Date]

        📈 TOP CATEGORY: [Category] ([Percentage]%)

        💡 [Spending insight or comparison]

        NOTES:
        📝 YOUR NOTES - [Folder]
        ═════════════════════════════════════════════

        📌 **[Note Title]**
        └─ Key points: [Summary]
           Last updated: [When]

        📌 **[Note Title]**
        └─ Key points: [Summary]
           Last updated: [When]

        💡 [Summary or action items]

        LOCATIONS:
        📍 YOUR SAVED LOCATIONS
        ═════════════════════════════════════════════

        ☕ CAFES ([count])
        ├─ **[Location Name]** - [Area]
          Rating: **[Rating]/5** | [Distance] away

        🍽️  RESTAURANTS ([count])
        ├─ **[Location Name]** - [Cuisine]
          Rating: **[Rating]/5** | [Distance] away

        💡 [Closest option or recommendation]

        WEATHER:
        🌤️  WEATHER - [City]
        ═════════════════════════════════════════════

        Current: **[Temp]°C** - [Conditions]
        Sunrise: [Time] | Sunset: [Time]

        📅 6-DAY FORECAST
        ├─ Tomorrow: **[Temp]°C** [Conditions]
        ├─ [Day]: **[Temp]°C** [Conditions]

        💡 [Relevant weather note]

        GENERAL RULES FOR ALL FORMATS:
        ────────────────────────────────────────────
        • Start with a summary/headline
        • Use section dividers to separate major sections
        • Use emoji to identify category/type
        • Bold all key information (numbers, names, times, decisions)
        • Indent sub-items for visual hierarchy
        • End with 💡 insight or action
        • Keep lines concise and scannable
        • Remove unnecessary words
        • Ensure easy visual scanning in 2-3 seconds

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
        // Rate limiting
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Optimize conversation history to reduce token usage
        let optimizedHistory = optimizeConversationHistory(conversationHistory)

        // Extract context from the query with all available data (now includes semantic enrichment)
        let context = await buildContextForQuestion(
            query: query,
            taskManager: taskManager,
            notesManager: notesManager,
            emailService: emailService,
            weatherService: weatherService,
            locationsManager: locationsManager,
            navigationService: navigationService,
            conversationHistory: optimizedHistory
        )

        let systemPrompt = """
        You are a personal assistant that helps users manage their schedule, notes, emails, weather, locations, and travel.

        CRITICAL FILTERING RULES:

        **FOR EVENTS/TASKS:**
        - ONLY show events for the timeframe the user asked about (today, tomorrow, this week, etc.)
        - If user asks "show me events today", ONLY show events where date = today. Do NOT show next week's events.
        - Format events as: "Time - Event Title" (e.g., "9:00 AM - Team Meeting")
        - Include task completion status (✓ for completed, ○ for pending)
        - If no events found for requested timeframe, explicitly state "No events for [timeframe]"

        **FOR NOTES:**
        - Show all available notes unless user specifies a folder/category
        - If user mentions a specific folder, ONLY show notes from that folder
        - Include folder name when listing notes
        - Show note titles and full content

        **FOR EMAILS:**
        - Show only emails from the specified date range (today, this week, etc.)
        - If user asks "emails today", only show emails from today. Do NOT show last week's emails.
        - Include sender name, subject, and date
        - Mark emails as [Read] or [Unread]
        - Highlight important details like receipts, action items, or meeting invites

        **FOR LOCATIONS:**
        - Show all saved locations unless user specifies filters
        - User can filter by: country, city, category (folder), or rating
        - Include location name, address, category, and rating if available
        - If user asks for a specific city or country, ONLY show locations from that area

        **FOR WEATHER:**
        - Show current weather and forecast when user asks
        - Include temperature, conditions, sunrise/sunset times
        - Include 6-day forecast if available

        **FOR NAVIGATION/ETAs:**
        - Show travel time to saved destinations
        - If user asks "how far" or "how long", show ETA information

        **FOR RECEIPTS/EXPENSES:**
        - Show only receipts from the specified date range (today, this month, this year, etc.)
        - If user asks "expenses this month", only show receipts from this month
        - Include receipt name/merchant, amount, date, and category if available
        - Format as: **$AMOUNT** | Merchant Name | Date
        - Group receipts by date or merchant for clarity
        - If user asks about spending/expenses/costs, analyze patterns and totals

        GENERAL RULES:
        - Answer what the user asked for, nothing more
        - If user asks "what are my events today?", don't include emails or notes
        - Be concise and direct - avoid unnecessary information
        - Use date context provided to understand "today", "tomorrow", etc.
        - When filtering by date, be strict: if user asks for today, only show today's items

        UNIVERSAL FORMATTING SYSTEM (Apply to ALL responses):
        ════════════════════════════════════════════════════════════════

        STRUCTURE: Use this pattern for every response
        ────────────────────────────────────────────
        1. HEADLINE (1-2 lines, bold key info)
        2. Divider line (═════)
        3. SECTIONS with emoji headers (🔹 SECTION NAME)
        4. List items with visual hierarchy
        5. KEY INSIGHT or action (💡)

        TYPOGRAPHY & VISUAL ELEMENTS:
        ────────────────────────────────────────────
        • **Bold** = Key information (names, amounts, times, key facts)
        • ═══════ = Major section dividers (use at top/bottom)
        • ─────── = Subsection breaks (between groups)
        • 📌📅💰 = Category emojis (identify what type of info)
        • ├─ or • = List items (indent for hierarchy)
        • ✓ = Completion/success status
        • 💡 = Key insights or next actions
        • Code formatting: Use monospace for amounts and times like $105.42 or 12:30 PM

        SPECIFIC FORMATS BY DATA TYPE:
        ────────────────────────────────────────────

        EVENTS/SCHEDULE:
        📅 YOUR SCHEDULE - [Date]
        ═════════════════════════════════════════════

        🌅 ALL DAY
        ├─ Event Title
        ├─ Event Title

        🕐 [TIME]
        ├─ Event Title (duration if known)
        ├─ Location: [Place]
        ├─ With: [Person]

        💡 [Key insight about day/schedule]

        EMAILS:
        📬 YOUR INBOX - [Count] Messages
        ═════════════════════════════════════════════

        ⚠️  ACTION NEEDED ([count])
        ├─ **[Sender Name]**
          Subject: [Subject line]

        💰 FINANCIAL ([count])
        ├─ **[Sender Name]** - [Amount] [Status]
        ├─ **[Sender Name]** - [Amount] [Status]

        🛒 ORDERS ([count])
        ├─ **[Sender Name]** - [Description]

        💡 [Summary or action needed]

        EXPENSES/RECEIPTS:
        💰 YOUR SPENDING - [Time Period]
        ═════════════════════════════════════════════

        📊 TOTAL: **$[Amount]**

        🍔 CATEGORY ([count])
        ├─ **[Merchant]** - **$[Amount]** on [Date]
        ├─ **[Merchant]** - **$[Amount]** on [Date]

        📈 TOP CATEGORY: [Category] ([Percentage]%)

        💡 [Spending insight or comparison]

        NOTES:
        📝 YOUR NOTES - [Folder]
        ═════════════════════════════════════════════

        📌 **[Note Title]**
        └─ Key points: [Summary]
           Last updated: [When]

        📌 **[Note Title]**
        └─ Key points: [Summary]
           Last updated: [When]

        💡 [Summary or action items]

        LOCATIONS:
        📍 YOUR SAVED LOCATIONS
        ═════════════════════════════════════════════

        ☕ CAFES ([count])
        ├─ **[Location Name]** - [Area]
          Rating: **[Rating]/5** | [Distance] away

        🍽️  RESTAURANTS ([count])
        ├─ **[Location Name]** - [Cuisine]
          Rating: **[Rating]/5** | [Distance] away

        💡 [Closest option or recommendation]

        WEATHER:
        🌤️  WEATHER - [City]
        ═════════════════════════════════════════════

        Current: **[Temp]°C** - [Conditions]
        Sunrise: [Time] | Sunset: [Time]

        📅 6-DAY FORECAST
        ├─ Tomorrow: **[Temp]°C** [Conditions]
        ├─ [Day]: **[Temp]°C** [Conditions]

        💡 [Relevant weather note]

        GENERAL RULES FOR ALL FORMATS:
        ────────────────────────────────────────────
        • Start with a summary/headline
        • Use section dividers to separate major sections
        • Use emoji to identify category/type
        • Bold all key information (numbers, names, times, decisions)
        • Indent sub-items for visual hierarchy
        • End with 💡 insight or action
        • Keep lines concise and scannable
        • Remove unnecessary words
        • Ensure easy visual scanning in 2-3 seconds

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
        try await makeOpenAIStreamingRequest(url: url, requestBody: requestBody, onChunk: onChunk)
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

        if httpResponse.statusCode != 200 {
            throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Process streaming response
        var buffer = ""
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
        let locationKeywords = ["location", "locations", "place", "places", "where", "saved", "restaurant", "cafe"]
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
            return "Use this format: Your saved locations: • **Name** | Category | Location | Rating: X/5"
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
    private func optimizeConversationHistory(_ history: [ConversationMessage]) -> [ConversationMessage] {
        // Keep the last 10 messages for sufficient context but avoid token waste
        // For most conversations, this is enough to maintain continuity
        let maxMessages = 10

        if history.count <= maxMessages {
            return history
        }

        // Return only the most recent messages
        return Array(history.suffix(maxMessages))
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

    /// Filter emails to only those within the requested date range
    private func filterEmailsByDateRange(_ emails: [Email], range: (start: Date, end: Date), currentDate: Date) -> [Email] {
        let calendar = Calendar.current

        return emails.filter { email in
            let emailStartOfDay = calendar.startOfDay(for: email.timestamp)
            return emailStartOfDay >= range.start && emailStartOfDay < range.end
        }
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
        // This week
        else if lowerQuery.contains("this week") || (lowerQuery.contains("week") && !lowerQuery.contains("next")) {
            startDate = todayStart
            endDate = calendar.date(byAdding: .day, value: 7, to: todayStart)!
        }
        // Next week
        else if lowerQuery.contains("next week") {
            startDate = calendar.date(byAdding: .day, value: 7, to: todayStart)!
            endDate = calendar.date(byAdding: .day, value: 14, to: todayStart)!
        }
        // This month
        else if lowerQuery.contains("this month") || (lowerQuery.contains("month") && !lowerQuery.contains("next")) {
            startDate = todayStart
            endDate = calendar.date(byAdding: .month, value: 1, to: todayStart)!
        }
        // Next month
        else if lowerQuery.contains("next month") {
            startDate = calendar.date(byAdding: .month, value: 1, to: todayStart)!
            endDate = calendar.date(byAdding: .month, value: 2, to: todayStart)!
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
}

// MARK: - Response Models (for future use if needed)
struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
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