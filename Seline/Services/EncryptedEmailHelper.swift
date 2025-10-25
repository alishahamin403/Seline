import Foundation

/// Helper methods to encrypt/decrypt email data before storing in Supabase
/// This is critical for protecting email content that users consider private
///
/// Encryption scope:
/// - Email body/snippet (main content)
/// - Email subject line
/// - Sender and recipient email addresses
/// - AI-generated summaries
extension EmailService {

    // MARK: - Encrypt Email Data

    /// Encrypt sensitive email fields before storing summaries
    /// Encrypted fields: subject, body/snippet, aiSummary
    /// User email addresses are also encrypted for privacy
    func encryptEmailData(
        subject: String,
        body: String,
        aiSummary: String?,
        senderEmail: String,
        recipientEmails: [String]
    ) async throws -> EncryptedEmailData {

        let encryptedSubject = try EncryptionManager.shared.encrypt(subject)
        let encryptedBody = try EncryptionManager.shared.encrypt(body)

        // Handle optional summary with encryption
        let encryptedSummary: String?
        if let summary = aiSummary {
            encryptedSummary = try EncryptionManager.shared.encrypt(summary)
        } else {
            encryptedSummary = nil
        }

        let encryptedSenderEmail = try EncryptionManager.shared.encrypt(senderEmail)
        let encryptedRecipientEmails = try EncryptionManager.shared.encryptMultiple(recipientEmails)

        print("✅ Encrypted email subject and content")

        return EncryptedEmailData(
            encryptedSubject: encryptedSubject,
            encryptedBody: encryptedBody,
            encryptedSummary: encryptedSummary,
            encryptedSenderEmail: encryptedSenderEmail,
            encryptedRecipientEmails: encryptedRecipientEmails
        )
    }

    // MARK: - Decrypt Email Data

    /// Decrypt email fields after fetching from storage
    func decryptEmailData(_ encryptedData: EncryptedEmailData) async throws -> DecryptedEmailData {
        do {
            let subject = try EncryptionManager.shared.decrypt(encryptedData.encryptedSubject)
            let body = try EncryptionManager.shared.decrypt(encryptedData.encryptedBody)

            // Handle optional summary with decryption
            let summary: String?
            if let encryptedSummary = encryptedData.encryptedSummary {
                summary = try EncryptionManager.shared.decrypt(encryptedSummary)
            } else {
                summary = nil
            }

            let senderEmail = try EncryptionManager.shared.decrypt(encryptedData.encryptedSenderEmail)
            let recipientEmails = try EncryptionManager.shared.decryptMultiple(encryptedData.encryptedRecipientEmails)

            print("✅ Decrypted email data")

            return DecryptedEmailData(
                subject: subject,
                body: body,
                summary: summary,
                senderEmail: senderEmail,
                recipientEmails: recipientEmails
            )
        } catch {
            print("⚠️ Failed to decrypt email data: \(error.localizedDescription)")
            print("   Email will be returned as stored (legacy unencrypted data)")
            // Return original data for backward compatibility
            throw error
        }
    }
}

// MARK: - Data Structures for Encryption

/// Holds encrypted email data ready to store in Supabase
struct EncryptedEmailData {
    let encryptedSubject: String
    let encryptedBody: String
    let encryptedSummary: String?
    let encryptedSenderEmail: String
    let encryptedRecipientEmails: [String]
}

/// Holds decrypted email data for display to user
struct DecryptedEmailData {
    let subject: String
    let body: String
    let summary: String?
    let senderEmail: String
    let recipientEmails: [String]
}

// MARK: - Integration Points

/// Integration Guide for Email Encryption:
///
/// 1. WHEN STORING EMAIL SUMMARY (in OpenAIService or EmailService):
/// ```swift
/// let encryptedEmail = try await emailService.encryptEmailData(
///     subject: email.subject,
///     body: email.body,
///     aiSummary: generatedSummary,
///     senderEmail: email.sender.email,
///     recipientEmails: email.recipients.map { $0.email }
/// )
///
/// // Store encrypted fields in database:
/// let data: [String: PostgREST.AnyJSON] = [
///     "subject": .string(encryptedEmail.encryptedSubject),
///     "body": .string(encryptedEmail.encryptedBody),
///     "ai_summary": encryptedEmail.encryptedSummary.map { .string($0) } ?? .null,
///     "sender_email": .string(encryptedEmail.encryptedSenderEmail),
///     "recipient_emails": .array(...)
/// ]
/// ```
///
/// 2. WHEN DISPLAYING EMAIL (before showing to user):
/// ```swift
/// let storedEncryptedEmail = ... // fetched from database
///
/// let decryptedEmail = try await emailService.decryptEmailData(
///     EncryptedEmailData(
///         encryptedSubject: storedEncryptedEmail.subject,
///         encryptedBody: storedEncryptedEmail.body,
///         ...
///     )
/// )
/// // Now you can show:
/// // - decryptedEmail.subject
/// // - decryptedEmail.body
/// // - decryptedEmail.summary
/// ```
///
/// 3. WHY THIS MATTERS:
/// - Email content is often highly sensitive (financial, personal, etc.)
/// - Users don't want even Supabase staff seeing their emails
/// - Encryption happens on device before sending to server
/// - Only decryption key exists on client - server never has it
