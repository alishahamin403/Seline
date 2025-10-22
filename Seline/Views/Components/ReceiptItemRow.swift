import SwiftUI

struct ReceiptItemRow: View {
    let receipt: ReceiptStat
    let onTap: (UUID) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Button(action: { onTap(receipt.noteId) }) {
                    Text(receipt.title)
                        .font(.system(size: 14, weight: .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(CurrencyParser.formatAmount(receipt.amount))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.gray.opacity(0.02))
        .cornerRadius(6)
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
