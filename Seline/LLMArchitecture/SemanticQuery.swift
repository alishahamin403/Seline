import Foundation

// MARK: - Universal Semantic Query System
// This replaces rigid query types with flexible semantic intent description

/// Main semantic query structure - describes exactly what data transformation is needed
struct SemanticQuery {
    let userQuery: String
    let intent: QueryIntent
    let dataSources: [DataSource]
    let filters: [AnyFilter]
    let operations: [AnyOperation]
    let presentation: PresentationRules
    let confidence: Double
    let reasoning: String

    var isValid: Bool {
        confidence > 0.3 && !dataSources.isEmpty
    }
}

// MARK: - Query Intent (WHAT the user wants to do)

enum QueryIntent: String, Codable {
    case search       // Find items matching criteria
    case compare      // Compare entities or time periods
    case analyze      // Statistics, trends, patterns
    case explore      // Browse/discover data
    case track        // Monitor status/progress
    case summarize    // Overview/digest
    case predict      // Forecast/suggest
}

// MARK: - Data Sources (WHERE to look)

enum DataSource: Hashable, Codable {
    case receipts(category: String? = nil)
    case emails(folder: String? = nil)
    case events(status: EventStatus? = nil)
    case notes(folder: String? = nil)
    case locations(type: LocationFilter? = nil)
    case calendar

    enum CodingKeys: String, CodingKey {
        case type, category, folder, status, locationType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .receipts(let category):
            try container.encode("receipts", forKey: .type)
            try container.encodeIfPresent(category, forKey: .category)
        case .emails(let folder):
            try container.encode("emails", forKey: .type)
            try container.encodeIfPresent(folder, forKey: .folder)
        case .events(let status):
            try container.encode("events", forKey: .type)
            try container.encodeIfPresent(status?.rawValue, forKey: .status)
        case .notes(let folder):
            try container.encode("notes", forKey: .type)
            try container.encodeIfPresent(folder, forKey: .folder)
        case .locations(let filter):
            try container.encode("locations", forKey: .type)
            try container.encodeIfPresent(filter?.rawValue, forKey: .locationType)
        case .calendar:
            try container.encode("calendar", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "receipts":
            let category = try container.decodeIfPresent(String.self, forKey: .category)
            self = .receipts(category: category)
        case "emails":
            let folder = try container.decodeIfPresent(String.self, forKey: .folder)
            self = .emails(folder: folder)
        case "events":
            let status = try container.decodeIfPresent(String.self, forKey: .status)
                .flatMap { EventStatus(rawValue: $0) }
            self = .events(status: status)
        case "notes":
            let folder = try container.decodeIfPresent(String.self, forKey: .folder)
            self = .notes(folder: folder)
        case "locations":
            let filter = try container.decodeIfPresent(String.self, forKey: .locationType)
                .flatMap { LocationFilter(rawValue: $0) }
            self = .locations(type: filter)
        case "calendar":
            self = .calendar
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown data source type")
        }
    }
}

enum EventStatus: String, Codable {
    case upcoming
    case completed
    case all
}

enum LocationFilter: String, Codable {
    case favorited
    case ranked
    case inFolder
}

// MARK: - Filters (HOW to constrain data)

/// Type-erased filter protocol
protocol FilterProtocol {
    func matches(_ item: UniversalItem) -> Bool
    func description() -> String
}

/// Type-erased wrapper for any filter
struct AnyFilter: FilterProtocol {
    private let _matches: (UniversalItem) -> Bool
    private let _description: () -> String

    init<F: FilterProtocol>(_ filter: F) {
        self._matches = filter.matches
        self._description = filter.description
    }

    func matches(_ item: UniversalItem) -> Bool {
        _matches(item)
    }

    func description() -> String {
        _description()
    }
}

struct DateRangeFilter: FilterProtocol {
    let startDate: Date?
    let endDate: Date?
    let labels: [String]

    func matches(_ item: UniversalItem) -> Bool {
        let itemDate = item.date

        if let start = startDate, itemDate < start {
            return false
        }

        if let end = endDate, itemDate > end {
            return false
        }

        return true
    }

    func description() -> String {
        let parts = [
            labels.isEmpty ? nil : "period: \(labels.joined(separator: ", "))",
            startDate.map { "from: \($0.formatted())" },
            endDate.map { "to: \($0.formatted())" }
        ].compactMap { $0 }

        return parts.isEmpty ? "date range" : parts.joined(separator: ", ")
    }
}

struct CategoryFilter: FilterProtocol {
    let categories: [String]
    let excludeCategories: [String]

    func matches(_ item: UniversalItem) -> Bool {
        let itemCategory = item.category

        if !excludeCategories.isEmpty && excludeCategories.contains(itemCategory) {
            return false
        }

        if categories.isEmpty {
            return true
        }

        return categories.contains(itemCategory)
    }

    func description() -> String {
        var parts: [String] = []
        if !categories.isEmpty {
            parts.append("categories: \(categories.joined(separator: ", "))")
        }
        if !excludeCategories.isEmpty {
            parts.append("exclude: \(excludeCategories.joined(separator: ", "))")
        }
        return parts.isEmpty ? "category filter" : parts.joined(separator: ", ")
    }
}

struct TextSearchFilter: FilterProtocol {
    let query: String
    let fields: [String]
    let fuzzyMatch: Bool

    func matches(_ item: UniversalItem) -> Bool {
        let searchText = item.searchableContent.lowercased()
        let queryLower = query.lowercased()

        if fuzzyMatch {
            // Simple fuzzy: check if query appears as substring
            return searchText.contains(queryLower)
        } else {
            // Exact match required
            return searchText.contains(queryLower)
        }
    }

    func description() -> String {
        "search: '\(query)' in \(fields.isEmpty ? "all fields" : fields.joined(separator: ", "))"
    }
}

struct StatusFilter: FilterProtocol {
    let status: String

    func matches(_ item: UniversalItem) -> Bool {
        item.status.lowercased() == status.lowercased()
    }

    func description() -> String {
        "status: \(status)"
    }
}

struct AmountRangeFilter: FilterProtocol {
    let minAmount: Double?
    let maxAmount: Double?

    func matches(_ item: UniversalItem) -> Bool {
        let amount = item.amount

        if let min = minAmount, amount < min {
            return false
        }

        if let max = maxAmount, amount > max {
            return false
        }

        return true
    }

    func description() -> String {
        var parts: [String] = []
        if let min = minAmount {
            parts.append("min: $\(String(format: "%.2f", min))")
        }
        if let max = maxAmount {
            parts.append("max: $\(String(format: "%.2f", max))")
        }
        return parts.isEmpty ? "amount range" : parts.joined(separator: ", ")
    }
}

struct MerchantFilter: FilterProtocol {
    let merchants: [String]
    let fuzzyMatch: Bool

    func matches(_ item: UniversalItem) -> Bool {
        guard !merchants.isEmpty else { return true }

        let itemMerchant = item.merchant.lowercased()

        for merchant in merchants {
            let searchTerm = merchant.lowercased()
            if fuzzyMatch {
                if itemMerchant.contains(searchTerm) {
                    return true
                }
            } else {
                if itemMerchant == searchTerm {
                    return true
                }
            }
        }

        return false
    }

    func description() -> String {
        "merchants: \(merchants.joined(separator: ", "))"
    }
}

// MARK: - Operations (WHAT to do with the data)

protocol OperationProtocol {
    func execute(on items: [UniversalItem]) -> QueryResultData
    func description() -> String
}

struct AnyOperation: OperationProtocol {
    private let _execute: ([UniversalItem]) -> QueryResultData
    private let _description: () -> String

    init<O: OperationProtocol>(_ operation: O) {
        self._execute = operation.execute
        self._description = operation.description
    }

    func execute(on items: [UniversalItem]) -> QueryResultData {
        _execute(items)
    }

    func description() -> String {
        _description()
    }
}

struct AggregateOperation: OperationProtocol {
    enum AggregationType {
        case count
        case sum(field: String)
        case average(field: String)
        case min(field: String)
        case max(field: String)
    }

    let type: AggregationType
    let groupBy: String?
    let sortBy: String?

    func execute(on items: [UniversalItem]) -> QueryResultData {
        if let groupBy = groupBy {
            return executeGrouped(items, groupBy: groupBy)
        } else {
            return executeFlat(items)
        }
    }

    private func executeFlat(_ items: [UniversalItem]) -> QueryResultData {
        let value: String

        switch type {
        case .count:
            value = "\(items.count)"
        case .sum(let field):
            let total = items.reduce(0.0) { $0 + $1.amount }
            value = String(format: "$%.2f", total)
        case .average(let field):
            guard !items.isEmpty else { value = "$0.00"; break }
            let total = items.reduce(0.0) { $0 + $1.amount }
            let avg = total / Double(items.count)
            value = String(format: "$%.2f", avg)
        case .min(let field):
            let min = items.min(by: { $0.amount < $1.amount })?.amount ?? 0
            value = String(format: "$%.2f", min)
        case .max(let field):
            let max = items.max(by: { $0.amount < $1.amount })?.amount ?? 0
            value = String(format: "$%.2f", max)
        }

        return QueryResultData(
            items: items,
            aggregations: [AggregationResult(label: describeAggregation(), value: value, groupKey: nil)],
            comparisons: [],
            trends: []
        )
    }

    private func executeGrouped(_ items: [UniversalItem], groupBy: String) -> QueryResultData {
        var grouped: [String: [UniversalItem]] = [:]

        for item in items {
            let key: String
            switch groupBy.lowercased() {
            case "category":
                key = item.category
            case "merchant":
                key = item.merchant
            case "status":
                key = item.status
            case "date":
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                key = formatter.string(from: item.date)
            default:
                key = "Other"
            }

            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(item)
        }

        let results = grouped.map { key, items -> AggregationResult in
            let value: String
            switch type {
            case .count:
                value = "\(items.count)"
            case .sum:
                let total = items.reduce(0.0) { $0 + $1.amount }
                value = String(format: "$%.2f", total)
            case .average:
                let total = items.reduce(0.0) { $0 + $1.amount }
                let avg = items.isEmpty ? 0 : total / Double(items.count)
                value = String(format: "$%.2f", avg)
            case .min:
                let min = items.min(by: { $0.amount < $1.amount })?.amount ?? 0
                value = String(format: "$%.2f", min)
            case .max:
                let max = items.max(by: { $0.amount < $1.amount })?.amount ?? 0
                value = String(format: "$%.2f", max)
            }

            return AggregationResult(label: key, value: value, groupKey: key)
        }.sorted { a, b in
            // Sort by amount if numeric values
            if let aVal = Double(a.value.replacingOccurrences(of: "$", with: "")),
               let bVal = Double(b.value.replacingOccurrences(of: "$", with: "")) {
                return aVal > bVal
            }
            if let aNum = Int(a.value), let bNum = Int(b.value) {
                return aNum > bNum
            }
            return a.label < b.label
        }

        return QueryResultData(
            items: items,
            aggregations: results,
            comparisons: [],
            trends: []
        )
    }

    func description() -> String {
        let aggType = describeAggregation()
        if let groupBy = groupBy {
            return "group by \(groupBy), then \(aggType)"
        }
        return aggType
    }

    private func describeAggregation() -> String {
        switch type {
        case .count:
            return "count items"
        case .sum:
            return "sum amounts"
        case .average:
            return "average amount"
        case .min:
            return "minimum amount"
        case .max:
            return "maximum amount"
        }
    }
}

struct ComparisonOperation: OperationProtocol {
    let dimension: String
    let slices: [String]
    let metric: String

    func execute(on items: [UniversalItem]) -> QueryResultData {
        var sliceData: [String: [UniversalItem]] = [:]

        for slice in slices {
            sliceData[slice] = filterItemsForSlice(items, slice: slice, dimension: dimension)
        }

        let comparisonResult = ComparisonResult(
            dimension: dimension,
            slices: sliceData.mapValues { computeMetric($0, metric: metric) }
        )

        return QueryResultData(
            items: items,
            aggregations: [],
            comparisons: [comparisonResult],
            trends: []
        )
    }

    private func filterItemsForSlice(_ items: [UniversalItem], slice: String, dimension: String) -> [UniversalItem] {
        switch dimension.lowercased() {
        case "time", "month":
            return items.filter { item in
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: item.date).lowercased().contains(slice.lowercased())
            }
        case "category":
            return items.filter { $0.category.lowercased() == slice.lowercased() }
        case "merchant":
            return items.filter { $0.merchant.lowercased() == slice.lowercased() }
        case "status":
            return items.filter { $0.status.lowercased() == slice.lowercased() }
        default:
            return items
        }
    }

    private func computeMetric(_ items: [UniversalItem], metric: String) -> String {
        switch metric.lowercased() {
        case "total", "total_spent", "sum":
            let total = items.reduce(0.0) { $0 + $1.amount }
            return String(format: "$%.2f", total)
        case "count":
            return "\(items.count)"
        case "average":
            guard !items.isEmpty else { return "$0.00" }
            let total = items.reduce(0.0) { $0 + $1.amount }
            return String(format: "$%.2f", total / Double(items.count))
        default:
            return "\(items.count) items"
        }
    }

    func description() -> String {
        "compare \(dimension) across \(slices.joined(separator: ", ")) by \(metric)"
    }
}

struct SearchOperation: OperationProtocol {
    let query: String
    let rankBy: String?
    let limit: Int?

    func execute(on items: [UniversalItem]) -> QueryResultData {
        var results = items.filter { item in
            item.searchableContent.lowercased().contains(query.lowercased())
        }

        // Sort by preference
        if let rankBy = rankBy {
            switch rankBy.lowercased() {
            case "date":
                results.sort { $0.date > $1.date }
            case "amount":
                results.sort { $0.amount > $1.amount }
            case "relevance":
                // Simple relevance: exact matches first, then contains
                results.sort { a, b in
                    let aExact = a.searchableContent.lowercased().contains(query.lowercased())
                    let bExact = b.searchableContent.lowercased().contains(query.lowercased())
                    if aExact != bExact {
                        return aExact
                    }
                    return a.date > b.date
                }
            default:
                results.sort { $0.date > $1.date }
            }
        } else {
            results.sort { $0.date > $1.date }
        }

        // Apply limit
        if let limit = limit {
            results = Array(results.prefix(limit))
        }

        return QueryResultData(
            items: results,
            aggregations: [],
            comparisons: [],
            trends: []
        )
    }

    func description() -> String {
        var desc = "search for '\(query)'"
        if let rankBy = rankBy {
            desc += " ranked by \(rankBy)"
        }
        if let limit = limit {
            desc += " (limit: \(limit))"
        }
        return desc
    }
}

struct TrendAnalysisOperation: OperationProtocol {
    let metric: String
    let timeGranularity: String
    let direction: String?

    func execute(on items: [UniversalItem]) -> QueryResultData {
        let sortedItems = items.sorted { $0.date < $1.date }
        var timeSlices: [String: [UniversalItem]] = [:]

        for item in sortedItems {
            let timeKey = formatTimeKey(item.date, granularity: timeGranularity)
            if timeSlices[timeKey] == nil {
                timeSlices[timeKey] = []
            }
            timeSlices[timeKey]?.append(item)
        }

        let trendData = timeSlices.sorted { a, b in
            // Simple string sort (works for YYYY-MM-DD format)
            return a.key < b.key
        }.map { key, items -> (String, String) in
            let value: String
            switch metric.lowercased() {
            case "total", "spending":
                let total = items.reduce(0.0) { $0 + $1.amount }
                value = String(format: "$%.2f", total)
            case "count", "frequency":
                value = "\(items.count)"
            default:
                value = "\(items.count)"
            }
            return (key, value)
        }

        let trendResult = TrendResult(
            metric: metric,
            timeGranularity: timeGranularity,
            data: Dictionary(uniqueKeysWithValues: trendData)
        )

        return QueryResultData(
            items: items,
            aggregations: [],
            comparisons: [],
            trends: [trendResult]
        )
    }

    private func formatTimeKey(_ date: Date, granularity: String) -> String {
        let calendar = Calendar.current

        switch granularity.lowercased() {
        case "daily":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case "weekly":
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.year, from: date)
            return "Week \(weekOfYear), \(year)"
        case "monthly":
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case "yearly":
            let year = calendar.component(.year, from: date)
            return "\(year)"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }

    func description() -> String {
        "analyze \(metric) trend by \(timeGranularity)"
    }
}

// MARK: - Presentation Rules (HOW to show results)

struct PresentationRules: Codable {
    let format: ResponseFormat
    let includeIndividualItems: Bool
    let maxItemsToShow: Int
    let visualizations: [String]
    let summaryLevel: SummaryLevel

    enum ResponseFormat: String, Codable {
        case summary
        case table
        case list
        case timeline
        case trend
        case cards
        case mixed
    }

    enum SummaryLevel: String, Codable {
        case brief
        case detailed
        case comprehensive
    }

    static var `default`: PresentationRules {
        PresentationRules(
            format: .mixed,
            includeIndividualItems: true,
            maxItemsToShow: 5,
            visualizations: [],
            summaryLevel: .detailed
        )
    }
}

// MARK: - Result Structures

struct QueryResult {
    let intent: QueryIntent
    let data: QueryResultData
    let explanation: String
}

struct QueryResultData {
    let items: [UniversalItem]
    let aggregations: [AggregationResult]
    let comparisons: [ComparisonResult]
    let trends: [TrendResult]
}

struct AggregationResult {
    let label: String
    let value: String
    let groupKey: String?
}

struct ComparisonResult {
    let dimension: String
    let slices: [String: String]  // slice name -> computed value
}

struct TrendResult {
    let metric: String
    let timeGranularity: String
    let data: [String: String]  // time key -> value
}

// MARK: - Universal Item (Type-erased wrapper for all app data)

enum UniversalItem {
    case receipt(ReceiptStat)
    case email(Email)
    case event(Event)
    case note(Note)
    case location(Location)

    var date: Date {
        switch self {
        case .receipt(let receipt):
            return receipt.date
        case .email(let email):
            return email.timestamp
        case .event(let event):
            return event.eventDate
        case .note(let note):
            return note.dateModified
        case .location(let location):
            return location.dateCreated
        }
    }

    var category: String {
        switch self {
        case .receipt(let receipt):
            return receipt.category
        case .email(let email):
            return email.folder
        case .event(let event):
            return event.tags.first?.name ?? "General"
        case .note(let note):
            return note.folder
        case .location(let location):
            return location.category ?? "Place"
        }
    }

    var amount: Double {
        switch self {
        case .receipt(let receipt):
            return receipt.amount
        case .email:
            return 0.0
        case .event:
            return 0.0
        case .note:
            return 0.0
        case .location:
            return 0.0
        }
    }

    var status: String {
        switch self {
        case .receipt:
            return "completed"
        case .email(let email):
            return email.isRead ? "read" : "unread"
        case .event(let event):
            return event.isCompleted ? "completed" : "upcoming"
        case .note:
            return "active"
        case .location(let location):
            return location.isFavorited ? "favorited" : "saved"
        }
    }

    var merchant: String {
        switch self {
        case .receipt(let receipt):
            return receipt.title
        case .email(let email):
            return email.sender
        case .event(let event):
            return event.title
        case .note(let note):
            return note.title
        case .location(let location):
            return location.name
        }
    }

    var searchableContent: String {
        switch self {
        case .receipt(let receipt):
            return "\(receipt.title) \(receipt.category)"
        case .email(let email):
            return "\(email.subject) \(email.body) \(email.sender)"
        case .event(let event):
            return "\(event.title) \(event.notes)"
        case .note(let note):
            return "\(note.title) \(note.content)"
        case .location(let location):
            return "\(location.name) \(location.category ?? "")"
        }
    }
}
