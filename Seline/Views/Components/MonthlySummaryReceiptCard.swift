import SwiftUI

struct MonthlySummaryReceiptCard: View {
    let monthlySummary: MonthlyReceiptSummary
    let isLast: Bool
    let onReceiptTap: (UUID) -> Void
    let categorizedReceipts: [ReceiptStat]
    @State private var showCategoryBreakdown = false
    @State private var isExpanded = false
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
            // Month Header - Prominent (Tappable to expand/collapse)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(monthlySummary.month)
                                .font(FontManager.geist(size: 17, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            HStack(spacing: 6) {
                                Text("\(monthlySummary.receipts.count) receipts")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                Text("•")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                                Text(String(format: "Avg $%.0f/day", dailyAverage))
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                                .font(FontManager.geist(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            // Category breakdown button
                            Button(action: {
                                showCategoryBreakdown = true
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "chart.pie.fill")
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                    Text("Categories")
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                }
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            }
                        }
                    }
                }
                .padding(14)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                // Daily Groups - Shown when expanded
                VStack(spacing: 16) { // Added spacing between day boxes
                    ForEach(monthlySummary.dailySummaries, id: \.id) { daily in
                        DailyReceiptCard(dailySummary: daily, categorizedReceipts: categorizedReceipts, onReceiptTap: onReceiptTap)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .shadcnTileStyle(colorScheme: colorScheme) // Apply widget style to the whole month card

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
