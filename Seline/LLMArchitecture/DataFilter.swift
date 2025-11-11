import Foundation

// MARK: - Relevance Wrappers

/// Note with relevance score
struct NoteWithRelevance: Codable {
    let note: Note
    let relevanceScore: Double  // 0.0 - 1.0
    let matchType: MatchType
    let snippets: [String]      // Highlighted relevant excerpts

    enum MatchType: String, Codable {
        case exact_title
        case exact_content
        case folder_match
        case content_keyword
        case date_match
    }
}

/// Task/Event with relevance score
struct TaskItemWithRelevance: Codable {
    let task: TaskItem
    let relevanceScore: Double
    let matchType: MatchType

    enum MatchType: String, Codable {
        case exact_match
        case keyword_match
        case date_range_match
        case category_match
    }
}

/// Location with relevance score
struct SavedPlaceWithRelevance: Codable {
    let place: SavedPlace
    let relevanceScore: Double
    let matchType: MatchType
    let distanceFromLocation: String?  // e.g., "0.3 km"

    enum MatchType: String, Codable {
        case exact_match
        case category_match
        case geographic_match
        case rating_match
        case distance_match
    }
}

/// Email with relevance score
struct EmailWithRelevance: Codable {
    let email: Email
    let relevanceScore: Double
    let matchType: MatchType
    let importanceIndicators: [String]  // e.g., ["critical", "action_required"]

    enum MatchType: String, Codable {
        case sender_match
        case subject_match
        case content_match
        case date_match
    }
}

/// Filtered context ready for LLM
struct FilteredContext {
    let notes: [NoteWithRelevance]?
    let locations: [SavedPlaceWithRelevance]?
    let tasks: [TaskItemWithRelevance]?
    let emails: [EmailWithRelevance]?
    let receipts: [ReceiptWithRelevance]?
    let receiptStatistics: ReceiptStatistics?
    let weather: WeatherData?
    let metadata: ContextMetadata

    struct ContextMetadata: Codable {
        let timestamp: Date
        let currentWeather: String?
        let userTimezone: String
        let queryIntent: String
        let dateRangeQueried: String?
    }
}

// MARK: - DataFilter Service

@MainActor
class DataFilter {
    static let shared = DataFilter()

    private init() {}

    // MARK: - Main Filtering Function

    /// Filter data based on intent and create a ranked result set
    /// Now async to support merchant intelligence lookups
    func filterDataForQuery(
        intent: IntentContext,
        notes: [Note],
        locations: [SavedPlace],
        tasks: [TaskItem],
        emails: [Email],
        receipts: [ReceiptStat],
        weather: WeatherData?
    ) async -> FilteredContext {
        var filteredNotes: [NoteWithRelevance]? = nil
        var filteredLocations: [SavedPlaceWithRelevance]? = nil
        var filteredTasks: [TaskItemWithRelevance]? = nil
        var filteredEmails: [EmailWithRelevance]? = nil
        var filteredReceipts: [ReceiptWithRelevance]? = nil
        var receiptStats: ReceiptStatistics? = nil

        // Filter based on primary intent
        switch intent.intent {
        case .notes:
            filteredNotes = filterNotes(notes, intent: intent)

        case .locations:
            filteredLocations = filterLocations(locations, intent: intent)

        case .calendar:
            filteredTasks = filterTasks(tasks, intent: intent)

        case .email:
            filteredEmails = filterEmails(emails, intent: intent)

        case .weather:
            // Weather is returned as-is
            break

        case .navigation:
            // Navigation uses locations
            filteredLocations = filterLocations(locations, intent: intent, forNavigation: true)

        case .expenses:
            filteredReceipts = await ReceiptFilter.shared.filterReceiptsForQuery(
                intent: intent,
                receipts: receipts
            )
            if !receipts.isEmpty {
                receiptStats = ReceiptFilter.shared.calculateReceiptStatistics(from: filteredReceipts ?? [])
            }

        case .multi:
            // Multi-intent: filter everything
            if intent.subIntents.contains(.notes) {
                filteredNotes = filterNotes(notes, intent: intent)
            }
            if intent.subIntents.contains(.locations) {
                filteredLocations = filterLocations(locations, intent: intent)
            }
            if intent.subIntents.contains(.calendar) {
                filteredTasks = filterTasks(tasks, intent: intent)
            }
            if intent.subIntents.contains(.email) {
                filteredEmails = filterEmails(emails, intent: intent)
            }
            if intent.subIntents.contains(.expenses) {
                filteredReceipts = await ReceiptFilter.shared.filterReceiptsForQuery(
                    intent: intent,
                    receipts: receipts
                )
                if !receipts.isEmpty {
                    receiptStats = ReceiptFilter.shared.calculateReceiptStatistics(from: filteredReceipts ?? [])
                }
            }

        case .general:
            // For general queries, include minimal samples of all types
            filteredNotes = Array(filterNotes(notes, intent: intent).prefix(2))
            filteredLocations = Array(filterLocations(locations, intent: intent).prefix(2))
            filteredTasks = Array(filterTasks(tasks, intent: intent).prefix(2))
            filteredEmails = Array(filterEmails(emails, intent: intent).prefix(2))
        }

        // Build metadata
        let weatherDescription = weather.map { weather -> String in
            // Handle WeatherData properties - safe unwrapping
            return "\(Int(weather.temperature))°C"
        }

        let metadata = FilteredContext.ContextMetadata(
            timestamp: Date(),
            currentWeather: weatherDescription,
            userTimezone: TimeZone.current.identifier,
            queryIntent: intent.intent.rawValue,
            dateRangeQueried: intent.dateRange?.period.rawValue
        )

        return FilteredContext(
            notes: filteredNotes,
            locations: filteredLocations,
            tasks: filteredTasks,
            emails: filteredEmails,
            receipts: filteredReceipts,
            receiptStatistics: receiptStats,
            weather: weather,
            metadata: metadata
        )
    }

    // MARK: - Notes Filtering

    /// Filter and rank notes based on relevance to query
    private func filterNotes(_ notes: [Note], intent: IntentContext) -> [NoteWithRelevance] {
        var scored: [NoteWithRelevance] = []

        for note in notes {
            var score: Double = 0
            var matchType: NoteWithRelevance.MatchType = .content_keyword
            var snippets: [String] = []

            let lowerContent = note.content.lowercased()
            let lowerTitle = note.title.lowercased()

            // Match against entities
            for entity in intent.entities {
                let lowerEntity = entity.lowercased()

                // Exact title match (highest score)
                if lowerTitle == lowerEntity {
                    score += 10.0
                    matchType = .exact_title
                }
                // Title contains entity
                else if lowerTitle.contains(lowerEntity) {
                    score += 5.0
                    matchType = .exact_title
                }
                // Content contains entity
                else if lowerContent.contains(lowerEntity) {
                    score += 2.0
                    matchType = .content_keyword
                    // Extract snippet around match
                    if let snippet = extractSnippet(from: lowerContent, keyword: lowerEntity) {
                        snippets.append(snippet)
                    }
                }
            }

            // Bonus for date range match
            if let dateRange = intent.dateRange {
                if note.dateCreated >= dateRange.start && note.dateCreated <= dateRange.end {
                    score += 1.5
                    matchType = .date_match
                }
            }

            // Only include notes with some relevance
            if score > 0 {
                scored.append(NoteWithRelevance(
                    note: note,
                    relevanceScore: min(score / 10.0, 1.0),  // Normalize to 0-1
                    matchType: matchType,
                    snippets: Array(snippets.prefix(2))  // Limit snippets
                ))
            }
        }

        // Sort by relevance score (highest first)
        scored.sort { $0.relevanceScore > $1.relevanceScore }

        // Return top 8 results
        return Array(scored.prefix(8))
    }

    // MARK: - Tasks Filtering

    /// Filter and rank tasks based on relevance
    private func filterTasks(_ tasks: [TaskItem], intent: IntentContext) -> [TaskItemWithRelevance] {
        var scored: [TaskItemWithRelevance] = []

        for task in tasks {
            var score: Double = 0
            var matchType: TaskItemWithRelevance.MatchType = .keyword_match

            let lowerTitle = task.title.lowercased()
            let lowerDescription = task.description?.lowercased() ?? ""

            // Check date range first (use scheduledTime or targetDate)
            let taskDate = task.scheduledTime ?? task.targetDate
            if let dateRange = intent.dateRange, let tDate = taskDate {
                if tDate >= dateRange.start && tDate <= dateRange.end {
                    score += 5.0
                    matchType = .date_range_match
                } else {
                    // Task is outside the requested date range, skip it
                    continue
                }
            }

            // Match against entities
            for entity in intent.entities {
                let lowerEntity = entity.lowercased()

                if lowerTitle.contains(lowerEntity) {
                    score += 3.0
                    matchType = .keyword_match
                } else if lowerDescription.contains(lowerEntity) {
                    score += 1.5
                }
            }

            // Include if date range matches or score > 0
            if (intent.dateRange != nil && score > 0) || intent.dateRange == nil && score > 0 {
                scored.append(TaskItemWithRelevance(
                    task: task,
                    relevanceScore: min(score / 5.0, 1.0),
                    matchType: matchType
                ))
            }
        }

        // Sort by date, then relevance
        scored.sort { task1, task2 in
            let date1 = task1.task.scheduledTime ?? task1.task.targetDate ?? Date.distantFuture
            let date2 = task2.task.scheduledTime ?? task2.task.targetDate ?? Date.distantFuture

            if date1 == date2 {
                return task1.relevanceScore > task2.relevanceScore
            }
            return date1 < date2
        }

        // Return all tasks in date range (usually < 15 items)
        return scored
    }

    // MARK: - Locations Filtering

    /// Filter and rank saved locations based on relevance
    private func filterLocations(
        _ locations: [SavedPlace],
        intent: IntentContext,
        forNavigation: Bool = false
    ) -> [SavedPlaceWithRelevance] {
        var scored: [SavedPlaceWithRelevance] = []

        for place in locations {
            var score: Double = 0
            var matchType: SavedPlaceWithRelevance.MatchType = .exact_match
            var distanceStr: String? = nil

            let lowerName = place.name.lowercased()
            let lowerCategory = place.category.lowercased()

            // Geographic filter
            if let locationFilter = intent.locationFilter {
                var geoMatch = false

                // Check country
                if let filterCountry = locationFilter.country,
                   let placeCountry = place.country,
                   placeCountry.lowercased().contains(filterCountry) {
                    score += 5.0
                    geoMatch = true
                    matchType = .geographic_match
                }

                // Check city
                if let filterCity = locationFilter.city,
                   let placeCity = place.city,
                   placeCity.lowercased().contains(filterCity) {
                    score += 4.0
                    geoMatch = true
                    matchType = .geographic_match
                }

                // Check province
                if let filterProvince = locationFilter.province,
                   let placeProvince = place.province,
                   placeProvince.lowercased().contains(filterProvince) {
                    score += 3.0
                    geoMatch = true
                    matchType = .geographic_match
                }

                // If geographic filter specified but didn't match, skip
                if (locationFilter.country != nil || locationFilter.city != nil || locationFilter.province != nil) && !geoMatch {
                    continue
                }

                // Check category/folder
                if let filterCategory = locationFilter.category,
                   lowerCategory.contains(filterCategory) {
                    score += 3.0
                    matchType = .category_match
                }

                // Check minimum rating
                if let minRating = locationFilter.minRating,
                   let rating = place.rating,
                   rating < minRating {
                    continue
                }
            }

            // Match against entities
            for entity in intent.entities {
                let lowerEntity = entity.lowercased()

                if lowerName.contains(lowerEntity) {
                    score += 3.0
                    matchType = .exact_match
                } else if lowerCategory.contains(lowerEntity) {
                    score += 2.0
                    matchType = .category_match
                }
            }

            // Rating boost
            if let rating = place.rating {
                let ratingBoost = rating / 5.0 * 0.5  // Max 0.5 boost
                score += ratingBoost
            }

            // Only include locations with relevance
            if score > 0 {
                // Format distance if navigation query
                if forNavigation {
                    let dist = calculateDistance(latitude: place.latitude, longitude: place.longitude)
                    distanceStr = formatDistance(dist)
                }

                scored.append(SavedPlaceWithRelevance(
                    place: place,
                    relevanceScore: min(score / 5.0, 1.0),
                    matchType: matchType,
                    distanceFromLocation: distanceStr
                ))
            }
        }

        // Sort by relevance
        scored.sort { $0.relevanceScore > $1.relevanceScore }

        // Return top 8 results
        return Array(scored.prefix(8))
    }

    // MARK: - Emails Filtering

    /// Filter and rank emails based on relevance
    private func filterEmails(_ emails: [Email], intent: IntentContext) -> [EmailWithRelevance] {
        var scored: [EmailWithRelevance] = []

        for email in emails {
            var score: Double = 0
            var matchType: EmailWithRelevance.MatchType = .content_match
            var importanceIndicators: [String] = []

            let lowerFrom = (email.sender.name ?? email.sender.email).lowercased()
            let lowerSubject = email.subject.lowercased()
            let lowerBody = (email.body ?? "").lowercased()

            // Check date range
            if let dateRange = intent.dateRange {
                if email.timestamp >= dateRange.start && email.timestamp <= dateRange.end {
                    score += 3.0
                    matchType = .date_match
                } else {
                    // Email is outside requested date range
                    continue
                }
            }

            // Match against entities
            for entity in intent.entities {
                let lowerEntity = entity.lowercased()

                // Sender match
                if lowerFrom.contains(lowerEntity) {
                    score += 4.0
                    matchType = .sender_match
                }
                // Subject match
                else if lowerSubject.contains(lowerEntity) {
                    score += 3.0
                    matchType = .subject_match
                }
                // Body match
                else if lowerBody.contains(lowerEntity) {
                    score += 2.0
                    matchType = .content_match
                }
            }

            // Detect importance signals
            let importanceKeywords = ["urgent", "critical", "asap", "action required", "deadline", "important", "error", "warning", "failed"]
            for keyword in importanceKeywords {
                if lowerSubject.contains(keyword) || lowerBody.contains(keyword) {
                    importanceIndicators.append(keyword)
                    score += 1.0
                }
            }

            // Important emails get boost
            if email.isImportant {
                score += 0.5
            }

            // Only include emails with some relevance
            if score > 0 {
                scored.append(EmailWithRelevance(
                    email: email,
                    relevanceScore: min(score / 4.0, 1.0),
                    matchType: matchType,
                    importanceIndicators: importanceIndicators
                ))
            }
        }

        // Sort by relevance, then date (most recent first)
        scored.sort { email1, email2 in
            if abs(email1.relevanceScore - email2.relevanceScore) > 0.1 {
                return email1.relevanceScore > email2.relevanceScore
            }
            return email1.email.timestamp > email2.email.timestamp
        }

        // Return top 10 results
        return Array(scored.prefix(10))
    }

    // MARK: - Helper Methods

    /// Extract a snippet from text around a keyword
    private func extractSnippet(from text: String, keyword: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }

        let index = text.distance(from: text.startIndex, to: range.lowerBound)
        let startIndex = max(0, index - 50)
        let endIndex = min(text.count, index + keyword.count + 50)

        let start = text.index(text.startIndex, offsetBy: startIndex)
        let end = text.index(text.startIndex, offsetBy: endIndex)

        let snippet = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        return "...\(snippet)..."
    }

    /// Calculate distance from user's current location (placeholder)
    private func calculateDistance(latitude: Double, longitude: Double) -> Double {
        // This would use actual user location in production
        // For now, return a placeholder
        return 0.5  // km
    }

    /// Format distance for display
    private func formatDistance(_ km: Double) -> String {
        if km < 1.0 {
            return "\(Int(km * 1000)) m"
        }
        return String(format: "%.1f km", km)
    }
}
