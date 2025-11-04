import SwiftUI

struct CategoryBreakdownModal: View {
    let monthlyReceipts: [ReceiptStat]
    let monthName: String
    let monthlyTotal: Double
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var categoryBreakdown: [(category: String, total: Double, count: Int, receipts: [ReceiptStat])] {
        let categories = Set(monthlyReceipts.map { $0.category })
        return categories.map { category in
            let receiptsInCategory = monthlyReceipts.filter { $0.category == category }
            let total = receiptsInCategory.reduce(0) { $0 + $1.amount }
            return (category: category, total: total, count: receiptsInCategory.count, receipts: receiptsInCategory.sorted { $0.date > $1.date })
        }.sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(monthName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Spending")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.gray)
                            Text(CurrencyParser.formatAmount(monthlyTotal))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Categories")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.gray)
                            Text("\(categoryBreakdown.count)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(16)
                .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))

                Divider()
                    .opacity(0.3)

                // Category breakdown list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(categoryBreakdown.enumerated()), id: \.element.category) { index, item in
                            CategoryBreakdownItem(
                                category: item.category,
                                total: item.total,
                                count: item.count,
                                percentage: monthlyTotal > 0 ? (item.total / monthlyTotal) * 100 : 0,
                                receipts: item.receipts
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

// MARK: - Category Breakdown Item

struct CategoryBreakdownItem: View {
    let category: String
    let total: Double
    let count: Int
    let percentage: Double
    let receipts: [ReceiptStat]
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        ProgressView(value: percentage / 100)
                            .frame(height: 4)
                            .tint(colorForCategory(category))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CurrencyParser.formatAmount(total))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(String(format: "%.1f%%", percentage))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
                .cornerRadius(8)
            }

            // Expanded receipts
            if isExpanded && !receipts.isEmpty {
                VStack(spacing: 8) {
                    Divider()
                        .opacity(0.2)
                        .padding(.top, 8)

                    ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.title)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(formatDate(receipt.date))
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Text(CurrencyParser.formatAmount(receipt.amount))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)

                        if index < receipts.count - 1 {
                            Divider()
                                .opacity(0.1)
                        }
                    }
                }
                .padding(12)
                .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Starbucks", amount: 6.50, date: Date().addingTimeInterval(-86400), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Chipotle", amount: 12.40, date: Date().addingTimeInterval(-86400 * 2), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Whole Foods", amount: 89.20, date: Date().addingTimeInterval(-86400 * 3), noteId: UUID(), category: "Food"),
        ReceiptStat(id: UUID(), title: "Uber", amount: 45.00, date: Date().addingTimeInterval(-86400), noteId: UUID(), category: "Transportation"),
        ReceiptStat(id: UUID(), title: "Target", amount: 85.00, date: Date().addingTimeInterval(-86400 * 2), noteId: UUID(), category: "Shopping"),
    ]

    CategoryBreakdownModal(monthlyReceipts: receipts, monthName: "May", monthlyTotal: 238.10)
}
