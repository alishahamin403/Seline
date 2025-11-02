import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    let categoryBreakdown: YearlyCategoryBreakdown
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spending by Category")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Breakdown of \(categoryBreakdown.year)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }

                    Spacer()
                }
                .padding(16)
            }

            if isExpanded {
                Divider()
                    .opacity(0.3)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Category list
                        ForEach(Array(categoryBreakdown.sortedCategories.enumerated()), id: \.element.category) { index, categoryStat in
                            CategoryRow(categoryStat: categoryStat)

                            if index < categoryBreakdown.sortedCategories.count - 1 {
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: 400)  // Limit height so it doesn't expand infinitely
            }
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 1.0, green: 0.59, blue: 0.35) // Orange
        case "Services":
            return Color(red: 0.5, green: 0.8, blue: 0.9) // Light blue
        case "Transportation":
            return Color(red: 0.4, green: 0.8, blue: 0.4) // Green
        case "Healthcare":
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red
        case "Entertainment":
            return Color(red: 0.8, green: 0.4, blue: 0.9) // Purple
        case "Shopping":
            return Color(red: 1.0, green: 0.8, blue: 0.3) // Yellow
        default:
            return Color.gray
        }
    }
}

// MARK: - Category Row Component

struct CategoryRow: View {
    let categoryStat: CategoryStatWithPercentage
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(categoryStat.category)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        ProgressView(value: categoryStat.percentage / 100)
                            .frame(height: 4)
                            .tint(colorForCategory(categoryStat.category))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(categoryStat.formattedAmount)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(categoryStat.formattedPercentage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
            }

            if isExpanded && !categoryStat.receipts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(categoryStat.receipts.enumerated()), id: \.element.id) { index, receipt in
                        ReceiptRow(receipt: receipt)

                        if index < categoryStat.receipts.count - 1 {
                            Divider()
                                .opacity(0.1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.gray.opacity(0.05))
            }
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 1.0, green: 0.59, blue: 0.35) // Orange
        case "Services":
            return Color(red: 0.5, green: 0.8, blue: 0.9) // Light blue
        case "Transportation":
            return Color(red: 0.4, green: 0.8, blue: 0.4) // Green
        case "Healthcare":
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red
        case "Entertainment":
            return Color(red: 0.8, green: 0.4, blue: 0.9) // Purple
        case "Shopping":
            return Color(red: 1.0, green: 0.8, blue: 0.3) // Yellow
        default:
            return Color.gray
        }
    }
}

// MARK: - Receipt Row Component

struct ReceiptRow: View {
    let receipt: ReceiptStat
    @Environment(\.colorScheme) var colorScheme

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: receipt.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(formattedDate)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.gray)
            }

            Spacer()

            Text(CurrencyParser.formatAmount(receipt.amount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    CategoryBreakdownView(
        categoryBreakdown: YearlyCategoryBreakdown(
            year: 2025,
            categories: [
                CategoryStat(category: "Food", total: 450.50, count: 15),
                CategoryStat(category: "Services", total: 320.00, count: 8),
                CategoryStat(category: "Transportation", total: 280.75, count: 10),
                CategoryStat(category: "Healthcare", total: 150.00, count: 3),
                CategoryStat(category: "Entertainment", total: 200.25, count: 5),
            ],
            yearlyTotal: 1400.50
        )
    )
}
