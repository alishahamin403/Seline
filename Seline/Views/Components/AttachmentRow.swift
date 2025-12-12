import SwiftUI
import QuickLook

struct AttachmentRow: View {
    let attachment: EmailAttachment
    let emailMessageId: String? // Gmail message ID for downloading attachment
    @Environment(\.colorScheme) var colorScheme
    @State private var downloadedURL: URL?
    @State private var isDownloading = false
    @State private var showShareSheet = false
    @State private var showQuickLook = false

    var body: some View {
        Button(action: {
            openAttachment()
        }) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: attachment.systemIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
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
                        .foregroundColor(Color.gray.opacity(0.6))
                }

                Spacer()

                // Loading or view indicator
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                    .fill(
                        colorScheme == .dark ?
                            Color(white: 0.15) :
                            Color(white: 0.95)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                    .stroke(
                        colorScheme == .dark ?
                            Color(white: 0.25) :
                            Color(white: 0.85),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                downloadAndShare()
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(action: {
                openAttachment()
            }) {
                Label("Open", systemImage: "eye")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = downloadedURL {
                ShareSheet(activityItems: [url])
            }
        }
    .presentationBg()
        .sheet(isPresented: $showQuickLook) {
            if let url = downloadedURL {
                QuickLookView(url: url)
            }
        }
    .presentationBg()
    }

    private func openAttachment() {
        Task {
            await downloadAndView()
        }
    }

    private func downloadAndShare() {
        Task {
            if let url = await downloadAttachment() {
                await MainActor.run {
                    downloadedURL = url
                    showShareSheet = true
                }
            }
        }
    }

    private func downloadAndView() async {
        if let url = await downloadAttachment() {
            await MainActor.run {
                downloadedURL = url
                showQuickLook = true
            }
        }
    }

    private func downloadAttachment() async -> URL? {
        guard let messageId = emailMessageId else {
            print("❌ No email message ID provided for attachment download")
            return nil
        }

        await MainActor.run {
            isDownloading = true
        }

        do {
            // Download attachment from Gmail API
            guard let data = try await GmailAPIClient.shared.downloadAttachment(
                messageId: messageId,
                attachmentId: attachment.id
            ) else {
                print("❌ Failed to download attachment from Gmail: no data returned")
                await MainActor.run {
                    isDownloading = false
                }
                return nil
            }

            // Save to temporary directory
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(attachment.name)

            try data.write(to: fileURL)

            await MainActor.run {
                isDownloading = false
            }

            print("✅ Downloaded attachment: \(attachment.name)")
            return fileURL

        } catch {
            print("❌ Failed to download attachment: \(error)")
            await MainActor.run {
                isDownloading = false
            }
            return nil
        }
    }
}

// MARK: - QuickLook View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookView

        init(_ parent: QuickLookView) {
            self.parent = parent
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as QLPreviewItem
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
            ),
            emailMessageId: nil
        )

        AttachmentRow(
            attachment: EmailAttachment(
                id: "2",
                name: "Project_Timeline.xlsx",
                size: 512000,
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                url: nil
            ),
            emailMessageId: nil
        )

        AttachmentRow(
            attachment: EmailAttachment(
                id: "3",
                name: "screenshot.png",
                size: 1024000,
                mimeType: "image/png",
                url: nil
            ),
            emailMessageId: nil
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}