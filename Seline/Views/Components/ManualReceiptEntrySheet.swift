import SwiftUI

struct ManualReceiptEntrySheet: View {
    let onSave: (ReceiptDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var merchant = ""
    @State private var total = ""
    @State private var transactionDate = Date()
    @State private var includesTime = false
    @State private var transactionTime = Date()
    @State private var category = "Other"
    @State private var paymentMethod = ""
    @State private var subtotal = ""
    @State private var tax = ""
    @State private var tip = ""
    @State private var lineItems: [ManualLineItem] = [ManualLineItem()]
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Summary") {
                    TextField("Merchant", text: $merchant)
                    TextField("Total", text: $total)
                        .keyboardType(.decimalPad)

                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)

                    Toggle("Add time", isOn: $includesTime)
                    if includesTime {
                        DatePicker("Time", selection: $transactionTime, displayedComponents: .hourAndMinute)
                    }

                    TextField("Category", text: $category)
                    TextField("Payment method", text: $paymentMethod)
                }

                Section("Key Info") {
                    TextField("Subtotal", text: $subtotal)
                        .keyboardType(.decimalPad)
                    TextField("Tax", text: $tax)
                        .keyboardType(.decimalPad)
                    TextField("Tip", text: $tip)
                        .keyboardType(.decimalPad)
                }

                Section("Line Items") {
                    ForEach($lineItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Item name", text: $item.title)
                            TextField("Amount", text: $item.amount)
                                .keyboardType(.decimalPad)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        lineItems.append(ManualLineItem())
                    } label: {
                        Label("Add line item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Add Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        save()
                    }
                    .disabled(isSaving || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || decimal(total) == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color.emailLightBackground)
        }
    }

    private func save() {
        guard let totalValue = decimal(total) else { return }
        isSaving = true

        let detailFields = [
            paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ReceiptField(label: "Payment", value: paymentMethod, kind: .text),
            decimal(subtotal).map { ReceiptField(label: "Subtotal", value: CurrencyParser.formatAmount($0), kind: .currency) },
            decimal(tax).map { ReceiptField(label: "Tax", value: CurrencyParser.formatAmount($0), kind: .currency) },
            decimal(tip).map { ReceiptField(label: "Tip", value: CurrencyParser.formatAmount($0), kind: .currency) }
        ].compactMap { $0 }

        let draft = ReceiptDraft(
            merchant: merchant,
            total: totalValue,
            transactionDate: transactionDate,
            transactionTime: includesTime ? mergedDateTime : nil,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : category,
            subtotal: decimal(subtotal),
            tax: decimal(tax),
            tip: decimal(tip),
            paymentMethod: paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : paymentMethod,
            detailFields: detailFields,
            lineItems: lineItems.compactMap { item in
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return ReceiptLineItem(title: title, amount: decimal(item.amount))
            }
        )

        Task {
            await onSave(draft)
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }

    private var mergedDateTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: transactionDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: transactionTime)
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        return calendar.date(from: combined) ?? transactionDate
    }

    private func decimal(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }
}

private struct ManualLineItem: Identifiable {
    let id = UUID()
    var title = ""
    var amount = ""
}
