import SwiftUI
import QuickLook

struct AttachmentRow: View {
    let attachment: EmailAttachment
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

                // Loading or view indicator
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
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
        .sheet(isPresented: $showQuickLook) {
            if let url = downloadedURL {
                QuickLookView(url: url)
            }
        }
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
        guard let urlString = attachment.url,
              let downloadURL = URL(string: urlString) else {
            print("❌ Invalid attachment URL")
            return nil
        }

        await MainActor.run {
            isDownloading = true
        }

        do {
            // Download the file
            let (data, _) = try await URLSession.shared.data(from: downloadURL)

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