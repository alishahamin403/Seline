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
    private let monthNameToNumber: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12
    ]

    // MARK: - Configuration

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

    // MARK: - Query Understanding (single LLM decides: date range vs vector vs clarify)

    /// Result of the query-understanding LLM: use DB for this date range, vector search, or ask for clarification.
    private enum QueryUnderstandingResult {
        case dateRange(start: Date, end: Date)
        case vectorSearch
        case clarify(question: String)
    }

    /// Cost optimization: only run query-understanding LLM when the prompt likely depends on time disambiguation.
    private func shouldUseQueryUnderstandingLLM(
        query: String,
        conversationHistory: [(role: String, content: String)]
    ) -> Bool {
        let lower = query.lowercased()

        // Explicit date/time language where DB date-range retrieval helps accuracy.
        let dateKeywords = [
            "today", "yesterday", "tomorrow", "week", "weekend", "month", "year",
            "last", "next", "ago", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]
        if dateKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        // Absolute date formats.
        if lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b"#, options: .regularExpression) != nil {
            return true
        }

        // Referential follow-ups ("that", "then", etc.) benefit from disambiguation.
        if !conversationHistory.isEmpty {
            let referenceTerms = ["that", "then", "there", "same day", "before that", "after that", "that weekend"]
            if referenceTerms.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        // General semantic questions can skip this extra LLM hop.
        return false
    }

    private struct DeterministicTemporalRange {
        let start: Date
        let end: Date
        let weekendOnly: Bool
        let reason: String
    }

    /// Deterministic routing for explicit month/year queries.
    /// Example handled: "any weekend in January 2026".
    private func deterministicTemporalRange(for query: String) -> DeterministicTemporalRange? {
        let lower = query.lowercased()
        let weekendOnly = lower.contains("weekend")
        let calendar = Calendar.current

        // Match single "month year" mention (e.g., January 2026, jan 2026).
        let pattern = #"\b(?:in|of)?\s*(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\s*,?\s*(\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))

        // If multiple explicit month-year mentions are present, let the LLM handle comparison logic.
        guard matches.count == 1,
              let match = matches.first,
              let monthRange = Range(match.range(at: 1), in: lower),
              let yearRange = Range(match.range(at: 2), in: lower) else {
            return nil
        }

        let monthKey = String(lower[monthRange])
        guard let month = monthNameToNumber[monthKey], let year = Int(String(lower[yearRange])) else {
            return nil
        }

        var startComponents = DateComponents()
        startComponents.calendar = calendar
        startComponents.timeZone = TimeZone.current
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1

        guard let monthStart = calendar.date(from: startComponents),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return nil
        }

        let reason = weekendOnly
            ? "explicit weekend-in-month query (\(monthKey) \(year))"
            : "explicit month-year query (\(monthKey) \(year))"
        return DeterministicTemporalRange(
            start: calendar.startOfDay(for: monthStart),
            end: calendar.startOfDay(for: monthEnd),
            weekendOnly: weekendOnly,
            reason: reason
        )
    }

    private func buildWeekendOnlyCompletenessContext(dateRange: (start: Date, end: Date)) async -> String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .full
        dayFormatter.timeStyle = .none

        var context = "\n=== COMPLETE WEEKEND DATA ===\n"
        let lastDay = calendar.date(byAdding: .day, value: -1, to: dateRange.end) ?? dateRange.end
        context += "Date range: \(dayFormatter.string(from: dateRange.start)) – \(dayFormatter.string(from: lastDay))\n"
        context += "Only Saturday/Sunday data is included for this query.\n\n"

        var cursor = dateRange.start
        var weekendCount = 0

        while cursor < dateRange.end {
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun ... 7=Sat
            if weekday == 1 || weekday == 7 {
                let weekendStart: Date
                let weekendEnd: Date

                if weekday == 7 {
                    weekendStart = cursor
                    weekendEnd = min(
                        dateRange.end,
                        calendar.date(byAdding: .day, value: 2, to: weekendStart) ?? dateRange.end
                    )
                } else {
                    let previousSaturday = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                    if previousSaturday >= dateRange.start {
                        weekendStart = previousSaturday
                        weekendEnd = min(
                            dateRange.end,
                            calendar.date(byAdding: .day, value: 2, to: weekendStart) ?? dateRange.end
                        )
                    } else {
                        // Range starts on Sunday; include just that in-range day.
                        weekendStart = cursor
                        weekendEnd = min(
                            dateRange.end,
                            calendar.date(byAdding: .day, value: 1, to: weekendStart) ?? dateRange.end
                        )
                    }
                }

                weekendCount += 1
                context += "=== WEEKEND \(weekendCount) (\(dayFormatter.string(from: weekendStart))) ===\n"
                context += await buildDayCompletenessContext(dateRange: (start: weekendStart, end: weekendEnd))
                context += "\n"

                cursor = weekendEnd
                continue
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? dateRange.end
        }

        if weekendCount == 0 {
            context += "(No weekend dates in this range)\n"
        }

        return context
    }

    /// Single LLM call: decide if the query is about a specific date/range (→ DB), general (→ vector), or vague (→ clarify).
    /// Uses conversation history to resolve "that", "last weekend", "last last weekend", etc. No pattern list.
    private func understandQuery(query: String, conversationHistory: [(role: String, content: String)]) async -> QueryUnderstandingResult {
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: todayStart)

        // Compute "last weekend" and "weekend before that" so the model has exact reference dates
        var referenceBlock = ""
        let weekday = calendar.component(.weekday, from: today) // 1=Sun ... 7=Sat
        let daysToLastSat = (weekday == 7) ? 0 : (weekday == 1 ? 1 : weekday)
        if let lastSaturday = calendar.date(byAdding: .day, value: -daysToLastSat, to: todayStart),
           let lastWeekendEnd = calendar.date(byAdding: .day, value: 2, to: lastSaturday),
           let weekendBeforeStart = calendar.date(byAdding: .day, value: -7, to: lastSaturday),
           let weekendBeforeEnd = calendar.date(byAdding: .day, value: -5, to: lastSaturday) {
            let lastWeekendStartStr = df.string(from: lastSaturday)
            let lastWeekendEndStr = df.string(from: lastWeekendEnd)
            let weekendBeforeStartStr = df.string(from: weekendBeforeStart)
            let weekendBeforeEndStr = df.string(from: weekendBeforeEnd)
            referenceBlock = "\nReference (use these exact dates): \"Last weekend\" = \(lastWeekendStartStr) to \(lastWeekendEndStr) (output START: \(lastWeekendStartStr), END: \(lastWeekendEndStr)). \"Last last weekend\" or \"the weekend before that\" = \(weekendBeforeStartStr) to \(weekendBeforeEndStr) (output START: \(weekendBeforeStartStr), END: \(weekendBeforeEndStr)).\n\n"
        }

        let recentTurns = conversationHistory.suffix(6)
        let historyBlock = recentTurns.isEmpty ? "" : """
            Recent conversation (use this to resolve references like "that", "last weekend", "the weekend before that"):
            \(recentTurns.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))

            """

        let prompt = """
            Today's date is \(todayStr). User's message: "\(query)"

            \(historyBlock)\(referenceBlock)Decide what the user is asking for. Respond with EXACTLY one of these (no other text):

            1) If they are asking about a SPECIFIC day or date range (e.g. "how was my day yesterday", "what did I do last weekend", "last last weekend", "the weekend before that", "two weeks ago"), output the date range:
            START: YYYY-MM-DD
            END: YYYY-MM-DD
            (START = first day inclusive, END = day after last day. For a single day, END = next day. For a weekend Sat–Sun, END = Monday.)

            2) If they are asking something general with NO specific date (e.g. "where do I go most", "summarize my spending", "my top locations"), output:
            NONE

            3) If the request is too vague even with the conversation and you cannot infer what they mean, output:
            CLARIFY: <one short clarifying question>

            Respond with ONLY the chosen option (START/END lines, or NONE, or CLARIFY: ...).
            """

        do {
            let response = try await GeminiService.shared.simpleChatCompletion(
                systemPrompt: "You are a query understanding assistant. Output only START/END, NONE, or CLARIFY: as instructed. Use the conversation to resolve time references like 'that' or 'last last weekend'.",
                messages: [["role": "user", "content": prompt]],
                operationType: "query_understanding"
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // CLARIFY
            if trimmed.uppercased().hasPrefix("CLARIFY:") {
                let question = trimmed.dropFirst("CLARIFY:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty {
                    print("📅 Query understanding: CLARIFY - \(question.prefix(60))...")
                    return .clarify(question: question)
                }
            }

            // NONE → vector search
            if trimmed.uppercased().contains("NONE") {
                print("📅 Query understanding: NONE (vector search)")
                return .vectorSearch
            }

            // Parse START/END dates
            let datePattern = #"\d{4}-\d{2}-\d{2}"#
            guard let regex = try? NSRegularExpression(pattern: datePattern) else {
                print("📅 Query understanding: parse failed, falling back to vector search")
                return .vectorSearch
            }
            let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            let dates = matches.compactMap { match -> Date? in
                guard let range = Range(match.range, in: trimmed) else { return nil }
                return df.date(from: String(trimmed[range]))
            }.map { calendar.startOfDay(for: $0) }

            guard let startDate = dates.first else {
                print("📅 Query understanding: no dates in response, falling back to vector search")
                return .vectorSearch
            }
            let endDate: Date = dates.count > 1 ? dates[1] : calendar.date(byAdding: .day, value: 1, to: startDate)!
            print("📅 Query understanding: DATE RANGE \(startDate) to \(endDate)")
            return .dateRange(start: startDate, end: endDate)
        } catch {
            print("⚠️ Query understanding failed: \(error), falling back to vector search")
            return .vectorSearch
        }
    }

    // MARK: - REMOVED: Old Query Planning System (~600 lines deleted)
    // The complex QueryPlan system tried to categorize queries into "receipt vs email vs visit"
    // This was fragile and over-engineered. Replaced with unified semantic search below.
    // Vector similarity naturally finds the right documents regardless of type.
    // MARK: - Main Context Building

    /// Build optimized context for LLM using vector search
    /// This is the main replacement for buildContextPrompt(forQuery:)
    /// CACHING OPTIMIZATION: Context is structured for Gemini 2.5 implicit caching
    /// - Static content (system instructions, schema) goes FIRST
    /// - Variable content (user query, search results) goes LAST
    /// - This enables 75% discount on cached tokens automatically
    func buildContext(forQuery query: String, conversationHistory: [(role: String, content: String)] = []) async -> ContextResult {
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

        // 3. Query routing: deterministic temporal parsing first, then LLM understanding.
        var understanding: QueryUnderstandingResult
        var useWeekendOnlyCompleteness = false

        if let forcedRange = deterministicTemporalRange(for: query) {
            understanding = .dateRange(start: forcedRange.start, end: forcedRange.end)
            useWeekendOnlyCompleteness = forcedRange.weekendOnly
            print("📅 Deterministic query understanding: \(forcedRange.reason) → DATE RANGE \(forcedRange.start) to \(forcedRange.end)")
        } else if shouldUseQueryUnderstandingLLM(query: query, conversationHistory: conversationHistory) {
            print("🔍 Query understanding...")
            understanding = await understandQuery(query: query, conversationHistory: conversationHistory)
        } else {
            print("🔍 Query understanding skipped (general query) → vector search")
            understanding = .vectorSearch
        }

        // Guardrail: if LLM returned NONE for a clearly explicit month-year query, force deterministic date range.
        if case .vectorSearch = understanding,
           let fallbackRange = deterministicTemporalRange(for: query) {
            understanding = .dateRange(start: fallbackRange.start, end: fallbackRange.end)
            useWeekendOnlyCompleteness = fallbackRange.weekendOnly
            print("📅 Guardrail routing: LLM returned NONE for explicit temporal query; forcing DATE RANGE \(fallbackRange.start) to \(fallbackRange.end)")
        }

        switch understanding {
        case .clarify(let question):
            context += "\n=== CLARIFICATION NEEDED ===\n"
            context += question + "\n"
            metadata.estimatedTokens = estimateTokenCount(context)
            metadata.buildTime = Date().timeIntervalSince(startTime)
            return ContextResult(context: context, metadata: metadata)

        case .dateRange(let start, let end):
            let dateRange = (start: start, end: end)
            let queryLower = query.lowercased()
            let isComparison = queryLower.contains("compare") || queryLower.contains(" vs ") || queryLower.contains(" versus ") || queryLower.contains("compared to")

            // When user asks to "compare to last week" (or similar), also fetch this week so the model has both periods
            if isComparison {
                let calendar = Calendar.current
                let today = Date()
                let todayStart = calendar.startOfDay(for: today)
                let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                let requestedRangeIsPast = end <= tomorrowStart
                if requestedRangeIsPast {
                    let weekday = calendar.component(.weekday, from: today)
                    let daysSinceMonday = (weekday == 1) ? 6 : (weekday - 2)
                    if let thisWeekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: todayStart) {
                        let thisWeekEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                        let baselineRange = (start: thisWeekStart, end: thisWeekEnd)
                        let baselineContext = await buildDayCompletenessContext(dateRange: baselineRange)
                        if !baselineContext.isEmpty {
                            context += "\n=== PERIOD TO COMPARE AGAINST (This week) ===\n"
                            context += baselineContext
                            metadata.usedCompleteDayData = true
                            print("✅ Added comparison baseline period (this week)")
                        }
                    }
                }
            }

            do {
                let dayContext = useWeekendOnlyCompleteness
                    ? await buildWeekendOnlyCompletenessContext(dateRange: dateRange)
                    : await buildDayCompletenessContext(dateRange: dateRange)
                if !dayContext.isEmpty {
                    if isComparison {
                        context += "\n=== OTHER PERIOD (Requested range, e.g. last week) ===\n"
                    }
                    context += "\n" + dayContext
                    metadata.usedCompleteDayData = true
                    print("✅ Found complete day data via direct DB query")
                } else {
                    print("⚠️ Direct DB query returned nothing, falling back to vector search")
                    let limit = determineSearchLimit(forQuery: query)
                    let relevantContext = try await vectorSearch.getRelevantContext(
                        forQuery: query,
                        limit: limit,
                        dateRange: dateRange
                    )
                    context += "\n" + relevantContext
                    metadata.usedVectorSearch = true
                }
            } catch {
                print("❌ Day completeness / vector search failed: \(error)")
                context += "\n[Search unavailable for this date range]\n"
            }

        case .vectorSearch:
            do {
                let limit = determineSearchLimit(forQuery: query)
                var relevantContext = try await vectorSearch.getRelevantContext(
                    forQuery: query,
                    limit: limit,
                    dateRange: nil
                )
                if !relevantContext.isEmpty {
                    context += "\n" + relevantContext
                    metadata.usedVectorSearch = true
                    // Second pass: if first result is thin, fetch more with expanded limit
                    if relevantContext.count < 2500 {
                        let secondLimit = min(limit + 25, 80)
                        let secondContext = try await vectorSearch.getRelevantContext(
                            forQuery: query,
                            limit: secondLimit,
                            dateRange: nil
                        )
                        if !secondContext.isEmpty && secondContext != relevantContext {
                            context += "\n\n=== ADDITIONAL RELEVANT DATA (second pass) ===\n"
                            context += secondContext
                        }
                    }
                } else {
                    context += "\n[No relevant data found for this query]\n"
                }
            } catch {
                print("❌ Vector search failed: \(error)")
                context += "\n[Search unavailable - using minimal context]\n"
            }
        }
        
        // 5. Calculate token estimate
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
    func buildVoiceContext(forQuery query: String, conversationHistory: [(role: String, content: String)] = []) async -> String {
        // Backwards-compatible API: voice mode now uses the SAME context as chat mode.
        // (Response concision is handled by the voice-mode system prompt, not by hiding data.)
        let result = await buildContext(forQuery: query, conversationHistory: conversationHistory)
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
        context += "Events: \(TaskManager.shared.getAllTasksIncludingArchived().count)\n"
        context += "Notes: \(NotesManager.shared.notes.count)\n"
        context += "Emails: \(EmailService.shared.inboxEmails.count + EmailService.shared.sentEmails.count)\n"
        context += "Locations: \(LocationsManager.shared.savedPlaces.count)\n"
        let peopleCount = PeopleManager.shared.people.count
        context += "People: \(peopleCount)\n\n"

        // IMPORTANT: Include complete people list with birthdays for easy lookup
        if peopleCount > 0 {
            context += "=== YOUR PEOPLE (Complete List) ===\n"
            context += "IMPORTANT: This is the ONLY source of truth for people in the app. Do NOT search the web for random people.\n\n"

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .none

            for person in PeopleManager.shared.people.sorted(by: { $0.name < $1.name }) {
                var personLine = "- \(person.name)"
                if let nickname = person.nickname {
                    personLine += " (aka \(nickname))"
                }
                personLine += " — \(person.relationshipDisplayText)"

                if let birthday = person.birthday {
                    let birthdayStr = dateFormatter.string(from: birthday)
                    personLine += " — Birthday: \(birthdayStr)"
                }

                context += personLine + "\n"
            }
            context += "\n"
        }

        
        // Critical instruction to prevent hallucination
        context += "🚨 CRITICAL INSTRUCTIONS:\n"
        context += "- ONLY use data explicitly provided in this context below.\n"
        context += "- If the context shows \"No relevant data found\", tell the user you don't have that information.\n"
        context += "- NEVER invent, fabricate, estimate, or guess data that isn't in the context.\n"
        context += "- NEVER reference emails, events, or data from future dates (after today).\n"
        context += "- When in doubt, say \"I don't have that information\" instead of guessing.\n\n"
        
        return context
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
        context += "This is the authoritative list of ALL items for this period. Each day is labeled with its weekday and date — use the exact weekday (e.g. Monday, Sunday) when answering.\n\n"
        
        print("📊 Building day completeness context for: \(dayLabelFormatter.string(from: dayStart))")
        
        let calendar = Calendar.current
        
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
            
            print("📍 Found \(visitsForDay.count) visits for range")
        } catch {
            print("⚠️ Failed to fetch visits for day: \(error)")
        }
        
        // 2. Events/Tasks (source-of-truth from TaskManager) — build list for per-day output
        var validTasks: [TaskItem] = []
        do {
            let tagManager = TagManager.shared
            var allTasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            var iterDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            while iterDay < dayEnd {
                let moreTasks = TaskManager.shared.getTasksForDate(iterDay).filter { !$0.isDeleted }
                allTasks.append(contentsOf: moreTasks)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: iterDay) else { break }
                iterDay = nextDay
            }
            var seenIds = Set<String>()
            let tasks = allTasks.filter { task in
                if seenIds.contains(task.id) { return false }
                seenIds.insert(task.id)
                return true
            }
            validTasks = tasks.filter { task in
                if let targetDate = task.targetDate {
                    let isInRange = targetDate >= dayStart && targetDate < dayEnd
                    if !isInRange { print("⚠️ MISMATCH: Task '\(task.title)' targetDate \(targetDate) outside range \(dayStart)–\(dayEnd)") }
                    return isInRange
                }
                if let scheduledTime = task.scheduledTime {
                    let isInRange = scheduledTime >= dayStart && scheduledTime < dayEnd
                    if !isInRange { print("⚠️ MISMATCH: Task '\(task.title)' scheduledTime \(scheduledTime) outside range \(dayStart)–\(dayEnd)") }
                    return isInRange
                }
                return true
            }
            let rangeLabel = isSingleDay ? dayLabelFormatter.string(from: dayStart) : "\(dayLabelFormatter.string(from: dayStart))–\(dayLabelFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: dayEnd) ?? dayEnd))"
            print("📋 Day completeness: Found \(validTasks.count) validated events for \(rangeLabel)")
        }
        
        // 3. Receipts (source-of-truth from receipt notes) — build list for per-day output
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
        }
        
        // 4. Per-day blocks (weekday + date so the model reports e.g. "Monday" not "Saturday")
        var currentDay = dayStart
        while currentDay < dayEnd {
            context += "--- \(dayLabelFormatter.string(from: currentDay)) ---\n"
            let visitsOnDay = visitsForDay.filter { calendar.isDate($0.entryTime, inSameDayAs: currentDay) }
            if !visitsOnDay.isEmpty {
                context += "VISITS (\(visitsOnDay.count)):\n"
                for visit in visitsOnDay {
                    let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                    let placeName = place?.displayName ?? "Unknown Location"
                    let start = visit.entryTime
                    let end = visit.exitTime
                    let range = end != nil ? "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end!))" : "\(timeFormatter.string(from: start))–(ongoing)"
                    let duration = visit.durationMinutes.map { "\($0)m" } ?? "unknown duration"
                    let notes = (visit.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let peopleForVisit = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)
                    let peopleNames = peopleForVisit.map { $0.name }
                    var visitLine = "- \(range) • \(placeName) • \(duration)"
                    if !peopleNames.isEmpty { visitLine += " • With: \(peopleNames.joined(separator: ", "))" }
                    if !notes.isEmpty { visitLine += " • Reason: \(notes)" }
                    context += visitLine + "\n"
                }
                context += "\n"
            }
            let tagManager = TagManager.shared
            let taskDate: (TaskItem) -> Date? = { t in t.scheduledTime ?? t.targetDate ?? t.createdAt }
            let tasksOnDay = validTasks.filter { guard let d = taskDate($0) else { return false }; return calendar.isDate(d, inSameDayAs: currentDay) }
            if !tasksOnDay.isEmpty {
                context += "EVENTS/TASKS (\(tasksOnDay.count)):\n"
                for t in tasksOnDay.sorted(by: { (taskDate($0) ?? .distantPast) < (taskDate($1) ?? .distantPast) }) {
                    let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                    let timeLabel: String = {
                        if t.scheduledTime == nil, t.targetDate != nil { return "[All-day]" }
                        if let st = t.scheduledTime, let et = t.endTime {
                            let tf = DateFormatter(); tf.timeStyle = .short
                            if calendar.isDate(st, inSameDayAs: et) { return "\(tf.string(from: st)) - \(tf.string(from: et))" }
                            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
                            return "\(df.string(from: st)) → \(df.string(from: et))"
                        }
                        if let st = t.scheduledTime {
                            let tf = DateFormatter(); tf.timeStyle = .short
                            return tf.string(from: st)
                        }
                        return ""
                    }()
                    let loc = (t.location?.isEmpty == false) ? " @ \(t.location!)" : ""
                    context += "- \(timeLabel) \(t.title) — \(tagName)\(loc)\n"
                    if let desc = t.description, !desc.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        context += "  - \(desc.prefix(160))\n"
                    }
                }
                context += "\n"
            }
            let receiptsOnDay = receiptNotes.filter { calendar.isDate($0.date, inSameDayAs: currentDay) }
            if !receiptsOnDay.isEmpty {
                let total = receiptsOnDay.reduce(0.0) { $0 + $1.amount }
                context += "RECEIPTS (\(receiptsOnDay.count)) — Total $\(String(format: "%.2f", total)):\n"
                for r in receiptsOnDay.sorted(by: { $0.amount > $1.amount }) {
                    let linkedPeople = await linkReceiptToPeople(receipt: r, visits: visitsForDay)
                    var receiptLine = "- \(r.note.title) — $\(String(format: "%.2f", r.amount)) (\(r.category))"
                    if !linkedPeople.isEmpty { receiptLine += " — With: \(linkedPeople.joined(separator: ", "))" }
                    context += receiptLine + "\n"
                }
                context += "\n"
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        
        // 5. SPENDING SUMMARY - Match receipts to visits with smart connections
        do {
            // Match receipts to visits using time + location name scoring
            let receiptMatches = matchReceiptsToVisits(receipts: receiptNotes, visits: visitsForDay)
            
            // Build spending summary grouped by location
            let spendingSummary = await buildSpendingSummary(matches: receiptMatches, visits: visitsForDay, timeFormatter: timeFormatter)
            if !spendingSummary.isEmpty {
                context += spendingSummary + "\n"
            }
        }

        // 6. RELATED CONTEXT - Synthesize connections across data types
        context += "RELATED CONTEXT (Smart Connections):\n"
        var hasRelatedData = false

        // Link receipts to events at same time
        for r in receiptNotes.sorted(by: { $0.amount > $1.amount }).prefix(5) {
            let receiptTime = r.date
            let allTasks = TaskManager.shared.getAllTasksIncludingArchived()
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
    
    /// Enhanced receipt-to-visit matching with time + location name scoring
    /// Matches within ±2 hours OR if receipt title contains location name (loose matching)
    private struct ReceiptVisitMatch {
        let receipt: (note: Note, date: Date, amount: Double, category: String)
        let visit: LocationVisitRecord?
        let matchType: String // "time", "location", or nil
    }
    
    private func matchReceiptsToVisits(
        receipts: [(note: Note, date: Date, amount: Double, category: String)],
        visits: [LocationVisitRecord]
    ) -> [ReceiptVisitMatch] {
        var matches: [ReceiptVisitMatch] = []
        let twoHours: TimeInterval = 2 * 60 * 60
        
        for receipt in receipts {
            var bestMatch: LocationVisitRecord?
            var matchType: String?
            var bestScore: Double = 0
            
            for visit in visits {
                var score: Double = 0
                var currentMatchType: String?
                
                // Score 1: Time proximity (within ±2 hours)
                let timeDiff = abs(visit.entryTime.timeIntervalSince(receipt.date))
                if timeDiff <= twoHours {
                    // Closer time = higher score
                    score = 1.0 - (timeDiff / twoHours)  // 1.0 for exact match, 0 for 2 hours away
                    currentMatchType = "time"
                }
                
                // Score 2: Location name match (loose matching)
                if let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                    let receiptTitle = receipt.note.title.lowercased()
                    let locationName = place.displayName.lowercased()
                    
                    // Check various matching strategies
                    let hasLocationMatch = 
                        receiptTitle.contains(locationName) ||
                        locationName.contains(receiptTitle) ||
                        receiptTitle.split(separator: " ").contains(where: { locationName.contains($0) }) ||
                        locationName.split(separator: " ").contains(where: { receiptTitle.contains($0) })
                    
                    if hasLocationMatch {
                        // Location match is very strong signal
                        if score > 0 {
                            score += 0.5  // Bonus for time + location match
                            currentMatchType = "location+time"
                        } else {
                            // Location match without time - still consider it
                            score = 0.3
                            currentMatchType = "location"
                        }
                    }
                }
                
                if score > bestScore {
                    bestScore = score
                    bestMatch = visit
                    matchType = currentMatchType
                }
            }
            
            // Only include matches with meaningful score
            if bestScore >= 0.1 {
                matches.append(ReceiptVisitMatch(
                    receipt: receipt,
                    visit: bestMatch,
                    matchType: matchType ?? "time"
                ))
            } else {
                // Receipt with no matching visit
                matches.append(ReceiptVisitMatch(
                    receipt: receipt,
                    visit: nil,
                    matchType: ""
                ))
            }
        }
        
        return matches
    }
    
    /// Build spending summary grouped by location with visit connections
    private func buildSpendingSummary(
        matches: [ReceiptVisitMatch],
        visits: [LocationVisitRecord],
        timeFormatter: DateFormatter
    ) async -> String {
        guard !matches.isEmpty else { return "" }
        
        // Group receipts by visit location
        var locationSpending: [String: (amount: Double, receipts: [(note: Note, amount: Double)], visitTime: Date?)] = [:]
        
        for match in matches {
            let receipt = match.receipt
            let locationName: String
            
            if let visit = match.visit, let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                locationName = place.displayName
            } else {
                locationName = receipt.note.title  // Use receipt title if no visit match
            }
            
            if var existing = locationSpending[locationName] {
                existing.amount += receipt.amount
                existing.receipts.append((note: receipt.note, amount: receipt.amount))
                if let visit = match.visit {
                    existing.visitTime = visit.entryTime
                }
                locationSpending[locationName] = existing
            } else {
                locationSpending[locationName] = (
                    amount: receipt.amount,
                    receipts: [(note: receipt.note, amount: receipt.amount)],
                    visitTime: match.visit?.entryTime
                )
            }
        }
        
        // Build output
        var output = "SPENDING BY LOCATION (Smart Connections):\n"
        let totalSpending = locationSpending.values.reduce(0.0) { $0 + $1.amount }
        output += "Total: $\(String(format: "%.2f", totalSpending)) across \(matches.count) purchases\n\n"
        
        // Sort by amount descending
        for (location, data) in locationSpending.sorted(by: { $0.value.amount > $1.value.amount }) {
            output += "📍 \(location): $\(String(format: "%.2f", data.amount))\n"
            
            // Show individual receipts
            for receipt in data.receipts.sorted(by: { $0.amount > $1.amount }) {
                output += "   • \(receipt.note.title) — $\(String(format: "%.2f", receipt.amount))\n"
            }
            
            // Link to visit if available
            if let visitTime = data.visitTime {
                let timeStr = timeFormatter.string(from: visitTime)
                if let visit = visits.first(where: { $0.entryTime == visitTime }),
                   let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                    let people = await PeopleManager.shared.getPeopleForVisit(visitId: visit.id)
                    if !people.isEmpty {
                        let peopleNames = people.map { $0.name }.joined(separator: ", ")
                        output += "   → Visit at \(timeStr) with \(peopleNames)\n"
                    }
                }
            }
            output += "\n"
        }
        
        return output
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
