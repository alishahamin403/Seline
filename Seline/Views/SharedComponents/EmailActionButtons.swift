//
//  EmailActionButtons.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI
import UIKit

struct EmailActionButtons {
    
    // MARK: - Reply Actions
    
    static func replyToEmail(_ email: Email) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let subject = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
        let body = "\n\nOn \(EmailFormatters.formatFullDate(email.date)), \(email.sender.name ?? email.sender.email) wrote:\n\(email.body)"
        
        openGmailCompose(to: email.sender.email, subject: subject, body: body)
    }
    
    static func forwardEmail(_ email: Email) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let subject = email.subject.hasPrefix("Fwd:") ? email.subject : "Fwd: \(email.subject)"
        let body = "\n\n---------- Forwarded message ----------\nFrom: \(email.sender.name ?? email.sender.email)\nDate: \(EmailFormatters.formatFullDate(email.date))\nSubject: \(email.subject)\n\n\(email.body)"
        
        openGmailCompose(to: "", subject: subject, body: body)
    }
    
    // MARK: - Email Management Actions
    
    static func archiveEmail(_ email: Email, viewModel: ContentViewModel) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        Task {
            do {
                try await GmailService.shared.archiveEmail(emailId: email.id)
                await MainActor.run {
                    viewModel.archiveEmail(email.id)
                }
            } catch {
                ProductionLogger.logEmailError(error, operation: "archive_email")
            }
        }
    }
    
    static func deleteEmail(_ email: Email, viewModel: ContentViewModel) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Delete Email",
            message: "Are you sure you want to delete this email?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            Task {
                do {
                    try await GmailService.shared.deleteEmail(emailId: email.id)
                    await MainActor.run {
                        viewModel.deleteEmail(email.id)
                    }
                } catch {
                    ProductionLogger.logEmailError(error, operation: "delete_email")
                }
            }
        })
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private static func openGmailCompose(to recipient: String, subject: String, body: String) {
        let encodedRecipient = recipient.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let gmailComposeURL = URL(string: "googlegmail:///co?to=\(encodedRecipient)&subject=\(encodedSubject)&body=\(encodedBody)")!
        
        if UIApplication.shared.canOpenURL(gmailComposeURL) {
            UIApplication.shared.open(gmailComposeURL)
        } else {
            // Fallback to web Gmail
            let webGmailURL = URL(string: "https://mail.google.com/mail/?view=cm&to=\(encodedRecipient)&su=\(encodedSubject)&body=\(encodedBody)")!
            UIApplication.shared.open(webGmailURL)
        }
    }
}