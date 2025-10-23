import Foundation

/// Helper methods to encrypt/decrypt notes before storing in Supabase
/// Usage:
///   1. When saving a note: `let encryptedNote = try await note.encrypted()`
///   2. When loading notes: `let decryptedNote = try await encryptedNote.decrypted()`
extension NotesManager {

    // MARK: - Encrypt Note Before Saving

    /// Encrypt sensitive note fields before saving to Supabase
    /// Encrypted fields: title, content
    /// This ensures only the authenticated user can read their notes
    func encryptNoteBeforeSaving(_ note: Note) async throws -> Note {
        var encryptedNote = note

        // Encrypt title and content
        encryptedNote.title = try EncryptionManager.shared.encrypt(note.title)
        encryptedNote.content = try EncryptionManager.shared.encrypt(note.content)

        print("✅ Encrypted note: \(note.id.uuidString)")

        return encryptedNote
    }

    // MARK: - Decrypt Note After Loading

    /// Decrypt sensitive note fields after fetching from Supabase
    /// This is automatically called when loading notes
    func decryptNoteAfterLoading(_ encryptedNote: Note) async throws -> Note {
        var decryptedNote = encryptedNote

        do {
            // Try to decrypt title and content
            // If decryption fails, it means the data wasn't encrypted (old data)
            // So we return it as-is for backward compatibility

            decryptedNote.title = try EncryptionManager.shared.decrypt(encryptedNote.title)
            decryptedNote.content = try EncryptionManager.shared.decrypt(encryptedNote.content)

            print("✅ Decrypted note: \(encryptedNote.id.uuidString)")
        } catch {
            // Decryption failed - this note is probably not encrypted (old data)
            // Return the note as-is (backward compatible)
            print("⚠️ Could not decrypt note \(encryptedNote.id.uuidString): \(error.localizedDescription)")
            print("   Note will be returned unencrypted (legacy data)")
            // Return the original note - it's already decrypted
            return encryptedNote
        }

        return decryptedNote
    }

    // MARK: - Batch Operations

    /// Encrypt multiple notes before batch saving
    func encryptNotes(_ notes: [Note]) async throws -> [Note] {
        var encryptedNotes: [Note] = []
        for note in notes {
            let encrypted = try await encryptNoteBeforeSaving(note)
            encryptedNotes.append(encrypted)
        }
        return encryptedNotes
    }

    /// Decrypt multiple notes after batch loading
    func decryptNotes(_ notes: [Note]) async throws -> [Note] {
        var decryptedNotes: [Note] = []
        for note in notes {
            let decrypted = try await decryptNoteAfterLoading(note)
            decryptedNotes.append(decrypted)
        }
        return decryptedNotes
    }
}

// MARK: - Integration Points (Where to Use These)

/// Here's how to integrate encryption with the existing NotesManager:
///
/// 1. IN `saveNoteToSupabase()` - Before storing:
/// ```swift
/// let encryptedNote = try await encryptNoteBeforeSaving(note)
/// // Then save encryptedNote to Supabase instead of the original note
/// let noteData: [String: PostgREST.AnyJSON] = [
///     "title": .string(encryptedNote.title),  // ← Now encrypted
///     "content": .string(encryptedNote.content),  // ← Now encrypted
///     ...
/// ]
/// ```
///
/// 2. IN `parseNoteFromSupabase()` - After fetching:
/// ```swift
/// var note = Note(...)
/// // ... set other fields ...
/// note.title = data.title  // ← Still encrypted
/// note.content = data.content  // ← Still encrypted
///
/// // Decrypt before returning to UI
/// let decryptedNote = try await decryptNoteAfterLoading(note)
/// return decryptedNote
/// ```
///
/// 3. IN `updateNoteInSupabase()` - Before updating:
/// ```swift
/// let encryptedNote = try await encryptNoteBeforeSaving(note)
/// let noteData: [String: PostgREST.AnyJSON] = [
///     "title": .string(encryptedNote.title),  // ← Now encrypted
///     "content": .string(encryptedNote.content),  // ← Now encrypted
///     ...
/// ]
/// ```
