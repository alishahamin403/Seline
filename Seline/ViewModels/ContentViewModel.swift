//
//  ContentViewModel.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import Foundation
import Combine

// MARK: - Date Filter Enum

enum DateFilter {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case specificDate(Date)
    
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .lastWeek:
            guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else { return false }
            return calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
            return calendar.isDate(date, equalTo: lastMonth, toGranularity: .month)
        case .specificDate(let targetDate):
            return calendar.isDate(date, inSameDayAs: targetDate)
        }
    }
}
import SwiftUI
import UIKit
import CoreData

// MARK: - Search Filter Types

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case important = "Important"
    case hasAttachment = "With Attachments"
    case today = "Today"
    case thisWeek = "This Week"
    
    var systemImage: String {
        switch self {
        case .all: return "tray"
        case .unread: return "envelope.badge"
        case .important: return "exclamationmark.circle"
        case .hasAttachment: return "paperclip"
        case .today: return "calendar"
        case .thisWeek: return "calendar.badge.clock"
        }
    }
}

enum SearchSortOption: String, CaseIterable {
    case date = "Date"
    case sender = "Sender"
    case subject = "Subject"
    case relevance = "Relevance"
    
    var systemImage: String {
        switch self {
        case .date: return "clock"
        case .sender: return "person"
        case .subject: return "text.alignleft"
        case .relevance: return "star"
        }
    }
}

@MainActor
class ContentViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var emails: [Email] = []
    @Published var importantEmails: [Email] = []
    @Published var calendarEmails: [Email] = []
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var searchResults: [Email] = []
    @Published var searchHistory: [String] = []
    @Published var searchSuggestions: [String] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var selectedSearchFilter: SearchFilter = .all
    @Published var selectedSortOption: SearchSortOption = .date
    @Published var sortAscending = false
    @Published var hasMoreEmails = true
    @Published var isLoadingMore = false
    @Published var currentSearchResult: IntelligentSearchResult?
    @Published var isPerformingIntelligentSearch = false
    
    private let localEmailService = LocalEmailService.shared
    private let gmailService: GmailServiceProtocol
    private let intelligentSearchService = IntelligentSearchService.shared
    private let calendarService = CalendarService.shared
    private var cancellables = Set<AnyCancellable>()
    private let searchHistoryKey = "SearchHistory"
    private let maxSearchHistoryItems = 10
    
    init(gmailService: GmailServiceProtocol = GmailService.shared) {
        self.gmailService = gmailService
        setupLocalEmailServiceObservers()
        setupSearchSubscription()
        loadInitialData()
        loadSearchHistory()
    }
    
    private func setupLocalEmailServiceObservers() {
        // Observe local email service state changes
        localEmailService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        localEmailService.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
    }
    
    private func setupSearchSubscription() {
        // Search text changes
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task {
                    await self?.performSearchInternal(query: searchText)
                    self?.updateSearchSuggestions(query: searchText)
                }
            }
            .store(in: &cancellables)
        
        // Filter and sort changes
        Publishers.CombineLatest3($selectedSearchFilter, $selectedSortOption, $sortAscending)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                Task {
                    await self?.applyFiltersAndSort()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadInitialData() {
        Task {
            await loadEmails(forceSync: false)
            await loadCategoryEmails()
        }
    }
    
    // Accept a 'forceSync' flag to match call sites; behavior remains the same for now.
    func loadEmails(forceSync: Bool = false) async {
        guard !isLoading else { return }
        
        await ProductionLogger.measureTimeAsync(operation: "Load emails") {
            isLoading = true
            errorMessage = nil
            
            do {
                let fetchedEmails = try await gmailService.fetchTodaysUnreadEmails()
                
                // Filter out promotional and noreply emails
                let filteredEmails = fetchedEmails.filter { email in
                    return !email.isPromotional && !email.sender.email.lowercased().contains("noreply")
                }
                
                // Update the @Published property with bounds checking (already on main actor)
                emails = filteredEmails
                
                // Preload email content in the background
                preloadEmailsInBackground(for: filteredEmails.map { $0.id })
                
                // Validate array integrity
                let finalCount = max(0, emails.count)
                ProductionLogger.logEmailLoad("main emails", count: finalCount)
                
            } catch {
                // Update error message (already on main actor)
                errorMessage = getErrorMessage(for: error)
                ProductionLogger.logEmailError(error, operation: "loadEmails")
            }
            
            // Update loading state (already on main actor)
            isLoading = false
        }
    }
    
    private func getErrorMessage(for error: Error) -> String {
        if error.localizedDescription.contains("noAccessToken") {
            return "Please sign in to view your emails"
        } else if error.localizedDescription.contains("network") {
            return "Network error. Please check your connection and try again."
        } else if error.localizedDescription.contains("401") || error.localizedDescription.contains("403") {
            return "Authentication expired. Please sign in again."
        } else {
            return "Unable to load emails. Using offline data."
        }
    }
    
    func loadCategoryEmails() async {
        await ProductionLogger.measureTimeAsync(operation: "Load category emails (local-first)") {
            // Load from local storage (instant UI)
            async let important = localEmailService.loadEmailsBy(category: .important)
            async let calendar = localEmailService.loadEmailsBy(category: .calendar)
            
            let _ = await important
            let calendarResult = await calendar
            
            // Recompute Important using all emails from TODAY and our smart filter instead of Gmail label
            let allEmails = await localEmailService.getAllEmails()
            let todaysEmails = allEmails.filter { Calendar.current.isDateInToday($0.date) }
            let recentImportantEmails = filterPersonalImportantEmails(todaysEmails)

            
            // Load calendar events (both Google Calendar and local events)
            let upcomingCalendarEvents: [CalendarEvent]
            do {
                // Get Google Calendar events
                let googleEvents = try await calendarService.getUpcomingEvents(days: 14)

                // Get local events
                let localEvents = LocalEventService.shared.getUpcomingEvents(days: 14)

                // Combine and deduplicate (local events take precedence for same time slots)
                var allEvents = googleEvents
                let googleEventIds = Set(googleEvents.map { $0.id })

                for localEvent in localEvents {
                    if !googleEventIds.contains(localEvent.id) {
                        allEvents.append(localEvent)
                    }
                }

                // Sort by start date and filter for today
                upcomingCalendarEvents = allEvents.filter { Calendar.current.isDateInToday($0.startDate) }.sorted { $0.startDate < $1.startDate }

                ProductionLogger.logEmailOperation("Calendar events loaded (Google: \(googleEvents.count), Local: \(localEvents.count))", count: upcomingCalendarEvents.count)
            } catch {
                // Fallback to local events only
                upcomingCalendarEvents = LocalEventService.shared.getUpcomingEvents(days: 14)
                ProductionLogger.logEmailError(error, operation: "Google Calendar events loading, using local events only")
                print("Error fetching calendar events: \(error)")
            }
            
            await MainActor.run {
                // Update category emails with bounds checking
                importantEmails = recentImportantEmails
                calendarEmails = calendarResult
                // Deduplicate calendar events before setting
                upcomingEvents = removeDuplicateCalendarEvents(from: upcomingCalendarEvents)
                
                // Validate all array integrity
                let safeImportantCount = max(0, importantEmails.count)
                let safeCalendarCount = max(0, calendarEmails.count)
                
                ProductionLogger.logEmailLoad("category emails (local)", count: safeImportantCount + safeCalendarCount)
                
                // Update error message if available from sync
                if let syncError = localEmailService.errorMessage {
                    errorMessage = "Sync warning: \(syncError)"
                }
            }
        }
    }
    
    func performSearch(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                currentSearchResult = nil
            }
            return
        }
        
        // Check if this is a date-specific search first
        if let dateFilter = parseDateQuery(query.lowercased()) {
            await performDateSpecificSearch(dateFilter: dateFilter, originalQuery: query)
            return
        }
        
        // Use intelligent search service for everything else
        isPerformingIntelligentSearch = true
        isSearching = true
        
        let searchResult = await intelligentSearchService.performSearch(query: query)
        
        await MainActor.run {
            currentSearchResult = searchResult
            
            // Update searchResults based on the type of search
            if searchResult.type == .emailSearch {
                searchResults = searchResult.emails
            } else {
                // For general searches, we still want to display the AI response card
                searchResults = []
            }
            
            let emailCount = searchResult.emails.count
            ProductionLogger.logEmailOperation("Intelligent search completed: \(searchResult.type.displayName)", count: emailCount)
            
            isPerformingIntelligentSearch = false
            isSearching = false
        }
    }
    
    // MARK: - Date-Specific Search Functions
    
    private func parseDateQuery(_ query: String) -> DateFilter? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch trimmedQuery {
        case "today":
            return .today
        case "yesterday":
            return .yesterday
        case "this week":
            return .thisWeek
        case "last week":
            return .lastWeek
        case "this month":
            return .thisMonth
        case "last month":
            return .lastMonth
        default:
            // Check for variations of "today" queries
            if trimmedQuery.contains("today") {
                if trimmedQuery.contains("email") || trimmedQuery.contains("emails") ||
                   trimmedQuery.contains("mail") || trimmedQuery.contains("message") {
                    return .today
                }
            }

            // Check for "today's" variations
            if trimmedQuery.hasPrefix("today's") || trimmedQuery.contains("today's") {
                return .today
            }

            // Check for "emails today" or similar patterns
            if (trimmedQuery.contains("email") || trimmedQuery.contains("emails") ||
                trimmedQuery.contains("mail") || trimmedQuery.contains("message")) &&
               trimmedQuery.contains("today") {
                return .today
            }

            // Check for specific date patterns like "January 15" or "2024-01-15"
            if let specificDate = parseSpecificDate(trimmedQuery) {
                return .specificDate(specificDate)
            }
            return nil
        }
    }
    
    private func parseSpecificDate(_ query: String) -> Date? {
        let dateFormatter = DateFormatter()
        
        // Try various date formats
        let formats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MMMM dd",
            "MMM dd",
            "dd MMMM",
            "dd MMM"
        ]
        
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: query) {
                return date
            }
        }
        
        return nil
    }
    
    private func performDateSpecificSearch(dateFilter: DateFilter, originalQuery: String) async {
        // Get all emails from local database
        let allEmails = await localEmailService.getAllEmails()

        // Filter by date first
        var filteredEmails = allEmails.filter { email in
            dateFilter.contains(email.date)
        }
        
        // Apply importance filter if query contains "important"
        let lowercaseQuery = originalQuery.lowercased()
        if lowercaseQuery.contains("important") {
            filteredEmails = filteredEmails.filter { $0.isImportant }
        }

        await MainActor.run {
            searchResults = filteredEmails
            let safeCount = max(0, searchResults.count)
            ProductionLogger.logEmailOperation("Date-specific search completed for '\(originalQuery)'", count: safeCount)
        }
    }
    
    private func performSearchInternal(query: String) async {
        await performSearch(query: query)
    }
    
    func markEmailAsRead(_ emailId: String) {
        Task {
            do {
                try await gmailService.markAsRead(emailId: emailId)
                // Update local state by reloading data
                // Note: Email struct would need to be mutable for direct updates
                await loadEmails()
            } catch {
                errorMessage = "Failed to mark email as read: \(error.localizedDescription)"
            }
        }
    }
    
    func markEmailAsImportant(_ emailId: String) {
        Task {
            do {
                try await gmailService.markAsImportant(emailId: emailId)
                await loadEmails()
                await loadCategoryEmails()
            } catch {
                errorMessage = "Failed to mark email as important: \(error.localizedDescription)"
            }
        }
    }
    
    func refresh() async {
        await ProductionLogger.measureTimeAsync(operation: "Refresh all data") {
            await loadEmails(forceSync: true)
            await loadCategoryEmails()
            ProductionLogger.logRefresh("All email data")
        }
    }
    
    func loadMoreEmails() async {
        guard hasMoreEmails && !isLoadingMore else { return }
        
        await ProductionLogger.measureTimeAsync(operation: "Load more emails") {
            isLoadingMore = true
            
            do {
                // Get the last email for pagination context
                guard let lastEmail = emails.last else {
                    hasMoreEmails = false
                    isLoadingMore = false
                    return
                }
                
                let moreEmails = try await gmailService.fetchMoreEmails(after: lastEmail)
                
                if moreEmails.isEmpty {
                    hasMoreEmails = false
                } else {
                    // Append new emails with safe bounds checking
                    let safeNewEmails = moreEmails
                    emails.append(contentsOf: safeNewEmails)
                    
                    ProductionLogger.logEmailLoad("more emails", count: safeNewEmails.count)
                }
                
            } catch {
                errorMessage = getErrorMessage(for: error)
                ProductionLogger.logEmailError(error, operation: "loadMoreEmails")
            }
            
            isLoadingMore = false
        }
    }
    
    func preloadEmailContent(for emailId: String) async -> Email? {
        do {
            let fullEmail = try await gmailService.fetchFullEmailContent(emailId: emailId)
            ProductionLogger.logEmailOperation("Preloaded full email content", count: 1)
            return fullEmail
        } catch {
            ProductionLogger.logEmailError(error, operation: "preloadEmailContent")
            return nil
        }
    }
    
    /// Preload content for multiple emails in background with priority
    func preloadEmailsInBackground(for emailIds: [String], priority: TaskPriority = .background) {
        Task(priority: priority) {
            await ProductionLogger.measureTimeAsync(operation: "Preload \(emailIds.count) emails") {
                let limitedIds = Array(emailIds.prefix(5)) // Limit to avoid overwhelming API
                
                for emailId in limitedIds {
                    // Check if already cached with full content
                    if let cached = EmailCacheManager.shared.getCachedEmail(id: emailId),
                       !cached.body.isEmpty {
                        continue // Skip already cached
                    }
                    
                    // Preload in background with small delay to avoid quota issues
                    _ = await preloadEmailContent(for: emailId)
                    
                    // Small delay between requests
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        }
    }
    
    // MARK: - Enhanced Search Functionality
    
    private func updateSearchSuggestions(query: String) {
        guard !query.isEmpty else {
            searchSuggestions = []
            return
        }
        
        // Generate suggestions from all email content with safe array access
        let safeEmails = max(0, emails.count) > 0 ? emails : []
        let safeImportantEmails = max(0, importantEmails.count) > 0 ? importantEmails : []
        let safeCalendarEmails = max(0, calendarEmails.count) > 0 ? calendarEmails : []
        let allEmails = safeEmails + safeImportantEmails + safeCalendarEmails
        
        var suggestions = Set<String>()
        
        // Add sender suggestions with bounds checking
        for (index, email) in allEmails.enumerated() {
            guard index < allEmails.count else { break }
            let sender = email.sender.displayName
            if sender.localizedCaseInsensitiveContains(query) {
                suggestions.insert("from:\(sender)")
            }
        }
        
        // Add subject suggestions with bounds checking
        for (index, email) in allEmails.enumerated() {
            guard index < allEmails.count else { break }
            let words = email.subject.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            for word in words {
                if word.localizedCaseInsensitiveContains(query) && word.count > 2 {
                    suggestions.insert("subject:\(word)")
                }
            }
        }
        
        // Add common search terms
        let commonTerms = ["meeting", "urgent", "follow up", "deadline", "invoice", "receipt"]
        for term in commonTerms {
            if term.localizedCaseInsensitiveContains(query) {
                suggestions.insert(term)
            }
        }
        
        // Safe array slicing
        let suggestionArray = Array(suggestions)
        let maxSuggestions = min(6, suggestionArray.count)
        searchSuggestions = Array(suggestionArray.prefix(maxSuggestions))
    }
    
    private func applyFiltersAndSort() async {
        guard !searchResults.isEmpty else { return }
        
        var filteredResults = searchResults
        
        // Apply filters
        switch selectedSearchFilter {
        case .all:
            break
        case .unread:
            filteredResults = filteredResults.filter { !$0.isRead }
        case .important:
            filteredResults = filteredResults.filter { $0.isImportant }
        case .hasAttachment:
            filteredResults = filteredResults.filter { !$0.attachments.isEmpty }
        case .today:
            let today = Calendar.current.startOfDay(for: Date())
            filteredResults = filteredResults.filter {
                Calendar.current.isDate($0.date, inSameDayAs: today)
            }
        case .thisWeek:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filteredResults = filteredResults.filter { $0.date >= weekAgo }
        }
        
        // Apply sorting
        switch selectedSortOption {
        case .date:
            filteredResults.sort {
                sortAscending ? $0.date < $1.date : $0.date > $1.date
            }
        case .sender:
            filteredResults.sort {
                let result = $0.sender.displayName.localizedCompare($1.sender.displayName)
                return sortAscending ? result == .orderedAscending : result == .orderedDescending
            }
        case .subject:
            filteredResults.sort {
                let result = $0.subject.localizedCompare($1.subject)
                return sortAscending ? result == .orderedAscending : result == .orderedDescending
            }
        case .relevance:
            // Sort by relevance (importance + unread status + recent date)
            filteredResults.sort { email1, email2 in
                let score1 = calculateRelevanceScore(for: email1)
                let score2 = calculateRelevanceScore(for: email2)
                return sortAscending ? score1 < score2 : score1 > score2
            }
        }
        
        searchResults = filteredResults
    }
    
    private func calculateRelevanceScore(for email: Email) -> Int {
        var score = 0
        
        if email.isImportant { score += 10 }
        if !email.isRead { score += 5 }
        if !email.attachments.isEmpty { score += 3 }
        
        // More recent emails get higher scores
        let daysSinceReceived = Calendar.current.dateComponents([.day], from: email.date, to: Date()).day ?? 0
        score -= daysSinceReceived
        
        return score
    }
    
    // MARK: - Search History Management
    
    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: searchHistoryKey) ?? []
    }
    
    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: searchHistoryKey)
    }
    
    func addToSearchHistory(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove if already exists
        searchHistory.removeAll { $0.lowercased() == trimmedQuery.lowercased() }
        
        // Add to beginning
        searchHistory.insert(trimmedQuery, at: 0)
        
        // Keep only the latest items
        if searchHistory.count > maxSearchHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxSearchHistoryItems))
        }
        
        saveSearchHistory()
    }
    
    func removeFromSearchHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        saveSearchHistory()
    }
    
    func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }
    
    // MARK: - Smart Search Functions
    
    func performSearchWithHistory(query: String) async {
        await performSearch(query: query)
        addToSearchHistory(query)
    }
    
    /// Get current intelligent search result
    func getCurrentSearchResult() -> IntelligentSearchResult? {
        return currentSearchResult
    }
    
    /// Check if we're currently performing an intelligent search
    func isCurrentlySearching() -> Bool {
        return isPerformingIntelligentSearch
    }
    
    func getHighlightedText(text: String, searchQuery: String) -> AttributedString {
        guard !searchQuery.isEmpty else {
            return AttributedString(text)
        }
        
        var attributedString = AttributedString(text)
        
        // Find and highlight search terms
        let searchTerms = searchQuery.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        for term in searchTerms {
            if let range = attributedString.range(of: term, options: [.caseInsensitive]) {
                attributedString[range].backgroundColor = Color.yellow.opacity(0.3)
                attributedString[range].font = .body.weight(.semibold)
            }
        }
        
        return attributedString
    }
    
    // MARK: - Email Actions with Haptic Feedback
    
    func archiveEmail(_ emailId: String) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        Task {
            do {
                try await gmailService.archiveEmail(emailId: emailId)
                await refresh()
            } catch {
                errorMessage = "Failed to archive email: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteEmail(_ emailId: String) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        Task {
            do {
                try await gmailService.deleteEmail(emailId: emailId)
                await refresh()
            } catch {
                errorMessage = "Failed to delete email: \(error.localizedDescription)"
            }
        }
    }
    
    func toggleReadStatus(_ emailId: String, isRead: Bool) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        Task {
            let success = await localEmailService.markAsRead(emailID: emailId)
            if success {
                await refresh()
            } else {
                await MainActor.run {
                    errorMessage = "Failed to update read status"
                }
            }
        }
    }
    
    func toggleImportantStatus(_ emailId: String, isImportant: Bool) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        Task {
            let success = await localEmailService.markAsImportant(emailID: emailId, isImportant: isImportant)
            if success {
                await refresh()
            } else {
                await MainActor.run {
                    errorMessage = "Failed to update important status"
                }
            }
        }
    }
    
    // MARK: - Offline Support
    
    func getOfflineStatus() -> OfflineStatus {
        return localEmailService.getOfflineStatus()
    }
    
    func getStorageStatistics() -> StorageStatistics {
        return localEmailService.getStorageStatistics()
    }
    
    // MARK: - Personal Important Email Filtering
    
    private func filterPersonalImportantEmails(_ emails: [Email]) -> [Email] {
        // Keep track of unique senders to show only one email per person
        var uniqueSenders: Set<String> = []
        var importantEmails: [Email] = []

        // Sort by date (most recent first) to prioritize latest emails from each sender
        let sortedEmails = emails.sorted { $0.date > $1.date }

        for email in sortedEmails {
            // Skip if we already have an email from this sender
            let senderKey = email.sender.email.lowercased()
            if uniqueSenders.contains(senderKey) {
                continue
            }

            // Include emails that are either personal OR contain important updates
            if isPersonalEmail(email) || isImportantUpdateEmail(email) {
                importantEmails.append(email)
                uniqueSenders.insert(senderKey)
            }
        }

        // Return up to 15 most recent important emails from unique senders
        return Array(importantEmails.prefix(15))
    }

    /// Check if email contains important updates, notifications, or system alerts
    private func isImportantUpdateEmail(_ email: Email) -> Bool {
        let subject = email.subject.lowercased()
        let body = email.body.lowercased()
        let senderEmail = email.sender.email.lowercased()

        // Important update keywords
        let updateKeywords = [
            "update", "updated", "notification", "alert", "security", "account",
            "password", "login", "verification", "confirm", "verify", "reset",
            "change", "modified", "status", "report", "summary", "activity",
            "maintenance", "scheduled", "reminder", "deadline", "due", "urgent",
            "important", "critical", "action required", "review", "approval",
            "feedback", "response", "reply", "follow-up", "meeting update"
        ]

        // Trusted update sender domains
        let trustedUpdateDomains = [
            "updates", "notifications", "alerts", "security", "support",
            "admin", "system", "noreply", "no-reply", "service", "help"
        ]

        // Check for update keywords in subject or body
        for keyword in updateKeywords {
            if subject.contains(keyword) || body.contains(keyword) {
                // Additional check: must be from a somewhat trusted source or have multiple indicators
                let hasTrustedDomain = trustedUpdateDomains.contains { domain in
                    senderEmail.contains(domain + "@") || senderEmail.contains("." + domain + "@")
                }

                // If it's clearly an update/notification email, include it
                if hasTrustedDomain || subject.contains("update") || subject.contains("notification") {
                    return true
                }
            }
        }

        // Include emails from common service providers that send important updates
        let importantServiceDomains = [
            "github.com", "gitlab.com", "bitbucket.org", "slack.com", "discord.com",
            "notion.so", "figma.com", "canva.com", "dropbox.com", "google.com",
            "microsoft.com", "apple.com", "amazon.com", "paypal.com", "stripe.com"
        ]

        for domain in importantServiceDomains {
            if senderEmail.contains("@" + domain) {
                return true
            }
        }

        return false
    }
    
    private func isPersonalEmail(_ email: Email) -> Bool {
        let subject = email.subject.lowercased()
        let body = email.body.lowercased()
        let senderName = email.sender.name?.lowercased() ?? ""
        let senderEmail = email.sender.email.lowercased()
        
        // Check for promotional/spam indicators
        let promotionalKeywords = [
            "unsubscribe", "promotion", "deal", "discount", "sale", "offer", "marketing",
            "newsletter", "campaign", "advertisement", "promo", "coupon", "limited time",
            "black friday", "cyber monday", "free shipping", "% off", "save now",
            "click here", "act now", "don't miss", "exclusive", "special offer"
        ]
        
        let spamKeywords = [
            "viagra", "casino", "lottery", "winner", "congratulations", "claim your",
            "urgent action required", "verify account", "suspended", "click now",
            "make money", "work from home", "get rich", "investment opportunity"
        ]
        
        let systemKeywords = [
            "noreply", "no-reply", "donotreply", "do-not-reply", "automated", "system",
            "notification", "alert", "security alert", "verify", "confirm"
        ]
        
        // Check if email contains promotional indicators
        for keyword in promotionalKeywords + spamKeywords {
            if subject.contains(keyword) || body.contains(keyword) {
                return false
            }
        }
        
        // Check if sender is a system/automated account
        for keyword in systemKeywords {
            if senderEmail.contains(keyword) || senderName.contains(keyword) {
                return false
            }
        }
        
        // Check for bulk email patterns
        if senderEmail.contains("info@") || 
           senderEmail.contains("marketing@") ||
           senderEmail.contains("sales@") ||
           senderEmail.contains("support@") ||
           senderEmail.contains("news@") ||
           senderEmail.contains("updates@") {
            return false
        }
        
        // Check for personal indicators
        let personalIndicators = [
            "meeting", "call", "chat", "discuss", "project", "question", "help", 
            "deadline", "review", "feedback", "opinion", "thoughts", "ideas", 
            "collaboration", "team", "schedule", "appointment", "follow up"
        ]
        
        var personalScore = 0
        for indicator in personalIndicators {
            if subject.contains(indicator) || body.contains(indicator) {
                personalScore += 1
            }
        }
        
        // Additional checks for personal emails:
        // 1. Has personal name (not just company/automated)
        let hasPersonalName = senderName.count > 2 && !senderName.contains("team") && 
                             !senderName.contains("support") && !senderName.contains("info")
        
        // 2. Short, direct subject lines (often personal)
        let hasShortSubject = email.subject.count < 50 && !subject.contains("newsletter")
        
        // 3. Not from a typical automated domain pattern
        let isFromPersonalDomain = !senderEmail.contains("@mailchimp") && 
                                  !senderEmail.contains("@constant-contact") &&
                                  !senderEmail.contains("@em.") &&
                                  !senderEmail.contains("@email.")
        
        // Consider it personal if it has multiple indicators
        let personalityScore = (personalScore > 0 ? 1 : 0) + 
                              (hasPersonalName ? 1 : 0) + 
                              (hasShortSubject ? 1 : 0) + 
                              (isFromPersonalDomain ? 1 : 0)
        
        return personalityScore >= 2
    }
    
    // MARK: - Home Page Display Properties (Maximum 3 items each)
    
    /// Returns maximum 3 emails for home page display
    var displayedTodaysEmails: [Email] {
        return Array(importantEmails.prefix(3))
    }
    
    /// Returns maximum 3 calendar events for home page display (deduplicated)
    var displayedUpcomingEvents: [CalendarEvent] {
        return Array(upcomingEvents.prefix(3))
    }
    
    /// Returns maximum 3 todos for home page display
    var displayedTodos: [TodoItem] {
        return Array(TodoManager.shared.todos.prefix(3))
    }
    
    // MARK: - Calendar Event Deduplication
    
    /// Removes duplicate calendar events based on title, start date, and end date
    private func removeDuplicateCalendarEvents(from events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        return events.filter { event in
            // Create a unique key combining title, start date, and end date
            let startTime = event.startDate.timeIntervalSince1970
            let endTime = event.endDate.timeIntervalSince1970
            let key = "\(event.title.lowercased())-\(startTime)-\(endTime)"
            
            return seen.insert(key).inserted
        }
    }
}
