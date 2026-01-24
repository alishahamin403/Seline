import Foundation

/// Service for generating deep spending insights from receipt data
@MainActor
class SpendingInsightsService: ObservableObject {
    static let shared = SpendingInsightsService()

    // MARK: - Insight Types

    enum InsightType: String, CaseIterable {
        case merchantStreak       // "You've bought at Starbucks 6 months in a row"
        case categoryComparison   // "Coffee spending up 25% vs last month"
        case topMerchantChange    // "Your top restaurant changed from X to Y"
        case spendingPace         // "On pace to spend $X this month"
        case newMerchant          // "First time at [merchant] this month"
        case frequentVisit        // "You visited Chipotle 12 times this month"
        case biggestIncrease      // "Biggest increase: Uber Eats (+$150)"
        case biggestDecrease      // "Biggest savings: Starbucks (-$45)"
        case loyaltyAlert         // "You're a regular at X - visited 3+ months"
        case monthComparison      // "Lowest spending month in 6 months"
    }

    struct SpendingInsight: Identifiable {
        let id = UUID()
        let type: InsightType
        let title: String
        let subtitle: String
        let icon: String
        let accentColor: InsightColor
        let value: String?
        let trend: TrendDirection?

        // Detail data for drill-down
        let merchantName: String?
        let detailReceipts: [ReceiptStat]?
        let monthlyBreakdown: [(month: String, amount: Double, count: Int)]?

        var hasDetails: Bool {
            return detailReceipts != nil || monthlyBreakdown != nil
        }

        enum TrendDirection {
            case up, down, neutral
        }

        enum InsightColor {
            case green, red, blue, orange, purple, gray

            var colorName: String {
                switch self {
                case .green: return "green"
                case .red: return "red"
                case .blue: return "blue"
                case .orange: return "orange"
                case .purple: return "purple"
                case .gray: return "gray"
                }
            }
        }

        init(type: InsightType, title: String, subtitle: String, icon: String, accentColor: InsightColor, value: String?, trend: TrendDirection?, merchantName: String? = nil, detailReceipts: [ReceiptStat]? = nil, monthlyBreakdown: [(month: String, amount: Double, count: Int)]? = nil) {
            self.type = type
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.accentColor = accentColor
            self.value = value
            self.trend = trend
            self.merchantName = merchantName
            self.detailReceipts = detailReceipts
            self.monthlyBreakdown = monthlyBreakdown
        }
    }

    // MARK: - Merchant Extraction

    /// Extract the merchant name from a receipt title
    /// e.g., "Starbucks - Coffee $5.50" -> "Starbucks"
    func extractMerchantName(from title: String) -> String {
        // Common separators in receipt titles
        let separators = [" - ", " | ", " @ ", ": "]

        for separator in separators {
            if let range = title.range(of: separator) {
                let merchant = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !merchant.isEmpty {
                    return merchant
                }
            }
        }

        // If no separator, try to extract before any dollar amount
        if let dollarRange = title.range(of: "$") {
            let beforeDollar = String(title[..<dollarRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !beforeDollar.isEmpty {
                return beforeDollar
            }
        }

        // Return the whole title if no pattern matches
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Normalize merchant names for comparison (handles variations)
    func normalizeMerchantName(_ name: String) -> String {
        var normalized = name.lowercased()

        // Remove common suffixes
        let suffixes = [" inc", " llc", " corp", " co", " restaurant", " cafe", " coffee"]
        for suffix in suffixes {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count))
            }
        }

        // Common merchant name variations
        let variations: [String: String] = [
            "starbucks coffee": "starbucks",
            "sbux": "starbucks",
            "mcdonald's": "mcdonalds",
            "mcd": "mcdonalds",
            "uber eats": "uber eats",
            "ubereats": "uber eats",
            "doordash": "doordash",
            "door dash": "doordash",
            "whole foods market": "whole foods",
            "wfm": "whole foods",
            "trader joe's": "trader joes",
            "tj": "trader joes",
            "amazon.com": "amazon",
            "amzn": "amazon",
        ]

        return variations[normalized] ?? normalized
    }

    // MARK: - Coffee Detection

    /// Keywords that indicate coffee-related spending
    private let coffeeKeywords = [
        "starbucks", "dunkin", "peet's", "peets", "coffee", "cafe", "espresso",
        "latte", "cappuccino", "blue bottle", "philz", "dutch bros", "caribou",
        "tim hortons", "costa coffee", "nespresso", "keurig"
    ]

    /// Check if a receipt is coffee-related
    func isCoffeeRelated(_ receipt: ReceiptStat) -> Bool {
        let titleLower = receipt.title.lowercased()
        return coffeeKeywords.contains { titleLower.contains($0) }
    }

    // MARK: - Restaurant Detection

    private let restaurantKeywords = [
        "restaurant", "grill", "bistro", "kitchen", "eatery", "diner",
        "pizzeria", "sushi", "taco", "burger", "bbq", "steakhouse",
        "chipotle", "panera", "subway", "mcdonalds", "wendy's", "chick-fil-a",
        "five guys", "shake shack", "in-n-out", "popeyes", "kfc"
    ]

    func isRestaurantRelated(_ receipt: ReceiptStat) -> Bool {
        let titleLower = receipt.title.lowercased()
        return restaurantKeywords.contains { titleLower.contains($0) }
    }

    // MARK: - Generate Insights

    /// Generate all insights for the current month compared to previous months
    func generateInsights(
        currentMonthReceipts: [ReceiptStat],
        previousMonthReceipts: [ReceiptStat],
        allTimeReceipts: [ReceiptStat]
    ) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []

        // 1. Merchant Streak Detection
        if let streakInsight = detectMerchantStreak(allTimeReceipts: allTimeReceipts) {
            insights.append(streakInsight)
        }

        // 2. Coffee Spending Comparison
        if let coffeeInsight = compareCoffeeSpending(
            current: currentMonthReceipts,
            previous: previousMonthReceipts
        ) {
            insights.append(coffeeInsight)
        }

        // 3. Frequent Visit Detection
        insights.append(contentsOf: detectFrequentVisits(receipts: currentMonthReceipts))

        // 4. Biggest Increase/Decrease by Merchant
        if let increaseInsight = findBiggestMerchantChange(
            current: currentMonthReceipts,
            previous: previousMonthReceipts,
            findIncrease: true
        ) {
            insights.append(increaseInsight)
        }

        if let decreaseInsight = findBiggestMerchantChange(
            current: currentMonthReceipts,
            previous: previousMonthReceipts,
            findIncrease: false
        ) {
            insights.append(decreaseInsight)
        }

        // 5. New Merchants This Month
        if let newMerchantInsight = detectNewMerchants(
            current: currentMonthReceipts,
            previous: previousMonthReceipts
        ) {
            insights.append(newMerchantInsight)
        }

        // 6. Loyalty Alert (3+ consecutive months at same place)
        insights.append(contentsOf: detectLoyaltyPatterns(allTimeReceipts: allTimeReceipts))

        // 7. Month-over-Month Total Comparison
        if let momInsight = compareMonthlyTotals(
            current: currentMonthReceipts,
            previous: previousMonthReceipts
        ) {
            insights.append(momInsight)
        }

        // 8. Spending Pace Projection
        if let paceInsight = calculateSpendingPace(
            currentMonthReceipts: currentMonthReceipts,
            previousMonthTotal: previousMonthReceipts.reduce(0) { $0 + $1.amount }
        ) {
            insights.append(paceInsight)
        }

        return insights
    }

    // MARK: - Individual Insight Generators

    /// Detect merchants visited multiple months in a row
    func detectMerchantStreak(allTimeReceipts: [ReceiptStat]) -> SpendingInsight? {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"

        // Group receipts by merchant and month
        var merchantReceiptsByMonth: [String: [String: [ReceiptStat]]] = [:] // merchant -> month -> receipts

        for receipt in allTimeReceipts {
            let merchant = normalizeMerchantName(extractMerchantName(from: receipt.title))
            let monthKey = calendar.dateComponents([.year, .month], from: receipt.date)
            let monthString = "\(monthKey.year ?? 0)-\(monthKey.month ?? 0)"

            if merchantReceiptsByMonth[merchant] == nil {
                merchantReceiptsByMonth[merchant] = [:]
            }
            if merchantReceiptsByMonth[merchant]?[monthString] == nil {
                merchantReceiptsByMonth[merchant]?[monthString] = []
            }
            merchantReceiptsByMonth[merchant]?[monthString]?.append(receipt)
        }

        // Sort months chronologically (most recent first)
        let allMonths = Set(allTimeReceipts.map { receipt -> String in
            let monthKey = calendar.dateComponents([.year, .month], from: receipt.date)
            return "\(monthKey.year ?? 0)-\(monthKey.month ?? 0)"
        }).sorted().reversed()

        // Find merchants with longest streaks
        var bestMerchant: String?
        var bestStreak = 0
        var bestStreakMonths: [String] = []

        for (merchant, monthData) in merchantReceiptsByMonth {
            var streak = 0
            var streakMonths: [String] = []

            for month in allMonths {
                if monthData[month] != nil {
                    streak += 1
                    streakMonths.append(month)
                } else {
                    break
                }
            }

            if streak >= 3 && streak > bestStreak {
                bestStreak = streak
                bestMerchant = merchant
                bestStreakMonths = streakMonths
            }
        }

        // Return the longest streak with detail data
        if let merchant = bestMerchant, bestStreak >= 3 {
            let displayName = merchant.capitalized

            // Build monthly breakdown
            var monthlyBreakdown: [(month: String, amount: Double, count: Int)] = []
            var allMerchantReceipts: [ReceiptStat] = []

            for monthKey in bestStreakMonths {
                if let receipts = merchantReceiptsByMonth[merchant]?[monthKey] {
                    let total = receipts.reduce(0) { $0 + $1.amount }
                    allMerchantReceipts.append(contentsOf: receipts)

                    // Parse month key to get display name
                    let parts = monthKey.split(separator: "-")
                    if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                        var components = DateComponents()
                        components.year = year
                        components.month = month
                        components.day = 1
                        if let date = calendar.date(from: components) {
                            let monthName = dateFormatter.string(from: date)
                            monthlyBreakdown.append((month: monthName, amount: total, count: receipts.count))
                        }
                    }
                }
            }

            return SpendingInsight(
                type: .merchantStreak,
                title: "\(bestStreak) month streak",
                subtitle: "You've visited \(displayName) \(bestStreak) months in a row",
                icon: "flame.fill",
                accentColor: .orange,
                value: "\(bestStreak)",
                trend: nil,
                merchantName: displayName,
                detailReceipts: allMerchantReceipts.sorted { $0.date > $1.date },
                monthlyBreakdown: monthlyBreakdown
            )
        }

        return nil
    }

    /// Compare coffee spending between months
    func compareCoffeeSpending(current: [ReceiptStat], previous: [ReceiptStat]) -> SpendingInsight? {
        let currentCoffee = current.filter { isCoffeeRelated($0) }
        let previousCoffee = previous.filter { isCoffeeRelated($0) }

        let currentTotal = currentCoffee.reduce(0) { $0 + $1.amount }
        let previousTotal = previousCoffee.reduce(0) { $0 + $1.amount }

        guard previousTotal > 0 || currentTotal > 0 else { return nil }

        let difference = currentTotal - previousTotal
        let percentChange = previousTotal > 0 ? (difference / previousTotal) * 100 : 100

        if abs(difference) < 5 { return nil } // Ignore tiny changes

        let isUp = difference > 0
        let formattedDiff = CurrencyParser.formatAmountNoDecimals(abs(difference))

        // Combine all coffee receipts
        let allCoffeeReceipts = (currentCoffee + previousCoffee).sorted { $0.date > $1.date }

        // Monthly breakdown
        let breakdown: [(month: String, amount: Double, count: Int)] = [
            ("This Month", currentTotal, currentCoffee.count),
            ("Last Month", previousTotal, previousCoffee.count)
        ]

        return SpendingInsight(
            type: .categoryComparison,
            title: "Coffee \(isUp ? "↑" : "↓") \(String(format: "%.0f", abs(percentChange)))%",
            subtitle: "\(isUp ? "+" : "-")\(formattedDiff) vs last month",
            icon: "cup.and.saucer.fill",
            accentColor: isUp ? .red : .green,
            value: formattedDiff,
            trend: isUp ? .up : .down,
            merchantName: "Coffee Spending",
            detailReceipts: allCoffeeReceipts,
            monthlyBreakdown: breakdown
        )
    }

    /// Detect merchants visited frequently this month
    func detectFrequentVisits(receipts: [ReceiptStat]) -> [SpendingInsight] {
        var merchantReceipts: [String: [ReceiptStat]] = [:]

        for receipt in receipts {
            let merchant = normalizeMerchantName(extractMerchantName(from: receipt.title))
            if merchantReceipts[merchant] == nil {
                merchantReceipts[merchant] = []
            }
            merchantReceipts[merchant]?.append(receipt)
        }

        return merchantReceipts
            .filter { $0.value.count >= 4 } // At least 4 visits
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .map { merchant, merchantReceiptList in
                let total = merchantReceiptList.reduce(0) { $0 + $1.amount }
                return SpendingInsight(
                    type: .frequentVisit,
                    title: "\(merchantReceiptList.count) visits",
                    subtitle: "\(merchant.capitalized) this month",
                    icon: "repeat.circle.fill",
                    accentColor: .blue,
                    value: "\(merchantReceiptList.count)",
                    trend: nil,
                    merchantName: merchant.capitalized,
                    detailReceipts: merchantReceiptList.sorted { $0.date > $1.date },
                    monthlyBreakdown: [("This Month", total, merchantReceiptList.count)]
                )
            }
    }

    /// Find biggest spending increase or decrease by merchant
    func findBiggestMerchantChange(
        current: [ReceiptStat],
        previous: [ReceiptStat],
        findIncrease: Bool
    ) -> SpendingInsight? {
        // Group by merchant with receipts
        func groupByMerchant(_ receipts: [ReceiptStat]) -> [String: (total: Double, receipts: [ReceiptStat])] {
            var groups: [String: (total: Double, receipts: [ReceiptStat])] = [:]
            for receipt in receipts {
                let merchant = normalizeMerchantName(extractMerchantName(from: receipt.title))
                if groups[merchant] == nil {
                    groups[merchant] = (0, [])
                }
                groups[merchant]?.total += receipt.amount
                groups[merchant]?.receipts.append(receipt)
            }
            return groups
        }

        let currentGroups = groupByMerchant(current)
        let previousGroups = groupByMerchant(previous)

        var changes: [(merchant: String, change: Double, currentTotal: Double, previousTotal: Double)] = []

        // Find all merchants in both months
        let allMerchants = Set(currentGroups.keys).union(Set(previousGroups.keys))

        for merchant in allMerchants {
            let currentAmount = currentGroups[merchant]?.total ?? 0
            let previousAmount = previousGroups[merchant]?.total ?? 0
            let change = currentAmount - previousAmount

            if abs(change) >= 20 { // Minimum $20 change to be notable
                changes.append((merchant, change, currentAmount, previousAmount))
            }
        }

        // Sort by change amount
        let sorted = findIncrease
            ? changes.sorted { $0.change > $1.change }
            : changes.sorted { $0.change < $1.change }

        guard let top = sorted.first else { return nil }

        let formattedAmount = CurrencyParser.formatAmountNoDecimals(abs(top.change))

        // Get receipts for this merchant from both months
        let currentReceipts = currentGroups[top.merchant]?.receipts ?? []
        let previousReceipts = previousGroups[top.merchant]?.receipts ?? []
        let allReceipts = (currentReceipts + previousReceipts).sorted { $0.date > $1.date }

        // Build monthly breakdown
        let currentCount = currentReceipts.count
        let previousCount = previousReceipts.count
        var breakdown: [(month: String, amount: Double, count: Int)] = []
        breakdown.append(("This Month", top.currentTotal, currentCount))
        breakdown.append(("Last Month", top.previousTotal, previousCount))

        if findIncrease && top.change > 0 {
            return SpendingInsight(
                type: .biggestIncrease,
                title: "Biggest increase",
                subtitle: "\(top.merchant.capitalized) +\(formattedAmount)",
                icon: "arrow.up.right.circle.fill",
                accentColor: .red,
                value: formattedAmount,
                trend: .up,
                merchantName: top.merchant.capitalized,
                detailReceipts: allReceipts,
                monthlyBreakdown: breakdown
            )
        } else if !findIncrease && top.change < 0 {
            return SpendingInsight(
                type: .biggestDecrease,
                title: "Biggest savings",
                subtitle: "\(top.merchant.capitalized) -\(formattedAmount)",
                icon: "arrow.down.right.circle.fill",
                accentColor: .green,
                value: formattedAmount,
                trend: .down,
                merchantName: top.merchant.capitalized,
                detailReceipts: allReceipts,
                monthlyBreakdown: breakdown
            )
        }

        return nil
    }

    /// Detect new merchants this month
    func detectNewMerchants(current: [ReceiptStat], previous: [ReceiptStat]) -> SpendingInsight? {
        // Group current receipts by merchant
        var currentByMerchant: [String: [ReceiptStat]] = [:]
        for receipt in current {
            let merchant = normalizeMerchantName(extractMerchantName(from: receipt.title))
            if currentByMerchant[merchant] == nil {
                currentByMerchant[merchant] = []
            }
            currentByMerchant[merchant]?.append(receipt)
        }

        let previousMerchants = Set(previous.map { normalizeMerchantName(extractMerchantName(from: $0.title)) })
        let newMerchants = Set(currentByMerchant.keys).subtracting(previousMerchants)

        guard !newMerchants.isEmpty else { return nil }

        // Collect all receipts from new merchants
        var newPlaceReceipts: [ReceiptStat] = []
        var merchantBreakdown: [(month: String, amount: Double, count: Int)] = []

        for merchant in newMerchants.sorted() {
            if let receipts = currentByMerchant[merchant] {
                newPlaceReceipts.append(contentsOf: receipts)
                let total = receipts.reduce(0) { $0 + $1.amount }
                merchantBreakdown.append((merchant.capitalized, total, receipts.count))
            }
        }

        // Sort receipts by date and breakdown by amount
        newPlaceReceipts.sort { $0.date > $1.date }
        merchantBreakdown.sort { $0.amount > $1.amount }

        let displayMerchant = merchantBreakdown.first?.month ?? ""
        let moreCount = newMerchants.count - 1

        return SpendingInsight(
            type: .newMerchant,
            title: "\(newMerchants.count) new place\(newMerchants.count > 1 ? "s" : "")",
            subtitle: moreCount > 0 ? "\(displayMerchant) + \(moreCount) more" : "First time at \(displayMerchant)",
            icon: "sparkles",
            accentColor: .purple,
            value: "\(newMerchants.count)",
            trend: nil,
            merchantName: "New Places This Month",
            detailReceipts: newPlaceReceipts,
            monthlyBreakdown: merchantBreakdown
        )
    }

    /// Detect loyalty patterns (3+ months at same place)
    func detectLoyaltyPatterns(allTimeReceipts: [ReceiptStat]) -> [SpendingInsight] {
        // Group by merchant and count unique months
        var merchantMonths: [String: Set<String>] = [:]
        let calendar = Calendar.current

        for receipt in allTimeReceipts {
            let merchant = normalizeMerchantName(extractMerchantName(from: receipt.title))
            let monthKey = calendar.dateComponents([.year, .month], from: receipt.date)
            let monthString = "\(monthKey.year ?? 0)-\(monthKey.month ?? 0)"

            if merchantMonths[merchant] == nil {
                merchantMonths[merchant] = []
            }
            merchantMonths[merchant]?.insert(monthString)
        }

        return merchantMonths
            .filter { $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(1)
            .map { merchant, months in
                SpendingInsight(
                    type: .loyaltyAlert,
                    title: "Regular customer",
                    subtitle: "\(merchant.capitalized) - \(months.count) months",
                    icon: "star.fill",
                    accentColor: .orange,
                    value: "\(months.count)",
                    trend: nil
                )
            }
    }

    /// Compare month-over-month total spending
    func compareMonthlyTotals(current: [ReceiptStat], previous: [ReceiptStat]) -> SpendingInsight? {
        let currentTotal = current.reduce(0) { $0 + $1.amount }
        let previousTotal = previous.reduce(0) { $0 + $1.amount }

        guard previousTotal > 0 else { return nil }

        let difference = currentTotal - previousTotal
        let percentChange = (difference / previousTotal) * 100

        if abs(percentChange) < 5 { return nil } // Ignore tiny changes

        let isUp = difference > 0
        let formattedDiff = CurrencyParser.formatAmountNoDecimals(abs(difference))

        return SpendingInsight(
            type: .monthComparison,
            title: "\(isUp ? "↑" : "↓") \(String(format: "%.0f", abs(percentChange)))% vs last month",
            subtitle: "\(isUp ? "+" : "-")\(formattedDiff) total spending",
            icon: isUp ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
            accentColor: isUp ? .red : .green,
            value: formattedDiff,
            trend: isUp ? .up : .down
        )
    }

    /// Calculate spending pace projection
    func calculateSpendingPace(currentMonthReceipts: [ReceiptStat], previousMonthTotal: Double) -> SpendingInsight? {
        guard !currentMonthReceipts.isEmpty else { return nil }

        let calendar = Calendar.current
        let today = Date()
        let dayOfMonth = calendar.component(.day, from: today)
        let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30

        let currentTotal = currentMonthReceipts.reduce(0) { $0 + $1.amount }
        let dailyAverage = currentTotal / Double(dayOfMonth)
        let projectedTotal = dailyAverage * Double(daysInMonth)

        let formattedProjection = CurrencyParser.formatAmountNoDecimals(projectedTotal)

        let comparison: String
        let color: SpendingInsight.InsightColor

        if previousMonthTotal > 0 {
            let percentVsPrevious = ((projectedTotal - previousMonthTotal) / previousMonthTotal) * 100
            if percentVsPrevious > 10 {
                comparison = "\(String(format: "%.0f", percentVsPrevious))% above last month's pace"
                color = .red
            } else if percentVsPrevious < -10 {
                comparison = "\(String(format: "%.0f", abs(percentVsPrevious)))% below last month's pace"
                color = .green
            } else {
                comparison = "Similar to last month"
                color = .blue
            }
        } else {
            comparison = "Based on \(dayOfMonth) days"
            color = .blue
        }

        return SpendingInsight(
            type: .spendingPace,
            title: "On pace for \(formattedProjection)",
            subtitle: comparison,
            icon: "speedometer",
            accentColor: color,
            value: formattedProjection,
            trend: nil
        )
    }
}
