import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    let categoryBreakdown: YearlyCategoryBreakdown
    @State private var expandedMonth: Int? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Spending")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("\(categoryBreakdown.year) Overview")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()
                .opacity(0.3)

            // Monthly breakdown
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(getMonthlySummaries().enumerated()), id: \.element.month) { index, monthlySummary in
                        MonthlyBreakdownCard(
                            monthlySummary: monthlySummary,
                            isExpanded: expandedMonth == index,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedMonth = expandedMonth == index ? nil : index
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private func getMonthlySummaries() -> [(month: Int, total: Double, categories: [CategoryStatWithPercentage])] {
        // Group receipts by month and calculate totals
        var monthlyData: [Int: (total: Double, categoryTotals: [String: (amount: Double, count: Int, receipts: [ReceiptStat])])] = [:]

        for receipt in categoryBreakdown.allReceipts {
            let calendar = Calendar.current
            let month = calendar.component(.month, from: receipt.date)

            if monthlyData[month] == nil {
                monthlyData[month] = (total: 0, categoryTotals: [:])
            }

            monthlyData[month]?.total += receipt.amount

            // Group by category
            if let categoryIndex = categoryBreakdown.categories.firstIndex(where: { $0.category == receipt.category }) {
                let category = categoryBreakdown.categories[categoryIndex].category

                if monthlyData[month]?.categoryTotals[category] == nil {
                    monthlyData[month]?.categoryTotals[category] = (amount: 0, count: 0, receipts: [])
                }

                monthlyData[month]?.categoryTotals[category]?.amount += receipt.amount
                monthlyData[month]?.categoryTotals[category]?.count += 1
                monthlyData[month]?.categoryTotals[category]?.receipts.append(receipt)
            }
        }

        // Convert to array and sort by month descending (latest first)
        return monthlyData.sorted { $0.key > $1.key }.map { month, data in
            let categoryStats = data.categoryTotals.map { category, stats in
                CategoryStatWithPercentage(
                    category: category,
                    total: stats.amount,
                    count: stats.count,
                    percentage: data.total > 0 ? (stats.amount / data.total) * 100 : 0,
                    receipts: stats.receipts
                )
            }.sorted { $0.total > $1.total }

            return (month: month, total: data.total, categories: categoryStats)
        }
    }
}

// MARK: - Monthly Breakdown Card

struct MonthlyBreakdownCard: View {
    let monthlySummary: (month: Int, total: Double, categories: [CategoryStatWithPercentage])
    let isExpanded: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var monthName: String {
        let calendar = Calendar.current
        let dateComponents = DateComponents(year: Calendar.current.component(.year, from: Date()), month: monthlySummary.month)
        let date = calendar.date(from: dateComponents) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private var dailyAverage: Double {
        let calendar = Calendar.current
        let dateComponents = DateComponents(year: Calendar.current.component(.year, from: Date()), month: monthlySummary.month)
        let date = calendar.date(from: dateComponents) ?? Date()
        let range = calendar.range(of: .day, in: .month, for: date) ?? 1..<2
        let daysInMonth = range.count
        return monthlySummary.total / Double(daysInMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onTap) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(monthName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(String(format: "Avg $%.2f/day", dailyAverage))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(CurrencyParser.formatAmount(monthlySummary.total))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }

                    // Stacked bar chart
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(monthlySummary.categories, id: \.category) { category in
                                let width = (category.total / monthlySummary.total) * geometry.size.width
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorForCategory(category.category))
                                    .frame(width: width)
                            }
                        }
                        .cornerRadius(4)
                    }
                    .frame(height: 6)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
                )
            }

            // Expanded details
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 0)

                    VStack(spacing: 10) {
                        ForEach(monthlySummary.categories, id: \.category) { category in
                            CategoryDetailRow(category: category)
                        }
                    }
                    .padding(14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
                )
            }
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574
        case "Services":
            return Color(red: 0.639, green: 0.608, blue: 0.553) // #A39B8D
        case "Transportation":
            return Color(red: 0.627, green: 0.533, blue: 0.408) // #A08968
        case "Healthcare":
            return Color(red: 0.831, green: 0.710, blue: 0.627) // #D4B5A0
        case "Entertainment":
            return Color(red: 0.722, green: 0.627, blue: 0.537) // #B8A089
        case "Shopping":
            return Color(red: 0.792, green: 0.722, blue: 0.659) // #C9B8A8
        default:
            return Color.gray
        }
    }
}

// MARK: - Category Detail Row

struct CategoryDetailRow: View {
    let category: CategoryStatWithPercentage
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.category)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    ProgressView(value: category.percentage / 100)
                        .frame(height: 4)
                        .tint(colorForCategory(category.category))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(category.formattedAmount)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(category.formattedPercentage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                }
            }

            if !category.receipts.isEmpty {
                VStack(spacing: 6) {
                    Divider()
                        .opacity(0.2)
                        .padding(.vertical, 8)

                    ForEach(Array(category.receipts.prefix(3).enumerated()), id: \.element.id) { index, receipt in
                        ReceiptRow(receipt: receipt)
                    }

                    if category.receipts.count > 3 {
                        Text("+\(category.receipts.count - 3) more")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.gray.opacity(0.05))
        )
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574
        case "Services":
            return Color(red: 0.639, green: 0.608, blue: 0.553) // #A39B8D
        case "Transportation":
            return Color(red: 0.627, green: 0.533, blue: 0.408) // #A08968
        case "Healthcare":
            return Color(red: 0.831, green: 0.710, blue: 0.627) // #D4B5A0
        case "Entertainment":
            return Color(red: 0.722, green: 0.627, blue: 0.537) // #B8A089
        case "Shopping":
            return Color(red: 0.792, green: 0.722, blue: 0.659) // #C9B8A8
        default:
            return Color.gray
        }
    }
}

// MARK: - Receipt Row Component

struct ReceiptRow: View {
    let receipt: ReceiptStat

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: receipt.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(formattedDate)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.gray)
            }

            Spacer()

            Text(CurrencyParser.formatAmount(receipt.amount))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    let sampleReceipts: [ReceiptStat] = [
        ReceiptStat(id: "1", title: "Starbucks", amount: 6.50, date: Date().addingTimeInterval(-86400 * 5), category: "Food"),
        ReceiptStat(id: "2", title: "Chipotle", amount: 12.40, date: Date().addingTimeInterval(-86400 * 4), category: "Food"),
        ReceiptStat(id: "3", title: "Whole Foods", amount: 89.20, date: Date().addingTimeInterval(-86400 * 3), category: "Food"),
        ReceiptStat(id: "4", title: "Uber", amount: 45.00, date: Date().addingTimeInterval(-86400 * 5), category: "Transportation"),
        ReceiptStat(id: "5", title: "Gas", amount: 120.00, date: Date().addingTimeInterval(-86400 * 2), category: "Transportation"),
        ReceiptStat(id: "6", title: "Target", amount: 85.00, date: Date().addingTimeInterval(-86400), category: "Shopping"),
        ReceiptStat(id: "7", title: "Netflix", amount: 12.99, date: Date().addingTimeInterval(-86400 * 6), category: "Entertainment"),
        ReceiptStat(id: "8", title: "Pharmacy", amount: 45.00, date: Date().addingTimeInterval(-86400 * 4), category: "Healthcare"),
    ]

    return CategoryBreakdownView(
        categoryBreakdown: YearlyCategoryBreakdown(
            year: 2025,
            categories: [
                CategoryStat(category: "Food", total: 450.50, count: 15),
                CategoryStat(category: "Services", total: 320.00, count: 8),
                CategoryStat(category: "Transportation", total: 280.75, count: 10),
                CategoryStat(category: "Healthcare", total: 150.00, count: 3),
                CategoryStat(category: "Entertainment", total: 200.25, count: 5),
            ],
            yearlyTotal: 1400.50,
            allReceipts: sampleReceipts
        )
    )
}
