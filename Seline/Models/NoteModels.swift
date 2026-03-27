import Foundation
import SwiftUI
import PostgREST
import WidgetKit

// MARK: - Note Models

enum NoteKind: String, Codable, Hashable {
    case standard
    case journalEntry
    case journalWeeklyRecap
}

enum JournalTodayStatus: Hashable {
    case missing
    case complete
}

struct JournalStats: Hashable {
    let currentStreak: Int
    let longestStreak: Int
    let completedThisWeek: Int
    let totalEntries: Int
    let lastEntryDate: Date?
    let todayStatus: JournalTodayStatus
}

struct JournalSummaryInput: Hashable {
    let date: Date
    let title: String
    let preview: String
    let mood: JournalMood?
}

struct JournalDraft: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let folderId: UUID
    let kind: NoteKind
    let journalDate: Date
}

enum JournalMood: String, CaseIterable, Codable, Hashable, Identifiable {
    case great
    case good
    case calm
    case tired
    case stressed
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .calm: return "Calm"
        case .tired: return "Tired"
        case .stressed: return "Stressed"
        case .low: return "Low"
        }
    }

    var iconName: String {
        switch self {
        case .great: return "sun.max.fill"
        case .good: return "sparkles"
        case .calm: return "leaf.fill"
        case .tired: return "moon.zzz.fill"
        case .stressed: return "bolt.fill"
        case .low: return "cloud.drizzle.fill"
        }
    }
}

struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var content: String
    var dateCreated: Date
    var dateModified: Date
    var isPinned: Bool
    var folderId: UUID?
    var isLocked: Bool
    var imageUrls: [String] // Store image URLs from Supabase Storage
    var attachmentId: UUID? // Single file attachment per note (for documents like bank statements, invoices)
    var blocksData: String? // JSON string of blocks for block-based editor
    var kind: NoteKind?
    var journalDate: Date?
    var journalWeekStartDate: Date?
    
    // Note Reminder fields
    var reminderDate: Date? // When to remind the user
    var reminderNote: String? // Short note about what needs to be done

    // Temporary compatibility - will be removed after migration
    var imageAttachments: [Data] {
        get { [] }
        set { }
    }

    init(
        title: String,
        content: String = "",
        folderId: UUID? = nil,
        kind: NoteKind? = nil,
        journalDate: Date? = nil,
        journalWeekStartDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.dateCreated = Date()
        self.dateModified = Date()
        self.isPinned = false
        self.folderId = folderId
        self.isLocked = false
        self.imageUrls = []
        self.kind = kind
        self.journalDate = journalDate
        self.journalWeekStartDate = journalWeekStartDate
        self.reminderDate = nil
        self.reminderNote = nil
    }
    
    /// Check if the note has an active reminder
    var hasActiveReminder: Bool {
        guard let reminderDate = reminderDate else { return false }
        return reminderDate > Date()
    }
    
    /// Check if the reminder is due (past or today)
    var isReminderDue: Bool {
        guard let reminderDate = reminderDate else { return false }
        return reminderDate <= Date()
    }

    var formattedDateModified: String {
        FormatterCache.formattedNoteModified(dateModified)
    }

    var journalMood: JournalMood? {
        Self.extractJournalMood(from: content)
    }

    var displayContent: String {
        Self.stripJournalMetadata(from: content)
    }

    var preview: String {
        let trimmed = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No additional text"
        }
        return String(trimmed.prefix(100))
    }

    var resolvedKind: NoteKind {
        kind ?? .standard
    }

    var isJournalEntry: Bool {
        resolvedKind == .journalEntry
    }

    var isJournalWeeklyRecap: Bool {
        resolvedKind == .journalWeeklyRecap
    }

    var isMeaningfulJournalEntry: Bool {
        guard isJournalEntry else { return false }
        let visibleContent = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return journalMood != nil || !visibleContent.isEmpty
    }

    private static let journalMoodMetadataPrefix = "<!--seline:journal_mood="
    private static let journalMoodMetadataSuffix = "-->"

    static func extractJournalMood(from rawContent: String) -> JournalMood? {
        let lines = rawContent.split(
            maxSplits: 1,
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        guard let firstLine = lines.first else { return nil }

        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(journalMoodMetadataPrefix),
              trimmed.hasSuffix(journalMoodMetadataSuffix) else {
            return nil
        }

        let rawValue = trimmed
            .replacingOccurrences(of: journalMoodMetadataPrefix, with: "")
            .replacingOccurrences(of: journalMoodMetadataSuffix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return JournalMood(rawValue: rawValue)
    }

    static func stripJournalMetadata(from rawContent: String) -> String {
        let lines = rawContent.split(
            maxSplits: 1,
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        guard let firstLine = lines.first else { return rawContent }

        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(journalMoodMetadataPrefix),
              trimmed.hasSuffix(journalMoodMetadataSuffix) else {
            return rawContent
        }

        guard lines.count > 1 else { return "" }
        return String(lines[1])
    }

    static func applyJournalMood(_ mood: JournalMood?, to rawContent: String) -> String {
        let stripped = stripJournalMetadata(from: rawContent)
        guard let mood else { return stripped }

        let metadata = "\(journalMoodMetadataPrefix)\(mood.rawValue)\(journalMoodMetadataSuffix)"
        guard !stripped.isEmpty else { return metadata }
        return "\(metadata)\n\(stripped)"
    }
}

extension Note {
    var embeddingDate: Date {
        if let journalDate {
            return journalDate
        }
        if let journalWeekStartDate {
            return journalWeekStartDate
        }
        return dateModified
    }

    var embeddingWeekEndDate: Date? {
        guard let start = journalWeekStartDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: 7, to: start)
    }

    func embeddingFolderName(resolvedFolderName: String?) -> String {
        if isJournalWeeklyRecap {
            return "Journal Weekly Summary"
        }
        if isJournalEntry {
            return "Journal"
        }
        let trimmed = resolvedFolderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Notes" : trimmed
    }

    func embeddingContent(resolvedFolderName: String?) -> String {
        let visibleContent = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = embeddingFolderName(resolvedFolderName: resolvedFolderName)
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        var lines: [String] = []
        switch resolvedKind {
        case .journalEntry:
            lines.append("Journal Entry")
            if let journalDate {
                lines.append("Journal date: \(formatter.string(from: journalDate))")
            }
            if let mood = journalMood {
                lines.append("Mood: \(mood.rawValue.capitalized)")
            }
        case .journalWeeklyRecap:
            lines.append("Journal Weekly Summary")
            if let weekStart = journalWeekStartDate {
                let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
                lines.append("Week of: \(formatter.string(from: weekStart)) to \(formatter.string(from: weekEnd))")
            }
        case .standard:
            lines.append("Note")
        }

        lines.append("Title: \(title)")
        lines.append("Folder: \(folderName)")

        if !visibleContent.isEmpty {
            lines.append("Content:")
            lines.append(visibleContent)
        }

        return lines.joined(separator: "\n")
    }

    func embeddingMetadata(resolvedFolderName: String?) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var metadata: [String: Any] = [
            "date": iso.string(from: embeddingDate),
            "folder_name": embeddingFolderName(resolvedFolderName: resolvedFolderName),
            "folder_id": folderId?.uuidString ?? NSNull(),
            "is_pinned": isPinned,
            "note_kind": resolvedKind.rawValue
        ]

        if let journalDate {
            metadata["journal_date"] = iso.string(from: journalDate)
        }
        if let journalWeekStartDate {
            metadata["journal_week_start_date"] = iso.string(from: journalWeekStartDate)
        }
        if let embeddingWeekEndDate {
            metadata["journal_week_end_date"] = iso.string(from: embeddingWeekEndDate)
        }
        if let mood = journalMood {
            metadata["journal_mood"] = mood.rawValue
        }

        return metadata
    }
}

// MARK: - Block Editor Support

extension Note {
    /// Get blocks from blocksData or parse from content
    var blocks: [AnyBlock] {
        get {
            // Try to load from blocksData first
            if let jsonString = blocksData,
               let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([AnyBlock].self, from: data) {
                return decoded
            }

            // Fallback: parse from old content (markdown)
            return BlockDocumentController.parseMarkdown(content)
        }
        set {
            // Save as JSON string
            if let encoded = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: encoded, encoding: .utf8) {
                blocksData = jsonString
            }

            // Also update content field for backward compatibility
            let controller = BlockDocumentController(blocks: newValue)
            content = controller.toMarkdown()
        }
    }
}

struct NoteFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String // Hex color string
    var parentFolderId: UUID? // Parent folder ID for subfolder hierarchy

    init(name: String, color: String = "#84cae9", parentFolderId: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.parentFolderId = parentFolderId
    }

    init(id: UUID, name: String, color: String = "#84cae9", parentFolderId: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.parentFolderId = parentFolderId
    }

    // Get the depth level of this folder (0 = root, 1 = child, 2 = grandchild)
    func getDepth(in folders: [NoteFolder]) -> Int {
        var depth = 0
        var currentParentId = parentFolderId

        while let parentId = currentParentId, depth < 3 {
            if let parent = folders.first(where: { $0.id == parentId }) {
                depth += 1
                currentParentId = parent.parentFolderId
            } else {
                break
            }
        }

        return depth
    }
}

// MARK: - Quick Notes
// Quick notes are small, sticky notes that appear in Quick Access for fast capture
struct QuickNote: Identifiable, Codable, Hashable {
    var id: UUID
    var content: String
    var dateCreated: Date
    var dateModified: Date
    var userId: UUID

    init(content: String, userId: UUID) {
        self.id = UUID()
        self.content = content
        self.dateCreated = Date()
        self.dateModified = Date()
        self.userId = userId
    }
}

// MARK: - Deleted Items Models

struct DeletedNote: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var content: String
    var dateCreated: Date
    var dateModified: Date
    var deletedAt: Date
    var isPinned: Bool
    var folderId: UUID?
    var isLocked: Bool
    var imageUrls: [String]

    var daysUntilPermanentDeletion: Int {
        let calendar = Calendar.current
        let daysSinceDeletion = calendar.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }
}

struct DeletedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String
    var parentFolderId: UUID?
    var dateCreated: Date
    var dateModified: Date
    var deletedAt: Date

    var daysUntilPermanentDeletion: Int {
        let calendar = Calendar.current
        let daysSinceDeletion = calendar.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - daysSinceDeletion)
    }
}

// MARK: - Notes Manager

@MainActor
class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published var notes: [Note] = []
    @Published var folders: [NoteFolder] = []
    @Published var deletedNotes: [DeletedNote] = []
    @Published var deletedFolders: [DeletedFolder] = []
    @Published var isLoading = false
    @Published var isViewingNoteInNavigation = false

    // MARK: - Sync Status (Phase 3)
    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    @Published var lastSyncTime: Date?

    private let notesKey = "SavedNotes"
    private let foldersKey = "SavedNoteFolders"
    private let authManager = AuthenticationManager.shared
    private let cacheManager = CacheManager.shared
    private let receiptStatsFallbackGracePeriod: TimeInterval = 15
    private var activeLoadOperationCount = 0
    private var lastReceiptCacheInvalidationDate: Date?
    private var receiptDataAvailabilityTask: Task<Void, Never>?

    private init() {
        // CRITICAL FIX: Clear old UserDefaults data (was 89MB!)
        migrateFromUserDefaultsToSupabase()

        // Don't load from UserDefaults anymore
        // loadNotes()
        // loadFolders()

        addSampleDataIfNeeded()

        // Don't load from Supabase here - wait for authentication!
        // The app will call syncNotesOnLogin() after user authenticates
        // This ensures EncryptionManager.setupEncryption() is called FIRST
    }

    // Migration: Remove old UserDefaults storage
    private func migrateFromUserDefaultsToSupabase() {
        // Remove the 89MB of data from UserDefaults
        UserDefaults.standard.removeObject(forKey: notesKey)
        UserDefaults.standard.removeObject(forKey: foldersKey)
    }

    private func beginDataLoadOperation() {
        activeLoadOperationCount += 1
        isLoading = activeLoadOperationCount > 0
    }

    private func endDataLoadOperation() {
        activeLoadOperationCount = max(0, activeLoadOperationCount - 1)
        isLoading = activeLoadOperationCount > 0
    }

    private func resolvedAuthenticatedUserId() async -> UUID? {
        let initialAuthUserId: UUID? = await MainActor.run {
            authManager.supabaseUser?.id
        }
        if let authUserId = initialAuthUserId {
            return authUserId
        }

        if let currentUserId = SupabaseManager.shared.getCurrentUser()?.id {
            return currentUserId
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000)

            let authUserId: UUID? = await MainActor.run {
                authManager.supabaseUser?.id
            }
            if let authUserId = authUserId {
                return authUserId
            }

            if let currentUserId = SupabaseManager.shared.getCurrentUser()?.id {
                return currentUserId
            }
        }

        return nil
    }

    private func hasReceiptsFolderLoaded() -> Bool {
        !receiptRootFolderIds().isEmpty
    }

    private func hasReceiptNotesLoaded() -> Bool {
        !receiptCandidateNotes().isEmpty
    }

    private func normalizedReceiptFolderName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func receiptRootFolderIds() -> Set<UUID> {
        Set(
            folders
                .filter { normalizedReceiptFolderName($0.name) == "receipts" }
                .map(\.id)
        )
    }

    private func isUnderFolderHierarchy(folderId: UUID?, rootFolderIds: Set<UUID>, foldersById: [UUID: NoteFolder]) -> Bool {
        guard let folderId, !rootFolderIds.isEmpty else { return false }

        var currentFolderId: UUID? = folderId
        while let currentId = currentFolderId {
            if rootFolderIds.contains(currentId) {
                return true
            }
            currentFolderId = foldersById[currentId]?.parentFolderId
        }

        return false
    }

    private func isReceiptLikeNote(_ note: Note) -> Bool {
        let combined = "\(note.title)\n\(note.content)".lowercased()
        let keywords = [
            "receipt",
            "subtotal",
            "total",
            "merchant",
            "invoice",
            "payment",
            "transaction",
            "interac",
            "e-transfer",
            "etransfer"
        ]

        let hasKeyword = keywords.contains { combined.contains($0) }
        let hasAttachment = !note.imageUrls.isEmpty || note.attachmentId != nil
        let hasParsedDate = extractFullDateFromTitle(note.title) != nil || extractMonthYearFromTitle(note.title) != nil
        let amount = CurrencyParser.extractAmount(
            from: [note.title, note.content]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )

        return amount > 0 && (hasKeyword || hasAttachment || hasParsedDate)
    }

    private func receiptCandidateNotes() -> [Note] {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let rootFolderIds = receiptRootFolderIds()

        var candidates = notes.filter { note in
            isUnderFolderHierarchy(folderId: note.folderId, rootFolderIds: rootFolderIds, foldersById: foldersById)
        }

        if rootFolderIds.isEmpty || candidates.isEmpty {
            let existingIds = Set(candidates.map(\.id))
            let fallbackCandidates = notes.filter { note in
                !existingIds.contains(note.id) && isReceiptLikeNote(note)
            }

            if !fallbackCandidates.isEmpty {
                candidates.append(contentsOf: fallbackCandidates)
            }
        }

        return candidates
    }

    @MainActor
    func ensureReceiptDataAvailable(forceRefresh: Bool = false) async {
        if let existingTask = receiptDataAvailabilityTask {
            await existingTask.value
            return
        }

        guard await resolvedAuthenticatedUserId() != nil else { return }

        let recentlySynced = lastSyncTime.map { Date().timeIntervalSince($0) < 30 } ?? false
        let shouldRetryAfterFailure = syncError != nil
        let hasReceiptsFolder = hasReceiptsFolderLoaded()
        let shouldLoadFolders = forceRefresh || shouldRetryAfterFailure || folders.isEmpty || (!hasReceiptsFolder && !recentlySynced)
        let shouldLoadNotes = forceRefresh || shouldRetryAfterFailure || notes.isEmpty || (hasReceiptsFolder && !hasReceiptNotesLoaded() && !recentlySynced)

        guard shouldLoadFolders || shouldLoadNotes || lastSyncTime == nil else {
            return
        }

        isSyncing = true
        syncError = nil
        let task = Task { [weak self] in
            guard let self else { return }

            if shouldLoadFolders || self.lastSyncTime == nil {
                await self.loadFoldersFromSupabase()
            }

            let needsNotesAfterFolderRefresh = forceRefresh
                || self.notes.isEmpty
                || (self.hasReceiptsFolderLoaded() && !self.hasReceiptNotesLoaded())

            if needsNotesAfterFolderRefresh || self.lastSyncTime == nil {
                await self.loadNotesFromSupabase()
            }
        }

        receiptDataAvailabilityTask = task
        defer {
            receiptDataAvailabilityTask = nil
            isSyncing = false
        }

        await task.value
    }

    // MARK: - Data Persistence

    private func saveNotes() {
        // CRITICAL FIX: REMOVED UserDefaults storage - was causing 89MB limit exceeded!
        // Notes are now ONLY stored in Supabase, not locally
        // UserDefaults has 4MB limit, we were storing 89MB of image data

        // Clear old data if it exists
        UserDefaults.standard.removeObject(forKey: notesKey)
    }

    private func loadNotes() {
        // CRITICAL FIX: Don't load from UserDefaults anymore
        // Notes are loaded from Supabase only in loadNotesFromSupabase()
        // This prevents the 89MB storage issue
    }

    private func saveFolders() {
        // CRITICAL FIX: Use Supabase only, not UserDefaults
        // Folders are already synced to Supabase in saveFolderToSupabase()
        UserDefaults.standard.removeObject(forKey: foldersKey)
    }

    private func loadFolders() {
        // CRITICAL FIX: Load from Supabase only
        // Folders are loaded from Supabase in loadFoldersFromSupabase()
    }

    // MARK: - Note Operations

    func addNote(_ note: Note) {
        notes.append(note)
        saveNotes()

        // Invalidate receipt cache if this is a receipt note
        invalidateReceiptCache()

        // Sync with Supabase with retry logic
        Task {
            let result = await saveNoteToSupabaseWithRetry(note, maxRetries: 3)
            // Immediately embed the note after successful save
            if result.success {
                await embedNoteImmediately(note)
                if note.isJournalEntry || note.isJournalWeeklyRecap {
                    await DaySummaryService.shared.refreshSummariesAffected(by: note)
                }
            }
        }
    }

    /// Async version that waits for Supabase sync to complete
    /// Use this when the note creation must be persisted before continuing (e.g., before uploading images)
    func addNoteAndWaitForSync(_ note: Note) async -> Bool {
        // CRITICAL FIX: Check if note already exists to prevent duplicates
        // This can happen if addNote() was called before addNoteAndWaitForSync()
        if !notes.contains(where: { $0.id == note.id }) {
            notes.append(note)
            saveNotes()

            // Invalidate receipt cache if this is a receipt note
            invalidateReceiptCache()
        }

        // Wait for Supabase save to complete with retry logic
        let result = await saveNoteToSupabaseWithRetry(note, maxRetries: 3)
        
        // Immediately embed the note after successful save
        if result.success {
            await embedNoteImmediately(note)
            if note.isJournalEntry || note.isJournalWeeklyRecap {
                await DaySummaryService.shared.refreshSummariesAffected(by: note)
            }
        }
        
        return result.success
    }

    /// Helper to make saveNoteToSupabaseWithRetry return a result
    private func saveNoteToSupabaseWithRetry(_ note: Note, maxRetries: Int, currentAttempt: Int = 1) async -> (success: Bool, error: String?) {
        let result = await saveNoteToSupabaseAndTrackResult(note)

        if !result.success && currentAttempt < maxRetries {
            // Exponential backoff: 2s, 4s, 8s
            let delaySeconds = pow(2.0, Double(currentAttempt))
            print("⏳ Retrying note save in \(delaySeconds)s (attempt \(currentAttempt + 1)/\(maxRetries))")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            return await saveNoteToSupabaseWithRetry(note, maxRetries: maxRetries, currentAttempt: currentAttempt + 1)
        } else if !result.success {
            print("❌ Failed to save note after \(maxRetries) attempts: \(result.error ?? "Unknown error")")
            return result
        }
        return result
    }


    private func saveNoteToSupabaseAndTrackResult(_ note: Note) async -> (success: Bool, error: String?) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return (false, "No user ID found")
        }

        // ✨ ENCRYPT sensitive fields before saving
        let encryptedNote: Note
        do {
            encryptedNote = try await encryptNoteBeforeSaving(note)
        } catch {
            return (false, "Encryption failed: \(error.localizedDescription)")
        }

        let imageUrls = encryptedNote.imageUrls
        let formatter = ISO8601DateFormatter()

        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        let noteData: [String: PostgREST.AnyJSON] = [
            "id": .string(note.id.uuidString),
            "user_id": .string(userId.uuidString),
            "title": .string(encryptedNote.title),
            "content": .string(encryptedNote.content),
            "is_locked": .bool(encryptedNote.isLocked),
            "date_created": .string(formatter.string(from: note.dateCreated)),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(encryptedNote.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "attachment_id": note.attachmentId != nil ? .string(note.attachmentId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray),
            "kind": .string(note.resolvedKind.rawValue),
            "journal_date": note.journalDate != nil ? .string(formatter.string(from: note.journalDate!)) : .null,
            "journal_week_start_date": note.journalWeekStartDate != nil ? .string(formatter.string(from: note.journalWeekStartDate!)) : .null
            // NOTE: reminder_date and reminder_note columns must be added to Supabase before enabling:
            // "reminder_date": note.reminderDate != nil ? .string(formatter.string(from: note.reminderDate!)) : .null,
            // "reminder_note": note.reminderNote != nil ? .string(note.reminderNote!) : .null
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .insert(noteData)
                .execute()
            print("✅ Successfully saved note to Supabase: \(note.title)")
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    /// Immediately embed a note after it's been saved/updated
    /// This ensures new/updated notes are searchable right away
    private func embedNoteImmediately(_ note: Note) async {
        // Decrypt note content for embedding (embeddings need plain text)
        let content: String
        do {
            if note.isLocked {
                // For locked notes, try to decrypt for embedding
                content = try await decryptNoteAfterLoading(note).content
            } else {
                content = note.content
            }
        } catch {
            print("⚠️ Could not decrypt note for embedding: \(error)")
            // Use encrypted content as fallback (less ideal but better than nothing)
            content = note.content
        }

        let folderName = note.folderId.flatMap { id in
            folders.first(where: { $0.id == id })?.name
        }
        let noteForEmbedding: Note = {
            var copy = note
            copy.content = content
            return copy
        }()
        let contentToEmbed = noteForEmbedding.embeddingContent(resolvedFolderName: folderName)
        
        do {
            try await VectorSearchService.shared.embedDocument(
                type: .note,
                id: note.id.uuidString,
                title: note.title,
                content: contentToEmbed,
                metadata: noteForEmbedding.embeddingMetadata(resolvedFolderName: folderName)
            )
            print("✅ Immediately embedded note: \(note.title)")
        } catch {
            print("⚠️ Failed to immediately embed note: \(error.localizedDescription)")
            // Note: The note will still be embedded on next sync, so this is not critical
        }
    }

    // Upload image and return URL - used when adding new images to notes
    func uploadNoteImage(_ image: UIImage, noteId: UUID) async throws -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "NotesManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Convert image to JPEG data with compression
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "NotesManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }

        // Generate filename with note ID and timestamp for uniqueness
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(noteId.uuidString)_\(timestamp).jpg"

        // Upload to Supabase Storage
        let imageUrl = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)

        return imageUrl
    }

    // Upload multiple images and return their URLs
    func uploadNoteImages(_ images: [UIImage], noteId: UUID) async -> [String] {
        var uploadedUrls: [String] = []

        for image in images {
            do {
                let url = try await uploadNoteImage(image, noteId: noteId)
                uploadedUrls.append(url)
            } catch {
                print("❌ Failed to upload image: \(error.localizedDescription)")
            }
        }

        return uploadedUrls
    }

    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = note
            updatedNote.dateModified = Date()
            notes[index] = updatedNote
            saveNotes()

            // Notify observers of change
            objectWillChange.send()

            // Invalidate receipt cache if this is a receipt note
            invalidateReceiptCache()
            
            // Update widgets to reflect changes
            WidgetInvalidationCoordinator.shared.requestReload(reason: "note_updated")
            
            // Invalidate reminder cache just in case
            CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.upcomingNoteReminders)

            // Sync with Supabase with retry logic (fire-and-forget for UI responsiveness)
            Task {
                let success = await updateNoteInSupabaseWithRetry(updatedNote, maxRetries: 3)
                // Immediately embed the note after successful update
                if success {
                    await embedNoteImmediately(updatedNote)
                    if updatedNote.isJournalEntry || updatedNote.isJournalWeeklyRecap {
                        await DaySummaryService.shared.refreshSummariesAffected(by: updatedNote)
                    }
                }
            }
        }
    }

    /// Async version that waits for Supabase sync to complete
    /// Use this when the note update must be persisted before continuing
    func updateNoteAndWaitForSync(_ note: Note) async -> Bool {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = note
            updatedNote.dateModified = Date()
            notes[index] = updatedNote
            saveNotes()

            // Notify observers of change
            objectWillChange.send()

            // Invalidate receipt cache if this is a receipt note
            invalidateReceiptCache()

            // Wait for Supabase update to complete with retry logic
            let result = await updateNoteInSupabaseWithRetry(updatedNote, maxRetries: 3)
            
            // Immediately embed the note after successful update
            if result {
                await embedNoteImmediately(updatedNote)
                if updatedNote.isJournalEntry || updatedNote.isJournalWeeklyRecap {
                    await DaySummaryService.shared.refreshSummariesAffected(by: updatedNote)
                }
            }
            
            return result
        }
        return false
    }

    private func updateNoteInSupabaseWithRetry(_ note: Note, maxRetries: Int, currentAttempt: Int = 1) async -> Bool {
        let result = await updateNoteInSupabaseAndTrackResult(note)

        if !result.success && currentAttempt < maxRetries {
            let delaySeconds = pow(2.0, Double(currentAttempt))
            print("⏳ Retrying note update in \(delaySeconds)s (attempt \(currentAttempt + 1)/\(maxRetries))")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            return await updateNoteInSupabaseWithRetry(note, maxRetries: maxRetries, currentAttempt: currentAttempt + 1)
        } else if !result.success {
            print("❌ Failed to update note after \(maxRetries) attempts: \(result.error ?? "Unknown error")")
            return false
        }
        return true
    }

    private func updateNoteInSupabaseAndTrackResult(_ note: Note) async -> (success: Bool, error: String?) {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else {
            return (false, "No user ID found")
        }

        let encryptedNote: Note
        do {
            encryptedNote = try await encryptNoteBeforeSaving(note)
        } catch {
            return (false, "Encryption failed: \(error.localizedDescription)")
        }

        let formatter = ISO8601DateFormatter()
        let imageUrlsArray: [PostgREST.AnyJSON] = encryptedNote.imageUrls.map { .string($0) }

        let noteData: [String: PostgREST.AnyJSON] = [
            "title": .string(encryptedNote.title),
            "content": .string(encryptedNote.content),
            "is_locked": .bool(encryptedNote.isLocked),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(encryptedNote.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "attachment_id": note.attachmentId != nil ? .string(note.attachmentId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray),
            "kind": .string(note.resolvedKind.rawValue),
            "journal_date": note.journalDate != nil ? .string(formatter.string(from: note.journalDate!)) : .null,
            "journal_week_start_date": note.journalWeekStartDate != nil ? .string(formatter.string(from: note.journalWeekStartDate!)) : .null
            // NOTE: reminder_date and reminder_note columns must be added to Supabase before enabling:
            // "reminder_date": note.reminderDate != nil ? .string(formatter.string(from: note.reminderDate!)) : .null,
            // "reminder_note": note.reminderNote != nil ? .string(note.reminderNote!) : .null
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .update(noteData)
                .eq("id", value: note.id.uuidString)
                .execute()
            print("✅ Successfully updated note in Supabase: \(note.title)")
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func deleteNote(_ note: Note) {
        // Move to trash instead of permanent deletion
        let deletedNote = DeletedNote(
            id: note.id,
            title: note.title,
            content: note.content,
            dateCreated: note.dateCreated,
            dateModified: note.dateModified,
            deletedAt: Date(),
            isPinned: note.isPinned,
            folderId: note.folderId,
            isLocked: note.isLocked,
            imageUrls: note.imageUrls
        )

        deletedNotes.append(deletedNote)
        notes.removeAll { $0.id == note.id }
        saveNotes()

        // Notify observers of change
        objectWillChange.send()

        // Invalidate receipt cache if this is a receipt note
        invalidateReceiptCache()

        // Immediately update widgets to reflect deletion
        WidgetInvalidationCoordinator.shared.requestReload(reason: "note_deleted")

        // Sync with Supabase
        Task {
            await moveNoteToTrash(deletedNote)
            if note.isJournalEntry || note.isJournalWeeklyRecap {
                await DaySummaryService.shared.refreshSummariesAffected(by: note)
            }
        }
    }

    private func moveNoteToTrash(_ deletedNote: DeletedNote) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        let formatter = ISO8601DateFormatter()

        let deletedNoteData: [String: PostgREST.AnyJSON] = [
            "id": .string(deletedNote.id.uuidString),
            "user_id": .string(userId.uuidString),
            "title": .string(deletedNote.title),
            "content": .string(deletedNote.content),
            "folder_id": deletedNote.folderId != nil ? .string(deletedNote.folderId!.uuidString) : .null,
            "is_pinned": .bool(deletedNote.isPinned),
            "background_color": .null,
            "created_at": .string(formatter.string(from: deletedNote.dateCreated)),
            "updated_at": .string(formatter.string(from: deletedNote.dateModified)),
            "deleted_at": .string(formatter.string(from: deletedNote.deletedAt))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            // Insert into deleted_notes
            try await client
                .from("deleted_notes")
                .insert(deletedNoteData)
                .execute()

            // Delete from notes table
            try await client
                .from("notes")
                .delete()
                .eq("id", value: deletedNote.id.uuidString)
                .execute()

        } catch {
            print("❌ Error moving note to trash: \(error)")
        }
    }

    // Permanent deletion - used when emptying trash or after 30 days
    func permanentlyDeleteNote(_ deletedNote: DeletedNote) {
        deletedNotes.removeAll { $0.id == deletedNote.id }

        Task {
            await permanentlyDeleteNoteWithImages(deletedNote)
        }
    }

    private func permanentlyDeleteNoteWithImages(_ deletedNote: DeletedNote) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping permanent deletion")
            return
        }

        // Delete from deleted_notes table
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("deleted_notes")
                .delete()
                .eq("id", value: deletedNote.id.uuidString)
                .execute()
        } catch {
            print("❌ Error permanently deleting note: \(error)")
        }

        // Delete associated images from storage
        for imageUrl in deletedNote.imageUrls {
            if let filename = imageUrl.components(separatedBy: "/").last {
                do {
                    let storage = await SupabaseManager.shared.getStorageClient()
                    let path = "\(userId.uuidString)/\(filename)"
                    try await storage
                        .from("note-images")
                        .remove(paths: [path])
                    print("🗑️ Deleted image: \(filename)")
                } catch {
                    print("❌ Failed to delete image \(filename): \(error)")
                }
            }
        }
    }

    // Restore note from trash
    func restoreNote(_ deletedNote: DeletedNote) {
        let restoredNote = Note(title: deletedNote.title, content: deletedNote.content, folderId: deletedNote.folderId)
        var note = restoredNote
        note.id = deletedNote.id
        note.dateCreated = deletedNote.dateCreated
        note.dateModified = deletedNote.dateModified
        note.isPinned = deletedNote.isPinned
        note.isLocked = deletedNote.isLocked
        note.imageUrls = deletedNote.imageUrls

        notes.append(note)
        deletedNotes.removeAll { $0.id == deletedNote.id }
        saveNotes()

        Task {
            await restoreNoteFromTrash(note)
        }
    }

    private func restoreNoteFromTrash(_ note: Note) async {
        // Delete from deleted_notes and insert back to notes
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("deleted_notes")
                .delete()
                .eq("id", value: note.id.uuidString)
                .execute()

            // Re-insert to notes table
            _ = await saveNoteToSupabaseWithRetry(note, maxRetries: 3)
        } catch {
            print("❌ Error restoring note from trash: \(error)")
        }
    }

    func togglePinStatus(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isPinned.toggle()
            notes[index].dateModified = Date()
            saveNotes()

            // Sync with Supabase with retry logic
            Task {
                await updateNoteInSupabaseWithRetry(notes[index], maxRetries: 3)
            }
        }
    }

    // MARK: - Folder Operations

    func addFolder(_ folder: NoteFolder) {
        folders.append(folder)
        saveFolders()

        // Sync with Supabase (async, non-blocking)
        Task {
            await saveFolderToSupabase(folder)
        }
    }

    /// Add folder and wait for Supabase sync to complete
    /// Used when folder reference is needed before saving notes
    func addFolderAndSync(_ folder: NoteFolder) async -> Bool {
        folders.append(folder)
        saveFolders()

        let success = await saveFolderToSupabaseWithRetry(folder, maxRetries: 3)
        return success
    }

    private func saveFolderToSupabaseWithRetry(_ folder: NoteFolder, maxRetries: Int, currentAttempt: Int = 1) async -> Bool {
        let result = await saveFolderToSupabaseAndTrackResult(folder)

        if !result.success && currentAttempt < maxRetries {
            let delaySeconds = pow(2.0, Double(currentAttempt))
            print("⏳ Retrying folder save in \(delaySeconds)s (attempt \(currentAttempt + 1)/\(maxRetries))")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            return await saveFolderToSupabaseWithRetry(folder, maxRetries: maxRetries, currentAttempt: currentAttempt + 1)
        } else if !result.success {
            print("❌ Failed to save folder after \(maxRetries) attempts: \(result.error ?? "Unknown error")")
        }
        return result.success
    }

    private func saveFolderToSupabaseAndTrackResult(_ folder: NoteFolder) async -> (success: Bool, error: String?) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return (false, "No user ID found")
        }

        let folderData: [String: PostgREST.AnyJSON] = [
            "id": .string(folder.id.uuidString),
            "user_id": .string(userId.uuidString),
            "name": .string(folder.name),
            "color": .string(folder.color),
            "parent_folder_id": folder.parentFolderId != nil ? .string(folder.parentFolderId!.uuidString) : .null
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("folders")
                .upsert(folderData)
                .execute()
            print("✅ Successfully saved folder to Supabase: \(folder.name)")
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func updateFolder(_ folder: NoteFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            saveFolders()

            // Sync with Supabase
            Task {
                await updateFolderInSupabase(folder)
            }
        }
    }

    func deleteFolder(_ folder: NoteFolder) {
        // Recursively collect all subfolders
        var foldersToDelete: Set<UUID> = [folder.id]
        var currentLevelFolders = [folder.id]

        while !currentLevelFolders.isEmpty {
            let childFolders = folders.filter { folder in
                currentLevelFolders.contains(folder.parentFolderId ?? UUID())
            }
            currentLevelFolders = childFolders.map { $0.id }
            foldersToDelete.formUnion(currentLevelFolders)
        }

        // Collect notes to move to trash
        let notesToDelete = notes.filter { note in
            if let folderId = note.folderId {
                return foldersToDelete.contains(folderId)
            }
            return false
        }

        // Move all notes in these folders to trash
        for note in notesToDelete {
            deleteNote(note)
        }

        // Move folders to trash
        let foldersToMove = folders.filter { foldersToDelete.contains($0.id) }
        for folderToDelete in foldersToMove {
            let deletedFolder = DeletedFolder(
                id: folderToDelete.id,
                name: folderToDelete.name,
                color: folderToDelete.color,
                parentFolderId: folderToDelete.parentFolderId,
                dateCreated: Date(),
                dateModified: Date(),
                deletedAt: Date()
            )
            deletedFolders.append(deletedFolder)
        }

        // Remove folders from active list
        folders.removeAll { foldersToDelete.contains($0.id) }

        saveFolders()

        // Sync with Supabase
        Task {
            for deletedFolder in deletedFolders.filter({ foldersToDelete.contains($0.id) }) {
                await moveFolderToTrash(deletedFolder)
            }
        }
    }

    private func moveFolderToTrash(_ deletedFolder: DeletedFolder) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        let formatter = ISO8601DateFormatter()

        let deletedFolderData: [String: PostgREST.AnyJSON] = [
            "id": .string(deletedFolder.id.uuidString),
            "user_id": .string(userId.uuidString),
            "name": .string(deletedFolder.name),
            "color": .string(deletedFolder.color),
            "parent_folder_id": deletedFolder.parentFolderId != nil ? .string(deletedFolder.parentFolderId!.uuidString) : .null,
            "created_at": .string(formatter.string(from: deletedFolder.dateCreated)),
            "updated_at": .string(formatter.string(from: deletedFolder.dateModified)),
            "deleted_at": .string(formatter.string(from: deletedFolder.deletedAt))
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            // Insert into deleted_folders
            try await client
                .from("deleted_folders")
                .insert(deletedFolderData)
                .execute()

            // Delete from folders table
            try await client
                .from("folders")
                .delete()
                .eq("id", value: deletedFolder.id.uuidString)
                .execute()

        } catch {
            print("❌ Error moving folder to trash: \(error)")
        }
    }

    // Permanent deletion of folder
    func permanentlyDeleteFolder(_ deletedFolder: DeletedFolder) {
        deletedFolders.removeAll { $0.id == deletedFolder.id }

        Task {
            await permanentlyDeleteFolderFromSupabase(deletedFolder.id)
        }
    }

    private func permanentlyDeleteFolderFromSupabase(_ folderId: UUID) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping permanent deletion")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("deleted_folders")
                .delete()
                .eq("id", value: folderId.uuidString)
                .execute()
        } catch {
            print("❌ Error permanently deleting folder: \(error)")
        }
    }

    // Restore folder from trash
    func restoreFolder(_ deletedFolder: DeletedFolder) {
        let restoredFolder = NoteFolder(
            id: deletedFolder.id,
            name: deletedFolder.name,
            color: deletedFolder.color,
            parentFolderId: deletedFolder.parentFolderId
        )

        folders.append(restoredFolder)
        deletedFolders.removeAll { $0.id == deletedFolder.id }
        saveFolders()

        Task {
            await restoreFolderFromTrash(restoredFolder)
        }
    }

    private func restoreFolderFromTrash(_ folder: NoteFolder) async {
        // Delete from deleted_folders and insert back to folders
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("deleted_folders")
                .delete()
                .eq("id", value: folder.id.uuidString)
                .execute()

            // Re-insert to folders table
            await saveFolderToSupabase(folder)
        } catch {
            print("❌ Error restoring folder from trash: \(error)")
        }
    }

    func getFolderName(for folderId: UUID?) -> String {
        guard let folderId = folderId,
              let folder = folders.first(where: { $0.id == folderId }) else {
            return "No Folder"
        }
        return folder.name
    }

    func getOrCreateReceiptsFolder() -> UUID {
        // Check if Receipts folder already exists
        if let existingFolder = folders.first(where: { normalizedReceiptFolderName($0.name) == "receipts" }) {
            return existingFolder.id
        }

        // Create new Receipts folder
        let receiptsFolder = NoteFolder(name: "Receipts", color: "#F59E42") // Orange color for receipts
        addFolder(receiptsFolder)
        return receiptsFolder.id
    }

    func getOrCreateJournalFolder() -> UUID {
        if let existingFolder = folders.first(where: { $0.name == "Journal" && $0.parentFolderId == nil }) {
            return existingFolder.id
        }

        let journalFolder = NoteFolder(name: "Journal", color: "#F3B27A")
        addFolder(journalFolder)
        return journalFolder.id
    }

    // MARK: - Receipt Organization by Month/Year

    // Extract month and year from receipt title (e.g., "Receipt - Store - December 15, 2024" -> (12, 2024))
    func extractMonthYearFromTitle(_ title: String) -> (month: Int, year: Int)? {
        // Common date patterns in receipt titles
        let datePatterns = [
            // "December 15, 2024" or "Dec 15, 2024"
            "([A-Z][a-z]+)\\s+(\\d{1,2}),?\\s+(\\d{4})",
            // "12/15/2024" or "12-15-2024"
            "(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})",
            // "2024-12-15"
            "(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})"
        ]

        let calendar = Calendar.current
        let monthSymbols = calendar.monthSymbols

        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, range: range) {
                    if pattern.contains("A-Z") {
                        // Month name pattern
                        if match.numberOfRanges >= 3,
                           let monthRange = Range(match.range(at: 1), in: title),
                           let yearRange = Range(match.range(at: 3), in: title) {
                            let monthName = String(title[monthRange])
                            if let monthIndex = monthSymbols.firstIndex(where: { $0.hasPrefix(monthName) }) {
                                if let year = Int(String(title[yearRange])) {
                                    return (month: monthIndex + 1, year: year)
                                }
                            }
                        }
                    } else if pattern.contains("\\d{4})[/-](\\d{1,2})") {
                        // ISO format (YYYY-MM-DD)
                        if match.numberOfRanges >= 3,
                           let yearRange = Range(match.range(at: 1), in: title),
                           let monthRange = Range(match.range(at: 2), in: title) {
                            if let year = Int(String(title[yearRange])),
                               let month = Int(String(title[monthRange])) {
                                return (month: month, year: year)
                            }
                        }
                    } else {
                        // MM/DD/YYYY or MM-DD-YYYY format
                        if match.numberOfRanges >= 3,
                           let monthRange = Range(match.range(at: 1), in: title),
                           let yearRange = Range(match.range(at: 3), in: title) {
                            if let month = Int(String(title[monthRange])),
                               let year = Int(String(title[yearRange])) {
                                return (month: month, year: year)
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    // Extract full date (day, month, year) from receipt title
    func extractFullDateFromTitle(_ title: String) -> Date? {
        let datePatterns = [
            // "December 15, 2024" or "Dec 15, 2024"
            ("([A-Z][a-z]+)\\s+(\\d{1,2}),?\\s+(\\d{4})", "monthName"),
            // "12/15/2024" or "12-15-2024"
            ("(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})", "mmddyyyy"),
            // "2024-12-15"
            ("(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})", "yyyymmdd")
        ]

        let calendar = Calendar.current
        let monthSymbols = calendar.monthSymbols

        for (pattern, format) in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, range: range) {
                    if format == "monthName" {
                        // Month name pattern
                        if match.numberOfRanges >= 4,
                           let monthRange = Range(match.range(at: 1), in: title),
                           let dayRange = Range(match.range(at: 2), in: title),
                           let yearRange = Range(match.range(at: 3), in: title) {
                            let monthName = String(title[monthRange])
                            if let monthIndex = monthSymbols.firstIndex(where: { $0.hasPrefix(monthName) }) {
                                if let day = Int(String(title[dayRange])),
                                   let year = Int(String(title[yearRange])) {
                                    var dateComponents = DateComponents()
                                    dateComponents.year = year
                                    dateComponents.month = monthIndex + 1
                                    dateComponents.day = day
                                    if let date = calendar.date(from: dateComponents) {
                                        return date
                                    }
                                }
                            }
                        }
                    } else if format == "yyyymmdd" {
                        // ISO format (YYYY-MM-DD)
                        if match.numberOfRanges >= 4,
                           let yearRange = Range(match.range(at: 1), in: title),
                           let monthRange = Range(match.range(at: 2), in: title),
                           let dayRange = Range(match.range(at: 3), in: title) {
                            if let year = Int(String(title[yearRange])),
                               let month = Int(String(title[monthRange])),
                               let day = Int(String(title[dayRange])) {
                                var dateComponents = DateComponents()
                                dateComponents.year = year
                                dateComponents.month = month
                                dateComponents.day = day
                                if let date = calendar.date(from: dateComponents) {
                                    return date
                                }
                            }
                        }
                    } else if format == "mmddyyyy" {
                        // MM/DD/YYYY or MM-DD-YYYY format
                        if match.numberOfRanges >= 4,
                           let monthRange = Range(match.range(at: 1), in: title),
                           let dayRange = Range(match.range(at: 2), in: title),
                           let yearRange = Range(match.range(at: 3), in: title) {
                            if let month = Int(String(title[monthRange])),
                               let day = Int(String(title[dayRange])),
                               let year = Int(String(title[yearRange])) {
                                var dateComponents = DateComponents()
                                dateComponents.year = year
                                dateComponents.month = month
                                dateComponents.day = day
                                if let date = calendar.date(from: dateComponents) {
                                    return date
                                }
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    // Get month name from month number
    func getMonthName(_ month: Int) -> String {
        let calendar = Calendar.current
        let monthSymbols = calendar.monthSymbols
        guard month >= 1 && month <= 12 else { return "Unknown" }
        return monthSymbols[month - 1]
    }

    // Get or create the year folder under Receipts
    private func getOrCreateYearFolder(_ year: Int, parentFolderId: UUID) -> UUID {
        let yearFolderName = String(year)
        if let existingFolder = folders.first(where: {
            $0.name == yearFolderName && $0.parentFolderId == parentFolderId
        }) {
            return existingFolder.id
        }

        let yearFolder = NoteFolder(name: yearFolderName, color: "#E8A87C", parentFolderId: parentFolderId)
        addFolder(yearFolder)
        return yearFolder.id
    }

    // Get or create the month folder under year folder
    private func getOrCreateMonthFolder(_ month: Int, year: Int, yearFolderId: UUID) -> UUID {
        let monthName = getMonthName(month)
        if let existingFolder = folders.first(where: {
            $0.name == monthName && $0.parentFolderId == yearFolderId
        }) {
            return existingFolder.id
        }

        let monthFolder = NoteFolder(name: monthName, color: "#D4956F", parentFolderId: yearFolderId)
        addFolder(monthFolder)
        return monthFolder.id
    }

    // Get or create the full month/year folder structure and return the month folder ID
    func getOrCreateReceiptMonthFolder(month: Int, year: Int) -> UUID {
        // Step 1: Get or create Receipts root folder
        let receiptsFolderId = getOrCreateReceiptsFolder()

        // Step 2: Get or create Year folder (e.g., "2024")
        let yearFolderId = getOrCreateYearFolder(year, parentFolderId: receiptsFolderId)

        // Step 3: Get or create Month folder (e.g., "December")
        let monthFolderId = getOrCreateMonthFolder(month, year: year, yearFolderId: yearFolderId)

        return monthFolderId
    }

    /// Async version that waits for all parent folders to sync to Supabase
    /// Used when folder ID is needed before saving notes to avoid foreign key violations
    func getOrCreateReceiptMonthFolderAsync(month: Int, year: Int) async -> UUID {
        // Step 1: Get or create Receipts root folder (sync to Supabase)
        let receiptsFolderId = await getOrCreateReceiptsFolderAsync()

        // Step 2: Get or create Year folder (sync to Supabase)
        let yearFolderId = await getOrCreateYearFolderAsync(year, parentFolderId: receiptsFolderId)

        // Step 3: Get or create Month folder (sync to Supabase)
        let monthFolderId = await getOrCreateMonthFolderAsync(month, year: year, yearFolderId: yearFolderId)

        return monthFolderId
    }

    /// Async version that ensures sync to Supabase
    private func getOrCreateReceiptsFolderAsync() async -> UUID {
        if let existingFolder = folders.first(where: { normalizedReceiptFolderName($0.name) == "receipts" }) {
            return existingFolder.id
        }
        let receiptsFolder = NoteFolder(name: "Receipts", color: "#F59E42")
        let synced = await addFolderAndSync(receiptsFolder)
        if synced {
            print("✅ Receipts folder synced to Supabase")
        } else {
            print("⚠️ Failed to sync Receipts folder, but using local ID")
        }
        return receiptsFolder.id
    }

    func getOrCreateJournalFolderAsync() async -> UUID {
        if let existingFolder = folders.first(where: { $0.name == "Journal" && $0.parentFolderId == nil }) {
            return existingFolder.id
        }

        let journalFolder = NoteFolder(name: "Journal", color: "#F3B27A")
        let synced = await addFolderAndSync(journalFolder)
        if synced {
            print("✅ Journal folder synced to Supabase")
        } else {
            print("⚠️ Failed to sync Journal folder, but using local ID")
        }
        return journalFolder.id
    }

    /// Async version that ensures sync to Supabase
    private func getOrCreateYearFolderAsync(_ year: Int, parentFolderId: UUID) async -> UUID {
        let yearFolderName = String(year)
        if let existingFolder = folders.first(where: {
            $0.name == yearFolderName && $0.parentFolderId == parentFolderId
        }) {
            return existingFolder.id
        }

        let yearFolder = NoteFolder(name: yearFolderName, color: "#E8A87C", parentFolderId: parentFolderId)
        let synced = await addFolderAndSync(yearFolder)
        if synced {
            print("✅ Year folder \(year) synced to Supabase")
        } else {
            print("⚠️ Failed to sync year folder, but using local ID")
        }
        return yearFolder.id
    }

    /// Async version that ensures sync to Supabase
    private func getOrCreateMonthFolderAsync(_ month: Int, year: Int, yearFolderId: UUID) async -> UUID {
        let monthName = getMonthName(month)
        if let existingFolder = folders.first(where: {
            $0.name == monthName && $0.parentFolderId == yearFolderId
        }) {
            return existingFolder.id
        }

        let monthFolder = NoteFolder(name: monthName, color: "#D4956F", parentFolderId: yearFolderId)
        let synced = await addFolderAndSync(monthFolder)
        if synced {
            print("✅ Month folder \(monthName) \(year) synced to Supabase")
        } else {
            print("⚠️ Failed to sync month folder, but using local ID")
        }
        return monthFolder.id
    }

    // Organize all receipts in the receipts folder into month/year structure
    func organizeReceiptsIntoMonthYears() {
        guard let receiptsFolderId = folders.first(where: { $0.name == "Receipts" })?.id else {
            return
        }

        // Get all notes in the Receipts folder (directly or in any subfolder)
        let allReceiptsNotes = notes.filter { note in
            guard let folderId = note.folderId else { return false }

            var currentFolderId: UUID? = folderId
            var isInReceiptsFolder = false

            // Check if this note is in the receipts folder hierarchy
            while let currentId = currentFolderId {
                if currentId == receiptsFolderId {
                    isInReceiptsFolder = true
                    break
                }
                currentFolderId = folders.first(where: { $0.id == currentId })?.parentFolderId
            }

            return isInReceiptsFolder
        }

        var movedCount = 0
        var movedWithoutDateCount = 0

        for receipt in allReceiptsNotes {
            // Try to extract month/year from title
            if let (month, year) = extractMonthYearFromTitle(receipt.title) {
                let monthFolderId = getOrCreateReceiptMonthFolder(month: month, year: year)
                if receipt.folderId != monthFolderId {
                    var updatedReceipt = receipt
                    updatedReceipt.folderId = monthFolderId
                    updateNote(updatedReceipt)
                    movedCount += 1
                    print("✅ Moved receipt '\(receipt.title)' to \(getMonthName(month)) \(year)")
                }
            } else {
                // If we can't extract date from title, try to use the note's creation/modification date
                let calendar = Calendar.current
                let components = calendar.dateComponents([.month, .year], from: receipt.dateModified)

                if let month = components.month, let year = components.year {
                    let monthFolderId = getOrCreateReceiptMonthFolder(month: month, year: year)
                    if receipt.folderId != monthFolderId {
                        var updatedReceipt = receipt
                        updatedReceipt.folderId = monthFolderId
                        updateNote(updatedReceipt)
                        movedWithoutDateCount += 1
                        print("⚠️ Moved receipt '\(receipt.title)' to \(getMonthName(month)) \(year) (using modification date)")
                    }
                }
            }
        }

        let totalMoved = movedCount + movedWithoutDateCount
        if totalMoved > 0 {
            print("✅ Successfully organized \(totalMoved) receipts into month/year folders (\(movedCount) by title date, \(movedWithoutDateCount) by modification date)")
        } else {
            print("ℹ️ No receipts needed reorganization")
        }
    }

    // MARK: - Computed Properties

    var pinnedNotes: [Note] {
        notes.filter { $0.isPinned }.sorted { $0.dateModified > $1.dateModified }
    }

    var recentNotes: [Note] {
        notes.filter { !$0.isPinned }.sorted { $0.dateModified > $1.dateModified }
    }

    var journalEntries: [Note] {
        notes
            .filter { $0.isJournalEntry }
            .sorted {
                let lhs = $0.journalDate ?? $0.dateModified
                let rhs = $1.journalDate ?? $1.dateModified
                return lhs > rhs
            }
    }

    var meaningfulJournalEntries: [Note] {
        journalEntries.filter(\.isMeaningfulJournalEntry)
    }

    var journalWeeklyRecaps: [Note] {
        notes
            .filter { $0.isJournalWeeklyRecap }
            .sorted {
                let lhs = $0.journalWeekStartDate ?? $0.dateModified
                let rhs = $1.journalWeekStartDate ?? $1.dateModified
                return lhs > rhs
            }
    }

    func searchNotes(query: String) -> [Note] {
        if query.isEmpty {
            return notes.sorted { $0.dateModified > $1.dateModified }
        }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query) ||
            note.content.localizedCaseInsensitiveContains(query)
        }.sorted { $0.dateModified > $1.dateModified }
    }

    func journalEntry(for day: Date, calendar: Calendar = .current) -> Note? {
        journalEntries.first { entry in
            guard let journalDate = entry.journalDate else { return false }
            return calendar.isDate(journalDate, inSameDayAs: day)
        }
    }

    func meaningfulJournalEntry(for day: Date, calendar: Calendar = .current) -> Note? {
        meaningfulJournalEntries.first { entry in
            guard let journalDate = entry.journalDate else { return false }
            return calendar.isDate(journalDate, inSameDayAs: day)
        }
    }

    func latestJournalRecap() -> Note? {
        journalWeeklyRecaps.first
    }

    func journalStats(referenceDate: Date = Date(), calendar: Calendar = .current) -> JournalStats {
        let uniqueEntryDays = Set(
            meaningfulJournalEntries.compactMap { entry in
                entry.journalDate.map { calendar.startOfDay(for: $0) }
            }
        )

        let sortedDays = uniqueEntryDays.sorted(by: >)
        let today = calendar.startOfDay(for: referenceDate)
        let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        let completedThisWeek = uniqueEntryDays.filter { day in
            guard let currentWeekInterval else { return false }
            return currentWeekInterval.contains(day)
        }.count

        var currentStreak = 0
        var cursor = today
        while uniqueEntryDays.contains(cursor) {
            currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var longestStreak = 0
        var activeStreak = 0
        var previousDay: Date?
        for day in sortedDays.reversed() {
            if let previousDay,
               let expectedNext = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(expectedNext, inSameDayAs: day) {
                activeStreak += 1
            } else {
                activeStreak = 1
            }
            longestStreak = max(longestStreak, activeStreak)
            previousDay = day
        }

        return JournalStats(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            completedThisWeek: completedThisWeek,
            totalEntries: uniqueEntryDays.count,
            lastEntryDate: sortedDays.first,
            todayStatus: uniqueEntryDays.contains(today) ? .complete : .missing
        )
    }

    // MARK: - Clear Data on Logout

    func clearNotesOnLogout() {
        notes = []
        folders = []
        deletedNotes = []
        deletedFolders = []

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: notesKey)
        UserDefaults.standard.removeObject(forKey: foldersKey)
        UserDefaults.standard.removeObject(forKey: "DeletedNotes")
        UserDefaults.standard.removeObject(forKey: "DeletedFolders")

        print("🗑️ Cleared all notes and folders on logout")
    }

    // MARK: - Sample Data

    private func addSampleDataIfNeeded() {
        // Sample data disabled per user request
    }

    // MARK: - Public Receipt Organization Method

    // Public method to organize all receipts into month/year folders
    func organizeAllReceiptsIntoMonthYears() {
        // Run on main thread to ensure UI updates properly
        DispatchQueue.main.async { [weak self] in
            self?.organizeReceiptsIntoMonthYears()
        }
    }

    // MARK: - Receipt Statistics

    /// Extract year and month from the folder hierarchy for a receipt
    /// - Parameter folderId: The folder ID of the receipt
    /// - Returns: Tuple containing (year as Int?, month as String?)
    private func extractYearAndMonthFromFolderHierarchy(_ folderId: UUID?) -> (year: Int?, month: String?) {
        guard let folderId = folderId else { return (nil, nil) }

        // Get the month folder (first level - should contain month name)
        guard let monthFolder = folders.first(where: { $0.id == folderId }) else {
            return (nil, nil)
        }

        let monthName = monthFolder.name

        // Get the year folder (second level - should contain year as string)
        guard let yearFolder = folders.first(where: { $0.id == monthFolder.parentFolderId }) else {
            return (nil, monthName)
        }

        let yearString = yearFolder.name
        let year = Int(yearString)

        return (year, monthName)
    }

    /// Get receipt statistics organized by year and month
    /// - Parameter year: Optional year to filter by. If nil, returns all years.
    /// - Returns: Array of YearlyReceiptSummary sorted by year (most recent first)
    func getReceiptStatistics(year: Int? = nil) -> [YearlyReceiptSummary] {
        // Check cache first
        let cacheKey = receiptStatsCacheKey(for: year)
        if let cached: [YearlyReceiptSummary] = cacheManager.get(forKey: cacheKey) {
            return cached
        }

        let receiptRootIds = receiptRootFolderIds()
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let allReceiptsNotes = receiptCandidateNotes()

        guard !allReceiptsNotes.isEmpty else {
            if shouldUseLastKnownReceiptStatsFallback(),
               let lastKnown = cachedLastKnownReceiptStatistics(year: year) {
                return lastKnown
            }
            return []
        }

        // Convert notes to ReceiptStat with resilient date/year/month derivation.
        // Priority:
        // 1) explicit date parsed from title
        // 2) folder year/month (if valid)
        // 3) note modified date
        let receiptStats = allReceiptsNotes.map { note in
            let calendar = Calendar.current
            let isInReceiptHierarchy = isUnderFolderHierarchy(
                folderId: note.folderId,
                rootFolderIds: receiptRootIds,
                foldersById: foldersById
            )
            let (folderYear, folderMonth) = isInReceiptHierarchy
                ? extractYearAndMonthFromFolderHierarchy(note.folderId)
                : (nil, nil)
            let parsedDateFromTitle = extractFullDateFromTitle(note.title)

            let fallbackFromFolder: Date? = {
                guard
                    let folderYear,
                    let folderMonth,
                    let monthIndex = calendar.monthSymbols.firstIndex(of: folderMonth)
                else {
                    return nil
                }

                var components = calendar.dateComponents([.hour, .minute, .second], from: note.dateModified)
                components.year = folderYear
                components.month = monthIndex + 1
                components.day = calendar.component(.day, from: note.dateModified)
                return calendar.date(from: components)
            }()

            let effectiveDate = parsedDateFromTitle ?? fallbackFromFolder ?? note.dateModified
            let effectiveYear = calendar.component(.year, from: effectiveDate)
            let effectiveMonth = calendar.monthSymbols[calendar.component(.month, from: effectiveDate) - 1]

            return ReceiptStat(
                from: note,
                year: effectiveYear,
                month: effectiveMonth,
                date: effectiveDate
            )
        }

        // Group by year from folder hierarchy
        var yearlyStats: [Int: [ReceiptStat]] = [:]

        for receipt in receiptStats {
            if let receiptYear = receipt.year {
                if yearlyStats[receiptYear] == nil {
                    yearlyStats[receiptYear] = []
                }
                yearlyStats[receiptYear]?.append(receipt)
            }
        }

        // Filter by year if specified
        if let specifiedYear = year {
            yearlyStats = yearlyStats.filter { $0.key == specifiedYear }
        }

        // Create yearly summaries with monthly breakdowns
        var yearlySummaries: [YearlyReceiptSummary] = []

        for (yearKey, receipts) in yearlyStats {
            // Group receipts by month from folder hierarchy
            var monthlyStats: [String: [ReceiptStat]] = [:]

            for receipt in receipts {
                if let monthName = receipt.month {
                    if monthlyStats[monthName] == nil {
                        monthlyStats[monthName] = []
                    }
                    monthlyStats[monthName]?.append(receipt)
                }
            }

            // Create monthly summaries
            var monthlySummaries: [MonthlyReceiptSummary] = []

            for (monthName, monthReceipts) in monthlyStats {
                // Convert month name to month number for date creation
                let calendar = Calendar.current
                let monthSymbols = calendar.monthSymbols
                let monthNumber = monthSymbols.firstIndex(of: monthName).map { $0 + 1 } ?? 1

                // Create a date for sorting
                var dateComponents = DateComponents()
                dateComponents.year = yearKey
                dateComponents.month = monthNumber
                dateComponents.day = 1
                let monthDate = calendar.date(from: dateComponents) ?? Date()

                let monthSummary = MonthlyReceiptSummary(
                    month: monthName,
                    monthDate: monthDate,
                    receipts: monthReceipts
                )
                monthlySummaries.append(monthSummary)
            }

            let yearlySummary = YearlyReceiptSummary(year: yearKey, monthlySummaries: monthlySummaries)
            yearlySummaries.append(yearlySummary)
        }

        // Sort by year (most recent first)
        let result = yearlySummaries.sorted { $0.year > $1.year }

        if !result.isEmpty {
            persistReceiptStatisticsCache(result, year: year)
            return result
        }

        if shouldUseLastKnownReceiptStatsFallback(),
           let lastKnown = cachedLastKnownReceiptStatistics(year: year) {
            return lastKnown
        }

        return result
    }

    /// Get all available years with receipts
    /// - Returns: Array of years sorted in descending order
    func getAvailableReceiptYears() -> [Int] {
        let statistics = getReceiptStatistics()
        return statistics.map { $0.year }.sorted(by: >)
    }

    /// Get category breakdown for a specific year
    /// - Parameter year: The year to get category breakdown for
    /// - Returns: YearlyCategoryBreakdown with categorized receipts
    func getCategoryBreakdown(for year: Int) async -> YearlyCategoryBreakdown {
        // Check cache first
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let cacheKey = CacheManager.CacheKey.categoryBreakdown(year: year, month: currentMonth)
        if let cached: YearlyCategoryBreakdown = cacheManager.get(forKey: cacheKey) {
            return cached
        }

        let yearStats = getReceiptStatistics(year: year)
        guard let stats = yearStats.first else {
            // Return empty breakdown if no receipts found
            return YearlyCategoryBreakdown(year: year, categories: [], yearlyTotal: 0, categoryReceipts: [:], allReceipts: [])
        }

        // Get all receipts from the yearly summary
        let allReceipts = stats.monthlySummaries.flatMap { $0.receipts }

        // Use ReceiptCategorizationService to get the breakdown
        let breakdown = await ReceiptCategorizationService.shared.getCategoryBreakdown(for: allReceipts)

        // Only cache non-empty results (prevents caching empty state during app initialization)
        if !breakdown.categories.isEmpty {
            cacheManager.set(breakdown, forKey: cacheKey, ttl: CacheManager.TTL.persistent)
        }

        return breakdown
    }

    // Debug method to print receipt information
    func debugPrintReceipts() {
        guard let receiptsFolderId = folders.first(where: { $0.name == "Receipts" })?.id else {
            return
        }

        print("\n📋 === RECEIPT DEBUG INFO ===")
        print("Total notes: \(notes.count)")
        print("Total folders: \(folders.count)")

        // Get all receipts
        let allReceiptsNotes = notes.filter { note in
            guard let folderId = note.folderId else { return false }
            var currentFolderId: UUID? = folderId
            while let currentId = currentFolderId {
                if currentId == receiptsFolderId {
                    return true
                }
                currentFolderId = folders.first(where: { $0.id == currentId })?.parentFolderId
            }
            return false
        }

        print("\nReceipts in Receipts folder: \(allReceiptsNotes.count)")
        for (index, receipt) in allReceiptsNotes.enumerated() {
            let folderName = receipt.folderId.flatMap { id in folders.first(where: { $0.id == id })?.name } ?? "Unknown"
            print("  \(index + 1). '\(receipt.title)' - Folder: \(folderName) - Modified: \(receipt.dateModified)")
            if let (month, year) = extractMonthYearFromTitle(receipt.title) {
                print("     → Extracted date: \(getMonthName(month)) \(year)")
            } else {
                let components = Calendar.current.dateComponents([.month, .year], from: receipt.dateModified)
                if let month = components.month, let year = components.year {
                    print("     → Fallback date: \(getMonthName(month)) \(year)")
                }
            }
        }

        // Print folder structure
        print("\n📁 Folder structure:")
        for folder in folders.sorted(by: { $0.name < $1.name }) {
            if let parentId = folder.parentFolderId {
                let parentName = folders.first(where: { $0.id == parentId })?.name ?? "Unknown"
                print("  - \(folder.name) (parent: \(parentName))")
            } else {
                print("  - \(folder.name) (root)")
            }
        }
        print("=== END DEBUG ===\n")
    }

    // MARK: - Supabase Sync


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
            // Check if it's a boolean encoded as NSNumber
            if CFNumberGetType(number as CFNumber) == .charType {
                return .bool(number.boolValue)
            }
            // Keep as number for proper JSONB encoding (timestamps, counts, etc.)
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return .integer(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        } else if object is NSNull {
            return .null
        }
        throw NSError(domain: "ConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported type: \(type(of: object))"])
    }


    private func deleteNoteFromSupabase(_ noteId: UUID) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .delete()
                .eq("id", value: noteId.uuidString)
                .execute()
        } catch {
            print("❌ Error deleting note from Supabase: \(error)")
        }
    }

    func loadNotesFromSupabase() async {
        beginDataLoadOperation()
        defer { endDataLoadOperation() }

        let authIsAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await resolvedAuthenticatedUserId()

        guard authIsAuthenticated || userId != nil, let userId = userId else {
            print("User not authenticated, loading local notes only")
            return
        }

        // CRITICAL: Ensure encryption key is initialized before loading
        // Wait for EncryptionManager to be ready (max 5 seconds)
        var attempts = 0
        while EncryptionManager.shared.isKeyInitialized == false && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }

        // If still not initialized, force initialize it now
        if !EncryptionManager.shared.isKeyInitialized {
            print("⚠️ Encryption key not initialized after 5 seconds, initializing now with userId: \(userId.uuidString)")
            await MainActor.run {
                EncryptionManager.shared.setupEncryption(with: userId)
            }
        }

        // Verify encryption key is now initialized before proceeding
        if !EncryptionManager.shared.isKeyInitialized {
            print("❌ CRITICAL: Encryption key failed to initialize! Notes cannot be decrypted.")
            return
        }

        // DEBUG: Commented out to reduce console spam
        // print("✅ Encryption key is ready. Proceeding to load notes.")

        // DEBUG: Commented out to reduce console spam
        // print("📥 Loading notes from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [NoteSupabaseData] = try await client
                .from("notes")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            // DEBUG: Commented out to reduce console spam
            // print("📥 Received \(response.count) notes from Supabase")

            // Parse notes with image URLs (no downloads!) and decrypt
            var parsedNotes: [Note] = []
            for supabaseNote in response {
                if let note = await parseNoteFromSupabase(supabaseNote) {
                    parsedNotes.append(note)
                }
            }

            await MainActor.run {
                // Only update if we have notes from Supabase
                if !response.isEmpty {
                    // Only update if we successfully parsed at least one note
                    if !parsedNotes.isEmpty {
                        self.notes = parsedNotes
                        saveNotes()
                        // Clear receipt cache to refresh stats with newly loaded data
                        self.invalidateReceiptCache()
                        self.lastSyncTime = Date()
                        self.syncError = nil
                    } else {
                        print("⚠️ Failed to parse any notes from Supabase, keeping \(self.notes.count) local notes")
                    }
                } else {
                    print("ℹ️ No notes in Supabase, keeping \(self.notes.count) local notes")
                    self.lastSyncTime = Date()
                    self.syncError = nil
                }
            }
        } catch {
            print("❌ Error loading notes from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            await MainActor.run {
                self.syncError = error.localizedDescription
            }
        }
    }

    private func parseNoteFromSupabase(_ data: NoteSupabaseData) async -> Note? {
        guard let id = UUID(uuidString: data.id) else {
            print("❌ Failed to parse note ID: \(data.id)")
            return nil
        }

        // Try parsing dates with different formatters
        let formatter = ISO8601DateFormatter()

        var dateCreated: Date?
        var dateModified: Date?

        // Try with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dateCreated = formatter.date(from: data.date_created)
        dateModified = formatter.date(from: data.date_modified)

        // If that fails, try without fractional seconds
        if dateCreated == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateCreated = formatter.date(from: data.date_created)
        }

        if dateModified == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateModified = formatter.date(from: data.date_modified)
        }

        guard let dateCreated = dateCreated else {
            print("❌ Failed to parse date_created: \(data.date_created)")
            return nil
        }

        guard let dateModified = dateModified else {
            print("❌ Failed to parse date_modified: \(data.date_modified)")
            return nil
        }

        var note = Note(title: data.title, content: data.content)
        note.id = id
        note.dateCreated = dateCreated
        note.dateModified = dateModified
        note.isPinned = data.is_pinned
        note.isLocked = data.is_locked
        if let folderIdString = data.folder_id {
            note.folderId = UUID(uuidString: folderIdString)
        }
        if let attachmentIdString = data.attachment_id {
            note.attachmentId = UUID(uuidString: attachmentIdString)
        }
        // Store image URLs directly - no download!
        note.imageUrls = data.image_attachments ?? []
        note.kind = data.kind.flatMap(NoteKind.init(rawValue:))
        if let journalDateString = data.journal_date {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsedDate = formatter.date(from: journalDateString) {
                note.journalDate = parsedDate
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                note.journalDate = formatter.date(from: journalDateString)
            }
        }
        if let journalWeekStartDateString = data.journal_week_start_date {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsedDate = formatter.date(from: journalWeekStartDateString) {
                note.journalWeekStartDate = parsedDate
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                note.journalWeekStartDate = formatter.date(from: journalWeekStartDateString)
            }
        }
        
        // Parse reminder details
        if let reminderDateString = data.reminder_date {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: reminderDateString) {
                note.reminderDate = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                note.reminderDate = formatter.date(from: reminderDateString)
            }
        }
        note.reminderNote = data.reminder_note

        // ✨ DECRYPT after loading
        let decryptedNote: Note
        do {
            decryptedNote = try await decryptNoteAfterLoading(note)
        } catch {
            print("⚠️ Could not decrypt note \(note.id.uuidString): \(error.localizedDescription)")
            print("   Note will be returned unencrypted (legacy data)")
            // Return original if decryption fails (backward compatible)
            return note
        }

        return decryptedNote
    }

    // Called when user signs in to load their notes
    func syncNotesOnLogin() async {
        beginDataLoadOperation()
        defer { endDataLoadOperation() }

        // Load folders first, then sync any local folders that aren't in Supabase
        await loadFoldersFromSupabase()
        await syncLocalFoldersToSupabase()

        // Then load notes (which may reference the folders)
        await loadNotesFromSupabase()
    }

    // Sync local folders to Supabase if they don't exist there yet
    private func syncLocalFoldersToSupabase() async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping local folder sync")
            return
        }

        // Get the current folders from local storage
        let localFolders = await MainActor.run { self.folders }

        guard !localFolders.isEmpty else {
            print("ℹ️ No local folders to sync")
            return
        }


        // Sort folders by hierarchy level to ensure parents are uploaded before children
        let sortedFolders = sortFoldersByHierarchy(localFolders)

        // Upload each local folder to Supabase in correct order
        for folder in sortedFolders {
            await saveFolderToSupabase(folder)
        }

    }

    // Sort folders so parents come before children
    private func sortFoldersByHierarchy(_ folders: [NoteFolder]) -> [NoteFolder] {
        var result: [NoteFolder] = []
        var processed: Set<UUID> = []

        // Helper function to add folder and its ancestors
        func addFolderWithAncestors(_ folder: NoteFolder) {
            // Skip if already processed
            if processed.contains(folder.id) {
                return
            }

            // If folder has a parent, add parent first
            if let parentId = folder.parentFolderId,
               let parent = folders.first(where: { $0.id == parentId }) {
                addFolderWithAncestors(parent)
            }

            // Add this folder
            result.append(folder)
            processed.insert(folder.id)
        }

        // Process all folders
        for folder in folders {
            addFolderWithAncestors(folder)
        }

        return result
    }

    // MARK: - Folder Supabase Sync

    private func saveFolderToSupabase(_ folder: NoteFolder) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase folder sync")
            return
        }

        // DEBUG: Commented out to reduce console spam
        // print("💾 Saving folder to Supabase - User ID: \(userId.uuidString), Folder ID: \(folder.id.uuidString)")

        let folderData: [String: PostgREST.AnyJSON] = [
            "id": .string(folder.id.uuidString),
            "user_id": .string(userId.uuidString),
            "name": .string(folder.name),  // Plain text - folder names are not sensitive
            "color": .string(folder.color),
            "parent_folder_id": folder.parentFolderId != nil ? .string(folder.parentFolderId!.uuidString) : .null
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            // Use upsert to insert or update if already exists
            try await client
                .from("folders")
                .upsert(folderData)
                .execute()
        } catch {
            print("❌ Error saving folder to Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func updateFolderInSupabase(_ folder: NoteFolder) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase folder sync")
            return
        }

        let folderData: [String: PostgREST.AnyJSON] = [
            "name": .string(folder.name),  // Plain text - folder names are not sensitive
            "color": .string(folder.color),
            "parent_folder_id": folder.parentFolderId != nil ? .string(folder.parentFolderId!.uuidString) : .null
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("folders")
                .update(folderData)
                .eq("id", value: folder.id.uuidString)
                .execute()
        } catch {
            print("❌ Error updating folder in Supabase: \(error)")
        }
    }

    private func deleteFolderFromSupabase(_ folderId: UUID) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase folder sync")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("folders")
                .delete()
                .eq("id", value: folderId.uuidString)
                .execute()
        } catch {
            print("❌ Error deleting folder from Supabase: \(error)")
        }
    }

    func loadFoldersFromSupabase() async {
        beginDataLoadOperation()
        defer { endDataLoadOperation() }

        let authIsAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await resolvedAuthenticatedUserId()

        guard authIsAuthenticated || userId != nil, let userId = userId else {
            print("User not authenticated, loading local folders only")
            return
        }

        // CRITICAL: Ensure encryption key is initialized before loading
        // Wait for EncryptionManager to be ready (max 5 seconds)
        var attempts = 0
        while EncryptionManager.shared.isKeyInitialized == false && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }

        // If still not initialized, force initialize it now
        if !EncryptionManager.shared.isKeyInitialized {
            print("⚠️ Encryption key not initialized after 5 seconds, initializing now with userId: \(userId.uuidString)")
            await MainActor.run {
                EncryptionManager.shared.setupEncryption(with: userId)
            }
        }

        // Verify encryption key is now initialized
        if !EncryptionManager.shared.isKeyInitialized {
            print("❌ CRITICAL: Encryption key failed to initialize! Folders cannot be decrypted.")
            return
        }

        // DEBUG: Commented out to reduce console spam
        // print("✅ Encryption key is ready. Proceeding to load folders.")

        // DEBUG: Commented out to reduce console spam
        // print("📥 Loading folders from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [FolderSupabaseData] = try await client
                .from("folders")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            // DEBUG: Commented out to reduce console spam
            // print("📥 Received \(response.count) folders from Supabase")

            // Parse folders with decryption
            var parsedFolders: [NoteFolder] = []
            for supabaseFolder in response {
                if let folder = await parseFolderFromSupabase(supabaseFolder) {
                    parsedFolders.append(folder)
                }
            }

            await MainActor.run {
                if !parsedFolders.isEmpty {
                    self.folders = parsedFolders
                    saveFolders()
                    // Clear receipt cache since folder structure affects receipt organization
                    self.invalidateReceiptCache()
                    self.lastSyncTime = Date()
                    self.syncError = nil
                } else {
                    print("⚠️ Failed to parse any folders from Supabase, keeping \(self.folders.count) local folders")
                }

                if response.isEmpty {
                    print("ℹ️ No folders in Supabase, keeping \(self.folders.count) local folders")
                    self.lastSyncTime = Date()
                    self.syncError = nil
                }
            }
        } catch {
            print("❌ Error loading folders from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            await MainActor.run {
                self.syncError = error.localizedDescription
            }
        }
    }

    private func parseFolderFromSupabase(_ data: FolderSupabaseData) async -> NoteFolder? {
        guard let id = UUID(uuidString: data.id) else {
            print("❌ Failed to parse folder ID: \(data.id)")
            return nil
        }

        var parentFolderId: UUID? = nil
        if let parentIdString = data.parent_folder_id {
            parentFolderId = UUID(uuidString: parentIdString)
        }

        // Try to decrypt folder name (handles legacy encrypted folders)
        var folderName = data.name
        do {
            // Attempt to decrypt - if it fails, the name is probably plain text (original behavior)
            let decryptedName = try EncryptionManager.shared.decrypt(data.name)
            folderName = decryptedName
            print("✅ Decrypted folder name: \(data.name.prefix(30))... → \(folderName)")
        } catch {
            // Decryption failed - name is already plain text, use as-is
            // DEBUG: Commented out to reduce console spam
            // print("ℹ️ Folder name is plain text (not encrypted): \(folderName)")
        }

        let folder = NoteFolder(
            id: id,
            name: folderName,
            color: data.color,
            parentFolderId: parentFolderId
        )

        return folder
    }

    // MARK: - Trash Management

    func loadDeletedItemsFromSupabase() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }

        guard isAuthenticated, let userId = userId else {
            print("User not authenticated, skipping trash load")
            return
        }

        print("📥 Loading deleted items from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Load deleted notes
            let deletedNotesResponse: [DeletedNoteSupabaseData] = try await client
                .from("deleted_notes")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            // Load deleted folders
            let deletedFoldersResponse: [DeletedFolderSupabaseData] = try await client
                .from("deleted_folders")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            await MainActor.run {
                self.deletedNotes = deletedNotesResponse.compactMap { parseDeletedNoteFromSupabase($0) }
                self.deletedFolders = deletedFoldersResponse.compactMap { parseDeletedFolderFromSupabase($0) }
            }
        } catch {
            print("❌ Error loading deleted items: \(error)")
        }
    }

    private func parseDeletedNoteFromSupabase(_ data: DeletedNoteSupabaseData) -> DeletedNote? {
        guard let id = UUID(uuidString: data.id) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let createdAt = formatter.date(from: data.created_at) ?? ISO8601DateFormatter().date(from: data.created_at),
              let updatedAt = formatter.date(from: data.updated_at) ?? ISO8601DateFormatter().date(from: data.updated_at),
              let deletedAt = formatter.date(from: data.deleted_at) ?? ISO8601DateFormatter().date(from: data.deleted_at) else {
            return nil
        }

        return DeletedNote(
            id: id,
            title: data.title,
            content: data.content,
            dateCreated: createdAt,
            dateModified: updatedAt,
            deletedAt: deletedAt,
            isPinned: data.is_pinned,
            folderId: data.folder_id != nil ? UUID(uuidString: data.folder_id!) : nil,
            isLocked: false,
            imageUrls: []
        )
    }

    private func parseDeletedFolderFromSupabase(_ data: DeletedFolderSupabaseData) -> DeletedFolder? {
        guard let id = UUID(uuidString: data.id) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let createdAt = formatter.date(from: data.created_at) ?? ISO8601DateFormatter().date(from: data.created_at),
              let updatedAt = formatter.date(from: data.updated_at) ?? ISO8601DateFormatter().date(from: data.updated_at),
              let deletedAt = formatter.date(from: data.deleted_at) ?? ISO8601DateFormatter().date(from: data.deleted_at) else {
            return nil
        }

        return DeletedFolder(
            id: id,
            name: data.name,
            color: data.color,
            parentFolderId: data.parent_folder_id != nil ? UUID(uuidString: data.parent_folder_id!) : nil,
            dateCreated: createdAt,
            dateModified: updatedAt,
            deletedAt: deletedAt
        )
    }

    // Clean up items older than 30 days
    func cleanupOldDeletedItems() {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        // Find items to permanently delete
        let expiredNotes = deletedNotes.filter { $0.deletedAt < thirtyDaysAgo }
        let expiredFolders = deletedFolders.filter { $0.deletedAt < thirtyDaysAgo }

        // Permanently delete expired items
        for note in expiredNotes {
            permanentlyDeleteNote(note)
        }

        for folder in expiredFolders {
            permanentlyDeleteFolder(folder)
        }

        if !expiredNotes.isEmpty || !expiredFolders.isEmpty {
            print("🗑️ Cleaned up \(expiredNotes.count) notes and \(expiredFolders.count) folders older than 30 days")
        }
    }

    // MARK: - Bulk Re-encryption for Existing Data

    /// Folder names are NOT encrypted (they're not sensitive)
    /// Only note titles and content are encrypted
    /// This function is deprecated and does nothing
    func reencryptAllExistingFolders() async {
        print("ℹ️ Folder re-encryption is not needed - folder names are stored as plain text")
        print("   Only note titles and content are encrypted for security")
    }

    /// Re-encrypt all existing notes in Supabase
    /// This converts plaintext notes to encrypted notes
    /// Call this once to secure all existing user data
    ///
    /// Usage:
    /// ```swift
    /// Task {
    ///     await NotesManager.shared.reencryptAllExistingNotes()
    /// }
    /// ```
    func reencryptAllExistingNotes() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }

        guard isAuthenticated, let userId = userId else {
            print("❌ User not authenticated, cannot re-encrypt notes")
            return
        }

        print("🔐 Starting bulk re-encryption of existing notes...")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch ALL notes for this user
            let response: [NoteSupabaseData] = try await client
                .from("notes")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Fetched \(response.count) notes for re-encryption")

            var reencryptedCount = 0
            var skippedCount = 0
            var errorCount = 0

            // Process each note
            for (index, supabaseNote) in response.enumerated() {
                // Try to decrypt it - if it fails, it's plaintext
                var note = Note(title: supabaseNote.title, content: supabaseNote.content)
                note.id = UUID(uuidString: supabaseNote.id) ?? UUID()
                note.isPinned = supabaseNote.is_pinned
                note.isLocked = supabaseNote.is_locked

                // Check if already encrypted by trying to decrypt
                let decryptTest = try? EncryptionManager.shared.decrypt(supabaseNote.title)

                if decryptTest != nil && decryptTest == supabaseNote.title {
                    // Successfully decrypted to same value = already encrypted
                    skippedCount += 1
                    print("✅ Note \(index + 1)/\(response.count): Already encrypted - '\(supabaseNote.title)'")
                } else {
                    // Failed to decrypt or got different value = plaintext
                    // Re-encrypt it
                    do {
                        let encrypted = try await encryptNoteBeforeSaving(note)

                        // Update in Supabase with encrypted version
                        let formatter = ISO8601DateFormatter()
                        let updateData: [String: PostgREST.AnyJSON] = [
                            "title": .string(encrypted.title),
                            "content": .string(encrypted.content),
                            "date_modified": .string(formatter.string(from: Date()))
                        ]

                        try await client
                            .from("notes")
                            .update(updateData)
                            .eq("id", value: note.id.uuidString)
                            .execute()

                        reencryptedCount += 1
                        print("🔐 Note \(index + 1)/\(response.count): Re-encrypted - '\(supabaseNote.title)'")
                    } catch {
                        errorCount += 1
                        print("❌ Note \(index + 1)/\(response.count): Failed to encrypt - '\(supabaseNote.title)': \(error.localizedDescription)")
                    }
                }
            }

            // Summary
            print("\n" + String(repeating: "=", count: 60))
            print("🔐 BULK RE-ENCRYPTION COMPLETE")
            print("=" + String(repeating: "=", count: 60))
            print("✅ Re-encrypted: \(reencryptedCount) notes")
            print("✅ Already encrypted: \(skippedCount) notes")
            print("❌ Errors: \(errorCount) notes")
            print("📊 Total: \(response.count) notes processed")
            print(String(repeating: "=", count: 60) + "\n")

            if reencryptedCount > 0 {
                print("✨ All \(reencryptedCount) plaintext notes have been encrypted!")
                print("   Your data is now protected with end-to-end encryption.")
            } else if skippedCount == response.count {
                print("✨ All notes are already encrypted!")
                print("   Your data is fully protected.")
            }

        } catch {
            print("❌ Error during bulk re-encryption: \(error)")
            print("   Please try again later")
        }
    }

    // MARK: - Cache Invalidation

    var shouldPreserveVisibleReceiptStats: Bool {
        shouldUseLastKnownReceiptStatsFallback()
    }

    private func receiptStatsCacheKey(for year: Int?) -> String {
        guard let year else { return CacheManager.CacheKey.receiptStatsAll }
        return CacheManager.CacheKey.receiptStats(year: year)
    }

    private func lastKnownReceiptStatsCacheKey(for year: Int?) -> String {
        guard let year else { return CacheManager.CacheKey.lastKnownReceiptStatsAll }
        return CacheManager.CacheKey.lastKnownReceiptStats(year: year)
    }

    private func persistReceiptStatisticsCache(_ result: [YearlyReceiptSummary], year: Int?) {
        guard !result.isEmpty else { return }

        let liveCacheKey = receiptStatsCacheKey(for: year)
        let lastKnownCacheKey = lastKnownReceiptStatsCacheKey(for: year)
        cacheManager.set(result, forKey: liveCacheKey, ttl: CacheManager.TTL.persistent)
        cacheManager.set(result, forKey: lastKnownCacheKey, ttl: CacheManager.TTL.persistent)

        if year == nil {
            for summary in result {
                let singleYearSummary = [summary]
                cacheManager.set(
                    singleYearSummary,
                    forKey: CacheManager.CacheKey.receiptStats(year: summary.year),
                    ttl: CacheManager.TTL.persistent
                )
                cacheManager.set(
                    singleYearSummary,
                    forKey: CacheManager.CacheKey.lastKnownReceiptStats(year: summary.year),
                    ttl: CacheManager.TTL.persistent
                )
            }
        }
    }

    private func cachedLastKnownReceiptStatistics(year: Int?) -> [YearlyReceiptSummary]? {
        let lastKnownCacheKey = lastKnownReceiptStatsCacheKey(for: year)
        if let cached: [YearlyReceiptSummary] = cacheManager.get(forKey: lastKnownCacheKey),
           !cached.isEmpty {
            return cached
        }

        let allCacheKeys = [
            CacheManager.CacheKey.receiptStatsAll,
            CacheManager.CacheKey.lastKnownReceiptStatsAll
        ]

        for cacheKey in allCacheKeys {
            if let cachedAll: [YearlyReceiptSummary] = cacheManager.get(forKey: cacheKey),
               !cachedAll.isEmpty {
                guard let year else { return cachedAll }

                let matchingYear = cachedAll.filter { $0.year == year }
                if !matchingYear.isEmpty {
                    return matchingYear
                }
            }
        }

        return nil
    }

    private func shouldUseLastKnownReceiptStatsFallback() -> Bool {
        if isLoading || isSyncing {
            return true
        }

        if notes.isEmpty || folders.isEmpty {
            return true
        }

        if receiptRootFolderIds().isEmpty && receiptCandidateNotes().isEmpty {
            return true
        }

        if let lastReceiptCacheInvalidationDate,
           Date().timeIntervalSince(lastReceiptCacheInvalidationDate) < receiptStatsFallbackGracePeriod {
            return true
        }

        return false
    }

    /// Invalidate all receipt-related caches when notes change
    private func invalidateReceiptCache() {
        lastReceiptCacheInvalidationDate = Date()

        // Invalidate all receipt stats caches
        cacheManager.invalidate(keysWithPrefix: "cache.receipts.stats.")
        // Invalidate all category breakdown caches
        cacheManager.invalidate(keysWithPrefix: "cache.receipts.categoryBreakdown.")
        // Invalidate today's receipts and spending
        cacheManager.invalidate(forKey: CacheManager.CacheKey.todaysReceipts)
        cacheManager.invalidate(forKey: CacheManager.CacheKey.todaysSpending)

        // OPTIMIZATION: Also invalidate search cache since notes are searchable
        cacheManager.invalidate(keysWithPrefix: "cache.search")
        
        // Refresh widget spending data after cache invalidation
        // Use a slight delay to ensure fresh data is calculated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SpendingAndETAWidget.refreshWidgetSpendingData()
        }
    }

    /// Public method to force clear all receipt caches (useful for debugging or fixing bad cached state)
    public func clearReceiptCache() {
        invalidateReceiptCache()
        cacheManager.invalidate(keysWithPrefix: "cache.receipts.lastKnownStats.")
        print("🗑️ Cleared all receipt caches")
    }
}

// MARK: - Supabase Data Structures

// Helper to decode any JSON value
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable(value: $0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable(value: $0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }

    init(value: Any) {
        self.value = value
    }
}

struct NoteSupabaseData: Codable {
    let id: String
    let user_id: String
    let title: String
    let content: String
    let is_locked: Bool
    let date_created: String
    let date_modified: String
    let is_pinned: Bool
    let folder_id: String?
    let attachment_id: String? // Single file attachment
    let image_attachments: [String]? // Array of image URLs from JSONB
    let kind: String?
    let journal_date: String?
    let journal_week_start_date: String?
    let reminder_date: String?
    let reminder_note: String?

    enum CodingKeys: String, CodingKey {
        case id, user_id, title, content, is_locked, date_created, date_modified, is_pinned, folder_id, attachment_id, image_attachments, kind, journal_date, journal_week_start_date, reminder_date, reminder_note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        user_id = try container.decode(String.self, forKey: .user_id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        is_locked = try container.decode(Bool.self, forKey: .is_locked)
        date_created = try container.decode(String.self, forKey: .date_created)
        date_modified = try container.decode(String.self, forKey: .date_modified)
        is_pinned = try container.decode(Bool.self, forKey: .is_pinned)
        folder_id = try container.decodeIfPresent(String.self, forKey: .folder_id)
        attachment_id = try container.decodeIfPresent(String.self, forKey: .attachment_id)

        // Handle both string (old format) and array (new format) for image_attachments
        if let attachmentsArray = try? container.decodeIfPresent([String].self, forKey: .image_attachments) {
            image_attachments = attachmentsArray
        } else if let attachmentsString = try? container.decodeIfPresent(String.self, forKey: .image_attachments),
                  let data = attachmentsString.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) {
            image_attachments = array
        } else {
            image_attachments = nil
        }

        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        journal_date = try container.decodeIfPresent(String.self, forKey: .journal_date)
        journal_week_start_date = try container.decodeIfPresent(String.self, forKey: .journal_week_start_date)
        
        reminder_date = try container.decodeIfPresent(String.self, forKey: .reminder_date)
        reminder_note = try container.decodeIfPresent(String.self, forKey: .reminder_note)
    }
}

struct FolderSupabaseData: Codable {
    let id: String
    let user_id: String
    let name: String
    let color: String
    let parent_folder_id: String?
    let created_at: String?
    let updated_at: String?
}

struct DeletedNoteSupabaseData: Codable {
    let id: String
    let user_id: String
    let title: String
    let content: String
    let folder_id: String?
    let is_pinned: Bool
    let created_at: String
    let updated_at: String
    let deleted_at: String
}

struct DeletedFolderSupabaseData: Codable {
    let id: String
    let user_id: String
    let name: String
    let color: String
    let parent_folder_id: String?
    let created_at: String
    let updated_at: String
    let deleted_at: String
}
