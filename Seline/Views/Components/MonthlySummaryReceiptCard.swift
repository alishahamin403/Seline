import SwiftUI

struct MonthlySummaryReceiptCard: View {
    let monthlySummary: MonthlyReceiptSummary
    let isLast: Bool
    let onReceiptTap: (UUID) -> Void
    let categorizedReceipts: [ReceiptStat]
    @State private var isExpanded = false
    @State private var showCategoryBreakdown = false
    @Environment(\.colorScheme) var colorScheme

    private var dailyAverage: Double {
        let calendar = Calendar.current

        // Get the first receipt's date to determine the month/year
        guard let firstReceiptDate = monthlySummary.receipts.first?.date else {
            return 0
        }

        // Get the range of days in this month
        let components = calendar.dateComponents([.year, .month], from: firstReceiptDate)
        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            return 0
        }

        // Calculate total days in the month
        let daysInMonth = calendar.component(.day, from: endOfMonth)

        // Divide by total days in month
        let divisor = Double(max(daysInMonth, 1))
        return monthlySummary.monthlyTotal / divisor
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthlySummary.month)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Text("\(monthlySummary.receipts.count) receipt\(monthlySummary.receipts.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)

                        Text("•")
                            .foregroundColor(.gray)

                        Text(String(format: "Avg $%.2f/day", dailyAverage))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                        .font(.system(size: 15, weight: .regular))
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
