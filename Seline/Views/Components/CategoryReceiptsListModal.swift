import SwiftUI

/// A simple modal that shows receipts for a single category without the breakdown
struct CategoryReceiptsListModal: View {
    let receipts: [ReceiptStat]
    let categoryName: String
    let total: Double
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(categoryName)
                    .font(FontManager.geist(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Spending")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                    Text(CurrencyParser.formatAmountNoDecimals(total))
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))

            Divider()
                .opacity(0.3)

            // Receipts list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.title)
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(formatDate(receipt.date))
                                    .font(FontManager.geist(size: 11, weight: .regular))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Text(CurrencyParser.formatAmount(receipt.amount))
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.gray.opacity(0.05))
                        .cornerRadius(8)

                        if index < receipts.count - 1 {
                            Divider()
                                .opacity(0.1)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
