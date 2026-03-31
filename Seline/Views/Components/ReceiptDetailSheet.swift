import SwiftUI

struct ReceiptDetailSheet: View {
    let receipt: ReceiptStat
    let note: Note?

    @State private var showNoteEditor = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(receipt: ReceiptStat, note: Note? = nil, folderName: String? = nil) {
        self.receipt = receipt
        self.note = note
    }

    private var legacyNote: Note? {
        note ?? ReceiptManager.shared.note(for: receipt)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color.emailLightTextPrimary
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
    }

    private var cardColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.emailLightSurface
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var displayFields: [ReceiptField] {
        if !receipt.detailFields.isEmpty {
            return receipt.detailFields
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
        if !receipt.lineItems.isEmpty {
            return receipt.lineItems
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

    private var imageURLs: [String] {
        if !receipt.imageUrls.isEmpty {
            return receipt.imageUrls
        }
        return legacyNote?.imageUrls ?? []
    }

    private var supportsLegacyNoteActions: Bool {
        receipt.source == .legacyFallback && legacyNote != nil
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.emailLightBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    summaryCard
                    if !displayFields.isEmpty {
                        keyInfoCard
                    }
                    lineItemsCard
                    receiptImageCard
                    if supportsLegacyNoteActions {
                        rawContentCard
                        actionsCard
                    } else {
                        closeCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showNoteEditor) {
            if let legacyNote {
                NavigationView {
                    NoteEditView(
                        note: legacyNote,
                        isPresented: Binding<Bool>(
                            get: { showNoteEditor },
                            set: { showNoteEditor = $0 }
                        )
                    )
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(secondaryText)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.merchant)
                        .font(FontManager.geist(size: 28, weight: .bold))
                        .foregroundColor(primaryText)
                        .lineLimit(2)

                    Text(formattedDate(receipt.date))
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(secondaryText)
                }

                Spacer(minLength: 8)

                Text(CurrencyParser.formatAmount(receipt.amount))
                    .font(FontManager.geist(size: 32, weight: .bold))
                    .foregroundColor(primaryText)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 8) {
                Text(receipt.category)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .black : primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.emailLightChipIdle)
                    )

                if receipt.source != .legacyFallback {
                    Text(receipt.source == .migratedLegacy ? "Migrated" : "Native")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(secondaryText)
                }
            }
        }
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    private var keyInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Info")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryText)

            ForEach(displayFields) { field in
                HStack(spacing: 10) {
                    Text(field.label)
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(secondaryText)
                    Spacer(minLength: 8)
                    Text(field.value)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(primaryText)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightChipIdle.opacity(0.55))
                )
            }
        }
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    private var lineItemsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extracted Line Items")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryText)

            if extractedLineItems.isEmpty {
                Text("No line items detected")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(secondaryText)
            } else {
                ForEach(extractedLineItems) { item in
                    HStack {
                        Text(item.title)
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(primaryText)
                            .lineLimit(1)
                        Spacer()
                        if let amount = item.amount {
                            Text(CurrencyParser.formatAmount(amount))
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(primaryText)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightChipIdle.opacity(0.55))
                    )
                }
            }
        }
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    @ViewBuilder
    private var receiptImageCard: some View {
        if let firstImageURL = imageURLs.first, let url = URL(string: firstImageURL) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Receipt Image")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText)

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
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        Text("Unable to load image")
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .cardShell(cardColor: cardColor, cardBorder: cardBorder)
        }
    }

    private var rawContentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Note Content")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryText)

            Text(legacyNote?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (legacyNote?.content ?? "") : "No content")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightChipIdle.opacity(0.55))
                )
        }
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    private var actionsCard: some View {
        HStack(spacing: 10) {
            Button(action: {
                showNoteEditor = true
            }) {
                Text("Edit Note")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.emailLightTextPrimary)
                    )
            }
            .buttonStyle(.plain)

            Button(action: {
                dismiss()
            }) {
                Text("Close")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle)
                    )
            }
            .buttonStyle(.plain)
        }
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    private var closeCard: some View {
        Button(action: { dismiss() }) {
            Text("Close")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle)
                )
        }
        .buttonStyle(.plain)
        .cardShell(cardColor: cardColor, cardBorder: cardBorder)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension View {
    func cardShell(cardColor: Color, cardBorder: Color) -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
    }
}
