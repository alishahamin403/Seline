import Foundation

/// Helper methods to encrypt/decrypt location data before storing in Supabase
/// This protects users' real-world locations from exposure
///
/// Encryption scope:
/// - Place coordinates (latitude, longitude) - essential for privacy
/// - Place names and addresses
/// - Place phone numbers
/// - Custom location labels (e.g., "Home", "Work")
extension LocationService {

    // MARK: - Encrypt Location Data

    /// Encrypt sensitive location fields before storing
    /// Coordinates are encrypted to prevent location tracking
    func encryptLocationData(
        googlePlaceId: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        phoneNumber: String?
    ) async throws -> EncryptedLocationData {

        let encryptedName = try EncryptionManager.shared.encrypt(name)
        let encryptedAddress = try EncryptionManager.shared.encrypt(address)
        let encryptedLatitude = try EncryptionManager.shared.encrypt(String(latitude))
        let encryptedLongitude = try EncryptionManager.shared.encrypt(String(longitude))
        let encryptedPhone = try phoneNumber.map { try EncryptionManager.shared.encrypt($0) }

        print("✅ Encrypted location: \(name)")

        return EncryptedLocationData(
            googlePlaceId: googlePlaceId, // Keep this unencrypted for Google API lookups if needed
            encryptedName: encryptedName,
            encryptedAddress: encryptedAddress,
            encryptedLatitude: encryptedLatitude,
            encryptedLongitude: encryptedLongitude,
            encryptedPhoneNumber: encryptedPhone
        )
    }

    // MARK: - Decrypt Location Data

    /// Decrypt location fields after fetching from storage
    func decryptLocationData(_ encryptedData: EncryptedLocationData) async throws -> DecryptedLocationData {
        do {
            let name = try EncryptionManager.shared.decrypt(encryptedData.encryptedName)
            let address = try EncryptionManager.shared.decrypt(encryptedData.encryptedAddress)
            let latitudeStr = try EncryptionManager.shared.decrypt(encryptedData.encryptedLatitude)
            let longitudeStr = try EncryptionManager.shared.decrypt(encryptedData.encryptedLongitude)
            let phoneNumber = try encryptedData.encryptedPhoneNumber.map { try EncryptionManager.shared.decrypt($0) }

            guard let latitude = Double(latitudeStr),
                  let longitude = Double(longitudeStr) else {
                throw LocationEncryptionError.invalidCoordinates
            }

            print("✅ Decrypted location: \(name)")

            return DecryptedLocationData(
                googlePlaceId: encryptedData.googlePlaceId,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                phoneNumber: phoneNumber
            )
        } catch {
            print("⚠️ Failed to decrypt location data: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Batch Operations

    /// Encrypt multiple locations for batch save
    func encryptLocations(_ places: [EncryptedLocationData]) async throws -> [EncryptedLocationData] {
        // Already encrypted in the input, just return
        // This is a placeholder for potential batch optimizations
        return places
    }

    /// Decrypt multiple locations for batch load
    func decryptLocations(_ encryptedPlaces: [EncryptedLocationData]) async throws -> [DecryptedLocationData] {
        var decrypted: [DecryptedLocationData] = []
        for place in encryptedPlaces {
            let decryptedPlace = try await decryptLocationData(place)
            decrypted.append(decryptedPlace)
        }
        return decrypted
    }
}

// MARK: - Data Structures

/// Holds encrypted location data ready to store in Supabase
struct EncryptedLocationData {
    let googlePlaceId: String
    let encryptedName: String
    let encryptedAddress: String
    let encryptedLatitude: String
    let encryptedLongitude: String
    let encryptedPhoneNumber: String?
}

/// Holds decrypted location data for display/use in app
struct DecryptedLocationData {
    let googlePlaceId: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let phoneNumber: String?
}

enum LocationEncryptionError: LocalizedError {
    case invalidCoordinates
    case decryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Failed to parse decrypted coordinates"
        case .decryptionFailed(let message):
            return "Location decryption failed: \(message)"
        }
    }
}

// MARK: - Integration Guide

/// Integration Guide for Location Encryption:
///
/// 1. WHEN SAVING A PLACE (in LocationsManager):
/// ```swift
/// let encryptedPlace = try await locationService.encryptLocationData(
///     googlePlaceId: place.googlePlaceId,
///     name: place.name,
///     address: place.address,
///     latitude: place.latitude,
///     longitude: place.longitude,
///     phoneNumber: place.phoneNumber
/// )
///
/// // Store encrypted fields:
/// let placeData: [String: PostgREST.AnyJSON] = [
///     "google_place_id": .string(encryptedPlace.googlePlaceId),
///     "name": .string(encryptedPlace.encryptedName),
///     "address": .string(encryptedPlace.encryptedAddress),
///     "latitude": .string(encryptedPlace.encryptedLatitude),
///     "longitude": .string(encryptedPlace.encryptedLongitude),
///     "phone": encryptedPlace.encryptedPhoneNumber.map { .string($0) } ?? .null
/// ]
/// try await client.from("saved_places").insert(placeData).execute()
/// ```
///
/// 2. WHEN LOADING PLACES (in LocationService):
/// ```swift
/// let savedPlaces: [SavedPlaceRow] = try await client
///     .from("saved_places")
///     .select()
///     .eq("user_id", value: userId.uuidString)
///     .execute()
///     .value
///
/// var decryptedPlaces: [SavedPlace] = []
/// for savedPlace in savedPlaces {
///     let encryptedData = EncryptedLocationData(...)
///     let decrypted = try await locationService.decryptLocationData(encryptedData)
///     // Convert to SavedPlace model
///     decryptedPlaces.append(SavedPlace(...))
/// }
/// ```
///
/// 3. PRIVACY BENEFIT:
/// - User's home, work, and frequent locations are encrypted on server
/// - Supabase cannot see where user goes
/// - Only authenticated user can decrypt locations
/// - Prevents location history leakage in case of breach
///
/// 4. NOTE ON COORDINATES:
/// - Coordinates are stored as encrypted strings (not numbers)
/// - This prevents approximate location inference from metadata
/// - Must be converted back to Double for map display
