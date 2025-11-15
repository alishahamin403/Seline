import Foundation
import PostgREST

actor EmailFolderService {
    static let shared = EmailFolderService()

    private let supabaseManager = SupabaseManager.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Folder Operations

    /// Create a new email folder
    func createFolder(name: String, color: String = "#84cae9") async throws -> CustomEmailFolder {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let folder = CustomEmailFolder(
            id: UUID(),
            userId: userId,
            name: name,
            color: color,
            createdAt: Date(),
            updatedAt: Date(),
            isImportedLabel: false,
            gmailLabelId: nil,
            lastSyncedAt: nil,
            syncEnabled: false
        )

        let client = await supabaseManager.getPostgrestClient()

        let response = try await client
            .from("email_folders")
            .insert(folder)
            .select()
            .single()
            .execute()

        let decodedFolder = try decoder.decode(CustomEmailFolder.self, from: response.data)
        return decodedFolder
    }

    /// Fetch all folders for the current user
    func fetchFolders() async throws -> [CustomEmailFolder] {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("email_folders")
            .select()
            .order("created_at", ascending: false)
            .execute()

        let folders = try decoder.decode([CustomEmailFolder].self, from: response.data)
        return folders
    }

    /// Fetch a specific folder by ID
    func fetchFolder(id: UUID) async throws -> CustomEmailFolder {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("email_folders")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()

        let folder = try decoder.decode(CustomEmailFolder.self, from: response.data)
        return folder
    }

    /// Update a folder's name
    func renameFolder(id: UUID, newName: String) async throws -> CustomEmailFolder {
        let client = await supabaseManager.getPostgrestClient()

        struct UpdateData: Codable {
            let name: String
            let updated_at: String
        }

        let updateData = UpdateData(
            name: newName,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        let response = try await client
            .from("email_folders")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()

        let folder = try decoder.decode(CustomEmailFolder.self, from: response.data)
        return folder
    }

    /// Update a folder's color
    func updateFolderColor(id: UUID, color: String) async throws -> CustomEmailFolder {
        let client = await supabaseManager.getPostgrestClient()

        struct UpdateData: Codable {
            let color: String
            let updated_at: String
        }

        let updateData = UpdateData(
            color: color,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        let response = try await client
            .from("email_folders")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()

        let folder = try decoder.decode(CustomEmailFolder.self, from: response.data)
        return folder
    }

    /// Delete a folder
    func deleteFolder(id: UUID) async throws {
        let client = await supabaseManager.getPostgrestClient()
        try await client
            .from("email_folders")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Saved Email Operations

    /// Save an email to a folder
    func saveEmail(
        from email: Email,
        to folderId: UUID,
        with attachments: [SavedEmailAttachment] = [],
        aiSummary: String? = nil
    ) async throws -> SavedEmail {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let recipientEmails = email.recipients.map { $0.email }
        let ccEmails = email.ccRecipients.map { $0.email }

        let savedEmail = SavedEmail(
            id: UUID(),
            userId: userId,
            emailFolderId: folderId,
            gmailMessageId: email.gmailMessageId ?? email.id,
            subject: email.subject,
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            recipients: recipientEmails,
            ccRecipients: ccEmails,
            body: email.body,
            snippet: email.snippet,
            aiSummary: aiSummary,
            timestamp: email.timestamp,
            savedAt: Date(),
            updatedAt: Date(),
            gmailLabelIds: nil,
            attachments: attachments
        )

        let client = await supabaseManager.getPostgrestClient()

        let response = try await client
            .from("saved_emails")
            .insert(savedEmail)
            .select()
            .single()
            .execute()

        let decodedEmail = try decoder.decode(SavedEmail.self, from: response.data)
        return decodedEmail
    }

    /// Fetch all saved emails in a folder
    func fetchEmailsInFolder(folderId: UUID) async throws -> [SavedEmail] {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_emails")
            .select()
            .eq("email_folder_id", value: folderId.uuidString)
            .order("timestamp", ascending: false)
            .execute()

        let emails = try decoder.decode([SavedEmail].self, from: response.data)

        // Fetch attachments for each email
        var emailsWithAttachments = emails
        for (index, email) in emailsWithAttachments.enumerated() {
            do {
                let attachments = try await fetchAttachments(for: email.id)
                emailsWithAttachments[index].attachments = attachments
            } catch {
                // Continue without attachments if fetch fails
            }
        }

        return emailsWithAttachments
    }

    /// Fetch a specific saved email
    func fetchSavedEmail(id: UUID) async throws -> SavedEmail {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_emails")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()

        var email = try decoder.decode(SavedEmail.self, from: response.data)
        email.attachments = try await fetchAttachments(for: email.id)
        return email
    }

    /// Move a saved email to a different folder
    func moveEmail(id: UUID, toFolder folderId: UUID) async throws -> SavedEmail {
        let client = await supabaseManager.getPostgrestClient()

        struct UpdateData: Codable {
            let email_folder_id: String
            let updated_at: String
        }

        let updateData = UpdateData(
            email_folder_id: folderId.uuidString,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        let response = try await client
            .from("saved_emails")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()

        var email = try decoder.decode(SavedEmail.self, from: response.data)
        email.attachments = try await fetchAttachments(for: email.id)
        return email
    }

    /// Delete a saved email from a folder
    func deleteSavedEmail(id: UUID) async throws {
        let client = await supabaseManager.getPostgrestClient()
        try await client
            .from("saved_emails")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Search for saved emails in a folder
    func searchEmailsInFolder(folderId: UUID, query: String) async throws -> [SavedEmail] {
        let lowerQuery = query.lowercased()
        let allEmails = try await fetchEmailsInFolder(folderId: folderId)

        return allEmails.filter { email in
            email.subject.lowercased().contains(lowerQuery) ||
            email.senderEmail.lowercased().contains(lowerQuery) ||
            email.senderName?.lowercased().contains(lowerQuery) ?? false ||
            email.snippet?.lowercased().contains(lowerQuery) ?? false
        }
    }

    // MARK: - Attachment Operations

    /// Fetch attachments for a saved email
    func fetchAttachments(for emailId: UUID) async throws -> [SavedEmailAttachment] {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_email_attachments")
            .select()
            .eq("saved_email_id", value: emailId.uuidString)
            .order("uploaded_at", ascending: false)
            .execute()

        let attachments = try decoder.decode([SavedEmailAttachment].self, from: response.data)
        return attachments
    }

    /// Save an attachment for a saved email
    func saveAttachment(
        emailId: UUID,
        fileName: String,
        fileSize: Int64,
        mimeType: String?,
        storagePath: String
    ) async throws -> SavedEmailAttachment {
        let attachment = SavedEmailAttachment(
            id: UUID(),
            savedEmailId: emailId,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            storagePath: storagePath,
            uploadedAt: Date()
        )

        let client = await supabaseManager.getPostgrestClient()

        let response = try await client
            .from("saved_email_attachments")
            .insert(attachment)
            .select()
            .single()
            .execute()

        let decodedAttachment = try decoder.decode(SavedEmailAttachment.self, from: response.data)
        return decodedAttachment
    }

    /// Delete an attachment
    func deleteAttachment(id: UUID) async throws {
        let client = await supabaseManager.getPostgrestClient()
        try await client
            .from("saved_email_attachments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Statistics

    /// Get count of saved emails in a folder
    func getEmailCountInFolder(folderId: UUID) async throws -> Int {
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_emails")
            .select("id", head: true, count: .exact)
            .eq("email_folder_id", value: folderId.uuidString)
            .execute()

        return response.count ?? 0
    }
}
