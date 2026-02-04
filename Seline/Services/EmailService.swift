import Foundation
import GoogleSignIn
import UIKit

@MainActor
class EmailService: ObservableObject {
    static let shared = EmailService()

    // Folder-based email storage
    @Published var inboxEmails: [Email] = []
    @Published var sentEmails: [Email] = []

    // Loading states for each folder
    @Published var inboxLoadingState: EmailLoadingState = .idle
    @Published var sentLoadingState: EmailLoadingState = .idle

    // Search functionality
    @Published var searchResults: [Email] = []
    @Published var isSearching: Bool = false

    // MARK: - Sync Status (Phase 3)
    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    @Published var lastSyncTime: Date?

    // Debouncing for search
    private var searchTask: Task<Void, Never>?
    private let searchDebounceDelay: TimeInterval = 0.5 // 500ms delay

    // Cache for searchable emails (used by LLM search)
    @Published var cachedSearchableEmails: [SearchableItem] = []

    // Cache management
    private var cacheTimestamps: [EmailFolder: Date] = [:]
    private let cacheExpirationTime: TimeInterval = 604800 // 7 days for longer persistence
    private let newEmailCheckInterval: TimeInterval = 60 // 1 minute for real-time notifications (uses <1% of Gmail API quota)

    // Persistent cache keys
    private enum CacheKeys {
        static let inboxEmails = "cached_inbox_emails"
        static let sentEmails = "cached_sent_emails"
        static let inboxTimestamp = "cached_inbox_timestamp"
        static let sentTimestamp = "cached_sent_timestamp"
        static let lastEmailIds = "last_email_ids" // For tracking new emails

        // Custom folder cache keys
        static let customFolders = "cached_custom_folders"
        static let customFoldersTimestamp = "cached_custom_folders_timestamp"
        static func emailsInFolder(_ folderId: UUID) -> String {
            return "cached_folder_emails_\(folderId.uuidString)"
        }
        static func emailsInFolderTimestamp(_ folderId: UUID) -> String {
            return "cached_folder_emails_timestamp_\(folderId.uuidString)"
        }
    }

    // Request management
    private var currentTasks: [EmailFolder: Task<Void, Never>] = [:]

    // Pagination tracking - store next page token for each folder
    private var pageTokens: [EmailFolder: String?] = [:]
    @Published var hasMoreEmails: [EmailFolder: Bool] = [.inbox: false, .sent: false]

    // New email checking
    private var newEmailTimer: Timer?
    private var isAppActive = false // Track if app is in foreground

    private let authManager = AuthenticationManager.shared
    private let gmailAPIClient = GmailAPIClient.shared
    let notificationService = NotificationService.shared // Made public for access from EmailView
    private let openAIService = GeminiService.shared
    private let emailIntelligence = EmailNotificationIntelligence.shared

    private init() {
        // Clear old cached data on app startup to prevent showing yesterday's emails
        validateAndCleanCache()
        loadCachedData()
        // Set initial loading states based on cached data
        if !inboxEmails.isEmpty {
            inboxLoadingState = .loaded(inboxEmails)
        }
        if !sentEmails.isEmpty {
            sentLoadingState = .loaded(sentEmails)
        }
        // Don't start polling on init - only when app becomes active
        setupAppLifecycleObservers()
    }

    deinit {
        // Cancel all ongoing tasks
        for task in currentTasks.values {
            task.cancel()
        }
        searchTask?.cancel()
        newEmailTimer?.invalidate()
    }

    func loadTodaysEmails() async {
        // CRITICAL FIX: Only load inbox on app start, not sent
        // Sent emails only load when user navigates to sent tab (on-demand)
        await loadEmailsForFolder(.inbox)
    }

    func loadEmailsForFolder(_ folder: EmailFolder, forceRefresh: Bool = false) async {
        // Cancel any existing task for this folder
        currentTasks[folder]?.cancel()

        // Check if we have valid cached data and don't need to refresh
        if !forceRefresh && isCacheValid(for: folder) && !getEmails(for: folder).isEmpty {
            // Data is cached and valid, set state to loaded with cached data
            setLoadingState(for: folder, state: .loaded(getEmails(for: folder)))
            return
        }

        let task = Task { @MainActor in
            setLoadingState(for: folder, state: .loading)

            do {
                let emails: [Email]
                let nextPageToken: String?

                switch folder {
                case .inbox:
                    // Fetch 20 emails per page for better performance (was 100)
                    let result = try await gmailAPIClient.fetchInboxEmails(maxResults: 20, pageToken: nil)
                    emails = result.emails
                    nextPageToken = result.nextPageToken
                case .sent:
                    // Fetch 20 emails per page for better performance (was 100)
                    let result = try await gmailAPIClient.fetchSentEmails(maxResults: 20, pageToken: nil)
                    emails = result.emails
                    nextPageToken = result.nextPageToken
                default:
                    // For other folders, we can extend this later
                    emails = []
                    nextPageToken = nil
                }

                // Store pagination token and update hasMore status
                pageTokens[folder] = nextPageToken
                hasMoreEmails[folder] = (nextPageToken != nil)

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    return
                }

                // Filter to include only today's emails
                let filteredEmails = filterTodaysEmails(emails)

                // CRITICAL FIX: Preserve AI summaries from existing cached emails
                let existingEmails = getEmails(for: folder)
                let mergedEmails = mergeWithExistingAISummaries(newEmails: filteredEmails, existingEmails: existingEmails)

                // Update the appropriate email list
                updateEmailsForFolder(folder, emails: mergedEmails)
                setLoadingState(for: folder, state: .loaded(mergedEmails))

                // Update cache timestamp and save to persistent storage
                updateCacheTimestamp(for: folder)
                saveCachedData(for: folder)

                // Generate AI summaries in background when emails are loaded
                // This ensures summaries are ready when user opens emails
                Task.detached(priority: .background) {
                    await self.preloadAISummaries(for: mergedEmails)
                }

            } catch {
                // Only update state if not cancelled
                if !Task.isCancelled {
                    let errorMessage = self.getUserFriendlyErrorMessage(error)
                    setLoadingState(for: folder, state: .error(errorMessage))
                    print("❌ Error loading emails for \(folder.displayName): \(error)")
                }
            }

            // Clean up task reference
            currentTasks[folder] = nil
        }

        currentTasks[folder] = task
        await task.value
    }

    /// Load more emails for pagination (infinite scroll)
    func loadMoreEmails(for folder: EmailFolder) async {
        // Check if we have a next page token
        guard let pageToken = pageTokens[folder], pageToken != nil else {
            print("ℹ️ No more emails to load for \(folder.displayName)")
            return
        }

        // Don't load if already loading
        guard currentTasks[folder] == nil else {
            print("⚠️ Already loading emails for \(folder.displayName)")
            return
        }

        let task = Task { @MainActor in
            do {
                let emails: [Email]
                let nextPageToken: String?

                switch folder {
                case .inbox:
                    let result = try await gmailAPIClient.fetchInboxEmails(maxResults: 20, pageToken: pageToken)
                    emails = result.emails
                    nextPageToken = result.nextPageToken
                case .sent:
                    let result = try await gmailAPIClient.fetchSentEmails(maxResults: 20, pageToken: pageToken)
                    emails = result.emails
                    nextPageToken = result.nextPageToken
                default:
                    emails = []
                    nextPageToken = nil
                }

                guard !Task.isCancelled else {
                    return
                }

                // Filter to include only today's emails
                let filteredEmails = filterTodaysEmails(emails)

                // Merge with existing emails (append new ones)
                let existingEmails = getEmails(for: folder)
                let mergedEmails = mergeWithExistingAISummaries(newEmails: existingEmails + filteredEmails, existingEmails: existingEmails)

                // Update the appropriate email list
                updateEmailsForFolder(folder, emails: mergedEmails)

                // Update pagination state
                pageTokens[folder] = nextPageToken
                hasMoreEmails[folder] = (nextPageToken != nil)

                // Generate AI summaries in background
                Task.detached(priority: .background) {
                    await self.preloadAISummaries(for: filteredEmails)
                }

            } catch {
                if !Task.isCancelled {
                    print("❌ Error loading more emails for \(folder.displayName): \(error)")
                }
            }

            currentTasks[folder] = nil
        }

        currentTasks[folder] = task
        await task.value
    }

    /// Search emails with debouncing to avoid excessive API calls
    @MainActor
    func searchEmails(query: String) async {
        // Cancel previous search task
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If query is empty, clear results immediately
        guard !trimmedQuery.isEmpty && trimmedQuery.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        
        // Debounce: wait before making API call
        searchTask = Task { @MainActor in
            // Wait for debounce delay
            try? await Task.sleep(nanoseconds: UInt64(searchDebounceDelay * 1_000_000_000))
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await performSearch(query: trimmedQuery)
        }
        
        await searchTask?.value
    }
    
    /// Perform the actual search (called after debounce)
    @MainActor
    private func performSearch(query: String) async {
        // Minimum 2 characters required to search
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // First, try local search (no API call) for cached emails - instant results
        let allCachedEmails = inboxEmails + sentEmails
        let localResults = allCachedEmails.filter { email in
            email.subject.localizedCaseInsensitiveContains(query) ||
            email.sender.displayName.localizedCaseInsensitiveContains(query) ||
            email.sender.email.localizedCaseInsensitiveContains(query) ||
            email.snippet.localizedCaseInsensitiveContains(query)
        }
        
        // Show local results immediately if available
        if !localResults.isEmpty {
            searchResults = localResults.sorted { $0.timestamp > $1.timestamp }
        }
        
        // Then search Gmail API for more results (only if query is substantial)
        // Limit to 20 results to reduce API costs
        do {
            let emails = try await gmailAPIClient.searchEmails(query: query, maxResults: 20)
            
            // Check if task was cancelled during API call
            guard !Task.isCancelled else {
                isSearching = false
                return
            }
            
            // Merge with local results, removing duplicates
            var allResults = localResults
            let localGmailIds = Set(localResults.compactMap { $0.gmailMessageId })
            
            for email in emails {
                if let gmailId = email.gmailMessageId, !localGmailIds.contains(gmailId) {
                    allResults.append(email)
                }
            }
            
            searchResults = allResults.sorted { $0.timestamp > $1.timestamp }
        } catch {
            // If API fails, keep local results if we have them
            if searchResults.isEmpty {
                searchResults = localResults.sorted { $0.timestamp > $1.timestamp }
            }
            print("⚠️ Search API error (using local results): \(error.localizedDescription)")
        }
        
        isSearching = false
    }

    func refreshEmails() async {
        // Clear notifications when user manually refreshes
        notificationService.clearEmailNotifications()

        await loadEmailsForFolder(.inbox, forceRefresh: true)
        // Add delay to respect rate limits
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await loadEmailsForFolder(.sent, forceRefresh: true)

        // Update app badge after refresh
        let unreadCount = inboxEmails.filter { !$0.isRead }.count
        notificationService.updateAppBadge(count: unreadCount)
    }

    func refreshFolder(_ folder: EmailFolder) async {
        await loadEmailsForFolder(folder, forceRefresh: true)
    }

    // MARK: - Helper Methods

    private func setLoadingState(for folder: EmailFolder, state: EmailLoadingState) {
        switch folder {
        case .inbox:
            inboxLoadingState = state
        case .sent:
            sentLoadingState = state
        default:
            break // Handle other folders if needed
        }
    }

    private func updateEmailsForFolder(_ folder: EmailFolder, emails: [Email]) {
        switch folder {
        case .inbox:
            inboxEmails = emails
        case .sent:
            sentEmails = emails
        default:
            break // Handle other folders if needed
        }
    }



    func getEmails(for folder: EmailFolder) -> [Email] {
        switch folder {
        case .inbox: return inboxEmails
        case .sent: return sentEmails
        default: return []
        }
    }

    func getLoadingState(for folder: EmailFolder) -> EmailLoadingState {
        switch folder {
        case .inbox: return inboxLoadingState
        case .sent: return sentLoadingState
        default: return .idle
        }
    }

    func getCategorizedEmails(for folder: EmailFolder, unreadOnly: Bool = false) -> [EmailSection] {
        var emails = getEmails(for: folder)

        // Filter to unread only if requested
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }

        let categorized = EmailTimePeriod.categorizeEmails(emails, for: Date())

        return EmailTimePeriod.allCases.compactMap { period in
            let periodEmails = categorized[period] ?? []
            guard !periodEmails.isEmpty else { return nil }
            return EmailSection(timePeriod: period, emails: periodEmails)
        }
    }

    func getCategorizedEmails(for folder: EmailFolder, category: EmailCategory, unreadOnly: Bool = false) -> [EmailSection] {
        var emails = getFilteredEmails(for: folder, category: category)

        // Filter to unread only if requested
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }

        let categorized = EmailTimePeriod.categorizeEmails(emails, for: Date())

        return EmailTimePeriod.allCases.compactMap { period in
            let periodEmails = categorized[period] ?? []
            guard !periodEmails.isEmpty else { return nil }
            return EmailSection(timePeriod: period, emails: periodEmails)
        }
    }
    
    // MARK: - Day-based Email Sections (7-day rolling view)
    
    func getDayCategorizedEmails(for folder: EmailFolder, unreadOnly: Bool = false) -> [EmailDaySection] {
        var emails = getEmails(for: folder)
        
        // Filter to last 7 days
        emails = filterTodaysEmails(emails)
        
        // Filter to unread only if requested
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }
        
        return EmailDaySection.categorizeByDay(emails)
    }
    
    func getDayCategorizedEmails(for folder: EmailFolder, category: EmailCategory, unreadOnly: Bool = false) -> [EmailDaySection] {
        var emails = getFilteredEmails(for: folder, category: category)
        
        // Filter to last 7 days
        emails = filterTodaysEmails(emails)
        
        // Filter to unread only if requested
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }
        
        return EmailDaySection.categorizeByDay(emails)
    }

    func getFilteredEmails(for folder: EmailFolder, category: EmailCategory) -> [Email] {
        let allEmails = getEmails(for: folder)

        // Filter emails by category
        return allEmails.filter { email in
            email.category == category
        }
    }

    func getEmailCount(for folder: EmailFolder, category: EmailCategory) -> Int {
        return getFilteredEmails(for: folder, category: category).count
    }

    // MARK: - Clear Data on Logout

    func clearEmailsOnLogout() {
        inboxEmails = []
        sentEmails = []
        searchResults = []
        cachedSearchableEmails = []

        // Clear cache timestamps
        cacheTimestamps = [:]

        // Clear UserDefaults cache for inbox/sent
        UserDefaults.standard.removeObject(forKey: CacheKeys.inboxEmails)
        UserDefaults.standard.removeObject(forKey: CacheKeys.sentEmails)
        UserDefaults.standard.removeObject(forKey: CacheKeys.inboxTimestamp)
        UserDefaults.standard.removeObject(forKey: CacheKeys.sentTimestamp)
        UserDefaults.standard.removeObject(forKey: CacheKeys.lastEmailIds)

        // Clear custom folder cache
        clearFolderCache()

        // Clear individual folder email caches (dynamic keys)
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("cached_folder_emails_") {
                defaults.removeObject(forKey: key)
            }
        }

        // Stop email polling
        newEmailTimer?.invalidate()
        newEmailTimer = nil

        print("🗑️ Cleared all emails and email cache on logout")
    }

    // MARK: - Email Actions

    func replyToEmail(_ email: Email) {
        guard let senderEmail = email.sender.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        // Construct reply subject with "Re: " prefix if not already present
        let replySubjectRaw = email.subject.hasPrefix("Re: ") ? email.subject : "Re: \(email.subject)"
        guard let replySubject = replySubjectRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        // Create a formatted reply with original email content
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        // Add attachment info if email has attachments
        var attachmentInfo = ""
        if email.hasAttachments && !email.attachments.isEmpty {
            attachmentInfo = "\n\n[Original email has \(email.attachments.count) attachment(s): \(email.attachments.map { $0.name }.joined(separator: ", "))]"
        }

        let replyContent = """



        On \(dateFormatter.string(from: email.timestamp)), \(email.sender.displayName) wrote:
        > \(email.body ?? email.snippet)\(attachmentInfo)
        """

        guard let emailBody = replyContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        // Try Gmail compose URL schemes for reply with original content
        let replyURLs = [
            "googlegmail://co?to=\(senderEmail)&subject=\(replySubject)&body=\(emailBody)",
            "googlegmail:///co?to=\(senderEmail)&subject=\(replySubject)&body=\(emailBody)",
            "mailto:\(senderEmail)?subject=\(replySubject)&body=\(emailBody)" // Fallback to system mail
        ]

        openEmailURL(replyURLs, action: "reply")
    }

    func forwardEmail(_ email: Email) {
        guard let subject = email.subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        // Construct forward subject with "Fwd: " prefix if not already present
        let forwardSubject = email.subject.hasPrefix("Fwd: ") ? subject : "Fwd:%20\(subject)"

        // Create a formatted forwarded message with context
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        // Add attachment info if email has attachments
        var attachmentInfo = ""
        if email.hasAttachments && !email.attachments.isEmpty {
            attachmentInfo = "\n\n[This email has \(email.attachments.count) attachment(s): \(email.attachments.map { $0.name }.joined(separator: ", "))]"
        }

        let forwardedContent = """
        ---------- Forwarded message ---------
        From: \(email.sender.displayName) <\(email.sender.email)>
        Date: \(dateFormatter.string(from: email.timestamp))
        Subject: \(email.subject)

        \(email.body ?? email.snippet)\(attachmentInfo)
        """

        guard let emailBody = forwardedContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        // Try Gmail compose URL schemes for forward
        let forwardURLs = [
            "googlegmail://co?subject=\(forwardSubject)&body=\(emailBody)",
            "googlegmail:///co?subject=\(forwardSubject)&body=\(emailBody)",
            "mailto:?subject=\(forwardSubject)&body=\(emailBody)" // Fallback to system mail
        ]

        openEmailURL(forwardURLs, action: "forward")
    }

    private func openEmailURL(_ urls: [String], action: String) {
        for urlString in urls {
            if let url = URL(string: urlString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url) { _ in }
                    return
                }
            }
        }
    }

    func deleteEmail(_ email: Email) async throws {
        guard let gmailMessageId = email.gmailMessageId else {
            throw EmailServiceError.missingGmailId
        }

        // First, delete from Gmail using the API
        try await gmailAPIClient.trashEmail(messageId: gmailMessageId)

        // Then remove from local storage
        await MainActor.run {
            removeEmailFromLocalStorage(email)
        }
    }

    private func removeEmailFromLocalStorage(_ email: Email) {
        var wasRemoved = false

        // Remove from inbox emails
        if let inboxIndex = inboxEmails.firstIndex(where: { $0.id == email.id }) {
            inboxEmails.remove(at: inboxIndex)
            wasRemoved = true
        }

        // Remove from sent emails
        if let sentIndex = sentEmails.firstIndex(where: { $0.id == email.id }) {
            sentEmails.remove(at: sentIndex)
            wasRemoved = true
        }

        // Remove from search results if present
        if let searchIndex = searchResults.firstIndex(where: { $0.id == email.id }) {
            searchResults.remove(at: searchIndex)
        }

        // Save updated cache if email was removed
        if wasRemoved {
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)

            // Update app badge count
            Task {
                let unreadCount = inboxEmails.filter { !$0.isRead }.count
                notificationService.updateAppBadge(count: unreadCount)
            }
        }
    }

    func markAsRead(_ email: Email) {
        var wasUpdated = false

        // Update in inbox emails
        if let inboxIndex = inboxEmails.firstIndex(where: { $0.id == email.id }) {
            if !inboxEmails[inboxIndex].isRead {
                let currentEmail = inboxEmails[inboxIndex]
                let updatedEmail = Email(
                    id: currentEmail.id,
                    threadId: currentEmail.threadId,
                    sender: currentEmail.sender,
                    recipients: currentEmail.recipients,
                    ccRecipients: currentEmail.ccRecipients,
                    subject: currentEmail.subject,
                    snippet: currentEmail.snippet,
                    body: currentEmail.body,
                    timestamp: currentEmail.timestamp,
                    isRead: true, // Mark as read
                    isImportant: currentEmail.isImportant,
                    hasAttachments: currentEmail.hasAttachments,
                    attachments: currentEmail.attachments,
                    labels: currentEmail.labels,
                    aiSummary: currentEmail.aiSummary,
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
                )
                inboxEmails[inboxIndex] = updatedEmail
                wasUpdated = true
            }
        }

        // Update in sent emails if it exists there too
        if let sentIndex = sentEmails.firstIndex(where: { $0.id == email.id }) {
            if !sentEmails[sentIndex].isRead {
                let currentEmail = sentEmails[sentIndex]
                let updatedEmail = Email(
                    id: currentEmail.id,
                    threadId: currentEmail.threadId,
                    sender: currentEmail.sender,
                    recipients: currentEmail.recipients,
                    ccRecipients: currentEmail.ccRecipients,
                    subject: currentEmail.subject,
                    snippet: currentEmail.snippet,
                    body: currentEmail.body,
                    timestamp: currentEmail.timestamp,
                    isRead: true, // Mark as read
                    isImportant: currentEmail.isImportant,
                    hasAttachments: currentEmail.hasAttachments,
                    attachments: currentEmail.attachments,
                    labels: currentEmail.labels,
                    aiSummary: currentEmail.aiSummary,
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
                )
                sentEmails[sentIndex] = updatedEmail
                wasUpdated = true
            }
        }

        // Only save and update if something actually changed
        if wasUpdated {
            // Mark as read in Gmail
            if let gmailMessageId = email.gmailMessageId {
                Task {
                    do {
                        try await GmailAPIClient.shared.markAsRead(messageId: gmailMessageId)
                    } catch {
                        print("❌ Failed to mark email as read in Gmail: \(error)")
                    }
                }
            }

            // Save updated data to persistent cache
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)

            // Update app badge count
            Task {
                let unreadCount = inboxEmails.filter { !$0.isRead }.count
                notificationService.updateAppBadge(count: unreadCount)
            }
        }
    }

    func markAsUnread(_ email: Email) {
        var wasUpdated = false

        // Update in inbox emails
        if let inboxIndex = inboxEmails.firstIndex(where: { $0.id == email.id }) {
            if inboxEmails[inboxIndex].isRead {
                let currentEmail = inboxEmails[inboxIndex]
                let updatedEmail = Email(
                    id: currentEmail.id,
                    threadId: currentEmail.threadId,
                    sender: currentEmail.sender,
                    recipients: currentEmail.recipients,
                    ccRecipients: currentEmail.ccRecipients,
                    subject: currentEmail.subject,
                    snippet: currentEmail.snippet,
                    body: currentEmail.body,
                    timestamp: currentEmail.timestamp,
                    isRead: false, // Mark as unread
                    isImportant: currentEmail.isImportant,
                    hasAttachments: currentEmail.hasAttachments,
                    attachments: currentEmail.attachments,
                    labels: currentEmail.labels,
                    aiSummary: currentEmail.aiSummary,
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
                )
                inboxEmails[inboxIndex] = updatedEmail
                wasUpdated = true
            }
        }

        // Update in sent emails if it exists there too
        if let sentIndex = sentEmails.firstIndex(where: { $0.id == email.id }) {
            if sentEmails[sentIndex].isRead {
                let currentEmail = sentEmails[sentIndex]
                let updatedEmail = Email(
                    id: currentEmail.id,
                    threadId: currentEmail.threadId,
                    sender: currentEmail.sender,
                    recipients: currentEmail.recipients,
                    ccRecipients: currentEmail.ccRecipients,
                    subject: currentEmail.subject,
                    snippet: currentEmail.snippet,
                    body: currentEmail.body,
                    timestamp: currentEmail.timestamp,
                    isRead: false, // Mark as unread
                    isImportant: currentEmail.isImportant,
                    hasAttachments: currentEmail.hasAttachments,
                    attachments: currentEmail.attachments,
                    labels: currentEmail.labels,
                    aiSummary: currentEmail.aiSummary,
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
                )
                sentEmails[sentIndex] = updatedEmail
                wasUpdated = true
            }
        }

        if wasUpdated {
            // Mark as unread in Gmail
            if let gmailMessageId = email.gmailMessageId {
                Task {
                    do {
                        try await GmailAPIClient.shared.markAsUnread(messageId: gmailMessageId)
                    } catch {
                        print("❌ Failed to mark email as unread in Gmail: \(error)")
                    }
                }
            }

            // Save updated data to persistent cache
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)

            Task {
                // Update app badge with new unread count
                let unreadCount = inboxEmails.filter { !$0.isRead }.count
                notificationService.updateAppBadge(count: unreadCount)
            }
        }
    }

    func updateEmailWithAISummary(_ email: Email, summary: String) async {
        var wasUpdated = false

        // Update in inbox emails
        if let inboxIndex = inboxEmails.firstIndex(where: { $0.id == email.id }) {
            let currentEmail = inboxEmails[inboxIndex]
            let updatedEmail = Email(
                id: currentEmail.id,
                threadId: currentEmail.threadId,
                sender: currentEmail.sender,
                recipients: currentEmail.recipients,
                ccRecipients: currentEmail.ccRecipients,
                subject: currentEmail.subject,
                snippet: currentEmail.snippet,
                body: currentEmail.body,
                timestamp: currentEmail.timestamp,
                isRead: currentEmail.isRead,
                isImportant: currentEmail.isImportant,
                hasAttachments: currentEmail.hasAttachments,
                attachments: currentEmail.attachments,
                    labels: currentEmail.labels,
                    aiSummary: summary, // Update AI summary
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
            )
            inboxEmails[inboxIndex] = updatedEmail
            wasUpdated = true
        }

        // Update in sent emails if it exists there too
        if let sentIndex = sentEmails.firstIndex(where: { $0.id == email.id }) {
            let currentEmail = sentEmails[sentIndex]
            let updatedEmail = Email(
                id: currentEmail.id,
                threadId: currentEmail.threadId,
                sender: currentEmail.sender,
                recipients: currentEmail.recipients,
                ccRecipients: currentEmail.ccRecipients,
                subject: currentEmail.subject,
                snippet: currentEmail.snippet,
                body: currentEmail.body,
                timestamp: currentEmail.timestamp,
                isRead: currentEmail.isRead,
                isImportant: currentEmail.isImportant,
                hasAttachments: currentEmail.hasAttachments,
                attachments: currentEmail.attachments,
                labels: currentEmail.labels,
                aiSummary: summary, // Update AI summary
                gmailMessageId: currentEmail.gmailMessageId,
                gmailThreadId: currentEmail.gmailThreadId,
                unsubscribeInfo: currentEmail.unsubscribeInfo
            )
            sentEmails[sentIndex] = updatedEmail
            wasUpdated = true
        }

        // Only save if something actually changed
        if wasUpdated {
            // Save updated data to persistent cache
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)
        }
    }

    // MARK: - AI Summary Pre-loading

    private func preloadAISummaries(for emails: [Email]) async {
        // Filter emails that don't have AI summaries yet (or have empty summaries)
        let emailsNeedingSummary = emails.filter { email in
            email.aiSummary == nil || email.aiSummary?.isEmpty == true
        }

        guard !emailsNeedingSummary.isEmpty else {
            return
        }

        // Generate summaries one at a time to respect rate limits
        for email in emailsNeedingSummary {
            do {
                // CRITICAL FIX: Fetch raw email body optimized for AI processing
                // This gets clean HTML/text without display wrapping
                var rawEmailBody: String?

                if let gmailMessageId = email.gmailMessageId {
                    // Use the new AI-optimized body extraction
                    rawEmailBody = try await gmailAPIClient.fetchBodyForAI(messageId: gmailMessageId)

                    // Debug logging to track content extraction
                    if rawEmailBody == nil || rawEmailBody?.isEmpty == true {
                        print("⚠️ No body content extracted for email: '\(email.subject)' (ID: \(gmailMessageId))")
                    }
                }

                // Fall back to snippet if body is unavailable
                let emailBody = rawEmailBody ?? email.snippet

                let summary = try await openAIService.summarizeEmail(
                    subject: email.subject,
                    body: emailBody
                )

                // Update the email with the summary
                await updateEmailWithAISummary(email, summary: summary)

            } catch {
                // Log detailed error but continue with other emails
                print("⚠️ Failed to generate summary for '\(email.subject)': \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App Lifecycle Management

    private func setupAppLifecycleObservers() {
        // Observe when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Observe when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        isAppActive = true

        // Fetch emails when app opens
        Task { @MainActor in
            await loadTodaysEmails()
        }

        // Start polling for new emails every 60 seconds
        // This enables automatic UI refresh and real-time notifications
        startNewEmailPolling()
    }

    @objc private func appDidEnterBackground() {
        isAppActive = false
        // Stop email polling when app goes to background to save battery
        stopNewEmailPolling()
    }

    // MARK: - New Email Polling

    private func startNewEmailPolling() {
        // Cancel any existing timer
        newEmailTimer?.invalidate()
        
        // Only poll if user is authenticated
        guard GIDSignIn.sharedInstance.currentUser != nil else {
            print("📧 Email polling disabled - user not authenticated")
            return
        }
        
        print("📧 Starting email polling (every \(Int(newEmailCheckInterval)) seconds)")
        
        // Create a timer that fires every 60 seconds to check for new emails
        newEmailTimer = Timer.scheduledTimer(withTimeInterval: newEmailCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForNewEmails()
            }
        }
        
        // Add to run loop to ensure it fires even during scrolling
        if let timer = newEmailTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopNewEmailPolling() {
        newEmailTimer?.invalidate()
        newEmailTimer = nil
        print("⏹️ Email polling stopped")
    }

    private func showNewEmailNotification(newEmails: [Email]) async {
        guard !newEmails.isEmpty else { return }

        let latestEmail = newEmails.first // Already sorted by timestamp descending
        await notificationService.scheduleNewEmailNotification(
            emailCount: newEmails.count,
            latestSender: latestEmail?.sender.displayName,
            latestSubject: latestEmail?.subject,
            latestEmailId: latestEmail?.id
        )

        // Update app badge with total unread count
        let unreadCount = inboxEmails.filter { !$0.isRead }.count
        notificationService.updateAppBadge(count: unreadCount)
    }
    
    /// Last time we checked for new emails (for rate limiting)
    private var lastEmailCheckTime: Date?
    
    /// Public method to check for new emails - can be called when navigating to email tab
    /// Rate limited to prevent excessive API calls (minimum 10 seconds between checks)
    func checkForNewEmailsIfNeeded() async {
        // Rate limit: don't check more than once every 10 seconds
        if let lastCheck = lastEmailCheckTime, Date().timeIntervalSince(lastCheck) < 10 {
            return
        }
        lastEmailCheckTime = Date()
        await checkForNewEmails()
    }

    private func checkForNewEmails() async {
        // Check for new emails and show detailed notifications
        // Only fetches metadata (5 quota units per email) for lightweight checks

        // Only check for new emails if we have cached data and user is authenticated
        guard !inboxEmails.isEmpty, GIDSignIn.sharedInstance.currentUser != nil else { return }

        do {
            // Fetch latest 3 emails from inbox
            let messageList = try await gmailAPIClient.fetchMessagesList(query: "in:inbox", maxResults: 3)
            let messageIds = messageList.messages?.map { $0.id } ?? []

            // Check if we have any new message IDs that aren't in our current list
            let newMessageIds = messageIds.filter { newId in
                !inboxEmails.contains { existingEmail in
                    existingEmail.id == newId
                }
            }

            if !newMessageIds.isEmpty {
                // CRITICAL FIX: Reload inbox emails to show new emails in UI
                await loadEmailsForFolder(.inbox, forceRefresh: true)

                // Only notify for emails from TODAY to prevent showing old cached emails
                // Filter newly loaded emails to today's emails only
                let todaysNewEmails = newMessageIds.compactMap { newId in
                    inboxEmails.first { email in
                        email.id == newId && Calendar.current.isDateInToday(email.timestamp)
                    }
                }

                // Only send notification if we have new emails from TODAY
                if !todaysNewEmails.isEmpty {
                    // Use email intelligence to determine which emails should notify
                    var emailsToNotify: [Email] = []

                    for email in todaysNewEmails {
                        // Record email activity for thread consolidation
                        emailIntelligence.recordEmailActivity(email: email)

                        // Check if this email should trigger a notification
                        if let priority = await emailIntelligence.shouldNotify(for: email) {
                            if priority.shouldNotify {
                                emailsToNotify.append(email)
                                print("📧 Email should notify: '\(email.subject)' - \(priority.displayReason)")
                            } else {
                                print("🔇 Email notification suppressed: '\(email.subject)' - \(priority.displayReason)")
                            }
                        }
                    }

                    // Check for thread consolidation
                    var consolidatedNotifications: [String: [Email]] = [:] // threadId: emails
                    var standaloneEmails: [Email] = []

                    for email in emailsToNotify {
                        if let threadId = email.threadId ?? email.gmailThreadId {
                            if consolidatedNotifications[threadId] == nil {
                                consolidatedNotifications[threadId] = []
                            }
                            consolidatedNotifications[threadId]?.append(email)
                        } else {
                            standaloneEmails.append(email)
                        }
                    }

                    // Send consolidated thread notifications
                    for (threadId, emails) in consolidatedNotifications {
                        if emails.count > 1 {
                            // Multiple emails in same thread - send consolidated notification
                            let senders = Set(emails.map { $0.sender.displayName }).joined(separator: ", ")
                            let latestEmail = emails.first
                            await notificationService.scheduleNewEmailNotification(
                                emailCount: emails.count,
                                latestSender: senders,
                                latestSubject: "[\(emails.count) messages] \(latestEmail?.subject ?? "")",
                                latestEmailId: latestEmail?.id
                            )
                            print("📨 Sent consolidated notification for thread with \(emails.count) emails")

                            // Clear thread activity after sending notification
                            emailIntelligence.clearThreadActivity(threadId: threadId)
                        } else if let email = emails.first {
                            // Single email in thread
                            standaloneEmails.append(email)
                        }
                    }

                    // Send standalone email notifications
                    for email in standaloneEmails {
                        await notificationService.scheduleNewEmailNotification(
                            emailCount: 1,
                            latestSender: email.sender.displayName,
                            latestSubject: email.subject,
                            latestEmailId: email.id
                        )
                        print("📧 Sent notification for email: '\(email.subject)'")
                    }

                    // Update badge count (only count today's unread emails)
                    let currentUnreadCount = todaysNewEmails.filter { !$0.isRead }.count
                    notificationService.updateAppBadge(count: currentUnreadCount)
                }
            }
        } catch {
            print("❌ Error checking for new emails: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Validates and cleans cached data on app startup
    /// Removes emails that are not from today to prevent stale notifications
    private func validateAndCleanCache() {
        // Load current cache
        if let inboxData = UserDefaults.standard.data(forKey: CacheKeys.inboxEmails),
           let cachedInboxEmails = try? JSONDecoder().decode([Email].self, from: inboxData) {
            // Filter to keep only today's emails
            let todaysEmails = filterTodaysEmails(cachedInboxEmails)

            // If we had emails and now we have fewer, save the cleaned cache
            if cachedInboxEmails.count > todaysEmails.count {
                // Save cleaned emails back to cache
                if let encoded = try? JSONEncoder().encode(todaysEmails) {
                    UserDefaults.standard.set(encoded, forKey: CacheKeys.inboxEmails)
                }
            }
        }

        // Clear cache timestamps if older than today (force refresh)
        if let inboxTimestamp = UserDefaults.standard.object(forKey: CacheKeys.inboxTimestamp) as? Date {
            let calendar = Calendar.current
            if !calendar.isDateInToday(inboxTimestamp) {
                UserDefaults.standard.removeObject(forKey: CacheKeys.inboxTimestamp)
            }
        }
    }

    private func loadCachedData() {
        // Load cached emails from persistent storage
        if let inboxData = UserDefaults.standard.data(forKey: CacheKeys.inboxEmails),
           let cachedInboxEmails = try? JSONDecoder().decode([Email].self, from: inboxData) {
            inboxEmails = cachedInboxEmails
        }

        if let sentData = UserDefaults.standard.data(forKey: CacheKeys.sentEmails),
           let cachedSentEmails = try? JSONDecoder().decode([Email].self, from: sentData) {
            sentEmails = cachedSentEmails
        }

        // Load cache timestamps
        if let inboxTimestamp = UserDefaults.standard.object(forKey: CacheKeys.inboxTimestamp) as? Date {
            cacheTimestamps[.inbox] = inboxTimestamp
        }

        if let sentTimestamp = UserDefaults.standard.object(forKey: CacheKeys.sentTimestamp) as? Date {
            cacheTimestamps[.sent] = sentTimestamp
        }
    }

    private func saveCachedData(for folder: EmailFolder) {
        let emails = getEmails(for: folder)
        let encoder = JSONEncoder()

        do {
            let data = try encoder.encode(emails)
            switch folder {
            case .inbox:
                UserDefaults.standard.set(data, forKey: CacheKeys.inboxEmails)
                UserDefaults.standard.set(Date(), forKey: CacheKeys.inboxTimestamp)
            case .sent:
                UserDefaults.standard.set(data, forKey: CacheKeys.sentEmails)
                UserDefaults.standard.set(Date(), forKey: CacheKeys.sentTimestamp)
            default:
                break
            }
        } catch {
            print("❌ Failed to save cached emails for \(folder.displayName): \(error)")
        }
    }

    private func isCacheValid(for folder: EmailFolder) -> Bool {
        guard let timestamp = cacheTimestamps[folder] else {
            return false
        }

        // Cache is valid for 7 days
        return Date().timeIntervalSince(timestamp) < cacheExpirationTime
    }

    private func updateCacheTimestamp(for folder: EmailFolder) {
        cacheTimestamps[folder] = Date()

        // Also update persistent timestamp
        switch folder {
        case .inbox:
            UserDefaults.standard.set(Date(), forKey: CacheKeys.inboxTimestamp)
        case .sent:
            UserDefaults.standard.set(Date(), forKey: CacheKeys.sentTimestamp)
        default:
            break
        }
    }

    func clearCache(for folder: EmailFolder? = nil) {
        if let folder = folder {
            cacheTimestamps.removeValue(forKey: folder)

            // Clear persistent cache
            switch folder {
            case .inbox:
                UserDefaults.standard.removeObject(forKey: CacheKeys.inboxEmails)
                UserDefaults.standard.removeObject(forKey: CacheKeys.inboxTimestamp)
            case .sent:
                UserDefaults.standard.removeObject(forKey: CacheKeys.sentEmails)
                UserDefaults.standard.removeObject(forKey: CacheKeys.sentTimestamp)
            default:
                break
            }
        } else {
            cacheTimestamps.removeAll()

            // Clear all persistent cache
            UserDefaults.standard.removeObject(forKey: CacheKeys.inboxEmails)
            UserDefaults.standard.removeObject(forKey: CacheKeys.sentEmails)
            UserDefaults.standard.removeObject(forKey: CacheKeys.inboxTimestamp)
            UserDefaults.standard.removeObject(forKey: CacheKeys.sentTimestamp)
            UserDefaults.standard.removeObject(forKey: CacheKeys.lastEmailIds)
        }
    }

    // MARK: - Background Refresh

    /// Called by iOS when the app is woken for background refresh
    /// This allows checking for new emails and sending notifications even when app is closed
    func handleBackgroundRefresh() async {
        print("📧 Background refresh: Checking for new emails...")
        
        // Only proceed if user is authenticated
        guard GIDSignIn.sharedInstance.currentUser != nil else {
            print("📧 Background refresh: User not authenticated, skipping")
            return
        }
        
        // Load cached data if not already loaded
        if inboxEmails.isEmpty {
            loadCachedData()
        }
        
        // If still empty, force load inbox emails
        if inboxEmails.isEmpty {
            print("📧 Background refresh: No cached emails, fetching fresh inbox...")
            await loadEmailsForFolder(.inbox, forceRefresh: true)
        }
        
        // Check for new emails and send notifications
        await checkForNewEmails()
        
        print("📧 Background refresh: Complete - Checked \(inboxEmails.count) emails")
    }

    // MARK: - Private Methods

    /// Merges new emails with existing emails, preserving AI summaries that were already generated
    private func mergeWithExistingAISummaries(newEmails: [Email], existingEmails: [Email]) -> [Email] {
        // Create a dictionary of existing emails by their ID for quick lookup
        let existingSummaries = Dictionary(uniqueKeysWithValues: existingEmails.map { ($0.id, $0.aiSummary) })

        // Map through new emails and restore AI summaries if they exist
        return newEmails.map { newEmail in
            // If this email had an AI summary before, restore it
            if let existingSummary = existingSummaries[newEmail.id], existingSummary != nil && !existingSummary!.isEmpty {
                return Email(
                    id: newEmail.id,
                    threadId: newEmail.threadId,
                    sender: newEmail.sender,
                    recipients: newEmail.recipients,
                    ccRecipients: newEmail.ccRecipients,
                    subject: newEmail.subject,
                    snippet: newEmail.snippet,
                    body: newEmail.body,
                    timestamp: newEmail.timestamp,
                    isRead: newEmail.isRead,
                    isImportant: newEmail.isImportant,
                    hasAttachments: newEmail.hasAttachments,
                    attachments: newEmail.attachments,
                    labels: newEmail.labels,
                    aiSummary: existingSummary, // Restore the existing AI summary
                    gmailMessageId: newEmail.gmailMessageId,
                    gmailThreadId: newEmail.gmailThreadId,
                    unsubscribeInfo: newEmail.unsubscribeInfo
                )
            }
            return newEmail
        }
    }

    private func filterTodaysEmails(_ emails: [Email], daysBack: Int = 30) -> [Email] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get date N days ago (configurable, default 30 days)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -(daysBack - 1), to: today) else {
            return emails.sorted { $0.timestamp > $1.timestamp }
        }

        return emails.filter { email in
            email.timestamp >= cutoffDate
        }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Gmail API Integration (Future Implementation)

    private func configureGmailAPI() async throws {
        guard authManager.currentUser != nil else {
            throw EmailServiceError.notAuthenticated
        }

        // TODO: Configure Gmail API with proper scopes
        // The Google OAuth flow would need to include Gmail scopes:
        // - https://www.googleapis.com/auth/gmail.readonly
        // - https://www.googleapis.com/auth/gmail.send (if sending emails)
    }

    private func makeGmailAPIRequest(endpoint: String) async throws -> Data {
        guard let user = authManager.currentUser else {
            throw EmailServiceError.notAuthenticated
        }

        let accessToken = user.accessToken.tokenString

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(endpoint)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmailServiceError.apiError
        }

        return data
    }

    // MARK: - Save Email to Folder

    /// Save an email to a custom folder with attachments
    func saveEmailToFolder(_ email: Email, folderId: UUID) async throws -> SavedEmail {
        let emailFolderService = await EmailFolderService.shared
        var emailToSave = email

        // First, fetch full email body if needed
        // CRITICAL: Preserve attachments from original email when fetching full body
        let originalAttachments = emailToSave.attachments
        let originalHasAttachments = emailToSave.hasAttachments
        
        do {
            if emailToSave.body == nil || emailToSave.body?.isEmpty == true {
                if let messageId = emailToSave.gmailMessageId {
                    if let fetchedEmail = try await GmailAPIClient.shared.fetchFullEmailBody(messageId: messageId) {
                        // CRITICAL FIX: If fetched email has no attachments but original does, preserve them
                        if originalHasAttachments && !originalAttachments.isEmpty && fetchedEmail.attachments.isEmpty {
                            // Create new Email with preserved attachments and fetched body
                            emailToSave = Email(
                                id: fetchedEmail.id,
                                threadId: fetchedEmail.threadId,
                                sender: fetchedEmail.sender,
                                recipients: fetchedEmail.recipients,
                                ccRecipients: fetchedEmail.ccRecipients,
                                subject: fetchedEmail.subject,
                                snippet: fetchedEmail.snippet,
                                body: fetchedEmail.body,
                                timestamp: fetchedEmail.timestamp,
                                isRead: fetchedEmail.isRead,
                                isImportant: fetchedEmail.isImportant,
                                hasAttachments: originalHasAttachments,
                                attachments: originalAttachments,
                                labels: fetchedEmail.labels,
                                aiSummary: fetchedEmail.aiSummary,
                                gmailMessageId: fetchedEmail.gmailMessageId,
                                gmailThreadId: fetchedEmail.gmailThreadId,
                                unsubscribeInfo: fetchedEmail.unsubscribeInfo
                            )
                            print("✅ Fetched full email body and preserved \(originalAttachments.count) attachment(s)")
                        } else {
                            // Use fetched email (it has attachments or no attachments needed)
                            emailToSave = fetchedEmail
                            print("✅ Fetched full email body for saving")
                        }
                    }
                }
            }
        } catch {
            print("⚠️ Warning: Failed to fetch full email body: \(error)")
            // Continue with current email data
        }

        // Generate AI summary
        var aiSummary: String? = nil
        do {
            let emailBody = emailToSave.body ?? emailToSave.snippet
            let plainTextContent = Self.stripHTMLTags(from: emailBody ?? "")

            if plainTextContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count >= 20 {
                let summary = try await openAIService.summarizeEmail(
                    subject: emailToSave.subject,
                    body: emailBody ?? ""
                )
                aiSummary = summary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ? nil : summary
                print("✅ Generated AI summary for email")
            }
        } catch {
            print("⚠️ Warning: Failed to generate AI summary: \(error)")
            // Continue saving email even if summary generation fails
        }

        // Download and upload attachments if any
        var savedAttachments: [SavedEmailAttachment] = []
        if emailToSave.hasAttachments && !emailToSave.attachments.isEmpty {
            do {
                savedAttachments = try await downloadAndSaveAttachments(
                    from: emailToSave,
                    toFolderId: folderId
                )
            } catch {
                print("⚠️ Warning: Failed to download some attachments: \(error)")
                // Continue saving email even if attachments fail
            }
        }

        // Save email to folder with full body and AI summary
        let savedEmail = try await emailFolderService.saveEmail(
            from: emailToSave,
            to: folderId,
            with: savedAttachments,
            aiSummary: aiSummary
        )

        return savedEmail
    }

    /// Download email attachments and save to Supabase Storage
    func downloadAndSaveAttachments(
        from email: Email,
        toFolderId: UUID
    ) async throws -> [SavedEmailAttachment] {
        var savedAttachments: [SavedEmailAttachment] = []
        let supabaseManager = SupabaseManager.shared
        let emailFolderService = await EmailFolderService.shared

        for attachment in email.attachments {
            do {
                // Download attachment from Gmail
                guard let messageId = email.gmailMessageId else {
                    print("⚠️ Warning: No Gmail message ID for email, skipping attachments")
                    continue
                }

                guard let fileData = try await gmailAPIClient.downloadAttachment(
                    messageId: messageId,
                    attachmentId: attachment.id
                ) else {
                    print("⚠️ Warning: Failed to download attachment '\(attachment.name)' - no data returned")
                    continue
                }

                print("✅ Downloaded attachment '\(attachment.name)' (\(fileData.count) bytes)")

                // Upload to Supabase Storage
                let storagePath = "email-attachments/\(messageId)/\(attachment.id)/\(attachment.name)"
                try await supabaseManager.uploadFile(
                    data: fileData,
                    bucket: "email-attachments",
                    path: storagePath
                )

                print("✅ Uploaded attachment '\(attachment.name)' to Supabase Storage")

                // Create attachment record in database
                // Note: This will be saved when SavedEmail is saved via EmailFolderService
                let savedAttachment = SavedEmailAttachment(
                    id: UUID(),
                    savedEmailId: UUID(), // Will be updated after SavedEmail is created
                    fileName: attachment.name,
                    fileSize: Int64(fileData.count),
                    mimeType: attachment.mimeType,
                    storagePath: storagePath,
                    uploadedAt: Date()
                )
                savedAttachments.append(savedAttachment)

            } catch {
                print("⚠️ Warning: Failed to download attachment '\(attachment.name)': \(error)")
                // Continue with other attachments
            }
        }

        return savedAttachments
    }

    // MARK: - Custom Folder Caching

    /// Check if custom folder cache is valid (not expired)
    private func isFolderCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: CacheKeys.customFoldersTimestamp) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheExpirationTime
    }

    /// Load cached custom folders
    private func loadCachedFolders() -> [CustomEmailFolder]? {
        guard let data = UserDefaults.standard.data(forKey: CacheKeys.customFolders) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([CustomEmailFolder].self, from: data)
        } catch {
            print("⚠️ Failed to decode cached folders: \(error)")
            return nil
        }
    }

    /// Save custom folders to cache
    private func saveCachedFolders(_ folders: [CustomEmailFolder]) {
        do {
            let data = try JSONEncoder().encode(folders)
            UserDefaults.standard.set(data, forKey: CacheKeys.customFolders)
            UserDefaults.standard.set(Date(), forKey: CacheKeys.customFoldersTimestamp)
            print("✅ Saved \(folders.count) folders to cache")
        } catch {
            print("❌ Failed to cache folders: \(error)")
        }
    }

    /// Load cached emails for a specific folder
    private func loadCachedFolderEmails(_ folderId: UUID) -> [SavedEmail]? {
        guard let data = UserDefaults.standard.data(forKey: CacheKeys.emailsInFolder(folderId)) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([SavedEmail].self, from: data)
        } catch {
            print("⚠️ Failed to decode cached emails for folder \(folderId): \(error)")
            return nil
        }
    }

    /// Check if folder emails cache is valid
    private func isFolderEmailsCacheValid(_ folderId: UUID) -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: CacheKeys.emailsInFolderTimestamp(folderId)) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheExpirationTime
    }

    /// Save folder emails to cache
    private func saveCachedFolderEmails(_ emails: [SavedEmail], for folderId: UUID) {
        do {
            let data = try JSONEncoder().encode(emails)
            UserDefaults.standard.set(data, forKey: CacheKeys.emailsInFolder(folderId))
            UserDefaults.standard.set(Date(), forKey: CacheKeys.emailsInFolderTimestamp(folderId))
        } catch {
            print("❌ Failed to cache emails for folder \(folderId): \(error)")
        }
    }

    /// Get all saved email folders (with caching)
    func fetchSavedFolders(forceRefresh: Bool = false) async throws -> [CustomEmailFolder] {
        // Check cache first (unless force refresh is requested)
        if !forceRefresh && isFolderCacheValid(), let cachedFolders = loadCachedFolders() {
            print("📂 Using cached folders (\(cachedFolders.count) folders)")
            return cachedFolders
        }

        // If cache is invalid or empty, fetch from Supabase
        print("🔄 Fetching folders from Supabase...")
        let emailFolderService = await EmailFolderService.shared
        do {
            let folders = try await emailFolderService.fetchFolders()
            print("📂 Fetched \(folders.count) folders from Supabase")

            // Cache the results
            saveCachedFolders(folders)

            return folders
        } catch {
            print("❌ Error fetching folders from Supabase: \(error)")
            // If Supabase fetch fails, try to use cache as fallback
            if let cachedFolders = loadCachedFolders() {
                print("⚠️ Using stale cache as fallback (\(cachedFolders.count) folders)")
                return cachedFolders
            }
            throw error
        }
    }

    /// Force clear the folder cache (useful for debugging/recovery)
    func clearFolderCache() {
        UserDefaults.standard.removeObject(forKey: CacheKeys.customFolders)
        UserDefaults.standard.removeObject(forKey: CacheKeys.customFoldersTimestamp)
        print("🗑️ Folder cache cleared")
    }

    /// Create a new email folder
    func createEmailFolder(name: String, color: String = "#84cae9") async throws -> CustomEmailFolder {
        let emailFolderService = await EmailFolderService.shared
        return try await emailFolderService.createFolder(name: name, color: color)
    }

    /// Rename an email folder
    func renameEmailFolder(id: UUID, newName: String) async throws -> CustomEmailFolder {
        let emailFolderService = await EmailFolderService.shared
        return try await emailFolderService.renameFolder(id: id, newName: newName)
    }

    /// Update email folder color
    func updateEmailFolderColor(id: UUID, color: String) async throws -> CustomEmailFolder {
        let emailFolderService = await EmailFolderService.shared
        return try await emailFolderService.updateFolderColor(id: id, color: color)
    }

    /// Delete an email folder
    func deleteEmailFolder(id: UUID) async throws {
        let emailFolderService = await EmailFolderService.shared
        try await emailFolderService.deleteFolder(id: id)
    }

    /// Get all saved emails in a folder (with caching)
    func fetchSavedEmails(in folderId: UUID, forceRefresh: Bool = false) async throws -> [SavedEmail] {
        // Check cache first
        if !forceRefresh && isFolderEmailsCacheValid(folderId), let cachedEmails = loadCachedFolderEmails(folderId) {
            print("📧 Using cached emails for folder (\(cachedEmails.count) emails)")
            return cachedEmails
        }

        // If cache is invalid or force refresh, fetch from Supabase
        print("🔄 Fetching emails from Supabase for folder...")
        let emailFolderService = await EmailFolderService.shared
        let emails = try await emailFolderService.fetchEmailsInFolder(folderId: folderId)

        // Cache the results
        saveCachedFolderEmails(emails, for: folderId)

        return emails
    }

    /// Search saved emails in a folder
    func searchSavedEmails(in folderId: UUID, query: String) async throws -> [SavedEmail] {
        let emailFolderService = await EmailFolderService.shared
        return try await emailFolderService.searchEmailsInFolder(folderId: folderId, query: query)
    }

    /// Move saved email to a different folder
    func moveSavedEmail(id: UUID, toFolder folderId: UUID) async throws -> SavedEmail {
        let emailFolderService = await EmailFolderService.shared
        return try await emailFolderService.moveEmail(id: id, toFolder: folderId)
    }

    /// Delete a saved email
    func deleteSavedEmail(id: UUID) async throws {
        let emailFolderService = await EmailFolderService.shared
        try await emailFolderService.deleteSavedEmail(id: id)
    }

    /// Get email count in a folder (uses cached data if available)
    func getSavedEmailCount(in folderId: UUID) async throws -> Int {
        // Try to use cached emails first
        if isFolderEmailsCacheValid(folderId), let cachedEmails = loadCachedFolderEmails(folderId) {
            return cachedEmails.count
        }

        // If cache invalid, fetch emails (which also caches them)
        let emails = try await fetchSavedEmails(in: folderId)
        return emails.count
    }


    // MARK: - Error Handling
    private func getUserFriendlyErrorMessage(_ error: Error) -> String {
        if let gmailError = error as? GmailAPIError {
            switch gmailError {
            case .notAuthenticated:
                return "Please sign in again to access your emails"
            case .apiError(let statusCode, _):
                if statusCode == 401 {
                    return "Session expired. Pull down to refresh"
                } else if statusCode == 403 {
                    return "Gmail access denied. Please check permissions"
                } else if statusCode >= 500 {
                    return "Gmail servers are temporarily unavailable"
                } else {
                    return "Failed to load emails. Pull down to retry"
                }
            default:
                return "Failed to load emails. Pull down to retry"
            }
        }
        return "Failed to load emails. Pull down to retry"
    }

    // MARK: - Helper Methods
    private static func stripHTMLTags(from html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Remove all HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text
    }
}

enum EmailServiceError: LocalizedError {
    case notAuthenticated
    case invalidAccessToken
    case apiError
    case parsingError
    case missingGmailId

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated with Google"
        case .invalidAccessToken:
            return "Invalid or expired access token"
        case .apiError:
            return "Gmail API request failed"
        case .parsingError:
            return "Failed to parse email data"
        case .missingGmailId:
            return "Email missing Gmail message ID"
        }
    }
}

// MARK: - Searchable Conformance for Saved Emails

extension EmailService: Searchable {
    /// Provide saved emails from all folders as searchable content for the LLM
    /// Note: This uses cached data to avoid blocking the main thread
    func getSearchableContent() -> [SearchableItem] {
        var searchableEmails: [SearchableItem] = []

        // Load saved emails asynchronously in the background
        Task {
            await self.loadSavedEmailsForSearch()
        }

        // Return cached searchable emails immediately (non-blocking)
        // This will be populated by the background task
        return self.cachedSearchableEmails
    }

    /// Load saved emails for search in the background (non-blocking)
    private func loadSavedEmailsForSearch() async {
        var searchableEmails: [SearchableItem] = []
        let emailFolderService = await EmailFolderService.shared

        do {
            // Fetch all folders
            let folders = try await emailFolderService.fetchFolders()

            // Fetch emails from each folder
            for folder in folders {
                do {
                    let emails = try await emailFolderService.fetchEmailsInFolder(folderId: folder.id)

                    // Convert each email to a SearchableItem
                    for email in emails {
                        let emailContent = """
                        From: \(email.senderName ?? email.senderEmail)
                        To: \(email.recipients.joined(separator: ", "))
                        Subject: \(email.subject)

                        \(email.body ?? email.snippet ?? "")

                        Summary: \(email.aiSummary ?? "No summary available")
                        """

                        let tags = [
                            "email",
                            "saved",
                            folder.name,
                            email.senderName ?? email.senderEmail
                        ].filter { !$0.isEmpty }

                        let metadata: [String: String] = [
                            "folder": folder.name,
                            "sender": email.senderEmail,
                            "senderName": email.senderName ?? "",
                            "recipients": email.recipients.joined(separator: ";"),
                            "subject": email.subject,
                            "hasAISummary": email.aiSummary != nil ? "yes" : "no"
                        ]

                        let searchItem = SearchableItem(
                            title: email.subject,
                            content: emailContent,
                            type: .email,
                            identifier: email.id.uuidString,
                            metadata: metadata,
                            tags: tags,
                            relatedItems: [],
                            date: email.timestamp
                        )

                        searchableEmails.append(searchItem)
                    }
                } catch {
                    print("⚠️ Error fetching emails from folder \(folder.name): \(error)")
                }
            }

            // Update cache on main thread
            await MainActor.run {
                self.cachedSearchableEmails = searchableEmails
            }
        } catch {
            print("⚠️ Error fetching folders for search: \(error)")
        }
    }
}