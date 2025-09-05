//
//  TokenEncryption.swift
//  Seline
//
//  Secure token encryption utility for protecting sensitive data before cloud storage
//

import Foundation
import CryptoKit

class TokenEncryption {
    static let shared = TokenEncryption()
    
    private init() {}
    
    /// Encrypt sensitive token data before storing in Supabase
    func encryptToken(_ token: String, using key: SymmetricKey) throws -> String {
        guard let tokenData = token.data(using: .utf8) else {
            throw TokenEncryptionError.invalidTokenData
        }
        
        let sealedBox = try AES.GCM.seal(tokenData, using: key)
        let encryptedData = sealedBox.combined
        return encryptedData?.base64EncodedString() ?? ""
    }
    
    /// Decrypt token data retrieved from Supabase
    func decryptToken(_ encryptedToken: String, using key: SymmetricKey) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedToken) else {
            throw TokenEncryptionError.invalidEncryptedData
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let decryptedToken = String(data: decryptedData, encoding: .utf8) else {
            throw TokenEncryptionError.decryptionFailed
        }
        
        return decryptedToken
    }
    
    /// Generate encryption key from user-specific data
    func generateUserEncryptionKey(userId: String, email: String) -> SymmetricKey {
        let keyMaterial = "\(userId):\(email):seline_token_encryption"
        let keyData = SHA256.hash(data: keyMaterial.data(using: .utf8) ?? Data())
        return SymmetricKey(data: keyData)
    }
    
    /// Encrypt user tokens with user-specific key
    func encryptUserTokens(accessToken: String?, refreshToken: String?, userId: String, email: String) throws -> (String?, String?) {
        let userKey = generateUserEncryptionKey(userId: userId, email: email)
        
        let encryptedAccessToken = try accessToken.map { try encryptToken($0, using: userKey) }
        let encryptedRefreshToken = try refreshToken.map { try encryptToken($0, using: userKey) }
        
        return (encryptedAccessToken, encryptedRefreshToken)
    }
    
    /// Decrypt user tokens with user-specific key
    func decryptUserTokens(encryptedAccessToken: String?, encryptedRefreshToken: String?, userId: String, email: String) throws -> (String?, String?) {
        let userKey = generateUserEncryptionKey(userId: userId, email: email)
        
        let accessToken = try encryptedAccessToken.map { try decryptToken($0, using: userKey) }
        let refreshToken = try encryptedRefreshToken.map { try decryptToken($0, using: userKey) }
        
        return (accessToken, refreshToken)
    }
}

enum TokenEncryptionError: Error, LocalizedError {
    case invalidTokenData
    case invalidEncryptedData
    case decryptionFailed
    case keyGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            return "Invalid token data for encryption"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .decryptionFailed:
            return "Failed to decrypt token data"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        }
    }
}