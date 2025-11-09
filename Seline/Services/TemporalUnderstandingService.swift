import Foundation

/// Service for understanding temporal expressions like "last month", "Q4 2024", etc.
class TemporalUnderstandingService {
    static let shared = TemporalUnderstandingService()

    private init() {}

    // MARK: - Temporal Range Models

    struct DateRange {
        let startDate: Date
        let endDate: Date
        let description: String  // e.g., "Last Month (September)"
    }

    // MARK: - Public API

    /// Extract temporal expressions from a query and return date range if found
    /// Example: "expenses from last month" → returns DateRange for September
    func extractTemporalRange(from query: String) -> DateRange? {
        let lowerQuery = query.lowercased()

        // Try specific date patterns first (more precise)
        if let range = parseSpecificDatePatterns(lowerQuery) {
            return range
        }

        // Try relative date expressions
        if let range = parseRelativeDateExpressions(lowerQuery) {
            return range
        }

        // Try seasonal expressions
        if let range = parseSeasonalExpressions(lowerQuery) {
            return range
        }

        return nil
    }

    /// Check if a date falls within a temporal expression from query
    /// Used for filtering search results by time
    func matchesTemporalExpression(_ date: Date, in query: String) -> Bool {
        guard let dateRange = extractTemporalRange(from: query) else {
            return true  // No temporal filter, include everything
        }

        return date >= dateRange.startDate && date <= dateRange.endDate
    }

    // MARK: - Pattern Parsing

    /// Parse specific date patterns like "2024", "January 2024", "12/25/2024"
    private func parseSpecificDatePatterns(_ query: String) -> DateRange? {
        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)

        // Pattern: "Q1/Q2/Q3/Q4 [year]"
        if let range = parseQuarterPattern(query, currentYear: currentYear) {
            return range
        }

        // Pattern: "month year" (e.g., "January 2024", "Dec 2023")
        if let range = parseMonthYearPattern(query, currentYear: currentYear) {
            return range
        }

        // Pattern: "year" (e.g., "2024", "2023")
        if let range = parseYearPattern(query, currentYear: currentYear) {
            return range
        }

        // Pattern: "specific date" (e.g., "December 25", "12/25")
        if let range = parseSpecificDatePattern(query) {
            return range
        }

        return nil
    }

    /// Parse relative date expressions like "yesterday", "last week", "last 3 months"
    private func parseRelativeDateExpressions(_ query: String) -> DateRange? {
        let calendar = Calendar.current
        let today = Date()

        // "yesterday"
        if query.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            return DateRange(
                startDate: yesterday,
                endDate: yesterday,
                description: "Yesterday"
            )
        }

        // "today"
        if query.contains("today") {
            return DateRange(
                startDate: today,
                endDate: today,
                description: "Today"
            )
        }

        // "last X [days/weeks/months]" (e.g., "last 3 months", "last week")
        if let range = parseLastNUnitsPattern(query, calendar: calendar, today: today) {
            return range
        }

        // "past X [days/weeks/months]"
        if let range = parsePastNUnitsPattern(query, calendar: calendar, today: today) {
            return range
        }

        // "last month/week/year"
        if let range = parseLastUnitPattern(query, calendar: calendar, today: today) {
            return range
        }

        // "this month/week/year"
        if let range = parseThisUnitPattern(query, calendar: calendar, today: today) {
            return range
        }

        // "next month/week/year"
        if let range = parseNextUnitPattern(query, calendar: calendar, today: today) {
            return range
        }

        return nil
    }

    /// Parse seasonal expressions like "summer 2024", "fall", "spring"
    private func parseSeasonalExpressions(_ query: String) -> DateRange? {
        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)

        // Extract year from query if present
        let year = extractYear(from: query) ?? currentYear

        // Summer: June, July, August
        if query.contains("summer") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: 8, day: 31))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Summer \(year)"
            )
        }

        // Fall/Autumn: September, October, November
        if query.contains("fall") || query.contains("autumn") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: 11, day: 30))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Fall \(year)"
            )
        }

        // Winter: December, January, February
        if query.contains("winter") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 12, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year + 1, month: 2, day: 28))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Winter \(year)-\(year + 1)"
            )
        }

        // Spring: March, April, May
        if query.contains("spring") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 3, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: 5, day: 31))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Spring \(year)"
            )
        }

        return nil
    }

    // MARK: - Helper Parsers

    private func parseQuarterPattern(_ query: String, currentYear: Int) -> DateRange? {
        let quarters = ["q1": 1, "q2": 2, "q3": 3, "q4": 4]

        for (quarterStr, quarterNum) in quarters {
            if query.contains(quarterStr) {
                let year = extractYear(from: query) ?? currentYear
                let monthStart = (quarterNum - 1) * 3 + 1
                let monthEnd = quarterNum * 3

                let calendar = Calendar.current
                let startDate = calendar.date(from: DateComponents(year: year, month: monthStart, day: 1))!
                let endDate = calendar.date(from: DateComponents(year: year, month: monthEnd, day: daysInMonth(monthEnd, year: year)))!

                return DateRange(
                    startDate: startDate,
                    endDate: endDate,
                    description: "Q\(quarterNum) \(year)"
                )
            }
        }

        return nil
    }

    private func parseMonthYearPattern(_ query: String, currentYear: Int) -> DateRange? {
        let monthNames = [
            "january": 1, "february": 2, "march": 3, "april": 4,
            "may": 5, "june": 6, "july": 7, "august": 8,
            "september": 9, "october": 10, "november": 11, "december": 12,
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7,
            "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
        ]

        let lowerQuery = query.lowercased()
        var foundMonths: [Int] = []

        // Find ALL months mentioned in the query (handles "oct and nov", "nov and oct", etc)
        for (monthName, monthNum) in monthNames {
            if lowerQuery.contains(monthName) {
                foundMonths.append(monthNum)
            }
        }

        guard !foundMonths.isEmpty else { return nil }

        let year = extractYear(from: query) ?? currentYear
        let calendar = Calendar.current

        // If multiple months found, span from earliest to latest
        if foundMonths.count > 1 {
            let minMonth = foundMonths.min() ?? 1
            let maxMonth = foundMonths.max() ?? 12

            let startDate = calendar.date(from: DateComponents(year: year, month: minMonth, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: maxMonth, day: daysInMonth(maxMonth, year: year)))!

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM"

            let startMonthStr = monthFormatter.string(from: startDate)
            let endMonthStr = monthFormatter.string(from: endDate)

            let description = minMonth == maxMonth ? "\(startMonthStr) \(year)" : "\(startMonthStr)-\(endMonthStr) \(year)"

            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: description
            )
        }

        // Single month case
        let monthNum = foundMonths[0]
        let startDate = calendar.date(from: DateComponents(year: year, month: monthNum, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: year, month: monthNum, day: daysInMonth(monthNum, year: year)))!

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let monthStr = formatter.string(from: startDate)

        return DateRange(
            startDate: startDate,
            endDate: endDate,
            description: "\(monthStr) \(year)"
        )
    }

    private func parseYearPattern(_ query: String, currentYear: Int) -> DateRange? {
        // Extract 4-digit year
        let pattern = "\\b(20\\d{2}|19\\d{2})\\b"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = query as NSString
            if let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: nsString.length)) {
                if let range = Range(match.range, in: query) {
                    if let year = Int(String(query[range])) {
                        let calendar = Calendar.current
                        let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
                        let endDate = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!

                        return DateRange(
                            startDate: startDate,
                            endDate: endDate,
                            description: "Year \(year)"
                        )
                    }
                }
            }
        }

        return nil
    }

    private func parseSpecificDatePattern(_ query: String) -> DateRange? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"

        // Try multiple date formats
        let formats = ["MM/dd/yyyy", "MM/dd/yy", "MM-dd-yyyy", "yyyy-MM-dd"]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: query) {
                return DateRange(
                    startDate: date,
                    endDate: date,
                    description: formatter.string(from: date)
                )
            }
        }

        return nil
    }

    private func parseLastNUnitsPattern(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        let pattern = "last\\s+(\\d+)\\s+(days?|weeks?|months?|years?)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsString = query as NSString
            if let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: nsString.length)) {
                if match.numberOfRanges >= 3,
                   let numberRange = Range(match.range(at: 1), in: query),
                   let unitRange = Range(match.range(at: 2), in: query),
                   let number = Int(String(query[numberRange])) {
                    let unitStr = String(query[unitRange]).lowercased()

                    var component: Calendar.Component = .day
                    if unitStr.contains("week") { component = .weekOfYear }
                    else if unitStr.contains("month") { component = .month }
                    else if unitStr.contains("year") { component = .year }

                    let startDate = calendar.date(byAdding: component, value: -number, to: today)!
                    return DateRange(
                        startDate: startDate,
                        endDate: today,
                        description: "Last \(number) \(unitStr)"
                    )
                }
            }
        }

        return nil
    }

    private func parsePastNUnitsPattern(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        let pattern = "past\\s+(\\d+)\\s+(days?|weeks?|months?|years?)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsString = query as NSString
            if let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: nsString.length)) {
                if match.numberOfRanges >= 3,
                   let numberRange = Range(match.range(at: 1), in: query),
                   let unitRange = Range(match.range(at: 2), in: query),
                   let number = Int(String(query[numberRange])) {
                    let unitStr = String(query[unitRange]).lowercased()

                    var component: Calendar.Component = .day
                    if unitStr.contains("week") { component = .weekOfYear }
                    else if unitStr.contains("month") { component = .month }
                    else if unitStr.contains("year") { component = .year }

                    let startDate = calendar.date(byAdding: component, value: -number, to: today)!
                    return DateRange(
                        startDate: startDate,
                        endDate: today,
                        description: "Past \(number) \(unitStr)"
                    )
                }
            }
        }

        return nil
    }

    private func parseLastUnitPattern(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        // "last month"
        if query.contains("last month") {
            let startDate = calendar.date(byAdding: .month, value: -1, to: today)!
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
            let endOfMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: startOfMonth)!)!
            return DateRange(
                startDate: startOfMonth,
                endDate: endOfMonth,
                description: "Last Month"
            )
        }

        // "last week"
        if query.contains("last week") {
            let startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: today)!
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
            let startOfWeek = calendar.date(from: components)!
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
            return DateRange(
                startDate: startOfWeek,
                endDate: endOfWeek,
                description: "Last Week"
            )
        }

        // "last year"
        if query.contains("last year") {
            let startDate = calendar.date(byAdding: .year, value: -1, to: today)!
            let startOfYear = calendar.date(from: DateComponents(year: calendar.component(.year, from: startDate), month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: calendar.component(.year, from: startDate), month: 12, day: 31))!
            return DateRange(
                startDate: startOfYear,
                endDate: endOfYear,
                description: "Last Year"
            )
        }

        return nil
    }

    private func parseThisUnitPattern(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        // "this month"
        if query.contains("this month") {
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            let endOfMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: startOfMonth)!)!
            return DateRange(
                startDate: startOfMonth,
                endDate: endOfMonth,
                description: "This Month"
            )
        }

        // "this week"
        if query.contains("this week") {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            let startOfWeek = calendar.date(from: components)!
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
            return DateRange(
                startDate: startOfWeek,
                endDate: endOfWeek,
                description: "This Week"
            )
        }

        // "this year"
        if query.contains("this year") {
            let currentYear = calendar.component(.year, from: today)
            let startOfYear = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31))!
            return DateRange(
                startDate: startOfYear,
                endDate: endOfYear,
                description: "This Year"
            )
        }

        return nil
    }

    private func parseNextUnitPattern(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        // "next month"
        if query.contains("next month") {
            let startDate = calendar.date(byAdding: .month, value: 1, to: today)!
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
            let endOfMonth = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: startOfMonth)!)!
            return DateRange(
                startDate: startOfMonth,
                endDate: endOfMonth,
                description: "Next Month"
            )
        }

        // "next week"
        if query.contains("next week") {
            let startDate = calendar.date(byAdding: .weekOfYear, value: 1, to: today)!
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
            let startOfWeek = calendar.date(from: components)!
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
            return DateRange(
                startDate: startOfWeek,
                endDate: endOfWeek,
                description: "Next Week"
            )
        }

        return nil
    }

    // MARK: - Utility Helpers

    private func extractYear(from query: String) -> Int? {
        let pattern = "\\b(20\\d{2}|19\\d{2})\\b"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = query as NSString
            if let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: nsString.length)) {
                if let range = Range(match.range, in: query) {
                    return Int(String(query[range]))
                }
            }
        }
        return nil
    }

    private func daysInMonth(_ month: Int, year: Int) -> Int {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let range = calendar.range(of: .day, in: .month, for: date)!
        return range.count
    }
}
