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
    var isDraft: Bool
    var imageAttachments: [Data] // Store images as Data array

    init(title: String, content: String = "", folderId: UUID? = nil, isDraft: Bool = false) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.dateCreated = Date()
        self.dateModified = Date()
        self.isPinned = false
        self.folderId = folderId
        self.isLocked = false
        self.isDraft = isDraft
        self.imageAttachments = []
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

// MARK: - Notes Manager

class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published var notes: [Note] = []
    @Published var folders: [NoteFolder] = []
    @Published var isLoading = false

    private let notesKey = "SavedNotes"
    private let foldersKey = "SavedNoteFolders"
    private let authManager = AuthenticationManager.shared

    private init() {
        loadNotes()
        loadFolders()
        addSampleDataIfNeeded()

        // Load notes from Supabase if user is authenticated
        Task {
            await loadNotesFromSupabase()
        }
    }

    // MARK: - Data Persistence

    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: notesKey)
        }
    }

    private func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let decodedNotes = try? JSONDecoder().decode([Note].self, from: data) {
            self.notes = decodedNotes
        }
    }

    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: foldersKey)
        }
    }

    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let decodedFolders = try? JSONDecoder().decode([NoteFolder].self, from: data) {
            self.folders = decodedFolders
        }
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

    // Upload image and return URL
    func uploadImage(_ image: UIImage) async throws -> String {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "NotesManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Convert image to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "NotesManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }

        // Generate unique filename
        let fileName = "\(UUID().uuidString).jpg"

        // Upload to Supabase
        let imageUrl = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)

        print("✅ Image uploaded successfully: \(imageUrl)")
        return imageUrl
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
        notes.removeAll { $0.id == note.id }
        saveNotes()

        // Sync with Supabase
        Task {
            await deleteNoteFromSupabase(note.id)
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
        // Move notes from this folder to no folder
        for index in notes.indices {
            if notes[index].folderId == folder.id {
                notes[index].folderId = nil
            }
        }

        folders.removeAll { $0.id == folder.id }
        saveNotes()
        saveFolders()

        // Sync with Supabase
        Task {
            await deleteFolderFromSupabase(folder.id)
        }
    }

    func getFolderName(for folderId: UUID?) -> String {
        guard let folderId = folderId,
              let folder = folders.first(where: { $0.id == folderId }) else {
            return "No Folder"
        }
        return folder.name
    }

    // MARK: - Computed Properties

    var pinnedNotes: [Note] {
        notes.filter { $0.isPinned && !$0.isDraft }.sorted { $0.dateModified > $1.dateModified }
    }

    var recentNotes: [Note] {
        notes.filter { !$0.isPinned && !$0.isDraft }.sorted { $0.dateModified > $1.dateModified }
    }

    var draftNotes: [Note] {
        notes.filter { $0.isDraft }.sorted { $0.dateModified > $1.dateModified }
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

        // Upload images to Supabase Storage and get URLs
        var imageUrls: [String] = []
        for (index, imageData) in note.imageAttachments.enumerated() {
            do {
                let fileName = "\(note.id.uuidString)_\(index).jpg"
                let url = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)
                imageUrls.append(url)
            } catch {
                print("❌ Error uploading image \(index): \(error)")
            }
        }

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
            "is_draft": .bool(note.isDraft),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray)
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .insert(noteData)
                .execute()
            print("✅ Note saved to Supabase: \(note.title) with \(imageUrls.count) images")
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

        // Upload images to Supabase Storage and get URLs
        var imageUrls: [String] = []
        for (index, imageData) in note.imageAttachments.enumerated() {
            do {
                let fileName = "\(note.id.uuidString)_\(index).jpg"
                let url = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)
                imageUrls.append(url)
            } catch {
                print("❌ Error uploading image \(index): \(error)")
            }
        }

        let formatter = ISO8601DateFormatter()

        // Convert image URLs to AnyJSON array
        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        let noteData: [String: PostgREST.AnyJSON] = [
            "title": .string(note.title),
            "content": .string(note.content),
            "is_locked": .bool(note.isLocked),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(note.isPinned),
            "is_draft": .bool(note.isDraft),
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
            print("✅ Note updated in Supabase: \(note.title) with \(imageUrls.count) images")
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

            // Parse notes and download images
            var parsedNotes: [Note] = []
            for supabaseNote in response {
                if var note = parseNoteFromSupabase(supabaseNote) {
                    // Download images from Supabase Storage
                    if let imageUrls = supabaseNote.image_attachments, !imageUrls.isEmpty {
                        for imageUrl in imageUrls {
                            do {
                                guard let url = URL(string: imageUrl) else {
                                    continue
                                }

                                let (data, _) = try await URLSession.shared.data(from: url)
                                note.imageAttachments.append(data)
                            } catch {
                                print("❌ Error downloading image: \(error)")
                            }
                        }
                    }
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

        print("✅ Successfully parsed note: \(note.title)")
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