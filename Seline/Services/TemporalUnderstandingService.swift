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
        let isEndExclusive: Bool

        init(startDate: Date, endDate: Date, description: String, isEndExclusive: Bool = false) {
            self.startDate = startDate
            self.endDate = endDate
            self.description = description
            self.isEndExclusive = isEndExclusive
        }
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

    func normalizedBounds(for range: DateRange, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: range.startDate)
        let end: Date
        if range.isEndExclusive {
            end = range.endDate
        } else {
            end = normalizedExclusiveEnd(for: range.endDate, startDate: start, calendar: calendar)
        }
        return (start, end)
    }

    /// Check if a date falls within a temporal expression from query
    /// Used for filtering search results by time
    func matchesTemporalExpression(_ date: Date, in query: String) -> Bool {
        guard let dateRange = extractTemporalRange(from: query) else {
            return true  // No temporal filter, include everything
        }

        let bounds = normalizedBounds(for: dateRange)
        return date >= bounds.start && date < bounds.end
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

        // Pattern: "weekend of Feb 7th" / "weekend around 2026-02-07"
        if let range = parseWeekendOfSpecificDatePattern(query, currentYear: currentYear, today: today) {
            return range
        }

        // Pattern: "specific date" (e.g., "December 25", "Feb 7th", "2026-02-07")
        if let range = parseSpecificDatePattern(query, currentYear: currentYear, today: today) {
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

        return nil
    }

    /// Parse relative date expressions like "yesterday", "last week", "last 3 months"
    private func parseRelativeDateExpressions(_ query: String) -> DateRange? {
        let calendar = Calendar.current
        let today = Date()

        // "day before yesterday"
        if query.contains("day before yesterday") {
            let todayStart = calendar.startOfDay(for: today)
            guard let start = calendar.date(byAdding: .day, value: -2, to: todayStart) else {
                return nil
            }
            let end = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return DateRange(
                startDate: start,
                endDate: end,
                description: "Day Before Yesterday",
                isEndExclusive: true
            )
        }

        // "yesterday"
        if query.contains("yesterday") {
            let todayStart = calendar.startOfDay(for: today)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            let yesterdayEnd = todayStart  // Yesterday ends when today begins
            return DateRange(
                startDate: yesterdayStart,
                endDate: yesterdayEnd,  // ✅ CORRECT: Full 24-hour day
                description: "Yesterday",
                isEndExclusive: true
            )
        }

        // "today"
        if query.contains("today") {
            let todayStart = calendar.startOfDay(for: today)
            guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
                return nil
            }
            return DateRange(
                startDate: todayStart,
                endDate: todayEnd,  // ✅ CORRECT: Full 24-hour day (midnight to midnight)
                description: "Today",
                isEndExclusive: true
            )
        }

        if let range = parseRelativeWeekendExpressions(query, calendar: calendar, today: today) {
            return range
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
        if containsStandaloneSeasonTerm(query, "summer") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: 8, day: 31))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Summer \(year)"
            )
        }

        // Fall/Autumn: September, October, November
        if containsStandaloneSeasonTerm(query, "fall") || containsStandaloneSeasonTerm(query, "autumn") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year, month: 11, day: 30))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Fall \(year)"
            )
        }

        // Winter: December, January, February
        if containsStandaloneSeasonTerm(query, "winter") {
            let startDate = calendar.date(from: DateComponents(year: year, month: 12, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: year + 1, month: 2, day: 28))!
            return DateRange(
                startDate: startDate,
                endDate: endDate,
                description: "Winter \(year)-\(year + 1)"
            )
        }

        // Spring: March, April, May
        if containsStandaloneSeasonTerm(query, "spring") {
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

    private func containsStandaloneSeasonTerm(_ query: String, _ term: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
        return query.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Helper Parsers

    private func parseQuarterPattern(_ query: String, currentYear: Int) -> DateRange? {
        let quarters = ["q1": 1, "q2": 2, "q3": 3, "q4": 4]

        for (quarterStr, quarterNum) in quarters {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: quarterStr) + "\\b"
            if query.range(of: pattern, options: .regularExpression) != nil {
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
        let monthPattern = #"\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b"#
        guard let regex = try? NSRegularExpression(pattern: monthPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(lowerQuery.startIndex..<lowerQuery.endIndex, in: lowerQuery)
        let matches = regex.matches(in: lowerQuery, range: nsRange)
        guard !matches.isEmpty else { return nil }

        var foundMonths: [Int] = []
        var seenMonths = Set<Int>()

        for match in matches {
            guard
                let matchRange = Range(match.range(at: 1), in: lowerQuery),
                let monthNum = monthNames[String(lowerQuery[matchRange])],
                !seenMonths.contains(monthNum)
            else {
                continue
            }

            seenMonths.insert(monthNum)
            foundMonths.append(monthNum)
        }

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

    private func parseSpecificDatePattern(_ query: String, currentYear: Int, today: Date) -> DateRange? {
        guard let detectedDate = detectSpecificDate(in: query, currentYear: currentYear, today: today) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .long

        return DateRange(
            startDate: detectedDate,
            endDate: detectedDate,
            description: formatter.string(from: detectedDate)
        )
    }

    private func parseWeekendOfSpecificDatePattern(_ query: String, currentYear: Int, today: Date) -> DateRange? {
        let normalizedQuery = query.lowercased()
        guard normalizedQuery.contains("weekend") else { return nil }
        guard let detectedDate = detectSpecificDate(in: query, currentYear: currentYear, today: today) else {
            return nil
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: detectedDate)
        let weekday = calendar.component(.weekday, from: dayStart) // 1 = Sunday, 7 = Saturday

        let saturday: Date
        switch weekday {
        case 7:
            saturday = dayStart
        case 1:
            saturday = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        default:
            let daysBackToSaturday = (weekday + 1) % 7
            saturday = calendar.date(byAdding: .day, value: -daysBackToSaturday, to: dayStart) ?? dayStart
        }

        return weekendRange(starting: saturday, description: "Weekend Of \(formattedMonthDay(detectedDate))", calendar: calendar)
    }

    private func parseRelativeWeekendExpressions(_ query: String, calendar: Calendar, today: Date) -> DateRange? {
        guard query.contains("weekend") else { return nil }

        let todayStart = calendar.startOfDay(for: today)
        guard let mostRecentSaturday = mostRecentSaturday(onOrBefore: todayStart, calendar: calendar) else {
            return nil
        }

        let weekday = calendar.component(.weekday, from: todayStart) // 1 = Sunday, 7 = Saturday
        let isActiveWeekend = weekday == 1 || weekday == 7

        if query.contains("last last weekend") || query.contains("weekend before that") {
            guard let lastWeekendStart = resolvedLastWeekendStart(
                from: mostRecentSaturday,
                isActiveWeekend: isActiveWeekend,
                calendar: calendar
            ),
            let priorWeekendStart = calendar.date(byAdding: .day, value: -7, to: lastWeekendStart) else {
                return nil
            }

            return weekendRange(starting: priorWeekendStart, description: "Weekend Before That", calendar: calendar)
        }

        if query.contains("last weekend") || query.contains("previous weekend") {
            guard let lastWeekendStart = resolvedLastWeekendStart(
                from: mostRecentSaturday,
                isActiveWeekend: isActiveWeekend,
                calendar: calendar
            ) else {
                return nil
            }

            return weekendRange(starting: lastWeekendStart, description: "Last Weekend", calendar: calendar)
        }

        if query.contains("this weekend") {
            let start: Date
            if isActiveWeekend {
                start = mostRecentSaturday
            } else {
                let daysUntilSaturday = (7 - weekday + 7) % 7
                guard let upcomingSaturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: todayStart) else {
                    return nil
                }
                start = upcomingSaturday
            }

            return weekendRange(starting: start, description: "This Weekend", calendar: calendar)
        }

        if query.contains("next weekend") {
            let baseSaturday: Date
            if isActiveWeekend {
                baseSaturday = mostRecentSaturday
            } else {
                let daysUntilSaturday = (7 - weekday + 7) % 7
                guard let upcomingSaturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: todayStart) else {
                    return nil
                }
                baseSaturday = upcomingSaturday
            }

            guard let nextWeekendStart = calendar.date(byAdding: .day, value: 7, to: baseSaturday) else {
                return nil
            }
            return weekendRange(starting: nextWeekendStart, description: "Next Weekend", calendar: calendar)
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

    private func normalizedExclusiveEnd(for endDate: Date, startDate: Date, calendar: Calendar) -> Date {
        if endDate <= startDate {
            return calendar.date(byAdding: .day, value: 1, to: startDate) ?? endDate
        }

        let startOfEndDay = calendar.startOfDay(for: endDate)
        let isMidnightBoundary = abs(endDate.timeIntervalSince(startOfEndDay)) < 1
        if isMidnightBoundary {
            return calendar.date(byAdding: .day, value: 1, to: startOfEndDay) ?? endDate
        }

        return endDate
    }

    private func weekendRange(starting saturday: Date, description: String, calendar: Calendar) -> DateRange? {
        let start = calendar.startOfDay(for: saturday)
        guard let sundayStart = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }

        return DateRange(
            startDate: start,
            endDate: sundayStart,
            description: description
        )
    }

    private func resolvedLastWeekendStart(from mostRecentSaturday: Date, isActiveWeekend: Bool, calendar: Calendar) -> Date? {
        if isActiveWeekend {
            return calendar.date(byAdding: .day, value: -7, to: mostRecentSaturday)
        }
        return mostRecentSaturday
    }

    private func mostRecentSaturday(onOrBefore date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday, 7 = Saturday
        let daysBackToSaturday = weekday == 7 ? 0 : (weekday == 1 ? 1 : weekday)
        guard let saturday = calendar.date(byAdding: .day, value: -daysBackToSaturday, to: day) else {
            return nil
        }
        return calendar.startOfDay(for: saturday)
    }

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

    private func detectSpecificDate(in query: String, currentYear: Int, today: Date) -> Date? {
        let sanitized = sanitizeOrdinalDates(query.lowercased())

        if let detected = detectISODate(in: sanitized) {
            return detected
        }

        if let detected = detectNumericDate(in: sanitized, currentYear: currentYear, today: today) {
            return detected
        }

        if let detected = detectMonthNameDate(in: sanitized, currentYear: currentYear, today: today) {
            return detected
        }

        if let detected = detectDayMonthDate(in: sanitized, currentYear: currentYear, today: today) {
            return detected
        }

        return nil
    }

    private func sanitizeOrdinalDates(_ query: String) -> String {
        query.replacingOccurrences(
            of: #"(\d{1,2})(st|nd|rd|th)\b"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private func detectISODate(in query: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#) else {
            return nil
        }
        let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: nsRange),
              let yearRange = Range(match.range(at: 1), in: query),
              let monthRange = Range(match.range(at: 2), in: query),
              let dayRange = Range(match.range(at: 3), in: query),
              let year = Int(query[yearRange]),
              let month = Int(query[monthRange]),
              let day = Int(query[dayRange]) else {
            return nil
        }

        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func detectNumericDate(in query: String, currentYear: Int, today: Date) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b"#) else {
            return nil
        }

        let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: nsRange),
              let monthRange = Range(match.range(at: 1), in: query),
              let dayRange = Range(match.range(at: 2), in: query),
              let month = Int(query[monthRange]),
              let day = Int(query[dayRange]) else {
            return nil
        }

        let explicitYear: Int? = {
            guard match.numberOfRanges > 3,
                  let yearRange = Range(match.range(at: 3), in: query),
                  !yearRange.isEmpty else {
                return nil
            }
            let raw = Int(query[yearRange]) ?? currentYear
            if raw < 100 {
                return raw >= 70 ? 1900 + raw : 2000 + raw
            }
            return raw
        }()

        let year = inferredYear(
            explicitYear: explicitYear,
            month: month,
            day: day,
            currentYear: currentYear,
            today: today,
            query: query
        )
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func detectMonthNameDate(in query: String, currentYear: Int, today: Date) -> Date? {
        let monthNames = monthNameLookup
        let pattern = #"\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\s+(\d{1,2})(?:\s*,?\s*(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: nsRange),
              let monthRange = Range(match.range(at: 1), in: query),
              let dayRange = Range(match.range(at: 2), in: query),
              let month = monthNames[String(query[monthRange]).lowercased()],
              let day = Int(query[dayRange]) else {
            return nil
        }

        let explicitYear = match.numberOfRanges > 3
            ? Range(match.range(at: 3), in: query).flatMap { Int(query[$0]) }
            : nil
        let year = inferredYear(
            explicitYear: explicitYear,
            month: month,
            day: day,
            currentYear: currentYear,
            today: today,
            query: query
        )
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func detectDayMonthDate(in query: String, currentYear: Int, today: Date) -> Date? {
        let monthNames = monthNameLookup
        let pattern = #"\b(\d{1,2})\s+(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)(?:\s*,?\s*(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: nsRange),
              let dayRange = Range(match.range(at: 1), in: query),
              let monthRange = Range(match.range(at: 2), in: query),
              let day = Int(query[dayRange]),
              let month = monthNames[String(query[monthRange]).lowercased()] else {
            return nil
        }

        let explicitYear = match.numberOfRanges > 3
            ? Range(match.range(at: 3), in: query).flatMap { Int(query[$0]) }
            : nil
        let year = inferredYear(
            explicitYear: explicitYear,
            month: month,
            day: day,
            currentYear: currentYear,
            today: today,
            query: query
        )
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private var monthNameLookup: [String: Int] {
        [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sept": 9, "sep": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12
        ]
    }

    private func inferredYear(
        explicitYear: Int?,
        month: Int,
        day: Int,
        currentYear: Int,
        today: Date,
        query: String
    ) -> Int {
        if let explicitYear {
            return explicitYear
        }

        let calendar = Calendar.current
        let normalizedQuery = query.lowercased()
        let todayStart = calendar.startOfDay(for: today)

        guard let candidate = calendar.date(from: DateComponents(year: currentYear, month: month, day: day)) else {
            return currentYear
        }

        let likelyPastReference = normalizedQuery.contains("last")
            || normalizedQuery.contains("previous")
            || normalizedQuery.contains("ago")
            || normalizedQuery.contains("that weekend")

        if likelyPastReference,
           candidate > calendar.date(byAdding: .day, value: 30, to: todayStart) ?? todayStart {
            return currentYear - 1
        }

        return currentYear
    }

    private func formattedMonthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
