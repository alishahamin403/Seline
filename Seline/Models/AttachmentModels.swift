import Foundation
import PostgREST

// MARK: - Attachment Models

struct NoteAttachment: Identifiable, Codable, Hashable {
    var id: UUID
    var noteId: UUID
    var fileName: String
    var fileSize: Int // in bytes
    var fileType: String // pdf, image, csv, excel, other
    var storagePath: String
    var documentType: String? // bank_statement, invoice, receipt, etc
    var uploadedAt: Date
    var createdAt: Date
    var updatedAt: Date

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    var fileTypeIcon: String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.pdf"
        case "csv":
            return "tablecells"
        case "excel", "xlsx", "xls":
            return "tablecells"
        case "image", "jpg", "jpeg", "png", "gif":
            return "photo"
        default:
            return "doc"
        }
    }
}

struct ExtractedData: Identifiable, Codable, Hashable {
    var id: UUID
    var attachmentId: UUID
    var documentType: String // bank_statement, invoice, receipt
    var extractedFields: [String: AnyCodable] // dynamic based on document type
    var rawText: String? // for full-text search
    var confidence: Double
    var isEdited: Bool
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Bank Statement Specific Fields

    struct BankStatementData: Codable, Hashable {
        var accountNumber: String?
        var accountNumberMasked: String? // ••••5678
        var statementPeriodStart: Date?
        var statementPeriodEnd: Date?
        var openingBalance: Double?
        var closingBalance: Double?
        var totalDeposits: Double?
        var totalWithdrawals: Double?
        var transactionCount: Int?
        var interestEarned: Double?
        var feesCharged: Double?
        var transactions: [BankTransaction]?
    }

    struct BankTransaction: Codable, Hashable {
        var date: Date
        var description: String
        var amount: Double
        var type: String // debit, credit
        var balance: Double?
    }

    // MARK: - Invoice Specific Fields

    struct InvoiceData: Codable, Hashable {
        var vendorName: String?
        var invoiceNumber: String?
        var invoiceDate: Date?
        var dueDate: Date?
        var lineItems: [InvoiceLineItem]?
        var subtotal: Double?
        var taxAmount: Double?
        var totalAmount: Double?
        var paymentTerms: String?
    }

    struct InvoiceLineItem: Codable, Hashable {
        var description: String
        var quantity: Double
        var unitPrice: Double
        var totalPrice: Double
    }

    // MARK: - Receipt Specific Fields

    struct ReceiptData: Codable, Hashable {
        var merchantName: String?
        var transactionDate: Date?
        var transactionTime: String?
        var items: [ReceiptItem]?
        var subtotal: Double?
        var tax: Double?
        var totalPaid: Double?
        var paymentMethod: String?
    }

    struct ReceiptItem: Codable, Hashable {
        var description: String
        var quantity: Double
        var price: Double
    }

    // Helper to get typed extracted data
    func getBankStatementData() -> BankStatementData? {
        guard documentType == "bank_statement" else { return nil }
        // Convert extractedFields to BankStatementData
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        do {
            let jsonData = try encoder.encode(extractedFields)
            return try decoder.decode(BankStatementData.self, from: jsonData)
        } catch {
            return nil
        }
    }

    func getInvoiceData() -> InvoiceData? {
        guard documentType == "invoice" else { return nil }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        do {
            let jsonData = try encoder.encode(extractedFields)
            return try decoder.decode(InvoiceData.self, from: jsonData)
        } catch {
            return nil
        }
    }

    func getReceiptData() -> ReceiptData? {
        guard documentType == "receipt" else { return nil }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        do {
            let jsonData = try encoder.encode(extractedFields)
            return try decoder.decode(ReceiptData.self, from: jsonData)
        } catch {
            return nil
        }
    }
}

// MARK: - Supabase Data Structures

struct AttachmentSupabaseData: Codable {
    let id: String
    let user_id: String
    let note_id: String
    let file_name: String
    let file_size: Int
    let file_type: String
    let storage_path: String
    let document_type: String?
    let uploaded_at: String
    let created_at: String
    let updated_at: String
}

struct ExtractedDataSupabaseData: Codable {
    let id: String
    let user_id: String
    let attachment_id: String
    let document_type: String
    let extracted_fields: [String: AnyCodable]
    let raw_text: String?
    let confidence: Double
    let is_edited: Bool
    let created_at: String
    let updated_at: String
}

// MARK: - Conversion Helpers

extension NoteAttachment {
    init?(from data: AttachmentSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let noteId = UUID(uuidString: data.note_id) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let uploadedAt = formatter.date(from: data.uploaded_at) ?? ISO8601DateFormatter().date(from: data.uploaded_at),
              let createdAt = formatter.date(from: data.created_at) ?? ISO8601DateFormatter().date(from: data.created_at),
              let updatedAt = formatter.date(from: data.updated_at) ?? ISO8601DateFormatter().date(from: data.updated_at) else {
            return nil
        }

        self.id = id
        self.noteId = noteId
        self.fileName = data.file_name
        self.fileSize = data.file_size
        self.fileType = data.file_type
        self.storagePath = data.storage_path
        self.documentType = data.document_type
        self.uploadedAt = uploadedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ExtractedData {
    init?(from data: ExtractedDataSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let attachmentId = UUID(uuidString: data.attachment_id) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let createdAt = formatter.date(from: data.created_at) ?? ISO8601DateFormatter().date(from: data.created_at),
              let updatedAt = formatter.date(from: data.updated_at) ?? ISO8601DateFormatter().date(from: data.updated_at) else {
            return nil
        }

        self.id = id
        self.attachmentId = attachmentId
        self.documentType = data.document_type
        self.extractedFields = data.extracted_fields
        self.rawText = data.raw_text
        self.confidence = data.confidence
        self.isEdited = data.is_edited
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
