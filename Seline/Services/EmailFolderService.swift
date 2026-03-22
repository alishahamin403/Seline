import Foundation
import PostgREST

actor EmailFolderService {
    static let shared = EmailFolderService()

    private enum MirrorStore {
        static let folderName = "__seline_email_mirror__"
        static let folderColor = "#111111"
    }

    private let supabaseManager = SupabaseManager.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    private struct SavedEmailIdentifier: Decodable {
        let id: UUID
    }

    private struct MirroredSummaryRecord: Decodable {
        let gmailMessageId: String
        let aiSummary: String?

        enum CodingKeys: String, CodingKey {
            case gmailMessageId = "gmail_message_id"
            case aiSummary = "ai_summary"
        }
    }

    private struct SavedEmailUpdatePayload: Encodable {
        let subject: String
        let sender_name: String?
        let sender_email: String
        let recipients: [String]
        let cc_recipients: [String]
        let body: String?
        let snippet: String?
        let ai_summary: String?
        let timestamp: String
        let updated_at: String
        let gmail_label_ids: [String]?
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
        return folders.filter { $0.name != MirrorStore.folderName }
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

        print("✅ Deleted folder \(id.uuidString) from Supabase")

        // Clear the folder cache so the deleted folder doesn't reappear on app rebuild
        await MainActor.run {
            EmailService.shared.clearFolderCache()
        }
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

        let gmailMessageId = email.gmailMessageId ?? email.id

        // Check if this email already exists in this folder
        let client = await supabaseManager.getPostgrestClient()
        do {
            let existingResponse = try await client
                .from("saved_emails")
                .select("id")
                .eq("email_folder_id", value: folderId.uuidString)
                .eq("gmail_message_id", value: gmailMessageId)
                .limit(1)
                .execute()

            let existingCount = existingResponse.count ?? 0
            if existingCount > 0 {
                print("ℹ️ Email \(gmailMessageId) already exists in folder \(folderId.uuidString), skipping duplicate")
                // Return existing email instead of creating duplicate
                let emails = try decoder.decode([SavedEmail].self, from: existingResponse.data)
                return emails.first ?? SavedEmail(
                    id: UUID(),
                    userId: userId,
                    emailFolderId: folderId,
                    gmailMessageId: gmailMessageId,
                    subject: email.subject,
                    senderName: email.sender.name,
                    senderEmail: email.sender.email,
                    recipients: [],
                    ccRecipients: [],
                    body: email.body,
                    snippet: email.snippet,
                    aiSummary: aiSummary,
                    timestamp: email.timestamp,
                    savedAt: Date(),
                    updatedAt: Date(),
                    gmailLabelIds: nil
                )
            }
        } catch {
            print("⚠️ Error checking for duplicate email: \(error)")
            // Continue with save attempt anyway
        }

        let recipientEmails = email.recipients.map { $0.email }
        let ccEmails = email.ccRecipients.map { $0.email }

        let savedEmail = SavedEmail(
            id: UUID(),
            userId: userId,
            emailFolderId: folderId,
            gmailMessageId: gmailMessageId,
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

        let response = try await client
            .from("saved_emails")
            .insert(savedEmail)
            .select()
            .single()
            .execute()

        var decodedEmail = try decoder.decode(SavedEmail.self, from: response.data)

        // CRITICAL FIX: Save attachments to the database
        // The attachments property is not a database column, so we need to insert them separately
        if !attachments.isEmpty {
            print("📎 Saving \(attachments.count) attachment(s) for email \(decodedEmail.id)")
            var savedAttachments: [SavedEmailAttachment] = []

            for attachment in attachments {
                do {
                    // Save each attachment to the saved_email_attachments table
                    let savedAttachment = try await saveAttachment(
                        emailId: decodedEmail.id,
                        fileName: attachment.fileName,
                        fileSize: attachment.fileSize,
                        mimeType: attachment.mimeType,
                        storagePath: attachment.storagePath
                    )
                    savedAttachments.append(savedAttachment)
                    print("✅ Saved attachment: \(attachment.fileName)")
                } catch {
                    print("❌ Failed to save attachment \(attachment.fileName): \(error)")
                    // Continue with other attachments even if one fails
                }
            }

            // Update the decodedEmail with the actual saved attachments
            decodedEmail.attachments = savedAttachments
        }

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

        // CRITICAL FIX: Fetch and delete attachment files from storage before deleting email
        do {
            let attachments = try await fetchAttachments(for: id)

            if !attachments.isEmpty {
                print("🗑️ Deleting \(attachments.count) attachment(s) from storage for email \(id)")

                // Delete attachment files from Supabase Storage
                let storage = await supabaseManager.getStorageClient()
                for attachment in attachments {
                    do {
                        try await storage
                            .from("email-attachments")
                            .remove(paths: [attachment.storagePath])
                        print("✅ Deleted attachment file: \(attachment.fileName)")
                    } catch {
                        // Log but continue - file might already be deleted
                        print("⚠️ Failed to delete attachment file \(attachment.fileName): \(error)")
                    }
                }
            }
        } catch {
            // Log but continue with email deletion even if attachment cleanup fails
            print("⚠️ Failed to fetch attachments for cleanup: \(error)")
        }

        // Delete the email (this will cascade delete attachment records via database foreign key constraint)
        try await client
            .from("saved_emails")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        print("✅ Deleted saved email \(id.uuidString) from database")

        // Clear email service cache to ensure UI refreshes properly
        await MainActor.run {
            EmailService.shared.clearFolderCache()
        }
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

    // MARK: - Hidden Mirror Store

    private func findMirrorFolder() async throws -> CustomEmailFolder? {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let client = await supabaseManager.getPostgrestClient()
        let existingResponse = try await client
            .from("email_folders")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("name", value: MirrorStore.folderName)
            .limit(1)
            .execute()

        let existingFolders = try decoder.decode([CustomEmailFolder].self, from: existingResponse.data)
        if let existingFolder = existingFolders.first {
            return existingFolder
        }

        return nil
    }

    private func ensureMirrorFolder() async throws -> CustomEmailFolder {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        if let existingFolder = try await findMirrorFolder() {
            return existingFolder
        }

        let client = await supabaseManager.getPostgrestClient()

        let folder = CustomEmailFolder(
            id: UUID(),
            userId: userId,
            name: MirrorStore.folderName,
            color: MirrorStore.folderColor,
            createdAt: Date(),
            updatedAt: Date(),
            isImportedLabel: false,
            gmailLabelId: nil,
            lastSyncedAt: nil,
            syncEnabled: false
        )

        let createResponse = try await client
            .from("email_folders")
            .insert(folder)
            .select()
            .single()
            .execute()

        return try decoder.decode(CustomEmailFolder.self, from: createResponse.data)
    }

    func fetchMirroredAISummaries(messageIds: [String]) async throws -> [String: String] {
        let uniqueIds = Array(Set(messageIds.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return [:] }

        guard let mirrorFolder = try await findMirrorFolder() else { return [:] }
        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_emails")
            .select("gmail_message_id,ai_summary")
            .eq("email_folder_id", value: mirrorFolder.id.uuidString)
            .in("gmail_message_id", values: uniqueIds)
            .execute()

        let records = try decoder.decode([MirroredSummaryRecord].self, from: response.data)
        return Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard let summary = record.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !summary.isEmpty else {
                    return nil
                }
                return (record.gmailMessageId, summary)
            }
        )
    }

    func upsertMirroredEmail(_ email: Email) async throws {
        let summary = email.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary, !summary.isEmpty else { return }

        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let mirrorFolder = try await ensureMirrorFolder()
        let client = await supabaseManager.getPostgrestClient()
        let remoteMessageId = email.gmailMessageId ?? email.id
        let now = Date()

        let existingResponse = try await client
            .from("saved_emails")
            .select("id")
            .eq("email_folder_id", value: mirrorFolder.id.uuidString)
            .eq("gmail_message_id", value: remoteMessageId)
            .limit(1)
            .execute()

        let existingRows = try decoder.decode([SavedEmailIdentifier].self, from: existingResponse.data)
        let recipients = email.recipients.map(\.email)
        let ccRecipients = email.ccRecipients.map(\.email)

        if let existingRow = existingRows.first {
            let payload = SavedEmailUpdatePayload(
                subject: email.subject,
                sender_name: email.sender.name,
                sender_email: email.sender.email,
                recipients: recipients,
                cc_recipients: ccRecipients,
                body: email.body,
                snippet: email.snippet,
                ai_summary: summary,
                timestamp: ISO8601DateFormatter().string(from: email.timestamp),
                updated_at: ISO8601DateFormatter().string(from: now),
                gmail_label_ids: email.labels.isEmpty ? nil : email.labels
            )

            try await client
                .from("saved_emails")
                .update(payload)
                .eq("id", value: existingRow.id.uuidString)
                .execute()
            return
        }

        let savedEmail = SavedEmail(
            id: UUID(),
            userId: userId,
            emailFolderId: mirrorFolder.id,
            gmailMessageId: remoteMessageId,
            subject: email.subject,
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            recipients: recipients,
            ccRecipients: ccRecipients,
            body: email.body,
            snippet: email.snippet,
            aiSummary: summary,
            timestamp: email.timestamp,
            savedAt: now,
            updatedAt: now,
            gmailLabelIds: email.labels.isEmpty ? nil : email.labels
        )

        _ = try await client
            .from("saved_emails")
            .insert(savedEmail)
            .execute()
    }

    func deleteAllSavedEmailRecords(gmailMessageId: String) async throws {
        guard !gmailMessageId.isEmpty else { return }

        let client = await supabaseManager.getPostgrestClient()
        let response = try await client
            .from("saved_emails")
            .select("id")
            .eq("gmail_message_id", value: gmailMessageId)
            .execute()

        let rows = try decoder.decode([SavedEmailIdentifier].self, from: response.data)

        for row in rows {
            let attachments = (try? await fetchAttachments(for: row.id)) ?? []
            if !attachments.isEmpty {
                let storage = await supabaseManager.getStorageClient()
                let storagePaths = attachments.map(\.storagePath)
                _ = try? await storage
                    .from("email-attachments")
                    .remove(paths: storagePaths)
            }
        }

        try await client
            .from("saved_emails")
            .delete()
            .eq("gmail_message_id", value: gmailMessageId)
            .execute()

        await MainActor.run {
            EmailService.shared.clearFolderCache()
        }
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
