import SwiftUI

struct MonthlySummaryReceiptCard: View {
    let monthlySummary: MonthlyReceiptSummary
    let isLast: Bool
    let onReceiptTap: (UUID) -> Void
    @State private var isExpanded = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(monthlySummary.month)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text("\(monthlySummary.receipts.count)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.gray)

                        Text("receipt\(monthlySummary.receipts.count == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyParser.formatAmount(monthlySummary.monthlyTotal))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.gray)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, alignment: .center)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Content (Daily Breakdowns)
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(monthlySummary.dailySummaries, id: \.id) { daily in
                        DailyReceiptCard(dailySummary: daily, onReceiptTap: onReceiptTap)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Whole Foods - Grocery", amount: 127.53, date: Date(), noteId: UUID()),
        ReceiptStat(id: UUID(), title: "Target - Shopping", amount: 89.99, date: Date(), noteId: UUID()),
        ReceiptStat(id: UUID(), title: "Gas Station", amount: 52.00, date: Date(), noteId: UUID())
    ]
    let summary = MonthlyReceiptSummary(month: "December", monthDate: Date(), receipts: receipts)

    MonthlySummaryReceiptCard(monthlySummary: summary, isLast: true, onReceiptTap: { _ in })
        .padding()
}
