import SwiftUI

struct ReceiptItemRow: View {
    let receipt: ReceiptStat
    let onTap: (UUID) -> Void
    @Environment(\.colorScheme) var colorScheme

    var destinationName: String {
        // Extract text before the dash (-) if it exists
        let components = receipt.title.split(separator: "-", maxSplits: 1)
        return String(components.first ?? "").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Button(action: { onTap(receipt.noteId) }) {
            HStack(spacing: 12) {
                Text(destinationName)
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text(CurrencyParser.formatAmount(receipt.amount))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            )
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
