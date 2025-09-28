import Foundation
import GoogleSignIn

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
    private let cacheExpirationTime: TimeInterval = 86400 // 24 hours (full day)
    private let newEmailCheckInterval: TimeInterval = 180 // 3 minutes for new email checks

    // Request management
    private var currentTasks: [EmailFolder: Task<Void, Never>] = [:]

    // New email checking
    private var newEmailTimer: Timer?

    private let authManager = AuthenticationManager.shared
    private let gmailAPIClient = GmailAPIClient.shared
    private let filterManager = EmailFilterManager.shared

    private init() {
        startNewEmailPolling()
    }

    deinit {
        // Cancel all ongoing tasks
        for task in currentTasks.values {
            task.cancel()
        }
        newEmailTimer?.invalidate()
    }

    func loadTodaysEmails() async {
        // Load sequentially to avoid rate limits
        await loadEmailsForFolder(.inbox)

        // Add delay to respect rate limits
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await loadEmailsForFolder(.sent)
    }

    func loadEmailsForFolder(_ folder: EmailFolder, forceRefresh: Bool = false) async {
        // Cancel any existing task for this folder
        currentTasks[folder]?.cancel()

        // Check if we have valid cached data and don't need to refresh
        if !forceRefresh && isCacheValid(for: folder) && !getEmails(for: folder).isEmpty {
            // Data is cached and valid, no need to reload
            return
        }

        let task = Task { @MainActor in
            setLoadingState(for: folder, state: .loading)

            do {
                let emails: [Email]

                switch folder {
                case .inbox:
                    let inboxEmails = try await gmailAPIClient.fetchInboxEmails(maxResults: 100)
                    // Apply user-configured filters for inbox
                    emails = applyUserFilters(inboxEmails)
                case .sent:
                    let sentEmails = try await gmailAPIClient.fetchSentEmails(maxResults: 100)
                    // Apply user-configured filters for sent emails too
                    emails = applyUserFilters(sentEmails)
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

                // Update cache timestamp
                updateCacheTimestamp(for: folder)

            } catch {
                // Only update state if not cancelled
                if !Task.isCancelled {
                    setLoadingState(for: folder, state: .error(error.localizedDescription))
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
            // Use Gmail API search
            let emails = try await gmailAPIClient.searchEmails(query: query, maxResults: 50)
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
        await loadEmailsForFolder(.inbox, forceRefresh: true)
        // Add delay to respect rate limits
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await loadEmailsForFolder(.sent, forceRefresh: true)
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


    private func applyUserFilters(_ emails: [Email]) -> [Email] {
        return emails.filter { email in
            filterManager.shouldShowEmail(email)
        }
    }

    func refreshEmailsWithCurrentFilters() async {
        // Force refresh all folders with current filter settings
        await loadEmailsForFolder(.inbox, forceRefresh: true)

        // Add delay to respect rate limits
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await loadEmailsForFolder(.sent, forceRefresh: true)
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

    func getCategorizedEmails(for folder: EmailFolder) -> [EmailSection] {
        let emails = getEmails(for: folder)
        let categorized = TimePeriod.categorizeEmails(emails, for: Date())

        return TimePeriod.allCases.compactMap { period in
            let periodEmails = categorized[period] ?? []
            guard !periodEmails.isEmpty else { return nil }
            return EmailSection(timePeriod: period, emails: periodEmails)
        }
    }


    // MARK: - New Email Polling

    private func startNewEmailPolling() {
        newEmailTimer?.invalidate()
        newEmailTimer = Timer.scheduledTimer(withTimeInterval: newEmailCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.checkForNewEmails()
            }
        }
    }

    private func checkForNewEmails() async {
        // Only check for new emails if we have cached data
        guard !inboxEmails.isEmpty else { return }

        // Quick check for new emails in inbox only
        do {
            let latestEmails = try await gmailAPIClient.fetchInboxEmails(maxResults: 10)
            let filteredLatest = applyUserFilters(latestEmails)
            let todaysLatest = filterTodaysEmails(filteredLatest)

            // Check if we have any new emails that aren't in our current list
            let newEmails = todaysLatest.filter { newEmail in
                !inboxEmails.contains { existingEmail in
                    existingEmail.id == newEmail.id
                }
            }

            if !newEmails.isEmpty {
                // Prepend new emails to the existing list
                inboxEmails = (newEmails + inboxEmails).sorted { $0.timestamp > $1.timestamp }
                print("📧 Found \(newEmails.count) new emails")
            }
        } catch {
            print("Error checking for new emails: \(error)")
        }
    }

    // MARK: - Cache Management

    private func isCacheValid(for folder: EmailFolder) -> Bool {
        guard let timestamp = cacheTimestamps[folder] else {
            return false
        }

        // Check if it's a new day - if so, invalidate cache
        let calendar = Calendar.current
        let now = Date()

        if !calendar.isDate(timestamp, inSameDayAs: now) {
            return false
        }

        return Date().timeIntervalSince(timestamp) < cacheExpirationTime
    }

    private func updateCacheTimestamp(for folder: EmailFolder) {
        cacheTimestamps[folder] = Date()
    }

    func clearCache(for folder: EmailFolder? = nil) {
        if let folder = folder {
            cacheTimestamps.removeValue(forKey: folder)
        } else {
            cacheTimestamps.removeAll()
        }
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
}

enum EmailServiceError: LocalizedError {
    case notAuthenticated
    case invalidAccessToken
    case apiError
    case parsingError

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
        }
    }
}