import SwiftUI

struct ReceiptStatsView: View {
    private enum DrilldownMode: String, CaseIterable {
        case overview = "Overview"
        case yearly = "Yearly"
        case monthly = "Monthly"
    }

    @StateObject private var notesManager = NotesManager.shared
    @State private var currentYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedReceipt: ReceiptStat? = nil
    @State private var categoryBreakdown: YearlyCategoryBreakdown? = nil
    @State private var isLoadingCategories = false
    @State private var selectedCategory: String? = nil
    @State private var showRecurringExpenses = false
    @State private var drilldownMode: DrilldownMode = .overview
    @State private var showAllYearlyCategories = false
    @State private var selectedMonthName: String? = nil
    @State private var monthlyCategoryFilter: String? = nil
    @State private var showMonthlyCategoryBreakdown = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var categoryBreakdownDebounceTask: Task<Void, Never>? = nil  // Debounce task for category recalculation
    @State private var contentHeight: CGFloat = 400

    var searchText: String? = nil
    var initialMonthDate: Date? = nil
    var onAddReceipt: (() -> Void)? = nil

    var isPopup: Bool = false

    var availableYears: [Int] {
        notesManager.getAvailableReceiptYears()
    }

    var currentYearStats: YearlyReceiptSummary? {
        notesManager.getReceiptStatistics(year: currentYear).first
    }

    private var monthlySummaries: [MonthlyReceiptSummary] {
        currentYearStats?.monthlySummaries ?? []
    }

    private var selectedMonthlySummary: MonthlyReceiptSummary? {
        if let selectedMonthName,
           let match = monthlySummaries.first(where: { $0.month == selectedMonthName }) {
            return match
        }
        return monthlySummaries.first
    }

    private var canSelectPreviousYear: Bool {
        guard let idx = availableYears.sorted().firstIndex(of: currentYear) else { return false }
        return idx > 0
    }

    private var canSelectNextYear: Bool {
        let ascending = availableYears.sorted()
        guard let idx = ascending.firstIndex(of: currentYear) else { return false }
        return idx < ascending.count - 1
    }

    private var currentYearTotal: Double {
        currentYearStats?.yearlyTotal ?? 0
    }

    private var currentYearReceiptCount: Int {
        currentYearStats?.monthlySummaries.reduce(0) { $0 + $1.receipts.count } ?? 0
    }

    private var averageMonthlySpend: Double {
        currentYearTotal / 12
    }

    private var previousYearTotal: Double? {
        notesManager.getReceiptStatistics(year: currentYear - 1).first?.yearlyTotal
    }

    private var yearOverYearDelta: Double? {
        guard let previousYearTotal, previousYearTotal > 0 else { return nil }
        return ((currentYearTotal - previousYearTotal) / previousYearTotal) * 100
    }

    private var topCategories: [CategoryStatWithPercentage] {
        Array(categoryBreakdown?.sortedCategories.prefix(3) ?? [])
    }

    private var allYearlyCategories: [CategoryStatWithPercentage] {
        categoryBreakdown?.sortedCategories ?? []
    }

    private var largestMonthlySummary: MonthlyReceiptSummary? {
        monthlySummaries.max { $0.monthlyTotal < $1.monthlyTotal }
    }

    private var quarterTotals: [(quarter: Int, total: Double)] {
        guard let stats = currentYearStats else {
            return (1...4).map { (quarter: $0, total: 0) }
        }

        let calendar = Calendar.current
        var totals = Array(repeating: 0.0, count: 4)
        for monthSummary in stats.monthlySummaries {
            let month = calendar.component(.month, from: monthSummary.monthDate)
            let quarterIdx = max(0, min(3, (month - 1) / 3))
            totals[quarterIdx] += monthSummary.monthlyTotal
        }

        return (0..<4).map { (quarter: $0 + 1, total: totals[$0]) }
    }

    private var selectedMonthCategorizedReceipts: [ReceiptStat] {
        guard let selectedMonthlySummary else { return [] }
        return getCategorizedReceiptsForMonth(selectedMonthlySummary.monthDate)
    }

    private var monthlyFilterCategories: [String] {
        let grouped = Dictionary(grouping: selectedMonthCategorizedReceipts, by: { $0.category })
        return grouped
            .map { category, receipts in
                (category: category, total: receipts.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.total > $1.total }
            .map { $0.category }
    }

    private var filteredMonthlyReceipts: [ReceiptStat] {
        guard let monthlyCategoryFilter else { return selectedMonthCategorizedReceipts }
        return selectedMonthCategorizedReceipts.filter { $0.category == monthlyCategoryFilter }
    }

    private var monthlyCategoryBreakdownStats: [CategoryStatWithPercentage] {
        let grouped = Dictionary(grouping: selectedMonthCategorizedReceipts, by: { $0.category })
        let monthTotal = selectedMonthlySummary?.monthlyTotal ?? 0

        return grouped
            .map { category, receipts in
                let total = receipts.reduce(0) { $0 + $1.amount }
                return CategoryStatWithPercentage(
                    category: category,
                    total: total,
                    count: receipts.count,
                    percentage: monthTotal > 0 ? (total / monthTotal) * 100 : 0,
                    receipts: receipts.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.total > $1.total }
    }

    private var displayedDailySummaries: [DailyReceiptSummary] {
        guard let selectedMonthlySummary else { return [] }
        guard monthlyCategoryFilter != nil else { return selectedMonthlySummary.dailySummaries }

        let calendar = Calendar.current
        return selectedMonthlySummary.dailySummaries.filter { daySummary in
            let dayStart = calendar.startOfDay(for: daySummary.dayDate)
            return filteredMonthlyReceipts.contains {
                calendar.startOfDay(for: $0.date) == dayStart
            }
        }
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.emailLightBackground
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.emailLightSurface
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color.emailLightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.emailLightTextSecondary
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color.emailLightTextSecondary.opacity(0.9)
    }

    private var mutedFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle
    }

    private var activeAccentColor: Color {
        colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent
    }

    private var neutralCategoryBarColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.56)
    }

    private var currentMonthSummaryTotal: Double {
        selectedMonthlySummary?.monthlyTotal ?? 0
    }

    private var currentMonthReceiptCount: Int {
        selectedMonthlySummary?.receipts.count ?? 0
    }

    private var currentMonthAveragePerDay: Double {
        guard let selectedMonthlySummary else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: selectedMonthlySummary.monthDate)?.count ?? 30
        guard days > 0 else { return selectedMonthlySummary.monthlyTotal }
        return selectedMonthlySummary.monthlyTotal / Double(days)
    }

    private var monthlyTotalsForYear: [Double] {
        monthlySummaries.map(\.monthlyTotal)
    }

    private var monthlyBaseline: (average: Double, stdDev: Double)? {
        let values = monthlyTotalsForYear
        guard values.count >= 2 else { return nil }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - avg
            return partial + (delta * delta)
        } / Double(values.count)
        return (avg, sqrt(max(variance, 0)))
    }

    private var yearlyAnomalyText: String? {
        guard let largestMonthlySummary,
              let baseline = monthlyBaseline,
              baseline.average > 0 else { return nil }

        let delta = largestMonthlySummary.monthlyTotal - baseline.average
        let percent = (delta / baseline.average) * 100
        guard percent >= 25 else { return nil }

        return "\(largestMonthlySummary.month) is \(String(format: "%.0f%%", percent)) above your monthly average."
    }

    var body: some View {
        ZStack {
            pageBackgroundColor.ignoresSafeArea()

            if showRecurringExpenses {
                RecurringExpenseStatsContent(searchText: searchText)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        if drilldownMode == .monthly {
                            monthlyContent
                        } else {
                            overviewContent
                        }
                    }
                    .padding(.top, isPopup ? 8 : 10)
                    .padding(.bottom, 18)
                }
            }
        }
        .onAppear {
            let calendar = Calendar.current
            if let initialMonthDate {
                let initialYear = calendar.component(.year, from: initialMonthDate)
                if availableYears.contains(initialYear) {
                    currentYear = initialYear
                } else if !availableYears.isEmpty {
                    currentYear = availableYears.first ?? calendar.component(.year, from: Date())
                }
            } else if !availableYears.isEmpty {
                currentYear = availableYears.first ?? calendar.component(.year, from: Date())
            }

            selectedMonthName = monthlySummaries.first?.month
            applyInitialMonthSelectionIfNeeded()
            loadCategoryBreakdown()
        }
        .onChange(of: currentYear) { _ in
            selectedMonthName = monthlySummaries.first?.month
            monthlyCategoryFilter = nil
            drilldownMode = .overview
            applyInitialMonthSelectionIfNeeded()
            loadCategoryBreakdown()
        }
        .onChange(of: notesManager.notes.count) { _ in
            categoryBreakdownDebounceTask?.cancel()
            categoryBreakdownDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if !Task.isCancelled {
                    loadCategoryBreakdown()
                }
            }
        }
        .sheet(item: $selectedReceipt) { receipt in
            if let note = notesManager.notes.first(where: { $0.id == receipt.noteId }) {
                ReceiptDetailSheet(
                    receipt: receipt,
                    note: note,
                    folderName: notesManager.getFolderName(for: note.folderId)
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(FontManager.geist(size: 34, weight: .light))
                        .foregroundColor(secondaryTextColor)
                    Text("Receipt note was not found.")
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(primaryTextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(pageBackgroundColor)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedCategory != nil },
            set: { if !$0 { selectedCategory = nil } }
        )) {
            if let category = selectedCategory {
                let sourceReceipts = drilldownMode == .monthly
                    ? selectedMonthCategorizedReceipts
                    : (categoryBreakdown?.allReceipts ?? [])
                let contextTitle = drilldownMode == .monthly
                    ? (selectedMonthlySummary?.month ?? "Month")
                    : String(currentYear)

                let categoryReceipts = sourceReceipts
                    .filter { $0.category == category }
                    .sorted { $0.date > $1.date }

                CategoryReceiptsListModal(
                    receipts: categoryReceipts,
                    categoryName: "\(category) - \(contextTitle)",
                    total: categoryReceipts.reduce(0) { $0 + $1.amount },
                    onReceiptTap: { receipt in
                        selectedCategory = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            selectedReceipt = receipt
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showMonthlyCategoryBreakdown) {
            monthlyCategoriesSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAllYearlyCategories) {
            allYearlyCategoriesSheet
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Yearly Summary

    private var overviewContent: some View {
        VStack(spacing: 12) {
            yearlyHeroCard()
            overviewTopCategoriesCard
            overviewMonthSnapshots
        }
    }

    private var overviewTopCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Categories")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                Spacer()

                Button(action: {
                    showAllYearlyCategories = true
                }) {
                    Text("All")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : primaryTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : mutedFillColor)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(allYearlyCategories.isEmpty)
            }

            if isLoadingCategories {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Categorizing receipts...")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                }
            } else if topCategories.isEmpty {
                Text("No category data yet")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(secondaryTextColor)
            } else {
                ForEach(topCategories, id: \.id) { category in
                    Button(action: {
                        selectedCategory = category.category
                    }) {
                        categoryProgressRow(category)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var allYearlyCategoriesSheet: some View {
        NavigationStack {
            ZStack {
                pageBackgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if allYearlyCategories.isEmpty {
                            emptyReceiptsCard
                        } else {
                            ForEach(allYearlyCategories, id: \.id) { category in
                                Button(action: {
                                    showAllYearlyCategories = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        selectedCategory = category.category
                                    }
                                }) {
                                    categoryProgressRow(category)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(Text(verbatim: "\(String(currentYear)) Categories"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showAllYearlyCategories = false
                    }
                    .font(FontManager.geist(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var monthlyCategoriesSheet: some View {
        NavigationStack {
            ZStack {
                pageBackgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if monthlyCategoryBreakdownStats.isEmpty {
                            emptyReceiptsCard
                        } else {
                            ForEach(monthlyCategoryBreakdownStats, id: \.id) { category in
                                Button(action: {
                                    showMonthlyCategoryBreakdown = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        selectedCategory = category.category
                                    }
                                }) {
                                    categoryProgressRow(category)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(Text(verbatim: "\((selectedMonthlySummary?.month ?? "Month")) Categories"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showMonthlyCategoryBreakdown = false
                    }
                    .font(FontManager.geist(size: 14, weight: .semibold))
                }
            }
        }
    }

    private func categoryProgressRow(_ category: CategoryStatWithPercentage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(category.category)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Spacer()

                Text(category.formattedAmount)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(primaryTextColor)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let fill = max(8, width * (category.percentage / 100))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(mutedFillColor)
                    Capsule()
                        .fill(neutralCategoryBarColor)
                        .frame(width: fill)
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1f%%", category.percentage))
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(tertiaryTextColor)
        }
    }

    private var overviewMonthSnapshots: some View {
        VStack(alignment: .leading, spacing: 10) {
            if monthlySummaries.isEmpty {
                emptyReceiptsCard
                    .padding(.horizontal, 16)
            } else {
                ForEach(Array(monthlySummaries.enumerated()), id: \.element.id) { _, monthlySummary in
                    monthSnapshotCard(monthlySummary)
                }
            }
        }
    }

    private func monthSnapshotCard(_ monthlySummary: MonthlyReceiptSummary) -> some View {
        Button(action: {
            selectedMonthName = monthlySummary.month
            monthlyCategoryFilter = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                drilldownMode = .monthly
            }
        }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthlySummary.month)
                        .font(FontManager.geist(size: 20, weight: .semibold))
                        .foregroundColor(primaryTextColor)

                    Text("\(monthlySummary.receipts.count) receipts • Avg \(CurrencyParser.formatAmountNoDecimals(monthAveragePerDay(for: monthlySummary)))/day")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                    .font(FontManager.geist(size: 24, weight: .bold))
                    .foregroundColor(primaryTextColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardBorderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }

    // MARK: - Yearly

    private var yearlyContent: some View {
        VStack(spacing: 12) {
            yearNavigator
            quarterPerformanceCard
            yearlyInsightsCard
            yearlyMonthEntryPointsCard
        }
    }

    private var yearNavigator: some View {
        HStack {
            Button(action: { selectPreviousYear() }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(canSelectPreviousYear ? secondaryTextColor : tertiaryTextColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(mutedFillColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSelectPreviousYear)

            Spacer()

            Text(String(currentYear))
                .font(FontManager.geist(size: 26, weight: .bold))
                .foregroundColor(primaryTextColor)

            Spacer()

            Button(action: { selectNextYear() }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(canSelectNextYear ? secondaryTextColor : tertiaryTextColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(mutedFillColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSelectNextYear)
        }
    }

    private var quarterPerformanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quarter Performance")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            let maxTotal = max(quarterTotals.map(\.total).max() ?? 0, 1)
            ForEach(quarterTotals, id: \.quarter) { quarter in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Q\(quarter.quarter)")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                        Spacer()
                        Text(CurrencyParser.formatAmountNoDecimals(quarter.total))
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(secondaryTextColor)
                    }

                    GeometryReader { geometry in
                        let fill = max(10, (geometry.size.width * (quarter.total / maxTotal)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(mutedFillColor)
                            Capsule()
                                .fill(quarter.quarter == 1 ? primaryTextColor : primaryTextColor.opacity(0.6))
                                .frame(width: fill)
                        }
                    }
                    .frame(height: 9)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var yearlyInsightsCard: some View {
        HStack(spacing: 10) {
            insightMiniCard(
                title: "Biggest Month",
                value: largestMonthlySummary?.month ?? "N/A",
                detail: largestMonthlySummary.map { CurrencyParser.formatAmountNoDecimals($0.monthlyTotal) } ?? "-"
            )

            insightMiniCard(
                title: "Total Receipts",
                value: "\(currentYearReceiptCount)",
                detail: "in \(currentYear)"
            )
        }
        .padding(.horizontal, 16)
    }

    private func insightMiniCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(secondaryTextColor)
            Text(value)
                .font(FontManager.geist(size: 20, weight: .bold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private var yearlyMonthEntryPointsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Month Entry Points")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            if monthlySummaries.isEmpty {
                Text("No months available for this year")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(secondaryTextColor)
            } else {
                ForEach(Array(monthlySummaries.prefix(6).enumerated()), id: \.element.id) { _, monthlySummary in
                    HStack {
                        Text(monthlySummary.month)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                        Spacer()
                        Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(mutedFillColor)
                    )
                    .onTapGesture {
                        selectedMonthName = monthlySummary.month
                        monthlyCategoryFilter = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            drilldownMode = .monthly
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Monthly

    private var monthlyContent: some View {
        VStack(spacing: 12) {
            monthlyBackHeader
            monthlySummaryCard
            monthlyCategoryFilterChips
            monthlyDailyCards
        }
    }

    private var monthlyBackHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    drilldownMode = .overview
                    monthlyCategoryFilter = nil
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                    Text("Year Summary")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                }
                .foregroundColor(secondaryTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(mutedFillColor)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var monthlyNavigator: some View {
        HStack {
            Button(action: { shiftSelectedMonth(by: 1) }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(canShiftToOlderMonth ? secondaryTextColor : tertiaryTextColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(mutedFillColor))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canShiftToOlderMonth)

            Spacer()

            Text(selectedMonthlySummary?.month ?? "No Month")
                .font(FontManager.geist(size: 24, weight: .bold))
                .foregroundColor(primaryTextColor)

            Spacer()

            Button(action: { shiftSelectedMonth(by: -1) }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(canShiftToNewerMonth ? secondaryTextColor : tertiaryTextColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(mutedFillColor))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canShiftToNewerMonth)
        }
    }

    private var monthlySummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            monthlyNavigator

            HStack(spacing: 6) {
                Text("\(currentMonthReceiptCount) receipts")
                Text("•")
                Text("Avg \(CurrencyParser.formatAmountNoDecimals(currentMonthAveragePerDay))/day")
            }
            .font(FontManager.geist(size: 13, weight: .medium))
            .foregroundColor(secondaryTextColor)

            HStack {
                Text(CurrencyParser.formatAmountNoDecimals(currentMonthSummaryTotal))
                    .font(FontManager.geist(size: 32, weight: .bold))
                    .foregroundColor(primaryTextColor)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        showMonthlyCategoryBreakdown = true
                    }) {
                        Text("Categories")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .black : primaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(colorScheme == .dark ? Color.white : mutedFillColor)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedMonthCategorizedReceipts.isEmpty)

                    if onAddReceipt != nil {
                        addReceiptCircleButton
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var monthlyCategoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                monthlyFilterChip(title: "All", isActive: monthlyCategoryFilter == nil) {
                    monthlyCategoryFilter = nil
                }

                ForEach(monthlyFilterCategories, id: \.self) { category in
                    monthlyFilterChip(title: category, isActive: monthlyCategoryFilter == category) {
                        monthlyCategoryFilter = category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func monthlyFilterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(
                    isActive
                        ? (colorScheme == .dark ? .black : .white)
                        : secondaryTextColor
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(
                            isActive
                                ? (colorScheme == .dark ? Color.white : primaryTextColor)
                                : mutedFillColor
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var monthlyDailyCards: some View {
        VStack(spacing: 12) {
            if displayedDailySummaries.isEmpty {
                emptyReceiptsCard
                    .padding(.horizontal, 16)
            } else {
                ForEach(displayedDailySummaries, id: \.id) { dailySummary in
                    DailyReceiptCard(
                        dailySummary: dailySummary,
                        categorizedReceipts: filteredMonthlyReceipts,
                        onReceiptTap: { receipt in
                            selectedReceipt = receipt
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Shared Cards

    private func yearlyHeroCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            yearNavigator

            Text(CurrencyParser.formatAmountNoDecimals(currentYearTotal))
                .font(FontManager.geist(size: 40, weight: .bold))
                .foregroundColor(primaryTextColor)

            HStack(spacing: 6) {
                Text("\(currentYearReceiptCount) receipts")
                Text("•")
                Text("Avg \(CurrencyParser.formatAmountNoDecimals(averageMonthlySpend))/month")
            }
            .font(FontManager.geist(size: 13, weight: .medium))
            .foregroundColor(secondaryTextColor)

            if let yearlyAnomalyText {
                anomalyCallout(text: yearlyAnomalyText)
            }

            if let yearOverYearDelta {
                let isUp = yearOverYearDelta >= 0
                let trendColor: Color = isUp ? .red : .green
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(FontManager.geist(size: 10, weight: .semibold))
                        Text(String(format: "%.1f%% vs %d", abs(yearOverYearDelta), currentYear - 1))
                            .font(FontManager.geist(size: 11, weight: .semibold))
                    }
                    .foregroundColor(trendColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(trendColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    )

                    Spacer()

                    if onAddReceipt != nil {
                        addReceiptCircleButton
                    }
                }
            } else if onAddReceipt != nil {
                HStack {
                    Spacer()
                    addReceiptCircleButton
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var addReceiptCircleButton: some View {
        Button(action: {
            onAddReceipt?()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(mutedFillColor)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Add receipt")
    }

    private func anomalyCallout(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(FontManager.geist(size: 10, weight: .semibold))
            Text(text)
                .font(FontManager.geist(size: 11, weight: .medium))
                .lineLimit(2)
        }
        .foregroundColor(colorScheme == .dark ? Color.orange.opacity(0.95) : Color.orange.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.orange.opacity(0.18) : Color.orange.opacity(0.1))
        )
    }

    private var emptyReceiptsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(FontManager.geist(size: 30, weight: .light))
                .foregroundColor(tertiaryTextColor)
            Text("No receipts found")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private func selectPreviousYear() {
        let ascending = availableYears.sorted()
        guard let idx = ascending.firstIndex(of: currentYear), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentYear = ascending[idx - 1]
        }
    }

    private func selectNextYear() {
        let ascending = availableYears.sorted()
        guard let idx = ascending.firstIndex(of: currentYear), idx < ascending.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentYear = ascending[idx + 1]
        }
    }

    private func loadCategoryBreakdown() {
        guard !availableYears.isEmpty else {
            categoryBreakdown = nil
            isLoadingCategories = false
            return
        }

        isLoadingCategories = true
        Task {
            let breakdown = await notesManager.getCategoryBreakdown(for: currentYear)
            await MainActor.run {
                categoryBreakdown = breakdown
                isLoadingCategories = false
            }
        }
    }

    private func monthAveragePerDay(for monthSummary: MonthlyReceiptSummary) -> Double {
        let days = Calendar.current.range(of: .day, in: .month, for: monthSummary.monthDate)?.count ?? 30
        guard days > 0 else { return monthSummary.monthlyTotal }
        return monthSummary.monthlyTotal / Double(days)
    }

    private var selectedMonthIndex: Int? {
        guard let selectedMonthlySummary else { return nil }
        return monthlySummaries.firstIndex(where: { $0.month == selectedMonthlySummary.month })
    }

    private var canShiftToOlderMonth: Bool {
        guard let selectedMonthIndex else { return false }
        return selectedMonthIndex < monthlySummaries.count - 1
    }

    private var canShiftToNewerMonth: Bool {
        guard let selectedMonthIndex else { return false }
        return selectedMonthIndex > 0
    }

    private func shiftSelectedMonth(by offset: Int) {
        guard let selectedMonthIndex else { return }
        let newIndex = selectedMonthIndex + offset
        guard newIndex >= 0 && newIndex < monthlySummaries.count else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonthName = monthlySummaries[newIndex].month
            monthlyCategoryFilter = nil
        }
    }

    private func getCategorizedReceiptsForMonth(_ monthDate: Date) -> [ReceiptStat] {
        guard let breakdown = categoryBreakdown else { return [] }

        let calendar = Calendar.current
        let month = calendar.component(.month, from: monthDate)
        let year = calendar.component(.year, from: monthDate)

        return breakdown.allReceipts.filter { receipt in
            let receiptMonth = calendar.component(.month, from: receipt.date)
            let receiptYear = calendar.component(.year, from: receipt.date)
            return receiptMonth == month && receiptYear == year
        }
    }

    private func applyInitialMonthSelectionIfNeeded() {
        guard let initialMonthDate else { return }

        let calendar = Calendar.current
        let initialYear = calendar.component(.year, from: initialMonthDate)
        guard initialYear == currentYear else { return }

        if let month = monthlySummaries.first(where: {
            calendar.isDate($0.monthDate, equalTo: initialMonthDate, toGranularity: .month)
        }) {
            selectedMonthName = month.month
            drilldownMode = .monthly
        }
    }

}

// MARK: - Recurring Expense Stats Content

struct RecurringExpenseStatsContent: View {
    private enum RecurringBucket {
        case dueNow
        case upcoming
        case paused

        var title: String {
            switch self {
            case .dueNow:
                return "Due Now"
            case .upcoming:
                return "Upcoming"
            case .paused:
                return "Paused"
            }
        }

        var subtitle: String {
            switch self {
            case .dueNow:
                return ""
            case .upcoming:
                return ""
            case .paused:
                return ""
            }
        }

        var emptyState: String {
            switch self {
            case .dueNow:
                return ""
            case .upcoming:
                return "No upcoming recurring charges."
            case .paused:
                return ""
            }
        }
    }

    @State private var recurringExpenses: [RecurringExpense] = []
    @State private var isLoading = true
    @State private var selectedExpense: RecurringExpense? = nil
    @State private var showEditSheet = false
    @State private var hasLoadedData = false
    @State private var quickFocusBucket: RecurringBucket? = nil
    @Environment(\.colorScheme) var colorScheme

    var searchText: String? = nil
    var onAddRecurring: (() -> Void)? = nil

    private var filteredRecurringExpenses: [RecurringExpense] {
        guard let searchText = searchText, !searchText.isEmpty else {
            return recurringExpenses
        }
        return recurringExpenses.filter { expense in
            expense.title.localizedCaseInsensitiveContains(searchText) ||
            (expense.category?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (expense.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var activeExpenses: [RecurringExpense] {
        filteredRecurringExpenses
            .filter { $0.isActive }
            .sorted { $0.nextOccurrence < $1.nextOccurrence }
    }

    private var pausedExpenses: [RecurringExpense] {
        filteredRecurringExpenses
            .filter { !$0.isActive }
            .sorted { $0.nextOccurrence < $1.nextOccurrence }
    }

    private var dueNowExpenses: [RecurringExpense] {
        activeExpenses.filter { isDueNow($0.nextOccurrence) }
    }

    private var upcomingExpenses: [RecurringExpense] {
        activeExpenses.filter { !isDueNow($0.nextOccurrence) }
    }

    private var next7DayTotal: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return activeExpenses
            .filter { $0.nextOccurrence <= cutoff }
            .reduce(0) { partial, expense in
                partial + Double(truncating: expense.amount as NSDecimalNumber)
            }
    }

    private var next30DayTotal: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        return activeExpenses
            .filter { $0.nextOccurrence <= cutoff }
            .reduce(0) { partial, expense in
                partial + Double(truncating: expense.amount as NSDecimalNumber)
            }
    }

    private var monthlyTotal: Double {
        activeExpenses.reduce(0) { total, expense in
            total + Double(truncating: expense.amount as NSDecimalNumber)
        }
    }

    private var yearlyProjection: Double {
        monthlyTotal * 12
    }

    private var activeCount: Int {
        activeExpenses.count
    }

    private var dueNowCount: Int {
        dueNowExpenses.count
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color.emailLightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.emailLightTextSecondary
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.emailLightSurface
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightSectionCard
    }

    private var controlButtonFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.emailLightChipIdle
    }

    private func recurringCardTitle(_ title: String) -> some View {
        Text(title)
            .font(FontManager.geist(size: 12, weight: .semibold))
            .foregroundColor(secondaryTextColor)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .padding(.vertical, 24)
            } else if filteredRecurringExpenses.isEmpty {
                recurringEmptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        recurringControlCard

                        if quickFocusBucket == nil || quickFocusBucket == .dueNow {
                            recurringBucketCard(bucket: .dueNow, expenses: dueNowExpenses)
                        }
                        if quickFocusBucket == nil || quickFocusBucket == .upcoming {
                            recurringBucketCard(bucket: .upcoming, expenses: upcomingExpenses)
                        }
                        if quickFocusBucket == nil || quickFocusBucket == .paused {
                            recurringBucketCard(bucket: .paused, expenses: pausedExpenses)
                        }

                        Spacer(minLength: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            selectedExpense = nil
            refreshRecurringExpenses()
        }) {
            if let expense = selectedExpense {
                RecurringExpenseEditView(expense: expense, isPresented: $showEditSheet)
                    .presentationBg()
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(colorScheme == .dark ? Color.white : Color.black)

                    Text("Loading expense details...")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            }
        }
        .onAppear {
            if !hasLoadedData {
                loadRecurringExpenses()
            }
        }
    }

    private var recurringControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                recurringCardTitle("Recurring Expenses")
                Spacer()
                if let onAddRecurring {
                    Button(action: onAddRecurring) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(controlButtonFillColor)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Add recurring expense")
                } else {
                    Text("\(dueNowCount) due")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(controlButtonFillColor)
                        )
                }
            }

            HStack(spacing: 8) {
                recurringSummaryTile(label: "Monthly", value: CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                recurringSummaryTile(label: "Yearly", value: CurrencyParser.formatAmountNoDecimals(yearlyProjection))
                recurringSummaryTile(label: "Active", value: "\(activeCount)")
            }

            HStack(spacing: 8) {
                recurringSummaryTile(label: "7d impact", value: CurrencyParser.formatAmountNoDecimals(next7DayTotal))
                recurringSummaryTile(label: "30d impact", value: CurrencyParser.formatAmountNoDecimals(next30DayTotal))
            }

            HStack(spacing: 8) {
                quickActionChip(
                    title: "Due now",
                    isActive: quickFocusBucket == .dueNow,
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            quickFocusBucket = quickFocusBucket == .dueNow ? nil : .dueNow
                        }
                    }
                )

                quickActionChip(
                    title: "Upcoming",
                    isActive: quickFocusBucket == .upcoming,
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            quickFocusBucket = quickFocusBucket == .upcoming ? nil : .upcoming
                        }
                    }
                )

                quickActionChip(
                    title: "Paused",
                    isActive: quickFocusBucket == .paused,
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            quickFocusBucket = quickFocusBucket == .paused ? nil : .paused
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private func recurringSummaryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(secondaryTextColor)
            Text(value)
                .font(FontManager.geist(size: 17, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rowFillColor)
        )
    }

    private func quickActionChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(
                    isActive
                        ? (colorScheme == .dark ? .black : .white)
                        : primaryTextColor
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(
                            isActive
                                ? (colorScheme == .dark ? Color.white : Color.black)
                                : controlButtonFillColor
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func recurringBucketCard(bucket: RecurringBucket, expenses: [RecurringExpense]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                recurringCardTitle(bucket.title)
                Text("· \(expenses.count)")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                Spacer()
            }

            if !bucket.subtitle.isEmpty {
                Text(bucket.subtitle)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }

            if expenses.isEmpty, !bucket.emptyState.isEmpty {
                Text(bucket.emptyState)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(expenses) { expense in
                        recurringBucketRow(expense)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private func recurringBucketRow(_ expense: RecurringExpense) -> some View {
        let due = dueBadge(for: expense)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(expense.title)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(expense.frequency.displayName)
                    if let category = expense.category, !category.isEmpty {
                        Text("• \(category)")
                    }
                }
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(secondaryTextColor)

                Text("Next \(formatInstanceDate(expense.nextOccurrence))")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(expense.formattedAmount)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Text("\(expense.formattedYearlyAmount)/yr")
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)

                Text(due.text)
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(due.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(due.background)
                    )
            }

            Menu {
                Button(action: { presentEditSheet(for: expense) }) {
                    Label("Edit Recurring", systemImage: "pencil")
                }

                Button(action: {
                    Task {
                        try? await RecurringExpenseService.shared.toggleRecurringExpenseActive(id: expense.id, isActive: !expense.isActive)
                        await MainActor.run {
                            refreshRecurringExpenses()
                        }
                    }
                }) {
                    Label(expense.isActive ? "Pause" : "Resume", systemImage: expense.isActive ? "pause.circle" : "play.circle")
                }

                Button(role: .destructive, action: {
                    Task {
                        try? await RecurringExpenseService.shared.deleteRecurringExpense(id: expense.id)
                        await MainActor.run {
                            refreshRecurringExpenses()
                        }
                    }
                }) {
                    Label("Delete Recurring", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(controlButtonFillColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(rowFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cardBorderColor.opacity(0.7), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            presentEditSheet(for: expense)
        }
    }

    private var recurringEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "repeat.circle.dashed")
                .font(FontManager.geist(size: 34, weight: .light))
                .foregroundColor(secondaryTextColor)

            Text("No recurring expenses")
                .font(FontManager.geist(size: 18, weight: .medium))
                .foregroundColor(primaryTextColor)

            Text("Use the + button to create your first recurring bill.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }

    private func presentEditSheet(for expense: RecurringExpense) {
        selectedExpense = expense
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            showEditSheet = true
        }
    }

    private func loadRecurringExpenses() {
        isLoading = true
        Task {
            do {
                let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
                await MainActor.run {
                    recurringExpenses = expenses.sorted { $0.nextOccurrence < $1.nextOccurrence }
                    isLoading = false
                    hasLoadedData = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("❌ Error loading recurring expenses: \(error.localizedDescription)")
            }
        }
    }

    private func refreshRecurringExpenses() {
        hasLoadedData = false
        loadRecurringExpenses()
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private func isDueNow(_ date: Date) -> Bool {
        daysUntil(date) <= 3
    }

    private func dueBadge(for expense: RecurringExpense) -> (text: String, background: Color, foreground: Color) {
        if !expense.isActive {
            return (
                "Paused",
                colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle,
                secondaryTextColor
            )
        }

        let days = daysUntil(expense.nextOccurrence)
        if days < 0 {
            return (
                "\(abs(days))d overdue",
                colorScheme == .dark ? Color.red.opacity(0.22) : Color.red.opacity(0.12),
                colorScheme == .dark ? Color.red.opacity(0.95) : Color.red.opacity(0.9)
            )
        }
        if days == 0 {
            return (
                "Due today",
                colorScheme == .dark ? Color.red.opacity(0.22) : Color.red.opacity(0.12),
                colorScheme == .dark ? Color.red.opacity(0.95) : Color.red.opacity(0.9)
            )
        }
        if days == 1 {
            return (
                "Tomorrow",
                colorScheme == .dark ? Color.orange.opacity(0.22) : Color.orange.opacity(0.14),
                colorScheme == .dark ? Color.orange.opacity(0.95) : Color.orange.opacity(0.9)
            )
        }
        if days <= 3 {
            return (
                "In \(days)d",
                colorScheme == .dark ? Color.orange.opacity(0.22) : Color.orange.opacity(0.14),
                colorScheme == .dark ? Color.orange.opacity(0.95) : Color.orange.opacity(0.9)
            )
        }
        return (
            formatUpcomingDate(expense.nextOccurrence),
            colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle,
            secondaryTextColor
        )
    }

    private func formatInstanceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        let components = calendar.dateComponents([.day], from: today, to: targetDate)
        let daysFromNow = components.day ?? 0

        if daysFromNow == 0 {
            return "Today"
        } else if daysFromNow == 1 {
            return "Tomorrow"
        } else if daysFromNow > 1 && daysFromNow <= 7 {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatUpcomingDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        let components = calendar.dateComponents([.day], from: today, to: targetDate)
        let daysFromNow = components.day ?? 0

        if daysFromNow == 0 {
            return "Today"
        } else if daysFromNow == 1 {
            return "Tomorrow"
        } else if daysFromNow > 1 && daysFromNow <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let icon: String
    let valueColor: Color?
    let isBold: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.headline)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(valueColor ?? .primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
        .cornerRadius(8)
    }
}

#Preview {
    ReceiptStatsView()
}
