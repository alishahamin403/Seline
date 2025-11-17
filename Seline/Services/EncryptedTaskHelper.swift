import Foundation
import PostgREST

/// Helper methods to encrypt/decrypt tasks before storing in Supabase
/// Protects task content from exposure
///
/// Encryption scope:
/// - Task title
/// - Task description
extension TaskManager {

    // MARK: - Encrypt Task Before Saving

    /// Encrypt sensitive task fields before saving to Supabase
    func encryptTaskBeforeSaving(_ task: TaskItem) async throws -> TaskItem {
        var encryptedTask = task

        // Encrypt title and description
        encryptedTask.title = try EncryptionManager.shared.encrypt(task.title)
        if let description = task.description {
            encryptedTask.description = try EncryptionManager.shared.encrypt(description)
        }

        return encryptedTask
    }

    // MARK: - Decrypt Task After Loading

    /// Check if a string looks like encrypted data (valid base64 with minimum length)
    private func isEncrypted(_ text: String) -> Bool {
        // Encrypted data must be:
        // 1. Valid base64
        // 2. At least 28 bytes (12 byte nonce + 16 byte tag + minimum ciphertext)
        guard let data = Data(base64Encoded: text) else {
            return false
        }
        return data.count >= 28
    }

    /// Decrypt sensitive task fields after fetching from Supabase
    func decryptTaskAfterLoading(_ encryptedTask: TaskItem) async throws -> TaskItem {
        var decryptedTask = encryptedTask

        // Only attempt decryption if data looks encrypted
        let titleIsEncrypted = isEncrypted(encryptedTask.title)
        print("🔓 Title encrypted check: \(titleIsEncrypted) (length: \(encryptedTask.title.count))")

        if titleIsEncrypted {
            print("🔓 Attempting to decrypt title...")
            do {
                decryptedTask.title = try EncryptionManager.shared.decrypt(encryptedTask.title)
                print("✅ Title decrypted successfully")
            } catch {
                // Decryption failed - keep original (assume plaintext despite base64 appearance)
                print("⚠️ Decryption failed for title, keeping as plaintext: \(error)")
                decryptedTask.title = encryptedTask.title
            }
        } else {
            print("ℹ️ Title not encrypted (plaintext)")
        }

        if let description = encryptedTask.description {
            let descIsEncrypted = isEncrypted(description)
            print("🔓 Description encrypted check: \(descIsEncrypted)")

            if descIsEncrypted {
                print("🔓 Attempting to decrypt description...")
                do {
                    decryptedTask.description = try EncryptionManager.shared.decrypt(description)
                    print("✅ Description decrypted successfully")
                } catch {
                    // Decryption failed - keep original (assume plaintext despite base64 appearance)
                    print("⚠️ Decryption failed for description, keeping as plaintext: \(error)")
                    decryptedTask.description = description
                }
            }
        }

        return decryptedTask
    }

    // MARK: - Batch Operations

    /// Encrypt multiple tasks before batch saving
    func encryptTasks(_ tasks: [TaskItem]) async throws -> [TaskItem] {
        var encryptedTasks: [TaskItem] = []
        for task in tasks {
            let encrypted = try await encryptTaskBeforeSaving(task)
            encryptedTasks.append(encrypted)
        }
        return encryptedTasks
    }

    /// Decrypt multiple tasks after batch loading
    func decryptTasks(_ tasks: [TaskItem]) async throws -> [TaskItem] {
        var decryptedTasks: [TaskItem] = []
        for task in tasks {
            let decrypted = try await decryptTaskAfterLoading(task)
            decryptedTasks.append(decrypted)
        }
        return decryptedTasks
    }

    // MARK: - Bulk Re-encryption

    /// Re-encrypt all existing tasks in Supabase
    func reencryptAllExistingTasks() async {
        guard let userId = AuthenticationManager.shared.supabaseUser?.id else {
            print("❌ User not authenticated, cannot re-encrypt tasks")
            return
        }

        print("🔐 Starting bulk re-encryption of existing tasks...")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch ALL tasks for this user
            let response: [TaskItemSupabaseData] = try await client
                .from("tasks")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Fetched \(response.count) tasks for re-encryption")

            var reencryptedCount = 0
            var skippedCount = 0
            var errorCount = 0

            // Process each task
            for (index, supabaseTask) in response.enumerated() {
                var task = TaskItem(
                    title: supabaseTask.title,
                    weekday: .monday,  // Default, actual value not used for encryption
                    description: supabaseTask.description
                )

                // Update ID to match Supabase record
                task.id = supabaseTask.id

                // Check if already encrypted by trying to decrypt
                let decryptTest = try? EncryptionManager.shared.decrypt(supabaseTask.title)

                if decryptTest != nil && decryptTest == supabaseTask.title {
                    // Successfully decrypted to same value = already encrypted
                    skippedCount += 1
                } else {
                    // Failed to decrypt or got different value = plaintext
                    do {
                        let encrypted = try await encryptTaskBeforeSaving(task)

                        // Update in Supabase with encrypted version
                        let formatter = ISO8601DateFormatter()
                        let updateData: [String: PostgREST.AnyJSON] = [
                            "title": .string(encrypted.title),
                            "description": encrypted.description.map { .string($0) } ?? .null,
                            "updated_at": .string(formatter.string(from: Date()))
                        ]

                        try await client
                            .from("tasks")
                            .update(updateData)
                            .eq("id", value: task.id)
                            .execute()

                        reencryptedCount += 1
                    } catch {
                        errorCount += 1
                    }
                }
            }

            // Summary
            print("🔐 Task re-encryption complete: \(reencryptedCount) re-encrypted, \(skippedCount) already encrypted, \(errorCount) errors")

        } catch {
            print("❌ Error during task re-encryption: \(error)")
        }
    }
}

// MARK: - Supabase Data Structure

struct TaskItemSupabaseData: Codable {
    let id: String
    let user_id: String
    let title: String
    let description: String?
    let due_date: String?
    let is_completed: Bool
    let priority: String?
    let created_at: String
    let updated_at: String
}
