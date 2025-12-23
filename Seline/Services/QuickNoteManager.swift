import Foundation
import PostgREST

@MainActor
class QuickNoteManager: ObservableObject {
    static let shared = QuickNoteManager()

    @Published var quickNotes: [QuickNote] = []

    private init() {}

    // MARK: - Fetch Quick Notes

    func fetchQuickNotes() async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ QuickNotes: No user session found")
            return
        }

        print("📥 QuickNotes: Fetching for user: \(userId.uuidString)")

        let client = await SupabaseManager.shared.getPostgrestClient()

        let response = try await client
            .from("quick_notes")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date_modified", ascending: false)
            .execute()

        let data = response.data
        print("📥 QuickNotes: Received data: \(String(data: data, encoding: .utf8) ?? "nil")")

        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase - we have explicit CodingKeys in the DTO

        // Use ISO8601 date decoding
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try with fractional seconds first
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }

        do {
            let dtos = try decoder.decode([QuickNoteDTO].self, from: data)
            print("✅ QuickNotes: Successfully decoded \(dtos.count) notes")

            let notes = dtos.map { dto in
                QuickNote(
                    id: dto.id,
                    content: dto.content,
                    dateCreated: dto.dateCreated,
                    dateModified: dto.dateModified,
                    userId: dto.userId
                )
            }

            await MainActor.run {
                self.quickNotes = notes
                print("✅ QuickNotes: Updated quickNotes array with \(notes.count) notes")
            }
        } catch {
            print("❌ QuickNotes: Decoding error: \(error)")
            throw error
        }
    }

    // MARK: - Create Quick Note

    /// Optimistic quick note creation: update UI immediately, then sync to Supabase in background.
    func createQuickNote(content: String) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "QuickNoteManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user session"])
        }

        let newNote = QuickNote(content: content, userId: userId)

        // 1. Update local state immediately so UI reflects the new note without waiting for network
        quickNotes.insert(newNote, at: 0)

        // 2. Fire-and-forget Supabase sync on a background task
        Task.detached(priority: .background) {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let formatter = ISO8601DateFormatter()
            let noteData: [String: AnyJSON] = [
                "id": .string(newNote.id.uuidString),
                "user_id": .string(userId.uuidString),
                "content": .string(newNote.content),
                "date_created": .string(formatter.string(from: newNote.dateCreated)),
                "date_modified": .string(formatter.string(from: newNote.dateModified))
            ]

            do {
                try await client
                    .from("quick_notes")
                    .insert(noteData)
                    .execute()
            } catch {
                // TODO: Optionally mark this note as "unsynced" and retry later
                print("❌ QuickNotes: Failed to sync new note: \(error)")
            }
        }
    }

    // MARK: - Update Quick Note

    func updateQuickNote(_ note: QuickNote, content: String) async throws {
        var updatedNote = note
        updatedNote.content = content
        updatedNote.dateModified = Date()

        let client = await SupabaseManager.shared.getPostgrestClient()
        let formatter = ISO8601DateFormatter()

        let updateData: [String: AnyJSON] = [
            "content": .string(content),
            "date_modified": .string(formatter.string(from: updatedNote.dateModified))
        ]

        try await client
            .from("quick_notes")
            .update(updateData)
            .eq("id", value: note.id.uuidString)
            .execute()

        await MainActor.run {
            if let index = self.quickNotes.firstIndex(where: { $0.id == note.id }) {
                self.quickNotes[index] = updatedNote
            }
        }
    }

    // MARK: - Delete Quick Note

    func deleteQuickNote(_ note: QuickNote) async throws {
        let client = await SupabaseManager.shared.getPostgrestClient()

        try await client
            .from("quick_notes")
            .delete()
            .eq("id", value: note.id.uuidString)
            .execute()

        await MainActor.run {
            self.quickNotes.removeAll { $0.id == note.id }
        }
    }
}

// MARK: - DTOs

private struct QuickNoteDTO: Codable {
    let id: UUID
    let content: String
    let dateCreated: Date
    let dateModified: Date
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case dateCreated = "date_created"
        case dateModified = "date_modified"
        case userId = "user_id"
    }
}

// MARK: - QuickNote Extension

extension QuickNote {
    init(id: UUID, content: String, dateCreated: Date, dateModified: Date, userId: UUID) {
        self.id = id
        self.content = content
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.userId = userId
    }
}
