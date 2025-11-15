import Foundation

/// Manages Gmail label synchronization and import
actor LabelSyncService {
    static let shared = LabelSyncService()

    private let gmailLabelService = GmailLabelService.shared
    private let emailFolderService = EmailFolderService.shared
    private let gmailAPIClient = GmailAPIClient.shared
    private let supabaseManager = SupabaseManager.shared
    private let openAIService = OpenAIService.shared

    // Progress tracking
    @MainActor private(set) var importProgress = ImportProgress()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Main Import Flow

    /// Manually trigger a full label sync (user-initiated)
    /// Shows progress to the user
    @MainActor
    func manualSyncLabels() async throws {
        let syncProgress = SyncProgress()
        await syncProgress.startSync()

        do {
            await syncProgress.updateStatus("Checking labels...", current: 0, total: 0)

            // Fetch all label mappings
            let mappings = try await fetchAllLabelMappings()
            await syncProgress.updateStatus("Syncing \(mappings.count) labels", current: 0, total: mappings.count)

            // Handle deleted labels first
            try await handleDeletedLabels(mappings: mappings)

            // Sync each label
            for (index, mapping) in mappings.enumerated() {
                guard mapping.syncStatus == "active" else { continue }

                await syncProgress.updateStatus("Syncing: \(mapping.gmailLabelName)", current: index + 1, total: mappings.count)

                do {
                    try await syncLabelEmails(mapping: mapping)
                } catch {
                    print("⚠️ Failed to sync label '\(mapping.gmailLabelName)': \(error.localizedDescription)")
                    continue
                }
            }

            await syncProgress.completeSync(success: true, message: "Sync completed successfully")
            print("✅ Manual label sync completed")

        } catch {
            await syncProgress.completeSync(success: false, message: "Sync failed: \(error.localizedDescription)")
            print("❌ Manual label sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Sync label updates periodically to keep folders in sync with Gmail
    /// This should be called periodically (e.g., every 15-30 minutes when app is active)
    func syncLabelUpdates() async throws {
        print("🔄 Starting background sync of Gmail labels...")

        // Fetch all label mappings for current user
        let mappings = try await fetchAllLabelMappings()
        print("📋 Syncing \(mappings.count) labels...")

        // First, check for deleted labels
        try await handleDeletedLabels(mappings: mappings)

        for mapping in mappings {
            // Skip if sync is disabled for this label
            guard mapping.syncStatus == "active" else {
                print("⏭️ Skipping disabled label: \(mapping.gmailLabelName)")
                continue
            }

            do {
                try await syncLabelEmails(mapping: mapping)
            } catch {
                print("⚠️ Failed to sync label '\(mapping.gmailLabelName)': \(error.localizedDescription)")
                // Continue with next label
                continue
            }
        }

        print("✅ Label sync completed")
    }

    /// Check for labels that have been deleted in Gmail and remove them from Seline
    private func handleDeletedLabels(mappings: [LabelMappingRecord]) async throws {
        // Fetch all current labels from Gmail
        let currentLabels = try await gmailLabelService.fetchAllCustomLabels()
        let currentLabelIds = Set(currentLabels.map { $0.id })

        // Find labels that exist in our mappings but not in Gmail
        for mapping in mappings {
            guard !currentLabelIds.contains(mapping.gmailLabelId) else { continue }

            print("🗑️ Label deleted in Gmail: \(mapping.gmailLabelName)")

            do {
                // Delete the corresponding folder in Seline
                try await emailFolderService.deleteFolder(id: mapping.folderId)
                print("✅ Deleted folder for label: \(mapping.gmailLabelName)")

                // Update mapping status to deleted
                try await deleteLabelMapping(id: mapping.id)

            } catch {
                print("⚠️ Failed to delete folder for label '\(mapping.gmailLabelName)': \(error.localizedDescription)")
                // Continue with next label instead of failing completely
                continue
            }
        }
    }

    /// Sync emails for a specific label
    private func syncLabelEmails(mapping: LabelMappingRecord) async throws {
        print("🔄 Syncing label: \(mapping.gmailLabelName)")

        // Fetch current emails in this Gmail label
        var currentGmailEmails: Set<String> = []
        var pageToken: String? = nil

        while true {
            let (messageIds, nextPageToken) = try await gmailLabelService.fetchEmailsInLabel(
                labelId: mapping.gmailLabelId,
                pageToken: pageToken,
                maxResults: 50
            )

            currentGmailEmails.formUnion(messageIds)

            if let nextPageToken = nextPageToken {
                pageToken = nextPageToken
            } else {
                break
            }
        }

        // Fetch emails currently in the Seline folder
        let savedEmails = try await emailFolderService.fetchEmailsInFolder(folderId: mapping.folderId)
        let selineEmailIds = Set(savedEmails.map { $0.gmailMessageId })

        // Find emails to add (in Gmail but not in Seline)
        let emailsToAdd = currentGmailEmails.subtracting(selineEmailIds)
        print("📧 Adding \(emailsToAdd.count) new emails to folder")

        for messageId in emailsToAdd {
            do {
                try await importEmailToFolder(
                    gmailMessageId: messageId,
                    folderId: mapping.folderId,
                    gmailLabelId: mapping.gmailLabelId
                )
            } catch {
                print("⚠️ Failed to import email \(messageId): \(error.localizedDescription)")
                continue
            }
        }

        // Find emails to remove (in Seline but not in Gmail)
        let emailsToRemove = selineEmailIds.subtracting(currentGmailEmails)
        print("🗑️ Removing \(emailsToRemove.count) emails from folder")

        for savedEmail in savedEmails {
            guard emailsToRemove.contains(savedEmail.gmailMessageId) else { continue }

            do {
                try await emailFolderService.deleteSavedEmail(id: savedEmail.id)
                print("✅ Removed email from folder: \(savedEmail.subject)")
            } catch {
                print("⚠️ Failed to remove email: \(error.localizedDescription)")
                continue
            }
        }

        // Update last sync timestamp
        try await updateLabelSyncStatus(mapping: mapping)

        // Invalidate cache for this folder so the app fetches fresh data
        await invalidateFolderCache(folderId: mapping.folderId)

        print("✅ Sync completed for label: \(mapping.gmailLabelName)")
    }

    /// Import all Gmail custom labels on first login
    /// This is the main entry point for label import
    func importLabelsOnFirstLogin() async throws {
        print("🔄 Starting Gmail label import on first login...")

        await importProgress.updateProgress(phase: "Fetching labels", current: 0, total: 0)

        // Fetch all custom labels from Gmail
        print("📡 Fetching Gmail labels from Gmail API...")
        do {
            let labels = try await gmailLabelService.fetchAllCustomLabels()
            print("📋 Found \(labels.count) custom labels to import")

            try await handleLabelImportResult(labels: labels)
        } catch {
            print("❌ ERROR fetching Gmail labels: \(error.localizedDescription)")
            print("🐛 Full error: \(String(describing: error))")
            throw error
        }
    }

    private func handleLabelImportResult(labels: [GmailLabel]) async throws {

        if labels.isEmpty {
            print("⚠️ No custom labels found! Please check if you have custom labels in Gmail (exclude system labels like INBOX, SENT, TRASH)")
            print("📝 Gmail API returned empty label list - this is expected if you don't have any custom labels")
            await importProgress.updateProgress(phase: "No labels found", current: 0, total: 0)
            return
        }

        print("📋 Custom labels found:")
        for label in labels {
            print("  ✓ Label: '\(label.name)' (ID: \(label.id))")
        }

        await importProgress.updateProgress(phase: "Importing labels", current: 0, total: labels.count)

        // Import each label
        var successCount = 0
        for (index, label) in labels.enumerated() {
            do {
                print("➡️ Importing label \(index + 1)/\(labels.count): '\(label.name)'")
                try await importLabel(label, progress: (index + 1, labels.count))
                successCount += 1
                await importProgress.updateProgress(phase: "Importing labels", current: index + 1, total: labels.count)
                print("✅ Successfully imported label: '\(label.name)'")
            } catch {
                print("⚠️ Failed to import label '\(label.name)': \(error.localizedDescription)")
                print("🐛 Error details: \(String(describing: error))")
                // Continue with next label instead of failing completely
                continue
            }
        }

        print("✅ Label import completed - Imported \(successCount)/\(labels.count) labels")
        await importProgress.updateProgress(phase: "Complete", current: labels.count, total: labels.count)
    }

    // MARK: - Individual Label Import

    /// Import a single label with all its emails
    private func importLabel(_ label: GmailLabel, progress: (current: Int, total: Int)) async throws {
        print("📥 Starting import for label: '\(label.name)' (Gmail ID: \(label.id))")

        // Check if folder already exists (user may have manually created a folder with this name)
        print("🔍 Checking if folder already exists...")
        let existingFolders = try await emailFolderService.fetchFolders()
        let existingFolder = existingFolders.first { $0.name == label.name }

        let folderColor = getColorForLabel(label)
        print("🎨 Folder color: \(folderColor)")

        let folder: CustomEmailFolder
        if let existing = existingFolder {
            print("✅ Found existing folder: '\(label.name)' (Folder ID: \(existing.id))")

            // Update folder color to match Gmail label color
            if existing.color != folderColor {
                print("🔄 Updating folder color from \(existing.color) to \(folderColor)")
                do {
                    let updatedFolder = try await emailFolderService.updateFolderColor(id: existing.id, color: folderColor)
                    folder = updatedFolder
                    print("✅ Folder color updated")
                } catch {
                    print("⚠️ Could not update folder color: \(error.localizedDescription)")
                    folder = existing
                }
            } else {
                folder = existing
            }
        } else {
            // Create folder for this label
            folder = try await emailFolderService.createImportedLabelFolder(
                name: label.name,
                color: folderColor,
                gmailLabelId: label.id
            )
            print("✅ Created email folder: '\(label.name)' (Folder ID: \(folder.id))")
        }

        // Create label mapping (skip if already exists)
        print("🔗 Checking if label mapping exists...")
        do {
            if let existingMapping = try await getLabelMapping(gmailLabelId: label.id) {
                print("✅ Label mapping already exists (ID: \(existingMapping.id))")
            } else {
                print("📝 Creating new label mapping...")
                try await createLabelMapping(
                    gmailLabelId: label.id,
                    gmailLabelName: label.name,
                    folderId: folder.id,
                    color: label.color?.backgroundColor
                )
                print("✅ Label mapping created successfully")
            }
        } catch {
            print("⚠️ Could not check/create label mapping: \(error.localizedDescription)")
            // Continue anyway - mapping may not be critical
        }

        // Fetch and import all emails in this label (paginated)
        print("📧 Fetching emails from Gmail label...")
        try await importEmailsFromLabel(
            gmailLabelId: label.id,
            folderId: folder.id,
            labelName: label.name
        )
        print("✅ Completed import for label: '\(label.name)'")
    }

    /// Import all emails from a specific label with pagination
    private func importEmailsFromLabel(
        gmailLabelId: String,
        folderId: UUID,
        labelName: String
    ) async throws {
        var pageToken: String? = nil
        var totalImported = 0
        var totalFetched = 0
        let batchSize = 50

        print("🔄 Starting email fetch for label '\(labelName)' (Gmail ID: \(gmailLabelId))")

        while true {
            print("📡 Fetching batch of emails (pageToken: \(pageToken ?? "none"))...")
            let (messageIds, nextPageToken) = try await gmailLabelService.fetchEmailsInLabel(
                labelId: gmailLabelId,
                pageToken: pageToken,
                maxResults: batchSize
            )

            print("📧 Batch returned \(messageIds.count) message IDs")
            totalFetched += messageIds.count

            if messageIds.isEmpty {
                print("📭 No emails in this label")
                break
            }

            print("📥 Processing \(messageIds.count) emails from this batch...")

            // Fetch full details for each message and save to folder
            for (index, messageId) in messageIds.enumerated() {
                do {
                    print("   ↳ Importing email \(index + 1)/\(messageIds.count): \(messageId)")
                    try await importEmailToFolder(
                        gmailMessageId: messageId,
                        folderId: folderId,
                        gmailLabelId: gmailLabelId
                    )
                    totalImported += 1
                    print("   ✅ Email imported successfully")
                } catch {
                    print("   ⚠️ Failed to import email \(messageId): \(error.localizedDescription)")
                    print("   🐛 Error: \(String(describing: error))")
                    // Continue with next email
                    continue
                }
            }

            // Check if there are more pages
            if let nextPageToken = nextPageToken {
                pageToken = nextPageToken
                print("⏭️ More emails available, fetching next page...")
            } else {
                print("✅ No more pages to fetch")
                break
            }
        }

        print("✅ Email import complete for '\(labelName)': Imported \(totalImported)/\(totalFetched) emails")

        // Invalidate cache for this folder so the app fetches fresh data
        print("🔄 Invalidating cache for folder \(folderId)")
        await invalidateFolderCache(folderId: folderId)
    }

    /// Invalidate the folder email cache so fresh data is fetched
    private func invalidateFolderCache(folderId: UUID) async {
        let emailService = EmailService.shared
        // Force refresh by saving an empty timestamp so cache is considered invalid
        UserDefaults.standard.removeObject(forKey: "cached_folder_emails_timestamp_\(folderId.uuidString)")
        UserDefaults.standard.removeObject(forKey: "cached_folder_emails_\(folderId.uuidString)")
        print("✅ Cache invalidated for folder \(folderId)")
    }

    /// Import a single email to a folder
    private func importEmailToFolder(
        gmailMessageId: String,
        folderId: UUID,
        gmailLabelId: String
    ) async throws {
        print("      📬 Fetching email details by message ID...")
        // Fetch full email details directly by message ID (more reliable than search)
        guard let email = try await gmailAPIClient.fetchSingleEmail(messageId: gmailMessageId) else {
            print("      ⚠️ Could not fetch email details for \(gmailMessageId)")
            return
        }

        print("      📧 Email subject: \(email.subject)")

        // Fetch full email body for AI summary
        var fullEmailBody: String? = nil
        do {
            print("      📥 Fetching email body for AI summary...")
            fullEmailBody = try await gmailAPIClient.fetchBodyForAI(messageId: gmailMessageId)
        } catch {
            print("      ⚠️ Could not fetch full body for email: \(error.localizedDescription)")
        }

        // Generate AI summary (non-blocking - can fail without affecting import)
        var aiSummary: String? = nil
        if let body = fullEmailBody {
            do {
                print("      🤖 Generating AI summary...")
                aiSummary = try await openAIService.summarizeEmail(subject: email.subject, body: body)
                print("      ✅ AI summary generated")
            } catch {
                print("      ⚠️ Failed to generate AI summary: \(error.localizedDescription)")
            }
        }

        // Save email to folder
        print("      💾 Saving email to folder...")
        let savedEmail = try await emailFolderService.saveEmail(
            from: email,
            to: folderId,
            with: [],
            aiSummary: aiSummary
        )

        // Update saved email with Gmail label IDs
        print("      🏷️ Updating email with Gmail label ID...")
        try await updateSavedEmailLabels(savedEmailId: savedEmail.id, labelIds: [gmailLabelId])

        print("      ✅ Saved email: \(email.subject)")
    }

    // MARK: - Database Operations

    /// Create a label mapping record in the database
    private func createLabelMapping(
        gmailLabelId: String,
        gmailLabelName: String,
        folderId: UUID,
        color: String?
    ) async throws {
        guard let currentUser = supabaseManager.getCurrentUser() else {
            throw NSError(domain: "LabelSyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let client = await supabaseManager.getPostgrestClient()

        struct LabelMapping: Codable {
            let user_id: String
            let gmail_label_id: String
            let gmail_label_name: String
            let folder_id: String
            let gmail_label_color: String?
            let sync_status: String

            init(userId: UUID, gmailLabelId: String, gmailLabelName: String, folderId: UUID, color: String?) {
                self.user_id = userId.uuidString
                self.gmail_label_id = gmailLabelId
                self.gmail_label_name = gmailLabelName
                self.folder_id = folderId.uuidString
                self.gmail_label_color = color
                self.sync_status = "active"
            }
        }

        let mapping = LabelMapping(
            userId: currentUser.id,
            gmailLabelId: gmailLabelId,
            gmailLabelName: gmailLabelName,
            folderId: folderId,
            color: color
        )

        print("📝 Inserting label mapping: user_id=\(currentUser.id.uuidString), gmail_label_id=\(gmailLabelId), folder_id=\(folderId.uuidString)")

        _ = try await client
            .from("email_label_mappings")
            .insert(mapping)
            .select()
            .single()
            .execute()

        print("✅ Created label mapping for \(gmailLabelName)")
    }

    /// Update saved email with Gmail label IDs
    private func updateSavedEmailLabels(
        savedEmailId: UUID,
        labelIds: [String]
    ) async throws {
        let client = await supabaseManager.getPostgrestClient()

        struct UpdateData: Codable {
            let gmail_label_ids: [String]
            let updated_at: String
        }

        let updateData = UpdateData(
            gmail_label_ids: labelIds,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        try await client
            .from("saved_emails")
            .update(updateData)
            .eq("id", value: savedEmailId.uuidString)
            .execute()
    }

    // MARK: - Utility Methods

    /// Convert Gmail label color to hex format
    private func getColorForLabel(_ label: GmailLabel) -> String {
        // Use Gmail's label color if available
        if let backgroundColor = label.color?.backgroundColor {
            // Gmail stores colors like "#5f6368", return as-is
            return backgroundColor
        }

        // Fallback to default Seline color
        return "#84cae9"
    }

    /// Fetch a label by ID from Gmail
    func getLabelMapping(gmailLabelId: String) async throws -> LabelMappingRecord? {
        let client = await supabaseManager.getPostgrestClient()

        let response = try await client
            .from("email_label_mappings")
            .select()
            .eq("gmail_label_id", value: gmailLabelId)
            .limit(1)
            .execute()

        guard !response.data.isEmpty else {
            print("ℹ️ No existing label mapping found for Gmail label: \(gmailLabelId)")
            return nil
        }

        let mappings = try decoder.decode([LabelMappingRecord].self, from: response.data)
        return mappings.first
    }

    /// Fetch all label mappings for the current user
    private func fetchAllLabelMappings() async throws -> [LabelMappingRecord] {
        let client = await supabaseManager.getPostgrestClient()

        let response = try await client
            .from("email_label_mappings")
            .select()
            .eq("sync_status", value: "active")
            .execute()

        let mappings = try decoder.decode([LabelMappingRecord].self, from: response.data)
        return mappings
    }

    /// Update the last sync timestamp for a label
    private func updateLabelSyncStatus(mapping: LabelMappingRecord) async throws {
        let client = await supabaseManager.getPostgrestClient()

        struct UpdateData: Codable {
            let last_synced_at: String
            let updated_at: String
        }

        let updateData = UpdateData(
            last_synced_at: ISO8601DateFormatter().string(from: Date()),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        try await client
            .from("email_label_mappings")
            .update(updateData)
            .eq("id", value: mapping.id.uuidString)
            .execute()
    }

    /// Delete a label mapping record
    private func deleteLabelMapping(id: UUID) async throws {
        let client = await supabaseManager.getPostgrestClient()

        try await client
            .from("email_label_mappings")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

// MARK: - Progress Tracking

@MainActor
class ImportProgress: ObservableObject {
    @Published var phase: String = "Idle"
    @Published var current: Int = 0
    @Published var total: Int = 0

    func updateProgress(phase: String, current: Int, total: Int) {
        self.phase = phase
        self.current = current
        self.total = total
    }

    var isImporting: Bool {
        phase != "Idle" && phase != "Complete"
    }

    var progressPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Manual Sync Progress

@MainActor
class SyncProgress: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var status: String = "Ready"
    @Published var current: Int = 0
    @Published var total: Int = 0
    @Published var isComplete: Bool = false
    @Published var isSuccess: Bool = false
    @Published var message: String = ""

    func startSync() {
        isSyncing = true
        isComplete = false
        isSuccess = false
        status = "Preparing..."
        current = 0
        total = 0
        message = ""
    }

    func updateStatus(_ status: String, current: Int, total: Int) {
        self.status = status
        self.current = current
        self.total = total
    }

    func completeSync(success: Bool, message: String) {
        isSyncing = false
        isComplete = true
        isSuccess = success
        self.message = message
        self.status = success ? "Complete" : "Failed"
    }

    var progressPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Database Models

struct LabelMappingRecord: Codable {
    let id: UUID
    let userId: UUID
    let gmailLabelId: String
    let gmailLabelName: String
    let folderId: UUID
    let gmailLabelColor: String?
    let lastSyncedAt: Date
    let syncStatus: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gmailLabelId = "gmail_label_id"
        case gmailLabelName = "gmail_label_name"
        case folderId = "folder_id"
        case gmailLabelColor = "gmail_label_color"
        case lastSyncedAt = "last_synced_at"
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Extension for EmailFolderService

extension EmailFolderService {
    /// Create a folder specifically for an imported Gmail label
    func createImportedLabelFolder(
        name: String,
        color: String,
        gmailLabelId: String
    ) async throws -> CustomEmailFolder {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "EmailFolderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let folder = CustomEmailFolder(
            id: UUID(),
            userId: userId,
            name: name,
            color: color,
            createdAt: Date(),
            updatedAt: Date(),
            isImportedLabel: true,
            gmailLabelId: gmailLabelId,
            lastSyncedAt: Date(),
            syncEnabled: true
        )

        let client = await SupabaseManager.shared.getPostgrestClient()

        // Insert with additional imported label fields
        struct ImportedFolderData: Codable {
            let id: String
            let user_id: String
            let name: String
            let color: String
            let is_imported_label: Bool
            let gmail_label_id: String
            let created_at: String
            let updated_at: String
        }

        let folderData = ImportedFolderData(
            id: folder.id.uuidString,
            user_id: userId.uuidString,
            name: folder.name,
            color: folder.color,
            is_imported_label: true,
            gmail_label_id: gmailLabelId,
            created_at: ISO8601DateFormatter().string(from: folder.createdAt),
            updated_at: ISO8601DateFormatter().string(from: folder.updatedAt)
        )

        let response = try await client
            .from("email_folders")
            .insert(folderData)
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedFolder = try decoder.decode(CustomEmailFolder.self, from: response.data)
        return decodedFolder
    }
}
