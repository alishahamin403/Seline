import SwiftUI

struct ExtractionDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var extractedData: ExtractedData
    @State var isSaving = false

    var onSave: (ExtractedData) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Document type header
                Section("Document Info") {
                    HStack {
                        Text("Type")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(extractedData.documentType.capitalized)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Confidence")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(Int(extractedData.confidence * 100))%")
                            .foregroundColor(.secondary)
                    }
                }

                // Extracted fields
                Section("Extracted Data") {
                    if extractedData.extractedFields.isEmpty {
                        Text("No data extracted")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(extractedData.extractedFields.sorted { $0.key < $1.key }), id: \.key) { key, value in
                            ExtractedFieldRow(
                                label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                                value: formatValue(value.value)
                            )
                        }
                    }
                }

                // Raw text preview
                if let rawText = extractedData.rawText, !rawText.isEmpty {
                    Section("Raw Text") {
                        Text(rawText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(5)
                    }
                }
            }
            .navigationTitle("Extracted Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if extractedData.isEdited {
                            isSaving = true
                            onSave(extractedData)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                dismiss()
                            }
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatValue(_ value: Any) -> String {
        if let str = value as? String {
            return str
        } else if let num = value as? NSNumber {
            return num.stringValue
        } else if let dict = value as? [String: Any] {
            return "[\(dict.count) items]"
        } else if let array = value as? [Any] {
            return "[\(array.count) items]"
        }
        return "\(value)"
    }
}

struct ExtractedFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExtractionDetailSheet(
        extractedData: ExtractedData(
            id: UUID(),
            attachmentId: UUID(),
            documentType: "receipt",
            extractedFields: [
                "merchantName": AnyCodable(value: "Whole Foods"),
                "totalPaid": AnyCodable(value: 87.54),
                "items": AnyCodable(value: 6)
            ],
            rawText: "Sample receipt text...",
            confidence: 0.92,
            isEdited: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onSave: { data in print("Saved") }
    )
}
