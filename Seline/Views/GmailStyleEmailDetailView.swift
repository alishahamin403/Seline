//
//  GmailStyleEmailDetailView.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import SwiftUI
import UIKit

struct GmailStyleEmailDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let email: Email
    @ObservedObject var viewModel: ContentViewModel
    @State private var isMarkedAsRead = false
    @State private var isMarkedAsImportant = false
    @State private var aiSummary: String = ""
    @State private var isLoadingSummary = false
    @StateObject private var openAIService = OpenAIService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Gmail-style header
            gmailStyleHeader
            
            // Email content in a clean, Gmail-like layout
            ScrollView {
                VStack(spacing: 16) {
                    // AI Summary section (if available)
                    if isLoadingSummary {
                        aiSummaryLoadingView
                    } else if !aiSummary.isEmpty {
                        aiSummaryView
                    }
                    
                    // Email content card
                    gmailStyleEmailCard
                    
                    // Attachments (if any)
                    if !email.attachments.isEmpty {
                        gmailStyleAttachmentsSection
                    }
                    
                    // Reply actions
                    replyActionsSection
                    
                    // Bottom padding
                    Color.clear.frame(height: 50)
                }
                .padding(.horizontal, 16)
            }
            .refreshable {
                await generateAISummary()
            }
        }
        .linearBackground()
        .onAppear {
            markAsRead()
            Task {
                await generateAISummary()
            }
        }
    }
    
    // MARK: - Gmail-style Header
    
    private var gmailStyleHeader: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // Star button
                Button(action: toggleImportant) {
                    Image(systemName: isMarkedAsImportant ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundColor(isMarkedAsImportant ? .yellow : DesignSystem.Colors.textSecondary)
                }
                
                // Archive button
                Button(action: archiveEmail) {
                    Image(systemName: "archivebox")
                        .font(.title3)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Delete button
                Button(action: deleteEmail) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // More actions
                Menu {
                    Button(action: {}) {
                        Label("Mark as Unread", systemImage: "envelope.badge")
                    }
                    Button(action: {}) {
                        Label("Move to Folder", systemImage: "folder")
                    }
                    Button(action: {}) {
                        Label("Mark as Spam", systemImage: "exclamationmark.octagon")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.background)
    }
    
    // MARK: - AI Summary Views
    
    private var aiSummaryLoadingView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(DesignSystem.Colors.accent)
                    .font(.title3)
                
                Text("AI Summary")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DesignSystem.Colors.accent)
            }
            
            HStack {
                Text("Generating summary...")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var aiSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(DesignSystem.Colors.accent)
                    .font(.title3)
                
                Text("AI Summary")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Button(action: {
                    Task { await generateAISummary() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Text(aiSummary)
                .font(.system(size: 15))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Gmail-style Email Card
    
    private var gmailStyleEmailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sender info
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(avatarColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String((email.sender.name ?? "").prefix(1).uppercased()))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(email.sender.name ?? email.sender.email)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        if email.isImportant {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        Spacer()
                        
                        Text(formatDate(email.date))
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Text("to me")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            // Subject
            Text(email.subject)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
                .background(DesignSystem.Colors.border)
            
            // Email body (Gmail-style formatting)
            GmailStyleEmailBody(content: email.body)
                .textSelection(.enabled)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: DesignSystem.Colors.shadow, radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Gmail-style Attachments Section
    
    private var gmailStyleAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paperclip")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("\(email.attachments.count) attachment\(email.attachments.count == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(email.attachments, id: \.id) { attachment in
                    GmailAttachmentCard(attachment: attachment)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: DesignSystem.Colors.shadow, radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Reply Actions Section
    
    private var replyActionsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                replyToEmail()
            }) {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Reply")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            
            Divider()
                .padding(.horizontal, 20)
            
            Button(action: {
                replyAllToEmail()
            }) {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.2")
                        .font(.system(size: 16, weight: .medium))
                    Text("Reply all")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            
            Divider()
                .padding(.horizontal, 20)
            
            Button(action: {
                forwardEmail()
            }) {
                HStack {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 16, weight: .medium))
                    Text("Forward")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(color: DesignSystem.Colors.shadow, radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Computed Properties
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink, .indigo]
        let index = abs((email.sender.name ?? email.sender.email).hashValue) % colors.count
        return colors[index]
    }
    
    private var cleanEmailBody: String {
        // Remove URLs and clean up the email body
        var cleanBody = email.body
        
        // Remove URLs (basic regex pattern)
        let urlPattern = #"https?://[^\s<>"{}|\\^`\[\]]+"#
        cleanBody = cleanBody.replacingOccurrences(of: urlPattern, with: "[Link]", options: .regularExpression)
        
        // Remove email addresses that might be links
        let emailPattern = #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
        cleanBody = cleanBody.replacingOccurrences(of: emailPattern, with: "[Email]", options: .regularExpression)
        
        // Clean up extra whitespace
        cleanBody = cleanBody.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleanBody = cleanBody.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanBody
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        return EmailFormatters.formatDate(date)
    }
    
    private func generateAISummary() async {
        guard openAIService.isConfigured else { return }
        
        isLoadingSummary = true
        
        do {
            let summaryPrompt = """
            Please provide a concise 1-2 sentence summary of this email:
            
            Subject: \(email.subject)
            From: \(email.sender.displayName)
            Content: \(String(email.body.prefix(500)))
            """
            
            let summary = try await openAIService.performAISearch(summaryPrompt)
            await MainActor.run {
                self.aiSummary = summary
                self.isLoadingSummary = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingSummary = false
                // Silently fail - don't show summary if it fails
            }
        }
    }
    
    private func markAsRead() {
        if !email.isRead {
            // Mark as read logic
            isMarkedAsRead = true
        }
    }
    
    private func toggleImportant() {
        isMarkedAsImportant.toggle()
        // TODO: Update email importance in backend
    }
    
    private func archiveEmail() {
        Task {
            do {
                try await GmailService.shared.archiveEmail(emailId: email.id)
                await MainActor.run {
                    // Provide user feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    // Refresh the email list and dismiss
                    Task {
                        await viewModel.refresh()
                    }
                    dismiss()
                }
            } catch {
                print("❌ Failed to archive email: \(error)")
                // Could show an error alert here
            }
        }
    }
    
    private func deleteEmail() {
        Task {
            do {
                try await GmailService.shared.deleteEmail(emailId: email.id)
                await MainActor.run {
                    // Provide user feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                    
                    // Refresh the email list and dismiss
                    Task {
                        await viewModel.refresh()
                    }
                    dismiss()
                }
            } catch GmailError.insufficientPermissions {
                await MainActor.run {
                    let alert = UIAlertController(
                        title: "Permission Required",
                        message: "To delete emails, Seline needs Gmail modify permission. Please sign out and sign in again when prompted to grant the new permission.",
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first,
                       let root = window.rootViewController {
                        root.present(alert, animated: true)
                    }
                }
            } catch {
                print("❌ Failed to delete email: \(error)")
            }
        }
    }
    
    private func replyToEmail() {
        EmailActionButtons.replyToEmail(email)
    }
    
    private func replyAllToEmail() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Create Gmail reply-all URL (similar to reply but would include all recipients)
        let subject = "Re: \(email.subject)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedTo = email.sender.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Note: Gmail URL scheme doesn't support CC/BCC, so this is same as regular reply
        let gmailComposeURL = URL(string: "googlegmail://co?to=\(encodedTo)&subject=\(encodedSubject)")!
        
        if UIApplication.shared.canOpenURL(gmailComposeURL) {
            UIApplication.shared.open(gmailComposeURL)
        } else {
            let webGmailURL = URL(string: "https://mail.google.com/mail/?view=cm&fs=1&to=\(encodedTo)&su=\(encodedSubject)")!
            UIApplication.shared.open(webGmailURL)
        }
    }
    
    private func forwardEmail() {
        EmailActionButtons.forwardEmail(email)
    }
}

// MARK: - Gmail Style Email Body Component

struct GmailStyleEmailBody: View {
    let content: String
    @State private var attributedContent: AttributedString = AttributedString("")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(attributedContent)
                .font(.system(size: 16, design: .default))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            processEmailContent()
        }
    }
    
    private func processEmailContent() {
        var processed = content
        
        // Remove common email headers/signatures that appear in the body
        processed = removeEmailHeaders(processed)
        
        // Convert HTML to plain text but preserve formatting
        processed = convertHTMLToPlainText(processed)
        
        // Clean up whitespace while preserving intentional line breaks
        processed = cleanupWhitespace(processed)
        
        // Create attributed string with proper formatting
        attributedContent = createFormattedText(processed)
    }
    
    private func removeEmailHeaders(_ text: String) -> String {
        var cleaned = text
        
        // Remove common email patterns
        let patterns = [
            // Remove "From:", "To:", "Sent:", "Subject:" lines
            #"^(From|To|Sent|Subject|Date|Cc|Bcc):[^\n]*\n?"#,
            // Remove email signatures (lines starting with --)
            #"^--[^\n]*\n?.*$"#,
            // Remove "On ... wrote:" patterns
            #"On .* wrote:\s*\n?"#,
            // Remove quoted text indicators
            #"^>.*$"#
        ]
        
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        return cleaned
    }
    
    private func convertHTMLToPlainText(_ html: String) -> String {
        var text = html
        
        // Replace HTML line breaks with actual line breaks
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        
        // Replace paragraph tags with double line breaks
        text = text.replacingOccurrences(of: "<p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "", options: .caseInsensitive)
        
        // Replace div tags with line breaks
        text = text.replacingOccurrences(of: "<div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "", options: .caseInsensitive)
        
        // Remove all other HTML tags
        text = text.replacingOccurrences(
            of: #"<[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        
        return text
    }
    
    private func cleanupWhitespace(_ text: String) -> String {
        var cleaned = text
        
        // Replace multiple consecutive spaces with single space, but preserve intentional formatting
        cleaned = cleaned.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
        
        // Replace more than 2 consecutive newlines with just 2
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        
        // Trim leading and trailing whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func createFormattedText(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Set base font
        attributedString.font = .system(size: 16, design: .default)
        attributedString.foregroundColor = DesignSystem.Colors.textPrimary
        
        // Find and style URLs
        if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"{}|\\^`\[\]]+"#) {
            let nsString = text as NSString
            let matches = urlRegex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let urlText = String(text[range])
                    if let startIndex = attributedString.range(of: urlText)?.lowerBound {
                        let endIndex = attributedString.index(startIndex, offsetByCharacters: urlText.count)
                        let urlRange = startIndex..<endIndex
                        
                        // Style the URL
                        attributedString[urlRange].foregroundColor = .blue
                        attributedString[urlRange].underlineStyle = .single
                    }
                }
            }
        }
        
        // Find and style email addresses
        if let emailRegex = try? NSRegularExpression(pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#) {
            let nsString = text as NSString
            let matches = emailRegex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let emailText = String(text[range])
                    if let startIndex = attributedString.range(of: emailText)?.lowerBound {
                        let endIndex = attributedString.index(startIndex, offsetByCharacters: emailText.count)
                        let emailRange = startIndex..<endIndex
                        
                        // Style the email
                        attributedString[emailRange].foregroundColor = .blue
                    }
                }
            }
        }
        
        return attributedString
    }
}

// MARK: - Gmail Style Attachment Card Component

struct GmailAttachmentCard: View {
    let attachment: EmailAttachment
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconForAttachment)
                .font(.system(size: 24))
                .foregroundColor(colorForAttachment)
            
            Text(attachment.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text(formatFileSize(attachment.size))
                .font(.system(size: 10))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.surfaceSecondary)
        )
    }
    
    private var iconForAttachment: String {
        let filename = attachment.filename.lowercased()
        if filename.hasSuffix(".pdf") { return "doc.text" }
        if filename.hasSuffix(".jpg") || filename.hasSuffix(".png") || filename.hasSuffix(".jpeg") { return "photo" }
        if filename.hasSuffix(".doc") || filename.hasSuffix(".docx") { return "doc.text" }
        if filename.hasSuffix(".xls") || filename.hasSuffix(".xlsx") { return "tablecells" }
        return "doc"
    }
    
    private var colorForAttachment: Color {
        let filename = attachment.filename.lowercased()
        if filename.hasSuffix(".pdf") { return .red }
        if filename.hasSuffix(".jpg") || filename.hasSuffix(".png") || filename.hasSuffix(".jpeg") { return .green }
        if filename.hasSuffix(".doc") || filename.hasSuffix(".docx") { return .blue }
        if filename.hasSuffix(".xls") || filename.hasSuffix(".xlsx") { return .green }
        return DesignSystem.Colors.textSecondary
    }
    
    private func formatFileSize(_ size: Int) -> String {
        return EmailFormatters.formatFileSize(size)
    }
}

// MARK: - Preview

struct GmailStyleEmailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let mockEmail = Email(
            id: "1",
            subject: "Important Update",
            sender: EmailContact(name: "John Doe", email: "john@example.com"),
            recipients: [],
            body: "This is a sample email body with some content to show how the Gmail-style interface looks.",
            date: Date(),
            isRead: false,
            isImportant: true,
            labels: [],
            attachments: []
        )
        
        GmailStyleEmailDetailView(email: mockEmail, viewModel: ContentViewModel())
    }
}