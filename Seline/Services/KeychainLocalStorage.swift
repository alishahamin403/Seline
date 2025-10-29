import Foundation
import Auth
import Security

/// Keychain-based local storage implementation for Auth sessions
/// This provides secure, persistent storage for authentication tokens
class KeychainLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let service: String
    private let keychainQueue = DispatchQueue(label: "com.seline.keychain", attributes: .concurrent)

    init(service: String = "com.seline.auth") {
        self.service = service
    }

    func store(key: String, value: Data) throws {
        try keychainQueue.sync(flags: .barrier) {
            // Delete any existing item first
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            // Add the new item
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemAdd(addQuery as CFDictionary, nil)

            if status != errSecSuccess {
                throw KeychainError.unableToStore(status)
            }
        }
    }

    func retrieve(key: String) throws -> Data? {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecSuccess {
                if let data = result as? Data {
                    return data
                }
            } else if status == errSecItemNotFound {
                return nil
            } else {
                throw KeychainError.unableToRetrieve(status)
            }

            return nil
        }
    }

    func remove(key: String) throws {
        try keychainQueue.sync(flags: .barrier) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            let status = SecItemDelete(query as CFDictionary)

            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeychainError.unableToDelete(status)
            }
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case unableToStore(OSStatus)
    case unableToRetrieve(OSStatus)
    case unableToDelete(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Unable to store item in keychain (status: \(status))"
        case .unableToRetrieve(let status):
            return "Unable to retrieve item from keychain (status: \(status))"
        case .unableToDelete(let status):
            return "Unable to delete item from keychain (status: \(status))"
        }
    }
}
