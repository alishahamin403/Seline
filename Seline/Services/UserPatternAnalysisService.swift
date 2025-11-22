import Foundation

/// Analyzes user metadata to extract behavior patterns for predictive intelligence
class UserPatternAnalysisService {

    /// Analyze metadata and extract user behavior patterns
    @MainActor
    static func analyzeUserPatterns(
        from metadata: AppDataMetadata
    ) -> UserPatterns {
        let calendar = Calendar.current
        let now = Date()

        // Analyze spending patterns
        let categorySpending = analyzeSpendingByCategory(metadata.receipts)
        let monthlyAvg = calculateAverageMonthlySpending(metadata.receipts)
        let spendingTrend = calculateSpendingTrend(metadata.receipts)
        let avgAmount = metadata.receipts.isEmpty ? 0 : metadata.receipts.reduce(0) { $0 + $1.amount } / Double(metadata.receipts.count)

        // Analyze event patterns
        let eventFrequencies = analyzeEventFrequencies(metadata.events)
        let eventsPerWeek = calculateEventsPerWeek(metadata.events)
        let favoriteEventTypes = extractFavoriteEventTypes(metadata.events)

        // Analyze location patterns
        let mostVisited = analyzeMostVisitedLocations(metadata.locations)
        let cuisinePreferences = extractCuisinePreferences(metadata.locations)

        // Analyze time patterns
        let activeTimeOfDay = analyzeActiveTimeOfDay(metadata.events)
        let busyDays = analyzeBusyDays(metadata.events)

        return UserPatterns(
            topExpenseCategories: categorySpending,
            averageMonthlySpending: monthlyAvg,
            spendingTrend: spendingTrend,
            mostFrequentEvents: eventFrequencies,
            averageEventsPerWeek: eventsPerWeek,
            favoriteEventTypes: favoriteEventTypes,
            mostVisitedLocations: mostVisited,
            favoriteRestaurantTypes: cuisinePreferences,
            mostActiveTimeOfDay: activeTimeOfDay,
            busyDays: busyDays,
            averageExpenseAmount: avgAmount,
            totalTransactions: metadata.receipts.count,
            dataPoints: metadata.receipts.count + metadata.events.count + metadata.locations.count
        )
    }

    // MARK: - Spending Analysis

    private static func analyzeSpendingByCategory(_ receipts: [ReceiptMetadata]) -> [CategorySpending] {
        guard !receipts.isEmpty else { return [] }

        var categoryTotals: [String: (amount: Double, count: Int)] = [:]

        for receipt in receipts {
            let category = receipt.category ?? "uncategorized"
            if categoryTotals[category] == nil {
                categoryTotals[category] = (0, 0)
            }
            categoryTotals[category]!.amount += receipt.amount
            categoryTotals[category]!.count += 1
        }

        let totalSpent = receipts.reduce(0) { $0 + $1.amount }

        return categoryTotals
            .map { category, data in
                CategorySpending(
                    category: category,
                    totalAmount: data.amount,
                    percentage: totalSpent > 0 ? (data.amount / totalSpent) * 100 : 0,
                    transactionCount: data.count
                )
            }
            .sorted { $0.totalAmount > $1.totalAmount }
            .prefix(5)  // Top 5 categories
            .map { $0 }
    }

    private static func calculateAverageMonthlySpending(_ receipts: [ReceiptMetadata]) -> Double {
        guard !receipts.isEmpty else { return 0 }

        var monthlyTotals: [String: Double] = [:]

        for receipt in receipts {
            let monthKey = receipt.monthYear ?? "Unknown"
            monthlyTotals[monthKey, default: 0] += receipt.amount
        }

        guard !monthlyTotals.isEmpty else { return 0 }
        return monthlyTotals.values.reduce(0, +) / Double(monthlyTotals.count)
    }

    private static func calculateSpendingTrend(_ receipts: [ReceiptMetadata]) -> String {
        guard receipts.count >= 2 else { return "stable" }

        // Group by month
        var monthlyTotals: [(month: String, amount: Double)] = []
        var monthlyMap: [String: Double] = [:]

        for receipt in receipts {
            let monthKey = receipt.monthYear ?? "Unknown"
            monthlyMap[monthKey, default: 0] += receipt.amount
        }

        // Sort by month and calculate trend
        let sortedMonths = monthlyMap.keys.sorted()
        guard sortedMonths.count >= 2 else { return "stable" }

        let firstMonthSpending = monthlyMap[sortedMonths.first!] ?? 0
        let lastMonthSpending = monthlyMap[sortedMonths.last!] ?? 0

        let percentChange = (lastMonthSpending - firstMonthSpending) / firstMonthSpending * 100

        if percentChange > 10 {
            return "increasing"
        } else if percentChange < -10 {
            return "decreasing"
        } else {
            return "stable"
        }
    }

    // MARK: - Event Analysis

    private static func analyzeEventFrequencies(_ events: [EventMetadata]) -> [EventFrequency] {
        guard !events.isEmpty else { return [] }

        var eventCounts: [String: (type: String?, completions: [Date])] = [:]

        for event in events {
            if eventCounts[event.title] == nil {
                eventCounts[event.title] = (event.eventType, [])
            }
            if let completedDates = event.completedDates {
                eventCounts[event.title]!.completions.append(contentsOf: completedDates)
            }
        }

        // Calculate frequency
        let now = Date()
        let monthsOfData = 3.0  // Assume we have ~3 months of data

        return eventCounts
            .map { title, data in
                let timesPerMonth = Double(data.completions.count) / monthsOfData
                return EventFrequency(
                    title: title,
                    timesPerMonth: timesPerMonth,
                    eventType: data.type,
                    averageDaysApart: calculateAverageDaysApart(data.completions)
                )
            }
            .filter { $0.timesPerMonth >= 1 }  // Only events that happen at least monthly
            .sorted { $0.timesPerMonth > $1.timesPerMonth }
            .prefix(5)  // Top 5 events
            .map { $0 }
    }

    private static func calculateAverageDaysApart(_ dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }

        let sorted = dates.sorted()
        var daysDifferences: [Double] = []

        for i in 1..<sorted.count {
            let daysDiff = sorted[i].timeIntervalSince(sorted[i - 1]) / 86400  // seconds to days
            daysDifferences.append(daysDiff)
        }

        guard !daysDifferences.isEmpty else { return nil }
        return daysDifferences.reduce(0, +) / Double(daysDifferences.count)
    }

    private static func calculateEventsPerWeek(_ events: [EventMetadata]) -> Double {
        guard !events.isEmpty else { return 0 }

        let totalCompletions = events.compactMap { $0.completedDates?.count ?? 0 }.reduce(0, +)
        let monthsOfData = 3.0
        let weeksOfData = monthsOfData * 4.33

        return Double(totalCompletions) / weeksOfData
    }

    private static func extractFavoriteEventTypes(_ events: [EventMetadata]) -> [String] {
        var typeCounts: [String: Int] = [:]

        for event in events {
            if let type = event.eventType {
                typeCounts[type, default: 0] += 1
            }
        }

        return typeCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    // MARK: - Location Analysis

    private static func analyzeMostVisitedLocations(_ locations: [LocationMetadata]) -> [LocationVisit] {
        return locations
            .filter { $0.visitCount ?? 0 > 0 }
            .map { location in
                LocationVisit(
                    name: location.displayName,
                    visitCount: location.visitCount ?? 0,
                    category: location.folderName ?? "Uncategorized",
                    lastVisited: location.lastVisited
                )
            }
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(5)
            .map { $0 }
    }

    private static func extractCuisinePreferences(_ locations: [LocationMetadata]) -> [String] {
        var cuisineCounts: [String: Int] = [:]

        for location in locations {
            if let cuisine = location.cuisine {
                cuisineCounts[cuisine, default: 0] += 1
            }
        }

        return cuisineCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    // MARK: - Time Pattern Analysis

    private static func analyzeActiveTimeOfDay(_ events: [EventMetadata]) -> String {
        guard !events.isEmpty else { return "unknown" }

        let calendar = Calendar.current
        var timeCounts = ["morning": 0, "afternoon": 0, "evening": 0]

        for event in events {
            guard let time = event.time else { continue }
            let hour = calendar.component(.hour, from: time)

            if hour >= 5 && hour < 12 {
                timeCounts["morning"]! += 1
            } else if hour >= 12 && hour < 17 {
                timeCounts["afternoon"]! += 1
            } else {
                timeCounts["evening"]! += 1
            }
        }

        return timeCounts.max(by: { $0.value < $1.value })?.key ?? "unknown"
    }

    private static func analyzeBusyDays(_ events: [EventMetadata]) -> [String] {
        guard !events.isEmpty else { return [] }

        let calendar = Calendar.current
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var dayCounts = [Int: Int]()  // weekday: count

        for event in events {
            guard let date = event.date else { continue }
            let weekday = calendar.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }

        return dayCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .compactMap { weekday, _ in
                let index = weekday - 1
                return index >= 0 && index < dayNames.count ? dayNames[index] : nil
            }
    }
}
