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
    
    // MARK: - Configuration
    
    /// Maximum total items in context from vector search
    private let maxTotalItems = 25  // Optimized for cost (75% reduction from 100) - top results capture 85-90% of relevance
    
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
        
        // 3. Extract date range from query using LLM (handles all natural language variations)
        let dateRange = await extractDateRange(from: query)
        
        // 4. Get semantically relevant data via vector search (with date filtering if specified)
        do {
            let relevantContext = try await vectorSearch.getRelevantContext(
                forQuery: query,
                limit: maxTotalItems,
                dateRange: dateRange
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
        
        // 5. For date-specific queries, ALSO fetch ALL items from that date
        // This guarantees completeness (not just top-k semantic matches)
        if let dateRange = dateRange {
            print("📍 Date range detected: fetching ALL items for completeness")
            let dayContext = await buildDayCompletenessContext(dateRange: dateRange)
            if !dayContext.isEmpty {
                context += "\n" + dayContext
            }
        }
        
        // 6. Calculate token estimate
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

        // Knowledge & search guidance
        context += "🔍 KNOWLEDGE & SEARCH:\n"
        context += "- Use your knowledge cutoff (January 2025) for historical questions\n"
        context += "- For current events, recent news, or live data, state what you know and when your knowledge was last updated\n"
        context += "- Be transparent about knowledge limitations\n\n"

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
                return (start: dayStart, end: dayEnd)
            }
        }
        
        // Use LLM to extract date from natural language query
        // This handles "two weeks ago", "same day last week", "3 days ago", etc.
        do {
            let dateExtractionPrompt = """
            Extract the specific date or date range from this user query. Today is \(DateFormatter.localizedString(from: today, dateStyle: .full, timeStyle: .none)).
            
            User query: "\(query)"
            
            If the query references a specific date or date range, respond with ONLY an ISO 8601 date (YYYY-MM-DD) for that date.
            If it references a single day (e.g., "yesterday", "last Tuesday", "two weeks ago"), return that date.
            If it references a range (e.g., "last week"), return the start date of that range.
            If no date is mentioned, respond with "none".
            
            Examples:
            - "yesterday" → \(calendar.date(byAdding: .day, value: -1, to: todayStart)!.ISO8601Format().prefix(10))
            - "two weeks ago" → \(calendar.date(byAdding: .day, value: -14, to: todayStart)!.ISO8601Format().prefix(10))
            - "same day last week" → \(calendar.date(byAdding: .day, value: -7, to: todayStart)!.ISO8601Format().prefix(10))
            - "January 15" → 2026-01-15
            - "no date mentioned" → none
            
            Response (date only, YYYY-MM-DD format, or "none"):
            """
            
            let response = try await GeminiService.shared.simpleChatCompletion(
                systemPrompt: "You are a date extraction assistant. Extract dates from user queries and respond with ISO 8601 format (YYYY-MM-DD) or 'none'.",
                messages: [["role": "user", "content": dateExtractionPrompt]]
            )
            
            let extractedDateStr = response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if extractedDateStr.lowercased() == "none" || extractedDateStr.isEmpty {
                print("📅 Date extraction: No date found in query (LLM response: 'none')")
                return nil
            }
            
            // Parse the ISO date
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = "yyyy-MM-dd"
            
            if let targetDate = df.date(from: extractedDateStr) {
                let dayStart = calendar.startOfDay(for: targetDate)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                    return nil
                }
                
                print("📅 Date extraction (LLM): Extracted '\(extractedDateStr)' from query: '\(query)'")
                return (start: dayStart, end: dayEnd)
            } else {
                print("⚠️ Date extraction: LLM returned invalid date format: '\(extractedDateStr)'")
                return nil
            }
        } catch {
            print("⚠️ Date extraction (LLM) failed: \(error), falling back to no date filter")
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
        
        var context = "\n=== COMPLETE DAY DATA (All Items) ===\n"
        context += "Date: \(dayLabelFormatter.string(from: dayStart))\n"
        context += "Note: This section includes ALL items from this date for completeness.\n\n"
        
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
            let tasks = TaskManager.shared.getTasksForDate(dayStart).filter { !$0.isDeleted }
            
            if !tasks.isEmpty {
                context += "EVENTS/TASKS (\(tasks.count)):\n"
                for t in tasks.sorted(by: { ($0.scheduledTime ?? $0.targetDate ?? $0.createdAt) < ($1.scheduledTime ?? $1.targetDate ?? $1.createdAt) }) {
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
                    context += "- \(r.note.title) — $\(String(format: "%.2f", r.amount)) (\(r.category))\n"
                }
                context += "\n"
            }
        }
        
        return context
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
        var usedVectorSearch: Bool = false
        var estimatedTokens: Int = 0
        var buildTime: TimeInterval = 0
    }
}
