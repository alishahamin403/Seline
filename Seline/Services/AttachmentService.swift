import Foundation
import PostgREST

class AttachmentService: ObservableObject {
    static let shared = AttachmentService()

    @Published var attachments: [NoteAttachment] = []
    @Published var extractedDataCache: [UUID: ExtractedData] = [:] // Cache by attachmentId
    @Published var isLoading = false

    private let attachmentStorageBucket = "note-attachments"
    private let maxFileSizeBytes = 5 * 1024 * 1024 // 5MB total per note
    private let authManager = AuthenticationManager.shared

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

    // MARK: - Claude API Integration

    private func extractFileContent(attachment: NoteAttachment, fileData: Data, fileName: String) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ User not authenticated, cannot extract")
            return
        }

        do {
            print("📨 Extracting content from \(fileName)...")

            // Convert file to Claude-compatible format
            let fileContent = try convertFileToClaudeFormat(fileData, fileName: fileName)
            let documentType = detectDocumentType(fileName)

            // Call Claude API
            let extractedData = try await callClaudeForExtraction(
                fileContent: fileContent,
                documentType: documentType
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
                "extracted_fields": try convertToAnyJSON(extractedData.fields),
                "raw_text": .string(extractedData.rawText),
                "confidence": .double(extractedData.confidence),
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

    private func convertFileToClaudeFormat(_ data: Data, fileName: String) throws -> (type: String, data: String, mediaType: String?) {
        let ext = (fileName as NSString).pathExtension.lowercased()

        if ["pdf", "jpg", "jpeg", "png", "gif"].contains(ext) {
            // Convert to base64 for image/PDF
            let base64 = data.base64EncodedString()
            return (type: "image", data: base64, mediaType: getMediaType(ext))
        } else if ["csv", "txt"].contains(ext) {
            // Text files
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "AttachmentService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not decode text file"])
            }
            return (type: "text", data: text, mediaType: nil)
        } else {
            throw NSError(domain: "AttachmentService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(ext)"])
        }
    }

    private func getMediaType(_ ext: String) -> String {
        let types: [String: String] = [
            "pdf": "application/pdf",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif"
        ]
        return types[ext] ?? "application/octet-stream"
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

    private func callClaudeForExtraction(
        fileContent: (type: String, data: String, mediaType: String?),
        documentType: String
    ) async throws -> (fields: [String: AnyCodable], rawText: String, confidence: Double) {
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw NSError(domain: "AttachmentService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing ANTHROPIC_API_KEY environment variable"])
        }

        let prompt = getExtractionPrompt(documentType)

        // Build message content
        var messageContent: [[String: Any]] = []

        if fileContent.type == "image", let mediaType = fileContent.mediaType {
            messageContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": fileContent.data
                ]
            ])
        } else {
            messageContent.append([
                "type": "text",
                "text": fileContent.data
            ])
        }

        messageContent.append([
            "type": "text",
            "text": prompt
        ])

        // Call Claude API
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 2000,
            "messages": [
                [
                    "role": "user",
                    "content": messageContent
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AttachmentService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Claude API error: \(errorText)"])
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let responseText = firstContent["text"] as? String else {
            throw NSError(domain: "AttachmentService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude response"])
        }

        // Extract JSON from response
        let jsonPattern = "\\{[\\s\\S]*\\}"
        let regex = try NSRegularExpression(pattern: jsonPattern)
        let range = NSRange(responseText.startIndex..<responseText.endIndex, in: responseText)
        guard let match = regex.firstMatch(in: responseText, range: range),
              let jsonRange = Range(match.range, in: responseText) else {
            throw NSError(domain: "AttachmentService", code: 8, userInfo: [NSLocalizedDescriptionKey: "No JSON found in Claude response"])
        }

        let jsonString = String(responseText[jsonRange])
        guard let jsonData = jsonString.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "AttachmentService", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to parse extracted JSON"])
        }

        // Convert to our model
        let fields = (parsed["fields"] as? [String: Any]) ?? [:]
        let rawText = (parsed["rawText"] as? String) ?? ""
        let confidence = (parsed["confidence"] as? Double) ?? 0.8

        // Convert fields to AnyCodable
        var anyCodableFields: [String: AnyCodable] = [:]
        for (key, value) in fields {
            anyCodableFields[key] = AnyCodable(value: value)
        }

        return (fields: anyCodableFields, rawText: rawText, confidence: confidence)
    }

    private func getExtractionPrompt(_ documentType: String) -> String {
        let base = """
        Extract structured information from the provided \(documentType).
        Return ONLY a valid JSON object with this structure:
        {
          "fields": { /* extracted key-value pairs */ },
          "rawText": "Full raw text from the document",
          "confidence": 0.95
        }
        """

        switch documentType {
        case "bank_statement":
            return base + """

            Bank Statement specific fields:
            - accountNumber (masked as ****XXXX)
            - statementPeriodStart (ISO date string)
            - statementPeriodEnd (ISO date string)
            - openingBalance (number)
            - closingBalance (number)
            - totalDeposits (number)
            - totalWithdrawals (number)
            - transactionCount (number)
            - interestEarned (number)
            - feesCharged (number)
            """

        case "invoice":
            return base + """

            Invoice specific fields:
            - vendorName
            - invoiceNumber
            - invoiceDate (ISO date string)
            - dueDate (ISO date string)
            - subtotal (number)
            - taxAmount (number)
            - totalAmount (number)
            - paymentTerms
            """

        case "receipt":
            return base + """

            Receipt specific fields:
            - merchantName
            - transactionDate (ISO date string)
            - transactionTime
            - subtotal (number)
            - tax (number)
            - totalPaid (number)
            - paymentMethod
            """

        default:
            return base
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
