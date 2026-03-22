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

    // Cache management
    private var cacheTimestamps: [EmailFolder: Date] = [:]
    private let cacheExpirationTime: TimeInterval = 604800 // 7 days for longer persistence
    private let newEmailCheckInterval: TimeInterval = 30 // 30s checks for more responsive inbox updates
    private let newEmailBaselineCount: Int = 50

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
    private let emailFolderService = EmailFolderService.shared
    private let persistenceCoordinator = DeferredPersistenceCoordinator.shared

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
        // Load inbox immediately, then warm sent mail in background so LLM/history has both sides.
        await loadEmailsForFolder(.inbox)
        let shouldPrimeSent = sentEmails.isEmpty || !isCacheValid(for: .sent)
        if shouldPrimeSent {
            Task { @MainActor in
                await self.loadEmailsForFolder(.sent)
            }
        }
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

                // Keep full fetched page; only sort by recency.
                let sortedEmails = sortEmailsByRecency(emails)

                // CRITICAL FIX: Preserve AI summaries from existing cached emails
                let existingEmails = getEmails(for: folder)
                let mergedEmails = mergeWithExistingAISummaries(newEmails: sortedEmails, existingEmails: existingEmails)
                let hydratedEmails = await hydrateWithMirroredAISummaries(mergedEmails)

                // Update the appropriate email list
                updateEmailsForFolder(folder, emails: hydratedEmails)
                setLoadingState(for: folder, state: .loaded(hydratedEmails))

                // Update cache timestamp and save to persistent storage
                updateCacheTimestamp(for: folder)
                saveCachedData(for: folder)

                // Generate AI summaries in background when emails are loaded
                // This ensures summaries are ready when user opens emails
                Task.detached(priority: .background) {
                    await self.preloadAISummaries(for: hydratedEmails)
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

                // Keep full fetched page; only sort by recency.
                let sortedEmails = sortEmailsByRecency(emails)
                let hydratedNewEmails = await hydrateWithMirroredAISummaries(sortedEmails)

                // Merge with existing emails (append new ones)
                let existingEmails = getEmails(for: folder)
                let mergedEmails = mergeWithExistingAISummaries(
                    newEmails: existingEmails + hydratedNewEmails,
                    existingEmails: existingEmails
                )

                // Update the appropriate email list
                updateEmailsForFolder(folder, emails: mergedEmails)

                // Update pagination state
                pageTokens[folder] = nextPageToken
                hasMoreEmails[folder] = (nextPageToken != nil)

                // Generate AI summaries in background
                Task.detached(priority: .background) {
                    await self.preloadAISummaries(for: hydratedNewEmails)
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
            seedKnownInboxMessageIdsIfNeeded(from: emails)
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
        emails = filterRecentEmails(emails, daysBack: 7)
        
        // Filter to unread only if requested
        if unreadOnly {
            emails = emails.filter { !$0.isRead }
        }
        
        return EmailDaySection.categorizeByDay(emails)
    }
    
    func getDayCategorizedEmails(for folder: EmailFolder, category: EmailCategory, unreadOnly: Bool = false) -> [EmailDaySection] {
        var emails = getFilteredEmails(for: folder, category: category)
        
        // Filter to last 7 days
        emails = filterRecentEmails(emails, daysBack: 7)
        
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

    /// Fire-and-forget delete for UI actions (context-menu delete, detail delete).
    /// The row is removed from local state immediately, then remote trash call is retried in background.
    func deleteEmailImmediately(_ email: Email) {
        _ = removeEmailFromLocalStorage(email)
        let remoteMessageId = remoteMirrorMessageId(for: email)

        Task {
            try? await emailFolderService.deleteAllSavedEmailRecords(gmailMessageId: remoteMessageId)
            if let gmailMessageId = email.gmailMessageId {
                await trashEmailInBackground(messageId: gmailMessageId)
            }
        }
    }

    /// Async compatibility method used by existing callers.
    /// This intentionally does not roll back UI state on network failures.
    func deleteEmail(_ email: Email) async throws {
        deleteEmailImmediately(email)
    }

    private func trashEmailInBackground(messageId: String, attempt: Int = 1) async {
        do {
            try await gmailAPIClient.trashEmail(messageId: messageId)
            return
        } catch {
            let maxAttempts = 2
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await trashEmailInBackground(messageId: messageId, attempt: attempt + 1)
                return
            }
            print("❌ Failed to trash email \(messageId) after retries: \(error.localizedDescription)")
        }
    }

    private func doesEmail(_ candidate: Email, match target: Email) -> Bool {
        if candidate.id == target.id { return true }

        if let targetMessageId = target.gmailMessageId {
            if candidate.gmailMessageId == targetMessageId || candidate.id == targetMessageId {
                return true
            }
        }

        if let candidateMessageId = candidate.gmailMessageId, candidateMessageId == target.id {
            return true
        }

        return false
    }

    @discardableResult
    private func removeEmailFromLocalStorage(_ email: Email) -> Bool {
        let inboxBefore = inboxEmails.count
        let sentBefore = sentEmails.count
        let searchBefore = searchResults.count

        inboxEmails.removeAll { doesEmail($0, match: email) }
        sentEmails.removeAll { doesEmail($0, match: email) }
        searchResults.removeAll { doesEmail($0, match: email) }

        let removedInbox = inboxEmails.count != inboxBefore
        let removedSent = sentEmails.count != sentBefore
        let removedSearch = searchResults.count != searchBefore

        if removedInbox || removedSent {
            persistEmailStorageChanges()
        }

        return removedInbox || removedSent || removedSearch
    }

    private func persistEmailStorageChanges() {
        saveCachedData(for: .inbox)
        saveCachedData(for: .sent)

        let unreadCount = inboxEmails.filter { !$0.isRead }.count
        notificationService.updateAppBadge(count: unreadCount)
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
        let normalizedSummary = normalizeSummary(summary)
        var wasUpdated = false
        var updatedEmailForMirror: Email? = emailByUpdatingSummary(email, summary: normalizedSummary)

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
                    aiSummary: normalizedSummary, // Update AI summary
                    gmailMessageId: currentEmail.gmailMessageId,
                    gmailThreadId: currentEmail.gmailThreadId,
                    unsubscribeInfo: currentEmail.unsubscribeInfo
            )
            inboxEmails[inboxIndex] = updatedEmail
            wasUpdated = true
            updatedEmailForMirror = updatedEmail
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
                aiSummary: normalizedSummary, // Update AI summary
                gmailMessageId: currentEmail.gmailMessageId,
                gmailThreadId: currentEmail.gmailThreadId,
                unsubscribeInfo: currentEmail.unsubscribeInfo
            )
            sentEmails[sentIndex] = updatedEmail
            wasUpdated = true
            if updatedEmailForMirror == nil {
                updatedEmailForMirror = updatedEmail
            }
        }

        // Only save if something actually changed
        if wasUpdated {
            // Save updated data to persistent cache
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)
        }

        if let updatedEmailForMirror {
            try? await emailFolderService.upsertMirroredEmail(updatedEmailForMirror)
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
                let context = await EmailSummaryBuilderService.shared.buildContext(for: email)

                let summary = try await openAIService.summarizeEmail(
                    subject: email.subject,
                    body: context.bodyForSummary,
                    analyzedSources: context.analyzedSources,
                    confidenceHint: context.confidenceHint
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
        
        // Create a timer that fires periodically to check for new emails
        newEmailTimer = Timer.scheduledTimer(withTimeInterval: newEmailCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForNewEmails()
            }
        }
        
        // Add to run loop to ensure it fires even during scrolling
        if let timer = newEmailTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Run one immediate check so users don't wait for the first timer tick.
        Task { @MainActor [weak self] in
            await self?.checkForNewEmails()
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

    func activateForegroundRefresh() async {
        guard UIApplication.shared.applicationState == .active else { return }
        isAppActive = true
        await loadTodaysEmails()
        startNewEmailPolling()
    }

    func suspendForegroundRefresh() {
        isAppActive = false
        stopNewEmailPolling()
    }

    /// Ensures email polling and near-real-time inbox updates are active while app is foregrounded.
    func ensureAutomaticRefreshActive() {
        guard UIApplication.shared.applicationState == .active else { return }
        Task { @MainActor [weak self] in
            await self?.activateForegroundRefresh()
        }
    }
    
    /// Last time we checked for new emails (for rate limiting)
    private var lastEmailCheckTime: Date?
    
    /// Public method to check for new emails - can be called when navigating to email tab
    /// Rate limited to prevent excessive API calls (minimum 5 seconds between checks)
    func checkForNewEmailsIfNeeded() async {
        // Rate limit: don't check more than once every 5 seconds
        if let lastCheck = lastEmailCheckTime, Date().timeIntervalSince(lastCheck) < 5 {
            return
        }
        lastEmailCheckTime = Date()
        await checkForNewEmails()
    }

    private func checkForNewEmails() async {
        // Check for new emails and show detailed notifications
        // Only fetches metadata (5 quota units per email) for lightweight checks

        // Only check for new emails if user is authenticated
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }

        do {
            // Fetch latest inbox IDs (lightweight list request).
            let messageList = try await gmailAPIClient.fetchMessagesList(query: "in:inbox", maxResults: 25)
            let messageIds = messageList.messages?.map { $0.id } ?? []
            guard !messageIds.isEmpty else { return }

            let persistedKnownIds = loadKnownInboxMessageIds()
            let inMemoryIds = Set(inboxEmails.map(\.id))
            let baselineIds: Set<String>

            if !persistedKnownIds.isEmpty {
                baselineIds = persistedKnownIds
            } else if !inMemoryIds.isEmpty {
                baselineIds = inMemoryIds
            } else {
                // First run with no baseline: establish it and skip notifying old mail.
                saveKnownInboxMessageIds(messageIds)
                print("📧 Established email baseline with \(messageIds.count) IDs")
                return
            }

            // Check if we have any new message IDs that aren't in our current list
            let newMessageIds = messageIds.filter { newId in
                !baselineIds.contains(newId)
            }

            // Persist refreshed baseline to keep background checks consistent across launches.
            var refreshedKnownIds = messageIds
            for knownId in baselineIds where !refreshedKnownIds.contains(knownId) {
                refreshedKnownIds.append(knownId)
            }
            saveKnownInboxMessageIds(refreshedKnownIds)

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

                    // Update badge count using full inbox unread total.
                    let unreadCount = inboxEmails.filter { !$0.isRead }.count
                    notificationService.updateAppBadge(count: unreadCount)
                }
            }
        } catch {
            print("❌ Error checking for new emails: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Validates and cleans cached data on app startup
    /// Keeps cached timestamps aligned with cache expiry rules.
    private func validateAndCleanCache() {
        // Clear cache timestamps only when they are truly expired.
        if let inboxTimestamp = UserDefaults.standard.object(forKey: CacheKeys.inboxTimestamp) as? Date {
            if Date().timeIntervalSince(inboxTimestamp) >= cacheExpirationTime {
                UserDefaults.standard.removeObject(forKey: CacheKeys.inboxTimestamp)
            }
        }

        if let sentTimestamp = UserDefaults.standard.object(forKey: CacheKeys.sentTimestamp) as? Date {
            if Date().timeIntervalSince(sentTimestamp) >= cacheExpirationTime {
                UserDefaults.standard.removeObject(forKey: CacheKeys.sentTimestamp)
            }
        }
    }

    private func loadCachedData() {
        // Load cached emails from persistent storage
        if let inboxData = UserDefaults.standard.data(forKey: CacheKeys.inboxEmails),
           let cachedInboxEmails = try? JSONDecoder().decode([Email].self, from: inboxData) {
            let (normalizedInbox, didMutateInbox) = normalizeCachedAISummaries(in: cachedInboxEmails)
            inboxEmails = normalizedInbox
            if didMutateInbox {
                persistEmailsToCache(normalizedInbox, key: CacheKeys.inboxEmails)
            }
        }

        if let sentData = UserDefaults.standard.data(forKey: CacheKeys.sentEmails),
           let cachedSentEmails = try? JSONDecoder().decode([Email].self, from: sentData) {
            let (normalizedSent, didMutateSent) = normalizeCachedAISummaries(in: cachedSentEmails)
            sentEmails = normalizedSent
            if didMutateSent {
                persistEmailsToCache(normalizedSent, key: CacheKeys.sentEmails)
            }
        }

        // Load cache timestamps
        if let inboxTimestamp = UserDefaults.standard.object(forKey: CacheKeys.inboxTimestamp) as? Date {
            cacheTimestamps[.inbox] = inboxTimestamp
        }

        if let sentTimestamp = UserDefaults.standard.object(forKey: CacheKeys.sentTimestamp) as? Date {
            cacheTimestamps[.sent] = sentTimestamp
        }

        // Initialize baseline IDs from cache on first launch to avoid false positives.
        seedKnownInboxMessageIdsIfNeeded(from: inboxEmails)
    }

    private func persistEmailsToCache(_ emails: [Email], key: String) {
        let snapshot = emails
        persistenceCoordinator.schedule(id: "EmailService.persistedEmails.\(key)") {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    private func normalizeCachedAISummaries(in emails: [Email]) -> ([Email], Bool) {
        var didMutate = false
        let normalizedEmails = emails.map { email in
            guard let summary = email.aiSummary else {
                return email
            }
            let normalizedSummary = normalizeSummary(summary)
            if normalizedSummary == summary {
                return email
            }
            didMutate = true
            return emailByUpdatingSummary(email, summary: normalizedSummary)
        }
        return (normalizedEmails, didMutate)
    }

    private func normalizeSummary(_ summary: String) -> String {
        let normalized = openAIService.sanitizeEmailSummary(summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "No content available." : normalized
    }

    private func emailByUpdatingSummary(_ email: Email, summary: String?) -> Email {
        Email(
            id: email.id,
            threadId: email.threadId,
            sender: email.sender,
            recipients: email.recipients,
            ccRecipients: email.ccRecipients,
            subject: email.subject,
            snippet: email.snippet,
            body: email.body,
            timestamp: email.timestamp,
            isRead: email.isRead,
            isImportant: email.isImportant,
            hasAttachments: email.hasAttachments,
            attachments: email.attachments,
            labels: email.labels,
            aiSummary: summary,
            gmailMessageId: email.gmailMessageId,
            gmailThreadId: email.gmailThreadId,
            unsubscribeInfo: email.unsubscribeInfo
        )
    }

    private func saveCachedData(for folder: EmailFolder) {
        let emails = getEmails(for: folder)
        let encoder = JSONEncoder()

        persistenceCoordinator.schedule(id: "EmailService.cachedData.\(folder.rawValue)") {
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

    private func loadKnownInboxMessageIds() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: CacheKeys.lastEmailIds) ?? []
        return Set(ids)
    }

    private func saveKnownInboxMessageIds(_ ids: [String]) {
        let normalized = Array(ids.prefix(newEmailBaselineCount))
        UserDefaults.standard.set(normalized, forKey: CacheKeys.lastEmailIds)
    }

    private func seedKnownInboxMessageIdsIfNeeded(from emails: [Email]) {
        guard !emails.isEmpty else { return }
        let existing = UserDefaults.standard.stringArray(forKey: CacheKeys.lastEmailIds) ?? []
        guard existing.isEmpty else { return }
        saveKnownInboxMessageIds(emails.map(\.id))
    }

    // MARK: - Private Methods

    /// Merges new emails with existing emails, preserving AI summaries that were already generated
    private func mergeWithExistingAISummaries(newEmails: [Email], existingEmails: [Email]) -> [Email] {
        // Create a dictionary of existing emails by their ID for quick lookup
        let existingById = Dictionary(uniqueKeysWithValues: existingEmails.map { ($0.id, $0) })

        // Map through new emails and restore durable local fields if they exist
        return newEmails.map { newEmail in
            guard let existingEmail = existingById[newEmail.id] else {
                return newEmail
            }

            var mergedSender = newEmail.sender
            if (mergedSender.avatarUrl == nil || mergedSender.avatarUrl?.isEmpty == true),
               let cachedAvatar = existingEmail.sender.avatarUrl,
               !cachedAvatar.isEmpty {
                mergedSender = EmailAddress(
                    name: newEmail.sender.name,
                    email: newEmail.sender.email,
                    avatarUrl: cachedAvatar
                )
            }

            let normalizedExistingSummary = existingEmail.aiSummary.flatMap { summary in
                summary.isEmpty ? nil : normalizeSummary(summary)
            }
            let normalizedNewSummary = newEmail.aiSummary.flatMap { summary in
                summary.isEmpty ? nil : normalizeSummary(summary)
            }

            let mergedSummary: String?
            if let existingSummary = normalizedExistingSummary,
               normalizedNewSummary == nil {
                mergedSummary = existingSummary
            } else {
                mergedSummary = normalizedNewSummary
            }

            if mergedSender == newEmail.sender && mergedSummary == newEmail.aiSummary {
                return newEmail
            }

            return Email(
                id: newEmail.id,
                threadId: newEmail.threadId,
                sender: mergedSender,
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
                aiSummary: mergedSummary,
                gmailMessageId: newEmail.gmailMessageId,
                gmailThreadId: newEmail.gmailThreadId,
                unsubscribeInfo: newEmail.unsubscribeInfo
            )
        }
    }

    private func hydrateWithMirroredAISummaries(_ emails: [Email]) async -> [Email] {
        let idsNeedingSummary = Array(
            Set(
                emails.compactMap { email in
                    let currentSummary = email.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return currentSummary.isEmpty ? remoteMirrorMessageId(for: email) : nil
                }
            )
        )

        guard !idsNeedingSummary.isEmpty else { return emails }
        guard let mirroredSummaries = try? await emailFolderService.fetchMirroredAISummaries(messageIds: idsNeedingSummary),
              !mirroredSummaries.isEmpty else {
            return emails
        }

        return emails.map { email in
            let currentSummary = email.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard currentSummary.isEmpty,
                  let mirroredSummary = mirroredSummaries[remoteMirrorMessageId(for: email)] else {
                return email
            }
            return emailByUpdatingSummary(email, summary: normalizeSummary(mirroredSummary))
        }
    }

    private func remoteMirrorMessageId(for email: Email) -> String {
        email.gmailMessageId ?? email.id
    }

    private func sortEmailsByRecency(_ emails: [Email]) -> [Email] {
        emails.sorted { $0.timestamp > $1.timestamp }
    }

    private func filterRecentEmails(_ emails: [Email], daysBack: Int) -> [Email] {
        guard daysBack > 0 else {
            return sortEmailsByRecency(emails)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Keep only a recent window when explicitly needed by UI sections.
        guard let cutoffDate = calendar.date(byAdding: .day, value: -(daysBack - 1), to: today) else {
            return sortEmailsByRecency(emails)
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

    /// Force clear the folder cache (useful for debugging/recovery)
    func clearFolderCache() {
        UserDefaults.standard.removeObject(forKey: CacheKeys.customFolders)
        UserDefaults.standard.removeObject(forKey: CacheKeys.customFoldersTimestamp)

        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("cached_folder_emails_") || key.hasPrefix("cached_folder_emails_timestamp_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
