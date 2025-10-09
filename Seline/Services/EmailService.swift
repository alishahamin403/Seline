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


    // Cache management
    private var cacheTimestamps: [EmailFolder: Date] = [:]
    private let cacheExpirationTime: TimeInterval = 604800 // 7 days for longer persistence
    private let newEmailCheckInterval: TimeInterval = 300 // 5 minutes for near real-time notifications (Gmail API - no Supabase egress!)

    // Persistent cache keys
    private enum CacheKeys {
        static let inboxEmails = "cached_inbox_emails"
        static let sentEmails = "cached_sent_emails"
        static let inboxTimestamp = "cached_inbox_timestamp"
        static let sentTimestamp = "cached_sent_timestamp"
        static let lastEmailIds = "last_email_ids" // For tracking new emails
    }

    // Request management
    private var currentTasks: [EmailFolder: Task<Void, Never>] = [:]

    // New email checking
    private var newEmailTimer: Timer?
    private var isAppActive = false // Track if app is in foreground

    private let authManager = AuthenticationManager.shared
    private let gmailAPIClient = GmailAPIClient.shared
    let notificationService = NotificationService.shared // Made public for access from EmailView
    private let openAIService = OpenAIService.shared

    private init() {
        loadCachedData()
        // Don't start polling on init - only when app becomes active
        setupAppLifecycleObservers()
    }

    deinit {
        // Cancel all ongoing tasks
        for task in currentTasks.values {
            task.cancel()
        }
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

                switch folder {
                case .inbox:
                    // Fetch recent 10 emails (Gmail API - doesn't count toward Supabase egress)
                    emails = try await gmailAPIClient.fetchInboxEmails(maxResults: 10)
                case .sent:
                    // Fetch recent 10 emails (Gmail API - doesn't count toward Supabase egress)
                    emails = try await gmailAPIClient.fetchSentEmails(maxResults: 10)
                default:
                    // For other folders, we can extend this later
                    emails = []
                }

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    return
                }

                // Filter to include only today's emails
                let filteredEmails = filterTodaysEmails(emails)

                // Update the appropriate email list
                updateEmailsForFolder(folder, emails: filteredEmails)
                setLoadingState(for: folder, state: .loaded(filteredEmails))

                // Update cache timestamp and save to persistent storage
                updateCacheTimestamp(for: folder)
                saveCachedData(for: folder)

                // Pre-generate AI summaries for emails without them (in background)
                Task.detached(priority: .background) {
                    await self.preloadAISummaries(for: filteredEmails)
                }

            } catch {
                // Only update state if not cancelled
                if !Task.isCancelled {
                    let errorMessage = self.getUserFriendlyErrorMessage(error)
                    setLoadingState(for: folder, state: .error(errorMessage))
                    print("Error loading emails for \(folder.displayName): \(error)")
                }
            }

            // Clean up task reference
            currentTasks[folder] = nil
        }

        currentTasks[folder] = task
        await task.value
    }

    func searchEmails(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            // Use Gmail API search (doesn't count toward Supabase egress)
            let emails = try await gmailAPIClient.searchEmails(query: query, maxResults: 15)
            let todaysEmails = filterTodaysEmails(emails)
            searchResults = todaysEmails
        } catch {
            // Fallback to local search
            let allEmails = inboxEmails + sentEmails
            let filteredEmails = allEmails.filter { email in
                email.subject.localizedCaseInsensitiveContains(query) ||
                email.sender.displayName.localizedCaseInsensitiveContains(query) ||
                email.snippet.localizedCaseInsensitiveContains(query)
            }
            searchResults = filteredEmails
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

        let categorized = TimePeriod.categorizeEmails(emails, for: Date())

        return TimePeriod.allCases.compactMap { period in
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

        let categorized = TimePeriod.categorizeEmails(emails, for: Date())

        return TimePeriod.allCases.compactMap { period in
            let periodEmails = categorized[period] ?? []
            guard !periodEmails.isEmpty else { return nil }
            return EmailSection(timePeriod: period, emails: periodEmails)
        }
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

    // MARK: - Email Actions

    func replyToEmail(_ email: Email) {
        guard let subject = email.subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let senderEmail = email.sender.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email data for reply")
            return
        }

        // Construct reply subject with "Re: " prefix if not already present
        let replySubject = email.subject.hasPrefix("Re: ") ? subject : "Re:%20\(subject)"

        // Try Gmail compose URL schemes for reply
        let replyURLs = [
            "googlegmail://co?to=\(senderEmail)&subject=\(replySubject)",
            "googlegmail:///co?to=\(senderEmail)&subject=\(replySubject)",
            "mailto:\(senderEmail)?subject=\(replySubject)" // Fallback to system mail
        ]

        openEmailURL(replyURLs, action: "reply")
    }

    func forwardEmail(_ email: Email) {
        guard let subject = email.subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email subject for forward")
            return
        }

        // Construct forward subject with "Fwd: " prefix if not already present
        let forwardSubject = email.subject.hasPrefix("Fwd: ") ? subject : "Fwd:%20\(subject)"

        // Create a formatted forwarded message with context
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        let forwardedContent = """
        ---------- Forwarded message ---------
        From: \(email.sender.displayName) <\(email.sender.email)>
        Date: \(dateFormatter.string(from: email.timestamp))
        Subject: \(email.subject)

        \(email.body ?? email.snippet)
        """

        guard let emailBody = forwardedContent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email body for forward")
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
                    UIApplication.shared.open(url) { success in
                        if success {
                            print("✅ Successfully opened Gmail for \(action) with: \(urlString)")
                        } else {
                            print("❌ Failed to open Gmail for \(action)")
                        }
                    }
                    return
                }
            }
        }

        // If all Gmail schemes failed, show a message
        print("Gmail app is not installed or none of the URL schemes worked for \(action)")
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
            print("🗑️ Deleted email: \(email.subject)")
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
                    gmailThreadId: currentEmail.gmailThreadId
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
                    gmailThreadId: currentEmail.gmailThreadId
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

            print("📧 Marked email as read: \(email.subject)")
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
                    gmailThreadId: currentEmail.gmailThreadId
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
                    gmailThreadId: currentEmail.gmailThreadId
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
            print("📧 Marked email as unread: \(email.subject)")
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
                gmailThreadId: currentEmail.gmailThreadId
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
                gmailThreadId: currentEmail.gmailThreadId
            )
            sentEmails[sentIndex] = updatedEmail
            wasUpdated = true
        }

        // Only save if something actually changed
        if wasUpdated {
            // Save updated data to persistent cache
            saveCachedData(for: .inbox)
            saveCachedData(for: .sent)
            print("🤖 Updated AI summary for email: \(email.subject)")
        }
    }

    // MARK: - AI Summary Pre-loading

    private func preloadAISummaries(for emails: [Email]) async {
        // Filter emails that don't have AI summaries yet
        let emailsNeedingSummary = emails.filter { $0.aiSummary == nil }

        guard !emailsNeedingSummary.isEmpty else {
            print("📧 All emails already have AI summaries")
            return
        }

        print("🤖 Pre-loading AI summaries for \(emailsNeedingSummary.count) emails...")

        // Generate summaries one at a time to respect rate limits
        for email in emailsNeedingSummary {
            do {
                let emailBody = email.body ?? email.snippet
                let summary = try await openAIService.summarizeEmail(
                    subject: email.subject,
                    body: emailBody
                )

                // Update the email with the summary
                await updateEmailWithAISummary(email, summary: summary)

            } catch {
                // Log error but continue with other emails
                print("⚠️ Failed to generate summary for '\(email.subject)': \(error.localizedDescription)")
            }
        }

        print("✅ Finished pre-loading AI summaries")
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
        print("📧 EmailService: App became active")
        isAppActive = true

        // Fetch emails when app opens
        Task { @MainActor in
            await loadTodaysEmails()
        }

        // Start 6-hour background polling
        startNewEmailPolling()
    }

    @objc private func appDidEnterBackground() {
        print("📧 EmailService: App entered background - stopping email polling")
        isAppActive = false
        stopNewEmailPolling()
    }

    // MARK: - New Email Polling (Only when app is active)

    private func startNewEmailPolling() {
        // Only start if app is active
        guard isAppActive else {
            print("⚠️ EmailService: Not starting polling - app is not active")
            return
        }

        newEmailTimer?.invalidate()
        newEmailTimer = Timer.scheduledTimer(withTimeInterval: newEmailCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                // Only check if app is still active
                guard self.isAppActive else {
                    print("⚠️ EmailService: Skipping email check - app is not active")
                    return
                }
                await self.checkForNewEmails()
            }
        }
        print("✅ EmailService: Email polling started (interval: \(newEmailCheckInterval)s)")
    }

    private func stopNewEmailPolling() {
        newEmailTimer?.invalidate()
        newEmailTimer = nil
        print("🛑 EmailService: Email polling stopped")
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

    private func checkForNewEmails() async {
        // CRITICAL FIX: Only check for new email COUNT, don't fetch content
        // User must manually refresh to actually load new emails

        // Only check for new emails if we have cached data
        guard !inboxEmails.isEmpty else { return }

        do {
            // Just check message list count, don't fetch full emails
            let messageList = try await gmailAPIClient.fetchMessagesList(query: "in:inbox", maxResults: 3)
            let messageIds = messageList.messages?.map { $0.id } ?? []

            // Check if we have any new message IDs that aren't in our current list
            let newMessageIds = messageIds.filter { newId in
                !inboxEmails.contains { existingEmail in
                    existingEmail.id == newId
                }
            }

            if !newMessageIds.isEmpty {
                // Show notification for new emails WITHOUT fetching content
                // Create minimal notification without full email data
                print("📧 Detected \(newMessageIds.count) new emails - user must refresh to load")

                // Show generic notification (no email ID since we don't fetch full content)
                await notificationService.scheduleNewEmailNotification(
                    emailCount: newMessageIds.count,
                    latestSender: nil,
                    latestSubject: "New email(s) received",
                    latestEmailId: nil
                )
            }
        } catch {
            print("Error checking for new emails: \(error)")
        }
    }

    // MARK: - Cache Management

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
            print("Failed to save cached emails for \(folder.displayName): \(error)")
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

    func handleBackgroundRefresh() async {
        // Perform a quick check for new emails when app refreshes in background
        guard !inboxEmails.isEmpty else { return }

        await checkForNewEmails()
    }

    // MARK: - Private Methods

    private func filterTodaysEmails(_ emails: [Email]) -> [Email] {
        let calendar = Calendar.current
        let today = Date()

        return emails.filter { email in
            calendar.isDate(email.timestamp, inSameDayAs: today)
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