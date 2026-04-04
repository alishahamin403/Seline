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

    private struct SelectedDayReceipts: Identifiable {
        let id = UUID()
        let title: String
        let receipts: [ReceiptStat]

        var total: Double {
            receipts.reduce(0) { $0 + $1.amount }
        }
    }

    private struct WeekSpendDaySummary: Identifiable {
        let date: Date
        let label: String
        let amount: Double
        let isFuture: Bool

        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var receiptManager = ReceiptManager.shared
    @StateObject private var insightsService = SpendingInsightsService.shared
    @Environment(\.colorScheme) var colorScheme

    var isVisible: Bool = true
    var onAddReceiptManually: (() -> Void)? = nil
    var onAddReceipt: (() -> Void)? = nil
    var onAddReceiptFromGallery: (() -> Void)? = nil
    var onReceiptSelected: ((ReceiptStat) -> Void)? = nil

    @State private var showReceiptStats = false
    @State private var spendingInsights: [SpendingInsightsService.SpendingInsight] = []
    @State private var selectedInsight: SpendingInsightsService.SpendingInsight?
    @State private var selectedCategory: SelectedCategory?
    @State private var selectedDayReceipts: SelectedDayReceipts?
    @State private var selectedWeekSpendDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var expandedTopCategoryName: String? = nil

    private var currentYearStats: YearlyReceiptSummary? {
        let year = Calendar.current.component(.year, from: Date())
        return receiptManager.receiptStatistics(year: year).first
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

    private var currentMonthReceipts: [ReceiptStat] {
        guard let stats = currentYearStats else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        return stats.monthlySummaries
            .filter { summary in
                let month = calendar.component(.month, from: summary.monthDate)
                let year = calendar.component(.year, from: summary.monthDate)
                return month == currentMonth && year == currentYear
            }
            .flatMap { $0.receipts }
    }

    private var allReceipts: [ReceiptStat] {
        receiptManager.receiptStatistics()
            .flatMap(\.monthlySummaries)
            .flatMap(\.receipts)
    }

    private var todayReceiptStats: [ReceiptStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return receiptManager.receipts
            .filter { receipt in
                calendar.startOfDay(for: receipt.date) == today
            }
            .sorted { $0.date > $1.date }
    }

    private var dailyTotal: Double {
        todayReceiptStats.reduce(0.0) { $0 + $1.amount }
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
            stats = receiptManager.receiptStatistics(year: previousYear).first
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

    private var topSpendingCategories: [(category: String, amount: Double, percentage: Double)] {
        Array(categoryBreakdown.prefix(3))
    }

    private var spendingComparisonCopy: String {
        guard previousMonthTotal > 0 else {
            if let strongest = topSpendingCategories.first {
                return "Starting fresh this month, with \(strongest.category) leading so far."
            }
            return "Starting fresh this month with the first receipts just coming in."
        }

        let delta = monthlyTotal - previousMonthTotal
        let comparisonMonth = Self.monthLabel(for: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        let leadingCategory = topSpendingCategories.first?.category ?? "miscellaneous"
        let comparisonText: String

        if abs(delta) < 1 {
            comparisonText = "Tracking even with \(comparisonMonth)"
        } else if delta > 0 {
            comparisonText = "\(CurrencyParser.formatAmountNoDecimals(delta)) above \(comparisonMonth)"
        } else {
            comparisonText = "\(CurrencyParser.formatAmountNoDecimals(abs(delta))) under \(comparisonMonth)"
        }

        return "\(comparisonText), strongest category is \(leadingCategory)."
    }

    private var weekSpendSummaries: [WeekSpendDaySummary] {
        let calendar = mondayFirstCalendar
        let today = calendar.startOfDay(for: Date())
        let weekStart = startOfCurrentWeek(for: today)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        let totalsByDay = Dictionary(grouping: allReceipts.filter { receipt in
            let day = calendar.startOfDay(for: receipt.date)
            return day >= weekStart && day < weekEnd
        }) { receipt in
            calendar.startOfDay(for: receipt.date)
        }
        .mapValues { receipts in
            receipts.reduce(0.0) { total, receipt in
                total + receipt.amount
            }
        }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }

            let dayStart = calendar.startOfDay(for: date)
            let amount = totalsByDay[dayStart] ?? 0

            return WeekSpendDaySummary(
                date: dayStart,
                label: weekdayLabel(for: dayStart),
                amount: dayStart > today ? 0 : amount,
                isFuture: dayStart > today
            )
        }
    }

    private var selectedWeekSpendSummary: WeekSpendDaySummary? {
        let calendar = mondayFirstCalendar

        if let selected = weekSpendSummaries.first(where: { summary in
            calendar.isDate(summary.date, inSameDayAs: selectedWeekSpendDate) && !summary.isFuture
        }) {
            return selected
        }

        return weekSpendSummaries.reversed().first(where: { !$0.isFuture }) ?? weekSpendSummaries.first
    }

    private func receiptsForWeekSpendDay(_ date: Date) -> [ReceiptStat] {
        let dayStart = mondayFirstCalendar.startOfDay(for: date)

        return allReceipts
            .filter { receipt in
                mondayFirstCalendar.startOfDay(for: receipt.date) == dayStart
            }
            .sorted { $0.date > $1.date }
    }

    private func receiptsForExpandedCategory(_ categoryName: String) -> [ReceiptStat] {
        (categoryReceiptsMapCache[categoryName] ?? [])
            .sorted { $0.date > $1.date }
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
                if let expandedTopCategoryName = self.expandedTopCategoryName,
                   !result.contains(where: { $0.category == expandedTopCategoryName }) {
                    self.expandedTopCategoryName = nil
                }
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
        WidgetInvalidationCoordinator.shared.requestReload(reason: "spending_widget_update")
    }
    
    /// Static method to refresh widget spending data from NotesManager
    /// Call this on app startup and when receipts change
    static func refreshWidgetSpendingData() {
        let receiptManager = ReceiptManager.shared
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let today = calendar.startOfDay(for: now)
        let dailyTotal = receiptManager.receipts
            .filter { receipt in
                calendar.startOfDay(for: receipt.date) == today
            }
            .reduce(0.0) { $0 + $1.amount }
        
        guard let stats = receiptManager.receiptStatistics(year: year).first else {
            updateWidgetWithSpendingData(
                monthlyTotal: 0,
                monthOverMonthPercentage: 0,
                isSpendingIncreasing: false,
                dailyTotal: dailyTotal
            )
            return
        }
        
        // Calculate monthly total
        let monthlyTotal = stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let yearComponent = calendar.component(.year, from: summary.monthDate)
            return month == currentMonth && yearComponent == currentYear
        }.reduce(0) { $0 + $1.monthlyTotal }
        
        // Calculate previous month and year, handling year boundary
        let previousMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let previousYear = currentMonth == 1 ? currentYear - 1 : currentYear
        
        // If previous month is in a different year, fetch that year's statistics
        let previousMonthTotal: Double
        if previousYear != currentYear {
            if let previousYearStats = receiptManager.receiptStatistics(year: previousYear).first {
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

    private static func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    var body: some View {
        spendingCard()
            .onAppear {
                guard isVisible else { return }
                Task {
                    await notesManager.ensureReceiptDataAvailable()
                    await MainActor.run {
                        updateCategoryBreakdown()
                        selectedWeekSpendDate = mondayFirstCalendar.startOfDay(for: Date())
                    }
                }
            }
            .onChange(of: isVisible) { newValue in
                guard newValue else { return }
                Task {
                    await notesManager.ensureReceiptDataAvailable()
                    await MainActor.run {
                        updateCategoryBreakdown()
                        selectedWeekSpendDate = mondayFirstCalendar.startOfDay(for: Date())
                    }
                }
            }
            .onChange(of: notesManager.notes.count) { _ in
                guard isVisible else { return }
                updateCategoryBreakdown()
                selectedWeekSpendDate = mondayFirstCalendar.startOfDay(for: Date())
            }
            .onChange(of: notesManager.folders.count) { _ in
                guard isVisible else { return }
                updateCategoryBreakdown()
                selectedWeekSpendDate = mondayFirstCalendar.startOfDay(for: Date())
            }
            .sheet(isPresented: $showReceiptStats) {
                ReceiptStatsView(isPopup: true)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedInsight) { insight in
                if insight.hasDetails {
                    InsightDetailSheet(insight: insight)
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(item: $selectedCategory) { category in
                CategoryReceiptsListModal(
                    receipts: category.receipts,
                    categoryName: category.name,
                    total: category.total,
                    onReceiptTap: { receipt in
                        onReceiptSelected?(receipt)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedDayReceipts) { selection in
                CategoryReceiptsListModal(
                    receipts: selection.receipts,
                    categoryName: selection.title,
                    total: selection.total,
                    onReceiptTap: { receipt in
                        onReceiptSelected?(receipt)
                    }
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
            let yearlyStats = receiptManager.receiptStatistics()

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
                allTimeReceipts: allTimeReceipts,
                historicalReceipts: allReceipts
            )

            await MainActor.run {
                spendingInsights = insights.filter { $0.type != .spendingPace }
            }
        }
    }

    private func spendingCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SPENDING")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .tracking(0.9)

                    Text("This month")
                        .font(FontManager.geist(size: 22, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                }

                Spacer(minLength: 12)
                addReceiptPillButton
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: openReceiptStatsPage) {
                        Text(CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                            .font(FontManager.geist(size: 42, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text(spendingComparisonCopy)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: openReceiptStatsPage) {
                    spendingSideMetricCard(
                        title: "Receipts",
                        value: "\(currentMonthReceipts.count)"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 120)
            }

            spendingRhythmRow
            selectedWeekSpendDetail

            if !topSpendingCategories.isEmpty {
                VStack(spacing: 10) {
                    ForEach(topSpendingCategories, id: \.category) { category in
                        topCategoryButtonRow(category)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeGlassCardStyle(
            colorScheme: colorScheme,
            cornerRadius: ShadcnRadius.xl,
            usesPureLightFill: true
        )
    }

    private var addReceiptPillButton: some View {
        Group {
            if onAddReceipt != nil || onAddReceiptFromGallery != nil {
                Menu {
                    receiptAddMenuContent
                } label: {
                    addReceiptPillLabel
                }
            } else {
                Button(action: {
                    HapticManager.shared.buttonTap()
                }) {
                    addReceiptPillLabel
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(true)
            }
        }
    }

    private var addReceiptMenuButton: some View {
        Group {
            if onAddReceipt != nil || onAddReceiptFromGallery != nil {
                Menu {
                    receiptAddMenuContent
                } label: {
                    addReceiptButtonLabel
                }
            } else {
                Button(action: {
                    HapticManager.shared.buttonTap()
                }) {
                    addReceiptButtonLabel
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(true)
            }
        }
        .contentShape(Circle())
    }

    private var addReceiptButtonLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(homeAccentColor)
            )
    }

    private var addReceiptPillLabel: some View {
        Text("ADD RECEIPT")
            .font(FontManager.geist(size: 13, weight: .semibold))
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(homeAccentColor)
            )
    }

    @ViewBuilder
    private var receiptAddMenuContent: some View {
        if let onAddReceiptManually {
            Button(action: {
                HapticManager.shared.selection()
                onAddReceiptManually()
            }) {
                Label("Add Manually", systemImage: "square.and.pencil")
            }
        }

        if let onAddReceipt {
            Button(action: {
                HapticManager.shared.selection()
                onAddReceipt()
            }) {
                Label("Take Picture", systemImage: "camera.fill")
            }
        }

        if let onAddReceiptFromGallery {
            Button(action: {
                HapticManager.shared.selection()
                onAddReceiptFromGallery()
            }) {
                Label("Select Picture", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var spendingSignalsOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signals")
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(categoryBreakdown.prefix(4)), id: \.category) { category in
                        Button(action: {
                            openCategoryExpenses(for: category.category)
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(category.category)
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Text(CurrencyParser.formatAmountNoDecimals(category.amount))
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }

                                Text("\(Int(category.percentage.rounded()))% of month")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                                    .lineLimit(1)
                            }
                            .frame(width: 178, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    // MARK: - Insights Scroll View

    private var insightsScrollView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(spendingInsights) { insight in
                        Button(action: {
                            guard insight.hasDetails else { return }
                            selectedInsight = insight
                            HapticManager.shared.selection()
                        }) {
                            insightChip(insight)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!insight.hasDetails)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
        .allowsParentScrolling()
    }

    private func insightChip(_ insight: SpendingInsightsService.SpendingInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)

            Text(insight.subtitle)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 194)
        .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 16)
    }

    private func spendingMetricTile(title: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 19, weight: .semibold))
                .foregroundColor(valueColor ?? Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private var spendingHeroCardBackground: some View {
        HomeGlassCardBackground(
            colorScheme: colorScheme,
            cornerRadius: 24,
            highlightStrength: 1
        )
    }

    private var homeAccentColor: Color {
        Color.homeGlassAccent
    }

    private var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var monthOverMonthMetricText: String {
        guard previousMonthTotal > 0 else {
            return monthlyTotal > 0 ? "New" : "--"
        }

        let sign = monthOverMonthPercentage.isIncrease ? "+" : "-"
        return "\(sign)\(Int(monthOverMonthPercentage.percentage.rounded()))%"
    }

    private var monthOverMonthMetricColor: Color {
        guard previousMonthTotal > 0 else {
            return Color.appTextPrimary(colorScheme)
        }
        return monthOverMonthPercentage.isIncrease ? .red : .green
    }

    private var spendingRhythmRow: some View {
        let maximum = max(weekSpendSummaries.filter { !$0.isFuture }.map(\.amount).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(weekSpendSummaries) { day in
                let isSelected = selectedWeekSpendSummary.map {
                    mondayFirstCalendar.isDate($0.date, inSameDayAs: day.date)
                } ?? false

                Button(action: {
                    guard !day.isFuture else { return }
                    HapticManager.shared.selection()
                    selectedWeekSpendDate = day.date
                }) {
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(weekdayPillFillColor(for: day, isSelected: isSelected))
                            .frame(
                                width: weekdayPillWidth(for: day.amount, maximum: maximum, isFuture: day.isFuture),
                                height: weekdayPillHeight(for: day.amount, maximum: maximum, isFuture: day.isFuture)
                            )
                            .opacity(weekdayPillOpacity(for: day, isSelected: isSelected))

                        Text(day.label.uppercased())
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .foregroundColor(
                                isSelected
                                ? Color.appTextPrimary(colorScheme)
                                : Color.appTextSecondary(colorScheme)
                            )
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isSelected
                                ? Color.homeGlassInnerTint(colorScheme)
                                : Color.clear
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(day.isFuture)
            }
        }
        .padding(.top, 4)
    }

    private var selectedWeekSpendDetail: some View {
        Group {
            if let selected = selectedWeekSpendSummary {
                Button(action: {
                    openSelectedDayReceipts(selected)
                }) {
                    HStack(alignment: .center, spacing: 12) {
                        Capsule()
                            .fill(selected.amount > 0 ? Color.homeGlassAccent : Color.homeGlassInnerTint(colorScheme))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(FormatterCache.weekdayShortMonthDay.string(from: selected.date))
                                .font(FontManager.geist(size: 12, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))

                            Text(selected.amount > 0 ? "Spent that day" : "No spend logged")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                        }

                        Spacer(minLength: 10)

                        Text(CurrencyParser.formatAmountNoDecimals(selected.amount))
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.homeGlassInnerTint(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.homeGlassInnerBorder(colorScheme), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func weekdayPillWidth(for amount: Double, maximum: Double, isFuture: Bool) -> CGFloat {
        guard !isFuture else { return 28 }
        guard amount > 0, maximum > 0 else { return 32 }
        let ratio = max(amount / maximum, 0.18)
        return 32 + (28 * ratio)
    }

    private func weekdayPillHeight(for amount: Double, maximum: Double, isFuture: Bool) -> CGFloat {
        guard !isFuture else { return 10 }
        guard amount > 0, maximum > 0 else { return 12 }
        let ratio = max(amount / maximum, 0.22)
        return 12 + (18 * ratio)
    }

    private func weekdayPillFillColor(for day: WeekSpendDaySummary, isSelected: Bool) -> Color {
        if day.isFuture {
            return Color.appTextPrimary(colorScheme)
        }

        if day.amount > 0 {
            return isSelected ? Color.homeGlassAccent : Color.appTextPrimary(colorScheme)
        }

        return Color.appTextPrimary(colorScheme)
    }

    private func weekdayPillOpacity(for day: WeekSpendDaySummary, isSelected: Bool) -> Double {
        if day.isFuture {
            return colorScheme == .dark ? 0.14 : 0.1
        }

        if day.amount > 0 {
            return isSelected ? 0.95 : 1
        }

        return isSelected ? 0.28 : (colorScheme == .dark ? 0.22 : 0.16)
    }

    private func startOfCurrentWeek(for date: Date) -> Date {
        let calendar = mondayFirstCalendar
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.startOfDay(for: calendar.date(from: components) ?? date)
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = mondayFirstCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func spendingSideMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(0.7)

            Text(value)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.homeGlassInnerTint(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.homeGlassInnerBorder(colorScheme), lineWidth: 1)
        )
    }

    private func spendingCategoryRow(_ category: (category: String, amount: Double, percentage: Double)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(category.category)
                .font(FontManager.geist(size: 15, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.26 : 0.2))

                    Capsule()
                        .fill(Color.appTextPrimary(colorScheme))
                        .frame(width: max(28, geometry.size.width * CGFloat(category.percentage / 100)))
                }
            }
            .frame(height: 6)

            Text(CurrencyParser.formatAmountNoDecimals(category.amount))
                .font(FontManager.geist(size: 15, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 24)
    }

    private func topCategoryButtonRow(_ category: (category: String, amount: Double, percentage: Double)) -> some View {
        let isExpanded = expandedTopCategoryName == category.category
        let receipts = receiptsForExpandedCategory(category.category)

        return VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                HapticManager.shared.selection()
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedTopCategoryName = nil
                    } else {
                        expandedTopCategoryName = category.category
                    }
                }
            }) {
                HStack(alignment: .center, spacing: 12) {
                    spendingCategoryRow(category)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if receipts.isEmpty {
                        Text("No receipt details available for this category.")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    } else {
                        ForEach(Array(receipts.prefix(3).enumerated()), id: \.offset) { index, receipt in
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(receipt.title)
                                        .font(FontManager.geist(size: 12, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)

                                    Text(FormatterCache.weekdayShortMonthDay.string(from: receipt.date))
                                        .font(FontManager.geist(size: 11, weight: .medium))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                }

                                Spacer(minLength: 10)

                                Text(CurrencyParser.formatAmountNoDecimals(receipt.amount))
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                            }

                            if index < min(receipts.count, 3) - 1 {
                                Divider()
                                    .overlay(Color.homeGlassInnerBorder(colorScheme))
                            }
                        }

                        if receipts.count > 3 {
                            Button(action: {
                                openCategoryExpenses(for: category.category)
                            }) {
                                Text("View all")
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.homeGlassInnerTint(colorScheme))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.homeGlassInnerTint(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.homeGlassInnerBorder(colorScheme), lineWidth: 1)
                )
            }
        }
    }

    private var monthlyForecastText: String {
        insightsService.calculateSpendingPace(
            currentMonthReceipts: currentMonthReceipts,
            previousMonthTotal: previousMonthTotal
        )?.value ?? "--"
    }

    private func openReceiptStatsPage() {
        HapticManager.shared.selection()
        showReceiptStats = true
    }

    private func openCategoryExpenses(for categoryName: String) {
        let matchingReceipts = (categoryReceiptsMapCache[categoryName] ?? [])
            .sorted { $0.date > $1.date }

        guard !matchingReceipts.isEmpty else { return }
        HapticManager.shared.selection()
        selectedCategory = SelectedCategory(name: categoryName, receipts: matchingReceipts)
    }

    private func openSelectedDayReceipts(_ selected: WeekSpendDaySummary) {
        let receipts = receiptsForWeekSpendDay(selected.date)
        guard !receipts.isEmpty else { return }

        HapticManager.shared.selection()
        selectedDayReceipts = SelectedDayReceipts(
            title: FormatterCache.weekdayShortMonthDay.string(from: selected.date),
            receipts: receipts
        )
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
                    if insight.type != .newMerchant, let receipts = insight.detailReceipts, !receipts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transactions")
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
