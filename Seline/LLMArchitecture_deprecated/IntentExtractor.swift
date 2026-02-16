import Foundation

/// Enum defining the types of user intents
enum ChatIntent: String, Codable {
    case calendar      // "What's on my calendar?"
    case notes         // "Find my note about..."
    case locations     // "Where is...?" / "Show me places..."
    case weather       // "What's the weather?"
    case email         // "Did I get an email from...?"
    case navigation    // "How far..." / "How long to..."
    case expenses      // "How much did I spend?"
    case multi         // Combines multiple intents
    case general       // Generic conversation
}

/// Represents intent extracted from user query with high confidence
struct IntentContext: Codable {
    let intent: ChatIntent
    let subIntents: [ChatIntent]  // For multi-intent queries
    let entities: [String]         // Keywords extracted from query
    let dateRange: DateRange?      // If temporal
    let locationFilter: LocationFilter?  // If geographic
    let confidence: Double          // 0.0 - 1.0
    let matchType: MatchType       // How the intent was detected

    enum MatchType: String, Codable {
        case keyword_exact      // Exact keyword match
        case keyword_fuzzy      // Fuzzy keyword match
        case pattern_detected   // Pattern detected (e.g., "show me...")
        case semantic_fallback  // LLM-based semantic classification
    }
}

/// Date range filter
struct DateRange: Codable {
    let start: Date
    let end: Date
    let period: TimePeriod

    enum TimePeriod: String, Codable {
        case today
        case tomorrow
        case thisWeek
        case nextWeek
        case thisMonth
        case lastMonth
        case thisYear
        case custom
    }
}

/// Location filter for geographic queries
struct LocationFilter: Codable {
    let city: String?
    let province: String?
    let country: String?
    let category: String?      // Folder/category filter
    let minRating: Double?     // Minimum rating filter
}

/// Service for extracting intent from user queries
@MainActor
class IntentExtractor {
    static let shared = IntentExtractor()

    private init() {}

    // MARK: - Main Intent Extraction

    /// Extract intent and context from user query
    func extractIntent(from query: String) -> IntentContext {
        let lowercased = query.lowercased()

        // Step 1: Extract entities (keywords)
        let entities = extractEntities(from: lowercased)

        // Step 2: Detect date range if temporal
        let dateRange = detectDateRange(from: lowercased)

        // Step 3: Detect location filter if geographic
        let locationFilter = detectLocationFilter(from: lowercased)

        // Step 4: Classify primary intent
        let (primaryIntent, confidence) = classifyIntent(
            query: lowercased,
            entities: entities,
            hasDateRange: dateRange != nil,
            hasLocationFilter: locationFilter != nil
        )

        // Step 5: Detect sub-intents for multi-intent queries
        let subIntents = detectSubIntents(query: lowercased, primaryIntent: primaryIntent)

        // Determine match type
        let matchType: IntentContext.MatchType
        if confidence > 0.95 {
            matchType = .keyword_exact
        } else if confidence > 0.75 {
            matchType = .keyword_fuzzy
        } else {
            matchType = .pattern_detected
        }

        return IntentContext(
            intent: primaryIntent,
            subIntents: subIntents,
            entities: entities,
            dateRange: dateRange,
            locationFilter: locationFilter,
            confidence: confidence,
            matchType: matchType
        )
    }

    // MARK: - Entity Extraction

    /// Extract keywords and entities from query
    private func extractEntities(from lowercasedQuery: String) -> [String] {
        var entities: [String] = []

        // Remove common filler words
        let fillerWords = Set(["the", "a", "an", "and", "or", "is", "are", "be", "have", "has", "do", "does", "did", "will", "would", "can", "could", "should", "my", "me", "i", "you", "show", "me", "tell", "me", "find", "search", "look", "for", "in", "on", "at", "to", "from", "about", "what", "when", "where", "who", "why", "how", "which"])

        let words = lowercasedQuery
            .replacingOccurrences(of: "?", with: "")
            .components(separatedBy: .whitespaces)
            .filter { word in
                !word.isEmpty && !fillerWords.contains(word) && word.count > 2
            }

        // Remove duplicates and take meaningful words
        entities = Array(Set(words)).sorted()

        return entities
    }

    // MARK: - Date Range Detection

    /// Detect temporal range from query
    private func detectDateRange(from lowercasedQuery: String) -> DateRange? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Today
        if lowercasedQuery.contains("today") || lowercasedQuery.contains("is today") {
            let end = calendar.date(byAdding: .day, value: 1, to: today)!
            return DateRange(start: today, end: end, period: .today)
        }

        // Tomorrow
        if lowercasedQuery.contains("tomorrow") {
            let start = calendar.date(byAdding: .day, value: 1, to: today)!
            let end = calendar.date(byAdding: .day, value: 2, to: today)!
            return DateRange(start: start, end: end, period: .tomorrow)
        }

        // This week
        if lowercasedQuery.contains("this week") || lowercasedQuery.contains("week") {
            let start = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            let startOfWeek = calendar.date(from: start)!
            let end = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            return DateRange(start: startOfWeek, end: end, period: .thisWeek)
        }

        // Next week
        if lowercasedQuery.contains("next week") {
            let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: today)!
            let start = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeekStart)
            let startOfWeek = calendar.date(from: start)!
            let end = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            return DateRange(start: startOfWeek, end: end, period: .nextWeek)
        }

        // This month
        if lowercasedQuery.contains("this month") || lowercasedQuery.contains("month") {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return DateRange(start: start, end: end, period: .thisMonth)
        }

        // Last month
        if lowercasedQuery.contains("last month") {
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonth))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return DateRange(start: start, end: end, period: .lastMonth)
        }

        // This year
        if lowercasedQuery.contains("this year") || lowercasedQuery.contains("year") {
            let start = calendar.date(from: calendar.dateComponents([.year], from: today))!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return DateRange(start: start, end: end, period: .thisYear)
        }

        return nil
    }

    // MARK: - Location Filter Detection

    /// Detect geographic filters from query
    private func detectLocationFilter(from lowercasedQuery: String) -> LocationFilter? {
        // Check for city/country mentions (this is basic - could be enhanced)
        let cities = ["toronto", "vancouver", "new york", "san francisco", "london", "paris", "tokyo"]
        let countries = ["canada", "usa", "uk", "france", "japan", "germany"]
        let categories = ["cafe", "restaurant", "coffee", "gym", "bank", "grocery", "store", "hotel"]

        var detectedCity: String?
        var detectedCountry: String?
        var detectedCategory: String?

        for city in cities {
            if lowercasedQuery.contains(city) {
                detectedCity = city
                break
            }
        }

        for country in countries {
            if lowercasedQuery.contains(country) {
                detectedCountry = country
                break
            }
        }

        for category in categories {
            if lowercasedQuery.contains(category) {
                detectedCategory = category
                break
            }
        }

        // Only return filter if something was detected
        if detectedCity != nil || detectedCountry != nil || detectedCategory != nil {
            return LocationFilter(
                city: detectedCity,
                province: nil,
                country: detectedCountry,
                category: detectedCategory,
                minRating: nil
            )
        }

        return nil
    }

    // MARK: - Intent Classification

    /// Classify the primary intent based on keywords
    private func classifyIntent(
        query: String,
        entities: [String],
        hasDateRange: Bool,
        hasLocationFilter: Bool
    ) -> (intent: ChatIntent, confidence: Double) {
        var intents: [(ChatIntent, Double)] = []

        // Calendar/Events
        let calendarKeywords = ["calendar", "schedule", "event", "meeting", "when", "appointment", "busy", "free", "available"]
        let calendarScore = scoreMatch(query: query, keywords: calendarKeywords)
        if calendarScore > 0 {
            intents.append((.calendar, calendarScore))
        }

        // Notes
        let noteKeywords = ["note", "notes", "remind", "remember", "memo", "write", "document"]
        let noteScore = scoreMatch(query: query, keywords: noteKeywords)
        if noteScore > 0 {
            intents.append((.notes, noteScore))
        }

        // Locations
        let locationKeywords = ["location", "place", "where", "near", "nearby", "address", "visit", "restaurant", "cafe", "coffee", "store"]
        let locationScore = scoreMatch(query: query, keywords: locationKeywords)
        if locationScore > 0 {
            intents.append((.locations, locationScore))
        }

        // Weather
        let weatherKeywords = ["weather", "rain", "snow", "temperature", "cold", "hot", "sunny", "cloudy", "forecast"]
        let weatherScore = scoreMatch(query: query, keywords: weatherKeywords)
        if weatherScore > 0 {
            intents.append((.weather, weatherScore))
        }

        // Email
        let emailKeywords = ["email", "email", "message", "inbox", "from", "sender", "subject"]
        let emailScore = scoreMatch(query: query, keywords: emailKeywords)
        if emailScore > 0 {
            intents.append((.email, emailScore))
        }

        // Navigation
        let navigationKeywords = ["how far", "how long", "distance", "travel time", "eta", "drive", "hours away"]
        let navigationScore = scoreMatch(query: query, keywords: navigationKeywords)
        if navigationScore > 0 {
            intents.append((.navigation, navigationScore))
        }

        // Expenses
        let expenseKeywords = ["expense", "spend", "spending", "cost", "receipt", "money", "budget", "amount", "price"]
        let expenseScore = scoreMatch(query: query, keywords: expenseKeywords)
        if expenseScore > 0 {
            intents.append((.expenses, expenseScore))
        }

        // Sort by score and get the highest
        intents.sort { $0.1 > $1.1 }

        if let (topIntent, score) = intents.first, score > 0.3 {
            return (topIntent, score)
        }

        // Fallback to general
        return (.general, 0.5)
    }

    /// Score how well query matches a set of keywords
    private func scoreMatch(query: String, keywords: [String]) -> Double {
        var score: Double = 0

        for keyword in keywords {
            if query.contains(keyword) {
                score += 1.0
            }
        }

        // Normalize to 0-1 range
        return min(score / Double(keywords.count), 1.0)
    }

    // MARK: - Sub-Intent Detection

    /// Detect sub-intents for multi-intent queries
    private func detectSubIntents(query: String, primaryIntent: ChatIntent) -> [ChatIntent] {
        var subIntents: [ChatIntent] = []

        let calendarKeywords = ["calendar", "schedule", "event", "meeting", "when"]
        let noteKeywords = ["note", "notes", "remind", "memo"]
        let locationKeywords = ["where", "place", "restaurant", "cafe"]
        let weatherKeywords = ["weather", "rain", "forecast"]
        let emailKeywords = ["email", "message", "inbox"]
        let navigationKeywords = ["how far", "distance", "travel"]
        let expenseKeywords = ["spend", "cost", "receipt"]

        if scoreMatch(query: query, keywords: calendarKeywords) > 0.3 && primaryIntent != .calendar {
            subIntents.append(.calendar)
        }
        if scoreMatch(query: query, keywords: noteKeywords) > 0.3 && primaryIntent != .notes {
            subIntents.append(.notes)
        }
        if scoreMatch(query: query, keywords: locationKeywords) > 0.3 && primaryIntent != .locations {
            subIntents.append(.locations)
        }
        if scoreMatch(query: query, keywords: weatherKeywords) > 0.3 && primaryIntent != .weather {
            subIntents.append(.weather)
        }
        if scoreMatch(query: query, keywords: emailKeywords) > 0.3 && primaryIntent != .email {
            subIntents.append(.email)
        }
        if scoreMatch(query: query, keywords: navigationKeywords) > 0.3 && primaryIntent != .navigation {
            subIntents.append(.navigation)
        }
        if scoreMatch(query: query, keywords: expenseKeywords) > 0.3 && primaryIntent != .expenses {
            subIntents.append(.expenses)
        }

        return subIntents
    }
}
