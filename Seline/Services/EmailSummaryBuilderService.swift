import Foundation
import PDFKit
import UIKit
import Vision

struct EmailSummaryInputContext {
    let bodyForSummary: String
    let analyzedSources: [String]
    let skippedSources: [String]
    let confidenceHint: String
}

actor EmailSummaryBuilderService {
    static let shared = EmailSummaryBuilderService()

    private init() {}

    func buildContext(for email: Email) async -> EmailSummaryInputContext {
        var analyzedSources: [String] = []
        var skippedSources: [String] = []
        var baseBody = fallbackBody(for: email)

        if let messageId = email.gmailMessageId {
            do {
                if let fetchedBody = try await GmailAPIClient.shared.fetchBodyForAI(messageId: messageId),
                   !fetchedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    baseBody = fetchedBody
                    analyzedSources.append("Full email body")
                } else {
                    analyzedSources.append("Email snippet")
                }
            } catch {
                analyzedSources.append("Email snippet")
                skippedSources.append("Full body fetch failed")
            }
        } else {
            analyzedSources.append("Email body/snippet")
        }

        let attachmentExtracts = await extractAttachmentContext(for: email, skippedSources: &skippedSources, analyzedSources: &analyzedSources)

        var combinedBody = baseBody
        if !attachmentExtracts.isEmpty {
            combinedBody += "\n\nATTACHMENT CONTENT EXTRACTS:\n"
            combinedBody += attachmentExtracts.joined(separator: "\n\n---\n\n")
        }

        if !analyzedSources.isEmpty || !skippedSources.isEmpty {
            combinedBody += "\n\nSUMMARY METADATA:\n"
            if !analyzedSources.isEmpty {
                combinedBody += "Analyzed sources: \(analyzedSources.joined(separator: ", "))\n"
            }
            if !skippedSources.isEmpty {
                combinedBody += "Partially parsed sources: \(skippedSources.joined(separator: ", "))\n"
            }
        }

        return EmailSummaryInputContext(
            bodyForSummary: combinedBody.trimmingCharacters(in: .whitespacesAndNewlines),
            analyzedSources: analyzedSources,
            skippedSources: skippedSources,
            confidenceHint: confidenceHint(baseBody: baseBody, skippedSources: skippedSources)
        )
    }

    private func fallbackBody(for email: Email) -> String {
        let body = email.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !body.isEmpty {
            return body
        }
        return email.snippet
    }

    private func extractAttachmentContext(
        for email: Email,
        skippedSources: inout [String],
        analyzedSources: inout [String]
    ) async -> [String] {
        guard !email.attachments.isEmpty else { return [] }
        guard let messageId = email.gmailMessageId else {
            skippedSources.append(contentsOf: email.attachments.prefix(3).map { "Attachment unavailable: \($0.name)" })
            return []
        }

        var extracts: [String] = []
        for attachment in email.attachments.prefix(3) {
            do {
                guard let fileData = try await GmailAPIClient.shared.downloadAttachment(
                    messageId: messageId,
                    attachmentId: attachment.id
                ), !fileData.isEmpty else {
                    skippedSources.append("Attachment missing: \(attachment.name)")
                    continue
                }

                guard let extractedText = await extractText(from: fileData, attachment: attachment),
                      extractedText.count > 24 else {
                    skippedSources.append("Attachment not readable: \(attachment.name)")
                    continue
                }

                analyzedSources.append("Attachment: \(attachment.name)")
                extracts.append("[Attachment: \(attachment.name)]\n\(String(extractedText.prefix(2200)))")
            } catch {
                skippedSources.append("Attachment fetch failed: \(attachment.name)")
            }
        }

        return extracts
    }

    private func extractText(from fileData: Data, attachment: EmailAttachment) async -> String? {
        let ext = attachment.fileExtension.lowercased()
        let mimeType = attachment.mimeType.lowercased()

        if ext == "pdf" || mimeType == "application/pdf" {
            return extractPDFText(fileData)
        }

        if isImageAttachment(ext: ext, mimeType: mimeType) {
            return await extractImageText(fileData)
        }

        if isTextAttachment(ext: ext, mimeType: mimeType) {
            return decodeText(fileData, looksLikeHTML: ext == "html" || mimeType.contains("html"))
        }

        return nil
    }

    private func isImageAttachment(ext: String, mimeType: String) -> Bool {
        let imageExts = ["jpg", "jpeg", "png", "webp", "heic", "gif", "bmp", "tiff"]
        return imageExts.contains(ext) || mimeType.hasPrefix("image/")
    }

    private func isTextAttachment(ext: String, mimeType: String) -> Bool {
        let textExts = ["txt", "csv", "md", "json", "xml", "html", "htm"]
        return textExts.contains(ext) ||
            mimeType.hasPrefix("text/") ||
            mimeType.contains("json") ||
            mimeType.contains("xml")
    }

    private func decodeText(_ data: Data, looksLikeHTML: Bool) -> String? {
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)

        guard var text = decoded?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        if looksLikeHTML || text.contains("<html") || text.contains("<body") {
            text = stripHTML(text)
        }

        return text
    }

    private func extractPDFText(_ data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }

        let pageCount = min(document.pageCount, 5)
        var extracted: [String] = []
        for index in 0..<pageCount {
            if let pageText = document.page(at: index)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                extracted.append(pageText)
            }
        }

        guard !extracted.isEmpty else { return nil }
        return extracted.joined(separator: "\n\n")
    }

    private func extractImageText(_ data: Data) async -> String? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let merged = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: merged.isEmpty ? nil : merged)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func stripHTML(_ html: String) -> String {
        var text = html

        text = text.replacingOccurrences(
            of: "<(script|style|noscript)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</(p|div|li|tr|h[1-6])>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]

        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confidenceHint(baseBody: String, skippedSources: [String]) -> String {
        let hasBody = !baseBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBody && skippedSources.isEmpty {
            return "High"
        }
        if hasBody {
            return "Medium"
        }
        return "Low"
    }
}
