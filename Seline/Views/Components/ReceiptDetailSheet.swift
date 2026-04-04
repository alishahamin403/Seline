import SwiftUI

struct ReceiptDetailSheet: View {
    let receipt: ReceiptStat
    let note: Note?

    @StateObject private var receiptManager = ReceiptManager.shared
    @State private var showReceiptEditor = false
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(receipt: ReceiptStat, note: Note? = nil, folderName: String? = nil) {
        self.receipt = receipt
        self.note = note
    }

    private var currentReceipt: ReceiptStat {
        receiptManager.receipt(by: receipt.id) ?? receipt
    }

    private var legacyNote: Note? {
        note ?? receiptManager.note(for: currentReceipt)
    }

    private var displayFields: [ReceiptField] {
        if !currentReceipt.detailFields.isEmpty {
            return currentReceipt.detailFields
        }

        guard let legacyNote else { return [] }
        let lines = legacyNote.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line in
            guard let separator = line.range(of: ":") else { return nil }
            let label = String(line[..<separator.lowerBound])
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "📍", with: "")
                .replacingOccurrences(of: "💳", with: "")
                .replacingOccurrences(of: "💰", with: "")
                .replacingOccurrences(of: "📊", with: "")
                .replacingOccurrences(of: "💵", with: "")
                .replacingOccurrences(of: "✅", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !value.isEmpty else { return nil }

            let kind: ReceiptFieldKind
            if label.lowercased().contains("time") {
                kind = .time
            } else if CurrencyParser.extractAmount(from: value) > 0 {
                kind = .currency
            } else {
                kind = .text
            }

            return ReceiptField(label: label, value: value, kind: kind)
        }
    }

    private var extractedLineItems: [ReceiptLineItem] {
        if !currentReceipt.lineItems.isEmpty {
            return currentReceipt.lineItems
        }

        guard let legacyNote else { return [] }
        let lines = legacyNote.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let ignored = ["subtotal", "tax", "tip", "total", "merchant", "payment", "summary"]
        return lines.compactMap { line in
            let lowered = line.lowercased()
            guard !ignored.contains(where: { lowered.contains($0) }) else { return nil }
            let amount = CurrencyParser.extractAmount(from: line)
            guard amount > 0 else { return nil }

            let title = line
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "\\$?\\d+[\\.,]?\\d*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else { return nil }
            return ReceiptLineItem(title: title, amount: amount)
        }
    }

    private var keyInfoRows: [ReceiptInfoRow] {
        var rows: [ReceiptInfoRow] = []
        var seenLabels = Set<String>()

        func append(label: String, value: String?) {
            let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else { return }
            let key = normalizedLabel.lowercased()
            guard !seenLabels.contains(key) else { return }
            rows.append(ReceiptInfoRow(label: normalizedLabel, value: normalizedValue))
            seenLabels.insert(key)
        }

        append(label: "Category", value: currentReceipt.category)
        append(label: "Time", value: currentReceipt.transactionTime.map { FormatterCache.shortTime.string(from: $0) })
        append(label: "Payment", value: currentReceipt.paymentMethod)
        append(label: "Subtotal", value: currentReceipt.subtotal.map { CurrencyParser.formatAmount($0) })
        append(label: "Tax", value: currentReceipt.tax.map { CurrencyParser.formatAmount($0) })
        append(label: "Tip", value: currentReceipt.tip.map { CurrencyParser.formatAmount($0) })

        for field in displayFields {
            append(label: field.label, value: field.value)
        }

        for item in extractedLineItems {
            let value = item.amount.map { CurrencyParser.formatAmount($0) }
                ?? item.quantity.map { "Qty \(ReceiptEditorNumberFormatter.string(from: NSNumber(value: $0)) ?? "\($0)")" }
                ?? "Included"
            append(label: item.title, value: value)
        }

        return rows
    }

    private var imageURLs: [String] {
        if !currentReceipt.imageUrls.isEmpty {
            return currentReceipt.imageUrls
        }
        return legacyNote?.imageUrls ?? []
    }

    private var showsRawContentSection: Bool {
        legacyNote != nil
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if !keyInfoRows.isEmpty {
                    keyInfoSection
                }

                receiptImageSection

                if showsRawContentSection {
                    rawContentSection
                }

                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showReceiptEditor = true
                    }
                }
            }
        }
        .sheet(isPresented: $showReceiptEditor) {
            ReceiptEditorSheet(receipt: currentReceipt) { title, draft in
                _ = receiptManager.updateReceipt(currentReceipt, title: title, draft: draft)
                HapticManager.shared.success()
            }
        }
        .confirmationDialog("Delete Receipt", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                HapticManager.shared.delete()
                receiptManager.deleteReceipt(currentReceipt)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete this receipt? This will remove the receipt from your records.")
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentReceipt.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        if currentReceipt.merchant != currentReceipt.title {
                            Text(currentReceipt.merchant)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(formattedDate(currentReceipt.date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(CurrencyParser.formatAmount(currentReceipt.amount))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 8) {
                    Text(currentReceipt.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())

                    if currentReceipt.source != .legacyFallback {
                        Text(currentReceipt.source == .migratedLegacy ? "Migrated" : "Native")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var keyInfoSection: some View {
        Section("Key Info") {
            ForEach(keyInfoRows) { row in
                LabeledContent(row.label) {
                    Text(row.value)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var receiptImageSection: some View {
        if let firstImageURL = imageURLs.first, let url = URL(string: firstImageURL) {
            Section("Receipt Image") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        Text("Unable to load image")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var rawContentSection: some View {
        Section("Raw Note Content") {
            Text(legacyNote?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (legacyNote?.content ?? "") : "No content")
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showReceiptEditor = true
            } label: {
                Text("Edit Receipt")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete Receipt")
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ReceiptInfoRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct ReceiptEditorSheet: View {
    let receipt: ReceiptStat
    let onSave: (String, ReceiptDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: String
    @State private var merchant: String
    @State private var total: String
    @State private var transactionDate: Date
    @State private var includesTime: Bool
    @State private var transactionTime: Date
    @State private var category: String
    @State private var paymentMethod: String
    @State private var subtotal: String
    @State private var tax: String
    @State private var tip: String
    @State private var lineItems: [EditableReceiptLineItem]
    @State private var isSaving = false

    init(receipt: ReceiptStat, onSave: @escaping (String, ReceiptDraft) async -> Void) {
        self.receipt = receipt
        self.onSave = onSave
        _title = State(initialValue: receipt.title)
        _merchant = State(initialValue: receipt.merchant)
        _total = State(initialValue: ReceiptEditorNumberFormatter.string(from: NSNumber(value: receipt.amount)) ?? "\(receipt.amount)")
        _transactionDate = State(initialValue: receipt.date)
        _includesTime = State(initialValue: receipt.transactionTime != nil)
        _transactionTime = State(initialValue: receipt.transactionTime ?? receipt.date)
        _category = State(initialValue: receipt.category)
        _paymentMethod = State(initialValue: receipt.paymentMethod ?? "")
        _subtotal = State(initialValue: Self.decimalFieldText(receipt.subtotal))
        _tax = State(initialValue: Self.decimalFieldText(receipt.tax))
        _tip = State(initialValue: Self.decimalFieldText(receipt.tip))
        _lineItems = State(initialValue: receipt.lineItems.isEmpty ? [EditableReceiptLineItem()] : receipt.lineItems.map(EditableReceiptLineItem.init))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Summary") {
                    TextField("Title", text: $title)
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
                        lineItems.append(EditableReceiptLineItem())
                    } label: {
                        Label("Add line item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Edit Receipt")
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
                    .disabled(
                        isSaving ||
                        merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        decimal(total) == nil
                    )
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
                let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedTitle.isEmpty else { return nil }
                return ReceiptLineItem(title: normalizedTitle, amount: decimal(item.amount))
            },
            imageUrls: receipt.imageUrls
        )

        Task {
            await onSave(title, draft)
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

    private static func decimalFieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return ReceiptEditorNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct EditableReceiptLineItem: Identifiable {
    let id: UUID
    var title: String
    var amount: String

    init(id: UUID = UUID(), title: String = "", amount: String = "") {
        self.id = id
        self.title = title
        self.amount = amount
    }

    init(_ item: ReceiptLineItem) {
        self.id = item.id
        self.title = item.title
        self.amount = item.amount.flatMap { ReceiptEditorNumberFormatter.string(from: NSNumber(value: $0)) } ?? ""
    }
}

private enum ReceiptEditorNumberFormatter {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func string(from number: NSNumber) -> String? {
        formatter.string(from: number)
    }
}
