import SwiftUI

struct HorizontalCategoryBreakdownView: View {
    let categoryBreakdown: YearlyCategoryBreakdown
    let onCategoryTap: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Horizontal scrollable categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categoryBreakdown.sortedCategories, id: \.category) { category in
                        HorizontalCategoryCard(category: category, onTap: { onCategoryTap(category.category) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Horizontal Category Card

struct HorizontalCategoryCard: View {
    let category: CategoryStatWithPercentage
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Category icon/color circle
                ZStack {
                    Circle()
                        .fill(colorForCategory(category.category).opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Text(getCategoryIcon(category.category))
                        .font(.system(size: 20))
                }

                // Category info
                VStack(spacing: 2) {
                    Text(category.category)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(category.formattedAmount)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(category.formattedPercentage)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.gray)
                }
            }
            .frame(minWidth: 90)
            .padding(10)
            .frame(minWidth: 90)
            .padding(10)
            .shadcnTileStyle(colorScheme: colorScheme)
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        return CategoryIconProvider.color(for: category)
    }

    private func getCategoryIcon(_ category: String) -> String {
        return CategoryIconProvider.icon(for: category)
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

    HorizontalCategoryBreakdownView(
        categoryBreakdown: YearlyCategoryBreakdown(
            year: 2025,
            categories: [
                CategoryStat(category: "Food", total: 450.50, count: 15),
                CategoryStat(category: "Services", total: 320.00, count: 8),
                CategoryStat(category: "Transportation", total: 280.75, count: 10),
                CategoryStat(category: "Healthcare", total: 150.00, count: 3),
                CategoryStat(category: "Entertainment", total: 200.25, count: 5),
                CategoryStat(category: "Shopping", total: 96.52, count: 2),
            ],
            yearlyTotal: 1400.50,
            allReceipts: sampleReceipts
        ),
        onCategoryTap: { _ in }
    )
}
