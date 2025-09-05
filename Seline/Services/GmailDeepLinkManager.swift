//
//  GmailDeepLinkManager.swift
//  Seline
//
//  Handles deep-linking to Gmail app or web interface
//

import Foundation
import UIKit

@MainActor
class GmailDeepLinkManager {
    static let shared = GmailDeepLinkManager()
    
    private init() {}
    
    /// Open email in Gmail app or web interface
    func openEmailInGmail(_ email: Email) {
        // It is not possible to deep link to a specific email in the native Gmail app on iOS.
        // The functionality has been disabled by Google.
        
        // The best we can do is open the Gmail app to the inbox if it's installed.
        if isGmailAppInstalled() {
            if let gmailAppInboxURL = URL(string: "googlegmail://") {
                print("[GmailDeepLink] 🔗 Gmail app is installed. Opening to inbox.")
                UIApplication.shared.open(gmailAppInboxURL)
            }
        } else {
            // If the Gmail app is not installed, fall back to opening the email in the web browser.
            print("[GmailDeepLink] 📱 Gmail app not installed, opening in web.")
            openEmailInWebGmail(email)
        }
    }
    
    /// Create Gmail app deep-link URL
    private func createGmailAppURL(for email: Email) -> URL? {
        let messageId = email.id.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[GmailDeepLink] Attempting to create URL for message ID: \(messageId)")

        guard isValidGmailID(messageId) else {
            print("[GmailDeepLink] ❌ Invalid Gmail message ID format: '\(messageId)'")
            return nil
        }

        // Primary URL format for opening a specific email
        var urlString = "googlegmail://email/\(messageId)"
        if let url = URL(string: urlString) {
            print("[GmailDeepKey] ✅ Generated primary URL: \(url.absoluteString)")
            return url
        }

        // Fallback to conversation view using threadId if available
        if let threadId = email.threadId?.trimmingCharacters(in: .whitespacesAndNewlines), isValidGmailID(threadId) {
            print("[GmailDeepLink] ⚠️ Primary URL failed, trying fallback with thread ID: \(threadId)")
            urlString = "googlegmail://co?op=cv&th=\(threadId)"
            if let url = URL(string: urlString) {
                print("[GmailDeepLink] ✅ Generated fallback URL: \(url.absoluteString)")
                return url
            }
        }

        print("[GmailDeepLink] ❌ Failed to create any valid URL.")
        return nil
    }
    
    /// Open email in web Gmail
    private func openEmailInWebGmail(_ email: Email) {
        // Use thread ID if available to open the conversation view
        let id = email.threadId ?? email.id
        
        // Validate email ID format before creating URL
        guard isValidGmailID(id) else {
            print("❌ Invalid Gmail ID format for web URL: \(id)")
            return
        }
        
        let webURLString = "https://mail.google.com/mail/u/0/#inbox/\(id)"
        
        guard let webURL = URL(string: webURLString) else {
            print("❌ Failed to create Gmail web URL for ID: \(id)")
            return
        }
        
        print("🌐 Opening email in web Gmail: \(webURLString)")
        UIApplication.shared.open(webURL)
    }
    
    /// Check if Gmail app is installed
    func isGmailAppInstalled() -> Bool {
        guard let gmailURL = URL(string: "googlegmail://") else { return false }
        return UIApplication.shared.canOpenURL(gmailURL)
    }
    
    /// Get the appropriate open method description
    func getOpenMethodDescription() -> String {
        return isGmailAppInstalled() ? "Gmail App" : "Gmail Web"
    }
    
    /// Validate Gmail ID format (should be alphanumeric string)
    private func isValidGmailID(_ gmailId: String) -> Bool {
        // Gmail IDs should be non-empty, alphanumeric strings without spaces
        guard !gmailId.isEmpty,
              gmailId.count > 5,  // Reasonable minimum length
              !gmailId.contains(" "),
              !gmailId.contains("\n") else {
            return false
        }
        
        // Check for basic alphanumeric characters (Gmail IDs can contain letters, numbers, and some symbols)
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return gmailId.unicodeScalars.allSatisfy { allowedCharacterSet.contains($0) }
    }
    
    /// Test Gmail deep-linking with debug info
    func testGmailDeepLink(emailId: String, threadId: String?) {
        print("🧪 Testing Gmail deep-link:")
        print("   Email ID: \(emailId)")
        print("   Thread ID: \(threadId ?? "nil")")
        
        let testEmail = Email(
            id: emailId,
            threadId: threadId,
            subject: "Test Email",
            sender: EmailContact(name: "Test", email: "test@test.com"),
            recipients: [],
            body: "Test body",
            date: Date(),
            isRead: true,
            isImportant: false,
            labels: []
        )
        
        if let gmailURL = createGmailAppURL(for: testEmail) {
            print("   Generated URL: \(gmailURL.absoluteString)")
            print("   Can open: \(UIApplication.shared.canOpenURL(gmailURL))")
        }
    }
    
}