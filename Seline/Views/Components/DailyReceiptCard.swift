import SwiftUI

struct DailyReceiptCard: View {
    let dailySummary: DailyReceiptSummary
    let onReceiptTap: (UUID) -> Void
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(dailySummary.dayString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text("\(dailySummary.receipts.count)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)

                        Text("receipt\(dailySummary.receipts.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyParser.formatAmount(dailySummary.dailyTotal))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.gray.opacity(0.01))

            // Content (Receipts)
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(dailySummary.receipts, id: \.id) { receipt in
                        ReceiptItemRow(receipt: receipt, onTap: onReceiptTap)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
