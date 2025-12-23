import SwiftUI

struct DailyReceiptCard: View {
    let dailySummary: DailyReceiptSummary
    let onReceiptTap: (UUID) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            // Date Header - Simple divider style
            HStack(spacing: 8) {
                Text(dailySummary.dayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                Text("•")
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))

                Text(CurrencyParser.formatAmount(dailySummary.dailyTotal))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Receipts - Always visible
            VStack(spacing: 6) {
                ForEach(dailySummary.receipts, id: \.id) { receipt in
                    ReceiptItemRow(receipt: receipt, onTap: onReceiptTap)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Whole Foods - Grocery", amount: 127.53, date: Date(), noteId: UUID()),
        ReceiptStat(id: UUID(), title: "Target - Shopping", amount: 89.99, date: Date(), noteId: UUID()),
    ]
    let daily = DailyReceiptSummary(day: 15, dayDate: Date(), receipts: receipts)

    DailyReceiptCard(dailySummary: daily, onReceiptTap: { _ in })
        .padding()
}
