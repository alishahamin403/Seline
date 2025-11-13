import Foundation

/// Filters app data by temporal range BEFORE sending to LLM
/// This ensures the LLM only sees relevant data for the requested time period
class TemporalDataFilterService {
    static let shared = TemporalDataFilterService()

    // MARK: - Main Filtering API

    /// Extract temporal range from user query and return filter bounds
    func extractTemporalBoundsFromQuery(_ query: String) -> DateBounds {
        let parser = AdvancedQueryParser.shared

        // Try advanced parser first
        if let temporalParams = parser.parseTemporalQuery(query) {
            if let dateRange = temporalParams.dateRange {
                return DateBounds(
                    start: dateRange.start,
                    end: dateRange.end,
                    periodDescription: describePeriod(dateRange.period)
                )
            }
        }

        // Fallback: check for common temporal phrases
        return extractCommonTemporalPatterns(query)
    }

    /// Filter events to only include those in the temporal range
    func filterEventsByDate(
        _ events: [EventMetadata],
        startDate: Date,
        endDate: Date
    ) -> [EventMetadata] {
        return events.filter { event in
            // Check targetDate
            if let targetDate = event.date {
                if targetDate >= startDate && targetDate <= endDate {
                    return true
                }
            }

            // Check completedDates (critical for counting completed gym sessions)
            if let completedDates = event.completedDates {
                for completedDate in completedDates {
                    if completedDate >= startDate && completedDate <= endDate {
                        return true
                    }
                }
            }

            // Check scheduledTime (for events without targetDate)
            if let scheduledTime = event.time {
                if scheduledTime >= startDate && scheduledTime <= endDate {
                    return true
                }
            }

            return false
        }
    }

    /// Filter receipts to only include those in the temporal range
    func filterReceiptsByDate(
        _ receipts: [ReceiptMetadata],
        startDate: Date,
        endDate: Date
    ) -> [ReceiptMetadata] {
        return receipts.filter { receipt in
            receipt.date >= startDate && receipt.date <= endDate
        }
    }

    /// Filter notes to only include those modified in the temporal range
    func filterNotesByDate(
        _ notes: [NoteMetadata],
        startDate: Date,
        endDate: Date
    ) -> [NoteMetadata] {
        return notes.filter { note in
            note.dateModified >= startDate && note.dateModified <= endDate
        }
    }

    /// Filter emails to only include those received in the temporal range
    func filterEmailsByDate(
        _ emails: [EmailMetadata],
        startDate: Date,
        endDate: Date
    ) -> [EmailMetadata] {
        return emails.filter { email in
            email.date >= startDate && email.date <= endDate
        }
    }

    // MARK: - Helper Methods

    private func describePeriod(_ period: DateRange.TimePeriod) -> String {
        switch period {
        case .today:
            return "today"
        case .tomorrow:
            return "tomorrow"
        case .thisWeek:
            return "this week"
        case .nextWeek:
            return "next week"
        case .thisMonth:
            return "this month"
        case .lastMonth:
            return "last month"
        case .thisYear:
            return "this year"
        case .custom:
            return "custom period"
        }
    }

    private func extractCommonTemporalPatterns(_ query: String) -> DateBounds {
        let lower = query.lowercased()
        let now = Date()
        let calendar = Calendar.current

        // Check for explicit patterns
        if lower.contains("today") {
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
            return DateBounds(start: start, end: end, periodDescription: "today")
        }

        if lower.contains("this week") {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = calendar.date(byAdding: DateComponents(day: 6), to: weekStart)!
            return DateBounds(start: weekStart, end: weekEnd, periodDescription: "this week")
        }

        if lower.contains("last week") {
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekEnd = calendar.date(byAdding: DateComponents(day: -1), to: thisWeekStart)!
            let lastWeekStart = calendar.date(byAdding: DateComponents(day: -6), to: lastWeekEnd)!
            return DateBounds(start: lastWeekStart, end: lastWeekEnd, periodDescription: "last week")
        }

        if lower.contains("this month") {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            return DateBounds(start: monthStart, end: monthEnd, periodDescription: "this month")
        }

        if lower.contains("last month") {
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let lastMonthEnd = calendar.date(byAdding: DateComponents(day: -1), to: currentMonthStart)!
            let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthEnd))!
            return DateBounds(start: lastMonthStart, end: lastMonthEnd, periodDescription: "last month")
        }

        if lower.contains("this year") {
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart)!
            return DateBounds(start: yearStart, end: yearEnd, periodDescription: "this year")
        }

        // Default: no bounds (return all data)
        return DateBounds(
            start: calendar.date(byAdding: DateComponents(year: -10), to: now)!,
            end: now,
            periodDescription: "all time"
        )
    }
}

// MARK: - Data Structures

struct DateBounds {
    let start: Date
    let end: Date
    let periodDescription: String
}
