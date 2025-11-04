import SwiftUI

struct MonthlySummaryReceiptCard: View {
    let monthlySummary: MonthlyReceiptSummary
    let isLast: Bool
    let onReceiptTap: (UUID) -> Void
    let categorizedReceipts: [ReceiptStat]
    @State private var isExpanded = true
    @State private var showCategoryBreakdown = false
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

                // Category breakdown button
                Button(action: { showCategoryBreakdown = true }) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .opacity(0.6)
                }
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
        .sheet(isPresented: $showCategoryBreakdown) {
            CategoryBreakdownModal(
                monthlyReceipts: categorizedReceipts,
                monthName: monthlySummary.month,
                monthlyTotal: monthlySummary.monthlyTotal
            )
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Whole Foods - Grocery", amount: 127.53, date: Date(), noteId: UUID(), category: "Shopping"),
        ReceiptStat(id: UUID(), title: "Target - Shopping", amount: 89.99, date: Date(), noteId: UUID(), category: "Shopping"),
        ReceiptStat(id: UUID(), title: "Gas Station", amount: 52.00, date: Date(), noteId: UUID(), category: "Transportation")
    ]
    let summary = MonthlyReceiptSummary(month: "December", monthDate: Date(), receipts: receipts)

    MonthlySummaryReceiptCard(monthlySummary: summary, isLast: true, onReceiptTap: { _ in }, categorizedReceipts: receipts)
        .padding()
}
