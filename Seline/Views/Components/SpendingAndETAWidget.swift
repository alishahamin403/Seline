import SwiftUI
import CoreLocation

struct SpendingAndETAWidget: View {
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    var isVisible: Bool = true
    var onAddReceipt: (() -> Void)? = nil
    var onAddReceiptFromGallery: (() -> Void)? = nil

    @State private var showReceiptStats = false

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
        guard let stats = currentYearStats else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let previousMonth = currentMonth - 1
        let previousYear = previousMonth <= 0 ? calendar.component(.year, from: now) - 1 : calendar.component(.year, from: now)
        let adjustedPreviousMonth = previousMonth <= 0 ? 12 : previousMonth

        return stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let year = calendar.component(.year, from: summary.monthDate)
            return month == adjustedPreviousMonth && year == previousYear
        }.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var monthOverMonthPercentage: (percentage: Double, isIncrease: Bool) {
        guard previousMonthTotal > 0 else { return (0, false) }
        let change = ((monthlyTotal - previousMonthTotal) / previousMonthTotal) * 100
        return (abs(change), change >= 0)
    }

    @State private var categoryBreakdownCache: [(category: String, amount: Double, percentage: Double)] = []

    private var categoryBreakdown: [(category: String, amount: Double, percentage: Double)] {
        return categoryBreakdownCache
    }

    private func categoryIcon(_ category: String) -> String {
        return CategoryIconProvider.icon(for: category)
    }

    private func categoryColor(_ category: String) -> Color {
        return CategoryIconProvider.color(for: category)
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
                // Update widget with spending data
                self.updateWidgetWithSpendingData()
            }
        }
    }

    private func updateWidgetWithSpendingData() {
        // Write spending data to shared UserDefaults for widget display
        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(monthlyTotal, forKey: "widgetMonthlySpending")
            userDefaults.set(monthOverMonthPercentage.percentage, forKey: "widgetMonthOverMonthPercentage")
            userDefaults.set(monthOverMonthPercentage.isIncrease, forKey: "widgetIsSpendingIncreasing")
            userDefaults.set(dailyTotal, forKey: "widgetDailySpending")
        }
    }

    var body: some View {
        spendingCard()
        .onAppear {
            updateCategoryBreakdown()
        }
        .onChange(of: notesManager.notes.count) { _ in
            updateCategoryBreakdown()
        }
        .sheet(isPresented: $showReceiptStats) {
            ReceiptStatsView(isPopup: true)
                .presentationDetents([.large])
        }
    }

    private func spendingCard() -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                // Monthly spending amount and % on same line
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Month")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }

                    // Month over month percentage
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: monthOverMonthPercentage.isIncrease ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(String(format: "%.0f%%", monthOverMonthPercentage.percentage))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(monthOverMonthPercentage.isIncrease ? Color.red.opacity(0.85) : Color.green.opacity(0.85))

                        Text("vs last month")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    }
                    .padding(.leading, 8)

                    Spacer()
                }

                // Categories - below % text
                topCategoryView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                showReceiptStats = true
            }

            // Add receipt button (camera/gallery) - Menu with options
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .allowsParentScrolling()
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    HStack(spacing: 8) {
                        ForEach(categoryBreakdown.prefix(3), id: \.category) { category in
                            // Compact category pill
                            HStack(spacing: 6) {
                                // Category icon with background
                                ZStack {
                                    Circle()
                                        .fill(categoryColor(category.category).opacity(0.2))
                                        .frame(width: 20, height: 20)
                                    
                                    Text(categoryIcon(category.category))
                                        .font(.system(size: 10))
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.category)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)

                                    Text(String(format: "%.0f%%", category.percentage))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
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
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Spacer()

                    Text(formatExpenseDate(note.dateCreated ?? Date()))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                    if let amount = extractAmount(from: note.content ?? "") {
                        Text(CurrencyParser.formatAmountNoDecimals(amount))
                            .font(.system(size: 10, weight: .semibold))
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

#Preview {
    SpendingAndETAWidget(isVisible: true)
        .padding()
}
