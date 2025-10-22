import Foundation
import GoogleSignIn

class GmailAPIClient {
    static let shared = GmailAPIClient()

    private init() {}

    // MARK: - Gmail API Endpoints
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    // MARK: - Token Management
    private func refreshAccessTokenIfNeeded() async throws {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        // Check if token needs refresh (if it's about to expire in the next 5 minutes)
        let currentToken = user.accessToken
        let expirationDate = currentToken.expirationDate

        if let expirationDate = expirationDate, expirationDate.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
        }
    }

    private func refreshAccessToken() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error = error {
                    print("❌ Failed to refresh token: \(error.localizedDescription)")
                    continuation.resume(throwing: GmailAPIError.notAuthenticated)
                    return
                }

                guard user != nil else {
                    print("❌ No user after refresh attempt")
                    continuation.resume(throwing: GmailAPIError.notAuthenticated)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    private func withRetry<T>(maxAttempts: Int = 2, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as GmailAPIError {
                switch error {
                case .apiError(let statusCode, _):
                    // If it's a 401 error, try refreshing the token and retry
                    if statusCode == 401 && attempt < maxAttempts {
                        try? await refreshAccessToken()
                        lastError = error
                        continue
                    }
                default:
                    break
                }
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? GmailAPIError.invalidResponse
    }

    // MARK: - Public Methods

    func fetchInboxEmails(maxResults: Int = 50) async throws -> [Email] {
        try await refreshAccessTokenIfNeeded()
        return try await withRetry {
            let messageList = try await self.fetchMessagesList(query: "in:inbox", maxResults: maxResults)
            return try await self.fetchEmailDetails(messageIds: messageList.messages?.map { $0.id } ?? [])
        }
    }

    // MARK: - Full Email Body Fetching
    // This function fetches the complete email body including HTML content
    // Only call this when you need the full body (e.g., for AI summaries or displaying email content)
    func fetchFullEmailBody(messageId: String) async throws -> Email? {
        try await refreshAccessTokenIfNeeded()
        return try await withRetry {
            try await self.fetchSingleEmailWithFullBody(messageId: messageId)
        }
    }

    /// Fetches raw email body content specifically for AI processing (no display wrapping)
    /// Returns clean HTML or plain text without any formatting for web display
    func fetchBodyForAI(messageId: String) async throws -> String? {
        try await refreshAccessTokenIfNeeded()
        return try await withRetry {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GmailAPIError.notAuthenticated
            }

            let accessToken = user.accessToken.tokenString

            var urlComponents = URLComponents(string: "\(self.baseURL)/messages/\(messageId)")!
            urlComponents.queryItems = [
                URLQueryItem(name: "format", value: "full")
            ]

            guard let url = urlComponents.url else {
                throw GmailAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw GmailAPIError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
            }

            let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)

            // Extract raw body for AI processing
            guard let payload = gmailMessage.payload else {
                return nil
            }

            return self.extractBodyForAI(from: payload)
        }
    }

    func fetchSentEmails(maxResults: Int = 50) async throws -> [Email] {
        try await refreshAccessTokenIfNeeded()
        return try await withRetry {
            let messageList = try await self.fetchMessagesList(query: "in:sent", maxResults: maxResults)
            return try await self.fetchEmailDetails(messageIds: messageList.messages?.map { $0.id } ?? [])
        }
    }

    func searchEmails(query: String, maxResults: Int = 50) async throws -> [Email] {
        try await refreshAccessTokenIfNeeded()
        return try await withRetry {
            let messageList = try await self.fetchMessagesList(query: query, maxResults: maxResults)
            return try await self.fetchEmailDetails(messageIds: messageList.messages?.map { $0.id } ?? [])
        }
    }

    func deleteEmail(messageId: String) async throws {
        try await refreshAccessTokenIfNeeded()

        try await withRetry {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GmailAPIError.notAuthenticated
            }

            let accessToken = user.accessToken.tokenString

            guard let url = URL(string: "\(self.baseURL)/messages/\(messageId)") else {
                throw GmailAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            // Gmail API returns 204 No Content for successful deletion
            guard httpResponse.statusCode == 204 else {
                let errorMessage = "Failed to delete email (HTTP \(httpResponse.statusCode))"
                throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
            }
        }
    }

    func trashEmail(messageId: String) async throws {
        try await refreshAccessTokenIfNeeded()

        try await withRetry {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GmailAPIError.notAuthenticated
            }

            let accessToken = user.accessToken.tokenString

            guard let url = URL(string: "\(self.baseURL)/messages/\(messageId)/trash") else {
                throw GmailAPIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = "Failed to move email to trash (HTTP \(httpResponse.statusCode))"
                throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
            }
        }
    }

    func markAsRead(messageId: String) async throws {
        try await refreshAccessTokenIfNeeded()

        try await withRetry {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GmailAPIError.notAuthenticated
            }

            let accessToken = user.accessToken.tokenString

            guard let url = URL(string: "\(self.baseURL)/messages/\(messageId)/modify") else {
                throw GmailAPIError.invalidURL
            }

            let requestBody: [String: Any] = [
                "removeLabelIds": ["UNREAD"]
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
                throw GmailAPIError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = "Failed to mark email as read (HTTP \(httpResponse.statusCode))"
                throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
            }
        }
    }

    func markAsUnread(messageId: String) async throws {
        try await refreshAccessTokenIfNeeded()

        try await withRetry {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GmailAPIError.notAuthenticated
            }

            let accessToken = user.accessToken.tokenString

            guard let url = URL(string: "\(self.baseURL)/messages/\(messageId)/modify") else {
                throw GmailAPIError.invalidURL
            }

            let requestBody: [String: Any] = [
                "addLabelIds": ["UNREAD"]
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
                throw GmailAPIError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = "Failed to mark email as unread (HTTP \(httpResponse.statusCode))"
                throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
            }
        }
    }

    // MARK: - Private Methods

    // CRITICAL FIX: Made public so EmailService can check for new emails without fetching full content
    func fetchMessagesList(query: String, maxResults: Int = 50) async throws -> GmailMessagesList {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        let accessToken = user.accessToken.tokenString

        var urlComponents = URLComponents(string: "\(baseURL)/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        do {
            return try JSONDecoder().decode(GmailMessagesList.self, from: data)
        } catch {
            throw GmailAPIError.decodingError(error)
        }
    }

    private func fetchEmailDetails(messageIds: [String]) async throws -> [Email] {
        var emails: [Email] = []

        // Process in batches of 20 for faster loading (increased from 5)
        let batchSize = 20
        for i in stride(from: 0, to: messageIds.count, by: batchSize) {
            let endIndex = min(i + batchSize, messageIds.count)
            let batch = Array(messageIds[i..<endIndex])

            // Process batch concurrently
            let batchEmails = try await withThrowingTaskGroup(of: Email?.self, returning: [Email].self) { group in
                for messageId in batch {
                    group.addTask {
                        try await self.fetchSingleEmail(messageId: messageId)
                    }
                }

                var results: [Email] = []
                for try await email in group {
                    if let email = email {
                        results.append(email)
                    }
                }
                return results
            }

            emails.append(contentsOf: batchEmails)

            // Add smaller delay between batches (reduced from 0.5s to 0.1s)
            if endIndex < messageIds.count {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }

        return emails.sorted { $0.timestamp > $1.timestamp }
    }

    func fetchSingleEmail(messageId: String) async throws -> Email? {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        let accessToken = user.accessToken.tokenString

        var urlComponents = URLComponents(string: "\(baseURL)/messages/\(messageId)")!
        urlComponents.queryItems = [
            // CRITICAL FIX: Use metadata instead of full to reduce egress by 85-90%
            // Only fetch headers and labels, not full email body/attachments
            URLQueryItem(name: "format", value: "metadata"),
            // Specify which headers we need
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "To"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        do {
            let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)
            return parseGmailMessage(gmailMessage)
        } catch {
            throw GmailAPIError.decodingError(error)
        }
    }

    // Fetch email with FULL body content (format=full) for AI summaries and HTML display
    private func fetchSingleEmailWithFullBody(messageId: String) async throws -> Email? {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        let accessToken = user.accessToken.tokenString

        var urlComponents = URLComponents(string: "\(baseURL)/messages/\(messageId)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "format", value: "full")
        ]

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GmailAPIError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        do {
            let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)
            return parseGmailMessage(gmailMessage)
        } catch {
            throw GmailAPIError.decodingError(error)
        }
    }

    private func parseGmailMessage(_ gmailMessage: GmailMessage) -> Email? {
        guard let payload = gmailMessage.payload,
              let headers = payload.headers else {
            return nil
        }

        // Extract headers
        var subject = ""
        var fromHeader = ""
        var toHeader = ""
        var dateHeader = ""

        for header in headers {
            switch header.name?.lowercased() {
            case "subject":
                subject = header.value ?? ""
            case "from":
                fromHeader = header.value ?? ""
            case "to":
                toHeader = header.value ?? ""
            case "date":
                dateHeader = header.value ?? ""
            default:
                break
            }
        }

        // Parse sender
        let sender = parseEmailAddress(fromHeader)

        // Parse recipients
        let recipients = parseEmailAddresses(toHeader)

        // Parse date - try multiple formats and fallback to internalDate
        let timestamp = parseDate(dateHeader) ?? parseInternalDate(gmailMessage.internalDate) ?? Date()

        // Extract snippet
        let snippet = gmailMessage.snippet ?? ""

        // Extract body (simplified)
        let body = extractBody(from: payload)

        // Determine if read
        let isRead = !(gmailMessage.labelIds?.contains("UNREAD") ?? false)

        // Check if important
        let isImportant = gmailMessage.labelIds?.contains("IMPORTANT") ?? false

        // Check for attachments
        let hasAttachments = hasAttachments(payload: payload)

        return Email(
            id: gmailMessage.id ?? UUID().uuidString,
            threadId: gmailMessage.threadId ?? "",
            sender: sender,
            recipients: recipients,
            ccRecipients: [], // TODO: Parse CC recipients from Gmail API
            subject: subject,
            snippet: snippet,
            body: body,
            timestamp: timestamp,
            isRead: isRead,
            isImportant: isImportant,
            hasAttachments: hasAttachments,
            attachments: [], // TODO: Parse attachments from Gmail API
            labels: gmailMessage.labelIds ?? [],
            aiSummary: nil, // TODO: Add AI summary generation
            gmailMessageId: gmailMessage.id,
            gmailThreadId: gmailMessage.threadId
        )
    }

    private func parseEmailAddress(_ emailString: String) -> EmailAddress {
        // Simple email parsing - can be enhanced
        let trimmed = emailString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("<") && trimmed.contains(">") {
            let components = trimmed.components(separatedBy: "<")
            let name = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
            let email = components.last?.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return EmailAddress(name: name?.isEmpty == false ? name : nil, email: email ?? trimmed)
        } else {
            return EmailAddress(name: nil, email: trimmed)
        }
    }

    private func parseEmailAddresses(_ emailString: String) -> [EmailAddress] {
        let addresses = emailString.components(separatedBy: ",")
        return addresses.map { parseEmailAddress($0) }
    }

    private func parseDate(_ dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try multiple common email date formats
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",      // Standard RFC 2822
            "dd MMM yyyy HH:mm:ss Z",           // Without day name
            "EEE, dd MMM yyyy HH:mm:ss zzz",    // With timezone name
            "dd MMM yyyy HH:mm:ss zzz",         // Without day name, timezone name
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",       // ISO 8601 with milliseconds
            "yyyy-MM-dd'T'HH:mm:ssZ",           // ISO 8601 without milliseconds
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",     // ISO 8601 with Z suffix
            "yyyy-MM-dd'T'HH:mm:ss'Z'",         // ISO 8601 with Z suffix, no milliseconds
            "EEE MMM dd HH:mm:ss yyyy",         // Some systems use this format
            "MMM dd, yyyy 'at' h:mm:ss a zzz"   // Some formatted versions
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    private func parseInternalDate(_ internalDateString: String?) -> Date? {
        guard let internalDateString = internalDateString,
              let timestamp = Double(internalDateString) else {
            return nil
        }

        // Gmail internalDate is in milliseconds since epoch
        return Date(timeIntervalSince1970: timestamp / 1000.0)
    }

    private func extractBody(from payload: GmailMessagePayload) -> String? {
        // Extract body content, preserving HTML for rich display

        // First, try to get the main body
        if let body = payload.body?.data {
            let decodedContent = decodeBase64String(body)
            return processEmailContent(decodedContent, mimeType: payload.mimeType)
        }

        // Recursively search through parts for text content
        // This handles nested multipart structures (e.g., multipart/mixed > multipart/alternative > text/html)
        if let parts = payload.parts {
            // First pass: look for HTML content to preserve formatting (recursively)
            if let htmlContent = findContentInParts(parts, mimeType: "text/html") {
                return processEmailContent(htmlContent, mimeType: "text/html")
            }

            // Second pass: fall back to plain text (recursively)
            if let plainContent = findContentInParts(parts, mimeType: "text/plain") {
                return plainContent
            }
        }

        return nil
    }

    // MARK: - AI Processing Body Extraction

    /// Extracts raw email body content for AI processing (no display formatting)
    /// This returns clean HTML or text without wrapping in display HTML structure
    private func extractBodyForAI(from payload: GmailMessagePayload) -> String? {
        // First, try to get the main body
        if let body = payload.body?.data {
            let decodedContent = decodeBase64String(body)
            // Return raw content without display processing
            return decodedContent
        }

        // Recursively search through parts for text content
        if let parts = payload.parts {
            // First pass: look for HTML content (recursively)
            if let htmlContent = findContentInParts(parts, mimeType: "text/html") {
                return htmlContent
            }

            // Second pass: fall back to plain text (recursively)
            if let plainContent = findContentInParts(parts, mimeType: "text/plain") {
                return plainContent
            }
        }

        return nil
    }

    // Recursively search through nested parts to find content with specific mime type
    private func findContentInParts(_ parts: [GmailMessagePart], mimeType: String) -> String? {
        for part in parts {
            // Check if this part has the mime type we're looking for
            if part.mimeType == mimeType,
               let bodyData = part.body?.data {
                return decodeBase64String(bodyData)
            }

            // Recursively check nested parts (for multipart/alternative, multipart/mixed, etc.)
            if let nestedParts = part.parts {
                if let foundContent = findContentInParts(nestedParts, mimeType: mimeType) {
                    return foundContent
                }
            }
        }

        return nil
    }

    private func processEmailContent(_ content: String?, mimeType: String?) -> String? {
        guard let content = content else { return nil }

        // If it's plain text, return as-is
        if mimeType == "text/plain" {
            return content
        }

        // If it's HTML, clean it up but preserve formatting and layout
        if mimeType == "text/html" || content.contains("<") {
            return cleanHTMLForDisplay(content)
        }

        return content
    }

    private func cleanHTMLForDisplay(_ html: String) -> String {
        var cleanedHTML = html

        // Remove problematic elements while preserving layout
        // Remove script tags and their content
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )

        // Remove style tags but keep inline styles for formatting
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Remove form elements that won't work in display context
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "<(form|input|button|select|textarea)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Clean up meta and link tags in head that might cause issues
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "<(meta|link)[^>]*>",
            with: "",
            options: .regularExpression
        )

        // Remove JavaScript event handlers
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "on\\w+=[\"'][^\"']*[\"']",
            with: "",
            options: .regularExpression
        )

        // Ensure images have proper styling for mobile display
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: "<img([^>]*)>",
            with: "<img$1 style=\"max-width: 100%; height: auto;\">",
            options: .regularExpression
        )

        // Add basic CSS for better mobile display
        let cssStyles = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 16px;
            line-height: 1.6;
            margin: 0;
            padding: 16px;
            max-width: 100%;
            overflow-x: hidden;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
            border-radius: 8px;
        }
        table {
            max-width: 100% !important;
            border-collapse: collapse;
        }
        td, th {
            padding: 8px;
            text-align: left;
        }
        a {
            color: #007AFF;
            text-decoration: none;
        }
        .email-content {
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        </style>
        """

        // If it's a complete HTML document, add our styles to head
        if cleanedHTML.contains("<head>") {
            cleanedHTML = cleanedHTML.replacingOccurrences(
                of: "</head>",
                with: "\(cssStyles)</head>"
            )
        } else {
            // If it's just HTML content, wrap it properly
            cleanedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(cssStyles)
            </head>
            <body>
            <div class="email-content">
            \(cleanedHTML)
            </div>
            </body>
            </html>
            """
        }

        return cleanedHTML
    }

    private func stripHTMLTags(from html: String) -> String? {
        // Remove HTML tags using regex
        var cleanText = html

        // Remove DOCTYPE declarations
        cleanText = cleanText.replacingOccurrences(
            of: "<!DOCTYPE[^>]*>",
            with: "",
            options: .regularExpression
        )

        // Remove script and style tags along with their content
        cleanText = cleanText.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Remove HTML comments
        cleanText = cleanText.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )

        // Remove links but keep link text
        cleanText = cleanText.replacingOccurrences(
            of: "<a[^>]*href=[\"'][^\"']*[\"'][^>]*>([^<]*)</a>",
            with: "$1",
            options: .regularExpression
        )

        // Remove any remaining standalone URLs (http/https/ftp links)
        cleanText = cleanText.replacingOccurrences(
            of: "https?://[^\\s<>\"]+",
            with: "",
            options: .regularExpression
        )

        cleanText = cleanText.replacingOccurrences(
            of: "ftp://[^\\s<>\"]+",
            with: "",
            options: .regularExpression
        )

        // Remove email addresses (optional - uncomment if you want to remove them too)
        // cleanText = cleanText.replacingOccurrences(
        //     of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
        //     with: "",
        //     options: .regularExpression
        // )

        // Convert common HTML entities
        let htmlEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&hellip;": "…",
            "&mdash;": "—",
            "&ndash;": "–",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\u{201D}",
            "&ldquo;": "\u{201C}",
            "&#39;": "'",
            "&#x27;": "'",
            "&#x2F;": "/",
            "&#8217;": "'",
            "&#8220;": "\u{201C}",
            "&#8221;": "\u{201D}",
            "&#8230;": "…"
        ]

        for (entity, replacement) in htmlEntities {
            cleanText = cleanText.replacingOccurrences(of: entity, with: replacement)
        }

        // Replace paragraph and break tags with line breaks
        cleanText = cleanText.replacingOccurrences(
            of: "<(p|br|div)[^>]*>",
            with: "\n",
            options: .regularExpression
        )

        cleanText = cleanText.replacingOccurrences(
            of: "</p>",
            with: "\n\n",
            options: .regularExpression
        )

        // Remove all remaining HTML tags
        cleanText = cleanText.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Clean up whitespace
        // Replace multiple consecutive line breaks with double line breaks
        cleanText = cleanText.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        // Replace multiple spaces with single space
        cleanText = cleanText.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        // Trim whitespace from beginning and end
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanText.isEmpty ? nil : cleanText
    }

    private func hasAttachments(payload: GmailMessagePayload) -> Bool {
        guard let parts = payload.parts else { return false }

        return parts.contains { part in
            return part.filename?.isEmpty == false && part.body?.attachmentId != nil
        }
    }

    private func decodeBase64String(_ base64String: String) -> String? {
        // Gmail uses URL-safe base64 encoding
        let urlSafeBase64 = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let paddedBase64 = urlSafeBase64 + String(repeating: "=", count: (4 - urlSafeBase64.count % 4) % 4)

        guard let data = Data(base64Encoded: paddedBase64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Gmail API Models

struct GmailMessagesList: Codable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String?
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailMessagePayload?
    let internalDate: String?
}

struct GmailMessagePayload: Codable {
    let headers: [GmailHeader]?
    let body: GmailMessageBody?
    let parts: [GmailMessagePart]?
    let mimeType: String?
}

struct GmailHeader: Codable {
    let name: String?
    let value: String?
}

struct GmailMessageBody: Codable {
    let data: String?
    let size: Int?
    let attachmentId: String?
}

struct GmailMessagePart: Codable {
    let mimeType: String?
    let filename: String?
    let body: GmailMessageBody?
    let parts: [GmailMessagePart]?
}

// MARK: - Errors

enum GmailAPIError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    case decodingError(Error)
    case noPermission

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated with Google"
        case .invalidURL:
            return "Invalid Gmail API URL"
        case .invalidResponse:
            return "Invalid response from Gmail API"
        case .apiError(let statusCode, let message):
            return "Gmail API error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Failed to decode Gmail API response: \(error.localizedDescription)"
        case .noPermission:
            return "No permission to access Gmail. Please sign in again with Gmail access."
        }
    }
}