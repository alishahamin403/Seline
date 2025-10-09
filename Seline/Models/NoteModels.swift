import Foundation
import SwiftUI
import PostgREST

// MARK: - Note Models

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

    // Temporary compatibility - will be removed after migration
    var imageAttachments: [Data] {
        get { [] }
        set { }
    }

    init(title: String, content: String = "", folderId: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.dateCreated = Date()
        self.dateModified = Date()
        self.isPinned = false
        self.folderId = folderId
        self.isLocked = false
        self.imageUrls = []
    }

    var formattedDateModified: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDate(dateModified, inSameDayAs: now) {
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: dateModified))"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(dateModified, inSameDayAs: yesterday) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: dateModified)
        }
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No additional text"
        }
        return String(trimmed.prefix(100))
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

class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published var notes: [Note] = []
    @Published var folders: [NoteFolder] = []
    @Published var deletedNotes: [DeletedNote] = []
    @Published var deletedFolders: [DeletedFolder] = []
    @Published var isLoading = false

    private let notesKey = "SavedNotes"
    private let foldersKey = "SavedNoteFolders"
    private let authManager = AuthenticationManager.shared

    private init() {
        // CRITICAL FIX: Clear old UserDefaults data (was 89MB!)
        migrateFromUserDefaultsToSupabase()

        // Don't load from UserDefaults anymore
        // loadNotes()
        // loadFolders()

        addSampleDataIfNeeded()

        // Load notes from Supabase if user is authenticated
        Task {
            await loadNotesFromSupabase()
        }
    }

    // Migration: Remove old UserDefaults storage
    private func migrateFromUserDefaultsToSupabase() {
        // Remove the 89MB of data from UserDefaults
        UserDefaults.standard.removeObject(forKey: notesKey)
        UserDefaults.standard.removeObject(forKey: foldersKey)
        print("✅ Cleared old UserDefaults notes storage (was 89MB)")
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

        // Sync with Supabase
        Task {
            await saveNoteToSupabase(note)
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

        print("✅ Image uploaded successfully: \(imageUrl)")
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

            // Sync with Supabase
            Task {
                await updateNoteInSupabase(updatedNote)
            }
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

        // Sync with Supabase
        Task {
            await moveNoteToTrash(deletedNote)
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

            print("✅ Note moved to trash: \(deletedNote.title)")
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
            print("✅ Note permanently deleted from database")
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
            await saveNoteToSupabase(note)
            print("✅ Note restored from trash: \(note.title)")
        } catch {
            print("❌ Error restoring note from trash: \(error)")
        }
    }

    func togglePinStatus(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isPinned.toggle()
            notes[index].dateModified = Date()
            saveNotes()

            // Sync with Supabase
            Task {
                await updateNoteInSupabase(notes[index])
            }
        }
    }

    // MARK: - Folder Operations

    func addFolder(_ folder: NoteFolder) {
        folders.append(folder)
        saveFolders()

        // Sync with Supabase
        Task {
            await saveFolderToSupabase(folder)
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

            print("✅ Folder moved to trash: \(deletedFolder.name)")
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
            print("✅ Folder permanently deleted from database")
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
            print("✅ Folder restored from trash: \(folder.name)")
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
        if let existingFolder = folders.first(where: { $0.name == "Receipts" }) {
            return existingFolder.id
        }

        // Create new Receipts folder
        let receiptsFolder = NoteFolder(name: "Receipts", color: "#F59E42") // Orange color for receipts
        addFolder(receiptsFolder)
        return receiptsFolder.id
    }

    // MARK: - Computed Properties

    var pinnedNotes: [Note] {
        notes.filter { $0.isPinned }.sorted { $0.dateModified > $1.dateModified }
    }

    var recentNotes: [Note] {
        notes.filter { !$0.isPinned }.sorted { $0.dateModified > $1.dateModified }
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

    // MARK: - Sample Data

    private func addSampleDataIfNeeded() {
        if notes.isEmpty {
            let sampleNote1 = Note(
                title: "Waqar is a psycho",
                content: "This is a sample note to demonstrate the notes functionality."
            )

            let sampleNote2 = Note(
                title: "Test",
                content: "Another test note with some content to show in the preview."
            )

            notes = [sampleNote1, sampleNote2]
            saveNotes()
        }
    }

    // MARK: - Supabase Sync

    private func saveNoteToSupabase(_ note: Note) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        print("💾 Saving note to Supabase - User ID: \(userId.uuidString), Note ID: \(note.id.uuidString)")

        // OPTIMIZED: Use existing imageUrls from note (no re-upload needed)
        let imageUrls = note.imageUrls

        let formatter = ISO8601DateFormatter()

        // Convert image URLs to AnyJSON array
        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        let noteData: [String: PostgREST.AnyJSON] = [
            "id": .string(note.id.uuidString),
            "user_id": .string(userId.uuidString),
            "title": .string(note.title),
            "content": .string(note.content),
            "is_locked": .bool(note.isLocked),
            "date_created": .string(formatter.string(from: note.dateCreated)),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(note.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray)
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .insert(noteData)
                .execute()
            print("✅ Note saved to Supabase: \(note.title) with \(imageUrls.count) image URLs")
        } catch {
            print("❌ Error saving note to Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func updateNoteInSupabase(_ note: Note) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        // OPTIMIZED: Use existing imageUrls from note (preserves existing URLs, no re-upload)
        let imageUrls = note.imageUrls

        let formatter = ISO8601DateFormatter()

        // Convert image URLs to AnyJSON array
        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        let noteData: [String: PostgREST.AnyJSON] = [
            "title": .string(note.title),
            "content": .string(note.content),
            "is_locked": .bool(note.isLocked),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(note.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray)
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .update(noteData)
                .eq("id", value: note.id.uuidString)
                .execute()
            print("✅ Note updated in Supabase: \(note.title) with \(imageUrls.count) image URLs (no re-upload)")
        } catch {
            print("❌ Error updating note in Supabase: \(error)")
        }
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
            print("✅ Note deleted from Supabase")
        } catch {
            print("❌ Error deleting note from Supabase: \(error)")
        }
    }

    func loadNotesFromSupabase() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }

        guard isAuthenticated, let userId = userId else {
            print("User not authenticated, loading local notes only")
            return
        }

        print("📥 Loading notes from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [NoteSupabaseData] = try await client
                .from("notes")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Received \(response.count) notes from Supabase")

            // Parse notes with image URLs (no downloads!)
            var parsedNotes: [Note] = []
            for supabaseNote in response {
                if let note = parseNoteFromSupabase(supabaseNote) {
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
                        print("✅ Loaded \(parsedNotes.count) notes from Supabase")
                    } else {
                        print("⚠️ Failed to parse any notes from Supabase, keeping \(self.notes.count) local notes")
                    }
                } else {
                    print("ℹ️ No notes in Supabase, keeping \(self.notes.count) local notes")
                }
            }
        } catch {
            print("❌ Error loading notes from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func parseNoteFromSupabase(_ data: NoteSupabaseData) -> Note? {
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
            print("⚠️ Parsed date_created without fractional seconds: \(data.date_created)")
        }

        if dateModified == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateModified = formatter.date(from: data.date_modified)
            print("⚠️ Parsed date_modified without fractional seconds: \(data.date_modified)")
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
        // Store image URLs directly - no download!
        note.imageUrls = data.image_attachments ?? []

        print("✅ Successfully parsed note: \(note.title) with \(note.imageUrls.count) image URLs")
        return note
    }

    // Called when user signs in to load their notes
    func syncNotesOnLogin() async {
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

        print("🔄 Syncing \(localFolders.count) local folders to Supabase")

        // Sort folders by hierarchy level to ensure parents are uploaded before children
        let sortedFolders = sortFoldersByHierarchy(localFolders)

        // Upload each local folder to Supabase in correct order
        for folder in sortedFolders {
            await saveFolderToSupabase(folder)
        }

        print("✅ Finished syncing local folders to Supabase")
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

        print("💾 Saving folder to Supabase - User ID: \(userId.uuidString), Folder ID: \(folder.id.uuidString)")

        let folderData: [String: PostgREST.AnyJSON] = [
            "id": .string(folder.id.uuidString),
            "user_id": .string(userId.uuidString),
            "name": .string(folder.name),
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
            print("✅ Folder saved to Supabase: \(folder.name)")
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
            "name": .string(folder.name),
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
            print("✅ Folder updated in Supabase: \(folder.name)")
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
            print("✅ Folder deleted from Supabase")
        } catch {
            print("❌ Error deleting folder from Supabase: \(error)")
        }
    }

    func loadFoldersFromSupabase() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }

        guard isAuthenticated, let userId = userId else {
            print("User not authenticated, loading local folders only")
            return
        }

        print("📥 Loading folders from Supabase for user: \(userId.uuidString)")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [FolderSupabaseData] = try await client
                .from("folders")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Received \(response.count) folders from Supabase")

            await MainActor.run {
                if !response.isEmpty {
                    let parsedFolders = response.compactMap { supabaseFolder in
                        parseFolderFromSupabase(supabaseFolder)
                    }

                    if !parsedFolders.isEmpty {
                        self.folders = parsedFolders
                        saveFolders()
                        print("✅ Loaded \(parsedFolders.count) folders from Supabase")
                    } else {
                        print("⚠️ Failed to parse any folders from Supabase, keeping \(self.folders.count) local folders")
                    }
                } else {
                    print("ℹ️ No folders in Supabase, keeping \(self.folders.count) local folders")
                }
            }
        } catch {
            print("❌ Error loading folders from Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func parseFolderFromSupabase(_ data: FolderSupabaseData) -> NoteFolder? {
        guard let id = UUID(uuidString: data.id) else {
            print("❌ Failed to parse folder ID: \(data.id)")
            return nil
        }

        var parentFolderId: UUID? = nil
        if let parentIdString = data.parent_folder_id {
            parentFolderId = UUID(uuidString: parentIdString)
        }

        let folder = NoteFolder(
            id: id,
            name: data.name,
            color: data.color,
            parentFolderId: parentFolderId
        )

        print("✅ Successfully parsed folder: \(folder.name)")
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
                print("✅ Loaded \(self.deletedNotes.count) deleted notes and \(self.deletedFolders.count) deleted folders")
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
}

// MARK: - Supabase Data Structures

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
    let image_attachments: [String]? // Array of image URLs from JSONB

    enum CodingKeys: String, CodingKey {
        case id, user_id, title, content, is_locked, date_created, date_modified, is_pinned, folder_id, image_attachments
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