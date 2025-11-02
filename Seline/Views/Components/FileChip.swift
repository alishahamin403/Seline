import SwiftUI

struct FileChip: View {
    let attachment: NoteAttachment
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: attachment.fileTypeIcon)
                    .font(.headline)
                    .foregroundColor(.gray)
                    .frame(width: 20)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(attachment.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .onTapGesture(perform: onTap)
        }
    }
}

#Preview {
    FileChip(
        attachment: NoteAttachment(
            id: UUID(),
            noteId: UUID(),
            fileName: "statement.pdf",
            fileSize: 2_300_000,
            fileType: "pdf",
            storagePath: "test/file.pdf",
            documentType: "bank_statement",
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        ),
        onTap: { print("Tapped") },
        onDelete: { print("Deleted") }
    )
}
