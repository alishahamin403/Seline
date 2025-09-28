import SwiftUI

struct AttachmentRow: View {
    let attachment: EmailAttachment
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            openAttachment()
        }) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: attachment.systemIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.518, green: 0.792, blue: 0.914) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
                    )
                    .frame(width: 24, height: 24)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(attachment.formattedSize)
                        .font(FontManager.geist(size: .small, weight: .regular))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }

                Spacer()

                // View indicator
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                    .fill(
                        colorScheme == .dark ?
                            Color.shadcnMuted(colorScheme).opacity(0.2) :
                            Color.shadcnBackground(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                    .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func openAttachment() {
        // In a real implementation, this would:
        // 1. Download the attachment if needed
        // 2. Open it in the appropriate viewer
        // 3. For images, show in a photo viewer
        // 4. For PDFs, open in PDF viewer
        // 5. For other files, use QuickLook or external app

        print("Opening attachment: \(attachment.name)")

        // For now, we'll just show an alert indicating the action
        // In production, you would implement proper file handling here

        if attachment.isImage {
            // Open image viewer
            print("📸 Opening image: \(attachment.name)")
        } else if attachment.isPDF {
            // Open PDF viewer
            print("📄 Opening PDF: \(attachment.name)")
        } else {
            // Open with system default app
            print("📎 Opening file: \(attachment.name)")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AttachmentRow(
            attachment: EmailAttachment(
                id: "1",
                name: "Q4_Report.pdf",
                size: 2048576,
                mimeType: "application/pdf",
                url: nil
            )
        )

        AttachmentRow(
            attachment: EmailAttachment(
                id: "2",
                name: "Project_Timeline.xlsx",
                size: 512000,
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                url: nil
            )
        )

        AttachmentRow(
            attachment: EmailAttachment(
                id: "3",
                name: "screenshot.png",
                size: 1024000,
                mimeType: "image/png",
                url: nil
            )
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}