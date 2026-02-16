import Foundation
import CoreLocation
import MapKit

/// Simple data context for LLM - collects all app data without pre-filtering
/// The LLM will handle filtering, reasoning, and natural language understanding
@MainActor
class SelineAppContext {
    // MARK: - Core Data

    private let taskManager: TaskManager
    private let tagManager: TagManager
    private let notesManager: NotesManager
    private let emailService: EmailService
    private let weatherService: WeatherService
    private let locationsManager: LocationsManager
    private let navigationService: NavigationService
    private let categorizationService: ReceiptCategorizationService
    private let habitTrackingService: HabitTrackingService
    private let visitFeedbackService: VisitFeedbackService
    private let attachmentService: AttachmentService
    // MARK: - Cached Data

    private(set) var events: [TaskItem] = []
    private(set) var receipts: [ReceiptStat] = []
    private(set) var notes: [Note] = []
    private(set) var emails: [Email] = []
    private(set) var customEmailFolders: [CustomEmailFolder] = []
    private(set) var savedEmailsByFolder: [UUID: [SavedEmail]] = [:]
    private(set) var locations: [SavedPlace] = []
    private(set) var currentDate: Date = Date()
    private(set) var weatherData: WeatherData?
    
    // MARK: - ETA Location Data (for map card display in chat)
    private(set) var lastETALocationInfo: ETALocationInfo?
    
    // MARK: - Event Creation Data (for event card display in chat)
    private(set) var lastEventCreationInfo: [EventCreationInfo]?
    
    // MARK: - Relevant Content Data (for inline email/note/event card display in chat)
    private(set) var lastRelevantContent: [RelevantContentInfo]?

    // MARK: - Cache Control

    private var lastRefreshTime: Date = Date.distantPast
    private let cacheValidityDuration: TimeInterval = 1800 // 30 minutes (increased from 5 minutes for better performance)
    private var folderNameCache: [UUID: String] = [:] // Cache for folder name lookups
    
    // Cache for computed values
    private var cachedFilteredEvents: [TaskItem]?
    private var cachedFilteredReceipts: [ReceiptStat]?
    private var lastFilterCacheTime: Date?

    private var isCacheValid: Bool {
        Date().timeIntervalSince(lastRefreshTime) < cacheValidityDuration
    }

    // OPTIMIZATION: Reusable DateFormatters (created once, used everywhere)
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE" // Full day name
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var mediumDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    init(
        taskManager: TaskManager = TaskManager.shared,
        tagManager: TagManager = TagManager.shared,
        notesManager: NotesManager = NotesManager.shared,
        emailService: EmailService = EmailService.shared,
        weatherService: WeatherService = WeatherService.shared,
        locationsManager: LocationsManager = LocationsManager.shared,
        navigationService: NavigationService = NavigationService.shared,
        categorizationService: ReceiptCategorizationService = ReceiptCategorizationService.shared,
        habitTrackingService: HabitTrackingService = HabitTrackingService.shared,
        visitFeedbackService: VisitFeedbackService = VisitFeedbackService.shared,
        attachmentService: AttachmentService = AttachmentService.shared
    ) {
        self.taskManager = taskManager
        self.tagManager = tagManager
        self.notesManager = notesManager
        self.emailService = emailService
        self.weatherService = weatherService
        self.locationsManager = locationsManager
        self.navigationService = navigationService
        self.categorizationService = categorizationService
        self.habitTrackingService = habitTrackingService
        self.visitFeedbackService = visitFeedbackService
        self.attachmentService = attachmentService

        // Note: refresh() is called asynchronously in buildContextPrompt()
        // to fetch custom email folders and saved emails
    }

    // MARK: - Cache Utilities

    /// Get folder name with caching to avoid repeated lookups
    private func getCachedFolderName(for folderId: UUID?) -> String {
        guard let folderId = folderId else { return "Uncategorized" }
        if let cached = folderNameCache[folderId] {
            return cached
        }
        let name = notesManager.getFolderName(for: folderId)
        folderNameCache[folderId] = name
        return name
    }
    
    // MARK: - Date Comparison Helpers (using currentDate, NOT system Date())
    
    /// Check if a date is "today" based on currentDate (NOT system time)
    private func isDateToday(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: currentDate)
    }
    
    /// Check if a date is "tomorrow" based on currentDate
    private func isDateTomorrow(_ date: Date) -> Bool {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }
    
    /// Check if a date is within "this week" from currentDate
    private func isDateThisWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: currentDate)
        guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return false }
        return date >= startOfToday && date < endOfWeek
    }
    
    /// Check if a date is in the past (before currentDate)
    private func isDatePast(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: currentDate)
        return date < startOfToday
    }

    /// Get a compact summary of events by count per time period
    private func getEventSummary() -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today)!

        let todayEvents = events.filter { event in
            guard let date = event.targetDate ?? event.scheduledTime else { return false }
            return date >= today && date < tomorrow
        }.count

        let thisWeekEvents = events.filter { event in
            guard let date = event.targetDate ?? event.scheduledTime else { return false }
            return date >= today && date < weekEnd
        }.count

        return "Today: \(todayEvents) | This Week: \(thisWeekEvents) | Total: \(events.count)"
    }

    // MARK: - Data Collection

    /// Refresh all app data (call this at start of each conversation)
    func refresh() async {
        print("🔄 SelineAppContext.refresh() called")
        self.currentDate = Date()
        
        // Debug: Show exactly what date/time we're using
        let debugFormatter = DateFormatter()
        debugFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        debugFormatter.timeZone = TimeZone.current
        print("📅 Current Date set to: \(debugFormatter.string(from: currentDate))")
        print("🌍 Timezone: \(TimeZone.current.identifier)")
        
        // Clear folder name cache on refresh
        self.folderNameCache.removeAll()

        // Collect recent events (limit to improve performance)
        // Load only tasks from the last 90 days and upcoming tasks
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        self.events = taskManager.getAllTasksIncludingArchived().filter { task in
            let taskDate = task.targetDate ?? task.createdAt
            return taskDate >= ninetyDaysAgo || task.isRecurring // Include recurring tasks
        }
        print("📅 Filtered to \(self.events.count) recent/upcoming events (last 90 days)")

        // Collect custom email folders and their saved emails (optimized with parallel loading)
        do {
            self.customEmailFolders = try await emailService.fetchSavedFolders()
            print("📧 Found \(self.customEmailFolders.count) custom email folders")

            // Load emails for each folder in parallel (non-blocking)
            await withTaskGroup(of: (UUID, [SavedEmail]?).self) { [self] group in
                for folder in self.customEmailFolders {
                    group.addTask {
                        do {
                            let savedEmails = try await self.emailService.fetchSavedEmails(in: folder.id)
                            return (folder.id, savedEmails)
                        } catch {
                            print("  ⚠️  Error loading emails for folder '\(folder.name)': \(error)")
                            return (folder.id, nil)
                        }
                    }
                }
                
                var foldersByEmail: [UUID: [SavedEmail]] = [:]
                for await (folderId, emails) in group {
                    foldersByEmail[folderId] = emails ?? []
                    if let emails = emails, !emails.isEmpty {
                        if let folder = self.customEmailFolders.first(where: { $0.id == folderId }) {
                            print("  • \(folder.name): \(emails.count) emails")
                        }
                    }
                }
                self.savedEmailsByFolder = foldersByEmail
            }
        } catch {
            print("⚠️  Error loading custom email folders: \(error)")
        }

        // Debug: Log recurring events and their next occurrence
        let recurringEvents = self.events.filter { $0.isRecurring }
        if !recurringEvents.isEmpty {
            print("🔁 Recurring events found: \(recurringEvents.count)")
            for event in recurringEvents {
                let frequency = event.recurrenceFrequency?.rawValue ?? "?"
                let anchorDate = event.targetDate ?? event.createdAt
                let nextDate = getNextOccurrenceDate(for: event)

                print("   • \(event.title)")
                print("     Frequency: \(frequency)")
                print("     Anchor date: \(formatDate(anchorDate))")
                print("     Recurrence end: \(event.recurrenceEndDate.map { formatDate($0) } ?? "None")")

                if let nextDate = nextDate {
                    let isTomorrow = isDateTomorrow(nextDate)
                    let isToday = isDateToday(nextDate)
                    print("     Next occurrence: \(formatDate(nextDate))\(isTomorrow ? " (TOMORROW)" : "")\(isToday ? " (TODAY)" : "")")
                } else {
                    print("     Next occurrence: NONE (ended or invalid)")
                }
            }
        }

        // Collect all receipts from notes
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
        print("📂 Receipts folder ID: \(receiptsFolderId)")

        let receiptNotes = notesManager.notes.filter { note in
            isUnderReceiptsFolderHierarchy(folderId: note.folderId, receiptsFolderId: receiptsFolderId)
        }
        print("📝 Found \(receiptNotes.count) receipt notes in folder")

        // Extract transaction dates from receipt notes
        self.receipts = receiptNotes.compactMap { note -> ReceiptStat? in
            // Extract date from note title - that's the transaction date
            guard let transactionDate = extractDateFromTitle(note.title) else {
                // Skip receipts where we can't extract a date from the title
                // This prevents fallback to dateModified which could be from wrong month
                print("⚠️  Skipping receipt with no extractable date: \(note.title)")
                return nil
            }

            return ReceiptStat(from: note, date: transactionDate, category: "Other")
        }
        print("✅ Extracted \(self.receipts.count) receipts with valid dates")

        // Collect recent notes (optimized filtering)
        // Load pinned notes (unlimited) + notes from last 90 days (unlimited)
        // For semantic queries, vector search will handle relevance ranking
        let recentNotes = notesManager.notes.filter { note in
            note.isPinned || note.dateModified >= ninetyDaysAgo
        }
        self.notes = recentNotes.sorted { $0.dateModified > $1.dateModified }
        print("📝 Filtered to \(self.notes.count) recent notes (last 90 days + pinned, no hard limit)")

        // Collect recent emails (limit to improve performance)
        // Emails are already paginated (20 per load), so just use what's loaded
        // This prevents loading thousands of historical emails into LLM context
        self.emails = emailService.inboxEmails + emailService.sentEmails
        print("📧 Loaded \(self.emails.count) emails (paginated, see EmailService for limits)")

        // Collect all locations (kept as-is since location list is typically small)
        self.locations = locationsManager.savedPlaces

        // OPTIMIZATION: Don't fetch visit stats here - only fetch when needed in buildContextPrompt
        // This prevents blocking the refresh operation
        print("📍 Locations loaded: \(self.locations.count) (visit stats will be fetched on-demand)")

        // OPTIMIZATION: Fetch weather in background (non-blocking)
        Task.detached(priority: .utility) { [self] in
            do {
                // Try to get current location, otherwise use default (Toronto)
                let locationService = LocationService.shared
                let location = await locationService.currentLocation ?? CLLocation(latitude: 43.6532, longitude: -79.3832)

                await self.weatherService.fetchWeather(for: location)
                await MainActor.run {
                    self.weatherData = self.weatherService.weatherData
                    print("🌤️ Weather data fetched")
                }
            } catch {
                print("⚠️ Failed to fetch weather: \(error)")
            }
        }

        print("📦 AppContext refreshed:")
        print("   Current date: \(formatDate(currentDate))")
        print("   Events: \(events.count)")
        print("   Receipts: \(receipts.count)")

        if !receipts.isEmpty {
            // Calculate current month range
            let calendar = Calendar.current
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate

            // Show current month receipts only
            let thisMonthReceipts = receipts.filter { $0.date >= startOfMonth && $0.date <= currentDate }
            let thisMonthTotal = thisMonthReceipts.reduce(0.0) { $0 + $1.amount }

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM"
            let currentMonthName = monthFormatter.string(from: currentDate)
            let dayOfMonth = Calendar.current.component(.day, from: currentDate)

            print("     THIS MONTH (\(currentMonthName) 1 - \(currentMonthName) \(dayOfMonth)): \(thisMonthReceipts.count) receipts, Total: $\(String(format: "%.2f", thisMonthTotal))")

            // Show ALL receipts counted as this month for verification
            print("     --- ALL \(currentMonthName.uppercased()) RECEIPTS (by transaction date) ---")
            for receipt in thisMonthReceipts.sorted(by: { $0.date < $1.date }) {
                print("     • \(formatDate(receipt.date)): \(receipt.title) - $\(String(format: "%.2f", receipt.amount))")
            }
            print("     --- END ---")
        }
        print("   Notes: \(notes.count)")
        print("   Emails: \(emails.count)")
        print("   Locations: \(locations.count)")

        // Update cache timestamp
        self.lastRefreshTime = Date()
    }

    // MARK: - Context Building for LLM

    /// Build a rich context string for the LLM with all app data
    // MARK: - Query Intent Extraction

    /// Extracts category/tag names from a user query
    private func extractCategoryFilter(from query: String) -> String? {
        let lowercaseQuery = query.lowercased()

        // Get all tags and check if any match the query
        for tag in tagManager.tags {
            if lowercaseQuery.contains(tag.name.lowercased()) {
                return tag.id
            }
        }

        return nil
    }

    /// Extracts time period from a user query
    private func extractTimePeriodFilter(from query: String) -> (startDate: Date, endDate: Date)? {
        let calendar = Calendar.current
        let lowercaseQuery = query.lowercased()

        if lowercaseQuery.contains("last week") || lowercaseQuery.contains("past week") {
            let endDate = currentDate
            let startDate = calendar.date(byAdding: .day, value: -7, to: currentDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("this week") {
            let startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate)) ?? currentDate
            let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("yesterday") {
            let endDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            let startDate = calendar.startOfDay(for: endDate)
            return (startDate, calendar.date(byAdding: .second, value: -1, to: calendar.startOfDay(for: currentDate)) ?? endDate)
        } else if lowercaseQuery.contains("today") {
            let startDate = calendar.startOfDay(for: currentDate)
            let endDate = currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("this month") {
            let startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate
            let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? currentDate
            return (startDate, endDate)
        } else if lowercaseQuery.contains("last month") {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
            let startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: previousMonth)) ?? previousMonth
            let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? currentDate
            return (startDate, endDate)
        }

        return nil
    }

    /// Detects if query is related to expenses/spending
    private func isExpenseQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let expenseKeywords = ["spend", "spending", "spent", "receipt", "receipts", "cost", "costs", "expense", "expenses", "money", "budget", "amount", "price", "paid", "how much", "total", "breakdown"]

        return expenseKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Detects if query is related to locations/places
    private func isLocationQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let locationKeywords = ["location", "locations", "place", "places", "visit", "visited", "go to", "went to", "restaurant", "restaurants", "cafe", "cafes", "coffee", "coffee shop", "shop", "shopping", "favorite", "favourite", "starred", "bookmarked", "save", "saved", "where", "nearby", "near", "at", "eating", "eat", "ate", "dining", "dine", "recommend", "recommended"]

        return locationKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Extracts category filter from query for locations
    private func extractLocationCategoryFilter(from query: String) -> String? {
        let lowercaseQuery = query.lowercased()

        // Get all available categories
        let categories = locationsManager.categories

        // Check if any category is mentioned in the query
        for category in categories {
            if lowercaseQuery.contains(category.lowercased()) {
                return category
            }
        }

        // Check for common category keywords
        let commonMappings: [String: String] = [
            "restaurant": "Restaurants",
            "cafe": "Coffee Shops",
            "coffee": "Coffee Shops",
            "coffee shop": "Coffee Shops",
            "shop": "Shopping",
            "shopping": "Shopping",
            "entertainment": "Entertainment",
            "fitness": "Health & Fitness",
            "gym": "Health & Fitness",
            "travel": "Travel",
            "service": "Services"
        ]

        for (keyword, categoryName) in commonMappings {
            if lowercaseQuery.contains(keyword) && categories.contains(categoryName) {
                return categoryName
            }
        }

        return nil
    }

    /// Detects if query is related to weather
    private func isWeatherQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let weatherKeywords = ["weather", "temperature", "rain", "rainy", "sunny", "forecast", "cold", "hot", "cloudy", "snow", "wind", "humid", "how's the weather", "what's the weather", "will it rain", "sunrise", "sunset"]

        return weatherKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Detects if query is related to news
    private func isNewsQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let newsKeywords = ["news", "headlines", "happening", "latest", "tell me about", "what about", "breaking", "trending", "trump", "ai", "artificial intelligence"]

        return newsKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Extracts specific news topic from query
    private func extractNewsTopic(from query: String) -> String? {
        let lowercaseQuery = query.lowercased()

        let commonTopics = ["trump", "ai", "artificial intelligence", "tech", "technology", "science", "business", "politics", "health", "sports", "entertainment"]

        for topic in commonTopics {
            if lowercaseQuery.contains(topic) {
                return topic
            }
        }

        return nil
    }

    /// Detects if query is related to notes
    private func isNotesQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let notesKeywords = [
            // Basic note keywords
            "notes", "note", "reminder", "reminders", "todo", "to-do", "tasks", "ideas", "thoughts", "organized", "categories", "folders", "notes organized", "key topics",
            // Financial statements and documents
            "statement", "statements", "american express", "amex", "visa", "mastercard", "credit card", "bank statement", "invoice", "receipt list", "transaction", "transactions",
            // Documents that would be stored in notes
            "document", "documents", "contract", "agreement", "bill", "bills", "record", "records", "log", "logs", "journal", "diary", "plan", "planning",
            // Data queries that suggest looking at notes
            "list of", "list all", "show me all", "all my", "summarize", "summary", "breakdown", "detail", "details", "compare"
        ]

        return notesKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Detects if query is specifically about bank statements (should look in notes instead of receipts)
    /// Examples: "show me my bank statement", "credit card statement", "amex statement"
    private func isBankStatementQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let bankKeywords = [
            "bank statement", "statement", "statements",
            "american express", "amex", "visa", "mastercard", "credit card",
            "account statement", "monthly statement", "transaction list"
        ]

        return bankKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Detects if query is related to emails
    private func isEmailsQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let emailKeywords = ["email", "emails", "sent", "inbox", "mail", "message", "messages", "correspondence", "contact", "from", "important", "unread", "draft", "archive", "folder"]

        return emailKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Detects if query is related to ETA/travel time/drive time
    private func isETAQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let etaKeywords = [
            // Direct ETA keywords
            "how long", "how far", "eta", "travel time", "drive time", "driving time",
            "get there", "get to", "commute", "distance", "minutes away", "hours away",
            // Direction/route keywords
            "from", "to get", "to drive", "route", "trip", "journey",
            // Time-based travel questions
            "take to get", "take to drive", "take me to", "will it take",
            // Traffic-related
            "traffic", "with traffic", "right now"
        ]

        return etaKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }
    
    /// Extract location names from an ETA query
    /// Examples: 
    ///   "how long from airbnb to lakeridge" -> origin: "airbnb", destination: "lakeridge"
    ///   "how far is lakeridge from my airbnb" -> origin: "my airbnb", destination: "lakeridge"
    private func extractETALocations(from query: String) -> (String?, String?) {
        let lowercaseQuery = query.lowercased()
        let stopPhrases = ["?", "right now", "with traffic", "today", "tonight", "by car", "driving", " and ", " also ", " then ", " plus ", ","]
        
        // Helper to clean up location names
        func cleanLocation(_ text: String) -> String? {
            var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for phrase in stopPhrases {
                if let range = cleaned.range(of: phrase) {
                    cleaned = String(cleaned[..<range.lowerBound])
                }
            }
            // Remove common prefixes like "my", "the", "our" for better search
            let prefixes = ["my ", "the ", "our "]
            for prefix in prefixes {
                if cleaned.hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                }
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        
        // Pattern 1: "from X to Y" (standard format)
        if let fromRange = lowercaseQuery.range(of: "from "),
           let toRange = lowercaseQuery.range(of: " to "),
           fromRange.upperBound < toRange.lowerBound {
            let originStart = fromRange.upperBound
            let originEnd = toRange.lowerBound
            let destinationStart = toRange.upperBound
            
            let origin = cleanLocation(String(lowercaseQuery[originStart..<originEnd]))
            let destination = cleanLocation(String(lowercaseQuery[destinationStart...]))
            
            return (origin, destination)
        }
        
        // Pattern 2: "X from Y" or "how far is X from Y" (reverse format - destination first)
        // Examples: "how far is lakeridge from my airbnb", "distance to starbucks from home"
        if let fromRange = lowercaseQuery.range(of: " from ") {
            // Destination is BEFORE "from", origin is AFTER "from"
            let beforeFrom = String(lowercaseQuery[..<fromRange.lowerBound])
            let afterFrom = String(lowercaseQuery[fromRange.upperBound...])
            
            // Extract destination from before "from" - remove question starters
            var destination = beforeFrom
            let questionStarters = ["how far is ", "how long is ", "what's the distance to ", 
                                    "distance to ", "eta to ", "how far ", "how long to get to ",
                                    "how long to ", "whats the eta to "]
            for starter in questionStarters {
                if let range = destination.range(of: starter) {
                    destination = String(destination[range.upperBound...])
                }
            }
            
            let cleanedDestination = cleanLocation(destination)
            let cleanedOrigin = cleanLocation(afterFrom)
            
            if cleanedDestination != nil || cleanedOrigin != nil {
                return (cleanedOrigin, cleanedDestination)
            }
        }
        
        // Pattern 3: "to X" only (from current location implied)
        if let toRange = lowercaseQuery.range(of: " to ") {
            let destinationStart = toRange.upperBound
            let destination = cleanLocation(String(lowercaseQuery[destinationStart...]))
            return (nil, destination)
        }
        
        // Pattern 4: "how far is X" or "eta to X" (destination only, from current location)
        let destinationOnlyPatterns = ["how far is ", "how long to ", "eta to ", "distance to ", 
                                       "how far to ", "drive time to ", "travel time to "]
        for pattern in destinationOnlyPatterns {
            if let range = lowercaseQuery.range(of: pattern) {
                let destination = cleanLocation(String(lowercaseQuery[range.upperBound...]))
                return (nil, destination)
            }
        }
        
        return (nil, nil)
    }
    
    // MARK: - Event Creation Detection
    
    /// Detects if query is requesting to create an event
    func isEventCreationQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let creationKeywords = [
            "create event", "create an event", "add event", "add an event",
            "schedule", "set up", "set a", "remind me", "reminder for",
            "create meeting", "add meeting", "schedule meeting",
            "create appointment", "add appointment", "book",
            "put on my calendar", "add to my calendar", "add to calendar",
            "new event", "make an event"
        ]
        
        return creationKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }
    
    /// Extracts event details from a creation query
    /// Returns array of EventCreationInfo for single or multiple events
    func extractEventDetails(from query: String) -> [EventCreationInfo] {
        var events: [EventCreationInfo] = []
        let lowercaseQuery = query.lowercased()
        
        // Split by "and also", "and", "plus" for multiple events
        let eventSeparators = [" and also ", " also ", " plus "]
        var queryParts = [query]
        
        for separator in eventSeparators {
            var newParts: [String] = []
            for part in queryParts {
                let subParts = part.lowercased().components(separatedBy: separator)
                if subParts.count > 1 {
                    newParts.append(contentsOf: subParts)
                } else {
                    newParts.append(part)
                }
            }
            queryParts = newParts
        }
        
        // Process each potential event
        for part in queryParts {
            if let eventInfo = parseSingleEvent(from: part) {
                events.append(eventInfo)
            }
        }
        
        // If no events parsed, try to extract from the whole query
        if events.isEmpty {
            if let eventInfo = parseSingleEvent(from: query) {
                events.append(eventInfo)
            }
        }
        
        return events
    }
    
    /// Parse a single event from a query part
    private func parseSingleEvent(from query: String) -> EventCreationInfo? {
        let lowercaseQuery = query.lowercased()
        print("🔍 parseSingleEvent called with: '\(query)'")

        // Extract title - look for quoted text or text after creation keywords
        var title = extractEventTitle(from: lowercaseQuery)
        print("🔍 Extracted title: '\(title)'")
        guard !title.isEmpty else {
            print("⚠️ Title extraction returned empty - aborting event creation")
            return nil
        }

        // Extract date and time
        let (date, hasTime) = extractEventDateTime(from: lowercaseQuery)
        print("🔍 Extracted date: \(String(describing: date)), hasTime: \(hasTime)")
        guard let eventDate = date else {
            print("⚠️ Date extraction returned nil - aborting event creation")
            return nil
        }

        // Extract reminder
        let reminderMinutes = extractReminderMinutes(from: lowercaseQuery)

        // Extract category (default to "Personal")
        let category = extractEventCategory(from: lowercaseQuery)
        print("🔍 Extracted category: '\(category)'")

        // Clean up the title
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 100 { title = String(title.prefix(100)) }

        print("✅ Successfully parsed event: '\(title)' on \(eventDate)")
        return EventCreationInfo(
            title: title.capitalized,
            date: eventDate,
            hasTime: hasTime,
            reminderMinutes: reminderMinutes,
            category: category
        )
    }
    
    /// Extract event title from query
    private func extractEventTitle(from query: String) -> String {
        let lowercased = query.lowercased()
        let originalQuery = query // Keep original for better extraction
        
        // Try to find quoted text first (use original query to preserve case)
        if let match = originalQuery.range(of: "\"([^\"]+)\"", options: .regularExpression) {
            var title = String(originalQuery[match])
            title = title.replacingOccurrences(of: "\"", with: "")
            return title
        }
        
        // NEW: Pattern 0a: Extract text BETWEEN date and time patterns
        // Handles: "for February 14 for a dentist appointment at 11:30 AM"
        // Should extract: "dentist appointment"
        let datePatterns = [
            "january|february|march|april|may|june|july|august|september|october|november|december",
            "jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|dec",
            "tomorrow",
            "today",
            "next week",
            "monday|tuesday|wednesday|thursday|friday|saturday|sunday",
            "mon|tue|wed|thu|fri|sat|sun"
        ]

        let timePatterns = [
            "at\\s+\\d{1,2}\\s*(am|pm|:\\d+\\s*(am|pm)?)",
            "\\d{1,2}\\s*(am|pm|:\\d+\\s*(am|pm)?)"
        ]

        // Try to find text between date and time
        var datePat: NSRange? = nil
        var timePat: NSRange? = nil

        // Find last date pattern
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: lowercased.utf16.count)
                let matches = regex.matches(in: lowercased, range: range)
                if let lastMatch = matches.last {
                    if datePat == nil || lastMatch.range.upperBound > datePat!.upperBound {
                        datePat = lastMatch.range
                    }
                }
            }
        }

        // Find first time pattern AFTER the date
        for pattern in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: lowercased.utf16.count)
                let matches = regex.matches(in: lowercased, range: range)
                for match in matches {
                    if let dateRange = datePat, match.range.lowerBound > dateRange.upperBound {
                        if timePat == nil || match.range.lowerBound < timePat!.lowerBound {
                            timePat = match.range
                        }
                    }
                }
            }
        }

        // If we found both date and time, extract text between them
        if let dateRange = datePat, let timeRange = timePat, dateRange.upperBound < timeRange.lowerBound {
            if let dateIndex = lowercased.utf16.index(lowercased.utf16.startIndex, offsetBy: dateRange.upperBound, limitedBy: lowercased.utf16.endIndex),
               let timeIndex = lowercased.utf16.index(lowercased.utf16.startIndex, offsetBy: timeRange.lowerBound, limitedBy: lowercased.utf16.endIndex),
               let dateStringIndex = dateIndex.samePosition(in: lowercased),
               let timeStringIndex = timeIndex.samePosition(in: lowercased),
               dateStringIndex < timeStringIndex {

                var betweenText = String(lowercased[dateStringIndex..<timeStringIndex])

                // Remove prefixes
                let prefixesToRemove = ["for\\s+", "to\\s+", "a\\s+", "an\\s+"]
                for prefix in prefixesToRemove {
                    betweenText = betweenText.replacingOccurrences(of: "^" + prefix, with: "", options: .regularExpression)
                }

                betweenText = betweenText.trimmingCharacters(in: .whitespacesAndNewlines)

                if betweenText.count >= 3 && betweenText.count <= 100 {
                    return betweenText.capitalized
                }
            }
        }

        // Pattern 0b: Extract text after time/date indicators - fallback
        // Find the last occurrence of time/date pattern
        var lastTimeNSRange: NSRange? = nil
        let allPatterns = datePatterns + timePatterns
        for pattern in allPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: lowercased.utf16.count)
                let matches = regex.matches(in: lowercased, range: range)
                if let lastMatch = matches.last {
                    if lastTimeNSRange == nil || lastMatch.range.upperBound > lastTimeNSRange!.upperBound {
                        lastTimeNSRange = lastMatch.range
                    }
                }
            }
        }
        
        // If we found a time/date, extract everything after it
        if let timeNSRange = lastTimeNSRange {
            // Convert NSRange to String.Index safely
            if let timeIndex = lowercased.utf16.index(lowercased.utf16.startIndex, offsetBy: timeNSRange.upperBound, limitedBy: lowercased.utf16.endIndex),
               let timeStringIndex = timeIndex.samePosition(in: lowercased),
               timeStringIndex < lowercased.endIndex {
                
                var titleCandidate = String(lowercased[timeStringIndex...])
            
            // Remove duration phrases like "for an hour", "for 30 minutes", "for 1 hour"
            let durationPatterns = [
                "for\\s+(an|\\d+)\\s+(hour|hours|minute|minutes|min|mins)\\s*$",
                "for\\s+(an|\\d+)\\s*h\\s*$",
                "lasting\\s+(an|\\d+)\\s+(hour|hours|minute|minutes)\\s*$"
            ]
            for pattern in durationPatterns {
                titleCandidate = titleCandidate.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }

            // Remove common prefixes that aren't part of the title
            let prefixesToRemove = [
                "for\\s+me\\s+",
                "for\\s+",
                "create\\s+",
                "schedule\\s+",
                "add\\s+",
                "make\\s+",
                "put\\s+",
                "to\\s+"
            ]
            for prefix in prefixesToRemove {
                if let prefixRange = titleCandidate.range(of: prefix, options: .regularExpression) {
                    titleCandidate = String(titleCandidate[prefixRange.upperBound...])
                }
            }

            // Remove category mentions at the end
            let categoryPatterns = ["\\s+(work|health|social|family|personal)\\s*$"]
            for pattern in categoryPatterns {
                titleCandidate = titleCandidate.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }

            titleCandidate = titleCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If we got a meaningful title (at least 5 chars), use it
            if titleCandidate.count >= 5 && titleCandidate.count <= 100 {
                // Preserve original capitalization from original query
                // Convert the same NSRange position to originalQuery's index
                if let originalTimeIndex = originalQuery.utf16.index(originalQuery.utf16.startIndex, offsetBy: timeNSRange.upperBound, limitedBy: originalQuery.utf16.endIndex),
                   let originalTimeStringIndex = originalTimeIndex.samePosition(in: originalQuery),
                   originalTimeStringIndex < originalQuery.endIndex {
                    let originalAfterTime = String(originalQuery[originalTimeStringIndex...])
                    // Try to find the same text in original to preserve case
                    if let foundRange = originalAfterTime.lowercased().range(of: titleCandidate) {
                        return String(originalAfterTime[foundRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return titleCandidate.capitalized
            }
            }
        }
        
        // Pattern 1: "[activity] with [name]" - e.g., "drinks with Arnab"
        if let match = lowercased.range(of: "(grab |have |get )?(drinks|lunch|dinner|breakfast|coffee|meeting|call|chat)\\s+with\\s+([a-zA-Z]+)", options: .regularExpression) {
            let extracted = String(lowercased[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.count >= 5 {
                return extracted.capitalized
            }
        }
        
        // Pattern 2: "with [name] to [activity]" - e.g., "with Arnab to grab drinks"
        if let match = lowercased.range(of: "with\\s+([a-zA-Z]+)\\s+to\\s+(grab |have |get )?(drinks|lunch|dinner|breakfast|coffee|meeting|chat)", options: .regularExpression) {
            let extracted = String(lowercased[match])
            // Reformat to "[activity] with [name]"
            if let nameMatch = extracted.range(of: "with\\s+([a-zA-Z]+)", options: .regularExpression),
               let activityMatch = extracted.range(of: "(drinks|lunch|dinner|breakfast|coffee|meeting|chat)", options: .regularExpression) {
                let name = String(extracted[nameMatch]).replacingOccurrences(of: "with ", with: "")
                let activity = String(extracted[activityMatch])
                return "\(activity.capitalized) with \(name.capitalized)"
            }
        }
        
        // Pattern 3: "meet [name]" or "meeting with [name]"
        if let match = lowercased.range(of: "(meet|meeting)\\s+(with\\s+)?([a-zA-Z]+)", options: .regularExpression) {
            let extracted = String(lowercased[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.count >= 5 {
                return extracted.capitalized
            }
        }
        
        // Pattern 4: "[appointment type] appointment"
        if let match = lowercased.range(of: "(doctor|dentist|dental|medical|therapy|gym|haircut|workout|checkup|cleaning)('s)?\\s*(appointment|session|visit)?", options: .regularExpression) {
            var extracted = String(lowercased[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Only add "appointment" if it's a medical/professional service without it
            if !extracted.contains("appointment") && !extracted.contains("haircut") && !extracted.contains("workout") {
                extracted += " appointment"
            }
            return extracted.capitalized
        }

        // Pattern 4b: Extract activity between day-of-week and time
        // Handles: "for thurs to get haircut at 6 pm" -> "get haircut"
        let dayPatterns = ["mon", "tue", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
                          "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                          "tomorrow", "today"]
        for dayPattern in dayPatterns {
            if lowercased.contains(dayPattern) {
                // Find text after the day pattern and before time
                if let dayRange = lowercased.range(of: dayPattern) {
                    let afterDay = String(lowercased[dayRange.upperBound...])

                    // Remove "to " prefix if present
                    var titleCandidate = afterDay.replacingOccurrences(of: "^\\s*to\\s+", with: "", options: .regularExpression)

                    // Extract until time pattern or "at"
                    if let atRange = titleCandidate.range(of: "\\s+at\\s+\\d+", options: .regularExpression) {
                        titleCandidate = String(titleCandidate[..<atRange.lowerBound])
                    } else if let timeRange = titleCandidate.range(of: "\\d+\\s*(am|pm|:\\d+)", options: .regularExpression) {
                        titleCandidate = String(titleCandidate[..<timeRange.lowerBound])
                    }

                    titleCandidate = titleCandidate.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Remove "get " or "have " prefix
                    titleCandidate = titleCandidate.replacingOccurrences(of: "^(get|have|do|go to)\\s+", with: "", options: .regularExpression)

                    if titleCandidate.count >= 5 && titleCandidate.count <= 100 {
                        return titleCandidate.capitalized
                    }
                }
                break
            }
        }

        // Pattern 5: Extract activity description after "for" but skip short words like "me", "tom"
        // Improved to handle "for me for tom at 5 pm [actual title]"
        if let forRange = lowercased.range(of: "for\\s+(?:me\\s+)?(?:for\\s+)?(?:tom|tomorrow|today|this\\s+)?(?:wed|thu|fri|sat|sun|mon|tue|wednesday|thursday|friday|saturday|sunday|monday|tuesday)?\\s*(?:at\\s+\\d+\\s*(am|pm|:\\d+))?\\s*", options: .regularExpression) {
            var afterFor = String(lowercased[forRange.upperBound...])
            
            // Stop at common delimiters
            let stopWords = [" at ", " on ", " in ", " give ", " put ", " and make", " do some", " the meet"]
            for stop in stopWords {
                if let stopRange = afterFor.range(of: stop) {
                    afterFor = String(afterFor[..<stopRange.lowerBound])
                }
            }
            
            // Remove time patterns
            afterFor = afterFor.replacingOccurrences(of: "\\d+\\s*(am|pm|:\\d+)", with: "", options: .regularExpression)
            afterFor = afterFor.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip if it's just "me" or very short
            if afterFor.count >= 5 && afterFor.count <= 100 && !["me", "tom", "tomorrow", "today"].contains(afterFor.lowercased()) {
                return afterFor.capitalized
            }
        }
        
        // Pattern 6: Just look for "[name] to [activity]" anywhere
        if let match = lowercased.range(of: "([a-zA-Z]+)\\s+to\\s+(grab|have|get)?\\s*(drinks|lunch|dinner|coffee)", options: .regularExpression) {
            let extracted = String(lowercased[match])
            // Try to build a sensible title
            if let activityMatch = extracted.range(of: "(drinks|lunch|dinner|coffee)", options: .regularExpression) {
                let activity = String(extracted[activityMatch])
                let name = extracted.replacingOccurrences(of: " to.*", with: "", options: .regularExpression)
                if name.count >= 2 && name.count <= 20 {
                    return "\(activity.capitalized) with \(name.capitalized)"
                }
            }
        }
        
        // Fallback: Look for person name + activity clues
        let activities = ["drinks", "lunch", "dinner", "coffee", "meeting", "call", "chat", "hangout"]
        for activity in activities {
            if lowercased.contains(activity) {
                // Find a name near "with"
                if let withRange = lowercased.range(of: "with\\s+([a-zA-Z]+)", options: .regularExpression) {
                    let nameWithPrefix = String(lowercased[withRange])
                    let name = nameWithPrefix.replacingOccurrences(of: "with ", with: "")
                    if name.count >= 2 {
                        return "\(activity.capitalized) with \(name.capitalized)"
                    }
                }
                return activity.capitalized
            }
        }
        
        return "New Event"
    }
    /// Extract date and time from query
    private func extractEventDateTime(from query: String) -> (Date?, Bool) {
        let calendar = Calendar.current
        var hasTime = false
        var baseDate = Date()
        var foundDate = false

        // First check for month + day patterns (e.g., "February 14", "March 5", "Dec 25")
        let monthPatterns: [(patterns: [String], month: Int)] = [
            (["january", "jan"], 1),
            (["february", "feb"], 2),
            (["march", "mar"], 3),
            (["april", "apr"], 4),
            (["may"], 5),
            (["june", "jun"], 6),
            (["july", "jul"], 7),
            (["august", "aug"], 8),
            (["september", "sept", "sep"], 9),
            (["october", "oct"], 10),
            (["november", "nov"], 11),
            (["december", "dec"], 12)
        ]

        for (patterns, monthNum) in monthPatterns {
            for pattern in patterns {
                // Look for "February 14" or "Feb 14" pattern
                if let monthRange = query.lowercased().range(of: pattern) {
                    // Look for a number after the month name
                    let afterMonth = String(query[monthRange.upperBound...])
                    if let dayMatch = afterMonth.range(of: "\\s*(\\d{1,2})", options: .regularExpression),
                       let dayNum = Int(afterMonth[dayMatch].trimmingCharacters(in: .whitespaces)) {
                        // Create date with current year, extracted month, and extracted day
                        var components = calendar.dateComponents([.year], from: Date())
                        components.month = monthNum
                        components.day = dayNum
                        if let date = calendar.date(from: components) {
                            baseDate = date
                            foundDate = true
                            break
                        }
                    }
                }
            }
            if foundDate { break }
        }

        // Check for relative dates - including common abbreviations
        if !foundDate {
            let tomorrowPatterns = ["tomorrow", " tom ", "tom ", " tmrw", " tmr ", " tom", "for tom", "for tomorrow"]
            for pattern in tomorrowPatterns {
                if query.contains(pattern) || query.hasPrefix("tom ") || query.hasSuffix(" tom") {
                    baseDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    foundDate = true
                    break
                }
            }
        }

        if !foundDate && query.contains("today") {
            baseDate = Date()
            foundDate = true
        } else if !foundDate && query.contains("next week") {
            baseDate = calendar.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
            foundDate = true
        }
        
        // Check for day of week - handle full names AND abbreviations
        // Map includes both full names and common abbreviations
        let weekdayMappings: [(patterns: [String], weekday: Int)] = [
            (["sunday", " sun ", " sun", "sun ", "this sun", "next sun", "for sun"], 1),
            (["monday", " mon ", " mon", "mon ", "this mon", "next mon", "for mon"], 2),
            (["tuesday", " tue ", " tue", "tue ", " tues ", " tues", "tues ", "this tue", "next tue", "this tues", "next tues", "for tue", "for tues"], 3),
            (["wednesday", " wed ", " wed", "wed ", "this wed", "next wed", "for wed"], 4),
            (["thursday", " thu ", " thu", "thu ", " thur ", " thur", "thur ", " thurs ", " thurs", "thurs ", "this thu", "next thu", "this thur", "next thur", "this thurs", "next thurs", "for thu", "for thur", "for thurs"], 5),
            (["friday", " fri ", " fri", "fri ", "this fri", "next fri", "for fri"], 6),
            (["saturday", " sat ", " sat", "sat ", "this sat", "next sat", "for sat"], 7)
        ]
        
        if !foundDate {
            for (patterns, dayNumber) in weekdayMappings {
                for pattern in patterns {
                    if query.contains(pattern) {
                        if let nextDate = calendar.nextDate(after: Date(), matching: DateComponents(weekday: dayNumber), matchingPolicy: .nextTime) {
                            baseDate = nextDate
                            foundDate = true
                        }
                        break
                    }
                }
                if foundDate { break }
            }
        }
        
        // Extract time
        var hour = 9  // Default to 9 AM
        var minute = 0
        
        // Match patterns like "3pm", "3:30pm", "15:00"
        if let match = query.range(of: "(\\d{1,2}):(\\d{2})\\s*(am|pm)?", options: .regularExpression) {
            let timeStr = String(query[match])
            let components = timeStr.components(separatedBy: CharacterSet(charactersIn: ": "))
            if let h = Int(components[0]) {
                hour = h
                if components.count > 1, let m = Int(components[1].prefix(2)) {
                    minute = m
                }
                if timeStr.contains("pm") && hour < 12 { hour += 12 }
                if timeStr.contains("am") && hour == 12 { hour = 0 }
                hasTime = true
            }
        } else if let match = query.range(of: "(\\d{1,2})\\s*(am|pm)", options: .regularExpression) {
            let timeStr = String(query[match])
            if let h = Int(timeStr.filter { $0.isNumber }) {
                hour = h
                if timeStr.contains("pm") && hour < 12 { hour += 12 }
                if timeStr.contains("am") && hour == 12 { hour = 0 }
                hasTime = true
            }
        }
        
        // Combine date and time
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        
        return (calendar.date(from: components), hasTime)
    }
    
    /// Extract reminder minutes from query
    private func extractReminderMinutes(from query: String) -> Int? {
        // Check for specific reminder patterns
        if query.contains("no reminder") { return nil }
        
        if let match = query.range(of: "(\\d+)\\s*min(ute)?s?\\s*(before|reminder|early)", options: .regularExpression) {
            let numStr = String(query[match]).filter { $0.isNumber }
            if let minutes = Int(numStr) {
                return minutes
            }
        }
        
        if query.contains("1 hour") || query.contains("an hour") || query.contains("one hour") {
            return 60
        }
        
        if query.contains("30 min") { return 30 }
        if query.contains("15 min") { return 15 }
        if query.contains("10 min") { return 10 }
        if query.contains("5 min") { return 5 }
        
        // Default reminder keywords without specific time
        if query.contains("remind") || query.contains("reminder") {
            return 15  // Default to 15 minutes
        }
        
        return nil
    }
    
    /// Extract category from query - matches category names flexibly
    private func extractEventCategory(from query: String) -> String {
        let lowercased = query.lowercased()

        // ONLY check for EXPLICIT category mentions - no automatic keyword matching
        // Users must explicitly say "put in X category" or similar
        let explicitPatterns: [(pattern: String, category: String)] = [
            ("put in work", "Work"),
            ("in work category", "Work"),
            ("work category", "Work"),
            ("category work", "Work"),
            ("categorize as work", "Work"),
            ("categorize work", "Work"),
            ("as work category", "Work"),

            ("put in health", "Health"),
            ("in health category", "Health"),
            ("health category", "Health"),
            ("category health", "Health"),
            ("categorize as health", "Health"),
            ("categorize health", "Health"),
            ("as health category", "Health"),

            ("put in social", "Social"),
            ("in social category", "Social"),
            ("social category", "Social"),
            ("category social", "Social"),
            ("categorize as social", "Social"),
            ("categorize social", "Social"),
            ("as social category", "Social"),

            ("put in family", "Family"),
            ("in family category", "Family"),
            ("family category", "Family"),
            ("category family", "Family"),
            ("categorize as family", "Family"),
            ("categorize family", "Family"),
            ("as family category", "Family"),

            ("put in personal", "Personal"),
            ("in personal category", "Personal"),
            ("personal category", "Personal"),
            ("category personal", "Personal"),
            ("categorize as personal", "Personal"),
            ("categorize personal", "Personal"),
            ("as personal category", "Personal")
        ]

        // Check explicit patterns - user MUST explicitly specify category
        for (pattern, category) in explicitPatterns {
            if lowercased.contains(pattern) {
                return category
            }
        }

        // NO automatic keyword matching - always default to Personal
        // User must explicitly say "put in X category" or similar
        return "Personal"
    }

    /// Detects if query is related to restaurants, stores, or specific locations
    private func isRestaurantOrLocationQuery(_ query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        let locationKeywords = [
            // Restaurant/dining related
            "restaurant", "restaurant", "cafe", "coffee", "dinner", "lunch", "breakfast", "eating", "food", "dine", "dining",
            "bill", "cost", "price", "prices", "menu", "expect", "spend", "spending", "budget", "order",
            // Store/shopping related
            "store", "shop", "shopping", "retail", "price", "prices", "cost", "expensive",
            // Generic location queries
            "place", "location", "venue", "business", "going to", "planning to go"
        ]

        return locationKeywords.contains { keyword in
            lowercaseQuery.contains(keyword)
        }
    }

    /// Extracts a restaurant or location name from the query
    /// Examples: "Eddies", "Starbucks", "Best Buy" from queries like "what bill at Eddies" or "prices at Starbucks"
    private func extractLocationName(from query: String) -> String? {
        let lowercaseQuery = query.lowercased()

        // Look for pattern: "[at/to/for] [NAME]"
        let patterns = [
            "at\\s+([A-Za-z\\s&'-]+?)(?:\\s+(?:for|to|in|with)|\\?|$)",  // at [NAME]
            "for\\s+([A-Za-z\\s&'-]+?)(?:\\s+(?:at|in)|\\?|$)",           // for [NAME]
            "going\\s+(?:to|for)\\s+([A-Za-z\\s&'-]+?)(?:\\s+(?:for|to|in)|\\?|$)",  // going to [NAME]
            "visiting\\s+([A-Za-z\\s&'-]+?)(?:\\s+(?:for|to|in)|\\?|$)" // visiting [NAME]
        ]

        for patternString in patterns {
            if let regex = try? NSRegularExpression(pattern: patternString, options: .caseInsensitive) {
                let nsString = query as NSString
                let range = NSRange(location: 0, length: nsString.length)

                if let match = regex.firstMatch(in: query, range: range) {
                    if let captureRange = Range(match.range(at: 1), in: query) {
                        let locationName = String(query[captureRange])
                            .trimmingCharacters(in: .whitespaces)
                            .filter { !$0.isPunctuation || $0 == "-" || $0 == "&" || $0 == "'" }

                        if !locationName.isEmpty && locationName.count > 1 {
                            return locationName
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Fetch information about a specific restaurant or location (prices, menu, hours, ratings)
    private func fetchRestaurantInfo(name: String) async throws -> [String] {
        // Use Google Search to find restaurant information
        let searchTerm = "\(name) restaurant prices menu hours ratings"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "restaurant"

        // Use DuckDuckGo HTML search as an alternative (no API key needed)
        let searchURL = "https://html.duckduckgo.com/?q=\(searchTerm)&format=json&no_html=1&skip_disambig=1"

        guard let url = URL(string: searchURL) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        // Try to parse JSON response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = jsonObject["Results"] as? [[String: Any]] {
            var info: [String] = []

            for result in results.prefix(3) {
                if let text = result["Text"] as? String {
                    let cleanedText = text
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if !cleanedText.isEmpty {
                        info.append(cleanedText)
                    }
                }
            }

            return info
        }

        return []
    }

    // ============================================================================
    // DEPRECATED: buildContextPrompt() methods moved to LLMArchitecture_deprecated/
    // These methods are NEVER called - SelineChat uses VectorContextBuilder instead
    // ============================================================================
    /*
    /// DEPRECATED: Build context with intelligent filtering based on user query
    /// This method is NEVER called - SelineChat uses VectorContextBuilder.buildContext() instead
    func buildContextPrompt(forQuery userQuery: String) async -> String {
        // Reset ETA location info for each new query - prevents map card from persisting on unrelated follow-ups
        self.lastETALocationInfo = nil
        
        // Reset event creation info for each new query
        self.lastEventCreationInfo = nil
        
        // Reset relevant content for each new query
        self.lastRelevantContent = nil
        
        // Find relevant content (emails, notes, events) to display inline
        await findRelevantContent(forQuery: userQuery)
        
        // Detect event creation queries and extract details
        let userAskedToCreateEvent = isEventCreationQuery(userQuery)
        print("🔍 Event creation query detected: \(userAskedToCreateEvent) for query: '\(userQuery)'")
        if userAskedToCreateEvent {
            let extractedEvents = extractEventDetails(from: userQuery)
            print("🔍 Extracted \(extractedEvents.count) events from query")
            if !extractedEvents.isEmpty {
                self.lastEventCreationInfo = extractedEvents
                print("📅✅ SET lastEventCreationInfo with \(extractedEvents.count) event(s)")
                for event in extractedEvents {
                    print("   • Title: '\(event.title)' on \(event.formattedDateTime)")
                    print("   • Category: '\(event.category)', HasTime: \(event.hasTime)")
                }
            } else {
                print("⚠️ Event keyword matched but extraction returned EMPTY array - check extractEventDetails()")
            }
        }
        
        // Extract useful filters from the query (but don't gate sections based on keywords)
        let categoryFilter = extractCategoryFilter(from: userQuery)
        let timePeriodFilter = extractTimePeriodFilter(from: userQuery)
        let locationCategoryFilter = extractLocationCategoryFilter(from: userQuery)
        let specificNewsTopic = extractNewsTopic(from: userQuery)
        let specificLocationName = isRestaurantOrLocationQuery(userQuery) ? extractLocationName(from: userQuery) : nil

        // Detect expense vs bank statement queries
        let userAskedAboutExpenses = isExpenseQuery(userQuery)
        let userAskedAboutBankStatement = isBankStatementQuery(userQuery)
        
        // Detect ETA/travel time queries and extract locations
        let userAskedAboutETA = isETAQuery(userQuery)
        let etaLocations = userAskedAboutETA ? extractETALocations(from: userQuery) : (nil, nil)

        // Only refresh if cache is invalid (OPTIMIZATION: Skip refresh if data is fresh)
        if !isCacheValid {
            await refresh()
        } else {
            print("✅ Using cached data (valid for \(Int(cacheValidityDuration - Date().timeIntervalSince(lastRefreshTime))) more seconds)")
        }

        // OPTIMIZATION: Only fetch geofence stats if query is location-related
        let isLocationQuery = userQuery.lowercased().contains("location") ||
                              userQuery.lowercased().contains("place") ||
                              userQuery.lowercased().contains("restaurant") ||
                              userQuery.lowercased().contains("visit") ||
                              userQuery.lowercased().contains("where") ||
                              userQuery.lowercased().contains("been")

        if isLocationQuery {
            print("📊 Location query detected - fetching visit stats...")
            // Fetch stats in background (non-blocking) - don't await to prevent blocking UI
            let locationsToFetch = await MainActor.run { self.locations.prefix(20) }
            Task.detached(priority: .utility) {
                await withTaskGroup(of: Void.self) { group in
                    for place in locationsToFetch {  // Limit to 20 most recent locations
                        group.addTask {
                            await LocationVisitAnalytics.shared.fetchStats(for: place.id)
                        }
                    }
                }
                print("✅ Visit stats loaded for top locations")
            }
        } else {
            print("⚡ Skipping visit stats - not a location query")
        }

        // Ensure weather data is available if user explicitly asked for it
        let isWeatherRequest = userQuery.lowercased().contains("weather") || 
                              userQuery.lowercased().contains("temperature") || 
                              userQuery.lowercased().contains("forecast") ||
                              userQuery.lowercased().contains("rain") ||
                              userQuery.lowercased().contains("snow") ||
                              userQuery.lowercased().contains("sun")
        
        if isWeatherRequest {
            if weatherData == nil {
                print("🌤️ Weather query detected but data missing - force fetching...")
                let locationService = LocationService.shared
                // Default to Toronto if location unavailable
                let location = await locationService.currentLocation ?? CLLocation(latitude: 43.6532, longitude: -79.3832)
                
                await self.weatherService.fetchWeather(for: location)
                self.weatherData = self.weatherService.weatherData
                print("✅ Weather data forced loaded for query")
            }
        }

        // OPTIMIZATION: Cache filtered results to avoid recomputation
        let cacheKey = "\(categoryFilter ?? "none")_\(timePeriodFilter != nil ? "\(timePeriodFilter!.startDate.timeIntervalSince1970)" : "none")"
        let shouldRecompute = cachedFilteredEvents == nil ||
                             lastFilterCacheTime == nil ||
                             Date().timeIntervalSince(lastFilterCacheTime!) > 300 // 5 minute cache (optimized from 60s)
        
        var filteredEvents: [TaskItem]
        if shouldRecompute {
            filteredEvents = events

            // Apply category filter if detected
            if let categoryId = categoryFilter {
                filteredEvents = filteredEvents.filter { $0.tagId == categoryId }
            }

            // Apply time period filter if detected
            if let timePeriod = timePeriodFilter {
                filteredEvents = filteredEvents.filter { event in
                    // For recurring events, check if ANY completion falls within the time period
                    if event.isRecurring {
                        // Include event if it has at least one completion in the time period
                        let hasCompletionInPeriod = event.completedDates.contains { date in
                            return date >= timePeriod.startDate && date <= timePeriod.endDate
                        }
                        // Also include if the event is scheduled/active during this period
                        let eventDate = event.targetDate ?? event.scheduledTime ?? currentDate
                        let isActiveInPeriod = eventDate <= timePeriod.endDate && (event.recurrenceEndDate == nil || event.recurrenceEndDate! >= timePeriod.startDate)
                        return hasCompletionInPeriod || isActiveInPeriod
                    } else {
                        // For non-recurring events, use the original date-based filtering
                        let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate
                        return eventDate >= timePeriod.startDate && eventDate <= timePeriod.endDate
                    }
                }
            }
            
            // Cache the result
            cachedFilteredEvents = filteredEvents
            lastFilterCacheTime = Date()
        } else {
            filteredEvents = cachedFilteredEvents ?? events
        }

        // Filter receipts by time period if detected (apply regardless of query type)
        var filteredReceipts: [ReceiptStat]
        if shouldRecompute {
            filteredReceipts = receipts
            if let timePeriod = timePeriodFilter {
                filteredReceipts = receipts.filter { receipt in
                    return receipt.date >= timePeriod.startDate && receipt.date <= timePeriod.endDate
                }
            }
            cachedFilteredReceipts = filteredReceipts
        } else {
            filteredReceipts = cachedFilteredReceipts ?? receipts
        }

        // Temporarily replace events and receipts with filtered versions
        let originalEvents = self.events
        let originalReceipts = self.receipts
        self.events = filteredEvents
        self.receipts = filteredReceipts

        // Build context with filtered events (skip refresh since we just did it)
        var context = ""

        // Current date context - using reusable formatters
        context += "=== CURRENT DATE ===\n"
        context += "Today is: \(dayFormatter.string(from: currentDate)), \(dateFormatter.string(from: currentDate))\n"
        let utcOffset = TimeZone.current.secondsFromGMT() / 3600
        let utcSign = utcOffset >= 0 ? "+" : ""
        context += "Timezone: \(TimeZone.current.identifier) (UTC\(utcSign)\(utcOffset))\n\n"

        // Current location context
        let locationService = LocationService.shared
        if let currentLocation = locationService.currentLocation {
            context += "=== CURRENT LOCATION ===\n"
            context += "Location: \(locationService.locationName)\n"
            context += "Coordinates: \(String(format: "%.6f", currentLocation.coordinate.latitude)), \(String(format: "%.6f", currentLocation.coordinate.longitude))\n"
            context += "Accuracy: \(Int(currentLocation.horizontalAccuracy))m\n\n"
        } else {
            context += "=== CURRENT LOCATION ===\n"
            context += "Location: Not available (location services may be disabled or location not yet determined)\n\n"
        }

        // Data summary
        context += "=== DATA SUMMARY ===\n"
        context += "Total Events: \(events.count)\n"
        context += "Total Receipts: \(receipts.count)\n"
        context += "Total Notes: \(notes.count)\n"
        context += "Total Emails: \(emails.count)\n"
        context += "Total Locations: \(locations.count)\n\n"

        // Available folders for clarification
        context += "=== AVAILABLE FOLDERS (For Clarifying Questions) ===\n"
        context += "**EMAIL FOLDERS (from sidebar):**\n"

        // Show custom email folders from sidebar with email counts
        if !customEmailFolders.isEmpty {
            for folder in customEmailFolders.sorted(by: { $0.name < $1.name }) {
                let emailCount = savedEmailsByFolder[folder.id]?.count ?? 0
                context += "  • \(folder.name): \(emailCount) emails\n"
            }
        } else {
            context += "  • (No custom folders created yet)\n"
        }

        context += "\n**NOTE FOLDERS:**\n"
        let noteFolderMap = Dictionary(grouping: notes) { note in
            getCachedFolderName(for: note.folderId)
        }
        for folder in noteFolderMap.keys.sorted() {
            if let folderNotes = noteFolderMap[folder] {
                context += "  • \(folder): \(folderNotes.count) notes\n"
            }
        }
        context += "\n"

        // Build events section from buildContextPromptInternal but without refresh
        let calendar = Calendar.current

        // Organize events by temporal proximity
        var today: [TaskItem] = []
        var tomorrow: [TaskItem] = []
        var thisWeek: [TaskItem] = []
        var upcoming: [TaskItem] = []
        var past: [TaskItem] = []

        for event in events {
            if event.isRecurring {
                let todayDate = currentDate
                let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                let dayAfterTomorrowDate = calendar.date(byAdding: .day, value: 2, to: currentDate)!

                if shouldEventOccurOn(event, date: todayDate) {
                    today.append(event)
                }

                if shouldEventOccurOn(event, date: tomorrowDate) {
                    tomorrow.append(event)
                }

                if shouldEventOccurOn(event, date: dayAfterTomorrowDate) {
                    thisWeek.append(event)
                } else {
                    var hasUpcomingOccurrence = false
                    for daysAhead in 3...7 {
                        if let checkDate = calendar.date(byAdding: .day, value: daysAhead, to: currentDate),
                           shouldEventOccurOn(event, date: checkDate) {
                            thisWeek.append(event)
                            hasUpcomingOccurrence = true
                            break
                        }
                    }

                    if !hasUpcomingOccurrence {
                        if let nextDate = getNextOccurrenceDate(for: event, after: calendar.date(byAdding: .day, value: 7, to: currentDate)!) {
                            upcoming.append(event)
                        }
                    }
                }
            } else {
                let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate

                // Use our custom date comparison helpers (based on currentDate, not system time)
                if isDateToday(eventDate) {
                    today.append(event)
                } else if isDateTomorrow(eventDate) {
                    tomorrow.append(event)
                } else if isDateThisWeek(eventDate) && !isDateToday(eventDate) && !isDateTomorrow(eventDate) {
                    thisWeek.append(event)
                } else if eventDate > currentDate {
                    upcoming.append(event)
                } else {
                    past.append(event)
                }
            }
        }

        context += "=== EVENTS & CALENDAR ===\n"
        if !events.isEmpty {
            // TODAY
            if !today.isEmpty {
                context += "\n**TODAY** (\(today.count) events):\n"
                for event in today.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo)\(calendarIndicator) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // TOMORROW
            if !tomorrow.isEmpty {
                context += "\n**TOMORROW** (\(tomorrow.count) events):\n"
                for event in tomorrow.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo)\(calendarIndicator) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                    
                    // Try to find location in event title/description and calculate ETA
                    let eventText = "\(event.title) \(event.description ?? "")"
                    if let location = findLocationByName(eventText) {
                        if let eta = await calculateETA(to: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                            context += "    📍 Location: \(location.displayName) | ETA: \(eta)\n"
                        } else {
                            context += "    📍 Location: \(location.displayName)\n"
                        }
                    }
                }
            }

            // THIS WEEK (next 3-7 days)
            if !thisWeek.isEmpty {
                context += "\n**THIS WEEK** (\(thisWeek.count) events):\n"
                for event in thisWeek.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo)\(calendarIndicator) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week) - LIMITED to first 5 for context size
            if !upcoming.isEmpty {
                let upcomingToShow = Array(upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }).prefix(5))
                context += "\n**UPCOMING** (\(upcomingToShow.count) of \(upcoming.count) events):\n"
                for event in upcomingToShow {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo)\(calendarIndicator) - \(categoryName) - \(dateStr)\n"
                }
                if upcoming.count > 10 {
                    context += "  ... and \(upcoming.count - 10) more upcoming events\n"
                }
            }

            // LAST WEEK EVENTS
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: currentDate)!
            let lastWeekEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate >= sevenDaysAgo && eventDate < currentDate
            }
            if !lastWeekEvents.isEmpty {
                context += "\n**LAST WEEK** (\(lastWeekEvents.count) events):\n"
                for event in lastWeekEvents.sorted(by: { ($0.targetDate ?? $0.completedDate ?? Date.distantPast) > ($1.targetDate ?? $1.completedDate ?? Date.distantPast) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(calendarIndicator) - \(categoryName) - \(dateStr)\n"
                }
            }

            // OLDER PAST EVENTS
            let olderPastEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate < sevenDaysAgo
            }
            if !olderPastEvents.isEmpty {
                context += "\n**PAST EVENTS** (older than 1 week, showing last 5):\n"
                for event in olderPastEvents.suffix(5).reversed() {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let calendarIndicator = event.isFromCalendar ? " [📅 CALENDAR]" : ""

                    context += "  \(status): \(event.title)\(calendarIndicator) - \(categoryName) - \(dateStr)\n"
                }
                if olderPastEvents.count > 5 {
                    context += "  ... and \(olderPastEvents.count - 5) more older past events\n"
                }
            }
            // RECURRING EVENTS SUMMARY - With next occurrence dates for accurate answers
            let recurringEvents = events.filter { $0.isRecurring }
            if !recurringEvents.isEmpty {
                context += "\n**RECURRING EVENTS SUMMARY** (\(recurringEvents.count) recurring):\n"
                context += "**IMPORTANT: For recurring events (especially birthdays/anniversaries), use the 'Next occurrence' date below to answer 'when' questions.**\n"
                
                for event in recurringEvents.prefix(15) {  // Increased to 15 for better coverage
                    let categoryName = getCategoryName(for: event.tagId)
                    
                    // Frequency info
                    var frequencyStr = "Unknown"
                    if let freq = event.recurrenceFrequency {
                        switch freq {
                        case .daily: frequencyStr = "Daily"
                        case .weekly: frequencyStr = "Weekly"
                        case .biweekly: frequencyStr = "Bi-weekly"
                        case .monthly: frequencyStr = "Monthly"
                        case .yearly: frequencyStr = "Yearly"
                        case .custom: frequencyStr = "Custom"
                        }
                    }
                    
                    // Next occurrence - CRITICAL for answering "when is X" questions
                    var nextOccurrenceStr = "Unknown"
                    if let nextDate = getNextOccurrenceDate(for: event) {
                        nextOccurrenceStr = dateFormatter.string(from: nextDate)
                    } else if let targetDate = event.targetDate {
                        nextOccurrenceStr = dateFormatter.string(from: targetDate) + " (original date)"
                    }
                    
                    // Original/anchor date - for reference
                    let anchorDate = event.targetDate ?? event.createdAt
                    let anchorStr = dateFormatter.string(from: anchorDate)
                    
                    context += "  • \(event.title)\n"
                    context += "    Category: \(categoryName) | Frequency: \(frequencyStr)\n"
                    context += "    Original date: \(anchorStr) | **Next occurrence: \(nextOccurrenceStr)**\n"
                    context += "    Completions: \(event.completedDates.count) total\n"
                }
                if recurringEvents.count > 15 {
                    context += "  ... and \(recurringEvents.count - 15) more recurring events\n"
                }
            }
        } else {
            context += "  No events\n"
        }

        // Add receipts section (always included)
        context += "\n=== RECEIPTS & EXPENSES ===\n"

        // Add context about the data source for the user's query
        if userAskedAboutBankStatement {
            context += "**NOTE: User asked about bank/credit card statements. These are typically stored in NOTES folder. Check the NOTES section for bank statements, credit card statements, or transaction lists from American Express, Visa, Mastercard, etc.**\n\n"
        }

        if !receipts.isEmpty {
                // Group receipts by month dynamically
                let receiptsByMonth = Dictionary(grouping: receipts) { receipt in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMMM yyyy"
                    return formatter.string(from: receipt.date)
                }

                // Get current month for detection
                let calendar = Calendar.current
                let currentMonthFormatter = DateFormatter()
                currentMonthFormatter.dateFormat = "MMMM yyyy"
                let currentMonthStr = currentMonthFormatter.string(from: currentDate)

                // Sort months: current month first, then others by recency
                let sortedMonths = receiptsByMonth.keys.sorted { month1, month2 in
                    if month1 == currentMonthStr { return true }
                    if month2 == currentMonthStr { return false }
                    return month1 > month2  // Most recent first
                }

                // Show ALL months with receipts to ensure complete data for comparisons
                // This allows LLM to properly compare spending across any months user asks about
                for month in sortedMonths {
                    guard let items = receiptsByMonth[month] else { continue }

                    let total = items.reduce(0.0) { $0 + $1.amount }
                    let isCurrentMonth = (month == currentMonthStr)

                    context += "\n**\(month)**\(isCurrentMonth ? " (Current Month)" : ""): \(items.count) receipts, Total: $\(String(format: "%.2f", total))\n"
                    
                    // Add DATE-BY-DATE breakdown to help LLM answer date-specific queries
                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "MMMM d"
                    let receiptsByDay = Dictionary(grouping: items) { receipt in
                        dayFormatter.string(from: receipt.date)
                    }
                    let sortedDays = receiptsByDay.keys.sorted { day1, day2 in
                        // Sort by extracting day number
                        let num1 = Int(day1.components(separatedBy: " ").last ?? "0") ?? 0
                        let num2 = Int(day2.components(separatedBy: " ").last ?? "0") ?? 0
                        return num1 < num2
                    }
                    context += "  **Days with receipts**: \(sortedDays.joined(separator: ", "))\n"

                    // Get real category breakdown for this month using ReceiptCategorizationService
                    let categoryBreakdown = await categorizationService.getCategoryBreakdown(for: items)

                    // Show categories and amounts
                    for (category, receiptsInCategory) in categoryBreakdown.categoryReceipts.sorted(by: { $0.key < $1.key }) {
                        let categoryTotal = receiptsInCategory.reduce(0.0) { $0 + $1.amount }
                        context += "  **\(category)**: $\(String(format: "%.2f", categoryTotal)) (\(receiptsInCategory.count) items)\n"

                        // Show all items for current month, summary for previous months
                        if isCurrentMonth {
                            for receipt in receiptsInCategory.sorted(by: { $0.date > $1.date }) {
                                context += "    • \(receipt.title): $\(String(format: "%.2f", receipt.amount)) - \(formatDate(receipt.date))\n"
                            }
                        }
                    }
                }
            } else {
                context += "  No receipts\n"
            }

        // Add recurring expenses section (detailed)
        do {
            let activeRecurring = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()

            if !activeRecurring.isEmpty {
                context += "\n=== RECURRING EXPENSES (SUBSCRIPTIONS & BILLS) ===\n\n"

                // Calculate totals
                let totalMonthly = activeRecurring.reduce(0.0) { total, expense in
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    switch expense.frequency {
                    case .daily:
                        return total + (amount * 30)
                    case .weekly:
                        return total + (amount * 4.3)
                    case .biweekly:
                        return total + (amount * 2.15)
                    case .monthly:
                        return total + amount
                    case .yearly:
                        return total + (amount / 12)
                    case .custom:
                        // Custom frequency typically means specific days per week
                        // Using weekly multiplier (4.3) as a reasonable approximation
                        return total + (amount * 4.3)
                    }
                }

                let totalYearly = activeRecurring.reduce(0.0) { total, expense in
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    switch expense.frequency {
                    case .daily:
                        return total + (amount * 365)
                    case .weekly:
                        return total + (amount * 52)
                    case .biweekly:
                        return total + (amount * 26)
                    case .monthly:
                        return total + (amount * 12)
                    case .yearly:
                        return total + amount
                    case .custom:
                        // Custom frequency typically means specific days per week
                        // Using weekly multiplier (52) as a reasonable approximation
                        return total + (amount * 52)
                    }
                }

                context += "**💰 Monthly Total: $\(String(format: "%.2f", totalMonthly))** | **Yearly Total: $\(String(format: "%.2f", totalYearly))**\n"
                context += "**Active Subscriptions: \(activeRecurring.count)**\n\n"

                // Sort by next occurrence
                for expense in activeRecurring.sorted(by: { $0.nextOccurrence < $1.nextOccurrence }) {
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    context += "• **\(expense.title)**\n"
                    context += "    Amount: \(expense.formattedAmount) | Frequency: \(expense.frequency.rawValue.capitalized)\n"
                    context += "    Next: \(formatDate(expense.nextOccurrence)) | Started: \(formatDate(expense.startDate))\n"

                    if let endDate = expense.endDate {
                        context += "    Ends: \(formatDate(endDate))\n"
                    }

                    if let description = expense.description, !description.isEmpty {
                        context += "    Notes: \(description)\n"
                    }

                    if let category = expense.category, !category.isEmpty {
                        context += "    Category: \(category)\n"
                    }

                    context += "    Status: \(expense.isActive ? "✅ Active" : "⏸️ Paused")\n"
                    context += "\n"
                }
            }
        } catch {
            print("⚠️ Error fetching recurring expenses for context: \(error)")
        }

        // Add ETA section if user asked about travel times
        if userAskedAboutETA {
            context += "\n=== TRAVEL TIME / ETA CALCULATIONS ===\n"
            
            let locationService = LocationService.shared
            let currentLocation = locationService.currentLocation
            
            // Search for locations (saved OR any location via MapKit/geocoding)
            var originResult: LocationSearchResult?
            var destinationResult: LocationSearchResult?
            
            if let originName = etaLocations.0 {
                originResult = await searchAnyLocation(originName)
                if let origin = originResult {
                    let savedTag = origin.isSavedLocation ? " [Saved]" : " [Found via search]"
                    context += "📍 Origin: \(origin.name)\(savedTag)\n"
                    context += "   Address: \(origin.address)\n"
                } else {
                    context += "📍 Origin: \"\(originName)\" - ⚠️ LOCATION NOT FOUND\n"
                    context += "   **ASK USER:** Please ask the user for the exact address or full name of '\(originName)'\n"
                }
            }
            
            if let destName = etaLocations.1 {
                destinationResult = await searchAnyLocation(destName)
                if let dest = destinationResult {
                    let savedTag = dest.isSavedLocation ? " [Saved]" : " [Found via search]"
                    context += "🎯 Destination: \(dest.name)\(savedTag)\n"
                    context += "   Address: \(dest.address)\n"
                } else {
                    context += "🎯 Destination: \"\(destName)\" - ⚠️ LOCATION NOT FOUND\n"
                    context += "   **ASK USER:** Please ask the user for the exact address or full name of '\(destName)'\n"
                }
            }
            
            // Calculate ETA if we have both locations
            if let origin = originResult, let dest = destinationResult {
                // Calculate from origin to destination
                let originLocation = CLLocation(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)
                do {
                    let result = try await navigationService.calculateETA(
                        from: originLocation,
                        to: dest.coordinate
                    )
                    context += "\n🚗 **CALCULATED ETA (with current traffic):**\n"
                    context += "   Drive time: \(result.durationText)\n"
                    context += "   Distance: \(result.distanceText)\n"
                    context += "   Route: \(origin.name) → \(dest.name)\n"
                    
                    // Store for UI display
                    self.lastETALocationInfo = ETALocationInfo(
                        originName: origin.name,
                        originAddress: origin.address,
                        originLatitude: origin.coordinate.latitude,
                        originLongitude: origin.coordinate.longitude,
                        destinationName: dest.name,
                        destinationAddress: dest.address,
                        destinationLatitude: dest.coordinate.latitude,
                        destinationLongitude: dest.coordinate.longitude,
                        driveTime: result.durationText,
                        distance: result.distanceText
                    )
                } catch {
                    context += "\n⚠️ Could not calculate ETA: \(error.localizedDescription)\n"
                }
            } else if let dest = destinationResult, let current = currentLocation, originResult == nil && etaLocations.0 == nil {
                // No origin specified - calculate from current location to destination
                do {
                    let result = try await navigationService.calculateETA(
                        from: current,
                        to: dest.coordinate
                    )
                    context += "\n🚗 **CALCULATED ETA FROM CURRENT LOCATION (with current traffic):**\n"
                    context += "   Drive time: \(result.durationText)\n"
                    context += "   Distance: \(result.distanceText)\n"
                    context += "   From: Current location (\(locationService.locationName))\n"
                    context += "   To: \(dest.name)\n"
                    
                    // Store for UI display
                    self.lastETALocationInfo = ETALocationInfo(
                        originName: "Current Location",
                        originAddress: locationService.locationName,
                        originLatitude: current.coordinate.latitude,
                        originLongitude: current.coordinate.longitude,
                        destinationName: dest.name,
                        destinationAddress: dest.address,
                        destinationLatitude: dest.coordinate.latitude,
                        destinationLongitude: dest.coordinate.longitude,
                        driveTime: result.durationText,
                        distance: result.distanceText
                    )
                } catch {
                    context += "\n⚠️ Could not calculate ETA: \(error.localizedDescription)\n"
                }
            } else if originResult == nil || destinationResult == nil {
                // One or both locations not found
                context += "\n⚠️ **CANNOT CALCULATE ETA** - One or more locations could not be found.\n"
                context += "**INSTRUCTION FOR LLM:** Ask the user to provide more details:\n"
                if originResult == nil && etaLocations.0 != nil {
                    context += "  - For '\(etaLocations.0!)': Ask for the full address or exact business name\n"
                }
                if destinationResult == nil && etaLocations.1 != nil {
                    context += "  - For '\(etaLocations.1!)': Ask for the full address or exact business name\n"
                }
                context += "\nExample follow-up questions:\n"
                context += "  - \"What's the full address of your airbnb?\"\n"
                context += "  - \"Is that Lakeridge Ski Resort in Uxbridge, Ontario?\"\n"
                context += "  - \"Could you give me the exact location name or address?\"\n"
            }
            
            context += "\n"
        }

        // Add locations section (always included)
        context += "\n=== SAVED LOCATIONS ===\n"

        // Filter locations by category if specified
        var filteredLocations = locations
        if let locationCategory = locationCategoryFilter {
            filteredLocations = filteredLocations.filter { $0.category == locationCategory }
        }

        if !filteredLocations.isEmpty {
                // Separate favorites from other locations
                let favorites = filteredLocations.filter { $0.isFavourite }
                let nonFavorites = filteredLocations.filter { !$0.isFavourite }

                // Show favorites first
                if !favorites.isEmpty {
                    context += "\n**FAVORITES** (\(favorites.count) locations):\n"
                    for place in favorites.sorted(by: { $0.displayName < $1.displayName }).prefix(5) {  // Limit to 5 favorites
                        context += "  ★ \(place.displayName)\n"
                        context += "    Address: \(place.address)\n"

                        // Geographic info
                        let geoInfo = [place.city, place.province, place.country].compactMap { $0 }.joined(separator: ", ")
                        if !geoInfo.isEmpty {
                            context += "    Location: \(geoInfo)\n"
                        }

                        // Ratings
                        if let googleRating = place.rating {
                            context += "    Google Rating: ⭐ \(String(format: "%.1f", googleRating))/5.0\n"
                        }
                        if let userRating = place.userRating {
                            context += "    Your Rating: ⭐ \(userRating)/10\n"
                        }

                        // Cuisine for restaurants
                        if let cuisine = place.userCuisine {
                            context += "    Cuisine: \(cuisine)\n"
                        }

                        // GEOFENCE VISIT DATA - Include detailed location tracking statistics
                        if let stats = LocationVisitAnalytics.shared.visitStats[place.id] {
                            context += "    📊 Visit Statistics:\n"
                            context += "      Total visits: \(stats.totalVisits) times\n"
                            context += "      This month: \(stats.thisMonthVisits) visits\n"
                            context += "      This year: \(stats.thisYearVisits) visits\n"

                            if stats.averageDurationMinutes > 0 {
                                context += "      Average duration: \(stats.formattedAverageDuration)\n"
                            }

                            if let lastVisit = stats.lastVisitDate {
                                let lastVisitFormatter = RelativeDateTimeFormatter()
                                lastVisitFormatter.unitsStyle = .short
                                let lastVisitStr = lastVisitFormatter.localizedString(for: lastVisit, relativeTo: Date())
                                context += "      Last visited: \(lastVisitStr)\n"
                            }

                            if let peakTime = stats.mostCommonTimeOfDay {
                                context += "      Most common time: \(peakTime)\n"
                            }
                            if let peakDay = stats.mostCommonDayOfWeek {
                                context += "      Most visited day: \(peakDay)\n"
                            }
                        }
                        
                        // LOCATION MEMORIES - General reasons for visiting this location
                        // Note: This is loaded asynchronously in MetadataBuilderService, so we need to fetch it here
                        Task {
                            do {
                                let memories = try await LocationMemoryService.shared.getMemories(for: place.id)
                                let purposeMemory = memories.first(where: { $0.memoryType == .purpose })
                                let purchaseMemory = memories.first(where: { $0.memoryType == .purchase })
                                
                                if purposeMemory != nil || purchaseMemory != nil {
                                    await MainActor.run {
                                        // This will be included in next context build
                                    }
                                }
                            } catch {
                                print("⚠️ Failed to load location memories for context: \(error)")
                            }
                        }

                        // SPECIFIC DATE VISITS - Include if user asked about a specific time period
                        if let timePeriod = timePeriodFilter {
                            let visitsInPeriod = await LocationVisitAnalytics.shared.getVisitsInDateRange(for: place.id, startDate: timePeriod.startDate, endDate: timePeriod.endDate)
                            if !visitsInPeriod.isEmpty {
                                context += "    🎯 Visits during requested period:\n"
                                for visit in visitsInPeriod.sorted(by: { $0.entryTime > $1.entryTime }) {
                                    let entryStr = mediumDateTimeFormatter.string(from: visit.entryTime)
                                    let durationStr = visit.durationMinutes.map { "\($0) min" } ?? "ongoing"
                                    context += "      • \(entryStr) (\(durationStr))\n"
                                }
                            }
                        }

                        // User notes
                        if let notes = place.userNotes, !notes.isEmpty {
                            context += "    Notes: \(notes)\n"
                        }

                        // Phone
                        if let phone = place.phone, !phone.isEmpty {
                            context += "    Phone: \(phone)\n"
                        }

                        context += "\n"
                    }
                }

                // Group non-favorites by category
                if !nonFavorites.isEmpty {
                    let locationsByCategory = Dictionary(grouping: nonFavorites) { $0.category }
                    let sortedCategories = locationsByCategory.keys.sorted()

                    for category in sortedCategories {
                        guard let placesInCategory = locationsByCategory[category] else { continue }

                        context += "\n**\(category.uppercased())** (\(placesInCategory.count) locations):\n"

                        for place in placesInCategory.sorted(by: { $0.displayName < $1.displayName }).prefix(8) {  // Limit to 8 per category
                            context += "  • \(place.displayName)\n"
                            context += "    Address: \(place.address)\n"

                            // Geographic info
                            let geoInfo = [place.city, place.province, place.country].compactMap { $0 }.joined(separator: ", ")
                            if !geoInfo.isEmpty {
                                context += "    Location: \(geoInfo)\n"
                            }

                            // Ratings
                            if let googleRating = place.rating {
                                context += "    Google Rating: ⭐ \(String(format: "%.1f", googleRating))/5.0\n"
                            }
                            if let userRating = place.userRating {
                                context += "    Your Rating: ⭐ \(userRating)/10\n"
                            }

                            // Cuisine for restaurants
                            if let cuisine = place.userCuisine {
                                context += "    Cuisine: \(cuisine)\n"
                            }

                            // GEOFENCE VISIT DATA - Include detailed location tracking statistics
                            if let stats = LocationVisitAnalytics.shared.visitStats[place.id] {
                                context += "    📊 Visit Statistics:\n"
                                context += "      Total visits: \(stats.totalVisits) times\n"
                                context += "      This month: \(stats.thisMonthVisits) visits\n"
                                context += "      This year: \(stats.thisYearVisits) visits\n"

                                if stats.averageDurationMinutes > 0 {
                                    context += "      Average duration: \(stats.formattedAverageDuration)\n"
                                }

                                if let lastVisit = stats.lastVisitDate {
                                    let lastVisitFormatter = RelativeDateTimeFormatter()
                                    lastVisitFormatter.unitsStyle = .short
                                    let lastVisitStr = lastVisitFormatter.localizedString(for: lastVisit, relativeTo: Date())
                                    context += "      Last visited: \(lastVisitStr)\n"
                                }

                                if let peakTime = stats.mostCommonTimeOfDay {
                                    context += "      Most common time: \(peakTime)\n"
                                }
                                if let peakDay = stats.mostCommonDayOfWeek {
                                    context += "      Most visited day: \(peakDay)\n"
                                }
                            }

                            // SPECIFIC DATE VISITS - Include if user asked about a specific time period
                            if let timePeriod = timePeriodFilter {
                                let visitsInPeriod = await LocationVisitAnalytics.shared.getVisitsInDateRange(for: place.id, startDate: timePeriod.startDate, endDate: timePeriod.endDate)
                                if !visitsInPeriod.isEmpty {
                                    let dateFormatter = DateFormatter()
                                    dateFormatter.dateStyle = .medium
                                    dateFormatter.timeStyle = .short
                                    context += "    🎯 Visits during requested period:\n"
                                    for visit in visitsInPeriod.sorted(by: { $0.entryTime > $1.entryTime }) {
                                        let entryStr = dateFormatter.string(from: visit.entryTime)
                                        let durationStr = visit.durationMinutes.map { "\($0) min" } ?? "ongoing"
                                        context += "      • \(entryStr) (\(durationStr))\n"
                                    }
                                }
                            }

                            // User notes
                            if let notes = place.userNotes, !notes.isEmpty {
                                context += "    Notes: \(notes)\n"
                            }

                            // Phone
                            if let phone = place.phone, !phone.isEmpty {
                                context += "    Phone: \(phone)\n"
                            }

                            context += "\n"
                        }
                    }
                }
            } else {
                context += "  No saved locations\n"
            }

        // Add weather section (always included)
        if weatherData != nil {
            context += "\n=== CURRENT WEATHER ===\n"
            if let weather = weatherData {
                context += "Location: \(weather.locationName)\n"
                context += "Temperature: \(weather.temperature)°\n"
                context += "Conditions: \(weather.description)\n"
                context += "Sunrise: \(formatTime(weather.sunrise))\n"
                context += "Sunset: \(formatTime(weather.sunset))\n"

                if !weather.dailyForecasts.isEmpty {
                    context += "\n**6-Day Forecast:**\n"
                    for forecast in weather.dailyForecasts.prefix(6) {
                        context += "  • \(forecast.day): \(forecast.temperature)° - \(forecast.iconName)\n"
                    }
                }
            }
        }

        // Add restaurant/location information section when a specific location is mentioned
        if let locationName = specificLocationName {
            context += "\n=== RESTAURANT/LOCATION INFO ===\n"
            context += "User is asking about: **\(locationName)**\n\n"

            do {
                let locationInfo = try await fetchRestaurantInfo(name: locationName)
                if !locationInfo.isEmpty {
                    context += "**Information from web search:**\n"
                    for info in locationInfo.prefix(3) {
                        context += "  • \(info)\n"
                    }
                } else {
                    context += "  (No specific pricing/menu information found in search)\n"
                }
            } catch {
                context += "  Could not fetch restaurant information at this time\n"
            }
        }

        // Add news section (always included)
        context += "\n=== NEWS ===\n"

        // Fetch web news based on topic
        let newsQuery = specificNewsTopic ?? "news"
        do {
            let headlines = try await fetchWebNews(topic: newsQuery)
            if !headlines.isEmpty {
                context += "**Top Headlines on \(newsQuery.uppercased())**:\n\n"
                for (index, headline) in headlines.prefix(5).enumerated() {
                    context += "\(index + 1). \(headline)\n\n"
                }
            } else {
                context += "  No headlines found\n"
            }
        } catch {
            context += "  Could not fetch news at this time\n"
        }

        // Add notes section with smart relevance filtering
        context += "\n=== NOTES (Smart Filtered) ===\n"
        context += "NOTE: Notes are filtered by relevance to your query. Most relevant notes shown first.\n\n"

        if !notes.isEmpty {
            // Filter out calendar event notes and receipts
            let calendarEventTitles = Set(events.filter { $0.isFromCalendar }.map { $0.title.lowercased() })
            let actualNotes = notes.filter { note in
                let noteTitle = note.title.lowercased()
                let folderName = getCachedFolderName(for: note.folderId).lowercased()

                // Exclude if it's a calendar event note
                if calendarEventTitles.contains(noteTitle) {
                    return false
                }

                // Exclude if it's in a receipts folder
                if folderName.contains("receipt") {
                    return false
                }

                return true
            }

            // Filter notes by query relevance (smart multi-source search)
            let filteredNotes = !userQuery.isEmpty ?
                Array(filterNotesByRelevance(notes: actualNotes, query: userQuery).prefix(12)) :  // Limit to 12 most relevant
                Array(actualNotes.sorted { $0.dateModified > $1.dateModified }.prefix(10))

            if !filteredNotes.isEmpty {
                // Group filtered notes by folder
                let notesByFolder = Dictionary(grouping: filteredNotes) { note in
                    getCachedFolderName(for: note.folderId)
                }

                let sortedFolders = notesByFolder.keys.sorted()

                for folder in sortedFolders {
                    guard let folderNotes = notesByFolder[folder] else { continue }

                    context += "**\(folder)**:\n"

                    for note in folderNotes {
                        let lastModified = formatDate(note.dateModified)
                        context += "  • **\(note.title)** (Updated: \(lastModified))\n"

                        // Truncate note content to 500 chars to save tokens (full content for transaction lists)
                        let noteContent = note.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if !noteContent.isEmpty {
                            let truncatedContent = noteContent.count > 500 
                                ? String(noteContent.prefix(500)) + "... [truncated]" 
                                : noteContent
                            // Split into lines and add with proper indentation
                            let contentLines = truncatedContent.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                            for line in contentLines.prefix(20) {  // Limit to 20 lines max
                                let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespaces)
                                if !trimmedLine.isEmpty {
                                    context += "    \(trimmedLine)\n"
                                }
                            }
                        }

                        context += "\n"
                    }
                }

                // Show how many notes were filtered out
                if filteredNotes.count < actualNotes.count {
                    context += "\n(Showing \(filteredNotes.count) most relevant notes out of \(actualNotes.count) total)\n"
                }
            } else {
                context += "  No relevant notes found for your query. Try a broader search.\n"
            }
        } else {
            context += "  No notes found\n"
        }

        // Add emails section (always included)
        context += "\n=== EMAILS ===\n"

        if !emails.isEmpty {
            // Group emails by folder status
            let emailsByFolder = Dictionary(grouping: emails) { email in
                if email.labels.contains("SENT") {
                    return "Sent"
                } else if email.labels.contains("DRAFT") {
                    return "Drafts"
                } else if email.labels.contains("ARCHIVED") {
                    return "Archive"
                } else if email.labels.contains("IMPORTANT") {
                    return "Important"
                } else if email.labels.contains("STARRED") {
                    return "Starred"
                } else {
                    return "Inbox"
                }
            }

            let sortedFolders = emailsByFolder.keys.sorted { folder1, folder2 in
                if folder1 == "Inbox" { return true }
                if folder2 == "Inbox" { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderEmails = emailsByFolder[folder] else { continue }

                context += "\n**\(folder)** (\(folderEmails.count) emails):\n"

                // Show most recent emails first
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(6) {  // Reduced from 10 to 6
                    let formattedDate = mediumDateTimeFormatter.string(from: email.timestamp)

                    let senderDisplay = email.sender.displayName
                    let status = email.isRead ? "" : " [UNREAD]"
                    let important = email.isImportant ? " ★" : ""

                    context += "  • **\(email.subject)**\(status)\(important)\n"
                    context += "    From: \(senderDisplay) | Date: \(formattedDate)\n"

                    // Add AI summary if available
                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    Summary: \(aiSummary)\n"
                    }

                    // Add brief content preview
                    if let body = email.body, !body.isEmpty {
                        let bodyPreview = String(body.prefix(100))  // Reduced from 150 to 100 chars
                        context += "    Preview: \(bodyPreview)...\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 6 {
                    context += "  ... and \(folderEmails.count - 6) more emails in this folder\n"
                }
            }
        } else {
            context += "  No emails found\n"
        }

        // Add custom email folders
        if !customEmailFolders.isEmpty {
            context += "\n**CUSTOM FOLDERS** (\(customEmailFolders.count) folders):\n"

            for folder in customEmailFolders.sorted(by: { $0.name < $1.name }) {
                guard let folderEmails = savedEmailsByFolder[folder.id], !folderEmails.isEmpty else {
                    context += "\n**\(folder.name)** (0 emails)\n"
                    continue
                }

                context += "\n**\(folder.name)** (\(folderEmails.count) emails):\n"

                // Show most recent emails first
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(6) {  // Reduced from 10 to 6
                    let formattedDate = mediumDateTimeFormatter.string(from: email.timestamp)

                    let senderDisplay = email.senderName ?? email.senderEmail
                    let recipientDisplay = email.recipients.joined(separator: ", ")

                    context += "  • **\(email.subject)**\n"
                    context += "    From: \(senderDisplay) | To: \(recipientDisplay) | Date: \(formattedDate)\n"

                    // Add AI summary if available
                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    Summary: \(aiSummary)\n"
                    }

                    // Add brief content preview
                    if let body = email.body, !body.isEmpty {
                        let bodyPreview = String(body.prefix(100))  // Reduced from 150 to 100 chars
                        context += "    Preview: \(bodyPreview)...\n"
                    }

                    // Show attachments if any
                    if !email.attachments.isEmpty {
                        context += "    Attachments: \(email.attachments.map { $0.fileName }.joined(separator: ", "))\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 10 {
                    context += "  ... and \(folderEmails.count - 10) more emails in this folder\n"
                }
            }
        }

        // Add USER BEHAVIOR PATTERNS section
        context += "\n=== USER BEHAVIOR PATTERNS ===\n"
        context += "Analysis of your spending, event, and location patterns:\n\n"

        // Build metadata for pattern analysis
        let patternCalendar = Calendar.current
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM yyyy"

        let metadata = AppDataMetadata(
            receipts: receipts.map { receipt in
                let dayOfWeek = patternCalendar.component(Calendar.Component.weekday, from: receipt.date)
                let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

                return ReceiptMetadata(
                    id: UUID(), // Generate ID for receipt
                    merchant: receipt.title,
                    amount: receipt.amount,
                    date: receipt.date,
                    category: receipt.category,
                    preview: receipt.title,
                    monthYear: monthYearFormatter.string(from: receipt.date),
                    dayOfWeek: dayNames[dayOfWeek - 1]
                )
            },
            events: events.map { event in
                EventMetadata(
                    id: event.id,
                    title: event.title,
                    date: event.targetDate ?? event.scheduledTime ?? event.completedDate,
                    time: event.scheduledTime,
                    endTime: event.endTime,
                    description: event.description,
                    location: nil,
                    reminder: nil,
                    isRecurring: event.isRecurring,
                    recurrencePattern: event.recurrenceFrequency?.rawValue,
                    isCompleted: event.isCompleted,
                    completedDates: event.completedDates.isEmpty ? nil : event.completedDates,
                    eventType: event.tagId.map { getCategoryName(for: $0) },
                    priority: nil
                )
            },
            locations: locations.map { location in
                let stats = LocationVisitAnalytics.shared.visitStats[location.id]
                return LocationMetadata(
                    id: location.id,
                    name: location.name,
                    customName: location.customName,
                    folderName: location.category,
                    address: location.address,
                    city: location.city,
                    province: location.province,
                    country: location.country,
                    folderCity: nil,
                    folderProvince: nil,
                    folderCountry: nil,
                    userRating: location.userRating,
                    notes: location.userNotes,
                    cuisine: location.userCuisine,
                    dateCreated: location.dateCreated,
                    dateModified: location.dateModified,
                    visitCount: stats?.totalVisits,
                    totalVisitDuration: nil,
                    averageVisitDuration: stats?.averageDurationMinutes != nil ? TimeInterval(stats!.averageDurationMinutes * 60) : nil,
                    lastVisited: stats?.lastVisitDate,
                    isFrequent: stats?.totalVisits != nil ? (stats!.totalVisits > 1) : nil,
                    peakVisitTimes: nil,
                    mostVisitedDays: nil,
                    locationMemories: nil, // Location memories are loaded asynchronously in MetadataBuilderService
                    recentVisitNotes: nil // Visit notes are loaded asynchronously in MetadataBuilderService
                )
            },
            notes: [],
            emails: [],
            recurringExpenses: []
        )

        let patterns = UserPatternAnalysisService.analyzeUserPatterns(from: metadata)

        // Top expense categories
        if !patterns.topExpenseCategories.isEmpty {
            context += "**Top Spending Categories:**\n"
            for categorySpending in patterns.topExpenseCategories {
                context += "  • \(categorySpending.category): $\(String(format: "%.2f", categorySpending.totalAmount)) (\(String(format: "%.1f", categorySpending.percentage))% of total, \(categorySpending.transactionCount) transactions)\n"
            }
            context += "\n"
        }

        // Spending trends
        context += "**Spending Trends:**\n"
        context += "  • Average monthly spending: $\(String(format: "%.2f", patterns.averageMonthlySpending))\n"
        context += "  • Trend: \(patterns.spendingTrend.capitalized)\n"
        context += "  • Average transaction amount: $\(String(format: "%.2f", patterns.averageExpenseAmount))\n"
        context += "  • Total transactions: \(patterns.totalTransactions)\n\n"

        // Event patterns
        if !patterns.mostFrequentEvents.isEmpty {
            context += "**Most Frequent Events:**\n"
            for eventFreq in patterns.mostFrequentEvents {
                let avgDays = eventFreq.averageDaysApart.map { String(format: "%.0f", $0) } ?? "N/A"
                context += "  • \(eventFreq.title): \(String(format: "%.1f", eventFreq.timesPerMonth)) times/month (avg \(avgDays) days apart)\n"
            }
            context += "\n"
        }

        // Location patterns
        if !patterns.mostVisitedLocations.isEmpty {
            context += "**Most Visited Locations:**\n"
            for locationVisit in patterns.mostVisitedLocations {
                let lastVisitStr = locationVisit.lastVisited.map { formatDate($0) } ?? "Unknown"
                context += "  • \(locationVisit.name): \(locationVisit.visitCount) visits (last: \(lastVisitStr))\n"
            }
            context += "\n"
        }

        // Time patterns
        context += "**Activity Patterns:**\n"
        context += "  • Most active time of day: \(patterns.mostActiveTimeOfDay.capitalized)\n"
        context += "  • Average events per week: \(String(format: "%.1f", patterns.averageEventsPerWeek))\n"
        if !patterns.busyDays.isEmpty {
            context += "  • Busiest days: \(patterns.busyDays.joined(separator: ", "))\n"
        }
        if !patterns.favoriteRestaurantTypes.isEmpty {
            context += "  • Favorite cuisines: \(patterns.favoriteRestaurantTypes.joined(separator: ", "))\n"
        }
        context += "\n"

        // Add HABIT TRACKING & STREAKS section
        context += "\n=== HABIT TRACKING & STREAKS ===\n"
        context += "Location visit streaks and consistency patterns:\n\n"

        // Check for streaks at top locations
        var hasStreaks = false
        for location in locations.prefix(10) {
            if let stats = LocationVisitAnalytics.shared.visitStats[location.id] {
                // Estimate streak potential based on recent visit patterns
                if stats.thisMonthVisits >= 3 {
                    context += "**\(location.displayName)**:\n"
                    context += "  • This month: \(stats.thisMonthVisits) visits (consistent!)\n"

                    if let peakDay = stats.mostCommonDayOfWeek, let peakTime = stats.mostCommonTimeOfDay {
                        context += "  • Habit pattern: Usually visit on \(peakDay)s during \(peakTime)\n"
                    }

                    if stats.thisMonthVisits >= 7 {
                        context += "  • 🔥 Strong habit detected - visiting regularly!\n"
                    }

                    context += "\n"
                    hasStreaks = true
                }
            }
        }

        if !hasStreaks {
            context += "  No strong habit streaks detected yet. Visit locations consistently to build habits!\n"
        }

        // Add TAGS & CATEGORIES section
        context += "\n=== TAGS & CATEGORIES ===\n"
        context += "Event tags/categories and their distribution:\n\n"

        let allTags = tagManager.tags
        if !allTags.isEmpty {
            // Count events per tag
            var tagCounts: [String: Int] = [:]
            for event in events {
                if let tagId = event.tagId {
                    let tagName = getCategoryName(for: tagId)
                    tagCounts[tagName, default: 0] += 1
                }
            }

            // Sort by count
            let sortedTags = tagCounts.sorted { $0.value > $1.value }

            context += "**Available Tags:** \(allTags.map { $0.name }.joined(separator: ", "))\n\n"

            if !sortedTags.isEmpty {
                context += "**Tag Distribution:**\n"
                for (tagName, count) in sortedTags {
                    let percentage = events.isEmpty ? 0.0 : (Double(count) / Double(events.count)) * 100
                    context += "  • \(tagName): \(count) events (\(String(format: "%.1f", percentage))%)\n"
                }
            }
        } else {
            context += "  No tags/categories created yet\n"
        }
        context += "\n"

        // Add MOOD & VISIT FEEDBACK section
        context += "\n=== LOCATION SATISFACTION & FEEDBACK ===\n"
        context += "User ratings and feedback on location visits:\n\n"

        let overallFeedback = await visitFeedbackService.getOverallStats()

        if overallFeedback.total > 0 {
            context += "**Overall Visit Accuracy:**\n"
            context += "  • Total feedback submissions: \(overallFeedback.total)\n"
            context += "  • Visit tracking accuracy: \(String(format: "%.1f", overallFeedback.accuracy * 100))%\n"

            if !overallFeedback.byType.isEmpty {
                context += "\n**Feedback Breakdown:**\n"
                for (feedbackType, count) in overallFeedback.byType.sorted(by: { $0.value > $1.value }) {
                    context += "  • \(feedbackType.displayName): \(count) times\n"
                }
            }
        } else {
            context += "  No visit feedback submitted yet\n"
        }
        context += "\n"

        // Add ATTACHMENTS & DOCUMENTS section
        context += "\n=== ATTACHMENTS & DOCUMENTS ===\n"
        context += "Files attached to notes and their extracted content:\n\n"

        let allAttachments = attachmentService.attachments
        if !allAttachments.isEmpty {
            context += "**Total Attachments:** \(allAttachments.count) files\n\n"

            // Group by document type
            let attachmentsByType = Dictionary(grouping: allAttachments) { attachment in
                attachment.documentType ?? attachment.fileType
            }

            for (type, attachments) in attachmentsByType.sorted(by: { $0.key < $1.key }) {
                context += "**\(type.capitalized)** (\(attachments.count) files):\n"

                for attachment in attachments.prefix(5) {
                    context += "  • \(attachment.fileName) (\(ByteCountFormatter.string(fromByteCount: Int64(attachment.fileSize), countStyle: .file)))\n"

                    // Include extracted data if available
                    if let extracted = attachmentService.extractedDataCache[attachment.id] {
                        if let summary = extracted.extractedFields["summary"] as? String {
                            let preview = summary.count > 150 ? String(summary.prefix(150)) + "..." : summary
                            context += "    Content: \(preview)\n"
                        }
                    }
                }

                if attachments.count > 5 {
                    context += "  ... and \(attachments.count - 5) more files\n"
                }
                context += "\n"
            }
        } else {
            context += "  No file attachments in notes\n"
        }

        // Add CROSS-DATA RELATIONSHIPS section
        context += "\n=== CROSS-DATA INSIGHTS ===\n"
        context += "Connections between receipts, locations, events, and emails:\n\n"

        // Link receipts to locations (improved semantic matching)
        var receiptLocationLinks: [(receipt: ReceiptStat, location: SavedPlace)] = []
        for receipt in receipts.prefix(20) {
            for location in locations {
                let receiptTitle = receipt.title.lowercased()
                let locationName = location.displayName.lowercased()

                // Exact match
                if receiptTitle.contains(locationName) || locationName.contains(receiptTitle) {
                    receiptLocationLinks.append((receipt, location))
                    break
                }

                // Fuzzy match: check if words overlap
                let receiptWords = Set(receiptTitle.split(separator: " ").map { String($0) })
                let locationWords = Set(locationName.split(separator: " ").map { String($0) })
                let commonWords = receiptWords.intersection(locationWords)
                if !commonWords.isEmpty && commonWords.count >= min(receiptWords.count, locationWords.count) / 2 {
                    receiptLocationLinks.append((receipt, location))
                    break
                }

                // Category matching (e.g., "Coffee Shop" receipt → Starbucks location)
                let receiptCategory = receipt.category.lowercased()
                let locationCategory = location.category.lowercased()
                if !receiptCategory.isEmpty && !locationCategory.isEmpty &&
                   (receiptCategory.contains(locationCategory) || locationCategory.contains(receiptCategory)) {
                    receiptLocationLinks.append((receipt, location))
                    break
                }
            }
        }

        if !receiptLocationLinks.isEmpty {
            context += "**Receipts Linked to Locations:**\n"
            for (receipt, location) in receiptLocationLinks.prefix(10) {
                context += "  • $\(String(format: "%.2f", receipt.amount)) at \(location.displayName) on \(formatDate(receipt.date))\n"
            }
            if receiptLocationLinks.count > 10 {
                context += "  ... and \(receiptLocationLinks.count - 10) more links\n"
            }
            context += "\n"
        }

        // Link events to location visits (by date proximity)
        var eventLocationLinks: [(event: TaskItem, location: SavedPlace)] = []
        for event in events.filter({ $0.isCompleted }).prefix(20) {
            guard let eventDate = event.completedDate ?? event.targetDate else { continue }

            for location in locations {
                if let stats = LocationVisitAnalytics.shared.visitStats[location.id],
                   let lastVisit = stats.lastVisitDate {
                    // Check if visit happened within 2 hours of event
                    let timeDiff = abs(lastVisit.timeIntervalSince(eventDate))
                    if timeDiff < 7200 { // 2 hours
                        eventLocationLinks.append((event, location))
                        break
                    }
                }
            }
        }

        if !eventLocationLinks.isEmpty {
            context += "**Events Linked to Location Visits:**\n"
            for (event, location) in eventLocationLinks.prefix(10) {
                context += "  • \(event.title) at \(location.displayName)\n"
            }
            if eventLocationLinks.count > 10 {
                context += "  ... and \(eventLocationLinks.count - 10) more links\n"
            }
            context += "\n"
        }

        if receiptLocationLinks.isEmpty && eventLocationLinks.isEmpty {
            context += "  No significant cross-data relationships detected\n\n"
        }

        // Restore original events and receipts
        self.events = originalEvents
        self.receipts = originalReceipts

        return context
    }
    */

    // DEPRECATED: buildContextPrompt() - Never called, use VectorContextBuilder instead
    /*
    func buildContextPrompt() async -> String {
        return await buildContextPromptInternal()
    }

    private func buildContextPromptInternal() async -> String {
        // Only refresh if cache is invalid (OPTIMIZATION: Skip refresh if data is fresh)
        if !isCacheValid {
            await refresh()
        } else {
            print("✅ Using cached data (valid for \(Int(cacheValidityDuration - Date().timeIntervalSince(lastRefreshTime))) more seconds)")
        }

        // OPTIMIZATION: Skip geofence stats when no specific query (saves time)
        // Location stats are only fetched in buildContextPrompt(forQuery:) when needed
        print("⚡ Skipping visit stats - no specific query")

        var context = ""

        // Current date context - using reusable formatters
        context += "=== CURRENT DATE ===\n"
        context += "Today is: \(dayFormatter.string(from: currentDate)), \(dateFormatter.string(from: currentDate))\n"
        let utcOffset2 = TimeZone.current.secondsFromGMT() / 3600
        let utcSign2 = utcOffset2 >= 0 ? "+" : ""
        context += "Timezone: \(TimeZone.current.identifier) (UTC\(utcSign2)\(utcOffset2))\n\n"

        // Current location context
        let locationService = LocationService.shared
        if let currentLocation = locationService.currentLocation {
            context += "=== CURRENT LOCATION ===\n"
            context += "Location: \(locationService.locationName)\n"
            context += "Coordinates: \(String(format: "%.6f", currentLocation.coordinate.latitude)), \(String(format: "%.6f", currentLocation.coordinate.longitude))\n"
            context += "Accuracy: \(Int(currentLocation.horizontalAccuracy))m\n\n"
        } else {
            context += "=== CURRENT LOCATION ===\n"
            context += "Location: Not available (location services may be disabled or location not yet determined)\n\n"
        }

        // Data summary
        // Fetch recurring expenses count
        var recurringCount = 0
        do {
            let activeRecurring = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
            recurringCount = activeRecurring.count
        } catch {
            print("⚠️ Could not fetch recurring expenses count: \(error)")
        }

        context += "=== DATA SUMMARY ===\n"
        context += "Total Events: \(events.count)\n"
        context += "Total Receipts: \(receipts.count)\n"
        context += "Total Recurring Expenses: \(recurringCount)\n"
        context += "Total Notes: \(notes.count)\n"
        context += "Total Emails: \(emails.count)\n"
        context += "Total Locations: \(locations.count)\n\n"

        // Events detail - Comprehensive with categories, temporal organization, and all-day status
        context += "=== EVENTS & CALENDAR ===\n"
        if !events.isEmpty {
            let calendar = Calendar.current

            // Organize events by temporal proximity
            var today: [TaskItem] = []
            var tomorrow: [TaskItem] = []
            var thisWeek: [TaskItem] = []
            var upcoming: [TaskItem] = []
            var past: [TaskItem] = []

            for event in events {
                if event.isRecurring {
                    // For recurring events, check which sections they appear in
                    // A daily event might appear in Today, Tomorrow, AND This Week, etc.

                    let todayDate = currentDate
                    let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                    let dayAfterTomorrowDate = calendar.date(byAdding: .day, value: 2, to: currentDate)!

                    if shouldEventOccurOn(event, date: todayDate) {
                        today.append(event)
                    }

                    if shouldEventOccurOn(event, date: tomorrowDate) {
                        tomorrow.append(event)
                    }

                    if shouldEventOccurOn(event, date: dayAfterTomorrowDate) {
                        thisWeek.append(event)
                    } else {
                        // If it doesn't occur in the next 2 days, check if it occurs within the week
                        var hasUpcomingOccurrence = false
                        for daysAhead in 3...7 {
                            if let checkDate = calendar.date(byAdding: .day, value: daysAhead, to: currentDate),
                               shouldEventOccurOn(event, date: checkDate) {
                                thisWeek.append(event)
                                hasUpcomingOccurrence = true
                                break
                            }
                        }

                        // If still no occurrence found, check further ahead
                        if !hasUpcomingOccurrence {
                            if let nextDate = getNextOccurrenceDate(for: event, after: calendar.date(byAdding: .day, value: 7, to: currentDate)!) {
                                upcoming.append(event)
                            }
                        }
                    }
                } else {
                    // For non-recurring events, use our custom date comparison helpers
                    let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate

                    // Use our custom date comparison helpers (based on currentDate, not system time)
                    if isDateToday(eventDate) {
                        today.append(event)
                    } else if isDateTomorrow(eventDate) {
                        tomorrow.append(event)
                    } else if isDateThisWeek(eventDate) && !isDateToday(eventDate) && !isDateTomorrow(eventDate) {
                        thisWeek.append(event)
                    } else if eventDate > currentDate {
                        upcoming.append(event)
                    } else {
                        past.append(event)
                    }
                }
            }

            // TODAY
            if !today.isEmpty {
                context += "\n**TODAY** (\(today.count) events):\n"
                for event in today.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    
                    // Correctly check completion for recurring events on *this specific day*
                    let isCompleted = event.isRecurring ? event.isCompletedOn(date: currentDate) : event.isCompleted
                    let status = isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // TOMORROW
            if !tomorrow.isEmpty {
                context += "\n**TOMORROW** (\(tomorrow.count) events):\n"
                for event in tomorrow.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    
                    // Correctly check completion for recurring events on *tomorrow*
                    let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                    let isCompleted = event.isRecurring ? event.isCompletedOn(date: tomorrowDate) : event.isCompleted
                    let status = isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"

                    if let description = event.description, !description.isEmpty {
                        context += "    \(description)\n"
                    }
                }
            }

            // THIS WEEK (next 3-7 days)
            if !thisWeek.isEmpty {
                context += "\n**THIS WEEK** (\(thisWeek.count) events):\n"
                for event in thisWeek.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week) - LIMITED to first 5 for context size
            if !upcoming.isEmpty {
                let upcomingToShow = Array(upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }).prefix(5))
                context += "\n**UPCOMING** (\(upcomingToShow.count) of \(upcoming.count) events):\n"
                for event in upcomingToShow {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = getRecurringInfo(event)

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
                }
                if upcoming.count > 10 {
                    context += "  ... and \(upcoming.count - 10) more upcoming events\n"
                }
            }

            // RECURRING EVENTS SUMMARY with next occurrence dates
            let recurringEvents = events.filter { $0.isRecurring }
            if !recurringEvents.isEmpty {
                context += "\n**RECURRING EVENTS SUMMARY** (\(recurringEvents.count) recurring):\n"
                context += "**IMPORTANT: For recurring events (especially birthdays/anniversaries), use the 'Next occurrence' date below to answer 'when' questions.**\n"
                
                for event in recurringEvents.prefix(15) {
                    let categoryName = getCategoryName(for: event.tagId)
                    
                    // Frequency info
                    var frequencyStr = "Unknown"
                    if let freq = event.recurrenceFrequency {
                        switch freq {
                        case .daily: frequencyStr = "Daily"
                        case .weekly: frequencyStr = "Weekly"
                        case .biweekly: frequencyStr = "Bi-weekly"
                        case .monthly: frequencyStr = "Monthly"
                        case .yearly: frequencyStr = "Yearly"
                        case .custom: frequencyStr = "Custom"
                        }
                    }
                    
                    // Next occurrence - CRITICAL for answering "when is X" questions
                    var nextOccurrenceStr = "Unknown"
                    if let nextDate = getNextOccurrenceDate(for: event) {
                        nextOccurrenceStr = dateFormatter.string(from: nextDate)
                    } else if let targetDate = event.targetDate {
                        nextOccurrenceStr = dateFormatter.string(from: targetDate) + " (original date)"
                    }
                    
                    // Original/anchor date - for reference
                    let anchorDate = event.targetDate ?? event.createdAt
                    let anchorStr = dateFormatter.string(from: anchorDate)
                    
                    context += "  • \(event.title)\n"
                    context += "    Category: \(categoryName) | Frequency: \(frequencyStr)\n"
                    context += "    Original date: \(anchorStr) | **Next occurrence: \(nextOccurrenceStr)**\n"
                    context += "    Completions: \(event.completedDates.count) total\n"
                }
                if recurringEvents.count > 15 {
                    context += "  ... and \(recurringEvents.count - 15) more recurring events\n"
                }
            }

            // LAST WEEK EVENTS
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: currentDate)!
            let lastWeekEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate >= sevenDaysAgo && eventDate < currentDate
            }
            if !lastWeekEvents.isEmpty {
                context += "\n**LAST WEEK** (\(lastWeekEvents.count) events):\n"
                for event in lastWeekEvents.sorted(by: { ($0.targetDate ?? $0.completedDate ?? Date.distantPast) > ($1.targetDate ?? $1.completedDate ?? Date.distantPast) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
            }

            // OLDER PAST EVENTS
            let olderPastEvents = past.filter { event in
                let eventDate = event.targetDate ?? event.completedDate ?? currentDate
                return eventDate < sevenDaysAgo
            }
            if !olderPastEvents.isEmpty {
                context += "\n**PAST EVENTS** (older than 1 week, showing last 5):\n"
                for event in olderPastEvents.suffix(5).reversed() {
                    let categoryName = getCategoryName(for: event.tagId)
                    let dateStr = formatDate(event.targetDate ?? event.completedDate ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"

                    context += "  \(status): \(event.title) - \(categoryName) - \(dateStr)\n"
                }
                if olderPastEvents.count > 5 {
                    context += "  ... and \(olderPastEvents.count - 5) more older past events\n"
                }
            }
        } else {
            context += "  No events\n"
        }

        // Receipts detail - Group all receipts by month and show with real categorization
        context += "\n=== RECEIPTS & EXPENSES ===\n"
        if !receipts.isEmpty {
            // Group all receipts by month dynamically
            let receiptsByMonth = Dictionary(grouping: receipts) { receipt in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: receipt.date)
            }

            // Get current month for detection
            let calendar = Calendar.current
            let currentMonthFormatter = DateFormatter()
            currentMonthFormatter.dateFormat = "MMMM yyyy"
            let currentMonthStr = currentMonthFormatter.string(from: currentDate)

            // Sort months: current month first, then others by recency
            let sortedMonths = receiptsByMonth.keys.sorted { month1, month2 in
                if month1 == currentMonthStr { return true }
                if month2 == currentMonthStr { return false }
                return month1 > month2  // Most recent first
            }

            // Show ALL months with receipts (not just 7) to ensure complete data
            for (index, month) in sortedMonths.enumerated() {
                guard let items = receiptsByMonth[month] else { continue }

                let total = items.reduce(0.0) { $0 + $1.amount }
                let isCurrentMonth = (month == currentMonthStr)

                context += "\n**\(month)**\(isCurrentMonth ? " (Current Month)" : ""): \(items.count) receipts, Total: $\(String(format: "%.2f", total))\n"

                // Get real category breakdown for this month using ReceiptCategorizationService
                let categoryBreakdown = await categorizationService.getCategoryBreakdown(for: items)

                // Show categories and amounts
                for (category, receiptsInCategory) in categoryBreakdown.categoryReceipts.sorted(by: { $0.key < $1.key }) {
                    let categoryTotal = receiptsInCategory.reduce(0.0) { $0 + $1.amount }
                    context += "  **\(category)**: $\(String(format: "%.2f", categoryTotal)) (\(receiptsInCategory.count) items)\n"

                    // Show all items for every month (not just current) to ensure complete data
                    for receipt in receiptsInCategory.sorted(by: { $0.date > $1.date }) {
                        context += "    • \(receipt.title): $\(String(format: "%.2f", receipt.amount)) - \(formatDate(receipt.date))\n"
                    }
                }
            }
        } else {
            context += "  No receipts\n"
        }

        // Recurring Expenses - Detailed breakdown with all information
        context += "\n=== RECURRING EXPENSES (SUBSCRIPTIONS & BILLS) ===\n"
        do {
            let activeRecurring = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()

            if !activeRecurring.isEmpty {
                // Calculate totals
                let totalMonthly = activeRecurring.reduce(0.0) { total, expense in
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    switch expense.frequency {
                    case .daily:
                        return total + (amount * 30)
                    case .weekly:
                        return total + (amount * 4.3)
                    case .biweekly:
                        return total + (amount * 2.15)
                    case .monthly:
                        return total + amount
                    case .yearly:
                        return total + (amount / 12)
                    case .custom:
                        // Custom frequency typically means specific days per week
                        // Using weekly multiplier (4.3) as a reasonable approximation
                        return total + (amount * 4.3)
                    }
                }

                let totalYearly = activeRecurring.reduce(0.0) { total, expense in
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    switch expense.frequency {
                    case .daily:
                        return total + (amount * 365)
                    case .weekly:
                        return total + (amount * 52)
                    case .biweekly:
                        return total + (amount * 26)
                    case .monthly:
                        return total + (amount * 12)
                    case .yearly:
                        return total + amount
                    case .custom:
                        // Custom frequency typically means specific days per week
                        // Using weekly multiplier (52) as a reasonable approximation
                        return total + (amount * 52)
                    }
                }

                context += "**Monthly Total: $\(String(format: "%.2f", totalMonthly))** | **Yearly Total: $\(String(format: "%.2f", totalYearly))**\n"
                context += "**Active Subscriptions: \(activeRecurring.count)**\n\n"

                // Sort by next occurrence
                for expense in activeRecurring.sorted(by: { $0.nextOccurrence < $1.nextOccurrence }) {
                    let amount = Double(truncating: expense.amount as NSDecimalNumber)
                    context += "• **\(expense.title)**\n"
                    context += "    Amount: \(expense.formattedAmount) | Frequency: \(expense.frequency.rawValue.capitalized)\n"
                    context += "    Next: \(formatDate(expense.nextOccurrence)) | Started: \(formatDate(expense.startDate))\n"

                    if let endDate = expense.endDate {
                        context += "    Ends: \(formatDate(endDate))\n"
                    }

                    if let description = expense.description, !description.isEmpty {
                        context += "    Notes: \(description)\n"
                    }

                    if let category = expense.category, !category.isEmpty {
                        context += "    Category: \(category)\n"
                    }

                    context += "    Status: \(expense.isActive ? "✅ Active" : "⏸️ Paused")\n"
                    context += "\n"
                }
            } else {
                context += "  No active recurring expenses\n"
            }
        } catch {
            context += "  Error fetching recurring expenses: \(error.localizedDescription)\n"
        }

        // Emails detail - Comprehensive with folder organization, metadata, and full content
        context += "\n=== EMAILS & MESSAGES ===\n"
        if !emails.isEmpty {
            // Group emails by labels (folders)
            let emailsByFolder = Dictionary(grouping: emails) { email in
                // Use labels to determine folder, default to "Inbox"
                if email.labels.contains("SENT") {
                    return "Sent"
                } else if email.labels.contains("DRAFT") {
                    return "Drafts"
                } else if email.labels.contains("ARCHIVED") {
                    return "Archive"
                } else if email.labels.contains("IMPORTANT") {
                    return "Important"
                } else if email.labels.contains("STARRED") {
                    return "Starred"
                } else {
                    return "Inbox"
                }
            }

            // Sort folders with Inbox first
            let sortedFolders = emailsByFolder.keys.sorted { folder1, folder2 in
                if folder1 == "Inbox" { return true }
                if folder2 == "Inbox" { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderEmails = emailsByFolder[folder] else { continue }

                context += "\n**\(folder)** (\(folderEmails.count) emails):\n"

                // Show most recent emails first, max 20 per folder
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20) {
                    let formattedDate = mediumDateTimeFormatter.string(from: email.timestamp)

                    let senderDisplay = email.sender.displayName
                    let recipientDisplay = email.recipients.map { $0.displayName }.joined(separator: ", ")

                    context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                    // Add email metadata
                    context += "    Status: \(email.isRead ? "Read" : "Unread")\(email.isImportant ? ", Important" : "")\n"

                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    AI Summary: \(aiSummary)\n"
                    }

                    // Add full email body/content
                    if let body = email.body, !body.isEmpty {
                        context += "    Content:\n"
                        let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                        for line in bodyLines.prefix(50) {  // Show up to 50 lines of email content
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                context += "      \(trimmedLine)\n"
                            }
                        }
                        if bodyLines.count > 50 {
                            context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                        }
                    }

                    // Add attachments if present
                    if email.hasAttachments && !email.attachments.isEmpty {
                        context += "    Attachments: \(email.attachments.map { $0.name }.joined(separator: ", "))\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 20 {
                    context += "  ... and \(folderEmails.count - 20) more emails in this folder\n"
                }
            }

            context += "**Total Standard Folders Emails**: \(emails.count)\n"

            // CUSTOM EMAIL FOLDERS
            if !customEmailFolders.isEmpty {
                context += "\n**CUSTOM EMAIL FOLDERS** (\(customEmailFolders.count) folders):\n"

                for folder in customEmailFolders {
                    guard let folderEmails = savedEmailsByFolder[folder.id], !folderEmails.isEmpty else {
                        context += "\n**\(folder.name)** (0 emails)\n"
                        continue
                    }

                    context += "\n**\(folder.name)** (\(folderEmails.count) emails):\n"

                    // Show most recent emails first, max 15 per custom folder
                    for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(15) {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateStyle = .medium
                        dateFormatter.timeStyle = .short
                        let formattedDate = dateFormatter.string(from: email.timestamp)

                        let senderDisplay = email.senderName ?? email.senderEmail
                        let recipientDisplay = email.recipients.joined(separator: ", ")

                        context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                        // Add email metadata
                        if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                            context += "    AI Summary: \(aiSummary)\n"
                        }

                        // Add full email body/content
                        if let body = email.body, !body.isEmpty {
                            context += "    Content:\n"
                            let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                            for line in bodyLines.prefix(50) {  // Show up to 50 lines of email content
                                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                if !trimmedLine.isEmpty {
                                    context += "      \(trimmedLine)\n"
                                }
                            }
                            if bodyLines.count > 50 {
                                context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                            }
                        }

                        // Add attachments if present
                        if !email.attachments.isEmpty {
                            context += "    Attachments: \(email.attachments.map { $0.fileName }.joined(separator: ", "))\n"
                        }

                        context += "\n"
                    }

                    if folderEmails.count > 15 {
                        context += "  ... and \(folderEmails.count - 15) more emails in this folder\n"
                    }
                }
            }

            let totalEmails = emails.count + (savedEmailsByFolder.values.reduce(0) { $0 + $1.count })
            context += "\n**Total Emails**: \(totalEmails)\n"
        } else if !customEmailFolders.isEmpty {
            // Show custom folders even if no standard emails
            context += "\n**CUSTOM EMAIL FOLDERS** (\(customEmailFolders.count) folders):\n"

            for folder in customEmailFolders {
                guard let folderEmails = savedEmailsByFolder[folder.id] else {
                    context += "\n**\(folder.name)** (0 emails)\n"
                    continue
                }

                context += "\n**\(folder.name)** (\(folderEmails.count) emails):\n"

                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(15) {
                    let formattedDate = mediumDateTimeFormatter.string(from: email.timestamp)

                    let senderDisplay = email.senderName ?? email.senderEmail
                    let recipientDisplay = email.recipients.joined(separator: ", ")

                    context += "  • **\(email.subject)** - From: \(senderDisplay) - To: \(recipientDisplay) - Date: \(formattedDate)\n"

                    if let aiSummary = email.aiSummary, !aiSummary.isEmpty {
                        context += "    AI Summary: \(aiSummary)\n"
                    }

                    if let body = email.body, !body.isEmpty {
                        context += "    Content:\n"
                        let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                        for line in bodyLines.prefix(50) {
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                context += "      \(trimmedLine)\n"
                            }
                        }
                        if bodyLines.count > 50 {
                            context += "      ... (email continues - \(bodyLines.count - 50) more lines)\n"
                        }
                    }

                    if !email.attachments.isEmpty {
                        context += "    Attachments: \(email.attachments.map { $0.fileName }.joined(separator: ", "))\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 15 {
                    context += "  ... and \(folderEmails.count - 15) more emails in this folder\n"
                }
            }

            context += "\n**Total Custom Emails**: \(savedEmailsByFolder.values.reduce(0) { $0 + $1.count })\n"
        } else {
            context += "  No emails or custom folders\n"
        }

        // Notes detail - Comprehensive with folder, dates, and full content
        context += "\n=== NOTES ===\n"
        if !notes.isEmpty {
            // Filter out calendar event notes and receipts
            let calendarEventTitles = Set(events.filter { $0.isFromCalendar }.map { $0.title.lowercased() })
            let actualNotes = notes.filter { note in
                let noteTitle = note.title.lowercased()
                let folderName = getCachedFolderName(for: note.folderId).lowercased()

                // Exclude if it's a calendar event note
                if calendarEventTitles.contains(noteTitle) {
                    return false
                }

                // Exclude if it's in a receipts folder
                if folderName.contains("receipt") {
                    return false
                }

                return true
            }

            // Group notes by folder
            let notesByFolder = Dictionary(grouping: actualNotes) { note in
                getCachedFolderName(for: note.folderId)
            }

            // Sort folders alphabetically
            let sortedFolders = notesByFolder.keys.sorted()

            for folder in sortedFolders {
                guard let folderNotes = notesByFolder[folder] else { continue }

                let folderLabel = folder == "Notes" ? "**Uncategorized Notes**" : "**\(folder)**"
                context += "\n\(folderLabel) (\(folderNotes.count) notes):\n"

                // Show most recently modified notes first, max 10 per folder
                for note in folderNotes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(10) {
                    let lastModified = formatDate(note.dateModified)
                    context += "  • **\(note.title)** (Updated: \(lastModified))\n"

                    // Include note content preview - limited to save tokens
                    let contentLines = note.content.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                    let lineLimit = 30  // Reduced from 1000 to 30 lines per note

                    for line in contentLines.prefix(lineLimit) {
                        let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespaces)
                        if !trimmedLine.isEmpty {
                            context += "    \(trimmedLine)\n"
                        }
                    }

                    if contentLines.count > lineLimit {
                        context += "    ... (note continues - \(contentLines.count - lineLimit) more lines)\n"
                    }
                    context += "\n"
                }

                if folderNotes.count > 10 {
                    context += "  ... and \(folderNotes.count - 10) more notes in this folder\n"
                }
            }

            context += "\n**Total Notes**: \(actualNotes.count)\n"
        } else {
            context += "  No notes\n"
        }

        // Locations detail
        context += "\n=== LOCATIONS ===\n"
        if !locations.isEmpty {
            for location in locations.prefix(15) {
                let rating = location.userRating.map { "⭐ \($0)/10" } ?? "No rating"
                context += "  • \(location.displayName) - \(location.address) (\(rating))\n"

                // Include geofence visit data if available
                if let stats = LocationVisitAnalytics.shared.visitStats[location.id] {
                    context += "    📊 \(stats.totalVisits) visits"
                    if let peakTime = stats.mostCommonTimeOfDay {
                        context += " | Peak: \(peakTime)"
                    }
                    context += "\n"
                }
            }
            if locations.count > 15 {
                context += "  ... and \(locations.count - 15) more locations\n"
            }
        } else {
            context += "  No saved locations\n"
        }

        context += "\n"
        return context
    }

    /// Build detailed context with full data (send when needed)
    func buildDetailedDataContext() -> String {
        var context = ""

        // Full events JSON
        context += "=== COMPLETE EVENTS DATA ===\n"
        let eventData = events.map { event -> [String: Any] in
            [
                "id": event.id,
                "title": event.title,
                "targetDate": event.targetDate.map { formatDate($0) } ?? NSNull(),
                "isCompleted": event.isCompleted,
                "completedDates": event.completedDates.map { formatDate($0) },
                "isRecurring": event.isRecurring,
                "description": event.description ?? ""
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: eventData, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            context += jsonString + "\n\n"
        }

        // Full receipts JSON
        context += "=== COMPLETE RECEIPTS DATA ===\n"
        let receiptData = receipts.map { receipt -> [String: Any] in
            [
                "id": receipt.id.uuidString,
                "title": receipt.title,
                "amount": receipt.amount,
                "date": formatDate(receipt.date),
                "category": receipt.category
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: receiptData, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            context += jsonString + "\n\n"
        }

        return context
    }

    // MARK: - Helper Methods

    private func isUnderReceiptsFolderHierarchy(folderId: UUID?, receiptsFolderId: UUID) -> Bool {
        guard let folderId = folderId else { return false }

        if folderId == receiptsFolderId {
            return true
        }

        if let folder = notesManager.folders.first(where: { $0.id == folderId }),
           let parentId = folder.parentFolderId {
            return isUnderReceiptsFolderHierarchy(folderId: parentId, receiptsFolderId: receiptsFolderId)
        }

        return false
    }

    private func formatDate(_ date: Date) -> String {
        return mediumDateFormatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }

    /// Fetch latest news headlines from web sources
    private func fetchWebNews(topic: String) async throws -> [String] {
        // Use DuckDuckGo news search as a free web source (no API key needed)
        let searchTerm = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "news"

        // Google News RSS feed (alternative if you want RSS parsing)
        let newsURL = "https://news.google.com/rss/search?q=\(searchTerm)&hl=en-US&gl=US&ceid=US:en"

        guard let url = URL(string: newsURL) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        // Parse RSS feed to extract headlines
        let rssString = String(data: data, encoding: .utf8) ?? ""
        return parseRSSHeadlines(rssString)
    }

    /// Parse RSS feed XML to extract headlines
    private func parseRSSHeadlines(_ rssContent: String) -> [String] {
        var headlines: [String] = []

        // Simple regex-based parsing for RSS <item> and <title> tags
        let itemPattern = "<item[^>]*>.*?</item>"
        let titlePattern = "<title[^>]*>([^<]+)</title>"

        if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) {
            let nsString = rssContent as NSString
            let itemMatches = itemRegex.matches(in: rssContent, range: NSRange(location: 0, length: nsString.length))

            for match in itemMatches.prefix(10) {
                let itemString = nsString.substring(with: match.range)

                if let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: []) {
                    let titleMatches = titleRegex.matches(in: itemString, range: NSRange(location: 0, length: (itemString as NSString).length))

                    if let titleMatch = titleMatches.first {
                        let titleRange = titleMatch.range(at: 1)
                        if titleRange.location != NSNotFound {
                            let title = (itemString as NSString).substring(with: titleRange)
                            // Decode HTML entities
                            let decodedTitle = decodeHTMLEntities(title)
                            if !decodedTitle.isEmpty && decodedTitle != "Google News" {
                                headlines.append(decodedTitle)
                            }
                        }
                    }
                }
            }
        }

        return headlines
    }

    /// Decode basic HTML entities
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        return result
    }

    /// Extract date from receipt note title
    /// The title contains the transaction date like "Mazaj Lounge - October 31, 2025"
    /// Searches for date patterns within the title, not the whole title as a date
    private func extractDateFromTitle(_ title: String) -> Date? {
        // Look for date pattern: "Month DD, YYYY" or "Month DD YYYY" within the title
        // Example: "Mazaj Lounge - October 31, 2025" → extract "October 31, 2025"

        let dateFormatter = DateFormatter()

        // Split by common separators and check each part for a date
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "-–—•"))

        for part in parts {
            let trimmedPart = part.trimmingCharacters(in: .whitespaces)

            // Try each date format on this part
            let formats = [
                "MMMM dd, yyyy",   // October 31, 2025
                "MMMM d, yyyy",    // October 1, 2025
                "MMMM dd yyyy",    // October 31 2025
                "MMMM d yyyy",     // October 1 2025
                "MMM dd, yyyy",    // Oct 31, 2025
                "MMM d, yyyy",     // Oct 1, 2025
                "MMM dd yyyy",     // Oct 31 2025
                "MMM d yyyy",      // Oct 1 2025
            ]

            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: trimmedPart) {
                    return date
                }
            }
        }

        // If no date found, return nil and let ReceiptStat use dateModified as fallback
        return nil
    }

    /// Get the category name for an event given its tagId
    private func getCategoryName(for tagId: String?) -> String {
        guard let tagId = tagId else { return "Personal" }
        return tagManager.getTag(by: tagId)?.name ?? "Personal"
    }

    /// Get formatted time info for an event
    private func getTimeInfo(_ event: TaskItem, isAllDay: Bool) -> String {
        if isAllDay {
            return "[All-day]"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if let start = event.scheduledTime, let end = event.endTime {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = event.scheduledTime {
            return formatter.string(from: start)
        }

        return ""
    }
    
    /// Get detailed recurring info including frequency and next occurrence date
    private func getRecurringInfo(_ event: TaskItem) -> String {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return "" }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        var info = " [RECURRING"
        
        // Add frequency type
        switch frequency {
        case .daily: info += " - Daily"
        case .weekly: info += " - Weekly"
        case .biweekly: info += " - Bi-weekly"
        case .monthly: info += " - Monthly"
        case .yearly: info += " - Yearly"
        case .custom: info += " - Custom"
        }
        
        // Add next occurrence date - this is CRITICAL for the LLM to know when the event actually happens
        if let nextDate = getNextOccurrenceDate(for: event) {
            info += ", Next: \(dateFormatter.string(from: nextDate))"
        } else if let targetDate = event.targetDate {
            // Fall back to target date for the original/anchor date
            info += ", Original date: \(dateFormatter.string(from: targetDate))"
        }
        
        info += "]"
        return info
    }

    /// Check if a recurring event occurs on a specific date
    private func shouldEventOccurOn(_ event: TaskItem, date: Date) -> Bool {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return false }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, date > endDate {
            return false
        }

        // For yearly events, don't check if date < anchorDate - we want to check if it occurs in ANY year
        // For other frequencies, check if event has started
        if frequency != .yearly && date < anchorDate {
            return false
        }

        // Check frequency
        switch frequency {
        case .daily:
            // Daily events occur every day after the anchor date
            return date >= anchorDate

        case .weekly:
            // Weekly events occur on the same day of week
            let targetWeekday = calendar.component(.weekday, from: anchorDate)
            let dateWeekday = calendar.component(.weekday, from: date)
            return targetWeekday == dateWeekday

        case .biweekly:
            // Biweekly events occur every 2 weeks from anchor date
            let daysDifference = calendar.dateComponents([.day], from: anchorDate, to: date).day ?? 0
            return daysDifference >= 0 && daysDifference % 14 == 0

        case .monthly:
            // Monthly events occur on the same day of month
            let targetDay = calendar.component(.day, from: anchorDate)
            let dateDay = calendar.component(.day, from: date)
            return targetDay == dateDay

        case .yearly:
            // Yearly events occur on the same month and day
            let targetMonth = calendar.component(.month, from: anchorDate)
            let targetDay = calendar.component(.day, from: anchorDate)
            let dateMonth = calendar.component(.month, from: date)
            let dateDay = calendar.component(.day, from: date)
            return targetMonth == dateMonth && targetDay == dateDay

        case .custom:
            // For custom frequency, check if date is on one of the custom days
            // Note: Full implementation would check customRecurrenceDays from the event
            // For now, treat as weekly (same day of week as anchor)
            let targetWeekday = calendar.component(.weekday, from: anchorDate)
            let dateWeekday = calendar.component(.weekday, from: date)
            return targetWeekday == dateWeekday
        }
    }

    /// Determine the next occurrence date for a recurring event after a given date
    private func getNextOccurrenceDate(for event: TaskItem, after minimumDate: Date = Date.distantPast) -> Date? {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return nil }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt
        let currentDate = Date()
        let startDate = minimumDate > currentDate ? minimumDate : currentDate

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, startDate > endDate {
            return nil
        }

        // For yearly events, optimize the search by checking the current year first
        if frequency == .yearly {
            let anchorMonth = calendar.component(.month, from: anchorDate)
            let anchorDay = calendar.component(.day, from: anchorDate)
            let currentYear = calendar.component(.year, from: startDate)
            
            // Try current year first
            if let thisYearDate = calendar.date(from: DateComponents(year: currentYear, month: anchorMonth, day: anchorDay)),
               thisYearDate >= startDate,
               shouldEventOccurOn(event, date: thisYearDate) {
                return thisYearDate
            }
            
            // If current year has passed, try next year
            if let nextYearDate = calendar.date(from: DateComponents(year: currentYear + 1, month: anchorMonth, day: anchorDay)),
               shouldEventOccurOn(event, date: nextYearDate) {
                return nextYearDate
            }
        }

        // For other frequencies or if yearly optimization didn't work, search day by day
        var searchDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let searchLimit = calendar.date(byAdding: .year, value: 2, to: startDate) ?? startDate

        while searchDate <= searchLimit {
            if shouldEventOccurOn(event, date: searchDate) {
                return searchDate
            }
            searchDate = calendar.date(byAdding: .day, value: 1, to: searchDate) ?? searchDate
        }

        return nil
    }

    // MARK: - ETA Calculation Helpers

    /// Calculate ETA from current location to a destination
    func calculateETA(to destination: CLLocationCoordinate2D) async -> String? {
        let locationService = LocationService.shared
        guard let currentLocation = locationService.currentLocation else {
            return nil
        }
        
        do {
            let result = try await navigationService.calculateETA(
                from: currentLocation,
                to: destination
            )
            return "\(result.durationText) (\(result.distanceText))"
        } catch {
            print("⚠️ Failed to calculate ETA: \(error)")
            return nil
        }
    }

    /// Find saved location by name (fuzzy match)
    /// Also searches user notes and address for context clues like "airbnb"
    /// Handles possessives ("Agithan's house"), folder names ("Homes"), and common phrases
    func findLocationByName(_ name: String) -> SavedPlace? {
        var searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common phrases that indicate it's a person's place
        let housePhrases = ["'s house", "'s home", "'s place", "s house", "s home", "s place", " house", " home", " place", " apartment", " condo"]
        var personName: String? = nil
        
        // Extract person's name from possessives like "Agithan's house"
        for phrase in housePhrases {
            if searchName.contains(phrase) {
                personName = searchName.replacingOccurrences(of: phrase, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        let searchWords = searchName.split(separator: " ").map { String($0) }.filter { $0.count > 2 }
        
        // If we extracted a person's name, search for it specifically
        if let name = personName, !name.isEmpty {
            print("📍 Extracted person name: '\(name)' from query '\(searchName)'")
            
            // Try exact match on person's name
            if let exact = locations.first(where: { 
                $0.displayName.lowercased() == name || 
                $0.name.lowercased() == name ||
                $0.displayName.lowercased().contains(name) ||
                $0.name.lowercased().contains(name)
            }) {
                print("📍 Found by person name: \(exact.displayName)")
                return exact
            }
            
            // Check if location is in "Homes" or "Home" category (folder match)
            if let inHomesFolder = locations.first(where: { place in
                let isHomeCategory = place.category.lowercased().contains("home")
                let matchesName = place.displayName.lowercased().contains(name) || 
                                  place.name.lowercased().contains(name) ||
                                  (place.userNotes?.lowercased().contains(name) ?? false)
                return isHomeCategory && matchesName
            }) {
                print("📍 Found in Homes folder: \(inHomesFolder.displayName)")
                return inHomesFolder
            }
            
            // Check any location that contains the person's name
            for place in locations {
                let allText = "\(place.displayName) \(place.name) \(place.userNotes ?? "") \(place.address)".lowercased()
                if allText.contains(name) {
                    print("📍 Found by name in location text: \(place.displayName)")
                    return place
                }
            }
        }
        
        // Handle common named locations like "work", "home", "gym"
        let commonLocations: [String: [String]] = [
            "work": ["work", "office", "workplace", "job"],
            "home": ["home", "house", "my place", "my house", "apartment", "condo", "residence"],
            "gym": ["gym", "fitness", "workout"]
        ]
        
        for (category, keywords) in commonLocations {
            if keywords.contains(where: { searchName.contains($0) }) {
                // Find location in matching category
                if let match = locations.first(where: { 
                    $0.category.lowercased().contains(category) ||
                    $0.displayName.lowercased().contains(category) ||
                    $0.name.lowercased().contains(category)
                }) {
                    print("📍 Found by common location type '\(category)': \(match.displayName)")
                    return match
                }
            }
        }
        
        // Try exact match first
        if let exact = locations.first(where: { 
            $0.displayName.lowercased() == searchName || 
            $0.name.lowercased() == searchName 
        }) {
            print("📍 Found exact match: \(exact.displayName)")
            return exact
        }
        
        // Try partial match on name (contains)
        if let partial = locations.first(where: { 
            $0.displayName.lowercased().contains(searchName) || 
            $0.name.lowercased().contains(searchName) ||
            searchName.contains($0.displayName.lowercased()) ||
            searchName.contains($0.name.lowercased())
        }) {
            print("📍 Found partial match: \(partial.displayName)")
            return partial
        }
        
        // Try word-level matching - all significant search words should be in location name
        if searchWords.count >= 1 {
            if let wordMatch = locations.first(where: { place in
                let locationWords = place.displayName.lowercased() + " " + place.name.lowercased()
                return searchWords.allSatisfy { locationWords.contains($0) }
            }) {
                print("📍 Found word-level match: \(wordMatch.displayName)")
                return wordMatch
            }
            
            // Also try if ANY significant word matches (for single-word searches like "shawarma")
            if let anyWordMatch = locations.first(where: { place in
                let locationName = place.displayName.lowercased() + " " + place.name.lowercased()
                return searchWords.contains { word in 
                    locationName.contains(word) && word.count >= 4 // Only match on substantial words
                }
            }) {
                print("📍 Found any-word match: \(anyWordMatch.displayName)")
                return anyWordMatch
            }
        }
        
        // Try searching in user notes (e.g., user might have noted "airbnb" in a location's notes)
        if let fromNotes = locations.first(where: { place in
            if let notes = place.userNotes?.lowercased() {
                return notes.contains(searchName)
            }
            return false
        }) {
            return fromNotes
        }
        
        // Try searching in address
        if let fromAddress = locations.first(where: { 
            $0.address.lowercased().contains(searchName)
        }) {
            return fromAddress
        }
        
        // Try category/folder match (e.g., "ski" might match a location in "Ski Resort" category)
        if let fromCategory = locations.first(where: { 
            $0.category.lowercased().contains(searchName) ||
            searchName.contains($0.category.lowercased())
        }) {
            return fromCategory
        }
        
        return nil
    }
    
    /// Search for any location using Apple's geocoding/MapKit (not just saved locations)
    /// Returns the first matching result with coordinates
    func searchAnyLocation(_ searchQuery: String) async -> LocationSearchResult? {
        // First check saved locations
        if let saved = findLocationByName(searchQuery) {
            return LocationSearchResult(
                name: saved.displayName,
                address: saved.address,
                coordinate: CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude),
                isSavedLocation: true
            )
        }
        

        
        // Smart Context Search: Check calendar events for location context
        // e.g. "Airbnb" -> Matches event "Airbnb Stay" with location "2601 Apricot Ln"
        var queryToSearch = searchQuery
        let searchLower = searchQuery.lowercased()
        
        if let eventMatch = events.first(where: { 
            let hasLocation = !($0.location ?? "").isEmpty
            let matchesTitle = $0.title.lowercased().contains(searchLower)
            let matchesLocation = ($0.location ?? "").lowercased().contains(searchLower)
            return hasLocation && (matchesTitle || matchesLocation)
        }) {
            if let loc = eventMatch.location {
                print("📍 Found context in event '\(eventMatch.title)': Using address '\(loc)' for search")
                queryToSearch = loc
            }
        }
        
        // Use MapKit local search for any location
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = queryToSearch
        
        // Bias search towards user's current location if available
        if let currentLocation = LocationService.shared.currentLocation {
            request.region = MKCoordinateRegion(
                center: currentLocation.coordinate,
                latitudinalMeters: 200000,  // 200km radius - wider to capture GTA and surrounding areas
                longitudinalMeters: 200000
            )
        } else {
            // Default to Toronto area if no current location
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
                latitudinalMeters: 200000,
                longitudinalMeters: 200000
            )
        }
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            
            if let firstResult = response.mapItems.first {
                let placemark = firstResult.placemark
                let name = firstResult.name ?? placemark.name ?? searchQuery
                
                // Build address string
                var addressParts: [String] = []
                if let street = placemark.thoroughfare {
                    if let number = placemark.subThoroughfare {
                        addressParts.append("\(number) \(street)")
                    } else {
                        addressParts.append(street)
                    }
                }
                if let city = placemark.locality {
                    addressParts.append(city)
                }
                if let state = placemark.administrativeArea {
                    addressParts.append(state)
                }
                let address = addressParts.isEmpty ? "Location found" : addressParts.joined(separator: ", ")
                
                return LocationSearchResult(
                    name: name,
                    address: address,
                    coordinate: placemark.coordinate,
                    isSavedLocation: false
                )
            }
        } catch {
            print("⚠️ MapKit search failed for '\(searchQuery)': \(error)")
        }
        
        // Fallback: Try CLGeocoder for address-based search
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(searchQuery)
            if let first = placemarks.first, let location = first.location {
                let name = first.name ?? searchQuery
                var addressParts: [String] = []
                if let street = first.thoroughfare {
                    if let number = first.subThoroughfare {
                        addressParts.append("\(number) \(street)")
                    } else {
                        addressParts.append(street)
                    }
                }
                if let city = first.locality {
                    addressParts.append(city)
                }
                if let state = first.administrativeArea {
                    addressParts.append(state)
                }
                let address = addressParts.isEmpty ? "Location found" : addressParts.joined(separator: ", ")
                
                return LocationSearchResult(
                    name: name,
                    address: address,
                    coordinate: location.coordinate,
                    isSavedLocation: false
                )
            }
        } catch {
            print("⚠️ Geocoding failed for '\(searchQuery)': \(error)")
        }
        
        return nil
    }
    
    /// Result from location search (either saved or from MapKit/geocoder)
    struct LocationSearchResult {
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
        let isSavedLocation: Bool
    }

    // MARK: - Multi-Source Search Helpers

    /// Extract keywords from user query for note filtering
    private func extractKeywords(from query: String) -> Set<String> {
        // Convert to lowercase and split by common separators
        let lowercaseQuery = query.lowercased()

        // Remove common words that don't help with searching
        let stopwords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "up", "is", "are", "was", "were", "be",
            "have", "has", "do", "does", "did", "what", "when", "where", "why",
            "how", "my", "your", "our", "their", "if", "that", "this", "these",
            "as", "about", "can", "could", "would", "should", "may", "might"
        ])

        // Split by whitespace and punctuation
        let components = lowercaseQuery.split { !$0.isLetter && !$0.isNumber }.map { String($0) }

        // Filter out stopwords and very short words, keep meaningful keywords
        let keywords = Set(components.filter { word in
            word.count >= 3 && !stopwords.contains(word)
        })

        return keywords
    }

    /// Filter notes based on query keywords for relevance
    /// Returns notes sorted by relevance score (highest first), limited to top 10
    private func filterNotesByRelevance(notes: [Note], query: String) -> [Note] {
        let keywords = extractKeywords(from: query)

        if keywords.isEmpty {
            // If no keywords, return most recent notes
            return Array(notes.sorted { $0.dateModified > $1.dateModified }.prefix(10))
        }

        // Score each note based on keyword matches
        let scoredNotes = notes.map { note -> (note: Note, score: Int) in
            var score = 0
            let lowerTitle = note.title.lowercased()
            let lowerContent = note.content.lowercased()

            // Keywords in title get higher weight
            for keyword in keywords {
                if lowerTitle.contains(keyword) {
                    score += 5
                }
                if lowerContent.contains(keyword) {
                    score += 1
                }
            }

            return (note: note, score: score)
        }

        // Filter out notes with no matches, sort by score (descending) and date
        let filtered = scoredNotes
            .filter { $0.score > 0 }
            .sorted { scoreA, scoreB in
                if scoreA.score != scoreB.score {
                    return scoreA.score > scoreB.score
                }
                // If same score, sort by most recent first
                return scoreA.note.dateModified > scoreB.note.dateModified
            }

        // If we have keyword matches, return top 10; otherwise return recent notes
        if !filtered.isEmpty {
            return Array(filtered.prefix(10).map { $0.note })
        } else {
            return Array(notes.sorted { $0.dateModified > $1.dateModified }.prefix(10))
        }
    }
    
    // MARK: - Relevant Content Discovery
    
    /// Extract smart search keywords from user query
    /// Identifies company names, product types, and relevant search terms
    private func extractSmartSearchKeywords(from query: String) -> [String] {
        let lowerQuery = query.lowercased()
        var keywords: [String] = []
        
        // Common company/brand names to detect (order confirmations, purchases, etc.)
        let commonBrands = [
            "amazon", "apple", "google", "microsoft", "netflix", "spotify", "uber", "lyft",
            "doordash", "ubereats", "grubhub", "walmart", "target", "costco", "bestbuy",
            "ikea", "wayfair", "ebay", "etsy", "shopify", "paypal", "venmo", "zelle",
            "airbnb", "booking", "expedia", "delta", "united", "american airlines",
            "southwest", "jetblue", "hilton", "marriott", "starbucks", "dunkin",
            "mcdonalds", "chipotle", "dominos", "pizza hut", "subway"
        ]
        
        // Check for brand mentions in query
        for brand in commonBrands {
            if lowerQuery.contains(brand) {
                keywords.append(brand)
            }
        }
        
        // Common search intent keywords
        let intentKeywords: [(pattern: String, searchTerms: [String])] = [
            ("order", ["order confirmation", "your order", "shipped", "delivery"]),
            ("purchase", ["receipt", "order", "purchase", "payment"]),
            ("shipping", ["shipped", "tracking", "delivery", "package"]),
            ("receipt", ["receipt", "order confirmation", "payment"]),
            ("confirmation", ["confirmation", "confirmed", "booked"]),
            ("subscription", ["subscription", "renewal", "billing"]),
            ("flight", ["flight", "booking", "itinerary", "boarding"]),
            ("hotel", ["reservation", "booking", "confirmation"]),
            ("payment", ["payment", "receipt", "invoice", "charged"])
        ]
        
        for (pattern, terms) in intentKeywords {
            if lowerQuery.contains(pattern) {
                // Add the most relevant search term for this intent
                keywords.append(terms[0])
            }
        }
        
        // Remove duplicates and return
        return Array(Set(keywords))
    }
    
    /// Search Gmail API for relevant emails based on query keywords
    private func searchGmailForRelevantEmails(keywords: [String]) async -> [Email] {
        guard !keywords.isEmpty else { return [] }
        
        // Build Gmail search query - combine keywords with OR for broader search
        // Also search for recent emails (within last 90 days)
        let searchQuery = keywords.map { "(\($0))" }.joined(separator: " OR ")
        
        print("🔍 Smart email search query: '\(searchQuery)'")
        
        do {
            // Use GmailAPIClient directly to search
            let gmailClient = GmailAPIClient.shared
            let emails = try await gmailClient.searchEmails(query: searchQuery, maxResults: 5)
            print("📧 Found \(emails.count) emails via Gmail API search")
            return emails
        } catch {
            print("⚠️ Gmail search error: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Find relevant emails, notes, events based on user query for inline display
    private func findRelevantContent(forQuery query: String) async {
        let searchTerms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }  // Only use significant words
        
        guard !searchTerms.isEmpty else { return }
        
        var foundContent: [RelevantContentInfo] = []
        
        // SMART EMAIL SEARCH: Extract relevant keywords and search Gmail API
        let smartKeywords = extractSmartSearchKeywords(from: query)
        let lowerQuery = query.lowercased()
        
        // Helper function to check if email matches query keywords
        let emailMatchesQuery: (Email) -> Bool = { email in
            let emailText = "\(email.subject) \(email.sender.displayName) \(email.sender.email) \(email.snippet)".lowercased()
            
            // If we have smart keywords (like "amazon"), require at least one to match
            if !smartKeywords.isEmpty {
                let hasKeywordMatch = smartKeywords.contains { keyword in
                    emailText.contains(keyword.lowercased())
                }
                if !hasKeywordMatch {
                    return false // Reject emails that don't match any keyword
                }
            }
            
            // Also check if significant search terms match
            let significantTerms = searchTerms.filter { $0.count > 3 }
            if !significantTerms.isEmpty {
                let matchCount = significantTerms.filter { emailText.contains($0) }.count
                // Require at least 1 significant term match
                return matchCount >= 1
            }
            
            return true
        }
        
        // First, search Gmail API with smart keywords (more accurate results)
        if !smartKeywords.isEmpty {
            let gmailResults = await searchGmailForRelevantEmails(keywords: smartKeywords)
            
            // Filter results to only include emails that actually match the query
            let filteredResults = gmailResults.filter(emailMatchesQuery)
            
            for email in filteredResults.prefix(3) {
                foundContent.append(.email(
                    id: email.id,
                    subject: email.subject,
                    sender: email.sender.displayName,
                    snippet: String(email.snippet.prefix(100)),
                    date: email.timestamp
                ))
            }
            
            // Also add these emails to the cached emails for context building
            // This ensures the LLM can reference the full email content
            for email in filteredResults {
                if !emails.contains(where: { $0.id == email.id }) {
                    emails.append(email)
                }
            }
        }
        
        // If no Gmail results, fall back to cached email search with strict filtering
        if foundContent.filter({ $0.contentType == .email }).isEmpty {
            for email in emails.prefix(100) {
                // Only include emails that match the query
                if emailMatchesQuery(email) {
                    foundContent.append(.email(
                        id: email.id,
                        subject: email.subject,
                        sender: email.sender.displayName,
                        snippet: String(email.snippet.prefix(100)),
                        date: email.timestamp
                    ))
                    
                    // Limit to 3 emails max
                    if foundContent.filter({ $0.contentType == .email }).count >= 3 {
                        break
                    }
                }
            }
        }
        
        // Search events - look for matches in title and description  
        for event in events {
            let eventText = "\(event.title) \(event.description ?? "")".lowercased()
            let matchCount = searchTerms.filter { eventText.contains($0) }.count
            
            if matchCount >= 1 {
                let category = getCategoryName(for: event.tagId)
                // Convert String id to UUID (or create new UUID if conversion fails)
                let eventUUID = UUID(uuidString: event.id) ?? UUID()
                foundContent.append(.event(
                    id: eventUUID,
                    title: event.title,
                    date: event.targetDate ?? event.scheduledTime ?? Date(),
                    category: category
                ))
                
                // Limit to 3 events max
                if foundContent.filter({ $0.contentType == .event }).count >= 3 {
                    break
                }
            }
        }
        
        if !foundContent.isEmpty {
            self.lastRelevantContent = foundContent
            print("🔍 Found \(foundContent.count) relevant content items for query")
            for item in foundContent {
                switch item.contentType {
                case .email:
                    print("   📧 Email: \(item.emailSubject ?? "")")
                case .note:
                    print("   📝 Note: \(item.noteTitle ?? "")")
                case .event:
                    print("   📅 Event: \(item.eventTitle ?? "")")
                case .location:
                    print("   📍 Location: \(item.locationName ?? "")")
                }
            }
        }
    }
    */
}
