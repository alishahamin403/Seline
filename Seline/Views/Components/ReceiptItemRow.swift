import SwiftUI

struct ReceiptItemRow: View {
    let receipt: ReceiptStat
    let onTap: (ReceiptStat) -> Void
    @Environment(\.colorScheme) var colorScheme

    var destinationName: String {
        // Extract text before the dash (-) if it exists
        let components = receipt.title.split(separator: "-", maxSplits: 1)
        return String(components.first ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func iconForCategory(_ category: String?) -> String {
        var categoryToUse = category
        
        // If category is nil or "Other", try to infer from title
        if category == nil || category == "Other" {
             let title = receipt.title.lowercased()
             if title.contains("uber") || title.contains("lyft") || title.contains("gas") { categoryToUse = "Transportation" }
             else if title.contains("food") || title.contains("pizza") || title.contains("burger") { categoryToUse = "Food & Dining" }
             else if title.contains("grocery") || title.contains("market") { categoryToUse = "Shopping" }
             else if title.contains("wifi") || title.contains("internet") { categoryToUse = "Utilities & Internet" }
        }

        return CategoryIconProvider.icon(for: categoryToUse ?? "Other")
    }


    private var iconColor: Color {
        CategoryIconProvider.color(for: receipt.category)
    }

    var body: some View {
        Button(action: { onTap(receipt) }) {
            HStack(spacing: 12) {
                // Category Icon
                Text(iconForCategory(receipt.category))
                    .font(FontManager.geist(size: 16, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.26 : 0.2))
                    )

                Text(destinationName)
                    .font(FontManager.geist(size: 15, weight: .regular)) // 15pt
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text(CurrencyParser.formatAmount(receipt.amount))
                    .font(FontManager.geist(size: 15, weight: .regular)) // 15pt
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.86) : Color.emailLightTextPrimary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 12) {
        ReceiptItemRow(
            receipt: ReceiptStat(
                id: UUID(),
                title: "Whole Foods - Grocery",
                amount: 127.53,
                date: Date(),
                noteId: UUID()
            ),
            onTap: { _ in }
        )

        ReceiptItemRow(
            receipt: ReceiptStat(
                id: UUID(),
                title: "Target - Shopping",
                amount: 89.99,
                date: Date(),
                noteId: UUID()
            ),
            onTap: { _ in }
        )

        ReceiptItemRow(
            receipt: ReceiptStat(
                id: UUID(),
                title: "Gas Station",
                amount: 52.00,
                date: Date(),
                noteId: UUID()
            ),
            onTap: { _ in }
        )
    }
    .padding()
}
