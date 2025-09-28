import Foundation
import UIKit

struct GmailURLHelper {

    // MARK: - Gmail App URL Schemes
    private static let gmailAppScheme = "googlegmail://"
    private static let gmailComposeScheme = "googlegmail:///co"

    // MARK: - Gmail Web URLs
    private static let gmailWebBaseURL = "https://mail.google.com/mail/u/0/#all/"

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

    /// Attempts to open an email in Gmail app, with fallback to web
    /// - Parameters:
    ///   - email: The email object containing Gmail IDs
    ///   - completion: Completion handler called with success/failure result
    static func openEmailInGmail(_ email: Email, completion: @escaping (Result<Void, GmailOpenError>) -> Void) {
        // Check if we have Gmail IDs
        guard let threadId = email.gmailThreadId ?? email.gmailMessageId else {
            completion(.failure(.noGmailId))
            return
        }

        // Try Gmail app first if installed
        if isGmailAppInstalled() {
            if let appURL = createGmailAppURL(threadId: threadId) {
                UIApplication.shared.open(appURL) { success in
                    if success {
                        completion(.success(()))
                    } else {
                        // Fallback to web if app URL fails
                        openInGmailWeb(threadId: threadId, completion: completion)
                    }
                }
                return
            }
        }

        // Fallback to Gmail web
        openInGmailWeb(threadId: threadId, completion: completion)
    }

    // MARK: - Private Methods

    /// Creates a Gmail app URL for a specific thread (experimental)
    /// Note: This may not work reliably due to Gmail app limitations
    private static func createGmailAppURL(threadId: String) -> URL? {
        // Convert hex thread ID to decimal format if needed
        let decimalThreadId = convertToDecimalIfNeeded(threadId)
        let urlString = "googlegmail:///cv=\(decimalThreadId)/accountId=0&create-new-tab"
        return URL(string: urlString)
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