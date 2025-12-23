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
                VStack(spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(monthlySummary.month)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))

                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                            }

                            HStack(spacing: 6) {
                                Text("\(monthlySummary.receipts.count) receipt\(monthlySummary.receipts.count == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                                Text("•")
                                    .font(.system(size: 11))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))

                                Text(String(format: "Avg $%.0f/day", dailyAverage))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            // Category breakdown button
                            Button(action: {
                                showCategoryBreakdown = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.pie.fill")
                                        .font(.system(size: 11))
                                    Text("Categories")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                // Daily Groups - Shown when expanded
                VStack(spacing: 0) {
                    ForEach(monthlySummary.dailySummaries, id: \.id) { daily in
                        DailyReceiptCard(dailySummary: daily, onReceiptTap: onReceiptTap)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .background(Color.shadcnTileBackground(colorScheme))
        .cornerRadius(ShadcnRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear,
                    lineWidth: 1
                )
        )
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
