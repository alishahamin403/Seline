import Foundation
import PostgREST
import Storage

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

            // Call OpenAI to extract
            let responseText = try await openAIService.summarizeEmail(subject: fileName, body: prompt)

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

    private func buildExtractionPrompt(fileName: String, documentType: String) -> String {
        let base = "Extract key information from the following \(documentType) file named \(fileName).\n"

        switch documentType {
        case "bank_statement":
            return base + """
            Extract: account number (masked), statement period, opening/closing balance, total deposits/withdrawals, interest earned, fees, and number of transactions.
            """

        case "invoice":
            return base + """
            Extract: vendor name, invoice number, invoice date, due date, line items with quantities and prices, subtotal, tax amount, and total amount.
            """

        case "receipt":
            return base + """
            Extract: merchant name, transaction date and time, items purchased with quantities and prices, subtotal, tax, total paid, and payment method.
            """

        default:
            return base + "Extract the most important details and key information."
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
