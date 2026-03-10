import Foundation

/// Shared temporal range model used by query parsing and temporal filtering.
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
