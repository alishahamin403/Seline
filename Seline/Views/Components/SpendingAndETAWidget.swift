import SwiftUI
import CoreLocation
import WidgetKit

struct SpendingAndETAWidget: View {
    private struct SelectedCategory: Identifiable {
        let id = UUID()
        let name: String
        let receipts: [ReceiptStat]

        var total: Double {
            receipts.reduce(0) { $0 + $1.amount }
        }
    }

    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var insightsService = SpendingInsightsService.shared
    @Environment(\.colorScheme) var colorScheme

    var isVisible: Bool = true
    var onAddReceipt: (() -> Void)? = nil
    var onAddReceiptFromGallery: (() -> Void)? = nil

    @State private var showReceiptStats = false
    @State private var spendingInsights: [SpendingInsightsService.SpendingInsight] = []
    @State private var selectedInsight: SpendingInsightsService.SpendingInsight?
    @State private var showInsightDetail = false
    @State private var selectedCategory: SelectedCategory?
    @State private var isCategoryScrollInProgress = false

    private var cardHeadingFont: Font {
        FontManager.geist(size: 20, weight: .semibold)
    }

    private var currentYearStats: YearlyReceiptSummary? {
        let year = Calendar.current.component(.year, from: Date())
        return notesManager.getReceiptStatistics(year: year).first
    }

    private var monthlyTotal: Double {
        guard let stats = currentYearStats else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        return stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let year = calendar.component(.year, from: summary.monthDate)
            return month == currentMonth && year == currentYear
        }.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var dailyTotal: Double {
        guard let stats = currentYearStats else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // Get all receipts from current month
        var todayReceipts: [ReceiptStat] = []
        for monthlySummary in stats.monthlySummaries {
            let month = calendar.component(.month, from: monthlySummary.monthDate)
            let year = calendar.component(.year, from: monthlySummary.monthDate)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)

            if month == currentMonth && year == currentYear {
                todayReceipts.append(contentsOf: monthlySummary.receipts)
            }
        }

        // Filter for today only
        let todayTotal = todayReceipts.filter { receipt in
            let receiptDay = calendar.startOfDay(for: receipt.date)
            return receiptDay == today
        }.reduce(0.0) { $0 + $1.amount }

        return todayTotal
    }

    private var previousMonthTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        // Calculate previous month and year, handling year boundary
        let previousMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let previousYear = currentMonth == 1 ? currentYear - 1 : currentYear
        
        // If previous month is in a different year, fetch that year's statistics
        let stats: YearlyReceiptSummary?
        if previousYear != currentYear {
            stats = notesManager.getReceiptStatistics(year: previousYear).first
        } else {
            stats = currentYearStats
        }
        
        guard let stats = stats else { return 0 }

        return stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let year = calendar.component(.year, from: summary.monthDate)
            return month == previousMonth && year == previousYear
        }.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var monthOverMonthPercentage: (percentage: Double, isIncrease: Bool) {
        guard previousMonthTotal > 0 else { return (0, false) }
        let change = ((monthlyTotal - previousMonthTotal) / previousMonthTotal) * 100
        return (abs(change), change >= 0)
    }

    @State private var categoryBreakdownCache: [(category: String, amount: Double, percentage: Double)] = []
    @State private var categoryReceiptsMapCache: [String: [ReceiptStat]] = [:]

    private var categoryBreakdown: [(category: String, amount: Double, percentage: Double)] {
        return categoryBreakdownCache
    }

    private func updateCategoryBreakdown() {
        Task {
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)

            // Get receipts for the current month only
            guard let stats = currentYearStats else {
                DispatchQueue.main.async {
                    self.categoryBreakdownCache = []
                    self.categoryReceiptsMapCache = [:]
                }
                return
            }

            // Filter to get only current month's receipts
            let currentMonthReceipts = stats.monthlySummaries
                .filter { summary in
                    let month = calendar.component(.month, from: summary.monthDate)
                    let year = calendar.component(.year, from: summary.monthDate)
                    return month == currentMonth && year == currentYear
                }
                .flatMap { $0.receipts }

            // If no receipts for current month, return empty
            guard !currentMonthReceipts.isEmpty else {
                DispatchQueue.main.async {
                    self.categoryBreakdownCache = []
                    self.categoryReceiptsMapCache = [:]
                }
                return
            }

            // Calculate category breakdown for current month only
            let breakdown = await ReceiptCategorizationService.shared.getCategoryBreakdown(for: currentMonthReceipts)

            // Calculate month total from current month's receipts
            let monthTotal = breakdown.yearlyTotal // This is actually the month total since we filtered receipts

            // Map to tuple format with percentages based on current month's total
            let categoryTuples = breakdown.categories.map { categoryStat -> (category: String, amount: Double, percentage: Double) in
                let percentage = monthTotal > 0 ? (categoryStat.total / monthTotal) * 100 : 0
                return (category: categoryStat.category, amount: categoryStat.total, percentage: percentage)
            }

            // Sort by amount and take top 5
            let sorted = categoryTuples.sorted { $0.amount > $1.amount }
            let result = Array(sorted.prefix(5))

            DispatchQueue.main.async {
                self.categoryBreakdownCache = result
                self.categoryReceiptsMapCache = breakdown.categoryReceipts
                // Update widget with spending data
                Self.updateWidgetWithSpendingData(
                    monthlyTotal: self.monthlyTotal,
                    monthOverMonthPercentage: self.monthOverMonthPercentage.percentage,
                    isSpendingIncreasing: self.monthOverMonthPercentage.isIncrease,
                    dailyTotal: self.dailyTotal
                )
            }
        }
    }

    /// Static method to update widget with spending data - can be called from anywhere
    static func updateWidgetWithSpendingData(
        monthlyTotal: Double,
        monthOverMonthPercentage: Double,
        isSpendingIncreasing: Bool,
        dailyTotal: Double
    ) {
        // Write spending data to shared UserDefaults for widget display
        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(monthlyTotal, forKey: "widgetMonthlySpending")
            userDefaults.set(monthOverMonthPercentage, forKey: "widgetMonthOverMonthPercentage")
            userDefaults.set(isSpendingIncreasing, forKey: "widgetIsSpendingIncreasing")
            userDefaults.set(dailyTotal, forKey: "widgetDailySpending")
            userDefaults.set(Date(), forKey: "widgetSpendingLastUpdated")
            userDefaults.synchronize() // Force immediate write
        }
        
        // Reload widget timelines to pick up new data
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    /// Static method to refresh widget spending data from NotesManager
    /// Call this on app startup and when receipts change
    static func refreshWidgetSpendingData() {
        let notesManager = NotesManager.shared
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        guard let stats = notesManager.getReceiptStatistics(year: year).first else {
            // No stats - set zeros
            updateWidgetWithSpendingData(
                monthlyTotal: 0,
                monthOverMonthPercentage: 0,
                isSpendingIncreasing: false,
                dailyTotal: 0
            )
            return
        }
        
        // Calculate monthly total
        let monthlyTotal = stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let yearComponent = calendar.component(.year, from: summary.monthDate)
            return month == currentMonth && yearComponent == currentYear
        }.reduce(0) { $0 + $1.monthlyTotal }
        
        // Calculate daily total
        let today = calendar.startOfDay(for: now)
        var todayReceipts: [ReceiptStat] = []
        for monthlySummary in stats.monthlySummaries {
            let month = calendar.component(.month, from: monthlySummary.monthDate)
            let yearComponent = calendar.component(.year, from: monthlySummary.monthDate)
            if month == currentMonth && yearComponent == currentYear {
                todayReceipts.append(contentsOf: monthlySummary.receipts)
            }
        }
        let dailyTotal = todayReceipts.filter { receipt in
            let receiptDay = calendar.startOfDay(for: receipt.date)
            return receiptDay == today
        }.reduce(0.0) { $0 + $1.amount }
        
        // Calculate previous month and year, handling year boundary
        let previousMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let previousYear = currentMonth == 1 ? currentYear - 1 : currentYear
        
        // If previous month is in a different year, fetch that year's statistics
        let previousMonthTotal: Double
        if previousYear != currentYear {
            if let previousYearStats = notesManager.getReceiptStatistics(year: previousYear).first {
                previousMonthTotal = previousYearStats.monthlySummaries.filter { summary in
                    let month = calendar.component(.month, from: summary.monthDate)
                    let yearComponent = calendar.component(.year, from: summary.monthDate)
                    return month == previousMonth && yearComponent == previousYear
                }.reduce(0) { $0 + $1.monthlyTotal }
            } else {
                previousMonthTotal = 0
            }
        } else {
            previousMonthTotal = stats.monthlySummaries.filter { summary in
                let month = calendar.component(.month, from: summary.monthDate)
                let yearComponent = calendar.component(.year, from: summary.monthDate)
                return month == previousMonth && yearComponent == previousYear
            }.reduce(0) { $0 + $1.monthlyTotal }
        }
        
        // Calculate month over month percentage
        var percentage: Double = 0
        var isIncrease = false
        if previousMonthTotal > 0 {
            let change = ((monthlyTotal - previousMonthTotal) / previousMonthTotal) * 100
            percentage = abs(change)
            isIncrease = change >= 0
        }
        
        updateWidgetWithSpendingData(
            monthlyTotal: monthlyTotal,
            monthOverMonthPercentage: percentage,
            isSpendingIncreasing: isIncrease,
            dailyTotal: dailyTotal
        )
        
        print("💰 Widget spending data refreshed - Monthly: $\(monthlyTotal), Daily: $\(dailyTotal)")
    }

    var body: some View {
        spendingCard()
        .onAppear {
            updateCategoryBreakdown()
            generateSpendingInsights()
        }
        .onChange(of: notesManager.notes.count) { _ in
            updateCategoryBreakdown()
            generateSpendingInsights()
        }
        .sheet(isPresented: $showReceiptStats) {
            ReceiptStatsView(isPopup: true)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showInsightDetail) {
            if let insight = selectedInsight, insight.hasDetails {
                InsightDetailSheet(insight: insight)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $selectedCategory) { category in
            CategoryReceiptsListModal(
                receipts: category.receipts,
                categoryName: category.name,
                total: category.total
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func generateSpendingInsights() {
        Task {
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)

            // Get all receipt statistics
            let yearlyStats = notesManager.getReceiptStatistics()

            // Flatten all receipts
            var allReceipts: [ReceiptStat] = []
            for yearly in yearlyStats {
                for monthly in yearly.monthlySummaries {
                    allReceipts.append(contentsOf: monthly.receipts)
                }
            }

            // Current month receipts
            let currentMonthReceipts = allReceipts.filter { receipt in
                let components = calendar.dateComponents([.year, .month], from: receipt.date)
                return components.year == currentYear && components.month == currentMonth
            }

            // Previous month receipts
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
            let previousMonthReceipts = allReceipts.filter { receipt in
                let components = calendar.dateComponents([.year, .month], from: receipt.date)
                return components.year == prevComponents.year && components.month == prevComponents.month
            }

            // Last 6 months for streak detection
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
            let allTimeReceipts = allReceipts.filter { $0.date >= sixMonthsAgo }

            let insights = insightsService.generateInsights(
                currentMonthReceipts: currentMonthReceipts,
                previousMonthReceipts: previousMonthReceipts,
                allTimeReceipts: allTimeReceipts
            )

            await MainActor.run {
                spendingInsights = insights
            }
        }
    }

    private func spendingCard() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spending")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("This Month")
                        .font(cardHeadingFont)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)
                addReceiptMenuButton
            }

            HStack(spacing: 8) {
                spendingStatPill(
                    title: "Month",
                    value: CurrencyParser.formatAmountNoDecimals(monthlyTotal)
                )

                spendingStatPill(
                    title: "Today",
                    value: CurrencyParser.formatAmountNoDecimals(dailyTotal)
                )

                trendPill
            }

            topCategoryView

            if !spendingInsights.isEmpty {
                insightsScrollView
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCategoryScrollInProgress else { return }
            showReceiptStats = true
        }
        .shadcnTileStyle(colorScheme: colorScheme)
    }

    private var addReceiptMenuButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                onAddReceipt?()
            }) {
                Label("Camera", systemImage: "camera.fill")
            }

            Button(action: {
                HapticManager.shared.selection()
                onAddReceiptFromGallery?()
            }) {
                Label("Gallery", systemImage: "photo.fill")
            }
        } label: {
            Image(systemName: "plus")
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private var daysLeftInMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now)!
        let numDays = range.count
        let currentDay = calendar.component(.day, from: now)
        return numDays - currentDay
    }

    private var nextMonthName: String {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: nextMonth)
    }


    private var topCategoryView: some View {
        Group {
            if !categoryBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Categories")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(categoryBreakdown.prefix(5).enumerated()), id: \.element.category) { _, category in
                                let iconColor = CategoryIconProvider.color(for: category.category)
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(iconColor.opacity(colorScheme == .dark ? 0.24 : 0.16))
                                            .frame(width: 20, height: 20)
                                        Image(systemName: categorySymbol(category.category))
                                            .font(FontManager.geist(size: 9, weight: .semibold))
                                            .foregroundColor(iconColor)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.category)
                                            .font(FontManager.geist(size: 11, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        Text(CurrencyParser.formatAmountNoDecimals(category.amount))
                                            .font(FontManager.geist(size: 11, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .scrollSafeTapAction(minimumDragDistance: 3) {
                                    guard !isCategoryScrollInProgress else { return }
                                    openCategoryExpenses(for: category.category)
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { _ in
                                            isCategoryScrollInProgress = true
                                        }
                                        .onEnded { _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                isCategoryScrollInProgress = false
                                            }
                                        }
                                )
                                .allowsParentScrolling()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { _ in
                                isCategoryScrollInProgress = true
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    isCategoryScrollInProgress = false
                                }
                            }
                    )
                    .padding(.horizontal, -16)
                    .allowsParentScrolling()
                }
            }
        }
    }

    // MARK: - Insights Scroll View

    private var insightsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(spendingInsights) { insight in
                    insightChip(insight)
                        .onTapGesture {
                            if insight.hasDetails {
                                selectedInsight = insight
                                showInsightDetail = true
                                HapticManager.shared.selection()
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
        .allowsParentScrolling()
        .padding(.top, 2)
    }

    private func insightChip(_ insight: SpendingInsightsService.SpendingInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Text(insight.subtitle)
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
        )
    }

    private func spendingStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FontManager.geist(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.5))

            Text(value)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
        )
    }

    private var trendPill: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MoM")
                .font(FontManager.geist(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.5))

            HStack(spacing: 4) {
                Image(systemName: monthOverMonthPercentage.isIncrease ? "arrow.up.right" : "arrow.down.right")
                    .font(FontManager.geist(size: 10, weight: .semibold))
                Text(String(format: "%.0f%%", monthOverMonthPercentage.percentage))
                    .font(FontManager.geist(size: 14, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
        )
    }

    private func categorySymbol(_ category: String) -> String {
        let cat = category.lowercased()
        if cat.contains("food") || cat.contains("dining") || cat.contains("restaurant") {
            return "fork.knife"
        } else if cat.contains("grocery") {
            return "cart"
        } else if cat.contains("transport") || cat.contains("gas") || cat.contains("uber") || cat.contains("lyft") || cat.contains("auto") {
            return "car.fill"
        } else if cat.contains("shopping") || cat.contains("retail") || cat.contains("store") {
            return "bag"
        } else if cat.contains("entertainment") || cat.contains("movie") || cat.contains("netflix") {
            return "film"
        } else if cat.contains("health") || cat.contains("medical") || cat.contains("pharmacy") {
            return "cross.case"
        } else if cat.contains("travel") || cat.contains("hotel") || cat.contains("flight") {
            return "airplane"
        } else if cat.contains("utilities") || cat.contains("internet") || cat.contains("electric") || cat.contains("water") {
            return "bolt"
        } else if cat.contains("software") || cat.contains("subscription") || cat.contains("app") {
            return "laptopcomputer"
        }
        return "creditcard"
    }

    private func openCategoryExpenses(for categoryName: String) {
        let matchingReceipts = (categoryReceiptsMapCache[categoryName] ?? [])
            .sorted { $0.date > $1.date }

        guard !matchingReceipts.isEmpty else { return }
        HapticManager.shared.selection()
        selectedCategory = SelectedCategory(name: categoryName, receipts: matchingReceipts)
    }


    private var recentTransactionsView: some View {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let todaysNotes = notesManager.notes.filter { note in
            let noteDay = calendar.startOfDay(for: note.dateCreated)
            return noteDay == today
        }.sorted { $0.dateCreated > $1.dateCreated }.prefix(3)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(todaysNotes), id: \.id) { note in
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(FontManager.geist(size: 10, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Spacer()

                    Text(formatExpenseDate(note.dateCreated ?? Date()))
                        .font(FontManager.geist(size: 9, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                    if let amount = extractAmount(from: note.content ?? "") {
                        Text(CurrencyParser.formatAmountNoDecimals(amount))
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func formatExpenseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateDay = calendar.startOfDay(for: date)
        
        if dateDay == today {
            // For today's expenses, show time
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else {
            // For other dates, show short date format
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    private func extractAmount(from text: String) -> Double? {
        let pattern = "\\$[0-9,]+(?:\\.[0-9]{2})?"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) {
                    let amountStr = String(text[range]).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
                    return Double(amountStr)
                }
            }
        }
        return nil
    }
}

// MARK: - Insight Detail Sheet

struct InsightDetailSheet: View {
    let insight: SpendingInsightsService.SpendingInsight
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        if let merchantName = insight.merchantName {
                            Text(merchantName)
                                .font(FontManager.geist(size: 24, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }

                        Text(insight.subtitle)
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Monthly Breakdown (or Merchant Breakdown for new places)
                    if let breakdown = insight.monthlyBreakdown, !breakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(insight.type == .newMerchant ? "New Places" : "Breakdown")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(0.5)

                            ForEach(breakdown, id: \.month) { item in
                                HStack {
                                    Text(item.month)
                                        .font(FontManager.geist(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(item.count) visit\(item.count == 1 ? "" : "s")")
                                        .font(FontManager.geist(size: 13, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                                    Text(CurrencyParser.formatAmountNoDecimals(item.amount))
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Receipt List
                    if let receipts = insight.detailReceipts, !receipts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Transactions")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(0.5)

                            ForEach(receipts, id: \.id) { receipt in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(receipt.title)
                                            .font(FontManager.geist(size: 14, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        Text(dateFormatter.string(from: receipt.date))
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                    }

                                    Spacer()

                                    Text(CurrencyParser.formatAmountNoDecimals(receipt.amount))
                                        .font(FontManager.geist(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle(insight.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(FontManager.geist(size: 15, weight: .medium))
                }
            }
        }
    }
}

#Preview {
    SpendingAndETAWidget(isVisible: true)
        .padding()
}
