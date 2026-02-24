import SwiftUI

/// Modal that shows receipts for a single category in a consistent receipts design system.
struct CategoryReceiptsListModal: View {
    let receipts: [ReceiptStat]
    let categoryName: String
    let total: Double
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

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.emailLightBackground)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(categoryName)
                        .font(FontManager.geist(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)

                    HStack(spacing: 8) {
                        Text(CurrencyParser.formatAmountNoDecimals(total))
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                        Text("•")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(secondaryText)
                        Text("\(receipts.count) receipts")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if receipts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(FontManager.geist(size: 30, weight: .light))
                            .foregroundColor(secondaryText)
                        Text("No receipts in this category")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(receipts, id: \.id) { receipt in
                                Button(action: {
                                    guard let onReceiptTap else { return }
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        onReceiptTap(receipt)
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(CategoryIconProvider.color(for: receipt.category).opacity(colorScheme == .dark ? 0.3 : 0.2))
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Text(CategoryIconProvider.icon(for: receipt.category))
                                                    .font(FontManager.geist(size: 13, weight: .regular))
                                            )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(receipt.title)
                                                .font(FontManager.geist(size: 13, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                                                .lineLimit(1)

                                            Text(formatDate(receipt.date))
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(secondaryText)
                                        }

                                        Spacer()

                                        Text(CurrencyParser.formatAmount(receipt.amount))
                                            .font(FontManager.geist(size: 13, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
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
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
