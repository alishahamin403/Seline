import Foundation
import UIKit

struct GmailURLHelper {

    // MARK: - Gmail App URL Schemes
    private static let gmailAppScheme = "googlegmail://"
    private static let gmailComposeScheme = "googlegmail:///co"

    // MARK: - Gmail Web URLs
    private static let gmailWebBaseURL = "https://mail.google.com/mail/u/0/#inbox/"

    // MARK: - Public Methods

    /// Checks if Gmail app is installed on the device
    static func isGmailAppInstalled() -> Bool {
        guard let gmailURL = URL(string: gmailAppScheme) else { return false }
        return UIApplication.shared.canOpenURL(gmailURL)
    }

    /// Generates a Gmail web URL for a specific email using thread ID
    /// - Parameter threadId: The Gmail thread ID
    /// - Returns: URL to open the email in Gmail web interface
    static func createGmailWebURL(threadId: String) -> URL? {
        let urlString = gmailWebBaseURL + threadId
        return URL(string: urlString)
    }

    /// Generates a Gmail web URL for a specific email using message ID
    /// - Parameter messageId: The Gmail message ID
    /// - Returns: URL to open the email in Gmail web interface
    static func createGmailWebURL(messageId: String) -> URL? {
        let urlString = gmailWebBaseURL + messageId
        return URL(string: urlString)
    }

    /// Attempts to open specific email in Gmail app, with fallback to web
    /// - Parameters:
    ///   - email: The email object containing Gmail IDs
    ///   - completion: Completion handler called with success/failure result
    static func openEmailInGmail(_ email: Email, completion: @escaping (Result<Void, GmailOpenError>) -> Void) {
        // Always open Gmail web with specific email if we have Gmail IDs
        // This avoids the sandbox extension issues with complex Gmail app URL schemes
        if let threadId = email.gmailThreadId ?? email.gmailMessageId {
            openInGmailWeb(threadId: threadId, completion: completion)
        } else if isGmailAppInstalled() {
            // Only use basic Gmail app opening if no Gmail IDs available
            openGmailApp(completion: completion)
        } else {
            // No Gmail app and no IDs, open general Gmail web
            openGeneralGmailWeb(completion: completion)
        }
    }

    /// Opens Gmail app to main inbox
    static func openGmailApp(completion: @escaping (Result<Void, GmailOpenError>) -> Void) {
        guard let gmailURL = URL(string: gmailAppScheme) else {
            completion(.failure(.invalidURL))
            return
        }

        UIApplication.shared.open(gmailURL) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(.failedToOpen))
            }
        }
    }

    // MARK: - Private Methods

    /// Opens general Gmail web interface
    private static func openGeneralGmailWeb(completion: @escaping (Result<Void, GmailOpenError>) -> Void) {
        guard let webURL = URL(string: "https://mail.google.com/mail/u/0/#inbox") else {
            completion(.failure(.invalidURL))
            return
        }

        UIApplication.shared.open(webURL) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(.failedToOpen))
            }
        }
    }

    /// Opens email in Gmail web interface
    private static func openInGmailWeb(threadId: String, completion: @escaping (Result<Void, GmailOpenError>) -> Void) {
        guard let webURL = createGmailWebURL(threadId: threadId) else {
            completion(.failure(.invalidURL))
            return
        }

        UIApplication.shared.open(webURL) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(.failedToOpen))
            }
        }
    }

    /// Converts hex thread ID to decimal if it's in hex format
    private static func convertToDecimalIfNeeded(_ threadId: String) -> String {
        // Check if the string is hex (contains only hex characters)
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if threadId.rangeOfCharacter(from: hexCharacterSet.inverted) == nil {
            // Try to convert from hex to decimal
            if let hexValue = UInt64(threadId, radix: 16) {
                return String(hexValue)
            }
        }
        // Return as-is if not hex or conversion fails
        return threadId
    }
}

// MARK: - Error Types

enum GmailOpenError: Error, LocalizedError {
    case noGmailId
    case invalidURL
    case failedToOpen

    var errorDescription: String? {
        switch self {
        case .noGmailId:
            return "Gmail ID not available for this email"
        case .invalidURL:
            return "Invalid Gmail URL"
        case .failedToOpen:
            return "Failed to open Gmail"
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .noGmailId:
            return "This email doesn't have Gmail information available"
        case .invalidURL, .failedToOpen:
            return "Unable to open Gmail. Please try again."
        }
    }
}