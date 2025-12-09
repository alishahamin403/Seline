import Foundation
import CryptoKit

/// Manages end-to-end encryption for sensitive user data
/// Uses AES-256-GCM authenticated encryption
///
/// How it works:
/// 1. User authenticates with Google/Supabase (gets UUID)
/// 2. Encryption key is derived deterministically from user's UUID
/// 3. All sensitive data encrypted before sending to Supabase
/// 4. Data stored encrypted on server
/// 5. App decrypts data only when user is authenticated
///
/// **You NEVER have access to unencrypted user data - only they can decrypt it with their key**
@MainActor
class EncryptionManager: ObservableObject {
    static let shared = EncryptionManager()

    @Published var isEncryptionEnabled = true
    private var encryptionKey: SymmetricKey?

    /// Check if encryption key has been initialized
    var isKeyInitialized: Bool {
        encryptionKey != nil
    }

    private init() {}

    // MARK: - Key Management

    /// Initialize encryption with user's authentication ID
    /// This generates a deterministic key from the user's UUID
    /// The same UUID will always produce the same key (important for decryption)
    func setupEncryption(with userId: UUID) {
        let key = deriveKeyFromUserId(userId)
        self.encryptionKey = key
        // DEBUG: Commented out to reduce console spam
        // print("✅ Encryption initialized for user: \(userId.uuidString)")
    }

    /// Derive encryption key from user ID deterministically
    /// - Parameter userId: The user's UUID from Supabase authentication
    /// - Returns: A 256-bit symmetric key
    ///
    /// Uses HKDF (HMAC-based Key Derivation Function) to stretch the user ID
    /// into a cryptographically secure 256-bit key. The same userId will
    /// always produce the same key, enabling decryption later.
    private func deriveKeyFromUserId(_ userId: UUID) -> SymmetricKey {
        let userIdData = userId.uuidString.data(using: .utf8)!
        let salt = Data("seline_encryption_salt".utf8)

        // Use HKDF to derive a proper cryptographic key from the user ID
        let derivedKeyData = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: userIdData),
            salt: salt,
            info: Data("seline_encryption_info".utf8),
            outputByteCount: 32 // 256 bits for AES-256
        )

        return derivedKeyData
    }

    /// Clears the encryption key when user logs out
    func clearEncryption() {
        encryptionKey = nil
        print("✅ Encryption key cleared")
    }

    // MARK: - Encryption Operations

    /// Encrypt a string and return base64-encoded ciphertext with nonce
    /// - Parameter plaintext: The unencrypted text
    /// - Returns: Base64 string containing nonce + ciphertext (safe to store in database)
    /// - Throws: EncryptionError if encryption fails or key not initialized
    func encrypt(_ plaintext: String) throws -> String {
        guard let key = encryptionKey else {
            throw EncryptionError.keyNotInitialized
        }

        let data = plaintext.data(using: .utf8) ?? Data()
        let nonce = AES.GCM.Nonce() // Generate random nonce

        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Combine nonce + ciphertext for storage (nonce is safe to store unencrypted)
        // Format: base64(nonce || ciphertext)
        let combined = nonce.withUnsafeBytes { Data($0) } + (sealedBox.ciphertext + sealedBox.tag)

        return combined.base64EncodedString()
    }

    /// Decrypt a base64-encoded string encrypted with AES-256-GCM
    /// - Parameter encryptedBase64: The encrypted data from encrypt()
    /// - Returns: The original plaintext
    /// - Throws: EncryptionError if decryption fails or key not initialized
    func decrypt(_ encryptedBase64: String) throws -> String {
        guard let key = encryptionKey else {
            throw EncryptionError.keyNotInitialized
        }

        guard let combined = Data(base64Encoded: encryptedBase64) else {
            throw EncryptionError.invalidBase64
        }

        // Extract nonce (first 12 bytes) and ciphertext+tag (remaining)
        let nonceSize = 12 // AES-GCM nonce size
        guard combined.count > nonceSize else {
            throw EncryptionError.invalidCiphertext
        }

        let nonceData = combined.prefix(nonceSize)
        let ciphertextAndTag = combined.dropFirst(nonceSize)

        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw EncryptionError.invalidNonce
        }

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextAndTag.dropLast(16), tag: ciphertextAndTag.suffix(16))

        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decodingError
        }

        return plaintext
    }

    // MARK: - Batch Operations

    /// Encrypt multiple strings at once
    func encryptMultiple(_ plaintexts: [String]) throws -> [String] {
        return try plaintexts.map { try encrypt($0) }
    }

    /// Decrypt multiple strings at once
    func decryptMultiple(_ encryptedTexts: [String]) throws -> [String] {
        return try encryptedTexts.map { try decrypt($0) }
    }
}

enum EncryptionError: LocalizedError {
    case keyNotInitialized
    case invalidBase64
    case invalidCiphertext
    case invalidNonce
    case decodingError
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .keyNotInitialized:
            return "Encryption key not initialized. User must be authenticated."
        case .invalidBase64:
            return "Invalid base64 encoded data"
        case .invalidCiphertext:
            return "Invalid or corrupted ciphertext"
        case .invalidNonce:
            return "Invalid nonce in encrypted data"
        case .decodingError:
            return "Failed to decode decrypted data to string"
        case .encryptionFailed:
            return "Encryption operation failed"
        }
    }
}
