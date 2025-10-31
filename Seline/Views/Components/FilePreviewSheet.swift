import SwiftUI
import PDFKit
import QuickLook

struct FilePreviewSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with filename
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File Attachment")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))

                    // File preview area
                    if fileURL.pathExtension.lowercased() == "pdf" {
                        PDFPreviewView(fileURL: fileURL)
                    } else {
                        GenericFilePreviewView(fileURL: fileURL)
                    }

                    Spacer()
                }
            }
        }
    }
}

// MARK: - PDF Preview
struct PDFPreviewView: View {
    let fileURL: URL
    @State private var document: PDFDocument?

    var body: some View {
        ZStack {
            if let document = document {
                PDFKitRepresentable(document: document)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .onAppear {
                        document = PDFDocument(url: fileURL)
                    }
            }
        }
    }
}

// MARK: - PDFKit Representable
struct PDFKitRepresentable: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // No update needed
    }
}

// MARK: - Generic File Preview
struct GenericFilePreviewView: View {
    let fileURL: URL
    @State private var fileContent: String = ""

    var body: some View {
        VStack(spacing: 16) {
            if !fileContent.isEmpty {
                ScrollView {
                    Text(fileContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("File Preview Not Available")
                        .font(.system(size: 14, weight: .semibold))

                    Text("This file type cannot be previewed in-app")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text(fileURL.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            }
        }
        .padding(16)
        .onAppear {
            loadFileContent()
        }
    }

    private func loadFileContent() {
        let fileExtension = fileURL.pathExtension.lowercased()

        // Only show content for text-based files
        switch fileExtension {
        case "txt", "csv", "json", "xml", "log":
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                fileContent = content
            } else if let content = try? String(contentsOf: fileURL, encoding: .isoLatin1) {
                fileContent = content
            }
        default:
            fileContent = "" // No preview for other types
        }
    }
}

#Preview {
    FilePreviewSheet(fileURL: URL(fileURLWithPath: "/tmp/test.pdf"))
}
