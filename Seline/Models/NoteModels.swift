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
    var tables: [NoteTable] // Store embedded tables
    var todoLists: [NoteTodoList] // Store embedded todo lists

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
        self.tables = []
        self.todoLists = []
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
    var tables: [NoteTable]
    var todoLists: [NoteTodoList]

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
            imageUrls: note.imageUrls,
            tables: note.tables,
            todoLists: note.todoLists
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
        note.tables = deletedNote.tables

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
        if let existingFolder = folders.first(where: { $0.name == "Receipts" }) {
            return existingFolder.id
        }

        // Create new Receipts folder
        let receiptsFolder = NoteFolder(name: "Receipts", color: "#F59E42") // Orange color for receipts
        addFolder(receiptsFolder)
        return receiptsFolder.id
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

    // Organize all receipts in the receipts folder into month/year structure
    func organizeReceiptsIntoMonthYears() {
        guard let receiptsFolderId = folders.first(where: { $0.name == "Receipts" })?.id else {
            print("❌ Receipts folder not found")
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
        guard let receiptsFolderId = folders.first(where: { $0.name == "Receipts" })?.id else {
            print("❌ Receipts folder not found")
            return []
        }

        // Get all notes in the Receipts folder hierarchy
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

        // Convert notes to ReceiptStat with year and month extracted from folder hierarchy
        let receiptStats = allReceiptsNotes.map { note in
            let (folderYear, folderMonth) = extractYearAndMonthFromFolderHierarchy(note.folderId)
            return ReceiptStat(from: note, year: folderYear, month: folderMonth)
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
        return yearlySummaries.sorted { $0.year > $1.year }
    }

    /// Get all available years with receipts
    /// - Returns: Array of years sorted in descending order
    func getAvailableReceiptYears() -> [Int] {
        let statistics = getReceiptStatistics()
        return statistics.map { $0.year }.sorted(by: >)
    }

    // Debug method to print receipt information
    func debugPrintReceipts() {
        guard let receiptsFolderId = folders.first(where: { $0.name == "Receipts" })?.id else {
            print("❌ Receipts folder not found")
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

    private func saveNoteToSupabase(_ note: Note) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        print("💾 Saving note to Supabase - User ID: \(userId.uuidString), Note ID: \(note.id.uuidString)")

        // ✨ ENCRYPT sensitive fields before saving
        let encryptedNote: Note
        do {
            encryptedNote = try await encryptNoteBeforeSaving(note)
        } catch {
            print("❌ Failed to encrypt note: \(error.localizedDescription)")
            return
        }

        // OPTIMIZED: Use existing imageUrls from note (no re-upload needed)
        let imageUrls = encryptedNote.imageUrls

        let formatter = ISO8601DateFormatter()

        // Convert image URLs to AnyJSON array
        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        // Convert tables to JSON data
        var tablesJSON: PostgREST.AnyJSON = .null
        if !note.tables.isEmpty {
            do {
                let encoder = JSONEncoder()
                // Use custom date encoding for NSDate/timeIntervalSinceReferenceDate format
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(date.timeIntervalSinceReferenceDate)
                }
                let tablesData = try encoder.encode(note.tables)
                let jsonObject = try JSONSerialization.jsonObject(with: tablesData)
                tablesJSON = try convertToAnyJSON(jsonObject)
                print("✅ Successfully encoded \(note.tables.count) table(s) for note: \(note.title)")
            } catch {
                print("❌ Error encoding tables for note \(note.title): \(error)")
                print("❌ Tables data: \(note.tables)")
            }
        }

        // Convert todo lists to JSON data
        var todoListsJSON: PostgREST.AnyJSON = .null
        if !note.todoLists.isEmpty {
            do {
                let encoder = JSONEncoder()
                // Use custom date encoding for NSDate/timeIntervalSinceReferenceDate format
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(date.timeIntervalSinceReferenceDate)
                }
                let todoListsData = try encoder.encode(note.todoLists)
                let jsonObject = try JSONSerialization.jsonObject(with: todoListsData)
                todoListsJSON = try convertToAnyJSON(jsonObject)
                print("✅ Successfully encoded \(note.todoLists.count) todo list(s) for note: \(note.title)")
            } catch {
                print("❌ Error encoding todo lists for note \(note.title): \(error)")
                print("❌ Todo lists data: \(note.todoLists)")
            }
        }

        let noteData: [String: PostgREST.AnyJSON] = [
            "id": .string(note.id.uuidString),
            "user_id": .string(userId.uuidString),
            "title": .string(encryptedNote.title),  // ✨ Encrypted
            "content": .string(encryptedNote.content),  // ✨ Encrypted
            "is_locked": .bool(encryptedNote.isLocked),
            "date_created": .string(formatter.string(from: note.dateCreated)),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(encryptedNote.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray),
            "tables": tablesJSON,
            "todo_lists": todoListsJSON
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .insert(noteData)
                .execute()
        } catch {
            print("❌ Error saving note to Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

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

    private func updateNoteInSupabase(_ note: Note) async {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }

        // ✨ ENCRYPT sensitive fields before updating
        let encryptedNote: Note
        do {
            encryptedNote = try await encryptNoteBeforeSaving(note)
        } catch {
            print("❌ Failed to encrypt note: \(error.localizedDescription)")
            return
        }

        // OPTIMIZED: Use existing imageUrls from note (preserves existing URLs, no re-upload)
        let imageUrls = encryptedNote.imageUrls

        let formatter = ISO8601DateFormatter()

        // Convert image URLs to AnyJSON array
        let imageUrlsArray: [PostgREST.AnyJSON] = imageUrls.map { .string($0) }

        // Convert tables to JSON data
        var tablesJSON: PostgREST.AnyJSON = .null
        if !note.tables.isEmpty {
            do {
                let encoder = JSONEncoder()
                // Use custom date encoding for NSDate/timeIntervalSinceReferenceDate format
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(date.timeIntervalSinceReferenceDate)
                }
                let tablesData = try encoder.encode(note.tables)
                let jsonObject = try JSONSerialization.jsonObject(with: tablesData)
                tablesJSON = try convertToAnyJSON(jsonObject)
                print("✅ Successfully encoded \(note.tables.count) table(s) for UPDATE of note: \(note.title)")
            } catch {
                print("❌ Error encoding tables for UPDATE of note \(note.title): \(error)")
                print("❌ Tables data: \(note.tables)")
            }
        }

        // Convert todo lists to JSON data
        var todoListsJSON: PostgREST.AnyJSON = .null
        if !note.todoLists.isEmpty {
            do {
                let encoder = JSONEncoder()
                // Use custom date encoding for NSDate/timeIntervalSinceReferenceDate format
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    var container = encoder.singleValueContainer()
                    try container.encode(date.timeIntervalSinceReferenceDate)
                }
                let todoListsData = try encoder.encode(note.todoLists)
                let jsonObject = try JSONSerialization.jsonObject(with: todoListsData)
                todoListsJSON = try convertToAnyJSON(jsonObject)
                print("✅ Successfully encoded \(note.todoLists.count) todo list(s) for UPDATE of note: \(note.title)")
            } catch {
                print("❌ Error encoding todo lists for UPDATE of note \(note.title): \(error)")
                print("❌ Todo lists data: \(note.todoLists)")
            }
        }

        let noteData: [String: PostgREST.AnyJSON] = [
            "title": .string(encryptedNote.title),  // ✨ Encrypted
            "content": .string(encryptedNote.content),  // ✨ Encrypted
            "is_locked": .bool(encryptedNote.isLocked),
            "date_modified": .string(formatter.string(from: note.dateModified)),
            "is_pinned": .bool(encryptedNote.isPinned),
            "folder_id": note.folderId != nil ? .string(note.folderId!.uuidString) : .null,
            "image_attachments": .array(imageUrlsArray),
            "tables": tablesJSON,
            "todo_lists": todoListsJSON
        ]

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("notes")
                .update(noteData)
                .eq("id", value: note.id.uuidString)
                .execute()
            print("✅ Successfully updated note in Supabase: \(encryptedNote.title) (encrypted)")
        } catch {
            print("❌ Error updating note in Supabase: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
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
        // Store tables
        note.tables = data.tables ?? []
        // Store todo lists
        note.todoLists = data.todo_lists ?? []

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
            imageUrls: [],
            tables: [],
            todoLists: []
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
    let image_attachments: [String]? // Array of image URLs from JSONB
    let tables: [NoteTable]? // Array of tables from JSONB
    let todo_lists: [NoteTodoList]? // Array of todo lists from JSONB

    enum CodingKeys: String, CodingKey {
        case id, user_id, title, content, is_locked, date_created, date_modified, is_pinned, folder_id, image_attachments, tables, todo_lists
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

        // Decode tables array
        // The JSONB from Supabase needs special handling for dates (timeIntervalSinceReferenceDate)
        do {
            if container.contains(.tables) {
                let rawValue = try container.decode(AnyCodable.self, forKey: .tables)

                // Check if value is null or empty
                if rawValue.value is NSNull {
                    tables = nil
                    print("ℹ️ Tables field is null")
                } else if let arrayValue = rawValue.value as? [Any], arrayValue.isEmpty {
                    tables = []
                    print("ℹ️ Tables field is empty array")
                } else if let arrayValue = rawValue.value as? [Any], JSONSerialization.isValidJSONObject(arrayValue) {
                    // Convert to JSON data and re-decode with proper date strategy
                    let jsonData = try JSONSerialization.data(withJSONObject: arrayValue)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let container = try decoder.singleValueContainer()
                        let timeInterval = try container.decode(Double.self)
                        return Date(timeIntervalSinceReferenceDate: timeInterval)
                    }
                    tables = try decoder.decode([NoteTable].self, from: jsonData)
                    print("✅ Successfully decoded \(tables?.count ?? 0) table(s)")
                } else {
                    tables = nil
                    print("⚠️ Tables data is not a valid JSON array")
                }
            } else {
                tables = nil
                print("ℹ️ No tables field found")
            }
        } catch {
            print("⚠️ Failed to decode tables: \(error.localizedDescription)")
            tables = nil
        }

        // Decode todo lists array
        do {
            if container.contains(.todo_lists) {
                let rawValue = try container.decode(AnyCodable.self, forKey: .todo_lists)

                // Check if value is null or empty
                if rawValue.value is NSNull {
                    todo_lists = nil
                    print("ℹ️ Todo lists field is null")
                } else if let arrayValue = rawValue.value as? [Any], arrayValue.isEmpty {
                    todo_lists = []
                    print("ℹ️ Todo lists field is empty array")
                } else if let arrayValue = rawValue.value as? [Any], JSONSerialization.isValidJSONObject(arrayValue) {
                    // Convert to JSON data and re-decode with proper date strategy
                    let jsonData = try JSONSerialization.data(withJSONObject: arrayValue)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let container = try decoder.singleValueContainer()
                        let timeInterval = try container.decode(Double.self)
                        return Date(timeIntervalSinceReferenceDate: timeInterval)
                    }
                    todo_lists = try decoder.decode([NoteTodoList].self, from: jsonData)
                    print("✅ Successfully decoded \(todo_lists?.count ?? 0) todo list(s)")
                } else {
                    todo_lists = nil
                    print("⚠️ Todo lists data is not a valid JSON array")
                }
            } else {
                todo_lists = nil
                print("ℹ️ No todo_lists field found")
            }
        } catch {
            print("⚠️ Failed to decode todo lists: \(error.localizedDescription)")
            todo_lists = nil
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