import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    let categoryBreakdown: YearlyCategoryBreakdown
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Spending by Category")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Year: \(categoryBreakdown.year)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()
                .opacity(0.3)

            // Category cards - Simple, compact list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(categoryBreakdown.sortedCategories, id: \.category) { category in
                        CompactCategoryCard(category: category, yearlyTotal: categoryBreakdown.yearlyTotal)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Compact Category Card

struct CompactCategoryCard: View {
    let category: CategoryStatWithPercentage
    let yearlyTotal: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(category.category)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                ProgressView(value: category.percentage / 100)
                    .frame(height: 4)
                    .tint(colorForCategory(category.category))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(category.formattedAmount)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(.primary)

                Text(category.formattedPercentage)
                    .font(FontManager.geist(size: 11, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
        .cornerRadius(8)
    }

    private func colorForCategory(_ category: String) -> Color {
        // Use CategoryIconProvider for consistent colors (Google brand colors)
        return CategoryIconProvider.color(for: category)
    }
}

#Preview {
    let sampleReceipts: [ReceiptStat] = [
        ReceiptStat(id: UUID(), title: "Starbucks", amount: 6.50, date: Date().addingTimeInterval(-86400 * 5), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Chipotle", amount: 12.40, date: Date().addingTimeInterval(-86400 * 4), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Whole Foods", amount: 89.20, date: Date().addingTimeInterval(-86400 * 3), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Uber", amount: 45.00, date: Date().addingTimeInterval(-86400 * 5), noteId: UUID(), category: "Transportation"),
        ReceiptStat(id: UUID(), title: "Gas", amount: 120.00, date: Date().addingTimeInterval(-86400 * 2), noteId: UUID(), category: "Transportation"),
        ReceiptStat(id: UUID(), title: "Target", amount: 85.00, date: Date().addingTimeInterval(-86400), noteId: UUID(), category: "Shopping"),
        ReceiptStat(id: UUID(), title: "Netflix", amount: 12.99, date: Date().addingTimeInterval(-86400 * 6), noteId: UUID(), category: "Entertainment"),
        ReceiptStat(id: UUID(), title: "Pharmacy", amount: 45.00, date: Date().addingTimeInterval(-86400 * 4), noteId: UUID(), category: "Healthcare"),
    ]

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
            yearlyTotal: 1400.50,
            allReceipts: sampleReceipts
        )
    )
}
