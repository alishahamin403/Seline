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
    private var queryCache: [String: CachedQueryResponse] = [:]
    private let cacheQueue = DispatchQueue(label: "cache-queue", attributes: .concurrent)
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes cache

    private init() {}

    // MARK: - Cache Models
    struct CachedQueryResponse {
        let response: VoiceQueryResponse
        let timestamp: Date

        func isExpired() -> Bool {
            return Date().timeIntervalSince(timestamp) > 300 // 5 minutes
        }
    }

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

        // Preserve table structure better for receipts
        text = text.replacingOccurrences(of: "<tr[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<td[^>]*>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</td>", with: " | ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<th[^>]*>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</th>", with: " | ", options: .regularExpression)

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

        // Extract emphasized text (preserve emphasis indicators)
        text = text.replacingOccurrences(
            of: "<(strong|b)[^>]*>([^<]+)</\\1>",
            with: "**$2**",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: "<(em|i)[^>]*>([^<]+)</\\1>",
            with: "*$2*",
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

        let systemPrompt = """
        You are a helpful assistant that cleans up messy text into well-structured, sensible content.

        FORMATTING RULES:
        - Fix grammar and spelling errors
        - Use casual, friendly tone
        - Improve sentence structure and flow
        - Preserve the original meaning and all key information
        - Remove unnecessary repetition
        - Keep the same general length as the original

        TABLE FORMATTING (CRITICAL):
        When content contains structured data, ALWAYS format as a proper markdown table:
        - Use tables for: comparisons, schedules, lists with multiple attributes, pros/cons, feature lists, item specifications, categorized data
        - Table format: Use pipe symbols (|) to separate columns and hyphens (---) for header separator
        - Example table format:

        | Column 1 | Column 2 | Column 3 |
        |----------|----------|----------|
        | Data 1   | Data 2   | Data 3   |
        | Data 4   | Data 5   | Data 6   |

        - Recognize when information naturally fits a table structure (e.g., "Product A costs $10, Product B costs $20" → table with Product and Price columns)
        - For schedules, use Day/Time/Activity columns
        - For comparisons, use Feature/Option A/Option B columns
        - For lists with attributes, use Item/Description/Details columns

        TODO LIST FORMATTING:
        When content contains action items, tasks, or checklists, format as markdown todo lists:
        - Use format: - [ ] Task description (uncompleted) or - [x] Task description (completed)
        - Example:

        - [ ] Buy groceries
        - [ ] Call mom
        - [x] Finish project report

        - Auto-detect todo-like content: "need to do", "tasks", "checklist", "todo", "action items", etc.
        - Any list of actionable items should be formatted as todos

        TEXT FORMATTING:
        - Use **bold** for emphasis (not ** visible in output)
        - Use *italic* for subtle emphasis (not * visible in output)
        - Use bullet points (•) for simple non-actionable lists
        - Use headings (# ## ###) for sections

        IMPORTANT: Output clean markdown. Never show raw ** or * symbols - they are formatting markers only.
        """

        let userPrompt = """
        Clean up this text to make it clear and well-written:

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
    private func makeOpenAIRequest(url: URL, requestBody: [String: Any]) async throws -> String {
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

    // MARK: - Cache Management

    private func getCachedResponse(for query: String) -> VoiceQueryResponse? {
        var result: VoiceQueryResponse? = nil
        cacheQueue.sync {
            if let cached = queryCache[query], !cached.isExpired() {
                result = cached.response
            } else if queryCache[query] != nil {
                // Remove expired cache
                DispatchQueue.main.async {
                    self.cacheQueue.async(flags: .barrier) {
                        self.queryCache.removeValue(forKey: query)
                    }
                }
            }
        }
        return result
    }

    private func cacheResponse(_ response: VoiceQueryResponse, for query: String) {
        cacheQueue.async(flags: .barrier) {
            self.queryCache[query] = CachedQueryResponse(response: response, timestamp: Date())
        }
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

    func processVoiceQuery(query: String, events: [TaskItem], notes: [Note], locations: [SavedPlace], currentLocation: CLLocation?, weatherData: WeatherData?, allNewsByCategory: [(category: String, articles: [NewsArticle])], inboxEmails: [Email], sentEmails: [Email], conversationHistory: [[String: String]]? = nil) async throws -> VoiceQueryResponse {
        // OPTIMIZATION 5: Check cache first
        if let cachedResponse = getCachedResponse(for: query) {
            print("✅ Returning cached response for query: \(query)")
            return cachedResponse
        }

        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // OPTIMIZATION 1 & 3: Detect intent first (fast classification)
        // Always returns a valid intent (falls back to "general" if detection times out)
        let detectedIntent = await detectIntentOnly(query: query)
        print("🎯 Intent detected: \(detectedIntent)")

        // Build OPTIMIZED context with actual content for AI to analyze
        // Sort data by relevance before sending
        let sortedEvents = events.sorted { event1, event2 in
            // Prioritize upcoming events, then recent past events
            let date1 = event1.targetDate ?? event1.scheduledTime ?? event1.createdAt
            let date2 = event2.targetDate ?? event2.scheduledTime ?? event2.createdAt
            let now = Date()

            // Both in future: closer date first
            if date1 >= now && date2 >= now {
                return date1 < date2
            }
            // Both in past: more recent first
            if date1 < now && date2 < now {
                return date1 > date2
            }
            // One future, one past: future first
            return date1 >= now
        }

        // OPTIMIZATION 3: Adaptive event count based on intent
        let eventsCount = detectedIntent == "calendar" ? 15 : 8

        // Events: Send adaptive count of most relevant events (sorted by date)
        let eventsData = sortedEvents.prefix(eventsCount).map { event in
            var eventInfo = "- \(event.title)"

            // Use targetDate for the primary date if available (this is the actual event date)
            // Otherwise fall back to scheduledTime
            let eventDate = event.targetDate ?? event.scheduledTime

            if let date = eventDate {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMMM d, yyyy" // e.g., "Wednesday, October 3, 2025"
                eventInfo += " on \(dateFormatter.string(from: date))"

                // Add time if available and different from date
                if let scheduledTime = event.scheduledTime, !Calendar.current.isDate(scheduledTime, inSameDayAs: date) || event.scheduledTime != nil {
                    let timeFormatter = DateFormatter()
                    timeFormatter.timeStyle = .short
                    eventInfo += " at \(timeFormatter.string(from: event.scheduledTime!))"
                }
            }

            // Add recurring info if applicable
            if event.isRecurring, let frequency = event.recurrenceFrequency {
                eventInfo += " (recurring \(frequency.rawValue))"
            }

            if let description = event.description, !description.isEmpty {
                eventInfo += " | Notes: \(description.prefix(100))"
            }
            return eventInfo
        }.joined(separator: "\n")

        // Sort notes by most recently modified first
        let sortedNotes = notes.sorted { $0.dateModified > $1.dateModified }

        // OPTIMIZATION 6: Adaptive preview size based on intent
        // For notes-focused queries, use full preview; for others, use reduced preview
        let previewLength = detectedIntent == "notes" ? 150 : 75
        let notesCount = detectedIntent == "notes" ? 12 : 6 // Reduce notes sent for other intents

        // Notes: Send adaptive count with preview length
        let notesData = sortedNotes.prefix(notesCount).map { note in
            var noteInfo = "- \(note.title)"
            let content = note.content.prefix(previewLength)
            if !content.isEmpty {
                noteInfo += " | Preview: \(content)"
            }
            return noteInfo
        }.joined(separator: "\n")

        // Sort locations by most recently modified first
        let sortedLocations = locations.sorted { $0.dateModified > $1.dateModified }

        // OPTIMIZATION 3: Adaptive location count based on intent
        let locationsCount = detectedIntent == "locations" ? 10 : 5

        // Locations: Send adaptive count of most recently modified locations
        let locationsData = sortedLocations.prefix(locationsCount).map { place in
            var placeInfo = "- \(place.displayName) (\(place.category))"
            if !place.formattedAddress.isEmpty {
                placeInfo += " | Address: \(place.formattedAddress)"
            }

            // Add opening hours if available
            if let hours = place.openingHours, !hours.isEmpty {
                placeInfo += " | Hours: \(hours.joined(separator: ", "))"
            }

            // Add open/closed status if available
            if let isOpen = place.isOpenNow {
                placeInfo += " | Currently: \(isOpen ? "Open" : "Closed")"
            }

            // Add distance and ETA if current location is available
            if let currentLoc = currentLocation {
                let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let distance = currentLoc.distance(from: placeLocation)
                let distanceKm = distance / 1000.0
                placeInfo += String(format: " | Distance: %.1f km", distanceKm)

                // Estimate travel time (assuming ~40 km/h average speed)
                let estimatedTimeMinutes = Int((distanceKm / 40.0) * 60.0)
                placeInfo += " (~\(estimatedTimeMinutes) min drive)"
            }

            return placeInfo
        }.joined(separator: "\n")

        // Format email data (inbox and sent) - sorted by most recent
        let sortedInboxEmails = inboxEmails.sorted { $0.timestamp > $1.timestamp }
        let inboxEmailsData = sortedInboxEmails.prefix(8).map { email in
            var emailInfo = "- [\(email.sender.displayName)] \(email.subject)"
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            emailInfo += " (\(formatter.string(from: email.timestamp)))"
            if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                emailInfo += " | \(aiSummary.prefix(100))"
            }
            return emailInfo
        }.joined(separator: "\n")

        let sortedSentEmails = sentEmails.sorted { $0.timestamp > $1.timestamp }
        let sentEmailsData = sortedSentEmails.prefix(8).map { email in
            var emailInfo = "- [To: \(email.recipients.first?.displayName ?? "Unknown")] \(email.subject)"
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            emailInfo += " (\(formatter.string(from: email.timestamp)))"
            if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                emailInfo += " | \(aiSummary.prefix(100))"
            }
            return emailInfo
        }.joined(separator: "\n")

        // Format weather data
        var weatherInfo = "Not available"
        if let weather = weatherData {
            let dailyForecast = weather.dailyForecasts.map { forecast in
                "\(forecast.day): High \(forecast.highTemperature)°C, Low \(forecast.lowTemperature)°C"
            }.joined(separator: ", ")

            weatherInfo = """
            Location: \(weather.locationName)
            Current: \(weather.temperature)°C, \(weather.description)
            Next 6 days: \(dailyForecast)
            Sunrise: \(formatTime(weather.sunrise))
            Sunset: \(formatTime(weather.sunset))
            """
        }

        // Format news data by category (limited to save tokens - reduced for faster processing)
        var newsInfo = "Not available"
        if !allNewsByCategory.isEmpty {
            newsInfo = allNewsByCategory.prefix(2).map { categoryData in
                let categoryName = categoryData.category
                // Limit to 2 articles per category to save tokens
                let articles = categoryData.articles.prefix(2).map { article in
                    return "  - \(article.title) (\(article.source))"
                }.joined(separator: "\n")
                return "\(categoryName):\n\(articles)"
            }.joined(separator: "\n\n")
        }

        // Create "all titles" sections for complete visibility
        let allNoteTitles = notes.map { "• \($0.title)" }.joined(separator: "\n")
        let allEventTitles = events.map { event in
            let date = event.targetDate ?? event.scheduledTime
            if let date = date {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                return "• \(event.title) (\(formatter.string(from: date)))"
            }
            return "• \(event.title)"
        }.joined(separator: "\n")
        let allLocationNames = locations.map { "• \($0.displayName)" }.joined(separator: "\n")

        // Get current date and time for context using local calendar and timezone
        let now = Date()

        // Create calendar with explicit local timezone
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Extract date components in local timezone (including weekday)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)

        // CRITICAL: Use components to build date string to ensure correct local date
        let year = components.year!
        let month = components.month!
        let day = components.day!
        let _ = components.hour!
        let _ = components.minute!

        // Get weekday number (1=Sunday, 2=Monday, ..., 7=Saturday)
        // Must use components with timezone to get the correct weekday for local date
        let weekdayNumber = components.weekday!

        // Get weekday name with explicit timezone
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.timeZone = TimeZone.current
        weekdayFormatter.locale = Locale.current
        let weekdayName = weekdayFormatter.string(from: now)

        // Get month name with explicit timezone
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        monthFormatter.timeZone = TimeZone.current
        monthFormatter.locale = Locale.current
        let monthName = monthFormatter.string(from: now)

        // Format time with explicit timezone
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.timeZone = TimeZone.current
        timeFormatter.locale = Locale.current
        let timeString = timeFormatter.string(from: now)

        // Build the date string explicitly using components
        let currentDateTime = "\(weekdayName), \(monthName) \(day), \(year) at \(timeString)"


        let systemPrompt = """
        You are a helpful AI assistant that can read and analyze the user's calendar events, notes, emails, saved locations, current weather, and recent news. You can also CREATE events and notes when requested.

        CRITICAL CONTEXT:
        Current Date and Time: \(currentDateTime)

        When the user asks about "today", "tonight", "this week", or any time-relative queries, use the current date above as your reference point.

        Your task is to:
        1. Determine the user's intent (calendar, notes, emails, locations, weather, news, or general)
        2. DETECT if the user wants to CREATE an event or note
        3. Extract search parameters from the query
        4. READ AND ANALYZE the actual content of notes, events, emails, locations, weather, and news when asked
        5. Provide summaries, details, or answer questions about the content
        6. Remember previous conversation context and provide follow-up responses

        === EVENT & NOTE CREATION ===

        When the user requests to create an event or note (using phrases like "create event", "schedule", "remind me to", "create note", "take a note", "remember that"):

        EVENT CREATION:
        - Extract: title, date, time, end time, description, recurrence

        **⚠️ CRITICAL - ACTION DETECTION PRIORITY:**
        IF user mentions ANY of these keywords, ALWAYS check for update/delete actions FIRST:
        - "reschedule", "move", "change", "shift", "delete", "remove", "cancel"
        These MUST trigger action="update_event" or action="delete_event", NOT generic calendar queries

        **CRITICAL DATE PARSING RULES - READ CAREFULLY:**

        TODAY IS: \(weekdayName), \(monthName) \(day), \(year)
        TODAY'S ISO DATE: \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))
        TODAY'S WEEKDAY NUMBER: \(weekdayNumber)

        WEEKDAY NUMBERING SYSTEM (MUST USE THIS):
        1 = Sunday
        2 = Monday
        3 = Tuesday
        4 = Wednesday
        5 = Thursday
        6 = Friday
        7 = Saturday

        NEVER RETURN A DATE BEFORE: \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))

        FORMULA FOR "next [weekday]":
        1. Current weekday number = \(weekdayNumber) (today is \(weekdayName))
        2. Target weekday number = [1-7 from table above]
        3. If target > current: days_to_add = target - current
        4. If target <= current: days_to_add = (7 - current) + target
        5. Result = \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)) + days_to_add days

        CONCRETE EXAMPLES FROM TODAY (\(weekdayName) = weekday \(weekdayNumber)):
          * "today" → \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)) (0 days)
          * "tomorrow" → \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)) + 1 day
          * "in 3 days" → \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)) + 3 days
          * "next Sunday" → weekday 1 → \(weekdayNumber < 1 ? "1-\(weekdayNumber)=\(1-weekdayNumber)" : "(7-\(weekdayNumber))+1=\((7-weekdayNumber)+1)") days → calculate exact date
          * "next Monday" → weekday 2 → \(weekdayNumber < 2 ? "2-\(weekdayNumber)=\(2-weekdayNumber)" : "(7-\(weekdayNumber))+2=\((7-weekdayNumber)+2)") days → calculate exact date
          * "next Tuesday" → weekday 3 → \(weekdayNumber < 3 ? "3-\(weekdayNumber)=\(3-weekdayNumber)" : "(7-\(weekdayNumber))+3=\((7-weekdayNumber)+3)") days → calculate exact date
          * "next Wednesday" → weekday 4 → \(weekdayNumber < 4 ? "4-\(weekdayNumber)=\(4-weekdayNumber)" : "(7-\(weekdayNumber))+4=\((7-weekdayNumber)+4)") days → calculate exact date
          * "next Thursday" → weekday 5 → \(weekdayNumber < 5 ? "5-\(weekdayNumber)=\(5-weekdayNumber)" : "(7-\(weekdayNumber))+5=\((7-weekdayNumber)+5)") days → calculate exact date
          * "next Friday" → weekday 6 → \(weekdayNumber < 6 ? "6-\(weekdayNumber)=\(6-weekdayNumber)" : "(7-\(weekdayNumber))+6=\((7-weekdayNumber)+6)") days → calculate exact date
          * "next Saturday" → weekday 7 → \(weekdayNumber < 7 ? "7-\(weekdayNumber)=\(7-weekdayNumber)" : "(7-\(weekdayNumber))+7=\((7-weekdayNumber)+7)") days → calculate exact date

        DATE RANGE FOR QUERIES (searchQuery intent):
        When the user asks about a date range like "this week until Sunday", "events until Sunday", etc.:
        - Calculate startDate as today's date: \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))
        - Calculate endDate based on the specified weekday (Sunday, Monday, etc.)
        - Example: If today is \(weekdayName) and user asks "until Sunday":
          * If today is Sunday: endDate = today (\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)))
          * If today is Monday-Saturday: endDate = this Sunday (the next Sunday in the same week)
          * CRITICAL: ONLY go to the specified weekday, NOT beyond it!
          * DO NOT include Monday if user said "until Sunday"
        - For "this week" without a specific day: endDate = this coming Sunday
        - For "this month": endDate = last day of current month
        - For "today": startDate and endDate = \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))

        VALIDATION:
          * NEVER use yesterday's date or any past date
          * ALWAYS use the formula above for "next [weekday]"
          * Double-check: count the days from today to verify your calculation
          * Convert all dates to ISO8601 format (YYYY-MM-DD)
          * When user specifies "until [day]", STOP at that day - do not include the next day
        - Time parsing:
          * "6 pm" = 18:00
          * "8:30 am" = 08:30
          * Format as HH:mm (24-hour)
        - Recurrence (smart defaults):
          * "every day" = "daily"
          * "weekdays" or "every weekday" = "daily" (note: app will handle Mon-Fri logic)
          * "every week" or "weekly" = "weekly"
          * "every 2 weeks" or "biweekly" = "biweekly"
          * "every month" or "monthly" = "monthly"
          * "every year" or "yearly" = "yearly"
        - Ambiguity detection:
          * If date is missing: set requiresFollowUp=true, ask "What date?"
          * If time is vague (e.g., "in the morning"): set requiresFollowUp=true, ask "What time?"
          * If "all day" event: set isAllDay=true, time=null

        NOTE CREATION:
        - Extract: content (the note body)
        - Generate a concise, descriptive title (3-6 words) based on the content
        - Auto-format the content:
          * Detect lists: "1) xyz 2) abc" → "1. xyz\n2. abc"
          * Detect bullet points: "xyz, abc, def" → "• xyz\n• abc\n• def"
          * Add headings for structure if content has sections
          * Preserve line breaks and formatting
        - The formattedContent should be well-structured markdown

        EVENT UPDATE (MOST COMMON KEYWORDS):
        🔴 KEY PHRASES TO DETECT UPDATE ACTION:
        "reschedule", "move", "change", "shift", "push", "reschedule to", "move to", "change to"

        - When user says: "move [event] to [date]", "reschedule [event] to [date]", "change [event] to [date]", "shift [event] to [date]", "push [event] to [date]"
        - OR phrases like: "change [event] from [old date] to [new date]", "[event] from today to tomorrow", "move [event] from [date1] to [date2]"
        - OR: "reschedule [event]" or "reschedule [event] to [new time]"
        - Search through all event titles to find matching event
        - Extract the target event by matching title (case-insensitive partial match is OK)
        - IGNORE the "from [old date]" part and FOCUS ONLY on the target date after "to"
        - Calculate the new date using the same date parsing rules as EVENT CREATION
        - If time is mentioned, extract it too; otherwise leave newTime as null
        - **CRITICAL**: If user says "reschedule X", ALWAYS set action="update_event" with eventUpdateData
        - Set action="update_event" and populate eventUpdateData with:
          * eventTitle: exact or best-matching title of the event to update
          * newDate: ISO8601 date string (YYYY-MM-DD) - MUST be >= today's date (use the date AFTER "to")
          * newTime: HH:mm format or null (optional)
          * newEndTime: HH:mm format or null (optional)

        NOTE UPDATE:
        - When user says "update [note name] with [new content]" or "add to [note name]: [content]"
        - Search through all note titles to find matching note
        - Extract the new content to be added
        - Auto-format the new content
        - Set action="update_note" and populate noteUpdateData with:
          * noteTitle: exact title of the note to update
          * contentToAdd: raw new content
          * formattedContentToAdd: formatted new content

        EVENT DELETION:
        - When user says "delete [event name]", "remove [event]", or "cancel [event]"
        - Search through all event titles to find matching event
        - Extract the target event by matching title (case-insensitive partial match is OK)
        - Set action="delete_event" and populate deletionData with:
          * itemType: "event"
          * itemTitle: exact or best-matching title of the event to delete
          * deleteAllOccurrences: true if user says "all occurrences" or "every time", null/false otherwise

        NOTE DELETION:
        - When user says "delete [note name]", "remove [note]", or "clear [note]"
        - Search through all note titles to find matching note
        - Extract the target note by matching title (case-insensitive partial match is OK)
        - Set action="delete_note" and populate deletionData with:
          * itemType: "note"
          * itemTitle: exact or best-matching title of the note to delete
          * deleteAllOccurrences: null (not applicable for notes)

        IMPORTANT: When the user asks about content (e.g., "summarize my monthly expenses note", "what's in my passwords note", "what emails do I have", "what's the weather", "what's in the news"),
        you MUST read and analyze the actual content provided below, not just the titles.

        === COMPLETE INVENTORY (All Items by Title) ===

        All Note Titles (\(notes.count) total):
        \(allNoteTitles.isEmpty ? "None" : allNoteTitles)

        All Event Titles (\(events.count) total):
        \(allEventTitles.isEmpty ? "None" : allEventTitles)

        All Location Names (\(locations.count) total):
        \(allLocationNames.isEmpty ? "None" : allLocationNames)

        === DETAILED CONTENT (Most Recent/Relevant Items) ===

        Note: The sections below show DETAILED content for the most recently modified items.
        If a user asks about an item not shown in detail below, check the "All Titles" section above.

        Recent Calendar Events (top 15 upcoming/recent, with full details):
        \(eventsData.isEmpty ? "None" : eventsData)

        Recent Notes (top 12 most recently modified, with 150-char preview):
        \(notesData.isEmpty ? "None" : notesData)

        Recent Inbox Emails (top 8 most recent, with AI summaries):
        \(inboxEmailsData.isEmpty ? "None" : inboxEmailsData)

        Recent Sent Emails (top 8 most recent, with AI summaries):
        \(sentEmailsData.isEmpty ? "None" : sentEmailsData)

        Recent Saved Locations (top 10 most recently modified):
        \(locationsData.isEmpty ? "None" : locationsData)

        Current Weather:
        \(weatherInfo)

        Recent News Headlines (organized by category):
        \(newsInfo)

        **🔴 MANDATORY ACTION DETECTION - NON-NEGOTIABLE:**
        When you see keywords like "reschedule", "move", "change" + a date reference:
        1. Extract the event name
        2. Extract the TARGET date (the new date they want)
        3. ALWAYS populate eventUpdateData, NEVER leave it null
        4. Set action="update_event"
        5. Do NOT just provide a generic response without eventUpdateData

        Response format (MUST be valid JSON):
        {
          "intent": "calendar" | "notes" | "locations" | "general",
          "searchQuery": "keywords to search for",
          "dateRange": {
            "startDate": "ISO8601 date string or null",
            "endDate": "ISO8601 date string or null"
          },
          "category": "location category if relevant",
          "response": "natural language response to the user",
          "action": "create_event" | "update_event" | "delete_event" | "create_note" | "update_note" | "delete_note" | "none",
          "eventData": {
            "title": "string",
            "description": "string or null",
            "date": "YYYY-MM-DD (MUST be >= \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day)), NEVER a past date!)",
            "time": "HH:mm or null",
            "endTime": "HH:mm or null",
            "recurrenceFrequency": "daily|weekly|biweekly|monthly|yearly or null",
            "isAllDay": boolean,
            "requiresFollowUp": boolean
          } or null,
          "eventUpdateData": {
            "eventTitle": "exact or best-matching title of event to reschedule",
            "newDate": "YYYY-MM-DD (MUST be >= today's date)",
            "newTime": "HH:mm or null",
            "newEndTime": "HH:mm or null"
          } or null,
          "noteData": {
            "title": "generated title (3-6 words)",
            "content": "raw transcribed content",
            "formattedContent": "auto-formatted markdown content"
          } or null,
          "noteUpdateData": {
            "noteTitle": "exact title of note to update",
            "contentToAdd": "raw new content to add",
            "formattedContentToAdd": "formatted new content"
          } or null,
          "deletionData": {
            "itemType": "event" | "note",
            "itemTitle": "exact or best-matching title of item to delete",
            "deleteAllOccurrences": boolean or null
          } or null,
          "followUpQuestion": "string or null (e.g., 'What time should I schedule this?')"
        }

        CRITICAL ACTION DETECTION:
        **IMPORTANT**: If the user mentions moving/changing/rescheduling an event (even if they say "from X to Y"), ALWAYS:
        1. Set intent="calendar"
        2. Set action="update_event" (NOT "create_event")
        3. Populate eventUpdateData with the TARGET date (the date AFTER "to")
        4. IGNORE the source date (the date AFTER "from")

        Intent Detection Rules:
        - "calendar": Queries about events, appointments, tasks, schedules, birthdays (e.g., "when did I...", "what's on my calendar", "upcoming birthdays")
          * ALSO for creating events: set action="create_event", populate eventData
          * ALSO for updating/rescheduling events: set action="update_event", populate eventUpdateData
        - "notes": Queries about notes, memos, saved information (e.g., "show me notes about...", "what did I write")
          * ALSO for creating notes: set action="create_note", populate noteData
        - "locations": Queries about places, spots, addresses (e.g., "food spots nearby", "restaurants", "where is...")
        - "general": General questions or conversation, email queries

        Action Detection Examples (WITH EXACT DATE CALCULATIONS):
        - "create an event for today to go gym at 6 pm" → action="create_event", date="\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))", time="18:00"
        - "schedule a meeting tomorrow at 2 pm" → action="create_event", date=add 1 day to \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))
        - "remind me about the dentist next Tuesday" → action="create_event", use weekday formula: Tuesday=3, current=\(weekdayNumber), calculate days
        - "remind me to take medication every day at 8 am" → action="create_event", recurrence="daily"
        - "create a note about list of things to do in Greece" → action="create_note", format as list
        - "move gym to tomorrow" → action="update_event", find event titled "gym", newDate=tomorrow's date
        - "reschedule lunch meeting to next Monday" → action="update_event", find event with "lunch" or "meeting", calculate next Monday
        - "change dentist appointment to 3 pm tomorrow" → action="update_event", find "dentist" event, newDate=tomorrow, newTime="15:00"
        - "change gym from today to tomorrow" → action="update_event", find "gym" event, IGNORE "from today", use newDate=tomorrow
        - "move event from today to tomorrow" → action="update_event", find "event" by title, FOCUS on "to tomorrow", newDate=tomorrow
        - "shift meeting from Tuesday to Friday" → action="update_event", find "meeting", IGNORE Tuesday, newDate=next Friday
        - "delete my gym event" → action="delete_event", itemType="event", itemTitle="gym", deleteAllOccurrences=false (unless they said "all")
        - "remove the dentist appointment" → action="delete_event", find "dentist" event, deleteAllOccurrences=false
        - "cancel my daily standup all occurrences" → action="delete_event", itemTitle="daily standup", deleteAllOccurrences=true
        - "delete my grocery list note" → action="delete_note", itemType="note", itemTitle="grocery list"
        - "remove the meeting notes" → action="delete_note", find note with "meeting" in title

        CRITICAL REMINDER:
        - Today is \(weekdayName) (weekday #\(weekdayNumber))
        - TODAY'S DATE: "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
        - ALWAYS use the weekday formula for "next [day]" calculations
        - Verify your arithmetic: count the days from today to make sure it's correct
        - "take a note that I need to buy milk eggs and bread" → action="create_note"
        - "remember that the wifi password is xyz123" → action="create_note"
        - "update my groceries note with add bananas and apples" → action="update_note", find note titled "groceries"
        - "add to my meeting notes: discussed Q4 budget" → action="update_note"

        Key Guidelines:
        - **Two-tier data access**: You have ALL titles in the "Complete Inventory" section, but only recent items have full content
        - **When item is in titles but not in detailed section**: Acknowledge you see it exists and offer to help: "I see you have a note titled X. While I don't have the full content loaded, I can see it exists. Would you like me to help you find it in the app?"
        - For calendar queries: Extract date references and convert to ISO8601 format. Check both "All Event Titles" and "Recent Calendar Events" sections
        - For notes queries:
          * First check "All Note Titles" to see if the note exists
          * If found in titles but not in detailed content, acknowledge its existence
          * If found in detailed content, provide the preview or summarize
        - For location queries:
          * Extract category (restaurant, coffee shop, gas station, etc.)
          * ALWAYS include distance and travel time when available in the data
          * ALWAYS include opening hours and open/closed status when available in the data
          * Format: "Place Name - X km away (~Y min drive), Hours: [hours], Currently: Open/Closed"
        - For email queries: Reference inbox and sent emails with summaries (showing 8 most recent from each)
        - For news queries:
          * News is organized by category (General, Business, Technology, Sports, Entertainment, Health)
          * When user asks about a specific category, list the headlines from that category
          * When user asks about "the news" or "headlines", provide a mix from different categories
        - For birthday queries:
          * Search through both "All Event Titles" and "Recent Calendar Events" for events containing "birthday"
          * CRITICAL: Each event has its OWN specific date. Read the date for EACH event individually
          * When listing birthdays, include the person's name AND their specific date
          * Never assume all events are on the same date - each event has its own unique date
          * Format: "Person's birthday on [full date]" for each person
        - Keep responses conversational and helpful (2-3 sentences)
        - Reference previous conversation context when answering follow-up questions

        FORMATTING RULES FOR RESPONSES:
        - When providing lists of items, use bullet points with "- " prefix (e.g., "- Item 1")
        - When providing numbered steps or rankings, use "1. ", "2. ", etc.
        - Use bullet points for weather forecasts, news headlines, or any list of items
        - Keep bullet points concise (one line each when possible)
        - Separate sections with blank lines for better readability
        - DO NOT use markdown formatting like **bold** or *italic* - use plain text only
        - For event titles, dates, and times, just use regular text without any special symbols

        IMPORTANT: Always check the "Complete Inventory" section first to see what exists, then provide details from the "Detailed Content" section if available.
        """

        let userPrompt = """
        User query: "\(query)"

        Analyze this query and provide your response in JSON format.
        """

        // Build messages array with conversation history
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add conversation history if available (exclude the current query which is already added)
        if let history = conversationHistory, !history.isEmpty {
            // Only include last 4 messages to save tokens and speed up processing (reduced from 6)
            let recentHistory = Array(history.suffix(4))
            messages.append(contentsOf: recentHistory as [[String: Any]])
        }

        // Add current user query
        messages.append(["role": "user", "content": userPrompt])

        // OPTIMIZATION 4: Enable streaming for faster perceived response times
        // Note: Streaming mode doesn't support response_format constraint, but the model
        // is instructed to return valid JSON in the system prompt, so output will still be JSON
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // 16x cheaper than gpt-4o ($0.15 vs $2.50 per 1M input tokens)
            "messages": messages,
            "max_tokens": 600, // Increased to allow complete responses (news, lists, etc.)
            "temperature": 0.3,
            "stream": true // Enable streaming for incremental response delivery
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0 // 30 second timeout for voice queries

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("❌ Failed to serialize request body: \(error)")
            throw SummaryError.networkError(error)
        }

        do {
            // Use URLSession with configured timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            let session = URLSession(configuration: config)

            let (data, response) = try await session.data(for: request)

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

            // OPTIMIZATION 4: Parse streaming response
            // Extract the complete message from SSE format
            let content: String
            if let streamedContent = parseStreamingResponse(data: data) {
                content = streamedContent
            } else {
                throw SummaryError.decodingError
            }

            // Parse JSON response with better error handling
            guard let contentData = content.data(using: .utf8) else {
                throw SummaryError.decodingError
            }

            // Validate that the content is valid JSON before decoding
            do {
                _ = try JSONSerialization.jsonObject(with: contentData)
            } catch {

                // Return a helpful error response instead of crashing
                return VoiceQueryResponse(
                    intent: "general",
                    searchQuery: nil,
                    dateRange: nil,
                    category: nil,
                    response: "I apologize, but I encountered an error processing your request. The response was too long. Could you try asking a more specific question?",
                    action: nil,
                    eventData: nil,
                    eventUpdateData: nil,
                    noteData: nil,
                    noteUpdateData: nil,
                    deletionData: nil,
                    followUpQuestion: nil
                )
            }

            let decoder = JSONDecoder()
            do {
                let voiceResponse = try decoder.decode(VoiceQueryResponse.self, from: contentData)

                // OPTIMIZATION 5: Cache the response
                self.cacheResponse(voiceResponse, for: query)

                return voiceResponse
            } catch {
                // Return a helpful error response instead of crashing
                return VoiceQueryResponse(
                    intent: "general",
                    searchQuery: nil,
                    dateRange: nil,
                    category: nil,
                    response: "I apologize, but I encountered an error understanding the response. Could you try rephrasing your question?",
                    action: nil,
                    eventData: nil,
                    eventUpdateData: nil,
                    noteData: nil,
                    noteUpdateData: nil,
                    deletionData: nil,
                    followUpQuestion: nil
                )
            }

        } catch let error as SummaryError {
            print("❌ SummaryError: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Network error: \(error)")
            throw SummaryError.networkError(error)
        }
    }

    // MARK: - Receipt Analysis with Vision

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

// MARK: - String Extension for Pattern Matching
extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}