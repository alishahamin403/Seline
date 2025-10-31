import Foundation
import PostgREST
import Storage
import PDFKit

class AttachmentService: ObservableObject {
    static let shared = AttachmentService()

    @Published var attachments: [NoteAttachment] = []
    @Published var extractedDataCache: [UUID: ExtractedData] = [:] // Cache by attachmentId
    @Published var isLoading = false

    private let attachmentStorageBucket = "note-attachments"
    private let maxFileSizeBytes = 5 * 1024 * 1024 // 5MB total per note
    private let authManager = AuthenticationManager.shared
    private let openAIService = OpenAIService.shared

    private init() {}

    // MARK: - File Operations

    /// Upload a file to Supabase Storage and create attachment record
    func uploadFileToNote(_ fileData: Data, fileName: String, fileType: String, noteId: UUID) async throws -> NoteAttachment {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "AttachmentService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Validate file size
        if fileData.count > maxFileSizeBytes {
            throw NSError(domain: "AttachmentService", code: 2, userInfo: [NSLocalizedDescriptionKey: "File size exceeds 5MB limit"])
        }

        // Generate unique storage path
        let timestamp = Int(Date().timeIntervalSince1970)
        let storagePath = "\(userId.uuidString)/\(noteId.uuidString)_\(timestamp)_\(fileName)"

        // Upload to Supabase Storage
        let storage = await SupabaseManager.shared.getStorageClient()
        print("📤 Uploading file: \(fileName)")
        print("📤 Storage path: \(storagePath)")
        print("📤 File size: \(fileData.count) bytes")
        print("📤 Bucket: \(attachmentStorageBucket)")
        try await storage
            .from(attachmentStorageBucket)
            .upload(storagePath, data: fileData, options: FileOptions(cacheControl: "3600"))

        // Create attachment record in database
        let attachment = try await createAttachmentRecord(
            noteId: noteId,
            userId: userId,
            fileName: fileName,
            fileSize: fileData.count,
            fileType: fileType,
            storagePath: storagePath
        )

        // Trigger extraction via Claude API
        Task {
            await extractFileContent(attachment: attachment, fileData: fileData, fileName: fileName)
        }

        return attachment
    }

    /// Download file from Supabase Storage
    func downloadFile(from storagePath: String) async throws -> Data {
        let storage = await SupabaseManager.shared.getStorageClient()
        let data = try await storage
            .from(attachmentStorageBucket)
            .download(path: storagePath)
        return data
    }

    /// Delete attachment and associated extracted data
    func deleteAttachment(_ attachment: NoteAttachment) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "AttachmentService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Delete from storage
        let storage = await SupabaseManager.shared.getStorageClient()
        try await storage
            .from(attachmentStorageBucket)
            .remove(paths: [attachment.storagePath])

        // Delete from database (cascades to extracted_data)
        let client = await SupabaseManager.shared.getPostgrestClient()
        try await client
            .from("attachments")
            .delete()
            .eq("id", value: attachment.id.uuidString)
            .execute()

        // Remove from local cache
        attachments.removeAll { $0.id == attachment.id }
        extractedDataCache.removeValue(forKey: attachment.id)

        print("✅ Deleted attachment: \(attachment.fileName)")
    }

    // MARK: - Attachment Records

    private func createAttachmentRecord(
        noteId: UUID,
        userId: UUID,
        fileName: String,
        fileSize: Int,
        fileType: String,
        storagePath: String
    ) async throws -> NoteAttachment {
        let attachmentId = UUID()
        let now = Date()
        let formatter = ISO8601DateFormatter()

        let attachmentData: [String: PostgREST.AnyJSON] = [
            "id": .string(attachmentId.uuidString),
            "user_id": .string(userId.uuidString),
            "note_id": .string(noteId.uuidString),
            "file_name": .string(fileName),
            "file_size": .integer(fileSize),
            "file_type": .string(fileType),
            "storage_path": .string(storagePath),
            "uploaded_at": .string(formatter.string(from: now)),
            "created_at": .string(formatter.string(from: now)),
            "updated_at": .string(formatter.string(from: now))
        ]

        let client = await SupabaseManager.shared.getPostgrestClient()
        try await client
            .from("attachments")
            .insert(attachmentData)
            .execute()

        let attachment = NoteAttachment(
            id: attachmentId,
            noteId: noteId,
            fileName: fileName,
            fileSize: fileSize,
            fileType: fileType,
            storagePath: storagePath,
            documentType: nil,
            uploadedAt: now,
            createdAt: now,
            updatedAt: now
        )

        await MainActor.run {
            self.attachments.append(attachment)
        }

        return attachment
    }

    // MARK: - Extracted Data

    /// Load extracted data for an attachment
    func loadExtractedData(for attachmentId: UUID) async throws -> ExtractedData? {
        let client = await SupabaseManager.shared.getPostgrestClient()
        let response: [ExtractedDataSupabaseData] = try await client
            .from("extracted_data")
            .select()
            .eq("attachment_id", value: attachmentId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let data = response.first,
              let extracted = ExtractedData(from: data) else {
            return nil
        }

        await MainActor.run {
            self.extractedDataCache[attachmentId] = extracted
        }

        return extracted
    }

    /// Update extracted data fields (user edited)
    func updateExtractedData(_ data: ExtractedData) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "AttachmentService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let formatter = ISO8601DateFormatter()
        let updatedData: [String: PostgREST.AnyJSON] = [
            "extracted_fields": try convertToAnyJSON(data.extractedFields),
            "is_edited": .bool(true),
            "updated_at": .string(formatter.string(from: Date()))
        ]

        let client = await SupabaseManager.shared.getPostgrestClient()
        try await client
            .from("extracted_data")
            .update(updatedData)
            .eq("id", value: data.id.uuidString)
            .execute()

        await MainActor.run {
            self.extractedDataCache[data.attachmentId] = data
        }

        print("✅ Updated extracted data for attachment: \(data.attachmentId.uuidString)")
    }

    // MARK: - File Extraction via OpenAI

    private func extractFileContent(attachment: NoteAttachment, fileData: Data, fileName: String) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ User not authenticated, cannot extract")
            return
        }

        do {
            print("📨 Extracting content from \(fileName)...")

            let documentType = detectDocumentType(fileName)
            let prompt = buildExtractionPrompt(fileName: fileName, documentType: documentType)

            // Convert file data to text for extraction
            let fileContent = extractTextFromFileData(fileData, fileName: fileName)

            // Call OpenAI to extract detailed content
            let responseText = try await openAIService.extractDetailedDocumentContent(
                fileContent,
                withPrompt: prompt,
                fileName: fileName
            )

            // Store extracted data in database
            let extractedId = UUID()
            let now = Date()
            let formatter = ISO8601DateFormatter()

            let extractedDataRecord: [String: PostgREST.AnyJSON] = [
                "id": .string(extractedId.uuidString),
                "user_id": .string(userId.uuidString),
                "attachment_id": .string(attachment.id.uuidString),
                "document_type": .string(documentType),
                "extracted_fields": try convertToAnyJSON(["summary": responseText]),
                "raw_text": .string(responseText),
                "confidence": .double(0.9),
                "is_edited": .bool(false),
                "created_at": .string(formatter.string(from: now)),
                "updated_at": .string(formatter.string(from: now))
            ]

            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("extracted_data")
                .insert(extractedDataRecord)
                .execute()

            // Update attachment with document type
            let updateData: [String: PostgREST.AnyJSON] = [
                "document_type": .string(documentType),
                "updated_at": .string(formatter.string(from: Date()))
            ]

            try await client
                .from("attachments")
                .update(updateData)
                .eq("id", value: attachment.id.uuidString)
                .execute()

            print("✅ Successfully extracted data from \(fileName) as \(documentType)")

        } catch let error as NSError {
            // Provide specific error messages for common issues
            if error.code == NSURLErrorTimedOut {
                print("⏱️ Extraction timeout: Request took too long to process. This is normal for very large files.")
                print("💡 Tip: The file was still uploaded successfully. You can try again in a moment.")
            } else if error.domain == NSURLErrorDomain {
                print("⚠️ Network error during extraction: \(error.localizedDescription)")
            } else {
                print("❌ Failed to extract file: \(error.localizedDescription)")
            }
        } catch {
            print("❌ Failed to extract file: \(error.localizedDescription)")
        }
    }

    private func detectDocumentType(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("bank") || lower.contains("statement") || lower.contains("account") {
            return "bank_statement"
        } else if lower.contains("invoice") || lower.contains("bill") {
            return "invoice"
        } else if lower.contains("receipt") || lower.contains("order") {
            return "receipt"
        }
        return "document"
    }

    /// Extracts text content from file data based on file type
    /// Handles PDF text extraction using PDFKit, CSV, plain text, and provides fallback for binary formats
    private func extractTextFromFileData(_ fileData: Data, fileName: String) -> String {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        // For text-based files, try direct conversion
        switch fileExtension {
        case "txt", "csv", "json", "xml", "log":
            // Try to convert directly to string
            if let textContent = String(data: fileData, encoding: .utf8) {
                return textContent
            }
            // Fallback to other encodings
            if let textContent = String(data: fileData, encoding: .isoLatin1) {
                return textContent
            }
            return "[File could not be converted to text.]"

        case "pdf":
            // Extract text from PDF using PDFKit
            if let pdfDocument = PDFDocument(data: fileData) {
                var extractedText = ""
                let pageCount = pdfDocument.pageCount

                for pageIndex in 0..<pageCount {
                    if let page = pdfDocument.page(at: pageIndex) {
                        if let pageText = page.string {
                            extractedText += "--- Page \(pageIndex + 1) ---\n"
                            extractedText += pageText
                            extractedText += "\n\n"
                        }
                    }
                }

                if !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("✅ Extracted \(extractedText.count) characters from PDF")
                    return extractedText
                } else {
                    return "[PDF file found but contains no extractable text. File size: \(fileData.count) bytes]"
                }
            } else {
                return "[Error: Could not parse PDF file. File may be corrupted or encrypted.]"
            }

        case "xlsx", "xls":
            // For Excel files, try UTF-8 conversion as fallback
            if let textContent = String(data: fileData, encoding: .utf8) {
                // Extract readable parts from the UTF-8 conversion
                let cleanedContent = textContent.replacingOccurrences(of: "\u{0}", with: "")
                if !cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return cleanedContent
                }
            }
            return "[Excel file detected but text extraction not available. Please export to CSV or use a converter.]"

        default:
            // For other file types, try UTF-8 conversion first
            if let textContent = String(data: fileData, encoding: .utf8) {
                let cleaned = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count > 20 {
                    return cleaned
                }
            }

            return "[Binary file (.\(fileExtension)) - automatic text extraction not available. File size: \(fileData.count) bytes]"
        }
    }

    private func buildExtractionPrompt(fileName: String, documentType: String) -> String {
        let base = "Extract the complete detailed content from the following \(documentType) file named \(fileName). Provide comprehensive text that captures all information, not just a summary.\n\n"

        switch documentType {
        case "bank_statement":
            return base + """
            Extract ONLY the transaction details from this bank statement. EXCLUDE all header information, account details, promotional messages, legal disclaimers, and notes.

            Format the output as:
            1. Summary section (one line each):
               - Statement Period: [dates]
               - Opening Balance: [amount]
               - Closing Balance: [amount]

            2. Individual Transactions (each on its own line):
               Date | Description | Amount | Balance (if available)

            CRITICAL INSTRUCTIONS:
            - Extract EVERY transaction individually, one per line
            - Each transaction line must have: DATE | DESCRIPTION | AMOUNT | BALANCE
            - Do NOT group transactions by category
            - Do NOT include headers, footers, or bank marketing messages
            - Do NOT include account details or card numbers
            - Do NOT include disclaimers or terms
            - Do NOT create tables or complex formatting
            - Simple pipe-delimited format ONLY
            - Include deposit and withdrawal amounts with their signs (+ or -)
            - Sort transactions by date (oldest to newest or as appears in statement)

            Start directly with the summary, then list each transaction.
            """

        case "invoice":
            return base + """
            Extract ALL information from this invoice including:
            - Complete vendor/seller information
            - Invoice number, date, and due date
            - Complete bill-to and ship-to addresses
            - EVERY line item with full description, quantity, unit price, and total price
            - Subtotal amount
            - All taxes and tax details
            - All fees and charges with descriptions
            - Total amount due
            - Payment terms and methods
            - Any notes, terms, or special instructions

            Provide complete detailed text of ALL line items, not a summary.
            """

        case "receipt":
            return base + """
            Extract ALL information from this receipt including:
            - Complete merchant information (name, address, phone, website if available)
            - Transaction date and time
            - Receipt/transaction number
            - EVERY item purchased with full description, quantity, and individual price
            - Subtotal amount
            - Tax amount and tax details
            - Total paid
            - Payment method used
            - Cashier/register information if available
            - Any loyalty program or promotional information
            - Return policy or other notes

            Provide complete detailed text of ALL items purchased, not a summary.
            """

        default:
            return base + """
            Extract the COMPLETE detailed content and all information from this document. Include:
            - All text content in a structured format
            - All sections and subsections
            - All data, numbers, and values
            - All important details and information

            Provide comprehensive extraction of all content, not a summary or highlights only.
            """
        }
    }

    // MARK: - Helper Functions

    private func convertToAnyJSON(_ object: Any) throws -> PostgREST.AnyJSON {
        if let dict = object as? [String: Any] {
            var result: [String: PostgREST.AnyJSON] = [:]
            for (key, value) in dict {
                result[key] = try convertToAnyJSON(value)
            }
            return .object(result)
        } else if let array = object as? [Any] {
            return .array(try array.map { try convertToAnyJSON($0) })
        } else if let string = object as? String {
            return .string(string)
        } else if let bool = object as? Bool {
            return .bool(bool)
        } else if let number = object as? NSNumber {
            if CFNumberGetType(number as CFNumber) == .charType {
                return .bool(number.boolValue)
            }
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return .integer(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        } else if object is NSNull {
            return .null
        }
        throw NSError(domain: "ConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported type"])
    }

    // MARK: - Data Loading

    func loadAttachmentsForNote(_ noteId: UUID) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return
        }

        let client = await SupabaseManager.shared.getPostgrestClient()
        let response: [AttachmentSupabaseData] = try await client
            .from("attachments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("note_id", value: noteId.uuidString)
            .execute()
            .value

        let attachments = response.compactMap { NoteAttachment(from: $0) }

        await MainActor.run {
            self.attachments = attachments
        }
    }
}
