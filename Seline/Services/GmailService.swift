//
//  GmailService.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation

protocol GmailServiceProtocol {
    func fetchTodaysUnreadEmails() async throws -> [Email]
    func fetchMoreEmails(after lastEmail: Email) async throws -> [Email] // New pagination method
    func searchEmails(query: String) async throws -> [Email]
    func fetchImportantEmails() async throws -> [Email]
    func fetchPromotionalEmails() async throws -> [Email]
    func fetchCalendarEmails() async throws -> [Email]
    func fetchFullEmailContent(emailId: String) async throws -> Email // New method for on-demand content
    func markAsRead(emailId: String) async throws
    func markAsUnread(emailId: String) async throws
    func markAsImportant(emailId: String) async throws
    func archiveEmail(emailId: String) async throws
    func deleteEmail(emailId: String) async throws
}

class GmailService: GmailServiceProtocol {
    static let shared = GmailService()
    
    private let authService = AuthenticationService.shared
    private let quotaManager = GmailQuotaManager.shared
    private let cacheManager = EmailCacheManager.shared
    
    // Pagination state
    private var nextPageToken: String?
    private var isLoadingMore = false
    
    private init() {
        // Gmail service initialization handled through mock implementation
    }
    
    private func setupAuthorizationIfNeeded() async {
        // Authorization handled through AuthenticationService
    }
    
    // MARK: - Public API Methods
    
    func fetchTodaysUnreadEmails() async throws -> [Email] {
        // Use quota-aware configuration
        let config = EmailFetchConfig.forInbox(quotaManager: quotaManager)
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_inbox") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh")
                // Do not use mock data for inbox; show empty and surface auth message
                return []
            }
            
            do {
                let emails = try await self.fetchRealEmails(query: config.query, maxResults: config.maxResults)
                
                // Cache the results for future requests
                self.cacheManager.cacheEmails(emails, includeFullBody: false)
                
                ProductionLogger.logEmailLoad("inbox emails", count: emails.count)
                return emails
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_inbox_real")
                // No mock fallback
                return []
            }
        }
    }
    
    func searchEmails(query: String) async throws -> [Email] {
        guard !query.isEmpty else { return [] }
        
        let config = EmailFetchConfig.forSearch(query: query, quotaManager: quotaManager)
        
        return try await quotaManager.executeWithQuotaControl(operation: "search_emails") {
            try await self.refreshTokenIfNeeded()
            
            let emails = try await self.fetchRealEmails(query: config.query, maxResults: config.maxResults)
            ProductionLogger.logEmailOperation("Search completed", count: emails.count)
            return emails
        }
    }
    
    func fetchImportantEmails() async throws -> [Email] {
        // Use quota-aware configuration
        let config = EmailFetchConfig.forCategory(type: .important, quotaManager: quotaManager)
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_important") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh")
                // Do not fallback to mock for important; return empty and let local filter fill in
                return []
            }
            
            do {
                let emails = try await self.fetchRealEmails(query: config.query, maxResults: config.maxResults)
                // Filter to today only at source level as an extra guard
                let today = Calendar.current
                let todays = emails.filter { today.isDateInToday($0.date) }
                
                // Cache the results
                self.cacheManager.cacheEmailsByCategory(todays, category: .important)
                
                ProductionLogger.logEmailLoad("important emails", count: todays.count)
                return todays
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_important_real")
                // No mock fallback for important
                return []
            }
        }
    }
    
    func fetchPromotionalEmails() async throws -> [Email] {
        // Check cache first
        let cachedEmails = cacheManager.getCachedEmailsForCategory(.promotional)
        if !cachedEmails.isEmpty {
            ProductionLogger.logEmailOperation("Loaded promotional emails from cache", count: cachedEmails.count)
            return cachedEmails
        }
        
        // Use quota-aware configuration
        let config = EmailFetchConfig.forCategory(type: .promotional, quotaManager: quotaManager)
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_promotional") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh")
                return try await self.fetchMockPromotionalEmails()
            }
            
            do {
                let emails = try await self.fetchRealEmails(query: config.query, maxResults: config.maxResults)
                
                // Cache the results
                self.cacheManager.cacheEmailsByCategory(emails, category: .promotional)
                
                ProductionLogger.logEmailLoad("promotional emails", count: emails.count)
                return emails
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_promotional_real")
                return try await self.fetchMockPromotionalEmails()
            }
        }
    }
    
    func fetchCalendarEmails() async throws -> [Email] {
        // Check cache first
        let cachedEmails = cacheManager.getCachedEmailsForCategory(.calendar)
        if !cachedEmails.isEmpty {
            ProductionLogger.logEmailOperation("Loaded calendar emails from cache", count: cachedEmails.count)
            return cachedEmails
        }
        
        // Use quota-aware configuration
        let config = EmailFetchConfig.forCategory(type: .calendar, quotaManager: quotaManager)
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_calendar") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh")
                return try await self.fetchMockCalendarEmails()
            }
            
            do {
                let emails = try await self.fetchRealEmails(query: config.query, maxResults: config.maxResults)
                
                // Cache the results
                self.cacheManager.cacheEmailsByCategory(emails, category: .calendar)
                
                ProductionLogger.logEmailLoad("calendar emails", count: emails.count)
                return emails
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_calendar_real")
                return try await self.fetchMockCalendarEmails()
            }
        }
    }
    
    func markAsRead(emailId: String) async throws {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Gmail API call
        /*
        let query = GTLRGmailQuery_UsersMessagesModify.query(withUserId: "me", identifier: emailId)
        query.removeLabels = ["UNREAD"]
        
        _ = try await executeQuery(query)
        */
        
        print("Mock: Marking email \(emailId) as read")
    }
    
    func markAsUnread(emailId: String) async throws {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Gmail API call
        /*
        let query = GTLRGmailQuery_UsersMessagesModify.query(withUserId: "me", identifier: emailId)
        query.addLabels = ["UNREAD"]
        
        _ = try await executeQuery(query)
        */
        
        print("Mock: Marking email \(emailId) as unread")
    }
    
    func markAsImportant(emailId: String) async throws {
        try await refreshTokenIfNeeded()
        
        // TODO: Replace with actual Gmail API call
        /*
        let query = GTLRGmailQuery_UsersMessagesModify.query(withUserId: "me", identifier: emailId)
        query.addLabels = ["IMPORTANT"]
        
        _ = try await executeQuery(query)
        */
        
        print("Mock: Marking email \(emailId) as important")
    }
    
    func archiveEmail(emailId: String) async throws {
        try await refreshTokenIfNeeded()
        
        guard let accessToken = await getGoogleAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(emailId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Remove INBOX label to archive
        let body = ["removeLabelIds": ["INBOX"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailError.networkError
        }
        
        print("✅ Successfully archived email \(emailId)")
    }
    
    func deleteEmail(emailId: String) async throws {
        try await refreshTokenIfNeeded()
        
        guard let accessToken = await getGoogleAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // Use Trash endpoint; if it fails, try modify remove label as fallback
        // Gmail IDs from local cache/CoreData are expected to be the Gmail message ID string.
        // If we accidentally passed a thread ID or local UUID, the API returns 400 Invalid id value.
        // Validate format (Gmail message IDs are base64url or hex-like strings without spaces)
        let trimmedID = emailId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { throw GmailError.invalidResponse }
        let url = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(trimmedID)/trash")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            print("✅ Successfully deleted (moved to trash) email \(emailId)")
            // Remove from local store immediately
            _ = CoreDataManager.shared.deleteEmailByGmailID(trimmedID)
            return
        }
        
        // Fallback: remove INBOX and IMPORTANT labels (simulates archive from important)
        let modifyURL = URL(string: "https://www.googleapis.com/gmail/v1/users/me/messages/\(trimmedID)/modify")!
        var modify = URLRequest(url: modifyURL)
        modify.httpMethod = "POST"
        modify.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        modify.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            // Also remove Promotions and Social if present
            "removeLabelIds": ["INBOX", "IMPORTANT", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL"]
        ]
        modify.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (modifyData, modifyResp) = try await URLSession.shared.data(for: modify)
        guard let modifyHTTP = modifyResp as? HTTPURLResponse, modifyHTTP.statusCode == 200 else {
            let respStatus = (modifyResp as? HTTPURLResponse)?.statusCode ?? -1
            print("❌ Delete failed. Status: \(respStatus). Body: \(String(data: modifyData, encoding: .utf8) ?? "")")
            throw GmailError.insufficientPermissions
        }
        print("✅ Fallback: removed INBOX/IMPORTANT labels for email \(emailId)")
        _ = CoreDataManager.shared.deleteEmailByGmailID(trimmedID)
    }
    
    func fetchMoreEmails(after lastEmail: Email) async throws -> [Email] {
        guard !isLoadingMore else {
            return []
        }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_more_emails") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh for pagination")
                return []
            }
            
            // Use pagination configuration with smaller batch size
            let config = EmailFetchConfig(
                maxResults: GmailQuotaManager.paginationSize,
                query: "is:unread OR (is:read newer_than:1d)",
                includeBody: false,
                useCache: true
            )
            
            do {
                let emails = try await self.fetchRealEmailsWithPagination(
                    query: config.query, 
                    maxResults: config.maxResults,
                    pageToken: self.nextPageToken
                )
                
                // Cache paginated results
                self.cacheManager.cacheEmails(emails, includeFullBody: false)
                
                ProductionLogger.logEmailLoad("paginated emails", count: emails.count)
                return emails
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_more_emails")
                return []
            }
        }
    }
    
    func fetchFullEmailContent(emailId: String) async throws -> Email {
        // Check if we already have full content cached
        if let cached = cacheManager.getCachedEmail(id: emailId) {
            if !cached.body.isEmpty {
                ProductionLogger.logEmailOperation("Retrieved full content from cache", count: 1)
                return cached
            }
        }
        
        return try await quotaManager.executeWithQuotaControl(operation: "fetch_full_content") {
            do {
                try await self.refreshTokenIfNeeded()
            } catch {
                ProductionLogger.logAuthError(error, context: "token refresh for full content")
                throw error
            }
            
            guard let accessToken = await self.getGoogleAccessToken() else {
                throw GmailServiceError.noAccessToken
            }
            
            // Fetch full email with body content
            let email = try await self.fetchMessageDetails(messageId: emailId, accessToken: accessToken)
            
            // Cache with full body content
            self.cacheManager.cacheEmail(email, includeFullBody: true)
            
            ProductionLogger.logEmailOperation("Fetched full email content", count: 1)
            return email
        }
    }
    
    // MARK: - Cache Helper Methods
    
    private func getCachedInboxEmails() -> [Email] {
        // Try to get cached emails that match inbox criteria
        let allCachedEmails = cacheManager.getCachedEmailsForCategory(.important) +
                             cacheManager.getCachedEmailsForCategory(.promotional) +
                             cacheManager.getCachedEmailsForCategory(.calendar)
        
        // Return up to maxInitialEmails from cache
        let maxEmails = GmailQuotaManager.maxInitialEmails
        return Array(allCachedEmails.prefix(maxEmails))
    }
    
    // MARK: - Helper Methods
    
    private func refreshTokenIfNeeded() async throws {
        if authService.user?.isTokenExpired == true {
            await authService.refreshTokenIfNeeded()
        }
        
        guard authService.isAuthenticated else {
            throw GmailError.notAuthenticated
        }
        
        await setupAuthorizationIfNeeded()
    }
    
    
    // MARK: - Email Categorization Logic
    
    private func isImportantEmail(subject: String, body: String, sender: String) -> Bool {
        let importantKeywords = ["urgent", "important", "asap", "critical", "emergency", "deadline"]
        let importantSenders = ["noreply", "support", "security", "admin"]
        
        let subjectLower = subject.lowercased()
        let bodyLower = body.lowercased()
        let senderLower = sender.lowercased()
        
        // Check for urgent keywords
        if importantKeywords.contains(where: { subjectLower.contains($0) || bodyLower.contains($0) }) {
            return true
        }
        
        // Check for important senders
        if importantSenders.contains(where: { senderLower.contains($0) }) {
            return true
        }
        
        return false
    }
    
    private func isPromotionalEmail(subject: String, body: String) -> Bool {
        let promotionalKeywords = ["sale", "discount", "offer", "deal", "promotion", "coupon", "%", "free", "limited time"]
        
        let subjectLower = subject.lowercased()
        let bodyLower = body.lowercased()
        
        return promotionalKeywords.contains(where: { subjectLower.contains($0) || bodyLower.contains($0) })
    }
    
    private func hasCalendarContent(subject: String, body: String) -> Bool {
        let calendarKeywords = ["meeting", "calendar", "event", "appointment", "schedule", "invite", "zoom", "teams"]
        
        let subjectLower = subject.lowercased()
        let bodyLower = body.lowercased()
        
        return calendarKeywords.contains(where: { subjectLower.contains($0) || bodyLower.contains($0) })
    }
    
    // MARK: - Date Helpers
    
    private func todaysDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: Date())
    }
    
    private func sevenDaysAgoString() -> String {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: sevenDaysAgo)
    }
    
    // MARK: - Real Gmail API Integration
    
    private func fetchRealEmails(query: String, maxResults: Int) async throws -> [Email] {
        print("\n🌐 === FETCHING REAL GMAIL EMAILS ===")
        print("🔍 Query: \(query)")
        print("📊 Max results: \(maxResults)")
        
        guard let accessToken = await getGoogleAccessToken() else {
            print("❌ No access token available")
            throw GmailServiceError.noAccessToken
        }
        
        // Step 1: Get list of message IDs
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let listURL = "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(encodedQuery)&maxResults=\(maxResults)"
        print("🔗 API URL: \(listURL)")
        
        guard let url = URL(string: listURL) else {
            print("❌ Invalid URL: \(listURL)")
            throw GmailServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("📡 Making API request...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw GmailServiceError.apiError("Invalid HTTP response")
        }
        
        print("📊 HTTP Status: \(httpResponse.statusCode)")
        print("📦 Response size: \(data.count) bytes")
        
        // Log response body for debugging (first 500 chars)
        if let responseString = String(data: data, encoding: .utf8) {
            let preview = String(responseString.prefix(500))
            print("📄 Response preview: \(preview)")
            if responseString.count > 500 {
                print("📄 (Response truncated - total length: \(responseString.count) characters)")
            }
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ API request failed with status \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Error response: \(responseString)")
            }
            throw GmailServiceError.apiError("API request failed with status \(httpResponse.statusCode)")
        }
        
        do {
            let messageList = try JSONDecoder().decode(GmailMessageList.self, from: data)
            print("✅ Successfully decoded message list")
            print("📊 Result size estimate: \(messageList.resultSizeEstimate ?? 0)")
            print("📎 Next page token: \(messageList.nextPageToken ?? "None")")
            
            // Check if there are any messages
            guard let messages = messageList.messages, !messages.isEmpty else {
                print("📭 No messages found for query: \(query)")
                return []
            }
            
            print("📧 Found \(messages.count) messages, fetching details...")
        } catch {
            print("❌ Failed to decode JSON response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Raw response that failed to decode: \(responseString)")
            }
            throw GmailServiceError.decodingError
        }
        
        let messageList = try JSONDecoder().decode(GmailMessageList.self, from: data)
        let messages = messageList.messages!
        
        // Step 2: Fetch full message details for each ID
        var emails: [Email] = []
        let messagesToFetch = Array(messages.prefix(maxResults))
        print("📧 Fetching details for \(messagesToFetch.count) messages...")
        
        for (index, message) in messagesToFetch.enumerated() {
            print("🔄 [\(index + 1)/\(messagesToFetch.count)] Fetching message \(message.id)...")
            
            do {
                let email = try await fetchMessageDetails(messageId: message.id, accessToken: accessToken)
                emails.append(email)
                print("✅ [\(index + 1)/\(messagesToFetch.count)] Fetched email: '\(email.subject)' from \(email.sender.displayName)")
            } catch {
                print("⚠️ [\(index + 1)/\(messagesToFetch.count)] Failed to fetch message \(message.id): \(error)")
                // Continue with other messages
            }
        }
        
        print("📬 Successfully fetched \(emails.count)/\(messagesToFetch.count) emails")
        return emails
    }
    
    private func fetchRealEmailsWithPagination(query: String, maxResults: Int, pageToken: String?) async throws -> [Email] {
        guard let accessToken = await getGoogleAccessToken() else {
            throw GmailServiceError.noAccessToken
        }
        
        // Build URL with optional page token
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var listURL = "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(encodedQuery)&maxResults=\(maxResults)"
        
        if let pageToken = pageToken, !pageToken.isEmpty {
            listURL += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: listURL) else {
            throw GmailServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailServiceError.apiError("Invalid HTTP response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GmailServiceError.apiError("API request failed with status \(httpResponse.statusCode)")
        }
        
        let messageList = try JSONDecoder().decode(GmailMessageList.self, from: data)
        
        // Update next page token for future pagination
        self.nextPageToken = messageList.nextPageToken
        
        // Check if there are any messages
        guard let messages = messageList.messages, !messages.isEmpty else {
            return []
        }
        
        // Fetch details for each message
        var emails: [Email] = []
        let messagesToFetch = Array(messages.prefix(maxResults))
        
        for message in messagesToFetch {
            do {
                let email = try await fetchMessageDetails(messageId: message.id, accessToken: accessToken)
                emails.append(email)
            } catch {
                ProductionLogger.logEmailError(error, operation: "fetch_paginated_message_details")
                // Continue with other messages
            }
        }
        
        return emails
    }
    
    private func fetchMessageDetails(messageId: String, accessToken: String) async throws -> Email {
        let messageURL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)"
        
        guard let url = URL(string: messageURL) else {
            throw GmailServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)
        
        return convertGmailMessageToEmail(gmailMessage)
    }
    
    private func getGoogleAccessToken() async -> String? {
        print("🔑 Getting Google access token...")
        let token = await GoogleOAuthService.shared.getValidAccessToken()
        if let token = token {
            print("✅ Access token obtained (length: \(token.count))")
            print("🔑 Token preview: \(String(token.prefix(20)))...")
        } else {
            print("❌ No access token available")
        }
        return token
    }
    
    private func convertGmailMessageToEmail(_ gmailMessage: GmailMessage) -> Email {
        let headers = gmailMessage.payload.headers
        
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? "No Subject"
        let fromHeader = headers.first { $0.name.lowercased() == "from" }?.value ?? "unknown@example.com"
        let toHeader = headers.first { $0.name.lowercased() == "to" }?.value ?? ""
        let dateHeader = headers.first { $0.name.lowercased() == "date" }?.value ?? ""
        
        // Parse sender
        let sender = parseEmailAddress(fromHeader)
        
        // Parse recipients
        let recipients = parseEmailAddresses(toHeader)
        
        // Parse date
        let date = parseDate(dateHeader)
        
        // Get body (simplified - just get the plain text part)
        let body = extractEmailBody(from: gmailMessage.payload)
        
        // Determine email properties based on Gmail labels
        let isRead = !gmailMessage.labelIds.contains("UNREAD")
        // Treat Gmail Important and Starred as important; fallback to simple heuristics if labels are missing
        let labelImportant = gmailMessage.labelIds.contains("IMPORTANT")
        let labelStarred = gmailMessage.labelIds.contains("STARRED")
        var isImportant = labelImportant || labelStarred
        
        if !isImportant {
            let subjectLower = subject.lowercased()
            let bodyLower = body.lowercased()
            let heuristics = ["urgent", "important", "asap", "action required", "deadline", "security", "alert"]
            if heuristics.contains(where: { subjectLower.contains($0) || bodyLower.contains($0) }) {
                isImportant = true
            }
        }
        let isPromotional = gmailMessage.labelIds.contains("CATEGORY_PROMOTIONS")
        let hasCalendarEvent = detectCalendarEvent(subject: subject, body: body, sender: sender)
        
        // Parse attachments
        let attachments = parseAttachments(from: gmailMessage.payload)
        
        return Email(
            id: gmailMessage.id,
            subject: subject,
            sender: sender,
            recipients: recipients,
            body: body,
            date: date,
            isRead: isRead,
            isImportant: isImportant,
            labels: gmailMessage.labelIds,
            attachments: attachments,
            isPromotional: isPromotional,
            hasCalendarEvent: hasCalendarEvent
        )
    }
    
    private func detectCalendarEvent(subject: String, body: String, sender: EmailContact) -> Bool {
        let calendarKeywords = [
            "meeting", "appointment", "event", "calendar", "invite", "invitation",
            "scheduled", "rsvp", "agenda", "zoom", "conference", "call"
        ]
        
        let subjectAndBody = (subject + " " + body).lowercased()
        
        // Check for calendar-related keywords
        let hasCalendarKeywords = calendarKeywords.contains { keyword in
            subjectAndBody.contains(keyword)
        }
        
        // Check for calendar domains
        let calendarDomains = ["calendar.google.com", "zoom.us", "teams.microsoft.com", "webex.com"]
        let hasCalendarDomain = calendarDomains.contains { domain in
            sender.email.lowercased().contains(domain) || body.lowercased().contains(domain)
        }
        
        return hasCalendarKeywords || hasCalendarDomain
    }
    
    private func parseAttachments(from payload: GmailPayload) -> [EmailAttachment] {
        var attachments: [EmailAttachment] = []
        
        func extractAttachments(from parts: [GmailPart]?) {
            guard let parts = parts else { return }
            
            for part in parts {
                if let filename = part.filename, !filename.isEmpty {
                    let attachment = EmailAttachment(
                        filename: filename,
                        mimeType: part.mimeType,
                        size: part.body?.size ?? 0
                    )
                    attachments.append(attachment)
                }
                
                // Recursively check nested parts
                if let nestedParts = part.parts {
                    extractAttachments(from: nestedParts)
                }
            }
        }
        
        extractAttachments(from: payload.parts)
        return attachments
    }
    
    // MARK: - Gmail API Data Models
    
    struct GmailMessageList: Codable {
        let messages: [GmailMessageInfo]?
        let nextPageToken: String?
        let resultSizeEstimate: Int?
    }
    
    struct GmailMessageInfo: Codable {
        let id: String
        let threadId: String
    }
    
    struct GmailMessage: Codable {
        let id: String
        let threadId: String
        let labelIds: [String]
        let payload: GmailPayload
    }
    
    struct GmailPayload: Codable {
        let headers: [GmailHeader]
        let body: GmailBody?
        let parts: [GmailPart]?
    }
    
    struct GmailHeader: Codable {
        let name: String
        let value: String
    }
    
    struct GmailBody: Codable {
        let data: String?
        let size: Int
    }
    
    struct GmailPart: Codable {
        let mimeType: String
        let filename: String?
        let body: GmailBody?
        let parts: [GmailPart]?
    }
    
    // MARK: - Helper Methods
    
    private func parseEmailAddress(_ emailString: String) -> EmailContact {
        // Simple parsing - could be improved
        let pattern = #"^(.*?)\s*<(.+)>$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: emailString, range: NSRange(emailString.startIndex..., in: emailString)) {
            let nameRange = Range(match.range(at: 1), in: emailString)
            let emailRange = Range(match.range(at: 2), in: emailString)
            
            let name = nameRange.map { String(emailString[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let email = emailRange.map { String(emailString[$0]) } ?? emailString
            
            return EmailContact(name: name.isEmpty ? email : name, email: email)
        }
        
        return EmailContact(name: emailString, email: emailString)
    }
    
    private func parseEmailAddresses(_ emailString: String) -> [EmailContact] {
        // Simple implementation - split by comma
        return emailString.split(separator: ",").map { emailPart in
            parseEmailAddress(String(emailPart).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    private func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.date(from: dateString) ?? Date()
    }
    
    private func extractEmailBody(from payload: GmailPayload) -> String {
        // Try to get plain text body
        if let body = payload.body?.data, !body.isEmpty {
            return decodeBase64String(body)
        }
        
        // Look for text/plain part
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain", let body = part.body?.data, !body.isEmpty {
                    return decodeBase64String(body)
                }
            }
            
            // Fallback to HTML and strip tags
            for part in parts {
                if part.mimeType == "text/html", let body = part.body?.data, !body.isEmpty {
                    return stripHTMLTags(decodeBase64String(body))
                }
            }
        }
        
        return "No content available"
    }
    
    private func decodeBase64String(_ base64String: String) -> String {
        // Gmail uses URL-safe base64 encoding
        let corrected = base64String
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let paddedLength = ((corrected.count + 3) / 4) * 4
        let padded = corrected.padding(toLength: paddedLength, withPad: "=", startingAt: 0)
        
        guard let data = Data(base64Encoded: padded),
              let string = String(data: data, encoding: .utf8) else {
            return "Unable to decode content"
        }
        
        return string
    }
    
    private func stripHTMLTags(_ html: String) -> String {
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    
    // MARK: - Error Types
    
    enum GmailServiceError: LocalizedError {
        case noAccessToken
        case invalidURL
        case apiError(String)
        case decodingError
        
        var errorDescription: String? {
            switch self {
            case .noAccessToken:
                return "No valid access token available"
            case .invalidURL:
                return "Invalid Gmail API URL"
            case .apiError(let message):
                return "Gmail API error: \(message)"
            case .decodingError:
                return "Failed to decode Gmail API response"
            }
        }
    }
    
    // MARK: - Mock Data (for development)
    
    private func fetchMockTodaysEmails() async throws -> [Email] {
        print("🎭 Using mock today's emails data")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay to simulate network
        
        let today = Date()
        let userEmail = authService.user?.email ?? "user@example.com"
        
        return [
            Email(
                id: "gmail_1",
                subject: "Urgent: Review Required for Q4 Budget",
                sender: EmailContact(name: "Finance Team", email: "finance@company.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "Hi, We need your urgent review on the Q4 budget proposal. Please review and respond by EOD today. The document is attached for your reference.",
                date: Calendar.current.date(byAdding: .hour, value: -2, to: today) ?? today,
                isRead: false,
                isImportant: true,
                labels: ["INBOX", "IMPORTANT"],
                attachments: [
                    EmailAttachment(filename: "Q4_Budget.pdf", mimeType: "application/pdf", size: 2048000)
                ]
            ),
            Email(
                id: "gmail_2",
                subject: "🎉 50% Off Everything - Black Friday Sale!",
                sender: EmailContact(name: "TechStore", email: "deals@techstore.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "Don't miss out! Our biggest sale of the year is here. Get 50% off on all electronics, gadgets, and accessories. Limited time offer - shop now!",
                date: Calendar.current.date(byAdding: .hour, value: -4, to: today) ?? today,
                isRead: false,
                isImportant: false,
                labels: ["CATEGORY_PROMOTIONS"],
                attachments: []
            ),
            Email(
                id: "gmail_3",
                subject: "Team Standup Meeting - Tomorrow 10 AM",
                sender: EmailContact(name: "Sarah Johnson", email: "sarah.j@company.com"),
                recipients: [EmailContact(name: "Dev Team", email: "dev-team@company.com")],
                body: "Hi team, Just a reminder about our weekly standup meeting scheduled for tomorrow at 10 AM. We'll be discussing the sprint progress and upcoming deliverables. Zoom link: https://zoom.us/j/123456789",
                date: Calendar.current.date(byAdding: .hour, value: -6, to: today) ?? today,
                isRead: false,
                isImportant: true,
                labels: ["INBOX", "CALENDAR"],
                attachments: []
            ),
            Email(
                id: "gmail_4",
                subject: "Your Monthly Statement is Ready",
                sender: EmailContact(name: "Bank of America", email: "statements@bankofamerica.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "Your monthly account statement for November 2024 is now available. You can view and download it from your online banking account.",
                date: Calendar.current.date(byAdding: .hour, value: -8, to: today) ?? today,
                isRead: false,
                isImportant: false,
                labels: ["INBOX"],
                attachments: []
            )
        ]
    }
    
    private func fetchMockImportantEmails() async throws -> [Email] {
        print("🎭 Using mock important emails data")
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let today = Date()
        let userEmail = authService.user?.email ?? "user@example.com"
        
        return [
            Email(
                id: "important_1",
                subject: "URGENT: System Maintenance Tonight",
                sender: EmailContact(name: "IT Security", email: "security@company.com"),
                recipients: [EmailContact(name: "All Staff", email: "all@company.com")],
                body: "URGENT NOTICE: Scheduled system maintenance will begin at 11 PM tonight. All services will be temporarily unavailable for approximately 2 hours. Please save your work and log out before 11 PM.",
                date: Calendar.current.date(byAdding: .hour, value: -1, to: today) ?? today,
                isRead: false,
                isImportant: true,
                labels: ["INBOX", "IMPORTANT"],
                attachments: []
            ),
            Email(
                id: "important_2",
                subject: "Action Required: Complete Annual Training by Friday",
                sender: EmailContact(name: "HR Department", email: "hr@company.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "This is a reminder that your annual compliance training must be completed by end of business this Friday. Failure to complete training by the deadline may result in system access restrictions.",
                date: Calendar.current.date(byAdding: .hour, value: -3, to: today) ?? today,
                isRead: false,
                isImportant: true,
                labels: ["INBOX", "IMPORTANT"],
                attachments: [
                    EmailAttachment(filename: "Training_Guide.pdf", mimeType: "application/pdf", size: 1024000)
                ]
            )
        ]
    }
    
    private func fetchMockPromotionalEmails() async throws -> [Email] {
        print("🎭 Using mock promotional emails data")
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let today = Date()
        let userEmail = authService.user?.email ?? "user@example.com"
        
        return [
            Email(
                id: "promo_1",
                subject: "🚀 50% Off All Courses - Limited Time!",
                sender: EmailContact(name: "TechEd Online", email: "deals@teched.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "Don't miss our biggest sale of the year! Get 50% off all programming courses, including Python, Swift, JavaScript, and more. Use code SAVE50 at checkout. Offer valid until midnight!",
                date: Calendar.current.date(byAdding: .hour, value: -2, to: today) ?? today,
                isRead: false,
                isImportant: false,
                labels: ["CATEGORY_PROMOTIONS"],
                attachments: [],
                isPromotional: true,
                hasCalendarEvent: false
            ),
            Email(
                id: "promo_2",
                subject: "Flash Sale: Premium Software Bundle - 80% OFF!",
                sender: EmailContact(name: "Software Deals", email: "offers@softwaredeals.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "LIMITED TIME: Get our premium developer toolkit for just $39 (normally $199)! Includes IDE, debugging tools, version control, and more. Perfect for professional developers.",
                date: Calendar.current.date(byAdding: .hour, value: -5, to: today) ?? today,
                isRead: true,
                isImportant: false,
                labels: ["CATEGORY_PROMOTIONS"],
                attachments: [],
                isPromotional: true,
                hasCalendarEvent: false
            )
        ]
    }
    
    private func fetchMockCalendarEmails() async throws -> [Email] {
        print("🎭 Using mock calendar emails data")
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let today = Date()
        let userEmail = authService.user?.email ?? "user@example.com"
        
        return [
            Email(
                id: "calendar_1",
                subject: "Invitation: Weekly Team Standup",
                sender: EmailContact(name: "Google Calendar", email: "calendar-notification@google.com"),
                recipients: [EmailContact(name: "Dev Team", email: "dev-team@company.com")],
                body: "You have been invited to a meeting: Weekly Team Standup\n\nWhen: Tomorrow at 10:00 AM\nWhere: Conference Room A / Zoom\n\nJoin Zoom Meeting: https://zoom.us/j/123456789\n\nAgenda:\n- Sprint progress review\n- Blockers discussion\n- Next week planning",
                date: Calendar.current.date(byAdding: .hour, value: -4, to: today) ?? today,
                isRead: false,
                isImportant: false,
                labels: ["INBOX", "CALENDAR"],
                attachments: [
                    EmailAttachment(filename: "meeting.ics", mimeType: "text/calendar", size: 2048)
                ],
                isPromotional: false,
                hasCalendarEvent: true
            ),
            Email(
                id: "calendar_2",
                subject: "Meeting Reminder: Client Presentation - Tomorrow 2 PM",
                sender: EmailContact(name: "Project Manager", email: "pm@company.com"),
                recipients: [EmailContact(name: "You", email: userEmail)],
                body: "Hi team,\n\nJust a friendly reminder about our client presentation tomorrow at 2 PM. Please make sure you have:\n\n- Presentation slides ready\n- Demo environment tested\n- Backup plans prepared\n\nMeeting details:\nLocation: Client office / Teams backup\nDuration: 90 minutes\n\nLet me know if you have any questions!",
                date: Calendar.current.date(byAdding: .hour, value: -6, to: today) ?? today,
                isRead: true,
                isImportant: true,
                labels: ["INBOX", "IMPORTANT"],
                attachments: [],
                isPromotional: false,
                hasCalendarEvent: true
            )
        ]
    }
}

// MARK: - Errors

enum GmailError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case networkError
    case rateLimitExceeded
    case insufficientPermissions
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated with Gmail"
        case .invalidResponse:
            return "Invalid response from Gmail API"
        case .networkError:
            return "Network error while accessing Gmail"
        case .rateLimitExceeded:
            return "Gmail API rate limit exceeded"
        case .insufficientPermissions:
            return "Insufficient permissions to access Gmail"
        }
    }
}