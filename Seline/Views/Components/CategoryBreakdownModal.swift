import SwiftUI

struct CategoryBreakdownModal: View {
    let monthlyReceipts: [ReceiptStat]
    let monthName: String
    let monthlyTotal: Double
    var onReceiptTap: ((ReceiptStat) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.emailLightSurface
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
    }

    private var categoryBreakdown: [(category: String, total: Double, count: Int, receipts: [ReceiptStat])] {
        let categories = Set(monthlyReceipts.map { $0.category })
        return categories.map { category in
            let receiptsInCategory = monthlyReceipts.filter { $0.category == category }
            let total = receiptsInCategory.reduce(0) { $0 + $1.amount }
            return (
                category: category,
                total: total,
                count: receiptsInCategory.count,
                receipts: receiptsInCategory.sorted { $0.date > $1.date }
            )
        }.sorted { $0.total > $1.total }
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.emailLightBackground)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(monthName) Categories")
                        .font(FontManager.geist(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)

                    HStack(spacing: 8) {
                        Text(CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                        Text("•")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(secondaryText)
                        Text("\(monthlyReceipts.count) receipts")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if categoryBreakdown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(FontManager.geist(size: 30, weight: .light))
                            .foregroundColor(secondaryText)
                        Text("No category data")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(Array(categoryBreakdown.enumerated()), id: \.element.category) { _, item in
                                CategoryBreakdownItem(
                                    category: item.category,
                                    total: item.total,
                                    count: item.count,
                                    percentage: monthlyTotal > 0 ? (item.total / monthlyTotal) * 100 : 0,
                                    receipts: item.receipts,
                                    onReceiptTap: onReceiptTap
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
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
    var onReceiptTap: ((ReceiptStat) -> Void)? = nil
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.emailLightSurface
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(colorForCategory(category))
                            .frame(width: 8, height: 8)

                        Text(category)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(CurrencyParser.formatAmount(total))
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                    }

                    GeometryReader { geometry in
                        let fill = max(8, geometry.size.width * (percentage / 100))
                        ZStack(alignment: .leading) {
                            Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.emailLightChipIdle)
                            Capsule().fill(colorForCategory(category)).frame(width: fill)
                        }
                    }
                    .frame(height: 8)

                    HStack(spacing: 6) {
                        Text("\(count) receipts")
                        Text("•")
                        Text(String(format: "%.1f%%", percentage))
                    }
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(secondaryText)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(surfaceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded && !receipts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(receipts.prefix(8).enumerated()), id: \.element.id) { _, receipt in
                        Button(action: {
                            guard let onReceiptTap else { return }
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onReceiptTap(receipt)
                            }
                        }) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(receipt.title)
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                                        .lineLimit(1)

                                    Text(formatDate(receipt.date))
                                        .font(FontManager.geist(size: 10, weight: .regular))
                                        .foregroundColor(secondaryText)
                                }

                                Spacer()

                                Text(CurrencyParser.formatAmount(receipt.amount))
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightChipIdle.opacity(0.55))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func colorForCategory(_ category: String) -> Color {
        CategoryIconProvider.color(for: category)
    }
}

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Starbucks", amount: 6.50, date: Date().addingTimeInterval(-86400), noteId: UUID(), category: "Food & Dining"),
        ReceiptStat(id: UUID(), title: "Chipotle", amount: 12.40, date: Date().addingTimeInterval(-86400 * 2), noteId: UUID(), category: "Food & Dining"),
        ReceiptStat(id: UUID(), title: "Whole Foods", amount: 89.20, date: Date().addingTimeInterval(-86400 * 3), noteId: UUID(), category: "Food & Dining"),
        ReceiptStat(id: UUID(), title: "Uber", amount: 45.00, date: Date().addingTimeInterval(-86400), noteId: UUID(), category: "Transportation")
    ]

    CategoryBreakdownModal(monthlyReceipts: receipts, monthName: "May", monthlyTotal: 153.10)
}
