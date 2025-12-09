import SwiftUI
import CoreLocation

struct SpendingAndETAWidget: View {
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    var isVisible: Bool = true

    @State private var showReceiptStats = false
    @State private var upcomingRecurringExpenses: [(title: String, amount: Double, date: Date)] = []

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
            guard let stats = currentYearStats else { return }
            let calendar = Calendar.current
            let now = Date()
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)

            // Get all receipts for current month and year
            var monthReceipts: [ReceiptStat] = []
            for monthlySummary in stats.monthlySummaries {
                let month = calendar.component(.month, from: monthlySummary.monthDate)
                let year = calendar.component(.year, from: monthlySummary.monthDate)
                if month == currentMonth && year == currentYear {
                    monthReceipts.append(contentsOf: monthlySummary.receipts)
                }
            }

            // Categorize receipts using the service
            var categoryTotals: [String: Double] = [:]
            for receipt in monthReceipts {
                let category = await ReceiptCategorizationService.shared.categorizeReceipt(receipt.title)
                let current = categoryTotals[category] ?? 0
                categoryTotals[category] = current + receipt.amount
            }

            // Convert to sorted array with percentages
            let total = categoryTotals.values.reduce(0, +)
            let result = categoryTotals
                .map { (category: $0.key, amount: $0.value, percentage: total > 0 ? ($0.value / total) * 100 : 0) }
                .sorted { $0.amount > $1.amount }
                .prefix(5)
                .map { $0 }

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
            loadUpcomingRecurringExpenses()
        }
        .onChange(of: notesManager.notes.count) { _ in
            updateCategoryBreakdown()
            loadUpcomingRecurringExpenses()
        }
        .sheet(isPresented: $showReceiptStats) {
            ReceiptStatsView(isPopup: true)
                .presentationDetents([.large])
        }
    }

    private func spendingCard() -> some View {
        Button(action: { showReceiptStats = true }) {
            VStack(alignment: .leading, spacing: 12) {
                // Monthly spending amount and % on same line
                HStack(alignment: .bottom, spacing: 8) {
                    Text(CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))

                    // Month over month percentage
                    Text(String(format: "%.0f%% %@ than last month", monthOverMonthPercentage.percentage, monthOverMonthPercentage.isIncrease ? "more" : "less"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        .offset(y: -3)

                    Spacer()
                }

                // Categories - below % text
                topCategoryView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .cornerRadius(12)
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
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

    private func formatExpenseDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expenseDay = calendar.startOfDay(for: date)

        if expenseDay == today {
            return "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), expenseDay == tomorrow {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func loadUpcomingRecurringExpenses() {
        Task {
            do {
                let recurringExpenses = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
                let calendar = Calendar.current
                let now = Date()
                var expenses: [(title: String, amount: Double, date: Date)] = []

                // Get next 7 days
                let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now)!

                for expense in recurringExpenses {
                    let instances = try await RecurringExpenseService.shared.fetchInstances(for: expense.id)

                    for instance in instances {
                        let instanceDay = calendar.startOfDay(for: instance.occurrenceDate)
                        let nowStart = calendar.startOfDay(for: now)
                        let sevenDaysStart = calendar.startOfDay(for: sevenDaysFromNow)

                        // Check if instance is within next 7 days and is pending
                        if instanceDay >= nowStart && instanceDay <= sevenDaysStart {
                            if instance.status == .pending {
                                expenses.append((title: expense.title, amount: Double(truncating: expense.amount as NSDecimalNumber), date: instance.occurrenceDate))
                            }
                        }
                    }
                }

                // Sort by date ascending (earliest first)
                expenses.sort { $0.date < $1.date }

                await MainActor.run {
                    upcomingRecurringExpenses = expenses
                }
            } catch {
                print("Error loading recurring expenses: \(error)")
            }
        }
    }

    private var topCategoryView: some View {
        Group {
            if !categoryBreakdown.isEmpty {
                HStack(spacing: 4) {
                    ForEach(categoryBreakdown.prefix(3), id: \.category) { category in
                        HStack(spacing: 2) {
                            Text(categoryIcon(category.category))
                                .font(.system(size: 11))

                            VStack(alignment: .leading, spacing: 0) {
                                Text(category.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(String(format: "%.0f%%", category.percentage))
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .cornerRadius(4)
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
