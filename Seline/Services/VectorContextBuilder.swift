import Foundation
import CoreLocation

/**
 * VectorContextBuilder - LLM Context using Vector Search
 *
 * Simplified approach: Let vector search do the work, only add date completeness guarantees.
 * No hardcoded intent detection or routing - the LLM and embeddings figure it out.
 *
 * Benefits:
 * - Much simpler codebase (~80% less code)
 * - More flexible (adapts to new query types automatically)
 * - Still guarantees completeness for date-specific queries
 * - Better semantic matching (no brittle keyword matching)
 */
@MainActor
class VectorContextBuilder {
    static let shared = VectorContextBuilder()

    private let vectorSearch = VectorSearchService.shared

    // MARK: - Query Plan Data Structures

    struct QueryPlan: Codable {
        let searches: [SearchRequest]
        let reasoning: String?  // Optional: why LLM chose these searches

        struct SearchRequest: Codable {
            let type: DataType
            let keywords: [String]?
            let dateRange: String?  // Natural language: "yesterday", "Feb 2026", "last week"
            let limit: Int?
            let filters: [String: String]?  // Generic filters: merchant, category, sender, etc.

            enum DataType: String, Codable {
                case receipt
                case visit
                case email
                case event
                case note
                case person
            }
        }
    }

    // MARK: - Configuration

    /// Date extraction cache: query text -> (date range, extraction timestamp)
    /// TTL: 5 minutes
    private var dateExtractionCache: [String: (result: (start: Date, end: Date)?, timestamp: Date)] = [:]
    private let dateExtractionCacheTTL: TimeInterval = 300  // 5 minutes

    /// Determine dynamic search limit based on query complexity
    private func determineSearchLimit(forQuery query: String) -> Int {
        let lowercased = query.lowercased()

        // Broad semantic queries - need comprehensive results
        if lowercased.contains("all ") || lowercased.contains("every ") || lowercased.contains("total ") {
            return 100
        }

        // Date-specific queries - moderate limit (dates narrow scope)
        if lowercased.contains("yesterday") || lowercased.contains("today") ||
           lowercased.contains("week") || lowercased.contains("month") {
            return 50
        }

        // Focused semantic queries - smaller limit for precision
        return 30
    }
    
    // MARK: - Query Planning

    /// Generate a search plan from user query using LLM
    private func generateQueryPlan(for query: String) async -> QueryPlan? {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none

        let planningPrompt = """
        You are a query planner. Analyze the user's query and generate a search plan to find the data needed to answer it.

        Today's date: \(formatter.string(from: today))
        User query: "\(query)"

        Generate a JSON search plan with this structure:
        {
          "searches": [
            {
              "type": "receipt" | "visit" | "email" | "event" | "note" | "person",
              "keywords": ["keyword1", "keyword2"],  // Optional: search terms
              "dateRange": "yesterday" | "last week" | "Feb 2026" | "this month",  // Optional
              "limit": 50,  // Optional: how many results to return
              "filters": {"merchant": "Tesla", "category": "Food"}  // Optional
            }
          ],
          "reasoning": "brief explanation of your plan"  // Optional
        }

        Guidelines:
        - Use keywords to filter data (e.g., "Tesla" for Tesla receipts)
        - Include date ranges when mentioned ("last month", "yesterday", etc.)
        - For comparisons, create separate searches for each time period
        - Use appropriate data types: receipt (purchases), visit (locations), email, event (calendar), note, person
        - Be specific with keywords to avoid fetching too much data
        - Default limit is 50 unless query asks for "all"

        Examples:

        Query: "Tesla charging this month vs last month"
        Plan: {
          "searches": [
            {"type": "receipt", "keywords": ["Tesla", "charging"], "dateRange": "this month", "limit": 50},
            {"type": "receipt", "keywords": ["Tesla", "charging"], "dateRange": "last month", "limit": 50}
          ],
          "reasoning": "Comparing Tesla charging receipts across two months"
        }

        Query: "Who did I meet yesterday?"
        Plan: {
          "searches": [
            {"type": "visit", "dateRange": "yesterday", "limit": 20},
            {"type": "event", "dateRange": "yesterday", "limit": 20}
          ],
          "reasoning": "Find visits and events from yesterday to identify people met"
        }

        Query: "Emails from Sarah about the project"
        Plan: {
          "searches": [
            {"type": "email", "keywords": ["Sarah", "project"], "limit": 30}
          ],
          "reasoning": "Search emails with keywords Sarah and project"
        }

        Respond with ONLY the JSON plan. No other text.
        """

        do {
            let response = try await GeminiService.shared.simpleChatCompletion(
                systemPrompt: "You are a query planning assistant. Generate JSON search plans from user queries.",
                messages: [["role": "user", "content": planningPrompt]]
            )

            var trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📋 Query plan generated: \(trimmed)")

            // Strip markdown code fences if present (```json ... ```)
            if trimmed.hasPrefix("```") {
                // Remove opening fence
                if let firstNewline = trimmed.firstIndex(of: "\n") {
                    trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
                }
                // Remove closing fence
                if trimmed.hasSuffix("```") {
                    trimmed = String(trimmed.dropLast(3))
                }
                trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📋 Stripped markdown fences, clean JSON: \(trimmed)")
            }

            // Parse JSON response
            let jsonData = trimmed.data(using: .utf8)!
            let decoder = JSONDecoder()
            let plan = try decoder.decode(QueryPlan.self, from: jsonData)

            print("✅ Query plan parsed: \(plan.searches.count) searches")
            if let reasoning = plan.reasoning {
                print("💭 Reasoning: \(reasoning)")
            }

            return plan
        } catch {
            print("⚠️ Query planning failed: \(error)")
            return nil
        }
    }

    // MARK: - Search Execution

    /// Execute the search plan and return formatted context
    private func executeSearchPlan(_ plan: QueryPlan) async -> String {
        var context = "\n=== SEARCH RESULTS ===\n"
        if let reasoning = plan.reasoning {
            context += "Search strategy: \(reasoning)\n\n"
        }

        for (index, search) in plan.searches.enumerated() {
            print("🔍 Executing search \(index + 1)/\(plan.searches.count): \(search.type) - \(search.keywords ?? [])")

            let searchResult = await executeSearch(search)
            if !searchResult.isEmpty {
                context += searchResult + "\n"
            }
        }

        return context
    }

    /// Execute a single search request
    private func executeSearch(_ search: QueryPlan.SearchRequest) async -> String {
        // Parse date range if provided
        var dateRange: (start: Date, end: Date)? = nil
        if let dateStr = search.dateRange {
            dateRange = await parseDateRange(dateStr)
        }

        let limit = search.limit ?? 50

        switch search.type {
        case .receipt:
            return await searchReceipts(keywords: search.keywords, dateRange: dateRange, limit: limit, filters: search.filters)

        case .visit:
            return await searchVisits(keywords: search.keywords, dateRange: dateRange, limit: limit)

        case .email:
            return await searchEmails(keywords: search.keywords, dateRange: dateRange, limit: limit, filters: search.filters)

        case .event:
            return await searchEvents(keywords: search.keywords, dateRange: dateRange, limit: limit)

        case .note:
            return await searchNotes(keywords: search.keywords, limit: limit)

        case .person:
            return await searchPeople(keywords: search.keywords)
        }
    }

    // MARK: - Individual Search Functions

    private func searchReceipts(keywords: [String]?, dateRange: (start: Date, end: Date)?, limit: Int, filters: [String: String]?) async -> String {
        let notesManager = NotesManager.shared
        let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

        func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
            guard let folderId else { return false }
            if folderId == receiptsFolderId { return true }
            if let folder = notesManager.folders.first(where: { $0.id == folderId }),
               let parentId = folder.parentFolderId {
                return isUnderReceiptsFolderHierarchy(folderId: parentId)
            }
            return false
        }

        var receipts = notesManager.notes
            .filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
            .compactMap { note -> (note: Note, date: Date, amount: Double, category: String)? in
                let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                return (note, date, amount, category)
            }

        // Apply date filter
        if let dateRange = dateRange {
            receipts = receipts.filter { $0.date >= dateRange.start && $0.date < dateRange.end }
        }

        // Apply keyword filter
        if let keywords = keywords, !keywords.isEmpty {
            receipts = receipts.filter { receipt in
                let searchText = (receipt.note.title + " " + receipt.note.content + " " + receipt.category).lowercased()
                return keywords.contains { keyword in
                    searchText.contains(keyword.lowercased())
                }
            }
        }

        // Apply merchant filter if provided
        if let merchant = filters?["merchant"] {
            receipts = receipts.filter { $0.note.title.lowercased().contains(merchant.lowercased()) }
        }

        // Sort by date and limit
        receipts = Array(receipts.sorted { $0.date > $1.date }.prefix(limit))

        guard !receipts.isEmpty else {
            return "RECEIPTS: No receipts found matching criteria\n"
        }

        let total = receipts.reduce(0.0) { $0 + $1.amount }
        var context = "RECEIPTS (\(receipts.count) found, total: $\(String(format: "%.2f", total))):\n"

        for receipt in receipts {
            let dateStr = DateFormatter.localizedString(from: receipt.date, dateStyle: .medium, timeStyle: .none)
            context += "- \(dateStr): \(receipt.note.title) — $\(String(format: "%.2f", receipt.amount)) (\(receipt.category))\n"
        }

        return context
    }

    private func searchVisits(keywords: [String]?, dateRange: (start: Date, end: Date)?, limit: Int) async -> String {
        // TODO: Implement visit search
        return ""
    }

    private func searchEmails(keywords: [String]?, dateRange: (start: Date, end: Date)?, limit: Int, filters: [String: String]?) async -> String {
        // TODO: Implement email search
        return ""
    }

    private func searchEvents(keywords: [String]?, dateRange: (start: Date, end: Date)?, limit: Int) async -> String {
        // TODO: Implement event search
        return ""
    }

    private func searchNotes(keywords: [String]?, limit: Int) async -> String {
        // TODO: Implement note search
        return ""
    }

    private func searchPeople(keywords: [String]?) async -> String {
        // TODO: Implement people search
        return ""
    }

    /// Parse natural language date range into actual dates
    private func parseDateRange(_ dateStr: String) async -> (start: Date, end: Date)? {
        // Reuse existing date extraction logic
        return await extractDateRange(from: dateStr)
    }

    // MARK: - Main Context Building

    /// Build optimized context for LLM using vector search
    /// This is the main replacement for buildContextPrompt(forQuery:)
    /// CACHING OPTIMIZATION: Context is structured for Gemini 2.5 implicit caching
    /// - Static content (system instructions, schema) goes FIRST
    /// - Variable content (user query, search results) goes LAST
    /// - This enables 75% discount on cached tokens automatically
    func buildContext(forQuery query: String) async -> ContextResult {
        let startTime = Date()

        var context = ""
        var metadata = ContextMetadata()

        // 1. STATIC: Essential context (optimized for caching - date only, no time)
        context += buildEssentialContext()
        
        // 2. Add user memory context (learned preferences, entity relationships, etc.)
        let memoryContext = await UserMemoryService.shared.getMemoryContext()
        if !memoryContext.isEmpty {
            context += memoryContext
        }
        
        // 3. NEW APPROACH: LLM Query Planning
        print("📋 Generating query plan...")
        if let queryPlan = await generateQueryPlan(for: query) {
            print("✅ Query plan generated with \(queryPlan.searches.count) searches")

            // Execute the search plan
            let searchResults = await executeSearchPlan(queryPlan)
            if !searchResults.isEmpty {
                context += searchResults
                metadata.usedCompleteDayData = true  // Mark as using structured data
            } else {
                print("⚠️ No results from query plan, falling back to vector search")
                // Fallback to vector search if no results
                let relevantContext = try? await vectorSearch.getRelevantContext(
                    forQuery: query,
                    limit: 50,
                    dateRange: nil
                )
                if let relevantContext = relevantContext, !relevantContext.isEmpty {
                    context += "\n" + relevantContext
                    metadata.usedVectorSearch = true
                }
            }
        } else {
            // Fallback: If query planning fails, use vector search
            print("⚠️ Query planning failed, falling back to vector search")
            do {
                let relevantContext = try await vectorSearch.getRelevantContext(
                    forQuery: query,
                    limit: 50,
                    dateRange: nil
                )
                if !relevantContext.isEmpty {
                    context += "\n" + relevantContext
                    metadata.usedVectorSearch = true
                }
            } catch {
                print("⚠️ Vector search failed: \(error)")
                context += "\n[Context unavailable - using minimal context]\n"
            }
        }
        
        // 6. Calculate token estimate
        metadata.estimatedTokens = estimateTokenCount(context)
        metadata.buildTime = Date().timeIntervalSince(startTime)

        print("📊 Context built: ~\(metadata.estimatedTokens) tokens in \(String(format: "%.2f", metadata.buildTime))s")

        // DEBUG: Log context structure
        #if DEBUG
        if ProcessInfo.processInfo.environment["DEBUG_CONTEXT_TYPE"] != nil {
            print("📊 CONTEXT STRUCTURE:")
            print("  - Query Planning: \(!metadata.usedVectorSearch && metadata.usedCompleteDayData)")
            print("  - Vector Search Fallback: \(metadata.usedVectorSearch)")
            print("  - Estimated Tokens: \(metadata.estimatedTokens)")
        }
        #endif

        return ContextResult(context: context, metadata: metadata)
    }
    
    /// Build compact context for voice mode (even smaller)
    func buildVoiceContext(forQuery query: String) async -> String {
        // Backwards-compatible API: voice mode now uses the SAME context as chat mode.
        // (Response concision is handled by the voice-mode system prompt, not by hiding data.)
        let result = await buildContext(forQuery: query)
        return result.context
    }
    
    // MARK: - Essential Context
    
    /// Build essential context that's always included
    /// OPTIMIZATION: This is structured for Gemini 2.5 implicit caching (75% discount on cached tokens)
    /// Keep this stable across requests - avoid including frequently changing data like current time
    private func buildEssentialContext() -> String {
        var context = ""

        // Current date (NO TIME - for cache stability)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none  // Changed from .short to .none for caching
        dateFormatter.timeZone = TimeZone.current

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        dayFormatter.timeZone = TimeZone.current

        context += "=== CURRENT DATE ===\n"
        context += "Today: \(dayFormatter.string(from: Date())), \(dateFormatter.string(from: Date()))\n"
        
        let utcOffset = TimeZone.current.secondsFromGMT() / 3600
        let utcSign = utcOffset >= 0 ? "+" : ""
        context += "Timezone: \(TimeZone.current.identifier) (UTC\(utcSign)\(utcOffset))\n\n"
        
        // Current location
        let locationService = LocationService.shared
        if let currentLocation = locationService.currentLocation {
            context += "=== CURRENT LOCATION ===\n"
            context += "Location: \(locationService.locationName)\n"
            context += "Coordinates: \(String(format: "%.4f", currentLocation.coordinate.latitude)), \(String(format: "%.4f", currentLocation.coordinate.longitude))\n\n"
        }

        // Current weather
        let weatherService = WeatherService.shared
        if let weather = weatherService.weatherData {
            context += "=== CURRENT WEATHER ===\n"
            context += "Temperature: \(weather.temperature)°C\n"
            context += "Conditions: \(weather.description)\n"
            context += "Location: \(weather.locationName)\n\n"
        }

        // Data summary (quick counts)
        context += "=== DATA AVAILABLE ===\n"
        context += "Events: \(TaskManager.shared.tasks.values.flatMap { $0 }.count)\n"
        context += "Notes: \(NotesManager.shared.notes.count)\n"
        context += "Emails: \(EmailService.shared.inboxEmails.count + EmailService.shared.sentEmails.count)\n"
        context += "Locations: \(LocationsManager.shared.savedPlaces.count)\n"
        let peopleCount = PeopleManager.shared.people.count
        context += "People: \(peopleCount)\n"
        if peopleCount > 0 {
            let peopleNames = PeopleManager.shared.people.prefix(10).map { $0.name }
            context += "  (Sample: \(peopleNames.joined(separator: ", "))\(peopleCount > 10 ? "... and \(peopleCount - 10) more" : ""))\n"
        }
        context += "\n"
        
        // Critical instruction to prevent hallucination
        context += "🚨 CRITICAL INSTRUCTION:\n"
        context += "- ONLY answer questions using data explicitly provided in this context.\n"
        context += "- If data for a specific time period is NOT in the context, say \"I don't have data for that period.\"\n"
        context += "- NEVER invent, fabricate, or estimate data that isn't explicitly shown.\n"
        context += "- When comparing time periods, check if BOTH periods have data before answering.\n\n"
        
        return context
    }
    
    // MARK: - Query Type Detection

    /// Detect if query is date-specific or semantic
    private func detectQueryType(_ query: String, dateRange: (start: Date, end: Date)?) -> QueryType {
        // If date range detected, it's date-specific
        if dateRange != nil {
            return .dateSpecific
        }

        // Check for semantic keywords
        let lowercaseQuery = query.lowercased()
        let semanticKeywords = ["all", "every", "list", "show me", "history", "past"]
        let hasSemanticKeyword = semanticKeywords.contains { lowercaseQuery.contains($0) }

        return hasSemanticKeyword ? .semantic : .dateSpecific
    }

    enum QueryType {
        case dateSpecific    // "haircut today", "what did I do yesterday"
        case semantic       // "all haircuts", "meetings with John"
    }

    // MARK: - Date Extraction

    /// Extract date range from query using LLM intelligence
    /// This avoids hardcoding date patterns - the LLM understands natural language dates
    private func extractDateRange(from query: String) async -> (start: Date, end: Date)? {
        // First, try simple explicit date patterns (fast, no LLM call needed)
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)

        // Quick checks for common explicit patterns
        let lower = query.lowercased()

        // EXPLICIT PATTERN MATCHING for "today" (fast path, no LLM needed)
        if lower.contains("today") || lower.contains("my day") {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
                return nil
            }
            print("📅 Date extraction (pattern): Detected 'today' - Range: \(todayStart) to \(dayEnd)")
            return (start: todayStart, end: dayEnd)
        }

        // EXPLICIT PATTERN MATCHING for "yesterday" (fast path, no LLM needed)
        if lower.contains("yesterday") {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
                return nil
            }
            let dayEnd = todayStart  // Yesterday's end is today's start
            print("📅 Date extraction (pattern): Detected 'yesterday' - Range: \(yesterday) to \(dayEnd)")
            return (start: yesterday, end: dayEnd)
        }

        // "this weekend" — check BEFORE "this week" ("this weekend" contains "this week" as substring)
        if lower.contains("this weekend") {
            let weekday = calendar.component(.weekday, from: today) // 1=Sun...7=Sat
            let daysToLastSat = weekday % 7 // 0 for Sat, 1 for Sun, 2 for Mon, etc.
            let isWeekend = weekday == 1 || weekday == 7
            let saturday: Date
            if isWeekend {
                saturday = calendar.date(byAdding: .day, value: -daysToLastSat, to: todayStart)!
            } else {
                saturday = calendar.date(byAdding: .day, value: 7 - daysToLastSat, to: todayStart)!
            }
            guard let mondayAfter = calendar.date(byAdding: .day, value: 2, to: saturday) else { return nil }
            print("📅 Date extraction (pattern): Detected 'this weekend' - Range: \(saturday) to \(mondayAfter)")
            return (start: saturday, end: mondayAfter)
        }

        // "last weekend" — check BEFORE "last week" (same substring reason)
        if lower.contains("last weekend") {
            let weekday = calendar.component(.weekday, from: today)
            let daysToLastSat = weekday % 7
            let isWeekend = weekday == 1 || weekday == 7
            let saturday: Date
            if isWeekend {
                saturday = calendar.date(byAdding: .day, value: -(daysToLastSat + 7), to: todayStart)!
            } else {
                saturday = calendar.date(byAdding: .day, value: -daysToLastSat, to: todayStart)!
            }
            guard let mondayAfter = calendar.date(byAdding: .day, value: 2, to: saturday) else { return nil }
            print("📅 Date extraction (pattern): Detected 'last weekend' - Range: \(saturday) to \(mondayAfter)")
            return (start: saturday, end: mondayAfter)
        }

        // "this week" (Mon–Sun)
        if lower.contains("this week") {
            let weekday = calendar.component(.weekday, from: today)
            let daysFromMonday = weekday == 1 ? 6 : weekday - 2
            guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: todayStart),
                  let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) else { return nil }
            print("📅 Date extraction (pattern): Detected 'this week' - Range: \(monday) to \(nextMonday)")
            return (start: monday, end: nextMonday)
        }

        // "last week"
        if lower.contains("last week") {
            let weekday = calendar.component(.weekday, from: today)
            let daysFromMonday = weekday == 1 ? 6 : weekday - 2
            guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday - 7, to: todayStart),
                  let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) else { return nil }
            print("📅 Date extraction (pattern): Detected 'last week' - Range: \(monday) to \(nextMonday)")
            return (start: monday, end: nextMonday)
        }

        // "this month"
        if lower.contains("this month") {
            let components = calendar.dateComponents([.year, .month], from: today)
            guard let firstOfMonth = calendar.date(from: components),
                  let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else { return nil }
            print("📅 Date extraction (pattern): Detected 'this month' - Range: \(firstOfMonth) to \(firstOfNextMonth)")
            return (start: firstOfMonth, end: firstOfNextMonth)
        }

        // "last month"
        if lower.contains("last month") {
            let components = calendar.dateComponents([.year, .month], from: today)
            guard let firstOfMonth = calendar.date(from: components),
                  let firstOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) else { return nil }
            print("📅 Date extraction (pattern): Detected 'last month' - Range: \(firstOfLastMonth) to \(firstOfMonth)")
            return (start: firstOfLastMonth, end: firstOfMonth)
        }

        // Explicit ISO dates (fast path)
        if let range = lower.range(of: "\\b\\d{4}-\\d{2}-\\d{2}\\b", options: .regularExpression) {
            let token = String(lower[range])
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            if let targetDate = df.date(from: token) {
                let dayStart = calendar.startOfDay(for: targetDate)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
                print("📅 Date extraction (pattern): Detected ISO date '\(token)' - Range: \(dayStart) to \(dayEnd)")
                return (start: dayStart, end: dayEnd)
            }
        }
        
        // Check cache first to avoid redundant LLM calls
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = dateExtractionCache[cacheKey] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < dateExtractionCacheTTL {
                print("📅 Date extraction cache hit (age: \(Int(age))s): '\(query)'")
                return cached.result
            } else {
                // Cache expired, remove it
                dateExtractionCache.removeValue(forKey: cacheKey)
            }
        }

        // Use LLM to extract date from natural language query
        // This handles "two weeks ago", "same day last week", "the last 3 days", etc.
        do {
            let yesterdayStr = calendar.date(byAdding: .day, value: -1, to: todayStart)!.ISO8601Format().prefix(10)
            let twoWeeksAgoStr = calendar.date(byAdding: .day, value: -14, to: todayStart)!.ISO8601Format().prefix(10)
            let threeDaysAgoStr = calendar.date(byAdding: .day, value: -3, to: todayStart)!.ISO8601Format().prefix(10)
            let tomorrowStr = calendar.date(byAdding: .day, value: 1, to: todayStart)!.ISO8601Format().prefix(10)

            let dateExtractionPrompt = """
            Extract the date or date range from this user query. Today is \(DateFormatter.localizedString(from: today, dateStyle: .full, timeStyle: .none)).

            User query: "\(query)"

            Respond with EXACTLY one of these formats:

            For a single day:
            START: YYYY-MM-DD

            For a date range:
            START: YYYY-MM-DD
            END: YYYY-MM-DD

            If no date is mentioned:
            NONE

            Rules:
            - START is the first day (inclusive)
            - END is the day AFTER the last day (exclusive). Example: Saturday+Sunday range → END is Monday.
            - For a single day, omit the END line.

            Examples:
            - "yesterday" → START: \(yesterdayStr)
            - "two weeks ago" → START: \(twoWeeksAgoStr)
            - "the last 3 days" → START: \(threeDaysAgoStr)\nEND: \(tomorrowStr)
            - "today and yesterday" → START: \(yesterdayStr)\nEND: \(tomorrowStr)
            - "no date mentioned" → NONE

            Respond with ONLY the START/END lines or NONE. No other text.
            """

            let response = try await GeminiService.shared.simpleChatCompletion(
                systemPrompt: "You are a date extraction assistant. Extract dates from user queries. Respond with START:/END: lines or NONE.",
                messages: [["role": "user", "content": dateExtractionPrompt]]
            )

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.uppercased().contains("NONE") {
                print("📅 Date extraction: No date found in query (LLM response: 'none')")
                dateExtractionCache[cacheKey] = (result: nil, timestamp: Date())
                return nil
            }

            // Extract all YYYY-MM-DD dates from the response
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = "yyyy-MM-dd"

            let datePattern = #"\d{4}-\d{2}-\d{2}"#
            let regex = try NSRegularExpression(pattern: datePattern)
            let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            let dates = matches.compactMap { match -> Date? in
                guard let range = Range(match.range, in: trimmed) else { return nil }
                return df.date(from: String(trimmed[range]))
            }.map { calendar.startOfDay(for: $0) }

            guard let startDate = dates.first else {
                print("⚠️ Date extraction: No valid date found in LLM response: '\(trimmed)'")
                dateExtractionCache[cacheKey] = (result: nil, timestamp: Date())
                return nil
            }

            let endDate: Date
            if dates.count > 1 {
                endDate = dates[1]
                print("📅 Date extraction (LLM): Range \(startDate) to \(endDate) from query: '\(query)'")
            } else {
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
                print("📅 Date extraction (LLM): Single day \(startDate) from query: '\(query)'")
            }

            let result = (start: startDate, end: endDate)
            dateExtractionCache[cacheKey] = (result: result, timestamp: Date())
            return result
        } catch {
            print("⚠️ Date extraction (LLM) failed: \(error), falling back to no date filter")
            dateExtractionCache[cacheKey] = (result: nil, timestamp: Date())
            return nil
        }
    }
    
    // MARK: - Date Completeness Context
    
    /// Fetch ALL items for a date range to guarantee completeness
    /// This ensures "what did I do yesterday" gets ALL visits/events/receipts, not just top-k
    private func buildDayCompletenessContext(dateRange: (start: Date, end: Date)) async -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return ""
        }
        
        let dayStart = dateRange.start
        let dayEnd = dateRange.end
        
        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateStyle = .full
        dayLabelFormatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        let isSingleDay: Bool = {
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return true }
            return nextDay >= dayEnd
        }()

        var context: String
        if isSingleDay {
            context = "\n=== COMPLETE DATA ===\n"
            context += "Date: \(dayLabelFormatter.string(from: dayStart))\n"
        } else {
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: dayEnd) ?? dayEnd
            context = "\n=== COMPLETE DATA ===\n"
            context += "Date range: \(dayLabelFormatter.string(from: dayStart)) – \(dayLabelFormatter.string(from: lastDay))\n"
        }
        context += "This is the authoritative list of ALL items for this period.\n\n"
        
        print("📊 Building day completeness context for: \(dayLabelFormatter.string(from: dayStart))")
        
        // 1. Visits (source-of-truth from location_visits)
        var visitsForDay: [LocationVisitRecord] = []
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            
            // Fetch wider window to handle timezone issues
            let widenHours: TimeInterval = 12 * 60 * 60
            let fetchStart = dayStart.addingTimeInterval(-widenHours)
            let fetchEnd = dayEnd.addingTimeInterval(widenHours)
            
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: iso.string(from: fetchStart))
                .lt("entry_time", value: iso.string(from: fetchEnd))
                .order("entry_time", ascending: true)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let fetched: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            
            // Filter to local day window
            visitsForDay = fetched.filter { visit in
                let start = visit.entryTime
                let end = visit.exitTime ?? visit.entryTime
                return start < dayEnd && end >= dayStart
            }
            
            print("📍 Found \(visitsForDay.count) visits for \(dayLabelFormatter.string(from: dayStart))")
            if !visitsForDay.isEmpty {
                context += "VISITS (\(visitsForDay.count)):\n"
                for visit in visitsForDay {
                    let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                    let placeName = place?.displayName ?? "Unknown Location"
                    let start = visit.entryTime
                    let end = visit.exitTime
                    let range = end != nil ? "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end!))" : "\(timeFormatter.string(from: start))–(ongoing)"
                    let duration = visit.durationMinutes.map { "\($0)m" } ?? "unknown duration"
                    let notes = (visit.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Get people connected to this visit
                    let peopleForVisit = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)
                    let peopleNames = peopleForVisit.map { $0.name }
                    
                    var visitLine = "- \(range) • \(placeName) • \(duration)"
                    if !peopleNames.isEmpty {
                        visitLine += " • With: \(peopleNames.joined(separator: ", "))"
                    }
                    if !notes.isEmpty {
                        visitLine += " • Reason: \(notes)"
                    }
                    context += visitLine + "\n"
                }
                context += "\n"
            }
        } catch {
            print("⚠️ Failed to fetch visits for day: \(error)")
        }
        
        // 2. Events/Tasks (source-of-truth from TaskManager)
        do {
            let tagManager = TagManager.shared

            // Collect tasks for ALL days in the date range
            var allTasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            var iterDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
            while iterDay < dayEnd {
                let moreTasks = TaskManager.shared.getTasksForDate(iterDay).filter { !$0.isDeleted }
                allTasks.append(contentsOf: moreTasks)
                guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: iterDay) else { break }
                iterDay = nextDay
            }

            // Deduplicate by ID (recurring tasks may appear on multiple days)
            var seenIds = Set<String>()
            let tasks = allTasks.filter { task in
                if seenIds.contains(task.id) { return false }
                seenIds.insert(task.id)
                return true
            }

            // Validate tasks fall within the date range
            let validTasks = tasks.filter { task in
                if let targetDate = task.targetDate {
                    let isInRange = targetDate >= dayStart && targetDate < dayEnd
                    if !isInRange {
                        print("⚠️ MISMATCH: Task '\(task.title)' targetDate \(targetDate) outside range \(dayStart)–\(dayEnd)")
                    }
                    return isInRange
                }
                if let scheduledTime = task.scheduledTime {
                    let isInRange = scheduledTime >= dayStart && scheduledTime < dayEnd
                    if !isInRange {
                        print("⚠️ MISMATCH: Task '\(task.title)' scheduledTime \(scheduledTime) outside range \(dayStart)–\(dayEnd)")
                    }
                    return isInRange
                }
                return true
            }

            let rangeLabel = isSingleDay ? dayLabelFormatter.string(from: dayStart) : "\(dayLabelFormatter.string(from: dayStart))–\(dayLabelFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: dayEnd) ?? dayEnd))"
            print("📋 Day completeness: Found \(validTasks.count) validated events for \(rangeLabel)")
            for task in validTasks {
                let timeDesc = task.scheduledTime != nil ? timeFormatter.string(from: task.scheduledTime!) : "all-day"
                print("   - \(task.title) @ \(timeDesc)")
            }

            if !validTasks.isEmpty {
                context += "EVENTS/TASKS (\(validTasks.count)):\n"
                for t in validTasks.sorted(by: { ($0.scheduledTime ?? $0.targetDate ?? $0.createdAt) < ($1.scheduledTime ?? $1.targetDate ?? $1.createdAt) }) {
                    let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                    
                    let timeLabel: String = {
                        if t.scheduledTime == nil, t.targetDate != nil { return "[All-day]" }
                        if let st = t.scheduledTime, let et = t.endTime {
                            let tf = DateFormatter()
                            tf.timeStyle = .short
                            let sameDay = Calendar.current.isDate(st, inSameDayAs: et)
                            if sameDay { return "\(tf.string(from: st)) - \(tf.string(from: et))" }
                            let df = DateFormatter()
                            df.dateStyle = .short
                            df.timeStyle = .short
                            return "\(df.string(from: st)) → \(df.string(from: et))"
                        }
                        if let st = t.scheduledTime {
                            let tf = DateFormatter()
                            tf.timeStyle = .short
                            return tf.string(from: st)
                        }
                        return ""
                    }()
                    
                    let loc = (t.location?.isEmpty == false) ? " @ \(t.location!)" : ""
                    context += "- \(timeLabel) \(t.title) — \(tagName)\(loc)\n"
                    if let desc = t.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        context += "  - \(desc.prefix(160))\n"
                    }
                }
                context += "\n"
            }
        }
        
        // 3. Receipts (source-of-truth from receipt notes)
        var receiptNotes: [(note: Note, date: Date, amount: Double, category: String)] = []
        do {
            let notesManager = NotesManager.shared
            let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()

            func isUnderReceiptsFolderHierarchy(folderId: UUID?) -> Bool {
                guard let folderId else { return false }
                if folderId == receiptsFolderId { return true }
                if let folder = notesManager.folders.first(where: { $0.id == folderId }),
                   let parentId = folder.parentFolderId {
                    return isUnderReceiptsFolderHierarchy(folderId: parentId)
                }
                return false
            }

            receiptNotes = notesManager.notes
                .filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
                .compactMap { note -> (note: Note, date: Date, amount: Double, category: String)? in
                    let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                    guard date >= dayStart && date < dayEnd else { return nil }
                    let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                    let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                    return (note, date, amount, category)
                }
            
            if !receiptNotes.isEmpty {
                let total = receiptNotes.reduce(0.0) { $0 + $1.amount }
                context += "RECEIPTS (\(receiptNotes.count)) — Total $\(String(format: "%.2f", total)):\n"
                for r in receiptNotes.sorted(by: { $0.amount > $1.amount }) {
                    // Link receipt to people via nearby visits
                    let linkedPeople = await linkReceiptToPeople(receipt: r, visits: visitsForDay)
                    var receiptLine = "- \(r.note.title) — $\(String(format: "%.2f", r.amount)) (\(r.category))"
                    if !linkedPeople.isEmpty {
                        receiptLine += " — With: \(linkedPeople.joined(separator: ", "))"
                    }
                    context += receiptLine + "\n"
                }
                context += "\n"
            }
        }

        // 4. RELATED CONTEXT - Synthesize connections across data types
        context += "RELATED CONTEXT (Smart Connections):\n"
        var hasRelatedData = false

        // Link receipts to events at same time
        for r in receiptNotes.sorted(by: { $0.amount > $1.amount }).prefix(5) {
            let receiptTime = r.date
            let allTasks = TaskManager.shared.tasks.values.flatMap { $0 }
            let nearbyTasks = allTasks.filter { task in
                guard let taskTime = task.scheduledTime else { return false }
                return abs(taskTime.timeIntervalSince(receiptTime)) < 2 * 60 * 60  // Within 2 hours
            }

            if !nearbyTasks.isEmpty {
                hasRelatedData = true
                let taskNames = nearbyTasks.map { $0.title }.joined(separator: ", ")
                context += "💡 Receipt '\(r.note.title)' ($\(String(format: "%.2f", r.amount))) occurred during: \(taskNames)\n"
            }
        }

        // Link visits to receipts and events
        for visit in visitsForDay.prefix(5) {
            let visitTime = visit.entryTime
            let nearbyReceipts = receiptNotes.filter { receipt in
                abs(receipt.date.timeIntervalSince(visitTime)) < 2 * 60 * 60
            }

            if !nearbyReceipts.isEmpty {
                hasRelatedData = true
                let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                let placeName = place?.displayName ?? "Unknown Location"
                let receiptTitles = nearbyReceipts.map { $0.note.title }.joined(separator: ", ")
                context += "💡 Visit to \(placeName) had these receipts: \(receiptTitles)\n"
            }
        }

        if !hasRelatedData {
            context += "(No notable cross-connections detected for this time period)\n"
        }
        context += "\n"

        return context
    }
    
    // MARK: - Utilities

    /// Link receipts to people by finding visits within ±2 hours at same location
    private func linkReceiptToPeople(
        receipt: (note: Note, date: Date, amount: Double, category: String),
        visits: [LocationVisitRecord]
    ) async -> [String] {
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60

        // Find visits within ±2 hours of receipt time
        let nearbyVisits = visits.filter { visit in
            let timeDiff = abs(visit.entryTime.timeIntervalSince(receipt.date))
            return timeDiff <= twoHoursInSeconds
        }

        var allPeople: [String] = []
        for visit in nearbyVisits {
            let people = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)
            allPeople.append(contentsOf: people.map { $0.name })
        }

        return Array(Set(allPeople))  // Remove duplicates
    }

    /// Estimate token count (rough: ~4 chars per token)
    private func estimateTokenCount(_ text: String) -> Int {
        return text.count / 4
    }
    
    // MARK: - Types
    
    struct ContextResult {
        let context: String
        let metadata: ContextMetadata
    }
    
    struct ContextMetadata {
        var usedVectorSearch: Bool = false
        var usedCompleteDayData: Bool = false
        var estimatedTokens: Int = 0
        var buildTime: TimeInterval = 0
    }
}
