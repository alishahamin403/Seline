import Foundation
import CoreLocation

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

    // MARK: - Cache Invalidation
    private var lastRefreshTime: Date = Date(timeIntervalSince1970: 0)
    private var lastWeatherFetchTime: Date = Date(timeIntervalSince1970: 0)
    private let REFRESH_CACHE_INTERVAL: TimeInterval = 30 // seconds
    private let WEATHER_CACHE_INTERVAL: TimeInterval = 1800 // 30 minutes

    private var needsRefresh: Bool {
        Date().timeIntervalSince(lastRefreshTime) > REFRESH_CACHE_INTERVAL
    }

    private var needsWeatherFetch: Bool {
        Date().timeIntervalSince(lastWeatherFetchTime) > WEATHER_CACHE_INTERVAL
    }

    init(
        taskManager: TaskManager = TaskManager.shared,
        tagManager: TagManager = TagManager.shared,
        notesManager: NotesManager = NotesManager.shared,
        emailService: EmailService = EmailService.shared,
        weatherService: WeatherService = WeatherService.shared,
        locationsManager: LocationsManager = LocationsManager.shared,
        navigationService: NavigationService = NavigationService.shared,
        categorizationService: ReceiptCategorizationService = ReceiptCategorizationService.shared
    ) {
        self.taskManager = taskManager
        self.tagManager = tagManager
        self.notesManager = notesManager
        self.emailService = emailService
        self.weatherService = weatherService
        self.locationsManager = locationsManager
        self.navigationService = navigationService
        self.categorizationService = categorizationService

        // Note: refresh() is called asynchronously in buildContextPrompt()
        // to fetch custom email folders and saved emails
    }

    // MARK: - Data Collection

    /// Refresh all app data (call this at start of each conversation)
    func refresh() async {
        print("🔄 SelineAppContext.refresh() called")
        self.currentDate = Date()

        // Collect all events
        self.events = taskManager.tasks.values.flatMap { $0 }

        // Collect custom email folders and their saved emails (in parallel for speed)
        do {
            self.customEmailFolders = try await emailService.fetchSavedFolders()
            print("📧 Found \(self.customEmailFolders.count) custom email folders")

            // Load emails for each folder IN PARALLEL (not sequential)
            await withTaskGroup(of: (UUID, [SavedEmail]).self) { group in
                for folder in self.customEmailFolders {
                    group.addTask {
                        do {
                            let savedEmails = try await emailService.fetchSavedEmails(in: folder.id)
                            return (folder.id, savedEmails)
                        } catch {
                            print("  ⚠️  Error loading emails for folder '\(folder.name)': \(error)")
                            return (folder.id, [])
                        }
                    }
                }

                for await (folderId, emails) in group {
                    self.savedEmailsByFolder[folderId] = emails
                    if let folder = self.customEmailFolders.first(where: { $0.id == folderId }) {
                        print("  • \(folder.name): \(emails.count) emails")
                    }
                }
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
                    let isTomorrow = Calendar.current.isDateInTomorrow(nextDate)
                    let isToday = Calendar.current.isDateInToday(nextDate)
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

        // Collect all notes
        self.notes = notesManager.notes

        // Collect all emails
        self.emails = emailService.inboxEmails + emailService.sentEmails

        // Collect all locations
        self.locations = locationsManager.savedPlaces

        // Fetch weather data (only if cache expired - 30 min TTL)
        if needsWeatherFetch {
            do {
                // Try to get current location, otherwise use default (Toronto)
                let locationService = LocationService.shared
                let location = locationService.currentLocation ?? CLLocation(latitude: 43.6532, longitude: -79.3832)

                await weatherService.fetchWeather(for: location)
                self.weatherData = weatherService.weatherData
                self.lastWeatherFetchTime = Date()
                print("🌤️ Weather data fetched (fresh)")
            } catch {
                print("⚠️ Failed to fetch weather: \(error)")
            }
        } else {
            print("🌤️ Weather data cached (not fetching)")
        }

        // Mark refresh as complete for cache validation
        self.lastRefreshTime = Date()

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

            print("     THIS MONTH (Nov 1 - Nov 12): \(thisMonthReceipts.count) receipts, Total: $\(String(format: "%.2f", thisMonthTotal))")

            // Show ALL receipts counted as this month for verification
            print("     --- ALL NOVEMBER RECEIPTS ---")
            for receipt in thisMonthReceipts.sorted(by: { $0.date < $1.date }) {
                print("     • \(formatDate(receipt.date)): \(receipt.title) - $\(String(format: "%.2f", receipt.amount))")
            }
            print("     --- END ---")
        }
        print("   Notes: \(notes.count)")
        print("   Emails: \(emails.count)")
        print("   Locations: \(locations.count)")
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

    /// Build context with intelligent filtering based on user query
    func buildContextPrompt(forQuery userQuery: String) async -> String {
        // Extract useful filters from the query (but don't gate sections based on keywords)
        let categoryFilter = extractCategoryFilter(from: userQuery)
        let timePeriodFilter = extractTimePeriodFilter(from: userQuery)
        let locationCategoryFilter = extractLocationCategoryFilter(from: userQuery)
        let specificNewsTopic = extractNewsTopic(from: userQuery)
        let specificLocationName = isRestaurantOrLocationQuery(userQuery) ? extractLocationName(from: userQuery) : nil

        // Detect expense vs bank statement queries
        let userAskedAboutExpenses = isExpenseQuery(userQuery)
        let userAskedAboutBankStatement = isBankStatementQuery(userQuery)

        // Only refresh if cache expired (30 second TTL)
        // This prevents full refresh on every LLM query
        if needsRefresh {
            await refresh()
            self.lastRefreshTime = Date()
            print("✅ AppContext refreshed (fresh)")
        } else {
            print("✅ AppContext using cache (not refreshing)")
        }

        // Filter events based on extracted intent
        var filteredEvents = events

        // For recurring events: convert them to actual completion instances
        // This allows LLM to answer "when was my last X?" questions
        var expandedEvents: [TaskItem] = []
        for event in filteredEvents {
            if event.isRecurring && !event.completedDates.isEmpty {
                // Create a pseudo-event for each completion date
                // so LLM sees them as actual past events
                for completionDate in event.completedDates {
                    var completedInstance = event
                    completedInstance.targetDate = completionDate
                    completedInstance.scheduledTime = completionDate
                    completedInstance.isRecurring = false  // Mark as single instance for LLM
                    completedInstance.isCompleted = true
                    completedInstance.completedDate = completionDate
                    expandedEvents.append(completedInstance)
                }
            } else {
                expandedEvents.append(event)
            }
        }
        filteredEvents = expandedEvents

        // Apply category filter if detected
        if let categoryId = categoryFilter {
            filteredEvents = filteredEvents.filter { $0.tagId == categoryId }
        }

        // Apply time period filter if detected
        if let timePeriod = timePeriodFilter {
            filteredEvents = filteredEvents.filter { event in
                let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate
                return eventDate >= timePeriod.startDate && eventDate <= timePeriod.endDate
            }
        }

        // Filter receipts by time period if detected (apply regardless of query type)
        var filteredReceipts = receipts
        if let timePeriod = timePeriodFilter {
            filteredReceipts = receipts.filter { receipt in
                return receipt.date >= timePeriod.startDate && receipt.date <= timePeriod.endDate
            }
        }

        // Temporarily replace events and receipts with filtered versions
        let originalEvents = self.events
        let originalReceipts = self.receipts
        self.events = filteredEvents
        self.receipts = filteredReceipts

        // Build context with filtered events (skip refresh since we just did it)
        var context = ""

        // Current date context
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        context += "=== CURRENT DATE ===\n"
        context += dateFormatter.string(from: currentDate) + "\n\n"

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
            notesManager.getFolderName(for: note.folderId)
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

                if calendar.isDateInToday(eventDate) {
                    today.append(event)
                } else if calendar.isDateInTomorrow(eventDate) {
                    tomorrow.append(event)
                } else if calendar.isDate(eventDate, inSameDayAs: currentDate.addingTimeInterval(2*24*3600)) {
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
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

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
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

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
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week)
            if !upcoming.isEmpty {
                context += "\n**UPCOMING** (\(upcoming.count) events):\n"
                for event in upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
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
            // NOTE: Recurring events are NOT included in LLM context
            // They cause confusion for queries like "when was my last haircut?"
            // Anchor dates and next occurrences don't answer user's questions
        } else {
            context += "  No events\n"
        }

        // Add receipts section (always included)
        context += "\n=== RECEIPTS & EXPENSES ===\n"

        // Add context about the data source for the user's query
        if userAskedAboutExpenses {
            context += "**NOTE: User asked about expenses/spending. Use the RECEIPTS data below as the primary source for their expense information.**\n\n"
        } else if userAskedAboutBankStatement {
            context += "**NOTE: User asked about bank/credit card statements. These are typically stored in NOTES folder. Check the NOTES section for bank statements, credit card statements, or transaction lists from American Express, Visa, Mastercard, etc.**\n\n"
        }

        if !receipts.isEmpty {
                // Group receipts by month dynamically (use static formatter for performance)
                let receiptsByMonth = Dictionary(grouping: receipts) { receipt in
                    Self.dateFormatterMedium.string(from: receipt.date)
                }

                // Get current month for detection
                let calendar = Calendar.current
                let currentMonthStr = Self.dateFormatterMedium.string(from: currentDate)

                // Sort months: current month first, then others by recency
                let sortedMonths = receiptsByMonth.keys.sorted { month1, month2 in
                    if month1 == currentMonthStr { return true }
                    if month2 == currentMonthStr { return false }
                    return month1 > month2  // Most recent first
                }

                for month in sortedMonths.prefix(3) {
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
                    for place in favorites.sorted(by: { $0.displayName < $1.displayName }) {
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

                        for place in placesInCategory.sorted(by: { $0.displayName < $1.displayName }) {
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

        // Add notes section (always included)
        context += "\n=== NOTES ===\n"

        if !notes.isEmpty {
            // Group notes by folder
            let notesByFolder = Dictionary(grouping: notes) { note in
                notesManager.getFolderName(for: note.folderId)
            }

            let sortedFolders = notesByFolder.keys.sorted { folder1, folder2 in
                if folder1.lowercased().contains("receipt") { return false }
                if folder2.lowercased().contains("receipt") { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderNotes = notesByFolder[folder] else { continue }

                // Skip Receipts folder - shown in expenses section
                if folder.lowercased().contains("receipt") {
                    continue
                }

                context += "\n**\(folder)** (\(folderNotes.count) notes):\n"

                // Show most recent notes first
                for note in folderNotes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(15) {
                    let lastModified = formatDate(note.dateModified)
                    context += "  • **\(note.title)** (Updated: \(lastModified))\n"

                    // Include FULL note content - important for detailed notes like transaction lists
                    let noteContent = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !noteContent.isEmpty {
                        // Split into lines and add with proper indentation
                        let contentLines = noteContent.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                        for line in contentLines {
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                context += "    \(trimmedLine)\n"
                            }
                        }
                    }

                    context += "\n"
                }

                if folderNotes.count > 15 {
                    context += "  ... and \(folderNotes.count - 15) more notes in this folder\n"
                }
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
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(10) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

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
                        let bodyPreview = String(body.prefix(150))
                        context += "    Preview: \(bodyPreview)...\n"
                    }

                    context += "\n"
                }

                if folderEmails.count > 10 {
                    context += "  ... and \(folderEmails.count - 10) more emails in this folder\n"
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
                for email in folderEmails.sorted(by: { $0.timestamp > $1.timestamp }).prefix(10) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

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
                        let bodyPreview = String(body.prefix(150))
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

        // Restore original events and receipts
        self.events = originalEvents
        self.receipts = originalReceipts

        return context
    }

    func buildContextPrompt() async -> String {
        return await buildContextPromptInternal()
    }

    private func buildContextPromptInternal() async -> String {
        // Only refresh if cache expired (30 second TTL)
        if needsRefresh {
            await refresh()
            self.lastRefreshTime = Date()
        }

        var context = ""

        // Current date context (use static formatter for performance)
        let dateFormatter = Self.dateFormatterFull

        context += "=== CURRENT DATE ===\n"
        context += dateFormatter.string(from: currentDate) + "\n\n"

        // Data summary
        context += "=== DATA SUMMARY ===\n"
        context += "Total Events: \(events.count)\n"
        context += "Total Receipts: \(receipts.count)\n"
        context += "Total Notes: \(notes.count)\n"
        context += "Total Emails: \(emails.count)\n"
        context += "Total Locations: \(locations.count)\n\n"

        // Events detail - Comprehensive with categories, temporal organization, and all-day status
        context += "=== EVENTS & CALENDAR ===\n"

        // Expand recurring events into their completion instances
        // This allows LLM to accurately answer "when was my last X?" questions
        var expandedEvents: [TaskItem] = []
        for event in events {
            if event.isRecurring && !event.completedDates.isEmpty {
                // Create pseudo-events for each completion date
                for completionDate in event.completedDates {
                    var completedInstance = event
                    completedInstance.targetDate = completionDate
                    completedInstance.scheduledTime = completionDate
                    completedInstance.isRecurring = false  // Mark as single instance
                    completedInstance.isCompleted = true
                    completedInstance.completedDate = completionDate
                    expandedEvents.append(completedInstance)
                }
            } else {
                expandedEvents.append(event)
            }
        }

        if !expandedEvents.isEmpty {
            let calendar = Calendar.current

            // Organize events by temporal proximity
            var today: [TaskItem] = []
            var tomorrow: [TaskItem] = []
            var thisWeek: [TaskItem] = []
            var upcoming: [TaskItem] = []
            var past: [TaskItem] = []

            for event in expandedEvents {
                let eventDate = event.targetDate ?? event.scheduledTime ?? event.completedDate ?? currentDate

                if calendar.isDateInToday(eventDate) {
                    today.append(event)
                } else if calendar.isDateInTomorrow(eventDate) {
                    tomorrow.append(event)
                } else if calendar.isDate(eventDate, inSameDayAs: currentDate.addingTimeInterval(2*24*3600)) {
                    thisWeek.append(event)
                } else if eventDate > currentDate {
                    upcoming.append(event)
                } else {
                    past.append(event)
                }
            }

            // TODAY
            if !today.isEmpty {
                context += "\n**TODAY** (\(today.count) events):\n"
                for event in today.sorted(by: { ($0.scheduledTime ?? Date.distantFuture) < ($1.scheduledTime ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let timeInfo = getTimeInfo(event, isAllDay: isAllDay)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

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
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

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
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(timeInfo)\n"
                }
            }

            // UPCOMING (future beyond this week)
            if !upcoming.isEmpty {
                context += "\n**UPCOMING** (\(upcoming.count) events):\n"
                for event in upcoming.sorted(by: { ($0.targetDate ?? Date.distantFuture) < ($1.targetDate ?? Date.distantFuture) }) {
                    let categoryName = getCategoryName(for: event.tagId)
                    let isAllDay = event.scheduledTime == nil && event.endTime == nil
                    let dateStr = formatDate(event.targetDate ?? event.scheduledTime ?? currentDate)
                    let status = event.isCompleted ? "✓ COMPLETED" : "○ PENDING"
                    let recurringInfo = event.isRecurring ? " [RECURRING]" : ""

                    context += "  \(status): \(event.title)\(recurringInfo) - \(categoryName) - \(dateStr)\n"
                }
            }

            // RECURRING EVENTS SUMMARY with monthly/yearly stats
            let recurringEvents = events.filter { $0.isRecurring }
            if !recurringEvents.isEmpty {
                context += "\n**RECURRING EVENTS SUMMARY** (\(recurringEvents.count) recurring):\n"
                for event in recurringEvents {
                    let currentMonth = calendar.dateComponents([.month, .year], from: currentDate)

                    let thisMonthCompletions = event.completedDates.filter { date in
                        let dateComponents = calendar.dateComponents([.month, .year], from: date)
                        return dateComponents.month == currentMonth.month && dateComponents.year == currentMonth.year
                    }

                    let categoryName = getCategoryName(for: event.tagId)
                    context += "  • \(event.title) [\(categoryName)]\n"
                    context += "    All-time: \(event.completedDates.count) completions\n"
                    context += "    This month: \(thisMonthCompletions.count) completions\n"

                    // Monthly breakdown
                    let monthlyStats = Dictionary(grouping: event.completedDates) { date in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMMM yyyy"
                        return formatter.string(from: date)
                    }

                    if !monthlyStats.isEmpty {
                        // Sort months by date (most recent first)
                        let sortedMonths = monthlyStats.keys.sorted { month1, month2 in
                            // Create dummy dates from the month strings for comparison
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MMMM yyyy"
                            let date1 = formatter.date(from: month1) ?? Date.distantPast
                            let date2 = formatter.date(from: month2) ?? Date.distantPast
                            return date1 > date2
                        }

                        context += "    Monthly stats:\n"
                        for month in sortedMonths.prefix(6) {
                            let count = monthlyStats[month]?.count ?? 0
                            context += "      \(month): \(count) completions\n"
                        }
                    }

                    if !thisMonthCompletions.isEmpty {
                        let dateStrings = thisMonthCompletions.sorted().map { formatDate($0) }
                        context += "    Dates completed this month: \(dateStrings.joined(separator: ", "))\n"
                    } else {
                        context += "    No completions this month\n"
                    }
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

            for (index, month) in sortedMonths.prefix(7).enumerated() {
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
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

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
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .short
                    let formattedDate = dateFormatter.string(from: email.timestamp)

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
            // Group notes by folder
            let notesByFolder = Dictionary(grouping: notes) { note in
                notesManager.getFolderName(for: note.folderId)
            }

            // Sort folders with "Receipts" last (since it's for receipts, not general notes)
            let sortedFolders = notesByFolder.keys.sorted { folder1, folder2 in
                if folder1.lowercased().contains("receipt") { return false }
                if folder2.lowercased().contains("receipt") { return false }
                return folder1 < folder2
            }

            for folder in sortedFolders {
                guard let folderNotes = notesByFolder[folder] else { continue }

                // Skip Receipts folder - already shown in expenses section
                if folder.lowercased().contains("receipt") {
                    continue
                }

                let folderLabel = folder == "Notes" ? "**Uncategorized Notes**" : "**\(folder)**"
                context += "\n\(folderLabel) (\(folderNotes.count) notes):\n"

                // Show most recently modified notes first, max 15 per folder
                for note in folderNotes.sorted(by: { $0.dateModified > $1.dateModified }).prefix(15) {
                    let lastModified = formatDate(note.dateModified)
                    context += "  • **\(note.title)** (Updated: \(lastModified))\n"
                    context += "    Content:\n"

                    // Include full note content, formatted nicely
                    let contentLines = note.content.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                    let lineLimit = 1000  // Show up to 1000 lines per note (covers long statements and detailed notes)

                    for line in contentLines.prefix(lineLimit) {
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                        if !trimmedLine.isEmpty {
                            context += "    \(trimmedLine)\n"
                        }
                    }

                    if contentLines.count > lineLimit {
                        context += "    ... (note continues - \(contentLines.count - lineLimit) more lines)\n"
                    }
                    context += "\n"
                }

                if folderNotes.count > 15 {
                    context += "  ... and \(folderNotes.count - 15) more notes in this folder\n"
                }
            }

            let totalNotes = notes.count
            context += "\n**Total Notes**: \(totalNotes)\n"
        } else {
            context += "  No notes\n"
        }

        // Locations detail
        context += "\n=== LOCATIONS ===\n"
        if !locations.isEmpty {
            for location in locations.prefix(15) {
                let rating = location.userRating.map { "⭐ \($0)/10" } ?? "No rating"
                context += "  • \(location.displayName) - \(location.address) (\(rating))\n"
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    /// Check if a recurring event occurs on a specific date
    private func shouldEventOccurOn(_ event: TaskItem, date: Date) -> Bool {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return false }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, date > endDate {
            return false
        }

        // Check if event has started
        if date < anchorDate {
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
        }
    }

    /// Determine the next occurrence date for a recurring event after a given date
    private func getNextOccurrenceDate(for event: TaskItem, after minimumDate: Date = Date.distantPast) -> Date? {
        guard event.isRecurring, let frequency = event.recurrenceFrequency else { return nil }

        let calendar = Calendar.current
        let anchorDate = event.targetDate ?? event.createdAt
        let startDate = minimumDate > anchorDate ? minimumDate : anchorDate

        // Check if event has ended
        if let endDate = event.recurrenceEndDate, startDate > endDate {
            return nil
        }

        // Search for the next occurrence in the next year
        var searchDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let searchLimit = calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate

        while searchDate <= searchLimit {
            if shouldEventOccurOn(event, date: searchDate) {
                return searchDate
            }
            searchDate = calendar.date(byAdding: .day, value: 1, to: searchDate) ?? searchDate
        }

        return nil
    }

    // MARK: - Static Date Formatters (Performance Optimization)
    private static let dateFormatterFull: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatterMedium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dateFormatterShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
