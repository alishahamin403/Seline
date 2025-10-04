import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailService = EmailService.shared
    @StateObject private var openAIService = OpenAIService.shared
    @State private var isOriginalEmailExpanded: Bool = false

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Main content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Email Header
                            headerSection
                                .padding(.horizontal, 20)

                            // Sender/Recipient Information
                            CompactSenderView(email: email)
                                .padding(.horizontal, 20)

                            // AI Summary Section - always show
                            AISummaryCard(
                                email: email,
                                onGenerateSummary: { email in
                                    await generateAISummary(for: email)
                                }
                            )
                            .padding(.horizontal, 20)

                            // Original Email Content Section (Full Width)
                            originalEmailSection

                            // Attachments Section
                            if !email.attachments.isEmpty {
                                attachmentsSection
                                    .padding(.horizontal, 20)
                            }

                            // Bottom spacing to account for fixed buttons
                            Spacer()
                                .frame(height: 40)
                        }
                        .padding(.top, 24)
                    }

                    // Fixed action buttons at bottom
                    VStack(spacing: 0) {
                        EmailActionButtons(
                            email: email,
                            onReply: {
                                emailService.replyToEmail(email)
                            },
                            onForward: {
                                emailService.forwardEmail(email)
                            },
                            onDelete: {
                                Task {
                                    do {
                                        try await emailService.deleteEmail(email)
                                        dismiss()
                                    } catch {
                                        print("Failed to delete email: \(error.localizedDescription)")
                                        // You could show an alert here if needed
                                    }
                                }
                            },
                            onMarkAsUnread: {
                                emailService.markAsUnread(email)
                                dismiss()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .padding(.top, 4)
                        .background(
                            colorScheme == .dark ?
                                Color.gmailDarkBackground :
                                Color.white
                        )
                    }
                }
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground :
                        Color.white
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            // Mark email as read when view appears
            if !email.isRead {
                emailService.markAsRead(email)
            }
        }
    }


    // MARK: - AI Summary Generation

    private func generateAISummary(for email: Email) async -> Result<String, Error> {
        // Check if email already has a summary
        if let existingSummary = email.aiSummary {
            return .success(existingSummary)
        }

        do {
            // Generate summary using OpenAI
            let emailBody = email.body ?? email.snippet
            let summary = try await openAIService.summarizeEmail(
                subject: email.subject,
                body: emailBody
            )

            // Cache the summary in the email service
            await emailService.updateEmailWithAISummary(email, summary: summary)

            return .success(summary)
        } catch {
            print("Failed to generate AI summary: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject
            Text(email.subject)
                .font(FontManager.geist(size: .title1, weight: .bold))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }



    // MARK: - Original Email Section
    private var originalEmailSection: some View {
        VStack(spacing: 0) {
            // Expandable header button (with padding)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOriginalEmailExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Original Email")
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Image(systemName: isOriginalEmailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.shadcnMuted(colorScheme))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    colorScheme == .dark ?
                        Color.black.opacity(0.3) :
                        Color.gray.opacity(0.1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content (full width, no padding)
            if isOriginalEmailExpanded {
                if let htmlBody = email.body, htmlBody.contains("<") {
                    // Display HTML content using WebView with zoom
                    ZoomableHTMLContentView(htmlContent: htmlBody)
                        .frame(height: 500)
                        .background(
                            colorScheme == .dark ?
                                Color.black :
                                Color.white
                        )
                } else {
                    // Display plain text
                    ScrollView {
                        Text(email.body ?? email.snippet)
                            .font(FontManager.geist(size: .body, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .frame(height: 300)
                    .background(
                        colorScheme == .dark ?
                            Color.black :
                            Color.white
                    )
                }
            }
        }
    }

    // MARK: - Attachments Section
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(FontManager.geist(size: .title3, weight: .semibold))
                .foregroundColor(Color.shadcnForeground(colorScheme))

            LazyVStack(spacing: 8) {
                ForEach(email.attachments) { attachment in
                    AttachmentRow(attachment: attachment)
                }
            }
        }
    }
}

#Preview {
    EmailDetailView(email: Email.sampleEmails[0])
}