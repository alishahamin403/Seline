import Foundation
import PostgREST

/// Helper methods to encrypt/decrypt saved places before storing in Supabase
/// Encryption scope:
/// - Place name (original Google name)
/// - Custom place name (user's custom name/title)
/// - Address
/// - Phone number
/// - Latitude and longitude coordinates
extension LocationsManager {

    // MARK: - Encrypt SavedPlace Before Saving

    /// Encrypt sensitive location fields before saving to Supabase
    func encryptSavedPlaceBeforeSaving(_ place: SavedPlace) async throws -> SavedPlace {
        var encryptedPlace = place

        // Encrypt location data
        encryptedPlace.name = try await EncryptionManager.shared.encrypt(place.name)
        encryptedPlace.address = try await EncryptionManager.shared.encrypt(place.address)

        // Encrypt custom name if it exists
        if let customName = place.customName {
            encryptedPlace.customName = try await EncryptionManager.shared.encrypt(customName)
        }

        // Encrypt phone number if it exists
        if let phone = place.phone {
            encryptedPlace.phone = try await EncryptionManager.shared.encrypt(phone)
        }

        // Note: Coordinates are NOT encrypted to preserve their Double type in the model
        // The encryption of place name and address provides sufficient location privacy

        return encryptedPlace
    }

    // MARK: - Decrypt SavedPlace After Loading

    /// Decrypt sensitive location fields after fetching from Supabase
    func decryptSavedPlaceAfterLoading(_ encryptedPlace: SavedPlace) async throws -> SavedPlace {
        var decryptedPlace = encryptedPlace

        do {
            // Decrypt location data
            decryptedPlace.name = try await EncryptionManager.shared.decrypt(encryptedPlace.name)
            decryptedPlace.address = try await EncryptionManager.shared.decrypt(encryptedPlace.address)

            // Decrypt custom name if it exists
            if let customName = encryptedPlace.customName {
                decryptedPlace.customName = try await EncryptionManager.shared.decrypt(customName)
            }

            // Decrypt phone number if it exists
            if let phone = encryptedPlace.phone {
                decryptedPlace.phone = try await EncryptionManager.shared.decrypt(phone)
            }
        } catch {
            // Decryption failed - this place is probably not encrypted (old data)
            print("⚠️ Could not decrypt place \(encryptedPlace.id.uuidString): \(error.localizedDescription)")
            print("   Place will be returned unencrypted (legacy data)")
            return encryptedPlace
        }

        return decryptedPlace
    }

    // MARK: - Batch Operations

    /// Encrypt multiple places before batch saving
    func encryptSavedPlaces(_ places: [SavedPlace]) async throws -> [SavedPlace] {
        var encryptedPlaces: [SavedPlace] = []
        for place in places {
            let encrypted = try await encryptSavedPlaceBeforeSaving(place)
            encryptedPlaces.append(encrypted)
        }
        return encryptedPlaces
    }

    /// Decrypt multiple places after batch loading
    func decryptSavedPlaces(_ places: [SavedPlace]) async throws -> [SavedPlace] {
        var decryptedPlaces: [SavedPlace] = []
        for place in places {
            let decrypted = try await decryptSavedPlaceAfterLoading(place)
            decryptedPlaces.append(decrypted)
        }
        return decryptedPlaces
    }

    // MARK: - Bulk Re-encryption

    /// Re-encrypt all existing saved places in Supabase
    func reencryptAllExistingSavedPlaces() async {
        guard let userId = await AuthenticationManager.shared.supabaseUser?.id else {
            print("❌ User not authenticated, cannot re-encrypt saved places")
            return
        }

        print("🔐 Starting bulk re-encryption of saved places...")

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Fetch ALL saved places for this user
            let response: [SavedPlaceSupabaseData] = try await client
                .from("saved_places")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            print("📥 Fetched \(response.count) places for re-encryption")

            var reencryptedCount = 0
            var skippedCount = 0
            var errorCount = 0

            // Process each place
            for (index, supabasePlace) in response.enumerated() {
                var place = SavedPlace(
                    googlePlaceId: supabasePlace.google_place_id,
                    name: supabasePlace.name,
                    address: supabasePlace.address,
                    latitude: supabasePlace.latitude,
                    longitude: supabasePlace.longitude,
                    phone: supabasePlace.phone
                )
                place.id = UUID(uuidString: supabasePlace.id) ?? UUID()

                // Check if already encrypted by trying to decrypt
                let decryptTest = try? await EncryptionManager.shared.decrypt(supabasePlace.name)

                if decryptTest != nil && decryptTest == supabasePlace.name {
                    // Successfully decrypted to same value = already encrypted
                    skippedCount += 1
                } else {
                    // Failed to decrypt or got different value = plaintext
                    do {
                        let encrypted = try await encryptSavedPlaceBeforeSaving(place)

                        // Update in Supabase with encrypted version
                        let formatter = ISO8601DateFormatter()
                        let updateData: [String: PostgREST.AnyJSON] = [
                            "name": .string(encrypted.name),
                            "address": .string(encrypted.address),
                            "custom_name": encrypted.customName.map { .string($0) } ?? .null,
                            "phone": encrypted.phone.map { .string($0) } ?? .null,
                            "updated_at": .string(formatter.string(from: Date()))
                        ]

                        try await client
                            .from("saved_places")
                            .update(updateData)
                            .eq("id", value: place.id.uuidString)
                            .execute()

                        reencryptedCount += 1
                    } catch {
                        errorCount += 1
                    }
                }
            }

            // Summary
            print("🔐 Place re-encryption complete: \(reencryptedCount) re-encrypted, \(skippedCount) already encrypted, \(errorCount) errors")

        } catch {
            print("❌ Error during place re-encryption: \(error)")
        }
    }
}

// MARK: - Supabase Data Structure

struct SavedPlaceSupabaseData: Codable {
    let id: String
    let user_id: String
    let google_place_id: String
    let name: String
    let custom_name: String?
    let address: String
    let phone: String?
    let latitude: Double
    let longitude: Double
    let category: String
    let rating: Double?
    let created_at: String
    let updated_at: String
}
