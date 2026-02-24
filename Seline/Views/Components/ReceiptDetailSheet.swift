import SwiftUI

struct ReceiptDetailSheet: View {
    let receipt: ReceiptStat
    let note: Note
    let folderName: String
    @State private var showNoteEditor = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private struct ParsedLineItem: Identifiable {
        let id = UUID()
        let title: String
        let amount: Double
    }

    private var merchantName: String {
        receipt.title
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? receipt.title
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

    private var extractedLineItems: [ParsedLineItem] {
        let rawLines = note.content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var items: [ParsedLineItem] = []
        for line in rawLines {
            let lowered = line.lowercased()
            if lowered.contains("subtotal") || lowered.contains("tax") || lowered.contains("tip") || lowered.contains("total") {
                continue
            }

            let amount = CurrencyParser.extractAmount(from: line)
            guard amount > 0 else { continue }

            let normalizedTitle = line.replacingOccurrences(
                of: "\\$?\\d+[\\.,]?\\d*",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            let title = normalizedTitle.isEmpty ? "Line item" : normalizedTitle
            items.append(ParsedLineItem(title: title, amount: amount))
            if items.count == 6 { break }
        }
        return items
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.emailLightBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    headerCard
                    extractedItemsCard
                    receiptImageCard
                    rawContentCard
                    actionsCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showNoteEditor) {
            NavigationView {
                NoteEditView(
                    note: note,
                    isPresented: Binding<Bool>(
                        get: { showNoteEditor },
                        set: { showNoteEditor = $0 }
                    )
                )
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(secondaryText)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(merchantName)
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

                Text(folderName)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    private var extractedItemsCard: some View {
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
                        Text(CurrencyParser.formatAmount(item.amount))
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(primaryText)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var receiptImageCard: some View {
        if let firstImageURL = note.imageUrls.first, let url = URL(string: firstImageURL) {
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
            .padding(16)
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

    private var rawContentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Note Content")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryText)

            Text(note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No content" : note.content)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.emailLightChipIdle.opacity(0.55))
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
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
            .buttonStyle(PlainButtonStyle())

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
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
