import Foundation
import CoreLocation

/**
 * VectorContextBuilder - LLM Context using Vector Search
 *
 * This replaces the old SelineAppContext.buildContextPrompt() method
 * with a vector-based approach that only retrieves relevant data.
 *
 * Benefits:
 * - Much smaller context size (only relevant items)
 * - Faster LLM inference (fewer tokens)
 * - Better relevance (semantic matching vs keywords)
 * - Scales to unlimited data
 */
@MainActor
class VectorContextBuilder {
    static let shared = VectorContextBuilder()
    
    private let vectorSearch = VectorSearchService.shared
    
    // MARK: - Configuration
    
    /// Maximum number of items to retrieve per document type
    private let maxItemsPerType = 5
    
    /// Maximum total items in context
    private let maxTotalItems = 15
    
    /// Always include these regardless of query (essential context)
    private let alwaysIncludeTypes: Set<VectorSearchService.DocumentType> = []
    
    // MARK: - Main Context Building
    
    /// Build optimized context for LLM using vector search
    /// This is the main replacement for buildContextPrompt(forQuery:)
    func buildContext(forQuery query: String) async -> ContextResult {
        let startTime = Date()
        
        var context = ""
        var metadata = ContextMetadata()
        
        // 1. Always include essential context (date, location, weather)
        context += buildEssentialContext()
        
        // 2. Analyze query to understand intent
        let queryIntent = analyzeQueryIntent(query)
        metadata.queryIntent = queryIntent
        
        // 3. Get semantically relevant data via vector search
        do {
            let relevantContext = try await vectorSearch.getRelevantContext(
                forQuery: query,
                limit: maxTotalItems
            )
            
            if !relevantContext.isEmpty {
                context += "\n" + relevantContext
                metadata.usedVectorSearch = true
            }
        } catch {
            print("⚠️ Vector search failed: \(error)")
            // Fallback to minimal context
            context += "\n[Vector search unavailable - using minimal context]\n"
        }
        
        // 4. Add query-specific context that may not be in embeddings
        context += await buildQuerySpecificContext(query: query, intent: queryIntent)
        
        // 5. Calculate token estimate
        metadata.estimatedTokens = estimateTokenCount(context)
        metadata.buildTime = Date().timeIntervalSince(startTime)
        
        print("📊 Context built: ~\(metadata.estimatedTokens) tokens in \(String(format: "%.2f", metadata.buildTime))s")
        
        return ContextResult(context: context, metadata: metadata)
    }
    
    /// Build compact context for voice mode (even smaller)
    func buildVoiceContext(forQuery query: String) async -> String {
        // Backwards-compatible API: voice mode now uses the SAME context as chat mode.
        // (Response concision is handled by the voice-mode system prompt, not by hiding data.)
        let result = await buildContext(forQuery: query)
        return result.context
    }

    private func buildVoiceScheduleSnapshot(daysAhead: Int) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tagManager = TagManager.shared
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        var out = "\nThis week:\n"
        
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let tasks = TaskManager.shared.getTasksForDate(day).filter { !$0.isDeleted }
            guard !tasks.isEmpty else { continue }
            
            let label = offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : dayFormatter.string(from: day)
            out += "- \(label): "
            
            // Keep it voice-friendly: a few key items, plus count.
            let sorted = tasks.sorted { ($0.scheduledTime ?? $0.targetDate ?? $0.createdAt) < ($1.scheduledTime ?? $1.targetDate ?? $1.createdAt) }
            let top = sorted.prefix(3)
            let parts = top.map { t -> String in
                let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                if t.scheduledTime == nil, t.targetDate != nil {
                    return "\(t.title) [All-day, \(tagName)]"
                }
                if let st = t.scheduledTime {
                    return "\(timeFormatter.string(from: st)) \(t.title) [\(tagName)]"
                }
                return "\(t.title) [\(tagName)]"
            }
            out += parts.joined(separator: " · ")
            if tasks.count > 3 {
                out += " (+\(tasks.count - 3) more)"
            }
            out += "\n"
        }
        
        return out
    }
    
    private func buildVoiceSpendingSnapshot() async -> String {
        // Reuse the receipts-day/month summary but keep it short.
        // This is intentionally conservative: voice should highlight key totals and top categories.
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
        
        let receiptNotes = notesManager.notes.filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
        guard !receiptNotes.isEmpty else { return "" }
        
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return "" }
        
        let monthReceipts = receiptNotes.filter { note in
            let d = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
            return d >= monthStart && d <= now
        }
        
        let monthTotal = monthReceipts.reduce(0.0) {
            $0 + CurrencyParser.extractAmount(from: $1.content.isEmpty ? $1.title : $1.content)
        }
        
        // Quick category breakdown (fast heuristic)
        let categorized = monthReceipts.map { note -> (category: String, amount: Double) in
            let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
            let cat = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
            return (cat, amount)
        }
        let byCat = Dictionary(grouping: categorized) { $0.category }
        let topCats = byCat
            .map { (cat, items) in (cat, items.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
        
        let monthName = DateFormatter()
        monthName.dateFormat = "MMMM"
        
        var out = "\nSpending:\n"
        out += "- \(monthName.string(from: now)) so far: $\(String(format: "%.0f", monthTotal)) (\(monthReceipts.count) receipts)\n"
        if !topCats.isEmpty {
            out += "- Top categories: " + topCats.map { "\($0.0) $\(String(format: "%.0f", $0.1))" }.joined(separator: ", ") + "\n"
        }
        return out
    }
    
    // MARK: - Essential Context
    
    /// Build essential context that's always included
    private func buildEssentialContext() -> String {
        var context = ""
        
        // Current date/time
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
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
        
        // Data summary (quick counts)
        context += "=== DATA AVAILABLE ===\n"
        context += "Events: \(TaskManager.shared.tasks.values.flatMap { $0 }.count)\n"
        context += "Notes: \(NotesManager.shared.notes.count)\n"
        context += "Emails: \(EmailService.shared.inboxEmails.count + EmailService.shared.sentEmails.count)\n"
        context += "Locations: \(LocationsManager.shared.savedPlaces.count)\n"
        context += "People: \(PeopleManager.shared.people.count)\n\n"
        
        // Critical instruction to prevent hallucination
        context += "🚨 CRITICAL INSTRUCTION:\n"
        context += "- ONLY answer questions using data explicitly provided in this context.\n"
        context += "- If data for a specific time period is NOT in the context, say \"I don't have data for that period.\"\n"
        context += "- NEVER invent, fabricate, or estimate data that isn't explicitly shown.\n"
        context += "- When comparing time periods, check if BOTH periods have data before answering.\n\n"
        
        return context
    }
    
    // MARK: - Query Intent Analysis
    
    private func analyzeQueryIntent(_ query: String) -> QueryIntent {
        let lower = query.lowercased()
        
        // Event creation
        if lower.contains("create") || lower.contains("schedule") || lower.contains("add event") ||
           lower.contains("remind me") || lower.contains("set a reminder") {
            return .createEvent
        }
        
        // ETA/Travel
        if lower.contains("how long") || lower.contains("how far") || lower.contains("eta") ||
           lower.contains("drive time") || lower.contains("get there") {
            return .etaQuery
        }
        
        // Weather
        if lower.contains("weather") || lower.contains("temperature") || lower.contains("rain") ||
           lower.contains("forecast") {
            return .weather
        }
        
        // Spending/Receipts
        if lower.contains("spend") || lower.contains("receipt") || lower.contains("expense") ||
           lower.contains("how much") {
            return .expenses
        }
        
        // Calendar/Schedule
        // Include "week" phrasing so "what's my week look like?" reliably triggers schedule context
        if lower.contains("today") || lower.contains("tomorrow") || lower.contains("schedule") ||
           lower.contains("calendar") || lower.contains("busy") || lower.contains("free") ||
           lower.contains("this week") || lower.contains("next week") || lower.contains("my week") ||
           lower.contains("weekend") || lower.contains("weekly") || lower.contains("agenda") ||
           lower.contains("my day") || lower.contains("what's on") || lower.contains("anything on") ||
           lower.contains("prepare for") || lower.contains("coming up") || lower.contains("planned") ||
           (lower.contains("week") && (lower.contains("look like") || lower.contains("what") || lower.contains("show"))) ||
           (lower.contains("day") && (lower.contains("look") || lower.contains("what") || lower.contains("how"))) {
            return .schedule
        }
        
        // Email
        if lower.contains("email") || lower.contains("mail") || lower.contains("inbox") {
            return .email
        }
        
        // Notes
        if lower.contains("note") || lower.contains("notes") || lower.contains("wrote") {
            return .notes
        }
        
        // People-related queries
        if lower.contains("birthday") || lower.contains("mom") || lower.contains("dad") ||
           lower.contains("friend") || lower.contains("coworker") || lower.contains("family") ||
           lower.contains("who is") || lower.contains("who's") || lower.contains("person") ||
           lower.contains("favourite food") || lower.contains("favorite food") ||
           lower.contains("favourite gift") || lower.contains("favorite gift") ||
           lower.contains("favourite color") || lower.contains("favorite color") ||
           lower.contains("relationship") || lower.contains("partner") {
            return .people
        }
        
        // Locations / Visits / "who did I see" type questions
        // This ensures questions like "When was the last time I met X and what did we do?"
        // attach visit + receipts + events context instead of relying on semantic top-k alone.
        if lower.contains("restaurant") || lower.contains("place") || lower.contains("location") ||
           lower.contains("where") || lower.contains("visited") || lower.contains("visit") ||
           lower.contains("met") || lower.contains("see ") || lower.contains("saw ") ||
           lower.contains("hung out") || lower.contains("hang out") ||
           lower.contains("went to") || lower.contains("go to") {
            return .locations
        }
        
        return .general
    }
    
    // MARK: - Query-Specific Context
    
    /// Add context that's specific to query intent but may not be in embeddings
    private func buildQuerySpecificContext(query: String, intent: QueryIntent) async -> String {
        var context = ""
        
        switch intent {
        case .schedule:
            // If user asks about last week / comparisons, include both week ranges explicitly.
            // This avoids relying on semantic search (which can drop items due to top-k limits).
            if isWeekComparisonQuery(query) {
                context += await buildWeekComparisonContext(query: query)
            } else {
                // Default: upcoming week
                context += await buildScheduleContext()
            }
            
        case .weather:
            // Add current weather
            context += await buildWeatherContext()
            
        case .expenses:
            // Add spending summary
            context += await buildSpendingContext(query: query)
            
        case .locations:
            // Day-based location/visit questions ("where did I go yesterday", "what did I do on Jan 10")
            if isLastTimeVisitQuery(query) {
                context += await buildRecentRelevantVisitContext(query: query)
            } else {
                context += await buildDayActivityContext(query: query)
            }
            
        case .people:
            // People-related queries (birthdays, relationships, personal info)
            context += await buildPeopleContext(query: query)
            
        case .etaQuery:
            // ETA context is handled by SelineAppContext's existing logic
            break
            
        case .createEvent:
            // Event creation uses existing event extraction logic
            break
            
        default:
            // If the user asks "what did I do yesterday/on <date>", attach day activity context even if intent wasn't locations.
            if hasDayReference(query) {
                context += await buildDayActivityContext(query: query)
            }
            
            // Consistency/habit questions (e.g. gym) need cross-year completion + visits.
            if isConsistencyQuery(query) && isGymRelatedQuery(query) {
                context += await buildGymConsistencyContext(query: query)
            }
            break
        }
        
        return context
    }

    private func isConsistencyQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        return lower.contains("consistent") ||
               lower.contains("consistency") ||
               lower.contains("how often") ||
               lower.contains("frequency") ||
               lower.contains("habit") ||
               lower.contains("compare") ||
               lower.contains("compared")
    }
    
    private func isGymRelatedQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        // Keep generic: gym/workout/fitness. No place hardcoding.
        return lower.contains("gym") || lower.contains("workout") || lower.contains("fitness") || lower.contains("training")
    }
    
    private func extractYears(from query: String) -> [Int] {
        let lower = query.lowercased()
        
        // Avoid lookbehind (not supported in Swift regex on some toolchains).
        // \b works here because years are digits and we want token-like boundaries.
        let matches = lower.matches(of: /\b(20\d{2})\b/)
        let years = matches.compactMap { Int($0.1) }
        if !years.isEmpty { return Array(Set(years)).sorted() }
        // Default: current year + previous year
        let current = Calendar.current.component(.year, from: Date())
        return [current - 1, current]
    }
    
    private func normalizeTokens(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
    }
    
    /// Build cross-year gym consistency using SOURCE-OF-TRUTH:
    /// - recurring event completion days (TaskItem.completedDates / completedDate)
    /// - location visits (location_visits) for gym-like saved places
    ///
    /// This avoids top-k semantic search omissions and enables 2025 vs 2026 comparisons.
    private func buildGymConsistencyContext(query: String) async -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return "" }
        
        let years = extractYears(from: query)
        guard years.count >= 2 else { return "" }
        
        let startYear = years.min()!
        let endYear = years.max()!
        
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = startYear
        startComponents.month = 1
        startComponents.day = 1
        let startDate = calendar.date(from: startComponents) ?? Date.distantPast
        
        var endComponents = DateComponents()
        endComponents.year = endYear + 1
        endComponents.month = 1
        endComponents.day = 1
        let endDate = calendar.date(from: endComponents) ?? Date()
        
        // Identify candidate gym places from saved locations (category/name overlap with query tokens)
        let qTokens = normalizeTokens(query)
        let gymTokens = qTokens.union(["gym", "fitness", "workout", "training"])
        
        let places = LocationsManager.shared.savedPlaces
        let gymPlaces = places.filter { place in
            let hay = "\(place.displayName) \(place.category) \(place.userNotes ?? "")"
            let tokens = normalizeTokens(hay)
            return !tokens.intersection(gymTokens).isEmpty
        }
        let gymPlaceIds = gymPlaces.map { $0.id.uuidString }
        
        // 1) Location visits from Supabase (counts as "went to gym")
        var visitCountsByYear: [Int: Int] = [:]
        var visitMinutesByYear: [Int: Int] = [:]
        var visitsWithNotesByYear: [Int: Int] = [:]
        
        if !gymPlaceIds.isEmpty {
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .in("saved_place_id", values: gymPlaceIds)
                    .gte("entry_time", value: iso.string(from: startDate))
                    .lt("entry_time", value: iso.string(from: endDate))
                    .execute()
                
                let decoder = JSONDecoder.supabaseDecoder()
                let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
                
                for v in visits {
                    let y = calendar.component(.year, from: v.entryTime)
                    visitCountsByYear[y, default: 0] += 1
                    visitMinutesByYear[y, default: 0] += v.durationMinutes ?? 0
                    let notes = (v.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty { visitsWithNotesByYear[y, default: 0] += 1 }
                }
            } catch {
                // If visits fail, we still can compare via task completion history below.
            }
        }
        
        // 2) Gym-related tasks & recurring completion history from TaskManager (source-of-truth)
        let allTasks = TaskManager.shared.getAllTasksIncludingArchived().filter { !$0.isDeleted }
        let gymTasks = allTasks.filter { task in
            let hay = "\(task.title) \(task.location ?? "") \(task.description ?? "")"
            let tokens = normalizeTokens(hay)
            return !tokens.intersection(gymTokens).isEmpty
        }
        
        var completionCountsByYear: [Int: Int] = [:]
        var completionDaysByYear: [Int: Set<String>] = [:]
        
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        dayKeyFormatter.timeZone = calendar.timeZone
        
        for task in gymTasks {
            // Recurring completions are in completedDates
            for d in task.completedDates {
                guard d >= startDate && d < endDate else { continue }
                let y = calendar.component(.year, from: d)
                completionCountsByYear[y, default: 0] += 1
                completionDaysByYear[y, default: []].insert(dayKeyFormatter.string(from: d))
            }
            // Non-recurring completion date
            if let d = task.completedDate, d >= startDate && d < endDate {
                let y = calendar.component(.year, from: d)
                completionCountsByYear[y, default: 0] += 1
                completionDaysByYear[y, default: []].insert(dayKeyFormatter.string(from: d))
            }
        }
        
        // Build context for LLM
        var context = "\n=== GYM CONSISTENCY (Cross-year) ===\n"
        context += "Years compared: \(years.map(String.init).joined(separator: " vs "))\n"
        context += "Gym-like locations detected: \(gymPlaces.map { $0.displayName }.prefix(6).joined(separator: ", "))"
        if gymPlaces.count > 6 { context += " (+\(gymPlaces.count - 6) more)" }
        context += "\n"
        context += "Gym-like tasks detected: \(gymTasks.count)\n"
        
        for y in years {
            let visits = visitCountsByYear[y, default: 0]
            let minutes = visitMinutesByYear[y, default: 0]
            let notes = visitsWithNotesByYear[y, default: 0]
            let completions = completionCountsByYear[y, default: 0]
            let uniqueDays = completionDaysByYear[y]?.count ?? 0
            
            context += "\n\(y):\n"
            context += "- Location visits (gym places): \(visits) visits, \(minutes) minutes total"
            if notes > 0 { context += ", \(notes) with notes/reasons" }
            context += "\n"
            context += "- Completed gym occurrences (from tasks): \(completions) completions across \(uniqueDays) unique days\n"
        }
        
        // Include a few sample recurring gym series so the model can explain the routine.
        let recurringGym = gymTasks.filter { $0.isRecurring }.prefix(6)
        if !recurringGym.isEmpty {
            context += "\nRecurring gym series (samples):\n"
            for t in recurringGym {
                context += "- \(t.title) (\(t.recurrenceFrequency?.rawValue ?? "recurring")) — completed \(t.completedDates.count) times\n"
            }
        }
        
        return context
    }

    // MARK: - Day Activity (Visits + Cross-References)
    
    private func hasDayReference(_ query: String) -> Bool {
        let lower = query.lowercased()
        if lower.contains("yesterday") || lower.contains("today") || lower.contains("tomorrow") {
            return true
        }
        // Weekday reference (e.g. "on Sunday", "last Monday")
        if lower.range(of: "\\b(mon(day)?|tue(s(day)?)?|wed(nesday)?|thu(r(s(day)?)?)?|fri(day)?|sat(urday)?|sun(day)?)\\b", options: .regularExpression) != nil {
            return true
        }
        // Very lightweight explicit date check (e.g. "Jan 10", "January 10", "2026-01-10")
        return lower.range(of: "\\b\\d{4}-\\d{2}-\\d{2}\\b", options: .regularExpression) != nil ||
               lower.range(of: "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\\b\\s+\\d{1,2}\\b", options: .regularExpression) != nil
    }
    
    private func isLastTimeVisitQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        return lower.contains("last time") ||
               lower.contains("when was") ||
               lower.contains("when did") ||
               lower.contains("most recent") ||
               lower.contains("recent time")
    }
    
    private func extractTargetDate(from query: String) -> Date? {
        let lower = query.lowercased()
        let calendar = Calendar.current
        
        if lower.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: Date())
        }
        if lower.contains("today") {
            return Date()
        }
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: Date())
        }
        
        // ISO yyyy-mm-dd
        if let range = lower.range(of: "\\b\\d{4}-\\d{2}-\\d{2}\\b", options: .regularExpression) {
            let token = String(lower[range])
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: token)
        }
        
        // MonthName dd (assume current year if missing)
        if let range = lower.range(
            of: "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\\b\\s+\\d{1,2}\\b",
            options: .regularExpression
        ) {
            let token = String(lower[range])
            let year = calendar.component(.year, from: Date())
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = "MMMM d yyyy"
            if let d = df.date(from: "\(token) \(year)") {
                return d
            }
            df.dateFormat = "MMM d yyyy"
            return df.date(from: "\(token) \(year)")
        }
        
        // Weekday (assume most recent occurrence, including today)
        if let range = lower.range(
            of: "\\b(mon(day)?|tue(s(day)?)?|wed(nesday)?|thu(r(s(day)?)?)?|fri(day)?|sat(urday)?|sun(day)?)\\b",
            options: .regularExpression
        ) {
            let token = String(lower[range])
            let weekday: Int? = {
                if token.hasPrefix("sun") { return 1 } // Calendar weekday: 1 = Sunday
                if token.hasPrefix("mon") { return 2 }
                if token.hasPrefix("tue") { return 3 }
                if token.hasPrefix("wed") { return 4 }
                if token.hasPrefix("thu") { return 5 }
                if token.hasPrefix("fri") { return 6 }
                if token.hasPrefix("sat") { return 7 }
                return nil
            }()
            
            if let weekday {
                let now = Date()
                let todayWeekday = calendar.component(.weekday, from: now)
                // How many days to go back to reach the desired weekday (0..6)
                let delta = (todayWeekday - weekday + 7) % 7
                let candidate = calendar.date(byAdding: .day, value: -delta, to: now) ?? now
                return candidate
            }
        }
        
        return nil
    }
    
    private func parseAnyDate(_ value: Any) -> Date? {
        if let d = value as? Date { return d }
        if let t = value as? TimeInterval { return Date(timeIntervalSince1970: t) }
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let s = value as? String {
            let iso1 = ISO8601DateFormatter()
            iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso1.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let d = iso2.date(from: s) { return d }
        }
        return nil
    }
    
    private func extractPrimaryDate(from metadata: [String: Any]?) -> Date? {
        guard let metadata else { return nil }
        let keys = ["entry_time", "start", "date", "scheduled_time", "target_date", "created_at"]
        for key in keys {
            if let v = metadata[key], let d = parseAnyDate(v) {
                return d
            }
        }
        return nil
    }
    
    /// Build a day-scoped activity context using visits + cross-referenced semantic matches.
    /// This avoids "hardcoding": we provide raw factual signals (visits + related artifacts),
    /// and let the LLM synthesize meaningfully.
    private func buildDayActivityContext(query: String, defaultToTodayIfMissing: Bool = true) async -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return "" }
        let targetDate = extractTargetDate(from: query) ?? (defaultToTodayIfMissing ? Date() : nil)
        guard let targetDate else { return "" }
        
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: targetDate)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return "" }
        
        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateStyle = .full
        dayLabelFormatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        var context = "\n=== DAY ACTIVITY ===\n"
        context += "Target day: \(dayLabelFormatter.string(from: dayStart))\n"
        
        // 1) Visits for the day (source-of-truth from location_visits)
        var visitsForDay: [LocationVisitRecord] = []
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            
            // IMPORTANT: Supabase timestamps are stored in UTC. If we query strictly by UTC boundaries
            // for a *local* day, we can miss evening visits (e.g., 8pm local = next-day UTC).
            // Fetch a wider window and filter locally by overlap with the target local day.
            let widenHours: TimeInterval = 12 * 60 * 60
            let fetchStart = dayStart.addingTimeInterval(-widenHours)
            let fetchEnd = nextDayStart.addingTimeInterval(widenHours)
            
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
            
            // Keep visits that overlap the local day window.
            // Overlap rule: start < nextDayStart && (exit ?? start) >= dayStart
            let visits = fetched.filter { visit in
                let start = visit.entryTime
                let end = visit.exitTime ?? visit.entryTime
                return start < nextDayStart && end >= dayStart
            }
            visitsForDay = visits
            
            if visits.isEmpty {
                context += "\nVISITS:\n- No saved-location visits recorded for this day.\n"
            } else {
                context += "\nVISITS (with reasons/notes if available):\n"
                for visit in visits {
                    let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                    let placeName = place?.displayName ?? "Unknown Location"
                    let start = visit.entryTime
                    let end = visit.exitTime
                    let range = end != nil ? "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end!))" : "\(timeFormatter.string(from: start))–(ongoing)"
                    let duration = visit.durationMinutes.map { "\($0)m" } ?? "unknown duration"
                    let notes = (visit.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if notes.isEmpty {
                        context += "- \(range) • \(placeName) • \(duration)\n"
                    } else {
                        context += "- \(range) • \(placeName) • \(duration) • Reason: \(notes)\n"
                    }
                }
            }
        } catch {
            // If the visits query fails, we still can fall back to semantic matches below.
            context += "\nVISITS:\n- (Unable to load visits for this day.)\n"
        }
        
        // 2) Events for the day (source-of-truth from TaskManager)
        do {
            let tagManager = TagManager.shared
            let tasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            
            if tasks.isEmpty {
                context += "\nEVENTS:\n- No events/tasks found for this day.\n"
            } else {
                context += "\nEVENTS (from calendar/tasks):\n"
                for t in tasks.sorted(by: { ($0.scheduledTime ?? $0.targetDate ?? $0.createdAt) < ($1.scheduledTime ?? $1.targetDate ?? $1.createdAt) }).prefix(40) {
                    let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                    
                    let timeLabel: String = {
                        if t.scheduledTime == nil, t.targetDate != nil { return "[All-day]" }
                        if let st = t.scheduledTime, let et = t.endTime {
                            let tf = DateFormatter()
                            tf.timeStyle = .short
                            let sameDay = calendar.isDate(st, inSameDayAs: et)
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
            }
        }
        
        // 3) Receipts for the day (source-of-truth from receipt notes)
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
            
            let receiptNotes = notesManager.notes
                .filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
                .compactMap { note -> (note: Note, date: Date, amount: Double, category: String) in
                    let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                    let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                    let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                    return (note, date, amount, category)
                }
                .filter { $0.date >= dayStart && $0.date < nextDayStart }
            
            if receiptNotes.isEmpty {
                context += "\nRECEIPTS:\n- No receipt notes found for this day.\n"
            } else {
                let total = receiptNotes.reduce(0.0) { $0 + $1.amount }
                context += "\nRECEIPTS (from receipts folder): \(receiptNotes.count) — Total $\(String(format: "%.2f", total))\n"
                
                // Category breakdown (fast heuristic categories)
                let byCategory = Dictionary(grouping: receiptNotes) { $0.category }
                let topCats = byCategory
                    .map { (cat, items) in (cat, items.reduce(0.0) { $0 + $1.amount }, items.count) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(8)
                
                context += "Top categories:\n"
                for (cat, catTotal, count) in topCats {
                    context += "- \(cat): $\(String(format: "%.2f", catTotal)) (\(count))\n"
                }
                
                context += "Receipt list:\n"
                for r in receiptNotes.sorted(by: { $0.amount > $1.amount }).prefix(25) {
                    context += "- \(r.note.title) — $\(String(format: "%.2f", r.amount)) (\(r.category))\n"
                }
            }
        }
        
        // 4) Soft linking: group likely related items under visits (no hardcoded conclusions)
        if !visitsForDay.isEmpty {
            let tagManager = TagManager.shared
            let tasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            
            // Prepare receipt candidates once (same logic as above, but lighter)
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
            let receiptNotesForDay: [Note] = notesManager.notes
                .filter { isUnderReceiptsFolderHierarchy(folderId: $0.folderId) }
                .filter {
                    let d = notesManager.extractFullDateFromTitle($0.title) ?? $0.dateCreated
                    return d >= dayStart && d < nextDayStart
                }
            
            func normalizeTokens(_ s: String) -> Set<String> {
                let lowered = s.lowercased()
                let parts = lowered
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 3 }
                return Set(parts)
            }
            
            context += "\nLINKS (possible connections between visits, events, receipts):\n"
            
            for visit in visitsForDay.prefix(20) {
                let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
                let placeName = place?.displayName ?? "Unknown Location"
                let placeTokens = normalizeTokens(placeName)
                
                let visitStart = visit.entryTime
                let visitEnd = visit.exitTime ?? visit.entryTime
                
                // Events that overlap the visit window and/or mention the location
                let relatedEvents = tasks.filter { t in
                    let start = t.scheduledTime ?? t.targetDate ?? t.createdAt
                    let end = t.endTime ?? start
                    let overlaps = start < visitEnd.addingTimeInterval(5 * 60) && end >= visitStart.addingTimeInterval(-5 * 60)
                    
                    if overlaps { return true }
                    if let loc = t.location, !loc.isEmpty {
                        let locTokens = normalizeTokens(loc)
                        return !placeTokens.intersection(locTokens).isEmpty
                    }
                    return false
                }
                
                // Receipts that likely match the place name (token overlap)
                let relatedReceipts = receiptNotesForDay.filter { note in
                    let tokens = normalizeTokens(note.title)
                    return !placeTokens.intersection(tokens).isEmpty
                }
                
                let notes = (visit.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let reasonPart = notes.isEmpty ? "" : " — Reason: \(notes)"
                
                context += "\n- Visit: \(placeName) (\(timeFormatter.string(from: visitStart))–\(timeFormatter.string(from: visitEnd)))\(reasonPart)\n"
                
                if !relatedEvents.isEmpty {
                    context += "  Related events:\n"
                    for e in relatedEvents.prefix(6) {
                        let tagName = tagManager.getTag(by: e.tagId)?.name ?? "Personal"
                        context += "  - \(e.title) — \(tagName)\n"
                    }
                }
                
                if !relatedReceipts.isEmpty {
                    context += "  Related receipts (name match):\n"
                    for r in relatedReceipts.prefix(6) {
                        let amount = CurrencyParser.extractAmount(from: r.content.isEmpty ? r.title : r.content)
                        context += "  - \(r.title) — $\(String(format: "%.2f", amount))\n"
                    }
                }
            }
        }
        
        // 2) Cross-reference: semantic matches across other domains, then day-filter by metadata
        do {
            let results = try await vectorSearch.search(
                query: query,
                documentTypes: [.visit, .task, .receipt, .email, .note],
                limit: 30
            )
            
            let dayResults = results.filter { r in
                guard let d = extractPrimaryDate(from: r.metadata) else { return false }
                return d >= dayStart && d < nextDayStart
            }
            
            if !dayResults.isEmpty {
                context += "\nRELATED ITEMS FROM THAT DAY (semantic matches):\n"
                
                let grouped = Dictionary(grouping: dayResults) { $0.documentType }
                for (type, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    context += "\n\(type.displayName):\n"
                    for item in items.prefix(8) {
                        let similarity = String(format: "%.0f%%", item.similarity * 100)
                        let title = (item.title?.isEmpty == false) ? item.title! : String(item.content.prefix(80))
                        context += "- [\(similarity) match] \(title)\n"
                    }
                }
            }
        } catch {
            // Ignore; visits section already provides factual anchors.
        }
        
        return context
    }
    
    /// Find the most relevant recent visit (by place name + visit notes match),
    /// then attach a full day snapshot (visits + events + receipts + links).
    private func buildRecentRelevantVisitContext(query: String) async -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return "" }
        
        let calendar = Calendar.current
        let lower = query.lowercased()
        
        func normalizeTokens(_ s: String) -> Set<String> {
            let parts = s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
            return Set(parts)
        }
        
        let queryTokens = normalizeTokens(lower)
        guard !queryTokens.isEmpty else { return "" }
        
        // Find likely place IDs by matching query tokens against place names + notes.
        let places = LocationsManager.shared.savedPlaces
        let candidatePlaceIds: Set<UUID> = Set(
            places.filter { place in
                let hay = "\(place.displayName) \(place.userNotes ?? "")".lowercased()
                let tokens = normalizeTokens(hay)
                return !tokens.intersection(queryTokens).isEmpty
            }.map(\.id)
        )
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            
            // Pull a window of recent visits and pick the best match locally.
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .limit(400)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let fetched: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            guard !fetched.isEmpty else { return "" }
            
            // Score visits based on token overlap with place name + visit notes.
            func score(_ visit: LocationVisitRecord) -> Int {
                let place = places.first(where: { $0.id == visit.savedPlaceId })
                let placeName = place?.displayName ?? ""
                let notes = visit.visitNotes ?? ""
                let tokens = normalizeTokens("\(placeName) \(notes)")
                return tokens.intersection(queryTokens).count
            }
            
            // Filter to candidate places when we have them, otherwise use all visits.
            let pool = candidatePlaceIds.isEmpty ? fetched : fetched.filter { candidatePlaceIds.contains($0.savedPlaceId) }
            guard let best = pool.max(by: { score($0) < score($1) }), score(best) > 0 else {
                return ""
            }
            
            let place = places.first(where: { $0.id == best.savedPlaceId })
            let placeName = place?.displayName ?? "Unknown Location"
            let start = best.entryTime
            let end = best.exitTime ?? best.entryTime
            
            let fullFormatter = DateFormatter()
            fullFormatter.dateStyle = .full
            fullFormatter.timeStyle = .short
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.dateStyle = .none
            
            let durationStr = best.durationMinutes.map { "\($0) min" } ?? "unknown duration"
            let notes = (best.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let notesLine = notes.isEmpty ? "" : "\nReason/Notes: \(notes)"
            
            var context = "\n=== MOST RELEVANT RECENT VISIT ===\n"
            context += "Place: \(placeName)\n"
            context += "When: \(fullFormatter.string(from: start))"
            if best.exitTime != nil {
                context += " – \(timeFormatter.string(from: end))"
            }
            context += "\nDuration: \(durationStr)\(notesLine)\n"
            
            // Attach a full day snapshot for that date (this is where receipts/events get pulled in).
            let dayQuery = "What did I do on \(ISO8601DateFormatter().string(from: calendar.startOfDay(for: start)))"
            context += await buildDayActivityContext(query: dayQuery, defaultToTodayIfMissing: false)
            
            return context
        } catch {
            return ""
        }
    }
    
    /// Build schedule context (full week of events)
    private func buildScheduleContext() async -> String {
        var context = "\n=== THIS WEEK'S SCHEDULE ===\n"
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tagManager = TagManager.shared
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"
        
        var hasAnyEvents = false
        
        // Show next 7 days
        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            
            // Use getTasksForDate() to properly include all event types:
            // - Regular events
            // - Recurring events (daily, weekly, monthly, etc.)
            // - Multi-day events
            // - All categories (Work, Personal, Synced, etc.)
            let dayEvents = TaskManager.shared.getTasksForDate(dayStart)
                .filter { !$0.isDeleted }
                .sorted {
                    let a = $0.scheduledTime ?? $0.targetDate ?? $0.createdAt
                    let b = $1.scheduledTime ?? $1.targetDate ?? $1.createdAt
                    return a < b
                }
            
            if !dayEvents.isEmpty {
                hasAnyEvents = true
                let dayLabel = dayOffset == 0 ? "TODAY (\(dayFormatter.string(from: dayStart)))" :
                              dayOffset == 1 ? "TOMORROW (\(dayFormatter.string(from: dayStart)))" :
                              dayFormatter.string(from: dayStart)
                context += "\n**\(dayLabel):**\n"
                
                let maxPerDay = 25
                for event in dayEvents.prefix(maxPerDay) {
                    let status = event.isCompletedOn(date: dayStart) ? "✓" : "○"
                    
                    let start = event.scheduledTime ?? event.targetDate ?? event.createdAt
                    let end = event.endTime
                    
                    let timeLabel: String = {
                        // If no scheduledTime but has a targetDate, treat as all-day
                        if event.scheduledTime == nil, event.targetDate != nil {
                            return "[All-day]"
                        }
                        if let start = event.scheduledTime, let end = end {
                            let formatter = DateFormatter()
                            formatter.timeStyle = .short
                            let sameDay = calendar.isDate(start, inSameDayAs: end)
                            if sameDay {
                                return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
                            } else {
                                // Multi-day spanning
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateStyle = .short
                                dateFormatter.timeStyle = .short
                                return "\(dateFormatter.string(from: start)) → \(dateFormatter.string(from: end))"
                            }
                        }
                        if let start = event.scheduledTime {
                            let formatter = DateFormatter()
                            formatter.timeStyle = .short
                            return formatter.string(from: start)
                        }
                        // Fallback
                        let df = DateFormatter()
                        df.timeStyle = .short
                        return df.string(from: start)
                    }()
                    
                    let tagName = tagManager.getTag(by: event.tagId)?.name ?? "Personal"
                    let locationSuffix = (event.location?.isEmpty == false) ? " @ \(event.location!)" : ""
                    let recurringSuffix = event.isRecurring ? " [Recurring]" : ""
                    
                    context += "• [\(status)] \(timeLabel) \(event.title) — \(tagName)\(locationSuffix)\(recurringSuffix)\n"
                    if let desc = event.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        context += "  - \(desc.prefix(120))\n"
                    }
                }
                
                if dayEvents.count > maxPerDay {
                    context += "  ... plus \(dayEvents.count - maxPerDay) more events\n"
                }
            }
        }
        
        if !hasAnyEvents {
            context += "No events scheduled for this week.\n"
        }
        
        return context
    }
    
    /// Build people context for queries about saved people
    private func buildPeopleContext(query: String) async -> String {
        var context = "\n=== PEOPLE INFORMATION ===\n"
        
        let peopleManager = PeopleManager.shared
        let people = peopleManager.people
        
        if people.isEmpty {
            context += "No people saved yet.\n"
            return context
        }
        
        let lower = query.lowercased()
        let birthdayFormatter = DateFormatter()
        birthdayFormatter.dateFormat = "MMMM d"
        
        // Group people by relationship type
        let grouped = Dictionary(grouping: people) { $0.relationship }
        
        for relationshipType in RelationshipType.allCases {
            guard let relationshipPeople = grouped[relationshipType], !relationshipPeople.isEmpty else {
                continue
            }
            
            context += "\n**\(relationshipType.displayName) (\(relationshipPeople.count)):**\n"
            
            for person in relationshipPeople.sorted(by: { $0.name < $1.name }) {
                var personLine = "• \(person.name)"
                
                if let nickname = person.nickname, !nickname.isEmpty {
                    personLine += " (\"\(nickname)\")"
                }
                
                // Add birthday if available
                if let birthday = person.birthday {
                    personLine += " - Birthday: \(birthdayFormatter.string(from: birthday))"
                    if let age = person.age {
                        personLine += " (age \(age))"
                    }
                }
                
                context += personLine + "\n"
                
                // Add personal details if query seems to be asking about them
                var details: [String] = []
                
                if let food = person.favouriteFood, !food.isEmpty,
                   (lower.contains("food") || lower.contains("eat") || lower.contains("favourite") || lower.contains("favorite")) {
                    details.append("Favourite food: \(food)")
                }
                
                if let gift = person.favouriteGift, !gift.isEmpty,
                   (lower.contains("gift") || lower.contains("present") || lower.contains("buy")) {
                    details.append("Gift ideas: \(gift)")
                }
                
                if let color = person.favouriteColor, !color.isEmpty,
                   (lower.contains("color") || lower.contains("colour")) {
                    details.append("Favourite color: \(color)")
                }
                
                if let interests = person.interests, !interests.isEmpty {
                    details.append("Interests: \(interests.joined(separator: ", "))")
                }
                
                if let phone = person.phone, !phone.isEmpty,
                   (lower.contains("phone") || lower.contains("call") || lower.contains("contact")) {
                    details.append("Phone: \(phone)")
                }
                
                if let email = person.email, !email.isEmpty,
                   (lower.contains("email") || lower.contains("contact")) {
                    details.append("Email: \(email)")
                }
                
                for detail in details {
                    context += "  - \(detail)\n"
                }
                
                if let notes = person.notes, !notes.isEmpty {
                    context += "  - Notes: \(notes.prefix(100))\n"
                }
            }
        }
        
        // Check for upcoming birthdays
        let calendar = Calendar.current
        let today = Date()
        
        var upcomingBirthdays: [(person: Person, daysUntil: Int)] = []
        
        for person in people {
            guard let birthday = person.birthday else { continue }
            
            // Calculate this year's birthday
            var birthdayComponents = calendar.dateComponents([.month, .day], from: birthday)
            birthdayComponents.year = calendar.component(.year, from: today)
            
            guard let thisYearBirthday = calendar.date(from: birthdayComponents) else { continue }
            
            var targetBirthday = thisYearBirthday
            if thisYearBirthday < today {
                // Birthday has passed this year, check next year
                birthdayComponents.year! += 1
                if let nextYearBirthday = calendar.date(from: birthdayComponents) {
                    targetBirthday = nextYearBirthday
                }
            }
            
            let daysUntil = calendar.dateComponents([.day], from: today, to: targetBirthday).day ?? 0
            
            if daysUntil >= 0 && daysUntil <= 30 {
                upcomingBirthdays.append((person, daysUntil))
            }
        }
        
        if !upcomingBirthdays.isEmpty {
            context += "\n**Upcoming Birthdays (next 30 days):**\n"
            for (person, daysUntil) in upcomingBirthdays.sorted(by: { $0.daysUntil < $1.daysUntil }) {
                let whenText = daysUntil == 0 ? "TODAY!" : daysUntil == 1 ? "Tomorrow" : "in \(daysUntil) days"
                context += "• \(person.name) - \(whenText)"
                if let giftIdea = person.favouriteGift, !giftIdea.isEmpty {
                    context += " (Gift idea: \(giftIdea))"
                }
                context += "\n"
            }
        }
        
        return context
    }

    private func isWeekComparisonQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        return (lower.contains("last week") && (lower.contains("this week") || lower.contains("next week") || lower.contains("compared"))) ||
               lower.contains("compare") ||
               lower.contains("compared to")
    }
    
    private func startOfWeek(for date: Date) -> Date {
        let calendar = Calendar.current
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval.start
        }
        return calendar.startOfDay(for: date)
    }
    
    private func buildWeekComparisonContext(query: String) async -> String {
        let calendar = Calendar.current
        let thisWeekStart = startOfWeek(for: Date())
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        
        var context = "\n=== WEEK COMPARISON ===\n"
        context += await buildWeekScheduleContext(weekStart: lastWeekStart, title: "LAST WEEK")
        context += await buildWeekScheduleContext(weekStart: thisWeekStart, title: "THIS WEEK")
        context += "\n(Use tags/categories like Work/Personal to focus on \"work week\" questions.)\n"
        return context
    }
    
    private func buildWeekScheduleContext(weekStart: Date, title: String) async -> String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"
        
        let tagManager = TagManager.shared
        
        var allWeekTasks: [TaskItem] = []
        allWeekTasks.reserveCapacity(64)
        
        var section = "\n--- \(title) ---\n"
        
        for i in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: i, to: weekStart) else { continue }
            let dayTasks = TaskManager.shared.getTasksForDate(day)
            allWeekTasks.append(contentsOf: dayTasks)
            
            if !dayTasks.isEmpty {
                section += "\n**\(dayFormatter.string(from: day)):**\n"
                for t in dayTasks.sorted(by: { ($0.scheduledTime ?? $0.targetDate ?? $0.createdAt) < ($1.scheduledTime ?? $1.targetDate ?? $1.createdAt) }).prefix(30) {
                    let tagName = tagManager.getTag(by: t.tagId)?.name ?? "Personal"
                    let timeLabel: String = {
                        if t.scheduledTime == nil, t.targetDate != nil { return "[All-day]" }
                        if let st = t.scheduledTime, let et = t.endTime {
                            let tf = DateFormatter()
                            tf.timeStyle = .short
                            let sameDay = calendar.isDate(st, inSameDayAs: et)
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
                    section += "• \(timeLabel) \(t.title) — \(tagName)\(loc)\n"
                }
            }
        }
        
        // Summary by tag/category (helps "work week" comparisons without hardcoding)
        let byTag = Dictionary(grouping: allWeekTasks.filter { !$0.isDeleted }) { tagManager.getTag(by: $0.tagId)?.name ?? "Personal" }
        section += "\nSummary by category:\n"
        for (tag, items) in byTag.sorted(by: { $0.key < $1.key }) {
            section += "- \(tag): \(items.count) events\n"
        }
        
        return section
    }
    
    /// Build weather context
    private func buildWeatherContext() async -> String {
        guard let weather = WeatherService.shared.weatherData else {
            // Try to fetch weather
            let location = LocationService.shared.currentLocation ?? CLLocation(latitude: 43.6532, longitude: -79.3832)
            await WeatherService.shared.fetchWeather(for: location)
            
            guard let weather = WeatherService.shared.weatherData else {
                return "\n=== WEATHER ===\nWeather data unavailable.\n"
            }
            return formatWeatherContext(weather)
        }
        
        return formatWeatherContext(weather)
    }
    
    private func formatWeatherContext(_ weather: WeatherData) -> String {
        var context = "\n=== CURRENT WEATHER ===\n"
        context += "Temperature: \(weather.temperature)°C\n"
        context += "Conditions: \(weather.description.capitalized)\n"
        context += "Location: \(weather.locationName)\n"
        
        // Format sunrise/sunset
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        context += "Sunrise: \(timeFormatter.string(from: weather.sunrise))\n"
        context += "Sunset: \(timeFormatter.string(from: weather.sunset))\n"
        
        return context
    }
    
    /// Build spending context
    private func buildSpendingContext(query: String) async -> String {
        do {
            // Receipts source-of-truth is Notes under the Receipts folder hierarchy.
            // Do NOT rely on folder organization (Receipts/YYYY/Month) to avoid dropping older/unorganized receipts.
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
            
            let receiptNotes = notesManager.notes.filter { note in
                isUnderReceiptsFolderHierarchy(folderId: note.folderId)
            }
            
            guard !receiptNotes.isEmpty else { return "" }
            
            struct Tx {
                let date: Date
                let merchant: String
                let amount: Double
                let category: String
                let noteId: UUID
                let isWeekend: Bool
            }
            
            let calendar = Calendar.current
            var transactions: [Tx] = []
            transactions.reserveCapacity(receiptNotes.count)
            
            for note in receiptNotes {
                let date = notesManager.extractFullDateFromTitle(note.title) ?? note.dateCreated
                let amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
                let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
                transactions.append(Tx(date: date, merchant: note.title, amount: amount, category: category, noteId: note.id, isWeekend: isWeekend))
            }
            
            // Detect if query is about weekends
            let lower = query.lowercased()
            let isWeekendQuery = lower.contains("weekend") || lower.contains("saturday") || lower.contains("sunday")
            
            // Month-over-month summary (last 12 months for better coverage, includes Oct 2025)
            let monthKeyFormatter = DateFormatter()
            monthKeyFormatter.dateFormat = "yyyy-MM"
            
            let monthDisplayFormatter = DateFormatter()
            monthDisplayFormatter.dateFormat = "MMMM yyyy"
            
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .none
            
            let dayOfWeekFormatter = DateFormatter()
            dayOfWeekFormatter.dateFormat = "EEEE"
            
            // Determine the date range of available data
            let sortedDates = transactions.map { $0.date }.sorted()
            let oldestDate = sortedDates.first ?? Date()
            let newestDate = sortedDates.last ?? Date()
            
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "MMMM yyyy"
            
            var context = "\n----------\nSPENDING SUMMARY (from receipt notes):\n"
            context += "⚠️ DATA AVAILABILITY: Receipt data exists from \(yearFormatter.string(from: oldestDate)) to \(yearFormatter.string(from: newestDate)) ONLY.\n"
            context += "⚠️ If asked about dates OUTSIDE this range, say \"I don't have data for that period.\"\n"
            context += "Total receipt notes found: \(receiptNotes.count)\n"
            
            // If weekend query, add specific weekend analysis FIRST
            if isWeekendQuery {
                let weekendTxs = transactions.filter { $0.isWeekend }
                let weekdayTxs = transactions.filter { !$0.isWeekend }
                
                let weekendTotal = weekendTxs.reduce(0.0) { $0 + $1.amount }
                let weekdayTotal = weekdayTxs.reduce(0.0) { $0 + $1.amount }
                
                context += "\n=== WEEKEND SPENDING BREAKDOWN ===\n"
                context += "Total weekend spending (all time): $\(String(format: "%.2f", weekendTotal)) (\(weekendTxs.count) receipts)\n"
                context += "Total weekday spending (all time): $\(String(format: "%.2f", weekdayTotal)) (\(weekdayTxs.count) receipts)\n"
                
                // Weekend spending by month
                let weekendByMonth = Dictionary(grouping: weekendTxs) { monthKeyFormatter.string(from: $0.date) }
                let sortedWeekendMonths = weekendByMonth.keys.sorted(by: >).prefix(6)
                
                context += "\nWEEKEND SPENDING BY MONTH:\n"
                for monthKey in sortedWeekendMonths {
                    guard let txs = weekendByMonth[monthKey] else { continue }
                    let total = txs.reduce(0.0) { $0 + $1.amount }
                    let monthDate = txs.map(\.date).max() ?? Date()
                    context += "- \(monthDisplayFormatter.string(from: monthDate)): $\(String(format: "%.2f", total)) (\(txs.count) receipts)\n"
                    
                    // Top categories for weekend in this month
                    let byCategory = Dictionary(grouping: txs) { $0.category }
                    let topCategories = byCategory
                        .map { (cat, items) in (cat, items.reduce(0.0) { $0 + $1.amount }, items.count) }
                        .sorted { $0.1 > $1.1 }
                        .prefix(4)
                    
                    for (cat, catTotal, count) in topCategories {
                        context += "  • \(cat): $\(String(format: "%.2f", catTotal)) (\(count))\n"
                    }
                }
                
                // Recent weekend transactions
                context += "\nRECENT WEEKEND TRANSACTIONS:\n"
                for tx in weekendTxs.sorted(by: { $0.date > $1.date }).prefix(30) {
                    let dateStr = displayFormatter.string(from: tx.date)
                    let dayName = dayOfWeekFormatter.string(from: tx.date)
                    context += "- \(dateStr) (\(dayName)): \(tx.merchant) - $\(String(format: "%.2f", tx.amount)) (\(tx.category))\n"
                }
                
                context += "\n"
            }
            
            // Standard month-over-month summary
            let months = Dictionary(grouping: transactions) { monthKeyFormatter.string(from: $0.date) }
            let sortedMonthKeys = months.keys.sorted(by: >).prefix(12)
            
            context += "\n=== OVERALL MONTHLY SUMMARY ===\n"
            
            for monthKey in sortedMonthKeys {
                guard let txs = months[monthKey] else { continue }
                let total = txs.reduce(0.0) { $0 + $1.amount }
                let monthDate = txs.map(\.date).max() ?? Date()
                let weekendCount = txs.filter { $0.isWeekend }.count
                let weekendTotal = txs.filter { $0.isWeekend }.reduce(0.0) { $0 + $1.amount }
                
                context += "\n\(monthDisplayFormatter.string(from: monthDate)): $\(String(format: "%.2f", total)) (\(txs.count) receipts)"
                context += " [Weekend: $\(String(format: "%.2f", weekendTotal)) / \(weekendCount)]\n"
                
                // Top categories for this month (limit to top 6)
                let byCategory = Dictionary(grouping: txs) { $0.category }
                let topCategories = byCategory
                    .map { (cat, items) in (cat, items.reduce(0.0) { $0 + $1.amount }, items.count) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(6)
                
                for (cat, catTotal, count) in topCategories {
                    context += "  - \(cat): $\(String(format: "%.2f", catTotal)) (\(count))\n"
                }
            }
            
            // Recent transactions (limit to 25)
            context += "\nRECENT TRANSACTIONS:\n"
            for tx in transactions.sorted(by: { $0.date > $1.date }).prefix(25) {
                let dateStr = displayFormatter.string(from: tx.date)
                let dayName = dayOfWeekFormatter.string(from: tx.date)
                let weekendTag = tx.isWeekend ? " [WEEKEND]" : ""
                context += "- \(dateStr) (\(dayName)): \(tx.merchant) - $\(String(format: "%.2f", tx.amount)) (\(tx.category))\(weekendTag)\n"
            }

            // Also pull semantically relevant receipt embeddings for the specific question
            do {
                let receiptMatches = try await vectorSearch.search(
                    query: query,
                    documentTypes: [.receipt],
                    limit: 8
                )

                if !receiptMatches.isEmpty {
                    context += "\nRELEVANT RECEIPTS (semantic matches):\n"
                    for match in receiptMatches {
                        let similarity = String(format: "%.0f%%", match.similarity * 100)
                        let title = (match.title?.isEmpty == false) ? match.title! : "Receipt"
                        context += "• [\(similarity) match] \(title)\n"
                        let preview = match.content.prefix(220)
                        context += "  \(preview)\(match.content.count > 220 ? "..." : "")\n"
                    }
                }
            } catch {
                // If vector search fails, we still have the direct data above
                print("⚠️ Vector search for receipts failed, using direct data only")
            }

            return context
            
        } catch {
            print("⚠️ Failed to build receipts spending context: \(error)")
            return ""
        }
    }
    
    // MARK: - Utilities
    
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
        var queryIntent: QueryIntent = .general
        var usedVectorSearch: Bool = false
        var estimatedTokens: Int = 0
        var buildTime: TimeInterval = 0
    }
    
    enum QueryIntent: String {
        case general
        case createEvent
        case etaQuery
        case weather
        case expenses
        case schedule
        case email
        case notes
        case locations
        case people
    }
}
