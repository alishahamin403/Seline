import Foundation

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    // API key loaded from environment or stored securely
    // Set OPENAI_API_KEY in your environment or update this to use secure storage
    private let apiKey: String = {
        // Try to load from environment variable first
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        // Fallback to UserDefaults (you should set this in Settings)
        if let storedKey = UserDefaults.standard.string(forKey: "openai_api_key"), !storedKey.isEmpty {
            return storedKey
        }
        // TODO: Set your API key in Settings or as environment variable
        return ""
    }()
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    // Rate limiting properties
    private let requestQueue = DispatchQueue(label: "openai-requests", qos: .utility)
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 2.0 // 2 seconds between requests

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

    func summarizeEmail(subject: String, body: String) async throws -> String {
        // Rate limiting - ensure minimum interval between requests
        await enforceRateLimit()

        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Extract and clean the main body content
        let cleanedBody = extractMainBodyContent(from: body)

        // More aggressive truncation to reduce token usage (roughly 4 chars = 1 token)
        let maxBodyLength = 8000 // Reduced to ~2k tokens for faster processing
        let truncatedBody = cleanedBody.count > maxBodyLength ? String(cleanedBody.prefix(maxBodyLength)) + "..." : cleanedBody

        // Create the prompt for GPT
        let emailContent = """
        Subject: \(subject)

        Body: \(truncatedBody)
        """

        let systemPrompt = """
        Extract the 4 most important facts from this email content (may include formatted text, tables, or lists). Each fact should be 8-12 words and provide specific details.

        For receipts/order confirmations: prioritize order total, key items purchased, order/tracking number, and delivery/pickup details.
        For other emails: prioritize actions required, deadlines, key decisions, and important context.

        Ignore greetings, lengthy disclaimers, and excessive promotional content.
        """

        let userPrompt = """
        Email: \(emailContent)

        4 key facts:
        """

        // Create the request body - using gpt-4o-mini for cost-effective summaries
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // Much cheaper model: ~$0.15 per 1M input tokens vs ~$30 for gpt-4
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
            "max_tokens": 180, // Optimized for concise 4-point summaries with more detail
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
            return cleanedSummary

        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.networkError(error)
        }
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

        // Ensure we have exactly 4 bullet points
        let finalBullets = Array(bulletPoints.prefix(4))

        // If we have fewer than 4, pad with generic points (shouldn't happen with proper prompting)
        while finalBullets.count < 4 && bulletPoints.count < 4 {
            if bulletPoints.count == 1 {
                bulletPoints.append("Additional details mentioned")
            } else if bulletPoints.count == 2 {
                bulletPoints.append("Further information provided")
            } else if bulletPoints.count == 3 {
                bulletPoints.append("See email for more details")
            }
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

        // Detect if this is likely a receipt/order confirmation
        let isReceipt = detectReceipt(cleanedContent)

        // For receipts, be more conservative with content removal
        if !isReceipt {
            // Remove common email signatures and footers
            cleanedContent = removeEmailSignatures(cleanedContent)

            // Remove email threading (forwarded/replied content)
            cleanedContent = removeEmailThreading(cleanedContent)

            // Remove common email boilerplate
            cleanedContent = removeEmailBoilerplate(cleanedContent)
        } else {
            // For receipts, only remove very minimal boilerplate
            cleanedContent = removeMinimalBoilerplate(cleanedContent)
        }

        // Remove URLs and links (but preserve context) - safe for all emails
        cleanedContent = removeURLs(cleanedContent)

        // Remove excessive whitespace and clean up formatting
        cleanedContent = cleanUpWhitespace(cleanedContent)

        return cleanedContent
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

    private func extractHTMLContent(_ html: String) -> String {
        var content = html

        // Remove problematic elements that don't contain useful content
        content = removeHTMLNoise(content)

        // Extract meaningful text from HTML while preserving important structure
        content = extractMeaningfulHTMLText(content)

        // Clean up the extracted content
        content = cleanUpExtractedText(content)

        return content
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

        // Remove form elements that don't contain meaningful content
        cleaned = cleaned.replacingOccurrences(
            of: "<(input|button|select|textarea|form)[^>]*>",
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
        - Fix grammar and spelling errors
        - Use casual, friendly tone
        - Improve sentence structure and flow
        - Preserve the original meaning and all key information
        - Remove unnecessary repetition
        - Keep the same general length as the original
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
        - Follow the user's editing instructions precisely
        - Preserve important information unless instructed otherwise
        - Maintain clarity and coherence
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