import SwiftUI

struct DailyReceiptCard: View {
    let dailySummary: DailyReceiptSummary
    let categorizedReceipts: [ReceiptStat] // Receipts with categories assigned
    let onReceiptTap: (ReceiptStat) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    // Get receipts for this day from categorized list, falling back to daily summary
    private var receiptsForDay: [ReceiptStat] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: dailySummary.dayDate)
        
        // Find matching receipts from categorized list
        let matchingReceipts = categorizedReceipts.filter { receipt in
            let receiptDay = calendar.startOfDay(for: receipt.date)
            return receiptDay == dayStart
        }
        
        // If we found categorized receipts, use those; otherwise fall back to daily summary
        return matchingReceipts.isEmpty ? dailySummary.receipts : matchingReceipts
    }

    private var displayedTotal: Double {
        receiptsForDay.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(dailySummary.dayString) // E.g. "Fri, Dec 26"
                    .font(FontManager.geist(size: 15, weight: .semibold)) // 15pt Semi-Bold
                    .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)

                Spacer()

                Text(CurrencyParser.formatAmount(displayedTotal))
                    .font(FontManager.geist(size: 15, weight: .bold)) // 15pt Bold
                    .foregroundColor(colorScheme == .dark ? .white : Color.emailLightTextPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Receipts List - use categorized receipts
            VStack(spacing: 0) {
                ForEach(Array(receiptsForDay.enumerated()), id: \.element.id) { index, receipt in
                    VStack(spacing: 0) {
                        ReceiptItemRow(receipt: receipt, onTap: onReceiptTap)
                            .padding(.vertical, 8) // Increased breathing room between items
                        
                        // Add divider between items, but not after the last one
                        if index < receiptsForDay.count - 1 {
                            Divider()
                                .padding(.leading, 60) // Indent divider to align with text
                                .opacity(0.3)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder, lineWidth: 1)
        )
    }
}

#Preview {
    let receipts = [
        ReceiptStat(id: UUID(), title: "Whole Foods - Grocery", amount: 127.53, date: Date(), noteId: UUID(), category: "Shopping"),
        ReceiptStat(id: UUID(), title: "Target - Shopping", amount: 89.99, date: Date(), noteId: UUID(), category: "Shopping"),
    ]
    let daily = DailyReceiptSummary(day: 15, dayDate: Date(), receipts: receipts)

    DailyReceiptCard(dailySummary: daily, categorizedReceipts: receipts, onReceiptTap: { _ in })
        .padding()
}
